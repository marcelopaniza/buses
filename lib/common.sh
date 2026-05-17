#!/usr/bin/env bash
# Shared helpers for the buses plugin. Source, don't execute.
# Portable across Linux and macOS. Requires: bash 3.2+, jq, find, date.

set -u

# ── config dir resolution ───────────────────────────────────────────────────
# Identity is PER-TERMINAL so multiple Claude Code terminals on one machine
# never share a config. Precedence:
#   1. $BUSES_CONFIG_DIR if explicitly set    (manual override; highest)
#   2. <xdg-config>/buses/sessions/$CLAUDE_CODE_SESSION_ID   (per-terminal)
#   3. <xdg-config>/buses/projects/<flat-PWD>                (manual/scripted)
#
# Every Claude Code terminal has a distinct CLAUDE_CODE_SESSION_ID, so each
# one resolves to its own config dir, its own UUID, its own /buses:name. The
# id persists across resumes of the same conversation, so closing and
# reopening Claude Code keeps the same identity.
buses::_flatten_path() {
  local p="$1"
  case "$p" in
    /*) ;;
    *)  p="$(cd "$p" 2>/dev/null && pwd 2>/dev/null)" || p="$HOME" ;;
  esac
  [ -n "$p" ] || p="$HOME"
  printf '%s' "$p" | sed 's,/,-,g'
}

buses::project_dir() {
  local p="${CLAUDE_PROJECT_DIR:-$PWD}"
  [ -n "$p" ] || p="$HOME"
  printf '%s' "$p"
}

buses::terminal_id() {
  printf '%s' "${CLAUDE_CODE_SESSION_ID:-}"
}

buses::_resolve_config_dir() {
  if [ -n "${BUSES_CONFIG_DIR:-}" ]; then
    printf '%s' "$BUSES_CONFIG_DIR"
    return 0
  fi
  local base="${XDG_CONFIG_HOME:-$HOME/.config}/buses"
  if [ -n "${CLAUDE_CODE_SESSION_ID:-}" ]; then
    printf '%s/sessions/%s' "$base" "$CLAUDE_CODE_SESSION_ID"
    return 0
  fi
  # No Claude Code env (manual/scripted use): fall back to per-project key.
  local key; key=$(buses::_flatten_path "$(buses::project_dir)")
  printf '%s/projects/%s' "$base" "$key"
}

# Remember whether the user explicitly set the path, for the legacy hint.
BUSES_CONFIG_DIR_EXPLICIT="${BUSES_CONFIG_DIR:-}"
BUSES_CONFIG_DIR="$(buses::_resolve_config_dir)"
BUSES_CONFIG_FILE="$BUSES_CONFIG_DIR/config.json"
BUSES_LEGACY_CONFIG_FILE="$HOME/.config/buses/config.json"

# ── output ──────────────────────────────────────────────────────────────────
buses::err() { printf 'buses: %s\n' "$*" >&2; }
buses::die() { buses::err "$*"; exit 1; }

# ── dependencies ────────────────────────────────────────────────────────────
buses::require() {
  for cmd in "$@"; do
    command -v "$cmd" >/dev/null 2>&1 || buses::die "missing required command: $cmd"
  done
}

# ── UUID generation (portable) ──────────────────────────────────────────────
buses::uuid() {
  if [ -r /proc/sys/kernel/random/uuid ]; then
    cat /proc/sys/kernel/random/uuid
  elif command -v uuidgen >/dev/null 2>&1; then
    uuidgen | tr 'A-Z' 'a-z'
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c 'import uuid; print(uuid.uuid4())'
  else
    buses::die "no UUID generator available (need uuidgen or python3)"
  fi
}

# ── timestamps ──────────────────────────────────────────────────────────────
buses::now_iso() { date -u +'%Y-%m-%dT%H:%M:%SZ'; }
buses::now_compact() { date -u +'%Y%m%dT%H%M%SZ'; }

# ── config I/O ──────────────────────────────────────────────────────────────
buses::config_exists() { [ -f "$BUSES_CONFIG_FILE" ]; }

buses::config_require() {
  if buses::config_exists; then return 0; fi
  # Helpful hint when a legacy single-config exists but isn't being used.
  if [ -z "$BUSES_CONFIG_DIR_EXPLICIT" ] \
     && [ -f "$BUSES_LEGACY_CONFIG_FILE" ] \
     && [ "$BUSES_CONFIG_FILE" != "$BUSES_LEGACY_CONFIG_FILE" ]; then
    buses::err "no config for this terminal session yet."
    buses::err "  terminal session: ${CLAUDE_CODE_SESSION_ID:-<not set — running outside Claude Code?>}"
    buses::err "  expected config:  $BUSES_CONFIG_FILE"
    buses::err ""
    buses::err "  found legacy single-config at: $BUSES_LEGACY_CONFIG_FILE"
    buses::err "    (in the old layout all terminals shared one identity — that's the bug)"
    buses::err ""
    buses::err "  pick one:"
    buses::err "    /buses:init <shared-path>"
    buses::err "       → fresh per-terminal identity here (recommended — /buses:name only affects this terminal)"
    buses::err "    BUSES_CONFIG_DIR=$HOME/.config/buses <cmd>"
    buses::err "       → keep using the legacy shared identity"
    exit 1
  fi
  buses::die "not initialised — run /buses:init <shared-path> first"
}

buses::config_get() {
  # $1 = jq filter (e.g. '.session_id'); falls back to "" on null/missing
  jq -r "${1} // \"\"" "$BUSES_CONFIG_FILE"
}

buses::config_set() {
  # $1 = jq update expression, e.g. '.session_name = $v' with --arg v "foo"
  # Remaining args are passed to jq verbatim (for --arg / --argjson).
  local expr="$1"; shift
  local tmp="${BUSES_CONFIG_FILE}.tmp.$$"
  jq "$@" "$expr" "$BUSES_CONFIG_FILE" > "$tmp" && mv "$tmp" "$BUSES_CONFIG_FILE"
}

buses::config_init_file() {
  # Write a fresh config with shared_path + session_id. $1 = shared_path.
  local shared_path="$1"
  local sid
  sid=$(buses::uuid)
  mkdir -p "$BUSES_CONFIG_DIR"
  jq -n \
    --arg sp "$shared_path" \
    --arg sid "$sid" \
    --arg cc_sid "${CLAUDE_CODE_SESSION_ID:-}" \
    --arg created "$(buses::now_iso)" \
    '{
      version: 1,
      shared_path: $sp,
      session_id: $sid,
      session_name: "",
      claude_code_session_id: $cc_sid,
      buses: [],
      created: $created
    }' > "$BUSES_CONFIG_FILE"
  printf '%s' "$sid"
}

# ── shared-folder paths ─────────────────────────────────────────────────────
buses::shared_root() { buses::config_get '.shared_path'; }

buses::bus_dir()      { printf '%s/buses/%s' "$(buses::shared_root)" "$1"; }
buses::bus_messages() { printf '%s/buses/%s/messages' "$(buses::shared_root)" "$1"; }
buses::bus_members()  { printf '%s/buses/%s/members' "$(buses::shared_root)" "$1"; }

buses::state_dir() {
  # Per-session local state (cursors, etc). Lives under config dir, NOT shared,
  # so cursors are independent per session even if config is on the share.
  local sid; sid=$(buses::config_get '.session_id')
  printf '%s/state/%s' "$BUSES_CONFIG_DIR" "$sid"
}

buses::cursor_file() {
  # Per-bus cursor for "what's the newest message I've already processed
  # and delivered to the model". Advanced by the hook and /buses:read.
  printf '%s/cursor.%s' "$(buses::state_dir)" "$1"
}

buses::notify_cursor_file() {
  # Per-bus cursor for "what's the newest message I've already shown the user
  # via a desktop notification". Advanced by the watcher (and also by the hook,
  # so we never re-notify after delivery).
  printf '%s/notified.%s' "$(buses::state_dir)" "$1"
}

# ── bus validation ──────────────────────────────────────────────────────────
buses::bus_exists() { [ -d "$(buses::bus_dir "$1")" ]; }
buses::is_subscribed() {
  # $1 = bus name. Returns 0 if subscribed.
  jq -e --arg b "$1" '.buses | index($b) != null' "$BUSES_CONFIG_FILE" >/dev/null 2>&1
}

buses::valid_name() {
  # Bus and session names: 1-64 chars, [a-zA-Z0-9._-]
  [[ "$1" =~ ^[A-Za-z0-9._-]{1,64}$ ]]
}

# ── manifest / manager / lock / ban ─────────────────────────────────────────
buses::manifest_file() { printf '%s/manifest.json' "$(buses::bus_dir "$1")"; }

buses::manifest_get() {
  # $1 = bus, $2 = jq filter (e.g. '.manager')
  local mf; mf=$(buses::manifest_file "$1")
  [ -f "$mf" ] || { printf ''; return 0; }
  jq -r "${2} // \"\"" "$mf" 2>/dev/null || printf ''
}

buses::manifest_set() {
  # $1 = bus, $2 = jq expression, remaining args passed to jq.
  local bus="$1"; shift
  local expr="$1"; shift
  local mf; mf=$(buses::manifest_file "$bus")
  [ -f "$mf" ] || buses::die "bus '$bus' has no manifest"
  local tmp="${mf}.tmp.$$"
  jq "$@" "$expr" "$mf" > "$tmp" && mv "$tmp" "$mf"
}

buses::is_manager() {
  # $1 = bus. Returns 0 if our session is the bus manager.
  local sid mgr
  sid=$(buses::config_get '.session_id')
  mgr=$(buses::manifest_get "$1" '.manager')
  [ -n "$mgr" ] && [ "$mgr" = "$sid" ]
}

buses::is_locked() {
  # $1 = bus. Returns 0 if a lock is set.
  local mf; mf=$(buses::manifest_file "$1")
  [ -f "$mf" ] || return 1
  jq -e '.locked != null and .locked != {}' "$mf" >/dev/null 2>&1
}

buses::lock_reason() {
  buses::manifest_get "$1" '.locked.reason'
}

buses::is_banned() {
  # $1 = bus, $2 = target uuid (defaults to our own sid).
  local bus="$1"
  local target="${2:-$(buses::config_get '.session_id')}"
  local mf; mf=$(buses::manifest_file "$bus")
  [ -f "$mf" ] || return 1
  jq -e --arg t "$target" '.banned // [] | index($t) != null' "$mf" >/dev/null 2>&1
}

buses::resolve_member() {
  # $1 = bus, $2 = name-or-uuid. Echoes the canonical UUID if found, else empty.
  local bus="$1" who="$2"
  local mdir; mdir=$(buses::bus_members "$bus")
  [ -d "$mdir" ] || { printf ''; return 0; }
  # Already a uuid that exists as a member?
  if [ -f "$mdir/$who.json" ]; then printf '%s' "$who"; return 0; fi
  while IFS= read -r f; do
    [ -f "$f" ] || continue
    local id name
    id=$(jq -r '.id // ""' "$f" 2>/dev/null)
    name=$(jq -r '.name // ""' "$f" 2>/dev/null)
    if [ "$name" = "$who" ]; then printf '%s' "$id"; return 0; fi
  done < <(find "$mdir" -maxdepth 1 -name '*.json' -type f 2>/dev/null)
  printf ''
}

# ── presence ────────────────────────────────────────────────────────────────
buses::write_member_record() {
  # Drop / refresh this session's member.json inside a bus. $1 = bus.
  local bus="$1"
  local members_dir; members_dir=$(buses::bus_members "$bus")
  local sid; sid=$(buses::config_get '.session_id')
  local name; name=$(buses::config_get '.session_name')
  local host; host=$(hostname 2>/dev/null || echo "unknown")
  mkdir -p "$members_dir"
  local tmp="$members_dir/.$sid.tmp.$$"
  jq -n \
    --arg id "$sid" \
    --arg name "$name" \
    --arg host "$host" \
    --arg seen "$(buses::now_iso)" \
    '{id: $id, name: $name, host: $host, last_seen: $seen}' > "$tmp"
  mv "$tmp" "$members_dir/$sid.json"
}
