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
#     set (D-3, ordered richest→safest): 1 interactive+steer (tmux); 2 headless
#     pool (session-grade parallel, no steer) OR interactive-without-steer; 3
#     in-harness parallel no-steer (subagent); 4 synchronous single-stream
#     (in-session — the terminal rung). A spawn-deferred backend (print) is
#     `manual` — off the autonomous ladder. A hostile/unclassifiable arg exits 2.
#   - `terminal-plan <id>...` emits the synchronous terminal rung's run plan:
#     one `run <id>` line per unit with a `context-clear` line BETWEEN
#     consecutive units (bounded-context clears; never after the last). Ids are
#     validated against the task-id grammar before use; a hostile id exits 2 with
#     no output.
#   - `record <spec-dir> <backend>` writes the effective backend spec-locally to
#     `<spec-dir>/.orchestrate/effective-backend` (alongside the sibling's
#     dispatch marker, REQ-B1.6) atomically; NEVER to tasks.md. `read <spec-dir>`
#     prints it back (exit 1 when absent). A hostile backend name, a symlink /
#     non-regular file at the path, or an unwritable dir is refused fail-closed.
#   - `failover <spec-dir> <current> [candidate...]` descends EXACTLY one rung to
#     the richest present, guard-preserving (non-interactive, non-deferred)
#     backend strictly below the current rung; records the effective backend
#     spec-locally; emits a NOTE (stderr) + an `## Awaiting input` entry (stdout);
#     exit 0. It ESCALATES (exit 3, never a silent downgrade) when no lower
#     guard-preserving rung is available — the terminal-rung fatal crash, or a
#     descent that would drop a named guard (only interactive/manual candidates
#     remain below). A record-write failure aborts (exit 3) rather than proceeding
#     unrecorded (degrade capability, never safety).
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

got=$("$DEGRADE" rung tmux) || fail "rung tmux exited nonzero"
[ "$got" = 1 ] || fail "rung tmux: expected 1, got '$got'"

got=$("$DEGRADE" rung subagent) || fail "rung subagent exited nonzero"
[ "$got" = 3 ] || fail "rung subagent: expected 3, got '$got'"

got=$("$DEGRADE" rung in-session) || fail "rung in-session exited nonzero"
[ "$got" = 4 ] || fail "rung in-session (terminal rung): expected 4, got '$got'"

got=$("$DEGRADE" rung print) || fail "rung print exited nonzero"
[ "$got" = manual ] || fail "rung print: expected 'manual' (off-ladder), got '$got'"

# A headless `claude -p` pool: session-grade + parallel, no live steer → rung 2.
got=$("$DEGRADE" rung "false false false false true yes") || fail "rung headless-pool caps exited nonzero"
[ "$got" = 2 ] || fail "rung headless-pool caps: expected 2, got '$got'"

# An interactive multiplexer WITHOUT steer → also rung 2 (near the fallback).
got=$("$DEGRADE" rung "true false false false true yes") || fail "rung interactive-no-steer caps exited nonzero"
[ "$got" = 2 ] || fail "rung interactive-no-steer caps: expected 2, got '$got'"

# Hostile / unclassifiable arg is refused, not classified.
if "$DEGRADE" rung "../../etc/passwd" >/dev/null 2>&1; then
  fail "rung accepted a hostile arg"
fi
if "$DEGRADE" rung "not-a-real-backend" >/dev/null 2>&1; then
  fail "rung accepted an unknown backend name"
fi

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

# read on a spec dir with no record exits 1 (absent), not 0.
sd2=$(new_spec_dir)
if "$DEGRADE" read "$sd2" >/dev/null 2>&1; then
  fail "read succeeded with no record present"
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
ln -s /etc/passwd "$sd4/.orchestrate/effective-backend"
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

# --- runtime failover: descend exactly one rung (REQ-B1.5, REQ-B1.6) ---------

# tmux (rung 1) dies; subagent + in-session present → descend ONE rung to the
# richest safe present rung below rung 1 = subagent (rung 3; no rung-2 pool here).
sd=$(new_spec_dir)
tasks_before=$(cat "$sd/tasks.md")
out=$("$DEGRADE" failover "$sd" tmux subagent in-session 2>"$tmp/err") \
  || fail "failover tmux→ exited nonzero (expected a safe descent)"
grep -q "subagent" "$sd/.orchestrate/effective-backend" \
  || fail "failover did not record the effective backend (subagent)"
echo "$out" | grep -qi "awaiting input\|failover" \
  || fail "failover emitted no Awaiting-input entry on stdout"
grep -qi "descend" "$tmp/err" || fail "failover emitted no descent NOTE on stderr"
[ "$(cat "$sd/tasks.md")" = "$tasks_before" ] || fail "failover MUTATED tasks.md (REQ-B1.6 violation)"
got=$("$DEGRADE" read "$sd")
[ "$got" = subagent ] || fail "failover recorded '$got', expected subagent"

# subagent (rung 3) dies; only in-session below → descend to the terminal rung.
sd=$(new_spec_dir)
"$DEGRADE" failover "$sd" subagent subagent in-session >/dev/null 2>&1 \
  || fail "failover subagent→in-session exited nonzero"
got=$("$DEGRADE" read "$sd")
[ "$got" = in-session ] || fail "failover subagent→ recorded '$got', expected in-session"

# Multi-descent (R6): repeated failures walk down one rung each to the floor.
sd=$(new_spec_dir)
"$DEGRADE" failover "$sd" tmux subagent in-session >/dev/null 2>&1 || fail "R6 step 1 failed"
[ "$("$DEGRADE" read "$sd")" = subagent ] || fail "R6 step 1 wrong rung"
"$DEGRADE" failover "$sd" subagent subagent in-session >/dev/null 2>&1 || fail "R6 step 2 failed"
[ "$("$DEGRADE" read "$sd")" = in-session ] || fail "R6 step 2 wrong rung"

# --- safety-abort / escalation: degrade capability, NEVER safety --------------

# Terminal-rung fatal crash: in-session (rung 4) dies, no lower rung exists →
# ESCALATE (exit 3), never a silent downgrade, never a descent to print.
sd=$(new_spec_dir)
out=$("$DEGRADE" failover "$sd" in-session in-session print 2>"$tmp/err") && rc=0 || rc=$?
[ "$rc" = 3 ] || fail "terminal-rung escalation: expected exit 3, got $rc"
{
  printf '%s' "$out"
  cat "$tmp/err"
} | grep -qi "escalat\|terminal rung\|no lower rung" \
  || fail "terminal-rung escalation gave no operator-visible reason"

# A descent that would DROP A GUARD is refused: subagent (rung 3) dies and the
# only candidate below is the manual `print` rung (spawn deferred to a human,
# dropping planwright's guard enforcement) → ESCALATE, never descend to print.
sd=$(new_spec_dir)
out=$("$DEGRADE" failover "$sd" subagent subagent print 2>"$tmp/err") && rc=0 || rc=$?
[ "$rc" = 3 ] || fail "guard-drop refusal: expected exit 3, got $rc"
{
  printf '%s' "$out"
  cat "$tmp/err"
} | grep -qi "guard\|print\|manual\|escalat" \
  || fail "guard-drop refusal gave no operator-visible reason"
# The escalation must not have recorded print as the effective backend.
if [ -f "$sd/.orchestrate/effective-backend" ]; then
  ! grep -q "print" "$sd/.orchestrate/effective-backend" \
    || fail "escalation recorded the unsafe 'print' backend"
fi

# Never ascend / never pick an interactive backend as a descent target: subagent
# dies with only tmux (interactive, rung 1 — above) available → escalate.
sd=$(new_spec_dir)
if "$DEGRADE" failover "$sd" subagent tmux subagent >/dev/null 2>"$tmp/err"; then
  fail "failover ascended to an interactive backend"
fi

# Record-write failure aborts (R12): a regular FILE where .orchestrate must be a
# dir makes the record write fail → the failover ESCALATES rather than proceeding
# unrecorded (degrade capability, never safety).
sd=$(new_spec_dir)
: >"$sd/.orchestrate" # a file blocks `mkdir -p .orchestrate`
if "$DEGRADE" failover "$sd" tmux subagent in-session >/dev/null 2>"$tmp/err"; then
  fail "failover proceeded despite an unrecordable effective backend"
fi

# --- state-safety invariant: the script has no tasks.md-write or merge path ---
# REQ-B1.6 / REQ-J1.1: the effective-backend record is spec-local and the fleet
# never auto-merges. A source audit backs the functional assertions above.
if grep -nE "tasks\.md" "$DEGRADE" | grep -vqiE '#|never|not'; then
  fail "orchestrate-degrade.sh references tasks.md outside a comment"
fi
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
