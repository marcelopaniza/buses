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

# Add to subscriptions if not already.
if ! buses::is_subscribed "$bus"; then
  buses::config_set '.buses |= (. + [$b] | unique)' --arg b "$bus"
fi

# Initialise cursor at "now" (touch existing file or create empty one with now mtime).
mkdir -p "$(buses::state_dir)"
cursor=$(buses::cursor_file "$bus")
: > "$cursor"
touch "$cursor"

buses::write_member_record "$bus"
printf 'buses: joined "%s" (history before now is hidden — use /buses:read --all to see past messages)\n' "$bus"
