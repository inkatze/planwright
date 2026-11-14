#!/bin/bash
# Tests for scripts/spec-drift-check.sh — the spec-drift check: a changed file
# some spec lists as a task deliverable, with that spec's anchored content
# unchanged and no reason given, is flagged (mission-control REQ-D1.13; D-45).
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-spec-drift-check.sh
set -u
LC_ALL=C
export LC_ALL
unset CDPATH
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT

here=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$here/.." && pwd)
check="$repo_root/scripts/spec-drift-check.sh"

failures=0
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}
ok() { echo "ok: $1"; }

tmp=$(mktemp -d "${TMPDIR:-/tmp}/test-spec-drift-check.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT
trap 'exit 143' HUP INT TERM
tab=$(printf '\t')

repo="$tmp/repo"
mkdir -p "$repo"
gitc() { git -C "$repo" -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false "$@"; }
gitc init -q -b main
mkdir -p "$repo/specs/demo" "$repo/specs/_observations" "$repo/scripts" "$repo/src"
printf '# demo\n\n**Status:** Ready\n**Format-version:** 2\n\nBody.\n' >"$repo/specs/demo/requirements.md"
printf '# Design\n\nx\n' >"$repo/specs/demo/design.md"
printf '# Test spec\n\ny\n' >"$repo/specs/demo/test-spec.md"
cat >"$repo/specs/demo/tasks.md" <<'EOF'
# Tasks

**Format-version:** 2

## Tasks

### Task 1 — One

- **Deliverables:** `scripts/a.sh` and prose scripts/prose.sh, plus `src/b.c`.
- **Done when:** ok.
- **Dependencies:** none
- **Citations:** D-1
- **Estimated effort:** 1 day

### Task 2 — Two

- **Deliverables:** `lib/c.sh`.
- **Done when:** ok.
- **Dependencies:** none
- **Citations:** D-1
- **Estimated effort:** 1 day
EOF
printf 'a\n' >"$repo/scripts/a.sh"
printf 'prose\n' >"$repo/scripts/prose.sh"
printf 'b\n' >"$repo/src/b.c"
printf 'other\n' >"$repo/src/other.c"
mkdir -p "$repo/lib"
printf 'c\n' >"$repo/lib/c.sh"
gitc add -A >/dev/null
gitc commit -q -m base

# pr <message> <file>...: a pull request branch off main touching each file
pr() {
  local msg=$1 f
  shift
  gitc checkout -q -B pr main
  for f in "$@"; do
    mkdir -p "$repo/$(dirname "$f")"
    printf 'change\n' >>"$repo/$f"
  done
  gitc add -A >/dev/null
  gitc commit -q -m "$msg"
}
# run <body text>: the check over main..pr
run() {
  printf '%s' "$1" >"$tmp/body"
  out=$("$check" --repo "$repo" --base main --head pr --body-file "$tmp/body" 2>"$tmp/err")
  rc=$?
}
expect_rc() { if [ "$rc" = "$2" ]; then ok "$1"; else fail "$1: exit $rc, wanted $2 ($out $(cat "$tmp/err"))"; fi; }
expect_out() { case $out in *"$2"*) ok "$1" ;; *) fail "$1: output lacks '$2' ($out)" ;; esac; }
expect_err() { case $(cat "$tmp/err") in *"$2"*) ok "$1" ;; *) fail "$1: stderr lacks '$2' ($(cat "$tmp/err"))" ;; esac; }

# REQ-D1.13: a changed listed deliverable with no spec edit and no reason.
pr "feat: change a" scripts/a.sh
run "## Summary
Covering spec: none"
expect_rc "REQ-D1.13: a listed deliverable changed with no spec edit and no reason is flagged" 4
expect_out "and named with the task that lists it" "flagged${tab}scripts/a.sh${tab}demo/1"

run ""
expect_rc "a pull request with no statement is checked as covering nothing" 4

# A Not covered line naming the path, with a reason.
run "Covering spec: none
Not covered: scripts/a.sh — a typo fix in a comment"
expect_rc "a Not covered line naming the path, with its reason, passes" 0
run "- Not covered: \`scripts/a.sh\` - a typo fix"
expect_rc "a list marker, backticks and a plain dash are accepted" 0
run "Not covered: src/other.c — unrelated"
expect_rc "a Not covered line naming another path does not excuse it" 4
run "Not covered: scripts/a.sh"
expect_rc "a Not covered line with no reason does not excuse it" 4
run "Not covered: scripts/a.sh —   "
expect_rc "a Not covered line with a blank reason does not excuse it" 4

# A spec edit changing anchored content.
pr "feat: change a and the spec" scripts/a.sh specs/demo/design.md
run ""
expect_rc "the spec's anchored content edited passes" 0

# A status annotation alone is no edit.
gitc checkout -q -B pr main
sed 's/\*\*Status:\*\* Ready/**Status:** Active/' "$repo/specs/demo/requirements.md" >"$tmp/req" && cat "$tmp/req" >"$repo/specs/demo/requirements.md"
awk '{ print } /^### Task 1/ { getline; print; print "- **Last activity:** 2026-11-14" }' "$repo/specs/demo/tasks.md" >"$tmp/tasks" && cat "$tmp/tasks" >"$repo/specs/demo/tasks.md"
printf 'change\n' >>"$repo/scripts/a.sh"
gitc add -A >/dev/null
gitc commit -q -m "feat: a with status only"
run ""
expect_rc "a change to the status annotations alone does not count as an edit" 4

# The task pull request's own trailer.
pr "feat: task one

Planwright-Task: demo/1" scripts/a.sh
run ""
expect_rc "a pull request whose trailer names the task listing the file passes" 0
pr "feat: task two

Planwright-Task: demo/2" scripts/a.sh
run ""
expect_rc "a trailer naming another task does not excuse the file" 4

# Unlisted and prose-only.
pr "feat: other" src/other.c
run ""
expect_rc "a change touching no listed deliverable passes untouched" 0
pr "feat: prose" scripts/prose.sh
run ""
expect_rc "a deliverable path given in prose without backticks is not a listed file" 0

# A listed file moved away is still a change to it.
gitc checkout -q -B pr main
gitc mv scripts/a.sh scripts/moved.sh
gitc commit -q -m "feat: move a"
run ""
expect_rc "a listed deliverable moved away is flagged" 4
expect_out "under its old path" "flagged${tab}scripts/a.sh${tab}demo/1"

# Two listed files, one excused.
pr "feat: two" scripts/a.sh src/b.c lib/c.sh
run "Not covered: scripts/a.sh — reason"
expect_rc "an excused file leaves the others flagged" 4
expect_out "the unexcused one is named" "flagged${tab}src/b.c${tab}demo/1"
expect_out "the other task's file too" "flagged${tab}lib/c.sh${tab}demo/2"
case $out in *scripts/a.sh*) fail "the excused file is flagged" ;; *) ok "the excused file is not named" ;; esac

# A check that cannot run refuses with its reason.
pr "feat: change a" scripts/a.sh
printf '' >"$tmp/body"
out=$("$check" --repo "$repo" --base nosuchref --head pr --body-file "$tmp/body" 2>"$tmp/err")
rc=$?
expect_rc "no base refuses" 2
expect_err "with its reason" "base nosuchref is not a commit"
out=$("$check" --repo "$repo" --base main --head pr --body-file "$tmp/nosuchbody" 2>"$tmp/err")
rc=$?
expect_rc "an unreadable body refuses" 2
out=$("$check" --repo "$repo" --head pr --body-file "$tmp/body" 2>"$tmp/err")
rc=$?
expect_rc "a missing base argument refuses" 2
gitc checkout -q -B pr main
rm "$repo/specs/demo/design.md"
gitc add -A >/dev/null
gitc commit -q -m "break the bundle"
printf 'change\n' >>"$repo/scripts/a.sh"
gitc add -A >/dev/null
gitc commit -q -m "change a"
run ""
expect_rc "an unreadable bundle at the head refuses" 2
expect_err "naming the bundle" "bundle demo is unreadable"

# A repository with no spec root has nothing listed.
rm -rf "$tmp/plain"
mkdir -p "$tmp/plain"
git -C "$tmp/plain" init -q -b main
printf 'x\n' >"$tmp/plain/f"
git -C "$tmp/plain" add -A >/dev/null
git -C "$tmp/plain" -c user.name=t -c user.email=t@example.invalid commit -q -m one
git -C "$tmp/plain" checkout -q -b pr
printf 'y\n' >>"$tmp/plain/f"
git -C "$tmp/plain" -c user.name=t -c user.email=t@example.invalid commit -q -am two
: >"$tmp/body"
out=$("$check" --repo "$tmp/plain" --base main --head pr --body-file "$tmp/body" 2>"$tmp/err")
rc=$?
expect_rc "a repository with no spec root lists nothing" 0

[ "$failures" -eq 0 ] || {
  echo "$failures failure(s)" >&2
  exit 1
}
echo "all passed"
