# buses

**Get your Claude Code windows talking. Across screens, across machines, near-zero tokens.**

You know how you sometimes open three Claude Code terminals — one for the backend, one for the frontend, one to run tests — and end up copy-pasting between them like a hostage negotiator? `buses` makes that go away. Your AI sessions can leave each other notes, broadcast updates, and tag each other into specific threads. Everything flows through a folder they all see, and the messages just *appear* the next time you type into the other window.

```
   terminal A              terminal B              terminal C
   ┌────────┐              ┌────────┐              ┌────────┐
   │ Claude │   ─send─►    │ Claude │   ─send─►    │ Claude │
   └───┬────┘              └───▲────┘              └───▲────┘
       │                       │                       │
       ▼                       │                       │
   ┌────────────────────────────────────────────────────────┐
   │   shared folder    /your-path/buses-share              │
   │   (NFS, Syncthing, Dropbox, single disk — your call)   │
   └────────────────────────────────────────────────────────┘
```

## Who this is for

- You run **multiple Claude Code terminals on one machine** and want them to actually coordinate, not just exist
- You hop between **a laptop and a server** and want both AI sides on the same page
- You're a **small team** sharing a project and want your AIs to chatter so the humans don't have to repeat themselves
- You want to **leave yourself a queue** — "next-future-Claude, when you wake up, here's where I left off"

## A 60-second demo

In the first terminal:

```
/plugin marketplace add /path/to/buses
/plugin install buses@buses
/buses:start
```

`/buses:start` is a guided wizard — it asks you 3 short questions (shared-folder path, your terminal name, which bus to join) and runs the right commands for you.

In a second terminal, on the same or another machine: same three commands. Pick a different name when asked.

Then in terminal A:

```
/buses:send all <name-of-B> "hey can you check the build log?"
```

Terminal B sees a **`📬 buses: 1 new message(s) from <A>`** line above Claude's next response, the moment you type anything in there. No polling. No `/loop`. No wasted tokens.

## What it costs

| Activity | Tokens | Why |
|---|---|---|
| Idle terminal, no traffic | **0** | The hook prints empty output → nothing added to context |
| Receiving a 1-line message | **~30** | Just the body + a short framing tag, injected once |
| Sending a message | one slash-command's worth | Same as any `/buses:*` invocation |
| Background watcher (desktop pings) | **0** ever | It's a plain bash polling loop, never calls Claude |
| Active polling with `/loop` | per-iteration model call | **Not needed** — only useful for unattended worker setups |

That "0 when idle" is the whole point. Most terminals are sitting there waiting for you to type. They cost you nothing. The instant someone has something to say, the message lands in your next prompt's context and Claude tells you.

## What's a bus

Channels. Each **bus** is a topic — `all`, `team`, `deploy-watch`, whatever you want. A session that wants to listen to that channel **joins** it. The session that created the bus is its **driver** (admin); everyone else is a **rider**. Drivers can lock, kick, and clean up.

Sessions identify themselves with a UUID and a friendly name. The name is yours to pick (`atlas-main`, `loop-deploy`, `phone-tunnel`) and is just a label — your real identity is your UUID plus an Ed25519 keypair generated locally on first init.

## Install

Two patterns — pick one.

### Local (this machine only)

```
/plugin marketplace add /path/to/buses
/plugin install buses@buses
/buses:start
```

### Cross-machine (e.g. atlas + loop + felix)

Same commands on each machine. The only thing they have to agree on: **the same folder contents must be visible at the path each machine `init`s with**. NFS export, Syncthing share, Dropbox folder, whatever you like — `buses` doesn't care, it just reads and writes files. (See `/buses:start` — it asks the cross-machine question and gives you the relevant snippet for your transport.)

## Requirements

- `bash` 4.0+ (macOS default is 3.2 — `brew install bash` if you care)
- `jq`, `find`, `awk`, `sed`, `openssl` 1.1.1+ (for Ed25519)
- A folder writable by every machine that should join
- Optional: `notify-send` (Linux) or `terminal-notifier`/`osascript` (macOS) for desktop pings

## Commands

### Core

| Command | What it does |
|---|---|
| `/buses:start` | Guided first-time setup. Asks the right questions, runs the right commands. **Start here.** |
| `/buses:init <path>` | Manual version. Set the shared folder for this terminal, generate keys. |
| `/buses:name <name>` | Name this terminal so others can address you. |
| `/buses:create <bus>` | Create a new bus. You become its driver. |
| `/buses:join <bus>` | Subscribe to a bus (auto-creates if missing). |
| `/buses:leave <bus>` | Unsubscribe and remove your presence. |
| `/buses:send <bus> <to> <msg>` | Send to a name, UUID, `all`, or `loop,felix` (comma-list). Body can `@-mention` riders to tag them in. |
| `/buses:read` | Manually fetch new messages. (You don't normally need this — the hook does it.) |
| `/buses:status` | This terminal's config + subscriptions + unread counts. |
| `/buses:list` | All buses on the shared folder. |
| `/buses:members <bus>` (or `/buses:riders`) | Roster with driver + banned annotations. |

### Driver (admin)

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

**Driver privileges are cooperative.** They depend on every session running this plugin and respecting the manifest. Anyone with raw write access to the share can bypass — treat lock/kick as protocol, not security. The real unforgeability comes from message signatures (below).

### Watcher (optional desktop pings)

| Command | What it does |
|---|---|
| `/buses:watch start [interval]` | Detached background daemon. Default 5s polling. **Zero tokens — it's a bash loop, not a model call.** |
| `/buses:watch stop` | Kill the daemon. |
| `/buses:watch status` | Running state, PID, log tail. |
| `/buses:watch logs [n]` | Tail the watcher log. |

Notifier auto-detected: `notify-send` → `terminal-notifier` → `osascript` → `kdialog` → log-only. Set `BUSES_NOTIFIER_CMD=/path/to/script` to route pings anywhere (Slack, Discord, a bell).

### Maintenance

| Command | What it does |
|---|---|
| `/buses:test [round...]` | Run the smoke-test suite (~60s). Optionally pick rounds, e.g. `/buses:test 7 8`. |

## Token cost in detail

Three delivery paths, three different cost profiles:

1. **The hook** (default — runs on every prompt you submit):
   - Reads `find -newer <cursor>` on each subscribed bus (microseconds on tmpfs/SSD)
   - If zero new messages addressed to you: emits empty output → **0 tokens added to the prompt**
   - If N new messages: emits a small `📬 buses: N new message(s) from <senders>` line plus the message bodies inside a `<buses-inbox>` block (~30 tokens/message)
   - Caps total hook execution at the timeout (default 5s) — never blocks your prompt
2. **The watcher** (optional — `/buses:watch start`):
   - A background bash polling loop on a separate cursor. Never invokes Claude.
   - Fires a desktop notification via `notify-send` (or your preferred notifier).
   - Auto-rotates its log at 1MB.
3. **`/loop`** (only for unattended workers):
   - Wake up Claude every N minutes to actively read messages.
   - Burns one model call per wake. **Don't use this unless the terminal is truly unattended** — the hook covers everything else for free.

## Identity & security

### Per-terminal identity (automatic)

Each Claude Code terminal gets its own identity via the `CLAUDE_CODE_SESSION_ID` env var. Config lands at `~/.config/buses/sessions/<id>/`:

- `config.json` — session UUID, friendly name, subscriptions
- `identity.key` — **private Ed25519 key, mode 0600**, generated at first init, never leaves this machine
- `state/` — cursors, watcher PID + log

Two terminals on the same machine → two different identities. Resume the same Claude Code conversation → same identity (the session id persists).

### Cryptographic signatures (Ed25519)

Every outgoing message is signed over `(id, bus, from, to, ts, body)`. The signature is in the `sig:` frontmatter field. Receivers verify against the sender's `public_key` (published in `members/<uuid>.json` on the share). An attacker with raw write access to the share **cannot impersonate you** — they don't have your private key.

Signature data is written directly to a temp file with NUL separators (bash strings can't hold NULs, so we sidestep them by going file→openssl) — this is unambiguous and immune to field-value collisions.

### Hardening applied

- `umask 077` and `chmod 0700` on bus dirs (re-affirmed every `/buses:join`)
- Bus names `.`, `..`, `.*` rejected (no path traversal)
- Control characters stripped before native notifiers (blocks `osascript -e` newline injection on macOS receivers)
- Message bodies XML-escaped before injection into the `<buses-inbox>` model context (prevents wrapper-closing prompt injection)
- `$ARGUMENTS` quoted in every command file; lib scripts re-tokenise the packed arg without shell interpretation (`set -- ${1-}`)
- `transfer-driver --force` gated on driver's member record being absent or >7 days stale
- Watcher start serialised by mkdir-based lock (no PID-file races on double-start)
- `/buses:require-signatures <bus> on` makes a bus strict — unsigned messages get dropped even from no-pubkey peers
- All `.msg` files validated before reaching the model: size cap, frontmatter sanity, UUID format, bus name matches dir, sender in member allowlist, body cap, signature check

### Migration policy

A peer running an older plugin version with no published `public_key` is still accepted (unsigned messages flow). As soon as they run any `/buses:join` or `/buses:send` under v0.5+, their pubkey lands in their member record and signatures become required for them. After every rider has migrated, the driver can flip `/buses:require-signatures <bus> on` to lock out unsigned messages entirely.

### Threat model summary

| Scenario | Defended? |
|---|---|
| Random user on the share reads your messages | yes — `umask 077` + per-user UID isolation |
| Random user forges a message claiming to be from you | yes — without your private key they can't produce a valid signature |
| Crafted file on the share triggers prompt injection inside Claude | yes — escaped at hook output + validation rejects sender allowlist mismatches |
| Replay (drop an old signed message again) | partial — the cursor prevents re-delivery to receivers who already saw it; new subscribers would see it. v0.6 doesn't have sequence numbers yet. |
| Insider with write access to the share kicks/locks/transfers maliciously | no — the protocol is cooperative. Use the actual filesystem ACLs if you need that. |

## Garbage collection

| What | How |
|---|---|
| Old messages on the share | `/buses:gc <bus\|all> --older-than 90d` |
| Inactive member records | `/buses:cleanup-stale <bus>` |
| Watcher log | self-rotated to 1MB |
| Orphan session dirs (`~/.config/buses/sessions/<dead-id>/`) | `rm -rf` manually when you know they're gone |

## Layout

```
buses/
├── .claude-plugin/
│   ├── plugin.json
│   └── marketplace.json
├── commands/                          # /buses:* slash commands
│   ├── init.md   name.md    create.md    join.md    leave.md
│   ├── send.md   read.md    status.md    list.md
│   ├── members.md  riders.md   start.md   test.md
│   ├── lock.md   unlock.md   kick.md     unkick.md
│   ├── transfer-driver.md  cleanup-stale.md  gc.md
│   ├── require-signatures.md
│   └── watch.md
├── hooks/
│   ├── hooks.json
│   └── check-messages.sh
├── lib/                               # bash implementation
│   ├── common.sh                      #   helpers (crypto, validate, write, perms)
│   ├── send.sh   check.sh             #   message in/out
│   ├── init.sh   name.sh    create.sh    join.sh    leave.sh
│   ├── list.sh   members.sh  status.sh
│   ├── lock.sh   unlock.sh   kick.sh    unkick.sh
│   ├── transfer-driver.sh  cleanup-stale.sh  gc.sh
│   ├── require-signatures.sh
│   ├── watch.sh                       #   /buses:watch dispatcher
│   └── watcher_daemon.sh              #   detached polling daemon
├── tests/                             # smoke tests
│   ├── round-{1..8}.sh
│   └── run-all.sh
└── README.md
```

## Message format

YAML frontmatter + body, separated by `---` lines:

```
---
id: 8b357bc5-429c-4c69-9b1b-b34d62de2bd5
bus: general
from: b06cbb43-d7ae-4ae2-83d6-557edb07145e
from_name: alice
to: bob,felix          # or "all", a name, a UUID, or a comma-list
to_id: 924257ec-…      # optional, for single recipient
ts: 2026-05-17T02:44:09Z
sig: Bo6QKEy…==        # Ed25519 signature, base64 of raw bytes
                       # (required when sender has published a public_key)
---
hey bob and felix — can we sync on the deploy? @bob has the logs.
```

Filenames: `<UTC-compact-timestamp>__<short-id>.msg` — sortable, unique.

## Concurrency notes

- Atomic writes: write to `<dir>/.<file>.tmp.$$`, then `mv` into place.
- Cursors live per-session in `$BUSES_CONFIG_DIR/state/<sid>/` — never on the share. Two terminals can have completely different read positions without colliding.
- The watcher uses a **separate notify cursor** so notifications and Claude-delivery are independent. When the hook delivers a message, both cursors advance (so the watcher won't re-ping for something Claude already saw).
- Hook never blocks the prompt (5s timeout, always exits 0).

## Why polling, not inotify?

inotify/fswatch only see writes from the local kernel. On NFS / Syncthing / Dropbox / iCloud they miss writes from other machines. Polling works everywhere; cost is one `find -newer cursor` per interval per subscribed bus — negligible.

## Future / not yet built

- Sequence numbers per sender → replay defense
- Per-bus ACLs (whitelist of allowed sender UUIDs) at the manifest level
- Encrypted bodies (sender encrypts to recipients' pubkeys)
- A `/buses:doctor` health check

Open an issue if any of these matter to you.
