#!/bin/bash
# Tests for REQ-D1.1 / D-7 (worker-permission-ergonomics): the three dispatching
# skills — /execute-task, /orchestrate, /spec-kickoff — resolve the
# plugin/planwright root once per invocation and invoke plugin scripts by a
# resolved literal absolute path, never through an unexpanded shell variable.
#
# The motivation (obs:344dd129, brief §2): Claude Code's static allowlist matches
# the *literal* command token, never its expansion, and offers no persistent-allow
# for a "$VAR/scripts/x.sh" invocation — the commonest shape the dispatching skills
# issue. When jq is absent the auto-approve hook (Task 1) defers everything, so on
# that degraded path a $VAR-path script call floods a dispatched worker with a
# prompt per call. Resolving the root to a literal absolute path up front makes the
# invocation statically analyzable (persistent-allow-able / literal-path-allow
# matchable), closing the flood at its root independent of the hook.
#
# Like its /execute-task status-gate sibling this is a skill-prose change: the
# invocation convention is procedure the agent reads, not a script, so the [test]
# half of REQ-D1.1's verification path is a structural guard over the three
# SKILL.md files (same shape as tests/test-execute-task-status-gate.sh). The
# [manual] half (a dispatched worker confirms the invocations are now statically
# analyzable with the hook disabled) is exercised by the operator at execution.
#
# The full convention lives in doctrine/plugin-script-invocation.md (externalized
# to keep the three at-ceiling skills under their instruction-budget floors); each
# skill carries a labeled pointer to it. So this guard checks two surfaces:
#
# Per skill (execute-task, orchestrate, spec-kickoff):
#   - the labeled convention pointer is present, citing REQ-D1.1 and D-7;
#   - the "resolved literal absolute path" directive is stated (REQ-D1.1's
#     positive call-site property);
#   - the pointer references doctrine/plugin-script-invocation.md;
#   - NO "$VAR/scripts/x.sh" invocation shape remains: no unexpanded
#     $CLAUDE_PLUGIN_ROOT / $PLANWRIGHT_ROOT immediately followed by /scripts/
#     or /tests/ (the flooding shape the requirement forbids). A bare mention of
#     the variable *names* (the resolution chain) is allowed; only the
#     var-followed-by-/scripts/ invocation shape is forbidden.
#
# The doctrine doc:
#   - exists and states the full convention: "once per invocation" resolution to
#     a "resolved literal absolute path";
#   - cites REQ-D1.1 and D-7.
#
# Runs standalone: ./tests/test-skill-literal-path.sh
set -u
# Pin the C locale so grep character classes do not vary by host collation.
LC_ALL=C
export LC_ALL
unset CDPATH

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
doc="$REPO_ROOT/doctrine/plugin-script-invocation.md"

failures=0

fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}

ok() {
  echo "ok: $1"
}

# The three dispatching skills the requirement names.
skills="execute-task orchestrate spec-kickoff"

for name in $skills; do
  skill="$REPO_ROOT/skills/$name/SKILL.md"

  if [ ! -f "$skill" ]; then
    fail "$name SKILL.md missing at $skill"
    continue
  fi

  # The convention pointer is labeled and cites its governing requirement and
  # decision. Binding to the label + citation together (rather than a file-wide
  # REQ-D1.1 / D-7 grep) is deliberate: both IDs are overloaded in each skill's
  # own manifest, so a bare file-wide match would pass whether or not the
  # convention exists. The label pins the citation to the convention.
  if grep -qE 'Invoking plugin scripts \(REQ-D1\.1, D-7\)' "$skill"; then
    ok "$name: convention pointer labeled and cites REQ-D1.1 and D-7"
  else
    fail "$name: convention pointer 'Invoking plugin scripts (REQ-D1.1, D-7)' missing"
  fi

  # REQ-D1.1's positive call-site property: invocations use a resolved literal
  # path. Bind to the operative phrase so an inverted rewording cannot pass; it
  # may wrap across a line, so flatten newlines first.
  if tr '\n' ' ' <"$skill" | grep -qE 'resolved literal absolute path'; then
    ok "$name: states the resolved-literal-absolute-path directive"
  else
    fail "$name: 'resolved literal absolute path' directive missing"
  fi

  # The pointer routes to the doctrine doc that carries the full convention.
  if grep -qE 'doctrine/plugin-script-invocation\.md' "$skill"; then
    ok "$name: pointer references doctrine/plugin-script-invocation.md"
  else
    fail "$name: pointer does not reference doctrine/plugin-script-invocation.md"
  fi

  # Negative / regression fence: NO "$VAR/scripts/x.sh" (or /tests/) invocation
  # shape. The forbidden shape is an unexpanded $CLAUDE_PLUGIN_ROOT or
  # $PLANWRIGHT_ROOT (optionally braced) immediately followed by /scripts/ or
  # /tests/. A bare reference to the variable names (the resolution chain) does
  # not match, so the resolution prose stays legal.
  if grep -nE '\$\{?(CLAUDE_PLUGIN_ROOT|PLANWRIGHT_ROOT)\}?/(scripts|tests)/' "$skill"; then
    fail "$name: unexpanded \$VAR/scripts/ invocation shape present (REQ-D1.1 forbids it)"
  else
    ok "$name: no unexpanded \$VAR/scripts/ invocation shape remains"
  fi
done

# The doctrine doc carries the full convention.
if [ ! -f "$doc" ]; then
  fail "doctrine/plugin-script-invocation.md missing at $doc"
else
  flat="$(tr '\n' ' ' <"$doc")"
  if printf '%s' "$flat" | grep -qE 'once per invocation' \
    && printf '%s' "$flat" | grep -qE 'resolved literal absolute path|resolved literal\n?\s*absolute path'; then
    ok "doctrine doc: states 'once per invocation' resolution to a literal absolute path"
  else
    fail "doctrine doc: full convention ('once per invocation' + 'resolved literal absolute path') missing"
  fi
  if grep -qE 'REQ-D1\.1' "$doc" && grep -qE 'D-7' "$doc"; then
    ok "doctrine doc: cites REQ-D1.1 and D-7"
  else
    fail "doctrine doc: does not cite both REQ-D1.1 and D-7"
  fi
fi

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all skill literal-path tests passed"
