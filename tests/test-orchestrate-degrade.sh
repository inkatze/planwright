#!/bin/bash
# Tests for scripts/orchestrate-degrade.sh — the graceful-degradation LADDER,
# the synchronous terminal rung, and runtime FAILOVER for /orchestrate
# (orchestration-fleet Task 3; D-3, REQ-B1.4, REQ-B1.5, REQ-B1.6, REQ-A1.4).
#
# This is the Task 3 counterpart to Task 2's orchestrate-backends.sh (detect +
# selection-time pick). Task 2 explicitly deferred "the full richest-to-safest
# ladder, runtime failover, and the degrade-capability-never-safety abort" to
# Task 3; this script realizes them on top of the same Task 1 capability
# contract (doctrine/backend-capability-contract.md, D-2).
#
# Contract under test:
#   - `rung <backend|caps6>` reports a backend's ladder rung by its ADVERTISED
#     set (D-3, ordered richest->safest): 1 interactive+steer (tmux); 2 headless
#     pool (session-grade parallel) OR interactive-without-steer; 3 in-harness
#     parallel not-session-grade (subagent); 4 synchronous single-stream
#     (in-session — the terminal rung). Classification is TOTAL over well-formed
#     caps. A spawn-deferred backend (print) is `manual` — off the autonomous
#     ladder. A hostile/malformed arg exits 2.
#   - `terminal-plan <id>...` emits the synchronous terminal rung's run plan:
#     one `run <id>` line per unit with a `context-clear` line BETWEEN
#     consecutive units (bounded-context clears; never after the last). Ids are
#     validated against the task-id grammar before use; a hostile id or no id
#     exits 2 with no output.
#   - `record <spec-dir> <backend>` writes the effective backend spec-locally to
#     `<spec-dir>/.orchestrate/effective-backend` atomically; NEVER to tasks.md.
#     `read <spec-dir>` prints it back (exit 1 when absent, on a non-regular
#     record, or on a malformed value). A hostile backend name, a symlink /
#     non-regular file at the path, or an unwritable dir is refused fail-closed.
#   - `failover <spec-dir> <current> [candidate...]` descends one rung down the
#     available ladder to the richest present, guard-preserving (non-interactive,
#     non-deferred) backend strictly below the current rung — classifying
#     candidates by their advertised set (shipped via the table, pluggable via a
#     `planwright-backend-<name>` adapter); records the effective backend
#     spec-locally; emits a NOTE (stderr) + an `## Awaiting input` entry (stdout);
#     exit 0. It ESCALATES (exit 3, never a silent downgrade) with a DISTINCT
#     reason for the terminal-rung floor vs a lower rung that would drop a guard;
#     a record-write failure aborts (exit 3) rather than proceeding unrecorded.
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH
unset PLANWRIGHT_ORCH_STATE_DIR PLANWRIGHT_BACKEND_TMUX PLANWRIGHT_BACKEND_SUBAGENT

here=$(cd "$(dirname "$0")" && pwd)
DEGRADE="$here/../scripts/orchestrate-degrade.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -x "$DEGRADE" ] || fail "scripts/orchestrate-degrade.sh missing or not executable"

tmp=$(mktemp -d)
trap 'chmod -R u+rwx "$tmp" 2>/dev/null; rm -rf "$tmp"' EXIT

# A bin dir seeded with fake pluggable-backend adapters, so failover can be
# exercised against a rung-2 pool (the middle rung no shipped backend occupies)
# and an interactive (guard-dropping) lower rung — mirrors how
# test-orchestrate-backends.sh fakes adapters on PATH. Prepended to PATH only
# for the calls that need it.
BIN="$tmp/bin"
mkdir -p "$BIN"
# A non-interactive session-grade parallel pool → rung 2, guard-preserving.
cat >"$BIN/planwright-backend-pool" <<'EOF'
#!/bin/sh
[ "$1" = advertise ] && echo "false false false false true yes"
EOF
# An interactive session-grade parallel pool → rung 2, NOT guard-preserving
# (interactive would strand an unattended run).
cat >"$BIN/planwright-backend-ipool" <<'EOF'
#!/bin/sh
[ "$1" = advertise ] && echo "true false false false true yes"
EOF
chmod +x "$BIN/planwright-backend-pool" "$BIN/planwright-backend-ipool"

# A fresh spec-dir fixture with the four spec files a real bundle carries, so the
# script's spec-dir checks see a plausible directory. tasks.md is seeded so a
# test can assert the script NEVER writes it (REQ-B1.6 / REQ-A1.1).
new_spec_dir() {
  nsd=$(mktemp -d "$tmp/spec.XXXXXX")
  for f in requirements.md design.md tasks.md test-spec.md; do
    printf '# %s\n\n## Awaiting input\n\n(none)\n' "$f" >"$nsd/$f"
  done
  printf '%s' "$nsd"
}

# --- rung classification (the ladder ordering by advertised set) -------------

check_rung() { # <caps-or-backend> <expected>
  cr_got=$("$DEGRADE" rung "$1") || fail "rung '$1' exited nonzero"
  [ "$cr_got" = "$2" ] || fail "rung '$1': expected '$2', got '$cr_got'"
}
check_rung tmux 1
check_rung subagent 3
check_rung in-session 4
check_rung print manual
# A headless `claude -p` pool: session-grade + parallel, no live steer → rung 2.
check_rung "false false false false true yes" 2
# An interactive multiplexer WITHOUT steer → also rung 2 (near the fallback).
check_rung "true false false false true yes" 2
# Total classifier: a session-grade parallel pool whose steer is `na` or `true`
# still classifies as rung 2 (it is not rung 1, which requires interactivity),
# never "unclassifiable" (regression guard for the non-total classifier).
check_rung "false na na false true yes" 2
check_rung "false false true false true yes" 2
# A non-interactive single-stream backend is the terminal rung 4 regardless of
# session-grade.
check_rung "false na na false false no" 4

# Hostile / malformed args are refused, not classified.
for bad in "../../etc/passwd" "not-a-real-backend" "true false" "true true true false true bogus"; do
  if "$DEGRADE" rung "$bad" >/dev/null 2>&1; then
    fail "rung accepted a bad arg '$bad'"
  fi
done

# --- synchronous terminal rung: single-stream run with bounded-context clears -

plan=$("$DEGRADE" terminal-plan 1 2 3) || fail "terminal-plan exited nonzero"
expected=$(printf 'run 1\ncontext-clear\nrun 2\ncontext-clear\nrun 3')
[ "$plan" = "$expected" ] || fail "terminal-plan 1 2 3 wrong plan:
--- got ---
$plan
--- want ---
$expected"

# A single unit: one run line, NO trailing context-clear.
plan=$("$DEGRADE" terminal-plan 5) || fail "terminal-plan single exited nonzero"
[ "$plan" = "run 5" ] || fail "terminal-plan 5: expected 'run 5', got '$plan'"

# A cohesion-bundle sub-id (dotted) is a valid task id.
plan=$("$DEGRADE" terminal-plan 3.5) || fail "terminal-plan dotted id exited nonzero"
[ "$plan" = "run 3.5" ] || fail "terminal-plan 3.5: expected 'run 3.5', got '$plan'"

# A hostile id is refused with no plan emitted (REQ-F1.1: parsed input is data).
for bad in "../x" "1;rm -rf" "5-6" "*" ""; do
  if out=$("$DEGRADE" terminal-plan "$bad" 2>/dev/null); then
    fail "terminal-plan accepted hostile id '$bad'"
  fi
  [ -z "${out:-}" ] || fail "terminal-plan emitted output for hostile id '$bad'"
done

# No ids at all is a usage error (exit 2).
if "$DEGRADE" terminal-plan >/dev/null 2>&1; then
  fail "terminal-plan with no ids should exit nonzero"
fi

# --- effective-backend record: spec-local, never tasks.md (REQ-B1.6) ---------

sd=$(new_spec_dir)
tasks_before=$(cat "$sd/tasks.md")

"$DEGRADE" record "$sd" subagent || fail "record subagent exited nonzero"
rec="$sd/.orchestrate/effective-backend"
[ -f "$rec" ] || fail "record did not write $rec"
grep -q "subagent" "$rec" || fail "record file missing the backend name"
# The record must NOT touch tasks.md.
[ "$(cat "$sd/tasks.md")" = "$tasks_before" ] || fail "record MUTATED tasks.md (REQ-B1.6 violation)"

got=$("$DEGRADE" read "$sd") || fail "read exited nonzero after record"
[ "$got" = subagent ] || fail "read: expected 'subagent', got '$got'"

# read on a spec dir with no record exits EXACTLY 1 (absent), not a usage 2.
sd2=$(new_spec_dir)
"$DEGRADE" read "$sd2" >/dev/null 2>&1 && rc=0 || rc=$?
[ "$rc" = 1 ] || fail "read with no record: expected exit 1, got $rc"

# read tolerates a record written WITHOUT a trailing newline (external writer).
sd_nl=$(new_spec_dir)
mkdir -p "$sd_nl/.orchestrate"
printf 'subagent\t9' >"$sd_nl/.orchestrate/effective-backend"
got=$("$DEGRADE" read "$sd_nl") || fail "read of a newline-less record exited nonzero"
[ "$got" = subagent ] || fail "read newline-less: expected 'subagent', got '$got'"

# read refuses a symlink at the record path (write-path parity), reporting no
# valid record (exit 1) rather than following it.
sd_sl=$(new_spec_dir)
mkdir -p "$sd_sl/.orchestrate"
printf 'secret\n' >"$tmp/leak-target"
ln -s "$tmp/leak-target" "$sd_sl/.orchestrate/effective-backend"
out=$("$DEGRADE" read "$sd_sl" 2>/dev/null) && rc=0 || rc=$?
[ "$rc" = 1 ] || fail "read of a symlink record: expected exit 1, got $rc"
[ "${out:-}" != secret ] || fail "read followed a symlink and leaked target content"

# An empty record file is "no valid record" (exit 1), not a crash.
sd_empty=$(new_spec_dir)
mkdir -p "$sd_empty/.orchestrate"
: >"$sd_empty/.orchestrate/effective-backend"
"$DEGRADE" read "$sd_empty" >/dev/null 2>&1 && rc=0 || rc=$?
[ "$rc" = 1 ] || fail "read of an empty record: expected exit 1, got $rc"

# read refuses a malformed (tampered) value rather than emitting it raw.
sd_bad=$(new_spec_dir)
mkdir -p "$sd_bad/.orchestrate"
printf '../evil\t1\n' >"$sd_bad/.orchestrate/effective-backend"
if "$DEGRADE" read "$sd_bad" >/dev/null 2>&1; then
  fail "read emitted a malformed effective-backend value"
fi

# A hostile backend name is refused; nothing written.
sd3=$(new_spec_dir)
if "$DEGRADE" record "$sd3" "../evil" >/dev/null 2>&1; then
  fail "record accepted a hostile backend name"
fi
[ ! -e "$sd3/.orchestrate/effective-backend" ] || fail "record wrote a file for a hostile name"

# A symlink at the record path is refused, not written through (marker parity).
sd4=$(new_spec_dir)
mkdir -p "$sd4/.orchestrate"
ln -s "$tmp/leak-target" "$sd4/.orchestrate/effective-backend"
if "$DEGRADE" record "$sd4" subagent >/dev/null 2>&1; then
  fail "record wrote through a symlink at the record path"
fi

# The record path honors PLANWRIGHT_ORCH_STATE_DIR like the sibling marker (R8):
# the record sits alongside the markers dir (its parent), not inside it.
sd5=$(new_spec_dir)
mkdir -p "$sd5/mk"
PLANWRIGHT_ORCH_STATE_DIR="$sd5/mk" "$DEGRADE" record "$sd5" in-session \
  || fail "record with PLANWRIGHT_ORCH_STATE_DIR exited nonzero"
[ -f "$sd5/effective-backend" ] || fail "record ignored PLANWRIGHT_ORCH_STATE_DIR parent placement"

# --- runtime failover: descend one rung down the available ladder ------------

# tmux (rung 1) dies; subagent + in-session present, no rung-2 pool → descend to
# the richest safe present rung below rung 1 = subagent (rung 3).
sd=$(new_spec_dir)
tasks_before=$(cat "$sd/tasks.md")
out=$("$DEGRADE" failover "$sd" tmux subagent in-session 2>"$tmp/err") \
  || fail "failover tmux→ exited nonzero (expected a safe descent)"
grep -q "subagent" "$sd/.orchestrate/effective-backend" \
  || fail "failover did not record the effective backend (subagent)"
echo "$out" | grep -q -- "- \*\*Backend failover" \
  || fail "failover emitted no Awaiting-input entry bullet on stdout"
grep -qi "descend" "$tmp/err" || fail "failover emitted no descent NOTE on stderr"
[ "$(cat "$sd/tasks.md")" = "$tasks_before" ] || fail "failover MUTATED tasks.md (REQ-B1.6 violation)"
[ "$("$DEGRADE" read "$sd")" = subagent ] || fail "failover recorded the wrong backend"

# subagent (rung 3) dies; only in-session below → descend to the terminal rung.
sd=$(new_spec_dir)
"$DEGRADE" failover "$sd" subagent subagent in-session >/dev/null 2>&1 \
  || fail "failover subagent→in-session exited nonzero"
[ "$("$DEGRADE" read "$sd")" = in-session ] || fail "failover subagent→ recorded wrong backend"

# Descent to the rung-2 pool (the middle rung), a true adjacent one-rung step
# from rung 1, via a pluggable adapter (F11).
sd=$(new_spec_dir)
PATH="$BIN:$PATH" "$DEGRADE" failover "$sd" tmux tmux pool in-session >/dev/null 2>&1 \
  || fail "failover tmux→pool (rung 2) exited nonzero"
[ "$("$DEGRADE" read "$sd")" = pool ] || fail "failover did not descend to the rung-2 pool"

# Empty candidate list: the shipped presence probe fills it in (F4). With
# subagent forced present, tmux fails over to subagent.
sd=$(new_spec_dir)
PLANWRIGHT_BACKEND_SUBAGENT=1 "$DEGRADE" failover "$sd" tmux >/dev/null 2>&1 \
  || fail "failover with an empty candidate list exited nonzero"
[ "$("$DEGRADE" read "$sd")" = subagent ] || fail "empty-candidate probe recorded wrong backend"

# Multi-descent (R6): repeated failures walk down one rung each toward the floor.
sd=$(new_spec_dir)
"$DEGRADE" failover "$sd" tmux subagent in-session >/dev/null 2>&1 || fail "R6 step 1 failed"
[ "$("$DEGRADE" read "$sd")" = subagent ] || fail "R6 step 1 wrong rung"
"$DEGRADE" failover "$sd" subagent subagent in-session >/dev/null 2>&1 || fail "R6 step 2 failed"
[ "$("$DEGRADE" read "$sd")" = in-session ] || fail "R6 step 2 wrong rung"

# --- safety-abort / escalation: degrade capability, NEVER safety --------------

# Terminal-rung floor: in-session (rung 4) dies with no lower rung → ESCALATE
# (exit 3) with the TERMINAL reason, distinct from the guard-drop reason. `print`
# is off the autonomous ladder, so it does not count as a lower rung.
sd=$(new_spec_dir)
out=$("$DEGRADE" failover "$sd" in-session in-session print 2>"$tmp/err") && rc=0 || rc=$?
[ "$rc" = 3 ] || fail "terminal-rung escalation: expected exit 3, got $rc"
both=$({
  printf '%s' "$out"
  cat "$tmp/err"
})
echo "$both" | grep -qi "ladder floor\|no lower rung" \
  || fail "terminal-rung escalation gave no terminal-floor reason"
echo "$both" | grep -qi "would drop a named guard" \
  && fail "terminal-rung escalation was mislabeled as a guard-drop"
[ ! -f "$sd/.orchestrate/effective-backend" ] || fail "terminal escalation recorded a backend"

# Guard-drop: tmux (rung 1) dies and the only lower rung is an INTERACTIVE pool
# (rung 2, would strand an unattended run) → ESCALATE (exit 3) with the
# GUARD-DROP reason, distinct from the terminal reason (F3/F5).
sd=$(new_spec_dir)
out=$(PATH="$BIN:$PATH" "$DEGRADE" failover "$sd" tmux tmux ipool 2>"$tmp/err") && rc=0 || rc=$?
[ "$rc" = 3 ] || fail "guard-drop refusal: expected exit 3, got $rc"
both=$({
  printf '%s' "$out"
  cat "$tmp/err"
})
echo "$both" | grep -qi "would drop a named guard" \
  || fail "guard-drop refusal gave no guard-drop reason"
echo "$both" | grep -qi "ladder floor\|no lower rung" \
  && fail "guard-drop refusal was mislabeled as the terminal floor"
[ ! -f "$sd/.orchestrate/effective-backend" ] || fail "guard-drop escalation recorded a backend"

# Never ascend to an interactive backend: subagent dies with only tmux (rung 1,
# above) present → no lower rung → escalate (exit 3), nothing recorded.
sd=$(new_spec_dir)
"$DEGRADE" failover "$sd" subagent tmux subagent >/dev/null 2>&1 && rc=0 || rc=$?
[ "$rc" = 3 ] || fail "ascend refusal: expected exit 3, got $rc"
[ ! -f "$sd/.orchestrate/effective-backend" ] || fail "ascend refusal recorded a backend"

# Record-write failure aborts (R12): a regular FILE where .orchestrate must be a
# dir makes the record write fail → the failover ESCALATES (exit 3) rather than
# proceeding unrecorded, and says so.
sd=$(new_spec_dir)
: >"$sd/.orchestrate" # a file blocks `mkdir -p .orchestrate`
out=$("$DEGRADE" failover "$sd" tmux subagent in-session 2>"$tmp/err") && rc=0 || rc=$?
[ "$rc" = 3 ] || fail "record-write-failure abort: expected exit 3, got $rc"
{
  printf '%s' "$out"
  cat "$tmp/err"
} | grep -qi "record\|unrecorded" \
  || fail "record-write-failure abort gave no operator-visible reason"

# --- state-safety invariant: no tasks.md-write or merge path (REQ-B1.6/J1.1) --
# Every line of the script mentioning tasks.md must be a comment; and there is no
# merge path (never-auto-merge). The behavioral assertions above (tasks.md
# unchanged after record/failover) back this source audit.
noncomment=$(grep -n 'tasks\.md' "$DEGRADE" | sed 's/^[0-9]*://' | grep -vE '^[[:space:]]*#' || true)
[ -z "$noncomment" ] || fail "orchestrate-degrade.sh references tasks.md outside a comment: $noncomment"
if grep -niE "\bgit merge\b|--auto-merge|gh pr merge|merge_pull_request" "$DEGRADE" >/dev/null; then
  fail "orchestrate-degrade.sh contains a merge path (never-auto-merge invariant)"
fi

# --- usage / fail-closed -------------------------------------------------------
"$DEGRADE" >/dev/null 2>&1 && fail "no subcommand should exit nonzero"
"$DEGRADE" bogus >/dev/null 2>&1 && fail "unknown subcommand should exit nonzero"
"$DEGRADE" failover >/dev/null 2>&1 && fail "failover with no args should exit nonzero"
"$DEGRADE" record "$tmp/does-not-exist" subagent >/dev/null 2>&1 \
  && fail "record on a missing spec dir should exit nonzero"

echo "PASS: test-orchestrate-degrade.sh"
