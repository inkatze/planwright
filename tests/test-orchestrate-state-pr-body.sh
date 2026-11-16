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

# make_stub <dir> <search-rows-file|fail>: the search answers with the rows
# (whatever --state it was asked for, so the engine's own filter is what the
# open and closed cases prove) or fails; the list call finds no
# convention-branch PR.
make_stub() {
  mkdir -p "$1"
  {
    echo '#!/bin/sh'
    echo 'case " $* " in'
    if [ "$2" != fail ]; then
      printf '  *" --search "*) cat "%s"; exit 0 ;;\n' "$2"
    else
      echo '  *" --search "*) echo "gh: simulated search failure" >&2; exit 1 ;;'
    fi
    echo 'esac'
    echo 'exit 0'
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

### Task 11 — a fork's merged PR body names it
- **Dependencies:** none

### Task 12 — a control byte before the key names it
- **Dependencies:** none

### Task 13 — trailing whitespace control bytes follow its value
- **Dependencies:** none
EOF
gitc "$repo" add -A
gitc "$repo" commit -q -m "base"
gitc "$repo" commit -q --allow-empty -m "fix: the flight's work, squashed with its title only (#41)"
gitc "$repo" remote add origin https://example.invalid/demo.git

rows="$tmp/rows.tsv"
# shellcheck disable=SC2016 # the backticks are body text, not expansions
{
  printf '41\tMERGED\tfalse\tmain\tFixes the thing.\\r\\n\\r\\n<details><summary>Records</summary>\\r\\n\\r\\nPlanwright-Task: demo/1\\r\\n</details>\\r\\n\n'
  printf '42\tMERGED\tfalse\tmain\tSummary\\n  Planwright-Task: demo/3\\n\n'
  printf '43\tMERGED\tfalse\tmain\tExample:\\n\\n```\\nPlanwright-Task: demo/4\\n```\\n\n'
  printf '44\tMERGED\tfalse\tplanwright/demo/spec\tPlanwright-Task: demo/5\n'
  printf '45\tMERGED\tfalse\tmain\tSee the `Planwright-Task: demo/6` line.\n'
  printf '46\tMERGED\tfalse\tmain\tPlanwright-Task: other/7\\nPlanwright-Task: demo/7;rm -rf /\\nPlanwright-Task: demo/7\\tforged\n'
  printf '47\tMERGED\tfalse\tmain\tplanwright-task: demo/8\n'
  printf '48\tOPEN\tfalse\tmain\tPlanwright-Task: demo/9\n'
  printf '49\tCLOSED\tfalse\tmain\tPlanwright-Task: demo/10\n'
  printf '50\tMERGED\ttrue\tmain\tPlanwright-Task: demo/11\n'
  printf '51\tMERGED\tfalse\tmain\tAdd the line:\\nPlanwright-Task: <spec>/<id>\n'
  printf '52\tMERGED\tfalse\tmain\t\013Planwright-Task: demo/12\\nPlanwright-Task: demo/7\033[31m\n'
  printf '53\tMERGED\tfalse\tmain\tPlanwright-Task: demo/%s3\n' "$(printf '\013')"
  printf '54\tMERGED\tfalse\tmain\tPlanwright-Task: demo/13%s\n' "$(printf '\013\014')"
} >"$rows"

make_stub "$tmp/bin-ok" "$rows"
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
assert_task "$out" 11 ready "" "a fork's merged PR body completes nothing"
assert_task "$out" 12 ready "" "a control byte before the key is not column 0"
assert_task "$out" 13 completed pr-body "trailing whitespace controls trim, as in commits"
printf '%s\n' "$out" | grep -qxF "refused${TAB}Planwright-Task${TAB}demo/7;rm -rf /" \
  || fail "a malformed body value is not surfaced as refused"
printf '%s\n' "$out" | grep -qxF "refused${TAB}Planwright-Task${TAB}demo/7 forged" \
  || fail "a tab in a body value reached the output as a field break"
printf '%s\n' "$out" | grep -qxF "refused${TAB}Planwright-Task${TAB}demo/7?[31m" \
  || fail "a control byte in a body value reached the output"
printf '%s\n' "$out" | grep -qxF "refused${TAB}Planwright-Task${TAB}demo/?3" \
  || fail "a control byte inside a value repaired it into a valid one"
refusals=$(printf '%s\n' "$out" | awk -F"$TAB" '$1 == "refused"' | awk 'END { print NR }')
[ "$refusals" = 4 ] || fail "another spec's or a placeholder's line was refused ($refusals refusals)"
echo "ok: a merged PR's body trailer completes its task, anchored and grammar-checked"

out2=$(PATH="$tmp/bin-ok:$PATH" "$STATE" "$spec") || fail "second run exited non-zero"
[ "$out" = "$out2" ] || fail "two runs disagree"
echo "ok: the body read is idempotent"

make_stub "$tmp/bin-searchfail" fail
fout=$(PATH="$tmp/bin-searchfail:$PATH" "$STATE" "$spec") || fail "search failure: engine exited non-zero"
printf '%s\n' "$fout" | awk -F"$TAB" '$1=="degraded" && $2=="gh" {f=1} END{exit !f}' \
  || fail "search failure: no degraded record"
assert_task "$fout" 1 ready "" "search failure: a body-only task is never completed"
echo "ok: a failed body search degrades and completes nothing"

# page <rows>: the fixture padded with undeclaring PRs to <rows> rows.
page() {
  cat "$rows"
  awk -v n="$1" -v have="$(awk 'END { print NR }' "$rows")" \
    'BEGIN { for (i = have; i < n; i++) printf "%d\tMERGED\tfalse\tmain\tno declaration\n", 1000 + i }'
}
page 999 >"$tmp/under.tsv"
make_stub "$tmp/bin-under" "$tmp/under.tsv"
uout=$(PATH="$tmp/bin-under:$PATH" "$STATE" "$spec") || fail "a page short of full: engine exited non-zero"
assert_task "$uout" 1 completed pr-body "a page short of full still counts"
page 1000 >"$tmp/full.tsv"
make_stub "$tmp/bin-full" "$tmp/full.tsv"
pout=$(PATH="$tmp/bin-full:$PATH" "$STATE" "$spec") || fail "full page: engine exited non-zero"
printf '%s\n' "$pout" | awk -F"$TAB" '$1=="degraded" && $2=="gh" {f=1} END{exit !f}' \
  || fail "full page: no degraded record"
assert_task "$pout" 1 ready "" "full page: a body-only task is never completed"
echo "ok: a search that fills its page degrades rather than miss older declarations"

# A base named like a remote-tracking ref is the local branch it names.
gitc "$repo" branch release/1.0
gitc "$repo" remote add release https://example.invalid/release.git
gitc "$repo" update-ref refs/remotes/release/1.0 HEAD
printf '60\tMERGED\tfalse\trelease/1.0\tPlanwright-Task: demo/3\n' >"$tmp/release.tsv"
make_stub "$tmp/bin-release" "$tmp/release.tsv"
rout=$(PATH="$tmp/bin-release:$PATH" PLANWRIGHT_BASE_REF=release/1.0 "$STATE" "$spec") \
  || fail "release base: engine exited non-zero"
assert_task "$rout" 3 completed pr-body "a PR into a local branch named like a remote's counts"
echo "ok: a base branch keeps its whole name beside a like-named remote"

echo "PASS: test-orchestrate-state-pr-body.sh"
