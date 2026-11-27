# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154 # OUT and CODE are read, and passes and failures set, by the sourcing test
# Shared fixture for the ready-flip suites: the gh stub, the throwaway origin and
# unit clone, and the helpers that drive scripts/ready-flip.sh. The sourcing test
# sets REPO_ROOT, HELPER and STEP_RECORD, and defines passes, failures, pass,
# fail, check and not, before sourcing. Sourcing creates SANDBOX and installs the
# only EXIT trap (it removes SANDBOX), builds the template fixture, and exits
# 1 when the helper is missing; it leaves F, GHS, BRANCH and TASKS for the
# cases to read.

unset CDPATH
[ -r "$REPO_ROOT/tests/lib/emitter-lint.sh" ] || {
  echo "FAIL: tests/lib/emitter-lint.sh missing" >&2
  exit 1
}
# shellcheck source=tests/lib/emitter-lint.sh
. "$REPO_ROOT/tests/lib/emitter-lint.sh"

SANDBOX=$(mktemp -d "${TMPDIR:-/tmp}/ready-flip.XXXXXX") || exit 1
trap 'rm -rf "$SANDBOX"' EXIT
STUBBIN="$SANDBOX/bin"
mkdir -p "$STUBBIN" "$SANDBOX/nohooks" "$SANDBOX/noadopter"

# The gh stub. Calls are logged one per line; answers come from files under
# $GHS. The PR head is read from the bare origin, never from a file.
cat >"$STUBBIN/gh" <<'GHSTUB'
#!/bin/sh
{
  printf 'CALL'
  for a in "$@"; do printf ' %s' "$a"; done
  printf '\n'
} >>"$GHS/log"
head=$(git --git-dir="$GHS_ORIGIN" rev-parse --verify -q "refs/heads/$GHS_BRANCH" 2>/dev/null)
draft=true
[ ! -f "$GHS/ready" ] || draft=false
case "$1 $2" in
  'pr view')
    case "$*" in
      *statusCheckRollup*)
        n=0
        [ ! -f "$GHS/rollup_n" ] || n=$(cat "$GHS/rollup_n")
        n=$((n + 1))
        echo "$n" >"$GHS/rollup_n"
        if { [ -f "$GHS/rollup_fail_until" ] && [ "$n" -le "$(cat "$GHS/rollup_fail_until")" ]; } \
          || { [ -f "$GHS/rollup_fail_at" ] && [ "$n" = "$(cat "$GHS/rollup_fail_at")" ]; }; then
          echo 'HTTP 502: Bad Gateway' >&2
          exit 1
        fi
        if [ -f "$GHS/rollup_garbage_at" ] && [ "$n" = "$(cat "$GHS/rollup_garbage_at")" ]; then
          echo 'not json'
          exit 0
        fi
        [ ! -f "$GHS/head_override" ] || head=$(cat "$GHS/head_override")
        # head_lag_until reports a stale head for the first n reads.
        [ ! -f "$GHS/head_lag_until" ] || [ "$n" -gt "$(cat "$GHS/head_lag_until")" ] \
          || head=0123456789012345678901234567890123456789
        ci=$(cat "$GHS/ci")
        # ci_green_from turns the rollup green from the nth read on, to the
        # value in ci_then when one is given.
        [ ! -f "$GHS/ci_green_from" ] || [ "$n" -lt "$(cat "$GHS/ci_green_from")" ] || ci=$(cat "$GHS/ci_then" 2>/dev/null || echo green)
        case $ci in
          green) roll='[{"__typename":"CheckRun","name":"test","status":"COMPLETED","conclusion":"SUCCESS"},{"__typename":"StatusContext","context":"lint","state":"SUCCESS"}]' ;;
          failing) roll='[{"__typename":"CheckRun","name":"test","status":"COMPLETED","conclusion":"FAILURE"}]' ;;
          pending) roll='[{"__typename":"CheckRun","name":"test","status":"IN_PROGRESS","conclusion":""}]' ;;
          pending-macos) roll='[{"__typename":"CheckRun","name":"test","status":"COMPLETED","conclusion":"SUCCESS"},{"__typename":"CheckRun","name":"macos-suite (shard 2/4)","workflowName":"ci","status":"QUEUED","conclusion":"","startedAt":"0001-01-01T00:00:00Z"}]' ;;
          none) roll='[]' ;;
          own-status-red) roll='[{"__typename":"CheckRun","name":"test","status":"COMPLETED","conclusion":"SUCCESS"},{"__typename":"StatusContext","context":"planwright/pre-ready-flip","state":"FAILURE"},{"__typename":"StatusContext","context":"planwright/pre-spec-ready-flip","state":"PENDING"}]' ;;
          own-status-only) roll='[{"__typename":"StatusContext","context":"planwright/pre-ready-flip","state":"SUCCESS"}]' ;;
          superseded-red) roll='[{"__typename":"CheckRun","name":"test","workflowName":"ci","status":"COMPLETED","conclusion":"SUCCESS","startedAt":"2026-11-05T19:30:00Z"},{"__typename":"CheckRun","name":"test","workflowName":"ci","status":"COMPLETED","conclusion":"FAILURE","startedAt":"2026-11-05T19:00:00Z"}]' ;;
          tied-red) roll='[{"__typename":"CheckRun","name":"test","workflowName":"ci","status":"COMPLETED","conclusion":"FAILURE","startedAt":"2026-11-05T19:30:00Z"},{"__typename":"CheckRun","name":"test","workflowName":"ci","status":"COMPLETED","conclusion":"SUCCESS","startedAt":"2026-11-05T19:30:00Z"}]' ;;
          superseded-red-first) roll='[{"__typename":"CheckRun","name":"test","workflowName":"ci","status":"COMPLETED","conclusion":"FAILURE","startedAt":"2026-11-05T19:00:00Z"},{"__typename":"CheckRun","name":"test","workflowName":"ci","status":"COMPLETED","conclusion":"SUCCESS","startedAt":"2026-11-05T19:30:00Z"}]' ;;
          capped) roll=$(i=0; printf '['; while [ $i -lt 100 ]; do [ $i = 0 ] || printf ','; printf '{"__typename":"CheckRun","name":"c%s","workflowName":"ci","status":"COMPLETED","conclusion":"SUCCESS"}' "$i"; i=$((i + 1)); done; printf ']') ;;
          window-lock-red) roll='[{"__typename":"CheckRun","name":"test","workflowName":"ci","status":"COMPLETED","conclusion":"SUCCESS"},{"__typename":"CheckRun","name":"window-lock","workflowName":"release-window","status":"COMPLETED","conclusion":"FAILURE"}]' ;;
          window-lock-pending) roll='[{"__typename":"CheckRun","name":"test","workflowName":"ci","status":"COMPLETED","conclusion":"SUCCESS"},{"__typename":"CheckRun","name":"window-lock","workflowName":"release-window","status":"IN_PROGRESS","conclusion":""}]' ;;
          window-lock-and-red) roll='[{"__typename":"CheckRun","name":"test","workflowName":"ci","status":"COMPLETED","conclusion":"FAILURE"},{"__typename":"CheckRun","name":"window-lock","workflowName":"release-window","status":"COMPLETED","conclusion":"FAILURE"}]' ;;
          window-lock-foreign) roll='[{"__typename":"CheckRun","name":"test","workflowName":"ci","status":"COMPLETED","conclusion":"SUCCESS"},{"__typename":"CheckRun","name":"window-lock","workflowName":"ci","status":"COMPLETED","conclusion":"FAILURE"}]' ;;
          window-lock-only) roll='[{"__typename":"CheckRun","name":"window-lock","workflowName":"release-window","status":"COMPLETED","conclusion":"FAILURE"}]' ;;
          pr-agent-green) roll='[{"__typename":"CheckRun","name":"test","workflowName":"ci","status":"COMPLETED","conclusion":"SUCCESS"},{"__typename":"CheckRun","name":"PR-Agent","workflowName":"PR-Agent","status":"COMPLETED","conclusion":"SUCCESS"}]' ;;
          pr-agent-skipped) roll='[{"__typename":"CheckRun","name":"test","workflowName":"ci","status":"COMPLETED","conclusion":"SUCCESS"},{"__typename":"CheckRun","name":"PR-Agent","workflowName":"PR-Agent","status":"COMPLETED","conclusion":"SKIPPED"}]' ;;
          pr-agent-failed) roll='[{"__typename":"CheckRun","name":"test","workflowName":"ci","status":"COMPLETED","conclusion":"SUCCESS"},{"__typename":"CheckRun","name":"PR-Agent","workflowName":"PR-Agent","status":"COMPLETED","conclusion":"FAILURE"}]' ;;
          pr-agent-pending) roll='[{"__typename":"CheckRun","name":"test","workflowName":"ci","status":"COMPLETED","conclusion":"SUCCESS"},{"__typename":"CheckRun","name":"PR-Agent","workflowName":"PR-Agent","status":"IN_PROGRESS","conclusion":""}]' ;;
          own-name-checkrun-red) roll='[{"__typename":"CheckRun","name":"test","status":"COMPLETED","conclusion":"SUCCESS"},{"__typename":"CheckRun","name":"planwright/pre-ready-flip","status":"COMPLETED","conclusion":"FAILURE"}]' ;;
        esac
        printf '{"headRefOid":"%s","statusCheckRollup":%s}\n' "$head" "$roll"
        ;;
      *'--jq .headRefOid'*)
        h=0
        [ ! -f "$GHS/pin_n" ] || h=$(cat "$GHS/pin_n")
        h=$((h + 1))
        echo "$h" >"$GHS/pin_n"
        [ ! -f "$GHS/head_override" ] || head=$(cat "$GHS/head_override")
        [ ! -f "$GHS/head_at_flip" ] || head=$(cat "$GHS/head_at_flip")
        # head_after_record moves the head from the second re-read on.
        [ ! -f "$GHS/head_after_record" ] || [ "$h" -lt 2 ] || head=$(cat "$GHS/head_after_record")
        printf '%s\n' "$head"
        ;;
      *mergeable*)
        printf '{"baseRefName":"main","headRefOid":"%s","isDraft":%s,"mergeable":"MERGEABLE","url":"https://github.com/acme/widgets/pull/42"}\n' "$head" "$draft"
        ;;
      *)
        if [ -f "$GHS/nopr" ]; then
          echo "no pull requests found for branch \"$GHS_BRANCH\"" >&2
          exit 1
        fi
        l=0
        [ ! -f "$GHS/lookup_n" ] || l=$(cat "$GHS/lookup_n")
        l=$((l + 1))
        echo "$l" >"$GHS/lookup_n"
        if [ -f "$GHS/lookup_fail_until" ] && [ "$l" -le "$(cat "$GHS/lookup_fail_until")" ]; then
          echo 'HTTP 502: Bad Gateway' >&2
          exit 1
        fi
        base=main
        [ ! -f "$GHS/base" ] || base=$(cat "$GHS/base")
        fork=false
        [ ! -f "$GHS/fork" ] || fork=true
        printf '{"number":42,"isDraft":%s,"state":"OPEN","baseRefName":"%s","headRefName":"%s","headRefOid":"%s","isCrossRepository":%s}\n' "$draft" "$base" "$GHS_BRANCH" "$head" "$fork"
        ;;
    esac
    ;;
  'api '*)
    if [ -f "$GHS/behind" ]; then cat "$GHS/behind"; else echo 0; fi
    ;;
  'pr comment')
    c=0
    [ ! -f "$GHS/comments" ] || c=$(cat "$GHS/comments")
    c=$((c + 1))
    echo "$c" >"$GHS/comments"
    prev=''
    for a in "$@"; do
      [ "$prev" != --body-file ] || cp "$a" "$GHS/comment.$c"
      prev=$a
    done
    rc=0
    [ ! -f "$GHS/comment_rc" ] || rc=$(cat "$GHS/comment_rc")
    exit "$rc"
    ;;
  'pr ready')
    rc=0
    [ ! -f "$GHS/ready_rc" ] || rc=$(cat "$GHS/ready_rc")
    [ "$rc" != 0 ] || : >"$GHS/ready"
    exit "$rc"
    ;;
  *) exit 3 ;;
esac
GHSTUB
chmod +x "$STUBBIN/gh"

BRANCH=planwright/demo/task-1
TASKS=specs/demo/tasks.md

gitf() { git -C "$F/wt" "$@"; }

write_tasks() { # <awaiting-input body lines...>
  {
    printf '# Demo — Tasks\n\n**Status:** Ready\n**Format-version:** 2\n\n## Tasks\n\n'
    printf '### Task 1 — One\n\n- **Deliverables:** x\n\n### Task 2 — Two\n\n- **Deliverables:** y\n\n'
    printf '## Awaiting input\n\n'
    if [ "$#" = 0 ]; then printf '(none yet)\n'; else printf '%s\n' "$@"; fi
    printf '\n## Deferred\n\n(none yet)\n'
  } >"$F/wt/$TASKS"
}

# record_review — a convergence completion record naming the current head.
record_review() {
  local run
  run=$(/bin/sh "$STEP_RECORD" --worktree "$F/wt" new-run) || return 1
  /bin/sh "$STEP_RECORD" --worktree "$F/wt" write --completion --run "$run" \
    --point convergence --head "$(gitf rev-parse HEAD)" >/dev/null
}

# fixture [<awaiting-input lines on main>...] — a fresh origin and unit clone.
# The plain fixture is copied from one built template, which keeps the suite
# inside its time budget; a fixture with a base park is built from scratch.
TEMPLATE=''
fixture() {
  if [ "$#" = 0 ] && [ -n "$TEMPLATE" ]; then
    F=$(mktemp -d "$SANDBOX/fx.XXXXXX")
    cp -R "$TEMPLATE/." "$F/"
    gitf remote set-url origin "$F/origin.git"
    GHS="$F/gh"
    return
  fi
  build_fixture "$@"
}
build_fixture() {
  F=$(mktemp -d "$SANDBOX/fx.XXXXXX")
  git init -q --bare -b main "$F/origin.git"
  git clone -q "$F/origin.git" "$F/wt" 2>/dev/null
  gitf config user.name 'Fixture'
  gitf config user.email 'fixture@example.invalid'
  gitf config commit.gpgsign false
  gitf config core.hooksPath "$SANDBOX/nohooks"
  gitf checkout -q -b main 2>/dev/null
  mkdir -p "$F/wt/specs/demo"
  printf '.claude/\n' >"$F/wt/.gitignore"
  write_tasks
  gitf add -A
  gitf commit -q -m 'chore: seed'
  # The unit branch is cut before any human park lands on main.
  if [ "$#" -gt 0 ]; then
    write_tasks "$@"
    gitf commit -q -am 'chore: a human park on main'
    gitf push -q origin main 2>/dev/null
    gitf checkout -q -b "$BRANCH" HEAD~1
  else
    gitf push -q origin main 2>/dev/null
    gitf checkout -q -b "$BRANCH"
  fi
  printf 'work\n' >"$F/wt/feature.txt"
  gitf add feature.txt
  gitf commit -q -m 'feat: the unit'
  gitf push -q -u origin "$BRANCH" 2>/dev/null
  record_review
  GHS="$F/gh"
  mkdir -p "$GHS"
  echo green >"$GHS/ci"
  : >"$GHS/log"
}

set_policy() { # <value>
  mkdir -p "$F/wt/.claude"
  printf 'ready_flip_policy: %s\nready_flip_ci_wait: 30s\n' "$1" >"$F/wt/.claude/planwright.local.yml"
}

# runs_pr_agent — the unit head's CI runs the PR-Agent image, as this
# repository's does, so the flip waits for its run on the head. Committed,
# pushed and reviewed, so the head stays the converged one.
runs_pr_agent() {
  mkdir -p "$F/wt/.github/workflows"
  printf 'jobs:\n  review:\n    steps:\n      - env:\n          PR_AGENT_IMAGE: pragent/pr-agent@sha256:0\n' >"$F/wt/.github/workflows/pr-agent.yml"
  gitf add .github/workflows/pr-agent.yml
  gitf commit -q -m 'ci: the bot review'
  gitf push -q origin "$BRANCH" 2>/dev/null
  record_review
}

# run_polled <poll seconds> <max polls> <args...> — the helper from the unit
# clone, stub first on PATH. The helper reads <max polls> only at a poll of 0;
# pass an empty one otherwise.
run_polled() {
  local poll=$1 max=$2
  shift 2
  OUT=$(cd "$F/wt" && env PATH="$STUBBIN:$PATH" GHS="$GHS" GHS_ORIGIN="$F/origin.git" \
    GHS_BRANCH="$BRANCH" PLANWRIGHT_REPO_ROOT="$F/wt" PLANWRIGHT_LOCAL_CONFIG= \
    PLANWRIGHT_ADOPTER_OVERLAY="$SANDBOX/noadopter" PLANWRIGHT_READY_FLIP_POLL_SECONDS="$poll" \
    PLANWRIGHT_READY_FLIP_MAX_POLLS="$max" PLANWRIGHT_READY_GUARD_RETRY_DELAY=0 \
    /bin/bash "$HELPER" "$@" 2>&1)
  CODE=$?
}
run_helper() { run_polled 0 3 "$@"; }

calls() { grep -c "^CALL $1" "$GHS/log" 2>/dev/null || true; }
rollups() { grep -c 'statusCheckRollup' "$GHS/log" 2>/dev/null || true; }
first_line_of() { grep -n "^CALL $1" "$GHS/log" | head -1 | cut -d: -f1; }
origin_tasks() { git --git-dir="$F/origin.git" show "refs/heads/$BRANCH:$TASKS"; }
origin_head() { git --git-dir="$F/origin.git" rev-parse "refs/heads/$BRANCH"; }
bullet() { origin_tasks | grep '^- \*\*Task 1\*\*'; }
leads() { origin_tasks | grep -o 'pending ready-flip:' | wc -l | tr -d ' '; }
placeholder_in_section() { origin_tasks | sed -n '/^## Awaiting input/,/^## Deferred/p' | grep -q 'none yet'; }
head_trailer_is() { git --git-dir="$F/origin.git" log -1 --format=%B "refs/heads/$BRANCH" | grep -qx "$1"; }
commits_since() { git --git-dir="$F/origin.git" rev-list --count "$1..refs/heads/$BRANCH"; }
changed_since() { git --git-dir="$F/origin.git" diff --name-only "$1" "refs/heads/$BRANCH"; }

if [ ! -f "$HELPER" ]; then
  fail "the helper exists at scripts/ready-flip.sh"
  printf '%s: %s passed, %s failed\n' "${0##*/}" "$passes" "$failures" >&2
  exit 1
fi

build_fixture
TEMPLATE=$F
