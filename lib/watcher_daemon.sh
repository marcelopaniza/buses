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

# Path to our own log file, used for in-process rotation in the loop below.
# Defined here so the loop can reference it without recomputing each pass.
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
  # Strip every control character from preview before handing it to any
  # notifier, particularly to osascript -e which interprets a newline as a
  # statement terminator (would let a crafted message body break out of the
  # quoted notification string and execute AppleScript). Also strip CRs and
  # other low ASCII for safety across all notifiers.
  preview=$(printf '%s' "$preview" | tr -d '\000-\037')
  local title="buses: ${from} on ${bus}"
  if [ -n "${BUSES_NOTIFIER_CMD:-}" ]; then
    # Intentionally invoked as a single command (no word-splitting): set
    # BUSES_NOTIFIER_CMD to the absolute path of one executable, not a
    # shell snippet. Documented in README.
    "$BUSES_NOTIFIER_CMD" "$title" "$preview" 2>/dev/null || true
  elif command -v notify-send >/dev/null 2>&1; then
    notify-send -a buses -u low "$title" "$preview" 2>/dev/null || true
  elif command -v terminal-notifier >/dev/null 2>&1; then
    terminal-notifier -title buses -subtitle "${from} on ${bus}" -message "$preview" >/dev/null 2>&1 || true
  elif command -v osascript >/dev/null 2>&1; then
    local body_esc sub_esc
    body_esc=$(printf '%s' "$preview"               | sed 's/\\/\\\\/g; s/"/\\"/g')
    sub_esc=$(printf '%s' "${from} on ${bus}"       | sed 's/\\/\\\\/g; s/"/\\"/g')
    osascript -e "display notification \"$body_esc\" with title \"buses\" subtitle \"$sub_esc\"" 2>/dev/null || true
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

  # Cap watcher.log at ~1MB by truncating-and-restarting whenever it grows
  # past the threshold. Cheap (one stat per poll); never bounds total run
  # time. Done from inside the loop so it tracks the log we're already
  # writing to, no matter where it lives.
  log_self="${state_dir}/watcher.log"
  if [ -f "$log_self" ] && [ "$(wc -c < "$log_self" 2>/dev/null || echo 0)" -gt 1048576 ]; then
    : > "$log_self"
    echo "[$(buses::now_iso)] watcher.log rotated (exceeded 1MB)"
  fi

  # Background sleep so SIGTERM can interrupt the wait — bare `sleep` would
  # block trap delivery until the interval expired.
  sleep "$interval" &
  wait $!
done
