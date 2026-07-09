#!/usr/bin/env bash
#
# Interactive tmux session switcher, launched in an fzf popup by `prefix + s`.
# Browse and switch sessions, watch a live pane preview, set a per-session
# status emoji, and reorder the list. fzf runs the --* subcommands below via
# its key bindings; each writes state and asks fzf to reload/refresh.
#
# Each row also shows its worktree's GitHub PR (branch glyph + number, colored
# by state) when one exists; `o` opens it in the browser. PR state is cached
# and warmed in the background, so drawing the list never blocks on gh.
#
set -euo pipefail

# Transient: index of the pane currently shown in the preview.
STATE_FILE="${TMPDIR:-/tmp}/tmux-session-switcher.paneidx"
# Transient: the digits typed so far for a numeric jump, plus a timestamp
# ("digits epoch") so a pause between keystrokes starts a fresh number.
DIGIT_FILE="${TMPDIR:-/tmp}/tmux-session-switcher.digits"
# Persisted: desired session order, one name per line.
ORDER_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/tmux/session-order"
# Cached PR state, one file per session (state⇥isDraft⇥number⇥url, or the
# literal `none`). Warmed in the background by `--warm-prs`; the list only ever
# reads it, so rendering never blocks on the network.
PR_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/tmux-session-switcher/pr"
# Seconds a cached PR entry stays fresh before a warm refetches it.
PR_TTL=90
# Touched by a warm whenever a PR's cached state actually changes. The periodic
# tick reloads the list only when it sees this, so chips refresh without
# disturbing the cursor or live preview when nothing changed.
PR_DIRTY="$PR_CACHE_DIR/.dirty"

# Absolute path to this script, so fzf key bindings can re-invoke its
# --* subcommands. Defined before the dispatch below, which references it.
SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"

# ── Search mode (vim-style `/`) ─────────────────────────────────────────────
# Hotkey mode is fzf's --disabled state: the single letters below are actions,
# so typing can't filter. `/` flips to search mode (search enabled, those keys
# unbound so they type). Emptying the query or Esc flips back.
TYPING_KEYS='/,p,a,e,r,d,o,j,k,0,1,2,3,4,5,6,7,8,9'
HOTKEY_HEADER='#s jump   j/k move   C-j/C-k reorder   Tab pane   [p]PR [a]active [e]exp [r]review [d]clear   [o]open↗   C-x clean   / search   ↵ switch'
SEARCH_HEADER='search: type to filter · empty ⌫ or Esc exits'
ENTER_SEARCH="clear-query+enable-search+change-prompt(search ▸ )+change-header($SEARCH_HEADER)+unbind($TYPING_KEYS)"
EXIT_SEARCH="clear-query+disable-search+change-prompt(session ▸ )+change-header($HOTKEY_HEADER)+rebind($TYPING_KEYS)+reload($SELF --list)"

# ── Session list ───────────────────────────────────────────────────────────

emoji_for() {
  case "$1" in
    pr)           printf '✅' ;;
    active)       printf '✏️' ;;
    experimental) printf '🧪' ;;
    review)       printf '👀' ;;
    *)            printf '· ' ;;
  esac
}

# Automatic agent-state glyph, rendered after the name — a second axis
# independent of the manual @state phase emoji before it. Fed by each agent's
# lifecycle hooks via set-agent-state.sh (@claude / @codex). working ▶ (cyan),
# blocked/awaiting-you ! (red); idle/finished shows nothing.
agent_glyph() {
  case "$2" in
    working) printf '\033[36m%s▶\033[0m' "$1" ;;
    waiting) printf '\033[31m%s!\033[0m' "$1" ;;
  esac
}

# Display copy of a session name, capped at 20 columns so long worktree names
# don't shove the windows/agent/PR columns off the right edge; the full name
# stays in field 1 (the identity key). Padded to a fixed 20 columns by hand,
# since printf's width counts the ellipsis's bytes rather than its one column.
NAME_WIDTH=20
fit_name() {
  local n="$1"
  [ "${#n}" -gt "$NAME_WIDTH" ] && n="${n:0:$((NAME_WIDTH - 1))}…"
  printf '%s%*s' "$n" "$((NAME_WIDTH - ${#n}))" ''
}

# Session names in display order: saved order first (skipping any that no
# longer exist), then live sessions not yet in the order file, appended.
effective_order() {
  local current
  current=$(tmux list-sessions -F '#{session_name}')
  if [ -f "$ORDER_FILE" ]; then
    while read -r name || [ -n "$name" ]; do
      [ -n "$name" ] && grep -qxF "$name" <<< "$current" && printf '%s\n' "$name"
    done < "$ORDER_FILE"
  fi
  while read -r name; do
    { [ ! -f "$ORDER_FILE" ] || ! grep -qxF "$name" "$ORDER_FILE"; } && printf '%s\n' "$name"
  done <<< "$current"
}

# One fzf row per session: tab-separated name (field 1, the identity key)
# and the emoji-prefixed display column (field 2), prefixed with a 1-based
# row number so digit keys can jump straight to it.
list_sessions() {
  while read -r name; do
    tmux display-message -p -t "$name" \
      -F '#{session_name}	#{?@state,#{@state},none}	#{session_windows}	#{?session_attached,*,-}	#{?@claude,#{@claude},-}	#{?@codex,#{@codex},-}'
  done < <(effective_order) \
  | { index=0; while IFS=$'\t' read -r name state windows attached claude codex; do
      index=$((index + 1))
      [ "$attached" = - ] && attached=""
      [ "$claude" = - ] && claude=""
      [ "$codex" = - ] && codex=""
      agents="$(agent_glyph C "$claude")$(agent_glyph X "$codex")"
      chip="$(pr_chip "$name")"
      printf '%s\t%2d  %s  %s %sw%s%s%s\n' \
        "$name" "$index" "$(emoji_for "$state")" "$(fit_name "$name")" "$windows" \
        "${attached:+  (attached)}" "${agents:+  $agents}" "${chip:+  $chip}"
    done; }
}

# ── Git / PR state ─────────────────────────────────────────────────────────
# Each session's worktree branch may have a GitHub PR. Its state is cached per
# session (never fetched during render) so the list draws instantly; a
# background `--warm-prs` refetches stale entries. Colors: open=green,
# draft=gray, merged=purple, closed=red.

# Colored branch-glyph + PR-number chip for $1 (session name), read from cache.
# Prints nothing when there is no cache entry or the branch has no PR.
pr_chip() {
  local name="$1" cache state isDraft number color
  cache="$(pr_cache_file "$name")"
  [ -f "$cache" ] || return 0
  IFS=$'\t' read -r state isDraft number _ < "$cache" || return 0
  { [ -z "$state" ] || [ "$state" = none ]; } && return 0
  case "$state" in
    MERGED) color=35 ;;
    CLOSED) color=31 ;;
    OPEN)   if [ "$isDraft" = true ]; then color=90; else color=32; fi ;;
    *)      color=37 ;;
  esac
  printf '\033[%sm\357\220\230 %s\033[0m' "$color" "#$number"
}

# Open $1's PR in the browser, falling back to its branch page when it has no
# PR (or the URL isn't cached yet). Backgrounded so fzf never waits on it.
open_pr() {
  local name="$1" cache url path branch
  cache="$(pr_cache_file "$name")"
  if [ -f "$cache" ]; then
    IFS=$'\t' read -r _ _ _ url < "$cache" 2>/dev/null || true
  fi
  if [ -n "${url:-}" ]; then
    open "$url" >/dev/null 2>&1 || xdg-open "$url" >/dev/null 2>&1 || true
    return 0
  fi
  path=$(tmux display-message -p -t "$name" -F '#{pane_current_path}' 2>/dev/null) || return 0
  branch=$(git -C "$path" rev-parse --abbrev-ref HEAD 2>/dev/null) || return 0
  [ -n "$branch" ] || return 0
  ( cd "$path" 2>/dev/null && gh browse -b "$branch" >/dev/null 2>&1 ) &
}

# Refetch every session whose cache is missing or older than PR_TTL, in
# parallel. Lock-guarded (self-healing after 30s) so overlapping runs — the
# synchronous warm on open and the periodic background one — don't collide.
warm_prs() {
  command -v gh >/dev/null 2>&1 || return 0
  mkdir -p "$PR_CACHE_DIR"

  local lock="$PR_CACHE_DIR/.lock" now
  now=$(date +%s)
  if [ -d "$lock" ] && [ "$((now - $(mtime "$lock")))" -gt 30 ]; then
    rmdir "$lock" 2>/dev/null || true
  fi
  mkdir "$lock" 2>/dev/null || return 0

  local name path cache
  while read -r name; do
    cache="$(pr_cache_file "$name")"
    if [ -f "$cache" ] && [ "$((now - $(mtime "$cache")))" -lt "$PR_TTL" ]; then
      continue
    fi
    path=$(tmux display-message -p -t "$name" -F '#{pane_current_path}' 2>/dev/null) || continue
    git -C "$path" rev-parse --abbrev-ref HEAD >/dev/null 2>&1 || continue
    fetch_pr "$name" "$path" &
  done < <(tmux list-sessions -F '#{session_name}' 2>/dev/null)
  wait

  rmdir "$lock" 2>/dev/null || true
}

# fzf `every` handler: refresh the live preview, kick a background warm, and
# reload the list only when a warm has actually changed a chip — so the cursor
# and preview aren't disturbed on ticks where nothing changed. Prints the fzf
# actions to run on stdout.
tick() {
  ( "$SELF" --warm-prs >/dev/null 2>&1 & )
  printf 'refresh-preview'
  if [ -e "$PR_DIRTY" ]; then
    rm -f "$PR_DIRTY"
    printf '+reload(%s --list)' "$SELF"
  fi
  printf '\n'
}

# Query gh for the PR of the branch checked out in $2 (worktree path) and cache
# the result under $1 (session name). Caches the `none` sentinel when the
# branch has no PR, so it isn't retried until the entry goes stale.
fetch_pr() {
  local name="$1" path="$2" cache tmp line new old
  cache="$(pr_cache_file "$name")"
  new=none
  if line=$(cd "$path" 2>/dev/null && gh pr view \
        --json state,isDraft,number,url \
        --jq '[.state,(.isDraft|tostring),(.number|tostring),.url]|@tsv' \
        2>/dev/null) && [ -n "$line" ]; then
    new="$line"
  fi
  old=""
  if [ -f "$cache" ]; then IFS= read -r old < "$cache" || true; fi
  tmp="$cache.$$"
  printf '%s\n' "$new" > "$tmp" && mv "$tmp" "$cache" 2>/dev/null || rm -f "$tmp"
  [ "$new" = "$old" ] || : > "$PR_DIRTY"
}

# Cache-file path for a session name (slashes flattened for a safe filename).
pr_cache_file() {
  local key="$1"
  key=${key//\//_}
  printf '%s/%s' "$PR_CACHE_DIR" "$key"
}

# Modification time in epoch seconds, portable across BSD (macOS) and GNU stat.
mtime() { stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || echo 0; }

# ── Reordering (Ctrl-j / Ctrl-k) ───────────────────────────────────────────

# Swap $target one slot up/down in the saved order and persist the result.
reorder() {
  local target="$1" dir="$2"
  local names=()
  while read -r name; do names+=("$name"); done < <(effective_order)

  local pos=-1 idx
  for idx in "${!names[@]}"; do
    [ "${names[$idx]}" = "$target" ] && pos=$idx
  done

  if [ "$pos" -ge 0 ]; then
    local swap=-1
    if [ "$dir" = up ] && [ "$pos" -gt 0 ]; then
      swap=$((pos - 1))
    elif [ "$dir" = down ] && [ "$pos" -lt $((${#names[@]} - 1)) ]; then
      swap=$((pos + 1))
    fi
    if [ "$swap" -ge 0 ]; then
      local tmp="${names[$pos]}"
      names[$pos]="${names[$swap]}"
      names[$swap]="$tmp"
    fi
  fi

  mkdir -p "$(dirname "$ORDER_FILE")"
  printf '%s\n' "${names[@]}" > "$ORDER_FILE"
}

# ── Clean a work session (Ctrl-x) ───────────────────────────────────────────

# Fully tear down a finished work session: remove each linked git worktree the
# session's panes live in, force-delete its branch, then kill the tmux session.
# Behind a y/N confirm. Pure git + tmux (no workmux, no hardcoded paths) so it
# works on any repo/computer. The main checkout is never removed, and the
# session the popup is attached to is never killed.
clean_session() {
  local name="$1"

  local current
  current=$(tmux display-message -p '#{session_name}' 2>/dev/null || true)
  if [ "$name" = "$current" ]; then
    printf 'Cannot clean "%s" — it is the session you are in. Switch away first.\n' "$name"
    read -rsn1 -p 'Press any key… ' </dev/tty || true
    return 0
  fi

  local roots=() branches=() mains=() path top main branch
  while IFS= read -r path; do
    top=$(git -C "$path" rev-parse --show-toplevel 2>/dev/null) || continue
    main=$(git -C "$path" worktree list --porcelain 2>/dev/null \
      | awk '/^worktree /{print $2; exit}')
    [ -z "$main" ] && continue
    [ "$top" = "$main" ] && continue
    case " ${roots[*]-} " in *" $top "*) continue ;; esac
    branch=$(git -C "$top" rev-parse --abbrev-ref HEAD 2>/dev/null || true)
    roots+=("$top"); branches+=("$branch"); mains+=("$main")
  done < <(tmux list-panes -s -t "=$name" -F '#{pane_current_path}' | sort -u)

  printf 'Clean work session "%s"?\n' "$name"
  printf '  kill tmux session : %s\n' "$name"
  local idx
  if [ "${#roots[@]}" -eq 0 ]; then
    printf '  (no linked worktree found — only the tmux session will be killed)\n'
  else
    for idx in "${!roots[@]}"; do
      printf '  remove worktree   : %s\n' "${roots[$idx]}"
      printf '  delete branch     : %s (force)\n' "${branches[$idx]:-<detached>}"
    done
    printf '  NOTE: --force discards any uncommitted changes / unmerged commits.\n'
  fi

  local ans
  printf 'Proceed? [y/N] '
  read -rn1 ans </dev/tty || true
  printf '\n'
  case "$ans" in
    y|Y) ;;
    *) printf 'cancelled\n'; return 0 ;;
  esac

  for idx in "${!roots[@]}"; do
    top="${roots[$idx]}"; main="${mains[$idx]}"; branch="${branches[$idx]}"
    if git -C "$main" worktree remove --force "$top"; then
      git -C "$main" worktree prune
      if [ -n "$branch" ] && [ "$branch" != HEAD ]; then
        git -C "$main" branch -D "$branch" || true
      fi
    else
      printf 'error: failed to remove worktree %s — leaving "%s" intact\n' "$top" "$name"
      read -rsn1 -p 'Press any key… ' </dev/tty || true
      return 0
    fi
  done

  tmux kill-session -t "=$name"

  rm -f "$(pr_cache_file "$name")"

  if [ -f "$ORDER_FILE" ] && grep -qxF "$name" "$ORDER_FILE"; then
    grep -vxF "$name" "$ORDER_FILE" > "$ORDER_FILE.tmp" && mv "$ORDER_FILE.tmp" "$ORDER_FILE"
  fi
}

# ── Live pane preview ──────────────────────────────────────────────────────

# Render one pane of $name: the one selected by STATE_FILE's offset, with the
# active pane first. Tab cycles the offset; `follow` mode anchors to the last
# real line so the newest output stays visible.
preview_session() {
  local name="$1" offset=0
  [ -f "$STATE_FILE" ] && offset=$(cat "$STATE_FILE" 2>/dev/null || echo 0)

  local panes=()
  while read -r pane_id; do panes+=("$pane_id"); done < <(session_panes "$name")
  local count=${#panes[@]}
  [ "$count" -eq 0 ] && return 0

  local idx=$(( offset % count ))
  local pane_id="${panes[$idx]}"

  tmux display-message -p -t "$pane_id" \
    -F "  pane $((idx + 1))/$count  ▸ #{window_index}.#{pane_index} #{window_name} [#{pane_current_command}]"
  printf '\033[2m%s\033[0m\n' '──────────────────────────────────────────'
  tmux capture-pane -ep -t "$pane_id" | strip_trailing_blank_lines
}

# Pane ids for a session, active pane first, then window/pane order.
session_panes() {
  tmux list-panes -s -t "$1" \
    -F '#{?pane_active,0,1}	#{window_index}	#{pane_index}	#{pane_id}' \
  | sort -n -k1,1 -k2,2 -k3,3 | cut -f4
}

# Drop trailing blank rows (ANSI-aware) so `follow` lands on real content.
strip_trailing_blank_lines() {
  awk '
    { line[NR] = $0 }
    END {
      last = 0
      for (i = 1; i <= NR; i++) {
        stripped = line[i]
        gsub(/\033\[[0-9;?]*[a-zA-Z]/, "", stripped)
        if (stripped !~ /^[[:space:]]*$/) last = i
      }
      for (i = 1; i <= last; i++) print line[i]
    }'
}

# ── Numeric jump (digit keys) ──────────────────────────────────────────────

# Accumulate typed digits into a row number and echo the fzf action that moves
# the cursor there, so numbers past 9 are reachable (type 1 then 2 → row 12).
# Keystrokes more than 2s apart start a fresh number, as does a value that
# would overshoot the list; a lone leading 0 is ignored.
jump_digit() {
  local digit="$1" buffer="" prev_epoch=0 now
  now=$(date +%s)
  if [ -f "$DIGIT_FILE" ]; then
    read -r buffer prev_epoch < "$DIGIT_FILE" 2>/dev/null || true
    [ "$((now - ${prev_epoch:-0}))" -gt 2 ] && buffer=""
  fi

  local total value
  total=$(effective_order | wc -l | tr -d ' ' || true)
  value=$((10#${buffer}${digit}))
  [ "$value" -gt "$total" ] && value=$((10#$digit))

  if [ "$value" -lt 1 ]; then
    : > "$DIGIT_FILE"
    return 0
  fi

  printf '%s %s\n' "$value" "$now" > "$DIGIT_FILE"
  printf 'pos(%d)\n' "$value"
}

# ── Subcommand dispatch (called by the fzf key bindings) ────────────────────

case "${1:-}" in
  --list)         list_sessions; exit 0 ;;
  --preview)      preview_session "$2"; exit 0 ;;
  --next-pane)    offset=0; [ -f "$STATE_FILE" ] && offset=$(cat "$STATE_FILE" 2>/dev/null || echo 0)
                  echo $((offset + 1)) > "$STATE_FILE"; exit 0 ;;
  --reset-pane)   echo 0 > "$STATE_FILE"; exit 0 ;;
  --digit)        jump_digit "$2"; exit 0 ;;
  --reset-digits) : > "$DIGIT_FILE"; exit 0 ;;
  --move-up)      reorder "$2" up; exit 0 ;;
  --move-down)    reorder "$2" down; exit 0 ;;
  --clean)        clean_session "$2"; exit 0 ;;
  --open-pr)      open_pr "$2"; exit 0 ;;
  --warm-prs)     warm_prs; exit 0 ;;
  --tick)         tick; exit 0 ;;
  --esc)          [ "${FZF_INPUT_STATE:-}" = enabled ] \
                    && printf '%s\n' "$EXIT_SEARCH" || printf 'abort\n'
                  exit 0 ;;
esac

# ── Interactive UI ─────────────────────────────────────────────────────────

echo 0 > "$STATE_FILE"
: > "$DIGIT_FILE"
rm -f "$PR_DIRTY" 2>/dev/null || true

# Start the cursor on the session we launched from, not row 1. The popup is
# attached to that session, so display-message reports it.
CURRENT=$(tmux display-message -p '#{session_name}')
start_pos=1
if [ -n "$CURRENT" ]; then
  found=$(effective_order | grep -nxF -- "$CURRENT" | head -1 | cut -d: -f1 || true)
  [ -n "$found" ] && start_pos=$found
fi

# Each digit key feeds jump_digit, which returns the pos() action to run.
digit_binds=()
for digit in 0 1 2 3 4 5 6 7 8 9; do
  digit_binds+=(--bind="$digit:transform:$SELF --digit $digit")
done

list_sessions | fzf \
  "${digit_binds[@]}" \
  --sync \
  --bind="start:pos($start_pos)+execute-silent($SELF --warm-prs >/dev/null 2>&1 &)" \
  --ansi \
  --disabled \
  --layout=reverse \
  --delimiter='\t' --with-nth=2 --no-sort \
  --track --id-nth=1 \
  --prompt='session ▸ ' \
  --header="$HOTKEY_HEADER" \
  --bind="/:$ENTER_SEARCH" \
  --bind="backward-eof:$EXIT_SEARCH" \
  --bind="esc:transform:$SELF --esc" \
  --preview="$SELF --preview {1}" \
  --preview-window='right,60%,follow' \
  --preview-label=' Tab: next pane · live ' \
  --bind="j:execute-silent($SELF --reset-digits)+down,k:execute-silent($SELF --reset-digits)+up" \
  --bind="enter:execute-silent(tmux switch-client -t {1})+accept" \
  --bind="p:execute-silent(tmux set-option -t {1} @state pr)+reload($SELF --list)" \
  --bind="a:execute-silent(tmux set-option -t {1} @state active)+reload($SELF --list)" \
  --bind="e:execute-silent(tmux set-option -t {1} @state experimental)+reload($SELF --list)" \
  --bind="r:execute-silent(tmux set-option -t {1} @state review)+reload($SELF --list)" \
  --bind="d:execute-silent(tmux set-option -t {1} -u @state)+reload($SELF --list)" \
  --bind="o:execute-silent($SELF --open-pr {1})" \
  --bind="ctrl-j:execute-silent($SELF --move-down {1})+reload($SELF --list)" \
  --bind="ctrl-k:execute-silent($SELF --move-up {1})+reload($SELF --list)" \
  --bind="ctrl-x:execute($SELF --clean {1})+reload($SELF --list)" \
  --bind="every(2):transform:$SELF --tick" \
  --bind="focus:execute-silent($SELF --reset-pane)+refresh-preview" \
  --bind="tab:execute-silent($SELF --next-pane)+refresh-preview" \
  --bind="ctrl-d:preview-half-page-down,ctrl-u:preview-half-page-up"
