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
# `api graphql` prints a statusCheckRollup whose `ci` CheckRun node is set by
# GH_CI (green→conclusion SUCCESS, red→conclusion FAILURE, pending→status
# IN_PROGRESS, neutral→conclusion NEUTRAL, none→no `ci` node; with no nodes at
# all the rollup is null). These are per-node attributes, not rollup states: the
# top-level `state` is derived separately (see below), and there is no PENDING/
# NEUTRAL rollup-state shorthand here. The rollup carries per-check
# `contexts` so the publish gate's per-check evaluation and window-lock exclusion
# are exercised; GH_WINDOW_LOCK (red|green) adds a `window-lock` check-run;
# GH_STATUS_CONTEXT (success|error|pending) adds a legacy StatusContext
# (commit-status) node, named via GH_STATUS_CONTEXT_NAME (default legacy-ci) so a
# commit-status can be named `window-lock` to prove the carve-out is CheckRun-
# scoped; GH_HASNEXTPAGE=true forces the pagination guard. The top-level rollup
# `state` is computed with GitHub's rollup precedence (FAILURE > PENDING >
# SUCCESS — max severity, not last-writer-wins) so it stays server-accurate even
# when checks of differing severity coexist, and a gate that reads only the
# aggregate still sees the real, deadlocking state. `release view` exits per
# GH_RELEASE_EXISTS; `release create` copies its --notes-file to $GH_NOTES.
# Everything else is a benign success.
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
    # Two distinct `gh api` calls: the statusCheckRollup GraphQL query
    # ($2=graphql) and the relabel step's commit-to-PR lookup ($2 matches
    # .../commits/<sha>/pulls, $4 carries the real `-q` filter). The latter is
    # modeled as a synthetic PR list piped through the real filter — GH_PR_JSON
    # supplies the list directly (multiple PRs / labels); GH_PR_NUMBER is the
    # single-PR-no-labels shorthand used by the older fixtures. Unset/empty
    # means no PR found, mirroring gh's real `-q` yielding "null" on `[]`.
    case "$2" in
      *"/pulls")
        # GH_API_PULLS_FAIL=1 models the query itself failing (network/auth/
        # rate-limit) — distinct from a genuine empty result — so the
        # caller's query-failure-vs-absence distinction is testable.
        if [ "${GH_API_PULLS_FAIL:-0}" = 1 ]; then
          echo "gh: error connecting to api.github.com" >&2
          exit 1
        fi
        pulls_json="${GH_PR_JSON:-}"
        if [ -z "$pulls_json" ] && [ -n "${GH_PR_NUMBER:-}" ]; then
          pulls_json="[{\"number\": $GH_PR_NUMBER, \"labels\": []}]"
        fi
        printf '%s' "${pulls_json:-[]}" | jq -r "$4"
        exit 0
        ;;
    esac
    # GH_CI_QUERY_FAIL=1 models the statusCheckRollup GraphQL query itself failing
    # (network/auth/rate-limit): rl_ci_state returns 2, and publish's CI gate must
    # FAIL CLOSED (refuse), never treat a query failure as green.
    if [ "${GH_CI_QUERY_FAIL:-0}" = 1 ]; then
      echo "gh: error connecting to api.github.com" >&2
      exit 1
    fi
    # The statusCheckRollup GraphQL query. Build a
    # rollup with per-check `contexts` (plus an accurate top-level `state`).
    # GH_CI drives the `ci` quality CheckRun (green|red|pending|neutral|none);
    # GH_WINDOW_LOCK (red|green), when set, adds a `window-lock` CheckRun;
    # GH_STATUS_CONTEXT (success|error|pending), when set, adds a legacy
    # StatusContext (commit-status) node named via GH_STATUS_CONTEXT_NAME
    # (default legacy-ci) so the gate's non-CheckRun branch is exercised;
    # GH_HASNEXTPAGE=true forces hasNextPage so the >100-check pagination guard
    # (too-many) is exercised even with a green visible page. With no checks at
    # all the rollup is null. The top-level `state` stays server-accurate so a
    # gate that (wrongly) read only the aggregate would still see the real state.
    nodes=""
    st="SUCCESS"
    add_node() { if [ -n "$nodes" ]; then nodes="$nodes,$1"; else nodes="$1"; fi; }
    # Track the worst check state with GitHub's rollup precedence
    # (FAILURE > PENDING > SUCCESS) so the top-level `state` stays server-accurate
    # even when checks of differing severity coexist (a red check plus a pending
    # one). A plain per-branch `st=...` would be last-writer-wins and could report
    # PENDING while a FAILURE is present, contradicting the real rollup.
    worsen() { case "$1" in FAILURE) st="FAILURE" ;; PENDING) [ "$st" = "SUCCESS" ] && st="PENDING" ;; esac; }
    case "${GH_CI:-green}" in
      green) add_node '{"__typename":"CheckRun","name":"ci","status":"COMPLETED","conclusion":"SUCCESS"}' ;;
      red) add_node '{"__typename":"CheckRun","name":"ci","status":"COMPLETED","conclusion":"FAILURE"}'; worsen FAILURE ;;
      pending) add_node '{"__typename":"CheckRun","name":"ci","status":"IN_PROGRESS","conclusion":null}'; worsen PENDING ;;
      neutral) add_node '{"__typename":"CheckRun","name":"ci","status":"COMPLETED","conclusion":"NEUTRAL"}' ;;
      none) : ;;
    esac
    # The window-lock CheckRun models the REAL release-window lock, so it carries
    # checkSuite.workflowRun.workflow.name = release-window: rl_ci_state's
    # exclusion is now WORKFLOW-SCOPED (REQ-C1.3), excluding the lock only when it
    # is owned by the release-window workflow. (A foreign-workflow or null-workflowRun
    # window-lock namesake being JUDGED, not excluded, is covered in
    # tests/test-release-lib.sh, rl_ci_state's home.)
    case "${GH_WINDOW_LOCK:-}" in
      red) add_node '{"__typename":"CheckRun","name":"window-lock","status":"COMPLETED","conclusion":"FAILURE","checkSuite":{"workflowRun":{"workflow":{"name":"release-window"}}}}'; worsen FAILURE ;;
      green) add_node '{"__typename":"CheckRun","name":"window-lock","status":"COMPLETED","conclusion":"SUCCESS","checkSuite":{"workflowRun":{"workflow":{"name":"release-window"}}}}' ;;
    esac
    # GH_STATUS_CONTEXT_NAME overrides the legacy commit-status context name
    # (default legacy-ci) so a StatusContext can be named "window-lock" to prove
    # the carve-out is CheckRun-scoped and does NOT drop a same-named commit-status.
    sc_name="${GH_STATUS_CONTEXT_NAME:-legacy-ci}"
    case "${GH_STATUS_CONTEXT:-}" in
      success) add_node '{"__typename":"StatusContext","context":"'"$sc_name"'","state":"SUCCESS"}' ;;
      error) add_node '{"__typename":"StatusContext","context":"'"$sc_name"'","state":"ERROR"}'; worsen FAILURE ;;
      pending) add_node '{"__typename":"StatusContext","context":"'"$sc_name"'","state":"PENDING"}'; worsen PENDING ;;
    esac
    if [ -z "$nodes" ]; then
      printf '{"data":{"repository":{"object":{"statusCheckRollup":null}}}}\n'
    else
      printf '{"data":{"repository":{"object":{"statusCheckRollup":{"state":"%s","contexts":{"pageInfo":{"hasNextPage":%s},"nodes":[%s]}}}}}}\n' "$st" "${GH_HASNEXTPAGE:-false}" "$nodes"
    fi
    exit 0
    ;;
  label)
    # `label list --search ...`: the relabel step's create-if-missing probe.
    # GH_LABEL_TAGGED_EXISTS=1 models the label already being present; unset/0
    # prints nothing (grep -qxF then finds no match), driving the create path.
    [ "$2" = "list" ] && [ "${GH_LABEL_TAGGED_EXISTS:-0}" = 1 ] && printf 'autorelease: tagged\n'
    exit 0
    ;;
  pr)
    # `pr edit <number> --add-label ... --remove-label ...`: the relabel
    # step's actual mutation. GH_PR_EDIT_FAIL=1 models a failed relabel (e.g.
    # permissions/network) so the caller's non-fatal degrade path is testable.
    [ "${GH_PR_EDIT_FAIL:-0}" = 1 ] && exit 1
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

# gi <dir> <git-args...> — run git in <dir> with the developer's global/system
# config isolated, so creating a SIGNED tag in a fixture uses ONLY the repo-local
# signing config (gpg.format ssh + user.signingkey) and never the machine's real
# signer (e.g. a 1Password op-ssh-sign program that would intercept and fail).
gi() { env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null git -C "$1" "${@:2}"; }
# verify_ref_gone <dir> <tag> — the reserved resume verification ref was cleaned
# up (no stale ref left behind, REQ-B1.1).
verify_ref_gone() { ! git -C "$1" rev-parse -q --verify "refs/release-verify/$2" >/dev/null 2>&1; }

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
want "race: relabel looked up the PR at the release-merge SHA, not HEAD" gh_called "$LOG" "commits/$MERGE_SHA/pulls"

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

# 4b. Origin tag AND Release both present. REQ-B1.4/D-12 changed this from a hard
#     "already published" refusal into the idempotent-relabel path: the run must
#     NOT die before the relabel, must NOT re-create the already-present Release,
#     and — with no release PR found for the commit — degrades to a stderr warning
#     and exits 0 (the deadlock window stays closed either way).
r="$tmp/gate-origintag"
new_repo "$r"
seed_version "$r" 0.1.0
gc "$r" tag v0.1.0
gc "$r" push -q origin v0.1.0 2>/dev/null
gc "$r" tag -d v0.1.0 >/dev/null
run_publish "$r" GH_CI=green GH_RELEASE_EXISTS=1
assert_eq "gate/origin-tag: exit 0 (relabel path, no longer a hard refusal)" "$RC" "0"
case "$ERR" in
  *"already published"*) bad "gate/origin-tag: still dies 'already published' (REQ-B1.4 regressed)" ;;
  *) pass "gate/origin-tag: does not die 'already published'" ;;
esac
deny "gate/origin-tag: no Release re-created (already present)" gh_called "$LOG" "release create"
assert_contains "gate/origin-tag: relabel degrades gracefully with no PR found" "$ERR" "no pull request found"

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
assert_contains "gate/no-checks: names the ci gate with the verdict" "$ERR" "verdict: none"
deny "gate/no-checks: no local tag created" local_has_tag "$r" v0.1.0

# 4e-2. CI QUERY FAILURE fails closed at the CALLER: rl_ci_state returns 2 (a gh
#       query failure), and publish's CI gate must refuse naming the query
#       failure — never conflate an infra outage with a green verdict, and never
#       publish. Guards the refactored `[ "$ci_rc" -ne 0 ]` branch end-to-end.
r="$tmp/gate-ci-queryfail"
new_repo "$r"
seed_version "$r" 0.1.0
run_publish "$r" GH_CI=green GH_CI_QUERY_FAIL=1 GH_RELEASE_EXISTS=0
assert_ne "gate/ci-queryfail: exits non-zero (query failure → refuse, not publish)" "$RC" "0"
assert_contains "gate/ci-queryfail: names the query failure, not a red verdict" "$ERR" "gh query failed"
deny "gate/ci-queryfail: no local tag created on a query failure" local_has_tag "$r" v0.1.0

# 4f. CI not green.
r="$tmp/gate-ci"
new_repo "$r"
seed_version "$r" 0.1.0
run_publish "$r" GH_CI=red GH_RELEASE_EXISTS=0
assert_ne "gate/ci: exits non-zero" "$RC" "0"
assert_contains "gate/ci: names the ci gate" "$ERR" "ci gate"
deny "gate/ci: no local tag created" local_has_tag "$r" v0.1.0

# 4h. THE UNTAGGED-WINDOW DEADLOCK FIX (REQ-E1.1 vs REQ-D1.3). The window-lock
#     check (release-window.yml) is RED BY DESIGN on `main` throughout the
#     untagged window — from a release PR's merge until this script publishes the
#     tag — so the server-aggregated rollup is FAILURE. It is a MERGE gate, never
#     a PUBLISH gate: gating publish on it deadlocks (the window cannot close
#     because the open window makes the rollup red, and publishing the tag is the
#     only thing that closes it). With every OTHER check green, publish MUST
#     proceed. Before the fix the gate read the aggregate rollup and refused here.
r="$tmp/window-lock-red"
new_repo "$r"
seed_version "$r" 0.1.0
run_publish "$r" GH_CI=green GH_WINDOW_LOCK=red GH_RELEASE_EXISTS=0
assert_eq "window-lock/deadlock: publish proceeds with window-lock red + quality green" "$RC" "0"
want "window-lock/deadlock: tag created despite the expected-red window lock" local_has_tag "$r" v0.1.0
want "window-lock/deadlock: tag pushed to origin" origin_has_tag "$r" v0.1.0

# 4h-2. The carve-out is SURGICAL: window-lock red is tolerated, but a red
#       QUALITY check still fails the gate closed (only window-lock is excluded).
r="$tmp/window-lock-and-ci-red"
new_repo "$r"
seed_version "$r" 0.1.0
run_publish "$r" GH_CI=red GH_WINDOW_LOCK=red GH_RELEASE_EXISTS=0
assert_ne "window-lock/quality-red: a red quality check still fails with window-lock excluded" "$RC" "0"
assert_contains "window-lock/quality-red: names the ci gate" "$ERR" "ci gate"
deny "window-lock/quality-red: no tag created when a quality check is red" local_has_tag "$r" v0.1.0

# 4h-3. If window-lock is the ONLY check present, the gate still fails closed:
#       after excluding it there is no positive CI confirmation, and a release
#       gate requires a real green check, not merely "nothing else failed".
r="$tmp/window-lock-only"
new_repo "$r"
seed_version "$r" 0.1.0
run_publish "$r" GH_CI=none GH_WINDOW_LOCK=red GH_RELEASE_EXISTS=0
assert_ne "window-lock/only: window-lock alone is not positive CI confirmation" "$RC" "0"
assert_contains "window-lock/only: names the ci gate (no confirming check)" "$ERR" "ci gate"
deny "window-lock/only: no tag created with only the window lock present" local_has_tag "$r" v0.1.0

# 4h-4. Outside the window (window-lock green) with quality green → publishes; the
#       exclusion never turns a genuine green into a refusal.
r="$tmp/window-lock-green"
new_repo "$r"
seed_version "$r" 0.1.0
run_publish "$r" GH_CI=green GH_WINDOW_LOCK=green GH_RELEASE_EXISTS=0
assert_eq "window-lock/green: green window lock + green quality publishes" "$RC" "0"
want "window-lock/green: tag created" local_has_tag "$r" v0.1.0

# 4h-5. Fail-closed on PENDING (REQ-D1.3). A non-excluded check still in progress
#       blocks publish — the gate waits for CI to finish, it never races it.
r="$tmp/ci-pending"
new_repo "$r"
seed_version "$r" 0.1.0
run_publish "$r" GH_CI=pending GH_RELEASE_EXISTS=0
assert_ne "gate/pending: an in-progress check blocks publish" "$RC" "0"
assert_contains "gate/pending: names the ci gate" "$ERR" "ci gate"
assert_contains "gate/pending: classified PENDING (waits, not FAILURE)" "$ERR" "verdict: pending"
deny "gate/pending: no tag created while CI is pending" local_has_tag "$r" v0.1.0

# 4h-6. StatusContext (legacy commit-status) path publishes on a green status.
#       Here the ONLY check is a StatusContext (GH_CI=none), so the non-CheckRun
#       branch (state==SUCCESS as positive confirmation) is exercised in isolation
#       and a bug in it surfaces on its own. Mixed CheckRun + StatusContext
#       rollups are covered by 4h-10/4h-11.
r="$tmp/status-context-green"
new_repo "$r"
seed_version "$r" 0.1.0
run_publish "$r" GH_CI=none GH_STATUS_CONTEXT=success GH_RELEASE_EXISTS=0
assert_eq "gate/status-context: a green commit status publishes" "$RC" "0"
want "gate/status-context: tag created from a green StatusContext" local_has_tag "$r" v0.1.0

# 4h-7. StatusContext error fails closed. A commit status in ERROR maps to
#       FAILURE (not SUCCESS), blocking publish — guards the non-CheckRun state
#       mapping against a false green on a legacy status.
r="$tmp/status-context-error"
new_repo "$r"
seed_version "$r" 0.1.0
run_publish "$r" GH_CI=none GH_STATUS_CONTEXT=error GH_RELEASE_EXISTS=0
assert_ne "gate/status-context-error: an ERROR commit status blocks publish" "$RC" "0"
assert_contains "gate/status-context-error: names the ci gate" "$ERR" "ci gate"
deny "gate/status-context-error: no tag created on an ERROR status" local_has_tag "$r" v0.1.0

# 4h-7b. StatusContext pending fails closed. A legacy commit status still PENDING
#        maps to PENDING (not SUCCESS), blocking publish — the non-CheckRun branch
#        must wait for an in-progress status just like a CheckRun.
r="$tmp/status-context-pending"
new_repo "$r"
seed_version "$r" 0.1.0
run_publish "$r" GH_CI=none GH_STATUS_CONTEXT=pending GH_RELEASE_EXISTS=0
assert_ne "gate/status-context-pending: a PENDING commit status blocks publish" "$RC" "0"
assert_contains "gate/status-context-pending: names the ci gate" "$ERR" "ci gate"
deny "gate/status-context-pending: no tag created while a status is pending" local_has_tag "$r" v0.1.0

# 4h-8. Pagination guard (too-many). More checks than one page can hold
#       (hasNextPage) fails closed EVEN with a green visible page — an unseen
#       later page could hold a red check, so the gate refuses rather than trust
#       a partial view. This is the blind spot the per-check rewrite closes.
r="$tmp/too-many-checks"
new_repo "$r"
seed_version "$r" 0.1.0
run_publish "$r" GH_CI=green GH_HASNEXTPAGE=true GH_RELEASE_EXISTS=0
assert_ne "gate/pagination: hasNextPage fails closed despite a green visible page" "$RC" "0"
assert_contains "gate/pagination: names the ci gate" "$ERR" "ci gate"
assert_contains "gate/pagination: classified TOO_MANY (an unseen page could be red)" "$ERR" "verdict: too-many"
deny "gate/pagination: no tag created when checks exceed one page" local_has_tag "$r" v0.1.0

# 4h-9. Positive-confirmation requirement. A run whose only non-excluded check is
#       NEUTRAL/SKIPPED resolves to NONE (not SUCCESS) and fails closed — absence
#       of failure is not confirmation. Distinct jq branch from window-lock-only
#       (which drops to length==0); here a check survives but confirms nothing.
r="$tmp/neutral-only"
new_repo "$r"
seed_version "$r" 0.1.0
run_publish "$r" GH_CI=neutral GH_RELEASE_EXISTS=0
assert_ne "gate/neutral-only: a neutral-only run is not positive confirmation" "$RC" "0"
assert_contains "gate/neutral-only: names the ci gate" "$ERR" "ci gate"
assert_contains "gate/neutral-only: classified NONE (no positive confirmation)" "$ERR" "verdict: none"
deny "gate/neutral-only: no tag created with only neutral checks" local_has_tag "$r" v0.1.0

# 4h-10. MIXED-VERDICT PRECEDENCE: a green check must not mask a red one. Two
#        non-excluded checks coexist — a green `ci` CheckRun AND a legacy
#        StatusContext in ERROR — so the rollup carries [SUCCESS, FAILURE]. The
#        re-aggregation must resolve FAILURE (a failing check dominates a passing
#        one); were the precedence inverted (SUCCESS scanned before FAILURE), one
#        green check would publish a broken release and every other test would
#        still pass. This is also the ONLY scenario exercising both node-type
#        branches (CheckRun + StatusContext) in a single evaluation pass.
r="$tmp/mixed-success-failure"
new_repo "$r"
seed_version "$r" 0.1.0
run_publish "$r" GH_CI=green GH_STATUS_CONTEXT=error GH_RELEASE_EXISTS=0
assert_ne "gate/mixed-fail: a green check does not mask a red one" "$RC" "0"
assert_contains "gate/mixed-fail: classified FAILURE, not green" "$ERR" "verdict: failing"
deny "gate/mixed-fail: no tag created when any non-excluded check is red" local_has_tag "$r" v0.1.0

# 4h-11. MIXED-VERDICT PRECEDENCE: a green check must not mask a pending one. A
#        green `ci` CheckRun coexists with a still-PENDING legacy status →
#        [SUCCESS, PENDING] → PENDING (wait for CI per REQ-D1.3), never SUCCESS.
#        Pins that positive confirmation cannot race an in-progress check merely
#        because another check already finished green.
r="$tmp/mixed-success-pending"
new_repo "$r"
seed_version "$r" 0.1.0
run_publish "$r" GH_CI=green GH_STATUS_CONTEXT=pending GH_RELEASE_EXISTS=0
assert_ne "gate/mixed-pending: a green check does not mask a pending one" "$RC" "0"
assert_contains "gate/mixed-pending: classified PENDING, not green" "$ERR" "verdict: pending"
deny "gate/mixed-pending: no tag created while any non-excluded check is pending" local_has_tag "$r" v0.1.0

# 4h-12. CheckRun-SCOPED carve-out (Copilot #163 review thread). The window-lock
#        exclusion drops ONLY the Actions CheckRun of that name; a legacy
#        commit-status (StatusContext) named `window-lock` is NOT excluded, so a
#        red one still fails the gate closed. Before the type-scoping the bare
#        name match dropped it, and a green `ci` alongside would have published a
#        release while a check named window-lock was red.
r="$tmp/status-context-named-window-lock"
new_repo "$r"
seed_version "$r" 0.1.0
run_publish "$r" GH_CI=green GH_STATUS_CONTEXT=error GH_STATUS_CONTEXT_NAME=window-lock GH_RELEASE_EXISTS=0
assert_ne "gate/sc-window-lock: a red commit-status named window-lock is NOT carved out" "$RC" "0"
assert_contains "gate/sc-window-lock: classified FAILURE (StatusContext judged, not excluded)" "$ERR" "verdict: failing"
deny "gate/sc-window-lock: no tag created (the same-named commit-status still blocks)" local_has_tag "$r" v0.1.0

# 4h-13. The gh stub's top-level rollup `state` is server-accurate under mixed
#        severities (Copilot #163 review thread): a FAILURE alongside a later
#        PENDING aggregates to FAILURE (max severity), not last-writer-wins
#        PENDING — else a gate reading the aggregate could be misled and the
#        fixture would contradict its own "server-accurate" contract. Asserts the
#        stub directly (its `state` is the fixture's model of the real rollup).
state=$(env PATH="$stub:$PATH" GH_CI=red GH_STATUS_CONTEXT=pending gh api graphql -f query=x 2>/dev/null \
  | jq -r '.data.repository.object.statusCheckRollup.state')
assert_eq "stub/state-accuracy: red + pending aggregates to FAILURE (max severity)" "$state" "FAILURE"

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

# ===========================================================================
# 10. Relabel the merged release PR after publish (issue #173): release-please
#     tracks release state via the `autorelease: pending`/`autorelease: tagged`
#     label independently of the tag/window tracker, so a publish that never
#     flips it deadlocks release-please's own "untagged, merged release PRs
#     outstanding" guard on every subsequent run. Best-effort: never fatal.
# ===========================================================================

# 10a. Happy path: the release PR is found and the target label doesn't exist
#      yet (create-if-missing) — both the label create and the pr relabel run.
r="$tmp/relabel-happy"
new_repo "$r"
seed_version "$r" 0.1.0
run_publish "$r" GH_CI=green GH_RELEASE_EXISTS=0 GH_PR_NUMBER=42 GH_LABEL_TAGGED_EXISTS=0
assert_eq "relabel/happy: exit 0" "$RC" "0"
want "relabel/happy: the missing 'autorelease: tagged' label is created" \
  gh_called "$LOG" "label create autorelease: tagged"
want "relabel/happy: the release PR is relabeled pending -> tagged" \
  gh_called "$LOG" "pr edit 42 --add-label autorelease: tagged --remove-label autorelease: pending"

# 10b. The label already exists: no redundant `label create`, but the PR is
#      still relabeled.
r="$tmp/relabel-label-exists"
new_repo "$r"
seed_version "$r" 0.1.0
run_publish "$r" GH_CI=green GH_RELEASE_EXISTS=0 GH_PR_NUMBER=7 GH_LABEL_TAGGED_EXISTS=1
assert_eq "relabel/label-exists: exit 0" "$RC" "0"
deny "relabel/label-exists: no redundant label create when it already exists" \
  gh_called "$LOG" "label create"
want "relabel/label-exists: the release PR is still relabeled" gh_called "$LOG" "pr edit 7"

# 10c. No PR found for the release commit: degrades to a stderr warning, never
#      fails the publish (the tag + Release are already the real output).
r="$tmp/relabel-no-pr"
new_repo "$r"
seed_version "$r" 0.1.0
run_publish "$r" GH_CI=green GH_RELEASE_EXISTS=0
assert_eq "relabel/no-pr: exit 0 (non-fatal)" "$RC" "0"
assert_contains "relabel/no-pr: warns that no PR was found for the release commit" \
  "$ERR" "no pull request found"
deny "relabel/no-pr: no pr edit attempted" gh_called "$LOG" "pr edit"
want "relabel/no-pr: the Release was still created" gh_called "$LOG" "release create"

# 10d. The commit-to-PR lookup itself fails (network/auth/rate-limit) rather
#      than genuinely finding no PR: the warning must say the query failed,
#      not claim no PR exists for the commit — a real "no PR" reads as an
#      unusual release-process state, while a query failure just means retry.
r="$tmp/relabel-api-fail"
new_repo "$r"
seed_version "$r" 0.1.0
run_publish "$r" GH_CI=green GH_RELEASE_EXISTS=0 GH_API_PULLS_FAIL=1
assert_eq "relabel/api-fail: exit 0 (non-fatal)" "$RC" "0"
assert_contains "relabel/api-fail: warns that the query failed, not that no PR exists" \
  "$ERR" "could not query"
case "$ERR" in
  *"no pull request found"*) bad "relabel/api-fail: warning wrongly claims no PR was found" ;;
  *) pass "relabel/api-fail: warning does not conflate query failure with no PR found" ;;
esac
deny "relabel/api-fail: no pr edit attempted" gh_called "$LOG" "pr edit"
want "relabel/api-fail: the Release was still created" gh_called "$LOG" "release create"

# 10e. The PR is found but relabeling itself fails (permissions/network):
#      degrades to a stderr warning naming the PR and the manual fix, never
#      fails the publish.
r="$tmp/relabel-edit-fail"
new_repo "$r"
seed_version "$r" 0.1.0
run_publish "$r" GH_CI=green GH_RELEASE_EXISTS=0 GH_PR_NUMBER=9 GH_PR_EDIT_FAIL=1
assert_eq "relabel/edit-fail: exit 0 (best-effort, never fatal)" "$RC" "0"
assert_contains "relabel/edit-fail: names the PR and warns to relabel manually" \
  "$ERR" "PR #9"
assert_contains "relabel/edit-fail: warns to relabel manually so release-please does not deadlock" \
  "$ERR" "relabel it manually"
want "relabel/edit-fail: the Release was still created" gh_called "$LOG" "release create"

# 10f. The commit-to-PR lookup returns more than one PR for the release
#      commit (a backport or superseded branch can share it): the one still
#      carrying 'autorelease: pending' is relabeled, not just the first entry.
r="$tmp/relabel-multi-pr"
new_repo "$r"
seed_version "$r" 0.1.0
run_publish "$r" GH_CI=green GH_RELEASE_EXISTS=0 GH_LABEL_TAGGED_EXISTS=0 \
  GH_PR_JSON='[{"number":11,"labels":[{"name":"backport"}]},{"number":22,"labels":[{"name":"autorelease: pending"}]}]'
assert_eq "relabel/multi-pr: exit 0" "$RC" "0"
want "relabel/multi-pr: the PR still carrying autorelease: pending is relabeled" \
  gh_called "$LOG" "pr edit 22 --add-label autorelease: tagged --remove-label autorelease: pending"
deny "relabel/multi-pr: the first-listed PR without the pending label is left alone" \
  gh_called "$LOG" "pr edit 11"

# ===========================================================================
# 11. Resume-path integrity (release-hardening Task 4; REQ-B1.1..REQ-B1.4,
#     D-3, D-12). On a partial-publish resume (origin tag present, Release
#     absent) the tag is hardened before the Release is created: the ORIGIN
#     tag object is fetched to a reserved verification ref, its target commit is
#     asserted == the recomputed release SHA, and its signature is re-verified
#     keyed off the origin tag's OWN signedness. A resume that finds the Release
#     already present but the merged PR still `autorelease: pending` performs
#     only the idempotent relabel instead of dying "already published".
# ===========================================================================

# 11a. REQ-B1.1 — a matching-SHA fresh-clone resume (origin tag present, NO local
#      tag, Release absent) fetches the origin object, matches, and proceeds; the
#      reserved verification ref is cleaned up afterward.
r="$tmp/resume-match-freshclone"
new_repo "$r"
seed_version "$r" 0.1.0
gc "$r" tag v0.1.0 # lightweight tag on the release commit
gc "$r" push -q origin v0.1.0 2>/dev/null
gc "$r" tag -d v0.1.0 >/dev/null # fresh-clone: no local tag lingers
run_publish "$r" GH_CI=green GH_RELEASE_EXISTS=0
assert_eq "resume/match: exit 0 (matching origin tag resumes)" "$RC" "0"
assert_contains "resume/match: reports a resume" "$OUT" "resumed"
want "resume/match: gh release create invoked" gh_called "$LOG" "release create"
want "resume/match: the verification ref is cleaned up" verify_ref_gone "$r" v0.1.0

# 11b. REQ-B1.1 — a mismatched-SHA resume refuses, NAMING BOTH SHAs, and creates
#      no Release. The origin tag points at a later commit than the recomputed
#      release SHA (the "main was rewritten under a pushed tag" hole).
r="$tmp/resume-mismatch"
new_repo "$r"
seed_version "$r" 0.1.0
RS_SHA=$(git -C "$r" rev-parse HEAD) # release SHA (0.1.0 introduced here)
gc "$r" commit -q --allow-empty -m "later, still 0.1.0"
TAG_SHA=$(git -C "$r" rev-parse HEAD) # a later commit
gc "$r" push -q origin main 2>/dev/null
gc "$r" tag v0.1.0 # origin tag lands on the LATER commit
gc "$r" push -q origin v0.1.0 2>/dev/null
gc "$r" tag -d v0.1.0 >/dev/null
run_publish "$r" GH_CI=green GH_RELEASE_EXISTS=0
assert_ne "resume/mismatch: exits non-zero (SHA assertion refuses)" "$RC" "0"
assert_contains "resume/mismatch: names the recomputed release SHA" "$ERR" "$RS_SHA"
assert_contains "resume/mismatch: names the origin tag's target SHA" "$ERR" "$TAG_SHA"
deny "resume/mismatch: no Release created on a mismatch" gh_called "$LOG" "release create"
want "resume/mismatch: the verification ref is cleaned up even on refusal" verify_ref_gone "$r" v0.1.0

# 11c. REQ-B1.1 — a lingering same-named LOCAL tag does not shadow the origin
#      object: the local tag points at a WRONG commit while origin points at the
#      correct release SHA. The resume must read ORIGIN (proceed), not the local
#      tag (which would spuriously mismatch and refuse).
r="$tmp/resume-no-shadow"
new_repo "$r"
seed_version "$r" 0.1.0
RS_SHA=$(git -C "$r" rev-parse HEAD)
gc "$r" tag v0.1.0 "$RS_SHA" # local + origin tag on the release SHA
gc "$r" push -q origin v0.1.0 2>/dev/null
gc "$r" commit -q --allow-empty -m "later, still 0.1.0"
gc "$r" push -q origin main 2>/dev/null
gc "$r" tag -f v0.1.0 >/dev/null # move the LOCAL tag to the later commit
run_publish "$r" GH_CI=green GH_RELEASE_EXISTS=0
assert_eq "resume/no-shadow: exit 0 (reads the origin object, not the local tag)" "$RC" "0"
want "resume/no-shadow: gh release create invoked" gh_called "$LOG" "release create"

# 11d. REQ-B1.3 — a resume SKIPS the creation gates. Proof: with GH_CI=red a fresh
#      publish would refuse at the CI gate, but a resume proceeds (the CI gate is
#      not evaluated) and never issues the CI GraphQL query.
r="$tmp/resume-skips-gates"
new_repo "$r"
seed_version "$r" 0.1.0
gc "$r" tag v0.1.0
gc "$r" push -q origin v0.1.0 2>/dev/null # local tag kept (lingering)
run_publish "$r" GH_CI=red GH_RELEASE_EXISTS=0
assert_eq "resume/skips-gates: exit 0 despite red CI (creation CI gate skipped)" "$RC" "0"
deny "resume/skips-gates: no CI GraphQL query issued on resume" gh_called "$LOG" "graphql"
want "resume/skips-gates: the Release is still created" gh_called "$LOG" "release create"

# 11f. REQ-B1.2 — under `require`, a LIGHTWEIGHT origin tag (unsigned, no tag
#      object) is refused and never fed to signature verification.
r="$tmp/resume-require-lightweight"
new_repo "$r"
seed_version "$r" 0.1.0
gc "$r" tag v0.1.0 # lightweight → treated as unsigned
gc "$r" push -q origin v0.1.0 2>/dev/null
gc "$r" tag -d v0.1.0 >/dev/null
mkdir -p "$r/.claude"
printf 'require_signed_tags: require\n' >"$r/.claude/planwright.local.yml"
run_publish "$r" GH_CI=green GH_RELEASE_EXISTS=0
assert_ne "resume/require-lightweight: exits non-zero (unsigned refused under require)" "$RC" "0"
assert_contains "resume/require-lightweight: refuses on the no-signature branch (not a spurious SHA mismatch)" "$ERR" "carries no signature"
deny "resume/require-lightweight: no Release created" gh_called "$LOG" "release create"

# 11j. REQ-B1.2 — under `auto`, an UNSIGNED annotated origin tag is accepted (the
#      SHA is already pinned; auto is best-effort).
r="$tmp/resume-auto-unsigned"
new_repo "$r"
seed_version "$r" 0.1.0
gi "$r" tag -a -m v0.1.0 v0.1.0 # unsigned annotated tag object (config isolated so a machine-global tag.gpgsign can't sign it)
gc "$r" push -q origin v0.1.0 2>/dev/null
gc "$r" tag -d v0.1.0 >/dev/null
run_publish "$r" GH_CI=green GH_RELEASE_EXISTS=0
assert_eq "resume/auto-unsigned: exit 0 (auto accepts an unsigned tag)" "$RC" "0"
want "resume/auto-unsigned: gh release create invoked" gh_called "$LOG" "release create"

# --- REQ-B1.2 signature re-verify against real signed tags (needs ssh-keygen) --
if command -v ssh-keygen >/dev/null 2>&1; then
  # 11e. require + a VALID signed origin tag (fresh-clone: no local tag) → the
  #      re-verify runs against the fetched origin object and the resume proceeds.
  r="$tmp/resume-require-signed-ok"
  new_repo "$r"
  seed_version "$r" 0.1.0
  configure_signing "$r"          # allowed-signers = the signing key
  gi "$r" tag -s -m v0.1.0 v0.1.0 # signed annotated tag (config isolated)
  gi "$r" push -q origin v0.1.0 2>/dev/null
  gi "$r" tag -d v0.1.0 >/dev/null # fresh-clone: verify the FETCHED object
  mkdir -p "$r/.claude"
  printf 'require_signed_tags: require\n' >"$r/.claude/planwright.local.yml"
  run_publish "$r" GH_CI=green GH_RELEASE_EXISTS=0
  assert_eq "resume/require-signed-ok: exit 0 (valid signature verifies)" "$RC" "0"
  want "resume/require-signed-ok: gh release create invoked" gh_called "$LOG" "release create"
  want "resume/require-signed-ok: the verification ref is cleaned up" verify_ref_gone "$r" v0.1.0

  # 11g. require + a signed tag whose signature does NOT verify (allowed-signers is
  #      a DIFFERENT key) → refuse before creating the Release.
  r="$tmp/resume-require-signed-bad"
  new_repo "$r"
  seed_version "$r" 0.1.0
  mkdir -p "$r.keys"
  ssh-keygen -q -t ed25519 -N '' -C other -f "$r.keys/otherkey" 2>/dev/null
  configure_signing "$r" "$r.keys/otherkey.pub" # sign with key, allow otherkey
  gi "$r" tag -s -m v0.1.0 v0.1.0
  gi "$r" push -q origin v0.1.0 2>/dev/null
  gi "$r" tag -d v0.1.0 >/dev/null
  mkdir -p "$r/.claude"
  printf 'require_signed_tags: require\n' >"$r/.claude/planwright.local.yml"
  run_publish "$r" GH_CI=green GH_RELEASE_EXISTS=0
  assert_ne "resume/require-signed-bad: exits non-zero (invalid signature refused)" "$RC" "0"
  assert_contains "resume/require-signed-bad: refuses on the signature-verify branch (not a spurious SHA mismatch)" "$ERR" "signature verification failed"
  deny "resume/require-signed-bad: no Release created" gh_called "$LOG" "release create"

  # 11h. auto + a VALID signed origin tag → the re-verify runs (auto verifies iff
  #      signed) and the resume proceeds.
  r="$tmp/resume-auto-signed-ok"
  new_repo "$r"
  seed_version "$r" 0.1.0
  configure_signing "$r"
  gi "$r" tag -s -m v0.1.0 v0.1.0
  gi "$r" push -q origin v0.1.0 2>/dev/null
  gi "$r" tag -d v0.1.0 >/dev/null
  run_publish "$r" GH_CI=green GH_RELEASE_EXISTS=0
  assert_eq "resume/auto-signed-ok: exit 0 (auto verifies a signed tag, valid)" "$RC" "0"
  want "resume/auto-signed-ok: gh release create invoked" gh_called "$LOG" "release create"

  # 11i. auto + a signed tag whose signature does NOT verify → refuse (a
  #      present-but-invalid signature is refused even under auto).
  r="$tmp/resume-auto-signed-bad"
  new_repo "$r"
  seed_version "$r" 0.1.0
  mkdir -p "$r.keys"
  ssh-keygen -q -t ed25519 -N '' -C other -f "$r.keys/otherkey" 2>/dev/null
  configure_signing "$r" "$r.keys/otherkey.pub"
  gi "$r" tag -s -m v0.1.0 v0.1.0
  gi "$r" push -q origin v0.1.0 2>/dev/null
  gi "$r" tag -d v0.1.0 >/dev/null
  run_publish "$r" GH_CI=green GH_RELEASE_EXISTS=0
  assert_ne "resume/auto-signed-bad: exits non-zero (invalid signature refused under auto)" "$RC" "0"
  deny "resume/auto-signed-bad: no Release created" gh_called "$LOG" "release create"

  # 11k. never + a signed tag whose signature does NOT verify → the re-verify is
  #      SKIPPED and the resume proceeds (the operator opted out).
  r="$tmp/resume-never-signed-bad"
  new_repo "$r"
  seed_version "$r" 0.1.0
  mkdir -p "$r.keys"
  ssh-keygen -q -t ed25519 -N '' -C other -f "$r.keys/otherkey" 2>/dev/null
  configure_signing "$r" "$r.keys/otherkey.pub"
  gi "$r" tag -s -m v0.1.0 v0.1.0
  gi "$r" push -q origin v0.1.0 2>/dev/null
  gi "$r" tag -d v0.1.0 >/dev/null
  mkdir -p "$r/.claude"
  printf 'require_signed_tags: never\n' >"$r/.claude/planwright.local.yml"
  run_publish "$r" GH_CI=green GH_RELEASE_EXISTS=0
  assert_eq "resume/never-signed-bad: exit 0 (never skips the re-verify)" "$RC" "0"
  want "resume/never-signed-bad: gh release create invoked" gh_called "$LOG" "release create"
else
  echo "skip: ssh-keygen unavailable — resume signature sub-tests (11e/g/h/i/k) skipped"
fi

# 11l. REQ-B1.4 — a resume where the Release ALREADY exists but the merged release
#      PR is still `autorelease: pending` performs the pending -> tagged relabel
#      (does NOT die "already published" first) and does not re-create the Release.
r="$tmp/resume-relabel-pending"
new_repo "$r"
seed_version "$r" 0.1.0
gc "$r" tag v0.1.0
gc "$r" push -q origin v0.1.0 2>/dev/null
run_publish "$r" GH_CI=green GH_RELEASE_EXISTS=1 GH_LABEL_TAGGED_EXISTS=1 \
  GH_PR_JSON='[{"number":55,"labels":[{"name":"autorelease: pending"}]}]'
assert_eq "resume/relabel-pending: exit 0 (no 'already published' death)" "$RC" "0"
case "$ERR" in
  *"already published"*) bad "resume/relabel-pending: dies 'already published' before the relabel" ;;
  *) pass "resume/relabel-pending: does not die 'already published'" ;;
esac
want "resume/relabel-pending: the pending PR is relabeled pending -> tagged" \
  gh_called "$LOG" "pr edit 55 --add-label autorelease: tagged --remove-label autorelease: pending"
deny "resume/relabel-pending: the present Release is not re-created" gh_called "$LOG" "release create"

# 11m. REQ-B1.4 — a resume where the Release exists and the PR is ALREADY `tagged`
#      exits 0, does not die, and does not re-create the Release. The relabel is
#      idempotent at the GitHub layer but NOT suppressed: with no PR carrying
#      `autorelease: pending`, the relabel jq falls back to `.[0].number`, so the
#      script still issues a (harmless) `pr edit` that re-adds `tagged` / re-removes
#      `pending` on the already-tagged PR — a no-op on GitHub, not a skipped call.
r="$tmp/resume-relabel-tagged"
new_repo "$r"
seed_version "$r" 0.1.0
gc "$r" tag v0.1.0
gc "$r" push -q origin v0.1.0 2>/dev/null
run_publish "$r" GH_CI=green GH_RELEASE_EXISTS=1 GH_LABEL_TAGGED_EXISTS=1 \
  GH_PR_JSON='[{"number":66,"labels":[{"name":"autorelease: tagged"}]}]'
assert_eq "resume/relabel-tagged: exit 0 (idempotent, already tagged)" "$RC" "0"
case "$ERR" in
  *"already published"*) bad "resume/relabel-tagged: dies 'already published'" ;;
  *) pass "resume/relabel-tagged: does not die 'already published'" ;;
esac
deny "resume/relabel-tagged: the present Release is not re-created" gh_called "$LOG" "release create"
want "resume/relabel-tagged: the redundant relabel is a harmless GitHub-layer no-op (jq falls back to the tagged PR)" \
  gh_called "$LOG" "pr edit 66 --add-label autorelease: tagged --remove-label autorelease: pending"

# 11n. REQ-B1.2 (trust-boundary hardening) — a MALFORMED/unreadable require_signed_tags
#      config on the resume signature path FAILS CLOSED, never silently downgrades
#      to auto. Fault-inject config-get exit 4 with a malformed repo-tracked
#      overlay (a block sequence is not flat 'key: value' YAML). Even though the
#      overlay *intends* `require`, the parse failure must NOT be swallowed into an
#      auto fallback that would accept the unsigned lightweight origin tag and
#      create a Release.
r="$tmp/resume-malformed-config"
new_repo "$r"
seed_version "$r" 0.1.0
gc "$r" tag v0.1.0 # lightweight (unsigned) origin tag on the release commit
gc "$r" push -q origin v0.1.0 2>/dev/null
gc "$r" tag -d v0.1.0 >/dev/null
mkdir -p "$r/.claude"
# Malformed team-shared overlay: `require` is present, but the block sequence
# makes the whole file non-flat -> config-get.sh exits 4 (empty stdout).
printf 'require_signed_tags: require\nbroken_list:\n  - a\n  - b\n' >"$r/.claude/planwright.yml"
run_publish "$r" GH_CI=green GH_RELEASE_EXISTS=0
assert_ne "resume/malformed-config: exits non-zero (fail-closed, no silent auto downgrade)" "$RC" "0"
assert_contains "resume/malformed-config: names the malformed-config resume gate" "$ERR" "malformed or unreadable"
deny "resume/malformed-config: no Release created on a malformed signature-mode config" gh_called "$LOG" "release create"
want "resume/malformed-config: the verification ref is cleaned up on the fail-closed refusal" verify_ref_gone "$r" v0.1.0

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "PASS: test-release-publish.sh"
