#!/bin/bash
# Tests for scripts/migrate-status-lifecycle.sh — the one-time adoption migration
# sweep for the six-status lifecycle (kickoff-lifecycle Task 8; REQ-A1.7, D-4).
#
# The sweep is a thin one-time application of the single reconcile writer
# (tasks-pr-sync.sh reconcile-status, do_status) over every spec bundle: an
# Active-with-no-progress bundle migrates to Ready, a started bundle stays Active,
# Done takes precedence; Draft / Retired / Superseded and stored-Done are left
# untouched by the writer's own guards. The sweep adds the corpus iteration
# (excluding underscore accumulators), per-bundle malformed skip-and-report, and
# idempotence.
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
MIGRATE="$here/../scripts/migrate-status-lifecycle.sh"
SYNC="$here/../scripts/tasks-pr-sync.sh"
STATE="$here/../scripts/orchestrate-state.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -x "$MIGRATE" ] || fail "scripts/migrate-status-lifecycle.sh missing or not executable"
[ -x "$SYNC" ] || fail "scripts/tasks-pr-sync.sh missing (the single writer the sweep drives)"
[ -x "$STATE" ] || fail "scripts/orchestrate-state.sh missing (the derivation backbone)"
command -v jq >/dev/null 2>&1 || fail "jq required to run this suite"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# A deterministic, no-network gh stub (mirrors test-tasks-pr-sync.sh): the
# derivation falls back to git-only evidence.
stub=$tmp/bin
mkdir -p "$stub"
cat >"$stub/gh" <<'EOF'
#!/bin/sh
case "$*" in
  *"pr list"*) exit 0 ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$stub/gh"

status_of() { awk '/^\*\*Status:\*\* / { print $2; exit }' "$1"; }
assert_all() { # <spec-dir> <expected> <label>
  for f in requirements.md design.md tasks.md test-spec.md; do
    [ -f "$1/$f" ] || continue
    got=$(status_of "$1/$f")
    [ "$got" = "$2" ] || fail "$3: $f Status=$got, expected $2"
  done
}

# heads <spec-dir> <status>: requirements/design/test-spec headers mirrored.
heads() {
  mkdir -p "$1"
  printf '%s\n' '# Spec — Requirements' '' "**Status:** $2" '**Format-version:** 1' >"$1/requirements.md"
  printf '%s\n' '# Spec — Design' '' "**Status:** $2" '**Format-version:** 1' >"$1/design.md"
  printf '%s\n' '# Spec — Test Spec' '' "**Status:** $2" '**Format-version:** 1' >"$1/test-spec.md"
}

# two_tasks <spec-dir> <status>: a two-task tasks.md, both under Forward plan.
two_tasks() {
  {
    printf '%s\n' '# Spec — Tasks' '' "**Status:** $2" '**Format-version:** 1' ''
    printf '%s\n' '## Forward plan' ''
    printf '%s\n' '### Task 1 — Alpha' ''
    printf '%s\n' '- **Deliverables:** Alpha.' '- **Done when:** Alpha done.' \
      '- **Dependencies:** none' '- **Citations:** REQ-X1.1' '- **Estimated effort:** 1 day' ''
    printf '%s\n' '### Task 2 — Beta' ''
    printf '%s\n' '- **Deliverables:** Beta.' '- **Done when:** Beta done.' \
      '- **Dependencies:** none' '- **Citations:** REQ-X1.2' '- **Estimated effort:** 1 day' ''
    printf '%s\n' '## In progress' '' '(none yet)' ''
    printf '%s\n' '## Awaiting input' '' '(none yet)' ''
    printf '%s\n' '## Completed' '' '(none yet)'
  } >"$1/tasks.md"
}

# A single fixture corpus exercises every per-bundle outcome at once:
#   active-idle   — Active, no progress           -> migrates to Ready
#   active-busy   — Active, Task 1 in-progress     -> stays Active
#   done-spec     — Done, no progress              -> stays Done (never reopened)
#   draft-spec    — Draft                          -> left untouched
#   malformed     — Active header, no task blocks   -> skipped (malformed)
#   _accumulator  — underscore-prefixed             -> excluded entirely
repo=$tmp/corpus
mkdir -p "$repo"
git -C "$repo" init -q -b main
git -C "$repo" config user.email t@example.com
git -C "$repo" config user.name t
git -C "$repo" config commit.gpgsign false

heads "$repo/specs/active-idle" Active
two_tasks "$repo/specs/active-idle" Active

heads "$repo/specs/active-busy" Active
two_tasks "$repo/specs/active-busy" Active

heads "$repo/specs/done-spec" Done
two_tasks "$repo/specs/done-spec" Done

heads "$repo/specs/draft-spec" Draft
two_tasks "$repo/specs/draft-spec" Draft

# Malformed: a bundle header but no task blocks at all.
mkdir -p "$repo/specs/malformed"
printf '%s\n' '# Malformed — Requirements' '' '**Status:** Active' >"$repo/specs/malformed/requirements.md"
printf '%s\n' '# Malformed — Tasks' '' '**Status:** Active' '' '## Forward plan' '' '(none yet)' \
  >"$repo/specs/malformed/tasks.md"

# An underscore accumulator the sweep must skip without touching.
mkdir -p "$repo/specs/_observations"
printf '%s\n' '# Observations' '' 'Status: not a bundle header' >"$repo/specs/_observations/opportunities.md"

git -C "$repo" add -A
git -C "$repo" commit -qm fixture

# Give active-busy in-flight evidence: a task branch with a commit ahead of base.
git -C "$repo" branch planwright/active-busy/task-1
git -C "$repo" checkout -q planwright/active-busy/task-1
git -C "$repo" commit -q --allow-empty -m "wip: task 1"
git -C "$repo" checkout -q main

# Derivation precondition: active-idle has no progress; active-busy has one
# in-progress task. Guards against a fixture that does not actually exercise the
# Active->Ready arm.
idle_states=$(cd "$repo" && PATH="$stub:$PATH" "$STATE" specs/active-idle \
  | awk -F'\t' '$1=="task"{print $3}' | sort -u | tr '\n' ' ')
case "$idle_states" in
  *in-progress* | *completed*) fail "precondition: active-idle has progress ($idle_states)" ;;
esac
busy_states=$(cd "$repo" && PATH="$stub:$PATH" "$STATE" specs/active-busy \
  | awk -F'\t' '$1=="task"{print $2"="$3}' | sort | tr '\n' ' ')
case "$busy_states" in
  *"1=in-progress"*) ;;
  *) fail "precondition: active-busy Task 1 not in-progress ($busy_states)" ;;
esac

# --- Run 1: the migration sweep over the corpus.
out=$(cd "$repo" && PATH="$stub:$PATH" "$MIGRATE" specs 2>"$tmp/run1.err") \
  || fail "sweep exited non-zero"

assert_all "$repo/specs/active-idle" Ready "REQ-A1.7 Active-with-no-progress -> Ready"
assert_all "$repo/specs/active-busy" Active "REQ-A1.7 started bundle stays Active"
assert_all "$repo/specs/done-spec" Done "REQ-A1.6 stored-Done never reopened"
assert_all "$repo/specs/draft-spec" Draft "REQ-A1.4 Draft left untouched"
echo "ok: sweep migrates Active-with-no-progress to Ready, leaves busy/Done/Draft (REQ-A1.7)"

# Malformed bundle: surfaced by path on stderr, header NOT flipped.
grep -q "skipped (malformed): .*/specs/malformed" "$tmp/run1.err" \
  || fail "malformed bundle not surfaced by path on stderr"
[ "$(status_of "$repo/specs/malformed/requirements.md")" = Active ] \
  || fail "malformed bundle's Status was flipped despite the skip"
echo "ok: a malformed bundle is surfaced by path and skipped, never silently flipped (REQ-A1.7)"

# Accumulator: untouched, never reported as a bundle.
case "$out" in
  *_observations*) fail "underscore accumulator was treated as a bundle" ;;
esac
grep -q "_observations" "$tmp/run1.err" && fail "underscore accumulator surfaced in the report"
echo "ok: underscore-prefixed accumulators are excluded from the sweep"

# Summary line: one migrated (active-idle), three unchanged (busy/done/draft),
# one skipped (malformed).
case "$out" in
  *"1 migrated, 3 unchanged, 1 skipped"*) ;;
  *) fail "unexpected summary line: $out" ;;
esac
echo "ok: the sweep reports a per-outcome summary"

# --- Run 2: idempotence. A second sweep over the now-migrated corpus changes
# nothing and reports zero migrations.
before_snap=$tmp/snap
mkdir -p "$before_snap"
find "$repo/specs" -name '*.md' -type f | sort | while read -r f; do
  rel=${f#"$repo"/}
  mkdir -p "$before_snap/$(dirname "$rel")"
  cp "$f" "$before_snap/$rel"
done
out2=$(cd "$repo" && PATH="$stub:$PATH" "$MIGRATE" specs 2>/dev/null) \
  || fail "second sweep exited non-zero"
find "$repo/specs" -name '*.md' -type f | sort | while read -r f; do
  rel=${f#"$repo"/}
  cmp -s "$before_snap/$rel" "$f" || fail "idempotence: $rel changed on the second sweep"
done
case "$out2" in
  *"0 migrated,"*) ;;
  *) fail "second sweep reported a migration on an already-migrated corpus: $out2" ;;
esac
echo "ok: the sweep is idempotent — a second run is a no-op (REQ-A1.7, D-4)"

# --- Operational failure: an unreachable specs dir fails closed (exit 2).
("$MIGRATE" "$tmp/does-not-exist" >/dev/null 2>&1) \
  && fail "sweep over a nonexistent specs dir did not fail closed"
echo "ok: the sweep fails closed on an unreachable specs dir (exit 2)"

# --- A partial mirror (a symlinked sibling the writer refuses) is reported as a
# per-bundle skip with the writer's diagnostic surfaced, never a false
# "unchanged"/"migrated" (REQ-A1.7 skip-and-report). The bundle passes the sweep's
# file pre-checks (requirements.md and tasks.md are regular), so the failure is the
# in-writer refusal that reconcile-status now propagates.
repo2=$tmp/corpus2
mkdir -p "$repo2"
git -C "$repo2" init -q -b main
git -C "$repo2" config user.email t@example.com
git -C "$repo2" config user.name t
git -C "$repo2" config commit.gpgsign false
heads "$repo2/specs/partial" Active
two_tasks "$repo2/specs/partial" Active
mv "$repo2/specs/partial/design.md" "$repo2/specs/partial/design.real.md"
ln -s design.real.md "$repo2/specs/partial/design.md"
git -C "$repo2" add -A
git -C "$repo2" commit -qm fixture
out3=$(cd "$repo2" && PATH="$stub:$PATH" "$MIGRATE" specs 2>"$tmp/run3.err") \
  || fail "sweep over a partial-mirror corpus exited non-zero"
grep -q "skipped (reconcile failed): .*/specs/partial" "$tmp/run3.err" \
  || fail "partial-mirror bundle not reported as skipped (reconcile failed)"
grep -q "refusing symlinked" "$tmp/run3.err" \
  || fail "partial-mirror skip did not surface the writer's diagnostic"
case $out3 in
  *"0 migrated, 0 unchanged, 1 skipped"*) ;;
  *) fail "partial-mirror corpus summary wrong: $out3" ;;
esac
echo "ok: a partial-mirror bundle is reported skipped (reconcile failed) with its diagnostic, not unchanged (REQ-A1.7)"

# --- An existing but empty specs dir is a clean no-op: the no-match glob stays
# literal and is skipped, so the sweep reports a zero-count summary and exits 0
# (no bundles to migrate, nothing to fail on).
emptyspecs=$tmp/empty-corpus/specs
mkdir -p "$emptyspecs"
out_empty=$("$MIGRATE" "$emptyspecs" 2>/dev/null) \
  || fail "sweep over an existing but empty specs dir exited non-zero"
case "$out_empty" in
  *"0 migrated, 0 unchanged, 0 skipped"*) ;;
  *) fail "empty specs dir summary wrong: $out_empty" ;;
esac
echo "ok: an existing but empty specs dir is a clean no-op (REQ-A1.7)"

# --- A bundle with real task blocks but NO **Status:** header in requirements.md
# (the authoritative Status home) is malformed: the reconcile is a deliberate
# no-op (do_status leaves an absent header untouched), so the bundle's before/after
# Status are both empty. Without a header pre-check arm the sweep miscounts it as
# "unchanged ()" instead of skip-and-reporting it — the very "never silently
# flipped / surfaced by path" contract the malformed pre-check exists to honor. The
# bundle clears the file + task-block pre-checks, so this isolates the header arm.
repo3=$tmp/corpus3
mkdir -p "$repo3"
git -C "$repo3" init -q -b main
git -C "$repo3" config user.email t@example.com
git -C "$repo3" config user.name t
git -C "$repo3" config commit.gpgsign false
sd3=$repo3/specs/headerless
mkdir -p "$sd3"
printf '%s\n' '# Headerless — Requirements' '' 'No bundle Status header here.' >"$sd3/requirements.md"
printf '%s\n' '# Headerless — Design' '' 'No bundle Status header.' >"$sd3/design.md"
printf '%s\n' '# Headerless — Test Spec' '' 'No bundle Status header.' >"$sd3/test-spec.md"
two_tasks "$sd3" Active # real task blocks so the bundle clears the task-block arm
git -C "$repo3" add -A
git -C "$repo3" commit -qm fixture
out_hl=$(cd "$repo3" && PATH="$stub:$PATH" "$MIGRATE" specs 2>"$tmp/run-hl.err") \
  || fail "sweep over a headerless-bundle corpus exited non-zero"
grep -q "skipped (malformed): .*/specs/headerless" "$tmp/run-hl.err" \
  || fail "headerless bundle not surfaced as skipped (malformed) by path on stderr"
case $out_hl in
  *"0 migrated, 0 unchanged, 1 skipped"*) ;;
  *) fail "headerless-bundle summary wrong (expected skip, not unchanged): $out_hl" ;;
esac
echo "ok: a bundle missing its requirements.md **Status:** header is skipped (malformed), not miscounted unchanged (REQ-A1.7)"

echo "PASS: all migrate-status-lifecycle tests passed"
