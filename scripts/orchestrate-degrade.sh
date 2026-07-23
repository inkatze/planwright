#!/bin/sh
# orchestrate-degrade.sh — the graceful-degradation LADDER, the synchronous
# terminal rung, and runtime FAILOVER for /orchestrate (orchestration-fleet
# Task 3; D-3, REQ-B1.4, REQ-B1.5, REQ-B1.6, REQ-A1.4).
#
# Task 2's orchestrate-backends.sh does host autodetection and the
# selection-time autonomous pick; it explicitly deferred "the full
# richest-to-safest ladder, runtime failover, and the degrade-capability-never-
# safety abort" to Task 3. This script realizes them on top of the same Task 1
# capability contract (doctrine/backend-capability-contract.md, D-2): the ladder
# rung of a backend is a function of its ADVERTISED set, not its name.
#
# The ladder (D-3, richest -> safest):
#   rung 1  interactive multiplexer WITH steer                     (tmux)
#   rung 2  interactive multiplexer WITHOUT steer, OR a headless
#           `claude -p` pool (session-grade + parallel, no steer —
#           ambiguity routes to the queue; near the fallback)
#   rung 3  in-harness background subagent (parallel, no observe/steer)
#   rung 4  synchronous in-session with strategic context clears — no
#           external substrate, so it ALWAYS works (the terminal rung)
# A spawn-deferred backend (`print`) is `manual`: off the autonomous ladder
# (a human runs the printed command, so planwright is not driving the worker
# and cannot enforce its guards) — never an autonomous descent target.
#
# Subcommands:
#   rung <backend|caps>
#       Print the ladder rung of a shipped backend name, or of a six- or
#       eight-field advertised caps string `interactive can_observe
#       can_steer_inflight provides_attention_surface supports_parallel
#       session_grade [overhead hook_registration]` (the 6->8 grammar,
#       execution-backends D-13 — classification reads the first six fields).
#       Output is one of 1|2|3|4|manual. An unknown backend or unclassifiable
#       caps exits 2. The execution-backends rows classify as rung 2
#       (non-interactive session-grade pools); the finer five-way ordering of
#       REQ-A1.8 is the resolver's concern, not the four-rung classifier's.
#
#   terminal-plan <id> [<id>...]
#       Emit the synchronous terminal rung's run plan: one `run <id>` line per
#       unit with a `context-clear` line BETWEEN consecutive units (the bounded-
#       context clears — never after the last). Each id is validated against the
#       task-id grammar `^[0-9]+(\.[0-9]+)?$` before use (REQ-F1.1); a hostile id
#       exits 2 with nothing emitted. (Per-STEP isolation clears are Task 4's
#       resolve-dispatch-isolation.sh; this is the per-UNIT single-stream plan.)
#
#   record <spec-dir> <backend>
#       Write the effective backend spec-locally to the effective-backend record
#       beside the sibling's `markers/` dir in its dispatch-state root — the
#       `<spec-dir>/.orchestrate/` default, or wherever PLANWRIGHT_ORCH_STATE_DIR
#       relocates the markers dir's parent (REQ-B1.6). NEVER writes
#       tasks.md — dispatch-adjacent state stays out of the committed ledger
#       (REQ-A1.1, the sibling contract). Atomic write-temp-then-rename; a
#       symlink or non-regular file at the path is refused, not written through
#       (marker parity); a hostile backend name is refused before any path use.
#   read <spec-dir>
#       Print the recorded effective backend name (exit 1 when no record exists),
#       for a reconcile sweep / the cross-spec attention surface.
#
#   failover <spec-dir> <current-backend> [candidate...]
#       Runtime failover: a chosen backend died or proved unavailable mid-run.
#       Descend one rung down the AVAILABLE ladder — to the richest present,
#       guard-preserving candidate strictly below the current rung (an absent
#       intermediate rung is skipped) — record it spec-locally, and
#       emit a NOTE (stderr) + an `## Awaiting input`-ready entry (stdout) — never
#       a silent downgrade (REQ-B1.5). `candidate...` is the set of backends the
#       tower found present; omitted, the shipped presence probe fills it in.
#       Guard-preserving = non-interactive (never strand an unattended run) AND
#       not spawn-deferred (never the manual `print` rung) — the two advertised
#       properties whose loss would drop a named guard (worker-settings deny,
#       never-auto-merge, never-force-push, the freshness gate) by taking the
#       worker off planwright's driven, guarded path. It ESCALATES (exit 3) when
#       no lower guard-preserving rung is available — the terminal-rung fatal
#       crash, or a descent that would drop a guard — and if the record write
#       fails, it aborts (exit 3) rather than proceed unrecorded: degrade
#       capability, never safety.
#
# Scope (proportionality): failover classifies each candidate by its advertised
# set — shipped backends via the contract table, a pluggable candidate via its
# `planwright-backend-<name>` adapter — so the ladder's rung-2 (a headless
# `claude -p` pool) is a real descent target the moment such a backend is
# present. The no-candidate presence probe covers only the shipped set (a
# pluggable name is not known to it and must be passed explicitly). The `rung`
# subcommand takes a shipped name or a caps string directly (not a pluggable
# name — that needs the adapter, which `failover` consults).
#
# Exit codes: 0 success; 1 `read` with no record; 2 usage / hostile input /
# unclassifiable / spec-dir or record-path failure; 3 failover escalation
# (no safe descent, or a fail-closed record-write abort). No subcommand writes
# tasks.md and none has a merge path (never-auto-merge, REQ-J1.1).
#
# Portable POSIX sh + coreutils (bash 3.2 / BSD compatible): no eval, no gawk
# extensions; all input treated as data (REQ-K1.5, REQ-F1.1). Pathname expansion
# is disabled (set -f) so a token like `*` is taken literally and refused by the
# grammar rather than expanded.
set -uf

LC_ALL=C
export LC_ALL
unset CDPATH

# An invalid backend/id token is untrusted DATA: strip non-printable bytes before
# it reaches a diagnostic so an embedded escape sequence cannot drive the
# operator's terminal (doctrine/security-posture.md, "Echo discipline").
# shellcheck source=scripts/echo-safety.sh
. "$(dirname "$0")/echo-safety.sh"

# ---------------------------------------------------------------------------
# The advertised capability set of each shipped backend, verbatim from the
# contract table (doctrine/backend-capability-contract.md). Fields, in order:
# interactive can_observe can_steer_inflight provides_attention_surface
# supports_parallel session_grade overhead hook_registration (the 6->8
# extension, execution-backends D-13). Keep in lockstep with that table (and
# with orchestrate-backends.sh's identical table, which the CI drift guard
# checks against the doc). The classifier below reads only the first six
# fields; the appended two are validated, never classified on.
# ---------------------------------------------------------------------------
caps_for() {
  case "$1" in
    tmux) echo "true true true false true yes full-session true" ;;
    stream-json-persistent) echo "false true true false true yes full-session+supervisor true" ;;
    headless-oneshot) echo "false false false false true yes full-session true" ;;
    subagent) echo "false false false false true no light false" ;;
    print) echo "false false false false na deferred none false" ;;
    in-session) echo "false na na false false no none false" ;;
    *) return 1 ;;
  esac
}

is_known() {
  case "$1" in
    tmux | stream-json-persistent | headless-oneshot | subagent | print | in-session) return 0 ;;
    *) return 1 ;;
  esac
}

# Anchored identifier charset for a backend name (mirrors orchestrate-backends.sh
# and the spec-id grammar): lowercase alnum + hyphen, starts alnum, <=64 chars.
# Runs BEFORE the name is used to build any path/command.
valid_name() {
  case "$1" in
    '') return 1 ;;
    [!a-z0-9]*) return 1 ;;
    *[!a-z0-9-]*) return 1 ;;
  esac
  [ "${#1}" -le 64 ]
}

# Env-override presence probe for the shipped backends (parity with
# orchestrate-backends.sh's is_present), used only for the no-candidate failover
# default so the tower re-detects the present set at failover time.
env_present() {
  case "$1" in
    1 | true | TRUE | on | yes | YES) return 0 ;;
    0 | false | FALSE | off | no | NO) return 1 ;;
  esac
  case "$2" in
    yes) return 0 ;;
    no) return 1 ;;
    tmux) command -v tmux >/dev/null 2>&1 ;;
    claude) command -v claude >/dev/null 2>&1 ;;
  esac
}
is_present() {
  case "$1" in
    in-session | print) return 0 ;;
    subagent) env_present "${PLANWRIGHT_BACKEND_SUBAGENT-}" yes ;;
    tmux) env_present "${PLANWRIGHT_BACKEND_TMUX-}" tmux ;;
    # stream-json-persistent gained dispatch support (fleet-streamjson.sh,
    # Task 4): installed-CLI probe. headless-oneshot still defaults absent
    # until its dispatch support lands (Task 3) — parity with
    # orchestrate-backends.sh is_present.
    stream-json-persistent) env_present "${PLANWRIGHT_BACKEND_STREAM_JSON_PERSISTENT-}" claude ;;
    headless-oneshot) env_present "${PLANWRIGHT_BACKEND_HEADLESS_ONESHOT-}" no ;;
    *) return 1 ;;
  esac
}

# The advertised set of a PLUGGABLE backend, obtained from its adapter (mirrors
# orchestrate-backends.sh's adapter_caps — same fail-safe contract: an absent or
# malformed adapter is reported absent, so a backend whose capabilities are
# unknown is never a failover target; a malformed line carries a visible
# diagnostic per execution-backends REQ-A1.7). Echoes the eight validated
# fields — a legacy six-field line takes the fail-safe defaults
# (hook_registration=false, overhead=full-session+supervisor; D-13) — or
# returns 1. The advertise line is untrusted input (REQ-A1.9): first line only,
# length-bounded, stripped of non-printable bytes before any parse, use, or
# echo. The name is charset-validated by the caller before it reaches the
# `planwright-backend-<name>` command.
advertise_malformed() {
  printf '%s\n' "orchestrate-degrade: planwright-backend-$1: malformed advertise line ($2); backend not selectable" >&2
  return 1
}
adapter_caps() {
  ac_cmd="planwright-backend-$1"
  command -v "$ac_cmd" >/dev/null 2>&1 || return 1
  # Capture trusts the adapter process (the adapter trust model); the hygiene
  # bounds govern what is parsed and echoed, not the capture — see the
  # orchestrate-backends.sh copy for the full rationale comments.
  ac_raw=$("$ac_cmd" advertise 2>/dev/null) || return 1
  ac_line=''
  IFS= read -r ac_line <<EOF
$ac_raw
EOF
  if [ "${#ac_line}" -gt 512 ]; then
    advertise_malformed "$1" "line exceeds 512 bytes"
    return 1
  fi
  ac_line=$(printf '%s' "$ac_line" | tr '\t' ' ' | tr -d '\000-\037\177\200-\237')
  case "$ac_line" in
    *[!\ ]*) ;;
    *)
      advertise_malformed "$1" "empty advertise line"
      return 1
      ;;
  esac
  f_i='' f_o='' f_s='' f_a='' f_p='' f_g='' f_ov='' f_hr='' f_rest=''
  read -r f_i f_o f_s f_a f_p f_g f_ov f_hr f_rest <<EOF
$ac_line
EOF
  if [ -n "$f_rest" ]; then
    advertise_malformed "$1" "expected 6 or 8 whitespace-separated fields, got 9 or more"
    return 1
  fi
  if [ -n "$f_ov" ] && [ -z "$f_hr" ]; then
    advertise_malformed "$1" "expected 6 or 8 whitespace-separated fields, got 7"
    return 1
  fi
  for f in "$f_i" "$f_o" "$f_s" "$f_a" "$f_p"; do
    case "$f" in
      true | false | na) ;;
      *)
        advertise_malformed "$1" "invalid capability token"
        return 1
        ;;
    esac
  done
  case "$f_g" in
    yes | no | deferred) ;;
    *)
      advertise_malformed "$1" "invalid session_grade token"
      return 1
      ;;
  esac
  if [ -z "$f_ov" ]; then
    f_ov='full-session+supervisor'
    f_hr='false'
  else
    case "$f_ov" in
      none | light | full-session | full-session+supervisor) ;;
      *)
        advertise_malformed "$1" "invalid overhead class"
        return 1
        ;;
    esac
    case "$f_hr" in
      true | false) ;;
      *)
        advertise_malformed "$1" "invalid hook_registration token"
        return 1
        ;;
    esac
  fi
  echo "$f_i $f_o $f_s $f_a $f_p $f_g $f_ov $f_hr"
}

# The advertised caps of a backend by name: a shipped name via the contract
# table, else a validated pluggable name via its adapter. Returns 1 when the
# name is invalid or a pluggable adapter is absent/malformed (fail-safe absent).
caps_of_backend() {
  if is_known "$1"; then
    caps_for "$1"
  else
    valid_name "$1" || return 1
    adapter_caps "$1"
  fi
}

# Classify a six- or eight-field caps string onto the ladder (the 6->8
# grammar, execution-backends D-13: classification reads the first six fields;
# when the appended overhead/hook_registration fields are present they are
# validated, never classified on — a seven-field string is malformed). Reads
# into `f_`-prefixed targets so it never clobbers a caller's loop variable (sh
# has no lexical scope). Echoes 1|2|3|4|manual, or returns 1 when the set is
# not well-formed or does not classify.
rung_of_caps() {
  f_i='' f_o='' f_s='' f_a='' f_p='' f_g='' f_ov='' f_hr='' f_rest=''
  read -r f_i f_o f_s f_a f_p f_g f_ov f_hr f_rest <<EOF
$1
EOF
  [ -z "$f_rest" ] || return 1
  if [ -n "$f_ov" ] && [ -z "$f_hr" ]; then
    return 1
  fi
  for f in "$f_i" "$f_o" "$f_s" "$f_a" "$f_p"; do
    case "$f" in
      true | false | na) ;;
      *) return 1 ;;
    esac
  done
  case "$f_g" in
    yes | no | deferred) ;;
    *) return 1 ;;
  esac
  if [ -n "$f_ov" ]; then
    case "$f_ov" in
      none | light | full-session | full-session+supervisor) ;;
      *) return 1 ;;
    esac
    case "$f_hr" in
      true | false) ;;
      *) return 1 ;;
    esac
  fi
  # Classification is TOTAL over well-formed caps (every parsing-valid set maps
  # to a rung), so an unusual-but-valid advertisement never falls through to
  # "unclassifiable" — only a malformed set (rejected above) does.
  #
  # A spawn-deferred backend is off the autonomous ladder (manual).
  if [ "$f_g" = deferred ]; then
    echo manual
    return 0
  fi
  # Interactive multiplexer: rung 1 with steer, else rung 2 (without steer).
  # rung 1 is the ONLY rung requiring interactivity, so a non-interactive
  # backend never lands there however rich it is.
  if [ "$f_i" = true ]; then
    if [ "$f_s" = true ]; then echo 1; else echo 2; fi
    return 0
  fi
  # Non-interactive. A single-stream (non-parallel) backend is the terminal
  # rung 4 — the always-works floor — regardless of session-grade.
  if [ "$f_p" != true ]; then
    echo 4
    return 0
  fi
  # Non-interactive AND parallel: a session-grade pool is rung 2 (a headless
  # `claude -p` pool — steer is what routes ambiguity to the queue, it does not
  # move the rung); a non-session-grade in-harness pool is rung 3 (subagent).
  if [ "$f_g" = yes ]; then echo 2; else echo 3; fi
  return 0
}

# Rung of a backend by name (shipped) or a caps string. A shipped name resolves
# through the contract table; anything else is treated as a caps string.
rung_of() {
  if is_known "$1"; then
    rung_of_caps "$(caps_for "$1")"
  else
    rung_of_caps "$1"
  fi
}

# Numeric ordering for descent comparisons: 1..4 map to themselves; `manual`
# sorts BELOW every autonomous rung (5) so it is never a descent target above a
# real rung; anything unclassifiable is refused by the caller.
rung_num() {
  case "$1" in
    1 | 2 | 3 | 4) echo "$1" ;;
    manual) echo 5 ;;
    *) return 1 ;;
  esac
}

# A guard-preserving descent target keeps the worker on planwright's driven,
# guarded path: non-interactive (never strand an unattended run) AND not
# spawn-deferred (never the manual `print` rung). Reads a caps string on $1.
#
# Deliberately stricter than rung_of_caps's interactivity test: the classifier
# treats any `interactive != true` (including `na`) as non-interactive and puts
# it on the ladder, but the guard gate demands `interactive = false` EXACTLY. An
# advertisement of `interactive=na` (unknown interactivity — no real backend emits
# it, but the grammar admits it) is therefore refused as a descent target and the
# run escalates for a human, rather than risking an unattended strand on a backend
# whose interactivity we cannot confirm. This asymmetry is intentional:
# degrade capability, never safety — when interactivity is unknown, refuse.
caps_guard_preserving() {
  f_i='' f_g='' f_rest=''
  read -r f_i f_o f_s f_a f_p f_g f_rest <<EOF
$1
EOF
  [ "$f_i" = false ] && [ "$f_g" != deferred ]
}

# Resolve the spec-local effective-backend record path. It sits alongside the
# sibling's runtime dispatch marker (REQ-B1.6): the marker dir is
# ${PLANWRIGHT_ORCH_STATE_DIR:-<spec-dir>/.orchestrate/markers}; the record is a
# sibling of that dir (its parent, the `.orchestrate` root), so the same trusted
# operator/test knob relocates both consistently (R8: confirmed aligned with the
# sibling marker schema — a distinct filename, one line, never a task-id path).
record_path() {
  rp_markers="${PLANWRIGHT_ORCH_STATE_DIR:-$1/.orchestrate/markers}"
  rp_orch=$(dirname "$rp_markers")
  printf '%s/effective-backend' "$rp_orch"
}

# ---------------------------------------------------------------------------

cmd_rung() {
  if [ "$#" -ne 1 ] || [ -z "${1:-}" ]; then
    echo "usage: orchestrate-degrade.sh rung <backend|caps>" >&2
    return 2
  fi
  if ! r=$(rung_of "$1"); then
    printf '%s\n' "orchestrate-degrade: cannot classify backend/caps: $(sanitize_printable "$1" "(unprintable)")" >&2
    return 2
  fi
  printf '%s\n' "$r"
}

# Validate a single task id against the grammar (REQ-F1.1). The charset gate
# refuses any character outside [0-9.]; the grammar refuses the charset-valid
# residue (`..`, `1.`, `1.2.3`). The bundle-range form `5-6` fails the charset
# gate by design — the terminal plan is over individual task ids.
valid_id() {
  case "$1" in
    '' | *[!0-9.]*) return 1 ;;
  esac
  printf '%s' "$1" | grep -Eq '^[0-9]+(\.[0-9]+)?$'
}

cmd_terminal_plan() {
  if [ "$#" -eq 0 ]; then
    echo "usage: orchestrate-degrade.sh terminal-plan <id> [<id>...]" >&2
    return 2
  fi
  # Validate every id BEFORE emitting anything (all-or-nothing; a refused plan
  # emits no partial output).
  for id in "$@"; do
    if ! valid_id "$id"; then
      printf '%s\n' "orchestrate-degrade: refusing malformed task id '$(sanitize_printable "$id" "(unprintable id)")' (REQ-F1.1: ^[0-9]+(\.[0-9]+)?\$)" >&2
      return 2
    fi
  done
  tp_first=1
  for id in "$@"; do
    [ "$tp_first" -eq 1 ] || echo "context-clear"
    printf 'run %s\n' "$id"
    tp_first=0
  done
}

# Write the effective-backend record atomically, with the marker's write-time
# hardening (symlink/non-regular refusal + containment). Returns 2 on any
# failure (fail-closed). Does NOT emit to stdout.
write_record() {
  wr_spec=$1
  wr_backend=$2
  if [ ! -d "$wr_spec" ]; then
    echo "orchestrate-degrade: no such spec dir: $wr_spec" >&2
    return 2
  fi
  if ! is_known "$wr_backend" && ! valid_name "$wr_backend"; then
    printf '%s\n' "orchestrate-degrade: invalid backend name: $(sanitize_printable "$wr_backend" "(unprintable name)")" >&2
    return 2
  fi
  wr_file=$(record_path "$wr_spec")
  wr_dir=$(dirname "$wr_file")
  if ! mkdir -p "$wr_dir" 2>/dev/null; then
    echo "orchestrate-degrade: cannot create state dir $wr_dir" >&2
    return 2
  fi
  # Refuse a symlink or any other non-regular file already at the record path —
  # never write through it (the marker's write-time symlink-swap guard).
  if [ -L "$wr_file" ]; then
    echo "orchestrate-degrade: refusing symlink at record path $wr_file" >&2
    return 2
  fi
  if [ -e "$wr_file" ] && [ ! -f "$wr_file" ]; then
    echo "orchestrate-degrade: refusing non-regular file at record path $wr_file" >&2
    return 2
  fi
  # (No containment check is needed: the record filename is the constant literal
  # `effective-backend` with no token interpolated into the path, so it can never
  # escape its resolved dir — unlike the sibling marker, whose filename is a
  # variable task id and therefore does need a containment guard.)
  wr_now=$(date +%s)
  case "$wr_now" in '' | *[!0-9]*) wr_now=0 ;; esac
  wr_tmp=$(mktemp "$wr_dir/.effbk.XXXXXX") || {
    echo "orchestrate-degrade: cannot create a temp record in $wr_dir" >&2
    return 2
  }
  if ! printf '%s\t%s\n' "$wr_backend" "$wr_now" >"$wr_tmp"; then
    rm -f "$wr_tmp"
    echo "orchestrate-degrade: cannot write the effective-backend record" >&2
    return 2
  fi
  if ! mv -f "$wr_tmp" "$wr_file"; then
    rm -f "$wr_tmp"
    echo "orchestrate-degrade: cannot place the effective-backend record" >&2
    return 2
  fi
  return 0
}

cmd_record() {
  if [ "$#" -ne 2 ]; then
    echo "usage: orchestrate-degrade.sh record <spec-dir> <backend>" >&2
    return 2
  fi
  write_record "$1" "$2"
}

cmd_read() {
  if [ "$#" -ne 1 ]; then
    echo "usage: orchestrate-degrade.sh read <spec-dir>" >&2
    return 2
  fi
  rd_file=$(record_path "$1")
  [ -e "$rd_file" ] || return 1
  # A symlink or any other non-regular file at the record path is never a valid
  # record — refuse to follow it (write-path parity; a reconcile sweep degrades
  # to the configured backend on a nonzero read). Treated as "no valid record".
  if [ -L "$rd_file" ] || [ ! -f "$rd_file" ]; then
    echo "orchestrate-degrade: ignoring non-regular effective-backend record at $rd_file" >&2
    return 1
  fi
  # First field of the first line is the backend name. Pre-initialize so a
  # redirect that fails (the record vanished after the check above) leaves a
  # defined-but-empty value under `set -u` rather than an unbound-variable abort.
  # Do NOT gate on `read`'s exit status: a record written without a trailing
  # newline (e.g. by another tool) makes `read` return nonzero at EOF though it
  # populated the field.
  rd_backend=''
  IFS='	' read -r rd_backend _ <"$rd_file" || true
  [ -n "$rd_backend" ] || return 1
  # Re-validate the read-back value: the writer only ever persists a valid
  # backend name, so anything else means a tampered/foreign record — refuse it
  # (and route through sanitize_printable so escape bytes cannot reach the
  # operator's terminal) rather than emit it raw.
  if ! is_known "$rd_backend" && ! valid_name "$rd_backend"; then
    printf '%s\n' "orchestrate-degrade: ignoring malformed effective-backend record: $(sanitize_printable "$rd_backend" "(unprintable value)")" >&2
    return 1
  fi
  printf '%s\n' "$rd_backend"
}

cmd_failover() {
  if [ "$#" -lt 2 ]; then
    echo "usage: orchestrate-degrade.sh failover <spec-dir> <current-backend> [candidate...]" >&2
    return 2
  fi
  fo_spec=$1
  fo_current=$2
  shift 2
  if [ ! -d "$fo_spec" ]; then
    echo "orchestrate-degrade: no such spec dir: $fo_spec" >&2
    return 2
  fi
  if ! is_known "$fo_current" && ! valid_name "$fo_current"; then
    printf '%s\n' "orchestrate-degrade: invalid current backend: $(sanitize_printable "$fo_current" "(unprintable name)")" >&2
    return 2
  fi
  fo_cur_rung=''
  if is_known "$fo_current"; then
    fo_cur_rung=$(rung_of_caps "$(caps_for "$fo_current")")
  elif fo_cur_caps=$(caps_of_backend "$fo_current"); then
    fo_cur_rung=$(rung_of_caps "$fo_cur_caps")
  fi
  if [ -z "$fo_cur_rung" ]; then
    printf '%s\n' "orchestrate-degrade: cannot classify current backend '$(sanitize_printable "$fo_current" "(unprintable)")'" >&2
    return 2
  fi
  # A `manual` current classifies as rung_num 5 (below every autonomous rung), so
  # nothing is "strictly below" it and failover escalates. That is correct by
  # design: `print` is off the driven ladder — planwright never drives it, so it
  # cannot "die mid-run", and failover-from-manual is a nonsensical call that
  # fails safe to a human decision rather than descending to a real rung.
  fo_cur_n=$(rung_num "$fo_cur_rung") || fo_cur_n=5

  # No explicit candidates: re-detect the shipped present set at failover time,
  # enumerated in the contract's pinned ladder order so an intra-rung tie (both
  # execution-backends rows classify rung 2) resolves to the richer pinned rung
  # (REQ-A1.8; the strict `-lt` best-rung compare below is first-seen-wins
  # within a rung, so probe order IS the tie-break — an explicit candidate list
  # keeps its caller's order until the finer five-way resolver lands).
  # (A pluggable candidate must be passed explicitly — its name is not known to
  # the shipped presence probe.)
  if [ "$#" -eq 0 ]; then
    set --
    for b in tmux stream-json-persistent headless-oneshot subagent in-session print; do
      is_present "$b" && set -- "$@" "$b"
    done
  fi

  # Walk the candidates, each classified by its ADVERTISED set (shipped via the
  # contract table, pluggable via its adapter). Track the richest guard-
  # preserving rung strictly below the current one (the descent target), whether
  # any real LOWER LADDER RUNG exists (guard-preserving or not), and whether an
  # off-ladder manual backend is present. Together they distinguish the two
  # escalations: a lower rung that would drop a guard vs. the ladder floor.
  fo_best_backend=''
  fo_best_n=99
  fo_any_below=0
  fo_off_ladder=0
  for cand in "$@"; do
    cand_caps=$(caps_of_backend "$cand") || continue # unknown name / absent adapter → fail-safe skip
    cand_rung=$(rung_of_caps "$cand_caps") || continue
    if [ "$cand_rung" = manual ]; then
      fo_off_ladder=1 # off the autonomous ladder — never a lower rung, never a target
      continue
    fi
    cand_n=$(rung_num "$cand_rung") || continue
    [ "$cand_n" -gt "$fo_cur_n" ] || continue      # strictly below (further down the ladder)
    fo_any_below=1                                 # a real lower LADDER rung exists
    caps_guard_preserving "$cand_caps" || continue # but it would drop a guard — skip
    if [ "$cand_n" -lt "$fo_best_n" ]; then
      fo_best_n=$cand_n
      fo_best_backend=$cand
    fi
  done

  today=$(date +%Y-%m-%d)
  case "$today" in '' | *[!0-9-]*) today="(date-unavailable)" ;; esac

  if [ -z "$fo_best_backend" ]; then
    # No safe descent. Distinguish the escalation reasons for the operator.
    if [ "$fo_any_below" -eq 1 ]; then
      fo_reason="a lower ladder rung is available but would drop a named guard (an interactive or otherwise unsafe backend); refusing to descend — degrade capability, never safety"
    else
      # No lower ladder rung is present. This is the true terminal-rung floor
      # when current is rung 4; it is also reached when a higher rung's only
      # present descendants are off-ladder — so the message states the available
      # fact ("no lower rung present") without asserting current is the floor.
      fo_reason="no lower rung is present below '$fo_current' (rung $fo_cur_rung); nothing safe to descend to"
      [ "$fo_off_ladder" -eq 1 ] && fo_reason="$fo_reason (the manual 'print' backend remains, but the tower cannot drive it)"
    fi
    echo "NOTE: runtime-failover ESCALATION: $fo_reason." >&2
    printf -- '- **Backend failover escalation (%s):** %s. Human decision required.\n' \
      "$today" "$fo_reason"
    return 3
  fi

  # A safe descent exists. Record it FIRST (fail-closed: if we cannot record the
  # effective backend, we do not proceed unrecorded — R12).
  if ! write_record "$fo_spec" "$fo_best_backend"; then
    echo "NOTE: runtime-failover ESCALATION: could not record the effective backend for '$fo_spec'; aborting rather than degrade unrecorded." >&2
    # shellcheck disable=SC2016 # the backticks are literal markdown, not expansion
    printf -- '- **Backend failover escalation (%s):** could not persist the effective-backend record; aborted the descent to `%s` rather than proceed unrecorded (fail-closed). Human decision required.\n' \
      "$today" "$fo_best_backend"
    return 3
  fi

  # Name the ACTUAL record location (record_path honors PLANWRIGHT_ORCH_STATE_DIR),
  # not a hardcoded `.orchestrate/` the record may not live in under that override.
  fo_rec=$(record_path "$fo_spec")
  echo "NOTE: runtime failover — backend '$fo_current' (rung $fo_cur_rung) unavailable; descended one rung to '$fo_best_backend' (rung $fo_best_n). Effective backend recorded spec-locally." >&2
  # shellcheck disable=SC2016 # the backticks are literal markdown, not expansion
  printf -- '- **Backend failover (%s):** `%s` (rung %s) died mid-run; descended one rung to `%s` (rung %s). Effective backend recorded spec-locally in `%s`; all guards held. Review before resuming.\n' \
    "$today" "$fo_current" "$fo_cur_rung" "$fo_best_backend" "$fo_best_n" "$fo_rec"
  return 0
}

sub=${1-}
[ "$#" -gt 0 ] && shift
case "$sub" in
  rung) cmd_rung "$@" ;;
  terminal-plan) cmd_terminal_plan "$@" ;;
  record) cmd_record "$@" ;;
  read) cmd_read "$@" ;;
  failover) cmd_failover "$@" ;;
  '' | help | -h | --help)
    echo "usage: orchestrate-degrade.sh {rung <backend|caps> | terminal-plan <id>... | record <spec-dir> <backend> | read <spec-dir> | failover <spec-dir> <current> [candidate...]}" >&2
    exit 2
    ;;
  *)
    echo "orchestrate-degrade: unknown subcommand: $sub" >&2
    exit 2
    ;;
esac
