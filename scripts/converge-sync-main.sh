#!/usr/bin/env bash
# converge-sync-main.sh — merge `origin/main` into the current worker branch,
# once at the top of each `/execute-task` convergence pass, so the head the
# convergence steps verify is `main`-current
# (merge-currency-guard Task 3; D-4; REQ-B1.1, REQ-B1.2, REQ-B1.3, REQ-B1.6,
# REQ-D1.3, REQ-K1.1).
#
# NOT the head `/execute-task`'s own full-CI step ran on: that step runs before
# the Convergence section this sync opens, and the skill has no loop that
# re-runs it afterwards. The merged head is covered by whatever wider-suite runs
# the convergence steps perform, so a pass that applies no fix can leave it with
# no suite run at all. That gap is a known contract drift against D-4's premise,
# recorded for the spec owner in the 2026-08-26 `converge-sync-ci-ordering`
# observation rather than decided here.
#
# Why this exists as a script and not as skill prose: REQ-B1.5. `/execute-task`
# invokes it in one line, its instruction body does not grow a paragraph, and
# the mechanism stays testable in isolation.
#
# WHAT IT MAY NOT DO. `git pull` is forbidden outright (REQ-B1.2): a global
# `branch.autosetuprebase=always` silently rewrites it into a rebase, and
# rebase — like amend, squash, and force-push — rewrites published history and
# breaks the content anchor (bootstrap REQ-J1.4). So the sync is always an
# explicit fetch followed by an explicit merge, and `merge.ff` is pinned to its
# default at the call site so an ambient `merge.ff=only` cannot turn a routine
# non-fast-forward sync into a failure that looks like a conflict.
#
# WHAT IT LEAVES BEHIND ON FAILURE. Every non-zero path leaves a tree the next
# invocation can retry from unchanged (REQ-B1.3): the dirty-tree and
# fetch-failure paths never start a merge, and the conflict path aborts the one
# it started. That is what makes the caller's halt-and-resume idempotent rather
# than wedged on a lingering MERGE_HEAD. The exceptions are an abort that
# itself fails, which gets its own reason precisely because it is the one state
# a resume cannot assume is clean, and a conflict under `resolve`, left on
# purpose for the worker (see POLICY).
#
# WHY EACH FAILURE GETS ITS OWN REASON (REQ-B1.6, REQ-K1.1). The caller halts
# the unit to `Awaiting input` with whatever this prints, and the three causes
# need three different human actions: an unreachable remote is retried, a
# conflict is resolved by landing `origin/main`, a dirty tree is committed or
# discarded first. Collapsing any of them into a misreported "merge conflict"
# sends the human after the wrong thing.
#
# POLICY (human-gates D-7; REQ-E1.1, REQ-E1.2). The script is a spelling of
# the base-merge act the policy guard governs on `git merge` and `git pull`,
# which the guard cannot see inside a script, so it makes these checks itself:
# the knobs are read from the repository's primary checkout (a worker's edit to
# its own overlay governs nothing until it merges); the target must be on a
# unit branch outside the protected set; and that branch must be the session's
# (the branch at CLAUDE_PROJECT_DIR, else at the caller's own directory, when
# that directory belongs to the same repository). Unlike the guard, which
# takes the remote's default branch as the base, the source stays the literal
# `origin main` (see the fetch below). `worker_base_merge: deny` skips the
# merge, the operator syncing instead; being behind the base is not itself a
# reason to halt a unit, so the skip is a success. `worker_merge_conflict_policy`
# decides a conflict: `halt` aborts as below; `resolve` leaves the conflicted
# merge for the worker, and `--commit-resolution` then commits it stamped with
# the sign-off trailer and a `Base-merge resolution:` body line the checklist
# renders as the PR-body flag. Only the merge this script left is committed,
# while both knobs still allow it, and only with conflicted paths changed: the
# fetched commit and the index's other merged entries are recorded in the git
# dir at the conflict and checked again at the commit.
#
# Usage: converge-sync-main.sh [<repo-dir>]      (default: the current directory)
#        converge-sync-main.sh --commit-resolution <spec>/<id>
#          [--commit-resolution <spec>/<id> ...] [<repo-dir>]
#
# Output: tagged TSV records on stdout, the message last and meant for a
# human:
#   sync<TAB><up-to-date|fast-forward|merged|denied><TAB><head-sha>
#   park<TAB><reason><TAB><message>     the unit parks under Awaiting input
#                                       with this message (exits 3-6, 9)
#   repair<TAB>abort-failed<TAB><msg>   no park: the tree needs hand repair
#   resolve<TAB><target-sha><TAB><msg>  the conflict is left for the worker;
#                                       the message names the paths and step
#   resolution<TAB><head-sha><TAB><PS-id>
# Failures also print `converge-sync-main: <reason>: <message>` on stderr.
#
# Exit codes:
#   0  synced (already current, fast-forwarded, merged, or denied by policy),
#      or the resolution committed
#   2  usage — bad arguments, a target that is not a git work tree, or a
#      missing `git`/`tr` or sibling script (reason `environment`)
#   3  dirty-tree — tracked-file changes, or a merge/rebase/cherry-pick already
#      in progress; no fetch is attempted
#   4  fetch-failed — `git fetch origin main` failed (unreachable remote, no
#      `origin`, no `main` on the remote, auth failure), or an ssh command
#      refused before the fetch for quoting or escaping up to its binary
#   5  merge-conflict — an unresolvable merge under `halt`, aborted; the tree
#      is clean
#   6  merge-failed — a merge refused for a non-conflict reason (an untracked
#      file in the way, a config refusal); aborted if it had started
#   7  abort-failed — the merge failed AND `git merge --abort` failed; the tree
#      is NOT clean and a resume must not assume it is
#   8  merge-conflict-left — a conflict under `resolve`, left in progress for
#      the worker to resolve and commit with --commit-resolution
#   9  policy-unreadable — a knob or the protected set could not be read; no
#      fetch is attempted
#   10 off-branch — a detached HEAD, a branch that is not a unit branch or is
#      protected, or one that is not the session's; nothing is touched
#   11 resolution-refused — --commit-resolution with no resolve-mode merge of
#      this script's in progress, a recorded source origin/main does not
#      contain, either knob no longer allowing it, an unmerged path, a leftover
#      conflict marker, or a staged change outside the conflicted paths;
#      nothing is committed. A conflicted name git still quotes is refused
#      with a park record, since only a human can resolve it
#   12 resolution-failed — stamping or committing the resolution failed; the
#      merge is left in progress
#
# Portable bash 3.2 / BSD tooling; no fish/mise/tmux dependency (REQ-K1.5).
# No LLM and no model/API call anywhere in the decision path (REQ-D1.4): the
# logic is deterministic shell over local git state and one fetch.
set -u

LC_ALL=C
export LC_ALL
unset CDPATH

# A headless worker that hits a credential prompt would hang the whole
# convergence loop with no output. Failing the fetch fast, with a reason the
# caller can act on, is the better of the two. Credential helpers still work;
# only interactive terminal prompting is disabled.
GIT_TERMINAL_PROMPT=0
export GIT_TERMINAL_PROMPT

# die <exit-code> <reason> <message> — the single failure surface. The reason
# token is what the caller greps for and what keeps the causes distinct
# (REQ-B1.6); the message is what a human reads (REQ-K1.1).
# printf, not echo: git's own stderr rides these messages and can carry
# backslashes, which some echo implementations would interpret.
die() {
  printf 'converge-sync-main: %s: %s\n' "$2" "$3" >&2
  exit "$1"
}

# park <exit-code> <reason> <message> — a failure the caller parks the unit on,
# with the message as the parking text. The record is one line of three
# fields, so a tab in the message becomes a space.
park() {
  printf 'park\t%s\t%s\n' "$2" "$(printf '%s' "$3" | tr '\t\n' '  ')"
  die "$@"
}

# scrub — strip control bytes from anything git or the filesystem hands back
# before it reaches a terminal, so a hostile branch name or path cannot smuggle
# escape sequences into the caller's output. TAB and LF are the only C0 bytes
# kept, because the output format is built from them; every other one goes,
# carriage return included — it needs no escape byte to overwrite the rendered
# line and forge a different message on top of a real one.
scrub() {
  tr -d '\000-\010\013-\037\177'
}

USAGE='usage: converge-sync-main.sh [--commit-resolution <spec>/<id> ...] [<repo-dir>]'
mode=sync
task_refs=()
while [ "$#" -gt 0 ]; do
  case $1 in
    --commit-resolution)
      [ "$#" -ge 2 ] || die 2 usage "--commit-resolution needs a <spec>/<id>; $USAGE"
      mode=commit
      task_refs[${#task_refs[@]}]=$2
      shift 2
      ;;
    --)
      shift
      break
      ;;
    -*) die 2 usage "unknown option; $USAGE" ;;
    *) break ;;
  esac
done
if [ "$#" -gt 1 ]; then
  die 2 usage "too many arguments; $USAGE"
fi

# Probe the binaries before anything reads git state. Without this an absent
# `git` surfaces through the work-tree check below as "not a git work tree",
# which sends the human to inspect a directory that is fine; and an absent `tr`
# empties `scrub`'s output, dropping the path out of the very message meant to
# identify the problem. `die` is safe to use even here: it is printf and exit,
# and reaches for neither of the binaries being probed.
for bin in git tr; do
  command -v "$bin" >/dev/null 2>&1 \
    || die 2 environment "$bin is not on PATH; the sync cannot run"
done

# The target is echoed back in two failure messages, so it gets the same
# newline collapse the git-stderr paths below use: a message a human reads on a
# halt is one line, whatever the path it names contains.
repo="${1:-.}"
repo_shown=$(printf '%s' "$repo" | tr '\n' ' ' | scrub)
[ -d "$repo" ] || die 2 usage "target directory not found: $repo_shown"

# `--is-inside-work-tree` prints `false` inside a bare repo's git dir, where
# there is nothing to merge into, so the value is checked rather than just the
# exit status.
inside=$(git -C "$repo" rev-parse --is-inside-work-tree 2>/dev/null || true)
[ "$inside" = true ] \
  || die 2 usage "not a git work tree: $repo_shown"

# --- policy: the branch and the knobs, before anything is fetched -----------

# Absolute, because the siblings run after a `cd` into another checkout, where
# a relative path would name that checkout's copies.
script_dir=$(cd -- "$(dirname -- "$0")" 2>/dev/null && pwd -P) \
  || die 2 environment "the directory holding this script could not be resolved"
for sib in resolve-policy-knob.sh protected-branch.sh planwright-commit-trailers.sh; do
  [ -f "$script_dir/$sib" ] && [ -r "$script_dir/$sib" ] \
    || die 2 environment "$sib is missing beside this script (broken install)"
done

for ref in ${task_refs[@]+"${task_refs[@]}"}; do
  printf '%s\n' "$ref" | grep -Eq '^(specs/)?[a-z0-9][a-z0-9-]{0,63}/[0-9]+(\.[0-9]+)?$' \
    || die 2 usage "--commit-resolution takes <spec>/<id>, and this one is malformed; $USAGE"
done

common_dir() { # <dir> — the absolute git common dir, or empty
  git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true
}
common=$(common_dir "$repo")
case $common in
  /*/.git) policy_root=${common%/.git} ;;
  *) park 9 policy-unreadable "the primary checkout of this repository could not be found from its git common dir, and the policy is read only there" ;;
esac

# read_knob <knob> <legal...> — sets KNOB, or parks.
read_knob() {
  local k=$1 v legal
  shift
  v=$(cd -- "$policy_root" && PLANWRIGHT_REPO_ROOT=$policy_root /bin/sh "$script_dir/resolve-policy-knob.sh" "$k" </dev/null) \
    || park 9 policy-unreadable "the policy knob $k could not be resolved, so the base sync does not run; repair the value, then resume"
  for legal in "$@"; do
    if [ "$v" = "$legal" ]; then
      KNOB=$v
      return 0
    fi
  done
  park 9 policy-unreadable "the policy knob $k resolved to a value this script does not recognize; set it to one of: $*"
}

# path_list <names> — newline-separated names as one scrubbed line ending in a
# space, ten at most.
path_list() {
  local n
  n=$(printf '%s\n' "$1" | grep -c . || true)
  printf '%s\n' "$1" | head -10 | tr '\n' ' ' | scrub
  [ "$n" -le 10 ] || printf '(and %s more) ' "$((n - 10))"
}

# The unit-branch grammar the policy guard admits.
is_unit_branch() {
  local re_task='^planwright/[a-z0-9][a-z0-9-]*/task-[0-9]+(\.[0-9]+)?(-[0-9]+(\.[0-9]+)?)?$'
  local re_flight='^planwright/flight/[a-z0-9][a-z0-9-]*-[0-9a-f]{8}$'
  case $1 in planwright/flight/task-*) return 1 ;; esac
  [[ $1 =~ $re_task ]] || [[ $1 =~ $re_flight ]]
}

branch=$(git -C "$repo" symbolic-ref --quiet --short HEAD 2>/dev/null || true)
[ -n "$branch" ] \
  || die 10 off-branch "no branch is checked out (a detached HEAD), so there is no unit branch to sync"
branch_shown=$(printf '%s' "$branch" | scrub)
is_unit_branch "$branch" \
  || die 10 off-branch "$branch_shown is not a unit branch (planwright/<spec>/task-<id> or planwright/flight/<id>); the sync merges only into one"
prc=0
(cd -- "$policy_root" && PLANWRIGHT_REPO_ROOT=$policy_root /bin/sh "$script_dir/protected-branch.sh" "$branch" </dev/null >/dev/null 2>&1) || prc=$?
case $prc in
  0) ;;
  1) die 10 off-branch "$branch_shown is in the protected set; an agent session merges only into its own unit branch" ;;
  *) park 9 policy-unreadable "the protected set could not be read (exit $prc), so the base sync does not run" ;;
esac
# The session's unit branch is the one its project directory has checked out:
# CLAUDE_PROJECT_DIR where the caller has it (hooks do; a Bash tool command
# does not), else the caller's own directory. A directory in another
# repository says nothing about this one.
pdir=${CLAUDE_PROJECT_DIR:-$PWD}
if [ -d "$pdir" ] && [ "$(common_dir "$pdir")" = "$common" ]; then
  pbranch=$(git -C "$pdir" symbolic-ref --quiet --short HEAD 2>/dev/null || true)
  [ "$pbranch" = "$branch" ] \
    || die 10 off-branch "$branch_shown is not this session's unit branch ($(printf '%s' "${pbranch:-none}" | scrub)); run the sync in your own worktree"
fi

# The resolve record: the fetched commit's sha, then the conflicted names; and
# beside it the index's merged entries outside them, as the conflict left
# them, so the resolution commit can carry nothing else.
resolve_state=$(git -C "$repo" rev-parse --path-format=absolute --git-path planwright-sync-resolve 2>/dev/null || true)
[ -n "$resolve_state" ] || die 2 environment "the git dir of $repo_shown could not be read"

# merged_entries <names-file> — the index's stage-0 entries outside the names
# the file lists after its first line.
merged_entries() {
  git -C "$repo" -c core.quotePath=false ls-files -s 2>/dev/null \
    | awk -F '\t' -v st="$1" '
      BEGIN { while ((getline l < st) > 0) if (++i > 1) skip[l] = 1 }
      { split($1, a, " "); if (a[3] == 0 && !($2 in skip)) print }'
}

# --- --commit-resolution: commit the merge a resolve-mode sync left ---------

if [ "$mode" = commit ]; then
  git -C "$repo" rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1 && [ -f "$resolve_state" ] \
    || die 11 resolution-refused "no merge left by a resolve-mode sync is in progress; run the sync first"
  merge_target=$(sed -n 1p "$resolve_state")
  [ "$(git -C "$repo" rev-parse -q --verify MERGE_HEAD 2>/dev/null)" = "$merge_target" ] \
    || die 11 resolution-refused "the merge in progress is not the one the resolve-mode sync left; abort it and re-run the sync"
  git -C "$repo" merge-base --is-ancestor "$merge_target" refs/remotes/origin/main 2>/dev/null \
    || die 11 resolution-refused "the merge in progress does not merge origin/main; abort it and re-run the sync"
  read_knob worker_base_merge allow deny
  [ "$KNOB" = allow ] \
    || die 11 resolution-refused "worker_base_merge is deny, so the resolution is not committed; abort the merge (git merge --abort), and the operator syncs this branch"
  read_knob worker_merge_conflict_policy halt resolve
  [ "$KNOB" = resolve ] \
    || die 11 resolution-refused "worker_merge_conflict_policy is $KNOB, so the resolution is not committed; abort the merge (git merge --abort) and re-run the sync"
  unmerged=$(git -C "$repo" -c core.quotePath=false diff --name-only --diff-filter=U 2>/dev/null)
  [ -z "$unmerged" ] \
    || die 11 resolution-refused "unresolved paths remain: $(path_list "$unmerged")— resolve and stage them first"
  names=$(sed 1d "$resolve_state")
  # git still quotes a name holding a quote, backslash, or control byte, and
  # a quoted name cannot be passed back as a pathspec.
  # A hand commit would carry no sign-off trailer, so this one goes to a human.
  if printf '%s\n' "$names" | grep -q '^"'; then
    park 11 resolution-refused "a conflicted path name needs quoting, which this script does not check; a human resolves this merge, stamping its commit through planwright-commit-trailers.sh --sign-off"
  fi
  rpaths=()
  while IFS= read -r p; do
    [ -n "$p" ] && rpaths[${#rpaths[@]}]=$p
  done <<EOF
$names
EOF
  if [ "${#rpaths[@]}" -gt 0 ] \
    && git -C "$repo" --literal-pathspecs diff --cached --check -- "${rpaths[@]}" 2>/dev/null | grep -q 'leftover conflict marker'; then
    die 11 resolution-refused "a resolved path still carries a conflict marker; finish the resolution and stage it"
  fi
  merged_entries "$resolve_state" | cmp -s - "$resolve_state.index" \
    || die 11 resolution-refused "the index changes paths outside the conflicted ones, which a resolution commit may not carry; unstage those changes (they belong in their own commit after the merge), and a directory/file conflict whose resolution moves a path elsewhere needs a human under halt"
  shown=$(path_list "$names")
  msg=$(mktemp) || die 12 resolution-failed "a scratch file could not be created"
  stamped=$(mktemp) || {
    rm -f "$msg"
    die 12 resolution-failed "a scratch file could not be created"
  }
  printf '%s\n' "Merge origin/main, resolving conflicts" "" \
    "Base-merge resolution: ${shown% }" \
    "Route reason: worker_merge_conflict_policy is resolve, so the agent resolved this base merge's conflicts; the resolution awaits the approval act." >"$msg"
  if ! (cd -- "$repo" && /bin/sh "$script_dir/planwright-commit-trailers.sh" "${task_refs[@]}" --base "$merge_target" --sign-off <"$msg" >"$stamped"); then
    rm -f "$msg" "$stamped"
    die 12 resolution-failed "the sign-off trailer could not be stamped; the merge is still in progress"
  fi
  if ! commit_err=$(git -C "$repo" commit -q -F "$stamped" 2>&1 >/dev/null); then
    rm -f "$msg" "$stamped"
    die 12 resolution-failed "git commit refused the resolution, and the merge is still in progress: $(printf '%s' "$commit_err" | tr '\n' ' ' | scrub)"
  fi
  rm -f "$msg" "$stamped" "$resolve_state" "$resolve_state.index"
  head=$(git -C "$repo" rev-parse HEAD)
  ps=$(git -C "$repo" log -1 --format='%(trailers:key=Planwright-Sign-Off,valueonly)' | tr -d '\n')
  printf 'resolution\t%s\t%s\n' "$head" "$ps"
  exit 0
fi

read_knob worker_base_merge allow deny
base_merge=$KNOB
# A record whose merge is gone (aborted by hand) describes nothing.
git -C "$repo" rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1 \
  || rm -f "$resolve_state" "$resolve_state.index"

# ssh prompts on its own channel, which `GIT_TERMINAL_PROMPT` does not reach:
# an unverified host key or a passphrase-protected key would block the fetch
# just as hard as a credential prompt. `BatchMode=yes` turns both into a
# fetch-failed exit the caller can act on. The cost is deliberate and worth
# naming: first contact with a host absent from `known_hosts` now fails instead
# of asking, making that a setup step rather than something the sync completes.
# An agent-held key is unaffected, which is the fleet's normal case.
#
# The base command follows git's own precedence as far as this script reads
# it: the caller's GIT_SSH_COMMAND when set and non-empty, otherwise the
# `core.sshCommand` in effect for the target repo, otherwise plain `ssh`.
# Deliberate departures from git: an empty GIT_SSH_COMMAND falls through to
# the config, and an empty `core.sshCommand` falls through to `ssh`, where
# git would try to run the empty string in either case; and the legacy
# GIT_SSH variable is not consulted, so a host relying on it alone still
# loses it to the export below. Exporting GIT_SSH_COMMAND outranks the config
# in git's precedence, so building on bare `ssh` would silently discard a
# host's configured key and IdentitiesOnly, and the fetch would fail on
# exactly the hosts whose remote access depends on that config. This is why
# the block sits after the work-tree check: the config belongs to the target
# repo, not to the directory the script was launched from.
#
# The option has to WIN, not merely be present: ssh_config(5) specifies that
# the FIRST obtained value of a parameter is the one used, so appending after
# an incoming `-o BatchMode=no` would leave the prompt live and hang the loop
# exactly as if the guard were absent. When the incoming command names
# BatchMode at all, ours goes in directly after the ssh binary so it is read
# first, and the override is reported rather than silently discarded. The
# ordinary case (no BatchMode in the incoming command) still just appends,
# which keeps the common path clear of any parsing of the command string.
#
# The match is case-insensitive because ssh reads option names that way: a
# `batchmode=no` keeps the prompt live exactly as the canonical spelling
# does, so it has to be outranked, not left in place. And the binary is the
# first word AFTER any leading blanks and `VAR=value` assignments (git hands
# the string to a shell, where those are an environment prefix, not the
# command): splicing before the binary would make the shell run `-o` and the
# fetch would fail without ever reaching ssh. Quoting is not parsed: quoted
# or escaped text before or in the ssh binary is refused rather than spliced,
# since a cut at the wrong word can leave the prompt live or run the wrong
# binary.
_ssh_src=GIT_SSH_COMMAND
_ssh_cmd=${GIT_SSH_COMMAND:-}
if [ -z "$_ssh_cmd" ]; then
  _ssh_src=core.sshCommand
  _ssh_cmd=$(git -C "$repo" config --get core.sshCommand 2>/dev/null || true)
fi
[ -n "$_ssh_cmd" ] || _ssh_cmd=ssh
case "$(printf '%s' "$_ssh_cmd" | tr '[:upper:]' '[:lower:]')" in
  *batchmode*)
    _ssh_pre=
    _ssh_rest=$_ssh_cmd
    while :; do
      _ssh_ws=${_ssh_rest%%[![:space:]]*}
      _ssh_pre=$_ssh_pre$_ssh_ws
      _ssh_rest=${_ssh_rest#"$_ssh_ws"}
      _ssh_bin=${_ssh_rest%%[[:space:]]*}
      case "$_ssh_bin" in
        *=*) ;;
        *) break ;;
      esac
      case "${_ssh_bin%%=*}" in
        '' | [0-9]* | *[!A-Za-z0-9_]*) break ;;
      esac
      _ssh_pre=$_ssh_pre$_ssh_bin
      _ssh_rest=${_ssh_rest#"$_ssh_bin"}
    done
    case "$_ssh_pre$_ssh_bin" in
      *[\'\"\\]*)
        park 4 fetch-failed "refusing to add BatchMode=yes to $_ssh_src: it has a quote or backslash before or in the ssh binary, which this sync does not parse; no fetch was attempted and the tree is unchanged — unquote that part of the command and retry"
        ;;
    esac
    GIT_SSH_COMMAND="$_ssh_pre$_ssh_bin -o BatchMode=yes${_ssh_rest#"$_ssh_bin"}"
    printf 'converge-sync-main: note: %s already sets BatchMode; forcing BatchMode=yes so the fetch cannot block on a prompt\n' "$_ssh_src" >&2
    ;;
  *)
    GIT_SSH_COMMAND="$_ssh_cmd -o BatchMode=yes"
    ;;
esac
export GIT_SSH_COMMAND
unset _ssh_cmd _ssh_bin _ssh_src _ssh_pre _ssh_rest _ssh_ws

# --- pre-flight: the tree must be clean BEFORE the network -------------------
#
# Ordering is deliberate. A dirty tree is a dirty tree whether or not the remote
# answers, and checking it first means the sync never spends a fetch to
# rediscover that, and never reports a fetch failure for a run it was going to
# refuse anyway.

# resolve_left <target> <names> — print the resolve record and exit 8.
resolve_left() {
  local msg
  msg="origin/main conflicts with this branch on: $(path_list "$2")— worker_merge_conflict_policy is resolve, so the merge is left in progress: resolve and stage those paths, then run converge-sync-main.sh --commit-resolution <spec>/<id>"
  printf 'resolve\t%s\t%s\n' "$1" "$msg"
  die 8 merge-conflict-left "$msg"
}

for op in MERGE_HEAD REBASE_HEAD CHERRY_PICK_HEAD REVERT_HEAD; do
  if git -C "$repo" rev-parse -q --verify "$op" >/dev/null 2>&1; then
    # A retry finding the merge this script left under `resolve` gets the
    # same answer again, not a park.
    if [ "$op" = MERGE_HEAD ] && [ "$base_merge" = allow ] && [ -f "$resolve_state" ] \
      && [ "$(git -C "$repo" rev-parse -q --verify MERGE_HEAD 2>/dev/null)" = "$(sed -n 1p "$resolve_state")" ]; then
      read_knob worker_merge_conflict_policy halt resolve
      [ "$KNOB" != resolve ] || resolve_left "$(sed -n 1p "$resolve_state")" "$(sed 1d "$resolve_state")"
    fi
    park 3 dirty-tree "an operation is already in progress ($op exists) — finish or abort it before the sync can merge origin/main"
  fi
done

if [ "$base_merge" = deny ]; then
  printf 'converge-sync-main: note: worker_base_merge is deny, so the base is not merged; the operator syncs this branch\n' >&2
  printf 'sync\tdenied\t%s\n' "$(git -C "$repo" rev-parse HEAD)"
  exit 0
fi
read_knob worker_merge_conflict_policy halt resolve
conflict_policy=$KNOB

# Untracked files are deliberately excluded: they cannot make a merge ambiguous
# on paths the merge does not touch, and a worker's scratch output is not a
# reason to halt a unit. An untracked file that IS in the merge's way surfaces
# on the merge itself, as `merge-failed` — its own reason, not this one.
dirty=$(git -C "$repo" status --porcelain --untracked-files=no 2>/dev/null || true)
if [ -n "$dirty" ]; then
  count=$(printf '%s\n' "$dirty" | grep -c '' || true)
  park 3 dirty-tree "the working tree has $count uncommitted tracked change(s) — commit or discard them before the sync can merge origin/main"
fi

# --- fetch -------------------------------------------------------------------
#
# The remote and branch are literal: D-4 targets `origin/main` specifically, the
# worker-convergence base by planwright convention. A PR on some other base is
# the ready-guard's job, which reads each PR's real base server-side and needs
# no per-base handling here.

fetch_err=$(git -C "$repo" fetch origin main 2>&1 >/dev/null) || {
  park 4 fetch-failed "git fetch origin main failed — the remote is unreachable, absent, or refused the read: $(printf '%s' "$fetch_err" | tr '\n' ' ' | scrub)"
}

target=$(git -C "$repo" rev-parse --verify FETCH_HEAD 2>/dev/null || true)
[ -n "$target" ] \
  || park 4 fetch-failed "git fetch origin main left no FETCH_HEAD to merge"

# --- merge -------------------------------------------------------------------

# Already current: FETCH_HEAD is in the branch's history, so there is nothing to
# merge. This is the modal outcome on a quiet `main` and must stay a clean
# no-op — it neither moves the head nor makes an empty commit.
if git -C "$repo" merge-base --is-ancestor "$target" HEAD 2>/dev/null; then
  head=$(git -C "$repo" rev-parse HEAD)
  printf 'sync\tup-to-date\t%s\n' "$head"
  exit 0
fi

# Classified before the merge runs, because afterwards the two are
# indistinguishable from the resulting history alone.
kind=merged
if git -C "$repo" merge-base --is-ancestor HEAD "$target" 2>/dev/null; then
  kind=fast-forward
fi

# `--no-edit` so a tty-attached run never blocks on an editor (D-4).
# `-c merge.ff=true` pins the default at the call site: an ambient
# `merge.ff=only` would otherwise refuse every real merge, and `merge.ff=false`
# would manufacture a merge commit for a fast-forward that needs none.
merge_err=$(git -C "$repo" -c merge.ff=true merge --no-edit FETCH_HEAD 2>&1 >/dev/null) || {
  # `diff --diff-filter=U`, not `ls-files --unmerged`: it prints one path per
  # line already deduplicated across the three stages, so a path containing a
  # space survives into the message intact instead of being cut at the first
  # field.
  unmerged=$(git -C "$repo" -c core.quotePath=false diff --name-only --diff-filter=U 2>/dev/null)

  # Under `resolve` a conflict is the worker's to settle, so the merge stays.
  unrecorded=''
  if [ "$conflict_policy" = resolve ] && [ -n "$unmerged" ] \
    && [ "$(git -C "$repo" rev-parse -q --verify MERGE_HEAD 2>/dev/null)" = "$target" ]; then
    if printf '%s\n%s\n' "$target" "$unmerged" >"$resolve_state" 2>/dev/null \
      && merged_entries "$resolve_state" >"$resolve_state.index" 2>/dev/null; then
      resolve_left "$target" "$unmerged"
    fi
    rm -f "$resolve_state" "$resolve_state.index"
    unrecorded=' (worker_merge_conflict_policy is resolve, but the record of the merge could not be written in the git dir, so it was aborted)'
  fi

  # Abort whatever the merge left behind, before reporting. A conflict that is
  # not aborted leaves MERGE_HEAD in place and the NEXT sync fails on the stale
  # merge instead of the real cause (REQ-B1.3).
  if git -C "$repo" rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1; then
    if ! git -C "$repo" merge --abort >/dev/null 2>&1; then
      printf 'repair\tabort-failed\t%s\n' "no park: the origin/main merge failed and git merge --abort could not undo it; halt, and name this hand repair of the working tree in the handoff"
      die 7 abort-failed "the origin/main merge failed AND git merge --abort could not undo it — the working tree is NOT clean and must be repaired by hand before this unit resumes"
    fi
  fi

  if [ -n "$unmerged" ]; then
    park 5 merge-conflict "origin/main conflicts with this branch on: $(path_list "$unmerged")— the merge was aborted and the tree is clean$unrecorded; land origin/main's changes here (or resolve upstream) before convergence resumes"
  fi

  park 6 merge-failed "the origin/main merge was refused for a non-conflict reason: $(printf '%s' "$merge_err" | tr '\n' ' ' | scrub)"
}

head=$(git -C "$repo" rev-parse HEAD)
printf 'sync\t%s\t%s\n' "$kind" "$head"
exit 0
