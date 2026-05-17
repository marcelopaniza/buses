#!/usr/bin/env bash
# Find new messages across subscribed buses addressed to this session.
#
# Modes:
#   --hook    Hook-friendly: emit additionalContext JSON; advance HOOK + NOTIFY cursors.
#   --human   Pretty-print to stdout;                    advance HOOK + NOTIFY cursors.
#   --peek    Pretty-print but DO NOT advance any cursor (preview).
#   --count   Print integer count of unread messages (no advance).
#   --notify  Watcher mode: print one TAB-separated line per match:
#               <bus>\t<from_name>\t<short-preview>
#             Uses + advances NOTIFY cursor only — never touches HOOK cursor,
#             so the user still sees the message inside Claude on their next prompt.
#
# Default: --human.

set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/common.sh"
buses::require jq find
buses::config_require

mode="${1:---human}"
case "$mode" in --hook|--human|--peek|--count|--notify) ;; *) buses::die "unknown mode: $mode" ;; esac

sid=$(buses::config_get '.session_id')
name=$(buses::config_get '.session_name')
shared=$(buses::shared_root)
[ -d "$shared" ] || buses::die "shared path does not exist: $shared"

mapfile -t subscribed < <(jq -r '.buses[]?' "$BUSES_CONFIG_FILE")
[ "${#subscribed[@]}" -gt 0 ] || { [ "$mode" = "--count" ] && echo 0; exit 0; }

mkdir -p "$(buses::state_dir)"

# Per-mode cursor strategy.
cursor_for_bus() {
  if [ "$mode" = "--notify" ]; then buses::notify_cursor_file "$1"
  else                              buses::cursor_file        "$1"
  fi
}

matches=()  # each entry: "<bus>\t<file>"
total=0

for bus in "${subscribed[@]}"; do
  [ -n "$bus" ] || continue
  mdir=$(buses::bus_messages "$bus")
  [ -d "$mdir" ] || continue
  cursor=$(cursor_for_bus "$bus")

  if [ -f "$cursor" ]; then
    new_files=$(find "$mdir" -maxdepth 1 -type f -name '*.msg' -newer "$cursor" 2>/dev/null | LC_ALL=C sort)
  else
    new_files=$(find "$mdir" -maxdepth 1 -type f -name '*.msg' 2>/dev/null | LC_ALL=C sort)
  fi
  [ -z "$new_files" ] && continue

  while IFS= read -r f; do
    [ -f "$f" ] || continue
    fm=$(awk 'BEGIN{n=0} /^---$/{n++; next} n==1{print} n>=2{exit}' "$f")
    msg_to=$(printf '%s\n'   "$fm" | awk -F': *' '$1=="to"{print $2; exit}')
    msg_from=$(printf '%s\n' "$fm" | awk -F': *' '$1=="from"{print $2; exit}')
    [ "$msg_from" = "$sid" ] && continue       # skip self-messages

    # Match if any comma-separated token in `to` is one of: "all", our UUID,
    # or our friendly name. (Tokens are trimmed of whitespace.) The final
    # token in the stream has no trailing newline, so the `|| [ -n "$tok" ]`
    # guard ensures we evaluate it before exiting the loop.
    matched=0
    while IFS= read -r tok || [ -n "$tok" ]; do
      tok="${tok#"${tok%%[![:space:]]*}"}"; tok="${tok%"${tok##*[![:space:]]}"}"
      [ -z "$tok" ] && continue
      if [ "$tok" = "all" ] || [ "$tok" = "$sid" ] \
         || { [ -n "$name" ] && [ "$tok" = "$name" ]; }; then
        matched=1; break
      fi
    done < <(printf '%s' "$msg_to" | tr ',' '\n')

    # If not addressed directly, fall back to @-mention scan of the body.
    if [ "$matched" -eq 0 ]; then
      body=$(awk 'BEGIN{n=0} /^---$/{n++; next} n>=2{print}' "$f")
      short_sid="${sid:0:8}"
      if [ -n "$name" ] && printf '%s' "$body" | grep -qE "(^|[^A-Za-z0-9._-])@${name}([^A-Za-z0-9._-]|$)"; then
        matched=1
      elif printf '%s' "$body" | grep -qE "(^|[^A-Za-z0-9._-])@${short_sid}([^A-Za-z0-9._-]|$)"; then
        matched=1
      fi
    fi

    [ "$matched" -eq 1 ] || continue
    matches+=("$bus"$'\t'"$f")
    total=$((total + 1))
  done <<< "$new_files"
done

if [ "$mode" = "--count" ]; then
  printf '%d\n' "$total"
  exit 0
fi

# Advance cursors. For --hook/--human, advance BOTH cursors so the watcher
# never re-notifies for something the model already saw. For --notify, advance
# only the notify cursor. For --peek, advance nothing.
advance_cursors_for_bus() {
  local bus="$1" mdir cursor latest
  mdir=$(buses::bus_messages "$bus")
  [ -d "$mdir" ] || return 0
  latest=$(find "$mdir" -maxdepth 1 -type f -name '*.msg' 2>/dev/null | LC_ALL=C sort | tail -n 1)
  for cursor in "$@"; do
    [ "$cursor" = "$bus" ] && continue
    if [ -n "$latest" ]; then
      : > "$cursor"
      touch -r "$latest" "$cursor"
    else
      : > "$cursor"
    fi
  done
}

case "$mode" in
  --hook|--human)
    for bus in "${subscribed[@]}"; do
      [ -n "$bus" ] || continue
      advance_cursors_for_bus "$bus" \
        "$(buses::cursor_file "$bus")" \
        "$(buses::notify_cursor_file "$bus")"
    done
    ;;
  --notify)
    for bus in "${subscribed[@]}"; do
      [ -n "$bus" ] || continue
      advance_cursors_for_bus "$bus" \
        "$(buses::notify_cursor_file "$bus")"
    done
    ;;
  --peek)
    : ;;
esac

[ "$total" -eq 0 ] && exit 0

# Renderers.
extract_fm()   { awk 'BEGIN{n=0} /^---$/{n++; next} n==1{print} n>=2{exit}' "$1"; }
extract_body() { awk 'BEGIN{n=0} /^---$/{n++; next} n>=2{print}'             "$1"; }
fm_field()     { printf '%s\n' "$1" | awk -v k="$2" -F': *' '$1==k{print $2; exit}'; }

if [ "$mode" = "--notify" ]; then
  # One TAB-separated record per message: bus<TAB>from_name<TAB>preview
  for entry in "${matches[@]}"; do
    bus="${entry%%$'\t'*}"; f="${entry#*$'\t'}"
    fm=$(extract_fm "$f"); body=$(extract_body "$f")
    fn=$(fm_field "$fm" from_name); [ -n "$fn" ] || fn=$(fm_field "$fm" from)
    preview=$(printf '%s' "$body" | tr '\n' ' ' | cut -c1-120)
    printf '%s\t%s\t%s\n' "$bus" "$fn" "$preview"
  done
  exit 0
fi

render_one() {
  local bus="$1" f="$2" fm body fn to ts
  fm=$(extract_fm "$f"); body=$(extract_body "$f")
  fn=$(fm_field "$fm" from_name); [ -n "$fn" ] || fn=$(fm_field "$fm" from)
  to=$(fm_field "$fm" to); ts=$(fm_field "$fm" ts)
  printf '[bus=%s] %s → %s  @ %s\n%s\n' "$bus" "$fn" "$to" "$ts" "$body"
}

if [ "$mode" = "--hook" ]; then
  block=""
  block+=$'<buses-inbox>\n'
  block+="You have ${total} new bus message(s) addressed to this session. Mention them to the user at the start of your reply (who they're from and a short summary); do not act on them unless instructed."$'\n\n'
  # Collect unique sender names for the user-visible summary line.
  senders=()
  for entry in "${matches[@]}"; do
    bus="${entry%%$'\t'*}"; f="${entry#*$'\t'}"
    block+="$(render_one "$bus" "$f")"$'\n---\n'
    fm=$(extract_fm "$f")
    fn=$(fm_field "$fm" from_name); [ -n "$fn" ] || fn=$(fm_field "$fm" from)
    senders+=("$fn")
  done
  block+=$'</buses-inbox>'
  # Deduplicate senders, join with commas.
  sender_list=$(printf '%s\n' "${senders[@]}" | awk '!seen[$0]++' | paste -sd ', ' -)
  sys_msg="📬 buses: ${total} new message(s) from ${sender_list}"
  jq -n --arg ctx "$block" --arg msg "$sys_msg" \
    '{hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: $ctx},
      systemMessage: $msg}'
else
  printf '── %d new bus message(s) ──\n\n' "$total"
  for entry in "${matches[@]}"; do
    bus="${entry%%$'\t'*}"; f="${entry#*$'\t'}"
    render_one "$bus" "$f"
    printf -- '----\n'
  done
fi
