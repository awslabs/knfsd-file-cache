# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

"""MkDocs build hook: substitute the current year into the copyright notice.

The ``copyright`` string in mkdocs.yml uses a ``{year}`` placeholder; this hook
replaces it with the build year at build time so the footer never needs a manual
year bump. If no placeholder is present the copyright is left untouched.
"""

from __future__ import annotations

from datetime import datetime, timezone


def on_config(config, **kwargs):  # pylint: disable=unused-argument
    """Substitute the build year into the copyright notice (MkDocs event)."""
    copyright_text = config.get("copyright")
    if copyright_text and "{year}" in copyright_text:
        year = datetime.now(timezone.utc).year
        config["copyright"] = copyright_text.replace("{year}", str(year))
    return config
