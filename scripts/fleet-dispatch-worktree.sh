#!/bin/sh
# fleet-dispatch-worktree.sh — the tmux-backend dispatch primitive that produces
# a worker worktree on the canonical D-36 branch `planwright/<spec>/task-<id>`
# (or, on its flight arm, a visual flight's `planwright/flight/<flight-id>`)
# DETERMINISTICALLY at launch, with no manual post-launch `git branch -m` rename
# (fleet-hardening Task 10; D-7 amended 2026-07-20; REQ-B1.4, and REQ-C1.1 /
# REQ-C1.2 / REQ-E1.3 for the tower-guard interaction).
#
# Mechanism, in two steps (D-7):
#   1. CREATE the worktree with a SINGLE
#        git worktree add -b planwright/<spec>/task-<id> \
#          .claude/worktrees/<suffix> <base>
#      (the flight arm: `-b planwright/flight/<flight-id>` into
#      `.claude/worktrees/flight-<flight-id>`)
#      call — the narrow, documented never-shell-`git worktree` exception scoped
#      to THIS one dispatch primitive (D-7). `<base>` is the freshly-fetched
#      `origin/main` (never stale local `main` or the tower's HEAD — the
#      fetch-before-act discipline of D-9, via scripts/dispatch-fetch.sh);
#      `<suffix>` is a DETERMINISTIC function of (spec, task-id):
#      `<spec>-task-<id>`. The spec segment is what keeps it unique —
#      `.claude/worktrees/` is one flat namespace, so the bare `task-<id>` form
#      collided between any two specs sharing a task number (`attach` also
#      takes a flight's `flight-<flight-id>` suffix);
#      and `<spec>` / `<id>` / `<suffix>` are VALIDATED against the D-36 grammar
#      BEFORE interpolation and passed to git as ARGV (never spliced into a shell
#      string), so no shell metacharacter or `..` path-traversal can reach the
#      command.
#   2. LAUNCH: create the worker's DETACHED classic tmux session in the
#      already-placed worktree, in one tmux invocation that also turns
#      remain-on-exit off for its window:
#        tmux new-session -d -s <session> -c <physical worktree> \
#          -P -F '#{session_name}<TAB>#{window_id}' -- fleet-dispatch-env.sh \
#          <wrapper options> <absolute claude> <launch args> [-- <prompt>] \
#          ';' set-window-option -t '=<session>:' remain-on-exit off
#      and return once the session exists, never waiting on the worker and
#      never moving a tmux client. The launch runs ONLY if step 1 exited zero.
#      The worker runs THROUGH scripts/fleet-dispatch-env.sh inside the
#      session, so the ghost-text pin, the dispatcher's root and fleet home,
#      the worker identity, and a per-launch token reach the worker itself
#      whatever the tmux server's environment holds. The registry record is
#      written once, after new-session succeeds, its death handle the session
#      name and window id new-session printed, never a pane-path match. Then
#      CONFIRM: until the worker's startup confirmation is wired, a created
#      session reports started-unconfirmed, which every caller treats as
#      placed.
#
# Launch safety, all checked before any durable side effect (worktree, branch,
# dispatch marker, registry record) unless named otherwise:
#   - the physical worktree path is on the path charset [A-Za-z0-9._/@+-] and
#     the session name on [A-Za-z0-9_@-], alphanumeric first, at most 128
#     bytes: tmux format-expands both, and an allowlist does not depend on
#     knowing which bytes a given tmux version expands;
#   - `claude` resolves to an absolute executable file and `tmux` resolves;
#   - no live session already holds the session name;
#   - the env wrapper's --check accepts the launch options;
#   - no launch word ends in `;`, which tmux would read as a command separator;
#   - immediately before new-session, the start directory still exists and is
#     exactly <physical repo root>/.claude/worktrees/<suffix>; tmux would
#     otherwise start the pane in its fallback directory without a word.
# The session name is `<base>-<hash6>_<suffix'>`: <base> the primary
# checkout's physical basename with bytes outside [A-Za-z0-9@-] written `-`,
# leading non-alphanumerics dropped (`repo` if none remain), at most 32 bytes;
# <hash6> the first six of the eight zero-padded hex digits of the cksum CRC of
# its physical path; <suffix'> the suffix with `.` written `_`, as tmux would.
# A new-session that loses a race for the name touches nothing the winner
# owns; any other failure after the create undoes only what this run created.
#
# Splitting create-then-attach makes the exact D-36 branch name a guaranteed
# OUTPUT rather than a rename an operator must remember: the mangled
# `worktree-<suffix>` name that native `claude --worktree <suffix>` would produce
# is never this primitive's output, so the tasks-PR-sync hook can always map the
# branch back to its task (a merged task never reads as unmerged).
#
# Collision / orphan reconcile (D-7). `<suffix>` and the branch are deterministic
# per task, so a concurrent or repeat dispatch collides. Detection RELIES on
# `git worktree add -b`'s own atomic non-zero exit (git locks the worktrees admin
# dir; `-b` refuses an existing branch) — never a check-then-create pre-check,
# which would race (TOCTOU). On that failure the primitive RECONCILES rather than
# blindly aborting, distinguishing in-flight from stale via this bundle's
# liveness signals (the dispatch marker scripts/orchestrate-marker.sh writes, and
# a live tmux session under the launch's session name or, while workers started
# by the prior `claude --worktree` launcher may still run, under that launcher's
# `<repo-basename'>_worktree-<suffix'>` spelling — not a new source of truth; a
# probe name outside the session charset is never sent and reads as live):
#   - LIVE dispatch in flight  -> abort as already-in-flight (exit 3). On the
#     flight arm a registered flight worktree is in flight whatever its
#     session says, so it aborts the same way and is never GC'd below. A
#     worktree list that cannot be read counts as registered, so no removal
#     below acts on a worktree it could not see.
#   - STALE / orphaned branch or worktree with no live session (a prior create
#     that died before attach, or a finished task whose branch outlived its
#     worktree) -> GC-adopt: remove the leftover worktree checkout; adopt the
#     existing branch when it carries work (place a fresh worktree on it), or
#     roll it back (delete the just-made branch) when it is a bare partial
#     create; then proceed, so a crash can never wedge a task as permanently
#     already-in-flight. A leftover EMPTY `.claude/worktrees/<suffix>` dir (which
#     `git worktree add` would otherwise SILENTLY create into) is cleaned, not
#     silently reused.
#   - Branch CHECKED OUT ELSEWHERE (under a registered worktree at some other
#     path: the pre-`<spec>-task-<id>` flat `task-<id>` layout, or a checkout
#     made by hand) -> stop with exit 6 naming that path. It is neither a
#     partial create nor an adoptable orphan: git refuses to check a branch out
#     twice and refuses to delete a checked-out branch, so the GC arms above
#     cannot act on it and would only misreport a roll-back that never ran.
#     Nothing is touched; the message carries the `git worktree move` that
#     brings the checkout to the path this primitive expects. A live session
#     under the old path's name still reads as in-flight (exit 3).
#
# Exception scope (D-7). The `git worktree add` shell-out is confined to THIS
# primitive, its task and flight arms alike (scripts/flight-dispatch.sh places
# a flight through the flight arm rather than shelling out itself): a guard over
# the bundle's dispatch/tower sources (tests/test-fleet-dispatch-worktree.sh)
# asserts no other bundle worktree-creation path shells out to `git worktree`.
# The tower runs this primitive as a planwright script by resolved literal path
# (worker/tower-command-guard `is_repo_script` allowance),
# so the inner `git worktree add` is never a separate PreToolUse Bash string
# exposed to the stochastic auto-mode classifier; the tower deny floor
# (config/tower-settings.json) additionally names the dangerous `git worktree`
# forms (default-branch / detach / `--force`) as defense-in-depth.
#
# No model/API call anywhere in the branch-naming decision path (REQ-E1.3): the
# whole path is deterministic string logic + git plumbing.
#
# Usage:
#   fleet-dispatch-worktree.sh dispatch <spec> <id> \
#       [--repo-root <dir>] [--launch-only | --attach-dry-run | --no-attach] \
#       [-- <extra launch args>...]
#       Validate, fetch `<base>`, reconcile, `git worktree add -b`, launch, then
#       confirm. The report is `dispatch<TAB><key><TAB><value>` lines (branch,
#       worktree, base), `launch` lines (session, window, handle, since), and
#       `confirm` lines (outcome, session, handle, reason).
#       --repo-root      the primary checkout (default: resolve-root.sh repo --primary).
#       --launch-only    launch and report, without the confirm step, for a
#                        caller that releases a lock before confirming (the
#                        flight dispatch); exit 0 once the session exists.
#       --attach-dry-run create for real, but PRINT the launch plan instead of
#                        launching (no `claude` exec, no model/API call).
#       --no-attach      create-only (execution-backends Task 3): the full
#                        create machinery with no worker launched and no plan,
#                        printing the dispatch record only — for a backend
#                        that launches its own worker into the created worktree
#                        (the headless-oneshot rung, fleet-dispatch-headless.sh).
#                        Launches no worker, so it takes no post-`--` launch
#                        args (refused, not dropped), and the tmux rung's
#                        charset does not apply to it.
#       Everything after `--` is passed through to the `claude` launch argv.
#   fleet-dispatch-worktree.sh dispatch --flight <flight-id> [--brief <abs-file>] \
#       [--repo-root <dir>] [--launch-only | --attach-dry-run | --no-attach] \
#       [-- <extra launch args>...]
#       The same create-then-launch for a visual flight (tower-front-door D-11):
#       branch `planwright/flight/<flight-id>`, worktree `flight-<flight-id>`,
#       no spec bundle and no dispatch marker. A collision on a registered
#       flight worktree aborts as already-in-flight whatever its tmux session
#       says (a print-rung worker has none); only an unregistered remnant is
#       reconciled.
#       --brief          the worker brief the launch hands the worker, as the
#                        one prompt `Read <abs-file> and follow it exactly.`
#                        after `--` (the path, never the content, rides argv).
#                        Only the flight's own `<fleet-home>/flights/<flight-id>/
#                        brief.md` is accepted, after canonicalization, on the
#                        path charset `[A-Za-z0-9._/@+-]`, non-empty, with the
#                        fleet home, its flights directory, and the brief's
#                        own directory private to the user; an empty
#                        `--brief` is refused, and so are `--continue` and
#                        `--resume` beside it.
#   fleet-dispatch-worktree.sh attach <suffix> --dry-run [--brief <abs-file>] [-- <extra>...]
#       Print the launch plan for `<repo>/.claude/worktrees/<suffix>` (no
#       exec). A live standalone attach is refused (exit 2): the only live
#       launch is the dispatch arm's, after its path-escape guard. --brief
#       takes a flight's brief, as the dispatch arm does and under the same
#       confinement; the suffix must be `flight-<flight-id>`.
#   fleet-dispatch-worktree.sh confirm --session <name> --handle <handle> [--since <epoch>]
#       The confirm step a --launch-only caller runs once it has released its
#       lock. Until the worker's startup confirmation is wired it reports
#       started-unconfirmed (exit 14), which a caller treats as placed.
#   fleet-dispatch-worktree.sh check-session-name <name>
#       Exit 0 when <name> is on the session-name charset, 10 otherwise.
#
# Exit codes:
#   0  success: the plan printed, the create-only record printed, or (with
#      --launch-only) the session created.
#   2  usage / invalid input (fail closed — a malformed or hostile token is
#      never interpolated), a launch word ending in `;`, or a live standalone
#      attach.
#   3  already-in-flight: a LIVE concurrent/repeat dispatch, a live session
#      already holding the session name, a new-session that lost the race for
#      it (nothing touched), a registered flight worktree, or on the flight arm
#      a worktree list that cannot be read (the intended collision guard).
#   4  cannot resolve a fresh `<base>`: the remote is present but the fetch
#      failed after retries (stale ref) — the dispatch must not proceed on a
#      stale base.
#   5  create failed for a non-reconcilable reason (fs/lock/internal error), or
#      the path-escape guard refused a symlinked or uncontained worktree root.
#   6  the branch is checked out under another registered worktree path and
#      no live session holds it: nothing was changed; the message names the
#      path and the `git worktree move` that resolves it.
#   7  `claude` does not resolve to an absolute path of an executable file.
#   8  `tmux` does not resolve.
#   9  the physical worktree path is outside the path charset; this checkout
#      cannot use the tmux rung (the other rungs are unaffected).
#   10 the session name is outside the session-name charset or over 128 bytes.
#   11 the start directory is missing or is not the placed worktree; this
#      run's creations are undone.
#   12 the env wrapper's --check refused the launch options, or the
#      dispatcher's planwright root or fleet home could not be resolved.
#   13 new-session failed for a reason other than a lost race; this run's
#      creations are undone, and an undo step that fails is named.
#   14 started-unconfirmed: the session was created and no startup
#      confirmation arrived. The worker is placed; never re-dispatch over it.
#
# Portable POSIX sh (bash 3.2 / BSD compatible): no eval, no bashisms, input
# treated as data only.
# set -uf: pathname expansion disabled (the dispatch-path house convention —
# dispatch-fetch.sh / orchestrate-marker.sh / fleet-worktree-track.sh), so a
# stray glob metacharacter is never expanded even though every expansion below
# is already quoted and grammar-validated.
set -uf

LC_ALL=C
export LC_ALL
unset CDPATH

script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2
# Guarded source with an inline fallback, matching dispatch-fetch.sh: a missing
# echo-safety.sh must not turn every sanitize_printable on an error path into a
# "command not found" (set -e is unset, so the source would not otherwise abort).
if [ -r "$script_dir/echo-safety.sh" ]; then
  # shellcheck source=scripts/echo-safety.sh
  . "$script_dir/echo-safety.sh"
else
  sanitize_printable() {
    printf '%s' "$1" | tr -d '\000-\037\177'
  }
fi

FETCH="$script_dir/dispatch-fetch.sh"
ENVWRAP="$script_dir/fleet-dispatch-env.sh"
MARKER="$script_dir/orchestrate-marker.sh"
TRACK="$script_dir/fleet-worktree-track.sh"
FLEET_STATE="$script_dir/fleet-state.sh"

# How recent an orchestrate-marker must be to count as a LIVE dispatch when no
# tmux session is present. A marker older than this (a crashed dispatch that
# never cleared its marker) is treated as stale and reconciled, so a crash never
# wedges a task. Overridable for tests.
LIVENESS_TTL="${PLANWRIGHT_DISPATCH_LIVENESS_TTL:-900}"
# A non-numeric override must not make the age comparison error and degrade
# toward the unsafe (treat-live-as-stale) direction — fall back to the default.
case $LIVENESS_TTL in
  '' | *[!0-9]*) LIVENESS_TTL=900 ;;
esac

warn() {
  # Untrusted values are sanitized before they reach stderr.
  printf '%s\n' "fleet-dispatch-worktree: $(sanitize_printable "$1")" >&2
}

usage() {
  cat >&2 <<'EOF'
usage: fleet-dispatch-worktree.sh dispatch <spec> <id> [--repo-root <dir>] [--launch-only | --attach-dry-run | --no-attach] [-- <extra launch args>...]
       fleet-dispatch-worktree.sh dispatch --flight <flight-id> [--brief <abs-file>] [--repo-root <dir>] [--launch-only | --attach-dry-run | --no-attach] [-- <extra launch args>...]
       fleet-dispatch-worktree.sh attach <suffix> --dry-run [--brief <abs-file>] [-- <extra launch args>...]
       fleet-dispatch-worktree.sh confirm --session <name> --handle <handle> [--since <epoch>]
       fleet-dispatch-worktree.sh check-session-name <name>
EOF
  exit 2
}

REGISTER="$script_dir/fleet-register.sh"
TAB=$(printf '\t')

# The one prompt a flight dispatch hands its worker (dispatch --flight --brief);
# empty for every other launch.
ATTACH_PROMPT=''

# --- Session names --------------------------------------------------------
# SESSION_PREFIX and PRIOR_BASE are set by init_session_names from the primary
# checkout; every name below derives from them.
SESSION_PREFIX=''
PRIOR_BASE=''

# valid_session_name <name> — the session-name charset: the registry's tmux
# token grammar without `.`, which tmux rewrites, so every name the launch
# creates is also a valid death handle.
valid_session_name() {
  case $1 in
    '' | [!A-Za-z0-9]* | *[!A-Za-z0-9_@-]*) return 1 ;;
  esac
  [ "${#1}" -le 128 ]
}

# valid_launch_path <path> — the path charset every path handed to tmux must
# hold to, since tmux format-expands a start directory.
valid_launch_path() {
  case $1 in
    /*) ;;
    *) return 1 ;;
  esac
  case $1 in
    *[!A-Za-z0-9._/@+-]*) return 1 ;;
  esac
  return 0
}

# init_session_names <primary-physical> — the checkout's name prefix
# `<base>-<hash6>` and the prior launcher's basename spelling. The hash keeps
# two clones with one directory name apart; it is disambiguation, not
# security, and two checkouts colliding on it fail closed as a live name.
init_session_names() {
  isn_base=$(printf '%s' "${1##*/}" | tr -c 'A-Za-z0-9@-' '-' | sed 's/^[^A-Za-z0-9]*//' | cut -c1-32)
  [ -n "$isn_base" ] || isn_base=repo
  isn_crc=$(printf '%s' "$1" | cksum | awk '{ print $1 }')
  case $isn_crc in
    '' | *[!0-9]*) return 1 ;;
  esac
  SESSION_PREFIX="$isn_base-$(printf '%08x' "$isn_crc" | cut -c1-6)"
  PRIOR_BASE=$(printf '%s' "${1##*/}" | tr '.:' '__')
}

# worker_session <suffix> — the session the launch creates for <suffix>; the
# `.` of a dotted task id written `_`, as tmux would store it.
worker_session() {
  printf '%s_%s' "$SESSION_PREFIX" "$(printf '%s' "$1" | tr . _)"
}

# prior_session <suffix> — the session the prior `claude --worktree` launcher
# created for <suffix>, as tmux stored it.
prior_session() {
  printf '%s_worktree-%s' "$PRIOR_BASE" "$(printf '%s' "$1" | tr '.:' '__')"
}

# session_probe_live <name> — a live session holds <name>. A name outside the
# charset is never sent to tmux and reads as live, the probes' fail-safe
# direction.
session_probe_live() {
  valid_session_name "$1" || return 0
  tmux has-session -t "=$1" 2>/dev/null
}

# suffix_session_live <suffix> — a live session under either spelling.
suffix_session_live() {
  [ "$LIVENESS_SKIP_TMUX" != 1 ] || return 1
  command -v tmux >/dev/null 2>&1 || return 1
  session_probe_live "$(worker_session "$1")" && return 0
  session_probe_live "$(prior_session "$1")"
}

# register_dispatch <handle> <scope> <worktree> <death-handle> — write the
# dispatch record through the one registration seam (fleet-lifecycle-closure
# Task 3; REQ-E1.1, REQ-E1.2). Best-effort BY CONTRACT (REQ-E1.4): the exit is
# discarded, because a worktree and a worker that exist are facts, and failing
# a dispatch over its bookkeeping would trade the thing for the record of it.
# stderr is deliberately left alone — a dispatch the fleet has no record of is
# the leak this bundle exists to close, so it has to be visible.
register_dispatch() {
  # Readable, not executable: the call below is `/bin/sh <path>`, so the exec
  # bit is not what it depends on. Gating on `-x` would let a checkout with
  # core.fileMode=false, an unzip, or an `rsync` without `-p` switch
  # registration off fleet-wide with nothing on stderr.
  if [ ! -r "$REGISTER" ]; then
    warn "cannot register $1: $REGISTER is missing or unreadable; this worker will not appear in the fleet inventory"
    return 0
  fi
  rd_death=${5:-}
  set -- --handle "$1" --scope "$2" --backend tmux --state-dir "$3" \
    --checkout "$4"
  [ -n "$rd_death" ] && set -- "$@" --death-handle "$rd_death"
  /bin/sh "$REGISTER" "$@" >/dev/null </dev/null || true
}

# parse_created <file> <session> — set CREATED_WINDOW to the window id
# new-session printed for <session>, from the one line its -P -F format
# writes. Fails on anything else: a wrong death handle aims a reaper at
# someone else's window, so no handle beats a guessed one.
CREATED_WINDOW=''
parse_created() {
  CREATED_WINDOW=''
  [ -s "$1" ] || return 1
  [ "$(wc -l <"$1" | tr -d ' ')" = 1 ] || return 1
  IFS= read -r pc_line <"$1" || return 1
  pc_name=${pc_line%%"$TAB"*}
  pc_win=${pc_line#*"$TAB"}
  [ "$pc_name" = "$2" ] || return 1
  case $pc_win in
    @*) ;;
    *) return 1 ;;
  esac
  case ${pc_win#@} in
    '' | *[!0-9]*) return 1 ;;
  esac
  [ "${#pc_win}" -le 128 ] || return 1
  CREATED_WINDOW=$pc_win
}

# --- Token grammars (D-36), validated BEFORE any interpolation ---------------
# A `..` substring is rejected outright (path traversal) in every token, even
# though the charsets below already exclude `/`.

reject_dotdot() {
  case $1 in
    *..*) return 1 ;;
    *) return 0 ;;
  esac
}

# spec id: the REQ-A1.8 identifier charset, <=64 chars.
valid_spec() {
  reject_dotdot "$1" || return 1
  case $1 in
    '' | *[!a-z0-9-]* | [!a-z0-9]*) return 1 ;;
    flight) return 1 ;; # the reserved flight branch segment (tower-front-door D-11)
  esac
  [ "${#1}" -le 64 ] || return 1
  return 0
}

# task id: single or dotted-decimal (`5` or `3.5`).
valid_id() {
  reject_dotdot "$1" || return 1
  case $1 in
    '' | *[!0-9.]*) return 1 ;;
  esac
  printf '%s' "$1" | grep -Eq '^[0-9]+(\.[0-9]+)?$' || return 1
  return 0
}

# flight id: `<slug>-<uid>`, re-encoded from scripts/flight-id.sh (the
# reference check) so this primitive stands alone. `grep` matches per line, so
# the charset screen runs first to keep a newline from smuggling a second one.
valid_flight() {
  reject_dotdot "$1" || return 1
  case $1 in
    '' | *[!a-z0-9-]*) return 1 ;;
  esac
  [ "${#1}" -le 64 ] || return 1
  printf '%s' "$1" | grep -Eq '^[a-z0-9][a-z0-9-]*-[0-9a-f]{8}$'
}

# BRIEF_PATH — the canonical path valid_brief accepted.
BRIEF_PATH=''

# valid_brief <path> <flight-id> — the brief the attach hands a flight worker
# is that flight's own `brief.md` under the fleet home, after canonicalization,
# on a conservative charset: its path rides the prompt argv, so no other file
# can be handed to a worker as its instructions.
valid_brief() {
  case $1 in
    /*) ;;
    *) return 1 ;;
  esac
  reject_dotdot "$1" || return 1
  case $1 in
    *[!A-Za-z0-9._/@+-]*) return 1 ;;
  esac
  [ "$(basename "$1")" = brief.md ] || return 1
  [ -f "$1" ] && [ -r "$1" ] && [ -s "$1" ] && [ ! -L "$1" ] || return 1
  _vb_dir=$(cd "$(dirname "$1")" 2>/dev/null && pwd -P) || return 1
  _vb_home=$(/bin/sh "$FLEET_STATE" root 2>/dev/null </dev/null) || return 1
  [ -n "$_vb_home" ] || return 1
  _vb_home=$(cd "$_vb_home" 2>/dev/null && pwd -P) || return 1
  [ "$_vb_dir" = "$_vb_home/flights/$2" ] || return 1
  case $_vb_dir in
    *[!A-Za-z0-9._/@+-]*) return 1 ;;
  esac
  # Anyone who can write one of these directories can swap the brief a
  # worker is told to follow.
  private_dir "$_vb_home" && private_dir "$_vb_home/flights" && private_dir "$_vb_dir" || return 1
  BRIEF_PATH="$_vb_dir/brief.md"
}

# private_dir <dir> — a real directory the invoking user owns that neither
# group nor others can write.
private_dir() {
  [ ! -L "$1" ] && [ -d "$1" ] || return 1
  _pd_uid=$(id -u) || return 1
  [ -n "$(find "$1" -maxdepth 0 -user "$_pd_uid" ! -perm -0020 ! -perm -0002 2>/dev/null)" ]
}

# refuse_resume_beside_brief <launch args...> — a resumed session would carry
# its prior conversation beside the brief, so a brief launch starts fresh.
refuse_resume_beside_brief() {
  for _rb in "$@"; do
    case $_rb in
      --continue | -c | --resume | --resume=* | -r | -r=*)
        warn "refusing $_rb beside a flight brief: a brief launch starts a fresh session"
        exit 2
        ;;
    esac
  done
}

# worktree suffix: `<spec>-task-<id>`, the bare legacy `task-<id>`, or a
# flight's `flight-<flight-id>`.
#
# The spec segment is load-bearing, not decoration. `.claude/worktrees/` is one
# flat namespace shared by every spec, so a bare `task-<id>` collides whenever
# two specs carry the same task number — which is the common case, not a corner
# one. A collision makes the second dispatch fail on an existing directory, so
# the unit cannot be dispatched at all while the first holds it.
#
# The BARE form is still accepted so `attach` keeps working against worktrees
# placed before the spec segment existed; only construction changed.
valid_suffix() {
  reject_dotdot "$1" || return 1
  case $1 in
    '' | *[!a-z0-9.-]* | [!a-z0-9]*) return 1 ;;
  esac
  # A flight worktree, `flight-<flight-id>` (tower-front-door D-11): a kebab
  # slug plus an eight-character hex uid, the id bounded at 64 characters as
  # scripts/flight-id.sh bounds it, so the two screens agree. Past the bound
  # it falls through rather than failing: `flight-<long>-task-12345678` is
  # still a legal task suffix for a spec named `flight-<long>`.
  if printf '%s' "$1" | grep -Eq '^flight-[a-z0-9][a-z0-9-]*-[0-9a-f]{8}$' \
    && [ "${#1}" -le 71 ]; then
    return 0
  fi
  # The spec half must admit the WHOLE spec grammar, which starts [a-z0-9] —
  # requiring a letter here would reject a legal spec like `2fa` before git
  # ever sees it.
  printf '%s' "$1" | grep -Eq '^([a-z0-9][a-z0-9-]*-)?task-[0-9]+(\.[0-9]+)?$' || return 1
  # The spec half is a spec, so the reserved segment is refused here as
  # valid_spec refuses it: the suffix a spec named `flight` would build, not
  # every spec whose name starts with `flight-task-`. An eight-digit id is the
  # exception, already taken above as flight `task-<uid>`.
  if printf '%s' "$1" | grep -Eq '^flight-task-[0-9]+(\.[0-9]+)?$'; then
    return 1
  fi
  # The bound must clear what the grammars upstream of it can actually produce:
  # a spec is up to 64 characters, `-task-` adds 6, and a dotted id adds several
  # more, so the old 72 rejected a legal max-length spec outright — the suffix
  # only started carrying the spec in this change, so 72 predates the overflow.
  [ "${#1}" -le 128 ] || return 1
  return 0
}

# --- Liveness signals (dispatch marker + tmux session) -----------------------
# A dispatch is LIVE iff a tmux session for the suffix exists, OR the
# orchestrate-marker for the task id exists and is younger than LIVENESS_TTL.
#
# Every ambiguous read fails SAFE — toward LIVE — because the cost of a wrong
# "stale" is the reconcile force-removing a genuinely running worker's checkout
# (data loss), while the cost of a wrong "live" is only a spurious
# already-in-flight abort the operator retries. This matches the unparseable-
# marker arm and dispatch-fetch.sh's clock-failure discipline.
#
# The tmux probe reads the session the launch creates and the prior launcher's
# spelling (suffix_session_live), each for the suffix and for an alternate
# name alike.
LIVENESS_SKIP_TMUX="${PLANWRIGHT_DISPATCH_LIVENESS_SKIP_TMUX:-0}"

is_live() {
  # $1 spec-dir  $2 id  $3 suffix  [$4 alternate name]
  # $4 is the basename of a worktree path that already holds the branch (see
  # branch_checkout_path): a session launched under that older name is as live
  # as one under the current suffix.
  _sd=$1
  _id=$2
  _suffix=$3
  _alt=${4:-}

  suffix_session_live "$_suffix" && return 0
  if [ -n "$_alt" ] && [ "$_alt" != "$_suffix" ]; then
    suffix_session_live "$_alt" && return 0
  fi

  # A flight has no spec dir and no marker; the reconcile treats its
  # registered worktree as live on its own.
  [ -n "$_sd" ] || return 1
  _mdir="${PLANWRIGHT_ORCH_STATE_DIR:-$_sd/.orchestrate/markers}"
  _mfile="$_mdir/$_id"
  if [ -f "$_mfile" ]; then
    _written=$(cat "$_mfile" 2>/dev/null || echo '')
    case $_written in
      '' | *[!0-9]*) return 0 ;; # unparseable marker: fail safe, treat as live
    esac
    # A clock-read failure (empty $_now) fails SAFE to live, not stale — never
    # let a broken `date` degrade a running worker into a reconcile target.
    _now=$(date +%s 2>/dev/null || echo '')
    case $_now in
      '' | *[!0-9]*) return 0 ;;
    esac
    _age=$((_now - _written))
    # age < 0 is a future-dated marker (writer clock ahead / NFS skew): treat as
    # live (fresh), matching dispatch-fetch.sh, not as stale.
    if [ "$_age" -lt 0 ] || [ "$_age" -lt "$LIVENESS_TTL" ]; then
      return 0
    fi
  fi
  return 1
}

# Is <path> a currently-registered git worktree in <repo>? A worktree list
# that cannot be read answers yes: the callers guard a removal or an abort,
# and "cannot tell" must never read as "safe to delete".
is_registered_worktree() {
  # $1 repo-root  $2 abs-path. The porcelain stream emits one `worktree <abs>`
  # line per registered tree; a fixed whole-line match is portable across awks.
  _irw=$(git -C "$1" worktree list --porcelain 2>/dev/null </dev/null) || return 0
  printf '%s\n' "$_irw" | grep -Fxq "worktree $2"
}

# Is <path> provably registered: listed by a worktree list that was read? For
# the one caller that removes a REGISTERED worktree, where "cannot tell" must
# not read as registered either.
is_listed_worktree() {
  _ilw=$(git -C "$1" worktree list --porcelain 2>/dev/null </dev/null) || return 1
  printf '%s\n' "$_ilw" | grep -Fxq "worktree $2"
}

# Does <branch> exist in <repo>?
branch_exists() {
  git -C "$1" show-ref --verify --quiet "refs/heads/$2"
}

# Print the registered worktree path that has <branch> checked out, empty when
# none does. The porcelain stream is one block per worktree (`worktree <abs>`,
# then `HEAD`, then `branch refs/heads/<name>` for an attached checkout); the
# first block whose branch line matches wins. Fixed-string compare on the
# whole line, as is_registered_worktree does, so a branch whose name merely
# extends this one never matches.
branch_checkout_path() {
  # $1 repo-root  $2 branch
  git -C "$1" worktree list --porcelain 2>/dev/null \
    | awk -v want="branch refs/heads/$2" '
        index($0, "worktree ") == 1 { p = substr($0, 10) }
        $0 == want { print p; exit }'
}

# Does <branch> carry commits beyond <base> (real work worth adopting)?
branch_has_work() {
  # $1 repo-root  $2 branch  $3 base-ref
  _n=$(git -C "$1" rev-list --count "$3..$2" 2>/dev/null || echo 0)
  [ "${_n:-0}" -gt 0 ]
}

# Validate the caller-supplied EXTRA launch args against a known-safe flag
# allowlist before they reach `claude`. The tower runs this primitive as a
# resolved-literal-path script, so the tower command-guard approves the whole
# invocation WHOLESALE (is_repo_script) and never applies its per-flag
# `guard_claude` escalation pin to the launch this script constructs. The pin
# must therefore live HERE: a permission/trust-weakening flag
# (`--dangerously-skip-permissions`, `--permission-mode`, `--settings`,
# `--mcp-config`, `--add-dir`, `--agents`, `--plugin-dir`, …) or any stray
# argument is refused (exit 2), so `dispatch … -- <flag>` can never launch a
# worker with its permission layer disabled — the fleet-wide escalation
# REQ-C1.2 exists to stop.
validate_launch_extra() {
  while [ "$#" -gt 0 ]; do
    case $1 in
      --model | --fallback-model)
        [ "$#" -ge 2 ] || {
          warn "launch flag $1 needs a value"
          exit 2
        }
        case $2 in
          -*)
            warn "launch flag $1 has a flag-shaped value: $2"
            exit 2
            ;;
        esac
        shift 2
        ;;
      --model= | --fallback-model=)
        # Empty attached value — inconsistent with the space form (which requires
        # a value) and would pass an empty model to claude.
        warn "launch flag has an empty value: $1"
        exit 2
        ;;
      --model=-* | --fallback-model=-*)
        # Symmetry with the space-separated form: an attached flag-shaped value.
        warn "launch flag has a flag-shaped value: $1"
        exit 2
        ;;
      --model=* | --fallback-model=*) shift ;;
      --effort)
        # The launch-tier effort dimension (model-allocation D-10, REQ-B1.2).
        # Sanctioned for the same reason `--model` is: it selects capability and
        # cost, never permission or trust, so it is outside what the
        # escalation pin exists to stop. Its value is checked against
        # planwright's own effort enum rather than merely shape-checked, because
        # the resolver can emit nothing else and a wider value here could only
        # come from a hand-built launch.
        [ "$#" -ge 2 ] || {
          warn "launch flag $1 needs a value"
          exit 2
        }
        case $2 in
          low | medium | high) ;;
          *)
            warn "launch flag --effort has an out-of-enum value: $2"
            exit 2
            ;;
        esac
        shift 2
        ;;
      --effort=low | --effort=medium | --effort=high) shift ;;
      --effort=*)
        warn "launch flag --effort has an empty or out-of-enum value: $1"
        exit 2
        ;;
      --continue | -c) shift ;;
      --resume | -r)
        shift
        # An optional session-id value that is not itself a flag.
        if [ "$#" -ge 1 ]; then
          case $1 in
            -*) ;;
            *) shift ;;
          esac
        fi
        ;;
      --resume=* | -r=*) shift ;;
      *)
        warn "refusing unsanctioned launch arg (escalation-pin, REQ-C1.2): $1"
        exit 2
        ;;
    esac
  done
}

# --- attach: the worker's detached tmux session -------------------------------

do_attach() {
  # <suffix> [--brief <abs-file>] [--dry-run] [-- <extra launch args>...].
  # Guard the positional so a bare `attach` fails with the clean usage/exit-2
  # path, not a set -u abort.
  [ "$#" -ge 1 ] || usage
  _suffix=$1
  shift
  _dry=0
  _abrief=''
  _abrief_set=0
  while [ "$#" -gt 0 ]; do
    case $1 in
      --dry-run)
        _dry=1
        shift
        ;;
      --brief)
        [ "$#" -ge 2 ] || usage
        _abrief=$2
        _abrief_set=1
        shift 2
        ;;
      --)
        shift
        break
        ;;
      *) break ;;
    esac
  done
  valid_suffix "$_suffix" || {
    warn "invalid worktree suffix: $_suffix"
    exit 2
  }
  # A standalone attach of a flight can hand the worker its brief, under the
  # dispatch arm's confinement.
  if [ "$_abrief_set" -eq 1 ] && [ -z "$_abrief" ]; then
    warn "--brief is empty: name the flight's own brief.md, or drop --brief"
    exit 2
  fi
  if [ -n "$_abrief" ]; then
    _aflight=${_suffix#flight-}
    if [ "$_aflight" = "$_suffix" ] || ! valid_flight "$_aflight"; then
      warn "--brief is a flight option: the suffix must be flight-<flight-id>"
      exit 2
    fi
    valid_brief "$_abrief" "$_aflight" || {
      warn "--brief must be the flight's own brief.md under the fleet home (flights/<flight-id>/), non-empty, on the path charset [A-Za-z0-9._/@+-], in directories only you can write"
      exit 2
    }
    ATTACH_PROMPT="Read $BRIEF_PATH and follow it exactly."
  fi
  # Refuse any unsanctioned extra launch flag before it reaches claude.
  validate_launch_extra "$@"
  [ -z "$ATTACH_PROMPT" ] || refuse_resume_beside_brief "$@"

  # The only live launch is the dispatch arm's, after its path-escape guard;
  # a second live path would be a second thing to guard.
  if [ "$_dry" -eq 0 ]; then
    warn "a live standalone attach is refused: launch a worker with \`dispatch\`, whose path-escape guard every live launch passes; \`attach <suffix> --dry-run\` prints the plan"
    exit 2
  fi

  _aroot=$(/bin/sh "$script_dir/resolve-root.sh" repo --primary 2>/dev/null || true)
  [ -n "$_aroot" ] && _aroot=$(cd "$_aroot" 2>/dev/null && pwd -P) || _aroot=''
  [ -n "$_aroot" ] || {
    warn "cannot resolve the repo root for the attach plan"
    exit 2
  }
  init_session_names "$_aroot" || {
    warn "cannot compute the session name for $_aroot"
    exit 2
  }
  identity_for_suffix "$_suffix"
  print_plan "$_suffix" "$_aroot/.claude/worktrees/$_suffix" "$ID_HANDLE" "$ID_SCOPE" "$@"
}

# identity_for_suffix <suffix> — set ID_HANDLE and ID_SCOPE to the worker
# identity a dispatch of <suffix> registers, empty for the legacy bare
# `task-<id>` form, which names no spec.
identity_for_suffix() {
  ID_HANDLE=''
  ID_SCOPE=''
  case $1 in
    flight-*)
      if valid_flight "${1#flight-}"; then
        ID_HANDLE="tmux-$1"
        ID_SCOPE="flight:${1#flight-}"
        return 0
      fi
      ;;
  esac
  case $1 in
    task-*) return 0 ;;
    *-task-*)
      ID_HANDLE="tmux-$1"
      ID_SCOPE="${1%-task-*}:${1##*-task-}"
      ;;
  esac
}

# resolve_launch_tools — set WORKER_CLI and TMUX_BIN, or refuse: the worker
# CLI must resolve to an absolute path of an executable file (exit 7), and
# tmux must resolve (exit 8).
WORKER_CLI=''
TMUX_BIN=''
resolve_launch_tools() {
  WORKER_CLI=$(command -v claude 2>/dev/null) || WORKER_CLI=''
  case $WORKER_CLI in
    /*) ;;
    *) WORKER_CLI='' ;;
  esac
  if [ -z "$WORKER_CLI" ] || [ ! -f "$WORKER_CLI" ] || [ ! -x "$WORKER_CLI" ]; then
    warn "refusing the tmux rung: claude does not resolve to an absolute path of an executable file (resolved: $(command -v claude 2>/dev/null || echo none))"
    exit 7
  fi
  TMUX_BIN=$(command -v tmux 2>/dev/null) || TMUX_BIN=''
  [ -n "$TMUX_BIN" ] || {
    warn "refusing the tmux rung: tmux does not resolve"
    exit 8
  }
}

# launch_roots — set LAUNCH_ROOT and LAUNCH_HOME to the dispatcher's resolved
# planwright root and fleet home, which the worker is pinned to.
launch_roots() {
  LAUNCH_ROOT=$(/bin/sh "$script_dir/resolve-root.sh" install 2>/dev/null </dev/null) || LAUNCH_ROOT=''
  LAUNCH_HOME=$(/bin/sh "$FLEET_STATE" root 2>/dev/null </dev/null) || LAUNCH_HOME=''
}

# print_plan <suffix> <worktree> <handle> <scope> [<extra launch args>...] —
# the launch plan, for a dry run: no tmux call, no `claude` exec, no
# model/API call. Every token is sanitized: a validated `--model` VALUE can
# still carry control bytes, and the plan prints to the operator's terminal.
print_plan() {
  pp_suffix=$1
  pp_wt=$2
  pp_handle=$3
  pp_scope=$4
  shift 4
  pp_session=$(worker_session "$pp_suffix")
  pp_claude=$(command -v claude 2>/dev/null) || pp_claude=claude
  launch_roots
  printf 'attach-plan\tsuffix\t%s\n' "$(sanitize_printable "$pp_suffix")"
  printf 'attach-plan\tsession\t%s\n' "$(sanitize_printable "$pp_session")"
  printf 'attach-plan\tlaunch'
  tmux_launch plan tmux "$pp_session" "$pp_wt" "$pp_handle" "$pp_scope" '<launch-token>' \
    "$pp_claude" "$@"
  printf '\n'
}

# tmux_launch <plan|check|run> <tmux> <session> <worktree> <handle> <scope>
#   <token> <claude> [<launch args>...] — the one place the launch is built.
# plan prints its words, tab-led, without a newline; check runs the env
# wrapper's --check over the same options and command; run executes it, the
# -P -F line to LAUNCH_OUT and stderr to LAUNCH_ERR. The command after `--` is
# always several argv words, which tmux runs directly rather than through a
# shell, and which it passes through unexpanded.
tmux_launch() {
  tl_mode=$1
  tl_tmux=$2
  tl_session=$3
  tl_wt=$4
  tl_handle=$5
  tl_scope=$6
  tl_token=$7
  shift 7
  [ -z "$ATTACH_PROMPT" ] || set -- "$@" -- "$ATTACH_PROMPT"
  [ -z "$LAUNCH_HOME" ] || set -- --fleet-home "$LAUNCH_HOME" "$@"
  [ -z "$LAUNCH_ROOT" ] || set -- --root "$LAUNCH_ROOT" "$@"
  [ -z "$tl_token" ] || set -- --launch-token "$tl_token" "$@"
  [ -z "$tl_handle" ] || set -- --identity "$tl_handle" "$tl_scope" "$@"
  case $tl_mode in
    check)
      # tmux splits its argv into commands before parsing options, so a word
      # ending in `;` would end the launch command there, after `--` too.
      for tl_a in "$ENVWRAP" "$@"; do
        case $tl_a in
          *';')
            warn "refusing a launch word ending in ';', which tmux reads as a command separator: $tl_a"
            exit 2
            ;;
        esac
      done
      /bin/sh "$ENVWRAP" --check "$@" </dev/null >/dev/null
      return
      ;;
  esac
  set -- "$tl_tmux" new-session -d -s "$tl_session" -c "$tl_wt" \
    -P -F "#{session_name}$TAB#{window_id}" -- "$ENVWRAP" "$@" \
    ';' set-window-option -t "=$tl_session:" remain-on-exit off
  case $tl_mode in
    plan)
      # The format's tab is printed as `\t`: the plan is tab-separated.
      for tl_a in "$@"; do
        case $tl_a in
          "#{session_name}$TAB#{window_id}") tl_a='#{session_name}\t#{window_id}' ;;
        esac
        printf '\t%s' "$(sanitize_printable "$tl_a")"
      done
      ;;
    run) "$@" </dev/null >"$LAUNCH_OUT" 2>"$LAUNCH_ERR" ;;
  esac
}

# --- dispatch: create-then-attach --------------------------------------------

do_dispatch() {
  _spec=''
  _id=''
  _flight=''
  _brief=''
  _brief_set=0
  _repo_root=''
  _attach_dry=0
  _no_attach=0
  _launch_only=0
  # Collect extra launch args (after `--`) verbatim.
  _have_extra=0

  # Positional + flag parse. `<spec> <id>` are the first two non-flag args.
  while [ "$#" -gt 0 ]; do
    case $1 in
      --)
        shift
        _have_extra=1
        break
        ;;
      --repo-root)
        [ "$#" -ge 2 ] || usage
        _repo_root=$2
        shift 2
        ;;
      --attach-dry-run)
        _attach_dry=1
        shift
        ;;
      --no-attach)
        _no_attach=1
        shift
        ;;
      --launch-only)
        _launch_only=1
        shift
        ;;
      --flight)
        [ "$#" -ge 2 ] || usage
        _flight=$2
        shift 2
        ;;
      --brief)
        [ "$#" -ge 2 ] || usage
        _brief=$2
        _brief_set=1
        shift 2
        ;;
      --*)
        warn "unknown flag: $1"
        usage
        ;;
      *)
        if [ -z "$_spec" ]; then
          _spec=$1
        elif [ -z "$_id" ]; then
          _id=$1
        else
          warn "unexpected argument: $1"
          usage
        fi
        shift
        ;;
    esac
  done
  # Remaining "$@" (only meaningful when _have_extra=1) are the extra launch args.
  [ "$_have_extra" -eq 1 ] || set --

  # --attach-dry-run and --no-attach are documented as alternatives
  # (`[--attach-dry-run | --no-attach]`), and the arms below are checked in a
  # fixed order, so passing both silently discards one of them — the caller
  # cannot even pick which by reordering argv. Refuse the combination, same
  # refuse-rather-than-silently-drop discipline as the passthrough-args check
  # below. Post-parse, so the refusal is order-independent and pre-side-effect.
  if [ "$((_attach_dry + _no_attach + _launch_only))" -gt 1 ]; then
    warn "--launch-only, --attach-dry-run, and --no-attach are alternatives; pass at most one"
    usage
  fi

  # --no-attach launches no worker, so it cannot honor passthrough launch args;
  # accepting them silently would drop them (the attach/dry-run arms forward
  # them, this arm cannot). Refuse rather than silently discard.
  if [ "$_no_attach" -eq 1 ] && [ "$_have_extra" -eq 1 ] && [ "$#" -gt 0 ]; then
    warn "--no-attach launches no worker; it takes no post-\`--\` launch args"
    usage
  fi

  if [ -n "$_flight" ]; then
    [ -z "$_spec" ] && [ -z "$_id" ] || {
      warn "--flight takes no <spec> <id>"
      usage
    }
  else
    [ -n "$_spec" ] && [ -n "$_id" ] || usage
    [ -z "$_brief" ] || {
      warn "--brief is a flight option (--flight <flight-id>)"
      usage
    }
  fi
  if [ "$_brief_set" -eq 1 ] && [ -z "$_brief" ]; then
    warn "--brief is empty: name the flight's own brief.md, or drop --brief"
    exit 2
  fi
  if [ -n "$_brief" ] && [ "$_no_attach" -eq 1 ]; then
    warn "--no-attach launches no worker; it takes no --brief"
    usage
  fi

  # Validate every token BEFORE it appears in any path or command (D-36).
  if [ -n "$_flight" ]; then
    valid_flight "$_flight" || {
      warn "invalid flight id (expected <slug>-<uid>)"
      exit 2
    }
    if [ -n "$_brief" ]; then
      valid_brief "$_brief" "$_flight" || {
        warn "--brief must be the flight's own brief.md under the fleet home (flights/<flight-id>/), non-empty, on the path charset [A-Za-z0-9._/@+-], in directories only you can write"
        exit 2
      }
      ATTACH_PROMPT="Read $BRIEF_PATH and follow it exactly."
    fi
    _suffix="flight-$_flight"
    _branch="planwright/flight/$_flight"
  else
    valid_spec "$_spec" || {
      if [ "$_spec" = flight ]; then
        warn "reserved spec id 'flight' (the flight branch segment, tower-front-door D-11)"
      else
        warn "invalid spec id (D-36 grammar): $_spec"
      fi
      exit 2
    }
    valid_id "$_id" || {
      warn "invalid task id (D-36 grammar): $_id"
      exit 2
    }
    _suffix="$_spec-task-$_id"
    _branch="planwright/$_spec/task-$_id"
  fi
  valid_suffix "$_suffix" || {
    warn "invalid worktree suffix (D-36 grammar): $_suffix"
    exit 2
  }

  # Validate the extra launch args (the escalation-pin allowlist) NOW — before
  # any side effect — so a refused flag exits 2 without ever creating a worktree,
  # marker, or registry entry. (do_attach re-validates as defense-in-depth for a
  # direct `attach` invocation.)
  validate_launch_extra "$@"
  [ -z "$ATTACH_PROMPT" ] || refuse_resume_beside_brief "$@"

  # Resolve the repo root: the primary checkout, so a dispatch from inside a
  # worktree places the new worktree beside it rather than nested in it.
  if [ -z "$_repo_root" ]; then
    _repo_root=$(/bin/sh "$script_dir/resolve-root.sh" repo --primary 2>/dev/null || true)
  fi
  [ -n "$_repo_root" ] && [ -d "$_repo_root" ] || {
    warn "cannot resolve repo root (pass --repo-root)"
    exit 2
  }
  # Resolve to the PHYSICAL path (`pwd -P`): `git worktree list --porcelain`
  # reports physical paths, so the reconcile's fixed-string match must compare
  # against the same (on macOS a symlinked $TMPDIR /var -> /private/var otherwise
  # mismatches the porcelain path).
  _repo_root=$(cd "$_repo_root" && pwd -P) || exit 2
  # The tmux rung's arms: a live launch and its dry-run plan.
  _tmux_rung=1
  [ "$_no_attach" -eq 0 ] || _tmux_rung=0
  if [ "$_tmux_rung" -eq 1 ] && ! valid_launch_path "$_repo_root/.claude/worktrees/$_suffix"; then
    warn "refusing the tmux rung: the worktree path $_repo_root/.claude/worktrees/$_suffix is outside the path charset [A-Za-z0-9._/@+-], which tmux would format-expand; this checkout cannot use the tmux rung (the other rungs are unaffected)"
    exit 9
  fi
  _spec_dir=''
  if [ -z "$_flight" ]; then
    _spec_root=$(cd "$_repo_root" && env -u PLANWRIGHT_REPO_ROOT /bin/sh "$script_dir/resolve-root.sh" spec) || {
      warn "cannot resolve the spec root for $_repo_root"
      exit 2
    }
    _spec_dir="$_spec_root/$_spec"
  fi
  # Fail closed when the spec bundle dir is missing: a task is only ever
  # dispatched within an existing spec, and without `<root>/<spec>` the dispatch
  # marker cannot be written, which would degrade liveness to "not live" and let
  # a later collision reconcile force-remove an actually-running worker.
  if [ -z "$_flight" ] && [ ! -d "$_spec_dir" ]; then
    warn "spec bundle not found: $_spec_dir (dispatch requires an existing spec)"
    exit 2
  fi
  _wt_root="$_repo_root/.claude/worktrees"
  _worktree="$_wt_root/$_suffix"

  # Path-escape guard. `git worktree add` (and the reconcile `rm -rf`) FOLLOW a
  # symlink component, so a repo carrying a malicious `.claude` /
  # `.claude/worktrees` symlink (a compromised or untrusted checkout) could make
  # the primitive read/write/delete OUTSIDE the repo root. Refuse a symlinked
  # `.claude`, `.claude/worktrees`, or leaf worktree dir; materialize the root as
  # a REAL directory; and confirm it physically resolves UNDER the repo root
  # (catching a deeper symlink escape), fail-closed. Mirrors the canon-contained
  # discipline the command guards and fleet-cleanup already apply.
  if [ -L "$_repo_root/.claude" ]; then
    warn "refusing: $_repo_root/.claude is a symlink (path-escape guard)"
    exit 5
  fi
  mkdir -p "$_repo_root/.claude" 2>/dev/null || true
  if [ -L "$_wt_root" ]; then
    warn "refusing: $_wt_root is a symlink (path-escape guard)"
    exit 5
  fi
  mkdir -p "$_wt_root" 2>/dev/null || true
  _wt_root_phys=$(cd "$_wt_root" 2>/dev/null && pwd -P || echo '')
  case "$_wt_root_phys/" in
    "$_repo_root"/*) ;; # contained under the repo root
    *)
      warn "refusing: worktrees root does not resolve under the repo root (path-escape guard)"
      exit 5
      ;;
  esac
  if [ -L "$_worktree" ]; then
    warn "refusing: $_worktree is a symlink (path-escape guard)"
    exit 5
  fi

  if [ -n "$_flight" ]; then
    _handle="tmux-flight-$_flight"
    _scope="flight:$_flight"
  else
    _handle="tmux-$_spec-task-$_id"
    _scope="$_spec:$_id"
  fi

  # --- Launch checks, before any durable side effect -------------------------
  _session=''
  _token=''
  LAUNCH_ROOT=''
  LAUNCH_HOME=''
  if [ "$_tmux_rung" -eq 1 ]; then
    init_session_names "$_repo_root" || {
      warn "cannot compute the session name for $_repo_root"
      exit 10
    }
    _session=$(worker_session "$_suffix")
    valid_session_name "$_session" || {
      warn "refusing the tmux rung: the session name $_session is outside the session-name charset [A-Za-z0-9_@-] (alphanumeric first, at most 128 bytes)"
      exit 10
    }
  fi
  [ "$_tmux_rung" -eq 0 ] || [ "$_attach_dry" -eq 1 ] || resolve_launch_tools
  if [ "$_tmux_rung" -eq 1 ] && [ "$LIVENESS_SKIP_TMUX" != 1 ] \
    && command -v tmux >/dev/null 2>&1 && session_probe_live "$_session"; then
    warn "already-in-flight: a live tmux session already holds $_session (aborting before anything is placed)"
    exit 3
  fi
  if [ "$_tmux_rung" -eq 1 ] && [ "$_attach_dry" -eq 0 ]; then
    launch_roots
    if [ -z "$LAUNCH_ROOT" ] || [ -z "$LAUNCH_HOME" ]; then
      warn "refusing the tmux rung: cannot resolve the planwright root and fleet home to pin the worker to"
      exit 12
    fi
    _token=$(od -An -N16 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n') || _token=''
    case $_token in
      '' | *[!0-9a-f]*)
        warn "refusing the tmux rung: cannot mint a launch token"
        exit 12
        ;;
    esac
    if ! tmux_launch check "$TMUX_BIN" "$_session" "$_worktree" "$_handle" "$_scope" \
      "$_token" "$WORKER_CLI" "$@"; then
      warn "refusing the tmux rung: the dispatch environment wrapper refused the launch options; nothing was placed"
      exit 12
    fi
  fi

  # --- Resolve <base>: the freshly-fetched origin/main (D-9) ---------------
  # dispatch-fetch.sh updates refs/remotes/origin/main without advancing local
  # main; we then read the fetched SHA. exit 0 fetched/fresh-within-ttl (use
  # origin/main); exit 3 no-remote (degrade to local main with a NOTE); exit 4
  # stale-transient (must NOT proceed on a stale ref); exit 2 usage/internal
  # (fail closed); other -> fail closed.
  # Redirect stdin from /dev/null: a dispatch primitive must never block on an
  # inherited open stdin (an interactive tty or a still-open pipe), which a
  # config/overlay read down the fetch path can otherwise wait on forever.
  "$FETCH" "$_repo_root" >/dev/null 2>&1 </dev/null
  _frc=$?
  case $_frc in
    0)
      # `rev-parse --verify <ref>^{commit}` errors cleanly when the ref does not
      # resolve, instead of the bare `rev-parse <ref>` that ECHOES the literal
      # argument (`origin/main`) on failure — which would defeat the emptiness
      # guard below and hand git a bogus non-SHA base.
      _base=$(git -C "$_repo_root" rev-parse --verify --quiet "origin/main^{commit}" 2>/dev/null </dev/null || true)
      if [ -z "$_base" ]; then
        warn "origin/main unresolved after a successful fetch; cannot base the worktree"
        exit 4
      fi
      ;;
    3)
      _base=$(git -C "$_repo_root" rev-parse --verify --quiet "main^{commit}" 2>/dev/null </dev/null || true)
      [ -n "$_base" ] || {
        warn "no remote and no local main to base on"
        exit 4
      }
      warn "NOTE: no remote reachable; basing on local main (degraded, D-9)"
      ;;
    2)
      warn "dispatch-fetch reported a usage/internal error (exit 2); refusing to dispatch"
      exit 5
      ;;
    *)
      warn "cannot resolve a fresh base (dispatch-fetch exit $_frc); refusing to base on a stale ref"
      exit 4
      ;;
  esac

  # --- Filesystem-orphan hygiene: a leftover EMPTY <suffix> dir --------------
  # `git worktree add` would silently create into an empty dir (verified), so a
  # stale empty leftover must be removed first, not silently reused. This is fs
  # hygiene, not a branch-collision pre-check (that stays git's atomic exit).
  if [ -d "$_worktree" ] \
    && ! is_registered_worktree "$_repo_root" "$_worktree" \
    && [ -z "$(ls -A "$_worktree" 2>/dev/null)" ]; then
    rmdir "$_worktree" 2>/dev/null || true
  fi

  # --- Create: the SINGLE scoped `git worktree add -b` call (argv, no shell) --
  # Its atomic non-zero exit IS the collision detector (no TOCTOU pre-check).
  # `</dev/null` on every git worktree call: `add` runs a checkout that may fire
  # a repo `post-checkout` hook, which can read stdin and would otherwise block
  # on an inherited tty/pipe (the same hazard the FETCH redirect guards).
  # What this run creates is recorded, so a failed launch undoes only that.
  _made_branch=0
  _made_worktree=0
  _made_marker=0
  if git -C "$_repo_root" worktree add -b "$_branch" "$_worktree" "$_base" \
    >/dev/null 2>&1 </dev/null; then
    _created=1
    _made_branch=1
    _made_worktree=1
  else
    _created=0
  fi

  if [ "$_created" -eq 0 ]; then
    # Reconcile: distinguish LIVE (abort) from STALE (GC-adopt / roll back).
    # A checkout of the branch at some OTHER registered path counts toward
    # liveness under that path's own session name (the old flat layout named
    # its sessions after `task-<id>`).
    _held_at=$(branch_checkout_path "$_repo_root" "$_branch")
    [ "$_held_at" != "$_worktree" ] || _held_at=''
    _held_name=''
    [ -z "$_held_at" ] || _held_name=$(basename "$_held_at")
    if is_live "$_spec_dir" "$_id" "$_suffix" "$_held_name"; then
      warn "already-in-flight: a live dispatch holds $_branch (aborting)"
      exit 3
    fi
    # A flight has no marker, and a print-rung worker has no tmux session, so a
    # missing session proves nothing: its registered worktree is in flight.
    if [ -n "$_flight" ] && is_registered_worktree "$_repo_root" "$_worktree"; then
      warn "already-in-flight: flight worktree $_worktree is registered (or the worktree list could not be read), and a flight worktree is never force-removed (remove it with git worktree remove, then dispatch again)"
      exit 3
    fi

    # Checked out elsewhere and not live: the GC arms below cannot act on it
    # (git refuses a second checkout of a branch and refuses to delete a
    # checked-out one), so stop here with the state named, before anything is
    # removed or rolled back.
    if [ -n "$_held_at" ]; then
      warn "branch $_branch is already checked out at $_held_at, not at $_worktree; nothing was changed. Bring the checkout to the expected path: git worktree move '$_held_at' '$_worktree' (or remove it: git worktree remove '$_held_at'), then dispatch again"
      exit 6
    fi

    # Stale orphan. Remove any leftover worktree checkout (disposable).
    if is_listed_worktree "$_repo_root" "$_worktree"; then
      git -C "$_repo_root" worktree remove --force "$_worktree" >/dev/null 2>&1 </dev/null || true
    fi
    if [ -d "$_worktree" ] && [ -z "$(ls -A "$_worktree" 2>/dev/null)" ]; then
      rmdir "$_worktree" 2>/dev/null || true
    fi
    # A NON-EMPTY, unregistered leftover that is a dead git-worktree remnant (a
    # crashed `add` that populated files + a `.git` gitlink but never registered)
    # is cleaned so it cannot permanently wedge the path; a non-empty dir that is
    # NOT a worktree remnant is foreign data and is refused, never destroyed.
    if [ -d "$_worktree" ] \
      && ! is_registered_worktree "$_repo_root" "$_worktree" \
      && [ -n "$(ls -A "$_worktree" 2>/dev/null)" ]; then
      # A git worktree's `.git` is a gitlink FILE (`gitdir: …`), not a directory;
      # require `-f` so a standalone git repo (whose `.git` is a DIRECTORY) that
      # happens to sit under the path is treated as foreign data and refused,
      # never rm -rf'd.
      if [ -f "$_worktree/.git" ]; then
        rm -rf "$_worktree" 2>/dev/null || true
      else
        warn "refusing to reuse a non-empty non-worktree dir at $_worktree (clear it manually)"
        exit 5
      fi
    fi
    git -C "$_repo_root" worktree prune >/dev/null 2>&1 </dev/null || true

    if branch_exists "$_repo_root" "$_branch"; then
      if branch_has_work "$_repo_root" "$_branch" "$_base"; then
        # ADOPT the existing branch's work: place a fresh worktree on it (no
        # -b, no base re-apply, no data loss). Unwedges without discarding work.
        if ! git -C "$_repo_root" worktree add "$_worktree" "$_branch" \
          >/dev/null 2>&1 </dev/null; then
          warn "failed to adopt stale branch $_branch onto a worktree"
          exit 5
        fi
        _made_worktree=1
      else
        # Bare partial create (branch made, no commits): roll it back and
        # recreate on the fresh base.
        git -C "$_repo_root" branch -D "$_branch" >/dev/null 2>&1 </dev/null || true
        if ! git -C "$_repo_root" worktree add -b "$_branch" "$_worktree" "$_base" \
          >/dev/null 2>&1 </dev/null; then
          warn "failed to recreate $_branch after rolling back a partial create"
          exit 5
        fi
        _made_branch=1
        _made_worktree=1
      fi
    else
      # No branch, but the create still failed (e.g. a leftover path we just
      # cleaned). Retry once now that hygiene has run.
      if ! git -C "$_repo_root" worktree add -b "$_branch" "$_worktree" "$_base" \
        >/dev/null 2>&1 </dev/null; then
        warn "worktree create failed for $_branch (non-reconcilable)"
        exit 5
      fi
      _made_branch=1
      _made_worktree=1
    fi
  fi

  # Push the worktree into the registry and stamp the dispatch marker (the
  # liveness signals a later collision reconcile reads). Best-effort: a tracking
  # failure must not fail an otherwise-good dispatch.
  #
  # Concurrency scope (two known, bounded residuals): the marker is stamped AFTER
  # the create, and it is an ownerless timestamp, so this primitive does not by
  # itself serialize two concurrent dispatches of the SAME task — the real
  # /orchestrate flow provides that serialization (it records the marker under
  # the per-spec lock BEFORE dispatching, so a concurrent B sees A's marker and
  # aborts). Giving the marker an owner token to close the direct-invocation race
  # is a lock-discipline change deferred repo-wide across the planwright lock
  # family (see scripts/fleet-state.sh's stale-break note), not resolved here. A
  # failed launch clears the marker this run set, so a retry is not read as
  # in-flight.
  [ -x "$TRACK" ] && "$TRACK" record-create "$_worktree" >/dev/null 2>&1 </dev/null || true
  if [ -x "$MARKER" ] && [ -n "$_spec_dir" ] && [ -d "$_spec_dir" ]; then
    "$MARKER" write "$_spec_dir" "$_id" >/dev/null 2>&1 </dev/null && _made_marker=1
  fi

  # Sanitized like the plan tokens: a checkout path carrying control bytes would
  # otherwise inject terminal sequences into the operator's output.
  printf 'dispatch\tbranch\t%s\n' "$(sanitize_printable "$_branch")"
  printf 'dispatch\tworktree\t%s\n' "$(sanitize_printable "$_worktree")"
  printf 'dispatch\tbase\t%s\n' "$(sanitize_printable "$_base")"

  # Neither the create-only nor the dry-run arm registers. The first launches
  # no worker — the rung that does launch into this worktree registers its own,
  # which a record here would double. The second exists to PRINT what a launch
  # would do; a mode whose whole point is to change nothing must not leave a
  # permanent record of a worker that was never started, in an append-only
  # store with no retraction.
  if [ "$_no_attach" -eq 1 ]; then
    return 0
  fi
  if [ "$_attach_dry" -eq 1 ]; then
    print_plan "$_suffix" "$_worktree" "$_handle" "$_scope" "$@"
    return 0
  fi

  # --- Launch (gated on create success) --------------------------------------
  if ! start_dir_ok "$_worktree" "$_repo_root/.claude/worktrees/$_suffix"; then
    warn "refusing to launch: the start directory $_worktree is missing or is not the placed worktree"
    undo_launch
    exit 11
  fi
  _launch_dir=$(mktemp -d "${TMPDIR:-/tmp}/fleet-launch.XXXXXX") || {
    warn "cannot create a scratch directory for the launch"
    undo_launch
    exit 13
  }
  LAUNCH_OUT="$_launch_dir/out"
  LAUNCH_ERR="$_launch_dir/err"
  # The dispatch start the startup confirmation is measured from, taken
  # immediately before the session exists.
  _since=$(date +%s 2>/dev/null) || _since=''
  case $_since in
    '' | *[!0-9]*) _since=unknown ;;
  esac
  tmux_launch run "$TMUX_BIN" "$_session" "$_worktree" "$_handle" "$_scope" \
    "$_token" "$WORKER_CLI" "$@"
  _ns_rc=$?
  _parsed=0
  parse_created "$LAUNCH_OUT" "$_session" || _parsed=1
  _ns_err=$(head -c 2048 "$LAUNCH_ERR" 2>/dev/null)
  rm -rf "$_launch_dir"
  if [ "$_ns_rc" -ne 0 ]; then
    case $_ns_err in
      *'duplicate session'*)
        # Everything this dispatch would own is the winner's: remove, clear,
        # and write nothing.
        warn "already-in-flight: another dispatch created $_session first; its worktree, branch, and marker are left as they are"
        exit 3
        ;;
    esac
    if [ "$_parsed" -ne 0 ]; then
      warn "new-session failed (exit $_ns_rc): $_ns_err"
      undo_launch
      exit 13
    fi
    # The session exists; only the remain-on-exit step after it failed.
    warn "the worker session $_session was created, but turning remain-on-exit off failed: $_ns_err"
  fi

  # Registered once, after the session exists, so no failure arm ever has a
  # record to retract. The handle is the task identity the worker's own
  # environment carries, so a record and a heartbeat agree by construction.
  _death=''
  if [ "$_parsed" -eq 0 ]; then
    _death="tmux-window $_session $CREATED_WINDOW"
  else
    warn "new-session did not print $_session and one window id; registering no death handle"
  fi
  register_dispatch "$_handle" "$_scope" "$_worktree" "$_repo_root" "$_death"

  printf 'launch\tsession\t%s\n' "$_session"
  [ -z "$CREATED_WINDOW" ] || printf 'launch\twindow\t%s\n' "$CREATED_WINDOW"
  printf 'launch\thandle\t%s\n' "$_handle"
  printf 'launch\tsince\t%s\n' "$_since"
  [ "$_launch_only" -eq 0 ] || return 0
  do_confirm --session "$_session" --handle "$_handle" --since "$_since"
}

# start_dir_ok <dir> <expected-physical> — the start directory exists, is a
# real directory, and is exactly the placed worktree.
start_dir_ok() {
  [ ! -L "$1" ] && [ -d "$1" ] || return 1
  sdo_phys=$(cd "$1" 2>/dev/null && pwd -P) || return 1
  [ "$sdo_phys" = "$2" ]
}

# undo_launch — after a post-create failure, remove only what this run
# created: its worktree and its branch (never a branch it adopted), and only
# while no live session runs in the worktree, then the marker it set. A step
# that fails is named with what it left; the caller keeps its own exit status.
undo_launch() {
  ul_wt_left=0
  if suffix_session_live "$_suffix"; then
    warn "undo skipped: a live tmux session runs in $_worktree; its worktree and branch stay"
    ul_wt_left=1
  elif [ "$_made_worktree" -eq 1 ]; then
    if [ -L "$_worktree" ]; then
      ul_wt_left=1
    elif [ -d "$_worktree" ]; then
      git -C "$_repo_root" worktree remove --force "$_worktree" >/dev/null 2>&1 </dev/null || ul_wt_left=1
    fi
    git -C "$_repo_root" worktree prune >/dev/null 2>&1 </dev/null || true
    if [ "$ul_wt_left" -eq 1 ]; then
      warn "undo failed: could not remove the worktree this dispatch created; it is left at $_worktree"
    else
      [ ! -x "$TRACK" ] || "$TRACK" record-remove "$_worktree" >/dev/null 2>&1 </dev/null || true
    fi
  fi
  if [ "$_made_branch" -eq 1 ]; then
    if [ "$ul_wt_left" -eq 1 ]; then
      warn "undo failed: the branch this dispatch created stays with its worktree: $_branch"
    elif ! git -C "$_repo_root" branch -D "$_branch" >/dev/null 2>&1 </dev/null; then
      warn "undo failed: could not delete the branch this dispatch created: $_branch"
    fi
  fi
  if [ "$_made_marker" -eq 1 ]; then
    "$MARKER" clear "$_spec_dir" "$_id" >/dev/null 2>&1 </dev/null \
      || warn "undo failed: could not clear the dispatch marker for task $_id under $_spec_dir"
  fi
  return 0
}

# --- confirm: the launch's outcome --------------------------------------------

do_confirm() {
  dc_session=''
  dc_handle=''
  dc_since=''
  while [ "$#" -gt 0 ]; do
    case $1 in
      --session | --handle | --since)
        [ "$#" -ge 2 ] || usage
        case $1 in
          --session) dc_session=$2 ;;
          --handle) dc_handle=$2 ;;
          --since) dc_since=$2 ;;
        esac
        shift 2
        ;;
      *) usage ;;
    esac
  done
  valid_session_name "$dc_session" || {
    warn "confirm: invalid session name"
    exit 2
  }
  case $dc_handle in
    '' | -* | *[!A-Za-z0-9._=@:-]*)
      warn "confirm: invalid handle"
      exit 2
      ;;
  esac
  case $dc_since in
    '' | unknown) ;;
    *[!0-9]*)
      warn "confirm: --since must be epoch seconds"
      exit 2
      ;;
  esac
  printf 'confirm\toutcome\tstarted-unconfirmed\n'
  printf 'confirm\tsession\t%s\n' "$dc_session"
  printf 'confirm\thandle\t%s\n' "$dc_handle"
  printf 'confirm\treason\t%s\n' "the worker's session was created; its startup confirmation is not wired yet, so the worker is placed and must not be re-dispatched"
  exit 14
}

# --- Entry -------------------------------------------------------------------

[ "$#" -ge 1 ] || usage
sub=$1
shift
case $sub in
  dispatch) do_dispatch "$@" ;;
  attach) do_attach "$@" ;;
  confirm) do_confirm "$@" ;;
  check-session-name)
    [ "$#" -eq 1 ] || usage
    valid_session_name "$1" || exit 10
    ;;
  *)
    warn "unknown subcommand: $sub"
    usage
    ;;
esac
