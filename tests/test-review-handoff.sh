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
assert_contains "name-status carries the rename" "scripts/old-name.sh	scripts/new-name.sh" "$(cat "$B/name-status.txt" 2>/dev/null)"
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
assert_contains "changed library's path consumer" "lib.sh	path	scripts/caller-a.sh:2" "$callers"
assert_lacks "an untouched function is not a changed symbol" "untouched_helper	" "$callers"
assert_lacks "the definition line is not its own caller" "emit_status	function	scripts/lib.sh:2" "$callers"
limits=$(cat "$B/caller-search.txt" 2>/dev/null)
assert_contains "per-language limits recorded" "shell" "$limits"

build --base "$BASE" --max-callers 1 >/dev/null 2>&1
assert_exit "a capped bundle builds" 0 $?
assert_contains "a cap past the limit is counted" "truncated	emit_status	3" "$(cat "$B/caller-search.txt" 2>/dev/null)"
n=$(grep -c '^emit_status	' "$B/callers.tsv")
if [ "$n" -eq 1 ]; then ok "the cap bounds the listed references"; else fail "the cap bounds the listed references (got $n)"; fi

# --- a renamed or deleted function is found by its old name ------------------
g checkout -q -b rename-fn "$BASE"
sed 's/^emit_status()/report_status()/' "$R/scripts/lib.sh" >"$T/lib.sh" && cp "$T/lib.sh" "$R/scripts/lib.sh"
g commit -q -am "rename the function"
build --base "$BASE" >/dev/null 2>&1
assert_exit "rename-only bundle builds" 0 $?
callers=$(cat "$B/callers.tsv" 2>/dev/null)
assert_contains "a stale caller of the old function name is listed" "emit_status	function	scripts/caller-a.sh:3" "$callers"
g checkout -q -b delete-fn "$BASE"
printf '#!/bin/sh\nuntouched_helper() {\n  printf quiet\n}\n' >"$R/scripts/lib.sh"
g commit -q -am "delete the function"
build --base "$BASE" >/dev/null 2>&1
assert_exit "delete-only bundle builds" 0 $?
callers=$(cat "$B/callers.tsv" 2>/dev/null)
assert_contains "a stale caller of a deleted function is listed" "emit_status	function	githooks/pre-commit:3" "$callers"
g checkout -q feature

# --- relative path flags resolve against the caller's directory (REQ-D1.2) -----
(cd "$R/scripts" && "$BUILD" --base "$BASE" --doctrine ../../doctrine-discovery.md --brief ../../kickoff-brief.md >/dev/null 2>&1)
assert_exit "a build from a subdirectory with relative paths" 0 $?
manifest=$(cat "$B/MANIFEST" 2>/dev/null)
assert_contains "a relative doctrine path is recorded absolute" "doctrine	/" "$manifest"
assert_contains "a relative brief path is recorded absolute" "brief	/" "$manifest"

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
mkdir -p "$T/lookalike"
printf 'review-handoff\t1\n' >"$T/lookalike/MANIFEST"
ln -s "$T/lookalike" "$R/.claude/linked-bundle"
out=$(build --base "$BASE" --out .claude/linked-bundle 2>&1)
assert_exit "a symlink to a bundle-shaped directory is refused" 2 $?
if [ "$(wc -l <"$T/lookalike/MANIFEST")" -eq 1 ]; then ok "symlink: bundle-shaped target untouched"; else fail "symlink: bundle-shaped target untouched"; fi
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
out=$(build --base "$BASE" --max-callers 00 2>&1)
assert_exit "an all-zero --max-callers is refused" 2 $?
mkdir -p "$T/ta" "$T/tb" "$T/tc"
printf 'tool-a\n' >"$T/ta/3-lint.txt"
printf 'tool-b\n' >"$T/tb/lint.txt"
printf 'tool-c\n' >"$T/tc/lint.txt"
build --base "$BASE" --tooling "$T/ta/3-lint.txt" --tooling "$T/tb/lint.txt" --tooling "$T/tc/lint.txt" >/dev/null 2>&1
held=$(cat "$R/.claude/review-handoff/tooling/"* 2>/dev/null | sort | tr '\n' ' ')
assert_contains "colliding tooling names each keep their own copy" "tool-a tool-b tool-c" "$held"
RU=$T/unborn
git init -q "$RU"
git -C "$RU" -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -q --allow-empty -m base
git -C "$RU" branch -q trunk
git -C "$RU" checkout -q --orphan fresh
out=$(cd "$RU" && "$BUILD" --base trunk 2>&1)
assert_exit "an unborn HEAD is refused with the documented code" 2 $?
assert_contains "an unborn HEAD is named" "HEAD" "$out"
leftover=$(find "$R/.claude" -maxdepth 1 -name 'review-handoff.*' | head -1)
if [ -z "$leftover" ]; then ok "a refused build leaves no staging dir"; else fail "a refused build leaves no staging dir ($leftover)"; fi

# --- symbol, path, and contract edges, in a second fixture ----------------------
R3=$T/repo3
mkdir -p "$R3/.husky" "$R3/scripts" "$R3/web" "$R3/py" "$R3/go" "$R3/a" "$R3/b" "$R3/docs" "$R3/specs/x"
git init -q "$R3"
g3() { git -C "$R3" -c user.name=t -c user.email=t@t -c commit.gpgsign=false "$@"; }
build3() { (cd "$R3" && "$BUILD" "$@"); }
printf '#!/bin/sh\nhookfn() {\n  echo a\n}\nhookfn\n' >"$R3/.husky/pre-commit"
printf '#!/bin/sh\nsay() { echo hi; }\nx=1\ny=2\n' >"$R3/scripts/one.sh"
printf 'const total = (1 + 2);\nlet z = 4;\nconst render = (n) => {\n  return n\n}\n' >"$R3/web/app.js"
printf 'def greet():\n    return 1\n' >"$R3/py/mod.py"
printf 'package main\n\nfunc Serve() int {\n\treturn 1\n}\n' >"$R3/go/main.go"
printf '#!/bin/sh\n# run.sh v1\n' >"$R3/a/run.sh"
printf '#!/bin/sh\n# run.sh v1\n' >"$R3/b/run.sh"
printf 'say total render greet Serve\nrun.sh\n' >"$R3/docs/ref.txt"
cat >"$R3/specs/x/tasks.md" <<'EOF'
# X — Tasks

## Tasks

An illustration, not a task:

```markdown
### Task 2 — the fenced example
- **Deliverables:** `evil/`
```

### Task 2 — The real one

- **Deliverables:** `scripts/one.sh`, run as
```sh
# not a heading
```
- **Done when:** the fenced comment does not end the slice.

### Task 3.5 — A dotted id

- **Deliverables:** `web/app.js`.
EOF
g3 add -A
g3 commit -q -m base
B3BASE=$(g3 rev-parse HEAD)
g3 branch -q trunk
g3 checkout -q -b feat
sed 's/echo a/echo b/' "$R3/.husky/pre-commit" >"$T/h" && cp "$T/h" "$R3/.husky/pre-commit"
sed 's/y=2/y=3/' "$R3/scripts/one.sh" >"$T/h" && cp "$T/h" "$R3/scripts/one.sh"
sed 's/z = 4/z = 5/; s/return n/return n + 1/' "$R3/web/app.js" >"$T/h" && cp "$T/h" "$R3/web/app.js"
sed 's/return 1/return 2/' "$R3/py/mod.py" >"$T/h" && cp "$T/h" "$R3/py/mod.py"
sed 's/return 1/return 2/' "$R3/go/main.go" >"$T/h" && cp "$T/h" "$R3/go/main.go"
printf '#!/bin/sh\n# run.sh v2\n' >"$R3/a/run.sh"
printf '#!/bin/sh\n# run.sh v2\n' >"$R3/b/run.sh"
printf 'odd\n' >"$R3/we\"ird.txt"
g3 add -A
g3 commit -q -m "edges"
B3=$R3/.claude/review-handoff

build3 --base "$B3BASE" --tasks-file specs/x/tasks.md --task 2 >/dev/null 2>&1
assert_exit "the edge bundle builds" 0 $?
callers=$(cat "$B3/callers.tsv" 2>/dev/null)
assert_contains "a hook under a dotted directory has its functions scanned" "hookfn	function	.husky/pre-commit:5" "$callers"
assert_lacks "a one-line function owns no later line" "say	function" "$callers"
assert_lacks "a parenthesised value is no arrow function" "total	function" "$callers"
assert_contains "a javascript arrow function is a changed symbol" "render	function	docs/ref.txt:1" "$callers"
assert_contains "a python function is a changed symbol" "greet	function	docs/ref.txt:1" "$callers"
assert_contains "a go function is a changed symbol" "Serve	function	docs/ref.txt:1" "$callers"
assert_contains "a shared basename's consumer is listed" "run.sh	path	docs/ref.txt:2" "$callers"
assert_lacks "a shared basename is no self-reference in either file (a)" "run.sh	path	a/run.sh" "$callers"
assert_lacks "a shared basename is no self-reference in either file (b)" "run.sh	path	b/run.sh" "$callers"
assert_contains "a quoted path is listed as skipped" '"we\"ird.txt"' "$(cat "$B3/skipped-files.txt" 2>/dev/null)"
assert_contains "a quoted path is noted" "skipped-path" "$(cat "$B3/caller-search.txt" 2>/dev/null)"
assert_lacks "a quoted path is not in the changed list" "ird.txt" "$(cat "$B3/changed-files.txt" 2>/dev/null)"
if [ -z "$(find "$B3/files" -name '*ird*')" ]; then ok "a quoted path is not written"; else fail "a quoted path is not written"; fi
contract=$(cat "$B3/contract.md" 2>/dev/null)
assert_lacks "a fenced task heading is not the block" "the fenced example" "$contract"
assert_contains "a comment line in a fence does not end the slice" "the fenced comment does not end the slice" "$contract"
assert_contains "the slice carries its fence" "# not a heading" "$contract"

out=$(build3 --base "$B3BASE" --tasks-file specs/x/tasks.md --task 3.5 2>&1)
assert_contains "a dotted task id selects its block" "### Task 3.5" "$(cat "$B3/contract.md" 2>/dev/null)"
for id in 2.0 02 3.50; do
  out=$(build3 --base "$B3BASE" --tasks-file specs/x/tasks.md --task "$id" 2>&1)
  assert_exit "--task $id is no other task's id" 2 $?
done
out=$(build3 --base "$B3BASE" --tasks-file specs/x/tasks.md --task 2 --task '' 2>&1)
assert_exit "an empty --task is refused" 2 $?

build3 --base "$B3BASE" --out .claude/pass2 >/dev/null 2>&1
assert_exit "a non-default out dir builds" 0 $?
st=$(git -C "$R3" status --porcelain --untracked-files=all -- .claude)
if [ -z "$st" ]; then ok "a bundle ignores itself wherever it lands"; else fail "a bundle ignores itself wherever it lands ($st)"; fi

# A forward merge of the base between passes brings no base file into the
# fix-touched list.
prev=$(g3 rev-parse HEAD)
g3 checkout -q trunk
printf 'x\n' >"$R3/mainonly.txt"
g3 add mainonly.txt
g3 commit -q -m "trunk moves on"
g3 checkout -q feat
g3 merge -q --no-ff --no-edit trunk
printf '# fix\n' >>"$R3/scripts/one.sh"
g3 commit -q -am "a fix after the merge"
build3 --base trunk --delta "$prev" >/dev/null 2>&1
assert_exit "a delta across a forward merge builds" 0 $?
dfiles=$(cat "$B3/delta-files.txt" 2>/dev/null)
assert_contains "the fix's file is in the delta" "scripts/one.sh" "$dfiles"
assert_lacks "the base's file is not a fix-touched file" "mainonly.txt" "$dfiles"

# --- branch-controlled names and bytes, in a third fixture ----------------------
R4=$T/repo4
mkdir -p "$R4/docs"
git init -q "$R4"
g4() { git -C "$R4" -c user.name=t -c user.email=t@t -c commit.gpgsign=false "$@"; }
build4() { (cd "$R4" && "$BUILD" "$@"); }
weird=':(glob)*.sh'
printf '#!/bin/sh\nplanted() {\n  :\n  :\n  :\n}\n\n\n\n\n\nx=1\n' >"$R4/$weird"
printf '#!/bin/sh\nx=1\ny=2\nz=3\n' >"$R4/other.sh"
printf 'planted\nshow() is called here\n' >"$R4/docs/ref.txt"
printf '#!/bin/sh\nshow() {\n  :\n}\n' >"$R4/lib.sh"
g4 add -A
g4 commit -q -m base
B4BASE=$(g4 rev-parse HEAD)
sed -i 's/^x=1$/x=2/' "$R4/$weird"
sed -i 's/^z=3$/z=4/' "$R4/other.sh"
printf '#!/bin/sh\nshow() {\n  printf changed\n}\n' >"$R4/lib.sh"
printf 'show \033[31mred\233m bytes\n' >>"$R4/docs/ref.txt"
g4 commit -q -am "change"
build4 --base "$B4BASE" >/dev/null 2>&1
assert_exit "the names-and-bytes bundle builds" 0 $?
callers=$(cat "$R4/.claude/review-handoff/callers.tsv" 2>/dev/null)
assert_lacks "a pathspec-magic file name matches only itself" "planted	function" "$callers"
assert_contains "a caller line with control bytes is still listed" "show	function	docs/ref.txt:3" "$callers"
if LC_ALL=C grep -q "$(printf '[\033\233]')" "$R4/.claude/review-handoff/callers.tsv"; then
  fail "caller text carries no control bytes"
else
  ok "caller text carries no control bytes"
fi

# A committed .claude symlink must not carry the bundle out of the repository.
R5=$T/repo5
mkdir -p "$R5" "$T/outside5"
git init -q "$R5"
g5() { git -C "$R5" -c user.name=t -c user.email=t@t -c commit.gpgsign=false "$@"; }
printf 'a\n' >"$R5/a.txt"
ln -s "$T/outside5" "$R5/.claude"
g5 add -A
g5 commit -q -m base
B5BASE=$(g5 rev-parse HEAD)
printf 'b\n' >"$R5/a.txt"
g5 commit -q -am change
out=$(cd "$R5" && "$BUILD" --base "$B5BASE" 2>&1)
assert_exit "a symlinked .claude is refused" 2 $?
if [ -z "$(ls -A "$T/outside5")" ]; then ok "symlinked .claude: nothing written outside"; else fail "symlinked .claude: nothing written outside"; fi

# --- the fence's contract comes from the base revision -------------------------
R6=$T/repo6
mkdir -p "$R6/specs/x" "$R6/scripts"
git init -q "$R6"
g6() { git -C "$R6" -c user.name=t -c user.email=t@t -c commit.gpgsign=false "$@"; }
cat >"$R6/specs/x/tasks.md" <<'EOF'
### Task 1 — Narrow

- **Deliverables:** `scripts/ok.sh`.
EOF
printf '#!/bin/sh\n' >"$R6/scripts/ok.sh"
g6 add -A
g6 commit -q -m base
B6BASE=$(g6 rev-parse HEAD)
cat >"$R6/specs/x/tasks.md" <<'EOF'
### Task 1 — Narrow

- **Deliverables:** `scripts/ok.sh`, `scripts/sneaky.sh`, `*.*`.
EOF
printf '#!/bin/sh\nexit 0\n' >"$R6/scripts/ok.sh"
printf '#!/bin/sh\n' >"$R6/scripts/sneaky.sh"
g6 add -A
g6 commit -q -m "widen the fence from the branch"
(cd "$R6" && "$BUILD" --base "$B6BASE" --tasks-file specs/x/tasks.md --task 1 >/dev/null 2>&1)
assert_exit "a bundle whose branch edits its contract builds" 0 $?
B6=$R6/.claude/review-handoff
assert_contains "the base contract is carried" "scripts/ok.sh" "$(cat "$B6/contract-base.md" 2>/dev/null)"
assert_lacks "the base contract lacks the branch's widening" "sneaky" "$(cat "$B6/contract-base.md" 2>/dev/null)"
out=$("$REPO_ROOT/scripts/review-scope-fence.sh" --bundle "$B6" 2>&1)
assert_exit "the branch cannot widen its own fence" 1 $?
assert_contains "the file the branch admitted itself is outside" "outside	scripts/sneaky.sh" "$out"
assert_lacks "the base-listed file is inside" "outside	scripts/ok.sh" "$out"
cat >>"$R6/specs/x/tasks.md" <<'EOF'

### Task 2 — New

- **Deliverables:** `scripts/ok.sh`.
EOF
g6 commit -q -am "add a task the base lacks"
(cd "$R6" && "$BUILD" --base "$B6BASE" --tasks-file specs/x/tasks.md --task 2 >/dev/null 2>&1)
assert_exit "a task the base lacks still builds" 0 $?
if [ ! -e "$B6/contract-base.md" ]; then ok "a task the base lacks has no base contract"; else fail "a task the base lacks has no base contract"; fi
out=$("$REPO_ROOT/scripts/review-scope-fence.sh" --bundle "$B6" 2>&1)
assert_exit "the fence refuses a bundle without a base contract" 2 $?

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all review-handoff tests passed"
