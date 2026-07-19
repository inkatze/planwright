#!/bin/bash
# Tests for scripts/release-pending.sh — the release comparator, the one
# definition of "pending" the untagged-window lock and the bookkeeping surface
# share (autopilot-reflex Task 4; D-7, D-8; REQ-D1.8).
#
# Contract under test:
#   - version of truth ahead of the latest release tag → `pending<TAB><version>`;
#   - equal → `none`;
#   - no release tags yet → `pending<TAB><version>` (the first release);
#   - a malformed version of truth → exit 2, no `pending`/`none` on stdout;
#   - the "latest" tag is chosen by SemVer precedence, not lexically
#     (v0.10.0 > v0.2.0).
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
PENDING="$here/../scripts/release-pending.sh"
TAB=$(printf '\t')
failures=0

[ -x "$PENDING" ] || {
  echo "FAIL: scripts/release-pending.sh missing or not executable" >&2
  exit 1
}

gitc() {
  repo="$1"
  shift
  git -C "$repo" -c user.name=test -c user.email=test@example.invalid \
    -c commit.gpgsign=false -c init.defaultBranch=main "$@"
}

# make_repo <dir> <version> — a fixture repo whose plugin.json holds <version>.
make_repo() {
  mkdir -p "$1/.claude-plugin"
  cat >"$1/.claude-plugin/plugin.json" <<EOF
{
  "name": "fixture",
  "version": "$2"
}
EOF
  gitc "$1" init -q
  gitc "$1" add -A
  gitc "$1" commit -q -m "version $2"
}

assert_eq() {
  if [ "$2" = "$3" ]; then
    echo "ok: $1"
  else
    echo "FAIL: $1 — expected [$3], got [$2]" >&2
    failures=$((failures + 1))
  fi
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# 1. Ahead of the latest tag → pending with the version of truth.
r="$tmp/ahead"
make_repo "$r" 0.2.0
gitc "$r" tag v0.1.0
out=$(cd "$r" && env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null "$PENDING")
assert_eq "ahead-of-tag reports pending with the version" "$out" "pending${TAB}0.2.0"

# 2. Equal to the latest tag → none.
r="$tmp/equal"
make_repo "$r" 0.1.0
gitc "$r" tag v0.1.0
out=$(cd "$r" && env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null "$PENDING")
assert_eq "version equal to the latest tag reports none" "$out" "none"

# 3. No release tags at all → pending (the first release).
r="$tmp/first"
make_repo "$r" 0.1.0
out=$(cd "$r" && env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null "$PENDING")
assert_eq "no tags reports the first release as pending" "$out" "pending${TAB}0.1.0"

# 4. Malformed version of truth → exit 2, nothing on stdout.
r="$tmp/bad"
make_repo "$r" "not-a-version"
rc=0
out=$(cd "$r" && env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null "$PENDING" 2>/dev/null) || rc=$?
assert_eq "malformed version exits 2" "$rc" "2"
assert_eq "malformed version prints nothing on stdout" "$out" ""

# 4b. A numeric prerelease identifier with a leading zero is malformed per
#     SemVer 2.0.0 §9 ("Numeric identifiers MUST NOT include leading zeroes"):
#     the grammar is strict on the version core, so it must be strict on the
#     prerelease numeric identifiers too, or two spellings of one version
#     (1.0.0-01 vs 1.0.0-1) collapse and a pending release can be misreported.
r="$tmp/leadingzero"
make_repo "$r" "1.0.0-01"
rc=0
out=$(cd "$r" && env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null "$PENDING" 2>/dev/null) || rc=$?
assert_eq "leading-zero numeric prerelease identifier exits 2" "$rc" "2"
assert_eq "leading-zero numeric prerelease prints nothing on stdout" "$out" ""

# 4c. A leading zero in a NON-first numeric prerelease identifier is malformed
#     too — the §9 rule applies to every dot-separated identifier, not just the
#     first (a loop that only checked ids[0] would wrongly accept this).
r="$tmp/leadingzero-multi"
make_repo "$r" "1.0.0-alpha.01"
rc=0
out=$(cd "$r" && env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null "$PENDING" 2>/dev/null) || rc=$?
assert_eq "leading-zero in a later prerelease identifier exits 2" "$rc" "2"

# 4d. An EMPTY prerelease identifier is malformed per SemVer 2.0.0 §9
#     ("Identifiers MUST NOT be empty"): a leading dot, a trailing dot, or two
#     consecutive dots in the prerelease all produce an empty identifier. The
#     trailing-dot form matters specifically because `IFS=. read` drops the
#     trailing empty field, so a per-identifier loop alone would miss it.
for bad in "1.2.0-alpha..1" "1.2.0-.1" "1.2.0-rc1."; do
  r="$tmp/empty-$(printf '%s' "$bad" | tr -dc 'a-z0-9')"
  make_repo "$r" "$bad"
  rc=0
  out=$(cd "$r" && env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null "$PENDING" 2>/dev/null) || rc=$?
  assert_eq "empty prerelease identifier ($bad) exits 2" "$rc" "2"
done

# 4e. A well-formed prerelease version is accepted and flows through as pending
#     (positive coverage for the prerelease validation path, not just rejection).
r="$tmp/prerelease-ok"
make_repo "$r" "1.0.0-rc.1"
out=$(cd "$r" && env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null "$PENDING")
assert_eq "a valid prerelease version reports pending" "$out" "pending${TAB}1.0.0-rc.1"

# 4f. A build-metadata identifier MUST NOT be empty (SemVer 2.0.0 §10): a leading,
#     trailing, or double dot in the build part yields an empty identifier. The
#     grammar's build class permits dots anywhere, so a second-pass check on the
#     build metadata (mirroring the prerelease empty-identifier rule) rejects it.
#     Regression guard: before the §10 fix these validated and reported pending.
for bad in "1.2.3+build..1" "1.2.3+.foo" "1.2.3+foo."; do
  r="$tmp/badbuild-$(printf '%s' "$bad" | tr -dc 'a-z0-9')"
  make_repo "$r" "$bad"
  rc=0
  out=$(cd "$r" && env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null "$PENDING" 2>/dev/null) || rc=$?
  assert_eq "empty build-metadata identifier ($bad) exits 2" "$rc" "2"
  assert_eq "empty build-metadata identifier ($bad) prints nothing on stdout" "$out" ""
done

# 4g. A well-formed build-metadata version is accepted and flows through as
#     pending (positive coverage for the build-metadata validation path, §10
#     imposes no numeric/leading-zero rule so a leading-zero build id is fine).
r="$tmp/build-ok"
make_repo "$r" "1.0.0+build.001"
out=$(cd "$r" && env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null "$PENDING")
assert_eq "a valid build-metadata version reports pending" "$out" "pending${TAB}1.0.0+build.001"

# 4h. A malformed JSON version_file fails closed with a SPECIFIC parse error, not
#     a silent empty read. Before the fix, rl_extract_version ignored jq's
#     non-zero exit (returned 0 with empty stdout), so a corrupt file surfaced as
#     the generic "not valid SemVer: ''" message with jq's raw parse error leaking
#     to stderr. Both spellings exit 2; the discriminating signal is the message.
r="$tmp/badjson"
mkdir -p "$r/.claude-plugin"
printf '{ "name": "fixture", "version": ' >"$r/.claude-plugin/plugin.json" # truncated → invalid JSON
gitc "$r" init -q
gitc "$r" add -A
gitc "$r" commit -q -m "malformed version_file"
rc=0
err=$(cd "$r" && env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null "$PENDING" 2>&1 >/dev/null) || rc=$?
assert_eq "malformed JSON version_file exits 2" "$rc" "2"
case "$err" in
  *"could not parse JSON version_file"*) hit=yes ;;
  *) hit=no ;;
esac
assert_eq "malformed JSON version_file names the parse failure (no leaked jq error)" "$hit" "yes"

# 5. Latest tag chosen by SemVer precedence, not lexically (0.10.0 > 0.2.0).
r="$tmp/precedence"
make_repo "$r" 0.10.0
gitc "$r" tag v0.1.0
gitc "$r" tag v0.2.0
gitc "$r" tag v0.10.0
out=$(cd "$r" && env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null "$PENDING")
assert_eq "0.10.0 == latest (numeric precedence, not lexical) → none" "$out" "none"
# And one past it is pending.
r="$tmp/precedence2"
make_repo "$r" 0.11.0
gitc "$r" tag v0.2.0
gitc "$r" tag v0.10.0
out=$(cd "$r" && env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null "$PENDING")
assert_eq "0.11.0 ahead of v0.10.0 → pending" "$out" "pending${TAB}0.11.0"

# 6. CDPATH regression (REQ-D1.9): a hostile CDPATH with a decoy `scripts/` must
#    not corrupt the script's `cd "$(dirname "$0")"` (it calls `unset CDPATH`).
#    Per the house pattern (tests/test-check-options-reference.sh:124), the script
#    is copied under `scripts/` in the cwd and invoked by the BARE relative name
#    `scripts/release-pending.sh` — the only shape where CDPATH actually bites an
#    un-guarded cd (a `../`-prefixed or absolute path bypasses CDPATH entirely, so
#    invoking "$PENDING" by its absolute path would prove nothing).
work="$tmp/cdpath"
mkdir -p "$work/scripts" "$work/.claude-plugin" "$tmp/decoy/scripts"
cp "$here/../scripts/release-pending.sh" "$here/../scripts/release-lib.sh" \
  "$here/../scripts/echo-safety.sh" "$work/scripts/"
printf '{\n  "name": "fixture",\n  "version": "0.2.0"\n}\n' >"$work/.claude-plugin/plugin.json"
gitc "$work" init -q
gitc "$work" add -A
gitc "$work" commit -q -m "version 0.2.0"
gitc "$work" tag v0.1.0
out=$(cd "$work" && CDPATH="$tmp/decoy" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null \
  scripts/release-pending.sh)
assert_eq "a hostile CDPATH does not corrupt the comparator (unset CDPATH)" \
  "$out" "pending${TAB}0.2.0"

# 7. version_file canonicalization + containment (REQ-D1.1, REQ-D1.2, D-5).
#    The path is canonicalized (symlinks resolved in every component, INCLUDING
#    the leaf `version_file` itself) and confirmed within the repository root
#    before the filesystem read; anything outside is a clean exit-2 refusal, and
#    the read targets the canonicalized real path, not the original value.
#
# set_vf <repo> <value> — point the version_file knob at <value> via the
# machine-local overlay (same shape the publish tests use).
set_vf() {
  mkdir -p "$1/.claude"
  printf 'version_file: %s\n' "$2" >"$1/.claude/planwright.local.yml"
}

# 7a. A LEAF symlink — the `version_file` value itself is a symlink pointing
#     outside the tree (absolute target) — is refused. This is the exact attack
#     a parent-dir-only `cd; pwd -P` recipe misses. The out-of-tree file holds a
#     valid, ahead version, so a read would print `pending`; the refusal proves
#     no read happened (empty stdout, exit 2, diagnostic).
outside="$tmp/outside"
mkdir -p "$outside"
printf '9.9.9\n' >"$outside/secret"
r="$tmp/leaf-abs"
make_repo "$r" 0.2.0
gitc "$r" tag v0.1.0
ln -s "$outside/secret" "$r/escleaf"
set_vf "$r" escleaf
rc=0
out=$(cd "$r" && env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null "$PENDING" 2>/dev/null) || rc=$?
assert_eq "leaf symlink to an absolute out-of-tree path exits 2" "$rc" "2"
assert_eq "leaf symlink to an absolute out-of-tree path reads nothing (no stdout)" "$out" ""
err=$(cd "$r" && env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null "$PENDING" 2>&1 >/dev/null) || true
case "$err" in *"outside the repository"*) hit=yes ;; *) hit=no ;; esac
assert_eq "leaf symlink refusal names the containment failure" "$hit" "yes"

# 7b. A LEAF symlink escaping via a RELATIVE `../` target. The `version_file`
#     value (`escrel`) has no `..` component, so the cheap `..` pre-filter does
#     NOT catch it — only canonicalization does. This isolates the canonical
#     containment check as the thing doing the work.
r="$tmp/leaf-rel"
make_repo "$r" 0.2.0
gitc "$r" tag v0.1.0
ln -s "../outside/secret" "$r/escrel"
set_vf "$r" escrel
rc=0
out=$(cd "$r" && env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null "$PENDING" 2>/dev/null) || rc=$?
assert_eq "leaf symlink escaping via ../ exits 2 (canonicalization, not the pre-filter)" "$rc" "2"
assert_eq "leaf symlink escaping via ../ reads nothing" "$out" ""

# 7c. A symlinked PARENT directory escaping the tree is refused too (the
#     canonicalization resolves intermediate components, not just the leaf).
r="$tmp/parent-esc"
make_repo "$r" 0.2.0
gitc "$r" tag v0.1.0
ln -s "$outside" "$r/escdir"
set_vf "$r" "escdir/secret"
rc=0
out=$(cd "$r" && env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null "$PENDING" 2>/dev/null) || rc=$?
assert_eq "symlinked parent dir escaping the tree exits 2" "$rc" "2"
assert_eq "symlinked parent dir escaping the tree reads nothing" "$out" ""

# 7d. A dangling/broken symlink (target does not exist) is a CLEAN exit-2
#     refusal via the CANONICALIZATION path, not an unhandled error. Asserting the
#     canonicalization diagnostic (rather than only exit 2 + empty stdout, which
#     the pre-change `[ ! -f ]` branch already produced for a dangling symlink)
#     is what makes this discriminating — it fails on the pre-change code, which
#     says "not found".
r="$tmp/dangling"
make_repo "$r" 0.2.0
gitc "$r" tag v0.1.0
ln -s "/no/such/path/version" "$r/broken"
set_vf "$r" broken
rc=0
err=$(cd "$r" && env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null "$PENDING" 2>&1 >/dev/null) || rc=$?
assert_eq "a dangling symlink version_file exits 2 (clean refusal)" "$rc" "2"
case "$err" in *"cannot be canonicalized"*) hit=yes ;; *) hit=no ;; esac
assert_eq "a dangling symlink names the canonicalization failure (not generic not-found)" "$hit" "yes"

# 7e. A symlink LOOP is a clean exit-2 refusal via the canonicalization path
#     (bounded resolution, no hang, no unhandled error). Same discriminating
#     diagnostic assertion as 7d.
r="$tmp/loop"
make_repo "$r" 0.2.0
gitc "$r" tag v0.1.0
ln -s loopB "$r/loopA"
ln -s loopA "$r/loopB"
set_vf "$r" loopA
rc=0
err=$(cd "$r" && env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null "$PENDING" 2>&1 >/dev/null) || rc=$?
assert_eq "a symlink loop version_file exits 2 (clean refusal)" "$rc" "2"
case "$err" in *"cannot be canonicalized"*) hit=yes ;; *) hit=no ;; esac
assert_eq "a symlink loop names the canonicalization failure (not generic not-found)" "$hit" "yes"

# 7f. An in-tree `version_file` reached via an IN-TREE symlink still resolves and
#     reads (canonicalization must not break the legitimate case). The real file
#     is a plain whole-file VERSION; `vlink` points at it inside the repo.
r="$tmp/intree-link"
make_repo "$r" 0.1.0
printf '0.2.0\n' >"$r/REALVERSION"
gitc "$r" add -A
gitc "$r" commit -q -m "add REALVERSION"
gitc "$r" tag v0.1.0
ln -s REALVERSION "$r/vlink"
set_vf "$r" vlink
out=$(cd "$r" && env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null "$PENDING")
assert_eq "an in-tree version_file via an in-tree symlink still reads" "$out" "pending${TAB}0.2.0"

# 7g. A plain (non-symlink) in-tree `version_file` set via the knob still reads
#     — making the "(plain, ...) still resolves and reads" half of REQ-D1.1
#     explicit rather than only implied by the default-path sections above.
r="$tmp/intree-plain"
make_repo "$r" 0.1.0
printf '0.2.0\n' >"$r/VERSION"
gitc "$r" add -A
gitc "$r" commit -q -m "add VERSION"
gitc "$r" tag v0.1.0
set_vf "$r" VERSION
out=$(cd "$r" && env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null "$PENDING")
assert_eq "a plain in-tree version_file set via the knob still reads" "$out" "pending${TAB}0.2.0"

# 7h. A MULTI-HOP symlink chain resolves every hop: an in-tree chain still reads,
#     and a chain whose final hop escapes the tree is refused (single-hop 7a-7c
#     do not exercise the iterative leaf resolution).
r="$tmp/chain-intree"
make_repo "$r" 0.1.0
printf '0.2.0\n' >"$r/REALVERSION"
gitc "$r" add -A
gitc "$r" commit -q -m "add REALVERSION"
gitc "$r" tag v0.1.0
ln -s REALVERSION "$r/hop2"
ln -s hop2 "$r/hop1"
set_vf "$r" hop1
out=$(cd "$r" && env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null "$PENDING")
assert_eq "an in-tree multi-hop symlink chain resolves and reads" "$out" "pending${TAB}0.2.0"

r="$tmp/chain-escape"
make_repo "$r" 0.2.0
gitc "$r" tag v0.1.0
ln -s "$outside/secret" "$r/ehop2"
ln -s ehop2 "$r/ehop1"
set_vf "$r" ehop1
rc=0
out=$(cd "$r" && env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null "$PENDING" 2>/dev/null) || rc=$?
assert_eq "a multi-hop symlink chain escaping the tree is refused (exit 2)" "$rc" "2"
assert_eq "a multi-hop escaping chain reads nothing" "$out" ""

# 7i. A leaf symlink whose target is `..` (a parent-DENOTING path) must not pass
#     containment. `<root>/..` textually sits under the root but denotes the
#     parent; the reusable guard rejects it at canonicalization (via the clean
#     canonicalization diagnostic), rather than relying on the caller's `-f`
#     check to catch that the parent is a directory (REQ-D1.2 reusable-guard
#     contract). Discriminating: the pre-fix guard returned `<root>/..` as
#     "contained" and the caller's `[ ! -f ]` produced the generic not-found.
r="$tmp/dotdot-leaf"
make_repo "$r" 0.2.0
gitc "$r" tag v0.1.0
ln -s ".." "$r/uplink"
set_vf "$r" uplink
rc=0
err=$(cd "$r" && env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null "$PENDING" 2>&1 >/dev/null) || rc=$?
assert_eq "a leaf symlink denoting the parent (../) is refused (exit 2)" "$rc" "2"
case "$err" in *"outside the repository or cannot be canonicalized"*) hit=yes ;; *) hit=no ;; esac
assert_eq "a parent-denoting leaf is refused by the containment guard, not the -f check" "$hit" "yes"

# 7j. Prefix-collision containment boundary. The guard compares `"$canon/"`
#     against `"$root/"*` — the trailing slashes are load-bearing: they stop a
#     SIBLING whose path shares the root as a textual prefix (`<root>-evil`) from
#     matching `<root>` and being wrongly judged contained (the classic path-
#     prefix bypass). Every other escape case above targets `$tmp/outside`, which
#     is not a prefix-extension of any test root, so none of them exercise this
#     boundary; dropping the trailing slash from the pattern would leave the whole
#     suite green. This test pins it: a leaf symlink escaping into `<root>-evil`
#     (a valid, ahead version out there) must still be refused with no read.
r="$tmp/prefixcol"
sibling="$tmp/prefixcol-evil"
mkdir -p "$sibling"
printf '9.9.9\n' >"$sibling/secret"
make_repo "$r" 0.2.0
gitc "$r" tag v0.1.0
ln -s "$sibling/secret" "$r/siblink"
set_vf "$r" siblink
rc=0
out=$(cd "$r" && env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null "$PENDING" 2>/dev/null) || rc=$?
assert_eq "a sibling sharing the root as a path prefix (<root>-evil) is refused (exit 2)" "$rc" "2"
assert_eq "a prefix-collision sibling reads nothing (trailing-slash boundary holds)" "$out" ""

# 7k. A version_file value beginning with '-' must not be misparsed as an OPTION
#     by the readlink/dirname/basename calls inside the canonicalization guard.
#     Those calls need the `--` end-of-options guard the sibling `cd --` calls
#     already use; without it, BSD dirname/basename (GNU too) print an "illegal
#     option"/"invalid option" usage error to stderr and the refusal falls out of
#     an incidental cd failure rather than clean handling. The value is still a
#     safe exit-2 refusal either way, so the leaked usage noise is the
#     discriminating signal: this fails on the pre-`--` code (stderr carries the
#     option-parse error) and passes once the four calls are hardened.
r="$tmp/dash-leaf"
make_repo "$r" 0.2.0
gitc "$r" tag v0.1.0
set_vf "$r" "-n"
rc=0
err=$(cd "$r" && env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null "$PENDING" 2>&1 >/dev/null) || rc=$?
assert_eq "a leading-dash version_file exits 2 (clean refusal)" "$rc" "2"
case "$err" in
  *"illegal option"* | *"invalid option"*) leaked=yes ;;
  *) leaked=no ;;
esac
assert_eq "a leading-dash version_file leaks no readlink/dirname/basename option-parse error" "$leaked" "no"

# 7l. Regression guard for REQ-D1.2's "readers untouched" claim: the three
#     git-show readers are symlink-immune and must NOT gain the canonicalization
#     guard. Assert none of them reference the reusable function (a future edge
#     that wrongly added it would otherwise pass CI silently). Grep-level, matching
#     the [design-level] cross-check the test-spec names.
untouched=yes
for reader in release-window-check.sh release-publish.sh release-arm.sh; do
  if grep -q 'rl_canonical_contained_path' "$here/../scripts/$reader"; then
    untouched=no
    echo "  (unexpected: $reader references rl_canonical_contained_path)" >&2
  fi
done
assert_eq "the symlink-immune git-show readers do not reference the canonicalization guard" "$untouched" "yes"

# 7m. Exercise the `readlink --` end-of-options guard. It fires only when the
#     leaf IS a symlink whose NAME begins with '-', so `_rl_resolve_leaf_symlink`
#     calls `readlink -- "$target"` on a dash-leading operand. (7k's value `-n` is
#     a non-existent non-symlink, so `[ -L "-n" ]` is false and readlink is never
#     reached — only dirname/basename `--` are.) The leaf points at an in-tree
#     REALVERSION, so a correct resolve reads `pending`. Discriminating: without
#     the `--`, `readlink -dleaf` is parsed as options ("illegal option") and the
#     guard refuses (exit 2, no read); the green `pending` here holds only while
#     the readlink call is `--`-guarded.
r="$tmp/dash-symlink-leaf"
make_repo "$r" 0.1.0
printf '0.2.0\n' >"$r/REALVERSION"
gitc "$r" add -A
gitc "$r" commit -q -m "add REALVERSION"
gitc "$r" tag v0.1.0
ln -s REALVERSION "$r/-dleaf"
set_vf "$r" "-dleaf"
out=$(cd "$r" && env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null "$PENDING")
assert_eq "an in-tree leaf symlink whose name starts with '-' reads (readlink -- guard)" "$out" "pending${TAB}0.2.0"

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "PASS: test-release-pending.sh"
