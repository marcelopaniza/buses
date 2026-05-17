---
description: "Send a message to a bus. Recipient can be a session name, session UUID, or 'all' to broadcast."
argument-hint: "<bus> <to|all> <message...>"
allowed-tools: ["Bash(${CLAUDE_PLUGIN_ROOT}/lib/send.sh:*)"]
---

```!
"${CLAUDE_PLUGIN_ROOT}/lib/send.sh" $ARGUMENTS
```

Confirm in one line which bus and recipient received the message.
