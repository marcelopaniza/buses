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

msgs_dir=$(buses::bus_messages "$bus")
mkdir -p "$msgs_dir"

mid=$(buses::uuid)
short="${mid:0:8}"
ts_iso=$(buses::now_iso)
ts_compact=$(buses::now_compact)
sid=$(buses::config_get '.session_id')
name=$(buses::config_get '.session_name')
[ -n "$name" ] || name="$sid"

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

# Sign the message before composing the file. The signature covers the five
# fields that should be unforgeable: id, bus, from, to, ts — plus the body.
# from_name and to_id are conveniences and are NOT in the signed envelope
# (they can change without affecting authenticity).
buses::ensure_identity_key
canonical=$(buses::canonicalize "$mid" "$bus" "$sid" "$to_normalised" "$ts_iso" "$body")
sig=$(buses::sign "$canonical") || buses::die "signing failed (check openssl install)"

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
  printf 'to: %s\n'        "$to_normalised"
  [ -n "$to_id" ] && printf 'to_id: %s\n' "$to_id"
  printf 'ts: %s\n'        "$ts_iso"
  printf 'sig: %s\n'       "$sig"
  printf -- '---\n'
  printf '%s\n' "$body"
} > "$tmp"

mv "$tmp" "$final"
buses::write_member_record "$bus" >/dev/null 2>&1 || true

# Collect any @-mentions in the body so we can echo them as a hint.
# `|| true` because grep exits 1 when there are no matches, and `set -e` would
# otherwise kill the script for the (very common) zero-mentions case.
mentions=$(printf '%s' "$body" | { grep -oE '@[A-Za-z0-9._-]+' || true; } \
                                | sort -u | paste -sd ' ' -)
printf 'sent: %s/%s  to=%s%s  (id=%s)\n' \
  "$bus" "$fname" "$to_normalised" "${mentions:+  mentions=$mentions}" "$mid"
