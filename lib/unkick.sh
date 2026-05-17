#!/usr/bin/env bash
# /buses:unkick <bus> <name-or-uuid> — manager-only: remove a UUID from the banlist.
# Note: cannot resolve by friendly name once the member record is gone, so
# accepts a UUID directly, or a still-present name (some kick flows preserve names).

set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/common.sh"
buses::require jq
buses::config_require

bus="${1:-}"
who="${2:-}"
[ -n "$bus" ] && [ -n "$who" ] || buses::die "usage: unkick.sh <bus> <name-or-uuid>"
buses::bus_exists "$bus" || buses::die "bus '$bus' does not exist"
buses::is_manager "$bus" || buses::die "only the manager of '$bus' can unkick"

# Try member resolution first (in case they rejoined under a new record);
# otherwise treat input as a raw UUID.
target=$(buses::resolve_member "$bus" "$who")
[ -n "$target" ] || target="$who"

if ! buses::is_banned "$bus" "$target"; then
  printf 'buses: %s was not banned from "%s"\n' "$target" "$bus"
  exit 0
fi

buses::manifest_set "$bus" \
  '.banned = ((.banned // []) - [$t])' \
  --arg t "$target"

printf 'buses: lifted ban on %s in "%s"\n' "$target" "$bus"
