#!/bin/bash
# Tests for the release-please PR-only configuration and the opt-in adopter
# template (Task 5, specs/autopilot-reflex).
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
plugin_version="$(jq -r '.version' "$PLUGIN" 2>/dev/null)"
manifest_version="$(jq -r '.["."]' "$MANIFEST" 2>/dev/null)"
if [ -n "$plugin_version" ] && [ "$plugin_version" = "$manifest_version" ]; then
  pass "C1.2 manifest baseline ($manifest_version) matches plugin.json ($plugin_version)"
else
  fail "C1.2 manifest baseline '$manifest_version' != plugin.json '$plugin_version'"
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
  # No direct tagging / Release creation in the workflow itself.
  if grep -nE '(^|[^#])(git tag|gh release create|gh api[^#]*releases)' "$wf" \
    | grep -vE '#' >/dev/null 2>&1; then
    fail "C1.3 $label contains a direct tag/Release-creation command"
  else
    pass "C1.3 $label contains no direct tag/Release-creation command"
  fi
done

# --- REQ-C1.4: merge is the human's — no merge INVOCATION on any surface ------
# Scan shipped executable/prose surfaces for a merge invocation of the release
# PR: the gh CLI merge, the REST/GraphQL merge APIs, and auto-merge. Comment
# lines and the worker-settings deny-rule token (which BANS merging, the
# opposite of a violation) are excluded — they are not invocations.
merge_hits="$(
  grep -rnE 'gh pr merge|pulls/[^ ]*/merge|mergePullRequest|enablePullRequestAutoMerge|--auto-merge|gh pr merge --auto' \
    "$REPO_ROOT/scripts" "$REPO_ROOT/skills" "$REPO_ROOT/.github" \
    "$REPO_ROOT/templates" "$REPO_ROOT/config" "$REPO_ROOT/hooks" 2>/dev/null \
    | grep -vE ':[0-9]+:[[:space:]]*#' \
    | grep -vE 'Bash\(gh pr merge' \
    || true
)"
if [ -z "$merge_hits" ]; then
  pass "C1.4 no merge invocation of the release PR on any shipped surface"
else
  fail "C1.4 found a merge invocation:"
  printf '%s\n' "$merge_hits" >&2
fi

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
