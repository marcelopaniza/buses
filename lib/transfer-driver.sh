#!/usr/bin/env bash
# /buses:transfer-driver <bus> <name-or-uuid> [--force]
#
# Driver-only by default. With --force, any subscribed member can claim
# driver — intended as an escape hatch when the current driver's machine
# is gone and the bus is "stuck."
#
# Target must be a real member of the bus (we don't transfer to a stale
# or imaginary UUID), unless --force is also set on the target check.

set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/common.sh"
buses::require jq
buses::config_require

bus="${1:-}"
who="${2:-}"
force=""
for a in "${@:3}"; do [ "$a" = "--force" ] && force=1; done

[ -n "$bus" ] && [ -n "$who" ] || buses::die "usage: transfer-driver.sh <bus> <name-or-uuid> [--force]"
buses::bus_exists "$bus" || buses::die "bus '$bus' does not exist"

current_drv=$(buses::driver_uuid "$bus")
my_sid=$(buses::config_get '.session_id')

# Authorisation
if [ -z "$force" ]; then
  buses::is_driver "$bus" || buses::die "only the current driver can transfer (use --force if the driver is gone)"
else
  # --force: I must at least be a subscribed member of the bus.
  if ! buses::is_subscribed "$bus"; then
    buses::die "you must be subscribed to '$bus' to take it over (--force)"
  fi
fi

# Resolve target
target=$(buses::resolve_member "$bus" "$who")
if [ -z "$target" ]; then
  if [ -n "$force" ]; then
    # Allow raw UUID even if not a current member (in case the target hasn't
    # rejoined yet) — but make sure it looks like a UUID.
    case "$who" in
      [0-9a-fA-F]*-[0-9a-fA-F]*-[0-9a-fA-F]*-[0-9a-fA-F]*-*) target="$who" ;;
      *) buses::die "target '$who' is not a current member; pass a full UUID with --force if intended" ;;
    esac
  else
    buses::die "target '$who' is not a current member of '$bus' (use --force + UUID to override)"
  fi
fi

if [ "$target" = "$current_drv" ]; then
  printf 'buses: %s is already the driver of "%s"\n' "$target" "$bus"
  exit 0
fi

buses::set_driver "$bus" "$target"
printf 'buses: driver of "%s" transferred:\n' "$bus"
printf '         from: %s\n' "${current_drv:-(none)}"
printf '         to:   %s\n' "$target"
