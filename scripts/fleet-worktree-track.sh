#!/bin/sh
# fleet-worktree-track.sh — worktree lifecycle tracking (Task 4: D-7; REQ-B1.2).
#
# PUSH-FIRST, RECONCILE-BACKED (the D-1 pattern applied to worktrees). A live
# registry of tracked working trees is PUSHED the instant a worktree is created
# or removed, via the `WorktreeCreate`/`WorktreeRemove` hook events, so tracking
# never waits on a poll. On a backend that cannot register the hook pair, the
# same registry is reconciled from ground truth by a periodic `git worktree list`
# DISK SCAN (`scan`) — the graceful-degradation fallback D-7 requires, and the
# self-healing floor under a missed hook fire either way.
#
# THE VERIFIED `WorktreeCreate` CONTRACT (code.claude.com/docs/en/hooks.md).
# `WorktreeCreate` is a DECISION hook: "any non-zero exit code causes worktree
# creation to fail", and the command hook is expected to print the worktree path
# on stdout ("hook failure or missing path fails creation"). So `hook-create` is
# a STRICT PASS-THROUGH: it echoes the stdin `worktree_path` unchanged and ALWAYS
# exits 0, doing the registry write as a fully isolated best-effort side effect
# whose failure can change neither stdout nor the exit code (degrade capability,
# never safety — a tracking hiccup must never break worktree creation fleet-wide).
# `WorktreeRemove` is fire-and-forget (failures logged in debug only).
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

HOLD_LOCK=0
trap 'release_lock' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
acquire_lock() {
  al_tries=0
  while [ "$al_tries" -lt 1000 ]; do
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

# write_registry <content-file> — atomically replace the registry with the
# lines in <content-file>, under the lock (copy-modify-rename discipline).
write_registry() {
  wr_src=$1
  mkdir -p "$REG_DIR" 2>/dev/null || {
    warn "cannot create the worktree registry dir $REG_DIR"
    return 2
  }
  acquire_lock || {
    warn "cannot acquire the fleet lock"
    return 2
  }
  wr_tmp=$(mktemp "$REG_DIR/.registry.XXXXXX") || {
    release_lock
    warn "cannot create a temp file under $REG_DIR"
    return 2
  }
  wr_rc=0
  cat "$wr_src" >"$wr_tmp" 2>/dev/null || wr_rc=2
  if [ "$wr_rc" = 0 ]; then
    mv -f "$wr_tmp" "$REG" || wr_rc=2
  fi
  [ "$wr_rc" = 0 ] || rm -f "$wr_tmp" 2>/dev/null
  release_lock
  return "$wr_rc"
}

# read_registry_into <dest-file> — copy the current registry (if any) into a
# scratch file, one path per line, empty when absent.
read_registry_into() {
  : >"$1"
  [ -f "$REG" ] && cat "$REG" >"$1" 2>/dev/null
  return 0
}

do_record() {
  dr_mode=$1 # add | remove
  dr_path=$2
  if ! valid_path "$dr_path"; then
    warn "refusing a malformed worktree path (absolute, no control bytes)"
    return 2
  fi
  reg_paths || {
    warn "unresolvable fleet home"
    return 2
  }
  mkdir -p "$REG_DIR" 2>/dev/null || {
    warn "cannot create the worktree registry dir $REG_DIR"
    return 2
  }
  dr_cur=$(mktemp "$REG_DIR/.reg-cur.XXXXXX") || return 2
  dr_new=$(mktemp "$REG_DIR/.reg-new.XXXXXX") || {
    rm -f "$dr_cur"
    return 2
  }
  read_registry_into "$dr_cur"
  # Filter the target path out of the current set (idempotent for both modes),
  # keeping every other line intact; then, for add, append it once.
  dr_present=0
  : >"$dr_new"
  while IFS= read -r dr_line || [ -n "$dr_line" ]; do
    [ -n "$dr_line" ] || continue
    if [ "$dr_line" = "$dr_path" ]; then
      dr_present=1
      continue
    fi
    printf '%s\n' "$dr_line" >>"$dr_new"
  done <"$dr_cur"
  if [ "$dr_mode" = add ]; then
    printf '%s\n' "$dr_path" >>"$dr_new"
  fi
  rm -f "$dr_cur"
  # A remove of an absent path, or an add of a present path, is already the
  # desired state — still rewrite (idempotent, cheap) so the file exists.
  : "$dr_present"
  if ! write_registry "$dr_new"; then
    rm -f "$dr_new"
    return 2
  fi
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
  printf '%s' "$ewp_in" \
    | sed -n 's/.*"worktree_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
    | head -1
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
    sc_new=$(mktemp "$REG_DIR/.reg-scan.XXXXXX") || exit 2
    : >"$sc_new"
    # Prune: keep every currently-tracked path that STILL EXISTS on disk (a
    # vanished dir is a missed removal — dropping it is the disk-scan reconcile);
    # normalize kept paths through realpath so they dedup against scan output.
    if [ -f "$REG" ]; then
      while IFS= read -r ln || [ -n "$ln" ]; do
        [ -n "$ln" ] || continue
        [ -e "$ln" ] || continue
        ln_real=$(cd "$ln" 2>/dev/null && pwd -P) || ln_real=""
        [ -n "$ln_real" ] || continue
        printf '%s\n' "$ln_real" >>"$sc_new"
      done <"$REG"
    fi
    # Add: every worktree git reports for the scanned repo (realpath-normalized).
    git -C "$scan_root" worktree list --porcelain 2>/dev/null \
      | while IFS= read -r ln; do
        case $ln in
          "worktree "*)
            sc_p=${ln#worktree }
            sc_real=$(cd "$sc_p" 2>/dev/null && pwd -P) || sc_real=""
            [ -n "$sc_real" ] && printf '%s\n' "$sc_real"
            ;;
        esac
      done >>"$sc_new"
    # Dedup (stable) and write once under the lock.
    sc_uniq=$(mktemp "$REG_DIR/.reg-uniq.XXXXXX") || {
      rm -f "$sc_new"
      exit 2
    }
    awk '!seen[$0]++' "$sc_new" >"$sc_uniq" 2>/dev/null || {
      rm -f "$sc_new" "$sc_uniq"
      exit 2
    }
    rm -f "$sc_new"
    if ! write_registry "$sc_uniq"; then
      rm -f "$sc_uniq"
      exit 2
    fi
    rm -f "$sc_uniq"
    exit 0
    ;;
  hook-create)
    # DECISION-CONTROL SAFE (the verified WorktreeCreate contract): ALWAYS echo
    # the stdin worktree_path FIRST — that is the decision-control response the
    # harness reads, so it is emitted before any work that could stall — then
    # record best-effort in a fully isolated subshell, and ALWAYS exit 0. A slow
    # or failed record must never delay or fail worktree creation; a dropped
    # record self-heals on the next sweep's disk-scan reconcile (`scan`).
    hc_in=$(cat 2>/dev/null) || hc_in=""
    hc_path=$(extract_worktree_path "$hc_in")
    if [ -n "$hc_path" ]; then
      printf '%s\n' "$hc_path"
      (do_record add "$hc_path" >/dev/null 2>&1) || true
    else
      warn "WorktreeCreate payload carried no worktree_path — echoing nothing"
    fi
    exit 0
    ;;
  hook-remove)
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
