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
#      locally or on origin (idempotency); GitHub CI is green on the PR head.
#   2. Arm + watch: poll the PR until it is MERGED (fire) or CLOSED (disarm
#      cleanly, publishing nothing), up to a bounded poll cap.
#   3. On the observed merge: fast-forward local main to origin/main (new commits
#      only, never a rewrite), confirm the observed merge commit is on
#      origin/main, then run scripts/release-publish.sh. Finally verify the tag
#      publish created lands on the OBSERVED merge commit (the Done-when).
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
# Knobs (environment; sane defaults, overridable):
#   RELEASE_ARM_POLL_SECONDS   seconds between watch polls (default 15)
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
  '' | *[!0-9]* | 0) die "RELEASE_ARM_MAX_POLLS must be a positive integer: '$(sanitize_printable "$max_polls")'" ;;
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

# --- CI rollup check (inline; same shape as release-publish.sh's ci gate) ----
# rl_ci_state <sha> — set RL_CI_STATE to the server-aggregated statusCheckRollup
# state for <sha> and return 0 iff it is SUCCESS. Returns 2 on a query failure
# (distinct from a red verdict) so an infra outage fails closed rather than being
# misread as red CI. A null rollup (a repo with no checks) is RL_CI_STATE=NONE
# and refused: a release gate requires positive CI confirmation. Deliberately the
# same logic release-publish.sh applies to the merge SHA — kept an inline copy so
# release-publish.sh stays byte-for-byte the unchanged fallback (D-12); a shared
# rl_ci_state in release-lib.sh is a noted follow-up.
RL_CI_STATE=""
rl_ci_state() {
  local sha="$1" nwo owner repo raw
  nwo=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null) || return 2
  owner=${nwo%%/*}
  repo=${nwo#*/}
  # shellcheck disable=SC2016 # $o/$r/$sha are GraphQL variables, not shell expansions
  raw=$(gh api graphql \
    -f query='query($o:String!,$r:String!,$sha:GitObjectID!){repository(owner:$o,name:$r){object(oid:$sha){... on Commit{statusCheckRollup{state}}}}}' \
    -f o="$owner" -f r="$repo" -f sha="$sha" 2>/dev/null) || return 2
  RL_CI_STATE=$(printf '%s' "$raw" \
    | jq -r '.data.repository.object.statusCheckRollup.state // "NONE"' 2>/dev/null) || return 2
  [ "$RL_CI_STATE" = "SUCCESS" ]
}

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
head_oid=$(printf '%s' "$pr_json" | jq -r '.headRefOid // ""' 2>/dev/null)
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

# Idempotency: no tag for the proposed version, locally or on origin.
git rev-parse -q --verify "refs/tags/$tag" >/dev/null 2>&1 \
  && die "pre-validation: tag $tag already exists locally (idempotency); nothing to arm"
case "$origin_tags" in
  *"refs/tags/$tag"*) die "pre-validation: tag $tag already exists on origin (idempotency); the release is already published or in flight" ;;
esac

# Monotonicity: proposed strictly greater than the latest release tag on origin
# (vacuous when there are no release tags yet — the first release).
latest_ver=""
while IFS= read -r ref; do
  t=${ref##*refs/tags/}
  case "$t" in "" | *"^{}") continue ;; esac
  ver=${t#v}
  rl_valid_semver "$ver" || continue
  if [ -z "$latest_ver" ] || rl_version_gt "$ver" "$latest_ver"; then
    latest_ver="$ver"
  fi
done < <(printf '%s\n' "$origin_tags")
if [ -n "$latest_ver" ]; then
  rl_version_gt "$proposed" "$latest_ver" \
    || die "pre-validation: monotonicity gate — proposed $proposed is not strictly greater than the latest release v$latest_ver (on origin)"
fi

# GitHub CI green on the PR head — the real external state via gh.
ci_rc=0
rl_ci_state "$head_oid" || ci_rc=$?
if [ "$ci_rc" -eq 2 ]; then
  die "pre-validation: could not verify GitHub CI on the PR head $head_oid (gh query failed); resolve connectivity/auth and re-run"
elif [ "$ci_rc" -ne 0 ]; then
  die "pre-validation: ci gate — GitHub CI is not green on the PR head $head_oid (rollup state: ${RL_CI_STATE:-unknown})"
fi

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
  watch_state=$(printf '%s' "$watch_json" | jq -r '.state // ""' 2>/dev/null)
  case "$watch_state" in
    MERGED)
      merge_oid=$(printf '%s' "$watch_json" | jq -r '.mergeCommit.oid // ""' 2>/dev/null)
      break
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

is_hex_oid "$merge_oid" \
  || die "watch: PR #$pr reported MERGED but gh returned no valid merge commit oid: '$(sanitize_printable "$merge_oid")'"

echo "release-arm: observed the merge of PR #$pr at $merge_oid — syncing $MAIN_REF and publishing"

# --- Fire: sync main, then delegate to the unchanged publish (step 3) -------

# New commits only — fetch and fast-forward; never rewrite (REQ-J1.4 discipline).
git fetch origin >/dev/null 2>&1 \
  || die "could not fetch origin after the observed merge; main is unchanged — publish manually with $PUBLISH once synced"
git merge-base --is-ancestor "$merge_oid" "$ORIGIN_MAIN_REF" 2>/dev/null \
  || die "the observed merge $merge_oid is not on $ORIGIN_MAIN_REF after fetch; refusing to publish a state origin does not confirm"
if ! git merge --ff-only "$ORIGIN_MAIN_REF" >/dev/null 2>&1; then
  die "could not fast-forward $MAIN_REF to $ORIGIN_MAIN_REF (a non-ff divergence); resolve manually, then publish with $PUBLISH"
fi

# Delegate to the unchanged post-merge publish — the single tag authority. It
# recomputes the release-merge SHA itself (D-6) and re-enforces every gate.
if ! "$PUBLISH"; then
  die "publish failed after the observed merge; $MAIN_REF is synced — resolve and re-run $PUBLISH"
fi

# Verify the tag publish created lands on the OBSERVED merge commit (Done-when,
# REQ-D1.2). Publish's own D-6 scan is the authority; this is the belt-and-
# suspenders cross-check that arm watched the commit that actually got tagged.
tagged=$(git rev-parse -q --verify "refs/tags/$tag^{commit}" 2>/dev/null) \
  || die "publish reported success but tag $tag is absent"
[ "$tagged" = "$merge_oid" ] \
  || die "the published tag $tag is on $tagged, not the observed merge $merge_oid (D-6 mismatch — investigate before trusting the release)"

echo "release-arm: published $tag on the observed merge $merge_oid"
exit 0
