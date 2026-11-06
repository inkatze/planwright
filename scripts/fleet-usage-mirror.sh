#!/bin/sh
# fleet-usage-mirror.sh — writes the status-line usage mirror that
# fleet-usage-gate.sh reads, from the `rate_limits` fields Claude Code passes a
# statusLine command on stdin (code.claude.com/docs/en/statusline.md).
#
#   write                 write the mirror from stdin
#   statusline <command>  the same write, then run <command> on that stdin and
#                         pass its stdout and exit status through, so an
#                         operator's existing status line is unchanged
#
# The path comes from `fleet-usage-gate.sh mirror-path`; an empty
# PLANWRIGHT_USAGE_MIRROR disables the writer. A payload with no rate_limits
# writes nothing. The spend window is clamped to 100 (over the limit). Never
# fails: a status line must not blank because the mirror could not be written.
# POSIX sh. No eval, no jq.
set -u

LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" 2>/dev/null && pwd) || here=""
GATE="$here/fleet-usage-gate.sh"

# write_mirror: read the payload from stdin and write the mirror atomically.
# Returns non-zero on any failure; callers ignore it.
write_mirror() {
  wm_payload=$(head -c 65536 2>/dev/null) || return 1
  [ -x "$GATE" ] || return 1
  wm_path=$("$GATE" mirror-path 2>/dev/null) || return 1
  [ -n "$wm_path" ] || return 1
  wm_json=$(printf '%s\n' "$wm_payload" | awk '
    { doc = doc $0 " " }
    function window(rl, key, clamp,   obj, pct, rst) {
      if (!match(rl, "\"" key "\"[ ]*:[ ]*[{][^{}]*[}]")) return ""
      obj = substr(rl, RSTART, RLENGTH)
      if (!match(obj, /"used_percentage"[ ]*:[ ]*[0-9]+([.][0-9]+)?/)) return ""
      pct = substr(obj, RSTART, RLENGTH); sub(/^[^:]*:[ ]*/, "", pct)
      if (!match(obj, /"resets_at"[ ]*:[ ]*[0-9]+/)) return ""
      rst = substr(obj, RSTART, RLENGTH); sub(/^[^:]*:[ ]*/, "", rst)
      if (clamp && pct + 0 > 100) pct = 100
      return "\"" key "\":{\"used_percentage\":" pct ",\"resets_at\":" rst "}"
    }
    END {
      if (doc ~ /[\001-\010\013\014\016-\037\177]/) exit 1
      if (!match(doc, /"rate_limits"[ ]*:[ ]*[{]/)) exit 1
      rl = substr(doc, RSTART)
      n = 0
      for (i = 1; i <= 3; i++) {
        key = (i == 1) ? "five_hour" : (i == 2) ? "seven_day" : "spend_limit"
        w = window(rl, key, key == "spend_limit")
        if (w != "") out[++n] = w
      }
      if (n == 0) exit 1
      json = "{"
      for (i = 1; i <= n; i++) json = json (i > 1 ? "," : "") out[i]
      printf "%s}\n", json
    }') || return 1
  wm_dir=$(dirname "$wm_path")
  mkdir -p "$wm_dir" 2>/dev/null || return 1
  wm_tmp=$(mktemp "$wm_dir/.rate-limits.XXXXXX" 2>/dev/null) || return 1
  if printf '%s\n' "$wm_json" >"$wm_tmp" && mv -f "$wm_tmp" "$wm_path" 2>/dev/null; then
    return 0
  fi
  rm -f "$wm_tmp"
  return 1
}

cmd=${1:-}
case $cmd in
  write)
    [ "$#" -eq 1 ] || exit 0
    write_mirror >/dev/null 2>&1 || true
    exit 0
    ;;
  statusline)
    payload=$(head -c 65536 2>/dev/null) || payload=""
    printf '%s\n' "$payload" | write_mirror >/dev/null 2>&1 || true
    [ "$#" -ge 2 ] || exit 0
    printf '%s\n' "$payload" | sh -c "$2"
    exit $?
    ;;
  *)
    exit 0
    ;;
esac
