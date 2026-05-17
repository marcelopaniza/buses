#!/usr/bin/env bash
# /buses:members <bus> — list members of a bus (id, name, host, last_seen).

set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/common.sh"
buses::require jq
buses::config_require

bus="${1:-}"
[ -n "$bus" ] || buses::die "usage: members.sh <bus>"
buses::bus_exists "$bus" || buses::die "bus '$bus' does not exist"

mdir=$(buses::bus_members "$bus")
[ -d "$mdir" ] || { printf 'buses: no members in %s yet\n' "$bus"; exit 0; }

printf '%-38s %-20s %-20s %s\n' SESSION_ID NAME HOST LAST_SEEN
while IFS= read -r f; do
  [ -f "$f" ] || continue
  jq -r '"\(.id) \t\(.name // "-") \t\(.host // "-") \t\(.last_seen // "-")"' "$f" \
    | awk -F'\t' '{printf "%-38s %-20s %-20s %s\n", $1, $2, $3, $4}'
done < <(find "$mdir" -maxdepth 1 -name '*.json' -type f | LC_ALL=C sort)
