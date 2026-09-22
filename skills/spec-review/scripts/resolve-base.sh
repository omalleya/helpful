#!/usr/bin/env bash
# Resolve the base ref for reviewing the current branch's diff, handling
# stacked / forked branches — not just trunk. Prints a summary (branch, base,
# merge-base SHA, changed-file count, diffstat, file list) to stdout. The caller
# uses the printed merge-base to pull hunks: `git diff <merge-base> HEAD [-- path]`.
#
# Usage:
#   resolve-base.sh [base-ref]
#
#   [base-ref]  Optional explicit base: a branch (local or origin/…), a tag, or
#               a SHA. Pass the parent feature branch when this branch is stacked.
#               Omitted → auto-detect: the PR's base branch if a PR exists,
#               otherwise the repo's default trunk.
#
# Base resolution order:
#   1. Explicit arg (tried as-is, then as origin/<arg>).
#   2. The open PR's base branch for this HEAD (gh pr view), as origin/<base>.
#   3. Default trunk: origin/HEAD, else origin/{master,main,develop}.
set -euo pipefail

repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo "ERROR: not inside a git repository." >&2; exit 1; }
cd "$repo_root"

branch=$(git branch --show-current)
if [[ -z "$branch" ]]; then
  echo "ERROR: detached HEAD. Check out the branch you want to review first." >&2
  exit 1
fi

# Best-effort fetch so origin refs (and the PR base) aren't stale.
if ! git fetch origin --quiet 2>/dev/null; then
  echo "WARN: 'git fetch origin' failed; origin refs may be stale." >&2
fi

resolve_ref() {
  # Print the first of the given candidates that exists as a ref.
  local c
  for c in "$@"; do
    [[ -n "$c" ]] || continue
    if git rev-parse --verify --quiet "$c^{commit}" >/dev/null 2>&1; then
      printf '%s\n' "$c"; return 0
    fi
  done
  return 1
}

# Default trunk: prefer origin/HEAD's target, then common names.
trunk_default=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)
trunk=$(resolve_ref "$trunk_default" origin/master origin/main origin/develop || true)

explicit="${1:-}"
base=""
source_kind=""

if [[ -n "$explicit" ]]; then
  base=$(resolve_ref "$explicit" "origin/$explicit" || true)
  source_kind="explicit argument"
  if [[ -z "$base" ]]; then
    echo "ERROR: could not resolve base ref '$explicit' (tried '$explicit' and 'origin/$explicit')." >&2
    exit 1
  fi
else
  pr_base=$(gh pr view "$branch" --json baseRefName -q .baseRefName 2>/dev/null || true)
  if [[ -n "$pr_base" ]]; then
    base=$(resolve_ref "origin/$pr_base" "$pr_base" || true)
    source_kind="PR base branch ($pr_base)"
  fi
  if [[ -z "$base" ]]; then
    base="$trunk"
    source_kind="default trunk (no PR base found)"
  fi
fi

if [[ -z "$base" ]]; then
  echo "ERROR: could not resolve any base ref. Pass one explicitly: resolve-base.sh <ref>." >&2
  exit 1
fi

mergebase=$(git merge-base "$base" HEAD) || {
  echo "ERROR: no common ancestor between HEAD and '$base'." >&2; exit 1; }

files=$(git diff --name-only "$mergebase" HEAD)
nfiles=$(printf '%s\n' "$files" | grep -c . || true)

echo "branch:        $branch"
echo "base:          $base  ($source_kind)"
echo "merge-base:    $mergebase"
echo "review diff:   git diff $mergebase HEAD"
echo "changed files: $nfiles"
echo
echo "diffstat:"
git diff --stat "$mergebase" HEAD
echo
echo "changed files:"
[[ -n "$files" ]] && printf '%s\n' "$files"

if (( nfiles > 150 )); then
  {
    echo
    echo "WARN: $nfiles changed files is large for one branch. If this branch is"
    echo "      stacked on another feature branch, the base is probably wrong —"
    echo "      re-run with that parent branch: resolve-base.sh <parent-branch>."
  } >&2
fi
