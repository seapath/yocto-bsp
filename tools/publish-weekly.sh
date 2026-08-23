#!/usr/bin/env bash
# Publish a candidate weekly and retain only the latest two successful weeklies.
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

WEEKLY_ID=""
ARTIFACT_DIR=""
OUTPUT_ROOT=""
BUCKET="s3://seapath-releases"
RETAIN=2
DRY_RUN=false
S3_HOST="${S3_HOST:-e1e604922c4057433cbe77d3700ac51c.r2.cloudflarestorage.com}"
S3_HOST_BUCKET="${S3_HOST_BUCKET:-%(bucket)s.e1e604922c4057433cbe77d3700ac51c.r2.cloudflarestorage.com}"

usage() {
    cat <<'EOF'
Usage: publish-weekly.sh --weekly-id <id> --artifact-dir <path> [options]
  --output-root <path>  publish locally instead of using s3cmd
  --bucket <uri>        R2 bucket (default: s3://seapath-releases)
  --retain <count>      successful weeklies to preserve (default: 2)
  --dry-run             validate and print operations without copying
EOF
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --weekly-id) WEEKLY_ID=${2:?missing value}; shift 2 ;;
        --artifact-dir) ARTIFACT_DIR=${2:?missing value}; shift 2 ;;
        --output-root) OUTPUT_ROOT=${2:?missing value}; shift 2 ;;
        --bucket) BUCKET=${2:?missing value}; shift 2 ;;
        --retain) RETAIN=${2:?missing value}; shift 2 ;;
        --dry-run) DRY_RUN=true; shift ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; exit 2 ;;
    esac
done

[[ "$WEEKLY_ID" =~ ^weekly-[0-9]{4}-W[0-9]{2}(\.[0-9]+)?$ ]] || { echo "invalid weekly ID: $WEEKLY_ID" >&2; exit 2; }
[[ -d "$ARTIFACT_DIR" ]] || { echo "artifact directory not found: $ARTIFACT_DIR" >&2; exit 1; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
assembled="$tmp/assembled"
mkdir -p "$assembled"
cp -a "$ARTIFACT_DIR"/. "$assembled"/

if [[ ! -f "$assembled/weekly-metadata.json" ]]; then
    printf '{"schema_version":1,"weekly_id":"%s","manifest":"weekly.xml"}\n' "$WEEKLY_ID" > "$assembled/weekly-metadata.json"
fi
find "$assembled" -type f -name aggregate.md -print -quit | while read -r report; do cp "$report" "$assembled/security-aggregate.md"; done
find "$assembled" -type f ! -name provenance.json ! -name latest.json -printf '%P\n' | sort | while read -r path; do sha256sum "$assembled/$path"; done > "$assembled/artifact-sha256sums.txt"

python3 - "$assembled/provenance.json" "$WEEKLY_ID" "$assembled/weekly-metadata.json" "$assembled/artifact-sha256sums.txt" <<'PY'
import json, sys
from pathlib import Path
out, weekly_id, metadata_file, hashes = sys.argv[1:]
metadata=json.loads(Path(metadata_file).read_text())
files={}
for line in Path(hashes).read_text().splitlines():
    digest, path=line.split(maxsplit=1); files[path]=digest
Path(out).write_text(json.dumps({'schema_version':1,'weekly_id':weekly_id,'manifest':metadata.get('manifest','weekly.xml'),'manifest_sha256':metadata.get('manifest_sha256',''),'artifacts':files}, indent=2, sort_keys=True)+'\n')
PY
python3 - "$assembled/latest.json" "$WEEKLY_ID" "$assembled/provenance.json" <<'PY'
import json, sys
from pathlib import Path
out, weekly_id, provenance = sys.argv[1:]
data=json.loads(Path(provenance).read_text()); files=data['artifacts']
root=Path(provenance).parent
summary={'chronological':{},'controlled':{}}
for diff in root.glob('security/*/*/diff.json'):
    mode=diff.parent.name
    if mode not in summary:
        continue
    try:
        counts=json.loads(diff.read_text()).get('counts',{})
    except (OSError, ValueError, TypeError):
        continue
    for key in ('new','resolved','persistent','package-upgraded','risk-changed','status-changed'):
        summary[mode][key]=summary[mode].get(key,0)+int(counts.get(key,0))
Path(out).write_text(json.dumps({'schema_version':1,'active_weekly':weekly_id,'base_url':f'builds/weeklies/{weekly_id}/','manifest':data['manifest'],'images':sorted(p for p in files if p.endswith(('.wic.gz','.wic.qcow2','.swu','.bmap'))),'sboms':sorted(p for p in files if p.endswith('.spdx.json')),'vulnscout_reports':sorted(p for p in files if 'security' in p or 'vulnscout' in p),'security_summary':summary}, indent=2, sort_keys=True)+'\n')
PY

if [[ "$DRY_RUN" == true ]]; then
    echo "Would publish $WEEKLY_ID ($(wc -l < "$assembled/artifact-sha256sums.txt") files), retaining $RETAIN weeklies"
    exit 0
fi

publish_local() {
    local root=$1 target="$1/builds/weeklies/$WEEKLY_ID"
    mkdir -p "$root/builds/weeklies"
    if [[ -d "$target" ]]; then
        cmp -s "$target/provenance.json" "$assembled/provenance.json" || { echo "refusing to overwrite weekly with different content" >&2; exit 1; }
    else
        cp -a "$assembled" "$target"
    fi
    cp "$target/latest.json" "$root/builds/weeklies/latest.json"
    mapfile -t old < <(find "$root/builds/weeklies" -mindepth 1 -maxdepth 1 -type d -name 'weekly-*' -printf '%f\n' | sort -V)
    while (( ${#old[@]} > RETAIN )); do
        mv "$root/builds/weeklies/${old[0]}" "$tmp/expired-${old[0]}"
        old=("${old[@]:1}")
    done
}

if [[ -n "$OUTPUT_ROOT" ]]; then
    publish_local "$OUTPUT_ROOT"
    exit 0
fi

command -v s3cmd >/dev/null || { echo "s3cmd is required for R2 publication" >&2; exit 1; }
: "${S3CMD_ACCESS_KEY:?S3CMD_ACCESS_KEY is required}"
: "${S3CMD_SECRET_KEY:?S3CMD_SECRET_KEY is required}"
s3() { s3cmd --access_key="$S3CMD_ACCESS_KEY" --secret_key="$S3CMD_SECRET_KEY" --host="$S3_HOST" --host-bucket="$S3_HOST_BUCKET" "$@"; }
remote="$BUCKET/builds/weeklies/$WEEKLY_ID"
if s3 ls "$remote/provenance.json" | grep -q .; then
    s3 get "$remote/provenance.json" "$tmp/remote-provenance.json"
    cmp -s "$tmp/remote-provenance.json" "$assembled/provenance.json" || { echo "refusing to overwrite weekly with different content" >&2; exit 1; }
else
    s3 sync "$assembled/" "$remote/"
fi
s3 put "$assembled/latest.json" "$BUCKET/builds/weeklies/latest.json"
mapfile -t old < <(s3 ls "$BUCKET/builds/weeklies/" | awk '{print $4}' | sed -E 's#/$##; s#.*/##' | grep -E '^weekly-[0-9]{4}-W[0-9]{2}(\.[0-9]+)?$' | sort -V)
while (( ${#old[@]} > RETAIN )); do
    s3 del --recursive "$BUCKET/builds/weeklies/${old[0]}/"
    old=("${old[@]:1}")
done
