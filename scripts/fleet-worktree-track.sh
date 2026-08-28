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
# THE VERIFIED `WorktreeCreate` CONTRACT (operator-verified across CLI
# 2.1.226–2.1.234; corrects the earlier worktree_path back-fill, see
# obs:2036d463 / obs:16facd5b). `WorktreeCreate` input on stdin is
# `{hook_event_name, name}` — it never carries `worktree_path` (that shape is
# WorktreeRemove-only) — and a REGISTERED hook REPLACES native creation: the
# CLI's contract is that the hook IS the creator and "provides the absolute
# path to the created worktree" as its stdout result ("hook failure or missing
# path fails creation"; any non-zero exit also fails it). So `hook-create`
# reads `.name`, grammar-checks it, CREATES `<repo>/.claude/worktrees/<name>`
# on a fresh `worktree-<flattened-name>` branch (based on `origin/HEAD` where
# resolvable, else the current `HEAD` — the native `fresh` baseRef shape), and
# echoes the created path. Every refusal — a malformed or absent name, no git
# repo at the cwd, a branch or directory collision, a failed `git worktree
# add` — echoes NOTHING (creation fails closed, visibly, never under a forged
# name) and STILL exits 0. The registry write is a synchronous best-effort
# side effect with a SHORT bounded lock wait (LOCK_MAX_TRIES=100 × the 0.02s
# retry sleep => ~2s worst case), so a contended lock can never stall
# creation beyond that bound and never fail it; a skipped write self-heals on
# the next `scan`. `WorktreeRemove` keeps its genuinely different
# `worktree_path` input shape and is fire-and-forget (failures logged in
# debug only).
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

# extract_name <json> — pull `.name` from a WorktreeCreate hook payload via jq
# where present, else a bounded sed. jq is AUTHORITATIVE where present: an
# absent, null, or empty top-level `.name` (or unparseable JSON) is a refusal,
# never a downgrade to the sed capture — sed's unanchored match would promote
# a NESTED "name" key from anywhere in the payload. The sed fallback serves
# only a jq-less host (the documented degrade). A valid worktree name carries
# no backslash (the grammar below), so a backslash in the sed capture is an
# escape the sed path cannot decode — refuse it (emit nothing) rather than
# hand back a mis-parsed name, mirroring extract_worktree_path's fail-closed
# posture.
extract_name() {
  en_in=$1
  if command -v jq >/dev/null 2>&1; then
    en_v=$(printf '%s' "$en_in" | jq -r '.name // empty' 2>/dev/null) || en_v=""
    printf '%s' "$en_v"
    return 0
  fi
  en_sed=$(printf '%s' "$en_in" \
    | sed -n 's/.*"name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
    | head -1)
  case $en_sed in
    *\\*) return 0 ;;
  esac
  printf '%s' "$en_sed"
}

# valid_name <name> — the worktree-name grammar (the EnterWorktree shape):
# "/"-separated segments of letters, digits, dots, underscores, and dashes,
# max 64 chars total. Additionally refused: an empty or dot-only segment (so
# `..` traversal and hidden-relative segments cannot form), a leading dash on
# any segment (option injection), and any control byte. The name is DATA —
# checked by case-glob, never evaluated — and with `..` and absolute forms
# refused, `<root>/.claude/worktrees/<name>` is contained by construction.
valid_name() {
  vn=$1
  [ -n "$vn" ] || return 1
  [ "${#vn}" -le 64 ] || return 1
  [ "$vn" = "$(sanitize_printable "$vn")" ] || return 1
  case $vn in
    /* | */ | *//*) return 1 ;;
  esac
  old_ifs=$IFS
  IFS=/
  for vn_seg in $vn; do
    case $vn_seg in
      "" | -* | . | .. | *[!A-Za-z0-9._-]*)
        IFS=$old_ifs
        return 1
        ;;
    esac
  done
  IFS=$old_ifs
  return 0
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
      # Enforce the emitted-path grammar the header/contract promises callers
      # (fleet-sweep.sh inspects/escalates these paths): a malformed line — a
      # corrupted store, or a `scan` write that bypassed the grammar — is skipped
      # with a sanitized warning rather than handed to a caller that would `cd`
      # into it relative to its own cwd. A valid_path line is already printable,
      # so it is emitted verbatim (identical to the prior sanitize_printable
      # output for every well-formed entry).
      if valid_path "$ln"; then
        printf '%s\n' "$ln"
      else
        warn "skipping a malformed worktree registry entry (fails the path grammar): $(sanitize_printable "$ln")"
      fi
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
    # THE CREATOR (the verified WorktreeCreate contract in the header): a
    # registered WorktreeCreate hook replaces native creation, so this arm
    # reads `.name`, creates `<repo>/.claude/worktrees/<name>` on a fresh
    # `worktree-<flattened-name>` branch, and echoes the created path — the
    # decision-control response the harness reads. Every refusal echoes
    # NOTHING and exits 0 (a missing stdout path fails creation visibly; a
    # non-zero exit would too, but with a scarier harness error). The registry
    # record is a best-effort side effect that never changes stdout or the
    # exit; a skipped record self-heals on the next sweep's `scan`.
    LOCK_MAX_TRIES=100
    hc_in=$(cat 2>/dev/null) || hc_in=""
    hc_name=$(extract_name "$hc_in")
    if [ -z "$hc_name" ]; then
      warn "WorktreeCreate payload carried no name — echoing nothing"
      exit 0
    fi
    if ! valid_name "$hc_name"; then
      warn "WorktreeCreate name failed the grammar (segments of [A-Za-z0-9._-], no dot-only or dash-led segment, max 64 chars) — echoing nothing"
      exit 0
    fi
    if ! command -v git >/dev/null 2>&1; then
      warn "no git binary on PATH — cannot create a worktree; echoing nothing"
      exit 0
    fi
    hc_root=$(git rev-parse --show-toplevel 2>/dev/null) || hc_root=""
    if [ -z "$hc_root" ] || ! valid_path "$hc_root"; then
      warn "WorktreeCreate outside a git repository (or an unusable repo root) — echoing nothing"
      exit 0
    fi
    hc_target="$hc_root/.claude/worktrees/$hc_name"
    # Idempotent reattach: a target already registered as a worktree of this
    # repo is echoed (and re-recorded), never re-created — after the SAME
    # physical-path containment check the create path applies, so a stale or
    # symlinked-out entry never reaches the decision channel.
    if git -C "$hc_root" worktree list --porcelain 2>/dev/null \
      | grep -Fxq "worktree $hc_target"; then
      if [ ! -d "$hc_target" ]; then
        # A stale (prunable) admin entry: the directory is gone. Echoing the
        # dead path would report success on a nonexistent tree — prune the
        # entry and fall through to a fresh create instead (which may still
        # refuse on the leftover branch; a legible refusal beats a phantom
        # success).
        git -C "$hc_root" worktree prune >/dev/null 2>&1 || true
      else
        hc_real=$(cd "$hc_target" 2>/dev/null && pwd -P) || hc_real=""
        hc_root_real=$(cd "$hc_root" 2>/dev/null && pwd -P) || hc_root_real=""
        case $hc_real in
          "$hc_root_real"/.claude/worktrees/*) ;;
          *)
            warn "registered worktree at $hc_target resolves outside the worktrees root — echoing nothing"
            exit 0
            ;;
        esac
        printf '%s\n' "$hc_real"
        (do_record add "$hc_real" >/dev/null 2>&1) || true
        exit 0
      fi
    fi
    if [ -e "$hc_target" ]; then
      warn "WorktreeCreate target already exists and is not a worktree of this repo — echoing nothing"
      exit 0
    fi
    # Symlink screen BEFORE any filesystem write: `mkdir -p`, `git worktree
    # add`, and the failure-path `rm -rf` all FOLLOW symlink components, and a
    # DANGLING leaf symlink is invisible to the `-e` check above. A symlinked
    # `.claude`, worktrees root, or leaf is a refusal, never a traversal (the
    # sibling dispatch primitive's discipline).
    if [ -L "$hc_root/.claude" ] || [ -L "$hc_root/.claude/worktrees" ] || [ -L "$hc_target" ]; then
      warn "WorktreeCreate refuses a symlinked .claude, worktrees root, or target — echoing nothing"
      exit 0
    fi
    # Branch: worktree-<name> with "/" flattened to "-" (the native single-
    # segment shape, extended). A pre-existing branch is a refusal, not a
    # reuse: silently attaching to an unknown branch's history is the forged-
    # name risk in a different coat.
    hc_branch="worktree-$(printf '%s' "$hc_name" | tr '/' '-')"
    if git -C "$hc_root" show-ref --verify --quiet "refs/heads/$hc_branch"; then
      warn "WorktreeCreate branch $hc_branch already exists — echoing nothing (remove or rename the branch, or pick another worktree name)"
      exit 0
    fi
    # Base: origin/HEAD where resolvable (the native `fresh` baseRef shape),
    # else the current HEAD. Resolvable means resolvable to a COMMIT:
    # `symbolic-ref --quiet` still succeeds on a DANGLING symref (a renamed or
    # pruned remote default branch), which without the verify gate would turn
    # every creation into a refusal instead of the documented HEAD fallback.
    hc_base=$(git -C "$hc_root" symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null) || hc_base=""
    if [ -n "$hc_base" ] \
      && ! git -C "$hc_root" rev-parse --verify --quiet "$hc_base^{commit}" >/dev/null 2>&1; then
      hc_base=""
    fi
    [ -n "$hc_base" ] || hc_base=HEAD
    mkdir -p "$hc_root/.claude/worktrees" 2>/dev/null || {
      warn "cannot create $hc_root/.claude/worktrees — echoing nothing"
      exit 0
    }
    if ! git -C "$hc_root" worktree add -b "$hc_branch" "$hc_target" "$hc_base" >/dev/null 2>&1; then
      warn "git worktree add failed for $hc_target (branch $hc_branch, base $hc_base) — echoing nothing"
      # Race guard: a concurrent create for the same name may have WON between
      # the pre-checks and this add (`add -b`'s atomic non-zero exit is the
      # real collision detector). If git now lists the target, the tree and
      # the branch are the winner's — touch nothing.
      if git -C "$hc_root" worktree list --porcelain 2>/dev/null \
        | grep -Fxq "worktree $hc_target"; then
        exit 0
      fi
      rm -rf "$hc_target" 2>/dev/null || true
      # `add -b` creates the branch before the checkout, so a partway failure
      # can leave `refs/heads/$hc_branch` behind — which the collision check
      # above would then refuse FOREVER for this name. The branch's absence was
      # pre-checked this invocation, so deleting it here removes only what this
      # failed create made; prune drops any half-registered admin entry.
      git -C "$hc_root" branch -D "$hc_branch" >/dev/null 2>&1 || true
      git -C "$hc_root" worktree prune >/dev/null 2>&1 || true
      exit 0
    fi
    # Containment re-check on the CREATED path: worktree add follows symlinks,
    # so verify the physical path still sits under the repo root before it is
    # echoed on the decision channel; a breakout is undone, not tracked.
    hc_real=$(cd "$hc_target" 2>/dev/null && pwd -P) || hc_real=""
    hc_root_real=$(cd "$hc_root" 2>/dev/null && pwd -P) || hc_root_real=""
    case $hc_real in
      "$hc_root_real"/.claude/worktrees/*) ;;
      *)
        warn "created worktree resolved outside $hc_root_real/.claude/worktrees — removing it and echoing nothing"
        git -C "$hc_root" worktree remove --force "$hc_target" >/dev/null 2>&1 \
          || rm -rf "$hc_target" 2>/dev/null || true
        # Same leftover-branch discipline as the failed-add arm above.
        git -C "$hc_root" branch -D "$hc_branch" >/dev/null 2>&1 || true
        git -C "$hc_root" worktree prune >/dev/null 2>&1 || true
        exit 0
        ;;
    esac
    printf '%s\n' "$hc_real"
    (do_record add "$hc_real" >/dev/null 2>&1) || true
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
