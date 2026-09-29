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
printf 'pushd specs\nfind specs -name x\nls specs\ngit -C specs status\n[ -e specs ]\n[ -f specs ]\n[ -r specs ]\n[ -s specs ]\n[ -L specs ]\n' >>"$tmp/r/scripts/a.sh"
run
for n in 3 4 5 6 7 8 9 10 11; do
  expect 1 "bare-operand form on line $n fails" "scripts/a.sh:$n:"
done

fixture
printf 'cd "specs"$sub\n[ -d '"'"'specs'"'"'${id:+/$id} ]\n' >>"$tmp/r/scripts/a.sh"
run
expect 1 "a quoted operand followed by an expansion fails" "scripts/a.sh:3:"
expect 1 "a quoted test operand followed by an expansion fails" "scripts/a.sh:4:"

fixture
for f in m z a q; do printf 'cd specs\n' >"$tmp/r/scripts/$f.sh"; done
run
order=$(printf '%s\n' "$out" | sed -n 's#^  scripts/\([a-z]\)\.sh:.*#\1#p' | tr -d '\n')
if [ "$order" = amqz ]; then ok "the report lists files in byte order"; else fail "report order was '$order'"; fi

fixture
printf 'for d in "$root"/"specs"/*/; do :; done\nd="$root"/'"'"'specs'"'"'/x\nd=$root/"specs"\ncd "$r/"specs\n' >>"$tmp/r/scripts/a.sh"
run
for n in 3 4 5 6; do
  expect 1 "a quote-split literal on line $n fails" "scripts/a.sh:$n:"
done

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
printf 'x=1\n' >>"$tmp/r/scripts/a.sh"
printf '\tcat <<-EOF\n\t# specs/in-body\n\tEOF\n# specs/after the body\n' >>"$tmp/r/scripts/a.sh"
run
expect 1 "a <<- heredoc body line is text" "scripts/a.sh:5:"
case $out in *"a.sh:7:"*) fail "the comment after a <<- heredoc was flagged: $out" ;; *) ok "a tab-indented terminator closes a <<- heredoc" ;; esac

fixture
mkdir -p "$tmp/r/scripts/lib"
printf 'd=$root/specs/x\n' >"$tmp/r/scripts/lib/x.sh"
run
expect 1 "a script in a subdirectory of scripts/ is scanned" "scripts/lib/x.sh:1:"

fixture
printf '\n[ tasks . lint ]\nrun = "ls specs/"\n[tasks.b]\n"run" = "ls specs/"\n[tasks.c]\nrun_windows = "dir specs/"\n[tasks]\nd . run = "ls specs/"\n' >>"$tmp/r/mise.toml"
run
expect 1 "a task header with spaces is read" 'mise.toml:9: run = "ls specs/"'
expect 1 "a quoted run key is read" 'mise.toml:11: "run" = "ls specs/"'
expect 1 "run_windows is read" 'mise.toml:13: run_windows = "dir specs/"'
expect 1 "a spaced dotted key under [tasks] is read" 'mise.toml:15: d . run = "ls specs/"'

fixture
printf '\n["tasks".q]\nrun = "cd specs"\n[tasks]\nshort = "cd specs"\nlisted = ["cd specs"]\nd.description = "specs/ prose"\n' >>"$tmp/r/mise.toml"
run
expect 1 "a quoted tasks header is read" 'mise.toml:9: run = "cd specs"'
expect 1 "a shorthand task string is read" 'mise.toml:11: short = "cd specs"'
expect 1 "a shorthand task array is read" 'mise.toml:12: listed = ["cd specs"]'
case $out in *"mise.toml:13:"*) fail "a dotted description key was scanned: $out" ;; *) ok "a dotted description key under [tasks] is not scanned" ;; esac

fixture
printf '\n[tasks]\n# old = "cd specs"\nd.description = """\nnote = cd specs\n"""\nd.run = "echo"\n' >>"$tmp/r/mise.toml"
run
expect 0 "a comment and a multi-line description under [tasks] are not tasks"

fixture
cat >>"$tmp/r/mise.toml" <<'EOF'

[tasks.a]
description = "use x = ''' here"
run = "cd specs"
EOF
run
expect 1 "a single-line value holding = ''' opens no skip" 'mise.toml:10: run = "cd specs"'

fixture
printf '\n[tasks.a]\ndescription = """\nsome text\n"""\n[tasks.b]\nrun = "cd specs"\n' >>"$tmp/r/mise.toml"
run
expect 1 "a run after a skipped description body still fails" 'mise.toml:13: run = "cd specs"'

fixture
printf '\n[tasks]\na.description = """\n[tasks.build] example\n"""\nb.run = "cd specs"\n' >>"$tmp/r/mise.toml"
run
expect 1 "a header-like line inside a description body leaves the section alone" 'mise.toml:12: b.run = "cd specs"'

fixture
printf 'tasks.short = "cd specs"\n' >"$tmp/r/mise.toml.new"
cat "$tmp/r/mise.toml" >>"$tmp/r/mise.toml.new"
mv "$tmp/r/mise.toml.new" "$tmp/r/mise.toml"
run
expect 1 "a root-level shorthand task is read" 'mise.toml:1: tasks.short = "cd specs"'

fixture
printf "grep -e 'specs\$' f\n" >>"$tmp/r/scripts/a.sh"
run
expect 0 "an anchored pattern is not a path operand"

fixture
printf 'tasks.lint.run = "ls specs/"\n' >"$tmp/r/mise.toml.new"
cat "$tmp/r/mise.toml" >>"$tmp/r/mise.toml.new"
mv "$tmp/r/mise.toml.new" "$tmp/r/mise.toml"
run
expect 1 "a root-level dotted tasks key is read" 'mise.toml:1: tasks.lint.run = "ls specs/"'

fixture
printf '\n[tasks.e]\nrun = ["a"] # a comment\ndescription = "specs/ in prose"\n' >>"$tmp/r/mise.toml"
run
expect 0 "a one-line run array with a trailing comment closes on its line"

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
printf 'cd "$root/specs"\n' >"$tmp/r/scripts/ok.sh
x.sh"
run
expect 2 "a scanned filename containing a newline is refused" "containing a newline or tab"

fixture
mkdir -p "$tmp/elsewhere"
printf '#!/bin/sh\n' >"$tmp/elsewhere/pre-commit"
rm -r "$tmp/r/githooks"
ln -s "$tmp/elsewhere" "$tmp/r/githooks"
run
expect 2 "a symlinked scope directory is refused" "githooks/ is a symlink"

fixture
mkdir -p "$tmp/r/scripts/lib"
ln -s "$tmp/outside" "$tmp/r/scripts/lib/x.sh"
run
expect 2 "a symlink below the top level is refused" "scripts/lib/x.sh is a symlink"

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

# A row is matched on its trimmed text, as the flagged line is.
fixture
printf 'd=$r/specs/x\n' >>"$tmp/r/scripts/a.sh"
printf 'namespace\tscripts/a.sh\t  d=$r/specs/x\n' >>"$tmp/r/config/spec-literal-allowlist.tsv"
run
expect 0 "a row carrying the line's indentation still clears it" "clean (1 allowlisted"

# Options before the operand do not hide it.
for line in 'ls -la specs' 'cd -- specs' 'find -H specs -name x'; do
  fixture
  printf '%s\n' "$line" >>"$tmp/r/scripts/a.sh"
  run
  expect 1 "a bare operand after options fails: $line" "scripts/a.sh:3: $line"
done

# An array may close on its last element's line; what follows is not a run value.
fixture
printf '\n[tasks.arr]\nrun = [\n  "echo a",\n  "echo b"]\ndescription = "about specs/ dirs"\n' >>"$tmp/r/mise.toml"
run
expect 0 "a run array closing on its last element ends there"

# A static glob lives only where a tool reads patterns statically.
fixture
printf 'd=$r/specs/x\n' >>"$tmp/r/scripts/a.sh"
printf 'static-glob\tscripts/a.sh\td=$r/specs/x\n' >>"$tmp/r/config/spec-literal-allowlist.tsv"
run
expect 2 "a static-glob row naming a script is refused" "static-glob class names only lefthook.yml and .gitignore"

# --- Shrink-only ---------------------------------------------------------------

fixture
printf 'd=$repo/specs\n' >>"$tmp/r/scripts/b.sh"
printf '5\tscripts/b.sh\td=$repo/specs\n' >>"$tmp/r/config/spec-literal-pending.tsv"
g() {
  GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 git -C "$tmp/r" -c user.name=t \
    -c user.email=t@example.invalid -c commit.gpgsign=false -c init.defaultBranch=main "$@" >/dev/null
}
guard() {
  "$SH" "$GUARD" --repo-root "$tmp/r" "$@" >"$tmp/out" 2>"$tmp/err"
  rc=$?
  out=$(cat "$tmp/out" "$tmp/err")
}
if ! { g init -q && g add -A && g commit -q -m base && g branch -f base; }; then fail "shrink fixture: git setup failed"; fi
run
case $out in *"shrink check skipped: origin/main does not resolve"*) ok "a base ref that does not resolve says the shrink check skipped" ;; *) fail "shrink skip not reported: $out" ;; esac
guard --base base
expect 0 "a pending list equal to the base's passes" "clean (0 allowlisted, 1 pending migration)"
printf 'e=$repo/specs\n' >>"$tmp/r/scripts/b.sh"
printf '5\tscripts/b.sh\te=$repo/specs\n' >>"$tmp/r/config/spec-literal-pending.tsv"
guard --base base
expect 1 "a pending row the base lacks fails" 'row 3: scripts/b.sh: e=$repo/specs'

# A copy of a row the base carries once is an added row too.
printf 'd=$repo/specs\n' >>"$tmp/r/scripts/b.sh"
sed -i.bak '$d' "$tmp/r/config/spec-literal-pending.tsv" && rm -f "$tmp/r/config/spec-literal-pending.tsv.bak"
sed -i.bak '$d' "$tmp/r/scripts/b.sh" && rm -f "$tmp/r/scripts/b.sh.bak"
printf '5\tscripts/b.sh\td=$repo/specs\n' >>"$tmp/r/config/spec-literal-pending.tsv"
printf 'd=$repo/specs\n' >>"$tmp/r/scripts/b.sh"
guard --base base
expect 1 "a second copy of a base row is an added row" 'row 3: scripts/b.sh: d=$repo/specs'

# A branch cut before a migration deleted rows reads the merge base's list.
fixture
printf 'x=$r/specs/x\ny=$r/specs/y\n' >>"$tmp/r/scripts/b.sh"
printf '5\tscripts/b.sh\tx=$r/specs/x\n5\tscripts/b.sh\ty=$r/specs/y\n' >>"$tmp/r/config/spec-literal-pending.tsv"
if ! { g init -q && g add -A && g commit -q -m base && g branch feat; }; then fail "merge-base fixture: git setup failed"; fi
sed -i.bak '$d' "$tmp/r/scripts/b.sh" && sed -i.bak '$d' "$tmp/r/config/spec-literal-pending.tsv"
rm -f "$tmp/r/scripts/b.sh.bak" "$tmp/r/config/spec-literal-pending.tsv.bak"
if ! { g commit -q -am migrate && g checkout -q feat; }; then fail "merge-base fixture: git setup failed"; fi
guard --base main
expect 0 "a branch behind the base is bounded by the merge base's list" "clean (0 allowlisted, 2 pending migration)"

fixture
printf 'x=$r/specs/x\n' >>"$tmp/r/scripts/b.sh"
printf '5\tscripts/b.sh\tx=$r/specs/x\n' >>"$tmp/r/config/spec-literal-pending.tsv"
mv "$tmp/r/config/spec-literal-pending.tsv" "$tmp/r/config/p.tmp"
if ! { g init -q && g add -A && g commit -q -m base; }; then fail "no-list fixture: git setup failed"; fi
mv "$tmp/r/config/p.tmp" "$tmp/r/config/spec-literal-pending.tsv"
guard --base main
expect 0 "a base without the list skips the shrink check and says so" \
  "shrink check skipped: the merge base of main and HEAD has no pending list"

# A repo root below another repository's toplevel reads its own list.
fixture
printf 'x=$r/specs/x\n' >>"$tmp/r/scripts/b.sh"
printf '5\tscripts/b.sh\tx=$r/specs/x\n' >>"$tmp/r/config/spec-literal-pending.tsv"
mkdir -p "$tmp/outer"
rm -rf "$tmp/outer/r"
mv "$tmp/r" "$tmp/outer/r"
printf '# the outer list\n' >"$tmp/outer/spec-literal-pending.tsv"
mkdir -p "$tmp/outer/config" && cp "$tmp/outer/spec-literal-pending.tsv" "$tmp/outer/config/"
if ! { GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 git -C "$tmp/outer" -c init.defaultBranch=main init -q \
  && GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 git -C "$tmp/outer" add -A \
  && GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 git -C "$tmp/outer" -c user.name=t \
    -c user.email=t@example.invalid -c commit.gpgsign=false commit -q -m base; } >/dev/null; then
  fail "nested fixture: git setup failed"
fi
"$SH" "$GUARD" --repo-root "$tmp/outer/r" --base main >"$tmp/out" 2>"$tmp/err"
rc=$?
out=$(cat "$tmp/out" "$tmp/err")
expect 0 "a nested repo root reads the base list at its own path" "clean (0 allowlisted, 1 pending migration)"
rm -rf "$tmp/outer"

for bad in '' '-'; do
  (cd "$tmp/r" && "$SH" "$GUARD" --repo-root "$bad" >"$tmp/out" 2>"$tmp/err")
  rc=$?
  out=$(cat "$tmp/out" "$tmp/err")
  expect 2 "--repo-root '$bad' is refused rather than read as the current or previous directory"
done

fixture
guard --base no-such-ref
expect 2 "an explicit --base that does not resolve is an error, not a skip" "--base no-such-ref does not resolve"

fixture
for bad in '' '-x'; do
  guard --base "$bad"
  expect 2 "--base '$bad' is refused" "--base must name a ref"
done

# --- This repository --------------------------------------------------------

# Against HEAD, so the verdict is the scan's alone and not the freshness of
# this clone's origin/main; check:spec-literals runs the real comparison.
"$SH" "$GUARD" --base HEAD >"$tmp/out" 2>&1
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
