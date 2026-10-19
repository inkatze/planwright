#!/bin/sh
# fleet-messaging.sh — the one enforcement point for the fleet's peer-messaging
# transport (doctrine/messaging-transport.md). Every script-side messaging check
# and post goes through here: the per-session availability probe, the rung's
# messaging eligibility, the discipline oracle, the tower-to-worker send, the
# store re-read an idle notice drives, and the session's self-registration.
# Nothing here is a state of record: a message is a signal, and the attention
# store and worker registry stay the record.
#
# Usage:
#   fleet-messaging.sh probe [--cli-version <v>] [--owner-uid <uid>] [--socket-type <socket|other>]
#       Print `available` (exit 0) when all four conjuncts hold, else `absent`
#       (exit 1) with the failing conjunct on stderr:
#         1. CLAUDE_CODE_MESSAGING_SOCKET names an existing socket owned by
#            the invoking user (the `socket-ok` predicate);
#         2. the CLI version, compared numerically per dotted component, is
#            at or above PROBE_MIN_VERSION;
#         3. the session's effective crossSessionInbound is `accept`:
#            PLANWRIGHT_MESSAGING_INBOUND (the `--settings` command-line layer
#            a fleet launch seam exports) when set, else the CLI settings
#            files, local over project over user;
#         4. messaging_discipline resolves to a ladder value; `off` (the
#            per-fleet kill switch) and an unknown value read absent.
#   fleet-messaging.sh eligible <rung> --launch <bare|normal>
#       Print `eligible` (exit 0) or `ineligible` (exit 1): a rung whose
#       advertised Session-grade is `yes`, launched non-`--bare`, can bind an
#       inbox socket; `no`, `deferred`, and an unreadable or malformed
#       advertisement cannot. An unknown rung is refused (exit 2).
#   fleet-messaging.sh effective-mode --direction <worker-to-tower|tower-to-worker|tower-to-tower>
#       Print the discipline value a send in that direction runs at:
#       max(script, knob - direction offset - pressure demotion), the
#       tower-to-worker offset being one and the pressure demotion one while
#       the usage gate's rung is at or above reduce-concurrency. One stderr
#       notice when pressure demoted the value. A knob at `off` is refused
#       (exit 3): it sits outside the ladder, so no offset applies to it. A
#       knob or a usage-gate rung that cannot be resolved is refused (exit 4),
#       never read as no pressure.
#   fleet-messaging.sh send (--to <socket path> | --to-worker <worker>) --message-file <path>
#           [--cli-version <v>] [--owner-uid <uid>] [--socket-type <socket|other>]
#       Post the file's text to a worker's inbox as data, the tower-to-worker
#       direction only. Needs the sender's probe available and a target that
#       passes `socket-ok`; --to-worker resolves the registry's `inbox`
#       basename for that worker against the sender's own socket directory.
#       The frame carries a minted message id and the sender's own socket as
#       its reply address, and no auth line. Prints the message id for every
#       post written and accepted or held.
#   fleet-messaging.sh notice-read <session name>
#       Screen a session name read from an idle notice, match it against the
#       registry's `name` column, and print that worker's attention row
#       (fleet-attention.sh render --worker). The name is only a match key:
#       it reaches output solely sanitized, in a refusal diagnostic, and
#       nothing else from the notice is read. Exit 2 on a refusal (the name
#       fails the screen, matches no row or several, or the registry is
#       unreadable); a matched worker with no attention row prints nothing.
#   fleet-messaging.sh self-name
#       Print this session's observed name from its per-session record. Exit
#       1 when CLAUDE_PID names no record, or the record does not parse,
#       carries no name, or carries one failing the session-name screen.
#   fleet-messaging.sh self-register
#       From a worker session's own SessionStart hook: record its observed
#       name and inbox socket basename in its registry row through
#       `fleet-register.sh --amend`, which drops a value the registry's
#       grammar refuses and still writes the other. A session without the worker identity
#       environment (a tower) writes nothing. Exit 0 with one stderr notice
#       when CLAUDE_PID names no record; exit 2 on a malformed handle or a
#       record whose name or socket path fails its screen; otherwise the
#       amend's own exit.
#   fleet-messaging.sh socket-ok <path> [--owner-uid <uid>] [--socket-type <socket|other>]
#       Exit 0 when <path> is a local socket path (absolute, only
#       A-Za-z0-9._/- characters, no `..` segment or `//`, within the
#       107-byte socket address bound) naming an existing socket, not a
#       symlink, owned by the invoking user, else 1.
#
# Test-only seams, each refused unless PLANWRIGHT_TEST_SEAM=1: --cli-version
# (the version the probe compares), --owner-uid and --socket-type (what the
# predicate observes), and PLANWRIGHT_MESSAGING_POST, an executable invoked in
# place of the real post with the real post's argv and the frame on stdin,
# which prints the outcome line or nothing and exits with the write result.
#
# Send exit codes: 0 accepted (an empty response with a successful write
# counts as accepted, never as delivered); 2 usage or a refused input;
# 3 refused by the receiver; 4 the post failed or answered with an unknown
# line; 5 held at the receiver, which keeps it queued (never re-send it);
# 6 a precondition unmet (probe absent, target unaddressable or failing the
# predicate, or no iconv to check the body), nothing posted.
#
# POSIX sh on the macOS + Linux support bar. Every settings and session-record
# read is awk; no jq, no eval. All input is data; anything a message, notice,
# or session record carries is sanitized before it is echoed. A variable
# holding such a value is named `md_*`: the test suite's echo audit finds
# unsanitized sites by that prefix, so a new one keeps it.
set -uf

LC_ALL=C
export LC_ALL
unset CDPATH

me=fleet-messaging

script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2
if [ ! -f "$script_dir/echo-safety.sh" ] || [ ! -r "$script_dir/echo-safety.sh" ]; then
  printf '%s\n' "$me: echo-safety.sh is missing or unreadable (broken install)" >&2
  exit 2
fi
# shellcheck source=scripts/echo-safety.sh
. "$script_dir/echo-safety.sh"

FS="$script_dir/fleet-state.sh"
FR="$script_dir/fleet-register.sh"
FA="$script_dir/fleet-attention.sh"
OB="$script_dir/orchestrate-backends.sh"
RCK="$script_dir/resolve-config-knob.sh"
UG="$script_dir/fleet-usage-gate.sh"

# The documented messaging minimum's stricter arm, applied on every host so no
# provider detection is needed. The drift guard freezes this value.
PROBE_MIN_VERSION=2.1.248
# The bound a socket path must fit: sun_path holds 108 bytes with its NUL.
SOCKET_PATH_MAX=107
# Settings files and session records are small; anything larger is refused
# before the character-walking parse rather than walked.
JSON_MAX_BYTES=1048576
# Every value read from those files is a short screened token; a longer one is
# never decoded.
JSON_VALUE_MAX=4096
MESSAGE_MAX_BYTES=65536

TAB=$(printf '\t')

die_usage() {
  printf '%s\n' "$me: $1" >&2
  exit 2
}

# --- test-only seams ---------------------------------------------------------

SEAM_CLI_VERSION=""
SEAM_CLI_VERSION_SET=0
SEAM_OWNER_UID=""
SEAM_SOCKET_TYPE=""

seam_guard() {
  [ "${PLANWRIGHT_TEST_SEAM:-}" = 1 ] && return 0
  printf '%s\n' "$me: refusing the test-only seam $1: it is honored only with PLANWRIGHT_TEST_SEAM=1" >&2
  exit 2
}

# take_seam <flag> <value> — record one seam flag's value, refused outside tests.
take_seam() {
  seam_guard "$1"
  case $1 in
    --cli-version)
      SEAM_CLI_VERSION=$2
      SEAM_CLI_VERSION_SET=1
      ;;
    --owner-uid)
      case $2 in
        "" | *[!0-9]*) die_usage "--owner-uid takes a numeric uid" ;;
      esac
      SEAM_OWNER_UID=$2
      ;;
    --socket-type)
      case $2 in
        socket | other) ;;
        *) die_usage "--socket-type takes socket or other" ;;
      esac
      SEAM_SOCKET_TYPE=$2
      ;;
  esac
}

# --- grammars ----------------------------------------------------------------

# The registry's worker field grammar, byte-identical to fleet-state.sh.
valid_field() {
  vf_v=$1
  case $vf_v in
    "" | . | .. | *[!A-Za-z0-9._=@:-]*) return 1 ;;
  esac
  [ "${#vf_v}" -le 128 ]
}

# The session-name screen: printable ASCII, no path separator, 1 to 128 bytes.
# It is a path-safe screen of its own, not the relay's handle grammar: a
# session name is whatever the harness recorded, so it admits spaces and
# punctuation the handle grammar refuses, and refuses any separator a name
# would need to escape a path.
valid_session_name() {
  vs_v=$1
  [ -n "$vs_v" ] || return 1
  [ "${#vs_v}" -le 128 ] || return 1
  case $vs_v in
    */* | *\\*) return 1 ;;
  esac
  case $vs_v in
    *[!\ -~]*) return 1 ;;
  esac
  return 0
}

# An inbox socket basename as the registry holds it: no separator, no dot-run.
valid_inbox() {
  vi_v=$1
  case $vi_v in
    "" | . | .. | *[!A-Za-z0-9._-]*) return 1 ;;
  esac
  [ "${#vi_v}" -le 128 ]
}

# A local socket path: absolute, a conservative charset, no `..` segment, and
# within the socket address bound. A host-qualified or URL-shaped target has a
# `:` and fails here, so every script post is same-machine by construction.
valid_socket_path() {
  vp_v=$1
  case $vp_v in
    /*) ;;
    *) return 1 ;;
  esac
  case $vp_v in
    *[!A-Za-z0-9._/-]* | */../* | */.. | *//*) return 1 ;;
  esac
  [ "${#vp_v}" -le "$SOCKET_PATH_MAX" ]
}

# A CLI version: exactly three dotted numeric components, each 1 to 9 digits.
valid_version() {
  vv_v=$1
  case $vv_v in
    "" | *[!0-9.]* | .* | *. | *..*) return 1 ;;
  esac
  vv_rest=${vv_v#*.}
  vv_rest=${vv_rest#*.}
  case $vv_rest in
    *.*) return 1 ;;
  esac
  [ "$vv_rest" != "$vv_v" ] || return 1
  printf '%s\n' "$vv_v" | awk -F. 'NF == 3 && length($1) <= 9 && length($2) <= 9 && length($3) <= 9 { ok = 1 } END { exit !ok }'
}

# version_at_least <have> <min> — numeric per dotted component.
version_at_least() {
  awk -v a="$1" -v b="$2" 'BEGIN {
    split(a, x, "."); split(b, y, ".")
    for (i = 1; i <= 3; i++) {
      if (x[i] + 0 > y[i] + 0) exit 0
      if (x[i] + 0 < y[i] + 0) exit 1
    }
    exit 0
  }'
}

# --- the socket owner/existence predicate -----------------------------------

socket_ok() {
  so_p=$1
  valid_socket_path "$so_p" || return 1
  [ ! -L "$so_p" ] || return 1
  [ -e "$so_p" ] || return 1
  if [ -n "$SEAM_SOCKET_TYPE" ]; then
    [ "$SEAM_SOCKET_TYPE" = socket ] || return 1
  else
    [ -S "$so_p" ] || return 1
  fi
  if [ -n "$SEAM_OWNER_UID" ]; then
    so_owner=$SEAM_OWNER_UID
  else
    # ls -n is the owner read both GNU and BSD userlands share; stat's flags
    # differ between them.
    # shellcheck disable=SC2012
    so_owner=$(ls -lnd "$so_p" 2>/dev/null | awk '{ print $3 }') || return 1
  fi
  so_me=$(id -u) || return 1
  [ -n "$so_owner" ] && [ "$so_owner" = "$so_me" ]
}

# --- JSON top-level string read (awk, no jq) ---------------------------------

# json_top_string <file> <key> — print the value of a top-level string key.
# Exit 0 found, 1 absent, 3 the file fails the walk's structural checks (one
# top-level object, balanced brackets, closed strings, known escapes; it is
# not a full JSON validator) or the key holds a non-string value: the caller
# reads 3 as a parse failure. A \u escape
# decodes to a control byte, so a value carrying one fails every screen here.
json_top_string() {
  jt_size=$(wc -c <"$1" 2>/dev/null) || return 3
  jt_size=$(printf '%s' "$jt_size" | tr -d ' ')
  case $jt_size in
    "" | *[!0-9]*) return 3 ;;
  esac
  [ "$jt_size" -le "$JSON_MAX_BYTES" ] || return 3
  # The walk stays linear in the file size, so the cap above is a time bound
  # too: awk copies a string it grows, so the file is read as one record (a
  # raw \001 never appears in valid JSON; a second record is a parse failure)
  # and a string is only located while walking. It is decoded, a character at
  # a time, only where it matters and only while short: a key whose raw form
  # could still equal the wanted one, and the wanted value up to
  # JSON_VALUE_MAX bytes, a longer one reading as a control byte that fails
  # every screen.
  awk -v key="$2" -v vmax="$JSON_VALUE_MAX" '
    function dec(t,   o, p, m, ch, e) {
      o = ""; m = length(t)
      for (p = 1; p <= m; p++) {
        ch = substr(t, p, 1)
        if (ch != "\\") { o = o ch; continue }
        e = substr(t, ++p, 1)
        if (e == "n") o = o "\n"
        else if (e == "t") o = o "\t"
        else if (e == "r") o = o "\r"
        else if (e == "b") o = o "\b"
        else if (e == "f") o = o "\f"
        else if (e == "u") { o = o "\001"; p += 4 }
        else o = o e
      }
      return o
    }
    BEGIN { RS = "\001" }
    NR == 1 { s = $0 }
    NR > 1 { multi = 1 }
    END {
      n = length(s); i = 1; depth = 0; started = 0; bad = multi
      found = 0; val = ""; want = 0
      while (!bad && i <= n) {
        c = substr(s, i, 1)
        if (c == "\"") {
          if (!started) { bad = 1; break }
          j = i + 1; escaped = 0; closed = 0
          while (j <= n) {
            d = substr(s, j, 1)
            if (d == "\\") {
              e = substr(s, j + 1, 1)
              if (e == "u") j += 6
              else if (e != "" && index("\"\\/ntrbf", e)) j += 2
              else { bad = 1; break }
              escaped = 1
              continue
            }
            if (d == "\"") { closed = 1; break }
            j++
          }
          if (bad || !closed || j > n) { bad = 1; break }
          raw = substr(s, i + 1, j - i - 1)
          i = j + 1
          if (want) {
            if (length(raw) > vmax + 0) val = "\001"
            else val = escaped ? dec(raw) : raw
            found = 1; want = 0
            continue
          }
          if (depth == 1) {
            k = i
            while (k <= n && substr(s, k, 1) ~ /[ \t\r\n]/) k++
            str = raw
            if (escaped) str = (length(raw) <= 6 * length(key)) ? dec(raw) : ""
            if (substr(s, k, 1) == ":" && str == key) {
              k++
              while (k <= n && substr(s, k, 1) ~ /[ \t\r\n]/) k++
              if (substr(s, k, 1) == "\"") { want = 1; i = k; continue }
              found = 2; val = ""
            }
          }
          continue
        }
        if (c ~ /[ \t\r\n]/) { i++; continue }
        if (!started) {
          if (c != "{") { bad = 1; break }
          started = 1
        } else if (depth == 0) { bad = 1; break }
        if (c == "{" || c == "[") depth++
        else if (c == "}" || c == "]") { depth--; if (depth < 0) { bad = 1; break } }
        i++
      }
      if (!bad && (depth != 0 || !started)) bad = 1
      if (bad || found == 2) exit 3
      if (found == 1) { printf "%s", val; exit 0 }
      exit 1
    }' "$1"
}

# --- the probe ---------------------------------------------------------------

# inbound_value — the effective crossSessionInbound, or empty for none.
# Returns 3 on a settings file that does not parse.
inbound_value() {
  if [ -n "${PLANWRIGHT_MESSAGING_INBOUND:-}" ]; then
    printf '%s' "$PLANWRIGHT_MESSAGING_INBOUND"
    return 0
  fi
  iv_user_dir=${CLAUDE_CONFIG_DIR:-${HOME:-}/.claude}
  iv_val=""
  for iv_f in "$iv_user_dir/settings.json" "$PWD/.claude/settings.json" "$PWD/.claude/settings.local.json"; do
    [ -e "$iv_f" ] || continue
    [ -f "$iv_f" ] && [ -r "$iv_f" ] || return 3
    iv_rc=0
    iv_got=$(json_top_string "$iv_f" crossSessionInbound) || iv_rc=$?
    case $iv_rc in
      0) iv_val=$iv_got ;;
      1) ;;
      *) return 3 ;;
    esac
  done
  printf '%s' "$iv_val"
}

# discipline_knob — the resolved messaging_discipline, any overlay malformation
# a non-zero return (the resolver names the knob on stderr).
discipline_knob() {
  "$RCK" --key messaging_discipline --type enum --values 'off script tiered open' --no-degrade
}

# probe_reason — empty when available, else the failing conjunct.
probe_reason() {
  pr_sock=${CLAUDE_CODE_MESSAGING_SOCKET:-}
  if [ -z "$pr_sock" ]; then
    printf 'CLAUDE_CODE_MESSAGING_SOCKET is unset'
    return 0
  fi
  if ! socket_ok "$pr_sock"; then
    printf 'CLAUDE_CODE_MESSAGING_SOCKET does not name an existing socket owned by this user'
    return 0
  fi
  if [ "$SEAM_CLI_VERSION_SET" = 1 ]; then
    pr_ver=$SEAM_CLI_VERSION
  else
    pr_ver=$(claude --version 2>/dev/null | awk 'NR == 1 { print $1 }') || pr_ver=""
  fi
  if ! valid_version "$pr_ver"; then
    printf 'the CLI version is unreadable'
    return 0
  fi
  if ! version_at_least "$pr_ver" "$PROBE_MIN_VERSION"; then
    printf 'the CLI version is below %s' "$PROBE_MIN_VERSION"
    return 0
  fi
  pr_rc=0
  pr_in=$(inbound_value) || pr_rc=$?
  if [ "$pr_rc" != 0 ]; then
    printf 'a settings file does not parse, so crossSessionInbound is unknown'
    return 0
  fi
  if [ "$pr_in" != accept ]; then
    printf 'crossSessionInbound does not resolve to accept'
    return 0
  fi
  pr_knob=$(discipline_knob 2>/dev/null) || pr_knob=""
  case $pr_knob in
    script | tiered | open) ;;
    off)
      printf 'messaging_discipline is off, the kill switch'
      return 0
      ;;
    *)
      printf 'messaging_discipline does not resolve to a known value'
      return 0
      ;;
  esac
  return 0
}

# --- the post ----------------------------------------------------------------

frame_tmp=""
trap '[ -z "$frame_tmp" ] || rm -f "$frame_tmp"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

mint_id() {
  mi_hex=$(od -An -N16 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n')
  case $mi_hex in
    *[!0-9a-f]* | "") return 1 ;;
  esac
  [ "${#mi_hex}" -eq 32 ] || return 1
  printf '%s\n' "$mi_hex" | awk '{
    v = substr($0, 17, 1)
    n = index("0123456789abcdef", v) - 1
    v = substr("89ab", (n % 4) + 1, 1)
    printf "%s-%s-4%s-%s%s-%s", substr($0, 1, 8), substr($0, 9, 4), substr($0, 14, 3), v, substr($0, 18, 3), substr($0, 21, 12)
  }'
}

# write_frame <message-file> <reply-socket> <id> — the inbox's JSON line on
# stdout, the body escaped as a JSON string and never interpreted.
write_frame() {
  awk -v from="uds:$2" -v id="$3" '
    function esc(t,   o, i, n, c) {
      o = ""
      n = length(t)
      for (i = 1; i <= n; i++) {
        c = substr(t, i, 1)
        if (c == "\\") o = o "\\\\"
        else if (c == "\"") o = o "\\\""
        else if (c in ctl) o = o ctl[c]
        else o = o c
      }
      return o
    }
    BEGIN {
      for (i = 1; i < 32; i++) ctl[sprintf("%c", i)] = sprintf("\\u%04x", i)
      ctl[sprintf("%c", 127)] = "\\u007f"
      ctl["\n"] = "\\n"
      ctl["\t"] = "\\t"
      ctl["\r"] = "\\r"
    }
    { b = b (NR > 1 ? "\n" : "") $0 }
    END {
      printf "{\"type\":\"user\",\"message\":{\"role\":\"user\",\"content\":\"%s\"},\"from\":\"%s\",\"msg_id\":\"%s\"}\n", esc(b), esc(from), id
    }' "$1"
}

# post_frame <target> <frame-file> — sets po_out (first response line) and
# po_rc (the write result).
post_frame() {
  po_out=""
  po_rc=0
  if [ -n "${PLANWRIGHT_MESSAGING_POST:-}" ]; then
    po_out=$("$PLANWRIGHT_MESSAGING_POST" nc -N -w 5 -U "$1" <"$2") || po_rc=$?
  else
    if ! command -v nc >/dev/null 2>&1; then
      po_rc=127
      return 0
    fi
    po_out=$(nc -N -w 5 -U "$1" <"$2" 2>/dev/null) || po_rc=$?
  fi
  po_out=$(printf '%s\n' "$po_out" | awk 'NR == 1 { print; exit }')
}

# worker_inbox <worker> — the worker's inbox basename from its last registry
# record, or a non-zero return with the reason on stderr.
worker_inbox() {
  wi_reg=$("$FS" registry 2>/dev/null) || {
    printf '%s\n' "$me: send: cannot read the worker registry" >&2
    return 1
  }
  wi_row=$(printf '%s\n' "$wi_reg" | awk -F "$TAB" -v w="$1" '($2 "") == (w "") { l = $0 } END { if (l != "") print l }')
  if [ -z "$wi_row" ]; then
    printf '%s\n' "$me: send: worker '$1' has no registry record" >&2
    return 1
  fi
  wi_box=$(printf '%s\n' "$wi_row" | awk -F "$TAB" '
    ($NF == "closed" && (NF == 8 || NF == 10)) { print "closed"; exit }
    NF >= 9 { print "=" $9; exit }
    { print "none" }')
  case $wi_box in
    closed)
      printf '%s\n' "$me: send: worker '$1' is retired in the registry" >&2
      return 1
      ;;
    =-)
      printf '%s\n' "$me: send: worker '$1' has recorded no inbox yet" >&2
      return 1
      ;;
    =*) wi_box=${wi_box#=} ;;
    *)
      printf '%s\n' "$me: send: worker '$1' has no inbox column in its registry record" >&2
      return 1
      ;;
  esac
  if ! valid_inbox "$wi_box"; then
    printf '%s\n' "$me: send: worker '$1' carries a malformed inbox basename in its registry record" >&2
    return 1
  fi
  printf '%s' "$wi_box"
}

cmd_send() {
  sd_to=""
  sd_worker=""
  sd_file=""
  while [ "$#" -gt 0 ]; do
    case $1 in
      --to | --to-worker | --message-file | --cli-version | --owner-uid | --socket-type) ;;
      *) die_usage "send: unknown flag '$(sanitize_printable "$1" "(unprintable flag)")'" ;;
    esac
    [ "$#" -ge 2 ] || die_usage "send: $1 needs a value"
    case $1 in
      --to)
        [ -z "$sd_to$sd_worker" ] || die_usage "send takes exactly one of --to and --to-worker"
        sd_to=$2
        ;;
      --to-worker)
        [ -z "$sd_to$sd_worker" ] || die_usage "send takes exactly one of --to and --to-worker"
        sd_worker=$2
        ;;
      --message-file) sd_file=$2 ;;
      --cli-version | --owner-uid | --socket-type) take_seam "$1" "$2" ;;
    esac
    shift 2
  done
  [ -n "$sd_to$sd_worker" ] || die_usage "send needs --to <socket path> or --to-worker <worker>"
  [ -n "$sd_file" ] || die_usage "send needs --message-file <path>"
  if [ -n "${PLANWRIGHT_MESSAGING_POST:-}" ]; then
    seam_guard PLANWRIGHT_MESSAGING_POST
  fi
  if [ -n "$sd_to" ] && ! valid_socket_path "$sd_to"; then
    die_usage "send: --to takes a local socket path (absolute, no host or URL form)"
  fi
  if [ -n "$sd_worker" ] && ! valid_field "$sd_worker"; then
    die_usage "send: --to-worker takes a registry worker handle"
  fi
  if [ ! -f "$sd_file" ] || [ ! -r "$sd_file" ] || [ -L "$sd_file" ]; then
    die_usage "send: --message-file must be a readable regular file"
  fi
  sd_size=$(wc -c <"$sd_file" | tr -d ' ')
  case $sd_size in
    "" | *[!0-9]* | 0) die_usage "send: the message file is empty or unreadable" ;;
  esac
  [ "$sd_size" -le "$MESSAGE_MAX_BYTES" ] || die_usage "send: the message file exceeds $MESSAGE_MAX_BYTES bytes"
  # The frame is a JSON string, which holds UTF-8 text and no NUL; awk passes
  # neither defect through faithfully, so the receiver would drop the frame
  # while the post still reads as written.
  sd_nonul=$(tr -d '\000' <"$sd_file" | wc -c | tr -d ' ')
  [ "$sd_nonul" = "$sd_size" ] || die_usage "send: the message file carries a NUL byte"
  if ! command -v iconv >/dev/null 2>&1; then
    printf '%s\n' "$me: send: iconv is missing, so the message cannot be checked as UTF-8 text; take the fallback" >&2
    exit 6
  fi
  iconv -f UTF-8 -t UTF-8 <"$sd_file" >/dev/null 2>&1 || die_usage "send: the message file is not UTF-8 text"

  sd_reason=$(probe_reason)
  if [ -n "$sd_reason" ]; then
    printf '%s\n' "$me: send: messaging is absent in this session ($sd_reason); take the fallback" >&2
    exit 6
  fi
  sd_own=$CLAUDE_CODE_MESSAGING_SOCKET
  if [ -n "$sd_worker" ]; then
    sd_box=$(worker_inbox "$sd_worker") || exit 6
    sd_to="${sd_own%/*}/$sd_box"
    if ! valid_socket_path "$sd_to"; then
      printf '%s\n' "$me: send: the resolved inbox path for '$sd_worker' is not a valid local socket path" >&2
      exit 6
    fi
  fi
  if ! socket_ok "$sd_to"; then
    printf '%s\n' "$me: send: the target is not an existing socket owned by this user; nothing posted" >&2
    exit 6
  fi
  sd_id=$(mint_id) || {
    printf '%s\n' "$me: send: could not mint a message id" >&2
    exit 4
  }
  frame_tmp=$(mktemp "${TMPDIR:-/tmp}/fleet-messaging.XXXXXX") || exit 4
  chmod 600 "$frame_tmp" || exit 4
  write_frame "$sd_file" "$sd_own" "$sd_id" >"$frame_tmp" || {
    printf '%s\n' "$me: send: could not build the message frame" >&2
    exit 4
  }
  post_frame "$sd_to" "$frame_tmp"
  md_outcome=$po_out
  if [ "$po_rc" != 0 ]; then
    printf '%s\n' "$me: send: the post failed (write exit $po_rc); take the next fallback" >&2
    exit 4
  fi
  case $md_outcome in
    "" | accepted)
      printf '%s\n' "$sd_id"
      exit 0
      ;;
    held)
      printf '%s\n' "$sd_id"
      printf '%s\n' "$me: send: message $sd_id is held at the receiver; it stays queued there and is never re-sent, and nothing confirms delivery" >&2
      exit 5
      ;;
    refused)
      printf '%s\n' "$me: send: the receiver refused message $sd_id; take the next fallback" >&2
      exit 3
      ;;
    *)
      printf '%s\n' "$me: send: the post answered with an unknown outcome '$(sanitize_printable "$md_outcome" "(unprintable)")'; treated as failed" >&2
      exit 4
      ;;
  esac
}

# --- the session's own record ------------------------------------------------

# session_record — the invoking session's per-session record path, or a
# non-zero return when CLAUDE_PID is unset, malformed, or names no record.
session_record() {
  sr_pid=${CLAUDE_PID:-}
  case $sr_pid in
    "" | *[!0-9]*) return 1 ;;
  esac
  sr_f="${CLAUDE_CONFIG_DIR:-${HOME:-}/.claude}/sessions/$sr_pid.json"
  [ -f "$sr_f" ] && [ -r "$sr_f" ] || return 1
  printf '%s' "$sr_f"
}

cmd_self_name() {
  [ "$#" -eq 0 ] || die_usage "self-name takes no arguments"
  sn_f=$(session_record) || {
    printf '%s\n' "$me: self-name: no per-session record for this session" >&2
    exit 1
  }
  sn_rc=0
  md_name=$(json_top_string "$sn_f" name) || sn_rc=$?
  case $sn_rc in
    0) ;;
    1)
      printf '%s\n' "$me: self-name: the per-session record carries no name" >&2
      exit 1
      ;;
    *)
      printf '%s\n' "$me: self-name: the per-session record does not parse" >&2
      exit 1
      ;;
  esac
  if ! valid_session_name "$md_name"; then
    printf '%s\n' "$me: self-name: the recorded name fails the session-name screen: '$(sanitize_printable "$md_name" "(unprintable)")'" >&2
    exit 1
  fi
  printf '%s\n' "$(sanitize_printable "$md_name")"
}

cmd_self_register() {
  [ "$#" -eq 0 ] || die_usage "self-register takes no arguments"
  sg_handle=${PLANWRIGHT_WORKER_HANDLE:-}
  if [ -z "$sg_handle" ] || [ -z "${PLANWRIGHT_WORKER_SCOPE:-}" ]; then
    exit 0
  fi
  if ! valid_field "$sg_handle"; then
    printf '%s\n' "$me: self-register: PLANWRIGHT_WORKER_HANDLE is not a registry worker handle; nothing recorded" >&2
    exit 2
  fi
  sg_f=$(session_record) || {
    printf '%s\n' "$me: self-register: no per-session record for CLAUDE_PID; the worker stays unaddressable and its delivery falls back" >&2
    exit 0
  }
  sg_rc=0
  md_name=$(json_top_string "$sg_f" name) || sg_rc=$?
  if [ "$sg_rc" != 0 ] || ! valid_session_name "$md_name"; then
    printf '%s\n' "$me: self-register: the per-session record's name is absent or fails the session-name screen; nothing recorded" >&2
    exit 2
  fi
  sg_rc=0
  md_sock=$(json_top_string "$sg_f" messagingSocketPath) || sg_rc=$?
  if [ "$sg_rc" != 0 ] || ! valid_socket_path "$md_sock"; then
    printf '%s\n' "$me: self-register: the per-session record carries no usable socket path; nothing recorded" >&2
    exit 2
  fi
  md_box=${md_sock##*/}
  if ! valid_inbox "$md_box"; then
    printf '%s\n' "$me: self-register: the socket basename fails the inbox screen; nothing recorded" >&2
    exit 2
  fi
  /bin/sh "$FR" --amend "$sg_handle" --name "$md_name" --inbox "$md_box"
}

# --- notice-read -------------------------------------------------------------

cmd_notice_read() {
  [ "$#" -eq 1 ] || die_usage "usage: fleet-messaging.sh notice-read <session name>"
  md_name=$1
  if ! valid_session_name "$md_name"; then
    printf '%s\n' "$me: notice-read: refusing a session name that fails the screen: '$(sanitize_printable "$md_name" "(unprintable)")'" >&2
    exit 2
  fi
  nr_reg=$("$FS" registry 2>/dev/null) || {
    printf '%s\n' "$me: notice-read: cannot read the worker registry" >&2
    exit 2
  }
  # The name reaches awk through the environment: a -v value is
  # escape-processed, and the screen admits a backslash-free but otherwise
  # free-form name.
  NR_NAME=$md_name
  export NR_NAME
  nr_match=$(printf '%s\n' "$nr_reg" | awk -F "$TAB" '
    NF >= 2 { last[$2] = $0; if (!($2 in seen)) { seen[$2] = 1; order[++n] = $2 } }
    END {
      for (i = 1; i <= n; i++) {
        nf = split(last[order[i]], f, "\t")
        if (f[nf] == "closed" && (nf == 8 || nf == 10)) continue
        # `-` is the sentinel a row holds until its session registers a name.
        if (nf >= 9 && f[8] != "-" && f[8] == ENVIRON["NR_NAME"]) { hits++; w = order[i] }
      }
      if (hits == 1) print "one\t" w
      else if (hits > 1) print "many"
      else print "none"
    }')
  case $nr_match in
    one"$TAB"*) nr_worker=${nr_match#one"$TAB"} ;;
    many)
      printf '%s\n' "$me: notice-read: refusing an ambiguous name: more than one registry row carries '$(sanitize_printable "$md_name" "(unprintable)")'" >&2
      exit 2
      ;;
    *)
      printf '%s\n' "$me: notice-read: no registry row carries the name '$(sanitize_printable "$md_name" "(unprintable)")'" >&2
      exit 2
      ;;
  esac
  if ! valid_field "$nr_worker"; then
    printf '%s\n' "$me: notice-read: the matching registry row carries a malformed worker handle" >&2
    exit 2
  fi
  "$FA" render --worker "$nr_worker"
}

# --- eligible ----------------------------------------------------------------

cmd_eligible() {
  el_rung=""
  el_launch=""
  while [ "$#" -gt 0 ]; do
    case $1 in
      --launch)
        [ "$#" -ge 2 ] || die_usage "eligible: --launch needs bare or normal"
        el_launch=$2
        shift 2
        ;;
      -*) die_usage "eligible: unknown flag '$(sanitize_printable "$1" "(unprintable flag)")'" ;;
      *)
        [ -z "$el_rung" ] || die_usage "usage: fleet-messaging.sh eligible <rung> --launch <bare|normal>"
        el_rung=$1
        shift
        ;;
    esac
  done
  [ -n "$el_rung" ] || die_usage "usage: fleet-messaging.sh eligible <rung> --launch <bare|normal>"
  case $el_launch in
    bare | normal) ;;
    *) die_usage "eligible: --launch takes bare or normal" ;;
  esac
  case $el_rung in
    "" | [!a-z0-9]* | *[!a-z0-9-]*) die_usage "eligible: refusing a malformed rung name '$(sanitize_printable "$el_rung" "(unprintable)")'" ;;
  esac
  [ "${#el_rung}" -le 64 ] || die_usage "eligible: refusing an over-length rung name"
  case $el_rung in
    tmux | stream-json-persistent | headless-oneshot | subagent | print | in-session) ;;
    *)
      command -v "planwright-backend-$el_rung" >/dev/null 2>&1 \
        || die_usage "eligible: unknown rung '$el_rung' (no shipped backend and no adapter)"
      ;;
  esac
  el_caps=$("$OB" caps "$el_rung" 2>/dev/null) || el_caps=""
  el_grade=$(printf '%s\n' "$el_caps" | awk 'NR == 1 { print $6 }')
  if [ "$el_grade" = yes ] && [ "$el_launch" = normal ]; then
    printf 'eligible\n'
    exit 0
  fi
  printf 'ineligible\n'
  exit 1
}

# --- effective-mode ----------------------------------------------------------

cmd_effective_mode() {
  em_dir=""
  while [ "$#" -gt 0 ]; do
    case $1 in
      --direction)
        [ "$#" -ge 2 ] || die_usage "effective-mode: --direction needs a value"
        em_dir=$2
        shift 2
        ;;
      *) die_usage "effective-mode: unknown argument '$(sanitize_printable "$1" "(unprintable)")'" ;;
    esac
  done
  case $em_dir in
    worker-to-tower | tower-to-tower) em_offset=0 ;;
    tower-to-worker) em_offset=1 ;;
    "") die_usage "effective-mode needs --direction <worker-to-tower|tower-to-worker|tower-to-tower>" ;;
    *) die_usage "effective-mode: unknown direction '$(sanitize_printable "$em_dir" "(unprintable)")' (worker-to-tower|tower-to-worker|tower-to-tower)" ;;
  esac
  em_knob=$(discipline_knob) || {
    printf '%s\n' "$me: effective-mode: messaging_discipline does not resolve; refusing" >&2
    exit 4
  }
  case $em_knob in
    script) em_level=0 ;;
    tiered) em_level=1 ;;
    open) em_level=2 ;;
    off)
      printf '%s\n' "$me: effective-mode: messaging_discipline is off, the switch value outside the ladder; no direction or pressure offset applies and no model-composed message is sent" >&2
      exit 3
      ;;
    *)
      printf '%s\n' "$me: effective-mode: messaging_discipline resolved to an unknown value; refusing" >&2
      exit 4
      ;;
  esac
  em_level=$((em_level - em_offset))
  [ "$em_level" -ge 0 ] || em_level=0
  em_rung=$("$UG" rung 2>/dev/null) || {
    printf '%s\n' "$me: effective-mode: the usage gate's rung cannot be read, so the pressure demotion is unknown; refusing" >&2
    exit 4
  }
  case $em_rung in
    reduce-concurrency | defer-heavy | defer-all)
      if [ "$em_level" -gt 0 ]; then
        em_level=$((em_level - 1))
        printf '%s\n' "$me: effective-mode: usage pressure (rung $em_rung) demotes this $em_dir send one value" >&2
      fi
      ;;
  esac
  case $em_level in
    0) printf 'script\n' ;;
    1) printf 'tiered\n' ;;
    *) printf 'open\n' ;;
  esac
}

# --- dispatch ----------------------------------------------------------------

cmd=${1:-}
[ -n "$cmd" ] || die_usage "usage: fleet-messaging.sh probe|eligible|effective-mode|send|notice-read|self-name|self-register|socket-ok [args]"
shift

case $cmd in
  probe)
    while [ "$#" -gt 0 ]; do
      case $1 in
        --cli-version | --owner-uid | --socket-type)
          [ "$#" -ge 2 ] || die_usage "probe: $1 needs a value"
          take_seam "$1" "$2"
          shift 2
          ;;
        *) die_usage "probe: unknown flag '$(sanitize_printable "$1" "(unprintable flag)")'" ;;
      esac
    done
    reason=$(probe_reason)
    if [ -z "$reason" ]; then
      printf 'available\n'
      exit 0
    fi
    printf 'absent\n'
    printf '%s\n' "$me: probe: absent: $reason" >&2
    exit 1
    ;;
  socket-ok)
    [ "$#" -ge 1 ] || die_usage "usage: fleet-messaging.sh socket-ok <path> [--owner-uid <uid>] [--socket-type <socket|other>]"
    so_target=$1
    shift
    while [ "$#" -gt 0 ]; do
      case $1 in
        --owner-uid | --socket-type)
          [ "$#" -ge 2 ] || die_usage "socket-ok: $1 needs a value"
          take_seam "$1" "$2"
          shift 2
          ;;
        *) die_usage "socket-ok: unknown flag '$(sanitize_printable "$1" "(unprintable flag)")'" ;;
      esac
    done
    socket_ok "$so_target"
    exit $?
    ;;
  eligible) cmd_eligible "$@" ;;
  effective-mode) cmd_effective_mode "$@" ;;
  send) cmd_send "$@" ;;
  notice-read) cmd_notice_read "$@" ;;
  self-name) cmd_self_name "$@" ;;
  self-register) cmd_self_register "$@" ;;
  *) die_usage "unknown command '$(sanitize_printable "$cmd" "(unprintable command)")' (probe|eligible|effective-mode|send|notice-read|self-name|self-register|socket-ok)" ;;
esac
