---
description: "Create a new bus on the shared folder (idempotent — safe to re-run)."
argument-hint: "<bus-name>"
allowed-tools: ["Bash(${CLAUDE_PLUGIN_ROOT}/lib/create.sh:*)"]
---

```!
"${CLAUDE_PLUGIN_ROOT}/lib/create.sh" "$ARGUMENTS"
```

Tell the user the bus is ready. If they want to receive messages on it, suggest `/buses:join <bus-name>`.
