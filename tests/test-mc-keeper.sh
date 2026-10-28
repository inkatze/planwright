#!/bin/bash
# Tests for scripts/mc-keeper.sh — the session-keeper duty: retire a tracked
# session once its pull request lands, and pipelining, the next ready unit
# named for dispatch while another waits on CI (mission-control REQ-D1.5,
# REQ-M1.3, REQ-M1.4; D-10, D-27).
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-mc-keeper.sh
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$here/.." && pwd)

failures=0
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}
ok() { echo "ok: $1"; }

tmp=$(mktemp -d) || exit 1
tmp=$(cd "$tmp" && pwd -P) || exit 1
trap 'rm -rf "$tmp"' EXIT

# shellcheck source=tests/lib/mission-control-fixture.sh
. "$here/lib/mission-control-fixture.sh"

tab=$(printf '\t')
reset_mc_fixture
cat >"$tracked" <<EOF
mission_control_programs: [alpha]
program_alpha_repositories: [$repo]
program_alpha_spec_root: $repo/specs
program_alpha_home: $tmp/mchome
program_alpha_budget: {host_load: 1000000}
EOF
ledger="$fleet/mission-control/alpha/keeper.tsv"

mkdir -p "$tmp/bin"
cat >"$tmp/bin/gh" <<EOF
#!/bin/sh
case "\$*" in
  *"pr view 7 "*) cat "$tmp/state7" ;;
  *"pr view 8 "*) echo OPEN ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$tmp/bin/gh"

# ---------------------------------------------------------------------------
# REQ-D1.5: a session whose pull request landed is retired and dropped; an
# open one stays; a failed read keeps it.
# ---------------------------------------------------------------------------
mc_run mc-keeper.sh track --program alpha --session mc-alpha-worker-one --repo acme/web --pr 7
expect_rc "track" 0
mc_run mc-keeper.sh track --program alpha --session mc-alpha-worker-two --repo acme/web --pr 8
mc_run mc-keeper.sh track --program alpha --session mc-alpha-worker-bad --repo acme/web --pr 9
mc_run mc-keeper.sh track --program alpha --session mc-alpha-worker-one --repo acme/web --pr 7 --worktree relative/dir
expect_rc "a relative worktree is refused" 2
echo MERGED >"$tmp/state7"
PATH="$tmp/bin:$PATH" mc_run mc-keeper.sh sweep --program alpha
expect_rc "a sweep with a failed read reports it" 1
expect_out "REQ-D1.5: the landed pull request is seen" "landed${tab}mc-alpha-worker-one${tab}MERGED"
expect_out "REQ-D1.5: its session is retired" "retired${tab}mc-alpha-worker-one"
expect_out "the open one is left" "open${tab}mc-alpha-worker-two"
expect_out "the failed read is named" "unknown${tab}mc-alpha-worker-bad"
if ! grep -q "worker-one" "$ledger" && grep -q "worker-two" "$ledger" && grep -q "worker-bad" "$ledger"; then
  ok "REQ-M1.3: the landed unit frees its slot within one sweep"
else
  fail "REQ-M1.3: the ledger after the sweep: $(cat "$ledger")"
fi

mc_run mc-keeper.sh track --program alpha --session mc-alpha-worker-three --repo acme/web --pr 7
echo CLOSED >"$tmp/state7"
OUT=$(cd "$repo" && mc_env env PATH="$tmp/bin:$PATH" PLANWRIGHT_MC_PROGRAM=alpha /bin/bash "$repo_root/scripts/mc-keeper.sh" 2>"$tmp/stderr")
RC=$?
ERR=$(cat "$tmp/stderr")
expect_rc "under the runner, the failed read still fails the run" 1
expect_eq "under the runner, a landing is announced and nothing else printed" "announced${tab}session-landed${tab}mc-alpha-worker-three"
mc_run mc-event.sh list --program alpha
expect_out "the landing lands in the event store" "session-landed${tab}mc-alpha-worker-three${tab}CLOSED, retired"

# A landing that stays held wakes the session once, not every run.
mkdir -p "$tmp/dirty"
mc_run mc-keeper.sh track --program alpha --session mc-alpha-worker-four --repo acme/web --pr 7 --worktree "$tmp/dirty"
held_run_1=$(cd "$repo" && mc_env env PATH="$tmp/bin:$PATH" PLANWRIGHT_MC_PROGRAM=alpha /bin/bash "$repo_root/scripts/mc-keeper.sh" 2>"$tmp/held.err")
held_run_2=$(cd "$repo" && mc_env env PATH="$tmp/bin:$PATH" PLANWRIGHT_MC_PROGRAM=alpha /bin/bash "$repo_root/scripts/mc-keeper.sh" 2>/dev/null)
case $held_run_1 in *"announced${tab}session-landed${tab}mc-alpha-worker-four"*) ok "a held landing is announced" ;; *) fail "a held landing was not announced: $held_run_1 $(cat "$tmp/held.err")" ;; esac
case $held_run_2 in *worker-four*) fail "a held landing was announced again: $held_run_2" ;; *) ok "and not again while it stays held" ;; esac
if grep -q "worker-four" "$ledger"; then ok "a held session stays tracked"; else fail "a held session was dropped"; fi

# ---------------------------------------------------------------------------
# REQ-M1.4: the next ready unit dispatches while another waits on CI.
# ---------------------------------------------------------------------------
gr() { git -C "$repo" -c user.name=t -c user.email=t@example.invalid "$@" >/dev/null 2>&1; }
mkdir -p "$repo/specs/demo"
cat >"$repo/specs/demo/tasks.md" <<'EOF'
# Demo — Tasks

**Status:** Ready
**Format-version:** 2

## Tasks

### Task 1 — First

- **Deliverables:** a
- **Dependencies:** none

### Task 2 — Second

- **Deliverables:** b
- **Dependencies:** none

### Task 3 — Third

- **Deliverables:** c
- **Dependencies:** 1
EOF
gr checkout -q -b main
gr add -A
gr commit -m spec
gr checkout -q -b planwright/demo/task-1
gr commit --allow-empty -m "task 1 work, CI pending"
gr checkout -q main
mc_run mc-keeper.sh next --program alpha --spec "$repo/specs/demo"
expect_rc "next" 0
expect_out "REQ-M1.4: the unit waiting on CI is named waiting" "waiting${tab}demo:task-1${tab}in-progress"
expect_out "REQ-M1.4: the next ready unit dispatches" "dispatch${tab}demo:task-2"
expect_no_out "a unit whose dependency is in flight does not" "demo:task-3"
expect_no_out "REQ-M1.3: the unit with a branch is not dispatched again" "dispatch${tab}demo:task-1"

# The budget's admission holds dispatch when no session would be admitted.
sed -i.bak 's/^program_alpha_budget: .*/program_alpha_budget: {host_load: 1000000, sessions: 1}/' "$tracked"
mc_run mc-budget.sh record --program alpha sessions 1
mc_run mc-keeper.sh next --program alpha --spec "$repo/specs/demo"
expect_rc "next under a full budget" 0
expect_out "REQ-M1.4: a ready unit is held while the budget admits no session" "held${tab}demo:task-2${tab}the budget holds dispatch (sessions at their limit)"
expect_no_out "and is not dispatched" "dispatch${tab}"

if [ "$failures" -ne 0 ]; then
  echo "test-mc-keeper: $failures failure(s)" >&2
  exit 1
fi
echo "test-mc-keeper: all passed"
