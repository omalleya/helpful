#!/usr/bin/env bash
# restack-analyze.sh — READ-ONLY analysis for restacking the current branch (B)
# onto the parent branch (A) it is stacked on. Mutates nothing: it fetches,
# detects the parent, judges what the parent gained since B forked, reads B's PR
# state, and prints a recommended operation (rebase vs merge) plus the exact
# command the caller should run. All decisions that mutate the repo live in the
# skill prose, not here.
#
# Usage:
#   restack-analyze.sh [parent-ref]
#
#   [parent-ref]  Optional explicit parent: a branch (local or origin/…) or SHA.
#                 Omitted → auto-detect (PR base → workmux-base config → nearest
#                 local ancestor branch → trunk).
#
# Output is line-oriented. The caller scrapes these keys:
#   branch:        <B>
#   parent:        <A name>          (<how it was resolved>)
#   parent-ref:    <refA to sync from>
#   merge-base:    <X>
#   pr:            <state or "none"/"unknown">
#   recommend:     rebase | merge
#   push-after:    force-with-lease | normal
#   command:       <the git command to run>
#   flags:         <space-separated flags, or "none">
# followed by human-readable detail sections.
set -euo pipefail

repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo "ERROR: not inside a git repository." >&2; exit 1; }
cd "$repo_root"

B=$(git branch --show-current)
if [[ -z "$B" ]]; then
  echo "ERROR: detached HEAD. Check out the branch you want to restack first." >&2
  exit 1
fi

flags=""
add_flag() { flags="${flags:+$flags }$1"; }

# Best-effort fetch so origin refs / PR base aren't stale.
if ! git fetch origin --quiet 2>/dev/null; then
  echo "WARN: 'git fetch origin' failed; origin refs may be stale." >&2
fi

resolve_ref() {
  local c
  for c in "$@"; do
    [[ -n "$c" ]] || continue
    if git rev-parse --verify --quiet "$c^{commit}" >/dev/null 2>&1; then
      printf '%s\n' "$c"; return 0
    fi
  done
  return 1
}

# Default trunk: origin/HEAD's target, else common names.
trunk_default=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)
trunk=$(resolve_ref "$trunk_default" origin/master origin/main origin/develop || true)
trunk_short="${trunk#origin/}"

# ---- Parent NAME resolution -------------------------------------------------
# Emits $A_name (short branch name, no origin/ prefix) and $parent_how.
explicit="${1:-}"
A_name=""
parent_how=""

# Collect nearest local ancestor feature branches (for suggestion / sanity).
ancestors=""
while IFS= read -r ref; do
  [[ -n "$ref" ]] || continue
  [[ "$ref" == "$B" ]] && continue
  [[ "$ref" == "$trunk_short" ]] && continue
  if git merge-base --is-ancestor "$ref" HEAD 2>/dev/null; then
    dist=$(git rev-list --count "$ref..HEAD" 2>/dev/null || echo 999999)
    ancestors="${ancestors}${dist} ${ref}"$'\n'
  fi
done < <(git for-each-ref --format='%(refname:short)' refs/heads/)
nearest_ancestor=$(printf '%s' "$ancestors" | grep -v '^$' | sort -n | head -1 | awk '{print $2}' || true)

if [[ -n "$explicit" ]]; then
  parent_how="explicit argument"
  A_name="${explicit#origin/}"
else
  pr_base=$(gh pr view "$B" --json baseRefName -q .baseRefName 2>/dev/null || true)
  if [[ -n "$pr_base" ]]; then
    A_name="$pr_base"; parent_how="PR base branch"
  else
    cfg_base=$(git config --local --get "branch.$B.workmux-base" 2>/dev/null || true)
    if [[ -n "$cfg_base" ]]; then
      A_name="$cfg_base"; parent_how="workmux-base config"
    elif [[ -n "$nearest_ancestor" ]]; then
      A_name="$nearest_ancestor"; parent_how="nearest local ancestor branch"
      add_flag "ASK-PARENT"
    else
      A_name="$trunk_short"; parent_how="default trunk (no parent detected)"
    fi
  fi
fi

# If detection landed on trunk but a nearer feature ancestor exists, the branch
# is probably stacked on that instead — ask rather than assume.
if [[ "$A_name" == "$trunk_short" && -n "$nearest_ancestor" && "$parent_how" != "explicit argument" ]]; then
  add_flag "ASK-PARENT"
fi

# ---- Which parent state to sync from (local vs origin) ----------------------
local_ref="refs/heads/$A_name"
remote_ref="refs/remotes/origin/$A_name"
have_local=$(git rev-parse --verify --quiet "$local_ref" >/dev/null 2>&1 && echo 1 || true)
have_remote=$(git rev-parse --verify --quiet "$remote_ref" >/dev/null 2>&1 && echo 1 || true)

refA=""
parent_state=""
if [[ -n "$have_local" && -n "$have_remote" ]]; then
  counts=$(git rev-list --left-right --count "$local_ref...$remote_ref" 2>/dev/null || echo "0	0")
  L=$(printf '%s' "$counts" | awk '{print $1}')
  R=$(printf '%s' "$counts" | awk '{print $2}')
  L=${L:-0}; R=${R:-0}
  if (( L > 0 && R > 0 )); then
    refA="$local_ref"; parent_state="DIVERGED (local +$L / origin +$R)"; add_flag "STOP-DIVERGED"
  elif (( L > 0 )); then
    refA="$local_ref"; parent_state="local ahead of origin by $L (unpushed parent work)"
    add_flag "LOCAL-A-AHEAD"
  elif (( R > 0 )); then
    refA="$remote_ref"; parent_state="origin ahead of local by $R"
  else
    refA="$local_ref"; parent_state="local and origin identical"
  fi
elif [[ -n "$have_local" ]]; then
  refA="$local_ref"; parent_state="local only (parent never pushed)"
elif [[ -n "$have_remote" ]]; then
  refA="$remote_ref"; parent_state="origin only (parent not checked out locally)"
else
  echo "ERROR: parent '$A_name' resolves to neither refs/heads nor origin/. Pass an explicit parent." >&2
  exit 1
fi

# ---- Merge-base + up-to-date short-circuit ----------------------------------
X=$(git merge-base "$refA" HEAD) || {
  echo "ERROR: no common ancestor between HEAD and '$refA'." >&2; exit 1; }
if [[ "$(git rev-parse "$refA")" == "$X" ]]; then
  echo "branch:        $B"
  echo "parent:        $A_name  ($parent_how)"
  echo "parent-ref:    $refA"
  echo "merge-base:    $X"
  echo "recommend:     none"
  echo "flags:         up-to-date"
  echo
  echo "UP TO DATE: '$A_name' has gained no commits since '$B' forked ($X)."
  echo "Nothing to restack."
  exit 0
fi

# ---- Materiality ------------------------------------------------------------
FA=$(git diff --name-only "$X" "$refA" | sort -u)
FB=$(git diff --name-only "$X" HEAD | sort -u)
overlap=$(comm -12 <(printf '%s\n' "$FA") <(printf '%s\n' "$FB") | grep -v '^$' || true)
n_overlap=$(printf '%s\n' "$overlap" | grep -c . || true)
n_fa=$(printf '%s\n' "$FA" | grep -c . || true)
[[ -n "$overlap" ]] && add_flag "OVERLAP"

# ---- PR state → recommendation ----------------------------------------------
pr_tsv=""
pr_err=""
if pr_tsv=$(gh pr view "$B" --json number,state,isDraft,baseRefName,url \
      -q '[(.number|tostring),.state,(.isDraft|tostring),.baseRefName,.url]|@tsv' 2>/tmp/restack_pr_err); then
  :
else
  pr_err=$(cat /tmp/restack_pr_err 2>/dev/null || true)
fi
rm -f /tmp/restack_pr_err 2>/dev/null || true

pr_desc="unknown"
recommend=""
push_after=""
origin_B=$(git rev-parse --verify --quiet "refs/remotes/origin/$B" >/dev/null 2>&1 && echo 1 || true)

if [[ -n "$pr_tsv" ]]; then
  pr_num=$(printf '%s' "$pr_tsv" | cut -f1)
  pr_state=$(printf '%s' "$pr_tsv" | cut -f2)
  pr_draft=$(printf '%s' "$pr_tsv" | cut -f3)
  pr_url=$(printf '%s' "$pr_tsv" | cut -f5)
  if [[ "$pr_draft" == "true" ]]; then
    pr_desc="#$pr_num DRAFT ($pr_url)"; recommend="rebase"; push_after="force-with-lease"
  elif [[ "$pr_state" == "OPEN" ]]; then
    pr_desc="#$pr_num OPEN ($pr_url)"; recommend="merge"; push_after="normal"
  else
    pr_desc="#$pr_num $pr_state ($pr_url)"; recommend="merge"; push_after="normal"
    add_flag "PR-$pr_state"
  fi
elif printf '%s' "$pr_err" | grep -qi "no .*pull request"; then
  pr_desc="none"
  if [[ -n "$origin_B" ]]; then
    recommend="rebase"; push_after="force-with-lease"
  else
    recommend="rebase"; push_after="none (branch not pushed)"
  fi
else
  pr_desc="unknown (gh error)"; add_flag "PR-UNKNOWN"
  if [[ -n "$origin_B" ]]; then
    recommend="merge"; push_after="normal"
  else
    recommend="rebase"; push_after="none (branch not pushed)"
  fi
fi

# ---- Rebase form: append-only vs rewritten parent ---------------------------
old_base=""
suggested=""
if [[ "$recommend" == "rebase" ]]; then
  a_ids=$(for c in $(git rev-list "$X..$refA"); do
            git show "$c" 2>/dev/null | git patch-id --stable 2>/dev/null | awk '{print $1}'
          done | sort -u | grep -v '^$' || true)
  carried=""
  for c in $(git rev-list "$X..HEAD"); do
    p=$(git show "$c" 2>/dev/null | git patch-id --stable 2>/dev/null | awk '{print $1}')
    [[ -n "$p" ]] || continue
    if printf '%s\n' "$a_ids" | grep -qxF "$p"; then carried="${carried}${c}"$'\n'; fi
  done
  if [[ -n "$carried" ]]; then
    add_flag "PARENT-REWRITTEN"
    old_base=$(git merge-base --fork-point "$refA" HEAD 2>/dev/null || true)
    if [[ -z "$old_base" ]]; then
      old_base="$X"
      for c in $(git rev-list --reverse "$X..HEAD"); do
        p=$(git show "$c" 2>/dev/null | git patch-id --stable 2>/dev/null | awk '{print $1}')
        if printf '%s\n' "$a_ids" | grep -qxF "$p"; then old_base="$c"; else break; fi
      done
    fi
  else
    old_base="$X"
  fi
  suggested="git rebase --onto $refA $old_base HEAD"
elif [[ "$recommend" == "merge" ]]; then
  suggested="git merge --no-ff $refA -m \"merge $A_name into $B\""
fi

[[ -n "$flags" ]] || flags="none"

# ---- Emit -------------------------------------------------------------------
echo "branch:        $B"
echo "parent:        $A_name  ($parent_how)"
echo "parent-ref:    $refA"
echo "parent-state:  $parent_state"
echo "merge-base:    $X"
echo "pr:            $pr_desc"
echo "recommend:     $recommend"
echo "push-after:    $push_after"
[[ -n "$old_base" ]] && echo "old-base:      $old_base"
echo "command:       $suggested"
echo "flags:         $flags"
echo
echo "parent gained (since B forked):"
git log --oneline "$X..$refA"
echo
echo "diffstat (parent since fork):"
git diff --stat "$X" "$refA"
echo
echo "OVERLAP — files BOTH branches changed ($n_overlap of ${n_fa} parent files)"
echo "  (highest conflict/semantic risk; review even if git does not conflict):"
if [[ -n "$overlap" ]]; then printf '  %s\n' $overlap; else echo "  (none)"; fi

# ---- Guidance for flags -----------------------------------------------------
case " $flags " in
  *" STOP-DIVERGED "*)
    echo >&2
    echo "STOP: parent '$A_name' has diverged (local and origin both have unique commits)." >&2
    echo "      It was likely rebased/force-pushed. Decide which side is authoritative" >&2
    echo "      and re-run with an explicit parent ref (e.g. origin/$A_name or $A_name)." >&2 ;;
esac
case " $flags " in
  *" ASK-PARENT "*)
    echo >&2
    echo "CONFIRM PARENT: detection is not certain. Nearest local ancestor branch:" >&2
    echo "      ${nearest_ancestor:-<none>}. Confirm the parent before rebasing." >&2 ;;
esac
