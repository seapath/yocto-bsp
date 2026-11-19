#!/usr/bin/env python3
"""Create stable, reviewable vulnerability diffs from VulnScout JSON exports.

The exporter format has changed slightly between VulnScout releases.  This
script intentionally discovers CVE-shaped records recursively and keeps the
original records in the JSON output, so a database refresh cannot make the
weekly publication fail merely because an optional field moved.
"""

from __future__ import annotations

import argparse
import csv
import html
import json
import re
from pathlib import Path
from typing import Any

CVE_RE = re.compile(r"^CVE-\d{4}-\d{4,}$", re.IGNORECASE)


def _walk(value: Any):
    if isinstance(value, dict):
        yield value
        for child in value.values():
            yield from _walk(child)
    elif isinstance(value, list):
        for child in value:
            yield from _walk(child)


def _first(record: dict[str, Any], *keys: str, default: Any = "") -> Any:
    for key in keys:
        if key in record and record[key] not in (None, ""):
            return record[key]
    return default


def records_from_data(data: Any) -> dict[str, dict[str, Any]]:
    found: dict[str, dict[str, Any]] = {}
    for item in _walk(data):
        candidate = _first(item, "cve", "cve_id", "id", "vulnerability_id")
        if not isinstance(candidate, str) or not CVE_RE.match(candidate):
            continue
        cve = candidate.upper()
        found.setdefault(
            cve,
            {
                "cve": cve,
                "package": _first(item, "package", "package_name", "component", "name"),
                "version": _first(item, "version", "installed_version", "package_version"),
                "fixed": _first(item, "fixed", "fixed_version", "fix_version"),
                "status": _first(item, "status", "assessment", "vex_status"),
                "cvss": _first(item, "cvss", "cvss_score", "score"),
                "epss": _first(item, "epss", "epss_score", "epss_percentile"),
                "record": item,
            },
        )
    return found


def load_records(path: Path | None) -> tuple[dict[str, dict[str, Any]], str]:
    if not path or not path.exists():
        return {}, "missing"
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}, "invalid"
    return records_from_data(data), "valid"


def make_diff(previous: dict[str, dict[str, Any]], current: dict[str, dict[str, Any]], mode: str, baseline_status: str = "valid") -> dict[str, Any]:
    if baseline_status != "valid":
        return {
            "schema_version": 1,
            "mode": mode,
            "status": "initial-baseline",
            "counts": {key: 0 for key in ("new", "resolved", "persistent", "package-upgraded", "risk-changed", "status-changed")},
            "items": [],
        }
    items = []
    for cve in sorted(set(previous) | set(current)):
        old, new = previous.get(cve), current.get(cve)
        if old is None:
            kind = "new"
        elif new is None:
            kind = "resolved"
        else:
            kind = "persistent"
        changes: list[str] = []
        if old and new:
            if old.get("package") != new.get("package") or old.get("version") != new.get("version"):
                changes.append("package-upgraded")
            if old.get("cvss") != new.get("cvss") or old.get("epss") != new.get("epss"):
                changes.append("risk-changed")
            if old.get("status") != new.get("status"):
                changes.append("status-changed")
        item = {"cve": cve, "kind": kind, "changes": changes, "previous": old, "current": new}
        items.append(item)
    counts = {key: 0 for key in ("new", "resolved", "persistent", "package-upgraded", "risk-changed", "status-changed")}
    for item in items:
        counts[item["kind"]] += 1
        for change in item["changes"]:
            counts[change] += 1
    return {"schema_version": 1, "mode": mode, "status": "complete", "counts": counts, "items": items}


def write_outputs(diff: dict[str, Any], output: Path) -> None:
    output.mkdir(parents=True, exist_ok=True)
    (output / "diff.json").write_text(json.dumps(diff, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    with (output / "vulnerabilities.csv").open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=["cve", "kind", "changes", "package", "version", "cvss", "epss", "status"])
        writer.writeheader()
        for item in diff["items"]:
            record = item.get("current") or item.get("previous") or {}
            writer.writerow({"cve": item["cve"], "kind": item["kind"], "changes": ",".join(item["changes"]), **{key: record.get(key, "") for key in ("package", "version", "cvss", "epss", "status")}})
    counts = diff["counts"]
    lines = [f"# Vulnerability diff ({diff['mode']})", "", f"Status: **{diff['status']}**", "", "| Category | Count |", "| --- | ---: |"]
    lines.extend(f"| {key} | {counts[key]} |" for key in counts)
    lines.extend(["", "| CVE | Kind | Changes | Package | Version | CVSS | EPSS | Status |", "| --- | --- | --- | --- | --- | ---: | ---: | --- |"])
    for item in diff["items"]:
        record = item.get("current") or item.get("previous") or {}
        lines.append("| {cve} | {kind} | {changes} | {package} | {version} | {cvss} | {epss} | {status} |".format(cve=item["cve"], kind=item["kind"], changes=", ".join(item["changes"]), **{key: record.get(key, "") for key in ("package", "version", "cvss", "epss", "status")}))
    markdown = "\n".join(lines) + "\n"
    (output / "summary.md").write_text(markdown, encoding="utf-8")
    (output / "summary.adoc").write_text(markdown.replace("# ", "= ", 1), encoding="utf-8")
    (output / "summary.html").write_text("<html><body><pre>" + html.escape(markdown) + "</pre></body></html>\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--previous", type=Path)
    parser.add_argument("--current", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--mode", choices=("chronological", "controlled"), required=True)
    args = parser.parse_args()
    previous, baseline_status = load_records(args.previous)
    current, current_status = load_records(args.current)
    if current_status != "valid":
        raise SystemExit(f"current export is {current_status}")
    write_outputs(make_diff(previous, current, args.mode, baseline_status), args.output_dir)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
