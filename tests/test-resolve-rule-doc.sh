#!/bin/bash
# Tests for scripts/resolve-rule-doc.sh — the stable rule-doc resolution path
# (REQ-I1.1, REQ-I1.2, D-24). Plain bash 3.2, no test framework (the shared
# runner arrives with Task 2).
set -u
unset CDPATH

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RESOLVER="$REPO_ROOT/scripts/resolve-rule-doc.sh"

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

if [ ! -f "$RESOLVER" ]; then
  echo "FAIL: resolver script missing at $RESOLVER" >&2
  exit 1
fi

tmp="$(mktemp -d)" || exit 1
trap 'rm -rf "$tmp"' EXIT

# Isolate the core-resolution tests below from any ambient overlay layers a
# developer's environment might carry (a set CLAUDE_PLUGIN_DATA, the cwd
# repo's own .claude/doctrine): point the repo-side layers at an overlay-less
# dir and clear the adopter/plugin-data arms. The overlay-specific tests
# further down set these env vars per-invocation, so the isolation here only
# affects the pre-existing core tests (REQ-D1.2 no-regression / R4).
mkdir -p "$tmp/no-repo"
export PLANWRIGHT_REPO_ROOT="$tmp/no-repo"
unset PLANWRIGHT_ADOPTER_OVERLAY CLAUDE_PLUGIN_DATA

# Fixture: a fake plugin root and a fake writer-mode claude dir.
mkdir -p "$tmp/plugin/doctrine" "$tmp/claude/planwright/doctrine" "$tmp/override/doctrine"
echo "plugin copy" >"$tmp/plugin/doctrine/sample-doc.md"
echo "writer copy" >"$tmp/claude/planwright/doctrine/sample-doc.md"
echo "writer only" >"$tmp/claude/planwright/doctrine/writer-only.md"
echo "override copy" >"$tmp/override/doctrine/sample-doc.md"

# 1. Plugin mode: CLAUDE_PLUGIN_ROOT set resolves to the plugin copy.
out="$(PLANWRIGHT_ROOT="" CLAUDE_PLUGIN_ROOT="$tmp/plugin" CLAUDE_DIR="$tmp/claude" \
  /bin/bash "$RESOLVER" sample-doc)"
assert "plugin mode resolves" 0 $?
assert_eq "plugin mode path" "$tmp/plugin/doctrine/sample-doc.md" "$out"

# 2. Writer mode: no plugin root; falls back to <claude-dir>/planwright.
out="$(PLANWRIGHT_ROOT="" CLAUDE_PLUGIN_ROOT="" CLAUDE_DIR="$tmp/claude" \
  /bin/bash "$RESOLVER" writer-only)"
assert "writer mode resolves" 0 $?
assert_eq "writer mode path" "$tmp/claude/planwright/doctrine/writer-only.md" "$out"

# 3. Explicit PLANWRIGHT_ROOT override wins over both.
out="$(PLANWRIGHT_ROOT="$tmp/override" CLAUDE_PLUGIN_ROOT="$tmp/plugin" CLAUDE_DIR="$tmp/claude" \
  /bin/bash "$RESOLVER" sample-doc)"
assert "override mode resolves" 0 $?
assert_eq "override wins" "$tmp/override/doctrine/sample-doc.md" "$out"

# 4. A '.md' suffix is accepted and normalized to the same path.
out="$(PLANWRIGHT_ROOT="" CLAUDE_PLUGIN_ROOT="$tmp/plugin" CLAUDE_DIR="$tmp/claude" \
  /bin/bash "$RESOLVER" sample-doc.md)"
assert "md suffix accepted" 0 $?
assert_eq "md suffix path" "$tmp/plugin/doctrine/sample-doc.md" "$out"

# 5. Missing doc: non-zero exit, message on stderr, nothing on stdout.
out="$(PLANWRIGHT_ROOT="" CLAUDE_PLUGIN_ROOT="$tmp/plugin" CLAUDE_DIR="$tmp/claude" \
  /bin/bash "$RESOLVER" no-such-doc 2>/dev/null)"
assert "missing doc fails" 1 $?
assert_eq "missing doc prints nothing on stdout" "" "$out"

# 6. Hostile names are refused before any path is formed (REQ-D1.6
#    framework-script security; same charset discipline as REQ-A1.8).
for hostile in "../escape" "a/b" ".hidden" "UPPER" "name with space" "-leading-dash"; do
  PLANWRIGHT_ROOT="" CLAUDE_PLUGIN_ROOT="$tmp/plugin" CLAUDE_DIR="$tmp/claude" \
    /bin/bash "$RESOLVER" "$hostile" >/dev/null 2>&1
  assert "hostile name refused: $hostile" 2 $?
done

# 7. No argument: usage error.
/bin/bash "$RESOLVER" >/dev/null 2>&1
assert "no argument is a usage error" 2 $?

# 8. Fallthrough: a root earlier in the chain that lacks the doc falls
#    through to the next root instead of failing.
mkdir -p "$tmp/empty-root/doctrine"
out="$(PLANWRIGHT_ROOT="$tmp/empty-root" CLAUDE_PLUGIN_ROOT="$tmp/plugin" CLAUDE_DIR="$tmp/claude" \
  /bin/bash "$RESOLVER" sample-doc)"
assert "fallthrough past a doc-less root" 0 $?
assert_eq "fallthrough lands on the next root" "$tmp/plugin/doctrine/sample-doc.md" "$out"

# 9. HOME fallback: with CLAUDE_DIR unset, the writer-mode root derives from
#    $HOME/.claude.
mkdir -p "$tmp/home/.claude/planwright/doctrine"
echo "home copy" >"$tmp/home/.claude/planwright/doctrine/home-doc.md"
out="$(HOME="$tmp/home" PLANWRIGHT_ROOT="" CLAUDE_PLUGIN_ROOT="" \
  /bin/bash -c 'unset CLAUDE_DIR; exec /bin/bash "$1" home-doc' _ "$RESOLVER")"
assert "HOME fallback resolves" 0 $?
assert_eq "HOME fallback path" "$tmp/home/.claude/planwright/doctrine/home-doc.md" "$out"

# 10. Plugin mode must work without HOME or CLAUDE_DIR in the environment
#     (minimal containers): the earlier chain arms do not depend on the
#     writer-mode arm being derivable.
out="$(env -u HOME -u CLAUDE_DIR PLANWRIGHT_ROOT="" CLAUDE_PLUGIN_ROOT="$tmp/plugin" \
  /bin/bash "$RESOLVER" sample-doc 2>/dev/null)"
assert "plugin mode resolves without HOME" 0 $?
assert_eq "HOME-less plugin path" "$tmp/plugin/doctrine/sample-doc.md" "$out"

# 11. With no usable root at all (no override, no plugin root, no CLAUDE_DIR,
#     no HOME), the resolver reports its own not-found message (exit 1)
#     rather than crashing with a bash unbound-variable error.
err="$(env -u HOME -u CLAUDE_DIR PLANWRIGHT_ROOT="" CLAUDE_PLUGIN_ROOT="" \
  /bin/bash "$RESOLVER" sample-doc 2>&1 >/dev/null)"
rc=$?
assert "rootless environment exits 1" 1 "$rc"
case "$err" in
  *"not found"*"PLANWRIGHT_ROOT"*) echo "ok: rootless failure is the resolver's diagnostic with checked roots" ;;
  *)
    echo "FAIL: rootless failure lacks the evaluated-roots diagnostic: $err" >&2
    failures=$((failures + 1))
    ;;
esac

# ===========================================================================
# Task 4 — doctrine-overlay resolution (D-4, D-5, D-7, D-8, D-9, D-11;
# REQ-A1.2, REQ-B1.2, REQ-B1.6, REQ-B1.7, REQ-E1.4, REQ-E1.5).
# ===========================================================================

# Canonicalize the fixture base: the resolver returns overlay paths through the
# shared canonicalize-then-contain helper, which resolves /var -> /private/var
# (macOS) and any other symlinks. Building fixtures under a pre-canonicalized
# base lets path assertions match the resolver's canonical output. Content
# assertions are used where a path comparison would be brittle.
ovbase="$(cd "$tmp" && pwd -P)"

# The normative D-11 protected-doc set (mirrors scripts/resolve-rule-doc.sh's
# PROTECTED_DOCS, which is the operative copy; D-11 is the single normative
# source). Iterated below for the R3 mitigation.
PROTECTED_DOCS="spec-format security-posture validation-rigor discovery-rigor finding-categorization gate-wiring"

# Overlay fixture roots. core is an explicit PLANWRIGHT_ROOT; adopter is the
# explicit $PLANWRIGHT_ADOPTER_OVERLAY arm; the two repo-side layers share
# $PLANWRIGHT_REPO_ROOT/.claude with the doctrine/ vs doctrine.local/ split
# (D-4). CLAUDE_PLUGIN_ROOT/CLAUDE_DIR/HOME are cleared so only these arms fire.
ovcore="$ovbase/ov-core"
ovadopter="$ovbase/ov-adopter"
ovrepo="$ovbase/ov-repo"
mkdir -p "$ovcore/doctrine" "$ovadopter/doctrine" \
  "$ovrepo/.claude/doctrine" "$ovrepo/.claude/doctrine.local"

# A doc present in all four layers, each with distinct content.
printf 'CORE BODY\nCORE-ONLY SECTION\n' >"$ovcore/doctrine/layered.md"
printf 'ADOPTER BODY\n' >"$ovadopter/doctrine/layered.md"
printf 'REPO BODY\n' >"$ovrepo/.claude/doctrine/layered.md"
printf 'MLOCAL BODY\n' >"$ovrepo/.claude/doctrine.local/layered.md"

# ov <args...> — invoke the resolver with all four overlay arms wired to the
# fixtures and the ambient core/writer arms cleared.
ov() {
  PLANWRIGHT_ROOT="$ovcore" CLAUDE_PLUGIN_ROOT="" CLAUDE_DIR="" HOME="" \
    PLANWRIGHT_ADOPTER_OVERLAY="$ovadopter" PLANWRIGHT_REPO_ROOT="$ovrepo" \
    /bin/bash "$RESOLVER" "$@"
}

# 12. Precedence: machine-local wins over all lower layers (REQ-A1.2 uniform
#     four-layer order; the highest-precedence overlay doc wins in full).
out="$(ov layered)"
assert "all four layers present: resolves" 0 $?
assert_eq "machine-local wins" "MLOCAL BODY" "$(cat "$out" 2>/dev/null)"

# 13. Absent machine-local degrades to repo-tracked (REQ-A1.4).
rm "$ovrepo/.claude/doctrine.local/layered.md"
out="$(ov layered)"
assert "machine-local absent: resolves" 0 $?
assert_eq "repo-tracked wins next" "REPO BODY" "$(cat "$out" 2>/dev/null)"

# 14. Absent repo-tracked degrades to adopter (REQ-A1.4).
rm "$ovrepo/.claude/doctrine/layered.md"
out="$(ov layered)"
assert "repo-tracked absent: resolves" 0 $?
assert_eq "adopter wins next" "ADOPTER BODY" "$(cat "$out" 2>/dev/null)"

# 15. Whole-doc shadow, no fragment merge (REQ-B1.2): with only the adopter
#     overlay present, the resolved doc is the adopter's IN FULL — the
#     core-only section never appears spliced in.
out="$(ov layered)"
body="$(cat "$out" 2>/dev/null)"
assert_eq "adopter doc returned in full" "ADOPTER BODY" "$body"
case "$body" in
  *"CORE-ONLY SECTION"*)
    echo "FAIL: fragment merge occurred — core-only section leaked into the overlay doc" >&2
    failures=$((failures + 1))
    ;;
  *) echo "ok: no fragment merge (core-only section absent)" ;;
esac

# 16. Absent all overlays degrades to core (REQ-A1.4); core resolves in full.
rm "$ovadopter/doctrine/layered.md"
out="$(ov layered)"
assert "all overlays absent: resolves" 0 $?
assert_eq "core wins last" "CORE BODY" "$(printf '%s' "$(cat "$out" 2>/dev/null)" | head -1)"

# 17. Path-traversal confinement (REQ-E1.5, D-8): a symlink under the overlay
#     doctrine dir that escapes the overlay root is rejected and never read.
mkdir -p "$ovrepo/.claude/doctrine"
printf 'SECRET OUTSIDE ROOT\n' >"$ovbase/outside-secret.md"
ln -s "$ovbase/outside-secret.md" "$ovrepo/.claude/doctrine/escaper.md"
out="$(ov escaper 2>/dev/null)"
rc=$?
assert "escaping symlink rejected" 2 "$rc"
case "$out" in
  *"SECRET OUTSIDE ROOT"*)
    echo "FAIL: escaping symlink target was read (containment breach)" >&2
    failures=$((failures + 1))
    ;;
  *) echo "ok: escaping symlink target never read" ;;
esac
err="$(ov escaper 2>&1 >/dev/null)"
case "$err" in
  *escape*) echo "ok: escape rejection names the cause" ;;
  *)
    echo "FAIL: escape rejection lacks a clear message: $err" >&2
    failures=$((failures + 1))
    ;;
esac
rm "$ovrepo/.claude/doctrine/escaper.md"

# 18. Malformed-by-layer (REQ-E1.4, D-7). A doc path that exists but is not a
#     readable regular file (a directory stands in) is malformed for the
#     doctrine kind. adopter/machine-local degrade+warn; repo-tracked hard-fails.

# 18a. Malformed adopter overlay degrades to the next lower layer (core) with a
#      stderr warning and a zero exit.
printf 'CORE FALLBACK\n' >"$ovcore/doctrine/malf.md"
mkdir -p "$ovadopter/doctrine/malf.md"
out="$(ov malf 2>/dev/null)"
assert "malformed adopter: degrades, zero exit" 0 $?
assert_eq "malformed adopter: lands on core" "CORE FALLBACK" "$(cat "$out" 2>/dev/null)"
err="$(ov malf 2>&1 >/dev/null)"
case "$err" in
  *[Ww]arn*adopter*malformed* | *adopter*malformed*[Ww]arn*) echo "ok: malformed adopter warns" ;;
  *adopter*malformed*) echo "ok: malformed adopter warns (names layer)" ;;
  *)
    echo "FAIL: malformed adopter lacks a degrade warning: $err" >&2
    failures=$((failures + 1))
    ;;
esac
rmdir "$ovadopter/doctrine/malf.md"

# 18b. Malformed machine-local overlay degrades to repo-tracked with a warning.
printf 'REPO FALLBACK\n' >"$ovrepo/.claude/doctrine/malf.md"
mkdir -p "$ovrepo/.claude/doctrine.local/malf.md"
out="$(ov malf 2>/dev/null)"
assert "malformed machine-local: degrades, zero exit" 0 $?
assert_eq "malformed machine-local: lands on repo-tracked" "REPO FALLBACK" "$(cat "$out" 2>/dev/null)"
rmdir "$ovrepo/.claude/doctrine.local/malf.md"

# 18c. Malformed repo-tracked overlay hard-fails with a nonzero exit (a broken
#      team-shared overlay must not silently degrade).
mkdir -p "$ovrepo/.claude/doctrine/malf2.md"
ov malf2 >/dev/null 2>&1
rc=$?
if [ "$rc" -ne 0 ]; then
  echo "ok: malformed repo-tracked hard-fails (exit $rc)"
else
  echo "FAIL: malformed repo-tracked did not hard-fail (exit 0)" >&2
  failures=$((failures + 1))
fi
err="$(ov malf2 2>&1 >/dev/null)"
case "$err" in
  *repo-tracked*malformed*) echo "ok: repo-tracked hard-fail names the layer and cause" ;;
  *)
    echo "FAIL: repo-tracked hard-fail lacks a clear message: $err" >&2
    failures=$((failures + 1))
    ;;
esac
rmdir "$ovrepo/.claude/doctrine/malf2.md"

# 19. Protected-doc shadow warns but allows (REQ-B1.7, D-11). A repo-tracked
#     overlay shadowing a protected doc resolves to the overlay AND warns.
printf 'OVERLAY SECURITY POSTURE\n' >"$ovrepo/.claude/doctrine/security-posture.md"
out="$(ov security-posture 2>/dev/null)"
assert "protected shadow resolves (warn-but-allow)" 0 $?
assert_eq "protected shadow returns the overlay doc" "OVERLAY SECURITY POSTURE" "$(cat "$out" 2>/dev/null)"
err="$(ov security-posture 2>&1 >/dev/null)"
case "$err" in
  *security-posture*)
    case "$err" in
      *[Ww][Aa][Rr][Nn]* | *protected*) echo "ok: protected shadow emits a warning naming the doc" ;;
      *)
        echo "FAIL: protected shadow message is not a warning: $err" >&2
        failures=$((failures + 1))
        ;;
    esac
    ;;
  *)
    echo "FAIL: protected shadow did not warn for security-posture: $err" >&2
    failures=$((failures + 1))
    ;;
esac

# 19b. A non-protected overlay shadow is silent (no warning).
printf 'OVERLAY LAYERED AGAIN\n' >"$ovrepo/.claude/doctrine/layered.md"
err="$(ov layered 2>&1 >/dev/null)"
assert_eq "non-protected shadow is silent" "" "$err"
rm "$ovrepo/.claude/doctrine/layered.md" "$ovrepo/.claude/doctrine/security-posture.md"

# 19c. R3 mitigation: every normative D-11 protected doc actually resolves in
#      core, so a renamed/removed core doc that silently fell out of protection
#      fails this test. Resolved against the worktree's own doctrine/.
for d in $PROTECTED_DOCS; do
  PLANWRIGHT_ROOT="$REPO_ROOT" CLAUDE_PLUGIN_ROOT="" CLAUDE_DIR="" HOME="" \
    PLANWRIGHT_ADOPTER_OVERLAY="" PLANWRIGHT_REPO_ROOT="$tmp/no-repo" \
    /bin/bash "$RESOLVER" "$d" >/dev/null 2>&1
  assert "protected doc resolves in core: $d" 0 $?
done

# 20. Provenance --explain names the supplying layer (REQ-B1.6, D-9). Format:
#     "<layer>\t<path>" on stdout, exit 0.
printf 'CORE ONLY\n' >"$ovcore/doctrine/provdoc.md"
layer="$(ov --explain provdoc | cut -f1)"
assert "explain core: resolves" 0 $?
assert_eq "explain names core" "core" "$layer"

printf 'ADOPTER ONLY\n' >"$ovadopter/doctrine/provdoc.md"
layer="$(ov --explain provdoc | cut -f1)"
assert_eq "explain names adopter" "adopter" "$layer"

printf 'REPO ONLY\n' >"$ovrepo/.claude/doctrine/provdoc.md"
layer="$(ov --explain provdoc | cut -f1)"
assert_eq "explain names repo-tracked" "repo-tracked" "$layer"

printf 'MLOCAL ONLY\n' >"$ovrepo/.claude/doctrine.local/provdoc.md"
layer="$(ov --explain provdoc | cut -f1)"
assert_eq "explain names machine-local" "machine-local" "$layer"

# 20b. --explain still emits the resolved path as the second field.
path="$(ov --explain provdoc | cut -f2)"
assert_eq "explain emits the resolved path" "MLOCAL ONLY" "$(cat "$path" 2>/dev/null)"

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all resolve-rule-doc tests passed"
