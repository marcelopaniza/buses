---
description: "Initialise buses on this machine: set the shared folder path and generate a session UUID."
argument-hint: "<shared-folder-path> [--force]"
allowed-tools: ["Bash(${CLAUDE_PLUGIN_ROOT}/lib/init.sh:*)"]
---

```!
"${CLAUDE_PLUGIN_ROOT}/lib/init.sh" "$ARGUMENTS"
```

Report the output above to the user in one or two lines. If initialisation succeeded, remind them they can run `/buses:name <friendly-name>` next, then `/buses:create <bus>` or `/buses:join <bus>`.
