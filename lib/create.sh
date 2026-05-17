#!/usr/bin/env bash
# /buses:create <bus> — create a new bus on the shared folder.
# Idempotent: succeeds quietly if it already exists.

set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/common.sh"
buses::require jq
buses::config_require

# The matching .md command quotes "$ARGUMENTS" as a single arg for safety
# against shell metacharacters in user input. Re-split it into positionals
# here (whitespace-only; no shell interpretation). When tests call the
# script directly with already-split args, $# > 1 and we leave them alone.
[ "$#" -le 1 ] && set -- ${1-}

bus="${1:-}"
[ -n "$bus" ] || buses::die "usage: create.sh <bus>"
buses::valid_name "$bus" || buses::die "invalid bus name: $bus"

dir=$(buses::bus_dir "$bus")
created=no
if [ ! -d "$dir" ]; then
  mkdir -p "$dir/messages" "$dir/members" || buses::die "cannot create $dir (shared path writable?)"
  jq -n \
    --arg n "$bus" \
    --arg c "$(buses::now_iso)" \
    --arg by "$(buses::config_get '.session_id')" \
    '{name: $n, created: $c, created_by: $by, driver: $by}' > "$dir/manifest.json"
  created=yes
fi

printf 'buses: bus "%s" %s at %s\n' "$bus" \
  "$([ "$created" = yes ] && echo created || echo "already existed")" "$dir"
