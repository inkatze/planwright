# shellcheck shell=bash
# policy-guard-harness.sh — the shared fixture harness for the policy-guard
# suites (sourced, never executed): tests/test-policy-guard.sh (the git and
# pull-request acts), tests/test-policy-guard-hidden.sh (spellings that hide
# an act, and routine commands that must stay deferred), and
# tests/test-policy-guard-gh-api.sh (the gh api acts).
#
# The guard runs from a sandbox copy of scripts/ whose resolve-policy-knob.sh
# is a stub that logs the knob it was asked for and then runs the real
# resolver, so a case can assert which knobs were read (and that a command
# outside the guard's acts read none). STUB_FAIL_KNOB makes one knob's read
# fail; STUB_SLEEP holds every read past the guard's bound. A `gh` stub logs
# every call; the guard must never make one. Repository state is real git: a
# bare origin and a unit clone on a task branch carrying one pushed commit and
# three unpushed ones; clone_on builds more. The operator's global and system
# git config are cut off, since the guard reads git config.
#
# Sourcing runs setup and installs the only EXIT trap.
set -u
unset CDPATH
LC_ALL=C
export LC_ALL

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REAL_SCRIPTS="$REPO_ROOT/scripts"

passes=0
failures=0
pass() {
  echo "ok: $1"
  passes=$((passes + 1))
}
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}

for t in jq git timeout; do
  command -v "$t" >/dev/null 2>&1 || {
    echo "FAIL: $t is required to run this suite" >&2
    exit 1
  }
done

SANDBOX=$(mktemp -d "${TMPDIR:-/tmp}/policy-guard.XXXXXX") || exit 1
trap 'rm -rf "$SANDBOX"' EXIT
GIT_CONFIG_GLOBAL=/dev/null
GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL GIT_CONFIG_NOSYSTEM
S="$SANDBOX/scripts"
BIN="$SANDBOX/bin"
LOG="$SANDBOX/resolver.log"
GHLOG="$SANDBOX/gh.log"
mkdir -p "$S" "$BIN" "$SANDBOX/adopter"
cp "$REAL_SCRIPTS/policy-guard.sh" "$REAL_SCRIPTS/protected-branch.sh" "$REAL_SCRIPTS/echo-safety.sh" "$S/"
HOOK="$S/policy-guard.sh"

cat >"$S/resolve-policy-knob.sh" <<EOF
#!/bin/sh
printf '%s\n' "\$1" >>"$LOG"
[ -z "\${STUB_SLEEP:-}" ] || sleep "\$STUB_SLEEP"
[ "\${STUB_FAIL_KNOB:-}" != "\$1" ] || exit 4
exec /bin/sh "$REAL_SCRIPTS/resolve-policy-knob.sh" "\$@"
EOF
cat >"$BIN/gh" <<EOF
#!/bin/sh
printf '%s\n' "gh \$*" >>"$GHLOG"
exit 1
EOF
chmod +x "$S/resolve-policy-knob.sh" "$BIN/gh"

gitq() { git -c init.defaultBranch=main -c user.name=t -c user.email=t@example.invalid "$@" >/dev/null 2>&1; }
ORIGIN="$SANDBOX/origin.git"
SEED="$SANDBOX/seed"
gitq init --bare "$ORIGIN"
gitq init "$SEED"
gitq -C "$SEED" commit --allow-empty -m base
gitq -C "$SEED" remote add origin "$ORIGIN"
gitq -C "$SEED" push origin main
for b in planwright/demo/task-1 planwright/demo/task-2 planwright/demo/spec; do
  gitq -C "$SEED" switch -c "$b" main
  gitq -C "$SEED" commit --allow-empty -m "pushed on $b"
  gitq -C "$SEED" push origin "$b"
done

clone_on() { # <dir> <branch> <unpushed-commit-count>
  local d=$1 b=$2 c=$3 i=0
  gitq clone "$ORIGIN" "$d"
  gitq -C "$d" switch "$b"
  gitq -C "$d" remote set-head origin main
  while [ "$i" -lt "$c" ]; do
    i=$((i + 1))
    gitq -C "$d" commit --allow-empty -m "unpushed $i"
  done
}
UNIT="$SANDBOX/unit"
clone_on "$UNIT" planwright/demo/task-1 3

LOCAL_CFG="$SANDBOX/local.yml"

# set_knobs <yaml lines...> — the machine-local layer for the next runs.
set_knobs() {
  printf '%s\n' "$@" >"$LOCAL_CFG"
}
set_knobs 'ready_flip_policy: unit-owner' 'worker_base_merge: allow' 'unpushed_rewrite: allow'

# pg <tier> <command> [cwd] [project-dir] — run the guard on a Bash payload.
# Sets OUT, CODE, DECISION, REASON, READS (the knobs read, space-joined).
pg() {
  local tier=$1 cmd=$2 cwd=${3:-$UNIT} proj=${4:-$UNIT} payload
  payload=$(jq -n --arg c "$cmd" --arg w "$cwd" '{tool_name:"Bash", tool_input:{command:$c}, cwd:$w}')
  pg_payload "$tier" bash "$payload" "$proj"
}

# PG_LOCAL_CONFIG='' and PG_REPO_ROOT='' drop the explicit machine-local file
# and repository root, so both layers are derived from the repository the
# guard reads policy from.
pg_run() { # <tier> <surface> <project-dir>; the payload on stdin
  env PATH="$BIN:$PATH" CLAUDE_PROJECT_DIR="$3" \
    PLANWRIGHT_ADOPTER_OVERLAY="$SANDBOX/adopter" PLANWRIGHT_REPO_ROOT="${PG_REPO_ROOT-$UNIT}" \
    PLANWRIGHT_LOCAL_CONFIG="${PG_LOCAL_CONFIG-$LOCAL_CFG}" PLANWRIGHT_POLICY_GUARD_TIMEOUT="${PG_TIMEOUT:-10}" \
    STUB_FAIL_KNOB="${STUB_FAIL_KNOB:-}" STUB_SLEEP="${STUB_SLEEP:-}" \
    /bin/bash "$HOOK" "$1" "$2" 2>/dev/null
}

pg_payload() {
  local tier=$1 surface=$2 payload=$3 proj=${4:-$UNIT}
  : >"$LOG"
  # PG_STDIN, when set, is a path the hook reads instead of the payload (a
  # directory makes the payload read itself fail).
  if [ -n "${PG_STDIN:-}" ]; then
    OUT=$(pg_run "$tier" "$surface" "$proj" <"$PG_STDIN")
  else
    OUT=$(printf '%s' "$payload" | pg_run "$tier" "$surface" "$proj")
  fi
  CODE=$?
  DECISION=defer
  REASON=''
  case $OUT in
    *[![:space:]]*)
      DECISION=unparsed
      {
        IFS= read -r DECISION
        IFS= read -r REASON
      } <<EOF
$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput | (.permissionDecision // "unparsed"), (.permissionDecisionReason // "" | gsub("\n"; " "))' 2>/dev/null)
EOF
      ;;
  esac
  READS=$(tr '\n' ' ' <"$LOG")
  READS=${READS% }
}

expect() { # <deny|defer> <label>
  if [ "$CODE" != 0 ]; then
    fail "$2: the hook exited $CODE"
  elif [ "$DECISION" = "$1" ]; then
    if [ "$1" = deny ] && [ -z "$REASON" ]; then
      fail "$2: denied with no reason"
    else
      pass "$2"
    fi
  else
    fail "$2: expected $1, got $DECISION ${REASON:+($REASON)}"
  fi
}

reads() { # <expected space-joined knobs, or none> <label>
  local want=$1
  [ "$want" != none ] || want=''
  if [ "$READS" = "$want" ]; then
    pass "$2 (reads: ${want:-none})"
  else
    fail "$2: expected reads '${want:-none}', got '${READS:-none}'"
  fi
}

reason_has() { # <ERE> <label>
  if printf '%s' "$REASON" | grep -Eq -- "$1"; then
    pass "$2"
  else
    fail "$2: the reason '$REASON' does not match /$1/"
  fi
}

no_gh_calls() {
  if [ -s "$GHLOG" ]; then
    fail "the guard called gh: $(head -3 "$GHLOG")"
  else
    pass "the guard never called gh (no host query at guard time)"
  fi
}

finish() {
  echo
  echo "passes: $passes  failures: $failures"
  [ "$failures" = 0 ]
}
