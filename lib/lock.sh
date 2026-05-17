#!/usr/bin/env bash
# /buses:lock <bus> [reason...] — driver-only: lock a bus so only the manager
# can send. Members can still read.

set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/common.sh"
buses::require jq
buses::config_require

# The matching .md command quotes "$ARGUMENTS" as a single arg for safety
# against shell metacharacters in user input. Re-split it into positionals
# here (whitespace-only; no shell interpretation). When tests call the
# script directly with already-split args, $# > 1 and we leave them alone.
[ "$#" -le 1 ] && set -- ${1-}

bus="${1:-}"; shift || true
reason="$*"

[ -n "$bus" ] || buses::die "usage: lock.sh <bus> [reason...]"
buses::bus_exists "$bus" || buses::die "bus '$bus' does not exist"
buses::is_driver "$bus"  || buses::die "only the driver of '$bus' can lock it"

sid=$(buses::config_get '.session_id')
buses::manifest_set "$bus" \
  '.locked = {by: $by, reason: $r, at: $at}' \
  --arg by "$sid" \
  --arg r  "$reason" \
  --arg at "$(buses::now_iso)"

printf 'buses: bus "%s" locked%s\n' "$bus" "${reason:+ (reason: $reason)}"
