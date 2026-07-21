#!/bin/bash
# Tests for scripts/behavioral-eval.sh — the on-demand behavioral eval harness
# (operator-dialogue Task 5; REQ-G1.1–REQ-G1.6, D-8). A STUB tmux (env override
# BEHAVIORAL_EVAL_TMUX) replays the driver's sent answers through the REAL
# greeter fixture skill and grades the REAL artifacts, so every branch of the
# harness — the TTY-session drive loop, idle detection, persona divergence,
# artifact-only grading, grader independence and degradation, allowlisted-scalar
# recording, per-run-unique session names, stale-session reaping, and the
# security disciplines (send-keys sanitization, containment teardown, escape-safe
# logs, publishing-disabled launch, eval-only sign-off) — is exercised WITHOUT a
# real tmux, a live model, an API key, or spend. The unstubbed real-tmux path is
# the on-demand `mise run eval:behavioral` baseline ([manual] in test-spec).
#
# The stub is a faithful test double: it never re-implements the skill, it RUNS
# it (like prompt-eval.sh's tests run the plugin under a stubbed `claude`). Every
# fixture and persona input is data.
set -u
unset CDPATH

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RUNNER="$REPO_ROOT/scripts/behavioral-eval.sh"
FIXTURE="$REPO_ROOT/tests/behavioral-evals/fixtures/greeter"

failures=0
assert_exit() {
  if [ "$2" -eq "$3" ]; then
    echo "ok: $1"
  else
    echo "FAIL: $1 (expected exit $2, got $3)" >&2
    failures=$((failures + 1))
  fi
}
assert_contains() {
  case "$3" in
    *"$2"*) echo "ok: $1" ;;
    *)
      echo "FAIL: $1 (missing '$2')" >&2
      printf '%s\n' "----- output -----" "$3" "------------------" >&2
      failures=$((failures + 1))
      ;;
  esac
}
assert_absent() {
  case "$3" in
    *"$2"*)
      echo "FAIL: $1 (unexpected '$2')" >&2
      printf '%s\n' "----- output -----" "$3" "------------------" >&2
      failures=$((failures + 1))
      ;;
    *) echo "ok: $1" ;;
  esac
}
assert_eq() {
  if [ "$2" = "$3" ]; then
    echo "ok: $1"
  else
    echo "FAIL: $1 (expected '$2', got '$3')" >&2
    failures=$((failures + 1))
  fi
}

if [ ! -f "$RUNNER" ]; then
  echo "FAIL: runner missing at $RUNNER" >&2
  exit 1
fi
command -v jq >/dev/null 2>&1 || {
  echo "FAIL: jq required for these tests" >&2
  exit 1
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# ---- the stub tmux -----------------------------------------------------------
# Backs each "session" with a state dir. new-session records the launch and
# renders the first pane by running the skill with zero answers (it prints the
# turn-1 question + anchor, then EOF-exits). send-keys accumulates the driver's
# answers; each C-m replays ALL accumulated answers through the real skill,
# re-rendering the pane and — on the final answer — writing the durable
# artifacts. capture-pane cats the pane; has-session/kill-session/list-sessions
# complete the surface the harness funnels through tmux_*.
STUB="$TMP/tmux-stub.sh"
cat >"$STUB" <<'STUB_EOF'
#!/bin/sh
set -u
ST="${BEHAVIORAL_EVAL_TMUX_STATE:?stub needs BEHAVIORAL_EVAL_TMUX_STATE}"
mkdir -p "$ST" 2>/dev/null || true

# strip a leading '=' exact-match prefix from a target
untag() { printf '%s' "${1#=}"; }
# state dir for a session name (name is already grammar-safe)
sdir() { printf '%s/%s' "$ST" "$1"; }
# mark_liveness <state-dir> — model tmux session DEATH: under real tmux the pane
# dies when the launched skill exits. The stub can't keep a live process, so it
# infers death from the render: a skill that exited without leaving an at-prompt
# anchor (`turn=`) AND without writing a sign-off has terminated early (a crash /
# early-exit), and has-session must then report it dead so the harness's
# invalid-run (exit 3) branch is reachable. A completed run (sign-off present) is
# NOT dead — the harness breaks on the sign-off first, matching real tmux where
# the pane lingers after the skill exits.
mark_liveness() {
  _ml_d="$1"
  if ! grep -q 'turn=' "$_ml_d/pane" 2>/dev/null &&
    [ ! -f "$(cat "$_ml_d/art")/sign-off.json" ]; then
    : >"$_ml_d/dead"
  else
    rm -f "$_ml_d/dead" 2>/dev/null
  fi
}

sub="${1:-}"
shift 2>/dev/null || true

case "$sub" in
  new-session)
    name=""; launch=""
    while [ $# -gt 0 ]; do
      case "$1" in
        -d) shift ;;
        -s) name="$2"; shift 2 ;;
        -x | -y) shift 2 ;;
        *) launch="$1"; shift ;;
      esac
    done
    [ -n "$name" ] || exit 1
    d="$(sdir "$name")"; mkdir -p "$d/art-link" 2>/dev/null
    printf '%s' "$launch" >"$d/launch"
    : >"$d/answers"
    : >"$d/sends"
    # the harness pre-created the real art dir; the skill+art are the last two
    # whitespace tokens of the launch string.
    skill="$(printf '%s' "$launch" | awk '{print $(NF-1)}')"
    art="$(printf '%s' "$launch" | awk '{print $NF}')"
    printf '%s' "$skill" >"$d/skill"
    printf '%s' "$art" >"$d/art"
    # record the session name + launch for the test to assert on
    printf '%s\t%s\n' "$name" "$launch" >>"$ST/.new-sessions"
    # render the first pane (zero answers)
    sh "$skill" "$art" </dev/null >"$d/pane" 2>&1
    mark_liveness "$d"
    exit 0
    ;;
  capture-pane)
    name=""
    while [ $# -gt 0 ]; do
      case "$1" in
        -p | -e) shift ;;
        -t) name="$(untag "$2")"; shift 2 ;;
        -S) shift 2 ;;
        *) shift ;;
      esac
    done
    d="$(sdir "$name")"
    [ -f "$d/pane" ] && cat "$d/pane"
    exit 0
    ;;
  send-keys)
    name=""; literal=0; text=""; enter=0
    while [ $# -gt 0 ]; do
      case "$1" in
        -t) name="$(untag "$2")"; shift 2 ;;
        -l) literal=1; shift ;;
        --) shift; text="${1:-}"; shift 2>/dev/null || shift $# ;;
        C-m) enter=1; shift ;;
        *) shift ;;
      esac
    done
    d="$(sdir "$name")"
    [ -d "$d" ] || exit 0
    if [ "$literal" -eq 1 ]; then
      # buffer the literal text and record exactly what was sent. The persistent
      # copy under $ST survives kill-session teardown, so a test can assert on the
      # sanitized bytes after the run completes.
      printf '%s' "$text" >"$d/pending"
      printf '%s\n' "$text" >>"$d/sends"
      { printf '%s\t' "$name"; printf '%s' "$text" | od -An -c | tr -d '\n'; printf '\n'; } >>"$ST/.sends-log"
    fi
    if [ "$enter" -eq 1 ]; then
      pend=""; [ -f "$d/pending" ] && pend="$(cat "$d/pending")"
      printf '%s\n' "$pend" >>"$d/answers"
      : >"$d/pending"
      skill="$(cat "$d/skill")"; art="$(cat "$d/art")"
      # replay ALL accumulated answers through the real skill
      sh "$skill" "$art" <"$d/answers" >"$d/pane" 2>&1
      mark_liveness "$d"
    fi
    exit 0
    ;;
  has-session)
    name=""
    while [ $# -gt 0 ]; do
      case "$1" in
        -t) name="$(untag "$2")"; shift 2 ;;
        *) shift ;;
      esac
    done
    d="$(sdir "$name")"
    { [ -d "$d" ] && [ ! -f "$d/dead" ]; } && exit 0
    exit 1
    ;;
  kill-session)
    name=""
    while [ $# -gt 0 ]; do
      case "$1" in
        -t) name="$(untag "$2")"; shift 2 ;;
        *) shift ;;
      esac
    done
    rm -rf "$(sdir "$name")" 2>/dev/null
    exit 0
    ;;
  list-sessions)
    for d in "$ST"/*/; do
      [ -d "$d" ] || continue
      b="$(basename "$d")"
      printf '%s\n' "$b"
    done
    exit 0
    ;;
  *) exit 0 ;;
esac
STUB_EOF
chmod +x "$STUB"

# run_harness <workdir> <extra-args...> — invoke the harness against the greeter
# fixture with the stub tmux and a fresh state. Sets the globals OUT (combined
# output), RC (exit code), and STATE (stub state dir). Call it DIRECTLY, never in
# a command substitution — `x="$(run_harness ...)"` would run it in a subshell
# and the RC it sets would be lost to the parent (asserting a stale RC).
RC=0
OUT=""
STATE=""
run_harness() {
  wd="$1"
  shift
  STATE="$wd/tmux-state"
  rm -rf "$wd"
  mkdir -p "$wd/wb" "$wd/rec" "$STATE"
  OUT="$(BEHAVIORAL_EVAL_TMUX="$STUB" \
    BEHAVIORAL_EVAL_TMUX_STATE="$STATE" \
    BEHAVIORAL_EVAL_WORKBASE="$wd/wb" \
    BEHAVIORAL_EVAL_POLL_SLEEP=0 \
    /bin/sh "$RUNNER" --record "$wd/rec" "$@" "$FIXTURE" 2>&1)"
  RC=$?
}

# A single main run drives BOTH personas under a grader that records depth and
# self-checks it received only structured fixture artifacts (no pane text, no
# credential/driver keys). Most G1.1/G1.2/G1.3/G1.5/G1.6 assertions read from it,
# keeping the (slow, per-poll) driver loop to as few runs as possible.
GSTUB="$TMP/grader.sh"
cat >"$GSTUB" <<GRADER_EOF
#!/bin/sh
merged="\$1"
jq -r '"\(.persona) depth=\(.sign_off.depth)"' "\$merged" >>"$TMP/observed.txt" 2>/dev/null
# grade the ARTIFACTS the run wrote, not a scraped pane: the merged object must
# carry the structured sign_off + decision_log and NONE of a pane's anchor text
# or the harness's own driver/credential fields.
jq -e 'has("sign_off") and has("decision_log") and (.sign_off.subject|length>0)' "\$merged" >/dev/null 2>&1 || { echo fail; exit 0; }
if jq -e 'has("credential") or has("token") or has("driver_id")' "\$merged" >/dev/null 2>&1; then echo fail; exit 0; fi
if grep -q "EVAL-READY" "\$merged" 2>/dev/null; then echo fail; exit 0; fi
echo pass
GRADER_EOF
chmod +x "$GSTUB"
rm -f "$TMP/observed.txt"
MAIN="$TMP/main"
run_harness "$MAIN" --grader "$GSTUB" --grader-id ext-panel
mainout="$OUT"

echo "== G1.1: end-to-end persona-driven run, artifact-graded result =="
assert_exit "the persona-driven run completes end-to-end" 0 "$RC"
assert_contains "an outcome is reported per persona" "outcome=pass" "$mainout"
assert_eq "a scalar result is recorded" "greeter" "$(jq -r .fixture "$MAIN/rec/greeter.novice.json" 2>/dev/null)"
assert_eq "the structural grade passed" "true" "$(jq -r .structural_pass "$MAIN/rec/greeter.novice.json" 2>/dev/null)"

echo "== G1.2: persona-parameterized driver — novice vs expert divergence =="
obs="$(cat "$TMP/observed.txt" 2>/dev/null)"
assert_contains "novice pitched at full depth" "novice depth=full" "$obs"
assert_contains "expert pitched at brief depth" "expert depth=brief" "$obs"
assert_eq "both sessions' graded artifacts recorded (expert)" "pass" "$(jq -r .outcome "$MAIN/rec/greeter.expert.json" 2>/dev/null)"

echo "== G1.3: grading reads artifacts, never a scraped pane =="
# the grader (GSTUB) fails loud on pane text / non-fixture keys; a pass proves it
# graded the structured artifacts alone.
assert_eq "grader saw structured artifacts, not pane text" "pass" "$(jq -r .outcome "$MAIN/rec/greeter.novice.json" 2>/dev/null)"

echo "== G1.4: independent grader — self-grading refused; unavailable degrades =="
# (a) grader id equal to driver id is self-grading -> fail-closed at startup
w="$TMP/g14a"
STATE="$w/st"
mkdir -p "$w/wb" "$STATE"
out="$(BEHAVIORAL_EVAL_TMUX="$STUB" BEHAVIORAL_EVAL_TMUX_STATE="$STATE" \
  BEHAVIORAL_EVAL_WORKBASE="$w/wb" BEHAVIORAL_EVAL_POLL_SLEEP=0 \
  BEHAVIORAL_EVAL_DRIVER_ID=sameperson \
  /bin/sh "$RUNNER" --persona novice --grader /bin/true --grader-id sameperson "$FIXTURE" 2>&1)"
assert_exit "grader id == driver id is refused fail-closed" 4 "$?"
assert_contains "self-grading refusal is explained" "self-grading" "$out"
# (b) grader unavailable (non-zero) -> degrade to human-rater, run not failed
GBAD="$TMP/grader-bad.sh"
printf '#!/bin/sh\nexit 7\n' >"$GBAD"
chmod +x "$GBAD"
w="$TMP/g14b"
run_harness "$w" --persona novice --grader "$GBAD" --grader-id ext-panel
out="$OUT"
assert_exit "an unavailable grader does not fail the run" 0 "$RC"
assert_contains "degrades to human-rater on grader failure" "degrading to human-rater" "$out"
assert_eq "no self-graded score substituted on degrade" "human-rater-required" "$(jq -r .outcome "$w/rec/greeter.novice.json" 2>/dev/null)"

echo "== G1.5: per-run-unique session names; stale-session reaping; scalar results =="
# unique names: the MAIN run's two personas produced two DIFFERENT session names.
n1="$(sed -n '1p' "$MAIN/tmux-state/.new-sessions" | cut -f1)"
n2="$(sed -n '2p' "$MAIN/tmux-state/.new-sessions" | cut -f1)"
if [ -n "$n1" ] && [ -n "$n2" ] && [ "$n1" != "$n2" ]; then
  echo "ok: per-run session names are unique"
else
  echo "FAIL: session names not unique ('$n1' vs '$n2')" >&2
  failures=$((failures + 1))
fi
# the uniqueness guarantee rests on the urandom NONCE, not just persona/seq/pid:
# assert each name ends in an 8-hex-digit nonce segment (so an empty-nonce
# regression that still varies by persona would be caught).
case "$n1" in
  planwright-eval-greeter-*-[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]) echo "ok: session name carries a urandom nonce segment" ;;
  *)
    echo "FAIL: session name '$n1' lacks the 8-hex nonce segment" >&2
    failures=$((failures + 1))
    ;;
esac
# stale-session reaping: pre-seed a stale session for this fixture+persona
w="$TMP/g15b"
STATE="$w/tmux-state"
rm -rf "$w"
mkdir -p "$w/wb" "$w/rec" "$STATE/planwright-eval-greeter-novice-STALE99"
out="$(BEHAVIORAL_EVAL_TMUX="$STUB" BEHAVIORAL_EVAL_TMUX_STATE="$STATE" \
  BEHAVIORAL_EVAL_WORKBASE="$w/wb" BEHAVIORAL_EVAL_POLL_SLEEP=0 \
  /bin/sh "$RUNNER" --record "$w/rec" --persona novice "$FIXTURE" 2>&1)"
assert_contains "a stale eval session is reaped" "reaped stale eval session planwright-eval-greeter-novice-STALE99" "$out"
[ -d "$STATE/planwright-eval-greeter-novice-STALE99" ] \
  && {
    echo "FAIL: stale session was not removed" >&2
    failures=$((failures + 1))
  } \
  || echo "ok: stale session removed"
# allowlisted scalar-only result: only the allowed keys.
keys="$(jq -r 'keys | sort | join(",")' "$MAIN/rec/greeter.novice.json" 2>/dev/null)"
assert_eq "result carries only allowlisted keys" "cost_usd,driver_id,fixture,grader_id,outcome,persona,structural_pass" "$keys"
# containment-checked teardown removed the disposable run tree.
assert_eq "disposable run tree is torn down (work base empty)" "" "$(ls "$MAIN/wb" 2>/dev/null)"

echo "== G1.6: persona text sanitized before send-keys; escape-safe structured log =="
# ONE run covers both: a persona whose answer.1 carries control bytes (BEL, ESC)
# AND a JSON-breaking quote+backslash. The sent bytes must be stripped of the
# control bytes before send-keys; the resulting artifacts must stay valid JSON.
SANFIX="$TMP/sanfix"
mkdir -p "$SANFIX/personas"
cp "$FIXTURE/skill.sh" "$SANFIX/skill.sh"
cp "$FIXTURE/grade.jq" "$SANFIX/grade.jq"
cat >"$SANFIX/fixture.conf" <<'CONF'
id=sanfix
skill=skill.sh
personas=ctrl
turns=3
anchor=eval-ready
footer_lines=50
CONF
# answer.1 = printable 'A b X "q\z"' wrapped around a BEL (\007) and ESC (\033).
printf 'expertise=novice\nanswer.1=A\007b\033X "q\\z"\nanswer.2=novice\nanswer.3=approve-and-record\n' >"$SANFIX/personas/ctrl.persona"
GESC="$TMP/grader-esc.sh"
cat >"$GESC" <<'GESC_EOF'
#!/bin/sh
jq -e . "$1" >/dev/null 2>&1 && echo pass || echo fail
GESC_EOF
chmod +x "$GESC"
w="$TMP/g16san"
STATE="$w/tmux-state"
rm -rf "$w"
mkdir -p "$w/wb" "$w/rec" "$STATE"
out="$(BEHAVIORAL_EVAL_TMUX="$STUB" BEHAVIORAL_EVAL_TMUX_STATE="$STATE" \
  BEHAVIORAL_EVAL_WORKBASE="$w/wb" BEHAVIORAL_EVAL_POLL_SLEEP=0 \
  /bin/sh "$RUNNER" --record "$w/rec" --persona ctrl --grader "$GESC" --grader-id ext "$SANFIX" 2>&1)"
assert_exit "control-byte persona run completes" 0 "$?"
# the persistent sends-log (survives kill-session) records the od -c dump of each
# literal send; the first send must be stripped of the BEL (\a) and ESC (033).
firstsend="$(sed -n '1p' "$STATE/.sends-log" | cut -f2)"
assert_absent "no BEL byte reached send-keys" "\\a" "$firstsend"
assert_absent "no ESC byte reached send-keys" "033" "$firstsend"
assert_contains "the printable answer content survived sanitization" "A   b   X" "$firstsend"
# escape-safe: the JSON-breaking quote+backslash did not corrupt the artifacts.
assert_eq "a JSON-breaking answer keeps the artifacts valid JSON" "pass" "$(jq -r .outcome "$w/rec/sanfix.ctrl.json" 2>/dev/null)"

echo "== G1.6: publishing-disabled + eval-only launch env =="
launch="$(sed -n '1p' "$MAIN/tmux-state/.new-sessions" | cut -f2)"
assert_contains "launch disables publishing" "PLANWRIGHT_PUBLISH_DISABLED=1" "$launch"
assert_contains "launch marks the run eval-only" "PLANWRIGHT_EVAL_ONLY=1" "$launch"

echo "== G1.6: eval-only / non-authoritative sign-off; stamped if a skill omits it =="
assert_eq "recorded runs come from eval-only sign-offs (structural grade enforces it)" \
  "true" "$(jq -r .structural_pass "$MAIN/rec/greeter.novice.json" 2>/dev/null)"
# a fixture skill that writes a NON-eval-only sign-off is stamped by the harness
NOEVAL="$TMP/noeval"
mkdir -p "$NOEVAL/personas"
cat >"$NOEVAL/fixture.conf" <<'CONF'
id=noeval
skill=skill.sh
personas=novice
turns=1
anchor=eval-ready
footer_lines=50
CONF
printf 'expertise=novice\nanswer.1=Zed\n' >"$NOEVAL/personas/novice.persona"
# a one-turn skill that writes an AUTHORITATIVE sign-off (the harness must stamp it)
cat >"$NOEVAL/skill.sh" <<'SK'
#!/bin/sh
set -u
art="$1"; mkdir -p "$art"
: >"$art/decision-log.jsonl"
printf 'Greeter: name?\nEVAL-READY turn=1\n'
IFS= read -r name || exit 0
jq -cn --arg a "$name" '{turn:1,question:"name",answer:$a}' >>"$art/decision-log.jsonl"
# deliberately authoritative + not eval-only, to exercise the harness stamp
jq -n --arg s "$name" '{subject:$s, decision:"x", eval_only:false, authoritative:true}' >"$art/sign-off.json"
SK
cp "$FIXTURE/grade.jq" "$NOEVAL/grade.jq"
chmod +x "$NOEVAL/skill.sh"
w="$TMP/g16stamp"
STATE="$w/tmux-state"
rm -rf "$w"
mkdir -p "$w/wb" "$w/rec" "$STATE"
out="$(BEHAVIORAL_EVAL_TMUX="$STUB" BEHAVIORAL_EVAL_TMUX_STATE="$STATE" \
  BEHAVIORAL_EVAL_WORKBASE="$w/wb" BEHAVIORAL_EVAL_POLL_SLEEP=0 \
  /bin/sh "$RUNNER" --record "$w/rec" --persona novice "$NOEVAL" 2>&1)"
assert_contains "harness warns it stamped a non-eval-only sign-off" "stamping it" "$out"
# after stamping, the structural grade (eval_only && !authoritative) passes
assert_eq "a stamped sign-off grades eval-only" "true" "$(jq -r .structural_pass "$w/rec/noeval.novice.json" 2>/dev/null)"

echo "== fail path: a graded fail exits 1 but keeps structural_pass true =="
# an independent grader that returns `fail` on a structurally-sound run: the
# outcome is a graded fail (exit 1), but the MECHANICAL structural grade held, so
# structural_pass must stay true (the conflation bug this guards against).
GFAIL="$TMP/grader-fail.sh"
cat >"$GFAIL" <<'GF'
#!/bin/sh
echo fail
GF
chmod +x "$GFAIL"
w="$TMP/gfail"
run_harness "$w" --persona novice --grader "$GFAIL" --grader-id ext
out="$OUT"
assert_exit "a graded fail exits 1" 1 "$RC"
assert_eq "the fail outcome is recorded" "fail" "$(jq -r .outcome "$w/rec/greeter.novice.json" 2>/dev/null)"
assert_eq "structural_pass stays true on an experiential fail" "true" "$(jq -r .structural_pass "$w/rec/greeter.novice.json" 2>/dev/null)"

echo "== fail path: a structural (grade.jq) failure records structural_pass false =="
# a fixture whose grade.jq is unconditionally false: outcome fail, structural
# false, exit 1 — the other axis of the structural_pass fix.
SFAIL="$TMP/sfail"
mkdir -p "$SFAIL/personas"
cp "$FIXTURE/skill.sh" "$SFAIL/skill.sh"
printf 'false\n' >"$SFAIL/grade.jq"
cat >"$SFAIL/fixture.conf" <<'CONF'
id=sfail
skill=skill.sh
personas=novice
turns=3
anchor=eval-ready
footer_lines=50
CONF
printf 'expertise=novice\nanswer.1=Ada\nanswer.2=novice\nanswer.3=approve-and-record\n' >"$SFAIL/personas/novice.persona"
w="$TMP/gsfail"
STATE="$w/tmux-state"
rm -rf "$w"
mkdir -p "$w/wb" "$w/rec" "$STATE"
out="$(BEHAVIORAL_EVAL_TMUX="$STUB" BEHAVIORAL_EVAL_TMUX_STATE="$STATE" \
  BEHAVIORAL_EVAL_WORKBASE="$w/wb" BEHAVIORAL_EVAL_POLL_SLEEP=0 \
  /bin/sh "$RUNNER" --record "$w/rec" --persona novice "$SFAIL" 2>&1)"
assert_exit "a structural failure exits 1" 1 "$?"
assert_eq "structural_pass is false on a structural failure" "false" "$(jq -r .structural_pass "$w/rec/sfail.novice.json" 2>/dev/null)"

echo "== invalid run: a skill that exits without a sign-off is exit 3 =="
# the harness's core liveness claim: a session that dies without writing its
# durable sign-off is an invalid run, not a graded result.
CRASH="$TMP/crash"
mkdir -p "$CRASH/personas"
cat >"$CRASH/fixture.conf" <<'CONF'
id=crash
skill=skill.sh
personas=novice
turns=1
anchor=eval-ready
footer_lines=50
CONF
printf 'expertise=novice\nanswer.1=Ada\n' >"$CRASH/personas/novice.persona"
# a skill that prints a line WITHOUT an at-prompt anchor and exits — no sign-off
cat >"$CRASH/skill.sh" <<'SK'
#!/bin/sh
printf 'Greeter: boom — crashing before any prompt\n'
exit 0
SK
cp "$FIXTURE/grade.jq" "$CRASH/grade.jq"
chmod +x "$CRASH/skill.sh"
w="$TMP/gcrash"
STATE="$w/tmux-state"
rm -rf "$w"
mkdir -p "$w/wb" "$w/rec" "$STATE"
out="$(BEHAVIORAL_EVAL_TMUX="$STUB" BEHAVIORAL_EVAL_TMUX_STATE="$STATE" \
  BEHAVIORAL_EVAL_WORKBASE="$w/wb" BEHAVIORAL_EVAL_POLL_SLEEP=0 \
  /bin/sh "$RUNNER" --record "$w/rec" --persona novice "$CRASH" 2>&1)"
assert_exit "a session that dies without a sign-off is an invalid run (exit 3)" 3 "$?"
assert_contains "the invalid run is explained" "without writing a sign-off" "$out"

echo "== suite mode: --suite runs every fixture; overall rc survives the loop =="
# two fixtures under a suite root; a here-doc (not a pipe) keeps overall_rc/seq
# alive across fixtures, so a passing and a failing fixture both land.
SUITE="$TMP/suite"
mkdir -p "$SUITE"
cp -R "$FIXTURE" "$SUITE/greeter"
cp -R "$SFAIL" "$SUITE/sfail"
w="$TMP/gsuite"
STATE="$w/tmux-state"
rm -rf "$w"
mkdir -p "$w/wb" "$w/rec" "$STATE"
out="$(BEHAVIORAL_EVAL_TMUX="$STUB" BEHAVIORAL_EVAL_TMUX_STATE="$STATE" \
  BEHAVIORAL_EVAL_WORKBASE="$w/wb" BEHAVIORAL_EVAL_POLL_SLEEP=0 \
  /bin/sh "$RUNNER" --record "$w/rec" --persona novice --suite "$SUITE" 2>&1)"
srrc=$?
assert_eq "both suite fixtures produced a result (greeter)" "greeter" "$(jq -r .fixture "$w/rec/greeter.novice.json" 2>/dev/null)"
assert_eq "both suite fixtures produced a result (sfail)" "sfail" "$(jq -r .fixture "$w/rec/sfail.novice.json" 2>/dev/null)"
assert_exit "the failing fixture makes the suite exit 1 (overall_rc survived the loop)" 1 "$srrc"

echo "== cost bound: a never-completing dialogue trips the turn ceiling (exit 6) =="
# a skill that emits a fresh turn on every answer and never writes a sign-off; the
# driver keeps answering until sends exceed the turn ceiling (turns+3), then stops
# fail-closed rc=6 rather than looping to the poll ceiling.
LOOP="$TMP/loop"
mkdir -p "$LOOP/personas"
cat >"$LOOP/fixture.conf" <<'CONF'
id=loop
skill=skill.sh
personas=novice
turns=1
anchor=eval-ready
footer_lines=50
CONF
printf 'expertise=novice\nanswer.1=a\nanswer.2=b\nanswer.3=c\nanswer.4=d\nanswer.5=e\nanswer.6=f\n' >"$LOOP/personas/novice.persona"
cat >"$LOOP/skill.sh" <<'SK'
#!/bin/sh
art="$1"; mkdir -p "$art"; : >"$art/decision-log.jsonl"
n=1
while :; do
  printf 'EVAL-READY turn=%s\n' "$n"
  IFS= read -r a || exit 0
  n=$((n + 1))
done
SK
cp "$FIXTURE/grade.jq" "$LOOP/grade.jq"
chmod +x "$LOOP/skill.sh"
w="$TMP/gloop"
STATE="$w/tmux-state"
rm -rf "$w"
mkdir -p "$w/wb" "$w/rec" "$STATE"
out="$(BEHAVIORAL_EVAL_TMUX="$STUB" BEHAVIORAL_EVAL_TMUX_STATE="$STATE" \
  BEHAVIORAL_EVAL_WORKBASE="$w/wb" BEHAVIORAL_EVAL_POLL_SLEEP=0 \
  /bin/sh "$RUNNER" --record "$w/rec" --persona novice "$LOOP" 2>&1)"
assert_exit "a never-completing dialogue trips the turn ceiling (exit 6)" 6 "$?"
assert_contains "the turn ceiling is named" "turn ceiling" "$out"

echo "== usage/guard: --grader without --grader-id is a usage error =="
out="$(BEHAVIORAL_EVAL_TMUX="$STUB" /bin/sh "$RUNNER" --grader /bin/true "$FIXTURE" 2>&1)"
assert_exit "grader without grader-id is rejected" 2 "$?"
out="$(/bin/sh "$RUNNER" 2>&1)"
assert_exit "no fixtures is a usage error" 2 "$?"

if [ "$failures" -eq 0 ]; then
  echo "PASS: all behavioral-eval harness tests passed"
  exit 0
else
  echo "FAIL: $failures assertion(s) failed" >&2
  exit 1
fi
