# shellcheck shell=bash
# worker-guard-corpus.sh — the worker guard's real-prompt corpus: its grammar,
# the sandbox its rows run in, and the replay (sourced, never executed).
# tests/test-worker-guard-corpus.sh replays every policy column through the
# guard script; tests/smoke-worker-dispatch.sh replays the empty-policy column
# through the hook command as the settings fragment spells it.
#
#   corpus_sandbox <box> <plugin-root>
#                        build the sandbox under <box>: a worktree (a git
#                        repository on the unit branch, with an origin
#                        remote, a configured hooks directory, and the files
#                        the rows name), a scratch root holding a symlink
#                        that escapes it, a directory outside both, and one
#                        session record per policy column; <plugin-root> is
#                        the installed planwright root the rows trust
#   corpus_parse <file>  validate the corpus and print one normalized record
#                        per line: `class <name> <state>` and
#                        `row <line> <class> <state> <v1> <v2> <v3> <v4>
#                        <command>`, tab-separated; exit 2 naming the line on
#                        any malformed record, and on a corpus with no rows
#   corpus_replay <file> <runner> [<columns>]
#                        replay every row under each listed policy column
#                        (default all four), <runner> being a command or
#                        function that reads a hook payload on stdin and
#                        prints the hook's stdout. Sets CORPUS_ROWS,
#                        CORPUS_FAILED (rows that failed: any false-allow,
#                        and a shipped row's stall), CORPUS_FALSE_ALLOWS
#                        (those of them that allowed), and CORPUS_PENDING
#                        (pending rows that only stalled); prints each miss
#                        on stderr. Exit 0 when no row failed, 1 when one
#                        did, 2 when the corpus or the sandbox is unusable
#
# The session record each column injects is the guard's launch-time input
# (the policy, the unit identity, the scratch root, the audit-log home, the
# base-merge gate). Until the guard reads it, it is inert; the task that
# teaches the guard to read it binds corpus_decide to the real location.

unset CDPATH

# A parse yielding fewer rows than this means the file was mangled, not that
# the guard got better; the sourcing suites enforce it.
# shellcheck disable=SC2034
CORPUS_MIN_ROWS=100
CORPUS_SESSION_ID=corpus-session
CORPUS_UNIT_BRANCH=planwright/demo/task-1
CORPUS_TAB=$(printf '\t')

# corpus_policy <column>: the policy value a verdict column stands for.
corpus_policy() {
  case $1 in
    1) printf '' ;;
    2) printf 'own-branch' ;;
    3) printf 'scratch' ;;
    4) printf 'own-branch scratch' ;;
  esac
}

corpus_git() {
  env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_COMMON_DIR \
    GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 git -C "$CORPUS_WORKTREE" "$@"
}

corpus_sandbox() {
  mkdir -p "$1" || return 1
  CORPUS_BOX=$(cd -P "$1" && pwd -P) || return 1
  CORPUS_PLUGIN_ROOT=$2
  CORPUS_WORKTREE=$CORPUS_BOX/worktree
  CORPUS_SCRATCH=$CORPUS_BOX/scratch
  CORPUS_OUTSIDE=$CORPUS_BOX/outside
  local wt=$CORPUS_WORKTREE col
  mkdir -p "$wt/scripts" "$wt/tests" "$wt/sub" "$wt/build" "$wt/specs/demo" \
    "$wt/githooks" "$wt/.claude" "$CORPUS_SCRATCH" "$CORPUS_OUTSIDE" \
    "$CORPUS_BOX/home" "$CORPUS_BOX/state/audit" || return 1
  env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_COMMON_DIR \
    GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 git init -q "$wt" || return 1
  corpus_git checkout -q -b "$CORPUS_UNIT_BRANCH" || return 1
  corpus_git config core.hooksPath githooks || return 1
  corpus_git remote add origin ../origin.git || return 1

  printf 'a x\nb\n' >"$wt/f"
  printf 'x\n' >"$wt/g"
  printf 'x\n' >"$wt/sub/g"
  printf '# notes\nx\n' >"$wt/notes.md"
  printf '{}\n' >"$wt/f.json"
  printf 'a: 1\n' >"$wt/f.yml"
  printf '### REQ-A1.1\n' >"$wt/specs/demo/test-spec.md"
  printf 'msg\n' >"$wt/build/msg.txt"
  : >"$wt/build/a"
  : >"$wt/scripts/ok.sh"
  : >"$wt/tests/ok.sh"
  : >"$wt/tests/ok.bats"
  : >"$wt/mise.toml"
  : >"$wt/mise.local.toml"
  : >"$wt/lefthook.yml"
  : >"$wt/hardlinked"
  ln "$wt/hardlinked" "$wt/hardlinked.2" || return 1
  : >"$CORPUS_SCRATCH/f.orig"
  : >"$CORPUS_SCRATCH/a"
  ln -s "$CORPUS_OUTSIDE" "$CORPUS_SCRATCH/escape" || return 1
  : >"$CORPUS_OUTSIDE/x"

  for col in 1 2 3 4; do
    printf '%s\n' \
      "policy=$(corpus_policy "$col")" \
      "unit_branch=$CORPUS_UNIT_BRANCH" \
      "worktree_root=$CORPUS_WORKTREE" \
      "pr_base=origin/main" \
      "scratch_root=$CORPUS_SCRATCH" \
      "audit_log_home=$CORPUS_BOX/state/audit" \
      "worker_base_merge=allow" >"$CORPUS_BOX/state/record.$col" || return 1
  done
}

corpus_parse() {
  [ -r "$1" ] || {
    echo "corpus: not readable: $1" >&2
    return 2
  }
  awk -F'\t' -v file="$1" '
    function bad(m) {
      printf "corpus: %s:%d: %s\n", file, NR, m > "/dev/stderr"
      err = 1
      exit 2
    }
    { sub(/\r$/, "") }
    /^[[:space:]]*(#|$)/ { next }
    $1 == "class" {
      if (NF != 5) bad("a class record has five tab-separated fields")
      if ($2 !~ /^[a-z][a-z0-9-]*$/) bad("malformed class name")
      if ($3 !~ /^[0-9]+$/) bad("a class names the task that delivers it")
      if ($4 != "shipped" && $4 != "pending") bad("a class is shipped or pending")
      if ($2 in state) bad("class declared twice: " $2)
      state[$2] = $4
      print "class\t" $2 "\t" $4
      next
    }
    $1 == "row" {
      if (NF != 7) bad("a row has seven tab-separated fields")
      if (!($2 in state)) bad("row of an undeclared class: " $2)
      for (i = 3; i <= 6; i++)
        if ($i != "allow" && $i != "defer") bad("a verdict is allow or defer")
      if ($7 == "") bad("a row carries a command")
      if (($2 == "floor" || $2 == "uncovered") && ($3 $4 $5 $6) != "deferdeferdeferdefer")
        bad("a " $2 " row defers under every policy value")
      if ($3 == "allow" && ($4 != "allow" || $5 != "allow" || $6 != "allow"))
        bad("an arm only adds approvals: allowed under the empty policy, allowed under all")
      if (($4 == "allow" || $5 == "allow") && $6 != "allow")
        bad("an arm only adds approvals: allowed under one arm, allowed under both")
      rows++
      print "row\t" NR "\t" $2 "\t" state[$2] "\t" $3 "\t" $4 "\t" $5 "\t" $6 "\t" $7
      next
    }
    { bad("unknown record kind: " $1) }
    END {
      if (err) exit 2
      if (!rows) {
        printf "corpus: %s: no rows\n", file > "/dev/stderr"
        exit 2
      }
    }
  ' "$1"
}

# corpus_bind <command>: the command with the placeholders bound to the
# sandbox and the plugin root under test.
corpus_bind() {
  local c=$1
  c=${c//@@WORKTREE@@/$CORPUS_WORKTREE}
  c=${c//@@SCRATCH@@/$CORPUS_SCRATCH}
  c=${c//@@OUTSIDE@@/$CORPUS_OUTSIDE}
  c=${c//@@PLUGIN_ROOT@@/$CORPUS_PLUGIN_ROOT}
  printf '%s' "$c"
}

# corpus_decide <runner> <column> <command>: prints allow or defer. The
# decision field is parsed, never substring-matched, so a reason text that
# happens to say "allow" is not an approval; anything but a parsed `allow`
# (deny, ask, malformed output, silence) is a defer.
corpus_decide() {
  local runner=$1 col=$2 payload out
  payload=$(jq -cn --arg c "$3" --arg w "$CORPUS_WORKTREE" --arg s "$CORPUS_SESSION_ID" \
    '{hook_event_name:"PreToolUse", session_id:$s, tool_name:"Bash",
      tool_input:{command:$c}, cwd:$w}') || {
    echo defer
    return
  }
  out=$(
    cd "$CORPUS_WORKTREE" || exit 0
    unset CLAUDE_DIR GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR
    # HOME is pinned so the guard never reads the host's installed plugins.
    printf '%s' "$payload" \
      | HOME="$CORPUS_BOX/home" TMPDIR="$CORPUS_SCRATCH" \
        CLAUDE_PLUGIN_ROOT="$CORPUS_PLUGIN_ROOT" PLANWRIGHT_ROOT="$CORPUS_PLUGIN_ROOT" \
        PLANWRIGHT_WORKER_SESSION_RECORD="$CORPUS_BOX/state/record.$col" \
        "$runner" 2>/dev/null
  )
  case $(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // .permissionDecision // empty' 2>/dev/null) in
    allow) echo allow ;;
    *) echo defer ;;
  esac
}

corpus_replay() {
  local file=$1 runner=$2 columns=${3:-1 2 3 4} parsed
  local kind line class state v1 v2 v3 v4 cmd col want got missed allowed verdicts
  CORPUS_ROWS=0
  CORPUS_FAILED=0
  CORPUS_FALSE_ALLOWS=0
  CORPUS_PENDING=0
  [ -n "${CORPUS_WORKTREE:-}" ] && [ -d "$CORPUS_WORKTREE" ] || {
    echo "corpus: no sandbox; call corpus_sandbox first" >&2
    return 2
  }
  parsed=$(corpus_parse "$file") || return 2
  verdicts=$(mktemp -d) || return 2
  while IFS="$CORPUS_TAB" read -r kind line class state v1 v2 v3 v4 cmd; do
    [ "$kind" = row ] || continue
    CORPUS_ROWS=$((CORPUS_ROWS + 1))
    cmd=$(corpus_bind "$cmd")
    missed=0
    allowed=0
    # The columns are independent hook calls, so they run side by side.
    for col in $columns; do
      rm -f "$verdicts/$col"
      corpus_decide "$runner" "$col" "$cmd" >"$verdicts/$col" &
    done
    wait
    for col in $columns; do
      case $col in
        1) want=$v1 ;;
        2) want=$v2 ;;
        3) want=$v3 ;;
        4) want=$v4 ;;
        *) continue ;;
      esac
      got=$(cat "$verdicts/$col" 2>/dev/null)
      [ "$got" = allow ] || got=defer
      [ "$got" = "$want" ] && continue
      missed=1
      if [ "$got" = allow ]; then
        allowed=1
        printf 'FALSE-ALLOW (%s, line %s, policy "%s"): %s\n' \
          "$class" "$line" "$(corpus_policy "$col")" "$cmd" >&2
      elif [ "$state" = pending ]; then
        printf 'pending (%s, line %s, policy "%s"): expected allow, got defer: %s\n' \
          "$class" "$line" "$(corpus_policy "$col")" "$cmd" >&2
      else
        printf 'STALL (%s, line %s, policy "%s"): expected allow, got defer: %s\n' \
          "$class" "$line" "$(corpus_policy "$col")" "$cmd" >&2
      fi
    done
    [ "$missed" -eq 1 ] || continue
    # Pending excuses a stall only: a false-allow fails in every class.
    if [ "$allowed" -eq 1 ]; then
      CORPUS_FAILED=$((CORPUS_FAILED + 1))
      CORPUS_FALSE_ALLOWS=$((CORPUS_FALSE_ALLOWS + 1))
    elif [ "$state" = pending ]; then
      CORPUS_PENDING=$((CORPUS_PENDING + 1))
    else
      CORPUS_FAILED=$((CORPUS_FAILED + 1))
    fi
  done <<EOF
$parsed
EOF
  rm -rf "$verdicts"
  [ "$CORPUS_FAILED" -eq 0 ]
}
