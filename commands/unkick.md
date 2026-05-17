---
description: "Driver-only: lift a ban on a member, allowing them to rejoin and send."
argument-hint: "<bus> <name-or-uuid>"
allowed-tools: ["Bash(${CLAUDE_PLUGIN_ROOT}/lib/unkick.sh:*)"]
---

```!
"${CLAUDE_PLUGIN_ROOT}/lib/unkick.sh" "$ARGUMENTS"
```

Confirm in one line.
