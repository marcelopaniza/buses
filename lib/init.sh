#!/usr/bin/env bash
# /buses:init <shared-path> — set the shared folder for this machine/session and
# generate a session UUID. Safe to re-run: refuses to clobber an existing config
# unless --force is passed.

set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/common.sh"
buses::require jq

shared="${1:-}"
force="${2:-}"

[ -n "$shared" ] || buses::die "usage: init.sh <shared-path> [--force]"

# Expand ~ if present.
case "$shared" in
  '~'|'~/'*) shared="${HOME}${shared#\~}" ;;
esac

# Make absolute.
case "$shared" in
  /*) ;;
  *)  shared="$(cd "$shared" 2>/dev/null && pwd)" || buses::die "shared path not found (and could not resolve to absolute): $1" ;;
esac

if buses::config_exists && [ "$force" != "--force" ]; then
  existing=$(buses::config_get '.shared_path')
  sid=$(buses::config_get '.session_id')
  buses::die "config already exists at $BUSES_CONFIG_FILE
  shared_path: $existing
  session_id:  $sid
re-run with --force to reset."
fi

mkdir -p "$shared/buses" || buses::die "cannot create $shared/buses (check the path is mounted and writable)"

sid=$(buses::config_init_file "$shared")

cat <<EOF
buses: initialised
  config:      $BUSES_CONFIG_FILE
  shared_path: $shared
  session_id:  $sid

next steps:
  /buses:name <friendly-name>     give this session a memorable name
  /buses:create <bus>             make a new bus, or
  /buses:join <existing-bus>      subscribe to one
EOF
