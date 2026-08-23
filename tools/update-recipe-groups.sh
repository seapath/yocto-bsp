#!/usr/bin/env bash
# Generate atomic recipe upgrade PRs using the supported Yocto devtool flow.
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
LAYER_DIR=${SEAPATH_LAYER_DIR:-"$ROOT_DIR/sources/meta-seapath"}
UPSTREAM_REPO=${SEAPATH_UPSTREAM_REPO:-seapath/meta-seapath}
BASE_BRANCH=${SEAPATH_BASE_BRANCH:-wrynose}
FORK_OWNER=${SEAPATH_FORK_OWNER:-}
WORKDIR=${SEAPATH_RECIPE_UPDATE_WORKDIR:-"${XDG_CACHE_HOME:-${HOME}/.cache}/seapath-recipe-updates"}
GROUP_FILTER=all
DRY_RUN=false
NO_PR=false
FORCE=false

declare -A GROUP_RECIPES=(
    [grub]='grub grub-efi'
    [ha]='crmsh pacemaker corosync-qdevice'
    [boost]='boost boost-build-native'
    [ceph]='ceph cephadm'
    [libosinfo]='osinfo-db-tools'
)

usage() {
    cat <<'EOF'
Usage: update-recipe-groups.sh [options]

  --group <name>       grub, ha, boost, ceph, libosinfo, or all
  --layer <path>       meta-seapath checkout
  --workdir <path>     temporary work directory
  --fork <owner>       push destination
  --dry-run            run checks without pushing or opening PRs
  --no-pr              push branches without opening PRs
  --force              recreate existing branches/PRs

The command never creates a partial group PR. A failed devtool operation or a
targeted parse/fetch/compile check leaves a report and resets the group branch.
EOF
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --group) GROUP_FILTER=${2:?missing value}; shift 2 ;;
        --layer) LAYER_DIR=${2:?missing value}; shift 2 ;;
        --workdir) WORKDIR=${2:?missing value}; shift 2 ;;
        --fork) FORK_OWNER=${2:?missing value}; shift 2 ;;
        --dry-run) DRY_RUN=true; shift ;;
        --no-pr) NO_PR=true; shift ;;
        --force) FORCE=true; shift ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; exit 2 ;;
    esac
done

require() { command -v "$1" >/dev/null 2>&1 || { echo "required command missing: $1" >&2; exit 1; }; }
require git
require devtool
require bitbake
[[ -d "$LAYER_DIR/.git" ]] || { echo "meta-seapath checkout not found: $LAYER_DIR" >&2; exit 1; }

if [[ "$GROUP_FILTER" != all && -z "${GROUP_RECIPES[$GROUP_FILTER]+x}" ]]; then
    echo "unknown group: $GROUP_FILTER" >&2
    exit 2
fi
if [[ "$DRY_RUN" != true && "$NO_PR" != true ]]; then require gh; fi

mkdir -p "$WORKDIR"
if [[ -z "$FORK_OWNER" && "$DRY_RUN" != true ]]; then FORK_OWNER=$(gh api user --jq .login); fi

groups=(grub ha boost ceph libosinfo)
[[ "$GROUP_FILTER" == all ]] || groups=("$GROUP_FILTER")

cd "$LAYER_DIR"
git fetch --quiet --prune origin "$BASE_BRANCH"

for group in "${groups[@]}"; do
    branch="recipe-upgrade-${group}-$(date -u +%Y%m%d)"
    if [[ "$DRY_RUN" != true && "$FORCE" != true ]]; then
        existing=$(gh pr list --repo "$UPSTREAM_REPO" --state open --head "$branch" --json url --jq '.[0].url' || true)
        [[ -z "$existing" ]] || { echo "$group: PR already exists: $existing"; continue; }
    fi

    report="$WORKDIR/${group}-$(date -u +%Y%m%dT%H%M%SZ).log"
    git checkout --quiet --force -B "$branch" "origin/$BASE_BRANCH"
    git reset --quiet --hard "origin/$BASE_BRANCH"
    git clean --quiet -fdx
    recipes=${GROUP_RECIPES[$group]}
    {
        echo "group=$group"
        echo "recipes=$recipes"
        echo "started=$(date -u +%FT%TZ)"
        for recipe in $recipes; do
            echo "== devtool check-upgrade-status $recipe =="
            devtool check-upgrade-status "$recipe"
        done
        for recipe in $recipes; do
            echo "== devtool upgrade $recipe =="
            devtool upgrade "$recipe"
            echo "== devtool finish $recipe =="
            devtool finish --force-patch-refresh "$recipe" "$LAYER_DIR"
        done
        if [[ "$group" == ceph ]]; then
            versions=$(grep -rhoE '^(PV|SRC_URI).*20\.[0-9]+\.[0-9]+' recipes-* 2>/dev/null || true)
            if grep -Eq '20\.(0|1|3)\.' <<<"$versions"; then
                echo "Ceph upgrade escaped the supported 20.2.x series" >&2
                exit 1
            fi
        fi
        echo "== targeted parse =="
        bitbake -p ${recipes}
        echo "== targeted fetch =="
        bitbake -c fetch ${recipes}
        echo "== targeted compile =="
        bitbake -c compile ${recipes}
        echo "completed=$(date -u +%FT%TZ)"
    } >"$report" 2>&1 || {
        echo "$group: upgrade/check failed; report: $report" >&2
        git reset --quiet --hard "origin/$BASE_BRANCH"
        git clean --quiet -fdx
        continue
    }

    changed=$(git diff --name-only)
    [[ -n "$changed" ]] || { echo "$group: no upgrade available"; continue; }
    git add -A
    git commit -s -m "recipes: update ${group} recipe group"
    if [[ "$DRY_RUN" == true ]]; then
        echo "$group: dry-run commit created; report: $report"
        continue
    fi
    if [[ -n "${GH_TOKEN:-}" ]]; then
        push_url="https://x-access-token:${GH_TOKEN}@github.com/$FORK_OWNER/meta-seapath.git"
    else
        push_url="git@github.com:$FORK_OWNER/meta-seapath.git"
    fi
    if [[ "$FORK_OWNER" == "${UPSTREAM_REPO%%/*}" ]]; then head=$branch; else head="$FORK_OWNER:$branch"; fi
    git push --quiet --force-with-lease "$push_url" "$branch"
    if [[ "$NO_PR" != true ]]; then
        gh pr create --repo "$UPSTREAM_REPO" --base "$BASE_BRANCH" --head "$head" \
            --title "recipes: update ${group} recipe group" \
            --body "Automated atomic upgrade for: ${recipes}. The attached CI runs targeted parse, fetch, and compile checks."
    fi
done
