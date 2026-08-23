#!/usr/bin/env bash
# Update the two kernels used by SEAPATH and open one grouped PR.
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

UPSTREAM_REPO=${SEAPATH_UPSTREAM_REPO:-seapath/meta-seapath}
BASE_BRANCH=${SEAPATH_BASE_BRANCH:-wrynose}
WORKDIR=${SEAPATH_KERNEL_UPDATE_WORKDIR:-${XDG_CACHE_HOME:-${HOME}/.cache}/seapath-kernel-update}
FORK_OWNER=${SEAPATH_FORK_OWNER:-}
DRY_RUN=false
NO_PR=false
FORCE=false
PUSH_PROTOCOL=ssh
GIT_NAME=${SEAPATH_GIT_NAME:-}
GIT_EMAIL=${SEAPATH_GIT_EMAIL:-}

STABLE_GIT=${SEAPATH_KERNEL_GIT:-https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git}
RT_GIT=${SEAPATH_RT_KERNEL_GIT:-https://git.kernel.org/pub/scm/linux/kernel/git/rt/linux-stable-rt.git}

usage() {
    cat <<'EOF'
Usage: update-kernel-revisions.sh [options]

Updates linux-mainline-rt_6.12.bb and linux-mainline-rt_6.1.bb together so a
kernel refresh is reviewed and merged atomically.

  --repo <owner/repository>  meta-seapath repository
  --base-branch <branch>     target branch (default: wrynose)
  --workdir <path>           clone/cache directory
  --fork <owner>             push destination
  --https                    push over HTTPS
  --dry-run                  update a local branch without pushing
  --no-pr                    push without creating a PR
  --force                    recreate an existing topic branch/PR
EOF
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --repo) UPSTREAM_REPO=${2:?missing value}; shift 2 ;;
        --base-branch) BASE_BRANCH=${2:?missing value}; shift 2 ;;
        --workdir) WORKDIR=${2:?missing value}; shift 2 ;;
        --fork) FORK_OWNER=${2:?missing value}; shift 2 ;;
        --https) PUSH_PROTOCOL=https; shift ;;
        --git-name) GIT_NAME=${2:?missing value}; shift 2 ;;
        --git-email) GIT_EMAIL=${2:?missing value}; shift 2 ;;
        --dry-run) DRY_RUN=true; shift ;;
        --no-pr) NO_PR=true; shift ;;
        --force) FORCE=true; shift ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; exit 2 ;;
    esac
done

require() { command -v "$1" >/dev/null 2>&1 || { echo "required command missing: $1" >&2; exit 1; }; }
require git
require sed
require sort
if [[ "$DRY_RUN" != true && "$NO_PR" != true ]]; then require gh; fi

mkdir -p "$WORKDIR"
exec 9>"$WORKDIR/.lock"
command -v flock >/dev/null 2>&1 && flock -n 9 || true

repo_name=${UPSTREAM_REPO##*/}
clone_dir="$WORKDIR/$repo_name"
if [[ ! -d "$clone_dir/.git" ]]; then
    git clone --quiet "https://github.com/$UPSTREAM_REPO" "$clone_dir"
fi
cd "$clone_dir"
git remote set-url origin "https://github.com/$UPSTREAM_REPO"
git fetch --quiet --prune origin "$BASE_BRANCH"
git checkout --quiet --force -B "$BASE_BRANCH" "origin/$BASE_BRANCH"
git reset --quiet --hard "origin/$BASE_BRANCH"
git clean --quiet -fdx

if [[ -z "$FORK_OWNER" && "$DRY_RUN" != true ]]; then
    FORK_OWNER=$(gh api user --jq .login)
fi

if [[ "$DRY_RUN" != true ]]; then
    branch="kernel-update-$(date -u +%Y%m%d)"
    if [[ "$FORCE" != true ]]; then
        existing=$(gh pr list --repo "$UPSTREAM_REPO" --state open --head "$branch" --json url --jq '.[0].url' || true)
        [[ -z "$existing" ]] || { echo "PR already exists: $existing"; exit 0; }
    fi
else
    branch="kernel-update-dry-run"
fi

update_stable() {
    local recipe=recipes-kernel/linux/linux-mainline-rt_6.12.bb
    local remote_tags latest_revision latest_version latest_srcrev current_revision
    current_revision=$(sed -n -E 's/^LINUX_REVISION_VERSION = "([0-9]+)"$/\1/p' "$recipe")
    remote_tags=$(git ls-remote --tags "$STABLE_GIT" 'refs/tags/v6.12.*')
    latest_revision=$(printf '%s\n' "$remote_tags" | sed -n -E 's#^[0-9a-f]{40}[[:space:]]+refs/tags/v6\.12\.([0-9]+)$#\1#p' | sort -n | tail -1)
    latest_version="6.12.$latest_revision"
    latest_srcrev=$(printf '%s\n' "$remote_tags" | awk -v ref="refs/tags/v${latest_version}^{}" '$2 == ref {print $1}')
    [[ -n "$latest_srcrev" ]] || latest_srcrev=$(printf '%s\n' "$remote_tags" | awk -v ref="refs/tags/v${latest_version}" '$2 == ref {print $1}')
    [[ -n "$latest_revision" && -n "$latest_srcrev" ]] || { echo "cannot resolve latest 6.12 tag" >&2; return 1; }
    if [[ "$latest_revision" -le "$current_revision" ]]; then
        echo "6.12 is up to date at v6.12.$current_revision"
        return 0
    fi
    sed -i -E "s#^LINUX_REVISION_VERSION = \"[0-9]+\"$#LINUX_REVISION_VERSION = \"$latest_revision\"#" "$recipe"
    sed -i -E "s#^SRCREV = \"[0-9a-f]{40}\"$#SRCREV = \"$latest_srcrev\"#" "$recipe"
    echo "6.12: v6.12.$current_revision -> v$latest_version"
}

update_rt() {
    local recipe=recipes-kernel/linux/linux-mainline-rt_6.1.bb
    local remote_tags latest_tag latest_revision latest_rt latest_version latest_srcrev
    local current_revision current_rt
    current_revision=$(sed -n -E 's/^LINUX_REVISION_VERSION = "([0-9]+)"$/\1/p' "$recipe")
    current_rt=$(sed -n -E 's/^RT_REVISION = "([^"]+)"$/\1/p' "$recipe")
    remote_tags=$(git ls-remote --tags "$RT_GIT" 'refs/tags/v6.1.*-rt*')
    latest_tag=$(printf '%s\n' "$remote_tags" | sed -n -E 's#^[0-9a-f]{40}[[:space:]]+refs/tags/(v6\.1\.[0-9]+-rt[0-9]+)$#\1#p' | sort -V | tail -1)
    [[ -n "$latest_tag" ]] || { echo "cannot resolve latest 6.1 RT tag" >&2; return 1; }
    latest_revision=${latest_tag#v6.1.}; latest_revision=${latest_revision%%-*}
    latest_rt=${latest_tag#*-}
    latest_version="6.1.${latest_revision}-${latest_rt}"
    latest_srcrev=$(printf '%s\n' "$remote_tags" | awk -v ref="refs/tags/${latest_tag}^{}" '$2 == ref {print $1}')
    [[ -n "$latest_srcrev" ]] || latest_srcrev=$(printf '%s\n' "$remote_tags" | awk -v ref="refs/tags/${latest_tag}" '$2 == ref {print $1}')
    [[ -n "$latest_tag" && -n "$latest_srcrev" ]] || { echo "cannot resolve latest 6.1 RT tag" >&2; return 1; }
    if [[ "$latest_revision" -lt "$current_revision" || ( "$latest_revision" -eq "$current_revision" && "$latest_rt" == "$current_rt" ) ]]; then
        echo "6.1 RT is up to date at v6.1.$current_revision-$current_rt"
        return 0
    fi
    sed -i -E "s#^LINUX_REVISION_VERSION = \"[0-9]+\"$#LINUX_REVISION_VERSION = \"$latest_revision\"#" "$recipe"
    sed -i -E "s#^RT_REVISION = \"[^\"]+\"$#RT_REVISION = \"$latest_rt\"#" "$recipe"
    sed -i -E "s#^SRCREV = \"[0-9a-f]{40}\"$#SRCREV = \"$latest_srcrev\"#" "$recipe"
    echo "6.1 RT: v6.1.$current_revision-$current_rt -> v$latest_version"
}

git checkout --quiet -B "$branch" "origin/$BASE_BRANCH"
update_stable
update_rt

changed=$(git diff --name-only)
if [[ -n "$changed" ]]; then
    while read -r changed_file; do
        case "$changed_file" in
            recipes-kernel/linux/linux-mainline-rt_6.1.bb|recipes-kernel/linux/linux-mainline-rt_6.12.bb) ;;
            *) echo "unexpected file changed: $changed_file" >&2; exit 1 ;;
        esac
    done <<< "$changed"
    if [[ -n "$GIT_NAME" ]]; then git config user.name "$GIT_NAME"; fi
    if [[ -n "$GIT_EMAIL" ]]; then git config user.email "$GIT_EMAIL"; fi
    git config user.name >/dev/null || { echo "git user.name is not set" >&2; exit 1; }
    git config user.email >/dev/null || { echo "git user.email is not set" >&2; exit 1; }
    git add recipes-kernel/linux/linux-mainline-rt_6.1.bb recipes-kernel/linux/linux-mainline-rt_6.12.bb
    git commit -s -m "recipes-kernel/linux: update 6.1 RT and 6.12 kernels"
else
    echo "No kernel update available"
    exit 0
fi

if [[ "$DRY_RUN" == true ]]; then
    git --no-pager show --stat --oneline HEAD
    exit 0
fi

if [[ "$PUSH_PROTOCOL" == ssh ]]; then
    push_url="git@github.com:$FORK_OWNER/$repo_name.git"
elif [[ -n "${GH_TOKEN:-}" ]]; then
    push_url="https://x-access-token:${GH_TOKEN}@github.com/$FORK_OWNER/$repo_name.git"
else
    push_url="https://github.com/$FORK_OWNER/$repo_name.git"
fi
git push --quiet --force-with-lease "$push_url" "$branch"
if [[ "$NO_PR" == true ]]; then exit 0; fi
if [[ "$FORK_OWNER" == "${UPSTREAM_REPO%%/*}" ]]; then head=$branch; else head="$FORK_OWNER:$branch"; fi
gh pr create --repo "$UPSTREAM_REPO" --base "$BASE_BRANCH" --head "$head" \
    --title "recipes-kernel/linux: update 6.1 RT and 6.12 kernels" \
    --body "Automated grouped update of the active 6.1 RT and 6.12 kernel recipes. Targeted recipe checks must pass before merge."
