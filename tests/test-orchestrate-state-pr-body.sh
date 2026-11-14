#!/bin/bash
# Tests for scripts/orchestrate-state.sh reading a merged PR's body for its
# `Planwright-Task: <spec>/<id>` lines, so a task whose squash commit dropped
# the trailer still derives completed.
#
# The gh stub answers the body search with rows already rendered the way
# `@tsv` renders them (newlines as \n, CR as \r), so no system jq is needed.
# Runs standalone under /bin/bash (the bash 3.2 floor).
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
STATE="$here/../scripts/orchestrate-state.sh"
TAB=$(printf '\t')

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -x "$STATE" ] || fail "scripts/orchestrate-state.sh missing or not executable"

gitc() {
  repo="$1"
  shift
  git -C "$repo" -c user.name=test -c user.email=test@example.invalid \
    -c commit.gpgsign=false -c init.defaultBranch=main "$@"
}

field_of() {
  printf '%s\n' "$1" | awk -F"$TAB" -v i="$2" -v c="$3" '$1=="task" && $2==i {print $c; exit}'
}

assert_task() {
  got=$(field_of "$1" "$2" 3)
  [ "$got" = "$3" ] || fail "$5: task $2 derived '$got', expected '$3'"
  if [ -n "$4" ]; then
    got=$(field_of "$1" "$2" 4)
    [ "$got" = "$4" ] || fail "$5: task $2 evidence '$got', expected '$4'"
  fi
}

# make_stub <dir> <list-mode> <search-mode> <search-rows-file>: mode is ok or
# fail; the list call prints nothing on ok (no convention-branch PRs).
make_stub() {
  mkdir -p "$1"
  {
    echo '#!/bin/sh'
    echo 'case " $* " in'
    if [ "$3" = ok ]; then
      printf '  *" --search "*) cat "%s"; exit 0 ;;\n' "$4"
    else
      echo '  *" --search "*) echo "gh: simulated search failure" >&2; exit 1 ;;'
    fi
    echo 'esac'
    if [ "$2" = ok ]; then echo 'exit 0'; else echo 'exit 1'; fi
  } >"$1/gh"
  chmod +x "$1/gh"
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

repo="$tmp/repo"
spec="$repo/specs/demo"
mkdir -p "$spec"
gitc "$repo" init -q
cat >"$spec/tasks.md" <<'EOF'
# Demo — Tasks

**Status:** Active

## Forward plan

### Task 1 — delivered from a flight branch, squashed without its trailer
- **Dependencies:** none

### Task 2 — depends on Task 1
- **Dependencies:** 1

### Task 3 — an indented line names it
- **Dependencies:** none

### Task 4 — a fenced example names it
- **Dependencies:** none

### Task 5 — a PR merged into another branch names it
- **Dependencies:** none

### Task 6 — prose names it mid-line
- **Dependencies:** none

### Task 7 — another spec's line names its number
- **Dependencies:** none

### Task 8 — a lowercased key names it
- **Dependencies:** none

### Task 9 — an open PR's body names it
- **Dependencies:** none

### Task 10 — a closed, unmerged PR's body names it
- **Dependencies:** none
EOF
gitc "$repo" add -A
gitc "$repo" commit -q -m "base"
gitc "$repo" commit -q --allow-empty -m "fix: the flight's work, squashed with its title only (#41)"
gitc "$repo" remote add origin https://example.invalid/demo.git

rows="$tmp/rows.tsv"
# shellcheck disable=SC2016 # the backticks are body text, not expansions
{
  printf '41\tMERGED\tmain\tFixes the thing.\\r\\n\\r\\n<details><summary>Records</summary>\\r\\n\\r\\nPlanwright-Task: demo/1\\r\\n</details>\\r\\n\n'
  printf '42\tMERGED\tmain\tSummary\\n  Planwright-Task: demo/3\\n\n'
  printf '43\tMERGED\tmain\tExample:\\n\\n```\\nPlanwright-Task: demo/4\\n```\\n\n'
  printf '44\tMERGED\tplanwright/demo/spec\tPlanwright-Task: demo/5\n'
  printf '45\tMERGED\tmain\tSee the `Planwright-Task: demo/6` line.\n'
  printf '46\tMERGED\tmain\tPlanwright-Task: other/7\\nPlanwright-Task: demo/7;rm -rf /\n'
  printf '47\tMERGED\tmain\tplanwright-task: demo/8\n'
  printf '48\tOPEN\tmain\tPlanwright-Task: demo/9\n'
  printf '49\tCLOSED\tmain\tPlanwright-Task: demo/10\n'
  printf 'planwright/demo/task-9\tMERGED\n'
} >"$rows"

make_stub "$tmp/bin-ok" ok ok "$rows"
out=$(PATH="$tmp/bin-ok:$PATH" "$STATE" "$spec") || fail "engine exited non-zero"

assert_task "$out" 1 completed pr-body "body trailer, CRLF body, inside <details>"
assert_task "$out" 2 ready "" "dependent of a body-completed task"
assert_task "$out" 3 ready "" "an indented line is not a trailer"
assert_task "$out" 4 ready "" "a line inside a fenced block is not a trailer"
assert_task "$out" 5 ready "" "a PR merged into another branch completes nothing"
assert_task "$out" 6 ready "" "a mid-line mention is not a trailer"
assert_task "$out" 7 ready "" "another spec's line and a malformed value complete nothing"
assert_task "$out" 8 completed pr-body "a lowercased key matches, as in commits"
assert_task "$out" 9 ready "" "an open PR's body completes nothing"
assert_task "$out" 10 ready "" "a closed, unmerged PR's body completes nothing"
printf '%s\n' "$out" | grep -qxF "refused${TAB}Planwright-Task${TAB}demo/7;rm -rf /" \
  || fail "a malformed body value is not surfaced as refused"
echo "ok: a merged PR's body trailer completes its task, anchored and grammar-checked"

out2=$(PATH="$tmp/bin-ok:$PATH" "$STATE" "$spec") || fail "second run exited non-zero"
[ "$out" = "$out2" ] || fail "two runs disagree"
echo "ok: the body read is idempotent"

make_stub "$tmp/bin-searchfail" ok fail "$rows"
fout=$(PATH="$tmp/bin-searchfail:$PATH" "$STATE" "$spec") || fail "search failure: engine exited non-zero"
printf '%s\n' "$fout" | awk -F"$TAB" '$1=="degraded" && $2=="gh" {f=1} END{exit !f}' \
  || fail "search failure: no degraded record"
assert_task "$fout" 1 ready "" "search failure: a body-only task is never completed"
echo "ok: a failed body search degrades and completes nothing"

echo "PASS: test-orchestrate-state-pr-body.sh"
