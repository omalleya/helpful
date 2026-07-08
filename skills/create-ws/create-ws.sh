#!/usr/bin/env bash
# Create a git worktree under <repo>/.worktrees/<slug> for a branch and open a
# tmux session: left pane = shell, right pane split horizontally with Claude
# (top) and Codex (bottom). Works in any git repo, not one specific project.
#
# Usage:
#   create-ws.sh [--repo <path>] [--setup <cmd>] [--prompt <cmd>] \
#     <branch> [base-ref] [initial-prompt]
#
#   <branch>         branch to create/check out (e.g. aidan/proj-1234-widget)
#   [base-ref]       start point for a NEW branch; default: the repo's own
#                    default branch (origin/HEAD, falling back to origin/main
#                    then origin/master). Ignored when the branch already exists.
#   [initial-prompt] legacy positional form of --prompt (kept for compatibility).
#
# Options:
#   --repo <path>    git repo to create the worktree in (default: current repo).
#   --setup <cmd>    command to run in the shell pane after creation, in the new
#                    worktree (e.g. "pnpm install"). Runs asynchronously.
#   --prompt <cmd>   if given, the Claude pane launches running this prompt
#                    immediately (e.g. "/ship-ticket --here"). Omit for an idle
#                    Claude pane. Preferred over the positional form since it
#                    doesn't require also passing a base-ref.
set -euo pipefail

REPO_ARG=""
SETUP_CMD=""
PROMPT_ARG=""

# Flags may precede the positionals.
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO_ARG="${2:-}"; shift 2 ;;
    --repo=*) REPO_ARG="${1#*=}"; shift ;;
    --setup) SETUP_CMD="${2:-}"; shift 2 ;;
    --setup=*) SETUP_CMD="${1#*=}"; shift ;;
    --prompt) PROMPT_ARG="${2:-}"; shift 2 ;;
    --prompt=*) PROMPT_ARG="${1#*=}"; shift ;;
    --) shift; break ;;
    -*) echo "error: unknown option: $1" >&2; exit 1 ;;
    *) break ;;
  esac
done

BRANCH="${1:-}"
BASE_REF="${2:-}"
# --prompt wins; else the legacy 3rd positional. Empty = idle Claude pane.
INIT_PROMPT="${PROMPT_ARG:-${3:-}}"

usage() {
  echo "usage: create-ws.sh [--repo <path>] [--setup <cmd>] [--prompt <cmd>] <branch> [base-ref] [initial-prompt]" >&2
}

if [ -z "$BRANCH" ]; then
  echo "error: branch name is required" >&2
  usage
  exit 1
fi

# Detect the repo's default branch: origin/HEAD, then origin/main, then
# origin/master. Used only when creating a new branch without an explicit base.
detect_default_branch() {
  local head
  head="$(git -C "$MAIN_ROOT" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)"
  if [ -n "$head" ]; then
    printf '%s' "${head#origin/}"
    return
  fi
  if git -C "$MAIN_ROOT" show-ref --verify --quiet refs/remotes/origin/main; then
    printf 'main'
    return
  fi
  printf 'master'
}

# Copy untracked local env files a fresh worktree won't have (repo-agnostic).
# Prune node_modules/.git/.worktrees so this stays fast in a monorepo; skip
# committed templates (.env.example etc.).
copy_local_env_files() {
  local file rel base dest
  while IFS= read -r file; do
    rel="${file#"$MAIN_ROOT"/}"
    base="${rel##*/}"
    case "$base" in
      .env.example|.env.sample|.env.template|.env.dist) continue ;;
    esac
    dest="$WT_DIR/$rel"
    mkdir -p "$(dirname "$dest")"
    cp "$file" "$dest"
    echo "env copied: $rel"
  done < <(
    find "$MAIN_ROOT" \
      \( -name node_modules -o -name .git -o -name .worktrees \) -prune -o \
      -type f \( -name '.env' -o -name '.env.*' \) -print
  )
}

# Resolve the target repo's main worktree root (default: current directory).
REPO_CWD="${REPO_ARG:-$PWD}"
if ! git -C "$REPO_CWD" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "error: not a git repository: $REPO_CWD" >&2
  exit 1
fi
MAIN_ROOT="$(git -C "$REPO_CWD" worktree list --porcelain | awk '/^worktree /{print $2; exit}')"
if [ -z "$MAIN_ROOT" ]; then
  echo "error: could not resolve main worktree root for: $REPO_CWD" >&2
  exit 1
fi

# Slug for the worktree dir + tmux session: drop any owner/ prefix, lowercase,
# keep [a-z0-9-], collapse/trim hyphens, prefer <= 32 chars on a hyphen
# boundary. Keeps the issue key / short branch name so the session name says
# what it's for.
slug="${BRANCH##*/}"
slug="$(printf '%s' "$slug" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9-' '-')"
slug="$(printf '%s' "$slug" | sed -E 's/-+/-/g; s/^-+//; s/-+$//')"
if [ "${#slug}" -gt 32 ]; then
  trunc="${slug:0:32}"
  case "$trunc" in
    *-*) trunc="${trunc%-*}" ;;
  esac
  slug="$(printf '%s' "$trunc" | sed -E 's/-+$//')"
fi
if [ -z "$slug" ]; then
  echo "error: branch '$BRANCH' produced an empty slug" >&2
  exit 1
fi

WT_DIR="$MAIN_ROOT/.worktrees/$slug"
SESSION="$slug"

# Fail fast on collisions rather than clobbering existing work.
if [ -e "$WT_DIR" ]; then
  echo "error: worktree path already exists: $WT_DIR" >&2
  exit 1
fi
if tmux has-session -t "=$SESSION" 2>/dev/null; then
  echo "error: tmux session '$SESSION' already exists (attach: tmux attach -t $SESSION)" >&2
  exit 1
fi

git -C "$MAIN_ROOT" fetch origin --quiet || true

if [ -z "$BASE_REF" ]; then
  BASE_REF="origin/$(detect_default_branch)"
fi

# Reuse the branch if it already exists; otherwise create it off the base ref.
if git -C "$MAIN_ROOT" show-ref --verify --quiet "refs/heads/$BRANCH"; then
  git -C "$MAIN_ROOT" worktree add "$WT_DIR" "$BRANCH" >/dev/null
else
  git -C "$MAIN_ROOT" worktree add -b "$BRANCH" "$WT_DIR" "$BASE_REF" >/dev/null
fi

copy_local_env_files

# tmux: left pane = shell; right pane split with Claude (top) + Codex (bottom),
# all cwd'd into the worktree.
tmux new-session -d -s "$SESSION" -c "$WT_DIR"
left_pane="$(tmux list-panes -t "$SESSION" -F '#{pane_id}' | head -1)"
right_top="$(tmux split-window -h -t "$left_pane" -c "$WT_DIR" -P -F '#{pane_id}')"
right_bottom="$(tmux split-window -v -t "$right_top" -c "$WT_DIR" -P -F '#{pane_id}')"

if [ -n "$INIT_PROMPT" ]; then
  tmux send-keys -t "$right_top" "claude $(printf '%q' "$INIT_PROMPT")" Enter
else
  tmux send-keys -t "$right_top" 'claude' Enter
fi
tmux send-keys -t "$right_bottom" 'codex' Enter

if [ -n "$SETUP_CMD" ]; then
  tmux send-keys -t "$left_pane" "$SETUP_CMD" Enter
fi

tmux select-pane -t "$left_pane"

echo "repo     : $MAIN_ROOT"
echo "worktree : $WT_DIR"
echo "branch   : $BRANCH  (base: $BASE_REF)"
echo "session  : $SESSION  (shell | claude / codex)"
[ -n "$SETUP_CMD" ] && echo "setup    : $SETUP_CMD  (running in shell pane)"
echo "attach   : tmux attach -t $SESSION"
