#!/bin/sh
# behavioral-eval.sh — the on-demand behavioral eval harness (operator-dialogue
# Task 5; D-8; REQ-G1.1–REQ-G1.6). It drives a skill through a REAL interactive
# TTY session — a tmux session driven by `send-keys` + `C-m`, idle detected by a
# POSITIVE footer anchor (scripts/fleet-pane-detect.sh, the codified detector) —
# answered by a simulated-operator driver parameterized by an expertise persona
# (at minimum novice and expert). It GRADES the durable artifacts the run WRITES
# (a structured decision log, an eval-only sign-off record) — never a scraped
# pane (REQ-G1.3); the pane is used only for liveness and idle detection. An
# independent grader (a non-Anthropic backend and/or the human final rater),
# DISTINCT from the driver, scores experiential quality; with no independent
# grader — or one that is unavailable — the run degrades to human-rater scoring
# and NEVER substitutes a self-graded quality score (REQ-G1.4).
#
# It is ON-DEMAND ONLY. It is registered under the `eval:` mise namespace so the
# standing CI-exclusion guard (scripts/check-no-ci-evals.sh) covers it, and it is
# never wired into `mise run check` or CI (D-8). This scaffold demonstrates
# against a generic fixture skill (tests/behavioral-evals/fixtures/greeter); the
# acceptance assertions that drive the real /spec-kickoff surface live in Task 6.
#
# Isolation & hygiene (reused from prompt-eval.sh's disciplines, REQ-G1.5):
#   - a DISPOSABLE per-run tree under $WORKBASE, canonicalized and
#     containment-checked before a fail-closed teardown;
#   - a PER-RUN-UNIQUE tmux session name, with stale sessions from crashed prior
#     runs of the same fixture+persona REAPED before launch, so concurrent or
#     leftover eval sessions never collide;
#   - BOUNDED cost: a per-persona turn ceiling and a poll ceiling stop a runaway
#     dialogue (a model-backed Task-6 surface additionally binds a USD cap);
#   - ALLOWLISTED, scalar-only recorded results — a result carries the fixture,
#     persona, outcome, driver/grader ids, and cost, and nothing more, re-verified
#     to hold only the allowed keys and no machine-local substring before write.
#
# Security disciplines (REQ-G1.6, security-posture's framework-script rules):
#   - persona-driver text is SANITIZED (echo-safety's sanitize_printable) before
#     it reaches `send-keys`, so no control byte can inject terminal input;
#   - the disposable-tree teardown path is containment-checked AFTER
#     canonicalization, so a teardown never escapes $WORKBASE;
#   - the structured log is emitted (by the skill) and parsed (here, with jq) in a
#     non-code-bearing, escape-safe form — artifact values are data, never eval'd;
#   - surfaced artifact values pass the echo-safety sanitizer before reaching the
#     terminal;
#   - only fixture content (the merged artifacts) reaches a third-party grader;
#   - grader-backend credentials are read from the environment / a secret store,
#     never committed and never written into a recorded result;
#   - the session runs with publishing disabled (PLANWRIGHT_PUBLISH_DISABLED=1);
#     this scaffold's fixture has no publish path, the contract the Task-6 surface
#     inherits — no eval run pushes, opens a PR, or marks a PR ready;
#   - any driver-produced sign-off is marked eval-only / non-authoritative
#     (PLANWRIGHT_EVAL_ONLY=1; re-verified post-run) so it can never be mistaken
#     for a human sign-off.
#
# Usage:
#   behavioral-eval.sh [options] <fixture-dir> [<fixture-dir>...]
#   behavioral-eval.sh [options] --suite <fixtures-root>
# Options:
#   --persona <name>        run only this persona (repeatable); default: every
#                           persona the fixture names
#   --grader <cmd>          the independent grader command; invoked with the
#                           merged fixture-only artifacts file as its argument,
#                           printing `pass` / `fail` and exiting 0, or exiting
#                           non-zero when unavailable (degrade to human-rater)
#   --grader-id <id>        the grader backend identifier; MUST differ from the
#                           driver id (else the run is self-grading — refused)
#   --record <dir>          write a scrubbed <id>.<persona>.json result per run
#   --suite <root>          run every immediate subdir of <root> as a fixture
#   -h, --help              this help
#
# Test seams (env): BEHAVIORAL_EVAL_TMUX overrides the `tmux` binary;
# BEHAVIORAL_EVAL_WORKBASE overrides the disposable-tree base; BEHAVIORAL_EVAL_
# DRIVER_ID overrides the driver id; BEHAVIORAL_EVAL_POLL_SLEEP sets the
# inter-poll sleep (default 0.2s; the hermetic tests set 0).
#
# Exit: 0 every persona completed (pass or human-rater-required — a legitimate
# degrade); 1 a persona graded fail; 2 usage; 3 an invalid run (the session died
# without writing its artifacts, or never reached completion); 4 fail-closed
# harness error (unparseable artifact, self-grading independence violation, or an
# unbuildable result); 5 teardown / containment failure; 6 the turn / poll
# ceiling was hit.
#
# Portable POSIX sh + jq; bash 3.2 / BSD tooling. No eval; every fixture and
# persona input is treated as data. C locale pinned for stable matching.
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
PANE_DETECT="$SELF_DIR/fleet-pane-detect.sh"

# The canonical echo-discipline sanitizer (security-posture): every untrusted
# value — a persona answer before send-keys, an artifact value before the
# terminal — is stripped of control bytes first. Guarded source with an inline
# fallback so a missing helper never turns sanitize_printable into a
# command-not-found on an error path.
if [ -r "$SELF_DIR/echo-safety.sh" ]; then
  # shellcheck source=scripts/echo-safety.sh
  . "$SELF_DIR/echo-safety.sh"
else
  sanitize_printable() {
    _sp=$(printf '%s' "$1" | tr -d '\000-\037\177\200-\237')
    if [ -z "$_sp" ] && [ $# -ge 2 ]; then _sp=$2; fi
    printf '%s' "$_sp"
  }
fi

TMUX_BIN="${BEHAVIORAL_EVAL_TMUX:-tmux}"
WORKBASE="${BEHAVIORAL_EVAL_WORKBASE:-${TMPDIR:-/tmp}/planwright-behavioral-eval}"
DRIVER_ID="${BEHAVIORAL_EVAL_DRIVER_ID:-planwright-eval-driver}"
POLL_SLEEP="${BEHAVIORAL_EVAL_POLL_SLEEP:-0.2}"
SESSION_PREFIX="planwright-eval"

grader_cmd=""
grader_id=""
record_dir=""
suite_root=""
only_personas=""

die_usage() {
  # Sanitize before the terminal: the message often carries an operator-supplied
  # token (an unknown option, a bad --suite path), which could embed a terminal
  # escape (echo discipline, security-posture). sanitize_printable strips control
  # bytes; `printf '%s'` (never `echo`) then prevents a SysV/dash echo from
  # re-expanding a literal `\033`-style sequence back into a control byte.
  printf '%s\n' "behavioral-eval: $(sanitize_printable "$1")" >&2
  printf '%s\n' "run 'behavioral-eval.sh --help' for usage" >&2
  exit 2
}

print_help() {
  sed -n '2,/^[^#]/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'
}

warn() {
  # Untrusted values are sanitized before they reach stderr.
  printf '%s\n' "behavioral-eval: $(sanitize_printable "$1")" >&2
}

# ---- argument parsing --------------------------------------------------------
fixtures=""
while [ $# -gt 0 ]; do
  case "$1" in
    --persona)
      [ $# -ge 2 ] || die_usage "--persona needs a value"
      only_personas="$only_personas $2"
      shift 2
      ;;
    --grader)
      [ $# -ge 2 ] || die_usage "--grader needs a value"
      grader_cmd="$2"
      shift 2
      ;;
    --grader-id)
      [ $# -ge 2 ] || die_usage "--grader-id needs a value"
      grader_id="$2"
      shift 2
      ;;
    --record)
      [ $# -ge 2 ] || die_usage "--record needs a value"
      record_dir="$2"
      shift 2
      ;;
    --suite)
      [ $# -ge 2 ] || die_usage "--suite needs a value"
      suite_root="$2"
      shift 2
      ;;
    -h | --help)
      print_help
      exit 0
      ;;
    --)
      shift
      while [ $# -gt 0 ]; do
        fixtures="$fixtures$1
"
        shift
      done
      ;;
    -*)
      die_usage "unknown option: $1"
      ;;
    *)
      fixtures="$fixtures$1
"
      shift
      ;;
  esac
done

if [ -n "$suite_root" ]; then
  [ -d "$suite_root" ] || die_usage "suite root not a directory: $suite_root"
  for d in "$suite_root"/*/; do
    [ -d "$d" ] || continue
    fixtures="$fixtures${d%/}
"
  done
fi

[ -n "$fixtures" ] || die_usage "no fixtures given (pass a fixture dir or --suite)"

# ---- environment checks ------------------------------------------------------
command -v jq >/dev/null 2>&1 || {
  echo "behavioral-eval: jq is required but not on PATH" >&2
  exit 4
}
[ -x "$PANE_DETECT" ] || {
  printf '%s\n' "behavioral-eval: the pane detector is missing or not executable: $(sanitize_printable "$PANE_DETECT")" >&2
  exit 4
}

# Independence firewall (REQ-G1.4): a configured grader whose id equals the
# driver id would be the agent grading its own session. Refuse fail-closed up
# front, before any session is launched.
if [ -n "$grader_cmd" ]; then
  [ -n "$grader_id" ] || die_usage "--grader requires --grader-id (the independence check needs it)"
  if [ "$grader_id" = "$DRIVER_ID" ]; then
    warn "refusing: grader id '$grader_id' equals the driver id — that is self-grading (REQ-G1.4)"
    exit 4
  fi
fi

if [ -n "$record_dir" ]; then
  mkdir -p "$record_dir" || {
    printf '%s\n' "behavioral-eval: cannot create record dir '$(sanitize_printable "$record_dir")'" >&2
    exit 5
  }
fi
mkdir -p "$WORKBASE" || {
  printf '%s\n' "behavioral-eval: cannot create work base '$(sanitize_printable "$WORKBASE")'" >&2
  exit 5
}
# Resolve $WORKBASE to its physical path once: the teardown containment check
# compares the run tree's canonical path against this.
WORKBASE_PHYS="$(cd "$WORKBASE" && pwd -P)" || {
  printf '%s\n' "behavioral-eval: cannot canonicalize work base '$(sanitize_printable "$WORKBASE")'" >&2
  exit 5
}

# The machine-local leak pattern (prompt-eval.sh's, case-insensitive): the
# result artifact is built by allowlist from scalars, so nothing machine-local
# should reach it — this is the backstop for a future edit that widens the
# allowlist.
machine_local_re='/(Users|home|root|opt)/|/private/var/|[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'

seq=0
overall_rc=0
note_fail() { [ "$overall_rc" -eq 0 ] && overall_rc=1; }

# ---- helpers -----------------------------------------------------------------

# read_conf <fixture-dir> <key> — echo an allowlisted key's value from
# fixture.conf. Parsed as data: split on the first '=', no sourcing.
read_conf() {
  cf="$1/fixture.conf"
  [ -f "$cf" ] || return 0
  while IFS= read -r rawline || [ -n "$rawline" ]; do
    case "$rawline" in
      '' | '#'*) continue ;;
    esac
    key="${rawline%%=*}"
    val="${rawline#*=}"
    [ "$key" = "$2" ] && printf '%s' "$val" && return 0
  done <"$cf"
  return 0
}

# persona_answer <persona-file> <turn-n> — echo the answer for turn <n>, or
# return 1 if the persona has none (the driver then sends nothing further).
persona_answer() {
  [ -f "$1" ] || return 1
  while IFS= read -r rawline || [ -n "$rawline" ]; do
    case "$rawline" in
      '' | '#'*) continue ;;
    esac
    key="${rawline%%=*}"
    val="${rawline#*=}"
    [ "$key" = "answer.$2" ] && printf '%s' "$val" && return 0
  done <"$1"
  return 1
}

# current_turn <pane-file> — echo the LAST `turn=<N>` anchor value in the pane,
# or nothing. Pure string scan; the pane is read as data.
current_turn() {
  awk '{
    line=$0
    while (match(line, /turn=[0-9]+/)) {
      t=substr(line, RSTART+5, RLENGTH-5)
      line=substr(line, RSTART+RLENGTH)
    }
  } END { if (t != "") print t }' "$1" 2>/dev/null
}

# tmux_* — every tmux interaction funnels through these, so the stub in the test
# suite implements exactly this surface. Session-target commands (has-session,
# kill-session) take the `=` exact-name prefix so a name is never fnmatch-treated
# as a pattern; pane-target commands (capture-pane, send-keys) take the BARE name
# — tmux resolves a bare pane target exact-match-first, and the `=` prefix is not
# a valid pane-target form (it is parsed as a literal pane name). Names are
# globally unique (unique_session's nonce), so the bare exact match is safe.
tmux_new() {
  # tmux_new <session> <launch-string>
  "$TMUX_BIN" new-session -d -s "$1" -x 200 -y 50 "$2" >/dev/null 2>&1
}
tmux_alive() { "$TMUX_BIN" has-session -t "=$1" >/dev/null 2>&1; }
tmux_capture() { "$TMUX_BIN" capture-pane -p -t "$1" 2>/dev/null; }
tmux_kill() { "$TMUX_BIN" kill-session -t "=$1" >/dev/null 2>&1; }
tmux_sessions() { "$TMUX_BIN" list-sessions -F '#{session_name}' 2>/dev/null; }

# tmux_send <session> <text> — SANITIZE the persona answer (strip control bytes)
# before it reaches send-keys, so no embedded control input can be injected
# (REQ-G1.6), then submit it with a separate C-m (not the Enter key name, which
# tmux inserts as a literal newline).
tmux_send() {
  _ts_clean="$(sanitize_printable "$2")"
  "$TMUX_BIN" send-keys -t "$1" -l -- "$_ts_clean" >/dev/null 2>&1
  "$TMUX_BIN" send-keys -t "$1" C-m >/dev/null 2>&1
}

# reap_stale <fixture-id> <persona> <keep-session> — kill any leftover eval
# session for THIS fixture+persona from a crashed prior run, so a stale session
# never collides with the fresh one (REQ-G1.5). The current run's unique session
# is kept. Single-invocation-per-(fixture,persona) is assumed, mirroring
# prompt-eval.sh's prune-first (crash-recovery over concurrency-safety).
reap_stale() {
  _rs_pat="$SESSION_PREFIX-$1-$2-"
  tmux_sessions | while IFS= read -r _rs_name; do
    [ -n "$_rs_name" ] || continue
    [ "$_rs_name" = "$3" ] && continue
    case "$_rs_name" in
      "$_rs_pat"*)
        "$TMUX_BIN" kill-session -t "=$_rs_name" >/dev/null 2>&1 || true
        printf 'behavioral-eval: reaped stale eval session %s\n' \
          "$(sanitize_printable "$_rs_name")" >&2
        ;;
    esac
  done
}

# unique_session <fixture-id> <persona> — a per-run-unique, grammar-safe session
# name: prefix, fixture, persona, pid, a monotonic seq, and a urandom nonce so
# two runs (even at the same pid+seq) never collide (REQ-G1.5).
unique_session() {
  _us_nonce="$(od -An -t x1 -N4 /dev/urandom 2>/dev/null | tr -d ' \n')"
  [ -n "$_us_nonce" ] || _us_nonce="$seq"
  printf '%s-%s-%s-%s-%s-%s' "$SESSION_PREFIX" "$1" "$2" "$$" "$seq" "$_us_nonce"
}

# containment_rm <dir> — remove a disposable run tree, but ONLY after
# canonicalizing it and confirming it resolves UNDER $WORKBASE_PHYS (REQ-G1.6
# path handling). A path that escapes containment is a fail-closed refusal, never
# an rm. Returns non-zero on a containment violation or a removal failure.
containment_rm() {
  [ -e "$1" ] || return 0
  _cr_phys="$(cd "$1" 2>/dev/null && pwd -P)" || {
    warn "teardown: cannot canonicalize run tree '$1'"
    return 1
  }
  # Strict descendant only: the run tree must resolve to a path STRICTLY UNDER the
  # work base, never the base itself. (Equal would let the `"$base"/*` glob match
  # via an empty trailing segment and rm the whole base — reject it explicitly.)
  if [ "$_cr_phys" = "$WORKBASE_PHYS" ]; then
    warn "teardown: refusing to remove the work base itself (containment guard)"
    return 1
  fi
  case "$_cr_phys/" in
    "$WORKBASE_PHYS"/*) ;;
    *)
      warn "teardown: run tree '$_cr_phys' does not resolve under the work base (containment guard)"
      return 1
      ;;
  esac
  rm -rf "$_cr_phys" 2>/dev/null || {
    warn "teardown: failed to remove '$_cr_phys'"
    return 1
  }
  return 0
}

# ---- grading -----------------------------------------------------------------

# grade_run <persona> <artifacts-dir> <merged-out> — merge the durable artifacts
# into one fixture-only object (never a scraped pane, REQ-G1.3), validate they
# parse (escape-safe), apply the fixture's structural grade, then route to the
# independent grader or the human-rater degrade. Echoes TWO space-separated
# tokens on stdout — `<outcome> <structural>` where outcome is
# pass|fail|human-rater-required and structural is true|false — so the caller
# gets the MECHANICAL grade separately from the experiential outcome without a
# subshell-lost global (grade_run is invoked in a command substitution). Returns
# 4 fail-closed on an unparseable artifact or a build failure.
grade_run() {
  _gr_persona="$1"
  _gr_art="$2"
  _gr_merged="$3"
  _gr_signoff="$_gr_art/sign-off.json"
  _gr_log="$_gr_art/decision-log.jsonl"

  [ -f "$_gr_signoff" ] || {
    warn "[$_gr_persona] grade: no sign-off artifact to grade"
    return 4
  }
  # Parse both artifacts as data (jq), fail-closed on malformed JSON — the
  # escape-safe, non-code-bearing parse (REQ-G1.6). A missing log is an empty
  # array, not an error.
  if ! jq -e . "$_gr_signoff" >/dev/null 2>&1; then
    warn "[$_gr_persona] grade: sign-off is not valid JSON"
    return 4
  fi
  _gr_log_json="[]"
  if [ -f "$_gr_log" ]; then
    _gr_log_json="$(jq -cs . "$_gr_log" 2>/dev/null)" || {
      warn "[$_gr_persona] grade: decision log is not valid JSON lines"
      return 4
    }
  fi
  # The merged, fixture-only artifacts object — the ONLY thing a grader ever sees.
  if ! jq -n \
    --arg persona "$_gr_persona" \
    --argjson log "$_gr_log_json" \
    --slurpfile signoff "$_gr_signoff" \
    '{persona: $persona, decision_log: $log, sign_off: $signoff[0]}' \
    >"$_gr_merged" 2>/dev/null; then
    warn "[$_gr_persona] grade: could not build the merged artifacts object"
    return 4
  fi

  # Structural (invariant) grade — a mechanical check, not a quality verdict, so
  # it is legitimately harness-side (the firewall governs quality opinions, not
  # invariants). A fixture without grade.jq passes the structural floor vacuously.
  _gr_struct="true"
  if [ -f "$fx_dir/grade.jq" ]; then
    if jq -e -f "$fx_dir/grade.jq" "$_gr_merged" >/dev/null 2>&1; then
      _gr_struct="true"
    else
      _gr_rc=$?
      # jq exit 1 => the invariant is false (a graded structural fail); anything
      # else (2/3/4/5) is a broken grade.jq => fail-closed, never a silent pass.
      if [ "$_gr_rc" -eq 1 ]; then
        _gr_struct="false"
      else
        warn "[$_gr_persona] grade: grade.jq error (jq exit $_gr_rc)"
        return 4
      fi
    fi
  fi
  # The structural verdict (`$_gr_struct`) is emitted alongside every outcome
  # token, so the recorded result reflects the MECHANICAL grade — not the
  # experiential one. A grader `fail` on a structurally-sound run must not read as
  # a structural failure: the two verdicts are distinct axes (a mechanical floor
  # vs a quality opinion), and conflating them mislabels the artifact.
  if [ "$_gr_struct" = "false" ]; then
    printf 'fail %s' "$_gr_struct"
    return 0
  fi

  # Experiential verdict: the independent grader, or the human-rater degrade. The
  # agent NEVER scores its own session's quality (REQ-G1.4, REQ-H1.3).
  if [ -n "$grader_cmd" ]; then
    # Independence was checked at startup; re-affirm defensively.
    if [ "$grader_id" = "$DRIVER_ID" ]; then
      warn "[$_gr_persona] grade: grader id equals driver id (self-grading)"
      return 4
    fi
    # Only the merged FIXTURE-ONLY artifacts reach the third-party grader
    # (REQ-G1.6). Credentials, if any, are the grader command's own concern, read
    # from its environment — never passed here, never recorded.
    _gr_verdict="$("$grader_cmd" "$_gr_merged" 2>/dev/null)"
    _gr_grc=$?
    if [ "$_gr_grc" -ne 0 ]; then
      # Grader unavailable (failure / timeout / rate-limit): DEGRADE to the human
      # rater, do not fail the run, and substitute NO self-graded score.
      warn "[$_gr_persona] grade: independent grader unavailable (exit $_gr_grc) — degrading to human-rater"
      printf 'human-rater-required %s' "$_gr_struct"
      return 0
    fi
    case "$_gr_verdict" in
      pass) printf 'pass %s' "$_gr_struct" ;;
      fail) printf 'fail %s' "$_gr_struct" ;;
      *)
        warn "[$_gr_persona] grade: grader returned an unrecognized verdict — degrading to human-rater"
        printf 'human-rater-required %s' "$_gr_struct"
        ;;
    esac
    return 0
  fi

  # No independent grader configured: the experiential verdict is the human's.
  # The structural floor passed, but the harness records NO quality score of its
  # own (REQ-G1.4).
  printf 'human-rater-required %s' "$_gr_struct"
  return 0
}

# ---- result recording (allowlisted scalars) ----------------------------------
# record_result <fixture> <persona> <outcome> <structural> <cost> — build the
# scrubbed artifact by allowlist, re-verify only the allowed keys and no
# machine-local substring, then write it.
record_result() {
  _rr_art="$(jq -n \
    --arg fixture "$1" \
    --arg persona "$2" \
    --arg outcome "$3" \
    --arg driver_id "$DRIVER_ID" \
    --arg grader_id "${grader_id:-none}" \
    --argjson structural "$4" \
    --argjson cost "$5" \
    '{fixture: $fixture, persona: $persona, outcome: $outcome, driver_id: $driver_id, grader_id: $grader_id, structural_pass: $structural, cost_usd: $cost}' 2>/dev/null)"
  if [ -z "$_rr_art" ]; then
    warn "[$2] fail-closed — could not build result artifact"
    return 1
  fi
  _rr_extra="$(printf '%s' "$_rr_art" | jq -r 'keys - ["fixture","persona","outcome","driver_id","grader_id","structural_pass","cost_usd"] | .[]' 2>/dev/null)"
  if [ -n "$_rr_extra" ]; then
    warn "[$2] fail-closed — artifact carries disallowed keys: $_rr_extra"
    return 1
  fi
  if printf '%s' "$_rr_art" | grep -Eqi "$machine_local_re"; then
    warn "[$2] fail-closed — artifact contains a machine-local substring"
    return 1
  fi
  printf '%s\n' "$_rr_art" >"$record_dir/$1.$2.json" || {
    warn "[$2] cannot write artifact to '$record_dir'"
    return 1
  }
  printf '%s\n' "behavioral-eval: [$1/$2] recorded scrubbed result -> $record_dir/$1.$2.json"
  return 0
}

# ---- per-persona run ---------------------------------------------------------
# Sets the outcome via record_result / note_fail; returns 0 on a completed run
# (pass or human-rater-required or a graded fail) and a non-zero fatal code
# (3/4/5/6) that aborts the suite.
run_persona() {
  _rp_persona="$1"
  _rp_persona_file="$fx_dir/personas/$_rp_persona.persona"
  [ -f "$_rp_persona_file" ] || {
    warn "[$fx_id/$_rp_persona] no persona file at $_rp_persona_file"
    return 4
  }

  seq=$((seq + 1))
  _rp_run="$WORKBASE/$fx_id.$_rp_persona.$$.$seq"
  _rp_art="$_rp_run/artifacts"
  _rp_pane="$_rp_run/pane"
  _rp_pd="$_rp_run/pane-detect"
  _rp_merged="$_rp_run/merged.json"
  rm -rf "$_rp_run" 2>/dev/null
  mkdir -p "$_rp_art" "$_rp_pd" || {
    warn "[$fx_id/$_rp_persona] cannot create the run tree '$_rp_run'"
    return 5
  }

  # Path-safety: the launch string is interpolated into a tmux command, so the
  # skill and artifacts paths must be free of shell metacharacters and
  # whitespace. A hostile / unusual path is a clean refusal, never interpolated.
  case "$_rp_skill_abs$_rp_art" in
    *[!A-Za-z0-9._/-]*)
      warn "[$fx_id/$_rp_persona] refusing: a run path carries an unsafe character"
      containment_rm "$_rp_run" || return 5
      return 5
      ;;
  esac

  _rp_session="$(unique_session "$fx_id" "$_rp_persona")"
  reap_stale "$fx_id" "$_rp_persona" "$_rp_session"

  # Publishing disabled + eval-only marking are set in the session's environment
  # (REQ-G1.6): no eval run pushes / opens a PR / marks ready, and any
  # driver-produced sign-off is stamped non-authoritative.
  _rp_launch="env PLANWRIGHT_EVAL_ONLY=1 PLANWRIGHT_PUBLISH_DISABLED=1 sh $_rp_skill_abs $_rp_art"
  if ! tmux_new "$_rp_session" "$_rp_launch"; then
    warn "[$fx_id/$_rp_persona] could not start the tmux session"
    containment_rm "$_rp_run" || return 5
    return 3
  fi

  # ---- the driver loop: idle-detect, then answer the current turn ----------
  # Two bounds fire the fail-closed cost ceiling (REQ-G1.5): the TURN ceiling
  # (answers sent past the fixture's turn budget + margin — the direct analogue of
  # prompt-eval's per-run cap, and the bound the model-backed Task-6 surface binds
  # USD cost to), and the POLL ceiling (wall-clock polls, the backstop for a skill
  # that never advances a turn). Either tripping stops the run rc=6.
  _rp_max_turns="$turns"
  _rp_turn_cap=$((_rp_max_turns + 3))
  _rp_poll_cap=$((_rp_turn_cap * 60))
  _rp_last=0
  _rp_now=0
  _rp_poll=0
  _rp_sends=0
  _rp_rc=0
  while :; do
    _rp_poll=$((_rp_poll + 1))
    if [ "$_rp_poll" -gt "$_rp_poll_cap" ]; then
      warn "[$fx_id/$_rp_persona] poll ceiling hit without completion"
      _rp_rc=6
      break
    fi
    # `-ge`, not `-gt`: `_rp_sends` is incremented AFTER each send, so testing
    # `-ge` at the loop top stops once exactly `_rp_turn_cap` answers have been
    # sent — `-gt` would let a `cap + 1`th answer through before firing, one turn
    # past the intended `turns + 3` cost bound.
    if [ "$_rp_sends" -ge "$_rp_turn_cap" ]; then
      warn "[$fx_id/$_rp_persona] turn ceiling ($_rp_turn_cap) reached without completion"
      _rp_rc=6
      break
    fi
    if [ -f "$_rp_art/sign-off.json" ]; then
      _rp_rc=0
      break
    fi
    if ! tmux_alive "$_rp_session"; then
      # The session ended. If it wrote its sign-off we already broke above; an
      # ended session with no sign-off is an invalid run (crash / early exit).
      if [ -f "$_rp_art/sign-off.json" ]; then
        _rp_rc=0
      else
        warn "[$fx_id/$_rp_persona] session ended without writing a sign-off (invalid run)"
        _rp_rc=3
      fi
      break
    fi
    tmux_capture "$_rp_session" >"$_rp_pane" 2>/dev/null || : >"$_rp_pane"
    _rp_now=$((_rp_now + 1))
    _rp_verdict="$(FLEET_PANE_PROMPT_ANCHORS="$anchor" "$PANE_DETECT" classify \
      --pane "$_rp_pane" --backend in-session --worker "$_rp_session" \
      --scope eval --state-dir "$_rp_pd" --now "$_rp_now" \
      --footer-lines "$footer_lines" 2>/dev/null || echo indeterminate)"
    if [ "$_rp_verdict" = "idle" ]; then
      _rp_cur="$(current_turn "$_rp_pane")"
      case "$_rp_cur" in
        '' | *[!0-9]*) _rp_cur="" ;;
      esac
      if [ -n "$_rp_cur" ] && [ "$_rp_cur" -gt "$_rp_last" ]; then
        if _rp_ans="$(persona_answer "$_rp_persona_file" "$_rp_cur")"; then
          tmux_send "$_rp_session" "$_rp_ans"
          _rp_sends=$((_rp_sends + 1))
          _rp_last="$_rp_cur"
        else
          # The persona has no answer for this turn; nothing more to send. Let the
          # loop continue until the skill completes or the ceiling fires.
          _rp_last="$_rp_cur"
        fi
      fi
    fi
    case "$POLL_SLEEP" in
      '' | 0 | 0.0) : ;;
      *) sleep "$POLL_SLEEP" 2>/dev/null || : ;;
    esac
  done

  tmux_kill "$_rp_session" || true

  if [ "$_rp_rc" -ne 0 ]; then
    containment_rm "$_rp_run" || return 5
    return "$_rp_rc"
  fi

  # Eval-only verification (REQ-G1.6): a driver-produced sign-off must be marked
  # non-authoritative. Verify; if a fixture ever failed to mark it, stamp it here
  # so it can never be mistaken for a human sign-off, and warn.
  _rp_evalok="$(jq -r '(.eval_only == true) and (.authoritative == false)' "$_rp_art/sign-off.json" 2>/dev/null || echo false)"
  if [ "$_rp_evalok" != "true" ]; then
    warn "[$fx_id/$_rp_persona] sign-off was not marked eval-only/non-authoritative — stamping it"
    _rp_stamp="$(jq '. + {eval_only: true, authoritative: false}' "$_rp_art/sign-off.json" 2>/dev/null)"
    if [ -n "$_rp_stamp" ]; then
      printf '%s\n' "$_rp_stamp" >"$_rp_art/sign-off.json"
    fi
  fi

  # Grade the durable artifacts. grade_run emits `<outcome> <structural>`, so the
  # recorded structural verdict is the MECHANICAL grade, never re-derived from the
  # outcome token — a grader `fail` on a structurally sound run keeps
  # structural_pass true.
  _rp_graded="$(grade_run "$_rp_persona" "$_rp_art" "$_rp_merged")"
  _rp_grc=$?
  if [ "$_rp_grc" -ne 0 ]; then
    containment_rm "$_rp_run" || return 5
    return "$_rp_grc"
  fi
  _rp_outcome="${_rp_graded%% *}"
  _rp_struct="${_rp_graded##* }"

  # Surface a one-line, echo-safe summary of the graded subject.
  _rp_subject="$(sanitize_printable "$(jq -r '.sign_off.subject // ""' "$_rp_merged" 2>/dev/null)" "(none)")"
  printf '%s\n' "behavioral-eval: [$fx_id/$_rp_persona] outcome=$_rp_outcome subject=$_rp_subject"

  if [ -n "$record_dir" ]; then
    record_result "$fx_id" "$_rp_persona" "$_rp_outcome" "$_rp_struct" "0.000000" || {
      containment_rm "$_rp_run" || return 5
      return 4
    }
  fi

  case "$_rp_outcome" in
    fail) note_fail ;;
  esac

  # Fail-closed teardown (REQ-G1.5 / REQ-G1.6): a teardown or containment failure
  # is a re-runnability / safety hazard, surfaced fail-closed, never swallowed.
  containment_rm "$_rp_run" || return 5
  return 0
}

# ---- per-fixture -------------------------------------------------------------
run_fixture() {
  fx_dir="$1"
  [ -d "$fx_dir" ] || {
    warn "fixture dir not found: $fx_dir"
    return 2
  }
  # Canonicalize; guard the subshell so a cd failure (a TOCTOU removal between the
  # -d check above and here) is a clean refusal rather than an empty fx_dir that
  # would silently mis-resolve every path derived from it.
  fx_dir="$(cd "$fx_dir" 2>/dev/null && pwd -P)" || fx_dir=""
  [ -n "$fx_dir" ] || {
    warn "cannot resolve fixture dir '$(sanitize_printable "$1")'"
    return 2
  }
  fx_id="$(read_conf "$fx_dir" id)"
  [ -n "$fx_id" ] || fx_id="$(basename "$fx_dir")"
  case "$fx_id" in
    '' | *[!a-zA-Z0-9._-]*)
      warn "fixture id '$fx_id' has unsafe characters"
      return 2
      ;;
  esac

  _rf_skill="$(read_conf "$fx_dir" skill)"
  [ -n "$_rf_skill" ] || _rf_skill="skill.sh"
  case "$_rf_skill" in
    /*) _rp_skill_abs="$_rf_skill" ;;
    *) _rp_skill_abs="$fx_dir/$_rf_skill" ;;
  esac
  [ -f "$_rp_skill_abs" ] || {
    warn "[$fx_id] fixture skill not found: $_rp_skill_abs"
    return 2
  }

  turns="$(read_conf "$fx_dir" turns)"
  case "$turns" in
    '' | *[!0-9]*) turns=3 ;;
  esac

  # The positive at-prompt anchor the idle detector matches (lowercased), and the
  # footer window height it scans. Defaults suit a real Claude-TUI surface (its
  # `? for shortcuts` footer sits in the bottom ~8 rows); a fixture whose skill
  # prints top-down sets a larger footer_lines so its anchor is still inside the
  # scanned window (see the greeter fixture). Both are read as data.
  anchor="$(read_conf "$fx_dir" anchor)"
  [ -n "$anchor" ] || anchor="eval-ready"
  anchor="$(printf '%s' "$anchor" | tr '[:upper:]' '[:lower:]')"
  footer_lines="$(read_conf "$fx_dir" footer_lines)"
  case "$footer_lines" in
    '' | *[!0-9]* | 0) footer_lines=8 ;;
  esac

  # Personas: --persona overrides; else fixture.conf's list.
  _rf_personas="$only_personas"
  if [ -z "$_rf_personas" ]; then
    _rf_personas="$(read_conf "$fx_dir" personas)"
  fi
  [ -n "$_rf_personas" ] || {
    warn "[$fx_id] no personas to run (fixture.conf 'personas' empty and no --persona)"
    return 2
  }

  for _rf_p in $_rf_personas; do
    case "$_rf_p" in
      '' | *[!a-zA-Z0-9._-]*)
        warn "[$fx_id] persona name '$_rf_p' has unsafe characters"
        return 2
        ;;
    esac
    run_persona "$_rf_p"
    _rf_rc=$?
    case "$_rf_rc" in
      0) : ;;
      *) return "$_rf_rc" ;;
    esac
  done
  return 0
}

# ---- drive every fixture -----------------------------------------------------
# A here-doc (not a pipe) so the loop body runs in THIS shell — run_fixture must
# mutate overall_rc and the shared seq counter, which a pipe's subshell discards.
while IFS= read -r fx; do
  [ -n "$fx" ] || continue
  run_fixture "$fx"
  rc=$?
  case "$rc" in
    0) : ;;
    *) exit "$rc" ;;
  esac
done <<EOF
$fixtures
EOF

exit "$overall_rc"
