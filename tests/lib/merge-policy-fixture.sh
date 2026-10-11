#!/bin/bash
# Shared fixture for the merge-policy suites (tests/test-merge-class.sh,
# tests/test-merge-admitted.sh): a throwaway bare origin, a unit clone on a
# task branch with a convergence record naming its head, and a stub `gh` that
# answers from files under $GHS and logs every call. The PR head is whatever
# the bare origin holds for the branch, so a push moves it the way GitHub
# would. Nothing here reaches a real host.
#
# The sourcing suite defines pass/fail and sets REPO_ROOT and SANDBOX first.

MP_STEP_RECORD="$REPO_ROOT/scripts/step-record.sh"
MP_STUBBIN="$SANDBOX/bin"
mkdir -p "$MP_STUBBIN" "$SANDBOX/nohooks" "$SANDBOX/noadopter"

cat >"$MP_STUBBIN/gh" <<'GHSTUB'
#!/bin/sh
{
  printf 'CALL'
  for a in "$@"; do printf ' %s' "$a"; done
  printf '\n'
} >>"$GHS/log"
head=$(git --git-dir="$GHS_ORIGIN" rev-parse --verify -q "refs/heads/$GHS_BRANCH" 2>/dev/null)
[ ! -f "$GHS/head_override" ] || head=$(cat "$GHS/head_override")
draft=true
[ ! -f "$GHS/ready" ] || draft=false
hname=$GHS_BRANCH
[ ! -f "$GHS/head_name" ] || hname=$(cat "$GHS/head_name")
fork=false
[ ! -f "$GHS/fork" ] || fork=true
case "$1 $2" in
  'pr view')
    case "$*" in
      *statusCheckRollup*)
        n=0
        [ ! -f "$GHS/rollup_n" ] || n=$(cat "$GHS/rollup_n")
        echo "$((n + 1))" >"$GHS/rollup_n"
        case $(cat "$GHS/ci") in
          green) roll='[{"__typename":"CheckRun","name":"test","status":"COMPLETED","conclusion":"SUCCESS"}]' ;;
          failing) roll='[{"__typename":"CheckRun","name":"test","status":"COMPLETED","conclusion":"FAILURE"}]' ;;
          *) roll='[{"__typename":"CheckRun","name":"test","status":"IN_PROGRESS","conclusion":""}]' ;;
        esac
        printf '{"headRefOid":"%s","statusCheckRollup":%s}\n' "$head" "$roll"
        ;;
      *'--jq .headRefOid'*)
        h=0
        [ ! -f "$GHS/pin_n" ] || h=$(cat "$GHS/pin_n")
        h=$((h + 1))
        echo "$h" >"$GHS/pin_n"
        printf '%s\n' "$head"
        ;;
      *author*)
        printf '%s\n' "$(cat "$GHS/author" 2>/dev/null || echo operator)"
        ;;
      *mergeable*)
        printf '{"baseRefName":"main","headRefOid":"%s","isDraft":%s,"mergeable":"MERGEABLE","url":"https://github.com/acme/widgets/pull/42"}\n' "$head" "$draft"
        ;;
      *)
        if [ -f "$GHS/nopr" ]; then
          echo "no pull requests found for branch \"$GHS_BRANCH\"" >&2
          exit 1
        fi
        # head_after_eval reports another head from the nth lookup on: a
        # commit landed between evaluation and the merge call.
        l=0
        [ ! -f "$GHS/lookup_n" ] || l=$(cat "$GHS/lookup_n")
        l=$((l + 1))
        echo "$l" >"$GHS/lookup_n"
        if [ -f "$GHS/head_after_eval" ] && [ "$l" -ge "$(cat "$GHS/head_after_eval_from")" ]; then
          head=$(cat "$GHS/head_after_eval")
        fi
        printf '{"number":42,"isDraft":%s,"state":"OPEN","baseRefName":"main","headRefName":"%s","headRefOid":"%s","isCrossRepository":%s}\n' \
          "$draft" "$hname" "$head" "$fork"
        ;;
    esac
    ;;
  'api user')
    if [ -f "$GHS/login" ]; then cat "$GHS/login"; else echo operator; fi
    ;;
  'api '*)
    if [ -f "$GHS/behind" ]; then cat "$GHS/behind"; else echo 0; fi
    ;;
  'repo view')
    [ ! -f "$GHS/repo_rc" ] || exit "$(cat "$GHS/repo_rc")"
    methods=squash
    [ ! -f "$GHS/methods" ] || methods=$(cat "$GHS/methods")
    m=false s=false r=false
    case " $methods " in *' merge '*) m=true ;; esac
    case " $methods " in *' squash '*) s=true ;; esac
    case " $methods " in *' rebase '*) r=true ;; esac
    printf '{"mergeCommitAllowed":%s,"squashMergeAllowed":%s,"rebaseMergeAllowed":%s}\n' "$m" "$s" "$r"
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
    # comment_rc_at fails only the nth comment.
    [ ! -f "$GHS/comment_rc_at" ] || [ "$c" != "$(cat "$GHS/comment_rc_at")" ] || rc=1
    # on_comment.<n> runs after the nth comment: the world moving between a
    # record and the act it claims.
    [ ! -f "$GHS/on_comment.$c" ] || /bin/sh "$GHS/on_comment.$c" >/dev/null 2>&1
    exit "$rc"
    ;;
  'pr ready')
    rc=0
    [ ! -f "$GHS/ready_rc" ] || rc=$(cat "$GHS/ready_rc")
    [ "$rc" != 0 ] || : >"$GHS/ready"
    exit "$rc"
    ;;
  'pr merge')
    rc=0
    [ ! -f "$GHS/merge_rc" ] || rc=$(cat "$GHS/merge_rc")
    exit "$rc"
    ;;
  *) exit 3 ;;
esac
GHSTUB
chmod +x "$MP_STUBBIN/gh"

MP_BRANCH=planwright/demo/task-1
MP_TASKS=specs/demo/tasks.md

gitf() { git -C "$F/wt" "$@"; }

mp_write_tasks() { # <awaiting-input body lines...>
  {
    printf '# Demo — Tasks\n\n**Status:** Ready\n**Format-version:** 2\n\n## Tasks\n\n'
    printf '### Task 1 — One\n\n- **Deliverables:** x\n\n'
    printf '## Awaiting input\n\n'
    if [ "$#" = 0 ]; then printf '(none yet)\n'; else printf '%s\n' "$@"; fi
    printf '\n## Deferred\n\n(none yet)\n'
  } >"$F/wt/$MP_TASKS"
}

# mp_record_review — a convergence completion record naming the current head.
mp_record_review() {
  local run
  run=$(/bin/sh "$MP_STEP_RECORD" --worktree "$F/wt" new-run) || return 1
  /bin/sh "$MP_STEP_RECORD" --worktree "$F/wt" write --completion --run "$run" \
    --point convergence --head "$(gitf rev-parse HEAD)" >/dev/null
}

# mp_commit <message> <path> <content> — one commit on the unit branch,
# pushed, with the review record moved onto it.
mp_commit() {
  mkdir -p "$(dirname "$F/wt/$2")"
  printf '%s\n' "$3" >"$F/wt/$2"
  gitf add -f -- "$2"
  gitf commit -q -F - <<<"$1"
  gitf push -q origin "$MP_BRANCH" 2>/dev/null
  mp_record_review
}

# mp_fixture [<awaiting-input lines on main>...] — a fresh origin and unit
# clone, copied from one built template when no base park is asked for.
MP_TEMPLATE=''
mp_fixture() {
  if [ "$#" = 0 ] && [ -n "$MP_TEMPLATE" ]; then
    F=$(mktemp -d "$SANDBOX/fx.XXXXXX")
    cp -R "$MP_TEMPLATE/." "$F/"
    gitf remote set-url origin "$F/origin.git"
    GHS="$F/gh"
    return
  fi
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
  mp_write_tasks
  gitf add -A
  gitf commit -q -m 'chore: seed'
  if [ "$#" -gt 0 ]; then
    mp_write_tasks "$@"
    gitf commit -q -am 'chore: a human park on main'
    gitf push -q origin main 2>/dev/null
    gitf checkout -q -b "$MP_BRANCH" HEAD~1
  else
    gitf push -q origin main 2>/dev/null
    gitf checkout -q -b "$MP_BRANCH"
  fi
  gitf remote set-head origin main >/dev/null 2>&1
  printf 'work\n' >"$F/wt/feature.txt"
  gitf add feature.txt
  gitf commit -q -m 'feat: the unit'
  gitf push -q -u origin "$MP_BRANCH" 2>/dev/null
  mp_record_review
  GHS="$F/gh"
  mkdir -p "$GHS"
  echo green >"$GHS/ci"
  : >"$GHS/log"
}

# mp_policy <key: value lines> — the machine-local layer of the unit clone.
mp_policy() {
  mkdir -p "$F/wt/.claude"
  printf '%s\n' "$@" >"$F/wt/.claude/planwright.local.yml"
}

# mp_run <script> <args...> — a helper from the unit clone, stub first on PATH.
mp_run() {
  local script=$1
  shift
  OUT=$(cd "$F/wt" && env PATH="$MP_STUBBIN:$PATH" GHS="$GHS" GHS_ORIGIN="$F/origin.git" \
    GHS_BRANCH="$MP_BRANCH" PLANWRIGHT_REPO_ROOT="$F/wt" PLANWRIGHT_LOCAL_CONFIG= \
    PLANWRIGHT_ADOPTER_OVERLAY="$SANDBOX/noadopter" PLANWRIGHT_READY_FLIP_POLL_SECONDS=0 \
    PLANWRIGHT_READY_FLIP_MAX_POLLS=3 PLANWRIGHT_READY_GUARD_RETRY_DELAY=0 \
    /bin/bash "$script" "$@" 2>&1)
  CODE=$?
}

mp_calls() { grep -c "^CALL $1" "$GHS/log" 2>/dev/null || true; }
mp_first_line_of() { grep -n "^CALL $1" "$GHS/log" | head -1 | cut -d: -f1; }
mp_origin_head() { git --git-dir="$F/origin.git" rev-parse "refs/heads/$MP_BRANCH"; }
mp_origin_tasks() { git --git-dir="$F/origin.git" show "refs/heads/$MP_BRANCH:$MP_TASKS"; }
