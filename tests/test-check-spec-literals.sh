#!/bin/bash
# Tests for scripts/check-spec-literals.sh — the literal spec-home guard
# (custom-spec-location REQ-G1.1): a planted literal fails in every scanned
# location, while the resolver, comments, and the allowlisted classes pass.
# The planted lines are shell text written verbatim, never expanded here.
# shellcheck disable=SC2016
set -u
unset CDPATH

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
GUARD="$REPO_ROOT/scripts/check-spec-literals.sh"
SH=$(command -v dash || echo /bin/sh)

failures=0
ok() { echo "ok: $1"; }
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}

tmp="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/check-spec-literals.XXXXXX")" && pwd -P)" || exit 1
trap 'rm -rf "$tmp"' EXIT

# A clean tree carrying every scanned location.
fixture() {
  rm -rf "$tmp/r"
  mkdir -p "$tmp/r/scripts" "$tmp/r/githooks" "$tmp/r/.github/workflows" "$tmp/r/config"
  printf '#!/bin/sh\necho hello\n' >"$tmp/r/scripts/a.sh"
  printf '#!/bin/sh\necho b\n' >"$tmp/r/scripts/b.sh"
  printf '#!/bin/sh\nexit 0\n' >"$tmp/r/githooks/pre-commit"
  printf 'name: ci\njobs: {}\n' >"$tmp/r/.github/workflows/ci.yml"
  cat >"$tmp/r/mise.toml" <<'EOF'
[tools]
shfmt = "1"

[tasks.test]
description = "tests over specs/ bundles"
run = "echo test"
EOF
  printf 'pre-commit:\n  jobs: []\n' >"$tmp/r/lefthook.yml"
  printf '*.tmp\n' >"$tmp/r/.gitignore"
  printf '# class\tpath\tline\n' >"$tmp/r/config/spec-literal-allowlist.tsv"
  printf '# task\tpath\tline\n' >"$tmp/r/config/spec-literal-pending.tsv"
}

run() {
  "$SH" "$GUARD" --repo-root "$tmp/r" >"$tmp/out" 2>"$tmp/err"
  rc=$?
  out=$(cat "$tmp/out" "$tmp/err")
}

# expect <rc> <label> [<substring>] — assert the last run's exit and output.
expect() {
  if [ "$rc" -ne "$1" ]; then
    fail "$2 (exit $rc, expected $1): $out"
  elif [ -n "${3:-}" ] && case $out in *"$3"*) false ;; *) true ;; esac then
    fail "$2 (output lacks '$3'): $out"
  else
    ok "$2"
  fi
}

fixture
run
expect 0 "a clean tree passes" "clean (0 allowlisted, 0 pending migration)"

# --- A planted literal in each scanned location fails -----------------------

fixture
printf 'd="$root/specs/$id"\n' >>"$tmp/r/scripts/a.sh"
run
expect 1 "a literal in scripts/ fails" 'scripts/a.sh:3: d="$root/specs/$id"'

fixture
printf 'for d in specs/*/; do :; done\n' >>"$tmp/r/githooks/pre-commit"
run
expect 1 "a literal in githooks/ fails" "githooks/pre-commit:3:"

fixture
printf '\n[tasks.lint]\nrun = "lint specs/"\n' >>"$tmp/r/mise.toml"
run
expect 1 "a literal in a single-line mise run body fails" 'mise.toml:9: run = "lint specs/"'

fixture
printf "\n[tasks.check]\nrun = '''\necho start\nvalidate specs/\n'''\n" >>"$tmp/r/mise.toml"
run
expect 1 "a literal in a triple-quoted mise run body fails" "mise.toml:11: validate specs/"

fixture
printf '\n[tasks.many]\nrun = [\n  "echo a",\n  "ls specs/",\n]\n' >>"$tmp/r/mise.toml"
run
expect 1 "a literal in a mise run array fails" 'mise.toml:11: "ls specs/",'

fixture
printf '      glob: "specs/**"\n' >>"$tmp/r/lefthook.yml"
run
expect 1 "a literal in lefthook.yml fails" "lefthook.yml:3:"

fixture
printf 'specs/*/.lock\n' >>"$tmp/r/.gitignore"
run
expect 1 "a literal in .gitignore fails" ".gitignore:2: specs/*/.lock"

fixture
printf '      - run: scripts/spec-validate.sh specs/\n' >>"$tmp/r/.github/workflows/ci.yml"
run
expect 1 "a literal in a workflow fails" ".github/workflows/ci.yml:3:"

fixture
printf 'case $d in */specs) ;; esac\n' >>"$tmp/r/scripts/a.sh"
run
expect 1 "a path ending in /specs fails" "scripts/a.sh:3:"

fixture
printf '#!/bin/sh\nls specs/\n' >"$tmp/r/scripts/tool"
printf 'ls specs/\n' >"$tmp/r/scripts/notes.txt"
run
expect 1 "an extensionless script found by its shebang is scanned" "scripts/tool:2:"
case $out in
  *notes.txt*) fail "a non-shell file under scripts/ was scanned: $out" ;;
  *) ok "a non-shell file under scripts/ is not scanned" ;;
esac

# --- What passes ------------------------------------------------------------

fixture
cat >>"$tmp/r/scripts/a.sh" <<'EOF'
# the bundles live under specs/<id>/
  # indented: see "$root/specs" for the layout
echo x # trailing: specs/ is the default
echo "--specs/--fenced"
echo "a # in a string: specs/"
EOF
printf '# specs/**\n' >>"$tmp/r/lefthook.yml"
printf '# specs/*/.lock\n' >>"$tmp/r/.gitignore"
printf "\n[tasks.c]\nrun = '''\n# lint specs/ here\necho ok\n'''\n" >>"$tmp/r/mise.toml"
run
expect 1 "a # inside a string is not a comment" 'scripts/a.sh:7: echo "a # in a string: specs/"'
case $out in
  *":3:"* | *":4:"* | *":5:"* | *":6:"* | *lefthook* | *gitignore* | *mise.toml*)
    fail "a comment line or an option name was flagged: $out"
    ;;
  *) ok "full-line and trailing comments, an option name, and mise descriptions pass" ;;
esac

fixture
printf 'x=1 # specs/ there\n' >>"$tmp/r/.gitignore"
run
expect 1 "a trailing # in .gitignore is part of the pattern" ".gitignore:2:"

fixture
printf 'sr_primary=$rp_path/specs\n' >"$tmp/r/scripts/resolve-root.sh"
printf 'resolver\tscripts/resolve-root.sh\tsr_primary=$rp_path/specs\n' >>"$tmp/r/config/spec-literal-allowlist.tsv"
printf 'meta="Consumed-by: specs/$spec ($today)"\n' >>"$tmp/r/scripts/a.sh"
printf 'namespace\tscripts/a.sh\tmeta="Consumed-by: specs/$spec ($today)"\n' >>"$tmp/r/config/spec-literal-allowlist.tsv"
printf '      glob: "specs/**"\n' >>"$tmp/r/lefthook.yml"
printf 'static-glob\tlefthook.yml\tglob: "specs/**"\n' >>"$tmp/r/config/spec-literal-allowlist.tsv"
printf '  d=$repo/specs\n' >>"$tmp/r/scripts/b.sh"
printf '5\tscripts/b.sh\td=$repo/specs\n' >>"$tmp/r/config/spec-literal-pending.tsv"
run
expect 0 "the resolver, a namespace literal, a static glob, and a pending site pass" \
  "clean (3 allowlisted, 1 pending migration)"

# The same text in another file is not cleared by an entry for the first.
printf 'meta="Consumed-by: specs/$spec ($today)"\n' >>"$tmp/r/scripts/b.sh"
run
expect 1 "an entry clears its own file only" "scripts/b.sh:4:"

fixture
printf 'd=$repo/specs\n' >>"$tmp/r/scripts/b.sh"
printf '5\tscripts/b.sh\td=$repo/specs\n' >>"$tmp/r/config/spec-literal-pending.tsv"
printf 'namespace\tscripts/b.sh\td=$repo/specs\n' >>"$tmp/r/config/spec-literal-allowlist.tsv"
run
expect 2 "a site listed twice is refused" "listed more than once"

# --- Stale entries ----------------------------------------------------------

fixture
printf '5\tscripts/a.sh\td=$root/specs/$id\n' >>"$tmp/r/config/spec-literal-pending.tsv"
run
expect 1 "a pending entry whose site was migrated is stale" "pending row 2: scripts/a.sh: d=\$root/specs/\$id"

fixture
printf 'namespace\tscripts/a.sh\tgone="specs/$x"\n' >>"$tmp/r/config/spec-literal-allowlist.tsv"
run
expect 1 "an allowlist entry matching nothing is stale" "allowlist row 2:"

# --- Fail closed ------------------------------------------------------------

fixture
printf 'other\tscripts/a.sh\tx\n' >>"$tmp/r/config/spec-literal-allowlist.tsv"
run
expect 2 "an allowlist class outside the three is refused" "malformed list row"

fixture
printf 'resolver\tscripts/a.sh\tx\n' >>"$tmp/r/config/spec-literal-allowlist.tsv"
run
expect 2 "the resolver class names only the resolver" "malformed list row"

fixture
printf 'soon\tscripts/a.sh\tx\n' >>"$tmp/r/config/spec-literal-pending.tsv"
run
expect 2 "a pending row without a task id is refused" "malformed list row"

fixture
rm "$tmp/r/config/spec-literal-pending.tsv"
run
expect 2 "a missing list fails closed" "spec-literal-pending.tsv is missing"

fixture
rm -r "$tmp/r/githooks"
run
expect 2 "a missing scope directory fails closed" "githooks/ is missing"

fixture
rm "$tmp/r/scripts/a.sh" "$tmp/r/scripts/b.sh" "$tmp/r/githooks/pre-commit" "$tmp/r/.github/workflows/ci.yml"
run
expect 2 "an empty enumeration fails closed" "a broken enumeration"

fixture
printf 'ls specs/\n\033]0;pwned\007\n' >>"$tmp/r/scripts/a.sh"
printf 'echo "\033[31mspecs/\033[0m"\n' >>"$tmp/r/scripts/a.sh"
run
case $out in
  *$'\033'*) fail "a control byte from a scanned line reached the terminal" ;;
  *) ok "reported lines are stripped of control bytes" ;;
esac

# --- This repository --------------------------------------------------------

"$SH" "$GUARD" >"$tmp/out" 2>&1
rc=$?
out=$(cat "$tmp/out")
expect 0 "this repository passes its own guard"

echo
if [ "$failures" -eq 0 ]; then
  echo "all check-spec-literals tests passed"
  exit 0
fi
echo "$failures check-spec-literals test(s) failed" >&2
exit 1
