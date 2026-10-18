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

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all review-handoff tests passed"
