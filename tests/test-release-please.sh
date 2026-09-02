#!/bin/bash
# Tests for the release-please PR-only configuration and the opt-in adopter
# template (Task 5, specs/autopilot-reflex), plus the untagged-window guard on
# the proposal job (Task 9, specs/release-hardening).
#
# Covers the testable slice of the task's verification paths:
#   REQ-C1.2 — .claude-plugin/plugin.json $.version is the version source of
#              truth (the config's only automated writer targets it).
#   REQ-C1.3 — CI never tags: the workflow is PR-only (skip-github-release),
#              and neither the workflow nor the template tags or cuts a Release.
#   REQ-C1.4 — merge is the human's: no shipped script/workflow/skill/template
#              INVOKES a merge of the release PR.
#   REQ-F1.1 — the release-PR body carries the merge-then-publish instructions.
#   REQ-G1.3 — the templates ship in an opt-in location and never auto-land in
#              an active workflow path.
#
# And from specs/release-hardening (REQ-H1.1, D-13; obs:fd6c2f4f, obs:131af768):
#   REQ-H1.1 — the proposal job is guarded by scripts/release-window-check.sh,
#              the guard precedes the proposal step and splits that script's
#              tri-state exit (0 proceeds, 1 skips, 2 fails), over a checkout
#              that carries the tags and origin/main and resolves the
#              repository's own default branch rather than any ref the
#              triggering workflow_run carries.
#
# The remaining REQ-C1.1 / REQ-C1.5 checks are [manual] (a live release-PR
# cycle) and are exercised in the organic proof (Task 11), not here.
#
# Portable bash 3.2 floor; runs under /bin/bash in CI (REQ-K1.5).
set -u
unset CDPATH

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

WORKFLOW="$REPO_ROOT/.github/workflows/release-please.yml"
CONFIG="$REPO_ROOT/release-please-config.json"
MANIFEST="$REPO_ROOT/.release-please-manifest.json"
PLUGIN="$REPO_ROOT/.claude-plugin/plugin.json"
TEMPLATE_DIR="$REPO_ROOT/templates/release-please"
TEMPLATE_WORKFLOW="$TEMPLATE_DIR/release-please.yml"
TEMPLATE_CONFIG="$TEMPLATE_DIR/release-please-config.json"
TEMPLATE_MANIFEST="$TEMPLATE_DIR/.release-please-manifest.json"

# The greppable marker that distinguishes a template from an active workflow.
SENTINEL="planwright-adopter-template"

failures=0
pass() { echo "ok: $1"; }
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}

command -v jq >/dev/null 2>&1 || {
  echo "FAIL: jq required to run this suite" >&2
  exit 1
}

for f in "$WORKFLOW" "$CONFIG" "$MANIFEST" "$PLUGIN" \
  "$TEMPLATE_WORKFLOW" "$TEMPLATE_CONFIG" "$TEMPLATE_MANIFEST"; do
  [ -f "$f" ] || fail "expected file missing: ${f#"$REPO_ROOT"/}"
done

# --- REQ-C1.2: plugin.json $.version is the version source of truth ----------
# Both the live config and the template target the plugin manifest's $.version
# through a JSON-path extra-file.
for cfg in "$CONFIG" "$TEMPLATE_CONFIG"; do
  label="${cfg#"$REPO_ROOT"/}"
  if jq -e '.. | objects
      | select(.type? == "json" and .path? == ".claude-plugin/plugin.json"
               and .jsonpath? == "$.version")' "$cfg" >/dev/null 2>&1; then
    pass "C1.2 $label targets .claude-plugin/plugin.json \$.version (extra-file)"
  else
    fail "C1.2 $label does not target .claude-plugin/plugin.json \$.version"
  fi
done

# The live manifest's baseline matches the current plugin.json version, so
# release-please computes the next bump from the right base.
plugin_version="$(jq -r '.version // empty' "$PLUGIN" 2>/dev/null)"
manifest_version="$(jq -r '.["."] // empty' "$MANIFEST" 2>/dev/null)"
if [ -n "$plugin_version" ] && [ "$plugin_version" = "$manifest_version" ]; then
  pass "C1.2 manifest baseline ($manifest_version) matches plugin.json ($plugin_version)"
else
  fail "C1.2 manifest baseline '$manifest_version' != plugin.json '$plugin_version'"
fi

# Migration anchor: this repo carries hand-made release tags predating
# release-please, so the live config pins bootstrap-sha to the last release
# commit — without it the first release PR can dump full history into the
# changelog. Assert it is present and a 40-hex SHA (guards accidental removal
# before the first automated release; harmless/ignored afterward).
bootstrap_sha="$(jq -r '.["bootstrap-sha"] // ""' "$CONFIG" 2>/dev/null)"
if printf '%s' "$bootstrap_sha" | grep -qE '^[0-9a-f]{40}$'; then
  pass "C1.2 live config pins a 40-hex bootstrap-sha migration anchor"
else
  fail "C1.2 live config bootstrap-sha missing or not a 40-hex SHA ('$bootstrap_sha')"
fi

# --- REQ-C1.3: CI never tags — PR-only, no tag/Release from CI ---------------
# skip-github-release: true must be present, and never set false.
for wf in "$WORKFLOW" "$TEMPLATE_WORKFLOW"; do
  label="${wf#"$REPO_ROOT"/}"
  if grep -qE '^[[:space:]]*skip-github-release:[[:space:]]*true[[:space:]]*$' "$wf"; then
    pass "C1.3 $label sets skip-github-release: true (PR-only)"
  else
    fail "C1.3 $label does not set skip-github-release: true"
  fi
  if grep -qE '^[[:space:]]*skip-github-release:[[:space:]]*false' "$wf"; then
    fail "C1.3 $label sets skip-github-release: false"
  fi
  # No direct tagging / Release creation in the workflow itself. Strip only
  # whole-line comments (leading `#`), so an inline-commented tag/Release
  # command on a live line is still caught (a `#` anywhere no longer hides it).
  # -H so the `path:line:` prefix matches that filter; a bare `grep -n` emits
  # `line:` and the exclusion never fires.
  if grep -nHE '(git tag|gh release create|gh api[^#]*releases)' "$wf" \
    | grep -vE ':[0-9]+:[[:space:]]*#' | grep -q .; then
    fail "C1.3 $label contains a direct tag/Release-creation command"
  else
    pass "C1.3 $label contains no direct tag/Release-creation command"
  fi
  # SHA-pin (supply-chain invariant): the action must be pinned to a full
  # 40-hex commit SHA, never a mutable @vN / @main ref.
  if grep -qE 'uses:[[:space:]]*googleapis/release-please-action@[0-9a-f]{40}([[:space:]]|$)' "$wf"; then
    pass "C1.3 $label pins release-please-action to a 40-hex commit SHA"
  else
    fail "C1.3 $label does not pin release-please-action to a full commit SHA"
  fi
  # Gated on CI success on main (REQ-C1.1): the workflow_run trigger plus the
  # success + main guards. A regression that drops the conclusion guard would
  # propose releases off a red main; this catches it.
  if grep -qE '^[[:space:]]*workflow_run:' "$wf" \
    && grep -qE "conclusion[[:space:]]*==[[:space:]]*'success'" "$wf" \
    && grep -qE "head_branch[[:space:]]*==[[:space:]]*'main'" "$wf"; then
    pass "C1.1 $label gates on workflow_run + CI success on main"
  else
    fail "C1.1 $label missing the workflow_run / success / main gate"
  fi
done

# The live workflow's workflow_run references a workflow named `ci`; that
# workflow must actually exist, or release-please is silently never triggered.
if grep -qE '^[[:space:]]*workflows:[[:space:]]*\[[[:space:]]*ci[[:space:]]*\]' "$WORKFLOW"; then
  if grep -rlE '^name:[[:space:]]*ci[[:space:]]*$' "$REPO_ROOT/.github/workflows" >/dev/null 2>&1; then
    pass "C1.1 the referenced 'ci' workflow exists (workflow_run wiring is live)"
  else
    fail "C1.1 workflow_run references 'ci' but no .github/workflows file is named ci"
  fi
fi

# --- REQ-C1.4: merge is the human's — no merge INVOCATION on any surface ------
# Scan shipped executable/prose surfaces for a merge invocation of the release
# PR: the gh CLI merge, the REST/GraphQL merge APIs, and auto-merge. Two
# exclusions, each narrowly justified and NOT a blanket substring filter (so a
# future genuine invocation cannot hide merely by resembling them):
#   - whole-line comments (leading `#`) are documentation, not code;
#   - the Claude Code PERMISSIONS POLICY files, whose `gh pr merge` token is a
#     DENY rule (it BANS merging) — the opposite of a violation. Both the worker
#     policy (config/worker-settings.json) and the tower policy
#     (config/tower-settings.json, fleet-hardening D-8) carry the deny, so both
#     are excluded by PATH and separately asserted to be a deny.
# Note the detection code in scripts/tasks-pr-sync.sh uses the `gh_pr` wrapper
# (underscore), which never matches the literal `gh pr merge` scanned here.
POLICY_FILES="config/worker-settings.json config/tower-settings.json"
# Fixed-string exclusion, not ERE: a path like config/worker-settings.json carries
# a regex metacharacter (the "." before json). Under grep -E that "." is a wildcard,
# so the exclusion would also swallow look-alike paths (config/worker-settingsXjson)
# and could hide a real merge invocation in such a file. Build one -e fixed pattern
# per policy file and match with grep -vF so only the exact paths are excluded.
policy_exclude_args=()
for pf in $POLICY_FILES; do
  policy_exclude_args+=(-e "/${pf}:")
done
merge_hits="$(
  grep -rnE 'gh pr merge|pulls/[^ ]*/merge|mergePullRequest|enablePullRequestAutoMerge|--auto-merge' \
    "$REPO_ROOT/scripts" "$REPO_ROOT/skills" "$REPO_ROOT/.github" \
    "$REPO_ROOT/templates" "$REPO_ROOT/config" "$REPO_ROOT/hooks" 2>/dev/null \
    | grep -vE ':[0-9]+:[[:space:]]*#' \
    | grep -vF "${policy_exclude_args[@]}" \
    || true
)"
if [ -z "$merge_hits" ]; then
  pass "C1.4 no merge invocation of the release PR on any shipped surface"
else
  fail "C1.4 found a merge invocation:"
  printf '%s\n' "$merge_hits" >&2
fi

# Each excluded file must actually DENY merging, not allow it: prove the
# exclusion is safe rather than assume it.
for POLICY_FILE in $POLICY_FILES; do
  if grep -qE '"deny"' "$REPO_ROOT/$POLICY_FILE" 2>/dev/null \
    && grep -qE 'Bash\(gh pr merge' "$REPO_ROOT/$POLICY_FILE" 2>/dev/null; then
    pass "C1.4 $POLICY_FILE denies gh pr merge (exclusion is a ban, not an invocation)"
  else
    fail "C1.4 $POLICY_FILE no longer denies gh pr merge — re-verify the exclusion"
  fi
done

# The release workflow and template must not merge (strict, zero tolerance).
for wf in "$WORKFLOW" "$TEMPLATE_WORKFLOW"; do
  label="${wf#"$REPO_ROOT"/}"
  if grep -qiE 'gh pr merge|merge_pull_request|auto-merge|automerge' "$wf"; then
    fail "C1.4 $label references a merge"
  else
    pass "C1.4 $label references no merge"
  fi
done

# --- REQ-F1.1: release-PR body carries merge-then-publish instructions --------
for cfg in "$CONFIG" "$TEMPLATE_CONFIG"; do
  label="${cfg#"$REPO_ROOT"/}"
  header="$(jq -r '.["pull-request-header"] // ""' "$cfg" 2>/dev/null)"
  if printf '%s' "$header" | grep -qi 'merg' \
    && printf '%s' "$header" | grep -qi 'release-publish.sh'; then
    pass "C1.4/F1.1 $label PR body states merge-approves + names the publish command"
  else
    fail "C1.4/F1.1 $label PR body missing merge-then-publish instructions"
  fi
done

# --- REQ-G1.3: templates are opt-in and never auto-land ----------------------
if [ -f "$TEMPLATE_WORKFLOW" ] && grep -q "$SENTINEL" "$TEMPLATE_WORKFLOW"; then
  pass "G1.3 template workflow lives under templates/ and carries the sentinel"
else
  fail "G1.3 template workflow missing or lacks the '$SENTINEL' sentinel"
fi

# No file in the active-workflow path may carry the template sentinel: a
# template must never auto-land where GitHub would run it.
if grep -rl "$SENTINEL" "$REPO_ROOT/.github/workflows" >/dev/null 2>&1; then
  fail "G1.3 a '$SENTINEL' file is inside .github/workflows (would auto-run)"
else
  pass "G1.3 no template sentinel inside .github/workflows"
fi

# Conversely, planwright's own active workflow must NOT be marked a template.
if grep -q "$SENTINEL" "$WORKFLOW"; then
  fail "G1.3 the live release workflow is marked as a template"
else
  pass "G1.3 the live release workflow is not marked as a template"
fi

# --- REQ-H1.1: the untagged-window guard on the proposal job ------------------
# obs:fd6c2f4f: the workflow_run trigger fires on `ci` completing on main, which
# is exactly the window where the version PR has merged but the signed tag does
# not exist yet — so every release passes through it, and release-please
# regenerates from bootstrapSha rather than failing loudly. The guard closes the
# trigger; these cases keep it closed.

# The step id the proposal step's `if:` reads. Named once so the assertions
# below and the workflow stay pinned to the same wiring.
GUARD_STEP_ID="window-check"

guard_line="$(grep -nE 'release-window-check\.sh' "$WORKFLOW" | head -1 | cut -d: -f1)"
proposal_line="$(grep -nE 'uses:[[:space:]]*googleapis/release-please-action@' "$WORKFLOW" \
  | head -1 | cut -d: -f1)"

if [ -n "$guard_line" ]; then
  pass "H1.1 the proposal workflow invokes scripts/release-window-check.sh"
else
  fail "H1.1 the proposal workflow has no release-window-check.sh guard"
fi

# The guard judges main's state, not the checkout's working tree: --ref
# origin/main is the same base-reading release-window.yml uses.
if grep -qE 'release-window-check\.sh[[:space:]]+--ref[[:space:]]+origin/main' "$WORKFLOW"; then
  pass "H1.1 the guard judges origin/main (--ref), not the working tree"
else
  fail "H1.1 the guard does not pass --ref origin/main"
fi

# Ordering: a guard that ran after the proposal step would gate nothing.
if [ -n "$guard_line" ] && [ -n "$proposal_line" ] && [ "$guard_line" -lt "$proposal_line" ]; then
  pass "H1.1 the guard precedes the release-please proposal step"
else
  fail "H1.1 the guard does not precede the release-please proposal step"
fi

# The proposal step must actually consume the guard's verdict, in the
# fail-closed direction: `== 'false'` runs only on a proven-closed window, so an
# unset or unexpected output skips the proposal rather than proposing anyway.
if grep -qE "if:[^#]*steps\.${GUARD_STEP_ID}\.outputs\.open[[:space:]]*==[[:space:]]*'false'" \
  "$WORKFLOW"; then
  pass "H1.1 the proposal step runs only when the guard proved the window closed"
else
  fail "H1.1 the proposal step is not gated on steps.${GUARD_STEP_ID}.outputs.open == 'false'"
fi

# --- REQ-H1.1: the guard's prerequisites (both fail SILENTLY if missed) -------
# rl_latest_release_tag reads local `git tag -l`, so a tagless checkout reports
# "no release tags yet, window open" and skips the job forever, silently.
if grep -qE 'uses:[[:space:]]*actions/checkout@[0-9a-f]{40}([[:space:]]|$)' "$WORKFLOW"; then
  pass "H1.1 the proposal workflow checks out the repo (actions/checkout, SHA-pinned)"
else
  fail "H1.1 the proposal workflow has no SHA-pinned actions/checkout"
fi

if grep -qE '^[[:space:]]*fetch-depth:[[:space:]]*0[[:space:]]*$' "$WORKFLOW"; then
  pass "H1.1 the checkout brings full history (fetch-depth: 0)"
else
  fail "H1.1 the checkout does not set fetch-depth: 0"
fi

# actions/checkout configures a narrow fetch refspec, so the explicit refspec is
# required to populate refs/remotes/origin/main and the release tags.
if grep -qE 'git fetch --force --tags origin \+refs/heads/main:refs/remotes/origin/main' \
  "$WORKFLOW"; then
  pass "H1.1 the checkout explicitly fetches the tags and origin/main"
else
  fail "H1.1 the checkout does not explicitly fetch --tags and origin/main"
fi

# obs:131af768: this job holds contents: write and pull-requests: write, and its
# head_branch == 'main' filter is satisfiable by a fork PR whose head branch is
# literally named `main`. guard-coverage D-6 accepted that residual BECAUSE the
# job checked out no PR code; adding a checkout only keeps that acceptance true
# if the checkout resolves the repository's own default branch.
if grep -qE "ref:[[:space:]]*\\\$\{\{[[:space:]]*github\.event\.repository\.default_branch[[:space:]]*\}\}" \
  "$WORKFLOW"; then
  pass "H1.1 the checkout pins the repository's own default branch"
else
  fail "H1.1 the checkout does not pin github.event.repository.default_branch"
fi

# head_sha is never a legitimate ref in this workflow: it is the triggering
# run's head, which a fork PR controls.
# -H so the `path:line:` prefix matches the whole-line-comment filter its
# siblings above use; a bare `grep -n` emits `line:` and the filter never fires.
if grep -nHE 'head_sha' "$WORKFLOW" | grep -vE ':[0-9]+:[[:space:]]*#' | grep -q .; then
  fail "H1.1 the workflow references workflow_run head_sha outside a comment"
else
  pass "H1.1 the workflow never references the triggering run's head_sha"
fi

# Nor may any checkout input resolve a workflow_run-carried ref by another name.
if grep -nE '^[[:space:]]*ref:' "$WORKFLOW" | grep -qE 'workflow_run'; then
  fail "H1.1 a checkout ref: resolves a workflow_run-carried ref"
else
  pass "H1.1 no checkout ref: resolves a workflow_run-carried ref"
fi

# --- REQ-H1.1: the tri-state split, exercised rather than grepped ------------
# The defect this pins is reading the script's exit as merely non-zero: 1 is an
# open window (a normal pending publish, so SKIP) and 2 is fail-closed
# could-not-determine (so FAIL). Folding 2 into the skip would launder an
# unreadable state into a green no-op — the fail-open shape REQ-A1.3 exists to
# remove. So run the shipped guard body against a stub comparator.
#
# Extract the guard step's `run:` block scalar and dedent it. Same strict
# block-style subset check-workflow-posture.sh models: the body is every line
# indented deeper than the block's first line.
guard_script="$(
  awk -v id="$GUARD_STEP_ID" '
    $0 ~ ("^[[:space:]]*-[[:space:]]+id:[[:space:]]*" id "[[:space:]]*$") { instep = 1; next }
    instep && /^[[:space:]]*run:[[:space:]]*\|[[:space:]]*$/ { inrun = 1; next }
    inrun {
      if ($0 ~ /^[[:space:]]*$/) { print ""; next }
      match($0, /^[[:space:]]*/)
      if (base == 0) base = RLENGTH
      if (RLENGTH < base) exit
      print substr($0, base + 1)
    }
  ' "$WORKFLOW"
)"

if [ -n "$guard_script" ]; then
  pass "H1.1 the guard step '$GUARD_STEP_ID' carries an extractable run: body"
else
  fail "H1.1 no run: body found for guard step '$GUARD_STEP_ID' (cannot exercise the tri-state)"
fi

# Run the extracted body with a stub release-window-check.sh exiting <code>.
# Echoes: "<guard exit status>|<the open= value it recorded, or empty>".
run_guard_with_exit() {
  _rgwe_code="$1"
  _rgwe_dir="$(mktemp -d "${TMPDIR:-/tmp}/rp-guard.XXXXXX")" || return 1
  mkdir -p "$_rgwe_dir/scripts"
  printf '#!/bin/bash\nexit %s\n' "$_rgwe_code" >"$_rgwe_dir/scripts/release-window-check.sh"
  chmod +x "$_rgwe_dir/scripts/release-window-check.sh"
  printf '%s\n' "$guard_script" >"$_rgwe_dir/guard.sh"
  : >"$_rgwe_dir/github_output"
  # GitHub runs a `run:` block under `bash -e -o pipefail`; match it, or a guard
  # that only works without -e would pass here and fail on the runner.
  (
    cd "$_rgwe_dir" || exit 99
    GITHUB_OUTPUT="$_rgwe_dir/github_output" bash -eo pipefail guard.sh >/dev/null 2>&1
  )
  _rgwe_status=$?
  _rgwe_open="$(grep -E '^open=' "$_rgwe_dir/github_output" 2>/dev/null | tail -1)"
  rm -rf "$_rgwe_dir"
  printf '%s|%s' "$_rgwe_status" "${_rgwe_open#open=}"
}

if [ -n "$guard_script" ]; then
  # Exit 0 — no open window: the guard succeeds and clears the proposal step.
  got="$(run_guard_with_exit 0)"
  if [ "$got" = "0|false" ]; then
    pass "H1.1 window check exit 0 → guard succeeds, open=false (proposal runs)"
  else
    fail "H1.1 window check exit 0 → expected '0|false', got '$got'"
  fi

  # Exit 1 — window open: a pending publish is a normal state, so the job SKIPS
  # the proposal rather than going red.
  got="$(run_guard_with_exit 1)"
  if [ "$got" = "0|true" ]; then
    pass "H1.1 window check exit 1 → guard succeeds, open=true (proposal skipped, job green)"
  else
    fail "H1.1 window check exit 1 → expected '0|true', got '$got'"
  fi

  # Exit 2 — could not determine: FAIL the job. This is the assertion that fails
  # if someone folds 2 into the skip.
  got="$(run_guard_with_exit 2)"
  case "$got" in
    0\|*) fail "H1.1 window check exit 2 → guard succeeded ('$got'); an unreadable state must fail the job" ;;
    *\|true | *\|false) fail "H1.1 window check exit 2 → guard recorded an open= verdict ('$got'); it determined nothing" ;;
    *) pass "H1.1 window check exit 2 → guard fails the job (fail-closed, not skipped)" ;;
  esac

  # An unmodelled status is fail-closed too, never silently a skip.
  got="$(run_guard_with_exit 3)"
  case "$got" in
    0\|*) fail "H1.1 window check exit 3 (unmodelled) → guard succeeded ('$got'); must fail closed" ;;
    *) pass "H1.1 window check exit 3 (unmodelled) → guard fails the job (fail-closed)" ;;
  esac
fi

# --- JSON validity for every shipped config/manifest -------------------------
for j in "$CONFIG" "$MANIFEST" "$TEMPLATE_CONFIG" "$TEMPLATE_MANIFEST"; do
  label="${j#"$REPO_ROOT"/}"
  if jq . "$j" >/dev/null 2>&1; then
    pass "valid JSON: $label"
  else
    fail "invalid JSON: $label"
  fi
done

if [ "$failures" -eq 0 ]; then
  echo "All release-please tests passed."
  exit 0
fi
echo "$failures test(s) failed." >&2
exit 1
