#!/bin/sh
# fleet-worktree-track.sh — worktree lifecycle tracking (Task 4: D-7; REQ-B1.2).
#
# PUSH-FIRST, RECONCILE-BACKED (the D-1 pattern applied to worktrees). A live
# registry of tracked working trees is PUSHED the instant a worktree is created
# or removed, via the `WorktreeCreate`/`WorktreeRemove` hook events, so tracking
# never waits on a poll. Where a backend cannot register the hook pair, the same
# registry can be reconciled from ground truth by a `git worktree list` DISK SCAN
# (`scan`) — the graceful-degradation fallback D-7 requires. NOTE: in this task
# `scan` ships as a MANUAL CLI; it is not yet wired to run periodically (the
# housekeeping sweep reads the registry via `list`, not `scan`), so the
# self-healing floor is only as current as the last `scan` invocation until that
# wiring lands (a tracked follow-up).
#
# THE VERIFIED `WorktreeCreate` CONTRACT (code.claude.com/docs/en/hooks.md).
# `WorktreeCreate` is a DECISION hook: "any non-zero exit code causes worktree
# creation to fail", and the command hook is expected to print the worktree path
# on stdout ("hook failure or missing path fails creation"). So `hook-create` is
# a STRICT PASS-THROUGH: it echoes the stdin `worktree_path` (after the same
# grammar check every stored path gets — a control-byte path is refused rather
# than echoed raw) and ALWAYS exits 0. The registry write is a synchronous
# best-effort side effect with a SHORT bounded lock wait, so a contended lock can
# never stall creation more than a fraction of a second and never fail it; a
# skipped write self-heals on the next `scan`. `WorktreeRemove` is
# fire-and-forget (failures logged in debug only).
#
# NOT A DAEMON ACTION. Tracking is bookkeeping, not a destructive daemon action:
# it is NOT gated by the `fleet_daemon_pause` kill-switch (which pauses
# cleanup/restart/throttle) and does NOT write the audit trail (kickoff risk 31 —
# the trail records daemon actions, not routine lifecycle noise). The destructive
# reclaim that consumes this registry (fleet-cleanup.sh) is the audited,
# kill-switch-gated action.
#
# STORE. One absolute path per line under the cross-spec fleet home
# (fleet-state.sh root): `<fleet-home>/worktrees/registry`. Writes serialize
# through fleet-state.sh's existing cross-spec advisory lock (the same primitive
# fleet-audit.sh / fleet-attention.sh hold — no second lock, REQ-G1.3) and land
# via copy-modify-RENAME, so a lockless `list` reader always sees a complete file.
# Every stored/emitted path is grammar-checked (absolute, no control bytes) — an
# inbound hook-payload field is data, never interpolated unvalidated (risk 25).
#
# Usage:
#   fleet-worktree-track.sh record-create <path>   push a creation (idempotent)
#   fleet-worktree-track.sh record-remove <path>   push a removal (idempotent)
#   fleet-worktree-track.sh list                   print tracked paths, one/line
#   fleet-worktree-track.sh scan [<repo-root>]     disk-scan reconcile (fallback)
#   fleet-worktree-track.sh hook-create            WorktreeCreate handler (stdin)
#   fleet-worktree-track.sh hook-remove            WorktreeRemove handler (stdin)
#
# Exit codes: 0 success; 2 usage / refused malformed path; 2 also a lock/
#   filesystem error on the direct CLI (fail closed). The hook handlers always
#   exit 0 (they must never break a lifecycle operation).
#
# POSIX sh on the macOS + Linux support bar. All input is data; no eval (REQ-K1.5).
# jq is used for JSON parsing WHERE PRESENT with a bounded sed fallback (the
# tasks-pr-sync.sh hook's degrade pattern). Pathname expansion is disabled.
set -uf

LC_ALL=C
export LC_ALL
unset CDPATH

script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2

# shellcheck source=scripts/echo-safety.sh
. "$script_dir/echo-safety.sh"

FS="$script_dir/fleet-state.sh"

warn() { printf 'fleet-worktree-track: %s\n' "$*" >&2; }

valid_path() {
  vp=$1
  case $vp in
    "" | -*) return 1 ;;
    /*) ;;
    *) return 1 ;;
  esac
  [ "$vp" = "$(sanitize_printable "$vp")" ] || return 1
  [ "${#vp}" -le 4096 ]
}

resolve_home() {
  "$FS" root
}

# The lock-acquire retry budget. The direct CLI uses the full budget (a
# registry write must not be dropped); the hook handlers lower it (LOCK_MAX_TRIES
# below) so a contended lock can never stall a WorktreeCreate/Remove operation —
# a skipped hook record self-heals on the next sweep's `scan`.
LOCK_MAX_TRIES=1000

HOLD_LOCK=0
trap 'release_lock' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
acquire_lock() {
  al_tries=0
  while [ "$al_tries" -lt "$LOCK_MAX_TRIES" ]; do
    "$FS" lock >/dev/null 2>&1
    al_rc=$?
    case $al_rc in
      0)
        HOLD_LOCK=1
        return 0
        ;;
      1) ;;
      *) return 2 ;;
    esac
    al_tries=$((al_tries + 1))
    sleep 0.02
  done
  return 2
}
release_lock() {
  if [ "$HOLD_LOCK" = 1 ]; then
    "$FS" unlock >/dev/null 2>&1 || true
    HOLD_LOCK=0
  fi
}

# reg_dir / reg_file — resolve the registry paths under a resolvable home.
reg_paths() {
  rp_root=$(resolve_home) || return 2
  REG_DIR="$rp_root/worktrees"
  REG="$REG_DIR/registry"
  return 0
}

# rewrite_locked <content-file> — atomically replace the registry with the lines
# in <content-file> via copy-modify-RENAME. THE CALLER MUST ALREADY HOLD THE
# LOCK: the read-compute-write is one critical section (a lockless read + locked
# write would lose a concurrent writer's update — the fleet-audit.sh discipline).
rewrite_locked() {
  rl_src=$1
  rl_tmp=$(mktemp "$REG_DIR/.registry.XXXXXX") || {
    warn "cannot create a temp file under $REG_DIR"
    return 2
  }
  rl_rc=0
  cat "$rl_src" >"$rl_tmp" 2>/dev/null || rl_rc=2
  if [ "$rl_rc" = 0 ]; then
    mv -f "$rl_tmp" "$REG" || rl_rc=2
  fi
  [ "$rl_rc" = 0 ] || rm -f "$rl_tmp" 2>/dev/null
  return "$rl_rc"
}

# normalize_if_exists <path> — realpath a path that exists on disk (so a
# push-recorded create and a scan-discovered entry agree and dedup), else echo
# it unchanged (a remove of an already-gone worktree keeps the raw payload form).
normalize_if_exists() {
  if [ -e "$1" ]; then
    nie=$(cd "$1" 2>/dev/null && pwd -P) && [ -n "$nie" ] && {
      printf '%s' "$nie"
      return 0
    }
  fi
  printf '%s' "$1"
}

do_record() {
  dr_mode=$1 # add | remove
  dr_path=$2
  if ! valid_path "$dr_path"; then
    warn "refusing a malformed worktree path (absolute, no control bytes)"
    return 2
  fi
  dr_path=$(normalize_if_exists "$dr_path")
  reg_paths || {
    warn "unresolvable fleet home"
    return 2
  }
  mkdir -p "$REG_DIR" 2>/dev/null || {
    warn "cannot create the worktree registry dir $REG_DIR"
    return 2
  }
  # Read-modify-write as ONE locked critical section (atomicity, no lost update).
  acquire_lock || {
    warn "cannot acquire the fleet lock"
    return 2
  }
  dr_new=$(mktemp "$REG_DIR/.reg-new.XXXXXX") || {
    release_lock
    return 2
  }
  : >"$dr_new"
  if [ -f "$REG" ]; then
    while IFS= read -r dr_line || [ -n "$dr_line" ]; do
      [ -n "$dr_line" ] || continue
      [ "$dr_line" = "$dr_path" ] && continue
      printf '%s\n' "$dr_line" >>"$dr_new"
    done <"$REG"
  fi
  if [ "$dr_mode" = add ]; then
    printf '%s\n' "$dr_path" >>"$dr_new"
  fi
  if ! rewrite_locked "$dr_new"; then
    release_lock
    rm -f "$dr_new"
    return 2
  fi
  release_lock
  rm -f "$dr_new"
  return 0
}

# extract_worktree_path <json> — pull `.worktree_path` from a hook payload via
# jq where present, else a bounded sed (filesystem paths carry no escaped
# quotes, so the simple capture is safe). Prints the path (empty if none).
extract_worktree_path() {
  ewp_in=$1
  if command -v jq >/dev/null 2>&1; then
    ewp_p=$(printf '%s' "$ewp_in" | jq -r '.worktree_path // empty' 2>/dev/null) || ewp_p=""
    if [ -n "$ewp_p" ]; then
      printf '%s' "$ewp_p"
      return 0
    fi
  fi
  # jq absent: fall back to a bounded sed capture. The `[^"]*` capture cannot
  # JSON-unescape, so a worktree_path VALUE carrying a backslash-escape mis-parses
  # — an embedded `"` arrives as `\"` and truncates the capture; an embedded `\`
  # arrives as `\\` and doubles — yielding a WRONG path that still passes
  # valid_path and would be echoed on the WorktreeCreate decision channel. A
  # backslash in the sed result is exactly that untrustworthy signal (a real
  # fleet worktree path carries none), so refuse it: emit nothing, and the caller
  # fails CLOSED (hook-create echoes nothing => creation refused, never under a
  # mis-parsed name). jq, the primary path, unescapes correctly and is unaffected.
  ewp_sed=$(printf '%s' "$ewp_in" \
    | sed -n 's/.*"worktree_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
    | head -1)
  case $ewp_sed in
    *\\*) return 0 ;;
  esac
  printf '%s' "$ewp_sed"
}

cmd=${1:-}
case "$cmd" in
  record-create)
    [ "$#" -eq 2 ] || {
      warn "usage: record-create <path>"
      exit 2
    }
    do_record add "$2" || exit 2
    exit 0
    ;;
  record-remove)
    [ "$#" -eq 2 ] || {
      warn "usage: record-remove <path>"
      exit 2
    }
    do_record remove "$2" || exit 2
    exit 0
    ;;
  list)
    [ "$#" -eq 1 ] || {
      warn "usage: list"
      exit 2
    }
    reg_paths || {
      warn "unresolvable fleet home"
      exit 2
    }
    [ -f "$REG" ] || exit 0
    while IFS= read -r ln || [ -n "$ln" ]; do
      [ -n "$ln" ] || continue
      printf '%s\n' "$(sanitize_printable "$ln")"
    done <"$REG"
    exit 0
    ;;
  scan)
    [ "$#" -le 2 ] || {
      warn "usage: scan [<repo-root>]"
      exit 2
    }
    scan_root=${2:-$PWD}
    # Screen the operator-supplied root before it reaches git -C: a leading dash
    # would be read as an option; a control byte is never a real repo path.
    case $scan_root in
      -*)
        warn "refusing a malformed scan root (leading dash)"
        exit 2
        ;;
    esac
    if [ "$scan_root" != "$(sanitize_printable "$scan_root")" ]; then
      warn "refusing a scan root with a control byte"
      exit 2
    fi
    if ! command -v git >/dev/null 2>&1; then
      warn "no git binary on PATH — cannot disk-scan; leaving the registry unchanged"
      exit 0
    fi
    reg_paths || {
      warn "unresolvable fleet home"
      exit 2
    }
    mkdir -p "$REG_DIR" 2>/dev/null || {
      warn "cannot create the worktree registry dir $REG_DIR"
      exit 2
    }
    # Gather git's worktree set OUTSIDE the lock (a read-only query), so the
    # locked critical section stays short.
    sc_git=$(mktemp "$REG_DIR/.reg-git.XXXXXX") || exit 2
    git -C "$scan_root" worktree list --porcelain 2>/dev/null \
      | while IFS= read -r ln; do
        case $ln in
          "worktree "*)
            sc_p=${ln#worktree }
            sc_real=$(cd "$sc_p" 2>/dev/null && pwd -P) || sc_real=""
            [ -n "$sc_real" ] && printf '%s\n' "$sc_real"
            ;;
        esac
      done >"$sc_git"
    # Read-prune-merge-write as ONE locked critical section (atomicity vs a
    # concurrent hook record).
    acquire_lock || {
      rm -f "$sc_git"
      warn "cannot acquire the fleet lock"
      exit 2
    }
    sc_new=$(mktemp "$REG_DIR/.reg-scan.XXXXXX") || {
      release_lock
      rm -f "$sc_git"
      exit 2
    }
    : >"$sc_new"
    # Prune: keep every currently-tracked path that STILL EXISTS on disk (a
    # vanished dir is a missed removal — dropping it is the disk-scan reconcile).
    # Normalize a readable path through realpath so it dedups against scan
    # output; keep an existing-but-unreadable path AS-IS rather than dropping it
    # (only a truly-vanished dir is a removal, not a transient permission fault).
    if [ -f "$REG" ]; then
      while IFS= read -r ln || [ -n "$ln" ]; do
        [ -n "$ln" ] || continue
        [ -e "$ln" ] || continue
        ln_real=$(cd "$ln" 2>/dev/null && pwd -P) || ln_real=""
        [ -n "$ln_real" ] || ln_real=$ln
        printf '%s\n' "$ln_real" >>"$sc_new"
      done <"$REG"
    fi
    cat "$sc_git" >>"$sc_new" 2>/dev/null
    rm -f "$sc_git"
    # Dedup (stable) and write once under the lock.
    sc_uniq=$(mktemp "$REG_DIR/.reg-uniq.XXXXXX") || {
      release_lock
      rm -f "$sc_new"
      exit 2
    }
    awk '!seen[$0]++' "$sc_new" >"$sc_uniq" 2>/dev/null || {
      release_lock
      rm -f "$sc_new" "$sc_uniq"
      exit 2
    }
    rm -f "$sc_new"
    if ! rewrite_locked "$sc_uniq"; then
      release_lock
      rm -f "$sc_uniq"
      exit 2
    fi
    release_lock
    rm -f "$sc_uniq"
    exit 0
    ;;
  hook-create)
    # DECISION-CONTROL SAFE (the verified WorktreeCreate contract). The stdin
    # worktree_path is the decision-control response the harness reads, so it is
    # emitted FIRST — but only after passing the same grammar check every stored
    # path gets: a payload path carrying a control byte is refused (nothing
    # echoed, no raw bytes on the decision channel; a malformed path is a
    # pathological input, safer left uncreated than created under a forged name).
    # A well-formed path always passes. The record then runs synchronously with a
    # SHORT bounded lock wait (LOCK_MAX_TRIES), so a contended lock can never
    # stall creation; a skipped record self-heals on the next sweep's `scan`. The
    # record's isolated subshell can neither change stdout nor the exit — this
    # hook ALWAYS exits 0, so it never fails creation via a non-zero exit or a
    # stalled record. A well-formed payload echoes its path and creation proceeds;
    # the ONLY creation-failing path is the deliberate fail-closed one above — a
    # malformed/absent payload echoes nothing, and the contract treats a missing
    # stdout path as a refusal (safer than tracking a worktree under a forged name).
    LOCK_MAX_TRIES=100
    hc_in=$(cat 2>/dev/null) || hc_in=""
    hc_path=$(extract_worktree_path "$hc_in")
    if [ -n "$hc_path" ] && valid_path "$hc_path"; then
      printf '%s\n' "$hc_path"
      (do_record add "$hc_path" >/dev/null 2>&1) || true
    elif [ -n "$hc_path" ]; then
      warn "WorktreeCreate worktree_path failed the path grammar (not absolute, a leading dash, a control byte, or over 4096 chars) — echoing nothing"
    else
      warn "WorktreeCreate payload carried no worktree_path — echoing nothing"
    fi
    exit 0
    ;;
  hook-remove)
    LOCK_MAX_TRIES=100
    hr_in=$(cat 2>/dev/null) || hr_in=""
    hr_path=$(extract_worktree_path "$hr_in")
    if [ -n "$hr_path" ]; then
      (do_record remove "$hr_path" >/dev/null 2>&1) || true
    fi
    exit 0
    ;;
  "")
    warn "usage: record-create|record-remove <path> | list | scan [root] | hook-create | hook-remove"
    exit 2
    ;;
  *)
    warn "unknown command '$(sanitize_printable "$cmd" "(unprintable)")'"
    exit 2
    ;;
esac
