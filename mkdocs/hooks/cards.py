# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

"""MkDocs build hook: render marked blocks as card grids.

Two kinds of card are produced: Material grid cards linking to pages, built from
a bullet list, and click-to-play video cards, built from a table of posters. Both
live here because both need the identical trick, and splitting them across
modules would mean either duplicating the block parsing or importing between hook
files (which pylint cannot resolve, since MkDocs loads hooks by path rather than
as a package).

The trick is that the richer HTML each needs cannot be authored directly. GitHub
and GitLab ignore the ``markdown`` attribute, so Markdown inside a hand-written
``<div>`` renders as literal broken text; both strip ``<iframe>`` entirely, GitHub
against a fixed allowlist and GitLab unless an instance administrator has enabled
"Embedded content"; and neither allows any CSS, GitHub dropping ``style`` and
``class`` outright while GitLab permits ``style`` only on table cells and only for
``text-align``. This matters here because every page is also a repo file. So the
source stays markup those browsers render natively, and this hook expands it at
build time. Icons and video ids travel in HTML comments, invisible in the repo
browser, keeping Material's ``:material-...:`` shortcodes and other build-only
details out of that view.

Registered after ``repo_links.py`` so link rewriting happens while the content is
still plain Markdown.

Grid cards
----------

Each bullet's first line carries a linked title and an ``<!-- icon: ... -->``
comment, with the description on the following indented line, between
``grid-cards:start`` and ``grid-cards:end`` markers. At build time the icon is
expanded to a shortcode with Material's sizing attributes, the title stays on the
first line, and the remaining text becomes the card body below a divider.
Indented sub-bullets become a flush-left stack of links at the foot of the card,
so one card can point at several related pages. Titles are emboldened
automatically; the links keep the normal body weight.

Video cards
-----------

Videos are authored as a two-column HTML table, one poster per cell, linked to
the video, between ``video-cards:start`` and ``video-cards:end`` markers. See
``docs/resources.md`` for a worked example.

A table rather than a bullet list because the repo browsers allow no CSS at all:
GitHub strips ``style`` and ``class`` outright, and GitLab permits ``style`` only
on ``td``/``th`` and only for ``text-align``. Cell widths are therefore the one
mechanism that puts the posters side by side at matching sizes there, instead of
stacking them at whatever intrinsic size each image happens to have. MkDocs does
not use the table: this hook reads the cells and re-emits each poster as
Markdown, so the grid is rebuilt from the stylesheet.

The build wraps each in a facade rather than embedding a player. An iframe has no
``poster`` attribute, so an eagerly embedded YouTube player always shows whichever
thumbnail the uploader chose; keeping the authored image and swapping the player
in on click is the only way to control the holding frame, which is what lets a
page use ``.../frame0.jpg`` (YouTube's undocumented first-frame thumbnail) or a
frame extracted from a self-hosted file. It also avoids contacting YouTube until
the reader asks for playback, and it degrades cleanly without JavaScript because
the poster stays wrapped in its original link.

Note that ``frame0.jpg`` is only served at 480x268, unlike the 1280x720
``maxresdefault.jpg``, so it upscales slightly on a hi-DPI display. That is the
price of showing the true opening frame instead of the uploader's cover art.

``<!-- youtube: <id> -->`` marks a cell as playable in place: the id is handed
to the browser as ``data-youtube`` and ``videos.js`` swaps in a
``youtube-nocookie.com`` iframe on click. Cells without it stay plain links,
which is what a video hosted somewhere unembeddable needs -- notably a GitHub
``user-attachments`` asset, whose URL is a five-minute signed redirect that only
GitHub's own Markdown renderer can mint.

Both wrappers carry ``markdown`` so python-markdown parses the body. For video
cards that is also why each poster is re-emitted as Markdown rather than having
its ``<img>`` copied across: MkDocs only rewrites relative paths it parses, so a
copied tag would leave the path one directory level short.
"""

from __future__ import annotations

import logging
import re

# Named under "mkdocs." so records flow through MkDocs' own logging setup, which
# means --strict promotes these warnings to build failures.
_log = logging.getLogger("mkdocs.hooks.cards")

# Start of a top-level list item: "- " or "* ". Anchored with no leading
# whitespace so indented continuation lines are not mistaken for new cards.
_ITEM_RE = re.compile(r"^[-*][ \t]+", re.MULTILINE)

# An indented sub-bullet, which becomes a link in a grid card's list. Matched
# after the enclosing item has been dedented, hence the optional whitespace.
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

# Video id supplied as an HTML comment, for the same reason as the icon. YouTube
# ids are 11 characters of the URL-safe base64 alphabet; matched strictly so a
# pasted full URL is rejected rather than handed to the player.
_YOUTUBE_RE = re.compile(
    r"[ \t]*<!--[ \t]*youtube:[ \t]*(?P<id>[A-Za-z0-9_-]{11})[ \t]*-->"
)

# One cell of the video table, which holds a single poster.
_CELL_RE = re.compile(r"<td\b[^>]*>(?P<cell>.*?)</td>", re.DOTALL | re.IGNORECASE)

# The poster inside a cell: an <img> wrapped in a link to the video. Only the
# href, src and alt are carried over; the width attribute that sizes the poster
# in the repo browser is deliberately dropped, since the stylesheet sizes it here.
_POSTER_RE = re.compile(
    r"<a\b[^>]*\bhref=\"(?P<href>[^\"]*)\"[^>]*>\s*"
    r"<img\b(?P<img>[^>]*)>\s*"
    r"</a>",
    re.DOTALL | re.IGNORECASE,
)

_ATTR_RE = re.compile(r"\b(?P<key>[a-z-]+)=\"(?P<value>[^\"]*)\"", re.IGNORECASE)


def _block_pattern(name: str) -> re.Pattern[str]:
    """Return the pattern matching one ``<!-- name:start -->`` region."""
    marker = re.escape(name)
    return re.compile(
        rf"^[ \t]*<!--[ \t]*{marker}:start[ \t]*-->[ \t]*\n"
        r"(?P<body>.*?)"
        rf"^[ \t]*<!--[ \t]*{marker}:end[ \t]*-->[ \t]*$",
        re.DOTALL | re.MULTILINE,
    )


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


def _item_lines(item: str) -> list[str]:
    """Return one item's non-empty lines, stripped of indentation."""
    lines = [line.strip() for line in item.strip().splitlines()]
    return [line for line in lines if line]


def _format_grid_card(item: str) -> str | None:
    """Render one list item as a Material grid card, or None if it is empty."""
    lines = _item_lines(item)
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


def _format_video_card(cell: str) -> str | None:
    """Wrap one table cell's poster as a click-to-play card."""
    # Take the id before anything else, so the comment never reaches the page.
    video_id = None
    match = _YOUTUBE_RE.search(cell)
    if match:
        video_id = match.group("id")

    poster = _POSTER_RE.search(cell)
    if not poster:
        return None

    img = dict(_ATTR_RE.findall(poster.group("img")))
    src = img.get("src", "").strip()
    if not src:
        return None

    # Re-emitted as a Markdown image link rather than copying the authored
    # <img>: MkDocs only rewrites relative paths in Markdown it parses, so a
    # copied tag would leave a page-relative poster one directory level short.
    alt = img.get("alt", "").replace("[", r"\[").replace("]", r"\]")
    markdown_poster = f'[![{alt}]({src})]({poster.group("href").strip()})'

    attrs = f' data-youtube="{video_id}"' if video_id else ""
    return "\n".join(
        [f'<div class="video-card"{attrs} markdown>', "", markdown_poster, "", "</div>"]
    )


def _split_cells(body: str) -> list[str]:
    """Split the video table into its cell contents."""
    return [match.group("cell") for match in _CELL_RE.finditer(body)]


# Each block type: the wrapper class, how the block body is split, and how one
# piece becomes a card. A malformed or empty block is left exactly as authored,
# so it degrades to what the repo browser already shows rather than breaking the
# page.
_BLOCKS = (
    ("grid-cards", "grid cards", _split_items, _format_grid_card),
    ("video-cards", "grid video-cards", _split_cells, _format_video_card),
)


# `page` and `files` are part of the MkDocs on_page_markdown signature but are
# not needed here.
# pylint: disable-next=unused-argument
def on_page_markdown(markdown: str, *, page, config, files) -> str:
    """Convert marked blocks on this page into card grids (MkDocs event)."""
    for name, wrapper, splitter, formatter in _BLOCKS:
        if f"{name}:start" not in markdown:
            continue

        def substitute(
            match: re.Match[str],
            name=name,
            wrapper=wrapper,
            splitter=splitter,
            formatter=formatter,
        ):
            cards = [
                card
                for card in (
                    formatter(piece) for piece in splitter(match.group("body"))
                )
                if card
            ]
            if not cards:
                # Warn rather than fail: the authored source still renders, so a
                # page is never broken by a malformed block. Silence would be
                # worse than noise here, because the fallback for a video block
                # is the raw table, whose repo-relative image paths 404 on the
                # site -- a symptom whose cause is not otherwise obvious.
                _log.warning(
                    "%s: could not parse a '%s' block; left as authored",
                    page.file.src_path,
                    name,
                )
                return match.group(0)
            joined = "\n\n".join(cards)
            return f'<div class="{wrapper}" markdown>\n\n{joined}\n\n</div>'

        markdown = _block_pattern(name).sub(substitute, markdown)
    return markdown
