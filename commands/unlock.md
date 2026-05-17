---
description: "Driver-only: clear the lock on a bus so everyone can send again."
argument-hint: "<bus>"
allowed-tools: ["Bash(${CLAUDE_PLUGIN_ROOT}/lib/unlock.sh:*)"]
---

```!
"${CLAUDE_PLUGIN_ROOT}/lib/unlock.sh" "$ARGUMENTS"
```

Confirm in one line.
