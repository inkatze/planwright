#!/bin/bash
# Tests for scripts/release-arm.sh — armed/watch mode for the release publish
# flow (autopilot-reflex Task 10; D-12; REQ-D1.2, REQ-D1.3).
#
# Contract under test:
#   - Pre-validation refuses to ARM (without ever entering the watch loop) on
#     any failing pre-check: PR not OPEN, dirty tree, diverged main, a
#     non-monotonic proposed version, an already-existing tag, CI not green on
#     the PR head. Each exits non-zero, names the reason, creates no tag and
#     never invokes the publish (REQ-D1.3 pre-validation half).
#   - When pre-validation passes, arm ARMS and watches the release PR; on
#     observing the merge it runs scripts/release-publish.sh and the tag lands
#     on the OBSERVED merge commit oid, never HEAD (REQ-D1.2, the Done-when).
#   - A release PR closed without merging disarms cleanly (exit 0), publishing
#     nothing.
#   - post-merge mode remains the unchanged fallback: arm DELEGATES to
#     release-publish.sh and re-implements no tag/sign logic of its own (the
#     Done-when's "post-merge mode remains the unchanged fallback").
#
# gh is stubbed (no network); the poll interval is driven to 0 and the poll cap
# kept small so the watch loop runs instantly. Runs standalone under /bin/bash
# (bash 3.2 floor).
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
ARM="$here/../scripts/release-arm.sh"
failures=0

[ -x "$ARM" ] || {
  echo "FAIL: scripts/release-arm.sh missing or not executable" >&2
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
  # signing-free git for FIXTURE setup commits.
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
# repo-level (non-signing) identity; gitignores the machine-local overlay.
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

seed_version() {
  write_plugin "$1" "$2"
  git -C "$1" add -A
  git -C "$1" commit -q -m "chore: release $2"
  git -C "$1" push -q -u origin main 2>/dev/null
}

# setup_release_pr <dir> <proposed> <prnum> — build the standard fixture: main
# seeded at 0.1.0, a release-PR head branch that bumps to <proposed>, that head
# registered as refs/pull/<prnum>/head on origin, the bump MERGED into main, then
# a FURTHER unrelated commit on main so its tip is NOT the merge commit. Exports:
#   HEAD_OID  — the PR head (what CI runs on)
#   MERGE_OID — the release-merge commit (what publish must tag; the observed oid)
#   MAIN_TIP  — main's tip, a commit AFTER the merge (so MAIN_TIP != MERGE_OID)
# The post-merge commit is what makes "tag the observed merge, never HEAD"
# load-bearing: with HEAD (MAIN_TIP) distinct from the merge commit, a
# HEAD-tagging regression would tag MAIN_TIP and be caught, and publish's
# first-parent scan still resolves the release commit to MERGE_OID.
setup_release_pr() {
  local dir="$1" proposed="$2" prnum="$3"
  new_repo "$dir"
  seed_version "$dir" 0.1.0
  gc "$dir" checkout -q -b relprep
  write_plugin "$dir" "$proposed"
  gc "$dir" add -A
  gc "$dir" commit -q -m "chore: release $proposed"
  HEAD_OID=$(git -C "$dir" rev-parse HEAD)
  gc "$dir" checkout -q main
  gc "$dir" merge -q --no-ff -m "Merge release $proposed (#$prnum)" relprep
  MERGE_OID=$(git -C "$dir" rev-parse HEAD)
  gc "$dir" commit -q --allow-empty -m "chore: unrelated follow-up"
  MAIN_TIP=$(git -C "$dir" rev-parse HEAD)
  gc "$dir" push -q origin main 2>/dev/null
  # Register the PR head as a fetchable pull ref on the bare origin (GitHub's
  # refs/pull/N/head). The head object is already in origin via the merge push.
  git -C "$dir.git" update-ref "refs/pull/$prnum/head" "$HEAD_OID"
}

# --- gh stub -----------------------------------------------------------------
# `repo view` → canned nameWithOwner; `pr view` → JSON whose state transitions
# from OPEN to a final state after ARM_OPEN_CALLS calls (a persistent counter in
# $ARM_CALLS_FILE models the merge landing mid-watch; ARM_NULL_MERGE_UNTIL keeps
# mergeCommit null on MERGED calls up to that count, modelling GitHub's oid
# replication lag); `api graphql` → statusCheckRollup keyed by the queried sha
# (ARM_HEAD_CI for the PR head, ARM_MERGE_CI for the release sha, both default
# green); `release view/create` per GH_RELEASE_EXISTS / copies --notes-file to
# $GH_NOTES (publish's needs).
#
# The OPEN→final transition is keyed on the GLOBAL `gh pr view` call count
# ($ARM_CALLS_FILE): with ARM_OPEN_CALLS=1, call 1 is pre-validation's OPEN read
# and call 2 (the loop's first poll) is the terminal state. This couples the
# fixture to arm making exactly one pre-validation `pr view`; if that changes, the
# ARM_OPEN_CALLS values here must move in step.
make_gh_stub() {
  local dir="$1"
  mkdir -p "$dir"
  cat >"$dir/gh" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >>"${GH_LOG:-/dev/null}"
case "$1" in
  repo) printf 'testowner/testrepo\n'; exit 0 ;;
  pr)
    case "$2" in
      view)
        n=0
        if [ -n "${ARM_CALLS_FILE:-}" ] && [ -f "$ARM_CALLS_FILE" ]; then n=$(cat "$ARM_CALLS_FILE"); fi
        n=$((n + 1))
        [ -n "${ARM_CALLS_FILE:-}" ] && printf '%s' "$n" >"$ARM_CALLS_FILE"
        if [ "$n" -le "${ARM_OPEN_CALLS:-1}" ]; then
          printf '{"state":"OPEN","headRefOid":"%s","mergeCommit":null}\n' "${ARM_HEAD_OID:-}"
        else
          case "${ARM_FINAL_STATE:-MERGED}" in
            MERGED)
              if [ -n "${ARM_NULL_MERGE_UNTIL:-}" ] && [ "$n" -le "$ARM_NULL_MERGE_UNTIL" ]; then
                printf '{"state":"MERGED","headRefOid":"%s","mergeCommit":null}\n' "${ARM_HEAD_OID:-}"
              else
                printf '{"state":"MERGED","headRefOid":"%s","mergeCommit":{"oid":"%s"}}\n' "${ARM_HEAD_OID:-}" "${ARM_MERGE_OID:-}"
              fi
              ;;
            *) printf '{"state":"%s","headRefOid":"%s","mergeCommit":null}\n' "${ARM_FINAL_STATE}" "${ARM_HEAD_OID:-}" ;;
          esac
        fi
        exit 0
        ;;
    esac
    exit 0
    ;;
  api)
    sha=""
    for a in "$@"; do
      case "$a" in sha=*) sha=${a#sha=} ;; esac
    done
    sel=green
    if [ -n "${ARM_HEAD_OID:-}" ] && [ "$sha" = "${ARM_HEAD_OID}" ]; then
      sel=${ARM_HEAD_CI:-green}
    else
      sel=${ARM_MERGE_CI:-green}
    fi
    case "$sel" in
      green) printf '{"data":{"repository":{"object":{"statusCheckRollup":{"state":"SUCCESS"}}}}}\n' ;;
      none) printf '{"data":{"repository":{"object":{"statusCheckRollup":null}}}}\n' ;;
      *) printf '{"data":{"repository":{"object":{"statusCheckRollup":{"state":"FAILURE"}}}}}\n' ;;
    esac
    exit 0
    ;;
  release)
    case "$2" in
      view) [ "${GH_RELEASE_EXISTS:-0}" = 1 ] && exit 0; echo "release not found" >&2; exit 1 ;;
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
esac
exit 0
STUB
  chmod +x "$dir/gh"
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
stub="$tmp/bin"
make_gh_stub "$stub"

# run_arm <dir> <prnum> [VAR=val ...] — run arm in <dir> with the gh stub on
# PATH, a fresh call-counter/log/notes; sets RC/OUT/ERR/LOG. Poll interval 0 and
# a small cap keep the watch loop instant.
run_arm() {
  local dir="$1" prnum="$2"
  shift 2
  LOG="$tmp/ghlog.$$"
  NOTES="$tmp/ghnotes.$$"
  CALLS="$tmp/calls.$$"
  : >"$LOG"
  : >"$NOTES"
  : >"$CALLS"
  RC=0
  OUT=$(cd "$dir" && env PATH="$stub:$PATH" GH_LOG="$LOG" GH_NOTES="$NOTES" \
    ARM_CALLS_FILE="$CALLS" RELEASE_ARM_POLL_SECONDS=0 RELEASE_ARM_MAX_POLLS=5 \
    GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null "$@" \
    "$ARM" "$prnum" 2>"$tmp/err.$$") || RC=$?
  ERR=$(cat "$tmp/err.$$")
}

origin_has_tag() { [ -n "$(git -C "$1.git" tag -l "$2")" ]; }
local_has_tag() { [ -n "$(git -C "$1" tag -l "$2")" ]; }
gh_called() { grep -q "$2" "$1" 2>/dev/null; }

# ===========================================================================
# 1. post-merge mode remains the unchanged fallback: arm DELEGATES to
#    release-publish.sh and re-implements no tag/sign logic (Done-when). These
#    are static structural guards; the happy path (§2) proves the delegation
#    BEHAVIORALLY (publish's `release create` fires). The structural check
#    targets the actual invocation `"$PUBLISH"`, not any textual mention (which
#    the header comments also contain), so deleting the call is caught.
# shellcheck disable=SC2016 # the literal string "$PUBLISH" is the grep target, not an expansion
if grep -Eq '(^|[^A-Za-z_])"\$PUBLISH"' "$ARM"; then
  pass "delegation: arm actually invokes \"\$PUBLISH\" (not just a comment mention)"
else
  bad "delegation: arm has no \"\$PUBLISH\" invocation"
fi
# Arm must run NO `git tag` in any tag-creating form — annotated, signed, or
# lightweight. It only ever READS tags (git ls-remote --tags, git rev-parse
# refs/tags/...), which never spell `git tag`. Any `git tag <...>` would be arm
# re-implementing the tag authority publish owns.
if grep -Eq 'git[[:space:]]+tag[[:space:]]' "$ARM"; then
  bad "delegation: arm runs 'git tag' itself instead of delegating to publish"
else
  pass "delegation: arm runs no 'git tag' in any form (publish is the single authority)"
fi

# ===========================================================================
# 2. Happy path: pre-validation passes, arm watches, observes the merge, and
#    the tag lands on the OBSERVED merge oid — not HEAD (REQ-D1.2, Done-when).
# ===========================================================================
r="$tmp/happy"
setup_release_pr "$r" 0.2.0 42
# The observed merge oid is the release-merge COMMIT (MERGE_OID), which is NOT
# main's tip (MAIN_TIP, the post-merge follow-up) — so "tag the observed merge,
# never HEAD" is genuinely tested: a HEAD-tagging bug would tag MAIN_TIP.
run_arm "$r" 42 ARM_HEAD_OID="$HEAD_OID" ARM_MERGE_OID="$MERGE_OID" \
  ARM_OPEN_CALLS=1 ARM_FINAL_STATE=MERGED GH_RELEASE_EXISTS=0
assert_eq "happy: exit 0" "$RC" "0"
assert_contains "happy: reports it armed" "$OUT" "armed"
assert_contains "happy: reports it published" "$OUT" "published"
want "happy: tag v0.2.0 created" local_has_tag "$r" v0.2.0
want "happy: tag pushed to origin" origin_has_tag "$r" v0.2.0
TAGGED=$(git -C "$r" rev-parse "v0.2.0^{commit}" 2>/dev/null || echo none)
assert_eq "happy: tag lands on the OBSERVED merge oid" "$TAGGED" "$MERGE_OID"
assert_ne "happy: the tagged commit is NOT main's tip (never HEAD is load-bearing)" "$TAGGED" "$MAIN_TIP"
want "happy: publish created the GitHub Release" gh_called "$LOG" "release create"
want "happy: publish used --verify-tag" gh_called "$LOG" "verify-tag"
# CI was checked on the PR head during pre-validation (REQ-D1.3 pre-check).
want "happy: CI pre-validated on the PR head oid" gh_called "$LOG" "sha=$HEAD_OID"
# Arm never merges the PR — the merge is the human's reserved act (D-5).
deny "happy: arm never invoked 'gh pr merge'" gh_called "$LOG" "pr merge"

# ===========================================================================
# 3. Pre-validation refusals — each refuses to ARM, names the reason, creates
#    no tag, and never publishes (REQ-D1.3).
# ===========================================================================
# 3a. PR not OPEN at arm time (already merged/closed before arming).
r="$tmp/pv-notopen"
setup_release_pr "$r" 0.2.0 7
run_arm "$r" 7 ARM_HEAD_OID="$HEAD_OID" ARM_MERGE_OID="$MERGE_OID" \
  ARM_OPEN_CALLS=0 ARM_FINAL_STATE=MERGED GH_RELEASE_EXISTS=0
assert_ne "pv/not-open: exits non-zero" "$RC" "0"
assert_contains "pv/not-open: names the not-OPEN reason" "$ERR" "not OPEN"
deny "pv/not-open: no tag created" local_has_tag "$r" v0.2.0
deny "pv/not-open: never published" gh_called "$LOG" "release create"

# 3b. CI not green on the PR head.
r="$tmp/pv-ci"
setup_release_pr "$r" 0.2.0 8
run_arm "$r" 8 ARM_HEAD_OID="$HEAD_OID" ARM_MERGE_OID="$MERGE_OID" \
  ARM_OPEN_CALLS=1 ARM_HEAD_CI=red GH_RELEASE_EXISTS=0
assert_ne "pv/ci: exits non-zero" "$RC" "0"
assert_contains "pv/ci: names the ci gate specifically" "$ERR" "ci gate"
deny "pv/ci: no tag created" local_has_tag "$r" v0.2.0
deny "pv/ci: never published" gh_called "$LOG" "release create"

# 3c. A tag for the proposed version already exists on origin (idempotency).
r="$tmp/pv-tag"
setup_release_pr "$r" 0.2.0 9
gc "$r" tag v0.2.0
gc "$r" push -q origin v0.2.0 2>/dev/null
gc "$r" tag -d v0.2.0 >/dev/null
run_arm "$r" 9 ARM_HEAD_OID="$HEAD_OID" ARM_MERGE_OID="$MERGE_OID" \
  ARM_OPEN_CALLS=1 GH_RELEASE_EXISTS=0
assert_ne "pv/existing-tag: exits non-zero" "$RC" "0"
assert_contains "pv/existing-tag: names the origin idempotency refusal" "$ERR" "already exists on origin"
deny "pv/existing-tag: never published" gh_called "$LOG" "release create"

# 3c-2. Idempotency uses an EXACT ref match, not a substring: a prefix-colliding
#       prerelease tag (v0.2.0-rc.1 contains the substring 'refs/tags/v0.2.0')
#       must NOT block arming the real 0.2.0 release. Regression for the
#       substring-match false-positive.
r="$tmp/pv-prefixtag"
setup_release_pr "$r" 0.2.0 90
gc "$r" tag v0.2.0-rc.1 "$HEAD_OID"
gc "$r" push -q origin v0.2.0-rc.1 2>/dev/null
gc "$r" tag -d v0.2.0-rc.1 >/dev/null
run_arm "$r" 90 ARM_HEAD_OID="$HEAD_OID" ARM_MERGE_OID="$MERGE_OID" \
  ARM_OPEN_CALLS=1 GH_RELEASE_EXISTS=0
assert_eq "pv/prefix-tag: a prefix-colliding prerelease does NOT block (exit 0)" "$RC" "0"
want "pv/prefix-tag: the real v0.2.0 tag is published" local_has_tag "$r" v0.2.0

# 3d. Non-monotonic proposed version (a higher release tag already on origin).
r="$tmp/pv-mono"
setup_release_pr "$r" 0.2.0 10
gc "$r" tag v0.9.0
gc "$r" push -q origin v0.9.0 2>/dev/null
run_arm "$r" 10 ARM_HEAD_OID="$HEAD_OID" ARM_MERGE_OID="$MERGE_OID" \
  ARM_OPEN_CALLS=1 GH_RELEASE_EXISTS=0
assert_ne "pv/monotonic: exits non-zero" "$RC" "0"
assert_contains "pv/monotonic: names the monotonicity gate" "$ERR" "monotonic"
deny "pv/monotonic: no v0.2.0 tag pushed" origin_has_tag "$r" v0.2.0
deny "pv/monotonic: never published" gh_called "$LOG" "release create"

# 3e. Dirty working tree.
r="$tmp/pv-dirty"
setup_release_pr "$r" 0.2.0 11
echo "dirt" >>"$r/.claude-plugin/plugin.json"
run_arm "$r" 11 ARM_HEAD_OID="$HEAD_OID" ARM_MERGE_OID="$MERGE_OID" \
  ARM_OPEN_CALLS=1 GH_RELEASE_EXISTS=0
assert_ne "pv/dirty: exits non-zero" "$RC" "0"
assert_contains "pv/dirty: names the clean-tree gate" "$ERR" "clean-tree"
deny "pv/dirty: never published" gh_called "$LOG" "release create"

# ===========================================================================
# 4. Release PR closed without merging → disarm cleanly (exit 0), publish
#    nothing.
# ===========================================================================
r="$tmp/closed"
setup_release_pr "$r" 0.2.0 12
run_arm "$r" 12 ARM_HEAD_OID="$HEAD_OID" ARM_MERGE_OID="$MERGE_OID" \
  ARM_OPEN_CALLS=1 ARM_FINAL_STATE=CLOSED GH_RELEASE_EXISTS=0
assert_eq "closed: exit 0 (disarmed cleanly)" "$RC" "0"
assert_contains "closed: reports the PR closed without merging" "$OUT" "closed"
deny "closed: no tag created" local_has_tag "$r" v0.2.0
deny "closed: nothing published" gh_called "$LOG" "release create"

# ===========================================================================
# 4b. More pre-validation refusals (each refuses to arm, no tag, no publish).
# ===========================================================================
# not on main.
r="$tmp/pv-notmain"
setup_release_pr "$r" 0.2.0 13
gc "$r" checkout -q -b sidebranch
run_arm "$r" 13 ARM_HEAD_OID="$HEAD_OID" ARM_MERGE_OID="$MERGE_OID" \
  ARM_OPEN_CALLS=1 GH_RELEASE_EXISTS=0
assert_ne "pv/not-main: exits non-zero" "$RC" "0"
assert_contains "pv/not-main: names the on-main requirement" "$ERR" "not on main"
deny "pv/not-main: never published" gh_called "$LOG" "release create"

# local main diverged from origin/main (sync gate).
r="$tmp/pv-unsynced"
setup_release_pr "$r" 0.2.0 14
gc "$r" commit -q --allow-empty -m "local-only commit"
run_arm "$r" 14 ARM_HEAD_OID="$HEAD_OID" ARM_MERGE_OID="$MERGE_OID" \
  ARM_OPEN_CALLS=1 GH_RELEASE_EXISTS=0
assert_ne "pv/unsynced: exits non-zero" "$RC" "0"
assert_contains "pv/unsynced: names the sync gate" "$ERR" "sync gate"
deny "pv/unsynced: never published" gh_called "$LOG" "release create"

# positive monotonicity: a LOWER release tag exists on origin; arm proceeds and
# publishes (the rl_version_gt success branch, distinct from first-release).
r="$tmp/pv-mono-ok"
setup_release_pr "$r" 0.2.0 15
gc "$r" tag v0.1.0
gc "$r" push -q origin v0.1.0 2>/dev/null
run_arm "$r" 15 ARM_HEAD_OID="$HEAD_OID" ARM_MERGE_OID="$MERGE_OID" \
  ARM_OPEN_CALLS=1 GH_RELEASE_EXISTS=0
assert_eq "pv/mono-ok: proposed > latest release proceeds (exit 0)" "$RC" "0"
want "pv/mono-ok: v0.2.0 published over v0.1.0" local_has_tag "$r" v0.2.0

# ===========================================================================
# 4c. Watch-loop failure paths (timeout, transient oid lag) + fire-stage guards.
# ===========================================================================
# Watch times out: the PR stays OPEN past the poll cap → disarm non-zero,
# publish nothing. ARM_OPEN_CALLS high keeps every poll OPEN; a small cap fires.
r="$tmp/watch-timeout"
setup_release_pr "$r" 0.2.0 16
run_arm "$r" 16 ARM_HEAD_OID="$HEAD_OID" ARM_MERGE_OID="$MERGE_OID" \
  ARM_OPEN_CALLS=99 RELEASE_ARM_MAX_POLLS=3 GH_RELEASE_EXISTS=0
assert_ne "watch/timeout: exits non-zero" "$RC" "0"
assert_contains "watch/timeout: names the poll exhaustion" "$ERR" "after 3 polls"
deny "watch/timeout: never published" gh_called "$LOG" "release create"

# MERGED observed but mergeCommit.oid not yet populated (replication lag): arm
# re-polls within budget rather than hard-failing, then fires once the oid lands.
r="$tmp/merged-null"
setup_release_pr "$r" 0.2.0 17
# call 1 = pre-validation OPEN; call 2 = MERGED+null; call 3 = MERGED+oid.
run_arm "$r" 17 ARM_HEAD_OID="$HEAD_OID" ARM_MERGE_OID="$MERGE_OID" \
  ARM_OPEN_CALLS=1 ARM_NULL_MERGE_UNTIL=2 GH_RELEASE_EXISTS=0
assert_eq "merged-null: re-polls past the oid lag and publishes (exit 0)" "$RC" "0"
TAGGED=$(git -C "$r" rev-parse "v0.2.0^{commit}" 2>/dev/null || echo none)
assert_eq "merged-null: tag still lands on the observed merge oid" "$TAGGED" "$MERGE_OID"

# Cross-check tolerates rebase-and-merge: the observed oid is the rebased TIP
# (MAIN_TIP) while publish tags the version-change commit (MERGE_OID), an
# ANCESTOR of the tip. The ancestor-based cross-check must accept this, not raise
# a false "D-6 mismatch".
r="$tmp/rebase-xcheck"
setup_release_pr "$r" 0.2.0 18
run_arm "$r" 18 ARM_HEAD_OID="$HEAD_OID" ARM_MERGE_OID="$MAIN_TIP" \
  ARM_OPEN_CALLS=1 GH_RELEASE_EXISTS=0
assert_eq "rebase-xcheck: tagged-ancestor-of-observed-tip passes (exit 0)" "$RC" "0"
TAGGED=$(git -C "$r" rev-parse "v0.2.0^{commit}" 2>/dev/null || echo none)
assert_eq "rebase-xcheck: publish tagged the version commit, not the tip" "$TAGGED" "$MERGE_OID"
assert_ne "rebase-xcheck: tagged differs from the observed tip (the case under test)" "$TAGGED" "$MAIN_TIP"

# Observed merge oid is not on origin/main after fetch → refuse to publish a
# state origin does not confirm (fire-stage guard). A syntactically-valid but
# unreachable oid (40 zeros) trips it.
r="$tmp/merge-not-on-origin"
setup_release_pr "$r" 0.2.0 19
run_arm "$r" 19 ARM_HEAD_OID="$HEAD_OID" \
  ARM_MERGE_OID="0000000000000000000000000000000000000000" \
  ARM_OPEN_CALLS=1 GH_RELEASE_EXISTS=0
assert_ne "fire/not-on-origin: exits non-zero" "$RC" "0"
assert_contains "fire/not-on-origin: names the origin-confirmation refusal" "$ERR" "not on origin/main"
deny "fire/not-on-origin: never published" gh_called "$LOG" "release create"

# ===========================================================================
# 5. Argument validation (REQ-D1.9 conventions): usage error is exit 2.
# ===========================================================================
run_arm_raw() {
  RC=0
  OUT=$(cd "$1" && env PATH="$stub:$PATH" "$ARM" "${@:2}" 2>"$tmp/err.$$") || RC=$?
  ERR=$(cat "$tmp/err.$$")
}
r="$tmp/args"
new_repo "$r"
seed_version "$r" 0.1.0
run_arm_raw "$r" # no PR number
assert_eq "args/none: exit 2 usage" "$RC" "2"
run_arm_raw "$r" abc
assert_eq "args/nonnumeric: exit 2 usage" "$RC" "2"
run_arm_raw "$r" 0
assert_eq "args/zero: exit 2 usage" "$RC" "2"
run_arm_raw "$r" 01
assert_eq "args/leading-zero: exit 2 usage" "$RC" "2"

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "PASS: test-release-arm.sh"
