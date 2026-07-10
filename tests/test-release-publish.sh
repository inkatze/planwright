#!/bin/bash
# Tests for scripts/release-publish.sh — the signed-publish script (autopilot-
# reflex Task 4; D-4, D-6, D-8; REQ-D1.1..REQ-D1.7, REQ-E1.4).
#
# Contract under test:
#   - signer-agnostic: no signer name in the script; signing rides git config
#     (REQ-D1.1) — grep assertion plus behavioral signed/unsigned fixtures;
#   - tags the observed release-merge SHA, never HEAD, under a post-merge race
#     (REQ-D1.2, REQ-E1.4);
#   - every safety gate refuses WITHOUT side effects (no tag, no Release):
#     existing local tag, existing origin tag (fully published), non-monotonic
#     version, dirty tree, diverged main, CI-not-green (REQ-D1.3); a first
#     release (no tags) publishes;
#   - require_signed_tags auto/require/never each exercised (REQ-D1.4);
#   - a signed tag is verified before push; a verify failure aborts unpushed
#     (REQ-D1.5);
#   - the version_file knob ports the version of truth (REQ-D1.6);
#   - the GitHub Release is created from the CHANGELOG section with --verify-tag,
#     gh never creates the tag; a partial publish (tag pushed, Release absent)
#     resumes (REQ-D1.7).
#
# gh is stubbed (no network); git signing uses a throwaway SSH key (no
# 1Password/agent dependency). Runs standalone under /bin/bash (bash 3.2 floor).
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
PUBLISH="$here/../scripts/release-publish.sh"
failures=0

[ -x "$PUBLISH" ] || {
  echo "FAIL: scripts/release-publish.sh missing or not executable" >&2
  exit 1
}

pass() { echo "ok: $1"; }
bad() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}
assert_eq() {
  if [ "$2" = "$3" ]; then pass "$1"; else bad "$1 — expected [$3], got [$2]"; fi
}
assert_ne() {
  if [ "$2" != "$3" ]; then pass "$1"; else bad "$1 — did not expect [$3]"; fi
}
assert_contains() {
  case "$2" in
    *"$3"*) pass "$1" ;;
    *) bad "$1 — [$2] lacks [$3]" ;;
  esac
}
# want <desc> <cmd...> — <cmd> is expected to succeed; deny — to fail.
want() {
  local d="$1"
  shift
  if "$@"; then pass "$d"; else bad "$d"; fi
}
deny() {
  local d="$1"
  shift
  if "$@"; then bad "$d"; else pass "$d"; fi
}

gc() {
  # signing-free git for FIXTURE setup commits (the script's own tag commands
  # deliberately run with the ambient config so signing engages).
  git -C "$1" -c user.name=test -c user.email=test@example.invalid \
    -c commit.gpgsign=false -c init.defaultBranch=main "${@:2}"
}

write_plugin() {
  mkdir -p "$1/.claude-plugin"
  cat >"$1/.claude-plugin/plugin.json" <<EOF
{
  "name": "fixture",
  "version": "$2"
}
EOF
}

# new_repo <dir> — a working clone of a fresh bare origin, on branch main, with a
# repo-level (non-signing) identity. Mirrors the real repo by gitignoring the
# machine-local overlay so an overlay drop never dirties the tree. No commits yet.
new_repo() {
  local dir="$1" origin="$1.git"
  git init -q --bare "$origin"
  git clone -q "$origin" "$dir" 2>/dev/null
  git -C "$dir" checkout -q -b main 2>/dev/null || true
  git -C "$dir" config user.name test
  git -C "$dir" config user.email test@example.invalid
  git -C "$dir" config commit.gpgsign false
  printf '.claude/\n' >"$dir/.gitignore"
}

# seed_version <dir> <version> — the version-bump commit, pushed to origin/main.
seed_version() {
  write_plugin "$1" "$2"
  git -C "$1" add -A
  git -C "$1" commit -q -m "chore: release $2"
  git -C "$1" push -q -u origin main 2>/dev/null
}

# --- gh stub -----------------------------------------------------------------
# Logs each invocation to $GH_LOG; `release view` exits per GH_RELEASE_EXISTS;
# `api .../check-runs` prints canned JSON per GH_CI; `release create` copies its
# --notes-file to $GH_NOTES and logs. Everything else is a benign success.
make_gh_stub() {
  local dir="$1"
  mkdir -p "$dir"
  cat >"$dir/gh" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >>"${GH_LOG:-/dev/null}"
case "$1" in
  release)
    case "$2" in
      view) [ "${GH_RELEASE_EXISTS:-0}" = 1 ] && exit 0 || exit 1 ;;
      create)
        nf=""
        while [ "$#" -gt 0 ]; do
          [ "$1" = "--notes-file" ] && { nf="$2"; break; }
          shift
        done
        [ -n "$nf" ] && [ -n "${GH_NOTES:-}" ] && cp "$nf" "$GH_NOTES"
        exit 0
        ;;
    esac
    exit 0
    ;;
  api)
    if [ "${GH_CI:-green}" = green ]; then
      printf '{"check_runs":[{"status":"completed","conclusion":"success"}]}\n'
    else
      printf '{"check_runs":[{"status":"completed","conclusion":"failure"}]}\n'
    fi
    exit 0
    ;;
esac
exit 0
STUB
  chmod +x "$dir/gh"
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
stub="$tmp/bin"
make_gh_stub "$stub"

# run_publish <dir> [VAR=val ...] — run the script in <dir> with the gh stub on
# PATH and a fresh GH_LOG/GH_NOTES; prints nothing, sets RC/OUT/ERR/LOG/NOTES.
run_publish() {
  local dir="$1"
  shift
  LOG="$tmp/ghlog.$$"
  NOTES="$tmp/ghnotes.$$"
  : >"$LOG"
  : >"$NOTES"
  RC=0
  # Isolate git from the developer's global/system config (GIT_CONFIG_GLOBAL /
  # _SYSTEM = /dev/null) so ambient commit-signing never leaks into a fixture
  # and signing detection sees ONLY what the fixture configures repo-locally.
  OUT=$(cd "$dir" && env PATH="$stub:$PATH" GH_LOG="$LOG" GH_NOTES="$NOTES" \
    GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null "$@" \
    "$PUBLISH" 2>"$tmp/err.$$") || RC=$?
  ERR=$(cat "$tmp/err.$$")
}

origin_has_tag() { [ -n "$(git -C "$1.git" tag -l "$2")" ]; }
local_has_tag() { [ -n "$(git -C "$1" tag -l "$2")" ]; }
gh_called() { grep -q "$2" "$1" 2>/dev/null; }

# ===========================================================================
# 1. Signer-agnostic: no signer name hardcoded in the script (REQ-D1.1).
# ===========================================================================
# Reading `git config --get user.signingkey` IS the signer-agnostic pattern; a
# hardcoded signer would be op-ssh-sign, a 1Password reference, or an explicit
# --local-user/key id (the D-4 rejected alternatives).
if grep -Eqi 'op-ssh-sign|1password|--local-user' "$PUBLISH"; then
  bad "signer-agnostic: the script appears to name a signer"
else
  pass "signer-agnostic: no signer named in the script (signing rides git config)"
fi

# ===========================================================================
# 2. First release (no tags) publishes; tag lands, gh Release created (REQ-D1.3).
# ===========================================================================
r="$tmp/first"
new_repo "$r"
seed_version "$r" 0.1.0
run_publish "$r" GH_CI=green GH_RELEASE_EXISTS=0
assert_eq "first release: exit 0" "$RC" "0"
want "first release: local tag v0.1.0 created" local_has_tag "$r" v0.1.0
want "first release: tag pushed to origin" origin_has_tag "$r" v0.1.0
want "first release: gh release create invoked" gh_called "$LOG" "release create"
want "first release: --verify-tag passed to gh" gh_called "$LOG" "verify-tag"

# ===========================================================================
# 3. Tags the observed release-merge SHA, not HEAD, under a post-merge race
#    (REQ-D1.2, REQ-E1.4).
# ===========================================================================
r="$tmp/race"
new_repo "$r"
seed_version "$r" 0.1.0
gc "$r" checkout -q -b relprep
write_plugin "$r" 0.2.0
gc "$r" add -A
gc "$r" commit -q -m "chore: release 0.2.0"
gc "$r" checkout -q main
gc "$r" merge -q --no-ff -m "Merge release 0.2.0" relprep
MERGE_SHA=$(git -C "$r" rev-parse HEAD)
gc "$r" commit -q --allow-empty -m "chore: unrelated follow-up"
gc "$r" push -q origin main 2>/dev/null
run_publish "$r" GH_CI=green GH_RELEASE_EXISTS=0
assert_eq "race: exit 0" "$RC" "0"
TAGGED=$(git -C "$r" rev-parse "v0.2.0^{commit}" 2>/dev/null || echo none)
assert_eq "race: tag lands on the release-merge SHA, not HEAD" "$TAGGED" "$MERGE_SHA"
assert_ne "race: HEAD is past the merge (the race is real)" "$MERGE_SHA" "$(git -C "$r" rev-parse HEAD)"

# ===========================================================================
# 4. Safety gates each refuse WITHOUT side effects (REQ-D1.3).
# ===========================================================================
# 4a. existing local tag.
r="$tmp/gate-localtag"
new_repo "$r"
seed_version "$r" 0.1.0
gc "$r" tag v0.1.0
run_publish "$r" GH_CI=green GH_RELEASE_EXISTS=0
assert_ne "gate/local-tag: exits non-zero" "$RC" "0"
assert_contains "gate/local-tag: names the idempotency gate" "$ERR" "idempotency gate"
deny "gate/local-tag: no tag pushed to origin" origin_has_tag "$r" v0.1.0
deny "gate/local-tag: no Release created" gh_called "$LOG" "release create"

# 4b. existing origin tag, fully published (Release present).
r="$tmp/gate-origintag"
new_repo "$r"
seed_version "$r" 0.1.0
gc "$r" tag v0.1.0
gc "$r" push -q origin v0.1.0 2>/dev/null
gc "$r" tag -d v0.1.0 >/dev/null
run_publish "$r" GH_CI=green GH_RELEASE_EXISTS=1
assert_ne "gate/origin-tag: exits non-zero" "$RC" "0"
assert_contains "gate/origin-tag: names already-published" "$ERR" "already published"

# 4c. non-monotonic version.
r="$tmp/gate-monotonic"
new_repo "$r"
seed_version "$r" 0.1.0
gc "$r" tag v0.2.0
gc "$r" push -q origin v0.2.0 2>/dev/null
run_publish "$r" GH_CI=green GH_RELEASE_EXISTS=0
assert_ne "gate/monotonic: exits non-zero" "$RC" "0"
assert_contains "gate/monotonic: names the monotonicity gate" "$ERR" "monotonicity gate"
deny "gate/monotonic: no v0.1.0 tag pushed" origin_has_tag "$r" v0.1.0

# 4d. dirty working tree.
r="$tmp/gate-dirty"
new_repo "$r"
seed_version "$r" 0.1.0
echo "dirt" >>"$r/.claude-plugin/plugin.json"
run_publish "$r" GH_CI=green GH_RELEASE_EXISTS=0
assert_ne "gate/dirty: exits non-zero" "$RC" "0"
assert_contains "gate/dirty: names the clean-tree gate" "$ERR" "clean-tree gate"
deny "gate/dirty: no local tag created" local_has_tag "$r" v0.1.0

# 4e. diverged main (a local unpushed commit).
r="$tmp/gate-diverged"
new_repo "$r"
seed_version "$r" 0.1.0
gc "$r" commit -q --allow-empty -m "local only"
run_publish "$r" GH_CI=green GH_RELEASE_EXISTS=0
assert_ne "gate/diverged: exits non-zero" "$RC" "0"
assert_contains "gate/diverged: names the sync gate" "$ERR" "sync gate"

# 4f. CI not green.
r="$tmp/gate-ci"
new_repo "$r"
seed_version "$r" 0.1.0
run_publish "$r" GH_CI=red GH_RELEASE_EXISTS=0
assert_ne "gate/ci: exits non-zero" "$RC" "0"
assert_contains "gate/ci: names the ci gate" "$ERR" "ci gate"
deny "gate/ci: no local tag created" local_has_tag "$r" v0.1.0

# ===========================================================================
# 5. require_signed_tags modes (REQ-D1.4) + verify-before-push (REQ-D1.5).
# ===========================================================================
if command -v ssh-keygen >/dev/null 2>&1; then
  # A repo with SSH signing configured against a throwaway key. Key material and
  # the allowed-signers file live OUTSIDE the working tree so they never dirty it.
  configure_signing() { # <dir> [allowed-signers-key.pub]
    local dir="$1" keydir="$1.keys" allow
    mkdir -p "$keydir"
    ssh-keygen -q -t ed25519 -N '' -C test -f "$keydir/key" 2>/dev/null
    allow="${2:-$keydir/key.pub}"
    git -C "$dir" config gpg.format ssh
    git -C "$dir" config user.signingkey "$keydir/key"
    printf 'test@example.invalid %s\n' "$(cat "$allow")" >"$keydir/allowed_signers"
    git -C "$dir" config gpg.ssh.allowedSignersFile "$keydir/allowed_signers"
  }

  # 5a. auto + signing configured → a signed, verified tag.
  r="$tmp/sign-auto"
  new_repo "$r"
  seed_version "$r" 0.1.0
  configure_signing "$r"
  run_publish "$r" GH_CI=green GH_RELEASE_EXISTS=0
  assert_eq "sign/auto: exit 0" "$RC" "0"
  if git -C "$r" cat-file tag v0.1.0 2>/dev/null | grep -q 'BEGIN SSH SIGNATURE'; then
    pass "sign/auto: the tag is signed"
  else
    bad "sign/auto: the tag is not signed"
  fi

  # 5b. never + signing configured → an UNSIGNED annotated tag.
  r="$tmp/sign-never"
  new_repo "$r"
  seed_version "$r" 0.1.0
  configure_signing "$r"
  mkdir -p "$r/.claude"
  printf 'require_signed_tags: never\n' >"$r/.claude/planwright.local.yml"
  run_publish "$r" GH_CI=green GH_RELEASE_EXISTS=0
  assert_eq "sign/never: exit 0" "$RC" "0"
  if git -C "$r" cat-file tag v0.1.0 2>/dev/null | grep -q 'BEGIN SSH SIGNATURE'; then
    bad "sign/never: the tag is signed despite never"
  else
    pass "sign/never: the tag is unsigned"
  fi

  # 5c. require + NO signing configured → refuse.
  r="$tmp/sign-require"
  new_repo "$r"
  seed_version "$r" 0.1.0
  mkdir -p "$r/.claude"
  printf 'require_signed_tags: require\n' >"$r/.claude/planwright.local.yml"
  run_publish "$r" GH_CI=green GH_RELEASE_EXISTS=0
  assert_ne "sign/require: exits non-zero with no signing" "$RC" "0"
  assert_contains "sign/require: names the signing gate" "$ERR" "signing gate"

  # 5d. signed but verification fails (allowed-signers = a DIFFERENT key) →
  #     abort before push, no tag left behind (REQ-D1.5).
  r="$tmp/sign-verifyfail"
  new_repo "$r"
  seed_version "$r" 0.1.0
  mkdir -p "$r.keys"
  ssh-keygen -q -t ed25519 -N '' -C other -f "$r.keys/otherkey" 2>/dev/null
  configure_signing "$r" "$r.keys/otherkey.pub"
  run_publish "$r" GH_CI=green GH_RELEASE_EXISTS=0
  assert_ne "sign/verify-fail: exits non-zero" "$RC" "0"
  assert_contains "sign/verify-fail: names the verify gate" "$ERR" "verify gate"
  deny "sign/verify-fail: no local tag left behind" local_has_tag "$r" v0.1.0
  deny "sign/verify-fail: nothing pushed" origin_has_tag "$r" v0.1.0
else
  echo "skip: ssh-keygen unavailable — signing sub-tests (5a-5d) skipped"
fi

# ===========================================================================
# 6. version_file knob ports the version of truth (REQ-D1.6).
# ===========================================================================
# 6a. package.json JSON selector override.
r="$tmp/vf-pkg"
new_repo "$r"
cat >"$r/package.json" <<'EOF'
{
  "name": "fixture",
  "version": "0.4.0"
}
EOF
git -C "$r" add -A
git -C "$r" -c user.name=test -c user.email=t@e -c commit.gpgsign=false commit -q -m "chore: release 0.4.0"
git -C "$r" push -q -u origin main 2>/dev/null
mkdir -p "$r/.claude"
printf 'version_file: package.json::$.version\n' >"$r/.claude/planwright.local.yml"
run_publish "$r" GH_CI=green GH_RELEASE_EXISTS=0
assert_eq "version_file/pkg: exit 0" "$RC" "0"
want "version_file/pkg: tag v0.4.0 from package.json" local_has_tag "$r" v0.4.0

# 6b. whole-file VERSION selector (no JSON).
r="$tmp/vf-plain"
new_repo "$r"
printf '0.5.0\n' >"$r/VERSION"
git -C "$r" add -A
git -C "$r" -c user.name=test -c user.email=t@e -c commit.gpgsign=false commit -q -m "chore: release 0.5.0"
git -C "$r" push -q -u origin main 2>/dev/null
mkdir -p "$r/.claude"
printf 'version_file: VERSION\n' >"$r/.claude/planwright.local.yml"
run_publish "$r" GH_CI=green GH_RELEASE_EXISTS=0
assert_eq "version_file/plain: exit 0" "$RC" "0"
want "version_file/plain: tag v0.5.0 from a plain VERSION file" local_has_tag "$r" v0.5.0

# ===========================================================================
# 7. Release notes from the CHANGELOG section + partial-publish resume
#    (REQ-D1.7).
# ===========================================================================
# 7a. notes come from the version's CHANGELOG.md section.
r="$tmp/changelog"
new_repo "$r"
write_plugin "$r" 0.3.0
cat >"$r/CHANGELOG.md" <<'EOF'
# Changelog

## [0.3.0] - 2026-07-09

### Features

- the release-tagging machinery

## [0.2.0] - 2026-07-01

- earlier things
EOF
git -C "$r" add -A
git -C "$r" -c user.name=test -c user.email=t@e -c commit.gpgsign=false commit -q -m "chore: release 0.3.0"
git -C "$r" push -q -u origin main 2>/dev/null
run_publish "$r" GH_CI=green GH_RELEASE_EXISTS=0
assert_eq "changelog: exit 0" "$RC" "0"
assert_contains "changelog: notes include this version's section" "$(cat "$NOTES")" "the release-tagging machinery"
if grep -q "earlier things" "$NOTES"; then
  bad "changelog: notes bled into the previous version's section"
else
  pass "changelog: notes stop at the next version heading"
fi

# 7b. partial publish: tag pushed, Release absent → resume, create the Release.
r="$tmp/partial"
new_repo "$r"
seed_version "$r" 0.1.0
gc "$r" tag v0.1.0
gc "$r" push -q origin v0.1.0 2>/dev/null
gc "$r" tag -d v0.1.0 >/dev/null
run_publish "$r" GH_CI=green GH_RELEASE_EXISTS=0
assert_eq "partial: exit 0 (resumed)" "$RC" "0"
assert_contains "partial: reports a resume" "$OUT" "resumed"
want "partial: gh release create invoked on resume" gh_called "$LOG" "release create"

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "PASS: test-release-publish.sh"
