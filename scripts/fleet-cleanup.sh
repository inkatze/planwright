#!/bin/sh
# fleet-cleanup.sh — the deterministic stale-resource cleanup actuator with an
# explicit self-targeting guard (Task 4: D-6, D-5, D-15, D-16; REQ-B1.1).
#
# WHY DETERMINISTIC (D-6). Stale window/pane/worktree/process cleanup runs as
# script logic, never in-context model judgment. A real postmortem
# (anthropics/claude-code#29787) shows an LLM-driven cleanup non-deterministically
# issuing `tmux kill-session` against its OWN hosting pane, destroying the whole
# session. This actuator closes that exact failure mode two ways: it never lets a
# model decide what to reclaim (the caller passes an explicit target and this
# script gates it), and it REFUSES outright to act on a target that resolves to
# the caller's own hosting session/worktree (the self-targeting guard).
#
# POSITIVE EVIDENCE ONLY (D-5). A resource is reclaimed only on positive,
# deterministic evidence that reclaiming it loses nothing — a tmux window whose
# panes are all dead (`#{pane_dead}` = 1, the worker process exited), or a git
# worktree that is clean AND whose commits provably survive its removal (either
# upstream parity or a verified merged PR; see the `worktree` usage). Silence, a
# timeout, or a "probably stale" guess is never admissible: the same discipline
# scripts/fleet-death-evidence.sh encodes, applied to reclamation. A live pane or
# an unproven/dirty worktree is refused, never reclaimed. A worker process is
# reaped only on the stuck-detector's positive evidence that its owning tower is
# dead and its session ended (see the `process` usage).
#
# KILL-SWITCH + AUDIT (D-15, D-16). Every invocation gates through
# scripts/fleet-daemon-gate.sh BEFORE acting (a set `fleet_daemon_pause` pauses
# the whole daemon layer), and every reclaim — and every self-block, a notable
# safety event — is written to the shared audit trail (scripts/fleet-audit.sh).
#
# Usage:
#   fleet-cleanup.sh window <session> <window> <trigger> <reasoning>
#       Reclaim a stale tmux window (kill-window) whose panes are all dead.
#       <window> matches either #{window_id} (@N) or #{window_name}. The self
#       identity is resolved from the caller's own pane ($TMUX_PANE via
#       `tmux display-message`); it is refused if it resolves to that window.
#   fleet-cleanup.sh worktree <path> <trigger> <reasoning> [--merged-pr <n>]
#       Remove a clean, provably-reclaimable git worktree (git worktree remove).
#       Refused if <path> is (or contains) the caller's own worktree, or if it
#       carries uncommitted work, or if neither evidence path below holds:
#         A. upstream parity — a configured upstream, zero commits ahead;
#         B. --merged-pr <n> — this script verifies via `gh` that PR <n> is
#            MERGED and that its head oid IS this worktree's HEAD. This covers
#            the post-merge shape where the forge auto-deleted the remote branch:
#            the upstream is gone, so A can never hold, even though the commits
#            are provably merged. Verified, never trusted — no `gh`, no `timeout`
#            to bound the query, a query that exceeds that bound, a reply that is
#            not exactly the two fields asked for, an unreadable field, a
#            non-MERGED state, or an oid mismatch all refuse.
#            PLANWRIGHT_CLEANUP_GH_TIMEOUT bounds the query (default 20s).
#   fleet-cleanup.sh process <worker> <trigger> <reasoning> [--grace <secs>]
#       [--repo-root <dir>] [--tower-id <token>]
#       Reap a leaked worker process: one whose owning tower is gone, whose
#       session has ended, and whose process tree has not. It RELEASES THE
#       PROCESS ONLY, with the runtime the rung's `stop` releases alongside it:
#       it touches no fence, branch, or worktree, and a strand surfaced for the
#       operator stays surfaced. Reaping is not reclaiming, and the reclaim
#       decision stays the operator's.
#
#       The verdict comes from scripts/fleet-stuck-detector.sh, whose registry
#       read and owner attribution this arm does not re-derive; --tower-id is
#       handed to it, and without it the detector resolves this tower's
#       identity from the environment as it always does. An errored verdict or a
#       missing dispatch record refuses first (exit 5); past those, refused in
#       this order:
#         a `print`-backend unit, which spawned no process (exit 8);
#         a worker owned by a live peer tower, under any evidence (exit 7);
#         a backend with no process close, such as tmux (exit 5);
#         a headless worker whose record names no state directory (exit 5);
#         anything short of positive evidence on BOTH axes (exit 5): the
#           owning tower must be positively dead, and the session must have
#           positively ended, by death evidence or a completion signal. An
#           unknown, ambiguous, or unreadable verdict is a refusal, and so is
#           this tower's own worker, which the tower closes with the rung's
#           `stop`.
#
#       The close itself is the rung's own `stop`
#       (scripts/fleet-streamjson.sh, scripts/fleet-dispatch-headless.sh), so
#       the fleet has one kill path: this arm matches no process, sends no
#       signal, and releases nothing of its own. --grace is the SIGTERM-to-
#       SIGKILL grace that stop takes, and --repo-root is passed to the headless
#       rung, which resolves its unit directory from it. That rung is also
#       handed the state directory the verdict was read from and refuses a
#       handle resolving to any other unit, such as a same-handle unit in
#       another checkout (a plain refusal here, exit 5). The rung's result line
#       is printed on stdout. A close from inside the worker's own tree is the
#       rung's self-hosting refusal, reported here as the self-target block;
#       a rung that cannot read the process table to decide that refuses
#       before acting, which reaches this script as a plain refusal (exit 5).
#
#       A partial close is exit 5 with a `cleanup-partial` record naming what
#       was released and what is still held. It is recorded even when nothing
#       came free, since the rung may have signalled the tree before finding a
#       class still held. A rung that died on a signal mid-close is recorded as
#       a partial close too, both sets `unreported`.
#
#       A handle in the `pwfence.` namespace is refused as malformed: that is
#       where the fence sweep keys the strand entries it surfaces, and a close
#       clears the attention row keyed by the handle it is given.
#
# <trigger>/<reasoning> are free-text audit fields (the caller's determination of
# WHY the target is stale) under fleet-audit's control-free text grammar. A
# process record also names the worker, its owner token, and the evidence class,
# then for a close the released set (and for a partial one the held set), all
# ahead of <reasoning>, which is cut short when the whole would outgrow the
# grammar's bound. A self-block record carries the worker, owner, and evidence
# prefix, with no released set.
#
# Exit codes:
#   0  acted (resource reclaimed) or a clean no-op (target already gone)
#   2  usage / refused malformed token
#   3  refused by the self-targeting guard — the target is, or cannot be proven
#      not to be, the caller's own hosting session/worktree (the #29787 block).
#      This also covers any environment fault that makes proving non-self
#      impossible (no resolvable tmux / no $TMUX_PANE; caller not in a git
#      worktree; no git binary): fail closed, refuse rather than risk a self-hit.
#   4  refused: the fleet_daemon_pause kill-switch is set (or the gate could not
#      resolve its own switch — fail closed, degrade capability never safety)
#   5  refused: no positive evidence the target is reclaimable (a live pane, a
#      dirty worktree, one whose commits are not provably safe — no upstream
#      parity and no verified --merged-pr — or lost observability: neither a tmux
#      server unreachable mid-probe nor an unusable `gh` is proof of absence),
#      or the reclaim command itself failed; for `process`, also a partial
#      close, which acted and is recorded (see its usage)
#   6  acted (resource WAS reclaimed) but the audit-trail write failed — the
#      action happened and is unrecorded; distinct from 2 so a caller never reads
#      an unlogged reclaim as "nothing happened". For `process` that includes a
#      partial close, which may have signalled the tree and released nothing
#   7  process only: refused, the worker is owned by a live peer tower
#   8  process only: refused, a `print`-backend unit has no process to reap
#
# POSIX sh on the macOS + Linux support bar (bash 3.2 / BSD tooling). All input
# is data; no eval, no jq (REQ-K1.5). Pathname expansion is disabled (set -f).
set -uf

LC_ALL=C
export LC_ALL
unset CDPATH

script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2

# The canonical echo-discipline sanitizer, sourced as the sibling fleet scripts
# do; a missing helper is a broken install.
# shellcheck source=scripts/echo-safety.sh
. "$script_dir/echo-safety.sh"

GATE="$script_dir/fleet-daemon-gate.sh"
AUDIT="$script_dir/fleet-audit.sh"
TAB=$(printf '\t')

warn() { printf 'fleet-cleanup: %s\n' "$*" >&2; }

usage() {
  echo "usage: fleet-cleanup.sh window <session> <window> <trigger> <reasoning>" >&2
  echo "       fleet-cleanup.sh worktree <path> <trigger> <reasoning> [--merged-pr <n>]" >&2
  echo "       fleet-cleanup.sh process <worker> <trigger> <reasoning> [--grace <secs>] [--repo-root <dir>] [--tower-id <token>]" >&2
}

# The fleet field grammar worker handles are registered under (fleet-state.sh
# valid_field), plus a leading-dash refusal: the handle becomes an argv word.
valid_worker() {
  case $1 in
    "" | . | .. | -* | *[!A-Za-z0-9._=@:-]*) return 1 ;;
  esac
  [ "${#1}" -le 128 ]
}

# The registry's owner-token grammar (fleet-state.sh valid_owner).
valid_owner() {
  case $1 in
    "" | . | .. | unknown-owner | -* | *[!A-Za-z0-9._-]*) return 1 ;;
  esac
  [ "${#1}" -le 128 ]
}

# read_verdict <verdict> <worker> — the detector's row for <worker> and the
# evidence slots the process arm decides on, as one tab-joined line: state,
# owner class, reason, then the registry, backend, owner-token, owner-evidence
# and state-dir values. A slot the verdict lacks reads `-`, so no field is
# empty and a tab-split cannot shift the ones after it.
read_verdict() {
  printf '%s\n' "$1" | awk -F'\t' -v w="$2" '
    ($2 "") != (w "") { next }
    $1 == "worker" && !row { st = $3; oc = $4; rs = $6; row = 1 }
    $1 == "evidence" && !($3 in ev) { ev[$3] = $4 }
    function v(x) { return x == "" ? "-" : x }
    END {
      if (!row) exit
      printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n", v(st), v(oc), v(rs),
        v(ev["registry"]), v(ev["backend"]), v(ev["owner-token"]), v(ev["owner-evidence"]),
        v(ev["state-dir"])
    }'
}

# fit_text <text> — <text> cut to the audit grammar's bound. The cut is by
# byte, so it can land inside a multibyte character; the continuation bytes it
# left and the lead byte they belong to are dropped with it, which can cost
# one whole character when the cut fell exactly on a boundary.
fit_text() {
  ft_v=$1
  ft_cut=0
  while [ "${#ft_v}" -gt 512 ]; do
    ft_v=${ft_v%?}
    ft_cut=1
  done
  ft_n=0
  while [ "$ft_cut" = 1 ] && [ -n "$ft_v" ]; do
    ft_b=$(printf '%s' "$ft_v" | tail -c 1 | od -An -tu1 | tr -d ' ')
    case $ft_b in
      "" | *[!0-9]*) break ;;
    esac
    [ "$ft_b" -ge 128 ] || break
    ft_v=${ft_v%?}
    ft_n=$((ft_n + 1))
    # A byte from 0xC0 up leads a character; one is dropped, never more.
    { [ "$ft_b" -lt 192 ] && [ "$ft_n" -lt 4 ]; } || break
  done
  while [ -n "$ft_v" ] && ! valid_text "$ft_v"; do
    ft_v=${ft_v%?}
  done
  printf '%s' "$ft_v"
}

# The tmux handle grammar (fleet-death-evidence.sh's conservative single-token
# subset): no path separators, no `:` combined-target separator, no whitespace
# or shell metacharacter, no leading dash (option injection); bounded to 128.
valid_tmux_token() {
  vtt=$1
  case $vtt in
    "" | -*) return 1 ;;
    *[!A-Za-z0-9_@%.-]*) return 1 ;;
  esac
  [ "${#vtt}" -le 128 ]
}

# The control-free text grammar for the audit fields, byte-identical to
# fleet-audit.sh valid_text: non-empty, <=512 bytes, no C0/DEL/C1.
valid_text() {
  vt_v=$1
  [ -n "$vt_v" ] || return 1
  [ "${#vt_v}" -le 512 ] || return 1
  [ "$(sanitize_printable "$vt_v")" = "$vt_v" ]
}

# gh_timeout — the wall-clock bound on the merged-PR evidence query, in seconds.
# PLANWRIGHT_CLEANUP_GH_TIMEOUT overrides the default 20; a malformed, zero, or
# absurdly long value falls back to it (a zero bound would kill every query and
# read as a permanently unreachable forge). Validation shape is deliberately
# byte-for-byte fleet-liveness.sh's oracle_timeout, this tree's sibling
# wall-clock bound, so the two behave identically on malformed input.
gh_timeout() {
  gt_v="${PLANWRIGHT_CLEANUP_GH_TIMEOUT:-20}"
  case $gt_v in
    "" | *[!0-9]* | 0 | 0?*) gt_v=20 ;;
  esac
  [ "${#gt_v}" -le 4 ] || gt_v=20
  printf '%s' "$gt_v"
}

# gate <mechanism> — fail-closed kill-switch check. Returns 0 to proceed; prints
# a note and returns 4 on any non-zero gate result (paused, or a resolver
# hard-fail: never act under an unresolved/paused switch).
gate() {
  "$GATE" "$1" 2>/dev/null && return 0
  warn "daemon layer paused or kill-switch unresolvable — refusing '$1' (unset fleet_daemon_pause to resume)"
  return 4
}

# audit <mechanism> <action> <trigger> <reasoning> — best-effort trail write.
# A reclaim's audit failure is surfaced loudly by the caller (an unrecorded
# action is what the trail exists to prevent); a self-block's is a warn only.
audit() {
  "$AUDIT" record "$1" "$2" "$3" "$4"
}

cmd=${1:-}
case "$cmd" in
  window | worktree | process) shift ;;
  "")
    usage
    exit 2
    ;;
  *)
    usage
    exit 2
    ;;
esac

case "$cmd" in
  window)
    if [ "$#" -ne 4 ]; then
      usage
      exit 2
    fi
    session=$1
    window=$2
    trigger=$3
    reasoning=$4
    if ! valid_tmux_token "$session" || ! valid_tmux_token "$window"; then
      warn "refusing malformed tmux token"
      exit 2
    fi
    if ! valid_text "$trigger" || ! valid_text "$reasoning"; then
      warn "refusing an audit field with a control byte, an embedded tab/newline, or over-length text"
      exit 2
    fi

    gate window-cleanup || exit 4

    # Resolve self-identity from the caller's own pane. A cleanup that cannot
    # prove the target is NOT its own window fails closed (refuse): the whole
    # point of the guard is that we would rather leave a stale window than risk
    # the #29787 self-kill. TMUX_PANE must be non-empty — with an empty `-t ""`
    # tmux resolves the CURRENTLY ACTIVE pane, which need not be the caller's
    # host, so self-identity would be unreliable: refuse.
    if [ -z "${TMUX:-}" ] || ! command -v tmux >/dev/null 2>&1; then
      warn "not inside a resolvable tmux (no \$TMUX or no tmux binary) — cannot prove non-self-target, refusing (fail closed)"
      exit 3
    fi
    if [ -z "${TMUX_PANE:-}" ]; then
      warn "\$TMUX_PANE is unset — cannot reliably resolve the caller's own pane, refusing (fail closed)"
      exit 3
    fi
    self=$(tmux display-message -p -t "$TMUX_PANE" \
      "#{session_name}${TAB}#{window_id}${TAB}#{window_name}${TAB}#{window_index}" 2>/dev/null) || self=""
    if [ -z "$self" ]; then
      warn "could not resolve the caller's own tmux window — cannot prove non-self-target, refusing (fail closed)"
      exit 3
    fi
    self_session=${self%%"$TAB"*}
    self_rest=${self#*"$TAB"}
    self_wid=${self_rest%%"$TAB"*}
    self_rest=${self_rest#*"$TAB"}
    self_wname=${self_rest%%"$TAB"*}
    self_windex=${self_rest#*"$TAB"}

    # The guard matches the target window against the caller's own window id,
    # name, OR index (all three are valid tmux window addresses), so no address
    # form for the caller's own window slips past.
    if [ "$session" = "$self_session" ] \
      && { [ "$window" = "$self_wid" ] || [ "$window" = "$self_wname" ] || [ "$window" = "$self_windex" ]; }; then
      warn "REFUSING self-target: '$session:$window' is the caller's own hosting window (the #29787 block)"
      audit window-cleanup refuse-self "$trigger" "$reasoning" \
        || warn "could not record the self-block in the audit trail"
      exit 3
    fi

    # Positive evidence: the target's panes must all be dead. A list-panes
    # failure is NOT proof the window is gone — it could be lost observability
    # (the 2026-06-12 lesson). Distinguish the two by re-probing server health:
    # an unreachable server is unknown (refuse, exit 5), a healthy server with
    # the window absent is genuinely gone (a clean no-op, exit 0).
    target="=$session:$window"
    panes=$(tmux list-panes -t "$target" -F '#{pane_dead}' 2>/dev/null) || {
      if tmux ls >/dev/null 2>&1; then
        # Healthy server, window absent from its authoritative listing: gone.
        exit 0
      fi
      warn "tmux server unreachable while probing '$session:$window' — lost observability, refusing (not proof of absence)"
      exit 5
    }
    if [ -z "$panes" ]; then
      warn "no pane state for '$session:$window' — no positive evidence it is reclaimable, refusing"
      exit 5
    fi
    old_ifs=$IFS
    IFS='
'
    for pd in $panes; do
      if [ "$pd" != 1 ]; then
        IFS=$old_ifs
        warn "'$session:$window' has a live pane (pane_dead='$pd') — refusing to kill a live worker"
        exit 5
      fi
    done
    IFS=$old_ifs

    if ! tmux kill-window -t "$target" 2>/dev/null; then
      warn "kill-window '$session:$window' failed — not reclaimed"
      exit 5
    fi
    if ! audit window-cleanup cleanup "$trigger" "$reasoning"; then
      warn "reclaimed window '$session:$window' but FAILED to record it in the audit trail"
      exit 6
    fi
    exit 0
    ;;

  worktree)
    if [ "$#" -ne 3 ] && [ "$#" -ne 5 ]; then
      usage
      exit 2
    fi
    path=$1
    trigger=$2
    reasoning=$3
    # Optional second evidence path (see the evidence block below). The number is
    # DATA: digit-only, no leading zero, length-bounded, and never interpolated
    # into a shell string — it is passed to `gh` as ARGV.
    merged_pr=""
    if [ "$#" -eq 5 ]; then
      if [ "$4" != "--merged-pr" ]; then
        usage
        exit 2
      fi
      merged_pr=$5
      case $merged_pr in
        "" | *[!0-9]* | 0*)
          warn "refusing a --merged-pr value that is not a positive decimal PR number"
          exit 2
          ;;
      esac
      if [ "${#merged_pr}" -gt 9 ]; then
        warn "refusing an over-length --merged-pr number"
        exit 2
      fi
    fi
    case $path in
      "" | -*)
        warn "refusing malformed worktree path (empty or leading dash)"
        exit 2
        ;;
      /*) ;;
      *)
        warn "refusing a non-absolute worktree path"
        exit 2
        ;;
    esac
    if [ "$path" != "$(sanitize_printable "$path")" ]; then
      warn "refusing a worktree path with a control byte"
      exit 2
    fi
    if ! valid_text "$trigger" || ! valid_text "$reasoning"; then
      warn "refusing an audit field with a control byte, an embedded tab/newline, or over-length text"
      exit 2
    fi

    gate worktree-cleanup || exit 4

    command -v git >/dev/null 2>&1 || {
      warn "no git binary on PATH — cannot verify a worktree is reclaimable, refusing (fail closed)"
      exit 3
    }

    # Resolve the caller's own worktree root; fail closed if it cannot be
    # determined (we cannot prove the target is not ourselves).
    self_wt=$(git rev-parse --show-toplevel 2>/dev/null) || self_wt=""
    if [ -z "$self_wt" ]; then
      warn "caller is not inside a resolvable git worktree — cannot prove non-self-target, refusing (fail closed)"
      exit 3
    fi
    self_wt=$(cd "$self_wt" 2>/dev/null && pwd -P) || self_wt=""
    [ -n "$self_wt" ] || {
      warn "could not normalize the caller's own worktree — refusing (fail closed)"
      exit 3
    }

    # Target already gone: a clean no-op.
    if [ ! -e "$path" ]; then
      exit 0
    fi
    target_wt=$(cd "$path" 2>/dev/null && pwd -P) || {
      warn "target worktree path '$path' is not a traversable directory — refusing"
      exit 5
    }

    # Self-targeting guard: the target is the caller's own worktree, or an
    # ancestor of it (removing it would pull the ground out from under us).
    if [ "$target_wt" = "$self_wt" ]; then
      warn "REFUSING self-target: '$path' is the caller's own worktree"
      audit worktree-cleanup refuse-self "$trigger" "$reasoning" \
        || warn "could not record the self-block in the audit trail"
      exit 3
    fi
    case "$self_wt/" in
      "$target_wt"/*)
        warn "REFUSING self-target: '$path' contains the caller's own worktree"
        audit worktree-cleanup refuse-self "$trigger" "$reasoning" \
          || warn "could not record the self-block in the audit trail"
        exit 3
        ;;
    esac

    # Positive evidence the worktree is reclaimable: a git worktree whose root
    # is exactly this path, clean (no uncommitted changes), and carrying commits
    # that provably survive its removal — either evidence path in the block
    # below. Any missing piece is refused — reclaiming would lose work.
    top=$(git -C "$path" rev-parse --show-toplevel 2>/dev/null) || top=""
    if [ -z "$top" ]; then
      warn "'$path' is not a git worktree — refusing to remove an unknown directory"
      exit 5
    fi
    top=$(cd "$top" 2>/dev/null && pwd -P) || top=""
    if [ "$top" != "$target_wt" ]; then
      warn "'$path' is not a worktree root (its toplevel is '$top') — refusing"
      exit 5
    fi
    if [ -n "$(git -C "$path" status --porcelain 2>/dev/null)" ]; then
      warn "'$path' has uncommitted changes — refusing to remove (would lose work)"
      exit 5
    fi
    # TWO INDEPENDENT SUFFICIENT EVIDENCE PATHS. Either proves the worktree's
    # commits survive its removal; the clean check above is required for both.
    #
    #   A. UPSTREAM PARITY — a configured upstream with zero commits ahead.
    #
    #   B. MERGED-PR IDENTITY — the caller names a PR and this script VERIFIES
    #      (never trusts) that it is MERGED and that its head oid is exactly this
    #      worktree's HEAD. This is the post-merge shape a forge's branch
    #      auto-delete leaves behind: the remote branch is gone, so the upstream
    #      is unset and path A can NEVER be satisfied, yet the content is
    #      provably merged. Without B the commonest reclaimable worktree of all —
    #      "its PR merged" — is unreclaimable, which is what stalls a fleet on
    #      the deterministic `task-<id>` worktree suffixes.
    #
    # B is a WIDER EVIDENCE CLASS, not a looser bar: an oid match against a
    # MERGED pr is strictly stronger than upstream parity (which only proves the
    # commits left this machine, not that anyone took them). Any doubt — no `gh`,
    # no `timeout` to bound the query, a query that outruns that bound, an
    # unreadable field, a non-MERGED state, an oid mismatch — refuses.
    evidence=""
    upstream=$(git -C "$path" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null) || upstream=""
    if [ -n "$upstream" ]; then
      ahead=$(git -C "$path" rev-list --count '@{upstream}..HEAD' 2>/dev/null) || ahead=""
      case $ahead in
        "" | *[!0-9]*)
          warn "'$path' unpushed-commit count is unreadable — refusing (fail closed)"
          exit 5
          ;;
      esac
      if [ "$ahead" = 0 ]; then
        evidence='upstream-parity'
      elif [ -z "$merged_pr" ]; then
        warn "'$path' has $ahead unpushed commit(s) — refusing to remove (would lose work)"
        exit 5
      fi
    fi

    if [ -z "$evidence" ] && [ -n "$merged_pr" ]; then
      if ! command -v gh >/dev/null 2>&1; then
        warn "--merged-pr given but no gh binary on PATH — cannot verify the merge, refusing (fail closed)"
        exit 5
      fi
      # The query below is the ONLY network call in this actuator, and so the
      # only step that can hang without bound: a stalled forge, a wedged DNS
      # lookup, or a credential helper waiting on input would otherwise pin a
      # cleanup sweep open indefinitely. `timeout` is this tree's established
      # bound (fleet-liveness.sh, fleet-attention-watch.sh, release-arm.sh), but
      # it is GNU coreutils and is NOT on stock macOS, which this script's
      # support bar includes — so its ABSENCE must refuse rather than silently
      # fall back to running unbounded. An unbounded network call in the decision
      # path of a destructive actuator is exactly what "fail closed on any doubt"
      # forbids; reclaiming a worktree is a capability, whereas not wedging the
      # sweep that reclaims it is a safety property, and the capability yields.
      #
      # release-arm.sh's poll budget is NOT the model here: it bounds how many
      # times a query is retried, not how long one call may hang, so a single
      # wedged `gh` still hangs it. fleet-liveness.sh's oracle_fetch does bound a
      # single call portably, but with ~70 lines of supervisor/pid/TERM-KILL
      # choreography; putting that inside this decision path would add more
      # failure surface than the bound removes.
      if ! command -v timeout >/dev/null 2>&1; then
        warn "--merged-pr given but no timeout binary on PATH — refusing rather than making an unbounded network call (fail closed)"
        exit 5
      fi
      head_oid=$(git -C "$path" rev-parse HEAD 2>/dev/null) || head_oid=""
      case $head_oid in
        "" | *[!0-9a-f]*)
          warn "'$path' HEAD oid is unreadable — refusing (fail closed)"
          exit 5
          ;;
      esac
      # Read state and head oid in ONE query, as a space-separated pair, using
      # gh's built-in Go template (never the jq binary — REQ-K1.5). The response
      # is DATA: parsed by prefix/suffix expansion and re-validated below.
      gh_t=$(gh_timeout)
      pr_rc=0
      pr_pair=$(cd "$path" 2>/dev/null && timeout "$gh_t" gh pr view "$merged_pr" \
        --json state,headRefOid \
        --template '{{.state}} {{.headRefOid}}' 2>/dev/null) || pr_rc=$?
      [ "$pr_rc" = 0 ] || pr_pair=""
      # 124 is timeout's own "the command did not finish" status. Distinguishing
      # it matters operationally: a stalled forge should read as a stall an
      # operator can act on, not as an unreadable answer that looks like a
      # malformed reply. Either way it refuses — this only sharpens the message.
      if [ "$pr_rc" = 124 ]; then
        warn "--merged-pr $merged_pr: the gh query did not finish within ${gh_t}s — refusing (fail closed)"
        exit 5
      fi
      pr_state=${pr_pair%% *}
      pr_oid=${pr_pair##* }
      # EXACTLY the two fields the template asks for, joined by exactly one
      # space. Reconstructing the pair and requiring it to equal the reply is
      # what makes this shape check exact: prefix/suffix expansion alone reads
      # only the FIRST and LAST word, so a reply carrying extra tokens between
      # them (`MERGED <junk> <oid>`) would otherwise hand back a usable state and
      # a usable oid while silently discarding the middle — the one malformed
      # shape that fails OPEN instead of closed. The reconstruction also subsumes
      # the no-separator case: state and oid both collapse to the whole reply,
      # which cannot then reconstruct to it.
      if [ -z "$pr_pair" ] || [ "$pr_state $pr_oid" != "$pr_pair" ]; then
        warn "--merged-pr $merged_pr: could not read the PR's state and head oid — refusing (fail closed)"
        exit 5
      fi
      case $pr_oid in
        "" | *[!0-9a-f]*)
          warn "--merged-pr $merged_pr: head oid is not a plain hex oid — refusing (fail closed)"
          exit 5
          ;;
      esac
      if [ "$pr_state" != MERGED ]; then
        warn "--merged-pr $merged_pr is $pr_state, not MERGED — refusing (its commits may exist nowhere else)"
        exit 5
      fi
      if [ "$pr_oid" != "$head_oid" ]; then
        warn "--merged-pr $merged_pr merged $pr_oid but '$path' is at $head_oid — refusing (this worktree holds commits that PR did not carry)"
        exit 5
      fi
      evidence='merged-pr'
    fi

    if [ -z "$evidence" ]; then
      warn "'$path' has no upstream configured and no verified --merged-pr evidence — cannot prove it is pushed, refusing"
      exit 5
    fi

    # Reclaim, running the removal from the caller's own worktree (a sibling in
    # the same repo), never from inside the target.
    if ! git -C "$self_wt" worktree remove "$path" 2>/dev/null; then
      warn "git worktree remove '$path' failed — not reclaimed"
      exit 5
    fi
    if ! audit worktree-cleanup cleanup "$trigger" "$reasoning"; then
      warn "removed worktree '$path' but FAILED to record it in the audit trail"
      exit 6
    fi
    exit 0
    ;;

  process)
    if [ "$#" -lt 3 ]; then
      usage
      exit 2
    fi
    worker=$1
    trigger=$2
    reasoning=$3
    shift 3
    grace=""
    repo_root=""
    tower_id=""
    while [ "$#" -gt 0 ]; do
      [ "$#" -ge 2 ] || {
        usage
        exit 2
      }
      case $1 in
        --grace | --repo-root | --tower-id) ;;
        *)
          usage
          exit 2
          ;;
      esac
      # An empty value would read as the flag left out, which for
      # --tower-id means falling back to whatever identity the environment
      # carries.
      if [ -z "$2" ]; then
        warn "refusing an empty value for $1"
        exit 2
      fi
      case $1 in
        --grace) grace=$2 ;;
        --repo-root) repo_root=$2 ;;
        --tower-id) tower_id=$2 ;;
      esac
      shift 2
    done
    if ! valid_worker "$worker"; then
      warn "refusing malformed worker handle"
      exit 2
    fi
    case $worker in
      pwfence.*)
        warn "refusing '$worker': the pwfence. namespace holds the strand entries surfaced to the operator, and a close would clear the one keyed by this handle"
        exit 2
        ;;
    esac
    if ! valid_text "$trigger" || ! valid_text "$reasoning"; then
      warn "refusing an audit field with a control byte, an embedded tab/newline, or over-length text"
      exit 2
    fi
    # Shape only: the bound belongs to the rung's stop, which refuses past it.
    case $grace in
      "") ;;
      0* | *[!0-9]*)
        warn "refusing a --grace that is not a positive whole number of seconds"
        exit 2
        ;;
    esac
    if [ "${#grace}" -gt 4 ]; then
      warn "refusing an over-length --grace"
      exit 2
    fi
    case $repo_root in
      "" | /*) ;;
      *)
        warn "refusing a non-absolute --repo-root"
        exit 2
        ;;
    esac
    if [ "$repo_root" != "$(sanitize_printable "$repo_root")" ]; then
      warn "refusing a --repo-root with a control byte"
      exit 2
    fi
    if [ -n "$tower_id" ] && ! valid_owner "$tower_id"; then
      warn "refusing a malformed --tower-id"
      exit 2
    fi

    gate process-cleanup || exit 4

    # The detector's answer is read whole before anything is decided from it:
    # a non-zero exit is an errored verdict, and an errored verdict is not
    # evidence of anything.
    verdict=$(/bin/sh "$script_dir/fleet-stuck-detector.sh" classify "$worker" \
      ${tower_id:+--tower-id "$tower_id"}) || {
      warn "the liveness verdict for '$worker' errored — no positive evidence either way, refusing"
      exit 5
    }
    row=$(read_verdict "$verdict" "$worker")
    if [ -z "$row" ]; then
      warn "no liveness verdict for '$worker' — no positive evidence either way, refusing"
      exit 5
    fi
    IFS=$TAB read -r state owner_class reason registry backend owner_token owner_ev rec_dir <<EOF
$row
EOF
    reason=$(sanitize_printable "$reason" "-")
    valid_owner "$owner_token" || owner_token=-

    if [ "$registry" != present ]; then
      warn "no dispatch record for '$worker' (registry: $(sanitize_printable "$registry" "-")) — nothing says what it is or who owns it, refusing"
      exit 5
    fi
    if [ "$backend" = print ]; then
      warn "refusing '$worker': a print-backend unit spawned no process, so there is nothing to reap (it stays registered)"
      exit 8
    fi
    if [ "$owner_class" = live-peer ]; then
      warn "refusing '$worker': it is owned by live peer tower $owner_token, and a live peer's worker is never terminated from here"
      exit 7
    fi
    case $backend in
      stream-json-persistent) rung=fleet-streamjson.sh ;;
      headless-oneshot) rung=fleet-dispatch-headless.sh ;;
      *)
        warn "refusing '$worker': backend '$(sanitize_printable "$backend" "-")' has no process close (a tmux worker's window is reclaimed with 'window')"
        exit 5
        ;;
    esac
    # The headless rung resolves a handle to the unit in whichever checkout
    # its repo root names, and a unit in another checkout can share the
    # handle, so the close is bound to the directory the verdict was read from.
    if [ "$rung" = fleet-dispatch-headless.sh ]; then
      case $rec_dir in
        /*) ;;
        *)
          warn "refusing '$worker': its dispatch record names no state directory to bind the close to"
          exit 5
          ;;
      esac
    fi
    case $owner_ev/$owner_class in
      dead/dead-or-unknown) tower_ev=dead ;;
      self/this-tower)
        warn "refusing '$worker': it is this tower's own worker, whose owner is alive by definition — close it with the rung's stop, which needs no death evidence"
        exit 5
        ;;
      *)
        warn "refusing '$worker': no positive evidence its owning tower is gone (owner: $(sanitize_printable "$owner_class" "-"), evidence: $(sanitize_printable "$owner_ev" "-")) — unknown is treated as alive"
        exit 5
        ;;
    esac
    # A completion value the detector could not parse reads `unknown`, yet
    # still counts as a completion there; for a reap, unknown is alive.
    case $state/$reason in
      unclassified/completion-failed:*=unknown*) session_ended=0 ;;
      dead/* | finished-but-unreaped/* | unclassified/completion-failed:* | unclassified/completion-unlanded) session_ended=1 ;;
      *) session_ended=0 ;;
    esac
    if [ "$session_ended" = 0 ]; then
      warn "refusing '$worker': no positive evidence its session ended (state: $(sanitize_printable "$state" "-"), signal: $reason)"
      exit 5
    fi

    # The gate admits entry, not the whole run: reading the verdict can take
    # a while, and a pause set meanwhile still stops the first signal.
    gate process-cleanup || exit 4

    set --
    if [ "$rung" = fleet-dispatch-headless.sh ]; then
      set -- --expect-dir "$rec_dir"
      [ -z "$repo_root" ] || set -- "$@" --repo-root "$repo_root"
    fi
    [ -z "$grace" ] || set -- "$@" --grace "$grace"
    stop_rc=0
    result=$(/bin/sh "$script_dir/$rung" stop "$worker" "$@") || stop_rc=$?
    [ -z "$result" ] || printf '%s\n' "$result"

    detail="worker=$worker owner=$owner_token evidence=tower:$tower_ev,session:$state/$reason"
    held=""
    case $stop_rc in
      0)
        case $result in
          "stop $worker already-closed") exit 0 ;;
          "stop $worker stopped released="*)
            released=${result#"stop $worker stopped released="}
            action=cleanup
            ;;
          *)
            # A stop that succeeded may still have signalled something, so it
            # is recorded rather than read as nothing having happened.
            warn "the $rung stop for '$worker' succeeded with a result this script does not recognise — recording it as a reap of unknown extent"
            released=unreported
            action=cleanup
            ;;
        esac
        ;;
      6)
        # Recorded even when nothing came free: the rung may have signalled
        # the tree before finding a class still held.
        case $result in
          "stop $worker partial released="*" held="*)
            held=${result##* held=}
            released=${result#*" released="}
            released=${released%%" held="*}
            ;;
          *)
            released=unreported
            held=unreported
            ;;
        esac
        warn "'$worker' was only partly closed — still held: $(sanitize_printable "$held" "-")"
        action=cleanup-partial
        ;;
      3)
        warn "REFUSING self-target: the caller runs inside the worker's own process tree ('$worker')"
        audit process-cleanup refuse-self "$trigger" "$(fit_text "$detail; $reasoning")" \
          || warn "could not record the self-block in the audit trail"
        exit 3
        ;;
      *)
        # Past 128 the rung died on a signal, possibly mid-release: what it
        # had already signalled is unknown, so it is recorded as such. At or
        # below 128 it refused before acting.
        if [ "$stop_rc" -le 128 ]; then
          warn "the $rung stop for '$worker' did not complete (exit $stop_rc) — not reclaimed"
          exit 5
        fi
        warn "the $rung stop for '$worker' died (exit $stop_rc) — what it released is unknown, recording it as a partial close"
        released=unreported
        held=unreported
        action=cleanup-partial
        ;;
    esac

    record="$detail released=$(sanitize_printable "$released" "-")"
    [ -z "$held" ] || record="$record held=$(sanitize_printable "$held" "-")"
    record=$(fit_text "$record; $reasoning")
    if ! audit process-cleanup "$action" "$trigger" "$record"; then
      if [ "$action" = cleanup ]; then
        warn "closed '$worker' but FAILED to record it in the audit trail"
      else
        warn "could not record the partial close of '$worker' in the audit trail — what it released is unrecorded"
      fi
      exit 6
    fi
    [ "$action" = cleanup ] || exit 5
    exit 0
    ;;
esac
