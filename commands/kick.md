---
description: "Manager-only: kick a member from a bus (adds to banlist + drops a notice for them)."
argument-hint: "<bus> <name-or-uuid> [reason...]"
allowed-tools: ["Bash(${CLAUDE_PLUGIN_ROOT}/lib/kick.sh:*)"]
---

```!
"${CLAUDE_PLUGIN_ROOT}/lib/kick.sh" $ARGUMENTS
```

Confirm in one line. Banning is cooperative: it relies on every session running this plugin — anyone with raw write access to the shared folder can bypass.
