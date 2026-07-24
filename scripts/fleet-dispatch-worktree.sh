#!/bin/sh
# fleet-dispatch-worktree.sh — the tmux-backend dispatch primitive that produces
# a worker worktree on the canonical D-36 branch `planwright/<spec>/task-<id>`
# DETERMINISTICALLY at launch, with no manual post-launch `git branch -m` rename
# (fleet-hardening Task 10; D-7 amended 2026-07-20; REQ-B1.4, and REQ-C1.1 /
# REQ-C1.2 / REQ-E1.3 for the tower-guard interaction).
#
# Mechanism, in two steps (D-7):
#   1. CREATE the worktree with a SINGLE
#        git worktree add -b planwright/<spec>/task-<id> \
#          .claude/worktrees/<suffix> <base>
#      call — the narrow, documented never-shell-`git worktree` exception scoped
#      to THIS one dispatch primitive (D-7). `<base>` is the freshly-fetched
#      `origin/main` (never stale local `main` or the tower's HEAD — the
#      fetch-before-act discipline of D-9, via scripts/dispatch-fetch.sh);
#      `<suffix>` is a DETERMINISTIC function of (spec, task-id): `task-<id>`,
#      the branch's own final segment (docs/conventions.md worktree placement);
#      and `<spec>` / `<id>` / `<suffix>` are VALIDATED against the D-36 grammar
#      BEFORE interpolation and passed to git as ARGV (never spliced into a shell
#      string), so no shell metacharacter or `..` path-traversal can reach the
#      command.
#   2. ATTACH with `claude --worktree <suffix> --tmux=classic` (the `attach`
#      subcommand), which discovers the already-placed worktree and folds the
#      classic tmux session + launch. The attach runs ONLY if step 1 exited zero
#      (a non-zero create aborts the dispatch and never attaches to a missing or
#      wrong worktree). The launch is constructed THROUGH scripts/fleet-dispatch-
#      env.sh so the ghost-text pin (Task 5, D-5) is applied structurally, and it
#      is wrapped with the CLIENT-SWITCH MITIGATION (capture-and-restore the
#      prior tmux client attachment) so a tower watching another session is not
#      disrupted (D-7 carried caveat).
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
# a live tmux session for the suffix — not a new source of truth):
#   - LIVE dispatch in flight  -> abort as already-in-flight (exit 3).
#   - STALE / orphaned branch or worktree with no live session (a prior create
#     that died before attach, or a finished task whose branch outlived its
#     worktree) -> GC-adopt: remove the leftover worktree checkout; adopt the
#     existing branch when it carries work (place a fresh worktree on it), or
#     roll it back (delete the just-made branch) when it is a bare partial
#     create; then proceed, so a crash can never wedge a task as permanently
#     already-in-flight. A leftover EMPTY `.claude/worktrees/<suffix>` dir (which
#     `git worktree add` would otherwise SILENTLY create into) is cleaned, not
#     silently reused.
#
# Exception scope (D-7). The `git worktree add` shell-out is confined to THIS
# primitive: a guard over the bundle's dispatch/tower sources (tests/test-fleet-
# dispatch-worktree.sh) asserts no other bundle worktree-creation path shells out
# to `git worktree`. The tower runs this primitive as a planwright script by
# resolved literal path (worker/tower-command-guard `is_repo_script` allowance),
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
#       [--repo-root <dir>] [--attach-dry-run | --no-attach] [-- <extra launch args>...]
#       Validate, fetch `<base>`, reconcile, `git worktree add -b`, then attach.
#       --repo-root      the primary checkout (default: the cwd's git toplevel).
#       --attach-dry-run create for real, but PRINT the attach plan instead of
#                        launching (the create-gates-attach + mitigation fixture
#                        path; no `claude` exec, no model/API call).
#       --no-attach      create-only (execution-backends Task 3): the full
#                        create machinery with no tmux attach and no attach
#                        plan, printing the dispatch record only — for a
#                        backend that launches its own worker into the created
#                        worktree (the headless-oneshot rung,
#                        fleet-dispatch-headless.sh). Launches no worker, so it
#                        takes no post-`--` launch args (refused, not dropped).
#       Everything after `--` is passed through to the `claude` launch argv.
#   fleet-dispatch-worktree.sh attach <suffix> [--dry-run] [-- <extra>...]
#       The attach step alone: capture the prior tmux client session, launch
#       `claude --worktree <suffix> --tmux=classic` (pinned via fleet-dispatch-
#       env.sh), restore the client. --dry-run prints the plan (no exec).
#
# Exit codes:
#   0  success (created + attached / attach-plan printed).
#   2  usage / invalid input (fail closed — a malformed or hostile token is
#      never interpolated).
#   3  already-in-flight: a LIVE concurrent/repeat dispatch (the intended
#      collision guard).
#   4  cannot resolve a fresh `<base>`: the remote is present but the fetch
#      failed after retries (stale ref) — the dispatch must not proceed on a
#      stale base.
#   5  create failed for a non-reconcilable reason (fs/lock/internal error).
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
usage: fleet-dispatch-worktree.sh dispatch <spec> <id> [--repo-root <dir>] [--attach-dry-run | --no-attach] [-- <extra launch args>...]
       fleet-dispatch-worktree.sh attach <suffix> [--dry-run] [-- <extra launch args>...]
EOF
  exit 2
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

# worktree suffix: the branch's final segment `task-<id>`.
valid_suffix() {
  reject_dotdot "$1" || return 1
  case $1 in
    '' | *[!a-z0-9.-]* | [!a-z]*) return 1 ;;
  esac
  printf '%s' "$1" | grep -Eq '^task-[0-9]+(\.[0-9]+)?$' || return 1
  [ "${#1}" -le 72 ] || return 1
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
# The tmux probe accepts either the bare `<suffix>` or the `worktree-<suffix>`
# session name: `claude --worktree <suffix> --tmux=classic` names the classic
# session from the suffix, and the exact spelling is confirmed only by the
# Done-when's [manual] arm, so both plausible names are treated as live.
LIVENESS_SKIP_TMUX="${PLANWRIGHT_DISPATCH_LIVENESS_SKIP_TMUX:-0}"

is_live() {
  # $1 spec-dir  $2 id  $3 suffix
  _sd=$1
  _id=$2
  _suffix=$3

  if [ "$LIVENESS_SKIP_TMUX" != 1 ] && command -v tmux >/dev/null 2>&1; then
    if tmux has-session -t "=$_suffix" 2>/dev/null \
      || tmux has-session -t "=worktree-$_suffix" 2>/dev/null; then
      return 0
    fi
  fi

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

# Is <path> a currently-registered git worktree in <repo>?
is_registered_worktree() {
  # $1 repo-root  $2 abs-path. The porcelain stream emits one `worktree <abs>`
  # line per registered tree; a fixed whole-line match is portable across awks.
  git -C "$1" worktree list --porcelain 2>/dev/null \
    | grep -Fxq "worktree $2"
}

# Does <branch> exist in <repo>?
branch_exists() {
  git -C "$1" show-ref --verify --quiet "refs/heads/$2"
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

# --- attach: capture-and-restore the tmux client around the pinned launch ----

do_attach() {
  # <suffix> [--dry-run] [-- <extra launch args>...]. Guard the positional so a
  # bare `attach` fails with the clean usage/exit-2 path, not a set -u abort.
  [ "$#" -ge 1 ] || usage
  _suffix=$1
  shift
  _dry=0
  if [ "${1:-}" = "--dry-run" ]; then
    _dry=1
    shift
  fi
  if [ "${1:-}" = "--" ]; then
    shift
  fi
  valid_suffix "$_suffix" || {
    warn "invalid worktree suffix: $_suffix"
    exit 2
  }
  # Refuse any unsanctioned extra launch flag before it reaches claude.
  validate_launch_extra "$@"

  # The pinned launch argv: fleet-dispatch-env.sh applies the ghost-text pin
  # (CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION=false) structurally, then exec's the
  # `claude --worktree <suffix> --tmux=classic` launch. `--tmux=classic` is
  # MANDATORY (plain `--tmux` opens non-relay-targetable iTerm2 panes, D-7).
  set -- "$ENVWRAP" claude --worktree "$_suffix" --tmux=classic "$@"

  if [ "$_dry" -eq 1 ]; then
    # The attach PLAN — the designed client-switch mitigation, printed for the
    # fixture (no `claude` exec, no model/API call). Capture the prior client
    # session, run the pinned launch, restore the client to the prior session.
    # Launch tokens are sanitized: a validated `--model` VALUE can still carry
    # control bytes, and this plan prints to the operator's terminal.
    printf 'attach-plan\tsuffix\t%s\n' "$(sanitize_printable "$_suffix")"
    printf 'attach-plan\tcapture\ttmux display-message -p #{client_session}\n'
    printf 'attach-plan\tlaunch'
    for _a in "$@"; do printf '\t%s' "$(sanitize_printable "$_a")"; done
    printf '\n'
    printf 'attach-plan\trestore\ttmux switch-client -t <prior-session>\n'
    return 0
  fi

  # Live attach. Capture the tower's current tmux client session so we can
  # restore it after the launch switches the client to the new worker session.
  _prior=''
  if command -v tmux >/dev/null 2>&1; then
    _prior=$(tmux display-message -p '#{client_session}' 2>/dev/null || true)
  fi

  # Restore via a trap so the client is returned to its prior session on ANY
  # exit path — a normal launch return AND a SIGINT/SIGTERM that kills the
  # launch — never stranding a watching tower on the worker session (D-7). The
  # trap is idempotent (guarded on a non-empty prior + tmux present).
  _restore_client() {
    if [ -n "$_prior" ] && command -v tmux >/dev/null 2>&1; then
      tmux switch-client -t "$_prior" 2>/dev/null || true
    fi
  }
  trap '_restore_client' EXIT INT TERM

  # Run the pinned launch. It creates the classic tmux worker session and folds
  # the launch; the session persists after the client is restored.
  "$@"
  _rc=$?

  _restore_client
  trap - EXIT INT TERM
  return "$_rc"
}

# --- dispatch: create-then-attach --------------------------------------------

do_dispatch() {
  _spec=''
  _id=''
  _repo_root=''
  _attach_dry=0
  _no_attach=0
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
  if [ "$_attach_dry" -eq 1 ] && [ "$_no_attach" -eq 1 ]; then
    warn "--attach-dry-run and --no-attach are alternatives; pass at most one"
    usage
  fi

  # --no-attach launches no worker, so it cannot honor passthrough launch args;
  # accepting them silently would drop them (the attach/dry-run arms forward
  # them, this arm cannot). Refuse rather than silently discard.
  if [ "$_no_attach" -eq 1 ] && [ "$_have_extra" -eq 1 ] && [ "$#" -gt 0 ]; then
    warn "--no-attach launches no worker; it takes no post-\`--\` launch args"
    usage
  fi

  [ -n "$_spec" ] && [ -n "$_id" ] || usage

  # Validate every token BEFORE it appears in any path or command (D-36).
  valid_spec "$_spec" || {
    warn "invalid spec id (D-36 grammar): $_spec"
    exit 2
  }
  valid_id "$_id" || {
    warn "invalid task id (D-36 grammar): $_id"
    exit 2
  }
  _suffix="task-$_id"
  valid_suffix "$_suffix" || {
    warn "invalid worktree suffix (D-36 grammar): $_suffix"
    exit 2
  }
  _branch="planwright/$_spec/task-$_id"

  # Validate the extra launch args (the escalation-pin allowlist) NOW — before
  # any side effect — so a refused flag exits 2 without ever creating a worktree,
  # marker, or registry entry. (do_attach re-validates as defense-in-depth for a
  # direct `attach` invocation.)
  validate_launch_extra "$@"

  # Resolve the repo root.
  if [ -z "$_repo_root" ]; then
    _repo_root=$(git rev-parse --show-toplevel 2>/dev/null || true)
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
  _spec_dir="$_repo_root/specs/$_spec"
  # Fail closed when the spec bundle dir is missing: a task is only ever
  # dispatched within an existing spec, and without `specs/<spec>` the dispatch
  # marker cannot be written, which would degrade liveness to "not live" and let
  # a later collision reconcile force-remove an actually-running worker.
  if [ ! -d "$_spec_dir" ]; then
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
  if git -C "$_repo_root" worktree add -b "$_branch" "$_worktree" "$_base" \
    >/dev/null 2>&1 </dev/null; then
    _created=1
  else
    _created=0
  fi

  if [ "$_created" -eq 0 ]; then
    # Reconcile: distinguish LIVE (abort) from STALE (GC-adopt / roll back).
    if is_live "$_spec_dir" "$_id" "$_suffix"; then
      warn "already-in-flight: a live dispatch holds $_branch (aborting)"
      exit 3
    fi

    # Stale orphan. Remove any leftover worktree checkout (disposable).
    if is_registered_worktree "$_repo_root" "$_worktree"; then
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
      else
        # Bare partial create (branch made, no commits): roll it back and
        # recreate on the fresh base.
        git -C "$_repo_root" branch -D "$_branch" >/dev/null 2>&1 </dev/null || true
        if ! git -C "$_repo_root" worktree add -b "$_branch" "$_worktree" "$_base" \
          >/dev/null 2>&1 </dev/null; then
          warn "failed to recreate $_branch after rolling back a partial create"
          exit 5
        fi
      fi
    else
      # No branch, but the create still failed (e.g. a leftover path we just
      # cleaned). Retry once now that hygiene has run.
      if ! git -C "$_repo_root" worktree add -b "$_branch" "$_worktree" "$_base" \
        >/dev/null 2>&1 </dev/null; then
        warn "worktree create failed for $_branch (non-reconcilable)"
        exit 5
      fi
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
  # failed attach leaves the marker stamped, so a retry reads already-in-flight
  # until the marker ages past LIVENESS_TTL — bounded, never a PERMANENT wedge.
  [ -x "$TRACK" ] && "$TRACK" record-create "$_worktree" >/dev/null 2>&1 </dev/null || true
  if [ -x "$MARKER" ] && [ -d "$_spec_dir" ]; then
    "$MARKER" write "$_spec_dir" "$_id" >/dev/null 2>&1 </dev/null || true
  fi

  # --- Attach (gated on create success) ------------------------------------
  # We only reach here with the worktree created on the exact D-36 branch, so
  # the attach never targets a missing or wrong worktree.
  if [ "$_no_attach" -eq 1 ]; then
    # The create-only arm (execution-backends Task 3): a backend that launches
    # its own worker into the created worktree — the headless-oneshot rung via
    # fleet-dispatch-headless.sh — needs the create machinery above with no
    # tmux attach. Print the dispatch record only; the caller owns the launch.
    printf 'dispatch\tbranch\t%s\n' "$(sanitize_printable "$_branch")"
    printf 'dispatch\tworktree\t%s\n' "$(sanitize_printable "$_worktree")"
    printf 'dispatch\tbase\t%s\n' "$(sanitize_printable "$_base")"
    return 0
  fi
  if [ "$_attach_dry" -eq 1 ]; then
    # Sanitize the header fields too (consistent with the attach-plan tokens): a
    # repo checkout path carrying control bytes would otherwise inject terminal
    # sequences into the operator's output via $_worktree.
    printf 'dispatch\tbranch\t%s\n' "$(sanitize_printable "$_branch")"
    printf 'dispatch\tworktree\t%s\n' "$(sanitize_printable "$_worktree")"
    printf 'dispatch\tbase\t%s\n' "$(sanitize_printable "$_base")"
    if [ "$_have_extra" -eq 1 ]; then
      do_attach "$_suffix" --dry-run -- "$@"
    else
      do_attach "$_suffix" --dry-run
    fi
    return 0
  fi
  if [ "$_have_extra" -eq 1 ]; then
    do_attach "$_suffix" -- "$@"
  else
    do_attach "$_suffix"
  fi
}

# --- Entry -------------------------------------------------------------------

[ "$#" -ge 1 ] || usage
sub=$1
shift
case $sub in
  dispatch) do_dispatch "$@" ;;
  attach) do_attach "$@" ;;
  *)
    warn "unknown subcommand: $sub"
    usage
    ;;
esac
