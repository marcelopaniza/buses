#!/usr/bin/env bash
# /buses:watch — dispatcher for the background notification daemon.
# Subcommands:
#   start [interval]   start the watcher (default: 5s, or last saved interval)
#   stop               stop a running watcher
#   restart [interval] stop then start
#   status             show running state, PID, uptime, notifier, last log lines
#   logs [n]           tail the watcher log (default 30 lines)

set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/common.sh"
buses::require jq
buses::config_require

# The matching .md command quotes "$ARGUMENTS" as a single arg for safety
# against shell metacharacters in user input. Re-split it into positionals
# here (whitespace-only; no shell interpretation). When tests call the
# script directly with already-split args, $# > 1 and we leave them alone.
[ "$#" -le 1 ] && set -- ${1-}

sub="${1:-start}"; shift || true

state_dir=$(buses::state_dir)
mkdir -p "$state_dir"
pid_file="$state_dir/watcher.pid"
log_file="$state_dir/watcher.log"
interval_file="$state_dir/watcher.interval"

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

is_alive() {
  [ -f "$pid_file" ] || return 1
  local p; p=$(cat "$pid_file" 2>/dev/null || echo "")
  [ -n "$p" ] && kill -0 "$p" 2>/dev/null
}

cmd_start() {
  local interval="${1:-}"
  if [ -z "$interval" ] && [ -f "$interval_file" ]; then
    interval=$(cat "$interval_file" 2>/dev/null || echo 5)
  fi
  [ -n "$interval" ] || interval=5
  case "$interval" in ''|*[!0-9]*) buses::die "interval must be a positive integer (seconds)" ;; esac
  [ "$interval" -ge 1 ] || buses::die "interval must be >= 1 second"

  # Mkdir-based lock around the start sequence. mkdir is atomic on every
  # POSIX filesystem we care about, so this serialises concurrent
  # /buses:watch start calls in the same $BUSES_CONFIG_DIR. Without it,
  # two terminals starting the watcher within the 0.4s sanity sleep can
  # both launch a daemon and stomp on the PID file (one daemon stays
  # orphaned and unreachable by /buses:watch stop).
  local lock_dir="$state_dir/watcher.lock"
  local i=0
  while ! mkdir "$lock_dir" 2>/dev/null; do
    i=$((i + 1))
    [ "$i" -gt 50 ] && buses::die "couldn't acquire watcher start lock at $lock_dir (stuck? rmdir it manually)"
    sleep 0.1
  done
  # shellcheck disable=SC2064
  trap "rmdir '$lock_dir' 2>/dev/null || true" EXIT

  if is_alive; then
    local running_interval='?'
    [ -f "$interval_file" ] && running_interval=$(cat "$interval_file" 2>/dev/null)
    printf 'buses: watcher already running (pid=%s, interval=%ss)\n' \
      "$(cat "$pid_file")" "$running_interval"
    return 0
  fi

  echo "$interval" > "$interval_file"

  # Launch detached. nohup keeps it alive after the shell exits; stdin from
  # /dev/null so it never blocks on terminal input.
  export BUSES_CONFIG_DIR
  nohup bash "$PLUGIN_ROOT/lib/watcher_daemon.sh" "$interval" \
    >> "$log_file" 2>&1 < /dev/null &
  local pid=$!
  disown 2>/dev/null || true

  sleep 0.4
  if ! kill -0 "$pid" 2>/dev/null; then
    buses::err "watcher exited immediately. Last log lines:"
    tail -n 20 "$log_file" >&2 || true
    rm -f "$pid_file"
    exit 1
  fi

  printf 'buses: watcher started (pid=%s, interval=%ss, log=%s)\n' "$pid" "$interval" "$log_file"
}

cmd_stop() {
  if ! is_alive; then
    rm -f "$pid_file"
    printf 'buses: watcher was not running\n'
    return 0
  fi
  local p; p=$(cat "$pid_file")
  kill -TERM "$p" 2>/dev/null || true
  # Give it a moment to clean up.
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    kill -0 "$p" 2>/dev/null || break
    sleep 0.2
  done
  if kill -0 "$p" 2>/dev/null; then
    kill -KILL "$p" 2>/dev/null || true
    sleep 0.2
  fi
  rm -f "$pid_file"
  printf 'buses: watcher stopped (was pid=%s)\n' "$p"
}

cmd_restart() {
  cmd_stop
  cmd_start "$@"
}

cmd_status() {
  if is_alive; then
    local p; p=$(cat "$pid_file")
    local interval='?'
    [ -f "$interval_file" ] && interval=$(cat "$interval_file")
    printf 'buses: watcher RUNNING\n'
    printf '  pid:      %s\n' "$p"
    printf '  interval: %ss\n' "$interval"
    printf '  pid_file: %s\n' "$pid_file"
    printf '  log_file: %s\n' "$log_file"
    if [ -f "$log_file" ]; then
      printf '\n  recent log:\n'
      tail -n 5 "$log_file" | sed 's/^/    /'
    fi
  else
    printf 'buses: watcher NOT RUNNING\n'
    [ -f "$log_file" ] && {
      printf '  last log (tail 5):\n'
      tail -n 5 "$log_file" | sed 's/^/    /'
    }
  fi
}

cmd_logs() {
  local n="${1:-30}"
  case "$n" in ''|*[!0-9]*) n=30 ;; esac
  if [ -f "$log_file" ]; then
    tail -n "$n" "$log_file"
  else
    printf 'buses: no watcher log at %s\n' "$log_file"
  fi
}

case "$sub" in
  start)   cmd_start   "$@" ;;
  stop)    cmd_stop ;;
  restart) cmd_restart "$@" ;;
  status)  cmd_status ;;
  logs)    cmd_logs    "$@" ;;
  *) buses::die "unknown subcommand: $sub (use: start|stop|restart|status|logs)" ;;
esac
