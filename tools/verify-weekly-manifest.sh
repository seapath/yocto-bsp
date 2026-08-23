#!/usr/bin/env bash
# Validate that a repo manifest is suitable as an immutable weekly baseline.
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: verify-weekly-manifest.sh <manifest.xml>

Checks that the XML is well formed and every project revision is a complete
40-character commit SHA.  The command prints the canonical project -> SHA map
as JSON and exits non-zero on the first invalid manifest.
EOF
}

if [[ $# -ne 1 || "$1" == "-h" || "$1" == "--help" ]]; then
    usage
    [[ $# -eq 1 ]] && exit 0 || exit 2
fi

manifest=$1
[[ -f "$manifest" ]] || { echo "manifest not found: $manifest" >&2; exit 1; }

python3 - "$manifest" <<'PY'
import json
import re
import sys
import xml.etree.ElementTree as ET

path = sys.argv[1]
try:
    root = ET.parse(path).getroot()
except (ET.ParseError, OSError) as exc:
    print(f"invalid manifest {path}: {exc}", file=sys.stderr)
    raise SystemExit(1)

projects = {}
invalid = []
for project in root.findall("project"):
    name = project.get("name")
    revision = project.get("revision")
    if not name or not revision:
        invalid.append(f"project missing name or revision: {ET.tostring(project, encoding='unicode')}")
        continue
    if not re.fullmatch(r"[0-9a-fA-F]{40}", revision):
        invalid.append(f"{name}: revision is not a complete commit SHA ({revision!r})")
    if name in projects:
        invalid.append(f"duplicate project: {name}")
    projects[name] = revision.lower()

if not projects:
    invalid.append("manifest contains no projects")
if invalid:
    print("\n".join(invalid), file=sys.stderr)
    raise SystemExit(1)

print(json.dumps(dict(sorted(projects.items())), sort_keys=True))
PY
