#!/usr/bin/env bash
# Promote an immutable weekly candidate to an official release prefix.
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

WEEKLY_ID=""
VERSION=""
SOURCE_DIR=""
OUTPUT_ROOT=""
CORRECTIVE_SEQUENCE=""
DRY_RUN=false

usage() {
    cat <<'EOF'
Usage: promote-weekly.sh --weekly-id <weekly-id> --version <vX.Y.Z> [options]
  --source-dir <path>       local published weekly (otherwise use R2)
  --output-root <path>      local destination for testing
  --corrective-sequence <n> source a weekly corrective cut
  --dry-run                 validate without copying

The script never rebuilds. It refuses a version mismatch and leaves tag
creation to the maintainer after the repo-manifest PR is merged.
EOF
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --weekly-id) WEEKLY_ID=${2:?missing value}; shift 2 ;;
        --version) VERSION=${2:?missing value}; shift 2 ;;
        --source-dir) SOURCE_DIR=${2:?missing value}; shift 2 ;;
        --output-root) OUTPUT_ROOT=${2:?missing value}; shift 2 ;;
        --corrective-sequence) CORRECTIVE_SEQUENCE=${2:?missing value}; shift 2 ;;
        --dry-run) DRY_RUN=true; shift ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; exit 2 ;;
    esac
done

[[ "$WEEKLY_ID" =~ ^weekly-[0-9]{4}-W[0-9]{2}(\.[0-9]+)?$ ]] || { echo "invalid weekly ID" >&2; exit 2; }
[[ "$VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "version must be vX.Y.Z" >&2; exit 2; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
if [[ -z "$SOURCE_DIR" ]]; then
    command -v s3cmd >/dev/null || { echo "s3cmd is required when --source-dir is omitted" >&2; exit 1; }
    : "${S3CMD_ACCESS_KEY:?S3CMD_ACCESS_KEY is required}"
    : "${S3CMD_SECRET_KEY:?S3CMD_SECRET_KEY is required}"
    s3cmd --access_key="$S3CMD_ACCESS_KEY" --secret_key="$S3CMD_SECRET_KEY" sync "s3://seapath-releases/builds/weeklies/$WEEKLY_ID/" "$tmp/weekly/"
    SOURCE_DIR="$tmp/weekly"
fi
[[ -d "$SOURCE_DIR" ]] || { echo "weekly not found: $SOURCE_DIR" >&2; exit 1; }

find "$SOURCE_DIR" -type f -name '*.json' -print0 | while IFS= read -r -d '' file; do
    distro=$(jq -r '.distro_version // empty' "$file" 2>/dev/null || true)
    if [[ -n "$distro" && "$distro" != unknown && "$distro" != "$VERSION" ]]; then
        echo "DISTRO_VERSION mismatch in $file: expected $VERSION, got $distro" >&2
        exit 1
    fi
done
if ! find "$SOURCE_DIR" -type f -name '*.json' -exec jq -e --arg v "$VERSION" '(.distro_version? // empty) == $v' {} \; 2>/dev/null | grep -q true; then
    echo "no artifact provenance contains DISTRO_VERSION=$VERSION" >&2
    exit 1
fi

target_name="$VERSION"
[[ -z "$CORRECTIVE_SEQUENCE" ]] || target_name="${VERSION}.${CORRECTIVE_SEQUENCE}"
if [[ "$DRY_RUN" == true ]]; then
    echo "Weekly $WEEKLY_ID is eligible for promotion to $target_name"
    exit 0
fi

if [[ -n "$OUTPUT_ROOT" ]]; then
    target="$OUTPUT_ROOT/builds/$target_name"
    [[ ! -e "$target" ]] || { echo "release already exists: $target" >&2; exit 1; }
    mkdir -p "$target"
    cp -a "$SOURCE_DIR"/. "$target/"
    printf '%s\n' "$WEEKLY_ID" > "$target/source-weekly"
else
    command -v s3cmd >/dev/null || { echo "s3cmd is required for R2 promotion" >&2; exit 1; }
    : "${S3CMD_ACCESS_KEY:?S3CMD_ACCESS_KEY is required}"
    : "${S3CMD_SECRET_KEY:?S3CMD_SECRET_KEY is required}"
    s3cmd --access_key="$S3CMD_ACCESS_KEY" --secret_key="$S3CMD_SECRET_KEY" sync "$SOURCE_DIR/" "s3://seapath-releases/builds/$target_name/"
    printf '%s\n' "$WEEKLY_ID" | s3cmd --access_key="$S3CMD_ACCESS_KEY" --secret_key="$S3CMD_SECRET_KEY" put - "s3://seapath-releases/builds/$target_name/source-weekly"
fi

echo "Promoted $WEEKLY_ID to $target_name. Prepare the manifest PR with repo-manifest/tools/prepare-release.sh; create the tag only after merge."
