#!/bin/bash
# Tests for scripts/orchestrate-select.sh — FORMAT-VERSION 2 candidacy
# (invariant-tasks Task 5; D-8, D-3; REQ-C1.2, REQ-C1.8, REQ-C1.9, REQ-B1.5).
#
# Split out of tests/test-orchestrate-select.sh (guard-coverage Task 6,
# REQ-E1.2, D-9); the base file's header carries the full selection contract and
# names the other three siblings. No assertion changed in the split.
#
# What this file covers: v2 candidacy is computed without committed placement —
# completed / in-progress exclusion from the derivation engine, parked-ness from
# live reference bullets in the human-payload sections. Sections F1–F2 pin the
# Format-version fail-closed contract (REQ-C1.8) and V1–V10 the parked-map
# semantics, v1-equivalence, chain-weight terminality, transient-evidence
# refusal, grammar-violating bullets, fenced illustration, prose tolerance, and
# the no-PR-found-is-evidence rule. The remaining v2 cases (header/parse hygiene
# and untrusted-content echo discipline, V11–V19) live in
# tests/test-orchestrate-select-v2-hygiene.sh.
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
SEL="$here/../scripts/orchestrate-select.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -x "$SEL" ] || fail "scripts/orchestrate-select.sh missing or not executable"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# git with a deterministic, signing-free identity (mirrors the engine's test:
# the framework never signs CI fixtures, and a stray global commit.gpgsign would
# otherwise break fixture commits).
gitc() {
  repo="$1"
  shift
  git -C "$repo" -c user.name=test -c user.email=test@example.invalid \
    -c commit.gpgsign=false -c init.defaultBranch=main "$@"
}

# new_spec <repo> <spec-id> — init a git repo with specs/<spec-id>/ and echo the
# spec dir. The bundle's tasks.md is then written by the caller and committed
# with seal_base. The spec id is the bundle dir basename and must satisfy the
# anchored identifier grammar the engine validates (lowercase letters, digits,
# and dashes; first character a letter or digit), so all fixture spec ids below
# are well-formed.
new_spec() {
  nr_repo="$1"
  nr_spec="$2"
  mkdir -p "$nr_repo/specs/$nr_spec"
  git -C "$nr_repo" -c init.defaultBranch=main init -q
  printf '%s/specs/%s' "$nr_repo" "$nr_spec"
}

# seal_base <repo> — commit whatever is staged-or-not as the base commit on main.
seal_base() {
  gitc "$1" add -A
  gitc "$1" commit -q -m "base: spec bundle"
}

# done_trailer <repo> <spec-id> <id> — mark task <id> COMPLETED by adding a
# reachable completion trailer on main (no branch needed; the trailer is the
# durable anchor, D-2 / REQ-C1.4).
done_trailer() {
  gitc "$1" commit -q --allow-empty -m "task $3 done" -m "Planwright-Task: $2/$3"
}

# inflight_marker <spec-dir> <id> — mark task <id> IN-PROGRESS via a fresh
# runtime dispatch marker (D-3), the branch-create → first-commit window.
inflight_marker() {
  im_dir="$1/.orchestrate/markers"
  mkdir -p "$im_dir"
  date +%s >"$im_dir/$2"
}

# make_failing_gh_stub <dir> — drop a `gh` on PATH that always errors (mirrors
# the engine test). With a remote configured, this drives the engine's
# configured-but-failing-gh path, which emits a `degraded` record.
make_failing_gh_stub() {
  mkdir -p "$1"
  printf '#!/bin/sh\necho "gh: simulated failure" >&2\nexit 1\n' >"$1/gh"
  chmod +x "$1/gh"
}

# The always-failing `gh` stub the transient-evidence case (V5) drives. The
# pre-split file inherited this stub from its §17 fixture; each file stands
# alone, so it is rebuilt here.
degstub="$tmp/bindeg"
make_failing_gh_stub "$degstub"

# ---------------------------------------------------------------------------

# v2_tasks_md <path> — the shared v2 fixture skeleton: five tasks under a
# single ## Tasks section (no placement sections), the three human-payload
# sections empty. Task 1 is the root; 2/3/4/5 depend on it. Efforts make any
# parked-task leak visible: 2/3/4 (3 days each) outweigh 5 (half day), so if a
# bullet fails to exclude its task the selection flips away from 5.
v2_tasks_md() {
  cat >"$1" <<'EOF'
# tasks

**Format-version:** 2

## Tasks

### Task 1 — root

- **Dependencies:** none
- **Estimated effort:** 1 day

### Task 2 — parked awaiting input

- **Dependencies:** 1
- **Estimated effort:** 3 days

### Task 3 — parked deferred

- **Dependencies:** 1
- **Estimated effort:** 3 days

### Task 4 — parked out of scope

- **Dependencies:** 1
- **Estimated effort:** 3 days

### Task 5 — the only un-parked candidate

- **Dependencies:** 1
- **Estimated effort:** half day

## Awaiting input

- **Task 2** blocked on a human decision.

## Deferred

- **Task 3** deferred behind a gate.

## Out of scope

- **Task 4** excluded by decision.
EOF
}

# F1. REQ-C1.8 — a missing Format-version: line fails closed (exit 2) in both
#     modes, before any derivation runs (a plain non-git dir suffices).
dfv="$tmp/fvmissing"
mkdir -p "$dfv"
printf '# tasks\n\n## Forward plan\n\n### Task 1 — x\n\n- **Dependencies:** none\n' >"$dfv/tasks.md"
rc=0
fv_err=$(/bin/bash "$SEL" "$dfv" 2>&1 >/dev/null) || rc=$?
[ "$rc" = 2 ] || fail "fv-missing select: exit $rc, expected 2 (fail closed)"
case "$fv_err" in
  *Format-version*) : ;;
  *) fail "fv-missing select: diagnostic must name Format-version (got: $fv_err)" ;;
esac
rc=0
/bin/bash "$SEL" --critical-path "$dfv" >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "fv-missing --critical-path: exit $rc, expected 2 (fail closed)"
echo "ok: a missing Format-version: fails closed in both modes (REQ-C1.8)"

# F2. REQ-C1.8 — an unparseable Format-version: value fails closed too; the
#     selector never falls open to either version's rules.
dfv2="$tmp/fvbogus"
mkdir -p "$dfv2"
printf '# tasks\n\n**Format-version:** 3beta\n\n## Forward plan\n\n### Task 1 — x\n\n- **Dependencies:** none\n' >"$dfv2/tasks.md"
rc=0
/bin/bash "$SEL" "$dfv2" >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "fv-bogus select: exit $rc, expected 2 (fail closed)"
rc=0
/bin/bash "$SEL" --critical-path "$dfv2" >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "fv-bogus --critical-path: exit $rc, expected 2 (fail closed)"
echo "ok: an unparseable Format-version: fails closed in both modes (REQ-C1.8)"

# V1. REQ-C1.2 — parked-task exclusion, all three sections: with task 1
#     completed, tasks 2/3/4 are ready by evidence but each is parked by a live
#     reference bullet; only task 5 is dispatchable, despite its lower weight.
dv1="$tmp/v2park"
dv1spec=$(new_spec "$dv1" vtwo)
v2_tasks_md "$dv1spec/tasks.md"
seal_base "$dv1"
done_trailer "$dv1" vtwo 1
got=$(/bin/bash "$SEL" "$dv1spec") || fail "v2-parked fixture: non-zero exit ($?)"
[ "$got" = 5 ] || fail "v2-parked: selected '$got', expected 5 (2/3/4 parked by bullets)"
echo "ok: v2 reference bullets park their tasks in all three sections (REQ-C1.2)"

# V2. REQ-C1.2 — equivalence with the v1 section model: the same states
#     expressed as v1 section placement (task 2 in ## Awaiting input, 3 in
#     ## Deferred, 4 in ## Out of scope) pick the same candidate.
dv2="$tmp/v1twin"
dv2spec=$(new_spec "$dv2" vonetwin)
cat >"$dv2spec/tasks.md" <<'EOF'
# tasks

**Format-version:** 1

## Forward plan

### Task 1 — root

- **Dependencies:** none
- **Estimated effort:** 1 day

### Task 5 — the only un-parked candidate

- **Dependencies:** 1
- **Estimated effort:** half day

## Awaiting input

### Task 2 — parked awaiting input

- **Dependencies:** 1
- **Estimated effort:** 3 days

## Deferred

### Task 3 — parked deferred

- **Dependencies:** 1
- **Estimated effort:** 3 days

## Out of scope

### Task 4 — parked out of scope

- **Dependencies:** 1
- **Estimated effort:** 3 days
EOF
seal_base "$dv2"
done_trailer "$dv2" vonetwin 1
got_v1=$(/bin/bash "$SEL" "$dv2spec") || fail "v1-twin fixture: non-zero exit ($?)"
[ "$got_v1" = "5" ] || fail "v1-twin: selected '$got_v1', expected 5"
[ "$got_v1" = "$got" ] || fail "v2/v1 equivalence: v2 picked '$got', v1 twin picked '$got_v1'"
echo "ok: v2 selection matches the v1 section model in equivalent states (REQ-C1.2)"

# V3. REQ-C1.2 — completed / in-progress exclusion comes from derivation
#     evidence, not sections: on a v2 bundle (everything under ## Tasks, no
#     bullets) a trailer-completed task is not re-selected and a marker-held
#     task is not double-dispatched; the remaining ready task is picked.
dv3="$tmp/v2live"
dv3spec=$(new_spec "$dv3" vtwolive)
cat >"$dv3spec/tasks.md" <<'EOF'
# tasks

**Format-version:** 2

## Tasks

### Task 1 — completed by trailer

- **Dependencies:** none
- **Estimated effort:** 1 day

### Task 2 — in flight by marker

- **Dependencies:** 1
- **Estimated effort:** 3 days

### Task 3 — genuinely ready

- **Dependencies:** 1
- **Estimated effort:** half day

## Awaiting input

(none yet)

## Deferred

(none yet)

## Out of scope

(none yet)
EOF
seal_base "$dv3"
done_trailer "$dv3" vtwolive 1
inflight_marker "$dv3spec" 2
got=$(/bin/bash "$SEL" "$dv3spec") || fail "v2-live fixture: non-zero exit ($?)"
[ "$got" = 3 ] || fail "v2-live: selected '$got', expected 3 (1 completed, 2 in flight — derivation, no sections)"
echo "ok: v2 completed/in-progress exclusion derives from evidence, not sections (REQ-C1.2)"

# V4. Chain-weight terminality on v2: an out-of-scope-parked dependent never
#     lengthens the remaining critical path (it is not future work), while a
#     deferred-parked dependent still does — mirroring the v1 section
#     semantics (only Out of scope and completed are terminal).
v4_tasks_md() {
  # $1 = file, $2 = the section parking task 3 (Deferred | Out of scope)
  cat >"$1" <<EOF
# tasks

**Format-version:** 2

## Tasks

### Task 1 — root

- **Dependencies:** none
- **Estimated effort:** 1 day

### Task 2 — chain head (its weight rides on task 3)

- **Dependencies:** 1
- **Estimated effort:** half day

### Task 3 — heavy dependent, parked

- **Dependencies:** 2
- **Estimated effort:** 3 days

### Task 4 — leaf

- **Dependencies:** 1
- **Estimated effort:** 1 day

## Awaiting input

(none yet)

## Deferred

$([ "$2" = Deferred ] && printf -- '- **Task 3** deferred behind a gate.' || printf '(none yet)')

## Out of scope

$([ "$2" = "Out of scope" ] && printf -- '- **Task 3** excluded by decision.' || printf '(none yet)')
EOF
}
dv4a="$tmp/v2oosweight"
dv4aspec=$(new_spec "$dv4a" vtwooos)
v4_tasks_md "$dv4aspec/tasks.md" "Out of scope"
seal_base "$dv4a"
done_trailer "$dv4a" vtwooos 1
got=$(/bin/bash "$SEL" "$dv4aspec") || fail "v2-oos-weight fixture: non-zero exit ($?)"
[ "$got" = 4 ] || fail "v2-oos-weight: selected '$got', expected 4 (task 3 out-of-scope-parked must not extend 2's chain)"
dv4b="$tmp/v2defweight"
dv4bspec=$(new_spec "$dv4b" vtwodef)
v4_tasks_md "$dv4bspec/tasks.md" Deferred
seal_base "$dv4b"
done_trailer "$dv4b" vtwodef 1
got=$(/bin/bash "$SEL" "$dv4bspec") || fail "v2-def-weight fixture: non-zero exit ($?)"
[ "$got" = 2 ] || fail "v2-def-weight: selected '$got', expected 2 (a deferred-parked dependent still extends the chain)"
echo "ok: v2 out-of-scope bullets are chain-terminal; deferred bullets are not (v1 parity)"

# V5. REQ-B1.5 — transient evidence failure on a v2 bundle dispatches nothing:
#     with a remote configured and gh failing, the selector exits 3 (distinct
#     from 1 no-ready-unit and 2 malformed-input) with an empty stdout. The v1
#     degraded path above (check 17) still selects git-only — v1 unchanged.
dv5="$tmp/v2degraded"
dv5spec=$(new_spec "$dv5" vtwodeg)
cat >"$dv5spec/tasks.md" <<'EOF'
# tasks

**Format-version:** 2

## Tasks

### Task 1 — root

- **Dependencies:** none
- **Estimated effort:** 1 day

## Awaiting input

(none yet)

## Deferred

(none yet)

## Out of scope

(none yet)
EOF
seal_base "$dv5"
gitc "$dv5" remote add origin https://example.invalid/demo.git
v5_err="$tmp/v2degraded.err"
rc=0
v5_out=$(PATH="$degstub:$PATH" /bin/bash "$SEL" "$dv5spec" 2>"$v5_err") || rc=$?
[ "$rc" = 3 ] || fail "v2-degraded: exit $rc, expected 3 (transient evidence failure, dispatch nothing)"
[ -z "$v5_out" ] || fail "v2-degraded: stdout must be empty (got '$v5_out')"
grep -q 'transient evidence failure' "$v5_err" \
  || fail "v2-degraded: stderr must name the transient failure (got: $(cat "$v5_err"))"
echo "ok: v2 transient evidence failure exits 3 and dispatches nothing (REQ-B1.5)"

# V6. REQ-C1.9 — a reference bullet whose task id violates the task-id grammar
#     is rejected with a sanitized stderr warning and never used; a well-formed
#     bullet naming a non-existent task matches nothing here (asserting only
#     that it causes no crash or spurious warning — the unknown-id error itself
#     is the validator's, and is unobservable at this surface); selection
#     proceeds on the valid state either way.
dv6="$tmp/v2badbullet"
dv6spec=$(new_spec "$dv6" vtwobad)
{
  printf '# tasks\n\n**Format-version:** 2\n\n## Tasks\n\n'
  printf '### Task 1 — the only task\n\n'
  printf -- '- **Dependencies:** none\n'
  printf -- '- **Estimated effort:** 1 day\n\n'
  printf '## Awaiting input\n\n'
  # A grammar-violating bullet id carrying a raw ESC byte: rejected, sanitized.
  printf -- '- **Task 9\033[31mx** hostile id, must be rejected.\n'
  # A well-formed id naming a task that does not exist: parks nothing.
  printf -- '- **Task 99** names no existing task.\n\n'
  printf '## Deferred\n\n(none yet)\n\n## Out of scope\n\n(none yet)\n'
} >"$dv6spec/tasks.md"
seal_base "$dv6"
v6_err="$tmp/v2badbullet.err"
rc=0
v6_out=$(/bin/bash "$SEL" "$dv6spec" 2>"$v6_err") || rc=$?
[ "$rc" = 0 ] || fail "v2-bad-bullet: exit $rc, expected 0 (stderr: $(cat "$v6_err"))"
[ "$v6_out" = 1 ] || fail "v2-bad-bullet: selected '$v6_out', expected 1"
grep -q 'violates the task-id grammar' "$v6_err" \
  || fail "v2-bad-bullet: rejected bullet id must be surfaced on stderr (got: $(cat "$v6_err"))"
LC_ALL=C grep '[^ -~]' "$v6_err" >/dev/null \
  && fail "v2-bad-bullet: stderr carries non-printable bytes (unsanitized bullet id)"
echo "ok: v2 grammar-violating bullet ids are rejected with a sanitized warning (REQ-C1.9)"

# V7. Fenced code blocks are illustration in the v2 parked map: a fenced
#     example bullet must not park its task, and a fenced section heading must
#     not end the real section around it (a real bullet after the fence still
#     parks). Mirrors the drain-gates parked-map fence guard.
dv7="$tmp/v2fence"
dv7spec=$(new_spec "$dv7" vtwofence)
cat >"$dv7spec/tasks.md" <<'EOF'
# tasks

**Format-version:** 2

## Tasks

### Task 1 — ready, illustrated as parked in a fence

- **Dependencies:** none
- **Estimated effort:** 1 day

### Task 2 — genuinely parked after an embedded fence (heavier, so a
suppressed park flips the pick and fails the assertion)

- **Dependencies:** none
- **Estimated effort:** 3 days

## Awaiting input

(none yet)

## Deferred

```markdown
## Deferred

- **Task 1** an illustrative parking bullet, not a real one.
```

- **Task 2** genuinely parked; the fence above must not have ended the section.

## Out of scope

(none yet)
EOF
seal_base "$dv7"
got=$(/bin/bash "$SEL" "$dv7spec") || fail "v2-fence fixture: non-zero exit ($?)"
[ "$got" = 1 ] || fail "v2-fence: selected '$got', expected 1 (fenced bullet must not park 1; real bullet after the fence must park 2)"
echo "ok: v2 parked-map parse treats fenced content as illustration"

# V8. A fenced Format-version example must not shadow the real header line: the
#     bundle below is v2 (real header) with a fenced v1 example BELOW the header
#     block; v2 semantics (bullet parking) must apply.
#
#     The declaration sits in the header block and the fenced example below it,
#     because the parse is header-block-scoped since format-grammar Task 2
#     (REQ-A1.3, D-7): the block ends at the first line that is neither blank,
#     the H1, nor a bolded header line — a column-0 fence is one such line, so a
#     declaration BELOW a fence is body content and inert. Both readings agree
#     that the fenced example is not the declaration; the scoped one additionally
#     requires the real declaration to be where the format says it lives.
dv8="$tmp/v2fvfence"
dv8spec=$(new_spec "$dv8" vtwofvfence)
cat >"$dv8spec/tasks.md" <<'EOF'
# tasks

**Format-version:** 2

```markdown
**Format-version:** 1
```

## Tasks

### Task 1 — parked by bullet

- **Dependencies:** none
- **Estimated effort:** 3 days

### Task 2 — ready

- **Dependencies:** none
- **Estimated effort:** half day

## Awaiting input

- **Task 1** parked; only v2 semantics read this bullet.

## Deferred

(none yet)

## Out of scope

(none yet)
EOF
seal_base "$dv8"
got=$(/bin/bash "$SEL" "$dv8spec") || fail "v2-fv-fence fixture: non-zero exit ($?)"
[ "$got" = 2 ] || fail "v2-fv-fence: selected '$got', expected 2 (fenced FV example must not select v1 rules; bullet must park 1)"
echo "ok: a fenced Format-version example does not shadow the real header line"

# V9. Prose-bullet tolerance (validator parity): a plain prose bullet whose
#     bold lead happens to start with "Task " plus inner whitespace ("**Task
#     force assembled.**") is a plain bullet the format allows in Deferred /
#     Out of scope — silently skipped, never warned about as a grammar
#     violation, and parking nothing.
dv9="$tmp/v2prose"
dv9spec=$(new_spec "$dv9" vtwoprose)
cat >"$dv9spec/tasks.md" <<'EOF'
# tasks

**Format-version:** 2

## Tasks

### Task 1 — ready

- **Dependencies:** none
- **Estimated effort:** 1 day

## Awaiting input

(none yet)

## Deferred

- **Task force assembled.** A plain prose bullet, not a task reference.

## Out of scope

(none yet)
EOF
seal_base "$dv9"
v9_err="$tmp/v2prose.err"
rc=0
v9_out=$(/bin/bash "$SEL" "$dv9spec" 2>"$v9_err") || rc=$?
[ "$rc" = 0 ] || fail "v2-prose: exit $rc, expected 0 (stderr: $(cat "$v9_err"))"
[ "$v9_out" = 1 ] || fail "v2-prose: selected '$v9_out', expected 1 (a prose bullet parks nothing)"
grep -q 'violates the task-id grammar' "$v9_err" \
  && fail "v2-prose: a plain prose bullet must not be warned about as a rejected reference (got: $(cat "$v9_err"))"
echo "ok: prose bullets with inner whitespace are tolerated silently (validator parity)"

# V10. No-PR-found is evidence, not failure (REQ-B1.5): a working gh that
#      returns an EMPTY PR list is a definitive negative result — the v2
#      selector must select normally (exit 0), never exit 3.
dv10="$tmp/v2emptygh"
dv10spec=$(new_spec "$dv10" vtwoemptygh)
cat >"$dv10spec/tasks.md" <<'EOF'
# tasks

**Format-version:** 2

## Tasks

### Task 1 — ready

- **Dependencies:** none
- **Estimated effort:** 1 day

## Awaiting input

(none yet)

## Deferred

(none yet)

## Out of scope

(none yet)
EOF
seal_base "$dv10"
gitc "$dv10" remote add origin https://example.invalid/demo.git
okstub="$tmp/binokgh"
mkdir -p "$okstub"
printf '#!/bin/sh\nexit 0\n' >"$okstub/gh"
chmod +x "$okstub/gh"
rc=0
v10_out=$(PATH="$okstub:$PATH" /bin/bash "$SEL" "$dv10spec" 2>/dev/null) || rc=$?
[ "$rc" = 0 ] || fail "v2-empty-gh: exit $rc, expected 0 (an empty PR list is evidence, not failure)"
[ "$v10_out" = 1 ] || fail "v2-empty-gh: selected '$v10_out', expected 1"
echo "ok: an empty gh PR list is evidence, not a transient failure (REQ-B1.5)"

echo "PASS: orchestrate-select (format-version 2 candidacy)"
