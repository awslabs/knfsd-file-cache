# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

"""MkDocs build hook: render marked bullet lists as Material grid cards.

Material's card grid needs a ``<div class="grid cards" markdown>`` wrapper plus
a specific per-item shape. GitHub and GitLab ignore the ``markdown`` attribute,
so authoring that HTML directly would make the Markdown inside it (links, bold
text, lists) render as literal broken text when the same file is browsed in the
repository -- which matters here because every page is also a repo file.

This hook keeps the source as an ordinary bullet list wrapped in a pair of HTML
comments, which are invisible in the repo browser. Each item is a bullet whose
first line carries a linked title and an ``<!-- icon: ... -->`` comment, with the
description on the following (indented) line, between ``grid-cards:start`` and
``grid-cards:end`` comment markers. Naming the icon inside a comment keeps
Material's shortcode syntax out of the repo browser, which would otherwise show
it as literal ``:material-...:`` text.

At build time each item becomes a card: the icon is expanded to a shortcode with
Material's sizing attributes, the title stays on the first line, and the
remaining text becomes the card body below a divider.

Indented sub-bullets are rendered as a flush-left stack of links at the foot of
the card, so a card can point at several related pages. Any non-indented lines
after the title form the description; indented ones become the links. Titles are
emboldened automatically, and the links keep the normal body weight.

Registered after ``repo_links.py`` so link rewriting happens while the content
is still a plain list.
"""

from __future__ import annotations

import re

# The comment-delimited region holding the bullet list to convert.
_BLOCK_RE = re.compile(
    r"^[ \t]*<!--[ \t]*grid-cards:start[ \t]*-->[ \t]*\n"
    r"(?P<body>.*?)"
    r"^[ \t]*<!--[ \t]*grid-cards:end[ \t]*-->[ \t]*$",
    re.DOTALL | re.MULTILINE,
)

# Start of a top-level list item: "- " or "* ". Anchored with no leading
# whitespace so indented sub-bullets are not mistaken for new cards.
_ITEM_RE = re.compile(r"^[-*][ \t]+", re.MULTILINE)

# An indented sub-bullet, which becomes a link in the card's list. Matched after
# the enclosing item has been dedented, hence the optional leading whitespace.
_SUBITEM_RE = re.compile(r"^[ \t]*[-*][ \t]+")

# A leading icon/emoji shortcode, e.g. ":material-cog-outline:".
_ICON_RE = re.compile(r"^(?P<icon>:[a-z0-9_+-]+(?:-[a-z0-9_+-]+)*:)[ \t]*")

# Icon supplied as an HTML comment so the repo browser, which does not
# understand Material's shortcodes, shows nothing rather than literal text:
#   * **[Title](page.md)** <!-- icon: material-cog-outline -->
_ICON_COMMENT_RE = re.compile(
    r"[ \t]*<!--[ \t]*icon:[ \t]*(?P<icon>[a-z0-9/_+-]+)[ \t]*-->"
)

# Material's icon sizing/alignment attributes, applied via attr_list.
_ICON_ATTRS = "{ .lg .middle }"


def _split_items(body: str) -> list[str]:
    """Split a bullet list into raw item texts, preserving continuation lines."""
    matches = list(_ITEM_RE.finditer(body))
    if not matches:
        return []

    items = []
    for index, match in enumerate(matches):
        end = matches[index + 1].start() if index + 1 < len(matches) else len(body)
        items.append(body[match.end() : end])
    return items


def _format_card(item: str) -> str | None:
    """Render one list item as a Material grid card, or None if it is empty."""
    lines = [line.strip() for line in item.strip().splitlines()]
    lines = [line for line in lines if line]
    if not lines:
        return None

    title = lines[0]

    # Nested bullets become the card's link list; anything else is prose. The
    # nested list is safe inside a card because Material's border and padding
    # rules for cards use child combinators.
    description_parts: list[str] = []
    links: list[str] = []
    for line in lines[1:]:
        if _SUBITEM_RE.match(line):
            links.append(_SUBITEM_RE.sub("", line).strip())
        else:
            description_parts.append(line)
    description = " ".join(description_parts).strip()

    # Icon may come from an HTML comment (preferred, invisible in the repo
    # browser) or from a leading shortcode.
    icon = None
    comment_match = _ICON_COMMENT_RE.search(title)
    if comment_match:
        icon = f":{comment_match.group('icon')}:"
        title = _ICON_COMMENT_RE.sub("", title).strip()
    else:
        inline_match = _ICON_RE.match(title)
        if inline_match:
            icon = inline_match.group("icon")
            title = title[inline_match.end() :].strip()

    # Card titles are bold in Material's own card examples. Emphasise here so
    # the source Markdown stays free of formatting noise, unless the author
    # already styled the title themselves.
    if "**" not in title and "__" not in title:
        title = f"**{title}**"

    if icon:
        title = f"{icon}{_ICON_ATTRS} {title}"

    card = [f"-   {title}"]
    if description or links:
        card += ["", "    ---"]
    if description:
        card += ["", f"    {description}"]
    if links:
        card += [""]
        card += [f"    -   {link}" for link in links]
    return "\n".join(card)


def _render_block(match: re.Match[str]) -> str:
    """Replace one marked region with a Material card grid."""
    cards = [
        card
        for card in (_format_card(item) for item in _split_items(match.group("body")))
        if card
    ]
    if not cards:
        return match.group(0)

    joined = "\n\n".join(cards)
    return f'<div class="grid cards" markdown>\n\n{joined}\n\n</div>'


# `page` and `files` are part of the MkDocs on_page_markdown signature but are
# not needed here.
# pylint: disable-next=unused-argument
def on_page_markdown(markdown: str, *, page, config, files) -> str:
    """Convert marked bullet lists on this page into card grids (MkDocs event)."""
    if "grid-cards:start" not in markdown:
        return markdown
    return _BLOCK_RE.sub(_render_block, markdown)
