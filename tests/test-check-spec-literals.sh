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
expect 0 "a clean tree passes" "clean (0 allowlisted, 0 pending migration"

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
printf 'real=$(cd specs && pwd -P)\n[ -d "specs" ] || exit 1\necho "no such specs dir"\n' >>"$tmp/r/scripts/a.sh"
run
expect 1 "a bare specs operand of cd fails" "scripts/a.sh:3:"
expect 1 "a bare specs operand of a file test fails" "scripts/a.sh:4:"
case $out in *"a.sh:5:"*) fail "a bare specs in prose was flagged: $out" ;; *) ok "a bare specs in prose passes" ;; esac

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
  "clean (3 allowlisted, 1 pending migration"

# The same text in another file is not cleared by an entry for the first.
printf 'meta="Consumed-by: specs/$spec ($today)"\n' >>"$tmp/r/scripts/b.sh"
run
expect 1 "an entry clears its own file only" "scripts/b.sh:4:"

fixture
printf 'd=$repo/specs\nd=$repo/specs\n' >>"$tmp/r/scripts/b.sh"
printf '5\tscripts/b.sh\td=$repo/specs\n' >>"$tmp/r/config/spec-literal-pending.tsv"
run
expect 1 "one row clears one occurrence: a copied line fails" "scripts/b.sh:4: d=\$repo/specs"
printf '5\tscripts/b.sh\td=$repo/specs\n' >>"$tmp/r/config/spec-literal-pending.tsv"
run
expect 0 "a second row clears the second occurrence" "clean (0 allowlisted, 2 pending migration"

fixture
printf 'x=specs/a\tEVIL specs/b\n' >>"$tmp/r/scripts/a.sh"
printf 'namespace\tscripts/a.sh\tx=specs/a\n' >>"$tmp/r/config/spec-literal-allowlist.tsv"
run
expect 1 "text after an internal tab is part of the line" "scripts/a.sh:3: x=specs/a EVIL specs/b"
case $out in *"allowlist row 2"*) ok "the shorter row does not clear the tabbed line" ;; *) fail "the tabbed line was cleared: $out" ;; esac

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
expect 1 "a line carrying control bytes is still reported" "scripts/a.sh:3: ls specs/"
case $out in
  *$'\033'* | *$'\007'*) fail "a control byte from a scanned line reached the terminal" ;;
  *) ok "reported lines are stripped of control bytes" ;;
esac

# --- Parsing edges ---------------------------------------------------------

fixture
cat >>"$tmp/r/scripts/a.sh" <<'EOF'
cat <<DOC
see the docs # at specs/demo
# heading: specs/layout
DOC
echo "\" # specs/x"
EOF
run
expect 1 "a # inside a heredoc body is text" "scripts/a.sh:4: see the docs # at specs/demo"
expect 1 "a #-line inside a heredoc body is text" "scripts/a.sh:5: # heading: specs/layout"
expect 1 "an escaped quote does not open a comment" 'scripts/a.sh:7: echo "\" # specs/x"'

fixture
printf '\n[tasks.x]\nrun = [\n  "[ -d foo ] && echo ok",\n  "bash scripts/v.sh specs/",\n]\n' >>"$tmp/r/mise.toml"
run
expect 1 "a ] inside an array string does not end the array" 'mise.toml:11: "bash scripts/v.sh specs/",'

fixture
printf '\n[tasks]\nx = { run = "bash scripts/v.sh specs/" }\ny.run = "ls specs/"\n' >>"$tmp/r/mise.toml"
run
expect 1 "an inline-table task under [tasks] is scanned" 'mise.toml:9: x = { run = "bash scripts/v.sh specs/" }'
expect 1 "a dotted run key under [tasks] is scanned" 'mise.toml:10: y.run = "ls specs/"'

rm -rf "$tmp/pending-root"
fixture
mv "$tmp/r" "$tmp/pending-root"
printf 'x=specs/a\n' >>"$tmp/pending-root/scripts/a.sh"
printf 'namespace\tscripts/a.sh\tx=specs/a\n' >>"$tmp/pending-root/config/spec-literal-allowlist.tsv"
"$SH" "$GUARD" --repo-root "$tmp/pending-root" >"$tmp/out" 2>"$tmp/err"
rc=$?
out=$(cat "$tmp/out" "$tmp/err")
expect 0 "a root path containing 'pending' reads the allowlist as the allowlist" "clean (1 allowlisted"
rm -rf "$tmp/pending-root"

# --- Refusals ----------------------------------------------------------------

fixture
printf 'SECRET=1 specs/x\n' >"$tmp/outside"
ln -s "$tmp/outside" "$tmp/r/scripts/leak.sh"
run
expect 2 "a symlinked scanned file is refused, not followed" "leak.sh is a symlink"
case $out in *SECRET*) fail "the symlink target's content was printed" ;; *) ok "the symlink target's content is not printed" ;; esac

fixture
printf '#!/bin/sh\nls specs/\n' >"$tmp/r/scripts/tool"
chmod 000 "$tmp/r/scripts/tool"
if [ -r "$tmp/r/scripts/tool" ]; then
  ok "an unreadable extensionless script is refused (skipped: running as a user who can read mode 000)"
else
  run
  expect 2 "an unreadable extensionless script is refused" "cannot read scripts/tool"
fi
chmod 644 "$tmp/r/scripts/tool"

# An awk pass that fails is a scan that did not complete, never a clean one.
mkdir -p "$tmp/shim"
real_awk=$(command -v awk)
for n in 1 2; do
  cat >"$tmp/shim/awk" <<EOF
#!/bin/sh
c=\$(cat "$tmp/shim/count" 2>/dev/null || echo 0)
c=\$((c + 1))
echo "\$c" >"$tmp/shim/count"
[ "\$c" -eq $n ] && exit 1
exec "$real_awk" "\$@"
EOF
  chmod +x "$tmp/shim/awk"
  rm -f "$tmp/shim/count"
  fixture
  printf 'ls specs/\n' >>"$tmp/r/scripts/a.sh"
  PATH="$tmp/shim:$PATH" "$SH" "$GUARD" --repo-root "$tmp/r" >"$tmp/out" 2>"$tmp/err"
  rc=$?
  out=$(cat "$tmp/out" "$tmp/err")
  expect 2 "a failing awk pass $n fails closed" "could not complete"
done

# --- Shrink-only ---------------------------------------------------------------

fixture
printf 'd=$repo/specs\n' >>"$tmp/r/scripts/b.sh"
printf '5\tscripts/b.sh\td=$repo/specs\n' >>"$tmp/r/config/spec-literal-pending.tsv"
g() { git -C "$tmp/r" -c user.name=t -c user.email=t@example.invalid "$@" >/dev/null 2>&1; }
g init -q
g add -A
g commit -q -m base
g branch -f base
run
case $out in *"shrink check skipped"*) ok "without --base naming a ref the shrink check says it skipped" ;; *) fail "shrink skip not reported: $out" ;; esac
"$SH" "$GUARD" --repo-root "$tmp/r" --base base >"$tmp/out" 2>"$tmp/err"
rc=$?
out=$(cat "$tmp/out" "$tmp/err")
expect 0 "a pending list equal to the base's passes" "clean (0 allowlisted, 1 pending migration)"
printf 'e=$repo/specs\n' >>"$tmp/r/scripts/b.sh"
printf '5\tscripts/b.sh\te=$repo/specs\n' >>"$tmp/r/config/spec-literal-pending.tsv"
"$SH" "$GUARD" --repo-root "$tmp/r" --base base >"$tmp/out" 2>"$tmp/err"
rc=$?
out=$(cat "$tmp/out" "$tmp/err")
expect 1 "a pending row the base lacks fails" 'row 3: scripts/b.sh: e=$repo/specs'

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
