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
#      side effect; screens the passthrough args as a strict ALLOWLIST (see the
#      pins below); refuses a symlinked worktree (path-escape guard); and
#      fail-fast pre-checks that the launch can actually run (the wrapper is
#      executable and the worker CLI resolves) so a broken install is refused
#      HERE, not reported as a phantom dispatch that later reads as a death.
#   2. Guards the destructive reclaim against symlinked path components, sets a
#      077 umask (state files are owner-only), then writes the prompt (stdin) to
#      the unit's state dir — the prompt and task text travel as DATA end to end
#      (REQ-A1.9): stdin -> file -> the worker's stdin redirect. No token is
#      ever re-parsed by a shell: the runner re-invocation and the worker launch
#      are argv-vector calls, and fleet-dispatch-env.sh finishes with
#      `exec "$@"`.
#   3. Writes the durable `launched` marker, then re-invokes itself as the
#      detached RUNNER (`nohup ... &`), records the runner pid, and waits (a
#      bounded handshake) for the runner to signal readiness before reporting a
#      successful dispatch. The runner cds into the worktree, exports the
#      dispatch-time identity env
#      (PLANWRIGHT_WORKER_HANDLE=headless-<spec>-task-<id>,
#      PLANWRIGHT_WORKER_SCOPE=<spec>:<id>) so the worker's own session fires
#      hook-push liveness (hook_registration=true — fleet-liveness.sh
#      push-capable reads it from the contract), wraps the launch in
#      fleet-dispatch-env.sh (the ghost-text pin), feeds the prompt file on
#      stdin, and captures stdout/stderr.
#   4. The runner SUPERVISES the worker as a background child (not exec): it
#      traps TERM/INT to forward the signal to the worker, reap it, and write a
#      terminal completion record (143), so a graceful kill of the runner reads
#      as a completion rather than orphaning a live worker. When the worker
#      exits, the runner atomically writes the completion signal: `exit` =
#      `<rc> <epoch>`. `result.json` (the `--output-format json` result:
#      is_error, result text, session_id — the session persists and is
#      resumable) and `stderr.log` sit beside it. Only an untrappable SIGKILL of
#      the runner leaves the positive-evidence `died` verdict (the residual the
#      C1 torn-launch guard and /orchestrate's dispatch serialization contain).
#
# THE PINS (REQ-A1.5, D-12; the one-shot permission posture, REQ-A1.2).
#   - Passthrough args are a strict ESCALATION-PIN ALLOWLIST (REQ-A1.9), the
#     same policy as the sibling fleet-dispatch-worktree.sh: only `--model` /
#     `--fallback-model` / `--continue` / `--resume` are sanctioned; every
#     other flag — a permission escalation, a sandbox-widening `--add-dir`, and
#     the two posture-breakers below — is refused (exit 2), never forwarded to
#     the detached worker.
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
#     launched     launch epoch seconds (written BEFORE the runner backgrounds,
#                  so a torn launch is still ageable by the collision guard)
#     prompt       the worker's stdin (written from launch stdin)
#     pid          the detached runner's pid (the process liveness supervises)
#     started      the runner's readiness marker (its first durable act)
#     result.json  the worker's stdout (the --output-format json result)
#     stderr.log   the worker's stderr
#     exit         `<rc> <epoch>` — the completion signal (atomic, written last)
#     finish-error (only on a failed exit write) — marks a completed-but-
#                  unrecordable worker so status reports `unknown`, not `died`
# All files are owner-only (umask 077). The default base sits under
# specs/<spec>/.orchestrate/ (gitignored runtime state, like the dispatch
# markers), so nothing here is ever committed.
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
# Exit codes: launch 0 dispatched; 2 usage / refused input (hostile token, an
# unsanctioned/posture-violating passthrough arg, a symlinked worktree or state
# path, a broken install — missing wrapper or CLI, empty prompt, missing
# worktree) — nothing launched; 3 already-in-flight (a live runner, an unknown
# liveness, or a recent torn-launch window — refuse to double-dispatch); 4 the
# runner failed to start (it exited before signalling readiness) — the state
# dir is cleaned. status: per the verdict table above.
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
# The launch wrapper is overridable for tests (the fault-injection seam that
# exercises the launch-time executability pre-check); default is the sibling.
ENVWRAP="${PLANWRIGHT_HEADLESS_ENVWRAP:-$script_dir/fleet-dispatch-env.sh}"
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
  unit_base=$rud_base
  unit_dir="$rud_base/$2"
}

# --- Launch-arg allowlist (REQ-A1.9, mirrors fleet-dispatch-worktree.sh) ------
# The two posture-breakers are named specifically (they cite the pin they
# violate); every other unsanctioned arg is refused by the default arm. The
# sanctioned set is exactly the sibling's: model selection and session
# continuation. Runs before any side effect, so a refused arg exits 2 with
# nothing launched.
validate_launch_extra() {
  while [ "$#" -gt 0 ]; do
    case $1 in
      --bare | --bare=*)
        warn "refusing --bare: the non---bare launch pin (REQ-A1.5) forbids it at every worker launch site"
        exit 2
        ;;
      --permission-prompt-tool | --permission-prompt-tool=*)
        warn "refusing --permission-prompt-tool: a one-shot has no pend path (REQ-A1.2); an unauthorized ask must fail visibly in the result"
        exit 2
        ;;
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
        warn "launch flag has an empty value: $1"
        exit 2
        ;;
      --model=-* | --fallback-model=-*)
        warn "launch flag has a flag-shaped value: $1"
        exit 2
        ;;
      --model=* | --fallback-model=*) shift ;;
      --continue | -c) shift ;;
      --resume | -r)
        shift
        if [ "$#" -ge 1 ]; then
          case $1 in
            -*) ;;
            *) shift ;;
          esac
        fi
        ;;
      --resume=* | -r=*) shift ;;
      *)
        warn "refusing unsanctioned launch arg (escalation-pin, REQ-A1.9): $1"
        exit 2
        ;;
    esac
  done
}

# --- Destructive-path containment guard (REQ-A1.9, mirrors the sibling) -------
# `rm -rf`/`mkdir -p` on the unit dir FOLLOW a symlinked path component, so a
# compromised checkout carrying a symlinked `.orchestrate` / `headless` (or a
# hostile PLANWRIGHT_HEADLESS_STATE_DIR) could make the reclaim delete or create
# OUTSIDE the intended base. Refuse a symlinked base or leaf, materialize the
# base as a REAL directory, and confirm the unit dir physically resolves UNDER
# it — fail closed. $1 = base dir, $2 = unit dir. Runs before any rm/mkdir.
guard_unit_containment() {
  guc_base=$1
  guc_unit=$2
  if [ -L "$guc_base" ]; then
    warn "refusing: state base $guc_base is a symlink (path-escape guard)"
    exit 2
  fi
  mkdir -p "$guc_base" 2>/dev/null || {
    warn "cannot create state base: $guc_base"
    exit 2
  }
  guc_base_phys=$(cd "$guc_base" 2>/dev/null && pwd -P) || {
    warn "state base does not resolve: $guc_base"
    exit 2
  }
  if [ -L "$guc_unit" ]; then
    warn "refusing: unit state dir $guc_unit is a symlink (path-escape guard)"
    exit 2
  fi
  # The unit dir must sit directly under the physical base (its basename is the
  # validated task id, so string-join then physical-parent check is sound).
  case "$guc_base_phys/" in
    /*) ;;
    *)
      warn "refusing: state base is not an absolute path after resolution"
      exit 2
      ;;
  esac
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
  # Refuse a symlinked worktree leaf before resolving it (path-escape parity
  # with the sibling): the worker is cd'd into this dir, and a symlink would
  # silently redirect the run's cwd outside the intended checkout.
  if [ -L "$l_worktree" ]; then
    warn "refusing: worktree $l_worktree is a symlink (path-escape guard)"
    exit 2
  fi
  [ -d "$l_worktree" ] || {
    warn "worktree not found: $l_worktree (create it first: fleet-dispatch-worktree.sh dispatch $l_spec $l_id --no-attach)"
    exit 2
  }
  l_worktree=$(cd "$l_worktree" && pwd -P) || exit 2

  # Screen the passthrough args BEFORE any side effect (REQ-A1.5, REQ-A1.9),
  # as a strict ESCALATION-PIN ALLOWLIST — byte-for-byte the sibling
  # fleet-dispatch-worktree.sh `validate_launch_extra` policy (REQ-C1.2), so the
  # two worker-launch sites enforce the same containment. Only the model and
  # session-continuation flags are sanctioned; anything else (permission
  # escalation like `--dangerously-skip-permissions` / `--allowedTools`, sandbox
  # widening like `--add-dir`, and the two posture-breakers `--bare` /
  # `--permission-prompt-tool`) is refused, never forwarded to the detached
  # worker. The two posture-breakers keep their specific diagnostics (they name
  # the pin they violate); everything else off the allowlist is the default
  # unsanctioned-arg refusal.
  validate_launch_extra "$@"

  resolve_unit_dir "$l_spec" "$l_id" "$l_repo_root"

  # Fail-fast infrastructure pre-check (C9/C10): a launch that cannot possibly
  # run must be refused HERE, not reported as a successful dispatch that later
  # masquerades as a worker death or a `completed 127`. The wrapper must be
  # executable and the worker CLI must resolve; either missing is a broken
  # install, exit 2, nothing dispatched.
  if [ ! -x "$ENVWRAP" ]; then
    warn "launch wrapper missing or not executable: $ENVWRAP (broken install)"
    exit 2
  fi
  l_bin="${PLANWRIGHT_HEADLESS_CLAUDE:-claude}"
  if ! command -v "$l_bin" >/dev/null 2>&1; then
    warn "worker CLI not found on PATH: $l_bin (nothing to dispatch)"
    exit 2
  fi

  # Collision guard: never double-dispatch a unit whose runner may be live.
  # Death is decided by positive evidence only; UNKNOWN refuses too (lost
  # observability is not a license to double-dispatch). A dead or completed
  # prior record is cleaned and re-dispatched (a legitimate retry). The TORN
  # LAUNCH window (C1): a prior launch backgrounded but was killed before it
  # recorded its pid leaves a state dir with a `launched` marker and no pid —
  # ambiguous, so it fails SAFE toward live (refuse) until the marker ages past
  # the TTL, exactly as the sibling fleet-dispatch-worktree.sh treats its
  # dispatch marker.
  l_ttl="${PLANWRIGHT_HEADLESS_LIVENESS_TTL:-900}"
  case $l_ttl in
    '' | *[!0-9]*) l_ttl=900 ;;
  esac
  if [ -d "$unit_dir" ] && [ ! -f "$unit_dir/exit" ]; then
    if [ -f "$unit_dir/pid" ]; then
      l_old_pid=$(cat "$unit_dir/pid" 2>/dev/null || true)
      case $l_old_pid in
        '' | *[!0-9]* | 0*)
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
    else
      # No pid yet, no exit: either a torn launch mid-flight or a crashed
      # launch that never got going. Disambiguate by the `launched` marker's
      # age — younger than the TTL is treated as possibly-live (refuse), older
      # (or absent) is stale and reclaimable.
      l_born=$(cat "$unit_dir/launched" 2>/dev/null || true)
      l_now=$(date +%s 2>/dev/null || echo '')
      case ${l_born:-x}${l_now:-x} in
        *[!0-9]*)
          # Unreadable/unparseable marker or clock failure: fail safe toward
          # live, exactly like the sibling's ambiguous-read discipline.
          warn "unit $l_spec/$l_id has an in-flight-looking state dir with no readable launch time; refusing to double-dispatch (inspect $unit_dir)"
          exit 3
          ;;
        *)
          if [ "$((l_now - l_born))" -lt "$l_ttl" ]; then
            warn "unit $l_spec/$l_id has a recent in-flight launch with no pid yet (torn-launch window); refusing to double-dispatch"
            exit 3
          fi
          ;;
      esac
    fi
  fi

  # Containment guard BEFORE the destructive reclaim (S2): the rm -rf / mkdir
  # below follow symlinked path components, so refuse a symlinked base or leaf.
  guard_unit_containment "$unit_base" "$unit_dir"

  # State files carry the worker's brief (prompt) and the model's output
  # (result.json, session_id) — restrict them to the owner (S3): a subprocess
  # umask so the dir and every file below are 0700/0600, never world-readable
  # on a multi-user host. Scoped to this function via a subshell would lose the
  # side effects, so set it here; do_launch exits the process either way.
  umask 077

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

  # Write the durable `launched` timestamp BEFORE backgrounding (C1): it is the
  # marker the collision guard ages against, so even a launch killed in the
  # window before the pid is recorded leaves a marker that reads as in-flight
  # (fail safe) rather than as a reclaimable stale dir a concurrent launch
  # would rm -rf out from under a live runner.
  date +%s >"$unit_dir/launched"

  # Detach: re-invoke self as the runner under nohup so the worker survives
  # the tower's death (session-grade: the one-shot is its own top-level
  # session). Every token is an argv element end to end — never re-parsed by
  # a shell (REQ-A1.9). The runner (not the worker) is the recorded pid: it
  # traps signals, owns the completion write, and forwards its own death into a
  # terminal `exit` record (see do_run_worker), so a graceful kill reads as a
  # completion, and only an untrappable SIGKILL leaves the positive-evidence
  # `died` verdict.
  nohup /bin/sh "$SELF" run-worker "$unit_dir" "$l_worktree" "$l_handle" "$l_scope" -- \
    "$l_bin" --print --output-format json "$@" \
    >/dev/null 2>&1 </dev/null &
  l_pid=$!
  printf '%s\n' "$l_pid" >"$unit_dir/pid"

  # Runner-start handshake (C9): confirm the runner actually got going before
  # reporting a successful dispatch. The runner writes a `started` marker as its
  # first durable act; wait a bounded interval for `started`, `exit` (a very
  # fast worker), or positive evidence the runner is already gone. A runner that
  # dies with none of those never started (bad exec / instant crash) — clean up
  # and report a launch failure, not a phantom dispatch that later reads `died`.
  l_waited=0
  while [ ! -e "$unit_dir/started" ] && [ ! -e "$unit_dir/exit" ]; do
    if ! kill -0 "$l_pid" 2>/dev/null; then
      # Runner gone; give the filesystem a beat in case it wrote-then-exited.
      [ -e "$unit_dir/started" ] || [ -e "$unit_dir/exit" ] && break
      warn "unit $l_spec/$l_id runner failed to start (exited before signalling readiness)"
      rm -rf "$unit_dir"
      exit 4
    fi
    [ "$l_waited" -ge 100 ] && break # ~10s cap: proceed, status will observe it
    sleep 0.1
    l_waited=$((l_waited + 1))
  done

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

  # umask parity with the launch side (S3): the runner writes result.json /
  # stderr.log / exit under the same owner-only mode as the prompt.
  umask 077

  # The completion signal is written ATOMICALLY (temp + rename in the same dir)
  # and LAST, so a torn write can never present a half-completed unit. On a
  # write failure (C7 — ENOSPC, a read-only dir), the completion outcome must
  # NOT be silently lost: drop a `finish-error` marker so status reports
  # `unknown` (refuse to guess) rather than the runner's death later reading as
  # `died` for a worker that actually finished. Both writes are best-effort;
  # if even the marker cannot land the reconcile backstop still applies.
  finish() {
    if printf '%s %s\n' "$1" "$(date +%s)" >"$r_unit/exit.tmp" 2>/dev/null \
      && mv -f "$r_unit/exit.tmp" "$r_unit/exit" 2>/dev/null; then
      return 0
    fi
    : >"$r_unit/finish-error" 2>/dev/null || true
    return 1
  }

  # Readiness marker (C9 handshake counterpart): the runner's first durable act,
  # so launch can distinguish "started" from "never got going".
  : >"$r_unit/started" 2>/dev/null || true

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

  # Trap-forward supervision (C2): run the worker as a background child and wait
  # on it, so the runner (the recorded pid) can FORWARD a graceful kill into the
  # worker and record a terminal completion instead of orphaning it. On TERM/INT
  # the trap kills the worker, reaps it, and writes a terminal exit record
  # (143 = 128+SIGTERM), so `kill <runner>` reads as `completed 143`, never a
  # `died` verdict over a still-running orphan. An untrappable SIGKILL of the
  # runner is the one residual (the worker orphans, no exit record → `died`) —
  # the same limit fleet-death-evidence.sh already accepts, and /orchestrate's
  # dispatch serialization plus the C1 torn-launch guard keep a retry from
  # double-dispatching into the live worktree.
  "$ENVWRAP" "$@" <"$r_unit/prompt" >"$r_unit/result.json" 2>"$r_unit/stderr.log" &
  r_worker=$!
  trap 'kill "$r_worker" 2>/dev/null; wait "$r_worker" 2>/dev/null; finish 143; exit 0' TERM INT
  r_rc=0
  wait "$r_worker" || r_rc=$?
  # Clear the trap so a signal during the final write cannot double-invoke it.
  trap - TERM INT
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
  # read_exit: print `completed <rc>` (exit 0) if a well-formed exit record
  # exists, `unknown` (exit 4) if it is garbled; return 1 if there is no record
  # yet. Factored out so the death branch can re-check it (C5).
  read_exit() {
    [ -f "$unit_dir/exit" ] || return 1
    re_line=$(cat "$unit_dir/exit" 2>/dev/null || true)
    re_rc=${re_line%% *}
    case $re_rc in
      '' | *[!0-9]*)
        printf 'unknown\n'
        exit 4
        ;;
    esac
    printf 'completed %s\n' "$re_rc"
    exit 0
  }
  read_exit
  # A completed-but-unrecordable worker (C7): the runner finished but its exit
  # write failed and left a finish-error marker — refuse to guess `died`.
  if [ -f "$unit_dir/finish-error" ]; then
    printf 'unknown\n'
    exit 4
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
      # Positive evidence the runner is gone. RE-CHECK the completion record
      # first (C5): the runner writes `exit` and THEN terminates, so a probe
      # that raced that window would otherwise pronounce `died` over a worker
      # that in fact just completed. Only with no exit record and no
      # finish-error marker is this a genuine death (never inferred from
      # silence — the death-evidence predicate's own verdict).
      read_exit
      if [ -f "$unit_dir/finish-error" ]; then
        printf 'unknown\n'
        exit 4
      fi
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
