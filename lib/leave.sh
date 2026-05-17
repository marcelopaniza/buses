#!/usr/bin/env bash
# /buses:leave <bus> — unsubscribe from a bus. Removes member record + cursor.

set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/common.sh"
buses::require jq
buses::config_require

bus="${1:-}"
[ -n "$bus" ] || buses::die "usage: leave.sh <bus>"

if ! buses::is_subscribed "$bus"; then
  printf 'buses: not subscribed to "%s" — nothing to do\n' "$bus"
  exit 0
fi

buses::config_set '.buses |= map(select(. != $b))' --arg b "$bus"

sid=$(buses::config_get '.session_id')
members_dir=$(buses::bus_members "$bus")
[ -f "$members_dir/$sid.json" ] && rm -f "$members_dir/$sid.json"

for cursor in "$(buses::cursor_file "$bus")" "$(buses::notify_cursor_file "$bus")"; do
  [ -f "$cursor" ] && rm -f "$cursor"
done

printf 'buses: left "%s"\n' "$bus"
