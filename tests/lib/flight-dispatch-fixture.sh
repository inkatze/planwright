# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154 # the sourcing suite sets `here` and reads the paths and results set here
# flight-dispatch-fixture.sh — the shared fixture for the scripts/flight-dispatch.sh
# suites (sourced, never executed). tests/test-flight-dispatch.sh and
# tests/test-flight-dispatch-paths.sh split the cases between them so the two
# share the runner's parallelism rather than one file's budget; each sets
# `here` to its own directory before sourcing this and ends with `finish`.
#
# Every case builds its own fixture through new_case, so a case can move
# between the files without carrying state from another.
set -u
LC_ALL=C
export LC_ALL
unset CDPATH
# Live launches here have no confirming worker; shorten the startup wait.
export PLANWRIGHT_DISPATCH_CONFIRM_CAP=1 PLANWRIGHT_DISPATCH_CONFIRM_INTERVAL=0.2
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_SYSTEM=/dev/null
# A plugin session's own overlay and roots must not reach the fixtures.
unset CLAUDE_PLUGIN_DATA CLAUDE_PLUGIN_ROOT PLANWRIGHT_ROOT PLANWRIGHT_ADOPTER_OVERLAY \
  PLANWRIGHT_LOCAL_CONFIG PLANWRIGHT_CONFIG_DEFAULTS PLANWRIGHT_SKILLS_ROOT \
  PLANWRIGHT_ORCH_STATE_DIR PLANWRIGHT_FLIGHT_UID_SOURCE PLANWRIGHT_FLIGHT_LOCK_WAIT

ROOT=$(cd "$here/.." && pwd -P)
SCRIPT="$ROOT/scripts/flight-dispatch.sh"
OFFLOAD="$ROOT/scripts/offload-dispatch.sh"
STATE="$ROOT/scripts/fleet-state.sh"
TAB=$(printf '\t')
ESC=$(printf '\033')

fails=0
fail() {
  echo "FAIL: $1" >&2
  fails=$((fails + 1))
}

[ -x "$SCRIPT" ] || {
  echo "FAIL: scripts/flight-dispatch.sh missing or not executable" >&2
  exit 1
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
tmp=$(cd "$tmp" && pwd -P)

gitc() {
  _r=$1
  shift
  git -C "$_r" -c user.name=test -c user.email=test@example.invalid \
    -c commit.gpgsign=false -c init.defaultBranch=main "$@"
}

# A stub `gh` whose `auth status` answers per GH_STUB_AUTH, on a PATH that
# otherwise keeps the real tools.
mkdir -p "$tmp/bin"
cat >"$tmp/bin/gh" <<'EOF'
#!/bin/sh
[ -z "${GH_STUB_LOG:-}" ] || printf '%s\n' "$*" >>"$GH_STUB_LOG"
[ "$1 $2" = "auth status" ] && exit "${GH_STUB_AUTH:-0}"
exit 0
EOF
chmod +x "$tmp/bin/gh"
export PATH="$tmp/bin:$PATH"

# A git on $tmp/wlbin whose `worktree list` fails while $WTLIST_FAIL_FLAG
# exists, wherever the pair sits in its argv, logging each refusal to
# $WTLIST_FAIL_FLAG.log so a test can prove the failing path ran.
real_git=$(command -v git)
mkdir -p "$tmp/wlbin"
cat >"$tmp/wlbin/git" <<EOF
#!/bin/sh
if [ -e "\${WTLIST_FAIL_FLAG:-/nonexistent}" ]; then
  prev=''
  for a in "\$@"; do
    if [ "\$prev \$a" = "worktree list" ]; then
      echo refused >>"\$WTLIST_FAIL_FLAG.log"
      exit 128
    fi
    prev=\$a
  done
fi
exec '$real_git' "\$@"
EOF
chmod +x "$tmp/wlbin/git"

# A fresh case directory: a bare origin, a primary clone with main pushed, and
# isolated fleet/fetch state so no case touches the machine's fleet home or
# contends on its lock.
n=0
new_case() {
  n=$((n + 1))
  c="$tmp/c$n"
  mkdir -p "$c"
  git -c init.defaultBranch=main init -q --bare "$c/origin.git"
  git clone -q "$c/origin.git" "$c/primary" 2>/dev/null
  printf 'x\n' >"$c/primary/README.md"
  gitc "$c/primary" add -A
  gitc "$c/primary" commit -q -m init
  gitc "$c/primary" branch -M main
  gitc "$c/primary" push -q origin main
  # Fetches stay local; the push destination is what the home is judged on.
  gitc "$c/primary" remote set-url --push origin https://github.com/acme/widgets.git
  export PLANWRIGHT_FLEET_STATE_DIR="$c/fleet"
  export PLANWRIGHT_DISPATCH_FETCH_STATE_DIR="$c/fstate"
  export PLANWRIGHT_DISPATCH_LIVENESS_SKIP_TMUX=1
  export PLANWRIGHT_REPO_ROOT="$c/primary"
  export CLAUDE_DIR="$c/claude"
  # The shipped flight_pr_hosts is empty: the fixture opts github.com in from
  # the per-operator adopter layer, as an adopter would.
  mkdir -p "$c/adopter"
  printf 'flight_pr_hosts: [github.com]\n' >"$c/adopter/planwright.yml"
  export PLANWRIGHT_ADOPTER_OVERLAY="$c/adopter"
  printf 'Fix the typo in the README heading.\n' >"$c/ask.txt"
  printf 'visual flight: a one-line wording change, one revert from undone\n' >"$c/grounds.txt"
}

# grounds <text> — write a one-off grounds file and print its path.
grounds() {
  printf '%s\n' "$1" >"$c/g.txt"
  printf '%s' "$c/g.txt"
}

# run <args...> — sets OUT, ERR, RC.
run() {
  OUT=$("$SCRIPT" "$@" </dev/null 2>"$tmp/err")
  RC=$?
  ERR=$(cat "$tmp/err")
}

field() {
  printf '%s\n' "$1" | awk -F"$TAB" -v k="$2" '$1==k {print $2; exit}'
}

flight_branches() {
  gitc "$c/primary" for-each-ref --format='%(refname)' 'refs/heads/planwright/flight/' | grep -c . || true
}

briefs() {
  find "$c/fleet/flights" -mindepth 1 -maxdepth 1 2>/dev/null | grep -c . || true
}

# age <path...> — backdate past the sweep's grace, so its
# young-brief guard does not hold a brief the case retires on purpose.
age() {
  touch -t 202001010000 "$@"
}

dispatch_print() {
  run dispatch readme-typo --backend print --ask-file "$c/ask.txt" \
    --grounds-file "$c/grounds.txt" --repo-root "$c/primary"
}

# finish <suite> — report the failure count and exit on it.
finish() {
  if [ "$fails" -gt 0 ]; then
    echo "$1: $fails failure(s)" >&2
    exit 1
  fi
  echo "$1: ok"
}
