#!/bin/bash
# The tower deny-to-act map (tower-placement REQ-D1.3): every entry of
# config/tower-settings.json's deny list has a row in
# tests/fixtures/tower-deny-acts.tsv naming the policy-guard act that covers
# it, the check fails on a fixture profile with an unmapped entry, and the
# rows for the merge, flip, rewrite, ref-surgery, and GitHub MCP acts are
# refused by scripts/tower-session.sh in a marked session whose payload
# carries no profile (REQ-C1.1). The worktree and push rows run in their own
# files, for the per-file time ceiling.
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
unset CDPATH
# shellcheck source=tests/lib/tower-floor-harness.sh
. "$(cd "$(dirname "$0")" && pwd)/lib/tower-floor-harness.sh"

echo "# the map covers the shipped deny list, and the check fails on an unmapped entry"
if out=$(map_check "$PROFILE"); then
  pass "every shipped deny entry maps to an act, and every map row names a shipped entry (REQ-D1.3)"
else
  fail "the deny-to-act map and the shipped deny list disagree: $out"
fi
jq '.permissions.deny += ["Bash(git symbolic-ref:*)"]' "$PROFILE" >"$SANDBOX/unmapped.json"
if out=$(map_check "$SANDBOX/unmapped.json"); then
  fail "the map check passed a profile with an unmapped deny entry (REQ-D1.3)"
else
  case $out in
    *'unmapped deny entry: Bash(git symbolic-ref:*)'*) pass "the map check fails on a deliberately unmapped entry (REQ-D1.3)" ;;
    *) fail "the map check failed for another reason: $out" ;;
  esac
fi
if out=$(act_check "$MAP"); then
  pass "every map row names an act a floor suite runs, and every act has an entry row"
else
  fail "the deny-to-act map names an act no suite runs, or leaves one without a row: $out"
fi
awk -F'\t' -v OFS='\t' '$1 == "entry" && $3 == "pr-merge" { $3 = "pr-merg" } { print }' "$MAP" >"$SANDBOX/misspelled.tsv"
if out=$(act_check "$SANDBOX/misspelled.tsv"); then
  fail "the act check passed a map with a misspelled act"
else
  case $out in
    *'row names an act no suite runs: pr-merg'*) pass "the act check fails on a misspelled act" ;;
    *) fail "the act check failed for another reason: $out" ;;
  esac
fi
if jq -e '.permissions.deny | index("mcp__github__update_pull_request_branch") != null' "$PROFILE" >/dev/null; then
  pass "the profile denies mcp__github__update_pull_request_branch by name (REQ-C1.1)"
else
  fail "the profile does not deny mcp__github__update_pull_request_branch by name (REQ-C1.1)"
fi

echo "# each entry's sample: matched by its entry, refused in a marked session without the profile"
entry_rows '^(pr-merge|flip|base-merge|rewrite|ref-surgery|mcp-write)$'

no_gh_calls
finish
