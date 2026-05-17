---
description: "List all members of a bus (session id, friendly name, host, last seen)."
argument-hint: "<bus-name>"
allowed-tools: ["Bash(${CLAUDE_PLUGIN_ROOT}/lib/members.sh:*)"]
---

```!
"${CLAUDE_PLUGIN_ROOT}/lib/members.sh" $ARGUMENTS
```

Echo the table. If a recipient name appears more than once, mention to the user that they may want to disambiguate by UUID when sending.
