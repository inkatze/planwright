#!/bin/bash
# Tests for scripts/worker-command-guard.sh: the approved commands that can be
# made to write a file or run code the worker chose through an option or a
# config file they load. git's read verbs write their output to any path with
# --output; mise run takes the task's shell, directory, config environment or
# tools from its options; markdownlint-cli2 loads a JavaScript config, or a
# JSON one naming custom rules, from the directories it lints in and their
# parents. Each such form defers, and the plain forms keep their approval. A
# declared check command running markdownlint or mise run is held to the same
# screen.
# tests/test-worker-command-guard.sh holds the suite's overview; every file
# sources tests/lib/worker-command-guard-harness.sh.
# shellcheck disable=SC2034 # HOOK_ENV is read by the sourced harness
set -u
unset CDPATH
# shellcheck source=tests/lib/worker-command-guard-harness.sh
. "$(cd "$(dirname "$0")" && pwd)/lib/worker-command-guard-harness.sh"
# shellcheck source=tests/lib/committed-fixture.sh
. "$REPO_ROOT/tests/lib/committed-fixture.sh"

BOX=$(cd "$SANDBOX" && pwd -P)/loaders
# OUTER is no checkout, so a config file in it cannot be held to a commit.
OUTER=$BOX/outer
R=$OUTER/repo
SCR=$BOX/scratch
mkdir -p "$R/docs/sub" "$SCR"
printf '# Title\n' >"$R/README.md"
printf '# Docs\n' >"$R/docs/a.md"
printf '# Sub\n' >"$R/docs/sub/b.md"
printf '{ "MD013": false }\n' >"$R/.markdownlint.jsonc"
printf '{ "MD041": false }\n' >"$R/docs/.markdownlint.jsonc"
printf 'x\n' >"$R/f"
fixture_commit "$R" README.md docs f .markdownlint.jsonc || exit 1
printf '# Scratch\n' >"$SCR/n.md"
HOOK_ENV=("GIT_CONFIG_GLOBAL=/dev/null" "GIT_CONFIG_NOSYSTEM=1")
# The guard walks every folder above the repository, so a linter config the
# host left in one (a /tmp/package.json) would turn the allow rows below into
# defers; say so rather than fail them one by one.
d=$OUTER
while [ "$d" != / ]; do
  d=${d%/*}
  [ -n "$d" ] || d=/
  for n in .markdownlint-cli2.jsonc .markdownlint-cli2.yaml .markdownlint-cli2.yml .markdownlint-cli2.cjs \
    .markdownlint-cli2.mjs .markdownlint.jsonc .markdownlint.json .markdownlint.yaml .markdownlint.yml \
    .markdownlint.cjs .markdownlint.mjs .markdownlintrc package.json; do
    if [ -e "$d/$n" ] || [ -L "$d/$n" ]; then
      echo "FAIL: the host holds $d/$n above the fixture, which the guard rightly refuses; remove it to run this suite" >&2
      exit 1
    fi
  done
done
# What a worker's Write leaves: a config that runs code when the linter loads it.
JS='module.exports = { config: {} }; require("fs").writeFileSync("/tmp/pwned", "x");'

# with_file <path> <content> <label> <command> [cwd]: assert that <command>
# defers while <path> holds <content>, then remove it.
with_file() {
  printf '%s\n' "$2" >"$1"
  assert_defer "$3" "$4" Bash "${5:-$R}"
  rm -f -- "$1"
}

echo "### git read verbs: --output writes anywhere, so it defers"
OUT=$SCR/out.txt
for c in "git show --output=$OUT HEAD:f" "git show --output $OUT HEAD:f" "git log --output $OUT" \
  "git log --output=$OUT -1" "git diff --output=$OUT" "git diff HEAD --output $OUT" \
  "git show --out=$OUT HEAD:f" "git log -1 --outp=$OUT" "git format-patch -1 --output=$OUT" \
  "git format-patch -1 -o $SCR" "git diff-tree --output=$OUT HEAD" "git whatchanged --output=$OUT" \
  "git -C $R show --output=$OUT HEAD:f" "git -C $R log --output $OUT" \
  "git stash show --output=$OUT" "git stash show -p --out=$OUT" "git stash list --output=$OUT" \
  "git reflog show --output=$OUT" "git stash show --ext-diff"; do
  assert_defer "git: $c" "$c" Bash "$R"
done
for c in 'git show HEAD:f' 'git log --oneline -1' 'git diff HEAD' 'git show --stat HEAD' \
  'git stash list' 'git stash show -p' 'git reflog show -3' 'git reflog'; do
  assert_allow "git read: $c" "$c" Bash "$R"
done

echo "### mise run: options that change what the task runs defer"
for c in "mise run --shell 'sh x' t" "mise run -s 'sh x' t" "mise run --shell='sh x' t" \
  "mise run -qs 'sh x' t" "mise run -C $SCR t" "mise run --cd $SCR t" "mise run --cd=$SCR t" \
  "mise run -nC $SCR t" "mise run -E evil t" "mise run --env evil t" "mise run --env=evil t" \
  "mise run -qE evil t" "mise run -t node@20 t" "mise run --tool node@20 t" \
  "mise run --tool=node@20 t" "mise tasks run -C $SCR t" "mise tasks -C $SCR run t" \
  "mise tasks run --shell 'sh x' t" "mise run check -C $SCR" "mise run -Eevil t" \
  "mise run -tnode@20 t" "mise run -fs 'sh x' t" "mise tasks -E run t" "mise tasks --shell run t" "mise tasks -nC run t"; do
  assert_defer "mise: $c" "$c" Bash "$R"
done
for c in 'mise run check' 'mise run -n check' 'mise run -f check' 'mise run -j 2 check' \
  'mise run --timeout 60 check' 'mise run check ::: lint' 'mise tasks' 'mise tasks ls' \
  'mise tasks run check'; do
  assert_allow "mise: $c" "$c" Bash "$R"
done

echo "### markdownlint: committed config only"
for c in 'markdownlint-cli2 README.md' 'markdownlint-cli2 README.md docs/a.md' \
  'markdownlint-cli2 :README.md' 'markdownlint-cli2 -- README.md' 'markdownlint README.md' \
  'markdownlint -q README.md' 'markdownlint-cli2 --no-globs README.md'; do
  assert_allow "committed config: $c" "$c" Bash "$R"
done
assert_allow "committed config, from a subdirectory" 'markdownlint-cli2 a.md' Bash "$R/docs"
assert_allow "committed config, a file in a subdirectory" 'markdownlint-cli2 docs/sub/b.md' Bash "$R"
assert_allow "markdownlint-cli2 --version" 'markdownlint-cli2 --version' Bash "$R"

for n in .markdownlint-cli2.cjs .markdownlint-cli2.mjs .markdownlint.cjs .markdownlint.mjs; do
  with_file "$R/$n" "$JS" "a worker-written $n in the working directory" 'markdownlint-cli2 README.md'
  with_file "$R/$n" "$JS" "a worker-written $n in a parent of the working directory" \
    'markdownlint-cli2 a.md' "$R/docs"
  with_file "$R/docs/sub/$n" "$JS" "a worker-written $n beside the linted file" \
    'markdownlint-cli2 docs/sub/b.md'
  with_file "$OUTER/$n" "$JS" "a $n in a parent no commit holds" 'markdownlint-cli2 README.md'
  with_file "$R/$n" "$JS" "markdownlint with a worker-written $n" 'markdownlint README.md'
done
with_file "$R/.markdownlint-cli2.jsonc" '{ "customRules": ["./rule.js"] }' \
  "a worker-written JSON config naming a custom rule" 'markdownlint-cli2 README.md'
with_file "$R/docs/.markdownlint.yaml" 'extends: ../x.json' \
  "a worker-written YAML config in a linted directory" 'markdownlint-cli2 docs/a.md'
with_file "$R/package.json" '{ "markdownlint-cli2": { "customRules": ["./rule.js"] } }' \
  "a worker-written package.json in the working directory" 'markdownlint-cli2 README.md'
with_file "$R/.markdownlintrc" '{ "MD013": false }' \
  "a worker-written .markdownlintrc" 'markdownlint README.md'

cp "$R/.markdownlint.jsonc" "$BOX/ml.orig"
printf '{ "customRules": ["./rule.js"] }\n' >"$R/.markdownlint.jsonc"
assert_defer "a committed config edited since HEAD" 'markdownlint-cli2 README.md' Bash "$R"
cp "$BOX/ml.orig" "$R/.markdownlint.jsonc"
assert_allow "the committed config put back" 'markdownlint-cli2 README.md' Bash "$R"
printf '{ "MD041": true }\n' >"$R/docs/.markdownlint.json"
fixture_git -C "$R" add docs/.markdownlint.json
assert_defer "a config staged but not committed" 'markdownlint-cli2 docs/a.md' Bash "$R"
fixture_git -C "$R" rm -q --cached docs/.markdownlint.json
rm -f "$R/docs/.markdownlint.json"
# A committed module config may import a file beside it that the worker wrote.
printf 'module.exports = require("./rules.cjs");\n' >"$R/docs/.markdownlint.cjs"
fixture_commit "$R" docs/.markdownlint.cjs || exit 1
printf '%s\n' "$JS" >"$R/docs/rules.cjs"
assert_defer "a committed module config, which may import a worker-written file" \
  'markdownlint-cli2 docs/a.md' Bash "$R"
fixture_git -C "$R" rm -q docs/.markdownlint.cjs
fixture_git -C "$R" commit -q -m drop
rm -f "$R/docs/rules.cjs"
printf '{ "customRules": ["./rule.cjs"] }\n' >"$R/docs/.markdownlint-cli2.jsonc"
fixture_commit "$R" docs/.markdownlint-cli2.jsonc || exit 1
assert_defer "a committed options file naming a rule module" 'markdownlint-cli2 docs/a.md' Bash "$R"
printf '{ "custom\\u0052ules": ["./rule.cjs"] }\n' >"$R/docs/.markdownlint-cli2.jsonc"
fixture_commit "$R" docs/.markdownlint-cli2.jsonc || exit 1
assert_defer "a committed options file spelling a module key through an escape" \
  'markdownlint-cli2 docs/a.md' Bash "$R"
printf '{ "config": { "MD041": false } }\n' >"$R/docs/.markdownlint-cli2.jsonc"
fixture_commit "$R" docs/.markdownlint-cli2.jsonc || exit 1
assert_allow "a committed options file naming no module" 'markdownlint-cli2 docs/a.md' Bash "$R"
fixture_git -C "$R" rm -q docs/.markdownlint-cli2.jsonc
fixture_git -C "$R" commit -q -m drop
printf '{ "globs": ["**/*.md"] }\n' >"$R/.markdownlint-cli2.jsonc"
fixture_commit "$R" .markdownlint-cli2.jsonc || exit 1
assert_defer "a base options file may add globs, which reach unchecked folders" \
  'markdownlint-cli2 README.md' Bash "$R"
assert_allow "--no-globs keeps the run to the named files" 'markdownlint-cli2 --no-globs README.md' Bash "$R"
fixture_git -C "$R" rm -q .markdownlint-cli2.jsonc
fixture_git -C "$R" commit -q -m drop
printf '{ "name": "x" }\n' >"$R/package.json"
fixture_commit "$R" package.json || exit 1
assert_defer "a committed package.json in the working directory, without --no-globs" \
  'markdownlint-cli2 README.md' Bash "$R"
assert_allow "a committed package.json naming no module, with --no-globs" \
  'markdownlint-cli2 --no-globs README.md' Bash "$R"
fixture_git -C "$R" rm -q package.json
fixture_git -C "$R" commit -q -m drop
cp "$R/.markdownlint.jsonc" "$BOX/ml.copy"
rm -f "$R/.markdownlint.jsonc"
ln -s "$BOX/ml.copy" "$R/.markdownlint.jsonc"
assert_defer "a committed config swapped for a symlink to the same bytes" 'markdownlint-cli2 README.md' Bash "$R"
rm -f "$R/.markdownlint.jsonc"
cp "$BOX/ml.orig" "$R/.markdownlint.jsonc"

for c in 'markdownlint-cli2 --config x.jsonc README.md' 'markdownlint-cli2 --fix README.md' \
  'markdownlint -c x.json README.md' 'markdownlint --config x.json README.md' \
  'markdownlint -r ./rule.js README.md' 'markdownlint --rules ./rule.js README.md' \
  'markdownlint -o out README.md' 'markdownlint -f README.md' 'markdownlint-cli2 --format' \
  'markdownlint-cli2 "**/*.md"' 'markdownlint-cli2 "docs/*.md"' 'markdownlint-cli2 "#README.md"' \
  'markdownlint-cli2 docs' 'markdownlint docs' 'markdownlint-cli2' 'markdownlint-cli2 missing.md' \
  "markdownlint-cli2 $SCR/n.md" 'markdownlint-cli2 ../repo/README.md' 'markdownlint-cli2 ~/x.md' \
  'markdownlint-cli2 -q README.md' 'markdownlint-cli2 -- -x.md' 'markdownlint-cli2 --no-globs' \
  'markdownlint-cli2 "!README.md"'; do
  assert_defer "markdownlint shape: $c" "$c" Bash "$R"
done
# Extended-glob syntax, on files that exist, so the syntax alone is the reason.
for n in '@(a).md' '+(a).md' 'a|b.md' 'a\b.md'; do
  printf '# X\n' >"$R/docs/$n"
  assert_defer "an operand holding glob syntax: docs/$n" "markdownlint-cli2 'docs/$n'" Bash "$R"
  rm -f "$R/docs/$n"
done
assert_allow "markdownlint --quiet" 'markdownlint --quiet README.md' Bash "$R"
printf '# Hash\n' >"$R/#hash.md"
assert_defer "a name cli2 reads as a negated glob" 'markdownlint-cli2 "#hash.md"' Bash "$R"
rm -f "$R/#hash.md"
mkdir -p "$R/docs/a
b"
printf '# NL\n' >"$R/docs/a
b/c.md"
assert_defer "a folder name holding a newline" "markdownlint-cli2 'docs/a
b/c.md'" Bash "$R"
assert_defer "a working directory whose name holds a newline" 'markdownlint-cli2 c.md' Bash "$R/docs/a
b"
rm -rf "$R/docs/a
b"
assert_defer "markdownlint-cli2 in no checkout" 'markdownlint-cli2 n.md' Bash "$SCR"
F=$BOX/fakegit
mkdir -p "$F"
: >"$F/.git"
printf '# Fake\n' >"$F/README.md"
assert_defer "a .git that is no repository" 'markdownlint-cli2 README.md' Bash "$F"
# A folder linked inside the repository: the linter looks for config along the
# path as written, so the link's own folder would lie off the canonical walk.
ln -s docs/sub "$R/lk"
assert_defer "a file named through a linked folder" 'markdownlint-cli2 lk/b.md' Bash "$R"
assert_allow "the same file named without the link" 'markdownlint-cli2 docs/sub/b.md' Bash "$R"
rm -f "$R/lk"

echo "### markdownlint: a folder above the repository that another checkout holds"
P=$BOX/primary
W=$P/wt
mkdir -p "$W"
printf '{ "MD013": false }\n' >"$P/.markdownlint.jsonc"
fixture_commit "$P" .markdownlint.jsonc || exit 1
printf '# W\n' >"$W/README.md"
fixture_commit "$W" README.md || exit 1
assert_allow "a config the enclosing checkout commits" 'markdownlint-cli2 README.md' Bash "$W"
cp "$P/.markdownlint.jsonc" "$BOX/pml.orig"
printf '{ "MD013": true }\n' >"$P/.markdownlint.jsonc"
assert_defer "that config edited since its checkout's HEAD" 'markdownlint-cli2 README.md' Bash "$W"
cp "$BOX/pml.orig" "$P/.markdownlint.jsonc"
with_file "$P/.markdownlint.yaml" 'MD013: false' "a config the enclosing checkout does not hold" \
  'markdownlint-cli2 README.md' "$W"

echo "### declared check commands: a declared loader still passes its screen"
DECLS='markdownlint-cli2 <path>...; markdownlint <path>...; mise exec -- markdownlint-cli2 <path>...'
DECLS="$DECLS; ./node_modules/.bin/markdownlint-cli2 <path>...; mise run <word>; mise r <word>"
DECLS="$DECLS; mise run --cd <path> <word>; mise run --env <word> <word>; mise tasks run --tool <word> <word>"
DECLS="$DECLS; mise exec -- mix credo <word>; bin/check <word>; MarkdownLint-CLI2 <path>..."
DECLS="$DECLS; markdownlint-cli2 --fix <path>...; markdownlint-cli2-fix <path>...; mise -C <path> run <word>"
DECLS="$DECLS; mise t <word>; mise task run --cd <path> <word>; mise exec -- mise run <word>; mise exec -- mise r <word>"
write_record "$BOX/cc.record" "$R" '' || exit 1
printf 'check_commands=%s\n' "$DECLS" >>"$BOX/cc.record"
HOOK_ENV=("GIT_CONFIG_GLOBAL=/dev/null" "GIT_CONFIG_NOSYSTEM=1" "PLANWRIGHT_WORKER_SESSION_RECORD=$BOX/cc.record")
for c in 'markdownlint-cli2 README.md' 'markdownlint README.md' 'mise exec -- markdownlint-cli2 README.md' \
  './node_modules/.bin/markdownlint-cli2 docs/a.md' 'mise run check' 'mise exec -- mix credo strict' 'bin/check lint' \
  'MarkdownLint-CLI2 README.md' 'mise exec -- mise run check'; do
  assert_allow "declared, committed config only: $c" "$c" Bash "$R"
done
for n in .markdownlint-cli2.cjs .markdownlint.mjs; do
  for c in 'markdownlint-cli2 README.md' 'markdownlint README.md' 'mise exec -- markdownlint-cli2 README.md' \
    './node_modules/.bin/markdownlint-cli2 README.md' 'MarkdownLint-CLI2 README.md'; do
    with_file "$R/$n" "$JS" "declared, a worker-written $n: $c" "$c"
  done
done
with_file "$R/docs/.markdownlint.yaml" 'extends: ../x.json' \
  "declared, an uncommitted config beside the linted file" 'markdownlint-cli2 docs/a.md'
with_file "$R/docs/.markdownlint.yaml" 'extends: ../x.json' \
  "declared behind a runner prefix, an uncommitted config beside the linted file" \
  'mise exec -- markdownlint-cli2 docs/a.md'
with_file "$R/package.json" '{ "markdownlint-cli2": { "customRules": ["./rule.js"] } }' \
  "declared, a worker-written package.json in the working directory" 'markdownlint-cli2 README.md'
assert_defer "declared, a folder operand, not a file" 'markdownlint-cli2 docs' Bash "$R"
assert_defer "declared, an option the screen refuses" 'markdownlint-cli2 --fix README.md' Bash "$R"
assert_defer "declared, another markdownlint binary" 'markdownlint-cli2-fix README.md' Bash "$R"
mkdir -p "$R/sub"
printf '[tasks.t]\nrun = "touch /tmp/pwned"\n' >"$R/sub/mise.toml"
for c in 'mise run --cd sub t' 'mise run --env evil t' 'mise tasks run --tool node@20 t' 'mise r check' \
  'mise -C sub run t' 'mise t check' 'mise task run --cd sub t' 'mise exec -- mise r check'; do
  assert_defer "declared mise, another config or an unscreened spelling: $c" "$c" Bash "$R"
done
rm -rf "$R/sub"
HOOK_ENV=("GIT_CONFIG_GLOBAL=/dev/null" "GIT_CONFIG_NOSYSTEM=1")
assert_allow "undeclared, unchanged: committed config only" 'markdownlint-cli2 README.md' Bash "$R"
with_file "$R/.markdownlint-cli2.cjs" "$JS" "undeclared, unchanged: a worker-written module config" \
  'markdownlint-cli2 README.md'
assert_allow "undeclared, unchanged: mise run" 'mise run check' Bash "$R"
assert_defer "undeclared, unchanged: mise exec" 'mise exec -- markdownlint-cli2 README.md' Bash "$R"

# The approval stands on the folders as they are before the command runs: a
# write the own-branch arm admits in the same command could plant a config.
write_record "$BOX/ob.record" "$R" own-branch planwright/demo/task-1 || exit 1
fixture_git -C "$R" checkout -q -b planwright/demo/task-1
HOOK_ENV=("GIT_CONFIG_GLOBAL=/dev/null" "GIT_CONFIG_NOSYSTEM=1" "PLANWRIGHT_WORKER_SESSION_RECORD=$BOX/ob.record")
assert_allow "own-branch: the plain lint" 'markdownlint-cli2 README.md' Bash "$R"
assert_allow "own-branch: a write alone" 'printf x > notes.txt' Bash "$R"
assert_defer "own-branch: a write beside the lint" \
  'printf x > .markdownlint-cli2.cjs && markdownlint-cli2 README.md' Bash "$R"
assert_defer "own-branch: any admitted write beside the lint, which the guard cannot place" \
  'printf x > notes.txt && markdownlint-cli2 README.md' Bash "$R"
assert_allow "own-branch: a git add alone" 'git add README.md' Bash "$R"
assert_defer "own-branch: a git add beside the lint" \
  'git add README.md && markdownlint-cli2 README.md' Bash "$R"
assert_allow "own-branch: a git restore alone" 'git restore README.md' Bash "$R"
assert_defer "own-branch: a git restore beside the lint, which can write a config" \
  'git restore README.md && markdownlint-cli2 README.md' Bash "$R"
HOOK_ENV=()

finish_suite worker-command-guard-loaders
