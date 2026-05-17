#!/usr/bin/env bash
# Round 3: tests for per-terminal identity resolution via CLAUDE_CODE_SESSION_ID.
set -euo pipefail

PLUGIN=/mnt/data/buses
TMPDIR=$(mktemp -d /tmp/buses-test3.XXXXXX)
SHARED="$TMPDIR/share"
HOME_REAL="$HOME"
FAKE_HOME="$TMPDIR/home"

red()    { printf '\033[31m%s\033[0m\n' "$*"; }
green()  { printf '\033[32m%s\033[0m\n' "$*"; }
banner() { printf '\n\033[1;34m== %s ==\033[0m\n' "$*"; }
fail()   { red "FAIL: $*"; exit 1; }
pass()   { green "PASS: $*"; }

cleanup() { rm -rf "$TMPDIR"; }
trap cleanup EXIT

mkdir -p "$SHARED" "$FAKE_HOME/.config"

# Run a script with a synthetic Claude Code env. No BUSES_CONFIG_DIR override —
# we want to test the auto-resolution.
run_as_term() {
  local term_id="$1"; shift
  ( unset BUSES_CONFIG_DIR
    export CLAUDE_CODE_SESSION_ID="$term_id"
    export HOME="$FAKE_HOME"
    export XDG_CONFIG_HOME="$FAKE_HOME/.config"
    "$PLUGIN/lib/$1.sh" "${@:2}" )
}

banner "1. two terminals → two different config dirs (no BUSES_CONFIG_DIR override)"
run_as_term aaaaaaaa-1111-1111-1111-aaaaaaaaaaaa init "$SHARED" >/dev/null
run_as_term bbbbbbbb-2222-2222-2222-bbbbbbbbbbbb init "$SHARED" >/dev/null

cfg_a="$FAKE_HOME/.config/buses/sessions/aaaaaaaa-1111-1111-1111-aaaaaaaaaaaa/config.json"
cfg_b="$FAKE_HOME/.config/buses/sessions/bbbbbbbb-2222-2222-2222-bbbbbbbbbbbb/config.json"
[ -f "$cfg_a" ] && [ -f "$cfg_b" ] || fail "expected per-terminal config files; got: $(ls -R $FAKE_HOME/.config 2>&1)"

sid_a=$(jq -r '.session_id' "$cfg_a")
sid_b=$(jq -r '.session_id' "$cfg_b")
[ "$sid_a" != "$sid_b" ] || fail "two terminals should mint distinct UUIDs; both got $sid_a"
pass "terminal A sid=$sid_a, terminal B sid=$sid_b (distinct)"

banner "2. /buses:name in A does NOT rename B (the original bug)"
run_as_term aaaaaaaa-1111-1111-1111-aaaaaaaaaaaa name terminal-A >/dev/null
run_as_term bbbbbbbb-2222-2222-2222-bbbbbbbbbbbb name terminal-B >/dev/null

name_a=$(jq -r '.session_name' "$cfg_a")
name_b=$(jq -r '.session_name' "$cfg_b")
[ "$name_a" = "terminal-A" ] || fail "A's name should be terminal-A, got: $name_a"
[ "$name_b" = "terminal-B" ] || fail "B's name should be terminal-B, got: $name_b"
pass "names are independent (A=$name_a, B=$name_b)"

banner "3. claude_code_session_id is recorded in config"
cc_a=$(jq -r '.claude_code_session_id' "$cfg_a")
cc_b=$(jq -r '.claude_code_session_id' "$cfg_b")
[ "$cc_a" = "aaaaaaaa-1111-1111-1111-aaaaaaaaaaaa" ] || fail "A's recorded cc-sid wrong: $cc_a"
[ "$cc_b" = "bbbbbbbb-2222-2222-2222-bbbbbbbbbbbb" ] || fail "B's recorded cc-sid wrong: $cc_b"
pass "claude_code_session_id is captured in each config"

banner "4. legacy single-config triggers hint"
mkdir -p "$FAKE_HOME/.config/buses"
echo '{"version":1,"shared_path":"/x","session_id":"legacy","session_name":"legacy","buses":[]}' \
  > "$FAKE_HOME/.config/buses/config.json"
err=$(run_as_term cccccccc-3333-3333-3333-cccccccccccc status 2>&1 || true)
echo "$err" | grep -q "legacy single-config" || fail "expected legacy hint; got: $err"
echo "$err" | grep -q "/buses:init"           || fail "expected init suggestion in hint"
pass "legacy hint shown when current terminal lacks a config"

banner "5. explicit BUSES_CONFIG_DIR override beats CLAUDE_CODE_SESSION_ID"
custom="$TMPDIR/custom"
( unset CLAUDE_CODE_SESSION_ID
  BUSES_CONFIG_DIR="$custom" HOME="$FAKE_HOME" \
    "$PLUGIN/lib/init.sh" "$SHARED" >/dev/null )
[ -f "$custom/config.json" ] || fail "BUSES_CONFIG_DIR override didn't write to $custom"
pass "BUSES_CONFIG_DIR override respected"

# Same with CLAUDE_CODE_SESSION_ID also set — override still wins.
custom2="$TMPDIR/custom2"
BUSES_CONFIG_DIR="$custom2" CLAUDE_CODE_SESSION_ID="zzz" HOME="$FAKE_HOME" \
  "$PLUGIN/lib/init.sh" "$SHARED" >/dev/null
[ -f "$custom2/config.json" ] || fail "override didn't win over CLAUDE_CODE_SESSION_ID"
pass "explicit override beats CLAUDE_CODE_SESSION_ID"

banner "6. no CLAUDE_CODE_SESSION_ID, no BUSES_CONFIG_DIR → falls back to per-project key"
proj="$TMPDIR/proj-1"
mkdir -p "$proj"
( unset CLAUDE_CODE_SESSION_ID BUSES_CONFIG_DIR
  cd "$proj"
  export HOME="$FAKE_HOME" XDG_CONFIG_HOME="$FAKE_HOME/.config"
  "$PLUGIN/lib/init.sh" "$SHARED" >/dev/null )
expected_dir="$FAKE_HOME/.config/buses/projects/$(printf '%s' "$proj" | sed 's,/,-,g')"
[ -f "$expected_dir/config.json" ] || fail "expected per-project fallback at $expected_dir"
pass "per-project fallback used when no CLAUDE_CODE_SESSION_ID"

green ""
green "ALL ROUND-3 TESTS PASSED"
