#!/bin/bash
# Tests for scripts/check-ledger.sh — the structural-corruption + duplicate-
# Status guards over a committed tasks.md snapshot (orchestration-concurrency
# Task 7; REQ-E1.1, REQ-E1.2, REQ-E1.3).
#
# Contract under test:
#   - A well-formed snapshot passes (exit 0), INCLUDING one that merely lags
#     live truth: a not-yet-reconciled in-flight task still shown under Forward
#     plan with no Status annotation is correct, not corrupt (REQ-E1.1).
#     Freshness is the reconcile pass's job, not the guard's.
#   - A snapshot carrying a structural corruption the level-triggered reconcile
#     would never produce fails (exit 1) with a clear, located message:
#       * wrong-block placement contradicting the block's own Status evidence
#         (a completed-status block under Forward; an implementing-status block
#         under Completed; a Completed section block with no completion status);
#       * a mis-sort / duplicated block (the same task id under two sections);
#       * a malformed task heading;
#       * a task block orphaned outside any recognized state section.
#   - The `>1 Status line` lint (REQ-E1.2) fails a block carrying two Status
#     lines (the duplicate-dispatch-metadata signature).
#   - Every real spec bundle's tasks.md passes (no false positives).
#   - A missing file argument is a usage error (exit 2), not a silent pass.
set -u
unset CDPATH

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GUARD="$REPO_ROOT/scripts/check-ledger.sh"

failures=0

# assert_exit <label> <expected-exit> <actual-exit>
assert_exit() {
  if [ "$2" -eq "$3" ]; then
    echo "ok: $1"
  else
    echo "FAIL: $1 (expected exit $2, got $3)" >&2
    failures=$((failures + 1))
  fi
}

# assert_contains <label> <needle> <haystack>
assert_contains() {
  case "$3" in
    *"$2"*) echo "ok: $1 (message)" ;;
    *)
      echo "FAIL: $1 (expected output to contain '$2', got: $3)" >&2
      failures=$((failures + 1))
      ;;
  esac
}

if [ ! -x "$GUARD" ]; then
  echo "FAIL: guard script missing or not executable at $GUARD" >&2
  exit 1
fi

tmp="$(mktemp -d)" || exit 1
trap 'rm -rf "$tmp"' EXIT

# A reusable five-field task block body (definition fields only).
block_body() {
  cat <<'EOF'
- **Deliverables:** a thing
- **Done when:** the thing exists
- **Dependencies:** none
- **Citations:** D-1 · REQ-A1.1
- **Estimated effort:** 1 day
EOF
}

# Build the canonical well-formed snapshot into $tmp/clean.md. It deliberately
# includes a Forward-plan task with NO Status (the lagging-in-flight case that
# must pass), an In-progress task with an `implementing` Status, and a Completed
# task with a `Completed · merged` Status.
make_clean() {
  {
    printf '# Example — Tasks\n\n**Status:** Active\n**Format-version:** 1\n\n'
    printf '## Forward plan\n\n### Task 2 — Beta\n\n'
    block_body
    printf '\n## In progress\n\n### Task 3 — Gamma\n\n'
    block_body
    printf -- '- **Status:** implementing\n- **Last activity:** 2026-06-28\n'
    printf '\n## Awaiting input\n\n(none yet)\n'
    printf '\n## Completed\n\n### Task 1 — Alpha\n\n'
    block_body
    printf -- '- **Status:** Completed · PR #1 merged 2026-06-01\n'
    printf '\n## Deferred\n\n## Out of scope\n'
  } >"$1"
}

run() {
  out="$(/bin/bash "$GUARD" "$@" 2>&1)"
  code=$?
}

# --- 1. Clean well-formed snapshot passes (the lag case is built in) ---------
make_clean "$tmp/clean.md"
run "$tmp/clean.md"
assert_exit "clean well-formed snapshot passes" 0 "$code"

# --- 2. Lag-only variant passes ---------------------------------------------
# A second Forward-plan task with no Status (it may be in-flight per live truth;
# the guard must not consult truth, so it passes).
{
  make_clean "$tmp/lag.md"
} >/dev/null
# Re-emit clean but with an extra status-less Forward task to make the lag
# explicit and independent of test 1.
{
  printf '# Example — Tasks\n\n**Status:** Active\n**Format-version:** 1\n\n'
  printf '## Forward plan\n\n### Task 4 — Delta\n\n'
  block_body
  printf '\n### Task 5 — Epsilon\n\n'
  block_body
  printf '\n## In progress\n\n(none yet)\n'
  printf '\n## Awaiting input\n\n(none yet)\n'
  printf '\n## Completed\n\n(none yet)\n'
  printf '\n## Deferred\n\n## Out of scope\n'
} >"$tmp/lag.md"
run "$tmp/lag.md"
assert_exit "lagging-but-well-formed snapshot passes" 0 "$code"

# --- 3. Wrong-block: completed-status block under Forward plan ----------------
make_clean "$tmp/c1.md"
# Add a Forward-plan task carrying a Completed status (reconcile would never
# leave a merged task in Forward).
sed 's/### Task 2 — Beta/### Task 2 — Beta\n\n- **Status:** Completed · PR #9 merged 2026-06-02/' \
  "$tmp/clean.md" >"$tmp/c1.md"
run "$tmp/c1.md"
assert_exit "completed status under Forward plan fails" 1 "$code"
assert_contains "completed-under-forward message located" ":" "$out"

# --- 4. Wrong-block: implementing-status block under Completed ---------------
make_clean "$tmp/c2.md"
# Flip the Completed task's status to implementing.
sed 's/Completed · PR #1 merged 2026-06-01/implementing/' "$tmp/clean.md" >"$tmp/c2.md"
run "$tmp/c2.md"
assert_exit "implementing status under Completed fails" 1 "$code"
assert_contains "implementing-under-Completed message located" "under Completed lacks a completion Status" "$out"

# --- 5. Wrong-block: Completed section block with no completion status -------
make_clean "$tmp/c3.md"
# Drop the Completed task's Status line entirely.
grep -v 'Completed · PR #1 merged 2026-06-01' "$tmp/clean.md" >"$tmp/c3.md"
run "$tmp/c3.md"
assert_exit "no completion status under Completed fails" 1 "$code"
assert_contains "no-completion-under-Completed message located" "under Completed lacks a completion Status" "$out"

# --- 5b. Completion vocabulary is free-form: a bare "done" passes -----------
# spec-format declares Status a free-form descriptor; the canonical reconcile
# writer emits "Completed · PR #N merged", but a concurrent reconcile may use a
# bare "done". Both are completion evidence and must pass under Completed.
make_clean "$tmp/done.md"
sed 's/Completed · PR #1 merged 2026-06-01/done/' "$tmp/clean.md" >"$tmp/done.md"
run "$tmp/done.md"
assert_exit "bare \"done\" completion Status under Completed passes" 0 "$code"
# ...and a "done" Status under Forward plan is still a placement contradiction.
sed 's/### Task 2 — Beta/### Task 2 — Beta\n\n- **Status:** done/' \
  "$tmp/clean.md" >"$tmp/donefwd.md"
run "$tmp/donefwd.md"
assert_exit "\"done\" Status under Forward plan fails (completion in Forward)" 1 "$code"

# --- 6. Mis-sort / duplicate: same task id under two sections ----------------
{
  printf '# Example — Tasks\n\n**Status:** Active\n**Format-version:** 1\n\n'
  printf '## Forward plan\n\n(none yet)\n'
  printf '\n## In progress\n\n### Task 1 — Alpha\n\n'
  block_body
  printf -- '- **Status:** implementing\n'
  printf '\n## Awaiting input\n\n(none yet)\n'
  printf '\n## Completed\n\n### Task 1 — Alpha\n\n'
  block_body
  printf -- '- **Status:** Completed · PR #1 merged 2026-06-01\n'
  printf '\n## Deferred\n\n## Out of scope\n'
} >"$tmp/dup.md"
run "$tmp/dup.md"
assert_exit "duplicate task id across sections fails (mis-sort)" 1 "$code"
assert_contains "duplicate message names the id" "1" "$out"

# --- 7. Malformed task heading ----------------------------------------------
make_clean "$tmp/mal.md"
sed 's/### Task 3 — Gamma/### Task three — Gamma/' "$tmp/clean.md" >"$tmp/mal.md"
run "$tmp/mal.md"
assert_exit "malformed task heading fails" 1 "$code"

# --- 8. Orphaned block: a task under a non-state heading ---------------------
{
  printf '# Example — Tasks\n\n**Status:** Active\n**Format-version:** 1\n\n'
  printf '## Dependency graph\n\n### Task 9 — Orphan\n\n'
  block_body
  printf '\n## Forward plan\n\n(none yet)\n'
  printf '\n## In progress\n\n(none yet)\n'
  printf '\n## Awaiting input\n\n(none yet)\n'
  printf '\n## Completed\n\n(none yet)\n'
  printf '\n## Deferred\n\n## Out of scope\n'
} >"$tmp/orphan.md"
run "$tmp/orphan.md"
assert_exit "task block outside a state section fails" 1 "$code"

# --- 9. >1 Status line lint (REQ-E1.2) --------------------------------------
make_clean "$tmp/twostatus.md"
sed 's/- \*\*Status:\*\* implementing/- **Status:** implementing\n- **Status:** PR #5 draft/' \
  "$tmp/clean.md" >"$tmp/twostatus.md"
run "$tmp/twostatus.md"
assert_exit "two Status lines on a block fails" 1 "$code"
assert_contains "two-status message mentions Status" "Status" "$out"

# --- 9b. Section/status placement matrix (symmetric branch coverage) --------
# Tests 3-5 cover the Forward-plan and Completed branches; this matrix exercises
# the remaining state-section branches in finalize_block() (In progress,
# Awaiting input, Deferred, Out of scope, and the in-progress/deferred Forward
# cases) so every placement-vs-Status contract has an explicit located test.
# Build a minimal well-formed skeleton with a single task placed in <section>
# carrying <status>, then assert the expected exit (and message when it fails).
section_case() { # <label> <section> <status> <expected-exit> [needle]
  {
    printf '# Example — Tasks\n\n**Status:** Active\n**Format-version:** 1\n\n'
    printf '## Forward plan\n\n'
    [ "$2" = "Forward plan" ] && {
      printf '### Task 5 — Epsilon\n\n'
      block_body
      printf -- '- **Status:** %s\n' "$3"
    }
    printf '\n## In progress\n\n'
    [ "$2" = "In progress" ] && {
      printf '### Task 5 — Epsilon\n\n'
      block_body
      printf -- '- **Status:** %s\n' "$3"
    }
    printf '\n## Awaiting input\n\n'
    [ "$2" = "Awaiting input" ] && {
      printf '### Task 5 — Epsilon\n\n'
      block_body
      printf -- '- **Status:** %s\n' "$3"
    }
    printf '\n## Completed\n\n(none yet)\n'
    printf '\n## Deferred\n\n'
    [ "$2" = "Deferred" ] && {
      printf '### Task 5 — Epsilon\n\n'
      block_body
      printf -- '- **Status:** %s\n' "$3"
    }
    printf '\n## Out of scope\n'
    [ "$2" = "Out of scope" ] && {
      printf '\n### Task 5 — Epsilon\n\n'
      block_body
      printf -- '- **Status:** %s\n' "$3"
    }
  } >"$tmp/sec.md"
  run "$tmp/sec.md"
  assert_exit "$1" "$4" "$code"
  [ -n "${5:-}" ] && assert_contains "$1 (located)" "$5" "$out"
}

# Wrong placements: each fails with a section-named message.
section_case "Forward plan + in-progress Status fails" "Forward plan" "implementing" 1 "under Forward plan"
section_case "Forward plan + deferred Status fails" "Forward plan" "deferred" 1 "under Forward plan"
section_case "In progress + completed Status fails" "In progress" "Completed · PR #1 merged 2026-06-01" 1 "under In progress"
section_case "In progress + deferred Status fails" "In progress" "deferred" 1 "under In progress"
section_case "Awaiting input + completed Status fails" "Awaiting input" "Completed · PR #1 merged 2026-06-01" 1 "under Awaiting input"
section_case "Deferred + completed Status fails" "Deferred" "Completed · PR #1 merged 2026-06-01" 1 "under Deferred"
section_case "Deferred + in-progress Status fails" "Deferred" "implementing" 1 "under Deferred"
section_case "Out of scope + completed Status fails" "Out of scope" "Completed · PR #1 merged 2026-06-01" 1 "under Out of scope"
# Well-formed placements for the same sections pass (no false positives).
section_case "Deferred + deferred Status passes" "Deferred" "deferred" 0
section_case "Awaiting input + in-progress Status passes" "Awaiting input" "implementing" 0

# --- 10. No false positives on the real spec bundles ------------------------
real_args=""
for d in "$REPO_ROOT"/specs/*/; do
  base="$(basename "$d")"
  case "$base" in
    _*) continue ;; # accumulator dirs are not task bundles
  esac
  [ -f "$d/tasks.md" ] && real_args="$real_args $d/tasks.md"
done
# shellcheck disable=SC2086
run $real_args
assert_exit "all real spec tasks.md snapshots pass" 0 "$code"

# --- 11. Default (no args) scans the repo's bundles and passes ---------------
(cd "$REPO_ROOT" && /bin/bash "$GUARD" >/dev/null 2>&1)
assert_exit "default no-arg scan of repo bundles passes" 0 $?

# --- 12. Missing file argument is a usage error -----------------------------
run "$tmp/does-not-exist.md"
assert_exit "missing file argument is a usage error" 2 "$code"

# --- 12b. Usage-error exit (2) is sticky over a later corruption (1) ---------
# A missing/unreadable file sets the usage-error code; a later corrupt file must
# not silently downgrade the run to exit 1. The usage error means an input could
# not be processed at all, so it dominates the corruption-found code.
make_clean "$tmp/c2-sticky.md"
sed 's/Completed · PR #1 merged 2026-06-01/implementing/' "$tmp/clean.md" >"$tmp/c2-sticky.md"
run "$tmp/does-not-exist.md" "$tmp/c2-sticky.md"
assert_exit "usage-error exit (2) stays sticky over a later finding" 2 "$code"

# --- 12c. CRLF snapshots parse like LF ones (trailing CR is not data) --------
# A well-formed snapshot saved with CRLF line endings must still pass: the
# trailing \r must be stripped before section/heading/Status matching, or every
# task is falsely reported as outside a recognized state section.
make_clean "$tmp/clean-lf.md"
awk '{ printf "%s\r\n", $0 }' "$tmp/clean-lf.md" >"$tmp/clean-crlf.md"
run "$tmp/clean-crlf.md"
assert_exit "well-formed CRLF snapshot passes" 0 "$code"

# --- 12d. Control characters in file content do not reach the diagnostic -----
# tasks.md content is untrusted repo/PR input; the echo discipline (REQ-H1.3,
# mirrored across the sibling guards) requires stripping control characters
# before echoing extracted file content into a finding message.
printf '**Format-version:** 1\n\n## Completed\n\n### Task \007BEL — Bad heading\n' >"$tmp/ctrl.md"
run "$tmp/ctrl.md"
assert_exit "control-char malformed heading still fails" 1 "$code"
if printf '%s' "$out" | tr -d '\011\012' | LC_ALL=C grep -q '[[:cntrl:]]'; then
  echo "FAIL: control char leaked into check-ledger diagnostic output" >&2
  failures=$((failures + 1))
else
  echo "ok: control char stripped from malformed-heading diagnostic"
fi

# --- 13. Format-version 2: structural checks only (invariant-tasks Task 4;
# REQ-C1.4, REQ-C1.8, REQ-C1.9; D-7). The guard is version-keyed off the
# file's own `**Format-version:**` declaration: v2 keeps the structural checks
# (canonical heading form, duplicate task ids, the orphan-block check with
# `## Tasks` recognized) while the v1 placement/annotation coherence checks and
# the >1-Status lint do not fire (banned sections/annotations are the
# validator's findings there, not this guard's). A missing or unparseable
# declaration fails closed: the checks to apply cannot be selected, so the file
# is reported rather than silently checked under either version's rules.

v2_header() {
  printf '# Example — Tasks\n\n**Status:** Ready\n**Format-version:** 2\n'
  printf '**Execution:** derived — see the status render\n\n'
}

# 13a. A clean v2 snapshot passes: every block under ## Tasks (recognized as a
# valid section), reference bullets in the human-payload sections.
{
  v2_header
  printf '## Tasks\n\n### Task 1 — Alpha\n\n'
  block_body
  printf '\n### Task 2 — Beta\n\n'
  block_body
  printf '\n## Awaiting input\n\n- **Task 2** — blocked on a fixture question.\n'
  printf '\n## Deferred\n\n(none yet)\n\n## Out of scope\n\n(none yet)\n'
} >"$tmp/v2-clean.md"
run "$tmp/v2-clean.md"
assert_exit "v2: clean snapshot with blocks under ## Tasks passes" 0 "$code"

# 13b. Coherence checks and the >1-Status lint do not fire on v2: state
# annotations on a v2 block are the VALIDATOR's finding (banned annotation),
# not a ledger-coherence finding — the guard must not double-report them.
{
  v2_header
  printf '## Tasks\n\n### Task 1 — Alpha\n\n'
  block_body
  printf -- '- **Status:** Completed · PR #1 merged 2026-06-01\n'
  printf -- '- **Status:** implementing\n'
  printf '\n## Awaiting input\n\n(none yet)\n'
  printf '\n## Deferred\n\n(none yet)\n\n## Out of scope\n\n(none yet)\n'
} >"$tmp/v2-annot.md"
run "$tmp/v2-annot.md"
assert_exit "v2: placement/annotation coherence and >1-Status lint do not fire" 0 "$code"

# 13c. Canonical heading form still enforced on v2.
{
  v2_header
  printf '## Tasks\n\n### Task one — Alpha\n\n'
  block_body
} >"$tmp/v2-mal.md"
run "$tmp/v2-mal.md"
assert_exit "v2: malformed task heading still fails" 1 "$code"
assert_contains "v2 malformed-heading message" "malformed task heading" "$out"

# 13d. Duplicate task ids still enforced on v2.
{
  v2_header
  printf '## Tasks\n\n### Task 1 — Alpha\n\n'
  block_body
  printf '\n### Task 1 — Alpha again\n\n'
  block_body
} >"$tmp/v2-dup.md"
run "$tmp/v2-dup.md"
assert_exit "v2: duplicate task id still fails" 1 "$code"
assert_contains "v2 duplicate message names the id" "duplicate task block" "$out"

# 13e. A block outside any recognized section still fails on v2.
{
  v2_header
  printf '## Junk\n\n### Task 9 — Orphan\n\n'
  block_body
  printf '\n## Tasks\n\n(none yet)\n'
} >"$tmp/v2-orphan.md"
run "$tmp/v2-orphan.md"
assert_exit "v2: task block outside a recognized section fails" 1 "$code"
assert_contains "v2 orphan message names the section" "outside any recognized state section" "$out"

# 13f. A missing Format-version fails closed (REQ-C1.8): the rules to apply
# cannot be selected, so the file is reported (exit 1), never silently checked
# under the v1 rules.
{
  printf '# Example — Tasks\n\n**Status:** Active\n\n'
  printf '## Forward plan\n\n### Task 1 — Alpha\n\n'
  block_body
} >"$tmp/nover.md"
run "$tmp/nover.md"
assert_exit "missing Format-version fails closed" 1 "$code"
assert_contains "missing-version message names Format-version" "Format-version" "$out"

# 13g. An unparseable Format-version fails closed, and the echoed declared
# value is sanitized (REQ-C1.9): an embedded escape byte cannot reach the
# diagnostic stream.
{
  printf '# Example — Tasks\n\n**Status:** Active\n'
  printf '**Format-version:** 2\033[31mx\n\n'
  printf '## Tasks\n\n### Task 1 — Alpha\n\n'
  block_body
} >"$tmp/badver.md"
run "$tmp/badver.md"
assert_exit "unparseable Format-version fails closed" 1 "$code"
assert_contains "unparseable-version message names Format-version" "Format-version" "$out"
if printf '%s' "$out" | tr -d '\011\012' | LC_ALL=C grep -q '[[:cntrl:]]'; then
  echo "FAIL: control char leaked into the unparseable-version diagnostic" >&2
  failures=$((failures + 1))
else
  echo "ok: unparseable-version diagnostic is sanitized (REQ-C1.9)"
fi

if [ "$failures" -ne 0 ]; then
  echo "$failures test(s) failed" >&2
  exit 1
fi
echo "all check-ledger tests passed"
