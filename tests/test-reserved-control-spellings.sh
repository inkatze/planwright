#!/bin/bash
# Cross-copy test of the reserved-control spellings (REQ-G1.1, REQ-F1.5).
#
# Every line of tests/fixtures/reserved-control-spellings is driven through
# the tower queue's reserved-control check (`tower-queue.sh match`), the
# ready-guard, the worker and tower command guards, the policy guard, and the
# worker and tower deny profiles (through the permission-matcher model). The
# githooks/ backstop is not one of the copies driven here. The test fails on any
# copy whose verdict differs from the line's, on a line that claims a copy is
# outside its jurisdiction when the wiring says otherwise, and on a malformed
# line.
#
# The ready-guard runs against a pull request it cannot read (`gh pr view`
# fails), so its verdict measures recognition: a spelling it takes for a flip
# is denied fail-closed, and anything else defers. The policy guard runs with
# the tier and surface its wiring passes, the line's policy value in a
# machine-local config layer, against sandbox repositories (the fixture
# header describes them); a tier-`any` line runs it under both tiers.
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
set -u
unset CDPATH
LC_ALL=C
export LC_ALL

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FIXTURE="$REPO_ROOT/tests/fixtures/reserved-control-spellings"
TQ="$REPO_ROOT/scripts/tower-queue.sh"
WORKER_GUARD="$REPO_ROOT/scripts/worker-command-guard.sh"
TOWER_GUARD="$REPO_ROOT/scripts/tower-command-guard.sh"
POLICY_GUARD="$REPO_ROOT/scripts/policy-guard.sh"
WORKER_SETTINGS="$REPO_ROOT/config/worker-settings.json"
TOWER_SETTINGS="$REPO_ROOT/config/tower-settings.json"
HOOKS_JSON="$REPO_ROOT/hooks/hooks.json"

# shellcheck source=tests/lib/ready-guard-harness.sh
. "$REPO_ROOT/tests/lib/ready-guard-harness.sh"
# shellcheck source=tests/lib/permission-matcher.sh
. "$REPO_ROOT/tests/lib/permission-matcher.sh"

for f in "$FIXTURE" "$TQ" "$WORKER_GUARD" "$TOWER_GUARD" "$POLICY_GUARD" "$WORKER_SETTINGS" "$TOWER_SETTINGS" "$HOOKS_JSON"; do
  if [ ! -f "$f" ]; then
    echo "FAIL: missing $f" >&2
    exit 1
  fi
done

RC_ACTS="pr-merge flip undo-flip force-push protected-push base-merge amend squash fixup rebase opaque other"
RC_COPIES="queue ready wguard tguard pguard wprof tprof"
# The knobs a policy line may name, each with its legal values.
RC_KNOBS="ready_flip_policy=human,unit-owner worker_base_merge=allow,deny unpushed_rewrite=allow,deny"

# rc_parse_line <line> — split a fixture line into RC_ACT, RC_TIER, RC_POLICY,
# RC_VERDICTS (seven words, in RC_COPIES order) and RC_SPELL, and check every
# column. On a malformed line, return 1 with RC_ERR saying why.
rc_parse_line() {
  local q r wg tg pg wp tp v knob val legal
  RC_ERR=""
  RC_ACT="" RC_TIER="" RC_POLICY="" RC_SPELL=""
  read -r RC_ACT RC_TIER RC_POLICY q r wg tg pg wp tp RC_SPELL <<EOF
$1
EOF
  RC_VERDICTS="$q $r $wg $tg $pg $wp $tp"
  if [ -z "$RC_SPELL" ]; then
    RC_ERR="missing a column"
    return 1
  fi
  case " $RC_ACTS " in
    *" $RC_ACT "*) ;;
    *)
      RC_ERR="unknown act '$RC_ACT'"
      return 1
      ;;
  esac
  case "$RC_TIER" in
    any | worker | tower) ;;
    *)
      RC_ERR="unknown tier '$RC_TIER'"
      return 1
      ;;
  esac
  case "$RC_POLICY" in
    floor | floor-guard) ;;
    *=*)
      knob=${RC_POLICY%%=*}
      val=${RC_POLICY#*=}
      legal=''
      for v in $RC_KNOBS; do
        [ "${v%%=*}" != "$knob" ] || legal=${v#*=}
      done
      case ",$legal," in
        ,,)
          RC_ERR="policy '$RC_POLICY' names a knob the policy guard does not read"
          return 1
          ;;
        *",$val,"*) ;;
        *)
          RC_ERR="policy '$RC_POLICY' names a value $knob does not take"
          return 1
          ;;
      esac
      ;;
    *)
      RC_ERR="policy '$RC_POLICY' is neither floor, floor-guard, nor <knob>=<value>"
      return 1
      ;;
  esac
  for v in $q $r $wg $tg $pg $wp $tp; do
    case "$v" in
      deny | defer | prompt | n/a) ;;
      *)
        RC_ERR="verdict '$v' is not deny, defer, prompt, or n/a (a column is missing or misplaced)"
        return 1
        ;;
    esac
  done
  for v in $q $r $wg $tg $pg; do
    if [ "$v" = prompt ]; then
      RC_ERR="only a profile column can expect prompt"
      return 1
    fi
  done
  case "$RC_SPELL" in
    'git '* | 'gh '* | 'bash '* | 'env '* | mcp__*) ;;
    *)
      RC_ERR="spelling '$RC_SPELL' is not a git, gh, wrapped gh, or MCP call (a column is missing or misplaced)"
      return 1
      ;;
  esac
  case "$RC_ACT" in
    opaque | other)
      if [ "$RC_POLICY" != floor-guard ]; then
        RC_ERR="an $RC_ACT line is a gh api line, so its policy is floor-guard"
        return 1
      fi
      ;;
  esac
  case "$RC_POLICY" in
    floor)
      if [ "$RC_TIER" != any ] || [ "$wp" != deny ] || [ "$tp" != deny ]; then
        RC_ERR="a floor line must be tier any and denied by both profiles"
        return 1
      fi
      if [ "$q" = defer ] || [ "$pg" = defer ]; then
        RC_ERR="a floor line the tower queue or the policy guard screens must be denied by it"
        return 1
      fi
      ;;
    # The profiles leave the call at the permission prompt by operator
    # decision; the policy guard is the refusing layer.
    floor-guard)
      for v in $wp $tp; do
        if [ "$v" != prompt ] && [ "$v" != n/a ]; then
          RC_ERR="a floor-guard line must expect prompt from every profile that sees it"
          return 1
        fi
      done
      if [ "$RC_ACT" = other ] && [ "$pg" != defer ] && [ "$pg" != n/a ]; then
        RC_ERR="an other line is outside the reserved acts, so the policy guard defers it"
        return 1
      fi
      if [ "$RC_ACT" != other ] && [ "$pg" != deny ] && [ "$pg" != n/a ]; then
        RC_ERR="a floor-guard line must be denied by the policy guard"
        return 1
      fi
      ;;
  esac
  return 0
}

# wired <settings-json> <tool> <script> — 0 when the file wires the script on
# a PreToolUse matcher naming exactly that tool. Answers are cached, since the
# same few questions are asked for every line.
WIRED_CACHE=""
wired() {
  local key="<$1|$2|$3="
  case "$WIRED_CACHE" in
    *"${key}1>"*) return 0 ;;
    *"${key}0>"*) return 1 ;;
  esac
  if jq -e --arg t "$2" --arg s "$3" \
    '[.hooks.PreToolUse[]? | select(.matcher == $t) | .hooks[]?.command // "" | select(contains($s))] | length > 0' \
    "$1" >/dev/null 2>&1; then
    WIRED_CACHE="$WIRED_CACHE${key}1>"
    return 0
  fi
  WIRED_CACHE="$WIRED_CACHE${key}0>"
  return 1
}

tier_has() { [ "$1" = any ] || [ "$1" = "$2" ]; }

tool_of() {
  case "$1" in
    mcp__*) printf '%s' "${1%% *}" ;;
    *) printf 'Bash' ;;
  esac
}

# rc_jurisdiction <copy> <tier> <tool> — 0 when the copy sees this call.
rc_jurisdiction() {
  case "$1" in
    queue) tier_has "$2" tower && [ "$3" = Bash ] ;;
    ready) wired "$HOOKS_JSON" "$3" ready-guard.sh ;;
    wguard) tier_has "$2" worker && wired "$WORKER_SETTINGS" "$3" worker-command-guard.sh ;;
    tguard) tier_has "$2" tower && wired "$TOWER_SETTINGS" "$3" tower-command-guard.sh ;;
    pguard)
      { tier_has "$2" worker && wired "$WORKER_SETTINGS" "$3" policy-guard.sh; } \
        || { tier_has "$2" tower && wired "$TOWER_SETTINGS" "$3" policy-guard.sh; }
      ;;
    wprof) tier_has "$2" worker ;;
    tprof) tier_has "$2" tower ;;
    *) return 1 ;;
  esac
}

# rc_jurisdiction_mismatch — set RC_MISMATCH to each copy whose n/a column
# disagrees with the wiring for the parsed line, empty when they agree.
rc_jurisdiction_mismatch() {
  local tool copy v out=""
  tool=$(tool_of "$RC_SPELL")
  # shellcheck disable=SC2086 # the verdict words, split on purpose
  set -- $RC_VERDICTS
  for copy in $RC_COPIES; do
    v=$1
    shift
    if rc_jurisdiction "$copy" "$RC_TIER" "$tool"; then
      [ "$v" != n/a ] || out="$out $copy"
    else
      [ "$v" = n/a ] || out="$out $copy"
    fi
  done
  RC_MISMATCH=${out# }
}

# hook_verdict <stdout> — deny, defer, or what the hook emitted instead.
hook_verdict() {
  local d
  if [ -z "$(printf '%s' "$1" | tr -d '[:space:]')" ]; then
    printf 'defer'
    return
  fi
  d=$(printf '%s' "$1" | jq -r '.hookSpecificOutput.permissionDecision // "unparsed"' 2>/dev/null) || d=unparsed
  printf '%s' "$d"
}

# --- the parser rejects a malformed line ------------------------------------

GOOD='pr-merge any floor deny defer defer defer deny deny deny gh pr merge 42'
for good in "$GOOD" \
  'opaque worker floor-guard n/a defer defer n/a deny prompt n/a gh api graphql -F query=@q.graphql' \
  'other tower floor-guard defer defer n/a defer defer n/a prompt gh api graphql -f query=x' \
  'base-merge worker worker_base_merge=allow n/a defer defer n/a defer defer n/a git merge origin/main'; do
  if rc_parse_line "$good"; then
    pass "a complete line parses: $good"
  else
    fail "a complete line was rejected: $RC_ERR ($good)"
  fi
done
while IFS='|' read -r label bad; do
  [ -n "$label" ] || continue
  if rc_parse_line "$bad"; then
    fail "the parser accepted a line with $label: '$bad'"
  else
    pass "the parser rejects a line with $label ($RC_ERR)"
  fi
done <<'EOF'
a verdict column missing|pr-merge any floor deny defer defer defer deny deny gh pr merge 42
the policy column missing|pr-merge any deny defer defer defer deny deny deny gh pr merge 42
only the leading columns|pr-merge any floor deny defer defer defer deny deny deny
an unknown verdict|pr-merge any floor deny defer allow defer deny deny deny gh pr merge 42
an unknown act|merge-ish any floor deny defer defer defer deny deny deny gh pr merge 42
an unknown tier|pr-merge human floor deny defer defer defer deny deny deny gh pr merge 42
a floor line a profile defers|pr-merge any floor deny defer defer defer deny defer deny gh pr merge 42
a floor line the queue defers|pr-merge any floor defer defer defer defer deny deny deny gh pr merge 42
a floor line the policy guard defers|pr-merge any floor deny defer defer defer defer deny deny gh pr merge 42
a floor line scoped to one tier|pr-merge worker floor n/a defer defer n/a deny deny n/a gh pr merge 42
a knob the guard does not read|base-merge worker merge_policy=human n/a defer defer n/a deny defer n/a git merge origin/main
a value the knob does not take|base-merge worker worker_base_merge=unresolved n/a defer defer n/a deny defer n/a git merge origin/main
the retired prompt token|flip tower gh_api_write=prompt deny defer n/a defer deny n/a prompt gh api graphql -F query=@q.graphql
a prompt verdict outside a profile column|flip tower floor-guard prompt defer n/a defer deny n/a prompt gh api graphql -F query=@q.graphql
a prompt verdict in the policy-guard column|flip tower floor-guard deny defer n/a defer prompt n/a prompt gh api graphql -F query=@q.graphql
a floor-guard line a profile only defers|flip tower floor-guard deny defer n/a defer deny n/a defer gh api graphql -F query=@q.graphql
a floor-guard line a profile denies|flip worker floor-guard n/a defer defer n/a deny deny n/a gh api graphql -F query=@q.graphql
a floor-guard line the policy guard defers|opaque worker floor-guard n/a defer defer n/a defer prompt n/a gh api graphql -F query=@q.graphql
an other line the policy guard denies|other worker floor-guard n/a defer defer n/a deny prompt n/a gh api graphql -f query=x
an opaque line under a knob|opaque worker ready_flip_policy=human n/a defer defer n/a deny prompt n/a gh api graphql -F query=@q.graphql
EOF

rc_parse_line 'base-merge worker worker_base_merge=allow defer defer defer n/a defer defer n/a git merge origin/main' || true
rc_jurisdiction_mismatch
if [ "$RC_MISMATCH" = queue ]; then
  pass "a line that runs a copy outside its tier is caught"
else
  fail "a worker line naming a tower-queue verdict was not caught (got '$RC_MISMATCH')"
fi
rc_parse_line 'pr-merge any floor deny defer defer defer deny deny deny mcp__github__merge_pull_request' || true
rc_jurisdiction_mismatch
if [ "$RC_MISMATCH" = "queue ready wguard tguard pguard" ]; then
  pass "an MCP line that claims verdicts from copies not wired for it is caught"
else
  fail "an MCP line claiming verdicts from unwired copies was not caught (got '$RC_MISMATCH')"
fi

# --- read the fixture --------------------------------------------------------

N=0
LINES=()
lineno=0
while IFS= read -r raw || [ -n "$raw" ]; do
  lineno=$((lineno + 1))
  case "$raw" in
    '' | '#'*) continue ;;
  esac
  if ! rc_parse_line "$raw"; then
    fail "fixture line $lineno: $RC_ERR"
    continue
  fi
  rc_jurisdiction_mismatch
  if [ -n "$RC_MISMATCH" ]; then
    fail "fixture line $lineno: the n/a columns disagree with the wiring for: $RC_MISMATCH ($RC_SPELL)"
    continue
  fi
  LINES[N]=$raw
  N=$((N + 1))
done <"$FIXTURE"

if [ "$N" -gt 0 ]; then
  pass "the fixture parsed: $N lines"
else
  fail "the fixture has no usable lines"
fi

dups=$(printf '%s\n' "${LINES[@]+"${LINES[@]}"}" | awk '{ k = $2 " " $3; for (i = 11; i <= NF; i++) k = k " " $i; if (seen[k]++) print k }')
if [ -z "$dups" ]; then
  pass "no spelling appears twice for one tier and policy value"
else
  fail "duplicate tier, policy, and spelling: $dups"
fi

# The acts the requirement names, each present at least once, plus the
# spellings a narrower fixture would most plausibly drop.
all=$(printf '%s\n' "${LINES[@]+"${LINES[@]}"}")
for act in $RC_ACTS; do
  if printf '%s\n' "$all" | awk -v a="$act" '$1 == a { f = 1 } END { exit !f }'; then
    pass "the fixture covers the act $act"
  else
    fail "the fixture has no line for the act $act"
  fi
done
# shellcheck disable=SC2016 # the unexpanded $ forms are spellings to find
for needle in 'git pull' ' master' ':master' 'planwright/human-gates/spec' ' +' 'mcp__github__merge_pull_request' 'mcp__github__update_pull_request' \
  'git -C . ' 'gh api graphql' 'git commit --amen' 'markPullRequestReadyForReview' 'convertPullRequestToDraft' \
  'mergePullRequest' 'gh api -X PUT' 'gh api --method PUT' 'query=@' \
  'enablePullRequestAutoMerge' 'enqueuePullRequest' 'mergeBranch' 'updatePullRequestBranch' '/merges ' \
  '/update-branch' '-XPUT https://' '--method=PUT /repos/' 'force=true' 'git/refs/heads/main' 'contents/' \
  'query=@-' 'x=@file' '--field query=' '--input' 'gh api "$EP"' 'query="$Q"' 'query="$(' '{branch}' \
  '--frobnicate' 'bash -c ' 'env gh api' ' && gh api' 'resolveReviewThread' 'requested_reviewers'; do
  if printf '%s\n' "$all" | grep -qF -- "$needle"; then
    pass "the fixture carries a '$needle' spelling"
  else
    fail "the fixture carries no '$needle' spelling"
  fi
done

# --- the tower queue ---------------------------------------------------------

QHOME="$SANDBOX/fleet-home"
mkdir -p "$QHOME" "$SANDBOX/adopter"
chmod 0700 "$QHOME"
: >"$SANDBOX/local.yml"
QERR="$SANDBOX/queue.err"

tq() {
  PLANWRIGHT_FLEET_STATE_DIR="$QHOME" \
    PLANWRIGHT_ADOPTER_OVERLAY="$SANDBOX/adopter" \
    PLANWRIGHT_REPO_ROOT="$SANDBOX" \
    PLANWRIGHT_LOCAL_CONFIG="$SANDBOX/local.yml" \
    /bin/sh "$TQ" "$@" 2>"$QERR"
}

# A rule covering every git and gh command, so the only thing that can keep a
# spelling from matching it is the reserved-control screen.
QRULE=""
if qout=$(tq capture --kind standing --text 'let the tower answer any git or gh command' \
  --covers-command 'git ' --covers-command 'gh ' --now 1000); then
  QRULE=$(printf '%s' "$qout" | cut -f2)
fi
if [ -n "$QRULE" ]; then
  pass "the tower queue captured a rule covering git and gh"
else
  fail "the tower queue refused the covering rule: $(cat "$QERR")"
fi

queue_verdict() {
  local out rc=0
  out=$(tq match --decision "$QRULE" --command "$1") || rc=$?
  case "$rc:$out" in
    1:reserved) printf 'deny' ;;
    0:match | 1:no-match) printf 'defer' ;;
    *) printf 'error(%s:%s)' "$rc" "$out" ;;
  esac
}

# --- the ready-guard ---------------------------------------------------------

# The argument the wiring passes the guard for a tool: its surface.
# shellcheck disable=SC2016 # a jq program; $t is jq's variable
READY_SURFACE_Q='[.hooks.PreToolUse[]? | select(.matcher == $t) | .hooks[]?.command // "" | select(contains("ready-guard.sh"))][0] | split(" ") | last'
READY_BASH_SURFACE=$(jq -r --arg t Bash "$READY_SURFACE_Q" "$HOOKS_JSON")

ready_verdict() {
  local spell=$1 tool surface payload
  tool=$(tool_of "$spell")
  case "$tool" in
    Bash) surface=$READY_BASH_SURFACE ;;
    *) surface=$(jq -r --arg t "$tool" "$READY_SURFACE_Q" "$HOOKS_JSON") ;;
  esac
  if [ "$tool" = Bash ]; then
    payload=$(bash_payload "$spell")
  else
    payload=$(jq -n --arg t "$tool" \
      '{tool_name:$t, tool_input:{owner:"acme", repo:"widgets", pullNumber:42, draft:false}}')
  fi
  reset_stub_env
  STUB_VIEW_JSON=$VIEW_CONFORMING STUB_VIEW_RC=1
  RG_SURFACE=$surface run_hook "$payload"
  if [ "$CODE" != 0 ]; then
    printf 'exit-%s' "$CODE"
    return
  fi
  hook_verdict "$OUT"
}

# --- the command guards ------------------------------------------------------

mkdir -p "$SANDBOX/repo/scripts" "$SANDBOX/no-home"
: >"$SANDBOX/repo/.git"

guard_verdict() {
  local hook=$1 spell=$2 payload out rc=0
  payload=$(jq -n --arg c "$spell" --arg w "$SANDBOX/repo" \
    '{tool_name:"Bash", tool_input:{command:$c}, cwd:$w}')
  out=$(printf '%s' "$payload" | env -u CLAUDE_DIR HOME="$SANDBOX/no-home" \
    CLAUDE_PLUGIN_ROOT="$REPO_ROOT" /bin/bash "$hook" 2>/dev/null) || rc=$?
  if [ "$rc" != 0 ]; then
    printf 'exit-%s' "$rc"
    return
  fi
  hook_verdict "$out"
}

# Every fixture line expects the allow-only guards to defer, and a guard that
# never ran defers too; a known-safe command must come back allowed first.
for hook in "$WORKER_GUARD" "$TOWER_GUARD"; do
  got=$(guard_verdict "$hook" 'git status')
  if [ "$got" = allow ]; then
    pass "$(basename "$hook") allows git status, so its defers below are its own"
  else
    fail "$(basename "$hook") did not allow git status (got $got); its defer verdicts would be vacuous"
  fi
done

# --- the policy guard --------------------------------------------------------

# The sandbox the fixture header describes: a bare origin carrying main, the
# unit's task branch, and a sibling task branch; the unit clone on its task
# branch with one pushed commit and three unpushed ones. The operator's global
# and system git config are cut off, since the guard reads git config.
PG="$SANDBOX/pg"
PG_UNIT="$PG/unit"
mkdir -p "$PG/adopter"
pg_git() {
  GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 git -c init.defaultBranch=main \
    -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false "$@" >/dev/null 2>&1
}
pg_git init --bare "$PG/origin.git"
pg_git init "$PG/seed"
pg_git -C "$PG/seed" commit --allow-empty -m base
pg_git -C "$PG/seed" push "$PG/origin.git" main
for b in planwright/demo/task-1 planwright/demo/task-2; do
  pg_git -C "$PG/seed" switch -c "$b" main
  pg_git -C "$PG/seed" commit --allow-empty -m "pushed on $b"
  pg_git -C "$PG/seed" push "$PG/origin.git" "$b"
done
pg_git clone "$PG/origin.git" "$PG_UNIT"
pg_git -C "$PG_UNIT" switch planwright/demo/task-1
pg_git -C "$PG_UNIT" remote set-head origin main
for n in 1 2 3; do pg_git -C "$PG_UNIT" commit --allow-empty -m "unpushed $n"; done
if [ "$(GIT_CONFIG_GLOBAL=/dev/null git -C "$PG_UNIT" rev-list --count HEAD --not --remotes 2>/dev/null)" = 3 ]; then
  pass "the policy-guard sandbox carries three unpushed commits on the unit branch"
else
  fail "the policy-guard sandbox was not built; its verdicts below would be about nothing"
fi

# The tier and surface the wiring passes the guard for a tool, as
# "<tier> <surface>", from the profile that wires it for that tier.
pg_wiring_args() { # <settings-json> <tool>
  jq -r --arg t "$2" '[.hooks.PreToolUse[]? | select(.matcher == $t) | .hooks[]?.command // "" | select(contains("policy-guard.sh"))][0] // "" | split("policy-guard.sh ") | .[1] // ""' "$1"
}

# pg_run <tier-args> <spelling> <policy> — one guard verdict.
pg_run() {
  local args=$1 spell=$2 policy=$3 tool payload out rc=0
  tool=$(tool_of "$spell")
  case $policy in
    *=*) printf '%s: %s\n' "${policy%%=*}" "${policy#*=}" >"$PG/local.yml" ;;
    *) : >"$PG/local.yml" ;;
  esac
  if [ "$tool" = Bash ]; then
    payload=$(jq -n --arg c "$spell" --arg w "$PG_UNIT" '{tool_name:"Bash", tool_input:{command:$c}, cwd:$w}')
  else
    payload=$(jq -n --arg t "$tool" --arg w "$PG_UNIT" \
      '{tool_name:$t, tool_input:{owner:"acme", repo:"widgets", pullNumber:42, draft:false}, cwd:$w}')
  fi
  # shellcheck disable=SC2086 # "<tier> <surface>", split on purpose
  out=$(printf '%s' "$payload" | env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 \
    CLAUDE_PROJECT_DIR="$PG_UNIT" PLANWRIGHT_ADOPTER_OVERLAY="$PG/adopter" PLANWRIGHT_REPO_ROOT="$PG_UNIT" \
    PLANWRIGHT_LOCAL_CONFIG="$PG/local.yml" /bin/bash "$POLICY_GUARD" $args 2>/dev/null) || rc=$?
  if [ "$rc" != 0 ]; then
    printf 'exit-%s' "$rc"
    return
  fi
  hook_verdict "$out"
}

# pg_verdict <tier> <spelling> <policy> — the guard's verdict under every tier
# the line names that wires it; a split between tiers is reported as such.
pg_verdict() {
  local tier=$1 spell=$2 policy=$3 tool t settings args v first='' all=''
  tool=$(tool_of "$spell")
  for t in worker tower; do
    tier_has "$tier" "$t" || continue
    case $t in
      worker) settings=$WORKER_SETTINGS ;;
      tower) settings=$TOWER_SETTINGS ;;
    esac
    args=$(pg_wiring_args "$settings" "$tool")
    [ -n "$args" ] || continue
    v=$(pg_run "$args" "$spell" "$policy")
    all="$all $t=$v"
    [ -n "$first" ] || first=$v
    [ "$v" = "$first" ] || first='split'
  done
  if [ "$first" = split ]; then
    printf 'split(%s)' "${all# }"
  else
    printf '%s' "${first:-unwired}"
  fi
}

# --- the deny profiles -------------------------------------------------------

read_rules() { jq -r --arg k "$2" '.permissions[$k] // [] | .[]' "$1"; }

# profile_verdict <settings-json> <spelling> <want> — the loaded profile's
# verdict. An MCP call is denied by an entry naming the tool or its whole
# server; a Bash call goes through the matcher model. Anything short of a deny
# is `defer`, except where the line expects `prompt`: there the model's own
# answer is reported, so an allow or an ask cannot pass for a prompt.
profile_verdict() {
  local settings=$1 spell=$2 want=$3 tool d
  tool=$(tool_of "$spell")
  if [ "$tool" = Bash ]; then
    d=$(pm_decide "$spell")
    if [ "$d" = deny ]; then
      printf 'deny'
    elif [ "$want" = prompt ]; then
      printf '%s' "$d"
    else
      printf 'defer'
    fi
  elif jq -e --arg t "$tool" --arg s "${tool%__*}" '.permissions.deny // [] | any(. == $t or . == $s)' \
    "$settings" >/dev/null; then
    printf 'deny'
  else
    printf 'defer'
  fi
}

# load_profile <settings-json> — load its rules into the matcher model, setting
# LOAD_ERR when they do not load.
load_profile() {
  local rc=0
  pm_load_rules "$(read_rules "$1" deny)" "$(read_rules "$1" ask)" "$(read_rules "$1" allow)" || rc=$?
  LOAD_ERR=""
  [ "$rc" = 0 ] || LOAD_ERR="unloaded-rc-$rc"
}

# --- drive every line through every copy -------------------------------------

# rc_want <copy> — set RC_WANT to the parsed line's verdict for that copy.
rc_want() {
  local copy=$1 c
  RC_WANT=""
  # shellcheck disable=SC2086 # the verdict words, split on purpose
  set -- $RC_VERDICTS
  for c in $RC_COPIES; do
    [ "$c" != "$copy" ] || RC_WANT=$1
    shift
  done
}

# drive_copy <copy> — write one verdict per fixture line to that copy's file,
# `n/a` where the line puts the copy outside its jurisdiction, each verdict
# flattened to one line so the file stays aligned with the fixture.
drive_copy() {
  local copy=$1 i=0 got
  LOAD_ERR=""
  case "$copy" in
    wprof) load_profile "$WORKER_SETTINGS" ;;
    tprof) load_profile "$TOWER_SETTINGS" ;;
  esac
  while [ "$i" -lt "$N" ]; do
    rc_parse_line "${LINES[$i]}" || true
    rc_want "$copy"
    if [ "$RC_WANT" = n/a ]; then
      got=n/a
    elif [ -n "$LOAD_ERR" ]; then
      got=$LOAD_ERR
    else
      case "$copy" in
        queue) got=$(queue_verdict "$RC_SPELL") ;;
        ready) got=$(ready_verdict "$RC_SPELL") ;;
        wguard) got=$(guard_verdict "$WORKER_GUARD" "$RC_SPELL") ;;
        tguard) got=$(guard_verdict "$TOWER_GUARD" "$RC_SPELL") ;;
        pguard) got=$(pg_verdict "$RC_TIER" "$RC_SPELL" "$RC_POLICY") ;;
        wprof) got=$(profile_verdict "$WORKER_SETTINGS" "$RC_SPELL" "$RC_WANT") ;;
        tprof) got=$(profile_verdict "$TOWER_SETTINGS" "$RC_SPELL" "$RC_WANT") ;;
      esac
    fi
    printf '%s\n' "$(printf '%s' "${got:-empty}" | tr '\n' ' ')"
    i=$((i + 1))
  done >"$SANDBOX/verdicts.$copy"
}

# Each hook verdict forks a process, so every copy runs as its own job to
# bound the wall time.
for copy in $RC_COPIES; do
  drive_copy "$copy" &
done
wait

for copy in $RC_COPIES; do
  i=0
  while IFS= read -r got; do
    if [ "$i" -ge "$N" ]; then
      fail "$copy produced a verdict past the last fixture line: $got"
      break
    fi
    rc_parse_line "${LINES[$i]}" || true
    rc_want "$copy"
    if [ "$RC_WANT" != n/a ]; then
      if [ "$got" = "$RC_WANT" ]; then
        pass "[$RC_TIER] $copy $RC_WANT: $RC_SPELL"
      else
        fail "[$RC_TIER] $copy expected $RC_WANT, got $got: $RC_SPELL"
      fi
    fi
    i=$((i + 1))
  done <"$SANDBOX/verdicts.$copy"
  if [ "$i" != "$N" ]; then
    fail "$copy produced $i verdicts for $N lines"
  fi
done

echo
echo "passes: $passes  failures: $failures"
[ "$failures" = 0 ]
