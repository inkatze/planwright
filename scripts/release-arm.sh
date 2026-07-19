#!/usr/bin/env bash
# release-arm.sh — armed/watch mode for the release publish flow (autopilot-
# reflex Task 10; D-12; REQ-D1.2, REQ-D1.3). The ergonomic optimization over the
# post-merge path: run BEFORE the merge, pre-validate everything pre-validatable,
# watch the release PR, and the moment the merge is observed run the publish —
# shrinking the untagged-window lock from merge-to-human-remembers down to
# merge-to-sign (D-12). It NEVER merges (the human's merge is the approval, D-5)
# and it does not itself tag or sign: on the observed merge it delegates to the
# unchanged scripts/release-publish.sh, which stays the single tag authority and
# the standalone post-merge fallback.
#
# Why arm cannot weaken safety (D-12, REQ-E1.4): every gate this script runs
# pre-merge is a re-check for an EARLY refusal, not a bypass. release-publish.sh
# re-enforces every gate authoritatively at fire time against the real merged
# state — the observed-merge SHA it recomputes itself from main's first-parent
# history (D-6, REQ-D1.2), the monotonicity/idempotency/CI gates against origin.
# Arm's pre-validation only earns the right to WATCH; publish earns the right to
# TAG. So a race between arm-time and merge-time (a tag that appears, CI that
# goes red, a version that changes) is caught by publish, never slipped through.
#
# What it does, in order:
#   1. Pre-validate (refuse to arm WITHOUT watching on any failure): the local
#      checkout is on main, clean, and synced with origin/main; the target PR is
#      OPEN; the version the PR head proposes is valid SemVer, strictly greater
#      than the latest release tag (monotonicity), and has no existing tag
#      locally or on origin (idempotency); the release-gating GitHub CI is green
#      on the PR head, EXCLUDING the untagged-window lock (which gates merges,
#      not the publish — see rl_ci_state in release-lib.sh).
#   2. Arm + watch: poll the PR until it is MERGED (fire) or CLOSED (disarm
#      cleanly, publishing nothing), up to a bounded poll cap.
#   3. On the observed merge: confirm the merge is on origin/main, re-confirm HEAD
#      is still main, and fast-forward local main to origin/main (new commits
#      only, never a rewrite). Then WAIT for the release-gating CI to go green on
#      the merged commit (again excluding the window lock, which is red by design
#      there; firing before CI settles would only make publish refuse), and run
#      scripts/release-publish.sh. Finally verify the tag publish created — its
#      name RE-DERIVED from the merged commit's version, never the arm-time
#      proposal — lands within the OBSERVED merge commit (the Done-when).
#
# Security posture (doctrine/security-posture.md, framework-script rules): the PR
# number is validated as a positive integer before any interpolation; version
# strings pass the SemVer grammar (release-lib.sh) before use in a tag name;
# commit oids from gh are validated as hex before use as git refs; untrusted
# values on an error path are stripped of terminal-control bytes
# (sanitize_printable). No signing material is handled here — signing rides
# release-publish.sh's delegation to git config (D-4).
#
# Usage: release-arm.sh <pr-number>
#   Run inside the repo, on a checkout of `main` synced with `origin/main`,
#   BEFORE the release PR merges. Exit 0 on a completed publish OR a clean
#   disarm (PR closed without merging); 1 on a pre-validation refusal, a watch
#   timeout, or a publish/operational failure (the message names the cause); 2
#   on a usage error.
#
# Knobs (environment; sane defaults, overridable). Both the merge watch (step 2)
# and the fire-time CI-settle wait (step 3) share the same interval and cap:
#   RELEASE_ARM_POLL_SECONDS   seconds between polls (default 15)
#   RELEASE_ARM_MAX_POLLS      max polls before disarming on timeout (default
#                              240 — ~1h at the default interval)

set -u
LC_ALL=C
export LC_ALL
unset CDPATH

script_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=scripts/echo-safety.sh
. "$script_dir/echo-safety.sh"
# shellcheck source=scripts/release-lib.sh
. "$script_dir/release-lib.sh"

PUBLISH="$script_dir/release-publish.sh"
MAIN_REF="main"
ORIGIN_MAIN_REF="origin/main"

# The untagged-window lock check is red BY DESIGN while the untagged window is
# open (it gates merges, not the publish), so arm's release-gating verdict must
# not count it. That carve-out — now workflow-scoped (a CheckRun named
# `window-lock` whose owning workflow is `release-window`; REQ-C1.3) — lives in the
# shared rl_ci_state primitive (release-lib.sh), which release-publish.sh calls
# too, so arm never says green on a state publish would refuse: identical predicate
# = identical verdict, by construction (D-4, REQ-C1.2). The prior inline
# `rl_ci_verdict`/WINDOW_LOCK_NAME evaluator is retired in favor of it.

poll_seconds=${RELEASE_ARM_POLL_SECONDS:-15}
max_polls=${RELEASE_ARM_MAX_POLLS:-240}

die() {
  # die <reason> — refuse, naming the cause, without side effects. Untrusted
  # values interpolated into $1 are passed through sanitize_printable first.
  echo "release-arm: $1" >&2
  exit 1
}

usage() {
  echo "release-arm: usage: release-arm.sh <pr-number>" >&2
  exit 2
}

# --- Argument + environment validation --------------------------------------

[ "$#" -eq 1 ] || usage
pr="$1"
# A positive integer, no leading zero (a decimal PR number). Validate BEFORE the
# value ever reaches gh or a message.
case "$pr" in
  '' | *[!0-9]*) usage ;;
  0*) usage ;;
esac

case "$poll_seconds" in
  '' | *[!0-9]*) die "RELEASE_ARM_POLL_SECONDS must be a non-negative integer: '$(sanitize_printable "$poll_seconds")'" ;;
esac
case "$max_polls" in
  # Reject a leading zero as well as a bare 0: `-ge` reads "00"/"000" as 0, which
  # would silently make the poll budget zero and fire an immediate timeout.
  '' | *[!0-9]* | 0*) die "RELEASE_ARM_MAX_POLLS must be a positive integer with no leading zero: '$(sanitize_printable "$max_polls")'" ;;
esac

command -v git >/dev/null 2>&1 || die "git is required"
command -v gh >/dev/null 2>&1 || die "gh is required (release-PR watch + CI check)"
command -v jq >/dev/null 2>&1 || die "jq is required (gh JSON + CI parsing)"

git rev-parse --git-dir >/dev/null 2>&1 || die "not a git repository"

# --- Resolve the version of truth location (path + selector) ----------------

IFS=$(printf '\t')
read -r vf_path vf_sel < <(rl_resolve_version_file "$script_dir")
unset IFS

# Path guards mirror release-pending.sh / release-publish.sh: the version_file
# path is parsed config data — repo-relative only, never absolute or a `..`
# traversal (a component test, so `v..x` is not falsely rejected).
case "$vf_path" in
  /* | "") die "version_file must be a non-empty repo-relative path: '$(sanitize_printable "$vf_path")'" ;;
esac
case "/$vf_path/" in
  */../*) die "version_file must not use a '..' path component: '$(sanitize_printable "$vf_path")'" ;;
esac

# Release-gating CI verdict: the shared rl_ci_state primitive (release-lib.sh),
# which release-publish.sh's ci gate calls too, so arm and publish agree on the
# release-gating verdict by construction (D-4, REQ-C1.1, REQ-C1.2). It excludes
# the untagged-window lock workflow-scoped (REQ-C1.3), returns one canonical
# verdict (green|failing|pending|none|too-many) on stdout and rc 0, and a distinct
# status (2, empty stdout) on a gh/query failure — so arm fails closed and
# distinguishes an infra outage from a failing verdict (arm retries a query
# failure within its poll budget; publish fails closed one-shot — the downstream
# handling deliberately differs, the verdict does not).

# A 40- or 64-hex commit oid (SHA-1 / SHA-256), validated before use as a git ref.
is_hex_oid() {
  case "$1" in
    '' | *[!0-9a-fA-F]*) return 1 ;;
  esac
  case "${#1}" in 40 | 64) return 0 ;; *) return 1 ;; esac
}

# --- Pre-validation (step 1) ------------------------------------------------

# On main.
cur_branch=$(git symbolic-ref --quiet --short HEAD 2>/dev/null) || cur_branch=""
[ "$cur_branch" = "$MAIN_REF" ] \
  || die "pre-validation: not on $MAIN_REF (on '$(sanitize_printable "${cur_branch:-detached HEAD}")'); arm from a $MAIN_REF checkout"

# Clean working tree.
[ -z "$(git status --porcelain 2>/dev/null)" ] \
  || die "pre-validation: clean-tree gate — the working tree has uncommitted changes"

# Local main synced with origin/main.
git rev-parse -q --verify "$ORIGIN_MAIN_REF" >/dev/null 2>&1 \
  || die "pre-validation: no $ORIGIN_MAIN_REF tracking ref (fetch origin first)"
if [ "$(git rev-parse "$MAIN_REF")" != "$(git rev-parse "$ORIGIN_MAIN_REF")" ]; then
  die "pre-validation: sync gate — local $MAIN_REF is not synced with $ORIGIN_MAIN_REF"
fi

# The PR must be OPEN; capture its head oid.
if ! pr_json=$(gh pr view "$pr" --json state,headRefOid,mergeCommit 2>/dev/null); then
  die "pre-validation: could not read release PR #$pr (gh pr view failed); check the number and gh auth"
fi
pr_state=$(printf '%s' "$pr_json" | jq -r '.state // ""' 2>/dev/null) || die "pre-validation: could not parse gh pr view output for #$pr"
[ "$pr_state" = "OPEN" ] \
  || die "pre-validation: release PR #$pr is not OPEN (state: $(sanitize_printable "${pr_state:-unknown}")); arm only an open release PR (a merged/closed PR has nothing to watch)"
head_oid=$(printf '%s' "$pr_json" | jq -r '.headRefOid // ""' 2>/dev/null) \
  || die "pre-validation: could not parse the head oid from gh pr view output for #$pr"
is_hex_oid "$head_oid" \
  || die "pre-validation: gh returned no valid head commit oid for #$pr: '$(sanitize_printable "$head_oid")'"

# Fetch the PR head so its proposed version is readable from a git ref. A
# read-only fetch of GitHub's refs/pull/<n>/head; no branch switch, no merge.
if ! git fetch --force origin "refs/pull/$pr/head" >/dev/null 2>&1; then
  die "pre-validation: could not fetch the head of PR #$pr (refs/pull/$pr/head)"
fi
fetched=$(git rev-parse FETCH_HEAD 2>/dev/null) || die "pre-validation: could not resolve the fetched PR head"
[ "$fetched" = "$head_oid" ] \
  || die "pre-validation: the fetched PR head ($(sanitize_printable "$fetched")) does not match gh's head oid ($(sanitize_printable "$head_oid")); the PR may have moved — re-arm"

# The proposed version, read from the PR head's tree (never the working tree).
proposed=$(rl_version_at FETCH_HEAD "$vf_path" "$vf_sel") \
  || die "pre-validation: could not read the version_file ($(sanitize_printable "$vf_path")) at the PR head"
[ -n "$proposed" ] \
  || die "pre-validation: no version found in $(sanitize_printable "$vf_path") at the PR head"
rl_valid_semver "$proposed" \
  || die "pre-validation: the version proposed by PR #$pr is not valid SemVer: '$(sanitize_printable "$proposed")'"
tag="v$proposed"

# Monotonicity + idempotency read ORIGIN (read-only), not the local tag cache,
# so a stale/un-fetched clone cannot pass a gate origin would fail.
if ! origin_tags=$(git ls-remote --tags origin 2>/dev/null); then
  die "pre-validation: could not query origin tags (git ls-remote failed); resolve connectivity and re-run"
fi

# Idempotency (local): no tag for the proposed version in the local cache.
git rev-parse -q --verify "refs/tags/$tag" >/dev/null 2>&1 \
  && die "pre-validation: tag $tag already exists locally (idempotency); nothing to arm"

# One pass over origin's tags computes BOTH the origin-idempotency check and the
# latest release version. The idempotency test compares the WHOLE ref name for
# EQUALITY (`$t = $tag`), not a substring of the full ls-remote blob: a substring
# test would false-positive against any prefix-colliding tag — e.g. a prerelease
# `v1.2.0-rc.1` contains the substring `refs/tags/v1.2.0` and would spuriously
# block arming the real `1.2.0`.
tag_on_origin=0
latest_ver=""
while IFS= read -r ref; do
  t=${ref##*refs/tags/}
  case "$t" in "" | *"^{}") continue ;; esac
  [ "$t" = "$tag" ] && tag_on_origin=1
  ver=${t#v}
  rl_valid_semver "$ver" || continue
  if [ -z "$latest_ver" ] || rl_version_gt "$ver" "$latest_ver"; then
    latest_ver="$ver"
  fi
done < <(printf '%s\n' "$origin_tags")
[ "$tag_on_origin" -eq 0 ] \
  || die "pre-validation: tag $tag already exists on origin (idempotency); the release is already published or in flight"

# Monotonicity: proposed strictly greater than the latest release tag on origin
# (vacuous when there are no release tags yet — the first release).
if [ -n "$latest_ver" ]; then
  rl_version_gt "$proposed" "$latest_ver" \
    || die "pre-validation: monotonicity gate — proposed $proposed is not strictly greater than the latest release v$latest_ver (on origin)"
fi

# GitHub CI green on the PR head — the real external state via gh, EXCLUDING the
# untagged-window lock (it gates merges, not the publish, so it must not block
# arming; without the exclusion a release pending elsewhere would falsely fail
# this gate). Pre-validation requires a settled GREEN: a still-running head is a
# refusal to arm now, not a wait.
head_ci=""
head_ci=$(rl_ci_state "$head_oid") \
  || die "pre-validation: could not verify GitHub CI on the PR head $head_oid (gh query failed); resolve connectivity/auth and re-run"
case "$head_ci" in
  green) : ;;
  failing) die "pre-validation: ci gate — a release-gating check is failing on the PR head $head_oid (window lock excluded)" ;;
  pending) die "pre-validation: ci gate — release-gating CI is still running on the PR head $head_oid; wait for it to settle green before arming" ;;
  too-many) die "pre-validation: ci gate — the PR head $head_oid has more than one page of checks (>100); CI completeness cannot be verified from a single read — publish manually with $PUBLISH after confirming CI" ;;
  *) die "pre-validation: ci gate — no release-gating CI on the PR head $head_oid (a release gate requires positive CI confirmation)" ;;
esac

echo "release-arm: armed for release PR #$pr (proposed $tag) — pre-validation passed; watching for the merge"

# --- Watch loop (step 2) ----------------------------------------------------

merge_oid=""
i=0
while :; do
  i=$((i + 1))
  if ! watch_json=$(gh pr view "$pr" --json state,mergeCommit 2>/dev/null); then
    # A transient watch read is not fatal on its own; fail only if we exhaust the
    # poll budget without ever confirming a terminal state.
    if [ "$i" -ge "$max_polls" ]; then
      die "watch: could not read PR #$pr after $max_polls polls (last gh pr view failed); disarming — publish manually after the merge with $PUBLISH"
    fi
    sleep "$poll_seconds"
    continue
  fi
  # A gh success with unparseable JSON is a transient read, not an OPEN verdict:
  # treat it like the fetch-failure branch (retry within budget), so the
  # exhaustion message names the real cause rather than "still not merged".
  if ! watch_state=$(printf '%s' "$watch_json" | jq -r '.state // ""' 2>/dev/null); then
    if [ "$i" -ge "$max_polls" ]; then
      die "watch: could not parse PR #$pr state after $max_polls polls (malformed gh output); disarming — publish manually after the merge with $PUBLISH"
    fi
    sleep "$poll_seconds"
    continue
  fi
  case "$watch_state" in
    MERGED)
      merge_oid=$(printf '%s' "$watch_json" | jq -r '.mergeCommit.oid // ""' 2>/dev/null)
      # GitHub can report state=MERGED a replication tick BEFORE mergeCommit.oid
      # is populated (most visible on squash/rebase merges — exactly when arm
      # polls). An unpopulated oid here is transient, not fatal: re-poll within
      # the remaining budget rather than refuse a merge that just landed. The
      # loop only breaks once a valid hex oid is in hand, so the post-loop use of
      # merge_oid is guaranteed valid.
      if is_hex_oid "$merge_oid"; then
        break
      fi
      if [ "$i" -ge "$max_polls" ]; then
        die "watch: PR #$pr is MERGED but gh never returned a merge commit oid after $max_polls polls; disarming — publish manually with $PUBLISH"
      fi
      sleep "$poll_seconds"
      ;;
    CLOSED)
      echo "release-arm: release PR #$pr was closed without merging; nothing to publish (disarmed)"
      exit 0
      ;;
    *)
      if [ "$i" -ge "$max_polls" ]; then
        die "watch: PR #$pr still not merged after $max_polls polls; disarming — publish manually after the merge with $PUBLISH"
      fi
      sleep "$poll_seconds"
      ;;
  esac
done

echo "release-arm: observed the merge of PR #$pr at $merge_oid — syncing $MAIN_REF and publishing"

# --- Fire: sync main, wait for green CI, then delegate to publish (step 3) ---

# New commits only — fetch and fast-forward; never rewrite (REQ-J1.4 discipline).
git fetch origin >/dev/null 2>&1 \
  || die "could not fetch origin after the observed merge; main is unchanged — publish manually with $PUBLISH once synced"
git merge-base --is-ancestor "$merge_oid" "$ORIGIN_MAIN_REF" 2>/dev/null \
  || die "the observed merge $merge_oid is not on $ORIGIN_MAIN_REF after fetch; refusing to publish a state origin does not confirm"

# Re-confirm HEAD is still $MAIN_REF before fast-forwarding. The on-main check at
# arm time can go stale across a long watch (a branch switch in this worktree),
# and `git merge --ff-only` moves whatever branch is checked out — fast-forwarding
# the wrong branch would silently corrupt it.
cur_branch_now=$(git symbolic-ref --quiet --short HEAD 2>/dev/null) || cur_branch_now=""
[ "$cur_branch_now" = "$MAIN_REF" ] \
  || die "fire: no longer on $MAIN_REF (on '$(sanitize_printable "${cur_branch_now:-detached HEAD}")') at fire time; refusing to fast-forward a non-$MAIN_REF branch — publish manually with $PUBLISH from a $MAIN_REF checkout"

if ! git merge --ff-only "$ORIGIN_MAIN_REF" >/dev/null 2>&1; then
  die "could not fast-forward $MAIN_REF to $ORIGIN_MAIN_REF (a non-ff divergence); resolve manually, then publish with $PUBLISH"
fi

# Wait for the release-gating CI to go green on the merged commit before firing
# publish — EXCLUDING the untagged-window lock, which is red here BY DESIGN (the
# merge just opened the untagged window; see rl_ci_state in release-lib.sh) and gates
# merges, not the publish. Without this wait arm would fire the instant the merge
# is observed, when the merge commit's CI has not even started, and publish's own
# CI gate would refuse. Fail closed: a red release-gating check refuses outright;
# an absent or persistently-pending verdict times out and refuses (arm never fires
# on unconfirmed CI). A transient query error retries within the poll budget.
echo "release-arm: waiting for release-gating CI to go green on $merge_oid (window lock excluded)"
j=0
while :; do
  j=$((j + 1))
  merge_ci=""
  vrc=0
  merge_ci=$(rl_ci_state "$merge_oid") || vrc=$?
  [ "$vrc" -eq 2 ] && merge_ci="query-error" # transient — retry within budget
  case "$merge_ci" in
    green) break ;;
    failing)
      die "fire: ci gate — a release-gating check is failing on the merged commit $merge_oid (window lock excluded); refusing to publish — investigate CI, then publish manually with $PUBLISH once green"
      ;;
    too-many)
      # Will not self-heal by waiting: refuse now, like a failing check (and like
      # publish's own fail-closed on >100 checks). Waiting the whole budget would
      # only delay the same refusal.
      die "fire: ci gate — the merged commit $merge_oid has more than one page of checks (>100); CI completeness cannot be verified from a single read — refusing to publish, run $PUBLISH manually after confirming CI"
      ;;
    *) # pending | none | query-error — keep waiting within the poll budget
      if [ "$j" -ge "$max_polls" ]; then
        die "fire: release-gating CI did not go green on $merge_oid within $max_polls polls (last: $(sanitize_printable "$merge_ci")); disarming — publish manually with $PUBLISH once CI is green"
      fi
      sleep "$poll_seconds"
      ;;
  esac
done

# Delegate to the unchanged post-merge publish — the single tag authority. It
# recomputes the release-merge SHA itself (D-6) and re-enforces every gate.
if ! "$PUBLISH"; then
  die "publish failed after the observed merge; $MAIN_REF is synced — resolve and re-run $PUBLISH"
fi

# Verify the tag publish created lands within the OBSERVED merge (Done-when,
# REQ-D1.2). Re-derive the tag from the MERGED state (the version at the observed
# merge commit), NEVER the arm-time proposed version: if the PR's version changed
# between arming and merge, publish (correctly) tags the merged version, and a
# check against the stale arm-time tag would raise a false "tag absent" on a
# release that actually succeeded. Publish's own D-6 scan is the authority; this
# is the belt-and-suspenders cross-check that arm watched the change that got
# tagged.
#
# The predicate is "tagged is an ancestor of, or equal to, the observed merge
# oid", NOT strict equality. For squash and merge-commit strategies publish tags
# exactly `mergeCommit.oid`, so the two coincide and the ancestor test holds
# trivially. For rebase-and-merge, `mergeCommit.oid` is the TIP of the rebased
# range while publish (correctly) tags the commit that changed the version —
# which is an ancestor of that tip. Strict equality would raise a false "D-6
# mismatch" on a perfectly correct rebase-merge publish; the ancestor test still
# catches a genuine anomaly (publish tagging a commit outside the merged range).
merged_ver=$(rl_version_at "$merge_oid" "$vf_path" "$vf_sel") \
  || die "publish reported success but the version_file ($(sanitize_printable "$vf_path")) could not be read at the observed merge $merge_oid to verify the tag"
[ -n "$merged_ver" ] \
  || die "publish reported success but no version was found in $(sanitize_printable "$vf_path") at the observed merge $merge_oid"
rl_valid_semver "$merged_ver" \
  || die "publish reported success but the version at the observed merge is not valid SemVer: '$(sanitize_printable "$merged_ver")'"
published_tag="v$merged_ver"
tagged=$(git rev-parse -q --verify "refs/tags/$published_tag^{commit}" 2>/dev/null) \
  || die "publish reported success but tag $published_tag is absent"
git merge-base --is-ancestor "$tagged" "$merge_oid" 2>/dev/null \
  || die "the published tag $published_tag is on $tagged, which is not within the observed merge $merge_oid (D-6 mismatch — investigate before trusting the release)"

echo "release-arm: published $published_tag on the observed merge $merge_oid"
exit 0
