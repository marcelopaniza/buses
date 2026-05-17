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

### Core

| Command | What it does |
|---|---|
| `/buses:init <path>` | Set the shared folder for this machine, generate a session UUID. |
| `/buses:name <name>` | Set a friendly name (other sessions address you by this or your UUID). |
| `/buses:create <bus>` | Create a new bus on the shared folder. The creator becomes driver. |
| `/buses:join <bus>` | Subscribe this session to a bus (auto-creates if missing). |
| `/buses:leave <bus>` | Unsubscribe and remove presence. |
| `/buses:send <bus> <to> <msg>` | Send to a rider name, UUID, `all`, or a comma-list (`loop,felix`). Body can also `@-mention` riders to grab their attention. |
| `/buses:start` | First-time guided setup (asks the right questions and calls the right commands). |
| `/buses:read` | Manually fetch new messages and advance the cursor. (You don't normally need this — the hook does it.) |
| `/buses:status` | This session's config, subscriptions, and unread counts. |
| `/buses:list` | All buses on the shared folder. |
| `/buses:members <bus>` (or `/buses:riders`) | Riders of a bus, with driver + banned annotations. |

### Driver (creator of a bus, transferable)

Every bus has one **driver** (admin). Everyone else is a **rider**.

| Command | What it does |
|---|---|
| `/buses:lock <bus> [reason]` | Block all sends except from the driver. Riders can still read. |
| `/buses:unlock <bus>` | Lift the lock. |
| `/buses:kick <bus> <name-or-uuid> [reason]` | Add to banlist, remove member record, drop a kick-notice for the target. |
| `/buses:unkick <bus> <name-or-uuid>` | Lift a ban. |
| `/buses:transfer-driver <bus> <name-or-uuid> [--force]` | Hand the wheel to another rider. `--force` lets any rider take over a bus whose driver is gone — gated on the current driver's member record being absent or older than 7 days, to prevent casual takeovers. |
| `/buses:cleanup-stale <bus> [--older-than 30d] [--dry-run] [--force]` | Remove member records that haven't checked in recently. Driver record is preserved unless `--force`. |
| `/buses:gc <bus|all> [--older-than 90d] [--dry-run] [--force]` | Delete old messages from a bus (or every bus). Default threshold 90d. |

**Driver privileges are cooperative, not enforced.** They depend on every session running this plugin and respecting the manifest. Anyone with raw write access to the shared folder can bypass. Treat lock/kick as protocol, not security.

> **Naming history**: older manifests stored the driver under `manager`. The plugin reads either field and writes `driver`, so old buses migrate automatically the first time anyone runs a driver action on them.

### Watcher (optional desktop notifications)

| Command | What it does |
|---|---|
| `/buses:watch start [interval]` | Start a background polling daemon (default 5s). Detached, survives terminal close. |
| `/buses:watch stop` | Stop the watcher. |
| `/buses:watch restart [interval]` | Stop + start. |
| `/buses:watch status` | Show running state, PID, interval, recent log. |
| `/buses:watch logs [n]` | Tail the watcher log (default 30 lines). |

The watcher costs **zero tokens** — it's a plain bash polling loop, never invokes Claude. Notifications go through `notify-send` (Linux), `terminal-notifier` or `osascript` (macOS), or `kdialog` (KDE), in that order. Set `BUSES_NOTIFIER_CMD=/path/to/script` to route notifications anywhere (e.g. send to Slack, write to a file, ring a bell).

The watcher and the hook use **independent cursors** — getting a notification does NOT remove the message from the next prompt's inbox. Conversely, when the hook delivers a message to Claude, both cursors advance so the watcher won't fire for it later.

**Why polling, not inotify?** Inotify/fswatch only see writes from the local kernel, so on NFS / Syncthing / Dropbox / iCloud they miss changes made on other machines. Polling works everywhere; the daemon's cost is one `find -newer` per interval per subscribed bus — negligible.

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

**Per Claude Code terminal, automatic.** Every Claude Code session has a unique `CLAUDE_CODE_SESSION_ID` in its environment, and the plugin keys its config off it:

```
~/.config/buses/sessions/<CLAUDE_CODE_SESSION_ID>/config.json
```

This means:

- Open two terminals on the same machine → two distinct UUIDs, two distinct `/buses:name`s, two independent inboxes.
- Resume a conversation later → same `CLAUDE_CODE_SESSION_ID`, same identity, same buses.
- Two terminals in the same project → still distinct (each terminal is its own session).

**Resolution precedence:**

1. `$BUSES_CONFIG_DIR` if explicitly set — manual override, highest priority.
2. `~/.config/buses/sessions/<CLAUDE_CODE_SESSION_ID>/` — per-terminal, automatic.
3. `~/.config/buses/projects/<flat-PWD>/` — fallback when running scripts outside Claude Code.

**Overrides** you might want:

- Want two terminals to share one identity (e.g. a long-running "worker" identity bound to a project)?
  ```
  export BUSES_CONFIG_DIR=~/.config/buses/projects/my-worker
  ```
  Set this before launching Claude Code, in both terminals.
- Want one terminal to use someone else's pre-shared config? Same mechanism.

**Names are not globally unique.** If two sessions share a name, `/buses:send general alice ...` will land in **every** message file but only the one whose UUID matches will pick it up (the receive filter is `to == sid || to == name || to == "all"`). For unambiguous delivery, use the UUID.

### Migrating from earlier versions

Earlier versions used a single config at `~/.config/buses/config.json` — meaning every terminal on the machine shared one identity (when you `/buses:name foo` in one terminal, every terminal became `foo`). If you have that legacy file, `/buses:status` will detect it and print a hint. To migrate:

```
# in each terminal, once:
/buses:init <your-shared-path>
/buses:name <a-name-you-pick-for-this-terminal>
/buses:join <bus>
# optional cleanup, only after all terminals migrated:
rm ~/.config/buses/config.json
```

Or, to *keep* the old "single identity" behavior (not recommended but supported):

```
export BUSES_CONFIG_DIR=~/.config/buses
```

in every terminal's shell init, before launching Claude Code.

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

## Security notes

The plugin is designed for **trusted peers on a cooperative folder**. It is not a security boundary. Specifically:

- **Driver / lock / ban / kick are cooperative.** Anyone with raw write access to the shared folder can bypass them by writing files directly. Treat them as protocol, not security.
- **Hardening applied (v0.4):** restrictive `umask 077` for all files; bus names `.`/`..`/`.*` rejected (no path traversal); control characters stripped before passing message bodies to native notifiers (notably blocks `osascript -e` newline injection on macOS receivers); message bodies are XML-escaped before injection into the model's `<buses-inbox>` context block (prevents a sender from closing the wrapper and crafting injected instructions); `transfer-driver --force` requires the current driver's record to be absent or >7 days stale.
- **`$ARGUMENTS` is quoted** in every command file, and lib scripts re-tokenise the single packed arg without shell interpretation. This blocks the simple-metachar case (`;`, `|`, `&`, `$()`). A user typing literal `"` characters in a message body can still potentially break the quoting envelope — this is a Claude Code harness limitation, not specific to buses. Avoid typing `"` in `/buses:send` bodies unless escaped.
- **`BUSES_NOTIFIER_CMD`**, if set, must be the absolute path of a single executable (no extra args / shell snippet). It is invoked with `"$title"` and `"$body"` as positional args.
- **Bus messages are prompt-injection vectors** by design — a malicious sender can write content that tries to steer your local Claude. We escape the wrapper-closing characters, but treat received messages with the same scepticism you'd apply to any other untrusted input.

## Garbage collection

- `/buses:cleanup-stale <bus>` — remove inactive member records.
- `/buses:gc <bus|all>` — remove old `.msg` files. Default: older than 90 days.
- Watcher log is self-rotated to ~1MB (truncate-on-overflow) by the daemon itself.
- Per-session config dirs at `~/.config/buses/sessions/<dead-cc-sid>/` accumulate over time. Safe to delete any whose `config.json` references a Claude Code session you no longer have.

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
│   ├── lock.md  unlock.md  kick.md   unkick.md
│   └── watch.md
├── hooks/
│   ├── hooks.json           # registers UserPromptSubmit
│   └── check-messages.sh    # silent wrapper around lib/check.sh
└── lib/                     # bash implementation
    ├── common.sh            # config, paths, manifest, manager/ban helpers
    ├── send.sh   check.sh
    ├── init.sh   name.sh    create.sh  join.sh    leave.sh
    ├── list.sh   members.sh status.sh
    ├── lock.sh   unlock.sh  kick.sh    unkick.sh
    ├── watch.sh             # /buses:watch dispatcher
    └── watcher_daemon.sh    # the actual polling loop
```
