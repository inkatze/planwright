#!/bin/bash
# Tests for scripts/worker-command-guard.sh: the approved commands that can be
# made to write a file or run code the worker chose through an option or a
# config file they load. git's read verbs write their output to any path with
# --output; mise run takes the task's shell, directory, config environment or
# tools from its options; markdownlint-cli2 loads a JavaScript config, or a
# JSON one naming custom rules, from the directories it lints in and their
# parents. Each such form defers, and the plain forms keep their approval.
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
fixture_git init -q "$R"
fixture_commit "$R" README.md docs f .markdownlint.jsonc || exit 1
printf '# Scratch\n' >"$SCR/n.md"
HOOK_ENV=("GIT_CONFIG_GLOBAL=/dev/null" "GIT_CONFIG_NOSYSTEM=1")
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
  "git -C $R show --output=$OUT HEAD:f" "git -C $R log --output $OUT"; do
  assert_defer "git: $c" "$c" Bash "$R"
done
for c in 'git show HEAD:f' 'git log --oneline -1' 'git diff HEAD' 'git show --stat HEAD'; do
  assert_allow "git read: $c" "$c" Bash "$R"
done

echo "### mise run: options that change what the task runs defer"
for c in "mise run --shell 'sh x' t" "mise run -s 'sh x' t" "mise run --shell='sh x' t" \
  "mise run -qs 'sh x' t" "mise run -C $SCR t" "mise run --cd $SCR t" "mise run --cd=$SCR t" \
  "mise run -nC $SCR t" "mise run -E evil t" "mise run --env evil t" "mise run --env=evil t" \
  "mise run -qE evil t" "mise run -t node@20 t" "mise run --tool node@20 t" \
  "mise run --tool=node@20 t" "mise tasks run -C $SCR t" "mise tasks -C $SCR run t" \
  "mise tasks run --shell 'sh x' t" "mise run check -C $SCR"; do
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
printf '%s\n' "$JS" >"$R/docs/.markdownlint.cjs"
fixture_git -C "$R" add docs/.markdownlint.cjs
assert_defer "a config staged but not committed" 'markdownlint-cli2 docs/a.md' Bash "$R"
fixture_git -C "$R" commit -q -m config
assert_allow "a JavaScript config HEAD commits is repository code" 'markdownlint-cli2 docs/a.md' Bash "$R"
fixture_git -C "$R" rm -q docs/.markdownlint.cjs
fixture_git -C "$R" commit -q -m drop
printf '{ "globs": ["**/*.md"] }\n' >"$R/.markdownlint-cli2.jsonc"
fixture_commit "$R" .markdownlint-cli2.jsonc || exit 1
assert_defer "a base options file may add globs, which reach unchecked folders" \
  'markdownlint-cli2 README.md' Bash "$R"
assert_allow "--no-globs keeps the run to the named files" 'markdownlint-cli2 --no-globs README.md' Bash "$R"
fixture_git -C "$R" rm -q .markdownlint-cli2.jsonc
fixture_git -C "$R" commit -q -m drop

for c in 'markdownlint-cli2 --config x.jsonc README.md' 'markdownlint-cli2 --fix README.md' \
  'markdownlint -c x.json README.md' 'markdownlint --config x.json README.md' \
  'markdownlint -r ./rule.js README.md' 'markdownlint --rules ./rule.js README.md' \
  'markdownlint -o out README.md' 'markdownlint -f README.md' 'markdownlint-cli2 --format' \
  'markdownlint-cli2 "**/*.md"' 'markdownlint-cli2 "docs/*.md"' 'markdownlint-cli2 "#README.md"' \
  'markdownlint-cli2 docs' 'markdownlint docs' 'markdownlint-cli2' 'markdownlint-cli2 missing.md' \
  "markdownlint-cli2 $SCR/n.md" 'markdownlint-cli2 ../repo/README.md' 'markdownlint-cli2 ~/x.md'; do
  assert_defer "markdownlint shape: $c" "$c" Bash "$R"
done
assert_defer "markdownlint-cli2 in no checkout" 'markdownlint-cli2 n.md' Bash "$SCR"
ln -s "$SCR" "$R/linked"
with_file "$SCR/.markdownlint.cjs" "$JS" "a file reached through a folder symlinked out of the repository" \
  'markdownlint-cli2 linked/n.md'
rm -f "$R/linked"

# The approval stands on the folders as they are before the command runs: a
# write the own-branch arm admits in the same command could plant a config.
write_record "$BOX/ob.record" "$R" own-branch planwright/demo/task-1 || exit 1
fixture_git -C "$R" checkout -q -b planwright/demo/task-1
HOOK_ENV=("GIT_CONFIG_GLOBAL=/dev/null" "GIT_CONFIG_NOSYSTEM=1" "PLANWRIGHT_WORKER_SESSION_RECORD=$BOX/ob.record")
assert_allow "own-branch: the plain lint" 'markdownlint-cli2 README.md' Bash "$R"
assert_allow "own-branch: a write alone" 'printf x > notes.txt' Bash "$R"
assert_defer "own-branch: a write beside the lint" \
  'printf x > .markdownlint-cli2.cjs && markdownlint-cli2 README.md' Bash "$R"
HOOK_ENV=()

finish_suite worker-command-guard-loaders
