#!/usr/bin/env bash
# Generate the SHA-locked weekly baseline and its machine-readable metadata.
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
MANIFEST_REPOSITORY=${MANIFEST_REPOSITORY:-SEAPATH/repo-manifest}
MANIFEST_BASE_BRANCH=${SEAPATH_MANIFEST_BASE_BRANCH:-main}
SOURCE_MANIFEST=${SOURCE_MANIFEST:-wrynose.xml}
WEEKLY_MANIFEST=${WEEKLY_MANIFEST:-weekly.xml}
METADATA_FILE=${METADATA_FILE:-weekly-metadata.json}
OUTPUT_DIR=${OUTPUT_DIR:-"${ROOT_DIR}/.weekly-candidate"}
WEEKLY_ID=${WEEKLY_ID:-"weekly-$(date -u +%G-W%V)"}
PREVIOUS_WEEKLY=${PREVIOUS_WEEKLY:-}
DRY_RUN=false
OPEN_PR=false
ALLOW_EXISTING=false

usage() {
    cat <<'EOF'
Usage: update-weekly-manifest.sh [options]

Synchronize the current repo checkout, create a complete SHA-locked manifest,
and write weekly-metadata.json. The command is deliberately side-effect free
with respect to GitHub unless --open-pr is requested.

Options:
  --source-manifest <name>   Moving manifest to lock (default: wrynose.xml)
  --weekly-id <id>           Weekly identifier (default: weekly-YYYY-Www)
  --output-dir <path>        Candidate output directory
  --previous-weekly <id>     Previous published weekly identifier
  --open-pr                  Commit, push, and open one repo-manifest PR
  --allow-existing           Do not stop when a weekly PR is already open
  --dry-run                  Generate and validate without committing
EOF
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --source-manifest) SOURCE_MANIFEST=${2:?missing value}; shift 2 ;;
        --weekly-id) WEEKLY_ID=${2:?missing value}; shift 2 ;;
        --output-dir) OUTPUT_DIR=${2:?missing value}; shift 2 ;;
        --previous-weekly) PREVIOUS_WEEKLY=${2:?missing value}; shift 2 ;;
        --open-pr) OPEN_PR=true; shift ;;
        --allow-existing) ALLOW_EXISTING=true; shift ;;
        --dry-run) DRY_RUN=true; shift ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; exit 2 ;;
    esac
done

require() { command -v "$1" >/dev/null 2>&1 || { echo "required command missing: $1" >&2; exit 1; }; }
require repo
require python3
require sha256sum

cd "$ROOT_DIR"
[[ -f ".repo/manifests/${SOURCE_MANIFEST}" ]] || {
    echo "source manifest not found: .repo/manifests/${SOURCE_MANIFEST}" >&2
    exit 1
}

if [[ "$OPEN_PR" == true && "$ALLOW_EXISTING" != true && -n "${GH_TOKEN:-}${GITHUB_TOKEN:-}" ]]; then
    require gh
    existing=$(gh pr list --repo "$MANIFEST_REPOSITORY" --state open \
        --search "weekly baseline in:title" --json number,url --jq '.[0].url' || true)
    if [[ -n "$existing" ]]; then
        echo "a weekly manifest candidate is already open: $existing" >&2
        exit 3
    fi
fi

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

echo "Synchronizing branches referenced by ${SOURCE_MANIFEST}"
repo sync
repo manifest -m "$SOURCE_MANIFEST" -r > "$tmp_dir/${WEEKLY_MANIFEST}"

"$ROOT_DIR/tools/verify-weekly-manifest.sh" "$tmp_dir/${WEEKLY_MANIFEST}" > "$tmp_dir/projects.json"
manifest_sha256=$(sha256sum "$tmp_dir/${WEEKLY_MANIFEST}" | awk '{print $1}')

active_manifest=".repo/manifests/${WEEKLY_MANIFEST}"
if [[ -f "$active_manifest" ]]; then
    "$ROOT_DIR/tools/verify-weekly-manifest.sh" "$active_manifest" > "$tmp_dir/active-projects.json"
    if cmp -s "$tmp_dir/projects.json" "$tmp_dir/active-projects.json"; then
        echo "No project revision changed; no weekly candidate is required."
        exit 0
    fi
fi

mkdir -p "$OUTPUT_DIR"
cp "$tmp_dir/${WEEKLY_MANIFEST}" "$OUTPUT_DIR/${WEEKLY_MANIFEST}"
python3 - "$OUTPUT_DIR/$METADATA_FILE" "$WEEKLY_ID" "$manifest_sha256" \
    "$SOURCE_MANIFEST" "$PREVIOUS_WEEKLY" "$tmp_dir/projects.json" <<'PY'
import json
import sys
from datetime import datetime, timezone

out, weekly_id, manifest_sha, source, previous, projects_path = sys.argv[1:]
projects = json.load(open(projects_path, encoding="utf-8"))
now = datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
metadata = {
    "schema_version": 1,
    "weekly_id": weekly_id,
    "created_at": now,
    "cut_at": now,
    "source_manifest": source,
    "manifest": "weekly.xml",
    "manifest_sha256": manifest_sha,
    "previous_weekly": previous or None,
    "projects": projects,
}
with open(out, "w", encoding="utf-8") as stream:
    json.dump(metadata, stream, indent=2, sort_keys=True)
    stream.write("\n")
PY

if [[ "$DRY_RUN" == true || "$OPEN_PR" != true ]]; then
    echo "Weekly candidate written to $OUTPUT_DIR"
    exit 0
fi

require gh
repo_manifest_dir="$tmp_dir/repo-manifest"
gh repo clone "$MANIFEST_REPOSITORY" "$repo_manifest_dir" -- --quiet
pushd "$repo_manifest_dir" >/dev/null
branch="weekly/${WEEKLY_ID}"
git checkout -B "$branch"
cp "$OUTPUT_DIR/${WEEKLY_MANIFEST}" .
cp "$OUTPUT_DIR/$METADATA_FILE" .
git add "$WEEKLY_MANIFEST" "$METADATA_FILE"
if git diff --cached --quiet; then
    echo "Weekly manifest is already current; no PR created."
    exit 0
fi
git commit -s -m "manifest: update ${WEEKLY_ID} baseline"
git push --force-with-lease origin "$branch"
gh pr create --repo "$MANIFEST_REPOSITORY" --base "$MANIFEST_BASE_BRANCH" --head "$branch" \
    --title "manifest: update ${WEEKLY_ID} baseline" \
    --body "Automated weekly baseline candidate. Merge manually to activate CI."
popd >/dev/null
