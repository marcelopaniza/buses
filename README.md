# buses — cross-terminal messaging for Claude Code

A tiny plugin that lets multiple Claude Code sessions — on one machine or several — talk to each other through a **shared folder**. Designed to be:

- **Cheap.** Idle terminals burn **zero tokens**. Messages are picked up by a `UserPromptSubmit` hook (no polling, no loops, no scheduled wakeups).
- **Boring.** Plain files. `cat` the message folder and you can see everything.
- **Portable.** The plugin never hardcodes a path. Each machine points it at whatever shared folder you've already got mounted.

---

## How it works

```
  Session A ───┐                          ┌─── Session B
               │                          │
               ▼                          ▼
        ╔══════════════════════════════════════╗
        ║   <shared-folder>/buses/<bus>/       ║
        ║      ├─ manifest.json                ║
        ║      ├─ members/<uuid>.json          ║
        ║      └─ messages/<ts>__<id>.msg      ║
        ╚══════════════════════════════════════╝
```

- `/buses:send` writes a file. That's it.
- The receiver's `UserPromptSubmit` hook runs `find -newer <cursor>` on every prompt. If anything matches, it's injected as `additionalContext` and the cursor is advanced.
- If nothing is waiting, the hook emits empty output → **zero tokens added to the prompt**.

You only pay tokens for messages you actually receive, in the exact turn the user was already typing into.

## Requirements

- `bash` 3.2+, `jq`, `find`, GNU or BSD `date`.
- A folder path that's writable by every machine that should join (NFS, SMB, Syncthing, Dropbox, iCloud Drive, a git checkout with auto-pull, or simply `/tmp` for a single-machine demo).

## Install

Two patterns — pick one.

### Local development (this machine only)

From within Claude Code:

```
/plugin marketplace add /mnt/data/buses
/plugin install buses@buses
```

### Shared across machines

Push this repo somewhere, then on each machine:

```
/plugin marketplace add <git-url-of-this-repo>
/plugin install buses@buses
```

Then on each machine, point it at the shared path:

```
/buses:init /path/to/shared/folder/on/this/machine
/buses:name <friendly-name>
/buses:join general
```

The shared path can differ per machine — on Mac it might be `~/Library/CloudStorage/Dropbox/buses-share`, on a Linux server `/mnt/share/buses-share`. The plugin doesn't care, as long as every machine sees the same folder contents.

## Commands

| Command | What it does |
|---|---|
| `/buses:init <path>` | Set the shared folder for this machine, generate a session UUID. |
| `/buses:name <name>` | Set a friendly name (other sessions address you by this or your UUID). |
| `/buses:create <bus>` | Create a new bus on the shared folder. |
| `/buses:join <bus>` | Subscribe this session to a bus (auto-creates if missing). |
| `/buses:leave <bus>` | Unsubscribe and remove presence. |
| `/buses:send <bus> <to> <msg>` | Send to a member name, UUID, or `all`. |
| `/buses:read` | Manually fetch new messages and advance the cursor. (You don't normally need this — the hook does it.) |
| `/buses:status` | This session's config, subscriptions, and unread counts. |
| `/buses:list` | All buses on the shared folder. |
| `/buses:members <bus>` | Members of a bus. |

## Message format

A `.msg` file is YAML frontmatter + body:

```
---
id: 8b357bc5-429c-4c69-9b1b-b34d62de2bd5
bus: general
from: b06cbb43-d7ae-4ae2-83d6-557edb07145e
from_name: alice
to: bob
to_id: 924257ec-7a1b-498e-a943-a62c330ee1a5
ts: 2026-05-17T02:44:09Z
---
hey bob, can you check the deploy?
```

Filenames are `<UTC-compact-timestamp>__<short-id>.msg` — sortable, unique, and won't collide even on the same second.

## Identity model

- One **session UUID** per `/buses:init` invocation, stored in `~/.config/buses/config.json` (overridable via `$BUSES_CONFIG_DIR`).
- One **friendly name** per session, optional, can be anything matching `[A-Za-z0-9._-]{1,64}`.
- One config file per Claude Code session — so on a single machine you can have many sessions with distinct identities. Each session lives in its own `$BUSES_CONFIG_DIR`. (For a default install they all share `~/.config/buses`, meaning all terminals on that host share one identity. Override `$BUSES_CONFIG_DIR` if you want per-terminal identity.)

Names are *not* globally unique. If two sessions share a name, `/buses:send general alice ...` will land in **every** message file but only the one whose UUID matches will pick it up (the receive filter is `to == sid || to == name || to == "all"`). For unambiguous delivery, use the UUID.

## Why no `/loop`?

`/loop` invokes the model each iteration — even when there's nothing new. That's expensive at scale (multiple terminals, multiple buses). The `UserPromptSubmit` hook is **free** because:

1. It runs only when the user is already typing (i.e. about to spend tokens anyway).
2. If the inbox is empty, the hook prints nothing → no tokens added.
3. Filesystem `find -newer` is microseconds, not API round-trips.

If you genuinely need a session to react to messages **with no user input** (e.g. an unattended worker), then `/loop 30m /buses:read` is reasonable — but consider whether that session could be triggered some other way (cron, file watcher with `ScheduleWakeup`) first.

## Concurrency notes

- All writes are atomic: write to `<dir>/.<file>.tmp.$$`, then `mv` into place. Safe on local FS and most NFS configurations.
- Cursors are **per-session, stored locally** (in `$BUSES_CONFIG_DIR/state/<uuid>/cursor.<bus>`). They're never written to the shared folder, so two sessions can have wildly different read positions without conflict.
- No locking. Two senders writing identically-named files at the same nanosecond would collide, but filenames include a UUID short prefix to avoid this.

## Troubleshooting

- **Hook seems inactive.** Confirm plugin is loaded (`/plugin`), then run `/buses:status` and check that `shared_path` is `[ok]`. The hook silently no-ops if config is missing.
- **No messages arriving.** Run `/buses:read` manually. If that shows them, the hook is firing but maybe filtered out (sender == self, or `to:` doesn't match your name/UUID). Run `/buses:status` to confirm subscriptions.
- **"jq: command not found".** Install jq (`apt install jq`, `brew install jq`, etc.). This plugin is intentionally bash-only and leans on jq for JSON.

## Layout

```
buses/
├── .claude-plugin/
│   ├── plugin.json          # plugin manifest
│   └── marketplace.json     # marketplace manifest
├── commands/                # /buses:* slash commands
│   ├── init.md  name.md  create.md  join.md  leave.md
│   ├── send.md  read.md   status.md list.md  members.md
├── hooks/
│   ├── hooks.json           # registers UserPromptSubmit
│   └── check-messages.sh    # silent wrapper around lib/check.sh
└── lib/                     # bash implementation
    ├── common.sh            # config + path helpers
    ├── send.sh check.sh
    └── init.sh name.sh create.sh join.sh leave.sh
        list.sh members.sh status.sh
```
