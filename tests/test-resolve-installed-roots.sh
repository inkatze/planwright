#!/bin/bash
# Tests for scripts/resolve-installed-roots.sh — the one computation of "which
# roots did Claude Code install planwright at" that the worker-command-guard's
# installed-root arm and the stream-json launch preflight both read. Plain bash
# 3.2, no test framework (the sibling resolver suites follow the same
# inline-assert convention).
set -u
unset CDPATH

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RESOLVER="$REPO_ROOT/scripts/resolve-installed-roots.sh"

failures=0
assert_eq() {
  # assert_eq <description> <expected> <actual>
  if [ "$2" = "$3" ]; then
    echo "ok: $1"
  else
    echo "FAIL: $1 (expected '$2', got '$3')" >&2
    failures=$((failures + 1))
  fi
}

[ -f "$RESOLVER" ] || {
  echo "FAIL: resolver script missing at $RESOLVER" >&2
  exit 1
}
command -v jq >/dev/null 2>&1 || {
  echo "FAIL: jq is required to build the record fixtures" >&2
  exit 1
}

SANDBOX="$(mktemp -d)" || exit 1
trap 'rm -rf "$SANDBOX"' EXIT

# run [ENV=val...] — the resolver under a pinned environment; stdout captured,
# exit status in CODE. Ambient CLAUDE_DIR and HOME never leak in.
run() {
  OUT=$(env -u CLAUDE_DIR -u HOME "$@" /bin/sh "$RESOLVER" 2>/dev/null)
  CODE=$?
}

cdir="$SANDBOX/cdir"
mkdir -p "$cdir/plugins"

# --- no home at all: nothing printed, never a failure -------------------------
run
assert_eq "no CLAUDE_DIR and no HOME prints nothing" "" "$OUT"
assert_eq "no CLAUDE_DIR and no HOME exits 0" 0 "$CODE"
run "CLAUDE_DIR=$SANDBOX/no-such-dir"
assert_eq "a missing claude dir prints nothing" "" "$OUT"
assert_eq "a missing claude dir exits 0" 0 "$CODE"

# --- the installed record: the planwright entries, array and object forms -----
jq -n --arg a "$cdir/inst/a/0.1.0" --arg b "$cdir/inst/b/0.2.0" \
  '{version: 2, plugins: {
      "planwright@planwright": [{scope: "user", installPath: $a, version: "0.1.0"}],
      "planwright@other-mkt": {installPath: $b},
      "planwright-evil@mkt": [{installPath: "/tmp/evil"}],
      "other@mkt": [{installPath: "/tmp/other"}],
      "planwright@rel": [{installPath: "relative/path"}],
      "planwright@num": [{installPath: 42}],
      "planwright@none": [{version: "0.3.0"}]}}' >"$cdir/plugins/installed_plugins.json"
run "CLAUDE_DIR=$cdir"
assert_eq "array-form and object-form planwright entries print their installPath, nothing else does" \
  "$cdir/inst/a/0.1.0
$cdir/inst/b/0.2.0" "$OUT"
assert_eq "a record read exits 0" 0 "$CODE"

# --- HOME fallback: <HOME>/.claude when CLAUDE_DIR is unset -------------------
home="$SANDBOX/home"
mkdir -p "$home/.claude/plugins"
jq -n --arg a "$home/inst/0.9.0" \
  '{plugins: {"planwright@planwright": [{installPath: $a}]}}' >"$home/.claude/plugins/installed_plugins.json"
run "HOME=$home"
assert_eq "HOME/.claude is read when CLAUDE_DIR is unset" "$home/inst/0.9.0" "$OUT"
run "HOME=$home" "CLAUDE_DIR=$cdir"
assert_eq "CLAUDE_DIR wins over HOME" "$cdir/inst/a/0.1.0
$cdir/inst/b/0.2.0" "$OUT"

# --- the marketplace cache: every planwright version dir, no other plugin -----
mkdir -p "$cdir/plugins/cache/mkt/planwright/0.4.0" "$cdir/plugins/cache/mkt/planwright/0.5.0" \
  "$cdir/plugins/cache/mkt/otherplugin/0.4.0" "$cdir/plugins/cache/mkt/planwright-evil/0.4.0"
: >"$cdir/plugins/cache/mkt/planwright/not-a-dir"
run "CLAUDE_DIR=$cdir"
assert_eq "record entries first, then each cached planwright version directory" \
  "$cdir/inst/a/0.1.0
$cdir/inst/b/0.2.0
$cdir/plugins/cache/mkt/planwright/0.4.0
$cdir/plugins/cache/mkt/planwright/0.5.0" "$OUT"

# --- a record it cannot read yields nothing from the record, the cache still ---
printf '{not json' >"$cdir/plugins/installed_plugins.json"
run "CLAUDE_DIR=$cdir"
assert_eq "a malformed record contributes nothing; the cache walk survives it" \
  "$cdir/plugins/cache/mkt/planwright/0.4.0
$cdir/plugins/cache/mkt/planwright/0.5.0" "$OUT"
assert_eq "a malformed record still exits 0" 0 "$CODE"
jq -n --arg a "$cdir/inst/a/0.1.0" \
  '{plugins: {"planwright@planwright": [{installPath: $a}]}}' >"$cdir/plugins/installed_plugins.json"
run "CLAUDE_DIR=$cdir" "PATH=$SANDBOX/no-bin"
assert_eq "without jq the record contributes nothing; the cache walk needs no jq" \
  "$cdir/plugins/cache/mkt/planwright/0.4.0
$cdir/plugins/cache/mkt/planwright/0.5.0" "$OUT"
assert_eq "without jq the resolver still exits 0" 0 "$CODE"

# --- a root reached through a symlink is never printed -------------------------
# Callers canonicalize, so a printed symlinked root would trust its target.
ldir="$SANDBOX/linked"
mkdir -p "$ldir/plugins/cache/mkt/planwright/1.0.0" "$SANDBOX/elsewhere/v" \
  "$SANDBOX/elsewhere/mkt2/planwright/2.0.0" "$SANDBOX/elsewhere/pw/3.0.0"
ln -s "$SANDBOX/elsewhere/v" "$ldir/plugins/cache/mkt/planwright/9.9.9"
ln -s "$SANDBOX/elsewhere/mkt2" "$ldir/plugins/cache/mkt2"
mkdir -p "$ldir/plugins/cache/mkt3"
ln -s "$SANDBOX/elsewhere/pw" "$ldir/plugins/cache/mkt3/planwright"
mkdir -p "$SANDBOX/real-root"
ln -s "$SANDBOX/real-root" "$SANDBOX/link-root"
jq -n --arg a "$SANDBOX/link-root//" --arg b "$ldir/plugins/cache/mkt2/planwright/2.0.0" \
  --arg c "$SANDBOX/real-root" \
  '{plugins: {"planwright@planwright": [{installPath: $a}, {installPath: $b}, {installPath: $c}]}}' \
  >"$ldir/plugins/installed_plugins.json"
run "CLAUDE_DIR=$ldir"
assert_eq "symlinked leaves, marketplace and plugin dirs are dropped from both arms" \
  "$SANDBOX/real-root
$ldir/plugins/cache/mkt/planwright/1.0.0" "$OUT"
OUT=$(env -u HOME CLAUDE_DIR="$ldir" /bin/sh "$RESOLVER" --refused 2>/dev/null)
assert_eq "--refused lists exactly the dropped candidates, for the launch preflight" \
  "$SANDBOX/link-root//
$ldir/plugins/cache/mkt2/planwright/2.0.0
$ldir/plugins/cache/mkt/planwright/9.9.9
$ldir/plugins/cache/mkt2/planwright/2.0.0
$ldir/plugins/cache/mkt3/planwright/3.0.0" "$OUT"
/bin/sh "$RESOLVER" --unlinked "$ldir/plugins/cache/mkt/planwright/1.0.0/"
assert_eq "--unlinked passes a real cache root" 0 "$?"
/bin/sh "$RESOLVER" --unlinked "$ldir/plugins/cache/mkt2/planwright/2.0.0"
assert_eq "--unlinked refuses a root under a symlinked marketplace dir" 1 "$?"
/bin/sh "$RESOLVER" --unlinked "$SANDBOX/link-root//"
assert_eq "--unlinked refuses a symlinked leaf behind trailing slashes" 1 "$?"
/bin/sh "$RESOLVER" --unlinked 2>/dev/null
assert_eq "--unlinked without a path is a usage error" 2 "$?"
# A `.` or `..` component hides a symlink from `[ -L ]`, which follows the
# link when the path ends in `/.`, so any such component is refused.
mkdir -p "$SANDBOX/real-root/x"
for shape in "link-root/." "link-root/./" "link-root/x/.." "real-root/../link-root"; do
  /bin/sh "$RESOLVER" --unlinked "$SANDBOX/$shape"
  assert_eq "--unlinked refuses $shape" 1 "$?"
done
dots="$SANDBOX/dots"
mkdir -p "$dots/plugins"
jq -n --arg a "$SANDBOX/link-root/." --arg b "$SANDBOX/link-root/./" --arg c "$SANDBOX/link-root/x/.." \
  '{plugins: {"planwright@planwright": [{installPath: $a}, {installPath: $b}, {installPath: $c}]}}' \
  >"$dots/plugins/installed_plugins.json"
run "CLAUDE_DIR=$dots"
assert_eq "a symlinked root behind a dot component is never listed" "" "$OUT"
OUT=$(env -u HOME CLAUDE_DIR="$dots" /bin/sh "$RESOLVER" --refused 2>/dev/null)
assert_eq "--refused lists every dot-component shape" \
  "$SANDBOX/link-root/.
$SANDBOX/link-root/./
$SANDBOX/link-root/x/.." "$OUT"

if [ "$failures" -gt 0 ]; then
  echo "resolve-installed-roots suite: $failures failure(s)" >&2
  exit 1
fi
echo "all resolve-installed-roots tests passed"
