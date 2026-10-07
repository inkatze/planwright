# shellcheck shell=bash
# worker-guard-corpus.sh — the worker guard's real-prompt corpus: its grammar,
# the sandbox its rows run in, and the replay (sourced, never executed).
# tests/test-worker-guard-corpus.sh replays every policy column through the
# guard script; tests/smoke-worker-dispatch.sh replays the empty-policy column
# through the hook command as the settings fragment spells it.
#
#   corpus_sandbox <box> <plugin-root>
#                        build the sandbox under <box>, which must be empty:
#                        a linked worktree on the unit branch (its base
#                        resolving as origin/main, a configured hooks
#                        directory, the files the rows name, a symlink that
#                        escapes it), a scratch root holding the same kind
#                        of symlink, a directory outside both, and one
#                        session record and audit home per policy column;
#                        <plugin-root> is the installed planwright root the
#                        rows trust. Sets the CORPUS_* paths only on success
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
#                        did, 2 when the corpus, the column list, or the
#                        sandbox is unusable or a hook call yields no verdict
#
# The session record each column injects is the guard's launch-time input
# (the policy, the unit identity, the scratch root, the audit-log home, the
# base-merge gate). corpus_decide hands the guard its path as
# PLANWRIGHT_WORKER_SESSION_RECORD; if the guard locates its record any other
# way, corpus_decide must follow, or every column replays the same input.

unset CDPATH

# A parse yielding fewer rows than this means the file was mangled, not that
# the guard got better; the sourcing suites enforce it.
# shellcheck disable=SC2034
CORPUS_MIN_ROWS=100
CORPUS_SESSION_ID=corpus-session
CORPUS_UNIT_BRANCH=planwright/demo/task-1
CORPUS_TAB=$(printf '\t')
# Hook calls in flight at once. A test file holds one ticket of the suite's
# pool, so this stays small.
CORPUS_JOBS=4

# corpus_policy <column>: the policy value a verdict column stands for.
corpus_policy() {
  case $1 in
    1) printf '' ;;
    2) printf 'own-branch' ;;
    3) printf 'scratch' ;;
    4) printf 'own-branch scratch' ;;
  esac
}

# corpus_git_env <git-args>: git, isolated from the host's configuration and
# from any repository the caller's environment points at.
corpus_git_env() {
  env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_COMMON_DIR \
    GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 git "$@"
}

corpus_git() { corpus_git_env -C "$CORPUS_WORKTREE" "$@"; }

corpus_sandbox() {
  local box main wt scratch outside col
  mkdir -p "$1" || return 1
  [ -z "$(ls -A "$1")" ] || {
    echo "corpus: sandbox box is not empty: $1" >&2
    return 1
  }
  box=$(cd -P "$1" && pwd -P) || return 1
  main=$box/main
  wt=$box/worktree
  scratch=$box/scratch
  outside=$box/outside
  mkdir -p "$main" "$scratch" "$outside" "$box/home" "$box/hook-tmp" \
    "$box/state" || return 1

  # A worker's worktree is a linked one, so its .git is a file, and its unit
  # branch sits on a base that resolves as origin/main. The other branch and
  # the sibling repository exist so rows naming them are judged on a real
  # target rather than a missing one.
  {
    corpus_git_env init -q --bare "$box/origin.git" \
      && corpus_git_env init -q "$main" \
      && corpus_git_env init -q "$box/other" \
      && corpus_git_env -C "$main" symbolic-ref HEAD refs/heads/main \
      && corpus_git_env -C "$main" -c user.name=corpus -c user.email=corpus@example.invalid \
        -c commit.gpgsign=false commit -q --allow-empty -m init \
      && corpus_git_env -C "$main" branch other \
      && corpus_git_env -C "$main" remote add origin "$box/origin.git" \
      && corpus_git_env -C "$main" push -q origin main other \
      && corpus_git_env -C "$main" fetch -q origin \
      && corpus_git_env -C "$main" config core.hooksPath githooks \
      && corpus_git_env -C "$main" worktree add -q -b "$CORPUS_UNIT_BRANCH" "$wt" main
  } 2>"$box/build.log" || {
    echo "corpus: sandbox git setup failed:" >&2
    cat "$box/build.log" >&2
    return 1
  }

  {
    mkdir -p "$wt/scripts" "$wt/tests" "$wt/sub" "$wt/build" "$wt/specs/demo" \
      "$wt/githooks" "$wt/.claude" \
      && printf 'a x\nb\n' >"$wt/f" \
      && printf 'x\n' >"$wt/g" \
      && printf 'x\n' >"$wt/sub/g" \
      && printf '# notes\nx\n' >"$wt/notes.md" \
      && printf '{}\n' >"$wt/f.json" \
      && printf 'a: 1\n' >"$wt/f.yml" \
      && printf '### REQ-A1.1\n' >"$wt/specs/demo/test-spec.md" \
      && printf 'msg\n' >"$wt/build/msg.txt" \
      && : >"$wt/build/a" \
      && : >"$wt/scripts/ok.sh" \
      && : >"$wt/tests/ok.sh" \
      && : >"$wt/tests/ok.bats" \
      && : >"$wt/mise.toml" \
      && : >"$wt/mise.local.toml" \
      && : >"$wt/lefthook.yml" \
      && : >"$wt/hardlinked" \
      && ln "$wt/hardlinked" "$wt/hardlinked.2" \
      && ln -s "$outside" "$wt/outlink" \
      && : >"$scratch/f.orig" \
      && : >"$scratch/a" \
      && : >"$scratch/run.sh" \
      && : >"$scratch/env.sh" \
      && : >"$scratch/x.sh" \
      && ln -s "$outside" "$scratch/escape" \
      && : >"$outside/x"
  } || return 1

  for col in 1 2 3 4; do
    mkdir -p "$box/state/audit.$col" || return 1
    printf '%s\n' \
      "policy=$(corpus_policy "$col")" \
      "unit_branch=$CORPUS_UNIT_BRANCH" \
      "worktree_root=$wt" \
      "pr_base=origin/main" \
      "scratch_root=$scratch" \
      "audit_log_home=$box/state/audit.$col" \
      "worker_base_merge=allow" >"$box/state/record.$col" || return 1
  done

  CORPUS_BOX=$box
  CORPUS_PLUGIN_ROOT=$2
  CORPUS_WORKTREE=$wt
  CORPUS_SCRATCH=$scratch
  CORPUS_OUTSIDE=$outside
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
      known = $7
      gsub(/@@(WORKTREE|SCRATCH|OUTSIDE|PLUGIN_ROOT)@@/, "", known)
      if (known ~ /@@/) bad("unknown placeholder")
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
# Spliced by prefix and suffix rather than ${c//pat/rep}: bash 5.2 expands
# `&` in that replacement to the matched text.
corpus_bind() {
  local c=$1 name value out mark
  for name in WORKTREE SCRATCH OUTSIDE PLUGIN_ROOT; do
    case $name in
      WORKTREE) value=$CORPUS_WORKTREE ;;
      SCRATCH) value=$CORPUS_SCRATCH ;;
      OUTSIDE) value=$CORPUS_OUTSIDE ;;
      PLUGIN_ROOT) value=$CORPUS_PLUGIN_ROOT ;;
    esac
    mark="@@$name@@"
    out=
    while :; do
      case $c in
        *"$mark"*)
          out=$out${c%%"$mark"*}$value
          c=${c#*"$mark"}
          ;;
        *) break ;;
      esac
    done
    c=$out$c
  done
  printf '%s' "$c"
}

# corpus_unexport <keep>...: in the calling shell, drop the export attribute
# from every function and from every variable not named. Unexported rather
# than unset, so the caller's own values still resolve and a readonly export
# such as SHELLOPTS goes too. Entries bash cannot name as variables are
# beyond it. Kept out of any $( ): bash 3.2 misreads a case pattern's `)`
# there as the end of the substitution.
corpus_unexport() {
  local v keep=" $* "
  for v in $(compgen -e); do
    case $keep in
      *" $v "*) ;;
      *) export -n "${v?}" 2>/dev/null ;;
    esac
  done
  for v in $(compgen -A function); do
    export -fn "${v?}" 2>/dev/null
  done
}

# corpus_decide <runner> <column> <command>: prints allow, defer, or error.
# The decision field is parsed, never substring-matched, so a reason text
# that happens to say "allow" is not an approval; anything but a parsed
# `allow` (deny, ask, malformed output, silence) is a defer. A hook exits 0
# on every path, so a non-zero exit, like a payload that cannot be built, is
# the harness failing and prints error.
corpus_decide() {
  local runner=$1 col=$2 payload out
  payload=$(jq -cn --arg c "$3" --arg w "$CORPUS_WORKTREE" --arg s "$CORPUS_SESSION_ID-$col" \
    '{hook_event_name:"PreToolUse", session_id:$s, tool_name:"Bash",
      tool_input:{command:$c}, cwd:$w}') || {
    echo error
    return
  }
  out=$(
    cd "$CORPUS_WORKTREE" || exit 1
    # The guard reads its environment (it refuses an assignment to any name
    # exported there, and resolves overlays and fleet state through it), so
    # the caller's exports are dropped and only what the row needs is set.
    # HOME is pinned so the guard never reads the host's installed plugins,
    # and TMPDIR is not the scratch root, so a row resolving `$TMPDIR` proves
    # the guard took the root from the record.
    corpus_unexport PATH LC_ALL
    printf '%s' "$payload" \
      | HOME="$CORPUS_BOX/home" TMPDIR="$CORPUS_BOX/hook-tmp" \
        CLAUDE_PLUGIN_ROOT="$CORPUS_PLUGIN_ROOT" PLANWRIGHT_ROOT="$CORPUS_PLUGIN_ROOT" \
        PLANWRIGHT_WORKER_SESSION_RECORD="$CORPUS_BOX/state/record.$col" \
        "$runner" 2>/dev/null
  ) || {
    echo error
    return
  }
  # The deprecated top-level `decision: approve` still approves.
  case $(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // .permissionDecision
      // (if .decision == "approve" then "allow" else empty end)' 2>/dev/null) in
    allow) echo allow ;;
    *) echo defer ;;
  esac
}

corpus_replay() {
  local file=$1 runner=$2 columns=${3:-1 2 3 4} parsed
  local kind line class state v1 v2 v3 v4 cmd col want got missed allowed verdicts pids seen n inflight broken=0
  CORPUS_ROWS=0
  CORPUS_FAILED=0
  CORPUS_FALSE_ALLOWS=0
  CORPUS_PENDING=0
  [ -n "${CORPUS_WORKTREE:-}" ] && [ -d "$CORPUS_WORKTREE" ] || {
    echo "corpus: no sandbox; call corpus_sandbox first" >&2
    return 2
  }
  seen=" "
  for col in $columns; do
    case $col in
      1 | 2 | 3 | 4) ;;
      *)
        echo "corpus: unknown policy column: $col" >&2
        return 2
        ;;
    esac
    case $seen in
      *" $col "*)
        echo "corpus: policy column listed twice: $col" >&2
        return 2
        ;;
    esac
    seen="$seen$col "
  done
  [ "$seen" != " " ] || {
    echo "corpus: no policy column to replay" >&2
    return 2
  }
  parsed=$(corpus_parse "$file") || return 2
  verdicts=$(mktemp -d "$CORPUS_BOX/verdicts.XXXXXX") || return 2
  # Every (row, column) call is independent, so they run CORPUS_JOBS at a
  # time; the verdicts are read back in row order afterwards.
  n=0
  inflight=0
  pids=
  while IFS="$CORPUS_TAB" read -r kind line class state v1 v2 v3 v4 cmd; do
    [ "$kind" = row ] || continue
    n=$((n + 1))
    cmd=$(corpus_bind "$cmd")
    for col in $columns; do
      corpus_decide "$runner" "$col" "$cmd" >"$verdicts/$n.$col" &
      pids="$pids $!"
      inflight=$((inflight + 1))
      if [ "$inflight" -ge "$CORPUS_JOBS" ]; then
        # shellcheck disable=SC2086  # a list of pids
        wait $pids
        pids=
        inflight=0
      fi
    done
  done <<EOF
$parsed
EOF
  # shellcheck disable=SC2086  # a list of pids
  [ -z "$pids" ] || wait $pids
  n=0
  while IFS="$CORPUS_TAB" read -r kind line class state v1 v2 v3 v4 cmd; do
    [ "$kind" = row ] || continue
    n=$((n + 1))
    CORPUS_ROWS=$((CORPUS_ROWS + 1))
    cmd=$(corpus_bind "$cmd")
    missed=0
    allowed=0
    for col in $columns; do
      case $col in
        1) want=$v1 ;;
        2) want=$v2 ;;
        3) want=$v3 ;;
        4) want=$v4 ;;
      esac
      got=
      read -r got <"$verdicts/$n.$col" || :
      case $got in
        allow | defer) ;;
        *)
          printf 'corpus: no verdict (%s, line %s, policy "%s"): the hook call failed\n' \
            "$class" "$line" "$(corpus_policy "$col")" >&2
          broken=1
          break 2
          ;;
      esac
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
  [ "$broken" -eq 0 ] || return 2
  [ "$CORPUS_FAILED" -eq 0 ]
}
