#!/usr/bin/env bash
# /buses:kick <bus> <name-or-uuid> [reason...] — manager-only.
# Adds the target's UUID to manifest.banned and removes their member record.
# Cooperative enforcement: other sessions' send/join refuses for banned UUIDs.

set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/common.sh"
buses::require jq
buses::config_require

bus="${1:-}"; shift || true
who="${1:-}"; shift || true
reason="$*"

[ -n "$bus" ] && [ -n "$who" ] || buses::die "usage: kick.sh <bus> <name-or-uuid> [reason...]"
buses::bus_exists "$bus" || buses::die "bus '$bus' does not exist"
buses::is_manager "$bus" || buses::die "only the manager of '$bus' can kick"

target=$(buses::resolve_member "$bus" "$who")
[ -n "$target" ] || buses::die "no member named '$who' (or matching UUID) in bus '$bus'"

mgr=$(buses::manifest_get "$bus" '.manager')
[ "$target" != "$mgr" ] || buses::die "refusing to kick the manager — transfer management first"

if buses::is_banned "$bus" "$target"; then
  printf 'buses: %s is already banned from "%s"\n' "$target" "$bus"
  exit 0
fi

buses::manifest_set "$bus" \
  '.banned = ((.banned // []) + [$t] | unique)' \
  --arg t "$target"

members_dir=$(buses::bus_members "$bus")
[ -f "$members_dir/$target.json" ] && rm -f "$members_dir/$target.json"

# Drop a notice file so the kicked session sees it on their next prompt.
ts_iso=$(buses::now_iso)
ts_compact=$(buses::now_compact)
mid=$(buses::uuid)
short="${mid:0:8}"
fname="${ts_compact}__${short}.msg"
msgs_dir=$(buses::bus_messages "$bus")
mkdir -p "$msgs_dir"
sid=$(buses::config_get '.session_id')
name=$(buses::config_get '.session_name'); [ -n "$name" ] || name="$sid"
tmp="$msgs_dir/.$fname.tmp.$$"
{
  printf -- '---\n'
  printf 'id: %s\n'        "$mid"
  printf 'bus: %s\n'       "$bus"
  printf 'from: %s\n'      "$sid"
  printf 'from_name: %s\n' "$name"
  printf 'to: %s\n'        "$target"
  printf 'to_id: %s\n'     "$target"
  printf 'kind: kick-notice\n'
  printf 'ts: %s\n'        "$ts_iso"
  printf -- '---\n'
  printf 'You have been kicked from bus "%s" by manager %s.%s\n' \
    "$bus" "$name" "${reason:+ Reason: $reason}"
} > "$tmp"
mv "$tmp" "$msgs_dir/$fname"

printf 'buses: kicked %s from "%s"%s\n' "$target" "$bus" "${reason:+ (reason: $reason)}"
