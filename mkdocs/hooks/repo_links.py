# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

"""MkDocs build hook: rewrite links to unhostable repo targets into repo URLs.

Because ``docs_dir`` is the repository root (so scattered ``*.md`` files keep
their relative links), Markdown pages legitimately link to targets that a
static site cannot host: repo-root files such as ``../Makefile`` or
``../.tflint.hcl`` (MkDocs never publishes extensionless files or dotfiles),
and directories such as ``../image/`` or ``resources/scripts`` (MkDocs does not
resolve arbitrary folder links the way the GitLab/GitHub repo browser does).

Both work fine when browsing the repo but would 404 on the hosted page. This
hook acts like a ``${root}`` substitution: at build time it resolves each such
link against the page's source directory and rewrites it so the hosted page
keeps working. A directory that contains a hostable ``README.md``/``index.md``
is repointed at that page (staying inside the docs site); otherwise the target
is rewritten to a canonical repository URL (``/blob/`` for files, ``/tree/``
for directories) derived from ``repo_url`` — injected per-platform via
``!ENV``, so nothing is hard-coded.

When ``repo_url`` is unset (e.g. local ``mkdocs serve``) links are left
untouched, which is harmless locally.
"""

from __future__ import annotations

import os
import posixpath
import re
from pathlib import Path
from urllib.parse import urlsplit

# Markdown inline links: [text](target) and [text](target "title").
_LINK_RE = re.compile(r"(\]\()\s*(<?)([^)\s]+?)(>?)(\s+\"[^\"]*\")?(\))")

# Directory index files MkDocs publishes as the folder's page.
_INDEX_FILES = ("README.md", "index.md")

# Repo root == docs_dir == the directory containing mkdocs.yml.
_REPO_ROOT = Path(__file__).resolve().parent.parent.parent


def _repo_refs(repo_url: str) -> tuple[str, str] | None:
    """Return ``({repo}/<blob>/<branch>, {repo}/<tree>/<branch>)`` or None."""
    if not repo_url:
        return None
    branch = os.environ.get("MKDOCS_REPO_BRANCH", "main")
    host = urlsplit(repo_url).netloc.lower()
    # GitLab uses the /-/ infix; GitHub (and most others) do not.
    prefix = "-/" if "gitlab" in host else ""
    base = repo_url.rstrip("/")
    return f"{base}/{prefix}blob/{branch}", f"{base}/{prefix}tree/{branch}"


def _is_external(target: str) -> bool:
    return bool(urlsplit(target).scheme) or target.startswith(("//", "#", "mailto:"))


def _hostable(rel_path: str) -> bool:
    """True if MkDocs would publish this file (has an extension, not a dotfile)."""
    name = posixpath.basename(rel_path)
    return bool(posixpath.splitext(name)[1]) and not name.startswith(".")


# `files` is part of the MkDocs on_page_markdown signature but unused here.
# pylint: disable-next=unused-argument
def on_page_markdown(markdown: str, *, page, config, files) -> str:
    """Rewrite unhostable file/directory links on this page (MkDocs event)."""
    refs = _repo_refs(config.get("repo_url") or "")
    if not refs:
        return markdown
    blob_base, tree_base = refs

    src_dir = Path(page.file.src_path).parent

    def replace(match: re.Match[str]) -> str:
        open_paren, lt, target, gt, title, close_paren = match.groups()
        if _is_external(target):
            return match.group(0)

        # Split off any anchor/query so it survives the rewrite.
        path_part, sep, suffix = target.partition("#")
        if not path_part:
            return match.group(0)

        # Resolve the link relative to the page, normalised to a repo-root path.
        resolved = posixpath.normpath(posixpath.join(str(src_dir), path_part))
        if resolved.startswith(".."):
            return match.group(0)

        abs_target = (_REPO_ROOT / resolved).resolve()
        new_target: str | None = None

        if abs_target.is_dir():
            # Prefer the folder's own hosted page; keeps the link inside the site.
            index = next(
                (name for name in _INDEX_FILES if (abs_target / name).is_file()),
                None,
            )
            if index:
                rel = posixpath.relpath(posixpath.join(resolved, index), str(src_dir))
                new_target = f"{rel}{sep}{suffix}"
            else:
                new_target = f"{tree_base}/{resolved}{sep}{suffix}"
        elif abs_target.is_file() and not _hostable(resolved):
            # Real repo file MkDocs will not publish (extensionless/dotfile).
            new_target = f"{blob_base}/{resolved}{sep}{suffix}"

        if new_target is None:
            return match.group(0)
        return f"{open_paren}{lt}{new_target}{gt}{title or ''}{close_paren}"

    return _LINK_RE.sub(replace, markdown)
