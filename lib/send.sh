#!/usr/bin/env bash
# Write a single message file into a bus, atomically.
# Usage: send.sh <bus> <to> <body...>
#
# <to> can be:
#   all                       broadcast to every subscriber
#   <name|uuid>               single direct recipient
#   <name1>,<name2>,<uuid3>   comma-separated list of direct recipients
#
# The body may also contain @<name> mentions. A receiver matches if its
# name or short UUID appears in `to` OR is @-tagged in the body.

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
to="${1:-}";  shift || true
body="$*"

[ -n "$bus" ]  || buses::die "usage: send.sh <bus> <to> <body...>"
[ -n "$to" ]   || buses::die "missing <to> (use 'all' to broadcast)"
[ -n "$body" ] || buses::die "empty message body"

buses::valid_name "$bus" || buses::die "invalid bus name: $bus"
buses::bus_exists "$bus" || buses::die "bus '$bus' does not exist on the shared folder"

# Banlist gate: refuse if our session has been kicked from this bus.
if buses::is_banned "$bus"; then
  buses::die "you have been kicked from bus '$bus' — ask the driver to /buses:unkick you"
fi

# Lock gate: refuse if locked, unless we are the driver.
if buses::is_locked "$bus" && ! buses::is_driver "$bus"; then
  reason=$(buses::lock_reason "$bus")
  buses::die "bus '$bus' is locked${reason:+ ($reason)} — only the driver can send"
fi

# Normalise the `to` field: split on commas, trim whitespace, drop empties.
# Whatever the user typed (a single name, "all", or "loop,felix") is preserved
# verbatim in the frontmatter — check.sh does the splitting at receive time.
to_normalised=$(printf '%s' "$to" \
  | tr ',' '\n' \
  | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' \
  | grep -v '^$' \
  | paste -sd ',' -)
[ -n "$to_normalised" ] || buses::die "no valid recipients after normalising '$to'"

# Single-recipient back-compat: only when there's exactly one non-'all' name.
# Look up its UUID so receivers with name collisions can still disambiguate.
to_id=""
if [[ "$to_normalised" != *,* ]] && [ "$to_normalised" != "all" ]; then
  members_dir=$(buses::bus_members "$bus")
  if [ -d "$members_dir" ]; then
    while IFS= read -r f; do
      [ -f "$f" ] || continue
      mname=$(jq -r '.name // ""' "$f" 2>/dev/null)
      mid_candidate=$(jq -r '.id // ""' "$f" 2>/dev/null)
      if [ "$mname" = "$to_normalised" ] || [ "$mid_candidate" = "$to_normalised" ]; then
        to_id="$mid_candidate"
        break
      fi
    done < <(find "$members_dir" -maxdepth 1 -name '*.json' -type f 2>/dev/null)
  fi
fi

# Delegate file build + sign + atomic write to the shared helper.
result=$(buses::write_message "$bus" "$to_normalised" "$body" "$to_id") \
  || buses::die "send failed (check openssl install)"
fname="${result% *}"
mid="${result##* }"

# Refresh our presence (best effort).
buses::write_member_record "$bus" >/dev/null 2>&1 || true

# Echo back any @-mentions in the body as a usability cue.
mentions=$(printf '%s' "$body" | { grep -oE '@[A-Za-z0-9._-]+' || true; } \
                                | sort -u | paste -sd ' ' -)
printf 'sent: %s/%s  to=%s%s  (id=%s)\n' \
  "$bus" "$fname" "$to_normalised" "${mentions:+  mentions=$mentions}" "$mid"
