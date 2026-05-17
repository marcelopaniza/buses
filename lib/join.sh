#!/usr/bin/env bash
# /buses:join <bus> — subscribe this session to a bus.
# - Creates the bus if it doesn't exist (with confirmation prompt skipped: silent autocreate).
# - Drops member record on the shared folder.
# - Starts the cursor at "now" so we don't get flooded with history.

set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/common.sh"
buses::require jq
buses::config_require

bus="${1:-}"
[ -n "$bus" ] || buses::die "usage: join.sh <bus>"
buses::valid_name "$bus" || buses::die "invalid bus name: $bus"

if ! buses::bus_exists "$bus"; then
  "$(dirname "$0")/create.sh" "$bus" >/dev/null
fi

# Banlist gate: refuse to join if our session has been kicked.
if buses::is_banned "$bus"; then
  buses::die "you have been kicked from bus '$bus' — ask the manager to /buses:unkick you"
fi

# Warn (but do not block) if the bus is locked. You can still receive.
if buses::is_locked "$bus"; then
  reason=$(buses::lock_reason "$bus")
  buses::err "note: bus '$bus' is locked${reason:+ ($reason)} — you can read but cannot send"
fi

# Add to subscriptions if not already.
if ! buses::is_subscribed "$bus"; then
  buses::config_set '.buses |= (. + [$b] | unique)' --arg b "$bus"
fi

# Initialise BOTH cursors at "now" so neither hook nor watcher floods us
# with historical messages we never subscribed for.
mkdir -p "$(buses::state_dir)"
for cursor in "$(buses::cursor_file "$bus")" "$(buses::notify_cursor_file "$bus")"; do
  : > "$cursor"
  touch "$cursor"
done

buses::write_member_record "$bus"
printf 'buses: joined "%s" (history before now is hidden — use /buses:read --all to see past messages)\n' "$bus"
