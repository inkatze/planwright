#!/bin/bash
# Tests for scripts/resolve-steps.sh — the custom-steps point resolver
# (custom-steps Task 2; REQ-A1.1, REQ-A1.3, REQ-A1.4, REQ-B1.1–B1.4,
# REQ-B1.6, REQ-C1.1–C1.6, REQ-C1.8, REQ-D1.8, REQ-D1.9, REQ-G1.1, REQ-H1.3;
# D-4, D-5, D-6, D-10, D-17, D-19).
#
# Every fixture lives under a temporary home: a fixture core root (defaults,
# the steps seed, a skills tree, a doctrine dir), the adopter root, a repo
# root holding the repo-tracked and machine-local layers, a Claude dir holding
# the user command and skill directories and a fixture installed-plugin
# registry, and a bin dir on PATH for command targets. The one case that reads
# the shipped files verbatim is the Done-when check that the shipped defaults
# resolve `convergence` to the single `polish` step.
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-resolve-steps.sh
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$here/.." && pwd)
RS="$repo_root/scripts/resolve-steps.sh"
TAB=$(printf '\t')

failures=0
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}
ok() { echo "ok: $1"; }
# verdict <ok-message> <fail-message>: judged on the exit status of the
# command that precedes the call.
verdict() {
  if [ $? -eq 0 ]; then
    ok "$1"
  else
    fail "$2"
  fi
}

[ -x "$RS" ] || {
  echo "FAIL: scripts/resolve-steps.sh missing or not executable" >&2
  exit 1
}

command -v jq >/dev/null 2>&1 || {
  echo "FAIL: jq is required (the installed-plugin registry lookups read JSON)" >&2
  exit 1
}

tmp="$(cd "$(mktemp -d)" && pwd -P)" || exit 1
trap 'rm -rf "$tmp"' EXIT

WIRED="pre-implementation pre-ci convergence pre-pr post-pr pre-ready-flip pre-spec-ready-flip"
UNWIRED="spec-drafted kickoff-signed-off unit-selected pre-dispatch post-dispatch unit-halted post-merge orchestrator-idle"

# --- Fixture layout ----------------------------------------------------------
core="$tmp/core"
adopter="$tmp/adopter"
repo="$tmp/repo"
claude="$tmp/claude"
bin="$tmp/bin"
mkdir -p "$core/config" "$core/skills/polish" "$core/skills/self-review" \
  "$core/skills/execute-task" "$core/doctrine" \
  "$adopter/catalogs" "$repo/.claude/catalogs" "$repo/.claude/catalogs.local" \
  "$repo/.claude/commands" "$repo/.claude/skills" \
  "$claude/commands" "$claude/skills" "$claude/plugins" "$bin" "$tmp/home"
printf 'argument-hint: "[--nested]"\n' >"$core/skills/polish/SKILL.md"
printf 'argument-hint: "[--nested]"\n' >"$core/skills/self-review/SKILL.md"
printf 'name: execute-task\n' >"$core/skills/execute-task/SKILL.md"
cp "$repo_root/config/steps.yaml" "$core/config/steps.yaml"

# The fixture core defaults: every point key, convergence carrying polish.
write_core_defaults() {
  {
    printf 'dispatch_isolation: %s\n' "${1:-per-step}"
    for wp in $WIRED $UNWIRED; do
      k="steps_${wp//-/_}"
      if [ "$wp" = convergence ]; then
        printf '%s: [polish]\n' "$k"
      else
        printf '%s: []\n' "$k"
      fi
    done
  } >"$core/config/defaults.yml"
}
write_core_defaults

adopter_cfg="$adopter/planwright.yml"
tracked_cfg="$repo/.claude/planwright.yml"
mlocal_cfg="$repo/.claude/planwright.local.yml"
adopter_cat="$adopter/catalogs/steps.yaml"
tracked_cat="$repo/.claude/catalogs/steps.yaml"
mlocal_cat="$repo/.claude/catalogs.local/steps.yaml"
registry="$claude/plugins/installed_plugins.json"

reset_layers() {
  rm -f "$adopter_cfg" "$tracked_cfg" "$mlocal_cfg" \
    "$adopter_cat" "$tracked_cat" "$mlocal_cat" "$registry"
  rm -rf "$claude/commands" "$claude/skills" "$repo/.claude/commands" "$repo/.claude/skills"
  mkdir -p "$claude/commands" "$claude/skills" "$repo/.claude/commands" "$repo/.claude/skills"
  write_core_defaults
}

# cat_entry <file> <id> <field: value>... — append one catalog entry, creating
# the `steps:` section header on first use.
cat_entry() {
  f="$1"
  id="$2"
  shift 2
  [ -s "$f" ] || printf 'steps:\n' >"$f"
  printf '  - id: %s\n' "$id" >>"$f"
  for kv in "$@"; do printf '    %s\n' "$kv" >>"$f"; done
}

# run <args...>: the resolver under the fixture environment, the host's own
# PLANWRIGHT_STEP_* exports cleared so the suite is hermetic even when it
# runs inside a planwright step (the context cases set them through ctx_run).
STEP_UNSETS="-u PLANWRIGHT_STEP_SPEC -u PLANWRIGHT_STEP_TASK_IDS -u PLANWRIGHT_STEP_UNIT_KIND -u PLANWRIGHT_STEP_BRANCH -u PLANWRIGHT_STEP_BASE_BRANCH -u PLANWRIGHT_STEP_WORKTREE -u PLANWRIGHT_STEP_PR_NUMBER -u PLANWRIGHT_STEP_POINT -u PLANWRIGHT_STEP_ID -u PLANWRIGHT_STEP_PREV_RECORD"
# run [VAR=value ...] <args...>: a leading VAR=value sets a variable the
# hermetic environment would otherwise clear (the jq override, for one).
run() {
  overrides=()
  while [ $# -gt 0 ]; do
    case "$1" in
      [A-Z_]*=*)
        overrides+=("$1")
        shift
        ;;
      *) break ;;
    esac
  done
  # shellcheck disable=SC2086 # the unset flags are meant to word-split
  env $STEP_UNSETS -u CLAUDE_PLUGIN_ROOT -u CLAUDE_PLUGIN_DATA -u PLANWRIGHT_SKILLS_ROOT \
    -u PLANWRIGHT_JQ ${overrides[@]+"${overrides[@]}"} \
    PLANWRIGHT_ROOT="$core" \
    PLANWRIGHT_CONFIG_DEFAULTS="$core/config/defaults.yml" \
    PLANWRIGHT_ADOPTER_OVERLAY="$adopter" \
    PLANWRIGHT_REPO_ROOT="$repo" \
    PLANWRIGHT_LOCAL_CONFIG="" \
    CLAUDE_DIR="$claude" HOME="$tmp/home" PATH="$bin:$PATH" \
    /bin/bash "$RS" "$@"
}
# out / err / code: run once and capture all three (stdout, stderr, exit).
capture() {
  OUT=$(run "$@" 2>"$tmp/err")
  RC=$?
  ERR=$(<"$tmp/err")
}
first_line() { printf '%s\n' "$1" | head -1; }

# =============================================================================
# 1. Shipped defaults (Done-when): convergence resolves to the single polish
#    step as `run`; every other named point prints nothing with exit 0.
# =============================================================================
reset_layers
capture convergence --unattended
[ "$RC" = 0 ] && [ "$OUT" = "run${TAB}polish" ]
verdict "REQ-B1.3: with no overlay convergence resolves to 'run polish' (exit 0)" "REQ-B1.3: convergence with no overlay: rc=$RC out='$OUT' err='$ERR'"
for p in $WIRED $UNWIRED; do
  [ "$p" = convergence ] && continue
  capture "$p" --unattended
  [ "$RC" = 0 ] && [ -z "$OUT" ] \
    || fail "REQ-B1.3: point '$p' with no overlay: rc=$RC out='$OUT' err='$ERR'"
done
ok "REQ-B1.3/REQ-A1.1: every other named point resolves to nothing with exit 0"

# The same against the SHIPPED config and catalog (the repository's own files,
# no overlay layers), so the seed and the defaults are what this test pins.
run_shipped() {
  # shellcheck disable=SC2086 # the unset flags are meant to word-split
  env $STEP_UNSETS -u CLAUDE_PLUGIN_ROOT -u CLAUDE_PLUGIN_DATA -u PLANWRIGHT_SKILLS_ROOT \
    PLANWRIGHT_ROOT="$repo_root" PLANWRIGHT_CONFIG_DEFAULTS="$repo_root/config/defaults.yml" \
    PLANWRIGHT_ADOPTER_OVERLAY="$tmp/no-adopter" PLANWRIGHT_REPO_ROOT="$tmp/no-repo" \
    PLANWRIGHT_LOCAL_CONFIG="" CLAUDE_DIR="$claude" HOME="$tmp/home" \
    /bin/bash "$RS" "$@"
}
ship_out=$(run_shipped convergence --unattended 2>/dev/null)
ship_rc=$?
[ "$ship_rc" = 0 ] && [ "$ship_out" = "run${TAB}polish" ]
verdict "the shipped config/defaults.yml and config/steps.yaml resolve convergence to polish" "shipped files: convergence rc=$ship_rc out='$ship_out'"
# The fixture sweep above already exercises every point; against the shipped
# files it suffices that every other key ships `[]` and one such point runs.
for p in $WIRED $UNWIRED; do
  [ "$p" = convergence ] && continue
  grep -qx "steps_${p//-/_}: \[\]" "$repo_root/config/defaults.yml" \
    || fail "shipped defaults: steps_${p//-/_} is not an empty list"
done
ship_out=$(run_shipped orchestrator-idle --unattended 2>/dev/null)
ship_rc=$?
[ "$ship_rc" = 0 ] && [ -z "$ship_out" ]
verdict "the shipped files leave every other named point empty" "shipped files: orchestrator-idle rc=$ship_rc out='$ship_out'"
# Every wired point resolves a non-empty list (so none is silently treated
# as unwired), the flip points included.
for p in $WIRED; do
  reset_layers
  printf 'steps_%s: [polish]\n' "${p//-/_}" >"$tracked_cfg"
  capture "$p" --unattended
  { [ "$RC" = 0 ] && [ "$OUT" = "run${TAB}polish" ] && ! printf '%s' "$ERR" | grep -q 'not wired'; } \
    || fail "REQ-A1.1/REQ-E1.3: wired point '$p' with a list: rc=$RC out='$OUT' err='$ERR'"
done
ok "REQ-A1.1/REQ-E1.3: every wired point, the flip points included, resolves a non-empty list"

# An unknown point name is a usage error before any path or key use.
capture no-such-point --unattended
[ "$RC" = 2 ]
verdict "REQ-A1.1: an unknown point name is refused (exit 2)" "unknown point: rc=$RC (want 2)"
capture 'pre-ci; rm' --unattended
[ "$RC" = 2 ]
verdict "a point name outside the charset is refused (exit 2)" "hostile point name: rc=$RC (want 2)"
capture "" convergence --unattended
[ "$RC" = 2 ]
verdict "an empty positional before the point is an extra argument (exit 2)" "empty positional: rc=$RC (want 2)"

# An explicit `[]` at any layer resolves to no steps without a malformed warning.
for cfg in "$adopter_cfg" "$tracked_cfg" "$mlocal_cfg"; do
  reset_layers
  printf 'steps_convergence: []\n' >"$cfg"
  capture convergence --unattended
  { [ "$RC" = 0 ] && [ -z "$OUT" ] && ! printf '%s' "$ERR" | grep -q malformed; } \
    || fail "explicit [] at $cfg: rc=$RC out='$OUT' err='$ERR'"
done
ok "REQ-B1.3: an explicit [] at any layer resolves to no steps and is not malformed"
# Only a flow list is a list: a bare scalar, an empty value, and an empty
# field between commas are malformed for their layer.
for bad in 'polish' '' '[polish,,self-review]' '[,polish]'; do
  reset_layers
  printf 'steps_pre_pr: %s\n' "$bad" >"$tracked_cfg"
  capture pre-pr --unattended
  [ "$RC" = 4 ] || fail "REQ-B1.3: list value '$bad' in repo-tracked: rc=$RC (want 4) err='$ERR'"
  reset_layers
  printf 'steps_pre_pr: %s\n' "$bad" >"$adopter_cfg"
  capture pre-pr --unattended
  { [ "$RC" = 0 ] && [ -z "$OUT" ] && printf '%s' "$ERR" | grep -q 'malformed'; } \
    || fail "REQ-B1.3: list value '$bad' in adopter: rc=$RC out='$OUT' err='$ERR'"
done
ok "REQ-B1.3: a value that is not an inline flow list is malformed for its layer"

# =============================================================================
# 2. Attendance and check-mode usage (REQ-C1.4, REQ-H1.3).
# =============================================================================
reset_layers
capture convergence
[ "$RC" = 2 ]
verdict "REQ-C1.4: neither attendance flag is a usage error (exit 2)" "no attendance flag: rc=$RC (want 2)"
capture convergence --attended --unattended
[ "$RC" = 2 ]
verdict "both attendance flags together is a usage error (exit 2)" "both attendance flags: rc=$RC (want 2)"
capture convergence --check --attended
[ "$RC" = 2 ] && printf '%s' "$ERR" | grep -q 'never waits'
verdict "--check refuses --attended as a usage error (check mode never waits on a human)" "--check --attended: rc=$RC err='$ERR' (want 2)"
capture convergence --preamble --attended
[ "$RC" = 2 ]
verdict "the render modes refuse an attendance flag" "--preamble --attended: rc=$RC (want 2)"
capture convergence --check --unattended
[ "$RC" = 0 ]
verdict "--check --unattended passes on the shipped defaults" "--check --unattended: rc=$RC err='$ERR'"
capture convergence --preamble --explain
[ "$RC" = 2 ]
verdict "--preamble combined with a resolution flag is a usage error" "--preamble --explain: rc=$RC (want 2)"

# =============================================================================
# 3. The steps catalog kind (REQ-B1.1): every layer contributes, supersede
#    replaces core's polish, and `supersede` is never an unknown field.
# =============================================================================
reset_layers
cat_entry "$adopter_cat" a-step "kind: prompt" "target: adopter prompt"
cat_entry "$tracked_cat" r-step "kind: prompt" "target: repo prompt"
cat_entry "$mlocal_cat" m-step "kind: prompt" "target: local prompt"
printf 'steps_pre_pr: [polish, a-step, r-step, m-step]\n' >"$mlocal_cfg"
capture pre-pr --unattended --explain
[ "$RC" = 0 ] || fail "REQ-B1.1: four-layer catalog: rc=$RC err='$ERR'"
[ "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')" = 4 ] \
  || fail "REQ-B1.1: expected four steps, got: $OUT"
printf '%s\n' "$OUT" | grep -q "^run${TAB}a-step${TAB}pre-pr${TAB}machine-local${TAB}adopter${TAB}" \
  || fail "REQ-B1.1/REQ-C1.2: adopter entry provenance missing: $OUT"
printf '%s\n' "$OUT" | grep -q "^run${TAB}r-step${TAB}pre-pr${TAB}machine-local${TAB}repo-tracked${TAB}" \
  || fail "REQ-B1.1/REQ-C1.2: repo-tracked entry provenance missing: $OUT"
printf '%s\n' "$OUT" | grep -q "^run${TAB}m-step${TAB}pre-pr${TAB}machine-local${TAB}machine-local${TAB}" \
  || fail "REQ-B1.1/REQ-C1.2: machine-local entry provenance missing: $OUT"
printf '%s\n' "$OUT" | grep -q "^run${TAB}polish${TAB}pre-pr${TAB}machine-local${TAB}core${TAB}" \
  || fail "REQ-B1.1/REQ-C1.2: core entry provenance missing: $OUT"
ok "REQ-B1.1: the merged catalog carries an entry from every layer, each with its layer"

reset_layers
cat_entry "$adopter_cat" polish "supersede: true" "kind: skill" "target: self-review" "args: --nested --fast"
capture convergence --unattended --explain
[ "$RC" = 0 ] || fail "REQ-B1.1: supersede: rc=$RC err='$ERR'"
printf '%s\n' "$OUT" | grep -q "^run${TAB}polish${TAB}convergence${TAB}core${TAB}adopter${TAB}self-review${TAB}" \
  || fail "REQ-B1.1: a supersede: true overlay entry did not replace core's polish: $OUT"
printf '%s' "$ERR" | grep -q 'unknown field' \
  && fail "REQ-B1.1: supersede reported as an unknown field: $ERR"
ok "REQ-B1.1: supersede: true replaces the core entry and is never an unknown field"

# =============================================================================
# 4. Entry fields and enums (REQ-B1.2), by layer (REQ-C1.5).
# =============================================================================
reset_layers
printf '#!/bin/sh\nexit 0\n' >"$bin/fixture-tool"
chmod +x "$bin/fixture-tool"
cat_entry "$tracked_cat" full "kind: command" "target: fixture-tool" "args: --a b" \
  "hosting: isolated" "on-failure: continue" "timeout: 30" "requires: fixture-tool"
printf 'steps_pre_ci: [full]\n' >"$tracked_cfg"
capture pre-ci --unattended --explain
[ "$RC" = 0 ] && printf '%s\n' "$OUT" | grep -q "^run${TAB}full${TAB}pre-ci${TAB}repo-tracked${TAB}repo-tracked${TAB}fixture-tool${TAB}isolated${TAB}command${TAB}--a b${TAB}continue${TAB}30${TAB}fixture-tool${TAB}"
verdict "REQ-B1.2: an entry with every field resolves and --explain carries each" "REQ-B1.2: full entry: rc=$RC out='$OUT' err='$ERR'"

# malformed_case <label> <field lines...>: the entry, declared in the
# repo-tracked layer, hard-fails (exit 4) naming the layer; declared in the
# adopter layer it warns, is skipped, and its id takes the matrix path
# (unattended adopter list -> skip).
malformed_case() {
  label="$1"
  shift
  reset_layers
  rm -f "$tracked_cat"
  cat_entry "$tracked_cat" bad-one "$@"
  printf 'steps_pre_ci: [bad-one]\n' >"$tracked_cfg"
  capture pre-ci --unattended
  if [ "$RC" = 4 ] && printf '%s' "$ERR" | grep -q 'repo-tracked'; then
    ok "REQ-B1.2/REQ-C1.5: $label is malformed in repo-tracked (exit 4, layer named)"
  else
    fail "REQ-B1.2: $label in repo-tracked: rc=$RC (want 4) err='$ERR'"
  fi
  reset_layers
  cat_entry "$adopter_cat" bad-one "$@"
  printf 'steps_pre_ci: [bad-one]\n' >"$adopter_cfg"
  capture pre-ci --unattended
  if [ "$RC" = 0 ] && [ "$OUT" = "skip${TAB}bad-one" ] && printf '%s' "$ERR" | grep 'malformed' | grep -q 'adopter'; then
    ok "REQ-B1.2/REQ-C1.5: $label in adopter warns, is skipped, and takes the matrix path"
  else
    fail "REQ-B1.2: $label in adopter: rc=$RC out='$OUT' err='$ERR'"
  fi
  capture pre-ci --check --unattended
  [ "$RC" = 1 ] || fail "REQ-H1.3: $label in adopter must fail check mode (rc=$RC)"
}
malformed_case "an unknown field" "kind: prompt" "target: p" "colour: red"
malformed_case "an unknown kind" "kind: ritual" "target: p"
malformed_case "an unknown hosting" "kind: prompt" "target: p" "hosting: sometimes"
malformed_case "an unknown on-failure" "kind: prompt" "target: p" "on-failure: shrug"
malformed_case "a non-integer timeout" "kind: command" "target: fixture-tool" "timeout: 5m"
malformed_case "a zero timeout" "kind: command" "target: fixture-tool" "timeout: 0"
malformed_case "a missing target" "kind: prompt"
malformed_case "a missing kind" "target: p"
malformed_case "a timeout on an in-session skill step" "kind: skill" "target: polish" "hosting: in-session" "timeout: 10"
malformed_case "a timeout on an in-session prompt step" "kind: prompt" "target: p" "hosting: in-session" "timeout: 10"
malformed_case "args on a prompt step" "kind: prompt" "target: p" "args: --x"
malformed_case "a duplicated field" "kind: prompt" "target: p" "target: q"
malformed_case "an indented id field" "kind: prompt" "target: p" "id: other"
malformed_case "an empty hosting" "kind: prompt" "target: p" "hosting:"
malformed_case "an empty on-failure" "kind: prompt" "target: p" "on-failure:"
malformed_case "an empty timeout" "kind: command" "target: fixture-tool" "timeout:"
malformed_case "an empty args" "kind: command" "target: fixture-tool" "args:"
malformed_case "an empty requires" "kind: prompt" "target: p" "requires:"
malformed_case "a block indicator as args" "kind: skill" "target: polish" "args: |"
malformed_case "an indented block indicator as target" "kind: prompt" "target: |2-"
# An id left with an edge blank once its quote pair is stripped: the catalog
# reader skips it as malformed, and the skip takes the by-layer policy.
reset_layers
printf 'steps:\n  - id: " foo"\n    kind: prompt\n    target: p\n' >"$tracked_cat"
printf 'steps_pre_ci: [polish]\n' >"$tracked_cfg"
capture pre-ci --unattended
[ "$RC" = 4 ] || fail "REQ-C1.5: a repo-tracked id with surrounding whitespace: rc=$RC (want 4) err='$ERR'"
reset_layers
printf 'steps:\n  - id: "polish "\n    kind: prompt\n    target: p\n  - id: " "\n    kind: prompt\n    target: q\n' >"$adopter_cat"
printf 'steps_pre_ci: [polish]\n' >"$adopter_cfg"
capture pre-ci --unattended
{ [ "$RC" = 0 ] && [ "$OUT" = "run${TAB}polish" ] && [ "$(printf '%s\n' "$ERR" | grep -c 'malformed')" = 2 ]; } \
  || fail "REQ-C1.5: adopter ids with surrounding whitespace should each drop: rc=$RC out='$OUT' err='$ERR'"
ok "REQ-C1.5: an id the reader kept with surrounding whitespace is malformed for its layer, never a broken install"
# A catalog with more than one section aligns the two views by id: the
# entry keeps its own fields and layer wherever the merged view groups it,
# and a name that could match two entries fails closed.
reset_layers
printf 'steps:\n  - id: filler\n    kind: prompt\n    target: hello\nother:\n  - id: extra\n    kind: prompt\n    target: from the other section\n' >"$adopter_cat"
cat_entry "$tracked_cat" deploy "kind: command" "target: fixture-tool" "args: team"
printf 'steps_pre_pr: [deploy, extra]\n' >"$tracked_cfg"
capture pre-pr --unattended --explain
{ [ "$RC" = 0 ] \
  && printf '%s\n' "$OUT" | grep -q "^run${TAB}deploy${TAB}pre-pr${TAB}repo-tracked${TAB}repo-tracked${TAB}fixture-tool${TAB}isolated${TAB}command${TAB}team${TAB}" \
  && printf '%s\n' "$OUT" | grep -q "^run${TAB}extra${TAB}pre-pr${TAB}repo-tracked${TAB}adopter${TAB}from the other section${TAB}"; } \
  || fail "multi-section catalog: entries must keep their own fields and layer: rc=$RC out='$OUT' err='$ERR'"
printf 'steps:\n  - id: filler\n    kind: prompt\n    target: hello\nother:\n  - id: ""deploy""\n    kind: command\n    target: fixture-tool\n    args: attacker\n' >"$adopter_cat"
printf 'steps_pre_pr: [deploy]\n' >"$tracked_cfg"
capture pre-pr --unattended --explain
{ [ "$RC" = 0 ] \
  && printf '%s\n' "$OUT" | grep -q "^run${TAB}deploy${TAB}pre-pr${TAB}repo-tracked${TAB}repo-tracked${TAB}fixture-tool${TAB}isolated${TAB}command${TAB}team${TAB}" \
  && ! printf '%s\n' "$OUT" | grep -q attacker \
  && printf '%s' "$ERR" | grep 'malformed' | grep -q 'adopter'; } \
  || fail "multi-section catalog: a quoted adopter id must never rebind a repo-tracked one: rc=$RC out='$OUT' err='$ERR'"
reset_layers
printf 'steps:\n  - id: filler\n    kind: prompt\n    target: hello\nother:\n  - id: " polish"\n    kind: prompt\n    target: hi\n' >"$adopter_cat"
capture convergence --unattended
{ [ "$RC" = 0 ] && [ "$OUT" = "run${TAB}polish" ] && printf '%s' "$ERR" | grep 'malformed' | grep -q 'adopter'; } \
  || fail "multi-section catalog: an adopter id with edge whitespace degrades, never a broken install: rc=$RC out='$OUT' err='$ERR'"
ok "REQ-C1.5: a multi-section catalog aligns the views by id, a quoted overlay id judged by its own layer"
# An indented line the catalog reader drops (a misindented or quoted key)
# takes the by-layer policy: the declaration is never lost silently.
reset_layers
printf 'steps:\n  - id: lint\n    kind: command\n    target: fixture-tool\n     timeout: 30\n' >"$tracked_cat"
printf 'steps_pre_ci: [lint]\n' >"$tracked_cfg"
capture pre-ci --unattended
[ "$RC" = 4 ] && printf '%s' "$ERR" | grep -q 'not a field'
verdict "REQ-C1.5: a misindented field in a repo-tracked entry hard-fails" "misindented repo-tracked field: rc=$RC err='$ERR'"
reset_layers
printf 'steps:\n  - id: lint\n    kind: command\n    target: fixture-tool\n    "hosting": in-session\n' >"$adopter_cat"
printf 'steps_pre_ci: [lint]\n' >"$adopter_cfg"
capture pre-ci --unattended
{ [ "$RC" = 0 ] && [ "$OUT" = "skip${TAB}lint" ] && printf '%s' "$ERR" | grep -q 'not a field'; }
verdict "REQ-C1.5: an adopter entry that lost a line is skipped, never run without it" "quoted adopter key: rc=$RC out='$OUT' err='$ERR'"
capture pre-ci --check --unattended
[ "$RC" = 1 ] && printf '%s' "$ERR" | grep -q 'not a field'
verdict "REQ-H1.3: a quoted key in an adopter entry is degraded with its warning and fails check mode" "quoted adopter key: rc=$RC err='$ERR'"
# A lost line on a duplicate the reader skips never damages the entry it
# duplicates.
reset_layers
printf 'steps:\n  - id: mine\n    kind: prompt\n    target: hi\n  - id: mine\n    kind: prompt\n      nested: x\n' >"$adopter_cat"
printf 'steps_pre_pr: [mine]\n' >"$adopter_cfg"
capture pre-pr --unattended
{ [ "$RC" = 0 ] && [ "$OUT" = "run${TAB}mine" ] && ! printf '%s' "$ERR" | grep -q 'not a field'; } \
  || fail "a lost line on a skipped duplicate must not drop the established entry: rc=$RC out='$OUT' err='$ERR'"
# An indented line before a section's first entry belongs to no entry: the
# entry it would have opened is never lost silently.
reset_layers
printf 'steps:\n  - kind: prompt\n    id: ghost\n    target: hi\n  - id: real\n    kind: prompt\n    target: hi\n' >"$tracked_cat"
printf 'steps_pre_ci: [real]\n' >"$tracked_cfg"
capture pre-ci --unattended
[ "$RC" = 4 ] && printf '%s' "$ERR" | grep -q 'outside any entry'
verdict "REQ-C1.5: a repo-tracked item that does not open with id hard-fails" "stray pre-entry line: rc=$RC err='$ERR'"
# An entry the catalog reader itself skipped with a warning (an unmarked
# duplicate of a core id, an empty id) takes the by-layer policy here.
reset_layers
cat_entry "$tracked_cat" polish "kind: skill" "target: self-review"
printf 'steps_convergence: [polish]\n' >"$tracked_cfg"
capture convergence --unattended
[ "$RC" = 4 ] && printf '%s' "$ERR" | grep -q 'skipped'
verdict "REQ-C1.5: a repo-tracked entry the reader skipped (an unmarked duplicate) exits 4" "reader-skipped repo-tracked entry: rc=$RC err='$ERR'"
reset_layers
cp "$core/config/steps.yaml" "$tmp/steps.bak"
printf '  - id:\n    kind: prompt\n    target: p\n' >>"$core/config/steps.yaml"
capture convergence --unattended
[ "$RC" = 5 ] && printf '%s' "$ERR" | grep -q '^resolve-catalog: steps: core '
verdict "REQ-C1.5: a core entry the reader skipped (an empty id) is a broken install, the reader's own warning replayed" "reader-skipped core entry: rc=$RC err='$ERR'"
cp "$tmp/steps.bak" "$core/config/steps.yaml"
reset_layers
cat_entry "$adopter_cat" polish "kind: skill" "target: self-review"
capture convergence --unattended
{ [ "$RC" = 0 ] && [ "$OUT" = "run${TAB}polish" ] \
  && [ "$(printf '%s\n' "$ERR" | grep -c '^resolve-catalog: steps: adopter entry "polish" duplicates')" = 1 ]; }
verdict "REQ-C1.5: an adopter entry the reader skipped only warns (once) and degrades" "reader-skipped adopter entry: rc=$RC out='$OUT' err='$ERR'"
# The catalog as a whole: a core seed that contributes nothing, or a point
# key with no core default, is a broken install whatever the overlays hold.
reset_layers
mv "$core/config/steps.yaml" "$tmp/steps.bak"
cat_entry "$tracked_cat" lint "kind: prompt" "target: p"
capture convergence --unattended
[ "$RC" = 5 ] && printf '%s' "$ERR" | grep -q 'core steps seed'
verdict "a missing core steps seed is a broken install even with an overlay catalog" "missing core seed: rc=$RC err='$ERR'"
mv "$tmp/steps.bak" "$core/config/steps.yaml"
reset_layers
sed -i.bak '/^steps_pre_ci:/d' "$core/config/defaults.yml"
rm -f "$core/config/defaults.yml.bak"
printf 'steps_pre_ci: [polish]\n' >"$tracked_cfg"
capture pre-ci --unattended
[ "$RC" = 5 ] && printf '%s' "$ERR" | grep -q 'no core default'
verdict "a point key with no core default is a broken install even when an overlay sets it" "missing core key: rc=$RC err='$ERR'"
malformed_case "a tab inside a value" "kind: prompt" "target: a${TAB}b"
malformed_case "a one-sided quote on a skill target" "kind: skill" 'target: "polish'
malformed_case "a blank before a key's colon" "kind: prompt" "target: p" "supersede : true"
malformed_case "a control byte inside a value" "kind: prompt" "target: a$(printf '\033')[31mb"
# A control byte in the id itself: still attributed to its layer, and the
# diagnostic carries no raw byte.
reset_layers
cat_entry "$tracked_cat" "bad$(printf '\033')[2J" "kind: prompt" "target: p"
printf 'steps_pre_ci: [polish]\n' >"$tracked_cfg"
capture pre-ci --unattended
{ [ "$RC" = 4 ] && ! printf '%s' "$ERR" | grep -q "$(printf '\033')"; } \
  || fail "REQ-B1.2: an escape byte in a repo-tracked id: rc=$RC err='$ERR'"
reset_layers
cat_entry "$adopter_cat" "bad${TAB}b" "kind: prompt" "target: p"
printf 'steps_pre_ci: [polish]\n' >"$adopter_cfg"
capture pre-ci --unattended
{ [ "$RC" = 0 ] && [ "$OUT" = "run${TAB}polish" ] && printf '%s' "$ERR" | grep -q 'malformed'; } \
  || fail "REQ-C1.5: a tab in an adopter id should drop that entry only: rc=$RC out='$OUT' err='$ERR'"
ok "REQ-B1.2: a control byte in an id is malformed for its layer and never reaches stderr raw"

# Bad ids: a leading digit, an uppercase letter, and the reserved phase id.
for bad in 9lives Polish implementation; do
  reset_layers
  cat_entry "$tracked_cat" "$bad" "kind: prompt" "target: p"
  printf 'steps_pre_ci: [polish]\n' >"$tracked_cfg"
  capture pre-ci --unattended
  [ "$RC" = 4 ]
  verdict "REQ-B1.2: the id '$bad' is malformed for its layer (exit 4)" "REQ-B1.2: id '$bad': rc=$RC (want 4) err='$ERR'"
done
reset_layers
cat_entry "$tracked_cat" "$(printf '%0.sa' $(seq 1 65))" "kind: prompt" "target: p"
capture pre-ci --unattended
[ "$RC" = 4 ]
verdict "REQ-B1.2: an id over 64 bytes is malformed (exit 4)" "REQ-B1.2: 65-byte id: rc=$RC (want 4)"

# A timeout on an in-session COMMAND step resolves.
reset_layers
cat_entry "$tracked_cat" cmd-in "kind: command" "target: fixture-tool" "hosting: in-session" "timeout: 10"
printf 'steps_pre_ci: [cmd-in]\n' >"$tracked_cfg"
capture pre-ci --unattended --explain
[ "$RC" = 0 ] && printf '%s\n' "$OUT" | grep -q "^run${TAB}cmd-in${TAB}.*${TAB}in-session${TAB}command${TAB}-${TAB}halt${TAB}10${TAB}"
verdict "REQ-B1.2: a timeout on an in-session command step resolves" "REQ-B1.2: in-session command timeout: rc=$RC out='$OUT' err='$ERR'"

# The effective hosting is what the timeout rule reads: an unset hosting
# defaults from dispatch_isolation, so the same skill entry resolves under
# per-step (isolated) and is malformed under per-unit (in-session).
reset_layers
cat_entry "$tracked_cat" timed "kind: skill" "target: polish" "timeout: 10"
printf 'steps_pre_ci: [timed]\n' >"$tracked_cfg"
capture pre-ci --unattended --explain
[ "$RC" = 0 ] && printf '%s\n' "$OUT" | grep -q "^run${TAB}timed${TAB}.*${TAB}isolated${TAB}skill${TAB}"
verdict "REQ-D1.3: an unset hosting defaults to isolated under per-step" "default hosting per-step: rc=$RC out='$OUT' err='$ERR'"
write_core_defaults per-unit
capture pre-ci --unattended --explain
[ "$RC" = 4 ]
verdict "REQ-B1.2: the same timed skill step is malformed once per-unit makes it in-session" "timed skill under per-unit: rc=$RC (want 4) out='$OUT' err='$ERR'"
rm -f "$tracked_cat"
cat_entry "$tracked_cat" plain "kind: skill" "target: polish"
printf 'steps_pre_ci: [plain]\n' >"$tracked_cfg"
capture pre-ci --unattended --explain
[ "$RC" = 0 ] && printf '%s\n' "$OUT" | grep -q "^run${TAB}plain${TAB}.*${TAB}in-session${TAB}skill${TAB}"
verdict "REQ-D1.3: an unset hosting defaults to in-session under per-unit" "default hosting per-unit: rc=$RC out='$OUT' err='$ERR'"

# A malformed core entry is a broken install (exit 5).
reset_layers
cp "$core/config/steps.yaml" "$tmp/steps.bak"
cat_entry "$core/config/steps.yaml" broken "kind: ritual" "target: p"
capture convergence --unattended
[ "$RC" = 5 ]
verdict "REQ-C1.5: a malformed core entry is a broken install (exit 5)" "malformed core entry: rc=$RC (want 5) err='$ERR'"
cp "$tmp/steps.bak" "$core/config/steps.yaml"

# =============================================================================
# 5. Lists: order, duplicates, continue placement (REQ-B1.4).
# =============================================================================
reset_layers
cat_entry "$tracked_cat" one "kind: prompt" "target: first"
cat_entry "$tracked_cat" two "kind: prompt" "target: second"
printf 'steps_pre_pr: [two, polish, one]\n' >"$tracked_cfg"
capture pre-pr --unattended
[ "$RC" = 0 ] && [ "$OUT" = "$(printf 'run\ttwo\nrun\tpolish\nrun\tone')" ]
verdict "REQ-B1.4: the list is emitted in declared order" "REQ-B1.4: order: rc=$RC out='$OUT' err='$ERR'"

printf 'steps_pre_pr: [one, two, one]\n' >"$tracked_cfg"
capture pre-pr --unattended
[ "$RC" = 4 ] && printf '%s' "$ERR" | grep -q 'twice'
verdict "REQ-B1.4: a list naming an id twice is malformed (exit 4 in repo-tracked)" "REQ-B1.4: duplicate id: rc=$RC err='$ERR'"

# A list naming the reserved id, and a list with an id outside the charset.
printf 'steps_pre_pr: [implementation]\n' >"$tracked_cfg"
capture pre-pr --unattended
[ "$RC" = 4 ]
verdict "REQ-B1.2: a list naming 'implementation' is malformed" "list naming implementation: rc=$RC (want 4)"
printf 'steps_pre_pr: [one, Two]\n' >"$tracked_cfg"
capture pre-pr --unattended
[ "$RC" = 4 ]
verdict "REQ-B1.2: a list id outside the charset is malformed" "list id charset: rc=$RC (want 4)"

reset_layers
cat_entry "$tracked_cat" cont "kind: prompt" "target: carry on" "hosting: continue"
cat_entry "$tracked_cat" iso-cmd "kind: command" "target: fixture-tool" "hosting: isolated"
cat_entry "$tracked_cat" in-cmd "kind: command" "target: fixture-tool" "hosting: in-session"
cat_entry "$tracked_cat" iso-skill "kind: skill" "target: polish" "hosting: isolated"
printf 'steps_pre_pr: [cont, polish]\n' >"$tracked_cfg"
capture pre-pr --unattended
[ "$RC" = 4 ] && printf '%s' "$ERR" | grep -q 'first'
verdict "REQ-B1.4: a first-position continue is malformed" "first-position continue: rc=$RC err='$ERR'"
printf 'steps_pre_pr: [iso-cmd, cont]\n' >"$tracked_cfg"
capture pre-pr --unattended
[ "$RC" = 4 ] && printf '%s' "$ERR" | grep -q 'subprocess'
verdict "REQ-B1.4: continue immediately after an isolated command step is malformed" "continue after isolated command: rc=$RC err='$ERR'"
printf 'steps_pre_pr: [in-cmd, cont]\n' >"$tracked_cfg"
capture pre-pr --unattended --explain
[ "$RC" = 0 ] && printf '%s\n' "$OUT" | grep -q "^run${TAB}cont${TAB}.*${TAB}in-session${TAB}prompt${TAB}"
verdict "REQ-B1.4: continue after an in-session command step resolves with hosting in-session" "continue after in-session command: rc=$RC out='$OUT' err='$ERR'"
printf 'steps_pre_pr: [iso-skill, cont]\n' >"$tracked_cfg"
capture pre-pr --unattended --explain
[ "$RC" = 0 ] && printf '%s\n' "$OUT" | grep -q "^run${TAB}cont${TAB}.*${TAB}continue${TAB}prompt${TAB}"
verdict "REQ-B1.4: continue after an isolated skill step keeps hosting continue" "continue after isolated skill: rc=$RC out='$OUT' err='$ERR'"
# A timeout on a continue step attached to an in-session predecessor is a
# timeout on an effectively in-session session step: malformed for the entry.
cat_entry "$tracked_cat" cont-timed "kind: prompt" "target: carry on" "hosting: continue" "timeout: 5"
printf 'steps_pre_pr: [in-cmd, cont-timed]\n' >"$tracked_cfg"
capture pre-pr --unattended
[ "$RC" = 4 ] && printf '%s' "$ERR" | grep -q 'timeout'
verdict "REQ-B1.2: a timeout on a continue step attached to an in-session predecessor is malformed" "continue timeout attached in-session: rc=$RC err='$ERR'"
printf 'steps_pre_pr: [iso-skill, cont-timed]\n' >"$tracked_cfg"
capture pre-pr --unattended
[ "$RC" = 0 ]
verdict "REQ-B1.2: the same timed continue step resolves after an isolated predecessor" "continue timeout after isolated: rc=$RC err='$ERR'"
# A drop the list's order caused does not outlive the list: an adopter list
# drops cont-timed for its position, then hits a list-level fault and gives
# way to the core list, where the same id sits in a valid position.
reset_layers
cat_entry "$adopter_cat" cont "kind: prompt" "target: carry on" "hosting: continue"
cat_entry "$adopter_cat" iso-cmd "kind: command" "target: fixture-tool" "hosting: isolated"
cat_entry "$adopter_cat" in-cmd "kind: command" "target: fixture-tool" "hosting: in-session"
cat_entry "$adopter_cat" iso-skill "kind: skill" "target: polish" "hosting: isolated"
cat_entry "$adopter_cat" cont-timed "kind: prompt" "target: carry on" "hosting: continue" "timeout: 5"
printf 'steps_pre_pr: [in-cmd, cont-timed, iso-cmd, cont]\n' >"$adopter_cfg"
sed -i.bak 's/^steps_pre_pr: .*/steps_pre_pr: [iso-skill, cont-timed]/' "$core/config/defaults.yml"
rm -f "$core/config/defaults.yml.bak"
capture pre-pr --unattended
{ [ "$RC" = 0 ] && [ "$OUT" = "$(printf 'run\tiso-skill\nrun\tcont-timed')" ] && printf '%s' "$ERR" | grep -q 'for this list'; } \
  || fail "REQ-C1.5: a list-order drop should reset on the core fallback: rc=$RC out='$OUT' err='$ERR'"
ok "REQ-C1.5: a drop the list's order caused is reset when the list gives way to the core default"
reset_layers
cat_entry "$tracked_cat" cont "kind: prompt" "target: carry on" "hosting: continue"
cat_entry "$tracked_cat" iso-skill "kind: skill" "target: polish" "hosting: isolated"
# A list-level fault in an adopter list degrades to the core default (empty
# for pre-pr), with the warning, and fails check mode.
rm -f "$tracked_cfg"
printf 'steps_pre_pr: [cont, polish]\n' >"$adopter_cfg"
capture pre-pr --unattended
{ [ "$RC" = 0 ] && [ -z "$OUT" ] && printf '%s' "$ERR" | grep 'malformed' | grep -q 'adopter'; } \
  || fail "REQ-C1.5: a first-position continue in an adopter list: rc=$RC out='$OUT' err='$ERR'"
capture pre-pr --check --unattended
[ "$RC" = 1 ] || fail "REQ-H1.3: the degraded adopter list must fail check mode (rc=$RC)"
ok "REQ-C1.5: a list-level fault in an adopter list degrades to the core default and fails check mode"

# =============================================================================
# 6. Target grammar per kind (REQ-B1.6, REQ-G1.1).
# =============================================================================
reset_layers
mkdir -p "$claude/skills/user-skill" "$repo/.claude/skills/proj-skill"
printf 'user\n' >"$claude/commands/user-cmd.md"
printf 'user\n' >"$claude/skills/user-skill/SKILL.md"
printf 'proj\n' >"$repo/.claude/commands/proj-cmd.md"
printf 'proj\n' >"$repo/.claude/skills/proj-skill/SKILL.md"
plug="$tmp/plugins/other/1.0.0"
plug2="$tmp/plugins/other/2.0.0"
mkdir -p "$plug/skills/their-skill" "$plug/commands" "$plug2/skills/v2-skill"
printf 'theirs\n' >"$plug/skills/their-skill/SKILL.md"
printf 'theirs\n' >"$plug/commands/their-cmd.md"
printf 'v2\n' >"$plug2/skills/v2-skill/SKILL.md"
write_registry() {
  cat >"$registry" <<EOF
{"version": 2, "plugins": {
  "other@market": [{"installPath": "$plug", "version": "1.0.0"}],
  "multi@market": [{"installPath": "$tmp/plugins/nowhere"}, {"installPath": "$plug2"}],
  "first@market": [{"installPath": "$plug"}, {"installPath": "$plug2"}],
  "dup@one": [{"installPath": "$plug"}],
  "dup@two": [{"installPath": "$plug"}],
  "planwright@planwright": [{"installPath": "$core"}]
}}
EOF
}
write_registry
cat_entry "$tracked_cat" s-bare "kind: skill" "target: polish"
cat_entry "$tracked_cat" s-user-cmd "kind: skill" "target: user-cmd"
cat_entry "$tracked_cat" s-user-skill "kind: skill" "target: user-skill"
cat_entry "$tracked_cat" s-proj-cmd "kind: skill" "target: proj-cmd"
cat_entry "$tracked_cat" s-proj-skill "kind: skill" "target: proj-skill"
cat_entry "$tracked_cat" s-pw "kind: skill" "target: planwright:self-review" "args: --nested"
cat_entry "$tracked_cat" s-plug-skill "kind: skill" "target: other:their-skill"
cat_entry "$tracked_cat" s-plug-cmd "kind: skill" "target: other:their-cmd"
cat_entry "$tracked_cat" s-multi "kind: skill" "target: multi:v2-skill"
cat_entry "$tracked_cat" s-first "kind: skill" "target: first:their-skill"
cat_entry "$tracked_cat" c-name "kind: command" "target: fixture-tool" "args: --nested x=1  a/b   c"
cat_entry "$tracked_cat" c-path "kind: command" "target: $bin/fixture-tool"
cat_entry "$tracked_cat" c-rel "kind: command" "target: ./rel-tool"
cat_entry "$tracked_cat" p-text "kind: prompt" "target: Review the diff for typos."
printf '#!/bin/sh\nexit 0\n' >"$tmp/rel-tool"
chmod +x "$tmp/rel-tool"
printf 'steps_post_pr: [s-bare, s-user-cmd, s-user-skill, s-proj-cmd, s-proj-skill, s-pw, s-plug-skill, s-plug-cmd, s-multi, s-first, c-name, c-path, c-rel, p-text]\n' >"$tracked_cfg"
OUT=$(cd "$tmp" && run post-pr --unattended --explain 2>"$tmp/err")
RC=$?
ERR=$(cat "$tmp/err")
[ "$RC" = 0 ] || fail "REQ-C1.3: every target kind on the host: rc=$RC out='$OUT' err='$ERR'"
check_loc() {
  printf '%s\n' "$OUT" | grep -q "^run${TAB}$1${TAB}.*${TAB}$2\$" \
    || fail "REQ-C1.3: step '$1' did not resolve to '$2': $(printf '%s\n' "$OUT" | grep "${TAB}$1${TAB}")"
}
check_loc s-bare "$core/skills/polish/SKILL.md"
check_loc s-user-cmd "$claude/commands/user-cmd.md"
check_loc s-user-skill "$claude/skills/user-skill/SKILL.md"
check_loc s-proj-cmd "$repo/.claude/commands/proj-cmd.md"
check_loc s-proj-skill "$repo/.claude/skills/proj-skill/SKILL.md"
check_loc s-pw "$core/skills/self-review/SKILL.md"
check_loc s-plug-skill "$plug/skills/their-skill/SKILL.md"
check_loc s-plug-cmd "$plug/commands/their-cmd.md"
check_loc s-multi "$plug2/skills/v2-skill/SKILL.md"
check_loc s-first "$plug/skills/their-skill/SKILL.md"
check_loc c-name "$bin/fixture-tool"
check_loc c-path "$bin/fixture-tool"
check_loc c-rel "./rel-tool"
check_loc p-text "-"
ok "REQ-C1.3/D-19: skill, command, and prompt targets resolve on the host through every lookup rule"
# The declared command line is emitted as written (runs of spaces kept), and
# skill args verbatim.
printf '%s\n' "$OUT" | grep -q "^run${TAB}c-name${TAB}post-pr${TAB}repo-tracked${TAB}repo-tracked${TAB}fixture-tool${TAB}isolated${TAB}command${TAB}--nested x=1  a/b   c${TAB}"
verdict "REQ-G1.1: a declared command line is emitted as written" "REQ-G1.1: command line not byte-identical: $(printf '%s\n' "$OUT" | grep "${TAB}c-name${TAB}")"
printf '%s\n' "$OUT" | grep -q "^run${TAB}s-pw${TAB}.*${TAB}skill${TAB}--nested${TAB}"
verdict "REQ-B1.6/REQ-C1.3: a skill's --nested argument is passed through unexamined" "skill args verbatim: $(printf '%s\n' "$OUT" | grep "${TAB}s-pw${TAB}")"

# Each one absent does not resolve (matrix path: unattended repo-tracked -> park).
absent_case() {
  printf 'steps_post_pr: [%s]\n' "$1" >"$tracked_cfg"
  capture post-pr --unattended
  [ "$RC" = 1 ] && [ "$OUT" = "park${TAB}$1" ] \
    || fail "REQ-C1.3: '$1' ($2) should not resolve: rc=$RC out='$OUT' err='$ERR'"
}
rm -f "$claude/commands/user-cmd.md"
absent_case s-user-cmd "user command removed"
rm -rf "$repo/.claude/skills/proj-skill"
absent_case s-proj-skill "project skill removed"
rm -f "$plug/commands/their-cmd.md"
absent_case s-plug-cmd "plugin command removed"
rm -f "$bin/fixture-tool"
absent_case c-name "command off the path"
absent_case c-path "command path removed"
rm -rf "$claude/skills/user-skill"
absent_case s-user-skill "user skill removed"
rm -f "$repo/.claude/commands/proj-cmd.md"
absent_case s-proj-cmd "project command removed"
mv "$core/skills/self-review" "$tmp/self-review.bak"
absent_case s-pw "planwright-namespaced skill removed (never found in the user dirs)"
mkdir -p "$claude/skills/self-review"
printf 'user copy\n' >"$claude/skills/self-review/SKILL.md"
absent_case s-pw "planwright-namespaced skill present only in the user skills dir"
rm -rf "$claude/skills/self-review"
mv "$tmp/self-review.bak" "$core/skills/self-review"
mv "$plug/skills/their-skill" "$tmp/their-skill.bak"
absent_case s-plug-skill "plugin skill removed, registry intact"
mv "$tmp/their-skill.bak" "$plug/skills/their-skill"
mv "$plug2/skills/v2-skill" "$tmp/v2-skill.bak"
absent_case s-multi "neither listed install path holds the skill"
mv "$tmp/v2-skill.bak" "$plug2/skills/v2-skill"
# A relative install path would resolve against the worktree, which the
# worker can write: never probed.
mkdir -p "$tmp/plugins/rel/skills/rel-skill"
printf 'rel\n' >"$tmp/plugins/rel/skills/rel-skill/SKILL.md"
printf '{"version": 2, "plugins": {"rel@market": [{"installPath": "plugins/rel"}]}}\n' >"$registry"
cat_entry "$tracked_cat" s-rel "kind: skill" "target: rel:rel-skill"
printf 'steps_post_pr: [s-rel]\n' >"$tracked_cfg"
OUT=$(cd "$tmp" && run post-pr --unattended 2>"$tmp/err")
RC=$?
[ "$RC" = 1 ] && [ "$OUT" = "park${TAB}s-rel" ] \
  || fail "REQ-C1.3: a relative registry install path must not resolve: rc=$RC out='$OUT' err='$(cat "$tmp/err")'"
write_registry
printf '#!/bin/sh\nexit 0\n' >"$bin/fixture-tool"
chmod +x "$bin/fixture-tool"
ok "REQ-C1.3: each absent target is non-resolving under the matrix"

cat_entry "$tracked_cat" s-dup "kind: skill" "target: dup:their-skill"
cat_entry "$tracked_cat" s-none "kind: skill" "target: nosuch:their-skill"
absent_case s-dup "a namespace matching two registry keys"
printf '%s' "$ERR" | grep -q 'ambiguous' || fail "the ambiguous namespace should be named as such: $ERR"
absent_case s-none "a namespace absent from the registry"
printf 'not json' >"$registry"
absent_case s-plug-skill "an unreadable registry"
write_registry
OUT=$(run PLANWRIGHT_JQ="$tmp/no-jq" post-pr --unattended 2>"$tmp/err")
RC=$?
[ "$RC" = 1 ] && [ "$OUT" = "park${TAB}s-plug-skill" ] \
  || fail "REQ-C1.3: a missing JSON reader should be non-resolving: rc=$RC out='$OUT'"
printf 'steps_post_pr: [s-plug-skill]\n' >"$tracked_cfg"
capture post-pr --unattended
[ "$RC" = 0 ] && [ "$OUT" = "run${TAB}s-plug-skill" ] \
  || fail "REQ-C1.3: the registry lookup should resolve again once the registry is back"
ok "REQ-C1.3/D-19: an ambiguous namespace, an absent one, an unreadable registry, and a missing JSON reader are non-resolving, never an error"

# An id naming no catalog entry takes the matrix path.
printf 'steps_post_pr: [ghost]\n' >"$tracked_cfg"
capture post-pr --unattended
[ "$RC" = 1 ] && [ "$OUT" = "park${TAB}ghost" ] && printf '%s' "$ERR" | grep -q 'no catalog entry'
verdict "REQ-C1.3: an id naming no catalog entry takes the matrix path" "no catalog entry: rc=$RC out='$OUT' err='$ERR'"
# requires naming an absent executable does not resolve.
cat_entry "$tracked_cat" needs-path "kind: prompt" "target: p" "requires: $bin/fixture-tool"
printf 'steps_post_pr: [needs-path]\n' >"$tracked_cfg"
capture post-pr --unattended
[ "$RC" = 0 ] && [ "$OUT" = "run${TAB}needs-path" ]
verdict "REQ-D1.8: a requires executable given as a path resolves" "requires path: rc=$RC out='$OUT' err='$ERR'"
printf '#!/bin/sh\n' >"$bin/not-exec"
cat_entry "$tracked_cat" needs-nx "kind: prompt" "target: p" "requires: $bin/not-exec"
printf 'steps_post_pr: [needs-nx]\n' >"$tracked_cfg"
capture post-pr --unattended
[ "$RC" = 1 ] && [ "$OUT" = "park${TAB}needs-nx" ] && printf '%s' "$ERR" | grep -q 'at that path'
verdict "REQ-D1.8: a non-executable requires path does not resolve, the diagnostic naming the path form" "requires non-executable path: rc=$RC out='$OUT' err='$ERR'"
cat_entry "$tracked_cat" needs "kind: prompt" "target: p" "requires: fixture-tool no-such-exe"
printf 'steps_post_pr: [needs]\n' >"$tracked_cfg"
capture post-pr --unattended
[ "$RC" = 1 ] && [ "$OUT" = "park${TAB}needs" ] && printf '%s' "$ERR" | grep -q 'no-such-exe'
verdict "REQ-D1.8: a requires executable missing on the host is a step that does not resolve" "missing requires: rc=$RC out='$OUT' err='$ERR'"

# Refused grammar: a leading slash, a shell metacharacter, a traversal segment,
# an empty prompt, and command args carrying an operator, redirection,
# expansion, or quote. Each is malformed BEFORE any probe (the diagnostic says
# malformed, never not-found).
grammar_case() {
  label="$1"
  shift
  reset_layers
  cat_entry "$tracked_cat" g "$@"
  printf 'steps_post_pr: [g]\n' >"$tracked_cfg"
  capture post-pr --unattended
  if [ "$RC" = 4 ] && printf '%s' "$ERR" | grep -q 'malformed' && ! printf '%s' "$ERR" | grep -q 'not found'; then
    ok "REQ-B1.6: $label is malformed before any probe"
  else
    fail "REQ-B1.6: $label: rc=$RC (want 4) err='$ERR'"
  fi
}
grammar_case "a skill target with a leading slash" "kind: skill" "target: /polish"
grammar_case "a skill target with an empty namespace" "kind: skill" "target: :polish"
grammar_case "a skill target with an underscore" "kind: skill" "target: my_skill"
grammar_case "a skill target with two namespaces" "kind: skill" "target: a:b:c"
grammar_case "a skill target with a metacharacter" "kind: skill" "target: polish;rm"
grammar_case "a command target with a metacharacter" "kind: command" "target: tool|sh"
grammar_case "a command target with a traversal segment" "kind: command" "target: ../bin/tool"
grammar_case "a command target with a dollar" "kind: command" "target: \$HOME/tool"
grammar_case "an empty prompt" "kind: prompt" "target:"
grammar_case "a block-scalar prompt" "kind: prompt" "target: |" "  first line" "  second line"
grammar_case "a prompt with a continuation line" "kind: prompt" "target: first" "second line of prompt"
grammar_case "a block-valued requires" "kind: command" "target: fixture-tool" "requires:" "  - nosuchtool"
grammar_case "command args with a pipe" "kind: command" "target: fixture-tool" "args: a | b"
grammar_case "command args with a redirection" "kind: command" "target: fixture-tool" "args: a >out"
grammar_case "command args with an expansion" "kind: command" "target: fixture-tool" "args: \$HOME"
grammar_case "command args with a glob" "kind: command" "target: fixture-tool" "args: *.sh"
grammar_case "command args with a quote" "kind: command" "target: fixture-tool" "args: 'a b'"
grammar_case "command args with a backtick" "kind: command" "target: fixture-tool" "args: \`id\`"
grammar_case "requires with a metacharacter" "kind: prompt" "target: p" "requires: sh;rm"
grammar_case "requires with a traversal segment" "kind: prompt" "target: p" "requires: ../sh"
# Refused before any probe: a traversal target that WOULD resolve if probed
# first is still malformed, and a glob in args is judged as written even in a
# directory where it would match.
mkdir -p "$tmp/sub"
reset_layers
cat_entry "$tracked_cat" g "kind: command" "target: ../bin/fixture-tool"
printf 'steps_post_pr: [g]\n' >"$tracked_cfg"
OUT=$(cd "$tmp/sub" && run post-pr --unattended 2>"$tmp/err")
RC=$?
[ "$RC" = 4 ] || fail "REQ-B1.6: a traversal target that exists on disk must still be malformed (rc=$RC)"
rm -f "$tracked_cat"
cat_entry "$tracked_cat" g "kind: command" "target: fixture-tool" "args: *"
OUT=$(cd "$bin" && run post-pr --unattended 2>"$tmp/err")
RC=$?
[ "$RC" = 4 ] || fail "REQ-G1.1: a glob in args must be malformed even where it would match (rc=$RC)"
ok "REQ-B1.6: refusal precedes the probe, and a glob is judged as written"

# =============================================================================
# 7. Last layer wins with a shadow warning (REQ-C1.1).
# =============================================================================
reset_layers
cat_entry "$adopter_cat" a-step "kind: prompt" "target: a"
printf 'steps_pre_pr: [a-step]\n' >"$adopter_cfg"
printf 'steps_pre_pr: [polish]\n' >"$tracked_cfg"
capture pre-pr --unattended
[ "$RC" = 0 ] && [ "$OUT" = "run${TAB}polish" ] \
  && printf '%s' "$ERR" | grep 'shadow' | grep -q 'adopter'
verdict "REQ-C1.1: two layers resolve to the higher one and the warning names the lower" "REQ-C1.1 two layers: rc=$RC out='$OUT' err='$ERR'"
printf 'steps_pre_pr: [a-step]\n' >"$mlocal_cfg"
capture pre-pr --unattended
[ "$RC" = 0 ] && [ "$OUT" = "run${TAB}a-step" ] \
  && [ "$(printf '%s\n' "$ERR" | grep -c 'shadow')" = 1 ] \
  && printf '%s' "$ERR" | grep 'shadow' | grep -q 'adopter' \
  && printf '%s' "$ERR" | grep 'shadow' | grep -q 'repo-tracked'
verdict "REQ-C1.1: three layers name both lower ones in one warning" "REQ-C1.1 three layers: rc=$RC out='$OUT' err='$ERR'"
reset_layers
printf 'steps_pre_pr: [polish]\n' >"$tracked_cfg"
capture pre-pr --unattended
[ "$RC" = 0 ] && ! printf '%s' "$ERR" | grep -q 'shadow'
verdict "REQ-C1.1: a list at one overlay layer prints no shadow warning" "REQ-C1.1 one layer: rc=$RC err='$ERR'"
# The shadow warning names every lower overlay layer whatever its value: an empty
# lower list is still shadowed.
printf 'steps_pre_pr: []\n' >"$adopter_cfg"
capture pre-pr --unattended
[ "$RC" = 0 ] && printf '%s' "$ERR" | grep 'shadow' | grep -q 'adopter'
verdict "REQ-C1.1: a shadowed layer is named whatever its value" "REQ-C1.1 empty shadowed: err='$ERR'"

# =============================================================================
# 8. The missing-step matrix (REQ-C1.4) and whole-point resolution (REQ-D1.9).
# =============================================================================
missing_at() {
  # missing_at <layer-cfg> <attendance> <want-output> <want-rc>: judged in
  # the parent shell so a failure counts.
  reset_layers
  printf 'steps_pre_pr: [polish, ghost]\n' >"$1"
  capture pre-pr "$2"
  [ "$OUT" = "$3" ] || fail "matrix ($1 $2): out='$OUT' want='$3' err='$ERR'"
  [ "$RC" = "$4" ] || fail "matrix ($1 $2): rc=$RC (want $4)"
}
missing_at "$adopter_cfg" --attended "$(printf 'ask\tpolish\nask\tghost')" 1
missing_at "$tracked_cfg" --attended "$(printf 'ask\tpolish\nask\tghost')" 1
missing_at "$mlocal_cfg" --attended "$(printf 'ask\tpolish\nask\tghost')" 1
ok "REQ-C1.4: attended prints ask for a missing step from each overlay layer (point-wide, exit 1)"
missing_at "$tracked_cfg" --unattended "$(printf 'park\tpolish\npark\tghost')" 1
ok "REQ-C1.4/REQ-D1.9: unattended repo-tracked prints park for the point and run for no step"
missing_at "$adopter_cfg" --unattended "$(printf 'run\tpolish\nskip\tghost')" 0
missing_at "$mlocal_cfg" --unattended "$(printf 'run\tpolish\nskip\tghost')" 0
reset_layers
printf 'steps_pre_pr: [polish, ghost]\n' >"$mlocal_cfg"
capture pre-pr --unattended
printf '%s' "$ERR" | grep -q 'ghost' && printf '%s' "$ERR" | grep -qi 'skip'
verdict "REQ-C1.4: unattended adopter/machine-local prints skip with a warning naming the step (exit 0)" "skip warning: err='$ERR'"
# A core-default step made unresolvable prints park at both attendances.
reset_layers
mv "$core/skills/polish" "$tmp/polish.bak"
capture convergence --attended
[ "$RC" = 1 ] && [ "$OUT" = "park${TAB}polish" ] || fail "core unresolvable attended: rc=$RC out='$OUT'"
capture convergence --unattended
[ "$RC" = 1 ] && [ "$OUT" = "park${TAB}polish" ] || fail "core unresolvable unattended: rc=$RC out='$OUT'"
capture convergence --check --unattended
[ "$RC" = 1 ] || fail "check mode must fail (exit 1) on a core park: rc=$RC"
mv "$tmp/polish.bak" "$core/skills/polish"
ok "REQ-C1.4: a core-default step that does not resolve prints park at both attendances"
# Check mode: non-zero on any park; passes with a warning on an adopter skip.
reset_layers
printf 'steps_pre_pr: [ghost]\n' >"$tracked_cfg"
capture pre-pr --check --unattended
[ "$RC" = 1 ]
verdict "REQ-H1.3: check mode exits non-zero on a park" "check mode park: rc=$RC (want 1)"
reset_layers
printf 'steps_pre_pr: [polish, ghost]\n' >"$adopter_cfg"
capture pre-pr --check --unattended
[ "$RC" = 0 ] && printf '%s' "$ERR" | grep -q 'ghost'
verdict "REQ-H1.3: check mode passes with a warning on an adopter skip" "check mode adopter skip: rc=$RC err='$ERR'"
reset_layers
printf 'steps_pre_pr: [polish, ghost]\n' >"$mlocal_cfg"
capture pre-pr --check --unattended
[ "$RC" = 0 ] && printf '%s' "$ERR" | grep -q 'ghost'
verdict "REQ-H1.3: check mode passes with a warning on a machine-local skip" "check mode machine-local skip: rc=$RC err='$ERR'"

# A misplaced continue is the list's and the entry's together: a personal
# entry is dropped for the list and never breaks a core or team list, and a
# team entry misplaced by the core list hard-fails as the team's.
reset_layers
cat_entry "$adopter_cat" polish "supersede: true" "kind: skill" "target: polish" "hosting: continue"
capture convergence --unattended
{ [ "$RC" = 1 ] && [ "$OUT" = "park${TAB}polish" ] && printf '%s' "$ERR" | grep 'for this list' | grep -q 'adopter'; } \
  || fail "REQ-C1.5: an adopter continue entry in the core list must drop, not break the install: rc=$RC out='$OUT' err='$ERR'"
reset_layers
cat_entry "$tracked_cat" iso-cmd "kind: command" "target: fixture-tool" "hosting: isolated"
cat_entry "$adopter_cat" mine "kind: prompt" "target: carry on" "hosting: continue"
printf 'steps_pre_pr: [iso-cmd, mine]\n' >"$tracked_cfg"
capture pre-pr --unattended
{ [ "$RC" = 1 ] && [ "$OUT" = "$(printf 'park\tiso-cmd\npark\tmine')" ] && printf '%s' "$ERR" | grep 'for this list' | grep -q 'adopter'; } \
  || fail "REQ-C1.5: an adopter continue entry in a team list must drop, not hard-fail the team: rc=$RC out='$OUT' err='$ERR'"
reset_layers
cat_entry "$tracked_cat" polish "supersede: true" "kind: skill" "target: polish" "hosting: continue"
capture convergence --unattended
[ "$RC" = 4 ]
verdict "REQ-C1.5: a team continue entry misplaced by the core list hard-fails as the team's" "repo continue in core list: rc=$RC err='$ERR'"
ok "REQ-B1.4/REQ-C1.5: a misplaced continue is judged by the list's and the entry's layers together"

# =============================================================================
# 9. Malformation by layer for LISTS (REQ-C1.5), and the degraded winner.
# =============================================================================
reset_layers
printf 'steps_convergence: [polish, polish]\n' >"$tracked_cfg"
capture convergence --unattended
[ "$RC" = 4 ]
verdict "REQ-C1.5: a malformed repo-tracked list exits 4" "malformed repo list: rc=$RC err='$ERR'"
reset_layers
printf 'steps_convergence: [polish, polish]\n' >"$adopter_cfg"
capture convergence --unattended --explain
[ "$RC" = 0 ] && printf '%s\n' "$OUT" | grep -q "^run${TAB}polish${TAB}convergence${TAB}core${TAB}" \
  && printf '%s' "$ERR" | grep -q 'adopter'
verdict "REQ-C1.5: a malformed adopter list warns and resolves the core default, the winner then core" "malformed adopter list: rc=$RC out='$OUT' err='$ERR'"
# ... and the matrix then keys on core: with the core step unresolvable the
# degraded resolution parks at both attendances.
mv "$core/skills/polish" "$tmp/polish.bak"
capture convergence --unattended
[ "$RC" = 1 ] && [ "$OUT" = "park${TAB}polish" ]
verdict "REQ-C1.5/D-6: after an adopter list degrades, the matrix keys on the core layer" "degraded winner matrix: rc=$RC out='$OUT'"
mv "$tmp/polish.bak" "$core/skills/polish"
capture convergence --check --unattended
[ "$RC" = 1 ]
verdict "REQ-H1.3: check mode exits non-zero on a degraded adopter malformation" "check mode degraded malformation: rc=$RC"
reset_layers
printf 'steps_convergence: [polish, polish]\n' >"$core/config/defaults.yml"
printf 'dispatch_isolation: per-step\n' >>"$core/config/defaults.yml"
capture convergence --unattended
[ "$RC" = 5 ]
verdict "REQ-C1.5: a malformed core list is a broken install (exit 5)" "malformed core list: rc=$RC err='$ERR'"
reset_layers
printf 'dispatch_isolation: per-step\n' >"$core/config/defaults.yml"
capture convergence --unattended
[ "$RC" = 5 ]
verdict "a point key absent from every layer is a broken install (exit 5)" "absent key: rc=$RC (want 5) err='$ERR'"
reset_layers
printf 'steps_convergence:\n  - polish\n' >"$tracked_cfg"
capture convergence --unattended
[ "$RC" = 4 ] && printf '%s' "$ERR" | grep -q 'repo-tracked'
verdict "a structurally malformed repo-tracked config file propagates exit 4 with its diagnostic" "structural repo malformation: rc=$RC err='$ERR'"
# A sibling reader's own degrade (a malformed adopter config file) is
# replayed and fails check mode.
reset_layers
printf 'steps_convergence:\n  - polish\n' >"$adopter_cfg"
capture convergence --unattended
{ [ "$RC" = 0 ] && [ "$OUT" = "run${TAB}polish" ] && printf '%s' "$ERR" | grep -q 'adopter'; } \
  || fail "a malformed adopter config file should degrade with its warning replayed: rc=$RC out='$OUT' err='$ERR'"
# Several reads of the same layer repeat config-get's warning; it is
# replayed once.
w=$(printf '%s\n' "$ERR" | grep '^config-get' | head -1)
[ -n "$w" ] && [ "$(printf '%s\n' "$ERR" | grep -cxF "$w")" = 1 ] \
  || fail "a sibling warning repeated across reads should be replayed once: err='$ERR'"
capture convergence --check --unattended
[ "$RC" = 1 ] || fail "check mode must fail on a sibling reader's degrade (rc=$RC)"
# The same for a catalog the catalog reader degrades (a zero-entry adopter
# catalog).
reset_layers
printf 'steps:\n' >"$adopter_cat"
capture convergence --unattended
{ [ "$RC" = 0 ] && printf '%s' "$ERR" | grep -q 'adopter'; } \
  || fail "a degraded adopter catalog should have its warning replayed: rc=$RC err='$ERR'"
capture convergence --check --unattended
[ "$RC" = 1 ] || fail "check mode must fail on a degraded adopter catalog (rc=$RC)"
ok "REQ-H1.3: a sibling reader's degrade is replayed and fails check mode"

# =============================================================================
# 10. The stale key warns and is ignored (REQ-C1.6).
# =============================================================================
reset_layers
printf 'review_sequence: [self-review]\n' >"$adopter_cfg"
capture convergence --unattended
[ "$RC" = 0 ] && [ "$OUT" = "run${TAB}polish" ] \
  && [ "$(printf '%s\n' "$ERR" | grep -c 'review_sequence')" = 1 ] \
  && printf '%s' "$ERR" | grep 'review_sequence' | grep -q 'adopter' \
  && printf '%s' "$ERR" | grep 'review_sequence' | grep -q 'steps_convergence'
verdict "REQ-C1.6: review_sequence at one layer warns once naming the layer and steps_convergence; the chain is unaffected" "REQ-C1.6 one layer: rc=$RC out='$OUT' err='$ERR'"
printf 'review_sequence: [polish]\n' >"$mlocal_cfg"
capture pre-ci --unattended
[ "$RC" = 0 ] && [ -z "$OUT" ] && [ "$(printf '%s\n' "$ERR" | grep -c 'review_sequence')" = 2 ] \
  && printf '%s' "$ERR" | grep 'review_sequence' | grep -q 'machine-local'
verdict "REQ-C1.6: two layers produce two warnings, at every point" "REQ-C1.6 two layers: err='$ERR'"
printf 'review_sequence: [polish]\n' >"$tracked_cfg"
capture pre-ci --unattended
[ "$RC" = 0 ] && [ -z "$OUT" ] && [ "$(printf '%s\n' "$ERR" | grep -c 'review_sequence')" = 3 ] \
  && printf '%s' "$ERR" | grep 'review_sequence' | grep -q 'repo-tracked'
verdict "REQ-C1.6: the repo-tracked layer warns too" "REQ-C1.6 repo-tracked: err='$ERR'"
reset_layers
printf 'review_sequence: [polish]\n' >>"$core/config/defaults.yml"
capture convergence --unattended
{ [ "$RC" = 0 ] && [ "$OUT" = "run${TAB}polish" ] \
  && [ "$(printf '%s\n' "$ERR" | grep -c 'review_sequence')" = 1 ] \
  && printf '%s' "$ERR" | grep 'review_sequence' | grep -q 'the core layer'; }
verdict "REQ-C1.6: the core layer warns too" "REQ-C1.6 core: rc=$RC out='$OUT' err='$ERR'"

# =============================================================================
# 11. Unwired points (REQ-A1.3).
# =============================================================================
for p in $UNWIRED; do
  reset_layers
  k="steps_$(printf '%s' "$p" | tr '-' '_')"
  printf '%s: [polish]\n' "$k" >"$tracked_cfg"
  capture "$p" --unattended
  if ! { [ "$RC" = 0 ] && [ -z "$OUT" ] && printf '%s' "$ERR" | grep -q 'not wired'; }; then
    fail "REQ-A1.3: unwired '$p' non-empty: rc=$RC out='$OUT' err='$ERR'"
  fi
done
capture orchestrator-idle --check --unattended
[ "$RC" = 1 ] || fail "REQ-A1.3: an unwired non-empty list in check mode: rc=$RC (want 1)"
ok "REQ-A1.3: a non-empty list at every unwired point warns, resolves nothing (exit 0), and fails check mode"

# =============================================================================
# 12. No pipeline-entry targets (REQ-C1.8, D-17).
# =============================================================================
pipeline=$(sed -n 's/^pipeline-entry: //p' "$repo_root/doctrine/custom-steps.md")
[ -n "$pipeline" ] || fail "the rule doc carries no pipeline-entry line"
for name in $pipeline; do
  reset_layers
  cat_entry "$tracked_cat" entry "kind: skill" "target: $name"
  printf 'steps_pre_ci: [entry]\n' >"$tracked_cfg"
  capture pre-ci --unattended
  if ! { [ "$RC" = 4 ] && printf '%s' "$ERR" | grep -q 'pipeline-entry' && printf '%s' "$ERR" | grep -q "$name"; }; then
    fail "REQ-C1.8: '$name' as a skill target: rc=$RC err='$ERR'"
  fi
done
reset_layers
cat_entry "$tracked_cat" entry "kind: skill" "target: planwright:execute-task"
printf 'steps_pre_ci: [entry]\n' >"$tracked_cfg"
capture pre-ci --unattended
if ! { [ "$RC" = 4 ] && printf '%s' "$ERR" | grep -q 'pipeline-entry'; }; then
  fail "REQ-C1.8: 'planwright:execute-task' as a skill target: rc=$RC err='$ERR'"
fi
ok "REQ-C1.8: every pipeline-entry name is refused as a skill target, bare and namespaced, naming the rule"
# A plugin-namespaced pipeline-entry name is refused by the name after the
# prefix, never by resolvability.
reset_layers
cat_entry "$adopter_cat" entry "kind: skill" "target: other:orchestrate"
printf 'steps_pre_ci: [entry]\n' >"$adopter_cfg"
capture pre-ci --unattended
[ "$RC" = 0 ] && [ "$OUT" = "skip${TAB}entry" ] && printf '%s' "$ERR" | grep -q 'pipeline-entry'
verdict "REQ-C1.8: a foreign-namespaced pipeline-entry name is malformed for its layer (adopter: dropped)" "REQ-C1.8 foreign namespace: rc=$RC out='$OUT' err='$ERR'"

# The list is read from the script's own sibling doctrine dir and nowhere else:
# a copy an environment arm or resolve-rule-doc.sh would reach is ignored, and
# a missing or duplicated line is a broken install. The resolver is run from a
# symlinked scripts dir so its self-location points at a fixture doctrine.
inst="$tmp/inst"
mkdir -p "$inst/scripts" "$inst/doctrine"
for s in "$repo_root"/scripts/*.sh; do ln -s "$s" "$inst/scripts/$(basename "$s")"; done
run_inst() {
  # shellcheck disable=SC2086 # the unset flags are meant to word-split
  env $STEP_UNSETS -u CLAUDE_PLUGIN_ROOT -u CLAUDE_PLUGIN_DATA -u PLANWRIGHT_SKILLS_ROOT -u PLANWRIGHT_JQ \
    PLANWRIGHT_ROOT="$core" PLANWRIGHT_CONFIG_DEFAULTS="$core/config/defaults.yml" \
    PLANWRIGHT_ADOPTER_OVERLAY="$adopter" PLANWRIGHT_REPO_ROOT="$repo" \
    PLANWRIGHT_LOCAL_CONFIG="" CLAUDE_DIR="$claude" HOME="$tmp/home" PATH="$bin:$PATH" \
    /bin/bash "$inst/scripts/resolve-steps.sh" "$@"
}
reset_layers
cat_entry "$tracked_cat" fx "kind: skill" "target: fixture-entry"
printf 'steps_pre_ci: [fx]\n' >"$tracked_cfg"
printf 'pipeline-entry: execute-task fixture-entry\n' >"$inst/doctrine/custom-steps.md"
mkdir -p "$adopter/doctrine" "$core/doctrine"
printf 'pipeline-entry: execute-task\n' >"$adopter/doctrine/custom-steps.md"
printf 'pipeline-entry: execute-task\n' >"$core/doctrine/custom-steps.md"
rc=0
out=$(run_inst pre-ci --unattended 2>"$tmp/err") || rc=$?
[ "$rc" = 4 ] && grep -q 'pipeline-entry' "$tmp/err"
verdict "REQ-C1.8: the list is read from the script's sibling doctrine dir; overlay and env-arm copies are ignored" "sibling doctrine read: rc=$rc out='$out' err='$(cat "$tmp/err")'"
# Through the real script dir the same entry is merely unresolvable (park),
# which is what proves the fixture line, not the shipped one, was read above.
capture pre-ci --unattended
[ "$RC" = 1 ] && [ "$OUT" = "park${TAB}fx" ] \
  || fail "sibling doctrine control: rc=$RC out='$OUT' (want park through the shipped list)"
printf '# a rule doc with no pipeline-entry line\n' >"$inst/doctrine/custom-steps.md"
rc=0
run_inst convergence --unattended >/dev/null 2>"$tmp/err" || rc=$?
[ "$rc" = 5 ]
verdict "REQ-C1.8: a missing pipeline-entry line is a broken install (exit 5)" "missing pipeline-entry line: rc=$rc err='$(cat "$tmp/err")'"
rm -f "$inst/doctrine/custom-steps.md"
rc=0
run_inst convergence --unattended >/dev/null 2>"$tmp/err" || rc=$?
[ "$rc" = 5 ]
verdict "REQ-C1.8: a missing rule doc is a broken install (exit 5)" "missing rule doc: rc=$rc"
printf 'pipeline-entry: execute-task\npipeline-entry: drain\n' >"$inst/doctrine/custom-steps.md"
rc=0
run_inst convergence --unattended >/dev/null 2>"$tmp/err" || rc=$?
[ "$rc" = 5 ]
verdict "REQ-C1.8: a duplicated pipeline-entry line is a broken install (exit 5)" "duplicated pipeline-entry line: rc=$rc"
printf 'pipeline-entry: execute-task Bad\n' >"$inst/doctrine/custom-steps.md"
rc=0
run_inst convergence --unattended >/dev/null 2>"$tmp/err" || rc=$?
[ "$rc" = 5 ]
verdict "REQ-C1.8: a pipeline-entry token outside the id charset is a broken install (exit 5)" "bad pipeline-entry token: rc=$rc"
rm -rf "$adopter/doctrine" "$core/doctrine/custom-steps.md"

# =============================================================================
# 13. The preamble and the assignment prefix (REQ-A1.4, REQ-H1.3).
# =============================================================================
reset_layers
# ctx_run [VAR=value ...] -- <resolver args>: the resolver with the context
# fields set to the fixture values, the host's own exports cleared first, and
# any leading VAR=value overriding a fixture value.
prev_fixture="it's here"
ctx_run() {
  overrides=()
  while [ $# -gt 0 ] && [ "$1" != -- ]; do
    overrides+=("$1")
    shift
  done
  [ "${1:-}" = -- ] && shift
  # shellcheck disable=SC2086 # the unset flags are meant to word-split
  env $STEP_UNSETS -u CLAUDE_PLUGIN_ROOT -u CLAUDE_PLUGIN_DATA -u PLANWRIGHT_SKILLS_ROOT \
    -u PLANWRIGHT_JQ \
    PLANWRIGHT_STEP_SPEC=custom-steps PLANWRIGHT_STEP_TASK_IDS='2 3.5' \
    PLANWRIGHT_STEP_UNIT_KIND=task PLANWRIGHT_STEP_BRANCH=planwright/custom-steps/task-2 \
    PLANWRIGHT_STEP_BASE_BRANCH=main PLANWRIGHT_STEP_WORKTREE="$tmp/wt" \
    PLANWRIGHT_STEP_PR_NUMBER= PLANWRIGHT_STEP_POINT=wrong PLANWRIGHT_STEP_ID=polish \
    PLANWRIGHT_STEP_PREV_RECORD="$prev_fixture" \
    ${overrides[@]+"${overrides[@]}"} \
    PLANWRIGHT_ROOT="$core" PLANWRIGHT_CONFIG_DEFAULTS="$core/config/defaults.yml" \
    PLANWRIGHT_ADOPTER_OVERLAY="$adopter" PLANWRIGHT_REPO_ROOT="$repo" \
    PLANWRIGHT_LOCAL_CONFIG="" CLAUDE_DIR="$claude" HOME="$tmp/home" PATH="$bin:$PATH" \
    /bin/bash "$RS" "$@"
}
OUT=$(ctx_run -- pre-pr --preamble 2>"$tmp/err")
RC=$?
[ "$RC" = 0 ] || fail "REQ-A1.4: --preamble: rc=$RC err='$(cat "$tmp/err")'"
expected=$(printf '%s\n' \
  'planwright-step-context-begin' \
  'PLANWRIGHT_STEP_SPEC=custom-steps' \
  'PLANWRIGHT_STEP_TASK_IDS=2 3.5' \
  'PLANWRIGHT_STEP_UNIT_KIND=task' \
  'PLANWRIGHT_STEP_BRANCH=planwright/custom-steps/task-2' \
  'PLANWRIGHT_STEP_BASE_BRANCH=main' \
  "PLANWRIGHT_STEP_WORKTREE=$tmp/wt" \
  'PLANWRIGHT_STEP_PR_NUMBER=' \
  'PLANWRIGHT_STEP_POINT=pre-pr' \
  'PLANWRIGHT_STEP_ID=polish' \
  "PLANWRIGHT_STEP_PREV_RECORD=it's here" \
  'planwright-step-context-end')
[ "$OUT" = "$expected" ]
verdict "REQ-A1.4: --preamble renders exactly the ten fields, one per line, between whole-line delimiters, the point from the argument" "REQ-A1.4: preamble mismatch:
$OUT"
OUT=$(ctx_run -- pre-pr --prefix 2>"$tmp/err")
RC=$?
expected="PLANWRIGHT_STEP_SPEC='custom-steps' PLANWRIGHT_STEP_TASK_IDS='2 3.5' PLANWRIGHT_STEP_UNIT_KIND='task' PLANWRIGHT_STEP_BRANCH='planwright/custom-steps/task-2' PLANWRIGHT_STEP_BASE_BRANCH='main' PLANWRIGHT_STEP_WORKTREE='$tmp/wt' PLANWRIGHT_STEP_PR_NUMBER='' PLANWRIGHT_STEP_POINT='pre-pr' PLANWRIGHT_STEP_ID='polish' PLANWRIGHT_STEP_PREV_RECORD='it'\\''s here'"
[ "$RC" = 0 ] && [ "$OUT" = "$expected" ]
verdict "REQ-D1.3: --prefix renders the ten assignments POSIX single-quoted, a quote escaped as '\\''" "--prefix mismatch: rc=$RC
$OUT"
# The prefix round-trips through a shell: evaluating it reproduces the values.
got=$(eval "$OUT sh -c 'printf %s \"\$PLANWRIGHT_STEP_PREV_RECORD\"'")
[ "$got" = "it's here" ]
verdict "the rendered prefix round-trips through a POSIX shell" "prefix round-trip: got '$got'"
# An absent field renders empty, never unset: with nothing exported every
# value but the point is the empty string.
OUT=$(run pre-spec-ready-flip --preamble 2>/dev/null)
printf '%s\n' "$OUT" | grep -qx 'PLANWRIGHT_STEP_PR_NUMBER=' \
  && printf '%s\n' "$OUT" | grep -qx 'PLANWRIGHT_STEP_TASK_IDS=' \
  && printf '%s\n' "$OUT" | grep -qx 'PLANWRIGHT_STEP_POINT=pre-spec-ready-flip' \
  && [ "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')" = 12 ]
verdict "REQ-A1.4: an absent context value renders as the empty string" "absent context value: $OUT"
# A value carrying a newline or a control byte is refused on both channels,
# the diagnostic naming the field and never the value.
for mode in --preamble --prefix; do
  rc=0
  err=$(ctx_run PLANWRIGHT_STEP_BRANCH="$(printf 'a\nb')" -- pre-pr "$mode" 2>&1 >/dev/null) || rc=$?
  if ! { [ "$rc" = 6 ] && printf '%s' "$err" | grep -q 'PLANWRIGHT_STEP_BRANCH'; }; then
    fail "$mode: newline in a context value: rc=$rc err='$err' (want 6 naming the field)"
  fi
  rc=0
  err=$(ctx_run PLANWRIGHT_STEP_SPEC="$(printf 'secretish\033[31m')" -- pre-pr "$mode" 2>&1 >/dev/null) || rc=$?
  if ! { [ "$rc" = 6 ] && printf '%s' "$err" | grep -q 'PLANWRIGHT_STEP_SPEC' && ! printf '%s' "$err" | grep -q 'secretish'; }; then
    fail "$mode: control byte in a context value: rc=$rc err='$err'"
  fi
done
ok "REQ-A1.4: a context value carrying a newline or control byte is refused (exit 6) naming the field, never the value"
rc=0
ctx_run PLANWRIGHT_STEP_UNIT_KIND=widget -- pre-pr --preamble >/dev/null 2>&1 || rc=$?
[ "$rc" = 6 ]
verdict "a unit kind outside task/spec/flight is refused" "bad unit kind: rc=$rc"
rc=0
ctx_run PLANWRIGHT_STEP_TASK_IDS='2 x' -- pre-pr --preamble >/dev/null 2>&1 || rc=$?
[ "$rc" = 6 ]
verdict "a task id outside the task-id grammar is refused" "bad task id: rc=$rc"
for ids in '   ' '2  3' ' 2' '2 '; do
  rc=0
  ctx_run PLANWRIGHT_STEP_TASK_IDS="$ids" -- pre-pr --preamble >/dev/null 2>&1 || rc=$?
  [ "$rc" = 6 ] || fail "task ids '$ids' not joined by single spaces should be refused: rc=$rc"
done
ok "task ids not joined by single spaces are refused"
rc=0
ctx_run PLANWRIGHT_STEP_PR_NUMBER='12a' -- pre-pr --prefix >/dev/null 2>&1 || rc=$?
[ "$rc" = 6 ]
verdict "a non-numeric PR number is refused on the prefix channel too" "bad PR number: rc=$rc"
rc=0
out=$(cd "$tmp/sub" && ctx_run PLANWRIGHT_STEP_TASK_IDS='*' -- pre-pr --preamble 2>/dev/null) || rc=$?
[ "$rc" = 6 ]
verdict "a glob in the task ids is judged as written, never expanded" "glob task id: rc=$rc out='$out'"

# =============================================================================
# 14. Output contract: newline-terminated, deterministic, explain columns.
# =============================================================================
reset_layers
printf 'steps_pre_pr: [polish, self-review]\n' >"$tracked_cfg"
run pre-pr --unattended >"$tmp/out.txt" 2>/dev/null
[ "$(tail -c1 "$tmp/out.txt" | wc -l | tr -d ' ')" = 1 ]
verdict "REQ-H1.3: the emitted stream is newline-terminated" "output not newline-terminated"
a=$(run pre-pr --unattended --explain 2>/dev/null)
b=$(run pre-pr --unattended --explain 2>/dev/null)
[ "$a" = "$b" ]
verdict "resolution is deterministic across runs" "non-deterministic output"
cols=$(printf '%s\n' "$a" | head -1 | awk -F '\t' '{ print NF }')
[ "$cols" = 13 ]
verdict "REQ-C1.2: --explain lines carry the pinned thirteen tab-separated columns" "explain columns: got $cols"
printf '%s\n' "$a" | head -1 | grep -q "^run${TAB}polish${TAB}pre-pr${TAB}repo-tracked${TAB}core${TAB}polish${TAB}isolated${TAB}skill${TAB}--nested${TAB}halt${TAB}-${TAB}-${TAB}$core/skills/polish/SKILL.md\$"
verdict "REQ-C1.2: provenance carries point, id, list layer, entry layer, target, and hosting" "explain row: $(printf '%s\n' "$a" | head -1)"

if [ "$failures" -ne 0 ]; then
  echo "FAIL: resolve-steps ($failures failure(s))" >&2
  exit 1
fi
echo "PASS: resolve-steps"
