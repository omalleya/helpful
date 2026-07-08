#!/usr/bin/env bash
#
# Interactive tmux session switcher, launched in an fzf popup by `prefix + s`.
# Browse and switch sessions, watch a live pane preview, set a per-session
# status emoji, and reorder the list. fzf runs the --* subcommands below via
# its key bindings; each writes state and asks fzf to reload/refresh.
#
set -euo pipefail

# Transient: index of the pane currently shown in the preview.
STATE_FILE="${TMPDIR:-/tmp}/tmux-session-switcher.paneidx"
# Transient: the digits typed so far for a numeric jump, plus a timestamp
# ("digits epoch") so a pause between keystrokes starts a fresh number.
DIGIT_FILE="${TMPDIR:-/tmp}/tmux-session-switcher.digits"
# Persisted: desired session order, one name per line.
ORDER_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/tmux/session-order"

# Absolute path to this script, so fzf key bindings can re-invoke its
# --* subcommands. Defined before the dispatch below, which references it.
SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"

# ── Search mode (vim-style `/`) ─────────────────────────────────────────────
# Hotkey mode is fzf's --disabled state: the single letters below are actions,
# so typing can't filter. `/` flips to search mode (search enabled, those keys
# unbound so they type). Emptying the query or Esc flips back.
TYPING_KEYS='/,p,a,e,r,d,j,k,0,1,2,3,4,5,6,7,8,9'
HOTKEY_HEADER='#s jump   j/k move   C-j/C-k reorder   Tab pane   [p]PR [a]active [e]exp [r]review [d]clear   C-x clean   / search   ↵ switch'
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
      -F '#{session_name}	#{?@state,#{@state},none}	#{session_windows}	#{?session_attached,*,}'
  done < <(effective_order) \
  | { index=0; while IFS=$'\t' read -r name state windows attached; do
      index=$((index + 1))
      printf '%s\t%2d  %s  %-24s %sw%s\n' \
        "$name" "$index" "$(emoji_for "$state")" "$name" "$windows" \
        "${attached:+  (attached)}"
    done; }
}

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
  --esc)          [ "${FZF_INPUT_STATE:-}" = enabled ] \
                    && printf '%s\n' "$EXIT_SEARCH" || printf 'abort\n'
                  exit 0 ;;
esac

# ── Interactive UI ─────────────────────────────────────────────────────────

echo 0 > "$STATE_FILE"
: > "$DIGIT_FILE"

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
  --bind="start:pos($start_pos)" \
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
  --bind="ctrl-j:execute-silent($SELF --move-down {1})+reload($SELF --list)" \
  --bind="ctrl-k:execute-silent($SELF --move-up {1})+reload($SELF --list)" \
  --bind="ctrl-x:execute($SELF --clean {1})+reload($SELF --list)" \
  --bind="every(2):refresh-preview" \
  --bind="focus:execute-silent($SELF --reset-pane)+refresh-preview" \
  --bind="tab:execute-silent($SELF --next-pane)+refresh-preview" \
  --bind="ctrl-d:preview-half-page-down,ctrl-u:preview-half-page-up"
