#!/usr/bin/env bash
# /buses:init <shared-path> — set the shared folder for this machine/session and
# generate a session UUID. Safe to re-run: refuses to clobber an existing config
# unless --force is passed.

set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/common.sh"
buses::require jq

# Re-split: see comment in other lib scripts.
[ "$#" -le 1 ] && set -- ${1-}

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

# Generate cryptographic identity (Ed25519). The private key never leaves
# this machine; the public key is published in member records so peers can
# verify our signed messages.
buses::ensure_identity_key
fp=$(buses::fingerprint)

cc_sid=$(buses::terminal_id)
cat <<EOF
buses: initialised
  terminal:    ${cc_sid:-<not set — running outside Claude Code?>}
  project:     $(buses::project_dir)
  config:      $BUSES_CONFIG_FILE
  shared_path: $shared
  session_id:  $sid
  fingerprint: ${fp:-(none)}   (sha256/16 of public key)

  (identity is scoped to THIS terminal — other Claude Code terminals on this
   machine get their own UUIDs, even in the same project. Override with
   BUSES_CONFIG_DIR if you want to share identity across terminals.)

next steps:
  /buses:name <friendly-name>     give this session a memorable name
  /buses:create <bus>             make a new bus, or
  /buses:join <existing-bus>      subscribe to one
EOF
