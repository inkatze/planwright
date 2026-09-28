#!/bin/bash
# Cross-copy test of the reserved-control spellings (REQ-G1.1, REQ-F1.5).
#
# Every line of tests/fixtures/reserved-control-spellings is driven through
# each copy of the reserved-control refusal the repository ships: the tower
# queue's reserved-control check (`tower-queue.sh match`), the ready-guard,
# the worker and tower command guards, and the worker and tower deny profiles
# (through the permission-matcher model). The test fails on any copy whose
# verdict differs from the line's, on a line that claims a copy is outside its
# jurisdiction when the wiring says otherwise, and on a malformed line.
#
# The ready-guard runs against a pull request it cannot read (`gh pr view`
# fails), so its verdict measures recognition: a spelling it takes for a flip
# is denied fail-closed, and anything else defers.
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
WORKER_SETTINGS="$REPO_ROOT/config/worker-settings.json"
TOWER_SETTINGS="$REPO_ROOT/config/tower-settings.json"
HOOKS_JSON="$REPO_ROOT/hooks/hooks.json"

# shellcheck source=tests/lib/ready-guard-harness.sh
. "$REPO_ROOT/tests/lib/ready-guard-harness.sh"
# shellcheck source=tests/lib/permission-matcher.sh
. "$REPO_ROOT/tests/lib/permission-matcher.sh"

for f in "$FIXTURE" "$TQ" "$WORKER_GUARD" "$TOWER_GUARD" "$WORKER_SETTINGS" "$TOWER_SETTINGS" "$HOOKS_JSON"; do
  if [ ! -f "$f" ]; then
    echo "FAIL: missing $f" >&2
    exit 1
  fi
done

RC_ACTS="pr-merge flip undo-flip force-push protected-push base-merge amend squash fixup rebase"
RC_COPIES="queue ready wguard tguard wprof tprof"

# rc_parse_line <line> — split a fixture line into RC_ACT, RC_TIER, RC_POLICY,
# RC_VERDICTS (six words, in RC_COPIES order) and RC_SPELL, and check every
# column. On a malformed line, return 1 with RC_ERR saying why.
rc_parse_line() {
  local q r wg tg wp tp v deny_seen=0
  RC_ERR=""
  RC_ACT="" RC_TIER="" RC_POLICY="" RC_SPELL=""
  read -r RC_ACT RC_TIER RC_POLICY q r wg tg wp tp RC_SPELL <<EOF
$1
EOF
  RC_VERDICTS="$q $r $wg $tg $wp $tp"
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
  if [ "$RC_POLICY" != floor ] && ! [[ $RC_POLICY =~ ^[a-z_]+=[a-z-]+$ ]]; then
    RC_ERR="policy '$RC_POLICY' is neither floor nor <knob>=<value>"
    return 1
  fi
  for v in $q $r $wg $tg $wp $tp; do
    case "$v" in
      deny)
        deny_seen=1
        ;;
      defer | n/a) ;;
      *)
        RC_ERR="verdict '$v' is not deny, defer, or n/a (a column is missing or misplaced)"
        return 1
        ;;
    esac
  done
  case "$RC_SPELL" in
    'git '* | 'gh '* | mcp__*) ;;
    *)
      RC_ERR="spelling '$RC_SPELL' is not a git, gh, or MCP call (a column is missing or misplaced)"
      return 1
      ;;
  esac
  if [ "$RC_POLICY" = floor ]; then
    if [ "$RC_TIER" != any ] || [ "$wp" != deny ] || [ "$tp" != deny ]; then
      RC_ERR="a floor line must be tier any and denied by both profiles"
      return 1
    fi
    if [ "$q" = defer ]; then
      RC_ERR="a floor line the tower queue screens must be denied by it"
      return 1
    fi
  fi
  case "$RC_POLICY" in
    *=unresolved)
      if [ "$deny_seen" = 0 ]; then
        RC_ERR="an unresolved policy line must be denied by some copy"
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
  # shellcheck disable=SC2086 # the six verdict words, split on purpose
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

GOOD='pr-merge any floor deny defer defer defer deny deny gh pr merge 42'
if rc_parse_line "$GOOD"; then
  pass "a complete line parses"
else
  fail "a complete line was rejected: $RC_ERR"
fi
while IFS='|' read -r label bad; do
  [ -n "$label" ] || continue
  if rc_parse_line "$bad"; then
    fail "the parser accepted a line with $label: '$bad'"
  else
    pass "the parser rejects a line with $label ($RC_ERR)"
  fi
done <<'EOF'
a verdict column missing|pr-merge any floor deny defer defer defer deny gh pr merge 42
the policy column missing|pr-merge any deny defer defer defer deny deny gh pr merge 42
only the leading columns|pr-merge any floor deny defer defer defer deny deny
an unknown verdict|pr-merge any floor deny defer allow defer deny deny gh pr merge 42
an unknown act|merge-ish any floor deny defer defer defer deny deny gh pr merge 42
an unknown tier|pr-merge human floor deny defer defer defer deny deny gh pr merge 42
a floor line a profile defers|pr-merge any floor deny defer defer defer defer deny gh pr merge 42
a floor line the queue defers|pr-merge any floor defer defer defer defer deny deny gh pr merge 42
a floor line scoped to one tier|pr-merge worker floor n/a defer defer n/a deny n/a gh pr merge 42
an unresolved line nothing denies|base-merge worker worker_base_merge=unresolved n/a defer defer n/a defer n/a git merge origin/main
EOF

rc_parse_line 'base-merge worker worker_base_merge=unresolved defer defer defer n/a deny n/a git merge origin/main' || true
rc_jurisdiction_mismatch
if [ "$RC_MISMATCH" = queue ]; then
  pass "a line that runs a copy outside its tier is caught"
else
  fail "a worker line naming a tower-queue verdict was not caught (got '$RC_MISMATCH')"
fi
rc_parse_line 'pr-merge any floor deny defer defer defer deny deny mcp__github__merge_pull_request' || true
rc_jurisdiction_mismatch
if [ "$RC_MISMATCH" = "queue ready wguard tguard" ]; then
  pass "an MCP line that claims verdicts from Bash-only copies is caught"
else
  fail "an MCP line claiming Bash-only verdicts was not caught (got '$RC_MISMATCH')"
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

dups=$(printf '%s\n' "${LINES[@]+"${LINES[@]}"}" | awk '{ k = $2; for (i = 10; i <= NF; i++) k = k " " $i; if (seen[k]++) print k }')
if [ -z "$dups" ]; then
  pass "no spelling appears twice for one tier"
else
  fail "duplicate tier and spelling: $dups"
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
for needle in 'git pull' ' master' ':master' 'planwright/human-gates/spec' ' +' 'mcp__github__merge_pull_request' 'mcp__github__update_pull_request'; do
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

ready_verdict() {
  local spell=$1 tool surface payload
  tool=$(tool_of "$spell")
  surface=$(jq -r --arg t "$tool" \
    '[.hooks.PreToolUse[]? | select(.matcher == $t) | .hooks[]?.command // "" | select(contains("ready-guard.sh"))][0] | split(" ") | last' \
    "$HOOKS_JSON")
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

# --- the deny profiles -------------------------------------------------------

read_rules() { jq -r --arg k "$2" '.permissions[$k] // [] | .[]' "$1"; }

# profile_verdicts <settings-json> — fill PROFILE_V[i] for every fixture line.
# An MCP call is denied by an entry naming the tool or its whole server; a Bash
# call goes through the matcher model.
PROFILE_V=()
profile_verdicts() {
  local settings=$1 i spell tool server rc=0
  pm_load_rules "$(read_rules "$settings" deny)" "$(read_rules "$settings" ask)" \
    "$(read_rules "$settings" allow)" || rc=$?
  if [ "$rc" != 0 ]; then
    fail "$(basename "$settings") did not load into the matcher model (rc $rc)"
    return 1
  fi
  PROFILE_V=()
  i=0
  while [ "$i" -lt "$N" ]; do
    rc_parse_line "${LINES[$i]}" || true
    spell=$RC_SPELL
    tool=$(tool_of "$spell")
    if [ "$tool" = Bash ]; then
      if [ "$(pm_decide "$spell")" = deny ]; then PROFILE_V[i]=deny; else PROFILE_V[i]=defer; fi
    else
      server=${tool%__*}
      if jq -e --arg t "$tool" --arg s "$server" '.permissions.deny // [] | any(. == $t or . == $s)' \
        "$settings" >/dev/null; then
        PROFILE_V[i]=deny
      else
        PROFILE_V[i]=defer
      fi
    fi
    i=$((i + 1))
  done
}

WPROF_V=()
TPROF_V=()
if profile_verdicts "$WORKER_SETTINGS"; then
  WPROF_V=(${PROFILE_V[@]+"${PROFILE_V[@]}"})
fi
if profile_verdicts "$TOWER_SETTINGS"; then
  TPROF_V=(${PROFILE_V[@]+"${PROFILE_V[@]}"})
fi

# --- drive every line through every copy -------------------------------------

# drive_copy <copy> — write one verdict per fixture line to that copy's file,
# `n/a` where the line puts the copy outside its jurisdiction. The hook copies
# are process-bound, so each runs as its own background job.
drive_copy() {
  local copy=$1 i=0 want c got
  while [ "$i" -lt "$N" ]; do
    rc_parse_line "${LINES[$i]}" || true
    want=""
    # shellcheck disable=SC2086 # the six verdict words, split on purpose
    set -- $RC_VERDICTS
    for c in $RC_COPIES; do
      [ "$c" != "$copy" ] || want=$1
      shift
    done
    if [ "$want" = n/a ]; then
      got=n/a
    else
      case "$copy" in
        queue) got=$(queue_verdict "$RC_SPELL") ;;
        ready) got=$(ready_verdict "$RC_SPELL") ;;
        wguard) got=$(guard_verdict "$WORKER_GUARD" "$RC_SPELL") ;;
        tguard) got=$(guard_verdict "$TOWER_GUARD" "$RC_SPELL") ;;
        wprof) got=${WPROF_V[$i]:-unevaluated} ;;
        tprof) got=${TPROF_V[$i]:-unevaluated} ;;
      esac
    fi
    printf '%s\n' "${got:-empty}"
    i=$((i + 1))
  done >"$SANDBOX/verdicts.$copy"
}

for copy in queue ready wguard tguard; do
  drive_copy "$copy" &
done
drive_copy wprof
drive_copy tprof
wait

for copy in $RC_COPIES; do
  i=0
  while IFS= read -r got; do
    rc_parse_line "${LINES[$i]}" || true
    # shellcheck disable=SC2086 # the six verdict words, split on purpose
    set -- $RC_VERDICTS
    for c in $RC_COPIES; do
      [ "$c" != "$copy" ] || want=$1
      shift
    done
    if [ "$want" != n/a ]; then
      if [ "$got" = "$want" ]; then
        pass "[$RC_TIER] $copy $want: $RC_SPELL"
      else
        fail "[$RC_TIER] $copy expected $want, got $got: $RC_SPELL"
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
