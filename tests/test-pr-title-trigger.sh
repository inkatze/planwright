#!/bin/bash
# Tests for the PR-title lint's trigger and its isolation from the code gate.
#
# The defect pinned here (observed 2026-09-07 on PR 414; recorded as an
# observation entry and carried by PR 420): the conventional-commit lint over
# the PR TITLE reads the title out of the pull_request event payload, but the
# workflow carrying it declared a bare `pull_request:` — the default
# opened/synchronize/reopened, with no `edited`. A PR rejected for its title
# therefore had no path back to green: retitling raises no event that re-runs
# the gate, and `gh run rerun` replays the ORIGINAL payload, so it re-reads the
# stale title. The only exits were a spurious commit or a close/reopen. A gate
# that can reject an input it cannot re-check is a one-way door, which is what
# makes the trigger worth pinning rather than remembering.
#
# Why the lint lives in its own workflow instead of gaining `edited` in place:
# GitHub renders `github.ref` as refs/pull/<n>/merge for EVERY pull_request
# activity type, so an `edited` run and a `synchronize` run of one workflow
# land in the same concurrency group. Under cancel-in-progress that means
# editing a title or body mid-run cancels the run testing the code. Splitting
# the metadata gate onto its own group key is what keeps a retitle from killing
# code CI.
#
# That split holds only while the group STRINGS differ: concurrency groups are
# scoped to the repository, not to the workflow file. GitHub's concurrency
# reference: "concurrency group names must be unique across workflows to avoid
# canceling in-progress jobs or runs from other workflows. Otherwise, any
# previously in-progress or pending job will be canceled, regardless of the
# workflow." C3 below is what holds that, and it is why a separate file alone
# would not have been enough.
#
# Each assertion is preceded by an anti-vacuity check: a guard that finds
# nothing to inspect must fail rather than report a clean sweep over an empty
# set.
#
# Portable bash 3.2 floor; runs under /bin/bash in CI.
set -u
unset CDPATH

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORKFLOW_DIR="$REPO_ROOT/.github/workflows"

failures=0
pass() { echo "ok: $1"; }
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}

if [ ! -d "$WORKFLOW_DIR" ]; then
  fail "no .github/workflows directory — nothing to inspect"
  echo "$failures test(s) failed." >&2
  exit 1
fi

# Strip trailing comments before scanning for content, so a comment that merely
# NAMES an expression is never mistaken for a use of it. Same normalization,
# and the same accepted residual (a literal `#` inside a value truncates the
# line and fails loud), as scripts/check-workflow-posture.sh.
uncommented() { sed 's/#.*$//' "$1"; }

# Emit the body of a workflow's `<key>:` block: the lines indented deeper than
# the key itself. A bare `pull_request:` yields nothing, which is exactly the
# defect state. Comments are stripped first, so
# `types: [opened]  # TODO: add edited` cannot satisfy the C2 scan below —
# over-matching here would be a false PASS, the one direction that hides the
# defect this file exists to catch.
block_body() {
  uncommented "$1" | awk -v key="$2" '
    {
      n = match($0, /[^ ]/)
      if (n == 0) next
      indent = n - 1
      if ($0 ~ "^[[:space:]]*" key ":[[:space:]]*$") {
        inblock = 1
        blockindent = indent
        next
      }
      if (inblock && indent <= blockindent) inblock = 0
      if (inblock) print
    }
  '
}

# Emit every concurrency group string a workflow declares: the `group:` values
# inside a `concurrency:` block, top-level or job-level. Scoped to that block
# because `group:` is also a runs-on key (runner groups), and reading one of
# those would point the uniqueness check below at a string that is not a
# concurrency group at all.
concurrency_groups() {
  block_body "$1" concurrency | awk '
    /^[[:space:]]*group:[[:space:]]*/ {
      sub(/^[[:space:]]*group:[[:space:]]*/, "")
      sub(/[[:space:]]*$/, "")
      if ($0 != "") print
    }
  '
}

# --- C1: the metadata gate is discoverable -----------------------------------
# Every workflow that reads PR metadata a human can edit after the fact. This
# set drives C2 and C4, so an empty set is a failure, not a pass.
metadata_workflows=""
for wf in "$WORKFLOW_DIR"/*.yml "$WORKFLOW_DIR"/*.yaml; do
  [ -f "$wf" ] || continue
  # Only a pull_request-triggered workflow can read the PR payload at all.
  # Stripped like every other scan here: reading the raw file would drop a
  # workflow whose trigger line carries a trailing comment, and a workflow
  # dropped from this set is never checked by C2 at all.
  uncommented "$wf" | grep -qE '^[[:space:]]*pull_request:[[:space:]]*$' || continue
  if uncommented "$wf" \
    | grep -qE 'github\.event\.pull_request\.(title|body)'; then
    metadata_workflows="$metadata_workflows $wf"
  fi
done

if [ -n "$metadata_workflows" ]; then
  pass "C1 found a pull_request workflow reading editable PR metadata"
else
  fail "C1 no pull_request workflow reads github.event.pull_request.title/body —
    the title lint is gone or renamed; C2 and C4 would sweep an empty set"
fi

# --- C2: that gate fires on `edited`, so a correction is re-checkable --------
for wf in $metadata_workflows; do
  label="${wf#"$REPO_ROOT"/}"
  if block_body "$wf" pull_request | grep -qE '(^|[^a-z_])edited([^a-z_]|$)'; then
    pass "C2 $label lints editable PR metadata and fires on edited"
  else
    fail "C2 $label reads github.event.pull_request.title/body but its
    pull_request trigger omits 'edited' — a PR it rejects for its title has no
    path back to green (rerun replays the original payload's stale title)"
  fi
done

# --- C3: concurrency groups are unique across workflow files -----------------
# Groups are repository-scoped, so two files sharing a group string cancel each
# other regardless of which workflow queued the run.
groups=""
group_count=0
for wf in "$WORKFLOW_DIR"/*.yml "$WORKFLOW_DIR"/*.yaml; do
  [ -f "$wf" ] || continue
  # Fed by here-doc rather than a pipe: a `while read` on the right-hand side
  # of a pipe runs in a subshell, and the counter and failure tally raised in
  # the body would be discarded with it.
  while IFS= read -r g; do
    [ -n "$g" ] || continue
    group_count=$((group_count + 1))
    # Group keys are case-insensitive per GitHub's concurrency reference, so
    # compare them that way or a casing-only difference would read as unique.
    g_fold="$(printf '%s' "$g" | tr '[:upper:]' '[:lower:]')"
    if printf '%s\n' "$groups" | grep -qxF "$g_fold"; then
      fail "C3 ${wf#"$REPO_ROOT"/} reuses concurrency group '$g' — groups are
    repository-scoped, so these two workflows cancel each other"
    fi
    groups="$groups
$g_fold"
  done <<EOF
$(concurrency_groups "$wf")
EOF
done

if [ "$group_count" -ge 2 ]; then
  pass "C3 $group_count concurrency group(s) declared across workflows, all distinct"
else
  fail "C3 only $group_count concurrency group(s) found —
    too few for the uniqueness check to mean anything"
fi

# --- C4: the metadata gate is not the code gate ------------------------------
# The two must stay in separate workflows. Sharing one workflow puts both on a
# single concurrency key (github.ref does not vary by activity type), which is
# the regression the split exists to prevent.
CODE_GATE='mise run check'
code_gate_workflows=""
for wf in "$WORKFLOW_DIR"/*.yml "$WORKFLOW_DIR"/*.yaml; do
  [ -f "$wf" ] || continue
  if uncommented "$wf" | grep -qF "$CODE_GATE"; then
    code_gate_workflows="$code_gate_workflows $wf"
  fi
done

if [ -n "$code_gate_workflows" ]; then
  pass "C4 found the aggregate code gate ('$CODE_GATE')"
else
  fail "C4 no workflow runs '$CODE_GATE' — the code gate moved or was renamed;
    the separation check below would pass vacuously"
fi

for wf in $code_gate_workflows; do
  label="${wf#"$REPO_ROOT"/}"
  if block_body "$wf" pull_request | grep -qE '(^|[^a-z_])edited([^a-z_]|$)'; then
    fail "C4 $label runs the code gate AND fires on edited — a title or body
    edit would cancel the in-flight run testing the code (same concurrency
    group: github.ref is refs/pull/<n>/merge for every activity type)"
  else
    pass "C4 $label runs the code gate and does not fire on metadata edits"
  fi
done

if [ "$failures" -eq 0 ]; then
  echo "All PR-title trigger tests passed."
  exit 0
fi
echo "$failures test(s) failed." >&2
exit 1
