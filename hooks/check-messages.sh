#!/usr/bin/env bash
# UserPromptSubmit hook: pull any unread messages addressed to this session,
# inject them as additionalContext, and advance the cursor. Silent on error,
# silent when there is nothing to deliver — so cost is ~0 tokens in the idle
# case and never blocks the user's prompt.

set -uo pipefail

# Drain stdin (Claude Code passes JSON we don't currently consume).
cat >/dev/null 2>&1 || true

# Be paranoid: a misconfigured hook must never break the user's session.
{
  # Don't check for the config file ourselves — check.sh and common.sh do
  # the (per-terminal vs per-project vs legacy override) resolution. An
  # uninitialised session just makes check.sh exit silently, which is fine.
  [ -x "${CLAUDE_PLUGIN_ROOT:-}/lib/check.sh" ] || exit 0
  command -v jq    >/dev/null 2>&1 || exit 0
  command -v find  >/dev/null 2>&1 || exit 0

  out=$("${CLAUDE_PLUGIN_ROOT}/lib/check.sh" --hook 2>/dev/null) || exit 0
  [ -n "$out" ] && printf '%s' "$out"
} 2>/dev/null

exit 0
