#!/usr/bin/env bash
# Background poller for the buses plugin. Started by `lib/watch.sh start`.
# Polls every $1 seconds (default 5), fires desktop notifications for new
# messages addressed to this session. Uses the NOTIFY cursor only — does NOT
# touch the hook cursor, so the model still sees these messages when the user
# next types into Claude.
#
# Env:
#   BUSES_CONFIG_DIR     — inherited from the launching shell.
#   BUSES_NOTIFIER_CMD   — optional override: invoked as "$cmd <title> <body>".
#                          Useful for testing or piping notifications elsewhere.
#
# This script is never invoked directly by the user.

set -u
PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=common.sh
source "$PLUGIN_ROOT/lib/common.sh"

interval="${1:-5}"
case "$interval" in ''|*[!0-9]*) interval=5 ;; esac
[ "$interval" -ge 1 ] || interval=5

[ -f "$BUSES_CONFIG_FILE" ] || { echo "watcher: no config — exiting" >&2; exit 1; }
sid=$(buses::config_get '.session_id')
[ -n "$sid" ]               || { echo "watcher: empty session_id — exiting" >&2; exit 1; }

state_dir=$(buses::state_dir)
mkdir -p "$state_dir"
pid_file="$state_dir/watcher.pid"
echo $$ > "$pid_file"

cleanup() {
  rm -f "$pid_file"
  echo "[$(buses::now_iso)] watcher stop pid=$$"
  exit 0
}
trap cleanup TERM INT HUP

# Detect notifier once, print to log so /buses:watch status can show it.
detect_notifier() {
  if [ -n "${BUSES_NOTIFIER_CMD:-}" ];      then echo "override:${BUSES_NOTIFIER_CMD}"
  elif command -v notify-send       >/dev/null 2>&1; then echo notify-send
  elif command -v terminal-notifier >/dev/null 2>&1; then echo terminal-notifier
  elif command -v osascript         >/dev/null 2>&1; then echo osascript
  elif command -v kdialog           >/dev/null 2>&1; then echo kdialog
  else echo "(none — falling back to log only)"
  fi
}
notifier=$(detect_notifier)

notify() {
  local bus="$1" from="$2" preview="$3"
  local title="buses: ${from} on ${bus}"
  if [ -n "${BUSES_NOTIFIER_CMD:-}" ]; then
    "$BUSES_NOTIFIER_CMD" "$title" "$preview" 2>/dev/null || true
  elif command -v notify-send >/dev/null 2>&1; then
    notify-send -a buses -u low "$title" "$preview" 2>/dev/null || true
  elif command -v terminal-notifier >/dev/null 2>&1; then
    terminal-notifier -title buses -subtitle "${from} on ${bus}" -message "$preview" >/dev/null 2>&1 || true
  elif command -v osascript >/dev/null 2>&1; then
    local body_esc title_esc sub_esc
    body_esc=$(printf '%s' "$preview" | sed 's/\\/\\\\/g; s/"/\\"/g')
    title_esc="buses"
    sub_esc=$(printf '%s' "${from} on ${bus}" | sed 's/\\/\\\\/g; s/"/\\"/g')
    osascript -e "display notification \"$body_esc\" with title \"$title_esc\" subtitle \"$sub_esc\"" 2>/dev/null || true
  elif command -v kdialog >/dev/null 2>&1; then
    kdialog --title "$title" --passivepopup "$preview" 8 2>/dev/null || true
  else
    : # logged below
  fi
  echo "[$(buses::now_iso)] notify bus=$bus from=$from"
}

echo "[$(buses::now_iso)] watcher start sid=$sid interval=${interval}s notifier=$notifier pid=$$"

while true; do
  # If config disappears, exit gracefully (user uninstalled, reset, etc).
  if [ ! -f "$BUSES_CONFIG_FILE" ]; then
    echo "[$(buses::now_iso)] watcher: config gone — exiting"
    cleanup
  fi

  # If share is temporarily unmounted, back off without crashing.
  if [ -d "$(buses::shared_root)" ]; then
    out=$("$PLUGIN_ROOT/lib/check.sh" --notify 2>/dev/null || true)
    if [ -n "$out" ]; then
      while IFS=$'\t' read -r bus from preview; do
        [ -n "$bus" ] || continue
        notify "$bus" "$from" "$preview"
      done <<< "$out"
    fi
  fi

  sleep "$interval" &
  wait $!
done
