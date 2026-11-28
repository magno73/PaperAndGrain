#!/bin/bash
# Publishes the current branch to GitHub as `main`, with the author email replaced by the
# GitHub noreply address. The local repository is never rewritten: the script works on a
# temporary clone. The rewrite is deterministic, so commits published before keep their
# hashes and later runs push as a fast-forward.
set -euo pipefail
cd "$(dirname "$0")/.."

remote="${PAPERGRAIN_GITHUB_REPO:-https://github.com/magno73/PaperAndGrain.git}"
private_email="${PAPERGRAIN_PRIVATE_EMAIL:-$(git config user.email)}"
public_email="${PAPERGRAIN_PUBLIC_EMAIL:-175606015+magno73@users.noreply.github.com}"
branch="$(git rev-parse --abbrev-ref HEAD)"
# Files that must never appear in the public history, not even in old commits.
removed_paths=(docs/layout-comparison.md docs/release-plan.md docs/prd-0.11.md)
force=""
tag=""
dry_run=""
while [ $# -gt 0 ]; do
    case "$1" in
        --force)
            # Overwrite only the commit GitHub has now, never work pushed from elsewhere in the meantime.
            current="$(git ls-remote "$remote" refs/heads/main | cut -f1)"
            force="--force-with-lease=main:$current" ;;
        --dry-run)
            dry_run="--dry-run" ;;
        --tag)
            # The tag must be made on the rewritten commit, so it is created in the clone below.
            tag="${2:?--tag needs a name such as v0.10.0}"; shift ;;
        *) echo "Unknown option $1 (use --dry-run, --force or --tag vX.Y.Z)" >&2; exit 2 ;;
    esac
    shift
done

if [ -n "$(git status --porcelain)" ]; then
    echo "Commit or discard local changes before publishing." >&2
    exit 1
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
git clone --quiet --no-local --single-branch --branch "$branch" . "$work/repo"
cd "$work/repo"
git remote remove origin

export PRIVATE_EMAIL="$private_email" PUBLIC_EMAIL="$public_email"
export REMOVED_PATHS="${removed_paths[*]}"
FILTER_BRANCH_SQUELCH_WARNING=1 git filter-branch --force --prune-empty --env-filter '
    if [ "$GIT_AUTHOR_EMAIL" = "$PRIVATE_EMAIL" ]; then export GIT_AUTHOR_EMAIL="$PUBLIC_EMAIL"; fi
    if [ "$GIT_COMMITTER_EMAIL" = "$PRIVATE_EMAIL" ]; then export GIT_COMMITTER_EMAIL="$PUBLIC_EMAIL"; fi
' --index-filter 'git rm --cached --quiet --ignore-unmatch $REMOVED_PATHS' -- "$branch" >/dev/null

for path in "${removed_paths[@]}"; do
    if [ -n "$(git log --format=%H -- "$path")" ]; then
        echo "$path is still in the history; nothing was pushed." >&2
        exit 1
    fi
done

if git log --format='%ae%n%ce%n%B' | grep -iF -- "$private_email" >/dev/null; then
    echo "The private email is still in the history; nothing was pushed." >&2
    exit 1
fi

# HTTPS with the GitHub CLI login, so an unrelated SSH deploy key is never offered.
# Pass --force once after adding a path to removed_paths: the published history changes.
refs=("$branch:main")
if [ -n "$tag" ]; then
    git -c user.email="$public_email" tag -a "$tag" -m "Paper & Grain ${tag#v}"
    refs+=("refs/tags/$tag")
fi
git -c credential.helper= -c credential.helper='!gh auth git-credential' push --atomic $force $dry_run "$remote" "${refs[@]}"
if [ -z "$dry_run" ]; then
    echo "Published $(git rev-parse HEAD) as main to $remote"
fi
