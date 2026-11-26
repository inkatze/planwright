# shellcheck shell=bash
# shellcheck disable=SC2034,SC2329 # the helpers are used by the sourcing test
# Drift fixture for the mc-readiness tests, sourced after
# tests/lib/mc-readiness-spec-fixture.sh: a signed bundle whose task lists
# two deliverables, a base commit with code (dr_base, also origin/main),
# resign, dr_commit, dr_pr (collect and check over the forge's view of a pull
# request) and dr_a, a commit that changes a listed deliverable.

[ "$(type -t bundle)" = function ] || : "${bundle:?source tests/lib/mc-readiness-spec-fixture.sh first}"
: "${tmp:?}" "${repo:?}" "${repo_root:?}" "${tab:?}"

# ---------------------------------------------------------------------------
# REQ-D1.13: a pull request that is not spec-only is checked for spec drift,
# and its edited bundles' sign-offs are read as a spec-only one's are.
# ---------------------------------------------------------------------------
bundle demo Ready signed
cat >"$repo/specs/demo/tasks.md" <<'EOF'
# Tasks

**Format-version:** 2

## Tasks

### Task 1 — One

- **Deliverables:** `app/run.sh`, and prose app/prose.sh.
- **Done when:** ok.
- **Dependencies:** none
- **Citations:** D-1
- **Estimated effort:** 1 day
EOF
resign() { # resign: re-sign the demo bundle at its current content
  # shellcheck disable=SC2016 # the brief's backticks are literal
  printf '# Brief\n\nAnchor: `%s` — computed as\n`scripts/spec-anchor.sh specs/demo`\n' \
    "$(/bin/sh "$repo_root/scripts/spec-anchor.sh" "$repo/specs/demo")" >"$repo/specs/demo/kickoff-brief.md"
}
resign
mkdir -p "$repo/app" "$repo/src"
printf 'run\n' >"$repo/app/run.sh"
printf 'prose\n' >"$repo/app/prose.sh"
dr_commit() { # dr_commit <message>: commit the spec and code paths (never the fixture config), print the head
  git -C "$repo" add specs app src >/dev/null
  git -C "$repo" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m "$1"
  git -C "$repo" rev-parse HEAD
}
printf 'other\n' >"$repo/src/other.c"
dr_base=$(dr_commit "base with code and a signed spec")
git -C "$repo" update-ref refs/remotes/origin/main "$dr_base"
# dr_pr <head> <body> <base branch> <path[|change type[|source]]>...: collect
# and check over the forge's view. The source, a rename's or copy's, is known
# only to the REST file list, as spec_pr writes it; DR_REST=fail makes that
# read fail.
dr_pr() {
  dr_h=$1 dr_body=$2 dr_bb=$3
  shift 3
  jq -n --arg h "$dr_h" --arg body "$dr_body" --arg bb "$dr_bb" --args '
    {headRefOid: $h, headRefName: "feature", baseRefName: $bb, labels: [], body: $body,
     files: ($ARGS.positional | map(split("|") | {path: .[0], changeType: (.[1] // "MODIFIED")})),
     changedFiles: ($ARGS.positional | length),
     statusCheckRollup: [{name: "build", conclusion: "SUCCESS"}]}' "$@" >"$tmp/pr.json"
  jq -n --args '$ARGS.positional | map(split("|")
    | if (.[2] // "") != "" then {filename: .[0], status: "renamed", previous_filename: .[2]}
      else {filename: .[0], status: "modified"} end)' "$@" >"$tmp/files.json"
  [ "${DR_REST:-}" != fail ] || rm -f "$tmp/files.json"
  printf '%s\n' "$dr_h" >"$tmp/headnow"
  rm -f "$tmp/collected"
  PATH="$tmp/bin:$PATH" mc_run mc-readiness.sh collect --program alpha --repo acme/web --pr 7 --out "$tmp/collected"
  c=$(cat "$tmp/collected" 2>/dev/null)
  PATH="$tmp/bin:$PATH" mc_run mc-readiness.sh check --program alpha --repo acme/web --pr 7
}
printf 'changed\n' >>"$repo/app/run.sh"
dr_a=$(dr_commit "feat: change the listed file")
