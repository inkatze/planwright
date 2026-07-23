#!/bin/sh
# resolve-dispatch-backend.sh — the dispatch-time `dispatch_backend` resolver
# (execution-backends Task 5; D-8, D-9; REQ-B1.1, REQ-B1.2, REQ-B1.3,
# REQ-B1.4, REQ-B1.5).
#
# This is the config half of the dispatch-time backend pick: it resolves WHICH
# value is configured (the per-spec override, else the global knob, through the
# four-layer config overlay) and hands the selection itself to the sibling
# `orchestrate-backends.sh select-unattended` (the advertisement half), adding
# the one attended wrinkle D-8 defines — the tmux-context ask, persisted
# spec-locally so stateless steps re-read the answer instead of re-asking.
#
# Subcommands:
#   resolve <spec-dir> [--attended --session <token>]
#       Print TSV rows on stdout:
#         configured<TAB><value><TAB><per-spec|global>
#         ask<TAB>tmux            (only when the tmux-context ask should be
#                                  surfaced to the operator THIS call)
#         backend<TAB><selected>
#       The configured value is the per-spec entry in the winning
#       `dispatch_backend_per_spec` inline map when it carries one for this
#       spec (the map is one flat config key: the highest-precedence layer
#       that sets it supplies the whole map, D-5 last-layer-wins), else the
#       global `dispatch_backend` value. The per-spec entry WINS over the
#       global value in every layer combination (REQ-B1.3): specificity beats
#       layer precedence across the two keys; an absent entry falls through.
#       Selection semantics (semantic `full-session` ladder walk vs explicit
#       literal honored-or-halted) live in the sibling — see its header.
#
#       The tmux-context ask (D-8): exactly when the run is --attended AND
#       $TMUX is set (the tower is itself inside a tmux session) AND the
#       configured value is the SEMANTIC `full-session` (a literal never
#       asks), the operator is asked once per tower session whether tmux joins
#       the candidate set. Non-blocking: this call emits the `ask` row, records
#       `asked <token>` in the spec-local ask-state, and resolves unattended
#       immediately; a later `answer yes` applies from the next resolve onward.
#       Re-asks are suppressed while the ask-state carries the SAME session
#       token; a new token (a new tower session) re-asks, superseding the old
#       session's answer. Outside tmux context, attended resolution is exactly
#       unattended. --attended requires --session (the token IS the run
#       boundary; a `--watch` loop is one run).
#
#   answer <spec-dir> --session <token> <yes|no>
#       Record the operator's tmux-context answer for that tower session in
#       the spec-local ask-state (atomic write; a symlink or non-regular file
#       at the path is refused, never written through).
#
# Ask-state: ${PLANWRIGHT_ORCH_STATE_DIR:-<spec-dir>/.orchestrate/markers}'s
# parent /tmux-ask — one line, `<asked|yes|no> <token>`, gitignored alongside
# the sibling runtime records (the orchestration-fleet REQ-B1.6 precedent).
# The write is best-effort on the resolve path (a failed record warns and the
# resolve proceeds unattended — the ask is non-blocking by design) and
# fail-closed on the answer path (the operator explicitly acted; a lost
# answer must not be silent).
#
# By-layer malformed policy (customization-overlay REQ-E1.4, mirroring
# resolve-config-knob.sh): a malformed repo-tracked value or map hard-fails
# (exit 4); a malformed adopter/machine-local value warns and degrades to the
# core default (the map: treated absent); a malformed core default is a broken
# install (exit 5).
#
# Operator-default only (REQ-B1.2): the interface admits NO per-task
# parameter — an extra positional is a usage error.
#
# Exit codes: 0 resolved (rows on stdout); 1 a state-write failure on the
# `answer` path (the ask-state dir is unwritable or occupied by a symlink);
# 2 usage / hostile input; 4 malformed repo-tracked overlay (hard-fail,
# propagated or raised); 5 broken install; 6 fail-closed halt — the explicitly
# configured backend is not advertised on the host (REQ-B1.5; the dispatching
# skill parks the unit to Awaiting input naming it). The `resolve` path
# additionally re-emits the selection sibling's exit status verbatim
# (`orchestrate-backends.sh select-unattended`), whose contract is the subset
# {0, 2, 6} for the values this resolver passes it; a nonzero from it always
# means the dispatch cannot proceed, and 6 is its fail-closed halt above.
#
# Portable POSIX sh + coreutils (bash 3.2 / BSD compatible): no eval, input
# treated as data only (REQ-K1.5). set -f: nothing here intends pathname
# expansion, and map/token parsing must never glob against the CWD.
set -uf

LC_ALL=C
export LC_ALL
unset CDPATH

script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2

# Echo discipline (doctrine/security-posture.md): refused tokens and config
# values are stripped of control bytes before any diagnostic.
# shellcheck source=scripts/echo-safety.sh
. "$script_dir/echo-safety.sh"

usage() {
  echo "usage: resolve-dispatch-backend.sh resolve <spec-dir> [--attended --session <token>] | answer <spec-dir> --session <token> <yes|no>" >&2
}

# The spec identifier grammar (anchored, <=64) — the spec-dir BASENAME is the
# per-spec map key and must pass before it is ever matched against map entries.
valid_spec() {
  case "$1" in
    '') return 1 ;;
    [!a-z0-9]*) return 1 ;;
    *[!a-z0-9-]*) return 1 ;;
  esac
  [ "${#1}" -le 64 ]
}

# A session token names a tower run: plain printable token charset, <=128.
valid_token() {
  case "$1" in
    '') return 1 ;;
    *[!A-Za-z0-9._:-]*) return 1 ;;
  esac
  [ "${#1}" -le 128 ]
}

# A configured backend value: the semantic `full-session`, or a name in the
# backend identifier charset (shipped names and pluggables share it; whether
# it is advertised is the sibling's call, REQ-B1.5).
valid_value() {
  [ "$1" = full-session ] && return 0
  case "$1" in
    '') return 1 ;;
    [!a-z0-9]*) return 1 ;;
    *[!a-z0-9-]*) return 1 ;;
  esac
  [ "${#1}" -le 64 ]
}

# The ask-state path: sibling of the runtime marker dir, so the same trusted
# operator/test knob relocates every spec-local runtime record consistently
# (the orchestrate-degrade.sh record_path convention). The filename is a
# constant literal — no token is interpolated into the path.
ask_path() {
  ap_markers="${PLANWRIGHT_ORCH_STATE_DIR:-$1/.orchestrate/markers}"
  ap_orch=$(dirname "$ap_markers")
  printf '%s/tmux-ask' "$ap_orch"
}

# write_ask <spec-dir> <status> <token> -> 0 written, 1 failure (diagnosed).
# Atomic temp+rename; a symlink or non-regular file at the path is refused,
# never written through (the runtime-record write-time hardening).
write_ask() {
  wa_file=$(ask_path "$1")
  wa_dir=$(dirname "$wa_file")
  # The path prefix is trusted (parent dir + PLANWRIGHT_ORCH_STATE_DIR) and the
  # basename is the constant literal `tmux-ask`, but the diagnostics pass it
  # through the sanitizer anyway, uniformly with every other echo in this file
  # (echo discipline; the caller-supplied $specdir basename is charset-checked
  # before we reach here, so no escape byte can arrive, but consistency beats a
  # case-by-case exemption).
  wa_show=$(sanitize_printable "$wa_file" "(unprintable path)")
  if ! mkdir -p "$wa_dir" 2>/dev/null; then
    printf '%s\n' "resolve-dispatch-backend: cannot create state dir $(sanitize_printable "$wa_dir" "(unprintable path)")" >&2
    return 1
  fi
  if [ -L "$wa_file" ]; then
    printf '%s\n' "resolve-dispatch-backend: refusing symlink at ask-state path $wa_show" >&2
    return 1
  fi
  if [ -e "$wa_file" ] && [ ! -f "$wa_file" ]; then
    printf '%s\n' "resolve-dispatch-backend: refusing non-regular file at ask-state path $wa_show" >&2
    return 1
  fi
  wa_tmp=$(mktemp "$wa_dir/.tmux-ask.XXXXXX") || {
    printf '%s\n' "resolve-dispatch-backend: cannot create a temp ask-state in $(sanitize_printable "$wa_dir" "(unprintable path)")" >&2
    return 1
  }
  if ! printf '%s %s\n' "$2" "$3" >"$wa_tmp"; then
    rm -f "$wa_tmp"
    echo "resolve-dispatch-backend: cannot write the ask-state" >&2
    return 1
  fi
  if ! mv -f "$wa_tmp" "$wa_file"; then
    rm -f "$wa_tmp"
    echo "resolve-dispatch-backend: cannot place the ask-state" >&2
    return 1
  fi
  return 0
}

# read_ask <spec-dir> -> sets ASK_STATUS/ASK_TOKEN and returns 0, or returns 1
# when there is no usable state (absent, non-regular — a symlink is ignored,
# never followed — or malformed, each with a warning where suspicious).
ASK_STATUS=''
ASK_TOKEN=''
read_ask() {
  ra_file=$(ask_path "$1")
  ra_show=$(sanitize_printable "$ra_file" "(unprintable path)")
  [ -e "$ra_file" ] || [ -L "$ra_file" ] || return 1
  if [ -L "$ra_file" ] || [ ! -f "$ra_file" ]; then
    printf '%s\n' "resolve-dispatch-backend: warning: ignoring non-regular ask-state at $ra_show" >&2
    return 1
  fi
  ra_line=''
  IFS= read -r ra_line <"$ra_file" || [ -n "$ra_line" ] || {
    printf '%s\n' "resolve-dispatch-backend: warning: ignoring empty ask-state at $ra_show" >&2
    return 1
  }
  # Bound and sanitize before parse (the record is local state, but the parse
  # is defensive all the same).
  if [ "${#ra_line}" -gt 256 ]; then
    printf '%s\n' "resolve-dispatch-backend: warning: ignoring overlong ask-state at $ra_show" >&2
    return 1
  fi
  ra_status=${ra_line%% *}
  ra_token=${ra_line#* }
  case "$ra_status" in
    asked | yes | no) ;;
    *)
      printf '%s\n' "resolve-dispatch-backend: warning: ignoring malformed ask-state: $(sanitize_printable "$ra_line" "(unprintable)")" >&2
      return 1
      ;;
  esac
  if [ "$ra_token" = "$ra_line" ] || ! valid_token "$ra_token"; then
    printf '%s\n' "resolve-dispatch-backend: warning: ignoring malformed ask-state token" >&2
    return 1
  fi
  ASK_STATUS=$ra_status
  ASK_TOKEN=$ra_token
  return 0
}

config_get="$script_dir/config-get.sh"
backends="$script_dir/orchestrate-backends.sh"

# read_key <key> -> sets KEY_LAYER/KEY_VALUE, returns config-get's exit code
# (0 resolved, 3 absent; 4 propagates the repo-tracked structural hard-fail).
KEY_LAYER=''
KEY_VALUE=''
TABC=$(printf '\t')
read_key() {
  rk_out=''
  rk_rc=0
  rk_out=$("$config_get" --explain "$1") || rk_rc=$?
  [ "$rk_rc" -eq 0 ] || return "$rk_rc"
  case "$rk_out" in
    *"$TABC"*) ;;
    *)
      echo "resolve-dispatch-backend: config-get --explain output is malformed (no layer/value separator) — broken install" >&2
      return 5
      ;;
  esac
  KEY_LAYER=${rk_out%%"$TABC"*}
  KEY_VALUE=${rk_out#*"$TABC"}
  return 0
}

# core_value <key> -> the key's value with every overlay layer neutralized
# (the resolve-config-knob.sh degrade target). Prints the value; exit 3 when
# core omits the key, other non-zero on a broken install.
core_value() {
  cv_scratch=$(mktemp -d) || return 5
  cv_rc=0
  cv_val=$(
    PLANWRIGHT_ADOPTER_OVERLAY="$cv_scratch/no-adopter" \
      PLANWRIGHT_REPO_ROOT="$cv_scratch" \
      PLANWRIGHT_LOCAL_CONFIG="" \
      "$config_get" "$1"
  ) || cv_rc=$?
  rm -rf "$cv_scratch"
  [ "$cv_rc" -eq 0 ] || return "$cv_rc"
  printf '%s\n' "$cv_val"
}

# map_entry <map-value> <spec> -> the spec's entry value. Parses the inline
# flow map `{k: v, k2: v2}` (or `{}`) strictly: every entry key must be a
# valid spec identifier and every value a valid backend value, else the WHOLE
# map is malformed (return 2) — a half-parseable shared map must not silently
# serve some specs and not others. Returns 1 when the map is well-formed but
# carries no entry for the spec. All parsing is data-only string handling.
map_entry() {
  me_raw=$1
  me_spec=$2
  # Trim surrounding whitespace.
  me_raw=$(printf '%s' "$me_raw" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
  case "$me_raw" in
    "{"*"}") ;;
    *) return 2 ;;
  esac
  me_body=${me_raw#\{}
  me_body=${me_body%\}}
  me_body=$(printf '%s' "$me_body" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
  # An empty (or whitespace-only) body is the empty map.
  case "$me_body" in
    *[![:space:]]*) ;;
    *) return 1 ;;
  esac
  # A nested brace or bracket inside the body is structure the flat inline map
  # does not admit.
  case "$me_body" in
    *"{"* | *"}"* | *"["* | *"]"*) return 2 ;;
  esac
  # A leading or trailing comma (an empty entry) is malformed — rejected
  # consistently whether or not whitespace pads it (me_body is trimmed above,
  # so `{a: x,}` and `{a: x, }` both reduce to a `,`-terminated body here).
  case "$me_body" in
    ,* | *,) return 2 ;;
  esac
  me_found=''
  me_seen=' '
  me_rest="$me_body"
  while :; do
    case "$me_rest" in
      *,*)
        me_ent=${me_rest%%,*}
        me_rest=${me_rest#*,}
        ;;
      *)
        me_ent=$me_rest
        me_rest=''
        ;;
    esac
    me_ent=$(printf '%s' "$me_ent" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    case "$me_ent" in
      *:*) ;;
      *) return 2 ;;
    esac
    me_k=${me_ent%%:*}
    me_v=${me_ent#*:}
    me_k=$(printf '%s' "$me_k" | sed -e 's/[[:space:]]*$//' -e 's/^"\(.*\)"$/\1/' -e "s/^'\(.*\)'\$/\1/")
    me_v=$(printf '%s' "$me_v" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/^"\(.*\)"$/\1/' -e "s/^'\(.*\)'\$/\1/")
    valid_spec "$me_k" || return 2
    valid_value "$me_v" || return 2
    # A duplicate key makes the whole map ambiguous — reject it rather than
    # silently last-wins (the key charset excludes spaces, so a space-delimited
    # seen-set is collision-free).
    case "$me_seen" in
      *" $me_k "*) return 2 ;;
    esac
    me_seen="$me_seen$me_k "
    [ "$me_k" = "$me_spec" ] && me_found=$me_v
    [ -n "$me_rest" ] || break
  done
  if [ -n "$me_found" ]; then
    printf '%s\n' "$me_found"
    return 0
  fi
  return 1
}

# malformed_by_layer <key> <layer> <what> -> apply the REQ-E1.4 policy for a
# malformed winning value. Exits 4 (repo-tracked) / 5 (core) directly; for
# adopter/machine-local it warns and returns 0 — the caller then degrades to
# the core default.
malformed_by_layer() {
  case "$2" in
    repo-tracked)
      printf '%s\n' "resolve-dispatch-backend: repo-tracked overlay sets '$1' to a malformed $3; refusing to silently degrade a shared team value" >&2
      exit 4
      ;;
    adopter | machine-local)
      printf '%s\n' "resolve-dispatch-backend: warning: the $2 overlay sets '$1' to a malformed $3; degrading to the core default" >&2
      return 0
      ;;
    core)
      printf '%s\n' "resolve-dispatch-backend: the core default for '$1' is malformed ($3) — broken install" >&2
      exit 5
      ;;
    *)
      printf '%s\n' "resolve-dispatch-backend: config-get named an unrecognized layer '$(sanitize_printable "$2" "(unprintable layer)")'" >&2
      exit 5
      ;;
  esac
}

# ---------------------------------------------------------------------------

for helper in "$config_get" "$backends"; do
  if [ ! -x "$helper" ]; then
    echo "resolve-dispatch-backend: helper '$helper' is missing or not executable — broken install" >&2
    exit 5
  fi
done

sub=${1-}
[ "$#" -gt 0 ] && shift
case "$sub" in
  resolve | answer) ;;
  *)
    usage
    exit 2
    ;;
esac

specdir=${1-}
if [ -z "$specdir" ] || [ ! -d "$specdir" ]; then
  printf '%s\n' "resolve-dispatch-backend: no such spec dir: $(sanitize_printable "${specdir:-(missing)}" "(unprintable path)")" >&2
  exit 2
fi
shift
spec=$(basename "$specdir")
if ! valid_spec "$spec"; then
  printf '%s\n' "resolve-dispatch-backend: invalid spec identifier: $(sanitize_printable "$spec" "(unprintable)")" >&2
  exit 2
fi

attended=0
session=''
answer_val=''
while [ "$#" -gt 0 ]; do
  case "$1" in
    --attended)
      attended=1
      shift
      ;;
    --session)
      [ "$#" -ge 2 ] || {
        usage
        exit 2
      }
      session=$2
      shift 2
      ;;
    yes | no)
      # Only the answer subcommand takes a positional verdict.
      if [ "$sub" != answer ] || [ -n "$answer_val" ]; then
        usage
        exit 2
      fi
      answer_val=$1
      shift
      ;;
    *)
      # No other positional exists — in particular, NO per-task parameter
      # (REQ-B1.2: backend selection is operator policy, never per-task).
      usage
      exit 2
      ;;
  esac
done
if [ -n "$session" ] && ! valid_token "$session"; then
  printf '%s\n' "resolve-dispatch-backend: invalid session token: $(sanitize_printable "$session" "(unprintable)")" >&2
  exit 2
fi

if [ "$sub" = answer ]; then
  if [ -z "$session" ] || [ -z "$answer_val" ] || [ "$attended" -ne 0 ]; then
    usage
    exit 2
  fi
  write_ask "$specdir" "$answer_val" "$session" || exit 1
  exit 0
fi

if [ "$attended" -eq 1 ] && [ -z "$session" ]; then
  echo "resolve-dispatch-backend: --attended requires --session <token> (the token is the tower-session run boundary)" >&2
  exit 2
fi

# --- resolve the configured value -----------------------------------------

configured=''
source=''

# 1. The per-spec map (D-9, REQ-B1.3). One flat config key; the winning
#    layer's map is consulted (D-5 last-layer-wins per key). A per-spec entry
#    beats the global value in every layer combination: specificity wins
#    across the two keys.
rc=0
read_key dispatch_backend_per_spec || rc=$?
case "$rc" in
  0)
    entry=''
    erc=0
    entry=$(map_entry "$KEY_VALUE" "$spec") || erc=$?
    case "$erc" in
      0)
        configured=$entry
        source=per-spec
        ;;
      1) ;; # well-formed map, no entry for this spec: fall through to global
      *)
        # Malformed map: by-layer policy. On an adopter/machine-local degrade
        # the core default for the MAP is consulted (core ships the empty
        # map), which yields no entry — the global value then governs.
        malformed_by_layer dispatch_backend_per_spec "$KEY_LAYER" "per-spec map (not a flat inline '{spec: backend}' map)"
        crc=0
        cval=$(core_value dispatch_backend_per_spec) || crc=$?
        if [ "$crc" -eq 0 ]; then
          if centry=$(map_entry "$cval" "$spec"); then
            configured=$centry
            source=per-spec
          fi
        elif [ "$crc" -ne 3 ]; then
          # crc 3 (core omits the map key) is benign — no per-spec entry, the
          # global value governs. Any other non-zero is a broken install and
          # must surface, exactly as the global-knob degrade path does below
          # (never silently swallowed).
          echo "resolve-dispatch-backend: the core default for 'dispatch_backend_per_spec' is unresolvable (exit $crc) — broken install" >&2
          exit 5
        fi
        ;;
    esac
    ;;
  3) ;; # key absent in every layer: no per-spec override exists
  4) exit 4 ;;
  *)
    echo "resolve-dispatch-backend: unexpected config-get exit $rc resolving 'dispatch_backend_per_spec'" >&2
    exit 5
    ;;
esac

# 2. The global knob, when no per-spec entry governs.
if [ -z "$configured" ]; then
  rc=0
  read_key dispatch_backend || rc=$?
  case "$rc" in
    0)
      if valid_value "$KEY_VALUE"; then
        configured=$KEY_VALUE
        source=global
      else
        malformed_by_layer dispatch_backend "$KEY_LAYER" "backend value ('$(sanitize_printable "$KEY_VALUE" "(unprintable value)")')"
        crc=0
        cval=$(core_value dispatch_backend) || crc=$?
        if [ "$crc" -eq 3 ]; then
          echo "resolve-dispatch-backend: warning: the core default for 'dispatch_backend' is also unset; falling back to 'full-session'" >&2
          configured=full-session
          source=global
        elif [ "$crc" -ne 0 ]; then
          echo "resolve-dispatch-backend: the core default for 'dispatch_backend' is unresolvable (exit $crc) — broken install" >&2
          exit 5
        elif valid_value "$cval"; then
          configured=$cval
          source=global
        else
          echo "resolve-dispatch-backend: the core default for 'dispatch_backend' is itself malformed — broken install" >&2
          exit 5
        fi
      fi
      ;;
    3)
      echo "resolve-dispatch-backend: warning: 'dispatch_backend' is unset in every layer (broken/partial install); falling back to 'full-session'" >&2
      configured=full-session
      source=global
      ;;
    4) exit 4 ;;
    *)
      echo "resolve-dispatch-backend: unexpected config-get exit $rc resolving 'dispatch_backend'" >&2
      exit 5
      ;;
  esac
fi

# --- the tmux-context ask (D-8) -------------------------------------------

tmux_candidate=0
ask_row=0
if [ "$attended" -eq 1 ] && [ -n "${TMUX-}" ] && [ "$configured" = full-session ]; then
  if read_ask "$specdir" && [ "$ASK_TOKEN" = "$session" ]; then
    # This tower session was already asked; an answer applies, an open ask
    # stays suppressed (once per tower session).
    [ "$ASK_STATUS" = yes ] && tmux_candidate=1
  else
    # First ask of this tower session (or a new session superseding an old
    # one's state): surface the ask, record it, resolve unattended NOW —
    # non-blocking, the answer applies from the next resolve onward. A failed
    # record warns (inside write_ask) and the resolve still proceeds.
    ask_row=1
    write_ask "$specdir" asked "$session" || :
  fi
fi

# --- selection -------------------------------------------------------------

sel=''
src=0
if [ "$tmux_candidate" -eq 1 ]; then
  sel=$("$backends" select-unattended --tmux-candidate "$configured") || src=$?
else
  sel=$("$backends" select-unattended "$configured") || src=$?
fi
if [ "$src" -ne 0 ]; then
  # The sibling already diagnosed on stderr (exit 6: the fail-closed
  # explicit-but-unavailable halt the caller parks to Awaiting input).
  exit "$src"
fi

printf 'configured\t%s\t%s\n' "$configured" "$source"
[ "$ask_row" -eq 1 ] && printf 'ask\ttmux\n'
printf 'backend\t%s\n' "$sel"
exit 0
