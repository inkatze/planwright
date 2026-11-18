# shellcheck shell=bash
# shellcheck disable=SC2034,SC2329 # the helpers are used by the sourcing test
# Spec-only fixture for the mc-readiness tests, sourced after
# tests/lib/mc-readiness-collect-fixture.sh: the spec root under the fixture
# repository, bundle, commit_specs and spec_pr, an empty gate-conditions
# file, and the origin remote the collector matches the repository by.

: "${tmp:?}" "${repo:?}" "${tracked:?}" "${repo_root:?}" "${tab:?source the fixtures first}"

: >"$tmp/no-conditions"
# The collector matches the pull request's repository by the origin remote.
git -C "$repo" remote add origin git@github.com:acme/web.git
mkdir -p "$repo/specs/_observations/entries"
sed -i.bak "s|^program_alpha_spec_root: .*|program_alpha_spec_root: $repo/specs|" "$tracked"
bundle() { # bundle <name> <status> <brief: signed|none|stale>: write a bundle, its brief anchoring it
  mkdir -p "$repo/specs/$1"
  printf '# %s\n\n**Status:** %s\n**Format-version:** 2\n\nBody.\n' "$1" "$2" >"$repo/specs/$1/requirements.md"
  printf '# Design\n\nx\n' >"$repo/specs/$1/design.md"
  printf '# Tasks\n\n**Format-version:** 2\n' >"$repo/specs/$1/tasks.md"
  printf '# Test spec\n\ny\n' >"$repo/specs/$1/test-spec.md"
  rm -f "$repo/specs/$1/kickoff-brief.md"
  # shellcheck disable=SC2016 # the brief's backticks are literal
  [ "$3" = none ] || printf '# Brief\n\nAnchor: `%s` — computed as\n`scripts/spec-anchor.sh specs/%s`\n' \
    "$(/bin/sh "$repo_root/scripts/spec-anchor.sh" "$repo/specs/$1")" "$1" >"$repo/specs/$1/kickoff-brief.md"
  [ "$3" != stale ] || printf 'An edit after the sign-off.\n' >>"$repo/specs/$1/design.md"
}
commit_specs() { # commit_specs: commit the spec root, print the head
  printf '%s\n' '- 2026-11-05 [planwright] an entry' >"$repo/specs/_observations/entries/e.md"
  git -C "$repo" add -A specs >/dev/null
  git -C "$repo" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m specs
  git -C "$repo" rev-parse HEAD
}
spec_pr() { # spec_pr <head> <path[|change type]>...: collect over the forge's view of a spec pull request
  sp_h=$1
  shift
  sp_files=''
  for sp_p in "$@"; do
    case $sp_p in
      *'|'*) sp_files="$sp_files{\"path\": \"${sp_p%|*}\", \"changeType\": \"${sp_p##*|}\"}," ;;
      *) sp_files="$sp_files{\"path\": \"$sp_p\", \"changeType\": \"MODIFIED\"}," ;;
    esac
  done
  printf '{"headRefOid": "%s", "headRefName": "planwright/demo/spec", "baseRefName": "main", "labels": [], "files": [%s],
 "body": "## Summary", "statusCheckRollup": [{"name": "build", "conclusion": "SUCCESS"}]}\n' "$sp_h" "${sp_files%,}" >"$tmp/pr.json"
  printf '%s\n' "$sp_h" >"$tmp/headnow"
  rm -f "$tmp/collected"
  PATH="$tmp/bin:$PATH" mc_run mc-readiness.sh collect --program alpha --repo acme/web --pr 7 --out "$tmp/collected"
  expect_rc "collect over $*" 0
  c=$(cat "$tmp/collected" 2>/dev/null)
}
