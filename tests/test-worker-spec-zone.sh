#!/bin/bash
# The worker write zone gains the spec root (custom-spec-location REQ-E1.7,
# D-15). The dispatcher computes the root once (scripts/worker-spec-root.sh)
# and hands it to the worker's environment (fleet-dispatch-env.sh
# --spec-root); the command guard reads that value at load and approves a
# write inside the external root, while a write beside it, or with no root
# handed in, still defers, and the guard resolves no config per call.
set -u
unset CDPATH
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY \
  GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT
LC_ALL=C
export LC_ALL

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
S="$REPO_ROOT/scripts"
HOOK="$S/worker-command-guard.sh"

failures=0
ok() { echo "ok: $1"; }
fail() {
  printf 'FAIL: %s\n' "$1" | tr -d '\000-\010\013-\037\177' >&2
  failures=$((failures + 1))
}
command -v jq >/dev/null 2>&1 || {
  echo "FAIL: jq is required to run this suite" >&2
  exit 1
}

tmp=$(mktemp -d "${TMPDIR:-/tmp}/worker-spec-zone.XXXXXX") || exit 1
tmp=$(cd "$tmp" && pwd -P) || exit 1
trap 'rm -rf "$tmp"' EXIT

inherited_unsets=$(env | sed -n 's/^\(PLANWRIGHT_[A-Za-z0-9_]*\)=.*/-u \1/p')
mkdir -p "$tmp/home" "$tmp/fleet"
hermetic() {
  # shellcheck disable=SC2086 # one `-u NAME` pair per word
  env $inherited_unsets -u CLAUDE_PLUGIN_ROOT -u CLAUDE_PLUGIN_DATA -u CLAUDE_DIR \
    -u TMUX -u TMUX_PANE TMUX_TMPDIR="$tmp/home" HOME="$tmp/home" \
    GIT_CEILING_DIRECTORIES="$tmp" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 \
    GIT_AUTHOR_NAME=fixture GIT_AUTHOR_EMAIL=fixture@example.invalid \
    GIT_COMMITTER_NAME=fixture GIT_COMMITTER_EMAIL=fixture@example.invalid \
    PLANWRIGHT_ROOT="$REPO_ROOT" PLANWRIGHT_FLEET_STATE_DIR="$tmp/fleet" "$@"
}
gitq() { hermetic git "$@" >/dev/null 2>&1; }

# The fixture: a work repository, a holder whose root carries the marker, a
# bundle and a reserved directory in it, and the paths a write must not reach.
w=$tmp/work
gitq -c init.defaultBranch=main init -q "$w"
printf 'x\n' >"$w/file"
gitq -C "$w" add -A && gitq -C "$w" commit -q -m init
gitq -c init.defaultBranch=main init -q "$tmp/holder"
z=$tmp/holder/specs
mkdir -p "$z/demo/.orchestrate" "$z/_observations/entries" "$z/notabundle" \
  "$tmp/holder/elsewhere" "$tmp/holder/specs-evil/demo" "$tmp/outside"
printf 'project: fixture\nlayout: 1\n' >"$z/planwright-spec-root.yml"
printf '# Demo\n' >"$z/demo/requirements.md"
printf '# Demo — Tasks\n' >"$z/demo/tasks.md"
printf '# Evil\n' >"$tmp/holder/specs-evil/demo/requirements.md"
printf 'secret\n' >"$tmp/outside/target"
ln -s "$tmp/outside/target" "$z/demo/link.md"
ln "$tmp/outside/target" "$z/demo/hard.md"
mkdir -p "$w/.claude"
printf 'spec_root: %s\n' "$z" >"$w/.claude/planwright.local.yml"

# --- The dispatcher's computation -------------------------------------------
got=$(hermetic /bin/sh "$S/worker-spec-root.sh" "$w")
if [ "$got" = "$z" ]; then
  ok "worker-spec-root: a holder root is handed to the worker"
else
  fail "worker-spec-root: expected '$z', got '$got'"
fi
got=$(cd "$REPO_ROOT" && hermetic /bin/sh scripts/worker-spec-root.sh "$w")
if [ "$got" = "$z" ]; then
  ok "worker-spec-root: a relative invocation still finds the resolver"
else
  fail "worker-spec-root: called as scripts/worker-spec-root.sh, got '$got'"
fi
gitq -c init.defaultBranch=main init -q "$tmp/same"
got=$(hermetic /bin/sh "$S/worker-spec-root.sh" "$tmp/same")
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$got" ]; then
  ok "worker-spec-root: a same-repo root hands nothing"
else
  fail "worker-spec-root: a same-repo root (rc=$rc): '$got'"
fi
mkdir -p "$tmp/plainwork/.claude" "$tmp/plainstore"
gitq -c init.defaultBranch=main init -q "$tmp/plainwork"
printf 'project: fixture\nlayout: 1\n' >"$tmp/plainstore/planwright-spec-root.yml"
printf 'spec_root: %s\n' "$tmp/plainstore" >"$tmp/plainwork/.claude/planwright.local.yml"
got=$(hermetic /bin/sh "$S/worker-spec-root.sh" "$tmp/plainwork")
if [ "$got" = "$tmp/plainstore" ]; then
  ok "worker-spec-root: a plain root is handed to the worker"
else
  fail "worker-spec-root: expected '$tmp/plainstore', got '$got'"
fi

# The tmux rung hands the root it computed through the wrapper's option.
plan=$(cd "$w" && hermetic "$S/fleet-dispatch-worktree.sh" attach demo-task-1 --dry-run 2>&1)
case $plan in
  *"	--spec-root	$z	"*) ok "tmux rung: the launch hands the root through --spec-root" ;;
  *) fail "tmux rung: the launch plan carries no --spec-root: $plan" ;;
esac
plan=$(cd "$tmp/same" && hermetic "$S/fleet-dispatch-worktree.sh" attach demo-task-1 --dry-run 2>&1)
case $plan in
  *--spec-root*) fail "tmux rung: a same-repo root was handed to the worker: $plan" ;;
  *attach-plan*) ok "tmux rung: a same-repo root hands no --spec-root" ;;
  *) fail "tmux rung: no plan for the same-repo fixture: $plan" ;;
esac

# The wrapper exports the root, validates it, and drops an inherited one.
# shellcheck disable=SC2016 # the child shell expands it
got=$(hermetic env PLANWRIGHT_WORKER_SPEC_ROOT=/stale /bin/sh "$S/fleet-dispatch-env.sh" \
  --spec-root "$z" /bin/sh -c 'printf "%s" "$PLANWRIGHT_WORKER_SPEC_ROOT"')
if [ "$got" = "$z" ]; then
  ok "dispatch-env: --spec-root is exported to the worker"
else
  fail "dispatch-env: --spec-root exported '$got'"
fi
# shellcheck disable=SC2016 # the child shell expands it
got=$(hermetic env PLANWRIGHT_WORKER_SPEC_ROOT=/stale /bin/sh "$S/fleet-dispatch-env.sh" \
  --root "$REPO_ROOT" /bin/sh -c 'printf "%s" "${PLANWRIGHT_WORKER_SPEC_ROOT-unset}"')
if [ "$got" = unset ]; then
  ok "dispatch-env: a launch without --spec-root drops an inherited one"
else
  fail "dispatch-env: an inherited root survived the launch options: '$got'"
fi
for bad in relative/dir "$tmp/missing"; do
  hermetic /bin/sh "$S/fleet-dispatch-env.sh" --spec-root "$bad" true >/dev/null 2>&1
  if [ $? -eq 2 ]; then
    ok "dispatch-env: --spec-root '$bad' is refused"
  else
    fail "dispatch-env: --spec-root '$bad' was accepted"
  fi
done

# --- The guard -----------------------------------------------------------------
# A git stub on PATH records any call: resolving config or a root per call
# would run git, and the write-zone verdicts must not.
mkdir -p "$tmp/stub"
cat >"$tmp/stub/git" <<EOF
#!/bin/sh
: >"$tmp/git-called"
exit 1
EOF
chmod +x "$tmp/stub/git"
# verdict <zone|-> <command> — allow or defer, the hook run from the work
# repository with the root handed in (or none for -).
verdict() {
  v_payload=$(jq -n --arg c "$2" --arg w "$w" '{tool_name:"Bash", tool_input:{command:$c}, cwd:$w}')
  if [ "$1" = - ]; then
    set -- env -u PLANWRIGHT_WORKER_SPEC_ROOT
  else
    set -- env PLANWRIGHT_WORKER_SPEC_ROOT="$1"
  fi
  v_out=$(printf '%s' "$v_payload" | hermetic "$@" PATH="$tmp/stub:/usr/bin:/bin" /bin/bash "$HOOK" 2>/dev/null)
  case $v_out in
    *'"permissionDecision":"allow"'*) printf allow ;;
    '') printf defer ;;
    *) printf 'unexpected:%s' "$v_out" ;;
  esac
}
expect() {
  e_got=$(verdict "$2" "$3")
  if [ "$e_got" = "$1" ]; then
    ok "guard: $1 $4"
  else
    fail "guard: expected $1, got $e_got, for $4: $3"
  fi
}

expect allow "$z" "printf '%s\\n' x >> $z/demo/tasks.md" "an append to a bundle file in the root"
expect allow "$z" "printf x > $z/demo/notes.md" "a new file in a bundle"
expect allow "$z" "printf x | tee -a $z/demo/tasks.md" "tee -a into the root"
expect allow "$z" "mkdir -p $z/_observations/entries/new" "mkdir -p under a reserved directory"
expect allow "$z/" "printf x 2>> $z/demo/tasks.md" "an fd-prefixed append, the root handed with a trailing slash"
if [ ! -e "$tmp/git-called" ]; then
  ok "guard: no git or config resolution ran for a write-zone verdict"
else
  fail "guard: a write-zone verdict ran git"
fi

expect defer - "printf x >> $z/demo/tasks.md" "with no root handed in"
expect defer "$z" "printf x > $tmp/holder/elsewhere/x" "a write beside the root"
expect defer "$z" "printf x > $z/../elsewhere/x" "a dot-dot escape from the root"
expect defer "$z" "printf x > $tmp/holder/specs-evil/demo/x" "a sibling sharing the root's name prefix"
expect defer "$z" "printf x > $w/file" "a write in the work repository"
expect defer "$z" "printf x > $z/tasks.md" "the root's own top level"
expect defer "$z" "printf x > $z/planwright-spec-root.yml" "the root marker"
expect defer "$z" "printf x > $z/demo/.orchestrate/m" "a dot-led directory"
expect defer "$z" "printf x > $z/notabundle/x" "a directory that is not a bundle"
expect defer "$z" "printf x > $z/demo/link.md" "a symlinked leaf"
expect defer "$z" "printf x > $z/demo/hard.md" "a hard-linked leaf"
expect defer "$z" "R=$z && printf x > \$R/demo/tasks.md" "an expanded target"
expect defer "$z" "printf x > '$z/demo/tasks.md'" "a quoted target"
expect defer "$z" "printf x &> $z/demo/tasks.md" "an &> redirect"
expect defer "$z" "printf x | tee -p $z/demo/tasks.md" "tee with another flag"
expect defer "$z" "printf x | tee $z/demo/tasks.md $tmp/outside/x" "tee with one target outside"
expect defer - "printf x | tee" "tee with no file and no root handed in"
expect defer "$z" "printf x | tee -a" "tee with no file operand"
expect defer - "mkdir -p $z/demo/x" "mkdir with no root handed in"
expect defer "$z" "mkdir -m 777 $z/demo/x" "mkdir with a mode"
expect defer "$z" "mkdir -p $z/_observations/missing/deep" "mkdir under a parent that does not exist"
expect defer "$z" "rm $z/demo/tasks.md" "a writer verb outside the arm"
# The load-time checks on the handed-in value: each case would allow if its
# check were dropped, since the target is otherwise a valid bundle write.
expect defer "$tmp/holder/specs-evil" "printf x > $tmp/holder/specs-evil/demo/x" "a handed-in directory without the marker"
mkdir -p "$tmp/linkroot/demo"
printf '# Demo\n' >"$tmp/linkroot/demo/requirements.md"
ln -s "$z/planwright-spec-root.yml" "$tmp/linkroot/planwright-spec-root.yml"
expect defer "$tmp/linkroot" "printf x > $tmp/linkroot/demo/x" "a handed-in directory whose marker is a symlink"
e_got=$(cd "$tmp" && verdict "holder/specs" "printf x > $z/demo/tasks.md")
if [ "$e_got" = defer ]; then
  ok "guard: defer a relative handed-in value, even where it would resolve"
else
  fail "guard: expected defer, got $e_got, for a relative handed-in value resolved from $tmp"
fi
mkdir -p "$z/_res.x"
expect defer "$z" "printf x > $z/_res.x/f" "a reserved directory outside the name charset"
mkfifo "$z/demo/pipe"
expect defer "$z" "printf x > $z/demo/pipe" "a leaf that is neither a file nor a directory"

if [ "$failures" -ne 0 ]; then
  echo "FAIL: test-worker-spec-zone.sh ($failures failure(s))" >&2
  exit 1
fi
echo "PASS: test-worker-spec-zone.sh"
