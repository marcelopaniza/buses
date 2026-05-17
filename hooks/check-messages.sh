#!/usr/bin/env bash
# UserPromptSubmit hook: pull any unread messages addressed to this session,
# inject them as additionalContext, and advance the cursor. Silent on error,
# silent when there is nothing to deliver — so cost is ~0 tokens in the idle
# case and never blocks the user's prompt.

# Drain stdin (Claude Code may pass JSON; we don't currently need it).
cat >/dev/null 2>&1 || true

# Be paranoid: a misconfigured hook must never break the user's session.
{
  config_dir="${BUSES_CONFIG_DIR:-$HOME/.config/buses}"
  config_file="$config_dir/config.json"
  [ -f "$config_file" ] || exit 0
  [ -x "${CLAUDE_PLUGIN_ROOT}/lib/check.sh" ] || exit 0
  command -v jq >/dev/null 2>&1 || exit 0
  command -v find >/dev/null 2>&1 || exit 0

  out=$("${CLAUDE_PLUGIN_ROOT}/lib/check.sh" --hook 2>/dev/null) || exit 0
  [ -n "$out" ] && printf '%s' "$out"
} 2>/dev/null

exit 0
