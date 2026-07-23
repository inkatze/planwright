#!/bin/sh
# fleet-dispatch-headless.sh — the headless-oneshot dispatch primitive
# (execution-backends Task 3; D-3, D-12; REQ-A1.2, REQ-A1.5, REQ-A1.9).
#
# Launches one detached one-shot worker — `claude --print` in an existing
# worktree — and gives the tower two things the advertised set promises
# (doctrine/backend-capability-contract.md, `headless-oneshot` row): a
# COMPLETION SIGNAL it can consume, and POSITIVE-EVIDENCE-OF-DEATH liveness.
# There is no observe and no steer on this rung (can_observe=false,
# can_steer_inflight=false): the tower acts on the completion signal plus the
# liveness verdict, and ambiguity routes to the decision queue.
#
# WHAT A LAUNCH DOES.
#   1. Validates every token (spec/id grammars, worktree presence) BEFORE any
#      side effect; screens the passthrough args (see the pins below).
#   2. Writes the prompt (stdin) to the unit's state dir — the prompt and task
#      text travel as DATA end to end (REQ-A1.9): stdin -> file -> the
#      worker's stdin redirect. No token is ever re-parsed by a shell: the
#      runner re-invocation and the worker launch are argv-vector calls, and
#      fleet-dispatch-env.sh finishes with `exec "$@"`.
#   3. Re-invokes itself as the detached RUNNER (`nohup ... &`), records the
#      runner pid, and returns immediately. The runner cds into the worktree,
#      exports the dispatch-time identity env
#      (PLANWRIGHT_WORKER_HANDLE=headless-<spec>-task-<id>,
#      PLANWRIGHT_WORKER_SCOPE=<spec>:<id>) so the worker's own session fires
#      hook-push liveness (hook_registration=true — fleet-liveness.sh
#      push-capable reads it from the contract), wraps the launch in
#      fleet-dispatch-env.sh (the ghost-text pin), feeds the prompt file on
#      stdin, and captures stdout/stderr.
#   4. When the worker exits, the runner atomically writes the completion
#      signal: `exit` = `<rc> <epoch>`. `result.json` (the `--output-format
#      json` result: is_error, result text, session_id — the session persists
#      and is resumable) and `stderr.log` sit beside it.
#
# THE PINS (REQ-A1.5, D-12; the one-shot permission posture, REQ-A1.2).
#   - The launch NEVER passes `--bare`: at the verified CLI there is no
#     explicit inverse flag, so pinning non-`--bare` means never emitting the
#     flag, enforced here (a passthrough `--bare` is refused, exit 2) and by
#     the static launch-pin guard (tests/test-dispatch-launch-pin.sh), which
#     discovers `-p`-family launch sites by the long `--print` form this
#     primitive deliberately uses.
#   - The launch NEVER attaches a permission prompt tool (a passthrough
#     `--permission-prompt-tool` is refused): a one-shot has no pend path. An
#     unauthorized ask fails under `--print`'s non-interactive default and the
#     failure is VISIBLE — it lands in the captured result and the completion
#     signal fires — never an indefinite pend (verified live at CLI 2.1.218).
#
# WORKTREES. This primitive NEVER creates a worktree (the D-7 `git worktree`
# exception stays scoped to fleet-dispatch-worktree.sh): the tower creates the
# unit's worktree first — `fleet-dispatch-worktree.sh dispatch <spec> <id>
# --no-attach` — and passes it via --worktree.
#
# STATE. One dir per unit:
#   ${PLANWRIGHT_HEADLESS_STATE_DIR:-<repo-root>/specs/<spec>/.orchestrate/headless}/<id>/
#     prompt      the worker's stdin (written from launch stdin)
#     pid         the detached runner's pid (the process liveness supervises)
#     launched    launch epoch seconds
#     result.json the worker's stdout (the --output-format json result)
#     stderr.log  the worker's stderr
#     exit        `<rc> <epoch>` — the completion signal (atomic, written last)
# The default base sits under specs/<spec>/.orchestrate/ (gitignored runtime
# state, like the dispatch markers), so nothing here is ever committed.
#
# Usage:
#   fleet-dispatch-headless.sh launch <spec> <id> --worktree <dir>
#       [--repo-root <dir>] [-- <extra claude args...>]
#     Prompt text on stdin (required, non-empty). Prints the dispatch record:
#       headless<TAB>handle<TAB>headless-<spec>-task-<id>
#       headless<TAB>pid<TAB><runner-pid>
#       headless<TAB>state-dir<TAB><unit dir>
#     PLANWRIGHT_HEADLESS_CLAUDE overrides the worker CLI (default `claude`
#     on PATH) — the test shim seam, mirroring PLANWRIGHT_ORACLE_CLAUDE.
#   fleet-dispatch-headless.sh status <spec> <id> [--repo-root <dir>]
#     Consume the completion signal / liveness for one unit. Prints exactly
#     one line; the exit code is the verdict channel (sibling of
#     fleet-death-evidence.sh):
#       0  completed <rc>   completion signal present (rc = worker exit code;
#                           a non-zero rc is still a completed one-shot — the
#                           failure detail is in result.json/stderr.log)
#       1  running <pid>    positive evidence of life
#       3  died <pid>       the runner is demonstrably gone with no
#                           completion record (positive evidence via
#                           fleet-death-evidence.sh — never silence)
#       4  unknown          lost observability or a garbled record; the
#                           caller must refuse to treat this as death
#       5  absent           no dispatch record for this unit
#   (run-worker is the internal detached-runner entry point, not an API.)
#
# Exit codes: launch 0 dispatched; 2 usage / refused input (hostile token,
# unpinned or posture-violating passthrough arg, empty prompt, missing
# worktree) — nothing launched; 3 already-in-flight (a live runner exists for
# the unit, or its liveness is unknown — refuse to double-dispatch on lost
# observability). status: per the verdict table above.
#
# Portable POSIX sh + coreutils (bash 3.2 / BSD compatible): no eval, no jq
# (REQ-K1.5); every input treated as data. Pathname expansion is disabled
# (set -f), matching the dispatch-path house convention.
set -uf

LC_ALL=C
export LC_ALL
unset CDPATH

script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2
SELF="$script_dir/fleet-dispatch-headless.sh"
ENVWRAP="$script_dir/fleet-dispatch-env.sh"
EVIDENCE="$script_dir/fleet-death-evidence.sh"

if [ -r "$script_dir/echo-safety.sh" ]; then
  # shellcheck source=scripts/echo-safety.sh
  . "$script_dir/echo-safety.sh"
else
  sanitize_printable() {
    printf '%s' "$1" | tr -d '\000-\037\177'
  }
fi

warn() {
  printf '%s\n' "fleet-dispatch-headless: $(sanitize_printable "$1")" >&2
}

usage() {
  cat >&2 <<'EOF'
usage: fleet-dispatch-headless.sh launch <spec> <id> --worktree <dir> [--repo-root <dir>] [-- <extra claude args>...]
       fleet-dispatch-headless.sh status <spec> <id> [--repo-root <dir>]
(prompt text on stdin for launch)
EOF
  exit 2
}

# --- Token grammars (D-36), byte-identical to fleet-dispatch-worktree.sh -----

reject_dotdot() {
  case $1 in
    *..*) return 1 ;;
    *) return 0 ;;
  esac
}

valid_spec() {
  reject_dotdot "$1" || return 1
  case $1 in
    '' | *[!a-z0-9-]* | [!a-z0-9]*) return 1 ;;
  esac
  [ "${#1}" -le 64 ] || return 1
  return 0
}

valid_id() {
  reject_dotdot "$1" || return 1
  case $1 in
    '' | *[!0-9.]*) return 1 ;;
  esac
  printf '%s' "$1" | grep -Eq '^[0-9]+(\.[0-9]+)?$' || return 1
  return 0
}

# --- State-dir resolution ----------------------------------------------------
# $1 spec, $2 id, $3 repo-root (may be empty: resolved from the cwd's git
# toplevel unless the env override names the base directly). Sets unit_dir.
resolve_unit_dir() {
  if [ -n "${PLANWRIGHT_HEADLESS_STATE_DIR:-}" ]; then
    rud_base=$PLANWRIGHT_HEADLESS_STATE_DIR
  else
    rud_root=$3
    if [ -z "$rud_root" ]; then
      rud_root=$(git rev-parse --show-toplevel 2>/dev/null || true)
    fi
    if [ -z "$rud_root" ] || [ ! -d "$rud_root" ]; then
      warn "cannot resolve repo root (pass --repo-root)"
      exit 2
    fi
    if [ ! -d "$rud_root/specs/$1" ]; then
      warn "spec bundle not found: $rud_root/specs/$1"
      exit 2
    fi
    rud_base="$rud_root/specs/$1/.orchestrate/headless"
  fi
  unit_dir="$rud_base/$2"
}

# --- launch ------------------------------------------------------------------

do_launch() {
  l_spec=''
  l_id=''
  l_worktree=''
  l_repo_root=''
  l_have_extra=0
  while [ "$#" -gt 0 ]; do
    case $1 in
      --)
        shift
        l_have_extra=1
        break
        ;;
      --worktree)
        [ "$#" -ge 2 ] || usage
        l_worktree=$2
        shift 2
        ;;
      --repo-root)
        [ "$#" -ge 2 ] || usage
        l_repo_root=$2
        shift 2
        ;;
      --*)
        warn "unknown flag: $1"
        usage
        ;;
      *)
        if [ -z "$l_spec" ]; then
          l_spec=$1
        elif [ -z "$l_id" ]; then
          l_id=$1
        else
          warn "unexpected argument: $1"
          usage
        fi
        shift
        ;;
    esac
  done
  [ "$l_have_extra" -eq 1 ] || set --

  [ -n "$l_spec" ] && [ -n "$l_id" ] && [ -n "$l_worktree" ] || usage
  valid_spec "$l_spec" || {
    warn "invalid spec id (D-36 grammar)"
    exit 2
  }
  valid_id "$l_id" || {
    warn "invalid task id (D-36 grammar)"
    exit 2
  }
  [ -d "$l_worktree" ] || {
    warn "worktree not found: $l_worktree (create it first: fleet-dispatch-worktree.sh dispatch $l_spec $l_id --no-attach)"
    exit 2
  }
  l_worktree=$(cd "$l_worktree" && pwd -P) || exit 2

  # Screen the passthrough args BEFORE any side effect: the non-`--bare` pin
  # (REQ-A1.5, D-12) and the no-prompt-tool one-shot posture (REQ-A1.2) are
  # structural properties of this launch site, so an arg that would break
  # either is refused, never forwarded.
  for l_arg in "$@"; do
    case $l_arg in
      --bare | --bare=*)
        warn "refusing --bare: the non---bare launch pin (REQ-A1.5) forbids it at every worker launch site"
        exit 2
        ;;
      --permission-prompt-tool | --permission-prompt-tool=*)
        warn "refusing --permission-prompt-tool: a one-shot has no pend path (REQ-A1.2); an unauthorized ask must fail visibly in the result"
        exit 2
        ;;
    esac
  done

  resolve_unit_dir "$l_spec" "$l_id" "$l_repo_root"

  # Collision guard: never double-dispatch a unit whose runner may be live.
  # Death is decided by positive evidence only; UNKNOWN refuses too (lost
  # observability is not a license to double-dispatch). A dead or completed
  # prior record is cleaned and re-dispatched (a legitimate retry).
  if [ -d "$unit_dir" ] && [ ! -f "$unit_dir/exit" ] && [ -f "$unit_dir/pid" ]; then
    l_old_pid=$(cat "$unit_dir/pid" 2>/dev/null || true)
    case $l_old_pid in
      '' | *[!0-9]* | 0*)
        # A garbled pid record: observability is lost — refuse, do not clean.
        warn "unit $l_spec/$l_id has an unreadable dispatch record; refusing to double-dispatch (inspect $unit_dir)"
        exit 3
        ;;
      *)
        l_verdict_rc=0
        "$EVIDENCE" process "$l_old_pid" >/dev/null 2>&1 || l_verdict_rc=$?
        case $l_verdict_rc in
          0) ;; # dead: positive evidence — safe to reclaim below
          1)
            warn "unit $l_spec/$l_id already has a live headless runner (pid $l_old_pid); refusing to double-dispatch"
            exit 3
            ;;
          *)
            warn "unit $l_spec/$l_id runner liveness is unknown (lost observability); refusing to double-dispatch"
            exit 3
            ;;
        esac
        ;;
    esac
  fi
  rm -rf "$unit_dir"
  mkdir -p "$unit_dir" || {
    warn "cannot create state dir: $unit_dir"
    exit 2
  }

  # The prompt arrives on stdin and is stored as DATA (REQ-A1.9). Empty is a
  # usage error: a one-shot with no task is a caller bug, not a dispatch.
  cat >"$unit_dir/prompt" || {
    warn "cannot write prompt file"
    exit 2
  }
  [ -s "$unit_dir/prompt" ] || {
    warn "empty prompt on stdin; a one-shot needs its task text"
    rm -rf "$unit_dir"
    exit 2
  }

  l_handle="headless-$l_spec-task-$l_id"
  l_scope="$l_spec:$l_id"
  l_bin="${PLANWRIGHT_HEADLESS_CLAUDE:-claude}"

  # Detach: re-invoke self as the runner under nohup so the worker survives
  # the tower's death (session-grade: the one-shot is its own top-level
  # session). Every token is an argv element end to end — never re-parsed by
  # a shell (REQ-A1.9). The runner (not the worker) is the recorded pid: it
  # is the process that owns the completion write, so its death without an
  # `exit` file is the positive-evidence `died` verdict.
  nohup /bin/sh "$SELF" run-worker "$unit_dir" "$l_worktree" "$l_handle" "$l_scope" -- \
    "$l_bin" --print --output-format json "$@" \
    >/dev/null 2>&1 </dev/null &
  l_pid=$!
  printf '%s\n' "$l_pid" >"$unit_dir/pid"
  date +%s >"$unit_dir/launched"

  printf 'headless\thandle\t%s\n' "$l_handle"
  printf 'headless\tpid\t%s\n' "$l_pid"
  printf 'headless\tstate-dir\t%s\n' "$(sanitize_printable "$unit_dir")"
  return 0
}

# --- run-worker (internal) ---------------------------------------------------
# $1 unit-dir, $2 worktree, $3 handle, $4 scope, then `--` and the launch argv.

do_run_worker() {
  [ "$#" -ge 6 ] || exit 2
  r_unit=$1
  r_wt=$2
  r_handle=$3
  r_scope=$4
  shift 4
  [ "$1" = "--" ] || exit 2
  shift

  # The completion signal is written ATOMICALLY (temp + rename in the same
  # dir) and LAST, so a torn write can never present a half-completed unit.
  finish() {
    printf '%s %s\n' "$1" "$(date +%s)" >"$r_unit/exit.tmp" \
      && mv -f "$r_unit/exit.tmp" "$r_unit/exit"
  }

  cd "$r_wt" || {
    finish 125
    exit 0
  }

  # The dispatch-time identity env (fleet-liveness.sh hook contract): the
  # worker session inherits these, so its plugin hooks push liveness for
  # exactly this unit (hook_registration=true on the contract row).
  PLANWRIGHT_WORKER_HANDLE=$r_handle
  PLANWRIGHT_WORKER_SCOPE=$r_scope
  export PLANWRIGHT_WORKER_HANDLE PLANWRIGHT_WORKER_SCOPE

  r_rc=0
  "$ENVWRAP" "$@" <"$r_unit/prompt" >"$r_unit/result.json" 2>"$r_unit/stderr.log" || r_rc=$?
  finish "$r_rc"
  exit 0
}

# --- status ------------------------------------------------------------------

do_status() {
  s_spec=''
  s_id=''
  s_repo_root=''
  while [ "$#" -gt 0 ]; do
    case $1 in
      --repo-root)
        [ "$#" -ge 2 ] || usage
        s_repo_root=$2
        shift 2
        ;;
      --*)
        warn "unknown flag: $1"
        usage
        ;;
      *)
        if [ -z "$s_spec" ]; then
          s_spec=$1
        elif [ -z "$s_id" ]; then
          s_id=$1
        else
          warn "unexpected argument: $1"
          usage
        fi
        shift
        ;;
    esac
  done
  [ -n "$s_spec" ] && [ -n "$s_id" ] || usage
  valid_spec "$s_spec" || {
    warn "invalid spec id (D-36 grammar)"
    exit 2
  }
  valid_id "$s_id" || {
    warn "invalid task id (D-36 grammar)"
    exit 2
  }
  resolve_unit_dir "$s_spec" "$s_id" "$s_repo_root"

  if [ ! -d "$unit_dir" ]; then
    printf 'absent\n'
    exit 5
  fi
  if [ -f "$unit_dir/exit" ]; then
    s_line=$(cat "$unit_dir/exit" 2>/dev/null || true)
    s_rc=${s_line%% *}
    case $s_rc in
      '' | *[!0-9]*)
        # A garbled completion record: refuse to guess.
        printf 'unknown\n'
        exit 4
        ;;
    esac
    printf 'completed %s\n' "$s_rc"
    exit 0
  fi
  if [ ! -f "$unit_dir/pid" ]; then
    # A torn launch (dir exists, no pid recorded): observability lost.
    printf 'unknown\n'
    exit 4
  fi
  s_pid=$(cat "$unit_dir/pid" 2>/dev/null || true)
  case $s_pid in
    '' | *[!0-9]* | 0*)
      printf 'unknown\n'
      exit 4
      ;;
  esac
  s_rc=0
  "$EVIDENCE" process "$s_pid" >/dev/null 2>&1 || s_rc=$?
  case $s_rc in
    1)
      printf 'running %s\n' "$s_pid"
      exit 1
      ;;
    0)
      # Positive evidence the runner is gone, and no completion record was
      # ever written: the worker died. Never inferred from silence — this is
      # the death-evidence predicate's own verdict.
      printf 'died %s\n' "$s_pid"
      exit 3
      ;;
    *)
      printf 'unknown\n'
      exit 4
      ;;
  esac
}

# --- Entry -------------------------------------------------------------------

[ "$#" -ge 1 ] || usage
sub=$1
shift
case $sub in
  launch) do_launch "$@" ;;
  run-worker) do_run_worker "$@" ;;
  status) do_status "$@" ;;
  *)
    warn "unknown subcommand: $sub"
    usage
    ;;
esac
