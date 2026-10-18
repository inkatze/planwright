#!/bin/bash
# Tests for scripts/review-handoff.sh — the handoff bundle every review pass
# reads (review-effectiveness REQ-A1.6, REQ-B1.1, REQ-B1.5, REQ-D1.2, D-3,
# D-14).
set -u
unset CDPATH

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$REPO_ROOT/scripts/review-handoff.sh"

failures=0
ok() { echo "ok: $1"; }
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}
assert_exit() {
  if [ "$2" -eq "$3" ]; then ok "$1"; else fail "$1 (expected exit $2, got $3)"; fi
}
assert_contains() {
  case "$3" in
    *"$2"*) ok "$1" ;;
    *) fail "$1 (missing '$2' in: $3)" ;;
  esac
}
assert_lacks() {
  case "$3" in
    *"$2"*) fail "$1 (unexpectedly contains '$2')" ;;
    *) ok "$1" ;;
  esac
}

T=$(mktemp -d "${TMPDIR:-/tmp}/rho.XXXXXX")
trap 'rm -rf "$T"' EXIT

g() { git -C "$R" -c user.name=t -c user.email=t@t -c commit.gpgsign=false "$@"; }

# --- the fixture branch ------------------------------------------------------
# The base holds a library whose emit_status exit-code contract the branch
# changes, three planted callers of it (a script, a test, a git hook), a script
# the branch renames with two planted consumers, and an unrelated function
# nobody on the branch touches.
R=$T/repo
mkdir -p "$R"
git init -q "$R"
mkdir -p "$R/scripts" "$R/tests" "$R/docs" "$R/githooks" "$R/specs/demo"
cat >"$R/scripts/lib.sh" <<'EOF'
#!/bin/sh
emit_status() {
  printf 'status\n'
  return 0
}

untouched_helper() {
  printf 'quiet\n'
}
EOF
cat >"$R/scripts/caller-a.sh" <<'EOF'
#!/bin/sh
. "$(dirname "$0")/lib.sh"
emit_status || exit 3
EOF
cat >"$R/tests/test-lib.sh" <<'EOF'
#!/bin/bash
. scripts/lib.sh
if emit_status; then echo ok; fi
EOF
cat >"$R/githooks/pre-commit" <<'EOF'
#!/bin/sh
. scripts/lib.sh
emit_status >/dev/null
EOF
cat >"$R/scripts/old-name.sh" <<'EOF'
#!/bin/sh
printf 'old\n'
EOF
cat >"$R/docs/usage.md" <<'EOF'
# Usage

Run `old-name.sh` to print the greeting.
EOF
cat >"$R/mise.toml" <<'EOF'
[tasks.greet]
run = "sh scripts/old-name.sh"
EOF
printf 'nobody calls untouched_helper\n' >"$R/docs/notes.md"
cat >"$R/specs/demo/tasks.md" <<'EOF'
# Demo — Tasks

## Tasks

### Task 1 — An earlier task

- **Deliverables:** `scripts/other.sh`.

### Task 2 — Change the status contract

- **Deliverables:** `scripts/lib.sh` returning 2 on failure; the rename of
  `scripts/old-name.sh` to `scripts/new-name.sh`.
- **Done when:** the callers read the new code.

### Task 3 — A later task

- **Deliverables:** `scripts/later.sh`.
EOF
g add -A
g commit -q -m base
BASE=$(g rev-parse HEAD)
g checkout -q -b feature
cat >"$R/scripts/lib.sh" <<'EOF'
#!/bin/sh
emit_status() {
  printf 'status\n'
  return 2
}

untouched_helper() {
  printf 'quiet\n'
}
EOF
g mv scripts/old-name.sh scripts/new-name.sh
g commit -q -am "change the contract and rename the script"
HEAD1=$(g rev-parse HEAD)

DOCTRINE=$T/doctrine-discovery.md
BRIEF=$T/kickoff-brief.md
printf 'doctrine\n' >"$DOCTRINE"
printf 'brief\n' >"$BRIEF"
printf 'shellcheck: clean\n' >"$T/lint.txt"
printf 'Body line one.\nBody line two.\n' >"$T/body.md"

build() { (cd "$R" && "$BUILD" "$@"); }

# --- a full bundle carries every part (REQ-B1.1) ------------------------------
out=$(build --base "$BASE" --tasks-file specs/demo/tasks.md --task 2 \
  --title "feat: change the status contract" --body-file "$T/body.md" \
  --tooling "$T/lint.txt" --doctrine "$DOCTRINE" --brief "$BRIEF" 2>&1)
assert_exit "full bundle builds" 0 $?
B=$R/.claude/review-handoff
assert_contains "prints the bundle path" "$B" "$out"
if [ -f "$B/MANIFEST" ]; then ok "manifest written"; else fail "manifest written"; fi
manifest=$(cat "$B/MANIFEST" 2>/dev/null)
assert_contains "manifest names its format" "review-handoff	1" "$manifest"
assert_contains "manifest records the head" "head	$HEAD1" "$manifest"
assert_contains "manifest records the base" "base	$BASE" "$manifest"
assert_contains "manifest records full mode" "mode	full" "$manifest"
assert_contains "manifest records the task" "task	2" "$manifest"
assert_contains "resolved doctrine path recorded (REQ-D1.2)" "doctrine	$DOCTRINE" "$manifest"
assert_contains "resolved brief path recorded (REQ-D1.2)" "brief	$BRIEF" "$manifest"
diff=$(cat "$B/diff.patch" 2>/dev/null)
assert_contains "diff carries the changed line" "+  return 2" "$diff"
assert_contains "diff carries the rename" "rename to scripts/new-name.sh" "$diff"
whole=$(cat "$B/files/scripts/lib.sh" 2>/dev/null)
assert_contains "changed file whole: unchanged function present" "untouched_helper()" "$whole"
assert_contains "changed file whole: changed line present" "return 2" "$whole"
if [ -f "$B/files/scripts/new-name.sh" ]; then ok "renamed file written whole"; else fail "renamed file written whole"; fi
if [ ! -e "$B/files/scripts/old-name.sh" ]; then ok "a removed path is not written"; else fail "a removed path is not written"; fi
changed=$(cat "$B/changed-files.txt" 2>/dev/null)
assert_contains "changed list holds the old side of a rename" "scripts/old-name.sh" "$changed"
assert_contains "changed list holds the new side of a rename" "scripts/new-name.sh" "$changed"
contract=$(cat "$B/contract.md" 2>/dev/null)
assert_contains "contract slice holds the task heading" "### Task 2 — Change the status contract" "$contract"
assert_contains "contract slice holds the Done when" "the callers read the new code" "$contract"
assert_lacks "contract slice stops before the next task" "Task 3" "$contract"
assert_lacks "contract slice starts at its task" "Task 1" "$contract"
assert_contains "would-be PR title" "feat: change the status contract" "$(cat "$B/pr-title.txt" 2>/dev/null)"
assert_contains "would-be PR body" "Body line two." "$(cat "$B/pr-body.md" 2>/dev/null)"
assert_contains "tooling output copied" "shellcheck: clean" "$(cat "$B/tooling/lint.txt" 2>/dev/null)"

# --- every planted caller is found (REQ-A1.6) ---------------------------------
callers=$(cat "$B/callers.tsv" 2>/dev/null)
assert_contains "changed function's script caller" "emit_status	function	scripts/caller-a.sh:3" "$callers"
assert_contains "changed function's test caller" "emit_status	function	tests/test-lib.sh:3" "$callers"
assert_contains "changed function's hook caller" "emit_status	function	githooks/pre-commit:3" "$callers"
assert_contains "renamed script's doc consumer" "old-name.sh	path	docs/usage.md:3" "$callers"
assert_contains "renamed script's task consumer" "scripts/old-name.sh	path	mise.toml:2" "$callers"
assert_lacks "an untouched function is not a changed symbol" "untouched_helper	" "$callers"
assert_lacks "the definition line is not its own caller" "emit_status	function	scripts/lib.sh:2" "$callers"
limits=$(cat "$B/caller-search.txt" 2>/dev/null)
assert_contains "per-language limits recorded" "shell" "$limits"

build --base "$BASE" --max-callers 1 >/dev/null 2>&1
assert_exit "a capped bundle builds" 0 $?
assert_contains "a cap past the limit is counted" "truncated	emit_status	3" "$(cat "$B/caller-search.txt" 2>/dev/null)"
n=$(grep -c '^emit_status	' "$B/callers.tsv")
if [ "$n" -eq 1 ]; then ok "the cap bounds the listed references"; else fail "the cap bounds the listed references (got $n)"; fi

# --- a renamed or deleted function is found by its old name -------------------
g checkout -q -b rename-fn "$BASE"
sed 's/^emit_status()/report_status()/' "$R/scripts/lib.sh" >"$T/lib.sh" && cp "$T/lib.sh" "$R/scripts/lib.sh"
g commit -q -am "rename the function"
build --base "$BASE" >/dev/null 2>&1
assert_exit "rename-only bundle builds" 0 $?
callers=$(cat "$B/callers.tsv" 2>/dev/null)
assert_contains "a stale caller of the old function name is listed" "emit_status	function	scripts/caller-a.sh:3" "$callers"
g checkout -q feature

# --- delta mode (REQ-B1.5) ----------------------------------------------------
build --base "$BASE" --delta "$HEAD1" >/dev/null 2>&1
assert_exit "an empty delta builds" 0 $?
manifest=$(cat "$B/MANIFEST" 2>/dev/null)
assert_contains "empty delta: mode recorded" "mode	delta" "$manifest"
assert_contains "empty delta: previous head recorded" "previous_head	$HEAD1" "$manifest"
if [ -f "$B/delta.patch" ] && [ ! -s "$B/delta.patch" ]; then ok "empty delta: empty delta patch"; else fail "empty delta: empty delta patch"; fi
if [ -f "$B/delta-files.txt" ] && [ ! -s "$B/delta-files.txt" ]; then ok "empty delta: no fix-touched files"; else fail "empty delta: no fix-touched files"; fi
assert_contains "empty delta: whole branch still carried" "+  return 2" "$(cat "$B/diff.patch" 2>/dev/null)"

printf '# fixed\n' >>"$R/scripts/caller-a.sh"
g commit -q -am "a fix"
build --base "$BASE" --delta "$HEAD1" >/dev/null 2>&1
assert_exit "a one-file delta builds" 0 $?
assert_contains "one-file delta: the fixed file listed" "scripts/caller-a.sh" "$(cat "$B/delta-files.txt" 2>/dev/null)"
assert_lacks "one-file delta: an earlier change is not in the delta" "scripts/lib.sh" "$(cat "$B/delta-files.txt" 2>/dev/null)"
assert_contains "one-file delta: delta patch holds the fix" "+# fixed" "$(cat "$B/delta.patch" 2>/dev/null)"
assert_contains "one-file delta: whole branch still carried" "+  return 2" "$(cat "$B/diff.patch" 2>/dev/null)"

out=$(build --base "$BASE" --delta 0000000000000000000000000000000000000000 2>&1)
assert_exit "an unknown previous head is refused" 2 $?
g checkout -q rename-fn
out=$(build --base "$BASE" --delta "$HEAD1" 2>&1)
assert_exit "a previous head off this branch's history is refused" 2 $?
assert_contains "names the ancestry rule" "ancestor" "$out"
g checkout -q feature

# --- bundle path containment --------------------------------------------------
out=$(build --base "$BASE" --out "$T/elsewhere" 2>&1)
assert_exit "an out dir outside .claude/ is refused" 2 $?
if [ ! -e "$T/elsewhere" ]; then ok "nothing written outside"; else fail "nothing written outside"; fi
out=$(build --base "$BASE" --out .claude/../escape 2>&1)
assert_exit "a dot-dot escape is refused" 2 $?
if [ ! -e "$R/escape" ]; then ok "dot-dot: nothing written"; else fail "dot-dot: nothing written"; fi
out=$(build --base "$BASE" --out .claude 2>&1)
assert_exit ".claude itself is refused" 2 $?
mkdir -p "$T/target"
ln -s "$T/target" "$R/.claude/linked"
out=$(build --base "$BASE" --out .claude/linked 2>&1)
assert_exit "a symlinked out dir is refused" 2 $?
if [ -z "$(ls -A "$T/target")" ]; then ok "symlink: target untouched"; else fail "symlink: target untouched"; fi
mkdir -p "$R/.claude/precious"
printf 'keep\n' >"$R/.claude/precious/data"
out=$(build --base "$BASE" --out .claude/precious 2>&1)
assert_exit "a non-bundle directory is never replaced" 2 $?
if [ -f "$R/.claude/precious/data" ]; then ok "non-bundle dir kept"; else fail "non-bundle dir kept"; fi
build --base "$BASE" --out .claude/review-handoff-2 >/dev/null 2>&1
assert_exit "a named out dir under .claude/ builds" 0 $?
if [ -f "$R/.claude/review-handoff-2/MANIFEST" ]; then ok "named out dir written"; else fail "named out dir written"; fi
leftover=$(find "$R/.claude" -maxdepth 1 -name 'review-handoff.*' | head -1)
if [ -z "$leftover" ]; then ok "no staging dir left behind"; else fail "no staging dir left behind ($leftover)"; fi

# --- refused inputs -----------------------------------------------------------
out=$(build 2>&1)
assert_exit "no base is a usage error" 2 $?
out=$(build --base "$BASE" --tasks-file specs/demo/tasks.md --task 9 2>&1)
assert_exit "a task absent from the tasks file is refused" 2 $?
out=$(build --base "$BASE" --task 2 2>&1)
assert_exit "a task without a tasks file is refused" 2 $?
out=$(build --base "$BASE" --doctrine "$T/missing.md" 2>&1)
assert_exit "a doctrine path that does not exist is refused" 2 $?
out=$(build --base "$BASE" --tooling "$T/missing.txt" 2>&1)
assert_exit "an unreadable tooling file is refused" 2 $?

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all review-handoff tests passed"
