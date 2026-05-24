---
description: "Start/stop the background watcher daemon that fires desktop notifications for new bus messages. Uses zero tokens — pure polling daemon, not a model loop."
argument-hint: "[start [interval] | stop | restart | status | logs [n]]"
allowed-tools: ["Bash(${CLAUDE_PLUGIN_ROOT}/lib/watch.sh:*)"]
---

```!
"${CLAUDE_PLUGIN_ROOT}/lib/watch.sh" "$(cat <<'BUSES_END_PAYLOAD_3f5a8c2d1b9e7f0a'
$ARGUMENTS
BUSES_END_PAYLOAD_3f5a8c2d1b9e7f0a
)"
```

Report the output verbatim. If the user is starting the watcher for the first time, mention that:
- It runs detached; it survives this terminal closing.
- It uses a separate "notification cursor", so messages will STILL appear inside Claude on the next user prompt — notifications and in-conversation delivery are independent.
- On NFS / Syncthing / Dropbox the polling interval (default 5s) is the only way to detect remote writes — inotify cannot see other machines' changes.
- Stop it with `/buses:watch stop` when no longer needed.
