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
# Canonical, so a symlinked temp dir (macOS) only goes where a case puts one.
SANDBOX=$(cd -P "$SANDBOX" && pwd -P) || exit 1
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
/bin/sh "$RESOLVER" --unlinked "$ldir/plugins//cache/mkt2/planwright/2.0.0"
assert_eq "--unlinked refuses the same root written with plugins//cache" 1 "$?"
(cd "$ldir" && /bin/sh "$RESOLVER" --unlinked plugins/cache/mkt2/planwright/2.0.0)
assert_eq "--unlinked refuses a relative path, which the cache walk cannot anchor" 1 "$?"
/bin/sh "$RESOLVER" --unlinked "$ldir//plugins/cache/mkt/planwright/1.0.0"
assert_eq "--unlinked still passes a real root written with a doubled slash" 0 "$?"
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

# --- --current: the installed record alone, never the cache walk --------------
cur="$SANDBOX/cur"
old_copy="$cur/plugins/cache/planwright/planwright/0.65.0"
new_copy="$cur/plugins/cache/planwright/planwright/0.66.0"
mkdir -p "$cur/plugins"
# Only what the stale-copy cases below run.
for copy in "$old_copy" "$new_copy"; do
  mkdir -p "$copy/scripts" "$copy/doctrine"
  for f in resolve-root.sh resolve-installed-roots.sh resolve-rule-doc.sh resolve-overlay-root.sh \
    mc-event.sh mc-lib.sh echo-safety.sh fleet-dispatch-env.sh step-record.sh lock-lib.sh \
    mission-control-launch.sh fleet-launch-profile.sh; do
    cp "$REPO_ROOT/scripts/$f" "$copy/scripts/"
  done
  mkdir -p "$copy/config"
  cp "$REPO_ROOT/config/worker-settings.json" "$copy/config/"
  cp "$REPO_ROOT/doctrine/plugin-script-invocation.md" "$copy/doctrine/"
done
jq -n --arg a "$new_copy" '{plugins: {"planwright@planwright": [{scope: "user", installPath: $a, version: "0.66.0"}]}}' \
  >"$cur/plugins/installed_plugins.json"
OUT=$(env -u HOME CLAUDE_DIR="$cur" /bin/sh "$RESOLVER" --current 2>/dev/null)
assert_eq "--current prints the installed root alone, no older cached copy" "$new_copy" "$OUT"
OUT=$(env -u HOME CLAUDE_DIR="$cur" PATH="$SANDBOX/no-bin" /bin/sh "$RESOLVER" --current 2>/dev/null)
assert_eq "--current without jq prints nothing" "" "$OUT"
OUT=$(env -u HOME CLAUDE_DIR="$SANDBOX/no-such-dir" /bin/sh "$RESOLVER" --current 2>/dev/null)
assert_eq "--current with no record prints nothing" "" "$OUT"
for bad in "--current x" "--check" "--check ''" "--check a b"; do
  # shellcheck disable=SC2086 # each case is a word list on purpose
  eval "env -u HOME CLAUDE_DIR=\"\$cur\" /bin/sh \"\$RESOLVER\" $bad" >/dev/null 2>&1
  assert_eq "usage refused: $bad" 2 "$?"
done

# Scopes: a project or local install applies only under its project, before
# the user-scope one; another project's install never applies here.
scoped="$SANDBOX/scoped"
proj="$SANDBOX/proj"
mkdir -p "$scoped/plugins" "$proj/sub" "$SANDBOX/proj-2" "$SANDBOX/elsewhere"
proj=$(cd "$proj" && pwd -P)
ln -s "$cur/plugins/cache" "$scoped/plugins/cache"
jq -n --arg u "$new_copy" --arg p "$old_copy" --arg o "$SANDBOX/other-proj-copy" --arg pp "$proj" --arg op "$SANDBOX/other-proj" \
  '{plugins: {"planwright@planwright": [
      {scope: "project", projectPath: $op, installPath: $o},
      {scope: "user", installPath: $u},
      {scope: "local", projectPath: $pp, installPath: $p}]}}' >"$scoped/plugins/installed_plugins.json"
OUT=$(cd "$proj/sub" && env -u HOME CLAUDE_DIR="$scoped" /bin/sh "$RESOLVER" --current 2>/dev/null)
assert_eq "--current inside a project: its own install first, then the user one" "$old_copy
$new_copy" "$OUT"
OUT=$(cd "$proj" && env -u HOME -u CLAUDE_PROJECT_DIR CLAUDE_DIR="$scoped" /bin/sh "$RESOLVER" --current 2>/dev/null)
assert_eq "--current at the project's own root: its install first" "$old_copy
$new_copy" "$OUT"
OUT=$(cd "$SANDBOX/elsewhere" && env -u HOME CLAUDE_PROJECT_DIR="$proj" CLAUDE_DIR="$scoped" /bin/sh "$RESOLVER" --current 2>/dev/null)
assert_eq "--current follows the session's project over the working directory" "$old_copy
$new_copy" "$OUT"
nested="$SANDBOX/nested"
mkdir -p "$nested/plugins"
jq -n --arg u "$new_copy" --arg p "$old_copy" --arg s "$SANDBOX/sub-copy" --arg pp "$proj" --arg sp "$proj/sub" \
  '{plugins: {"planwright@planwright": [
      {scope: "user", installPath: $u},
      {scope: "project", projectPath: $pp, installPath: $p},
      {scope: "local", projectPath: $sp, installPath: $s}]}}' >"$nested/plugins/installed_plugins.json"
OUT=$(cd "$proj/sub" && env -u HOME -u CLAUDE_PROJECT_DIR CLAUDE_DIR="$nested" /bin/sh "$RESOLVER" --current 2>/dev/null)
assert_eq "--current in a nested project: the innermost install first, record order aside" "$SANDBOX/sub-copy
$old_copy
$new_copy" "$OUT"
for here in elsewhere proj-2; do
  OUT=$(cd "$SANDBOX/$here" && env -u HOME -u CLAUDE_PROJECT_DIR CLAUDE_DIR="$scoped" /bin/sh "$RESOLVER" --current 2>/dev/null)
  assert_eq "--current from $here: the user install alone" "$new_copy" "$OUT"
done
OUT=$(cd "$SANDBOX/elsewhere" && env -u HOME -u CLAUDE_PROJECT_DIR CLAUDE_DIR="$scoped" /bin/sh "$RESOLVER" 2>/dev/null)
assert_eq "the default listing still names every recorded root, once" "$SANDBOX/other-proj-copy
$new_copy
$old_copy" "$OUT"
ERR=$(cd "$proj" && env -u HOME -u CLAUDE_PROJECT_DIR CLAUDE_DIR="$scoped" /bin/sh "$RESOLVER" --check "$old_copy" 2>&1 >/dev/null)
assert_eq "--check inside the project: its local install is current" "" "$ERR"
ERR=$(cd "$SANDBOX/elsewhere" && env -u HOME -u CLAUDE_PROJECT_DIR CLAUDE_DIR="$scoped" /bin/sh "$RESOLVER" --check "$old_copy" 2>&1 >/dev/null)
case $ERR in
  *WARNING*) echo "ok: --check elsewhere: another project's install is stale here" ;;
  *)
    echo "FAIL: --check elsewhere said '$ERR'" >&2
    failures=$((failures + 1))
    ;;
esac

# --- --check: a copy under the cache that is not the installed one warns ------
check() { # check <path> [ENV=val...]: stderr in ERR, exit status in CODE
  ck_path=$1
  shift
  ERR=$(env -u HOME CLAUDE_DIR="$cur" "$@" /bin/sh "$RESOLVER" --check "$ck_path" 2>&1 >/dev/null)
  CODE=$?
}
check "$old_copy"
assert_eq "an older cached copy is stale (exit 1)" 1 "$CODE"
case $ERR in
  "planwright: WARNING running from $old_copy, "*"$new_copy"*) echo "ok: the warning keeps the prefix the panel filters on, naming both copies" ;;
  *)
    echo "FAIL: the stale warning reads '$ERR'" >&2
    failures=$((failures + 1))
    ;;
esac
check "$old_copy/scripts/.."
assert_eq "a stale copy named through its scripts directory is stale too" 1 "$CODE"
check "$new_copy"
assert_eq "the installed copy is current (exit 0)" 0 "$CODE"
assert_eq "and says nothing" "" "$ERR"
check "$REPO_ROOT"
assert_eq "a copy outside the plugin cache (a checkout) is never checked" 0 "$CODE"
assert_eq "and says nothing about it" "" "$ERR"
check "$old_copy" "PATH=$SANDBOX/no-bin"
assert_eq "without jq nothing can be compared, so nothing warns" 0 "$CODE"
assert_eq "and says nothing" "" "$ERR"
check "$cur/plugins/cache/planwright/planwright/0.10.0"
assert_eq "a path that does not exist is never stale" 0 "$CODE"
# A copy any applicable record entry names is current, first entry or not.
two="$SANDBOX/two"
mkdir -p "$two/plugins"
ln -s "$cur/plugins/cache" "$two/plugins/cache"
jq -n --arg a "$new_copy" --arg b "$old_copy" \
  '{plugins: {"planwright@planwright": [{installPath: $a}], "planwright@other": [{installPath: $b}]}}' \
  >"$two/plugins/installed_plugins.json"
ERR=$(env -u HOME CLAUDE_DIR="$two" /bin/sh "$RESOLVER" --check "$old_copy" 2>&1 >/dev/null)
assert_eq "a copy the second record entry names is current" "" "$ERR"

# --- the resolvers and mission control's scripts warn from a stale copy -------
stale_run() { # stale_run <copy> <script> <args...>: stdout in OUT, stderr in ERR
  sr_copy=$1
  sr_script=$2
  shift 2
  sr_err=$(mktemp "$SANDBOX/err.XXXXXX") || exit 1
  OUT=$(cd "$SANDBOX" && env -u HOME -u PLANWRIGHT_ROOT -u CLAUDE_PLUGIN_ROOT CLAUDE_DIR="$cur" \
    PLANWRIGHT_REPO_ROOT=none "$sr_copy/scripts/$sr_script" "$@" 2>"$sr_err")
  CODE=$?
  ERR=$(cat "$sr_err")
  rm -f "$sr_err"
}
stale_run "$old_copy" resolve-root.sh install
assert_eq "resolve-root.sh from a stale copy still answers" "$old_copy" "$OUT"
case $ERR in
  *"WARNING"*"$new_copy"*) echo "ok: resolve-root.sh from a stale copy warns, naming the installed copy" ;;
  *)
    echo "FAIL: resolve-root.sh from a stale copy said '$ERR'" >&2
    failures=$((failures + 1))
    ;;
esac
stale_run "$new_copy" resolve-root.sh install
assert_eq "resolve-root.sh from the installed copy says nothing on stderr" "" "$ERR"
ERR=$(cd "$old_copy" && env -u HOME -u PLANWRIGHT_ROOT -u CLAUDE_PLUGIN_ROOT CLAUDE_DIR="$cur" \
  scripts/resolve-root.sh install 2>&1 >/dev/null)
case $ERR in
  *"WARNING"*) echo "ok: resolve-root.sh run by a relative path from a stale copy warns" ;;
  *)
    echo "FAIL: the relative run said '$ERR'" >&2
    failures=$((failures + 1))
    ;;
esac
# A launched session inherits its launcher's pin: a pin naming a stale copy
# warns even from the installed copy's resolver.
OUT=$(cd "$SANDBOX" && env -u HOME -u PLANWRIGHT_ROOT CLAUDE_PLUGIN_ROOT="$old_copy" CLAUDE_DIR="$cur" \
  "$new_copy/scripts/resolve-root.sh" install 2>"$SANDBOX/pin.err")
assert_eq "an inherited stale pin still wins the chain" "$old_copy" "$OUT"
case $(cat "$SANDBOX/pin.err") in
  *"WARNING running from $old_copy"*) echo "ok: and the resolver warns about it" ;;
  *)
    echo "FAIL: an inherited stale pin said '$(cat "$SANDBOX/pin.err")'" >&2
    failures=$((failures + 1))
    ;;
esac
# shell-gnu-only-flag: BSD stat -f is the fallback when GNU stat -c fails
stamp=$(stat -c %Y "$cur/plugins/installed_plugins.json" 2>/dev/null || stat -f %m "$cur/plugins/installed_plugins.json")
ERR=$(cd "$SANDBOX" && env -u HOME -u PLANWRIGHT_ROOT -u CLAUDE_PLUGIN_ROOT PLANWRIGHT_COPY_CHECKED="$old_copy|$stamp" \
  CLAUDE_DIR="$cur" "$old_copy/scripts/resolve-root.sh" install 2>&1 >/dev/null)
assert_eq "a copy a calling script checked against this record is not warned about again" "" "$ERR"
ERR=$(cd "$SANDBOX" && env -u HOME -u PLANWRIGHT_ROOT -u CLAUDE_PLUGIN_ROOT PLANWRIGHT_COPY_CHECKED="$old_copy|1" \
  CLAUDE_DIR="$cur" "$old_copy/scripts/resolve-root.sh" install 2>&1 >/dev/null)
case $ERR in
  *WARNING*) echo "ok: a mark from an earlier state of the record (an inherited one) still warns" ;;
  *)
    echo "FAIL: an old mark silenced the warning" >&2
    failures=$((failures + 1))
    ;;
esac
stale_run "$old_copy" resolve-rule-doc.sh plugin-script-invocation
assert_eq "resolve-rule-doc.sh from a stale copy still resolves" "$old_copy/doctrine/plugin-script-invocation.md" "$OUT"
case $ERR in
  *"WARNING"*"$new_copy"*) echo "ok: resolve-rule-doc.sh from a stale copy warns" ;;
  *)
    echo "FAIL: resolve-rule-doc.sh from a stale copy said '$ERR'" >&2
    failures=$((failures + 1))
    ;;
esac
stale_run "$old_copy" mc-event.sh --help
case $ERR in
  *"WARNING"*"$new_copy"*) echo "ok: a mission-control script from a stale copy warns" ;;
  *)
    echo "FAIL: mc-event.sh from a stale copy said '$ERR'" >&2
    failures=$((failures + 1))
    ;;
esac
# Sourcing the shared library marks the tree, so a resolver it starts stays
# quiet: one warning per process tree.
# shellcheck disable=SC2016 # the inner script expands its own arguments
ERR=$(cd "$SANDBOX" && env -u HOME -u PLANWRIGHT_ROOT -u CLAUDE_PLUGIN_ROOT -u PLANWRIGHT_COPY_CHECKED CLAUDE_DIR="$cur" \
  /bin/bash -c 'prog=t; script_dir=$1; . "$1/echo-safety.sh"; . "$1/mc-lib.sh"; /bin/sh "$1/resolve-root.sh" install >/dev/null' \
  _ "$old_copy/scripts" 2>&1 >/dev/null)
assert_eq "a mission-control script and the resolver it starts warn once between them" 1 "$(printf '%s\n' "$ERR" | grep -c WARNING)"
# The resolver marks by canonical path, so the library must too: reached
# through a symlink, the two would otherwise disagree and warn twice.
ln -s "$cur" "$SANDBOX/cur-link"
# shellcheck disable=SC2016 # the inner script expands its own arguments
ERR=$(cd "$SANDBOX" && env -u HOME -u PLANWRIGHT_ROOT -u CLAUDE_PLUGIN_ROOT -u PLANWRIGHT_COPY_CHECKED CLAUDE_DIR="$SANDBOX/cur-link" \
  /bin/bash -c 'prog=t; script_dir=$1; . "$1/echo-safety.sh"; . "$1/mc-lib.sh"; /bin/sh "$1/resolve-root.sh" install >/dev/null' \
  _ "$SANDBOX/cur-link/plugins/cache/planwright/planwright/0.65.0/scripts" 2>&1 >/dev/null)
assert_eq "reached through a symlink, they still warn once between them" 1 "$(printf '%s\n' "$ERR" | grep -c WARNING)"
rm "$old_copy/scripts/resolve-installed-roots.sh"
stale_run "$old_copy" mc-event.sh --help
assert_eq "a copy missing the checker stays quiet" "" "$ERR"
cp "$REPO_ROOT/scripts/resolve-installed-roots.sh" "$old_copy/scripts/"
stale_run "$new_copy" mc-event.sh --help
assert_eq "a mission-control script from the installed copy says nothing on stderr" "" "$ERR"

# --- --fresh: the root a launch hands on --------------------------------------
fresh() { # fresh <path> [ENV=val...]: stdout in OUT, exit status in CODE
  fr_path=$1
  shift
  OUT=$(env -u HOME CLAUDE_DIR="$cur" "$@" /bin/sh "$RESOLVER" --fresh "$fr_path" 2>/dev/null)
  CODE=$?
}
fresh "$old_copy"
assert_eq "--fresh replaces a stale cached copy with the installed root" "$new_copy" "$OUT"
assert_eq "--fresh exits 0 for a replaced copy" 0 "$CODE"
fresh "$old_copy/scripts/.."
assert_eq "--fresh replaces a stale copy named through its scripts directory" "$new_copy" "$OUT"
fresh "$new_copy"
assert_eq "--fresh keeps the installed copy" "$new_copy" "$OUT"
fresh "$REPO_ROOT"
assert_eq "--fresh keeps a checkout, an operator's choice" "$REPO_ROOT" "$OUT"
fresh "$cur/plugins/cache/planwright/planwright/0.10.0"
assert_eq "--fresh keeps a path that does not exist" "$cur/plugins/cache/planwright/planwright/0.10.0" "$OUT"
fresh "$old_copy" "PATH=$SANDBOX/no-bin"
assert_eq "--fresh without jq keeps the path, never guessing" "$old_copy" "$OUT"
for args in '--fresh' "--fresh ''" '--fresh a b'; do
  eval "set -- $args"
  env -u HOME CLAUDE_DIR="$cur" /bin/sh "$RESOLVER" "$@" >/dev/null 2>&1
  assert_eq "$args is a usage error" 2 "$?"
done
set --
OUT=$(env -u HOME -u CLAUDE_DIR /bin/sh "$RESOLVER" --fresh "$old_copy" 2>/dev/null)
assert_eq "--fresh with no claude dir keeps the path" "$old_copy" "$OUT"
# A record naming a copy that is not on disk (mid-install, or pruned) must not
# replace a working one with a root whose hooks never run.
gone="$SANDBOX/gone"
mkdir -p "$gone/plugins"
ln -s "$cur/plugins/cache" "$gone/plugins/cache"
jq -n --arg a "$cur/plugins/cache/planwright/planwright/0.67.0" --arg b "$new_copy" \
  '{plugins: {"planwright@planwright": [{installPath: $a}], "planwright@other": [{installPath: $b}]}}' \
  >"$gone/plugins/installed_plugins.json"
OUT=$(env -u HOME CLAUDE_DIR="$gone" /bin/sh "$RESOLVER" --fresh "$old_copy" 2>/dev/null)
assert_eq "--fresh passes over a recorded root missing from disk to one present" "$new_copy" "$OUT"
jq -n --arg a "$cur/plugins/cache/planwright/planwright/0.67.0" \
  '{plugins: {"planwright@planwright": [{installPath: $a}]}}' >"$gone/plugins/installed_plugins.json"
OUT=$(env -u HOME CLAUDE_DIR="$gone" /bin/sh "$RESOLVER" --fresh "$old_copy" 2>/dev/null)
assert_eq "--fresh keeps the path when no recorded root is on disk" "$old_copy" "$OUT"

# --- the launch seam hands a worker the installed root ------------------------
# envrun <wrapper-copy> [ENV=val...]: the wrapper's exported roots and copy
# mark, read back through env; stdout in OUT, stderr in ERR.
envrun() {
  er_copy=$1
  shift
  er_err=$(mktemp "$SANDBOX/err.XXXXXX") || exit 1
  OUT=$(cd "$SANDBOX" && env -u HOME -u PLANWRIGHT_ROOT -u CLAUDE_PLUGIN_ROOT -u PLANWRIGHT_COPY_CHECKED \
    CLAUDE_DIR="$cur" "$@" "$er_copy/scripts/fleet-dispatch-env.sh" env 2>"$er_err" \
    | grep -E '^(PLANWRIGHT_ROOT|CLAUDE_PLUGIN_ROOT|PLANWRIGHT_COPY_CHECKED)=' | LC_ALL=C sort)
  ERR=$(cat "$er_err")
  rm -f "$er_err"
}
envrun "$new_copy" "PLANWRIGHT_ROOT=$old_copy" "CLAUDE_PLUGIN_ROOT=$old_copy" "PLANWRIGHT_COPY_CHECKED=$old_copy|1"
assert_eq "an inherited root naming a stale copy is replaced by the installed root, and the copy mark dropped" \
  "CLAUDE_PLUGIN_ROOT=$new_copy
PLANWRIGHT_ROOT=$new_copy" "$OUT"
case $ERR in
  *"PLANWRIGHT_ROOT"*"$old_copy"*"$new_copy"*) echo "ok: the replacement is said on stderr, naming both copies" ;;
  *)
    echo "FAIL: the replacement said '$ERR'" >&2
    failures=$((failures + 1))
    ;;
esac
envrun "$new_copy" "PLANWRIGHT_ROOT=$REPO_ROOT"
assert_eq "an inherited checkout root is the operator's and stays" \
  "CLAUDE_PLUGIN_ROOT=$new_copy
PLANWRIGHT_ROOT=$REPO_ROOT" "$OUT"
assert_eq "and nothing is said about it" "" "$ERR"
envrun "$old_copy"
assert_eq "a wrapper run from a stale copy hands on the installed root, not its own" \
  "CLAUDE_PLUGIN_ROOT=$new_copy
PLANWRIGHT_ROOT=$new_copy" "$OUT"
OUT=$(cd "$SANDBOX" && env -u HOME -u PLANWRIGHT_ROOT -u CLAUDE_PLUGIN_ROOT CLAUDE_DIR="$cur" \
  CLAUDE_PLUGIN_ROOT="$old_copy" "$new_copy/scripts/fleet-dispatch-env.sh" --print 2>/dev/null \
  | grep '^CLAUDE_PLUGIN_ROOT=')
assert_eq "--print hands on the installed root too" "CLAUDE_PLUGIN_ROOT=$new_copy" "$OUT"
OUT=$(cd "$SANDBOX" && env -u HOME -u PLANWRIGHT_ROOT -u CLAUDE_PLUGIN_ROOT CLAUDE_DIR="$cur" \
  "$new_copy/scripts/fleet-dispatch-env.sh" --root "$old_copy" env 2>/dev/null | grep '^PLANWRIGHT_ROOT=')
assert_eq "a --root a stale dispatcher computed is replaced too" "PLANWRIGHT_ROOT=$new_copy" "$OUT"
OUT=$(cd "$SANDBOX" && env -u HOME -u PLANWRIGHT_ROOT -u CLAUDE_PLUGIN_ROOT CLAUDE_DIR="$cur" \
  "$new_copy/scripts/fleet-dispatch-env.sh" --root "$REPO_ROOT" env 2>/dev/null | grep '^PLANWRIGHT_ROOT=')
assert_eq "a --root naming a checkout is the dispatcher's choice and stays" "PLANWRIGHT_ROOT=$REPO_ROOT" "$OUT"

OUT=$(cd "$SANDBOX" && env -u HOME -u CLAUDE_PLUGIN_ROOT CLAUDE_DIR="$cur" PLANWRIGHT_ROOT="$old_copy" \
  "$new_copy/scripts/fleet-launch-profile.sh" worker 2>/dev/null)
assert_eq "the settings profile comes from the installed root the wrapper hands on" \
  "$new_copy/config/worker-settings.json" "$OUT"
OUT=$(cd "$SANDBOX" && env -u HOME -u PLANWRIGHT_ROOT -u CLAUDE_PLUGIN_ROOT CLAUDE_DIR="$cur" \
  "$new_copy/scripts/fleet-launch-profile.sh" worker --root "$old_copy" 2>/dev/null)
assert_eq "and so does a --root naming a stale copy" "$new_copy/config/worker-settings.json" "$OUT"

# --- step-record.sh refuses to write a record from a stale copy ---------------
srwt="$SANDBOX/sr-wt"
mkdir -p "$srwt"
git -C "$srwt" init -q
stale_run "$old_copy" step-record.sh --worktree "$srwt" new-run
assert_eq "a stale step-record.sh refuses to open a run" 1 "$CODE"
assert_eq "and opens none" "" "$OUT"
case $ERR in
  *"$new_copy/scripts/step-record.sh"*) echo "ok: the refusal names the installed step-record.sh to run instead" ;;
  *)
    echo "FAIL: the stale step-record.sh said '$ERR'" >&2
    failures=$((failures + 1))
    ;;
esac
if [ -d "$srwt/.claude/steps" ]; then
  echo "FAIL: the refused run created $srwt/.claude/steps" >&2
  failures=$((failures + 1))
else
  echo "ok: the refused run left no cache"
fi
stale_run "$old_copy" step-record.sh --worktree "$srwt" status --point pre-ready-flip --repo o/r
assert_eq "a stale step-record.sh refuses to post a flip status" 1 "$CODE"
case $ERR in
  *"refusing status"*"$new_copy/scripts/step-record.sh"*) echo "ok: and names the installed copy" ;;
  *)
    echo "FAIL: the stale status said '$ERR'" >&2
    failures=$((failures + 1))
    ;;
esac
stale_run "$new_copy" step-record.sh --worktree "$srwt" new-run
assert_eq "the installed step-record.sh opens the run" "000001" "$OUT"
assert_eq "and says nothing on stderr" "" "$ERR"
stale_run "$old_copy" step-record.sh --worktree "$srwt" list
assert_eq "a stale step-record.sh still reads" 0 "$CODE"
case $ERR in
  *WARNING*"$new_copy"*) echo "ok: and warns while it reads" ;;
  *)
    echo "FAIL: the stale read said '$ERR'" >&2
    failures=$((failures + 1))
    ;;
esac
stale_run "$old_copy" step-record.sh --worktree "$srwt" write --completion --run 000001 --point pre-ci \
  --head 0123456789abcdef0123456789abcdef01234567
assert_eq "a stale step-record.sh still writes into a run opened before the upgrade" 0 "$CODE"
case $ERR in
  *WARNING*"$new_copy"*) echo "ok: and warns while it writes" ;;
  *)
    echo "FAIL: the stale write said '$ERR'" >&2
    failures=$((failures + 1))
    ;;
esac
# Which install is current follows the worktree's project, not the caller's
# directory: a project-scope install of the old copy makes it current there.
jq -n --arg a "$new_copy" --arg b "$old_copy" --arg p "$srwt" \
  '{plugins: {"planwright@planwright": [{scope: "user", installPath: $a}, {scope: "project", projectPath: $p, installPath: $b}]}}' \
  >"$SANDBOX/scoped-rec.json"
mkdir -p "$SANDBOX/scoped/plugins"
ln -s "$cur/plugins/cache" "$SANDBOX/scoped/plugins/cache"
cp "$SANDBOX/scoped-rec.json" "$SANDBOX/scoped/plugins/installed_plugins.json"
OUT=$(cd "$SANDBOX" && env -u HOME -u PLANWRIGHT_ROOT -u CLAUDE_PLUGIN_ROOT -u CLAUDE_PROJECT_DIR CLAUDE_DIR="$SANDBOX/scoped" \
  "$old_copy/scripts/step-record.sh" --worktree "$srwt" new-run 2>/dev/null)
assert_eq "a copy current for the worktree's project opens the run from anywhere" "000002" "$OUT"

# --- mission-control-launch.sh runs the installed launcher --------------------
mv "$new_copy/scripts/mission-control-launch.sh" "$SANDBOX/launch.keep"
printf '#!/bin/sh\nprintf "installed launcher:%%s\\n" "$*"\n' >"$new_copy/scripts/mission-control-launch.sh"
chmod +x "$new_copy/scripts/mission-control-launch.sh"
stale_run "$old_copy" mission-control-launch.sh name --program p
assert_eq "a launcher run from a stale copy hands its arguments to the installed one" \
  "installed launcher:name --program p" "$OUT"
case $ERR in
  *"$new_copy/scripts/mission-control-launch.sh"*) echo "ok: and says which launcher it ran" ;;
  *)
    echo "FAIL: the stale launcher said '$ERR'" >&2
    failures=$((failures + 1))
    ;;
esac
mv "$SANDBOX/launch.keep" "$new_copy/scripts/mission-control-launch.sh"

if [ "$failures" -gt 0 ]; then
  echo "resolve-installed-roots suite: $failures failure(s)" >&2
  exit 1
fi
echo "all resolve-installed-roots tests passed"
