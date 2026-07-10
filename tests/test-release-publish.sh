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
# Logs each invocation to $GH_LOG. `repo view` prints a canned nameWithOwner;
# `api graphql` prints a statusCheckRollup per GH_CI (green→SUCCESS, red→FAILURE,
# none→null rollup); `release view` exits per GH_RELEASE_EXISTS; `release create`
# copies its --notes-file to $GH_NOTES. Everything else is a benign success.
make_gh_stub() {
  local dir="$1"
  mkdir -p "$dir"
  cat >"$dir/gh" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >>"${GH_LOG:-/dev/null}"
case "$1" in
  repo) printf 'testowner/testrepo\n'; exit 0 ;;
  release)
    case "$2" in
      view)
        # Model real gh: exists → exit 0; genuinely absent → "release not found"
        # on stderr + exit 1; a transient failure → a generic error on stderr +
        # exit 1 (GH_RELEASE_VIEW_ERR selects this so the fail-closed path is
        # testable). release_state classifies on the stderr text, so the stub must
        # emit the real "release not found" phrasing for the absent case.
        if [ "${GH_RELEASE_VIEW_ERR:-0}" = 1 ]; then
          echo "error connecting to api.github.com" >&2
          exit 1
        fi
        [ "${GH_RELEASE_EXISTS:-0}" = 1 ] && exit 0
        echo "release not found" >&2
        exit 1
        ;;
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
    # The only `gh api` call is the statusCheckRollup GraphQL query.
    case "${GH_CI:-green}" in
      green) printf '{"data":{"repository":{"object":{"statusCheckRollup":{"state":"SUCCESS"}}}}}\n' ;;
      none) printf '{"data":{"repository":{"object":{"statusCheckRollup":null}}}}\n' ;;
      *) printf '{"data":{"repository":{"object":{"statusCheckRollup":{"state":"FAILURE"}}}}}\n' ;;
    esac
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
# auto + no signing configured (git isolated in run_publish) → the OTHER half of
# REQ-D1.1: an unsigned annotated tag plus a warning (behavioral teeth, A3).
if git -C "$r" cat-file tag v0.1.0 2>/dev/null | grep -q 'BEGIN SSH SIGNATURE'; then
  bad "first release: auto path produced a signed tag with no signing configured"
else
  pass "first release: auto with no signing → an unsigned annotated tag"
fi
assert_contains "first release: warns that no signing is configured" "$ERR" "no signing configured"

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
want "race: CI gate queried GitHub for the release-merge SHA, not HEAD" gh_called "$LOG" "sha=$MERGE_SHA"

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
deny "gate/origin-tag: no Release create attempted (no side effect)" gh_called "$LOG" "release create"

# 4b-2. A TRANSIENT gh failure during resume-detection must fail closed, not read
#       as "Release absent" (which would flip resume=1 and fire a misleading
#       gh release create + repeated wasted retries on every outage). Origin has
#       the tag; gh release view errors transiently → die naming the query
#       failure, no resume, no Release create. Before the fix, release_exists
#       treated any gh failure as absent, so this published (RC 0).
r="$tmp/gate-releaseview-err"
new_repo "$r"
seed_version "$r" 0.1.0
gc "$r" tag v0.1.0
gc "$r" push -q origin v0.1.0 2>/dev/null
gc "$r" tag -d v0.1.0 >/dev/null
run_publish "$r" GH_CI=green GH_RELEASE_VIEW_ERR=1
assert_ne "gate/release-view-error: exits non-zero" "$RC" "0"
assert_contains "gate/release-view-error: names the query failure, not absence" "$ERR" "could not query the GitHub Release"
deny "gate/release-view-error: no Release create attempted (fail closed)" gh_called "$LOG" "release create"

# 4b-3. The release-merge SHA scan fails closed on a version_file it cannot PARSE
#       at a historical ref (rl_version_at rc 2), rather than ignoring the exit
#       status and treating the empty read as a version boundary. An ABSENT file
#       at an older ref (rc 0, empty) remains a legitimate boundary — only a
#       genuine parse failure dies. Before the fix the scan ignored the status and
#       published.
r="$tmp/scan-parse-error"
new_repo "$r"
mkdir -p "$r/.claude-plugin"
printf '{ "name": "fixture", "version": ' >"$r/.claude-plugin/plugin.json" # malformed history commit
gc "$r" add -A
gc "$r" commit -q -m "chore: malformed version_file (history)"
write_plugin "$r" 0.2.0 # valid version of truth at the tip
gc "$r" add -A
gc "$r" commit -q -m "chore: release 0.2.0"
gc "$r" push -q origin main 2>/dev/null
run_publish "$r" GH_CI=green GH_RELEASE_EXISTS=0
assert_ne "scan/parse-error: exits non-zero (fails closed)" "$RC" "0"
assert_contains "scan/parse-error: names the scanning read failure" "$ERR" "while scanning for the release commit"
deny "scan/parse-error: no tag pushed" origin_has_tag "$r" v0.2.0

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

# 4c-2. Monotonicity reads ORIGIN's tags, not the local cache. A higher release
#       tag on origin that is ABSENT locally (stale/un-fetched clone) must still
#       block a lower publish. Before the fix rl_latest_release_tag read local
#       `git tag -l` only, so the stale clone saw no tags and published.
r="$tmp/gate-monotonic-origin"
new_repo "$r"
seed_version "$r" 0.1.0
gc "$r" tag v0.5.0
gc "$r" push -q origin v0.5.0 2>/dev/null
gc "$r" tag -d v0.5.0 >/dev/null # local clone no longer has the tag (stale cache)
run_publish "$r" GH_CI=green GH_RELEASE_EXISTS=0
assert_ne "gate/monotonic-origin: exits non-zero (origin tag beats a stale local cache)" "$RC" "0"
assert_contains "gate/monotonic-origin: names the monotonicity gate" "$ERR" "monotonicity gate"
deny "gate/monotonic-origin: no v0.1.0 tag pushed" origin_has_tag "$r" v0.1.0

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
deny "gate/diverged: no local tag created (no side effect)" local_has_tag "$r" v0.1.0

# 4g. GitHub CI reports no checks at all (null rollup) → refuse (strict: a
#     release gate requires positive CI confirmation).
r="$tmp/gate-nochecks"
new_repo "$r"
seed_version "$r" 0.1.0
run_publish "$r" GH_CI=none GH_RELEASE_EXISTS=0
assert_ne "gate/no-checks: exits non-zero (no CI → refuse)" "$RC" "0"
assert_contains "gate/no-checks: names the ci gate with the rollup state" "$ERR" "rollup state: NONE"
deny "gate/no-checks: no local tag created" local_has_tag "$r" v0.1.0

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
  # Positive verify-before-push (A4, REQ-D1.5): the pushed tag verifies against
  # the allowed-signers file, i.e. `git tag -v` would (and did) pass before push.
  if git -C "$r" -c gpg.ssh.allowedSignersFile="$r.keys/allowed_signers" tag -v v0.1.0 >/dev/null 2>&1; then
    pass "sign/auto: the signed tag verifies (git tag -v gates the push)"
  else
    bad "sign/auto: the signed tag does not verify"
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

# 7b. partial publish in the REAL post-failure state: the local tag is present
#     (created + pushed), the tag is on origin, and the Release is absent (gh
#     release create failed). A same-machine re-run must RESUME, not die on the
#     local tag. (Keeping the local tag is the key: an earlier version deleted it
#     and masked that the resume branch was unreachable with a local tag present.)
r="$tmp/partial"
new_repo "$r"
seed_version "$r" 0.1.0
gc "$r" tag v0.1.0
gc "$r" push -q origin v0.1.0 2>/dev/null
run_publish "$r" GH_CI=green GH_RELEASE_EXISTS=0
assert_eq "partial: exit 0 (resumed with the local tag still present)" "$RC" "0"
assert_contains "partial: reports a resume" "$OUT" "resumed"
want "partial: gh release create invoked on resume" gh_called "$LOG" "release create"

# 7c. local tag present but NOT on origin (e.g. a push that never landed) → a
#     clean refusal with actionable guidance, never a silent resume.
r="$tmp/localonly"
new_repo "$r"
seed_version "$r" 0.1.0
gc "$r" tag v0.1.0
run_publish "$r" GH_CI=green GH_RELEASE_EXISTS=0
assert_ne "local-only tag: exits non-zero" "$RC" "0"
assert_contains "local-only tag: names the idempotency gate with guidance" "$ERR" "exists locally but not on origin"
deny "local-only tag: no Release create attempted" gh_called "$LOG" "release create"

# 7d. release notes come from CHANGELOG at the RELEASE SHA, not the working tree
#     (F3, D-6): a commit after the release merge rewrites the section, but the
#     notes must reflect the tagged commit's content.
r="$tmp/changelog-sha"
new_repo "$r"
write_plugin "$r" 0.3.0
cat >"$r/CHANGELOG.md" <<'EOF'
# Changelog

## [0.3.0] - 2026-07-09

- notes AS OF the release commit
EOF
git -C "$r" add -A
git -C "$r" -c user.name=test -c user.email=t@e -c commit.gpgsign=false commit -q -m "chore: release 0.3.0"
# A later commit on main rewrites the same section (the interleaving the SHA
# pinning defends against) — this must NOT reach the notes.
cat >"$r/CHANGELOG.md" <<'EOF'
# Changelog

## [0.3.0] - 2026-07-09

- REWRITTEN after the release merge
EOF
git -C "$r" add -A
git -C "$r" -c user.name=test -c user.email=t@e -c commit.gpgsign=false commit -q -m "docs: tweak changelog"
git -C "$r" push -q -u origin main 2>/dev/null
run_publish "$r" GH_CI=green GH_RELEASE_EXISTS=0
assert_eq "changelog-sha: exit 0" "$RC" "0"
assert_contains "changelog-sha: notes are the release-commit content" "$(cat "$NOTES")" "notes AS OF the release commit"
if grep -q "REWRITTEN" "$NOTES"; then
  bad "changelog-sha: notes leaked the post-merge working-tree rewrite"
else
  pass "changelog-sha: post-merge CHANGELOG rewrite does not reach the notes"
fi

# 8. Input hardening (security-posture.md): a multi-line version (F9) is rejected,
#    not validated on its first line; a hostile version_file path is refused.
r="$tmp/multiline"
new_repo "$r"
mkdir -p "$r/.claude-plugin"
printf '{\n  "name": "fixture",\n  "version": "0.1.0\\nrm -rf /"\n}\n' >"$r/.claude-plugin/plugin.json"
git -C "$r" add -A
git -C "$r" -c user.name=test -c user.email=t@e -c commit.gpgsign=false commit -q -m "chore: release"
git -C "$r" push -q -u origin main 2>/dev/null
run_publish "$r" GH_CI=green GH_RELEASE_EXISTS=0
assert_ne "hardening/multiline: a multi-line version is rejected" "$RC" "0"
assert_contains "hardening/multiline: names the SemVer failure" "$ERR" "not valid SemVer"
deny "hardening/multiline: no tag created" local_has_tag "$r" v0.1.0

r="$tmp/badpath"
new_repo "$r"
seed_version "$r" 0.1.0
mkdir -p "$r/.claude"
printf 'version_file: /etc/passwd\n' >"$r/.claude/planwright.local.yml"
run_publish "$r" GH_CI=green GH_RELEASE_EXISTS=0
assert_ne "hardening/abspath: an absolute version_file is refused" "$RC" "0"
assert_contains "hardening/abspath: names the repo-relative requirement" "$ERR" "repo-relative"

r="$tmp/traversal"
new_repo "$r"
seed_version "$r" 0.1.0
mkdir -p "$r/.claude"
printf 'version_file: ../../../etc/passwd\n' >"$r/.claude/planwright.local.yml"
run_publish "$r" GH_CI=green GH_RELEASE_EXISTS=0
assert_ne "hardening/traversal: a '..' path component is refused" "$RC" "0"
assert_contains "hardening/traversal: names the '..' component rule" "$ERR" "'..' path component"

# 9. CDPATH regression for the publish script (A2, REQ-D1.9): a hostile CDPATH
#    with a decoy `scripts/` must not corrupt the script's `cd "$(dirname "$0")"`
#    (the script calls `unset CDPATH`). Per the house pattern
#    (tests/test-check-options-reference.sh:124), invoke by a BARE relative name
#    `scripts/release-publish.sh` from the repo root — a `../`-prefixed path would
#    bypass CDPATH entirely, so the script must live under `scripts/` in the cwd.
r="$tmp/cdpath"
new_repo "$r"
printf 'scripts/\n' >>"$r/.gitignore" # the copied scripts are test scaffolding
seed_version "$r" 0.1.0
mkdir -p "$r/scripts" "$tmp/decoy-pub/scripts"
cp "$here/../scripts/release-publish.sh" "$here/../scripts/release-lib.sh" "$here/../scripts/echo-safety.sh" "$r/scripts/"
LOG="$tmp/ghlog.cd"
NOTES="$tmp/ghnotes.cd"
: >"$LOG"
: >"$NOTES"
RC=0
OUT=$(cd "$r" && env PATH="$stub:$PATH" GH_LOG="$LOG" GH_NOTES="$NOTES" \
  GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null CDPATH="$tmp/decoy-pub" \
  GH_CI=green GH_RELEASE_EXISTS=0 \
  scripts/release-publish.sh 2>/dev/null) || RC=$?
assert_eq "cdpath: publish still succeeds under a hostile CDPATH" "$RC" "0"
want "cdpath: tag created under a hostile CDPATH" local_has_tag "$r" v0.1.0

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "PASS: test-release-publish.sh"
