#!/usr/bin/env bash
# release-publish.sh — cut the annotated release tag and the GitHub Release for
# an approved (merged) release proposal (autopilot-reflex Task 4; D-4, D-6, D-8;
# REQ-D1.1..REQ-D1.7). The mechanical half of the release ceremony: the human
# has already approved by merging the release PR; this script carries the work
# to the gate's edge and stops (autopilot-reflex step 2). It PERFORMS the tag +
# Release; it never merges and never marks anything ready.
#
# What it does, in order (nothing mutates until every gate passes — REQ-D1.3):
#   1. Resolve the version of truth (the `version_file` knob) and the release-
#      merge SHA — the commit where that version landed on `main`, never HEAD
#      (D-6, REQ-D1.2). The target version is re-read from that commit's tree.
#   2. Enforce every safety gate, refusing WITHOUT side effects on any failure:
#      clean working tree; local `main` synced with `origin/main`; the target
#      tag absent locally and on `origin` (idempotency); the target strictly
#      greater than the latest release tag (monotonicity; vacuous on the first
#      release); GitHub CI green on the release SHA, checked against the real
#      external state via `gh` (REQ-D1.3). Idempotency exception: a tag already
#      pushed whose GitHub Release is absent (a partial publish) resumes by
#      creating the Release rather than refusing.
#   3. Create the annotated tag on the release SHA, signing per the
#      `require_signed_tags` knob (`auto`/`require`/`never`, D-4/REQ-D1.4).
#      Signing is delegated ENTIRELY to the repo's git config (`gpg.format`,
#      `user.signingkey`, `gpg.ssh.program`) — no signer is named here. A signed
#      tag is verified (`git tag -v`) before it is pushed (REQ-D1.5).
#   4. Push the tag, then create the GitHub Release from the version's
#      CHANGELOG.md section, attached to the pushed tag (`gh release create
#      --verify-tag`), never a tag `gh` creates itself (REQ-D1.7).
#
# Security posture (doctrine/security-posture.md, framework-script rules):
# version strings are validated against the SemVer grammar before any use in a
# tag name or comparison; the `version_file` selector is treated as data
# (scripts/release-lib.sh), never executed. No signing material ever enters CI —
# signing is a local, human-gated act (D-4).
#
# Usage: release-publish.sh
#   Run inside the repo, on a checkout of `main` synced with `origin/main`,
#   after the release PR has merged. Exit 0 on a completed (or resumed) publish;
#   1 on a gate refusal or an operational error (the message names the gate);
#   2 on a usage error.

set -u
LC_ALL=C
export LC_ALL
unset CDPATH

script_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=scripts/release-lib.sh
. "$script_dir/release-lib.sh"

MAIN_REF="main"
ORIGIN_MAIN_REF="origin/main"

die() {
  # die <gate-or-context> — refuse, naming the gate, without side effects.
  echo "release-publish: $1" >&2
  exit 1
}

if [ "$#" -gt 0 ]; then
  echo "release-publish: usage: release-publish.sh (no arguments)" >&2
  exit 2
fi

command -v git >/dev/null 2>&1 || die "git is required"
command -v gh >/dev/null 2>&1 || die "gh is required (GitHub CI check + Release creation)"
command -v jq >/dev/null 2>&1 || die "jq is required (GitHub CI check parsing)"

git rev-parse --git-dir >/dev/null 2>&1 || die "not a git repository"

# --- Resolve the version of truth and the release-merge SHA -----------------

IFS=$(printf '\t')
read -r vf_path vf_sel < <(rl_resolve_version_file "$script_dir")
unset IFS

git rev-parse -q --verify "$MAIN_REF" >/dev/null 2>&1 \
  || die "no local '$MAIN_REF' branch to publish from"

# Provisional target from main's tip, then the landing SHA, then the definitive
# target re-read from that commit's tree (REQ-D1.2: never the working tree).
provisional=$(rl_version_at "$MAIN_REF" "$vf_path" "$vf_sel") \
  || die "could not read the version_file ($vf_path) at $MAIN_REF"
[ -n "$provisional" ] \
  || die "no version found in $vf_path at $MAIN_REF"
rl_valid_semver "$provisional" \
  || die "version of truth is not valid SemVer: '$provisional'"

# The release-merge SHA is the newest first-parent commit on main where the
# version_file became the target — so an unrelated commit landing after the
# release merge (which keeps the same version) is skipped, and the tag lands on
# the true release commit regardless of interleaving (D-6, REQ-D1.2, REQ-E1.4).
release_sha=""
while IFS= read -r c; do
  cver=$(rl_version_at "$c" "$vf_path" "$vf_sel")
  [ "$cver" = "$provisional" ] || continue
  parent=$(git rev-parse -q --verify "$c^1" 2>/dev/null) || parent=""
  if [ -z "$parent" ]; then
    release_sha="$c"
    break
  fi
  pver=$(rl_version_at "$parent" "$vf_path" "$vf_sel")
  if [ "$pver" != "$provisional" ]; then
    release_sha="$c"
    break
  fi
done < <(git rev-list --first-parent "$MAIN_REF")

[ -n "$release_sha" ] \
  || die "could not identify the release-merge commit for version $provisional on $MAIN_REF"

target=$(rl_version_at "$release_sha" "$vf_path" "$vf_sel")
rl_valid_semver "$target" \
  || die "version at the release commit is not valid SemVer: '$target'"
tag="v$target"

# --- Idempotency gate + partial-publish detection (REQ-D1.3) ----------------

release_exists() {
  # A GitHub Release for the tag exists (real external state, via gh).
  gh release view "$tag" >/dev/null 2>&1
}

resume=0
if git rev-parse -q --verify "refs/tags/$tag" >/dev/null 2>&1; then
  die "idempotency gate: tag $tag already exists locally (resolve it before publishing)"
fi
if [ -n "$(git ls-remote --tags origin "refs/tags/$tag" 2>/dev/null)" ]; then
  if release_exists; then
    die "idempotency gate: tag $tag and its GitHub Release already exist (already published)"
  fi
  # Partial publish: tag pushed, Release missing — resume by creating it.
  resume=1
fi

# --- Creation gates (skipped on a resume; the tag is already validated) -----

if [ "$resume" -eq 0 ]; then
  # Monotonicity: target strictly greater than the latest release tag; vacuous
  # when there are no release tags yet (the first release).
  latest=$(rl_latest_release_tag)
  if [ -n "$latest" ]; then
    rl_version_gt "$target" "${latest#v}" \
      || die "monotonicity gate: target $target is not strictly greater than the latest release $latest"
  fi

  # Clean working tree.
  [ -z "$(git status --porcelain 2>/dev/null)" ] \
    || die "clean-tree gate: the working tree has uncommitted changes"

  # Local main synced with origin/main.
  git rev-parse -q --verify "$ORIGIN_MAIN_REF" >/dev/null 2>&1 \
    || die "sync gate: no $ORIGIN_MAIN_REF tracking ref (fetch origin first)"
  if [ "$(git rev-parse "$MAIN_REF")" != "$(git rev-parse "$ORIGIN_MAIN_REF")" ]; then
    die "sync gate: local $MAIN_REF is not synced with $ORIGIN_MAIN_REF"
  fi

  # GitHub CI green on the release SHA — the real external state via gh.
  ci_green() {
    local sha="$1" raw verdict
    raw=$(gh api "repos/{owner}/{repo}/commits/$sha/check-runs" 2>/dev/null) || return 1
    verdict=$(printf '%s' "$raw" | jq -r '
      if (.check_runs | length) > 0
         and (all(.check_runs[];
                  .status == "completed"
                  and (.conclusion == "success"
                       or .conclusion == "neutral"
                       or .conclusion == "skipped")))
      then "green" else "red" end' 2>/dev/null) || return 1
    [ "$verdict" = "green" ]
  }
  ci_green "$release_sha" \
    || die "ci gate: GitHub CI is not green on the release commit $release_sha"
fi

# --- Create + verify + push the tag (skipped on a resume) -------------------

if [ "$resume" -eq 0 ]; then
  # Signing policy (D-4, REQ-D1.4). `auto`: sign when the repo has signing
  # configured, else annotated unsigned with a warning. `require`: refuse unless
  # signing is configured and succeeds. `never`: always annotated unsigned.
  mode=$("$script_dir/config-get.sh" require_signed_tags 2>/dev/null) || mode=""
  [ -n "$mode" ] || mode="auto"
  case "$mode" in
    auto | require | never) : ;;
    *) die "config: require_signed_tags must be auto|require|never, got '$mode'" ;;
  esac

  signing_configured=0
  [ -n "$(git config --get user.signingkey 2>/dev/null)" ] && signing_configured=1

  sign=0
  case "$mode" in
    never) sign=0 ;;
    auto)
      if [ "$signing_configured" -eq 1 ]; then
        sign=1
      else
        echo "release-publish: no signing configured; creating an unsigned annotated tag ($mode)" >&2
      fi
      ;;
    require)
      [ "$signing_configured" -eq 1 ] \
        || die "signing gate: require_signed_tags=require but no signing is configured (git user.signingkey)"
      sign=1
      ;;
  esac

  if [ "$sign" -eq 1 ]; then
    git tag -s -m "$tag" "$tag" "$release_sha" \
      || die "signing gate: git tag -s failed (require_signed_tags=$mode)"
    # Verify the signature before it can be pushed (REQ-D1.5). On failure,
    # remove the local tag so nothing signed-but-unverified is left behind.
    if ! git tag -v "$tag" >/dev/null 2>&1; then
      git tag -d "$tag" >/dev/null 2>&1 || true
      die "verify gate: git tag -v failed for $tag; aborted before push"
    fi
  else
    git tag -a -m "$tag" "$tag" "$release_sha" \
      || die "tag creation failed for $tag"
  fi

  if ! git push origin "refs/tags/$tag"; then
    echo "release-publish: pushing $tag failed; the local tag is kept — re-run after resolving the push" >&2
    exit 1
  fi
fi

# --- Create the GitHub Release from the CHANGELOG section (REQ-D1.7) ---------

changelog_notes() {
  # Print the CHANGELOG.md section for $target, from its `## [x.y.z]` heading to
  # the next `## ` heading; empty when the file or the section is absent.
  local file="CHANGELOG.md"
  [ -f "$file" ] || return 0
  awk -v marker="[$target]" '
    /^## / {
      if (inSec) exit
      if (index($0, marker) > 0) { inSec = 1; print; next }
    }
    inSec { print }
  ' "$file"
}

notes_file=$(mktemp)
trap 'rm -f "$notes_file"' EXIT
notes=$(changelog_notes)
if [ -n "$notes" ]; then
  printf '%s\n' "$notes" >"$notes_file"
else
  echo "release-publish: no CHANGELOG.md section for $target; using a minimal release note" >&2
  printf 'Release %s\n' "$tag" >"$notes_file"
fi

# --verify-tag makes gh attach to the already-pushed tag and refuse to create
# one itself (REQ-D1.7): the tag is ours, signed, on the release SHA.
if ! gh release create "$tag" --verify-tag --title "$tag" --notes-file "$notes_file"; then
  die "GitHub Release creation failed for $tag (the tag is pushed; re-run to resume)"
fi

if [ "$resume" -eq 1 ]; then
  echo "release-publish: resumed — created the GitHub Release for the already-pushed $tag"
else
  echo "release-publish: published $tag on $release_sha"
fi
exit 0
