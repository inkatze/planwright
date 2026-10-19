#!/bin/bash
# Tests for scripts/check-diff-scoped.sh — the per-fix check: the tests
# touching the changed files plus the linters over them
# (review-effectiveness REQ-D1.3, D-11).
set -u
unset CDPATH

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECK="$REPO_ROOT/scripts/check-diff-scoped.sh"

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

T=$(mktemp -d "${TMPDIR:-/tmp}/cds.XXXXXX")
trap 'rm -rf "$T"' EXIT

R=$T/repo
mkdir -p "$R/scripts" "$R/tests" "$R/docs" "$R/config" "$R/githooks"
git init -q "$R"
g() { git -C "$R" -c user.name=t -c user.email=t@t -c commit.gpgsign=false "$@"; }
printf '#!/bin/sh\nexit 0\n' >"$R/scripts/alpha.sh"
printf '#!/bin/sh\nexit 0\n' >"$R/githooks/pre-commit"
printf '# Docs\n' >"$R/docs/README.md"
printf '# Scripts\n' >"$R/scripts/README.md"
printf 'key: value\n' >"$R/config/settings.yml"
printf '#!/bin/bash\nsh scripts/alpha.sh\n' >"$R/tests/test-alpha.sh"
# shellcheck disable=SC2016 # the fixture's $S is for the fixture's shell
printf '#!/bin/bash\nS=scripts\nsh "$S/alpha.sh"\n' >"$R/tests/test-beta.sh"
printf '#!/bin/bash\ngrep -q Docs docs/README.md\n' >"$R/tests/test-doc-path.sh"
printf '#!/bin/bash\nls README.md >/dev/null 2>&1; exit 0\n' >"$R/tests/test-any-readme.sh"
printf '#!/bin/bash\nexit 0\n' >"$R/tests/test-unrelated.sh"
printf '#!/bin/bash\n. tests/lib/helper.sh\n' >"$R/tests/test-uses-lib.sh"
mkdir -p "$R/tests/lib"
printf 'helper() { :; }\n' >"$R/tests/lib/helper.sh"
g add -A
g commit -q -m base
BASE=$(g rev-parse HEAD)

ck() { (cd "$R" && "$CHECK" "$@"); }

# --- test selection ------------------------------------------------------------
out=$(ck --list scripts/alpha.sh 2>&1)
assert_exit "listing a script's checks" 0 $?
assert_contains "a test naming the script's path" "test	tests/test-alpha.sh" "$out"
assert_contains "a test naming its unique basename" "test	tests/test-beta.sh" "$out"
assert_lacks "an unrelated test" "test-unrelated.sh" "$out"
assert_lacks "a test naming another file" "test-doc-path.sh" "$out"
assert_contains "the script is shellchecked" "lint	shellcheck	scripts/alpha.sh" "$out"
assert_contains "the script is format-checked" "lint	shfmt	scripts/alpha.sh" "$out"

out=$(ck --list docs/README.md 2>&1)
assert_contains "a test naming the doc's path" "test	tests/test-doc-path.sh" "$out"
assert_lacks "a shared basename selects nothing by name" "test-any-readme.sh" "$out"
assert_contains "the doc is markdown-linted" "lint	markdownlint-cli2	docs/README.md" "$out"
assert_lacks "a doc is not shellchecked" "shellcheck" "$out"

out=$(ck --list tests/test-unrelated.sh tests/lib/helper.sh config/settings.yml githooks/pre-commit 2>&1)
assert_contains "a changed test selects itself" "test	tests/test-unrelated.sh" "$out"
assert_contains "a changed test library selects its users" "test	tests/test-uses-lib.sh" "$out"
assert_contains "yaml is linted" "lint	yamllint	config/settings.yml" "$out"
assert_contains "an extensionless shell hook is shellchecked" "lint	shellcheck	githooks/pre-commit" "$out"

# --- --base: committed, uncommitted, and untracked changes ---------------------
printf '#!/bin/sh\nexit 0\n# edit\n' >"$R/scripts/alpha.sh"
g commit -q -am "commit a change"
printf '# Docs edited\n' >"$R/docs/README.md"
printf '#!/bin/bash\nexit 0\n' >"$R/tests/test-new.sh"
out=$(ck --list --base "$BASE" 2>&1)
assert_exit "listing against a base" 0 $?
assert_contains "base: a committed change" "test	tests/test-alpha.sh" "$out"
assert_contains "base: an uncommitted change" "lint	markdownlint-cli2	docs/README.md" "$out"
assert_contains "base: an untracked test" "test	tests/test-new.sh" "$out"
assert_lacks "base: an unchanged file" "settings.yml" "$out"
g checkout -q -- docs/README.md
rm "$R/tests/test-new.sh"
out=$(ck --list --base HEAD 2>&1)
assert_exit "nothing changed against HEAD" 0 $?
assert_contains "an empty selection says so" "nothing changed" "$out"

# --- running: tests and linters, through stub linters --------------------------
STUB=$T/stub
mkdir -p "$STUB"
for tool in shellcheck shfmt markdownlint-cli2 yamllint; do
  cat >"$STUB/$tool" <<EOF
#!/bin/sh
printf '%s %s\n' "$tool" "\$*" >>"$T/lint-calls"
for f in "\$@"; do case \$f in -*) ;; *) ! grep -q LINTBAD "\$f" || exit 1 ;; esac; done
exit 0
EOF
  chmod +x "$STUB/$tool"
done
out=$(cd "$R" && PATH="$STUB:$PATH" "$CHECK" scripts/alpha.sh 2>&1)
assert_exit "a clean run passes" 0 $?
assert_contains "the selected test passed" "pass	test	tests/test-alpha.sh" "$out"
assert_contains "the linter passed" "pass	lint	shellcheck" "$out"
calls=$(cat "$T/lint-calls")
assert_contains "shellcheck ran on the file" "shellcheck ./scripts/alpha.sh" "$calls"
assert_contains "shfmt ran in diff mode" "shfmt -d ./scripts/alpha.sh" "$calls"

printf '#!/bin/bash\nsh scripts/alpha.sh\nexit 3\n' >"$R/tests/test-alpha.sh"
out=$(cd "$R" && PATH="$STUB:$PATH" "$CHECK" scripts/alpha.sh 2>/dev/null)
assert_exit "a failing selected test fails the check" 1 $?
assert_contains "names the failing test" "fail	test	tests/test-alpha.sh" "$out"
g checkout -q -- tests/test-alpha.sh

printf '#!/bin/sh\n# LINTBAD\nexit 0\n' >"$R/scripts/alpha.sh"
out=$(cd "$R" && PATH="$STUB:$PATH" "$CHECK" scripts/alpha.sh 2>/dev/null)
assert_exit "a linter finding fails the check" 1 $?
assert_contains "names the failing linter" "fail	lint	shellcheck" "$out"
g checkout -q -- scripts/alpha.sh

out=$(cd "$R" && PATH="$STUB:$PATH" "$CHECK" config/settings.yml docs/README.md 2>&1)
calls=$(cat "$T/lint-calls")
assert_contains "yamllint runs strict" "yamllint --strict ./config/settings.yml" "$calls"
assert_contains "markdownlint runs on the doc" "markdownlint-cli2 ./docs/README.md" "$calls"
printf '#!/bin/bash\n# scripts/alpha.sh\necho distinctive-failure-text\nexit 3\n' >"$R/tests/test-alpha.sh"
err=$(cd "$R" && PATH="$STUB:$PATH" "$CHECK" scripts/alpha.sh 2>&1 >/dev/null)
assert_contains "a failing test's output goes to stderr" "distinctive-failure-text" "$err"
g checkout -q -- tests/test-alpha.sh

# A linter that is not installed is reported, never silently passed.
nopath=
IFS=: read -r -a dirs <<<"$PATH"
for d in "${dirs[@]}"; do [ -x "$d/yamllint" ] || nopath=${nopath:+$nopath:}$d; done
rm "$STUB/yamllint"
out=$(cd "$R" && PATH="$STUB:$nopath" "$CHECK" config/settings.yml 2>&1)
assert_exit "a missing linter does not fail the check" 0 $?
assert_contains "a missing linter is reported" "skipped	lint	yamllint	not installed" "$out"

# --- selection edges, in a second fixture --------------------------------------
R2=$T/repo2
mkdir -p "$R2/scripts" "$R2/tests" "$R2/docs" "$R2/.husky"
git init -q "$R2"
g2() { git -C "$R2" -c user.name=t -c user.email=t@t -c commit.gpgsign=false "$@"; }
ck2() { (cd "$R2" && "$CHECK" "$@"); }
printf '#!/bin/sh\nexit 0\n' >"$R2/.husky/pre-commit"
printf '#!/bin/sh\nexit 0\n' >"$R2/scripts/old-name.sh"
printf '#!/bin/bash\nsh scripts/old-name.sh\n' >"$R2/tests/test-old.sh"
printf 'shared\n' >"$R2/notes.txt"
printf 'shared\n' >"$R2/docs/notes.txt"
printf '#!/bin/bash\ncat docs/notes.txt\n' >"$R2/tests/test-doc-notes.sh"
printf '#!/bin/bash\ngrep -q x mainonly.txt 2>/dev/null; exit 0\n' >"$R2/tests/test-names-mainonly.sh"
printf '#!/bin/bash\nexit 0\n' >"$R2/tests/test-gone.sh"
g2 add -A
g2 commit -q -m base
g2 branch -q trunk
g2 checkout -q -b feat
g2 checkout -q trunk
printf 'x\n' >"$R2/mainonly.txt"
g2 add mainonly.txt
g2 commit -q -m "trunk moves on"
g2 checkout -q feat

out=$(ck2 --list .husky/pre-commit 2>&1)
assert_contains "an extensionless hook under a dotted directory is shellchecked" "lint	shellcheck	.husky/pre-commit" "$out"

out=$(ck2 --list notes.txt 2>&1)
assert_lacks "a top-level file sharing its name selects nothing by name" "test-doc-notes.sh" "$out"

out=$(ck2 --list --base trunk 2>&1)
assert_lacks "base: the merge base, not the base's tip" "test-names-mainonly.sh" "$out"

g2 mv scripts/old-name.sh scripts/new-name.sh
g2 commit -q -m rename
out=$(ck2 --list --base trunk 2>&1)
assert_contains "base: a renamed script's old-path consumers are selected" "test	tests/test-old.sh" "$out"

rm "$R2/tests/test-gone.sh"
out=$(ck2 --list --base HEAD 2>&1)
assert_lacks "base: a deleted test is not selected" "test-gone.sh" "$out"
g2 checkout -q -- tests/test-gone.sh

printf '#!/bin/sh\nexit 0\n' >"$R2/scripts/back\\slash.sh"
out=$(ck2 --list --base HEAD 2>&1)
assert_contains "base: a path git quotes is reported skipped" "skipped	path	" "$out"
rm "$R2/scripts/back\\slash.sh"

out=$(cd "$R2/scripts" && "$CHECK" --list .husky/pre-commit 2>&1)
assert_contains "paths are read from the repository root" "lint	shellcheck	.husky/pre-commit" "$out"

# --- branch-controlled names, bytes, and state ------------------------------------
printf '#!/bin/sh\nexit 0\n' >"$R2/-hook"
printf '#!/bin/sh\nexit 0\n' >"$R2/-l.sh"
out=$(ck2 --list --base HEAD 2>&1 </dev/null)
assert_contains "a dash-leading extensionless hook is read as a file" "lint	shellcheck	-hook" "$out"
: >"$T/lint-calls"
out=$(cd "$R2" && PATH="$STUB:$PATH" "$CHECK" --base HEAD 2>&1 </dev/null)
assert_contains "a dash-leading file reaches the linter as a path" "./-l.sh" "$(grep '^shellcheck' "$T/lint-calls")"
rm "$R2/-hook" "$R2/-l.sh"

csi=$(printf '\233')
printf '#!/bin/sh\nexit 0\n' >"$R2/scripts/a${csi}b.sh"
printf '#!/bin/bash\n# scripts/one.sh\nprintf "\\033[31mred\\233m\\n"\nexit 3\n' >"$R2/tests/test-noisy.sh"
all=$(cd "$R2" && PATH="$STUB:$PATH" "$CHECK" --base HEAD 2>&1 </dev/null)
if LC_ALL=C grep -q "$(printf '[\033\233]')" <<<"$all"; then
  fail "printed paths and dumped output carry no control bytes"
else
  ok "printed paths and dumped output carry no control bytes"
fi
assert_contains "the noisy test still fails visibly" "fail	test	tests/test-noisy.sh" "$all"
rm "$R2/scripts/a${csi}b.sh" "$R2/tests/test-noisy.sh"

mkdir -p "$T/realfleet"
# shellcheck disable=SC2016 # the fixture's variable is for the fixture's shell
printf '#!/bin/bash\n# scripts/one.sh\nmkdir -p "$PLANWRIGHT_FLEET_STATE_DIR" && touch "$PLANWRIGHT_FLEET_STATE_DIR/ledger"\n' >"$R2/tests/test-writes-fleet.sh"
out=$(cd "$R2" && PLANWRIGHT_FLEET_STATE_DIR=$T/realfleet "$CHECK" tests/test-writes-fleet.sh 2>&1 </dev/null)
assert_exit "a test writing the inherited fleet home fails" 1 $?
assert_contains "names the fleet-home write" "fleet home" "$out"
if [ -z "$(ls -A "$T/realfleet")" ]; then ok "the inherited fleet home is untouched"; else fail "the inherited fleet home is untouched"; fi
rm "$R2/tests/test-writes-fleet.sh"

# --- --lint-exclude ----------------------------------------------------------------
out=$(ck --list --lint-exclude docs/ --lint-exclude 'config/*.yml' --lint-exclude scripts/README.md \
  docs/README.md config/settings.yml scripts/README.md scripts/alpha.sh 2>&1)
assert_exit "--lint-exclude lists" 0 $?
assert_lacks "a directory exclusion skips its files' linting" "markdownlint-cli2	docs/README.md" "$out"
assert_lacks "a pattern exclusion skips matching files' linting" "yamllint	config/settings.yml" "$out"
assert_lacks "an exact exclusion skips that file's linting" "markdownlint-cli2	scripts/README.md" "$out"
assert_contains "an excluded file still selects its tests" "test	tests/test-doc-path.sh" "$out"
assert_contains "a file outside the exclusions is still linted" "lint	shellcheck	scripts/alpha.sh" "$out"
out=$(ck --list --lint-exclude '' docs/README.md 2>&1)
assert_exit "an empty --lint-exclude is refused" 2 $?
# --- refused inputs ------------------------------------------------------------
out=$(ck 2>&1)
assert_exit "no files and no base is a usage error" 2 $?
out=$(ck --base nosuchrev 2>&1)
assert_exit "an unknown base is refused" 2 $?
out=$(ck --list ../outside.sh 2>&1)
assert_exit "a path escaping the repo is refused" 2 $?

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all check-diff-scoped tests passed"
