#!/bin/bash
# Tests for scripts/resolve-overlay-root.sh — the overlay-root resolution
# primitive the three per-kind resolvers (config, doctrine, catalog) share
# (Task 2; REQ-A1.1, REQ-A1.3, REQ-A1.4, REQ-A1.5, REQ-A1.6, REQ-E1.2,
# REQ-E1.5; D-1, D-3, D-4, D-8). Plain bash 3.2, no test framework (the
# sibling suites follow the same inline-assert convention).
set -u
unset CDPATH

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RESOLVER="$REPO_ROOT/scripts/resolve-overlay-root.sh"

failures=0
assert() {
  # assert <description> <expected-exit> <actual-exit>
  if [ "$2" -eq "$3" ]; then
    echo "ok: $1"
  else
    echo "FAIL: $1 (expected exit $2, got $3)" >&2
    failures=$((failures + 1))
  fi
}

assert_eq() {
  # assert_eq <description> <expected> <actual>
  if [ "$2" = "$3" ]; then
    echo "ok: $1"
  else
    echo "FAIL: $1 (expected '$2', got '$3')" >&2
    failures=$((failures + 1))
  fi
}

assert_ne() {
  # assert_ne <description> <unexpected> <actual>
  if [ "$2" != "$3" ]; then
    echo "ok: $1"
  else
    echo "FAIL: $1 (got '$3', expected something different)" >&2
    failures=$((failures + 1))
  fi
}

if [ ! -f "$RESOLVER" ]; then
  echo "FAIL: resolver script missing at $RESOLVER" >&2
  exit 1
fi

# Canonicalize the temp dir up front: on macOS /var symlinks to /private/var,
# and the resolver canonicalizes (pwd -P), so expected paths must match the
# canonical form.
tmp="$(cd "$(mktemp -d)" && pwd -P)" || exit 1
trap 'rm -rf "$tmp"' EXIT

# A clean base env: strip every overlay-affecting variable so each case sets
# only what it exercises. (env -i would also drop PATH, so unset explicitly.)
base() {
  env -u PLANWRIGHT_ROOT -u CLAUDE_PLUGIN_ROOT -u CLAUDE_DIR \
    -u PLANWRIGHT_ADOPTER_OVERLAY -u CLAUDE_PLUGIN_DATA \
    -u PLANWRIGHT_REPO_ROOT "$@"
}

# ---------------------------------------------------------------------------
# core layer
# ---------------------------------------------------------------------------
mkdir -p "$tmp/core/config" "$tmp/core/doctrine"
out="$(base PLANWRIGHT_ROOT="$tmp/core" /bin/bash "$RESOLVER" core)"
assert "core resolves via PLANWRIGHT_ROOT" 0 $?
assert_eq "core root is the planwright root" "$tmp/core" "$out"

# core falls through to the plugin root when PLANWRIGHT_ROOT is unset.
mkdir -p "$tmp/plugin/config"
out="$(base CLAUDE_PLUGIN_ROOT="$tmp/plugin" /bin/bash "$RESOLVER" core)"
assert "core resolves via CLAUDE_PLUGIN_ROOT" 0 $?
assert_eq "core root is the plugin root" "$tmp/plugin" "$out"

# core skips a set-but-nonexistent root and falls through to the next arm.
out="$(base PLANWRIGHT_ROOT="$tmp/no-such-core" CLAUDE_PLUGIN_ROOT="$tmp/plugin" \
  /bin/bash "$RESOLVER" core)"
assert "core skips a nonexistent PLANWRIGHT_ROOT" 0 $?
assert_eq "core falls through to the plugin root" "$tmp/plugin" "$out"

# core position 3: with the first two arms unset, the writer-mode arm
# (<claude-dir>/planwright) resolves core. CLAUDE_DIR derives the claude dir.
mkdir -p "$tmp/cdir/planwright/config"
out="$(base CLAUDE_DIR="$tmp/cdir" /bin/bash "$RESOLVER" core)"
assert "core resolves via the writer-mode claude dir" 0 $?
assert_eq "core root is <claude-dir>/planwright" "$tmp/cdir/planwright" "$out"

# core position 4: with no env arm derivable (no PLANWRIGHT_ROOT, no plugin
# root, and no CLAUDE_DIR/HOME so the writer-mode arm is skipped), core falls
# through to the script's own parent — the install root holding this resolver.
# It always exists, so core never degrades to absent on a sane checkout. HOME
# is unset explicitly: base keeps it, and a real ~/.claude/planwright would
# otherwise satisfy the writer-mode arm before the fall-through is reached.
script_parent="$(cd "$(dirname "$RESOLVER")/.." && pwd -P)"
out="$(base env -u HOME /bin/bash "$RESOLVER" core)"
assert "core falls through to the script-dir parent" 0 $?
assert_eq "core root is the resolver's install root" "$script_parent" "$out"

# ---------------------------------------------------------------------------
# adopter layer
# ---------------------------------------------------------------------------
# Explicit override wins over everything.
mkdir -p "$tmp/data/id1" "$tmp/claude/planwright"
echo '{"name": "planwright"}' >"$tmp/claude/planwright/plugin.json"
out="$(base PLANWRIGHT_ADOPTER_OVERLAY="$tmp/explicit" \
  CLAUDE_PLUGIN_DATA="$tmp/data/id1" CLAUDE_DIR="$tmp/claude" \
  /bin/bash "$RESOLVER" adopter)"
assert "adopter explicit override resolves" 0 $?
assert_eq "adopter override wins" "$tmp/explicit" "$out"

# Plugin mode: $CLAUDE_PLUGIN_DATA/overlay.
out="$(base CLAUDE_PLUGIN_DATA="$tmp/data/id1" CLAUDE_DIR="$tmp/claude" \
  /bin/bash "$RESOLVER" adopter)"
assert "adopter plugin-mode resolves" 0 $?
assert_eq "adopter plugin path" "$tmp/data/id1/overlay" "$out"

# Two distinct CLAUDE_PLUGIN_DATA ids resolve to distinct adopter roots
# (REQ-A1.5 multi-install coexistence).
out1="$(base CLAUDE_PLUGIN_DATA="$tmp/data/id1" /bin/bash "$RESOLVER" adopter)"
out2="$(base CLAUDE_PLUGIN_DATA="$tmp/data/id2" /bin/bash "$RESOLVER" adopter)"
assert_ne "distinct plugin-data ids give distinct adopter roots" "$out1" "$out2"

# Writer mode: namespace derived from the manifest name.
out="$(base CLAUDE_DIR="$tmp/claude" /bin/bash "$RESOLVER" adopter)"
assert "adopter writer-mode resolves" 0 $?
assert_eq "adopter writer path" "$tmp/claude/planwright/planwright/overlay" "$out"

# Writer mode honors HOME when CLAUDE_DIR is unset.
mkdir -p "$tmp/home/.claude/planwright"
echo '{"name": "planwright"}' >"$tmp/home/.claude/planwright/plugin.json"
out="$(base HOME="$tmp/home" /bin/bash "$RESOLVER" adopter)"
assert "adopter writer-mode via HOME resolves" 0 $?
assert_eq "adopter writer path via HOME" "$tmp/home/.claude/planwright/planwright/overlay" "$out"

# The manifest `name` is extracted even when displayName precedes it.
mkdir -p "$tmp/claude2/planwright"
cat >"$tmp/claude2/planwright/plugin.json" <<'JSON'
{
  "displayName": "Planwright Display",
  "name": "workfork",
  "version": "0.1.0"
}
JSON
out="$(base CLAUDE_DIR="$tmp/claude2" /bin/bash "$RESOLVER" adopter)"
assert "adopter writer-mode resolves with displayName present" 0 $?
assert_eq "manifest name not confused by displayName" \
  "$tmp/claude2/planwright/workfork/overlay" "$out"

# The parser must select the TOP-LEVEL name even when a nested object's "name"
# (e.g. author.name) appears earlier in the manifest and is itself a valid
# identifier. A non-depth-aware parser would pick the first "name" it sees
# (the nested one) and resolve the wrong adopter namespace — an isolation bug.
mkdir -p "$tmp/claude-nested/planwright"
cat >"$tmp/claude-nested/planwright/plugin.json" <<'JSON'
{
  "author": { "name": "diego" },
  "name": "workfork",
  "version": "0.1.0"
}
JSON
out="$(base CLAUDE_DIR="$tmp/claude-nested" /bin/bash "$RESOLVER" adopter)"
assert "adopter writer-mode ignores an earlier nested name" 0 $?
assert_eq "top-level name wins over an earlier nested author.name" \
  "$tmp/claude-nested/planwright/workfork/overlay" "$out"

# Same, compact single-line manifest with the nested name first.
mkdir -p "$tmp/claude-nested-compact/planwright"
printf '{"author":{"name":"diego"},"name":"workfork"}\n' \
  >"$tmp/claude-nested-compact/planwright/plugin.json"
out="$(base CLAUDE_DIR="$tmp/claude-nested-compact" /bin/bash "$RESOLVER" adopter)"
assert "adopter writer-mode ignores nested name (compact manifest)" 0 $?
assert_eq "top-level name wins over nested name (compact)" \
  "$tmp/claude-nested-compact/planwright/workfork/overlay" "$out"

# Absent manifest: adopter layer degrades to absent (empty, zero exit) —
# REQ-A1.5 / REQ-A1.4 / F9.
mkdir -p "$tmp/claude-nomanifest/planwright"
out="$(base CLAUDE_DIR="$tmp/claude-nomanifest" /bin/bash "$RESOLVER" adopter)"
assert "absent manifest degrades to absent (zero exit)" 0 $?
assert_eq "absent manifest yields empty adopter root" "" "$out"

# Manifest present but no name field: degrade to absent.
mkdir -p "$tmp/claude-noname/planwright"
echo '{"version": "1.0.0"}' >"$tmp/claude-noname/planwright/plugin.json"
out="$(base CLAUDE_DIR="$tmp/claude-noname" /bin/bash "$RESOLVER" adopter)"
assert "manifest without name degrades to absent" 0 $?
assert_eq "name-less manifest yields empty adopter root" "" "$out"

# Manifest with the name key and its value hand-split across lines: the parser
# anchors "name": "value" on one line (every JSON serializer emits this), so a
# split key/value reads as no name and degrades to absent — never a misparse.
# Locks the one-line-key/value assumption documented in the resolver.
mkdir -p "$tmp/claude-split/planwright"
printf '{\n"name":\n"splitname"\n}\n' >"$tmp/claude-split/planwright/plugin.json"
out="$(base CLAUDE_DIR="$tmp/claude-split" /bin/bash "$RESOLVER" adopter)"
assert "split-line manifest name degrades to absent" 0 $?
assert_eq "split-line manifest yields empty adopter root" "" "$out"

# Hostile manifest name: never interpolated into a path; degrade to absent
# with a stderr warning (REQ-E1.2 charset validation, F9 degrade).
mkdir -p "$tmp/claude-evil/planwright"
echo '{"name": "../escape"}' >"$tmp/claude-evil/planwright/plugin.json"
err="$(base CLAUDE_DIR="$tmp/claude-evil" /bin/bash "$RESOLVER" adopter 2>&1 >/dev/null)"
rc=$?
assert "hostile manifest name degrades (zero exit)" 0 "$rc"
out="$(base CLAUDE_DIR="$tmp/claude-evil" /bin/bash "$RESOLVER" adopter 2>/dev/null)"
assert_eq "hostile manifest name yields empty adopter root" "" "$out"
case "$err" in
  *name*) echo "ok: hostile manifest name warns on stderr" ;;
  *)
    echo "FAIL: hostile manifest name did not warn: $err" >&2
    failures=$((failures + 1))
    ;;
esac

# A set-but-nonexistent CLAUDE_DIR has no readable manifest: degrade to absent.
out="$(base CLAUDE_DIR="$tmp/no-such-claude" /bin/bash "$RESOLVER" adopter)"
assert "nonexistent CLAUDE_DIR degrades adopter to absent" 0 $?
assert_eq "nonexistent CLAUDE_DIR yields empty adopter root" "" "$out"

# No adopter arm derivable at all (no override, no plugin data, no HOME/CLAUDE_DIR):
# absent, zero exit.
out="$(base /bin/bash "$RESOLVER" adopter)"
assert "no adopter arm derivable degrades (zero exit)" 0 $?
assert_eq "no adopter arm yields empty root" "" "$out"

# ---------------------------------------------------------------------------
# repo-tracked & machine-local layers (both under <repo>/.claude, per D-4)
# ---------------------------------------------------------------------------
mkdir -p "$tmp/repo/.claude"
out="$(base PLANWRIGHT_REPO_ROOT="$tmp/repo" /bin/bash "$RESOLVER" repo-tracked)"
assert "repo-tracked resolves" 0 $?
assert_eq "repo-tracked root" "$tmp/repo/.claude" "$out"

out="$(base PLANWRIGHT_REPO_ROOT="$tmp/repo" /bin/bash "$RESOLVER" machine-local)"
assert "machine-local resolves" 0 $?
assert_eq "machine-local root" "$tmp/repo/.claude" "$out"

# A repo root of exactly "/" must yield "/.claude", not "//.claude" (a leading
# "//" is implementation-defined in POSIX) — F3.
out="$(base PLANWRIGHT_REPO_ROOT=/ /bin/bash "$RESOLVER" repo-tracked)"
assert "repo-tracked at filesystem root resolves" 0 $?
assert_eq "repo-tracked '/' root has no double slash" "/.claude" "$out"

# Outside any git repo and with no override: both degrade to absent.
out="$(cd "$tmp" && base /bin/bash "$RESOLVER" repo-tracked)"
assert "repo-tracked outside a repo degrades (zero exit)" 0 $?
assert_eq "repo-tracked absent yields empty root" "" "$out"

out="$(cd "$tmp" && base /bin/bash "$RESOLVER" machine-local)"
assert "machine-local outside a repo degrades (zero exit)" 0 $?
assert_eq "machine-local absent yields empty root" "" "$out"

# ---------------------------------------------------------------------------
# layer-argument validation
# ---------------------------------------------------------------------------
base /bin/bash "$RESOLVER" >/dev/null 2>&1
assert "no layer argument is a usage error" 2 $?

base /bin/bash "$RESOLVER" bogus-layer >/dev/null 2>&1
assert "unknown layer is rejected" 2 $?

for hostile in "../escape" "core/sub" "UPPER" "core layer"; do
  out="$(base /bin/bash "$RESOLVER" "$hostile" 2>/dev/null)"
  rc=$?
  assert "hostile layer name refused: $hostile" 2 "$rc"
  assert_eq "hostile layer prints nothing on stdout: $hostile" "" "$out"
done

# ---------------------------------------------------------------------------
# --contain: canonicalize-then-contain path-confinement helper (D-8, REQ-E1.5)
# ---------------------------------------------------------------------------
mkdir -p "$tmp/root/doctrine" "$tmp/outside"
echo "inside" >"$tmp/root/doctrine/ok.md"
echo "outside" >"$tmp/outside/evil.md"

# The candidate is relative to the root by contract (D-8, REQ-E1.5): --contain
# joins it onto the root, canonicalizes, and confirms containment.
out="$(base /bin/bash "$RESOLVER" --contain "$tmp/root" "doctrine/ok.md")"
assert "contained path accepted" 0 $?
assert_eq "contained path canonicalized" "$tmp/root/doctrine/ok.md" "$out"

# A not-yet-existing file whose parent is inside the root is accepted
# (confinement is checked before the read, the file need not exist yet).
out="$(base /bin/bash "$RESOLVER" --contain "$tmp/root" "doctrine/new.md")"
assert "contained nonexistent path accepted" 0 $?
assert_eq "contained nonexistent path canonicalized" "$tmp/root/doctrine/new.md" "$out"

# A ../ traversal escaping the root is rejected.
base /bin/bash "$RESOLVER" --contain "$tmp/root" "../outside/evil.md" >/dev/null 2>&1
assert "dotdot traversal rejected" 2 $?

# An absolute candidate is rejected outright — the contract requires a path
# relative to the root, and an absolute path bypasses the root join entirely.
base /bin/bash "$RESOLVER" --contain "$tmp/root" "$tmp/outside/evil.md" >/dev/null 2>&1
assert "absolute path outside root rejected" 2 $?

# An absolute candidate that *would* resolve inside the root is ALSO rejected:
# the rejection is categorical (absolute paths are not permitted), not a mere
# containment check. This is the strict-contract guard (D-8 / REQ-E1.5).
base /bin/bash "$RESOLVER" --contain "$tmp/root" "$tmp/root/doctrine/ok.md" >/dev/null 2>&1
assert "absolute path inside root rejected" 2 $?

# A symlink that escapes the root after canonicalization is rejected.
ln -s "$tmp/outside/evil.md" "$tmp/root/doctrine/escape.md"
base /bin/bash "$RESOLVER" --contain "$tmp/root" "doctrine/escape.md" >/dev/null 2>&1
assert "symlink escape rejected" 2 $?

# A symlink that stays within the root is accepted.
ln -s "$tmp/root/doctrine/ok.md" "$tmp/root/doctrine/alias.md"
out="$(base /bin/bash "$RESOLVER" --contain "$tmp/root" "doctrine/alias.md")"
assert "contained symlink accepted" 0 $?
assert_eq "contained symlink resolves to its target" "$tmp/root/doctrine/ok.md" "$out"

# A symlink within the root whose target does not yet exist but stays inside the
# root is accepted: canon_path resolves the link, then canonicalizes the
# (existing) parent of the not-yet-existing target. Exercises the symlink branch
# feeding the file-fallback branch together — confinement is checked before the
# read, so the target need not exist.
ln -s "$tmp/root/doctrine/not-created-yet.md" "$tmp/root/doctrine/dangling.md"
out="$(base /bin/bash "$RESOLVER" --contain "$tmp/root" "doctrine/dangling.md")"
assert "contained symlink to nonexistent in-root target accepted" 0 $?
assert_eq "dangling in-root symlink canonicalizes to its target" \
  "$tmp/root/doctrine/not-created-yet.md" "$out"

# A path under the filesystem root resolves correctly when the overlay root is
# "/" itself: pwd -P returns "/" (the one canonical root carrying a trailing
# slash), so the containment prefix must not become "//*" and reject real
# children. Everything absolute is under "/". The expected value is derived
# with an independent cd+pwd -P oracle rather than hardcoded: on a usr-merged
# Linux box /bin is a symlink to usr/bin (canonical /usr/bin), while on macOS
# /bin is a real directory (canonical /bin) — both must be accepted and must
# canonicalize without a "//" double slash (the relative-symlink-under-"/" join).
fsroot_child="$(cd /bin && pwd -P)"
out="$(base /bin/bash "$RESOLVER" --contain / bin)"
assert "filesystem-root containment accepts a real child" 0 $?
assert_eq "filesystem-root child canonicalized" "$fsroot_child" "$out"
case "$out" in
  //*)
    echo "FAIL: filesystem-root child has a leading double slash: $out" >&2
    failures=$((failures + 1))
    ;;
  *) echo "ok: filesystem-root child has no leading double slash" ;;
esac

# A *nonexistent* leaf directly under the filesystem root exercises canon_path's
# file-fallback concatenation (the /bin case above takes the directory branch and
# never reaches it). Its parent canonicalizes to "/", so the concatenation must
# not emit a "//leaf" double slash (F2/F3).
out="$(base /bin/bash "$RESOLVER" --contain / planwright-nonexist-leaf.md)"
assert "filesystem-root nonexistent child accepted" 0 $?
assert_eq "filesystem-root nonexistent child has no double slash" \
  "/planwright-nonexist-leaf.md" "$out"

# A sibling dir that merely shares the root's string prefix is NOT contained:
# the prefix match is boundary-aware (root + "/"), not a bare string prefix.
mkdir -p "$tmp/root-sibling"
echo "x" >"$tmp/root-sibling/evil.md"
base /bin/bash "$RESOLVER" --contain "$tmp/root" "../root-sibling/evil.md" >/dev/null 2>&1
assert "prefix-sharing sibling dir is rejected" 2 $?

# A root whose name contains glob metacharacters ([ ] ? *) must still enforce
# containment as a LITERAL prefix. The containment `case` quotes "$canon_root"
# and "$under", so bash matches their contents literally and only the explicit
# trailing '*' is a wildcard; without that quoting, a root named "g[x]r" could
# glob-match an escaping sibling "gxr". Security boundary — locked here on the
# bash 3.2 floor so a future rewrite cannot silently reintroduce a glob match.
mkdir -p "$tmp/g[x]r" "$tmp/gxr"
echo "ok" >"$tmp/g[x]r/in.md"
echo "evil" >"$tmp/gxr/evil.md"
out="$(base /bin/bash "$RESOLVER" --contain "$tmp/g[x]r" "in.md")"
assert "glob-metachar root accepts a real child" 0 $?
assert_eq "glob-metachar root child canonicalized" "$tmp/g[x]r/in.md" "$out"
base /bin/bash "$RESOLVER" --contain "$tmp/g[x]r" "../gxr/evil.md" >/dev/null 2>&1
assert "glob-metachar root rejects an escape to a glob-matching sibling" 2 $?

# --contain with a missing argument is a usage error.
base /bin/bash "$RESOLVER" --contain "$tmp/root" >/dev/null 2>&1
assert "--contain missing path is a usage error" 2 $?

# --contain against a nonexistent root is an error (the root must exist).
base /bin/bash "$RESOLVER" --contain "$tmp/no-such-root" "x" >/dev/null 2>&1
assert "--contain nonexistent root errors" 2 $?

# ---------------------------------------------------------------------------
# core: a candidate that exists but cannot be entered must be skipped
# ---------------------------------------------------------------------------
# An existing-but-unsearchable candidate (e.g. chmod 000) must not be treated as
# the resolved core root: the loop falls through to the next usable candidate
# rather than degrading core to absent (F1). Skipped as root, whose access is
# not bound by the search bit.
if [ "$(id -u)" -ne 0 ]; then
  mkdir -p "$tmp/core-noexec" "$tmp/core-fallback/config"
  chmod 000 "$tmp/core-noexec"
  out="$(base PLANWRIGHT_ROOT="$tmp/core-noexec" CLAUDE_PLUGIN_ROOT="$tmp/core-fallback" \
    /bin/bash "$RESOLVER" core 2>/dev/null)"
  rc=$?
  chmod 755 "$tmp/core-noexec"
  assert "core skips an unsearchable candidate (zero exit)" 0 "$rc"
  assert_eq "core falls through past an unsearchable dir" "$tmp/core-fallback" "$out"
else
  echo "skip: core unsearchable-candidate case (running as root)"
fi

# ---------------------------------------------------------------------------
# --contain: a candidate beginning with '-' is handled lexically
# ---------------------------------------------------------------------------
# A relative candidate beginning with '-' is joined onto the root before
# canonicalization, so the dash segment is interior to an absolute path and
# cd/dirname/basename (which carry the '--' option terminator) never read it as
# an option. It is rejected here because its parent does not exist under the
# root, and crucially WITHOUT leaking an "illegal option" / "invalid option"
# error from the canonicalizer (F5).
err="$(base /bin/bash "$RESOLVER" --contain "$tmp/root" "-dashleading/x" 2>&1 >/dev/null)"
rc=$?
assert "dash-leading candidate is rejected" 2 "$rc"
case "$err" in
  *"illegal option"* | *"invalid option"*)
    echo "FAIL: dash-leading path leaked an option-parsing error: $err" >&2
    failures=$((failures + 1))
    ;;
  *) echo "ok: dash-leading path handled without an option-parsing error" ;;
esac

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all resolve-overlay-root tests passed"
