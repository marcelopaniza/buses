#!/usr/bin/env bash
# Write a single message file into a bus, atomically.
# Usage: send.sh <bus> <to> <body...>
# Special <to> values: "all" (broadcast). Otherwise: a member name or session UUID.

set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/common.sh"
buses::require jq
buses::config_require

bus="${1:-}"; shift || true
to="${1:-}";  shift || true
body="$*"

[ -n "$bus" ]  || buses::die "usage: send.sh <bus> <to> <body...>"
[ -n "$to" ]   || buses::die "missing <to> (use 'all' to broadcast)"
[ -n "$body" ] || buses::die "empty message body"

buses::valid_name "$bus" || buses::die "invalid bus name: $bus"
buses::bus_exists "$bus" || buses::die "bus '$bus' does not exist on the shared folder"

msgs_dir=$(buses::bus_messages "$bus")
mkdir -p "$msgs_dir"

mid=$(buses::uuid)
short="${mid:0:8}"
ts_iso=$(buses::now_iso)
ts_compact=$(buses::now_compact)
sid=$(buses::config_get '.session_id')
name=$(buses::config_get '.session_name')
[ -n "$name" ] || name="$sid"

# Resolve recipient — if <to> is a known member name, look up their UUID too.
to_id=""
if [ "$to" != "all" ]; then
  members_dir=$(buses::bus_members "$bus")
  if [ -d "$members_dir" ]; then
    while IFS= read -r f; do
      [ -f "$f" ] || continue
      mname=$(jq -r '.name // ""' "$f" 2>/dev/null)
      mid_candidate=$(jq -r '.id // ""' "$f" 2>/dev/null)
      if [ "$mname" = "$to" ] || [ "$mid_candidate" = "$to" ]; then
        to_id="$mid_candidate"
        break
      fi
    done < <(find "$members_dir" -maxdepth 1 -name '*.json' -type f 2>/dev/null)
  fi
fi

# Compose the file: YAML frontmatter + blank line + body.
fname="${ts_compact}__${short}.msg"
final="$msgs_dir/$fname"
tmp="$msgs_dir/.$fname.tmp.$$"

{
  printf -- '---\n'
  printf 'id: %s\n'        "$mid"
  printf 'bus: %s\n'       "$bus"
  printf 'from: %s\n'      "$sid"
  printf 'from_name: %s\n' "$name"
  printf 'to: %s\n'        "$to"
  [ -n "$to_id" ] && printf 'to_id: %s\n' "$to_id"
  printf 'ts: %s\n'        "$ts_iso"
  printf -- '---\n'
  printf '%s\n' "$body"
} > "$tmp"

mv "$tmp" "$final"
buses::write_member_record "$bus" >/dev/null 2>&1 || true

printf 'sent: %s/%s  (id=%s)\n' "$bus" "$fname" "$mid"
