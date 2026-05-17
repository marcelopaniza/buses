---
description: "Driver-only: lock a bus so only the manager can send. Members can still read."
argument-hint: "<bus> [reason...]"
allowed-tools: ["Bash(${CLAUDE_PLUGIN_ROOT}/lib/lock.sh:*)"]
---

```!
"${CLAUDE_PLUGIN_ROOT}/lib/lock.sh" "$ARGUMENTS"
```

Confirm the lock in one line. If the command failed (e.g. not the manager), surface the error verbatim.
