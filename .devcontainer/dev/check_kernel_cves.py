# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

"""Check the pinned KNFSD kernel version against the Linux kernel CNA CVE records.

The Linux kernel CNA publishes one CVE JSON 5 record per CVE in the
``vulns.git`` repository (``cve/published/<YEAR>/CVE-*.json``). This script:

1. reads the ``KERNEL="X.Y.Z"`` pin from ``image/resources/scripts/10-build.sh``
2. keeps only records whose ``programFiles`` fall under the NFS server, NFS
    client, SUNRPC, cachefiles and netfs source paths
3. evaluates the ``semver`` and ``original_commit_for_fix`` version ranges to
    decide whether the pinned version is affected
4. flags affected CVEs whose CNA CVSS base score is at or above
    ``--min-cvss`` (unscored CVEs are skipped and listed, unless the threshold
    is ``0.0``, in which case every affected CVE is flagged)

A record that matches the paths but cannot be evaluated (unknown
``versionType``, unparsable version, or no version data) is treated as
affected and marked "unverifiable", so it is never silently dropped.

Exit codes: 0 clean, 1 flagged CVEs found, 2 error (bad input, missing pin, or
a sanity floor was not met, which indicates an upstream layout change).

Usage:
    python3 .devcontainer/dev/check_kernel_cves.py --vulns-dir .vulns
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

DEFAULT_BUILD_SCRIPT = "image/resources/scripts/10-build.sh"
DEFAULT_VULNS_DIR = ".vulns"
DEFAULT_PATHS = (
    "fs/nfsd/",
    "fs/nfs/",
    "net/sunrpc/",
    "fs/cachefiles/",
    "fs/netfs/",
)
DEFAULT_MIN_CVSS = 9.0
MIN_CVSS_ENV = "KNFSD_KERNEL_CVE_MIN_CVSS"

# sanity floors: guard against an upstream layout or schema change silently
# producing a "clean" result
MIN_RECORDS = 10000
MIN_PATH_MATCHES = 100

EXIT_CLEAN = 0
EXIT_FLAGGED = 1
EXIT_ERROR = 2

PIN_RE = re.compile(r'^KERNEL="(\d+\.\d+(?:\.\d+)?)"\s*$', re.MULTILINE)
VERSION_RE = re.compile(r"^(\d+(?:\.\d+)*)(?:-rc(\d+))?$")
EVALUATED_TYPES = ("semver", "original_commit_for_fix")
VersionKey = tuple[tuple[int, ...], int, int]


class CheckError(Exception):
    """Raised for invalid input or unmet sanity floors (exit code 2)."""


class UnverifiableError(Exception):
    """Raised when a record's version data cannot be evaluated."""


def parse_version(text: str) -> VersionKey:
    """Return a sortable key for a kernel version such as ``7.3.6`` or ``7.4-rc1``.

    Trailing zero components are dropped so ``7.4`` equals ``7.4.0``. A release
    candidate sorts before the final release of the same version.
    """
    match = VERSION_RE.match(text.strip())
    if not match:
        raise UnverifiableError(f"unparsable version: {text!r}")
    nums = [int(part) for part in match.group(1).split(".")]
    while len(nums) > 1 and nums[-1] == 0:
        nums.pop()
    if match.group(2) is None:
        return (tuple(nums), 1, 0)
    return (tuple(nums), 0, int(match.group(2)))


def version_components(text: str) -> tuple[int, ...]:
    """Return the numeric components of a version, without normalization."""
    match = VERSION_RE.match(text.strip())
    if not match:
        raise UnverifiableError(f"unparsable version: {text!r}")
    return tuple(int(part) for part in match.group(1).split("."))


def in_branch(pinned: str, branch_pattern: str) -> bool:
    """Return True if ``pinned`` belongs to a branch pattern such as ``7.3.*``."""
    prefix = version_components(branch_pattern[:-2])
    components = version_components(pinned)
    if len(components) < len(prefix):
        components = components + (0,) * (len(prefix) - len(components))
    return components[: len(prefix)] == prefix


def row_contains(pinned: str, row: dict[str, Any]) -> bool:
    """Return True if a CVE JSON 5 version row covers the pinned version."""
    pinned_key = parse_version(pinned)
    start = str(row.get("version", ""))
    if "lessThan" in row:
        return parse_version(start) <= pinned_key < parse_version(str(row["lessThan"]))
    if "lessThanOrEqual" in row:
        upper = str(row["lessThanOrEqual"])
        if pinned_key < parse_version(start):
            return False
        if upper == "*":
            return True
        if upper.endswith(".*"):
            return in_branch(pinned, upper)
        return pinned_key <= parse_version(upper)
    return pinned_key == parse_version(start)


def evaluate_entry(pinned: str, entry: dict[str, Any]) -> tuple[bool, bool]:
    """Evaluate one ``affected[]`` entry.

    Returns ``(has_version_data, affected)``. Git commit ranges are ignored,
    since only a version string is known. Rows without ``lessThan`` or
    ``lessThanOrEqual`` and without a ``versionType`` are "introduced in"
    markers that ``defaultStatus`` already covers, so they are skipped.
    """
    default = entry.get("defaultStatus", "unknown")
    hit_affected = False
    hit_unaffected = False
    has_data = False
    for row in entry.get("versions", []):
        version_type = row.get("versionType")
        is_range = "lessThan" in row or "lessThanOrEqual" in row
        if version_type == "git":
            continue
        if version_type is None and not is_range:
            continue
        if version_type is not None and version_type not in EVALUATED_TYPES:
            raise UnverifiableError(f"unknown versionType: {version_type!r}")
        has_data = True
        if row_contains(pinned, row):
            if row.get("status") == "affected":
                hit_affected = True
            elif row.get("status") == "unaffected":
                hit_unaffected = True
            else:
                raise UnverifiableError(f"unknown status: {row.get('status')!r}")
    if not has_data:
        return (False, False)
    if hit_affected:
        return (True, True)
    if hit_unaffected:
        return (True, False)
    if default not in ("affected", "unaffected"):
        raise UnverifiableError(f"unknown defaultStatus: {default!r}")
    return (True, default == "affected")


def fixed_in(pinned: str, record: dict[str, Any]) -> str:
    """Describe where the fix lands relative to the pinned branch."""
    branch_fix = ""
    mainline_fix = ""
    for entry in record["containers"]["cna"].get("affected", []):
        for row in entry.get("versions", []):
            if row.get("status") != "unaffected" or "lessThanOrEqual" not in row:
                continue
            upper = str(row["lessThanOrEqual"])
            try:
                if upper == "*":
                    mainline_fix = str(row.get("version", ""))
                elif upper.endswith(".*") and in_branch(pinned, upper):
                    branch_fix = str(row.get("version", ""))
            except UnverifiableError:
                continue
    branch = ".".join(str(n) for n in version_components(pinned)[:2])
    mainline = f" (mainline {mainline_fix})" if mainline_fix else ""
    if branch_fix:
        return f"{branch_fix}{mainline}"
    return f"none in {branch}.x{mainline}"


def cvss_score(record: dict[str, Any]) -> float | None:
    """Return the highest CNA CVSS base score, or None if unscored."""
    scores: list[float] = []
    for metric in record["containers"]["cna"].get("metrics", []):
        cvss = metric.get("cvssV3_1")
        if isinstance(cvss, dict) and "baseScore" in cvss:
            scores.append(float(cvss["baseScore"]))
    return max(scores) if scores else None


def matched_files(record: dict[str, Any], paths: tuple[str, ...]) -> list[str]:
    """Return the sorted programFiles that fall under any of the given paths."""
    files: set[str] = set()
    for entry in record["containers"]["cna"].get("affected", []):
        for program_file in entry.get("programFiles", []):
            if program_file.startswith(paths):
                files.add(program_file)
    return sorted(files)


@dataclass
class Finding:
    """A CVE record that affects the pinned kernel."""

    cve_id: str
    title: str
    files: list[str]
    score: float | None
    fix: str
    unverifiable: bool = False
    reason: str = ""


@dataclass
class Result:  # pylint: disable=too-many-instance-attributes
    """Aggregated outcome of a check run."""

    kernel: str
    min_cvss: float
    records: int = 0
    path_matches: int = 0
    affected: list[Finding] = field(default_factory=list)
    flagged: list[Finding] = field(default_factory=list)
    below: list[Finding] = field(default_factory=list)
    unscored: list[Finding] = field(default_factory=list)


def evaluate_record(
    pinned: str, record: dict[str, Any], paths: tuple[str, ...]
) -> Finding | None:
    """Return a Finding if the record matches the paths and affects ``pinned``."""
    files = matched_files(record, paths)
    if not files:
        return None
    cna = record["containers"]["cna"]
    cve_id = str(record.get("cveMetadata", {}).get("cveId", "UNKNOWN"))
    title = str(cna.get("title", ""))
    score = cvss_score(record)
    try:
        results = [evaluate_entry(pinned, e) for e in cna.get("affected", [])]
        if not any(has_data for has_data, _ in results):
            raise UnverifiableError("no semver version data")
        if not any(affected for _, affected in results):
            return None
        fix = fixed_in(pinned, record)
    except UnverifiableError as err:
        return Finding(cve_id, title, files, score, "unknown", True, str(err))
    return Finding(cve_id, title, files, score, fix)


def classify(result: Result, finding: Finding) -> None:
    """Sort an affected finding into flagged, below threshold, or unscored."""
    result.affected.append(finding)
    if result.min_cvss <= 0.0:
        result.flagged.append(finding)
    elif finding.score is None:
        result.unscored.append(finding)
    elif finding.score >= result.min_cvss:
        result.flagged.append(finding)
    else:
        result.below.append(finding)


def read_pin(build_script: Path) -> str:
    """Return the ``KERNEL="X.Y.Z"`` pin from the Packer build script."""
    try:
        text = build_script.read_text(encoding="utf-8")
    except OSError as err:
        raise CheckError(f"cannot read build script {build_script}: {err}") from err
    match = PIN_RE.search(text)
    if not match:
        raise CheckError(f'no KERNEL="X.Y.Z" pin found in {build_script}')
    return match.group(1)


def iter_records(vulns_dir: Path) -> list[Path]:
    """Return the published CVE JSON record paths in a vulns.git checkout."""
    published = vulns_dir / "cve" / "published"
    if not published.is_dir():
        raise CheckError(f"{published} not found; is --vulns-dir a vulns.git checkout?")
    return sorted(published.glob("*/CVE-*.json"))


def run_check(  # pylint: disable=too-many-arguments
    kernel: str,
    vulns_dir: Path,
    paths: tuple[str, ...],
    min_cvss: float,
    *,
    min_records: int = MIN_RECORDS,
    min_path_matches: int = MIN_PATH_MATCHES,
) -> Result:
    """Evaluate every published record against ``kernel``."""
    parse_version(kernel)
    result = Result(kernel=kernel, min_cvss=min_cvss)
    for record_path in iter_records(vulns_dir):
        try:
            record = json.loads(record_path.read_text(encoding="utf-8"))
        except (OSError, ValueError) as err:
            raise CheckError(f"cannot parse {record_path}: {err}") from err
        if not isinstance(record.get("containers", {}).get("cna"), dict):
            raise CheckError(f"{record_path} has no containers.cna object")
        result.records += 1
        if matched_files(record, paths):
            result.path_matches += 1
        finding = evaluate_record(kernel, record, paths)
        if finding is not None:
            classify(result, finding)
    if result.records < min_records:
        raise CheckError(
            f"only {result.records} records parsed (floor {min_records}); "
            "upstream layout may have changed"
        )
    if result.path_matches < min_path_matches:
        raise CheckError(
            f"only {result.path_matches} records match the path filter "
            f"(floor {min_path_matches}); upstream schema may have changed"
        )
    return result


def vulns_commit(vulns_dir: Path) -> str:
    """Return the vulns.git HEAD commit and date, or ``unknown``."""
    try:
        out = subprocess.run(
            ["git", "-C", str(vulns_dir), "log", "-1", "--format=%H %cd"],
            capture_output=True,
            text=True,
            check=False,
        )
    except OSError:
        return "unknown"
    return out.stdout.strip() or "unknown"


def format_score(score: float | None) -> str:
    """Format a CVSS score for display."""
    return "-" if score is None else f"{score:.1f}"


def print_report(result: Result, vulns_dir: Path, paths: tuple[str, ...]) -> None:
    """Print the findings table and summary."""
    print(f"vulns.git:    {vulns_commit(vulns_dir)}")
    print(f"kernel:       {result.kernel}")
    print(f"paths:        {', '.join(paths)}")
    print(f"min CVSS:     {result.min_cvss:.1f}")
    print(
        f"records:      {result.records} parsed, {result.path_matches} match the paths"
    )
    print(
        f"summary:      {len(result.affected)} affected, {len(result.flagged)} flagged, "
        f"{len(result.below)} below threshold, "
        f"{len(result.unscored)} unscored (skipped)"
    )
    if result.flagged:
        print()
        print(f"Flagged CVEs ({len(result.flagged)}):")
        print(f"  {'CVE':<16} {'CVSS':>4}  {'FIXED IN':<34} TITLE / FILES")
        for item in sorted(result.flagged, key=lambda f: (-(f.score or 0.0), f.cve_id)):
            fix = item.fix if not item.unverifiable else f"unverifiable: {item.reason}"
            print(
                f"  {item.cve_id:<16} {format_score(item.score):>4}  {fix:<34} {item.title}"
            )
            print(f"  {'':<16} {'':>4}  {'':<34} {', '.join(item.files)}")
    if result.unscored:
        ids = ", ".join(sorted(f.cve_id for f in result.unscored))
        print()
        print(f"unscored (skipped) ({len(result.unscored)}): {ids}")


def parse_min_cvss(text: str) -> float:
    """Parse and validate a CVSS threshold between 0.0 and 10.0."""
    try:
        value = float(text)
    except ValueError as err:
        raise CheckError(f"--min-cvss must be a number, got {text!r}") from err
    if not 0.0 <= value <= 10.0:
        raise CheckError(f"--min-cvss must be between 0.0 and 10.0, got {value}")
    return value


def main(argv: list[str] | None = None) -> int:
    """Command-line entry point."""
    parser = argparse.ArgumentParser(description=__doc__.split("\n", maxsplit=1)[0])
    parser.add_argument("--build-script", default=DEFAULT_BUILD_SCRIPT)
    parser.add_argument("--vulns-dir", default=DEFAULT_VULNS_DIR)
    parser.add_argument("--paths", nargs="+", default=list(DEFAULT_PATHS))
    parser.add_argument(
        "--min-cvss",
        default=os.environ.get(MIN_CVSS_ENV) or str(DEFAULT_MIN_CVSS),
        help=f"default: ${MIN_CVSS_ENV} or {DEFAULT_MIN_CVSS}",
    )
    args = parser.parse_args(argv)
    paths = tuple(args.paths)
    vulns_dir = Path(args.vulns_dir)
    try:
        min_cvss = parse_min_cvss(str(args.min_cvss))
        kernel = read_pin(Path(args.build_script))
        result = run_check(kernel, vulns_dir, paths, min_cvss)
    except (CheckError, UnverifiableError) as err:
        print(f"ERROR: {err}", file=sys.stderr)
        return EXIT_ERROR
    print_report(result, vulns_dir, paths)
    return EXIT_FLAGGED if result.flagged else EXIT_CLEAN


if __name__ == "__main__":
    sys.exit(main())
