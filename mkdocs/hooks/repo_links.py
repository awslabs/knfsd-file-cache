# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

"""MkDocs build hook: rewrite links to unhostable repo targets into repo URLs.

Because ``docs_dir`` is the repository root (so scattered ``*.md`` files keep
their relative links), Markdown pages legitimately link to targets the hosted
site cannot serve usefully. There are three such cases.

Files MkDocs never publishes: extensionless files such as ``../Makefile``,
dotfiles such as ``../.tflint.hcl``, and anything inside a dot-prefixed
directory such as ``.devcontainer/``. These 404 on the hosted page.

Files MkDocs copies verbatim but a browser only downloads, such as ``*.sh``,
``*.tf``, ``*.json``, and ``*.yaml``. Clicking one saves a file instead of
navigating, whereas the repo browser renders it with syntax highlighting.

Directories such as ``../image/`` or ``resources/scripts``, which MkDocs does
not resolve the way the GitLab/GitHub repo browser does.

All of these work fine when browsing the repo. This hook acts like a ``${root}``
substitution: at build time it resolves each such link against the page's source
directory and rewrites it so the hosted page behaves sensibly. A directory that
contains a published ``README.md``/``index.md`` is repointed at that page
(staying inside the docs site); otherwise the target is rewritten to a canonical
repository URL (``/blob/`` for files, ``/tree/`` for directories) derived from
``repo_url``, injected per-platform via ``!ENV`` so nothing is hard-coded.

Markdown pages and genuine browser-renderable assets (images, media, CSS, JS,
fonts, PDFs) are deliberately left alone so they keep being served locally.

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

# Extensions MkDocs turns into real HTML pages.
_PAGE_EXTS = frozenset({".md", ".markdown", ".mdown", ".mkdn", ".mkd"})

# Extensions a browser renders in place, so the site's own copy is genuinely
# useful and the link should stay local. Anything absent from this set is a
# source or config file that reads better in the repo browser than as a
# download, so it gets rewritten to a repository URL.
_ASSET_EXTS = frozenset(
    {
        # Images
        ".apng",
        ".avif",
        ".bmp",
        ".gif",
        ".ico",
        ".jpeg",
        ".jpg",
        ".png",
        ".svg",
        ".webp",
        # Audio and video
        ".m4a",
        ".mp3",
        ".mp4",
        ".ogg",
        ".wav",
        ".webm",
        # Documents and web assets the browser displays
        ".css",
        ".htm",
        ".html",
        ".js",
        ".mjs",
        ".pdf",
        # Fonts
        ".eot",
        ".otf",
        ".ttf",
        ".woff",
        ".woff2",
    }
)

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


def _served_usefully(rel_path: str) -> bool:
    """True if the site's own copy of this file is worth linking to.

    False means the link should point at the repo browser instead, either
    because MkDocs will not publish the file at all (extensionless, dotfile, or
    inside a dot-prefixed directory, per its built-in ``.*`` exclusion), or
    because it publishes the file verbatim and a browser would merely download
    it rather than display it.
    """
    parts = rel_path.split("/")
    if any(part.startswith(".") for part in parts):
        return False
    ext = posixpath.splitext(parts[-1])[1].lower()
    if not ext:
        return False
    return ext in _PAGE_EXTS or ext in _ASSET_EXTS


def _is_image(markdown: str, bracket_pos: int) -> bool:
    """True if the link closing at ``bracket_pos`` is an ``![alt](...)`` image.

    Scans back for the ``[`` matching this ``]`` and checks for a leading ``!``.
    An image must keep pointing at a file the browser can load inline, so it is
    never rewritten to a repository URL.
    """
    depth = 0
    for i in range(bracket_pos - 1, -1, -1):
        char = markdown[i]
        if char == "]":
            depth += 1
        elif char == "[":
            if depth == 0:
                return i > 0 and markdown[i - 1] == "!"
            depth -= 1
    return False


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
        if _is_external(target) or _is_image(markdown, match.start()):
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
        elif abs_target.is_file() and not _served_usefully(resolved):
            # Unpublished file, or one the browser would download rather than
            # display; the repo browser renders it instead.
            new_target = f"{blob_base}/{resolved}{sep}{suffix}"

        if new_target is None:
            return match.group(0)
        return f"{open_paren}{lt}{new_target}{gt}{title or ''}{close_paren}"

    return _LINK_RE.sub(replace, markdown)
