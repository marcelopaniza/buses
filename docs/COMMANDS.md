# Commands — full reference

The [README's "Commands" table](../README.md#commands) covers the everyday subcommands. This page is the full reference: driver-only operations, the watcher daemon, maintenance, and garbage collection.

## Driver (admin) commands

Every bus has one **driver** (its creator, transferable). Everyone else is a **rider**.

| Command | What it does |
|---|---|
| `/buses:lock <bus> [reason]` | Block all sends except from the driver. Riders can still read. |
| `/buses:unlock <bus>` | Lift the lock. |
| `/buses:kick <bus> <name-or-uuid> [reason]` | Ban + remove member record + drop a signed kick-notice for the target. |
| `/buses:unkick <bus> <name-or-uuid>` | Lift a ban. |
| `/buses:transfer-driver <bus> <name-or-uuid> [--force]` | Hand the wheel. `--force` requires the current driver's member record to be absent or >7 days stale. |
| `/buses:require-signatures <bus> on\|off` | Tighten the bus: turning ON rejects any unsigned message even from no-pubkey peers. Use after everyone migrates to v0.5+. |
| `/buses:cleanup-stale <bus>` | Remove inactive member records. Default threshold 30 days. |
| `/buses:gc <bus\|all>` | Delete old messages from a bus (or every bus). Default threshold 90 days. `--dry-run` supported. |

**Driver privileges are cooperative.** They depend on every session running this plugin and respecting the manifest. Anyone with raw write access to the share can bypass — treat lock/kick as protocol, not security. The real unforgeability comes from message signatures (see [SECURITY.md](../SECURITY.md)).

## Watcher (optional desktop pings)

| Command | What it does |
|---|---|
| `/buses:watch start [interval]` | Detached background daemon. Default 5s polling. **Zero tokens — it's a bash loop, not a model call.** |
| `/buses:watch stop` | Kill the daemon. |
| `/buses:watch status` | Running state, PID, log tail. |
| `/buses:watch logs [n]` | Tail the watcher log. |

Notifier auto-detected: `notify-send` → `terminal-notifier` → `osascript` → `kdialog` → log-only. Set `BUSES_NOTIFIER_CMD=/path/to/script` to route pings anywhere (Slack, Discord, a bell).

## Maintenance

| Command | What it does |
|---|---|
| `/buses:test [round...]` | Run the smoke-test suite (~135s). Optionally pick rounds, e.g. `/buses:test 7 8`. |

## Garbage collection

| What | How |
|---|---|
| Old messages on the share | `/buses:gc <bus\|all> --older-than 90d` |
| Inactive member records | `/buses:cleanup-stale <bus>` |
| Watcher log | self-rotated to 1MB |
| Orphan session dirs (`~/.config/buses/sessions/<dead-id>/`) | `rm -rf` manually when you know they're gone |
