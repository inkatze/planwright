#!/bin/bash
# Tests for scripts/check-entry-points.sh — the frozen entry-point guard.
#
# Each case builds a small fixture tree with a hand-written partition, so the
# guard's own rules are exercised without the partition's inputs; the real
# tree is covered by `mise run check:entry-points`.
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-check-entry-points.sh
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$here/.." && pwd)
G="$REPO_ROOT/scripts/check-entry-points.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -x "$G" ] || fail "scripts/check-entry-points.sh missing or not executable"

tmp=$(mktemp -d "${TMPDIR:-/tmp}/test-check-entry-points.XXXXXX") || fail "mktemp -d failed"
[ -n "$tmp" ] && [ -d "$tmp" ] || fail "mktemp -d produced no directory"
trap 'chmod -R u+w "$tmp" 2>/dev/null; rm -rf "$tmp"' EXIT

TAB=$(printf '\t')

# new_tree <dir>: a tree with a guard install, two entry points (a CLI a
# skill names and a hook reading its payload) and a library.
new_tree() {
  t=$1
  mkdir -p "$t/scripts" "$t/tests/fixtures"
  cp "$REPO_ROOT/scripts/check-entry-points.sh" "$REPO_ROOT/scripts/bounded-run.sh" "$t/scripts/"
  cat >"$t/scripts/cli.sh" <<'EOF'
#!/bin/sh
case ${1-} in
  --version) printf '%s\n' "cli 1.0" ;;
  *) printf '%s\n' "usage: cli.sh --version" >&2; exit 2 ;;
esac
EOF
  cat >"$t/scripts/hook.sh" <<'EOF'
#!/bin/sh
payload=$(cat)
case $payload in
  *Bash*) printf '%s\n' '{"decision":"allow"}' ;;
  *) exit 0 ;;
esac
EOF
  cat >"$t/scripts/lib.sh" <<'EOF'
lib_fn() { :; }
EOF
  chmod +x "$t/scripts/cli.sh" "$t/scripts/hook.sh"
  {
    printf 'path\ttier\tflag\tcallers\tmutation\tprofile\tunresolved\n'
    printf 'scripts/cli.sh\tskill-called\t-\tskill,test\t-\t-\t-\n'
    printf 'scripts/hook.sh\thook\t-\thook\t-\tcat\t-\n'
    printf 'scripts/lib.sh\tlibrary\t-\tscript\t-\t-\t-\n'
  } >"$t/partition.tsv"
  printf '%s\n' '{"tool_name":"Bash"}' >"$t/payload.json"
}

# guard <tree> [args...]: run the guard over a tree; output in $out, status
# in $rc.
guard() {
  t=$1
  shift
  out=$(/bin/sh "$t/scripts/check-entry-points.sh" --partition "$t/partition.tsv" "$@" 2>&1)
  rc=$?
}

# record_all <tree>
record_all() {
  guard "$1" --record scripts/cli.sh -- --version
  [ "$rc" -eq 0 ] || fail "recording cli.sh failed ($rc): $out"
  guard "$1" --record scripts/hook.sh --stdin "$1/payload.json"
  [ "$rc" -eq 0 ] || fail "recording hook.sh failed ($rc): $out"
}

expect() {
  want=$1 needle=$2 label=$3
  [ "$rc" -eq "$want" ] || fail "$label: exit $rc, want $want: $out"
  if [ -n "$needle" ]; then
    case $out in *"$needle"*) ;; *) fail "$label: output lacks '$needle': $out" ;; esac
  fi
}

# --- recording, then a clean pass ---
base="$tmp/base"
new_tree "$base"
record_all "$base"
fx="$base/tests/fixtures/entry-points"
[ "$(cat "$fx/scripts/cli.sh/stdout")" = "cli 1.0" ] || fail "record: cli.sh stdout not captured"
[ "$(cat "$fx/scripts/cli.sh/exit")" = 0 ] || fail "record: cli.sh exit not captured"
[ "$(cat "$fx/scripts/cli.sh/args")" = "--version" ] || fail "record: cli.sh args not captured"
[ "$(cat "$fx/scripts/cli.sh/stderr")" = empty ] || fail "record: cli.sh stderr class not empty"
cmp -s "$fx/scripts/hook.sh/stdin" "$base/payload.json" || fail "record: hook.sh stdin not captured"
guard "$base"
expect 0 "" "clean tree"

# A usage error is a contract too; its stderr class is the anchored line.
guard "$base" --record scripts/cli.sh -- --bogus
expect 0 "" "record a usage error"
[ "$(cat "$fx/scripts/cli.sh/stderr")" = 'match ^usage: cli\.sh --version$' ] \
  || fail "record: stderr class not escaped and anchored: $(cat "$fx/scripts/cli.sh/stderr")"
[ "$(cat "$fx/scripts/cli.sh/exit")" = 2 ] || fail "record: usage-error exit not captured"
guard "$base"
expect 0 "" "usage-error fixture passes"

# --- REQ-E1.2: a later entry point without a fixture ---
t="$tmp/new-ep"
cp -R "$base" "$t"
printf '#!/bin/sh\nexit 0\n' >"$t/scripts/late.sh"
chmod +x "$t/scripts/late.sh"
printf 'scripts/late.sh\tskill-called\t-\tskill\t-\t-\t-\n' >>"$t/partition.tsv"
guard "$t"
expect 1 "scripts/late.sh: an entry point with no recorded fixture" "later entry point without a fixture"

# --- REQ-E1.2: a removed entry point ---
t="$tmp/removed"
cp -R "$base" "$t"
rm "$t/scripts/cli.sh"
grep -v '^scripts/cli.sh' "$base/partition.tsv" >"$t/partition.tsv"
guard "$t"
expect 1 "scripts/cli.sh: a recorded entry point is gone from the tree" "removed entry point"

# --- REQ-E1.2: a changed exit code ---
t="$tmp/exit"
cp -R "$base" "$t"
sed 's/exit 2/exit 3/' "$base/scripts/cli.sh" >"$t/scripts/cli.sh"
guard "$t"
expect 1 "scripts/cli.sh: exit 3, recorded 2" "changed exit code"

# A changed stdout byte and a stderr outside its class fail too.
t="$tmp/stdout"
cp -R "$base" "$t"
sed 's/allow/approve/' "$base/scripts/hook.sh" >"$t/scripts/hook.sh"
guard "$t"
expect 1 "scripts/hook.sh: stdout differs from the recorded bytes" "changed stdout"
t="$tmp/stderr"
cp -R "$base" "$t"
sed 's/usage: cli.sh/cli.sh: usage/' "$base/scripts/cli.sh" >"$t/scripts/cli.sh"
guard "$t"
expect 1 "scripts/cli.sh: stderr is not in the recorded class" "changed stderr class"

# --- REQ-A1.3: a shim of a flagged script ---
t="$tmp/shim-flagged-target"
cp -R "$base" "$t"
cat >"$t/scripts/shim.sh" <<'EOF'
#!/bin/sh
# planwright-shim-target: scripts/old.sh
exec /bin/sh "$(dirname "$0")/old.sh" "$@"
EOF
printf '#!/bin/sh\nexit 0\n' >"$t/scripts/old.sh"
printf 'scripts/shim.sh\tlibrary\t-\tscript\t-\t-\t-\n' >>"$t/partition.tsv"
printf 'scripts/old.sh\ttests-only\tno-live-caller\ttest\t-\t-\t-\n' >>"$t/partition.tsv"
guard "$t"
expect 1 "scripts/shim.sh: delegates to scripts/old.sh, which the partition flags" "shim of a flagged script"
# The same shim delegating to a live script is fine.
t2="$tmp/shim-live-target"
cp -R "$t" "$t2"
sed "s/^scripts\/old.sh${TAB}tests-only${TAB}no-live-caller/scripts\/old.sh${TAB}library${TAB}-/" "$t/partition.tsv" >"$t2/partition.tsv"
guard "$t2"
expect 0 "" "shim of a live script"
# A marker spelled so the lookup would miss it is a finding, not a skip.
flagged_shim_tree="$tmp/shim-flagged-target"
for spelling in './scripts/old.sh' 'scripts/old.sh extra'; do
  t4="$tmp/shim-spelling"
  rm -rf "$t4"
  cp -R "$flagged_shim_tree" "$t4"
  printf '#!/bin/sh\n# planwright-shim-target: %s\nexit 0\n' "$spelling" >"$t4/scripts/shim.sh"
  guard "$t4"
  expect 1 "scripts/shim.sh: its planwright-shim-target is not one repository path" "shim marker spelled '$spelling'"
done
# Trailing whitespace and a CR are read through to the flagged target.
printf '#!/bin/sh\n#  planwright-shim-target:\tscripts/old.sh \r\nexit 0\n' >"$t4/scripts/shim.sh"
guard "$t4"
expect 1 "scripts/shim.sh: delegates to scripts/old.sh, which the partition flags" "shim marker with loose spacing and a CR"
# A shim the partition flags is a flagged script migrated.
t3="$tmp/shim-flagged-self"
cp -R "$t2" "$t3"
sed "s/^scripts\/shim.sh${TAB}library${TAB}-/scripts\/shim.sh${TAB}tests-only${TAB}no-live-caller/" "$t2/partition.tsv" >"$t3/partition.tsv"
guard "$t3"
expect 1 "scripts/shim.sh: a shim the partition flags" "flagged shim"

# --- REQ-E1.2: a shim exiting with the reserved fetch-failure code ---
t="$tmp/reserved"
cp -R "$base" "$t"
cat >"$t/scripts/cli.sh" <<'EOF'
#!/bin/sh
# planwright-shim-target: cli-artifact
printf '%s\n' "cli: artifact not verified; set the shell selector" >&2
exit 69
EOF
chmod +x "$t/scripts/cli.sh"
guard "$t"
expect 1 "scripts/cli.sh: exited 69, the reserved fetch-failure code" "reserved fetch-failure code"
# Recorded or not: a fixture claiming the code still fails, and recording
# refuses it.
printf '69\n' >"$t/tests/fixtures/entry-points/scripts/cli.sh/exit"
guard "$t"
expect 1 "the reserved fetch-failure code" "reserved code recorded in the fixture"
guard "$t" --record scripts/cli.sh -- --version
expect 5 "reserved fetch-failure code" "recording the reserved code"

# --- stale fixtures and the execute bit ---
t="$tmp/stale"
cp -R "$base" "$t"
sed "s/^scripts\/cli.sh${TAB}skill-called${TAB}-${TAB}skill,test/scripts\/cli.sh${TAB}tests-only${TAB}-${TAB}test/" "$base/partition.tsv" >"$t/partition.tsv"
guard "$t"
expect 1 "scripts/cli.sh: no longer an entry point, so its fixture is stale" "stale fixture"
t="$tmp/noexec"
cp -R "$base" "$t"
chmod -x "$t/scripts/hook.sh"
guard "$t"
expect 1 "scripts/hook.sh: not executable" "entry point lost its execute bit"

# --- recording refusals ---
t="$tmp/nondeterministic"
cp -R "$base" "$t"
cat >"$t/scripts/cli.sh" <<'EOF'
#!/bin/sh
pwd
EOF
guard "$t" --record scripts/cli.sh
expect 5 "two runs differ" "recording a nondeterministic run"
guard "$base" --record scripts/lib.sh
expect 1 "not an entry point" "recording a non-entry-point"
guard "$base" --record ../escape.sh
expect 5 "outside the path grammar" "recording a path outside the grammar"

# --- isolation: a run writes nowhere but its sandbox ---
t="$tmp/isolation"
cp -R "$base" "$t"
cat >"$t/scripts/cli.sh" <<'EOF'
#!/bin/sh
true >scripts/written-by-run 2>/dev/null && printf 'tree writable\n'
: >"$HOME/x" && [ -z "$(ls "$TMPDIR")" ] && printf 'home %s\n' "${CLAUDE_PLUGIN_ROOT-unset}"
EOF
guard "$t" --record scripts/cli.sh
expect 0 "" "record an isolation probe"
[ "$(cat "$t/tests/fixtures/entry-points/scripts/cli.sh/stdout")" = "home unset" ] \
  || fail "isolation: the run saw a writable tree or an inherited environment: $(cat "$t/tests/fixtures/entry-points/scripts/cli.sh/stdout")"
[ ! -e "$t/scripts/written-by-run" ] || fail "isolation: the run wrote into the real tree"
CLAUDE_PLUGIN_ROOT=/elsewhere guard "$t"
expect 0 "" "an inherited variable does not reach the run"

# --- fail-closed inputs ---
t="$tmp/malformed"
cp -R "$base" "$t"
printf 'sometimes\n' >"$t/tests/fixtures/entry-points/scripts/cli.sh/stderr"
guard "$t"
expect 5 "stderr class is malformed" "malformed stderr class"
# A second line would read as a second class the guard never evaluates.
for extra in '\nmatch ^never$\n' '\nmatch ^never$'; do
  printf 'empty%b' "$extra" >"$t/tests/fixtures/entry-points/scripts/cli.sh/stderr"
  guard "$t"
  expect 5 "stderr class is malformed" "stderr class with a second line"
done
t="$tmp/badexit"
cp -R "$base" "$t"
printf 'two\n' >"$t/tests/fixtures/entry-points/scripts/cli.sh/exit"
guard "$t"
expect 5 "exit is not a number" "malformed exit"
# An unreadable fixture file fails closed rather than reusing the previous
# entry point's run (unenforceable as root, where every file reads).
if [ "$(id -u)" -ne 0 ]; then
  for f in stdin stderr; do
    t="$tmp/unreadable-$f"
    cp -R "$base" "$t"
    chmod 000 "$t/tests/fixtures/entry-points/scripts/hook.sh/$f"
    guard "$t"
    expect 5 "scripts/hook.sh: the fixture's $f" "unreadable fixture $f"
    chmod 644 "$t/tests/fixtures/entry-points/scripts/hook.sh/$f"
  done
fi
# Re-recording replaces the fixture whole: a stdin the new recording does not
# feed is gone.
t="$tmp/rerecord"
cp -R "$base" "$t"
guard "$t" --record scripts/hook.sh
expect 0 "" "re-record without stdin"
[ ! -e "$t/tests/fixtures/entry-points/scripts/hook.sh/stdin" ] || fail "re-record kept the old stdin"
[ ! -s "$t/tests/fixtures/entry-points/scripts/hook.sh/stdout" ] || fail "re-record kept the old stdout"
t="$tmp/header"
cp -R "$base" "$t"
sed '1s/^path/file/' "$base/partition.tsv" >"$t/partition.tsv"
guard "$t"
expect 5 "header" "unexpected partition header"
# A body row short of a column, or with one emptied, would drop its entry
# point or its flag without a word.
for row in "scripts/late.sh${TAB}skill-called${TAB}-${TAB}skill" \
  "scripts/late.sh${TAB}skill-called${TAB}-${TAB}skill${TAB}-${TAB}-${TAB}-${TAB}-" \
  "scripts/late.sh${TAB}skill-called${TAB}${TAB}skill${TAB}-${TAB}-${TAB}-"; do
  cp "$base/partition.tsv" "$t/partition.tsv"
  printf '%s\n' "$row" >>"$t/partition.tsv"
  guard "$t"
  expect 5 "a partition row" "malformed partition row"
done
out=$(/bin/sh "$base/scripts/check-entry-points.sh" --bogus 2>&1)
rc=$?
expect 2 "usage:" "unknown option"
out=$(/bin/sh "$base/scripts/check-entry-points.sh" 2>&1)
rc=$?
expect 2 "usage:" "no partition"

echo "PASS: test-check-entry-points"
