#!/bin/sh
# tasks-pr-sync.sh — the level-triggered, idempotent reconcile that is the
# SOLE writer of tasks.md section placement (orchestration-concurrency Task 4;
# D-1, D-3; REQ-B1.1, REQ-B1.2, REQ-B1.3, REQ-C1.3) AND of the derived bundle
# `**Status:**` header (kickoff-lifecycle Task 6; D-2, D-3; REQ-A1.5, REQ-C1.2).
# It supersedes the prior edge-triggered single-block move: instead of relocating
# one task per PR event, it recomputes the FULL placement of every task block from
# the Task 1 derivation engine (scripts/orchestrate-state.sh) and rewrites tasks.md
# to match, then reconciles the bundle Status header (Ready/Active/Done) from the
# same derivation across the four spec files (see do_status / STATUS_AWK below).
#
# Two entry points share one reconcile:
#   * PostToolUse(Bash) hook — invoked with NO arguments, reads the tool call
#     from stdin. A `gh pr create` / `gh pr merge` on a convention-named branch
#     (planwright/<spec>/task-<ids>, D-36) triggers a reconcile of THAT spec.
#     Any other Bash command, and any non-Bash tool, is a fast silent no-op
#     (the hook fires after every Bash call, so the no-op path stays cheap).
#   * Direct CLI — `tasks-pr-sync.sh reconcile <spec-dir>` reconciles one spec
#     on demand (the path /orchestrate --bookkeeping and tests drive).
#
# Placement model (D-1): progress state is a DERIVED PROJECTION. The committed
# tasks.md sections are a read-model snapshot, never authoritative. Each
# `### Task <id>` block is relocated by its derived state:
#   completed   -> ## Completed
#   in-progress -> ## In progress
#   ready / blocked (or anything else) -> ## Forward plan
# The human-owned sections — `## Awaiting input`, `## Deferred`, `## Out of
# scope` — are STICKY: their bodies are preserved without data loss (REQ-B1.3)
# and their task blocks are never relocated by the derivation (a human parked
# them; the reconcile does not second-guess that). "Without data loss" is not
# byte-for-byte: blank-line whitespace is normalized to the canonical form
# (leading/trailing blank lines trimmed, blank runs collapsed to one) so the
# snapshot stays idempotent (REQ-B1.2); the content lines themselves are kept
# intact. The header block and intro prose (everything before the first `## `
# state section — including a leading non-canonical section such as a top-of-file
# `## Dependency graph`) are preserved the same way, in place. A non-canonical
# `## ` section that appears after the canonical set is preserved too, parked
# after it (see the END loop).
#
# Properties the rework guarantees:
#   * Level-triggered & idempotent (REQ-B1.2): placement is recomputed from
#     current truth, never from the prior section assignment; a second run
#     against unchanged truth is a byte-identical no-op (the write is skipped
#     when the recomputed file equals the current one).
#   * Self-healing rebuild (REQ-B1.2, REQ-B1.3): a scrambled or flattened
#     snapshot reconciles to the same canonical placement; the snapshot is a
#     discardable derivation.
#   * Conflict regeneration (REQ-C1.3): a tasks.md carrying git conflict markers
#     (<<<<<<<, =======, >>>>>>>, |||||||) has them stripped and placement is
#     regenerated from the derivation — never resolved by ours/theirs/union.
#     Dedupe-by-id covers the task blocks the derivation PLACES (the triad
#     sections), so a conflict that duplicated a triad block leaves one copy.
#     Content in the sticky human-owned / unknown sections is preserved as-is and
#     not parsed for task blocks, so a conflict that duplicated a task PARKED in
#     such a section leaves both copies for the human to resolve — the reconcile
#     does not edit human-owned bodies (sticky preservation wins there).
#   * Atomic write (REQ-B1.1): the rewrite goes to a same-directory temp file
#     and is renamed into place, so a racy stale lock-break cannot observe a
#     half-written tasks.md.
#   * Definition invariance (REQ-B1.1): the five task-definition fields move
#     byte-for-byte and the task-level Status / Last activity / Dispatch
#     annotations ride along untouched (those are /execute-task's to write, and
#     are excluded from the content anchor — scripts/spec-anchor.sh — so a
#     placement move never changes the anchor).
#   * Bundle Status reconcile (kickoff-lifecycle Task 6): the bundle `**Status:**`
#     header (distinct from the task-level `- **Status:**` annotations above) is
#     derived and rewritten across the four files by do_status. CAVEAT: that
#     header is NOT yet anchor-excluded (spec-anchor.sh hashes requirements.md /
#     design.md / test-spec.md whole), so a derived Ready->Active flip DOES change
#     the anchor today. This is inert until kickoff-lifecycle Task 3 ships the
#     Draft->Ready producer (no bundle is Ready before then, and a currently-Active
#     bundle with progress derives Active = a no-op). The required follow-up before
#     Task 3 — exclude the bundle Status header from the anchor + a re-anchor
#     migration — is logged in specs/_observations/opportunities.md (2026-06-29).
#
# Worker sessions: the hook fires inside worktrees, so it resolves and writes
# the canonical tasks.md in the PRIMARY checkout (kickoff brief risk row 3),
# under the per-spec advisory lock at specs/<spec>/.orchestrate.lock. That lock
# is acquired and released through the ONE shared primitive,
# scripts/orchestrate-lock.sh (D-4, REQ-D1.1) — no acquire or stale-break logic
# lives here. A busy or unavailable lock is a clean no-op (the hook is
# fail-soft; `/orchestrate --bookkeeping` reconciles the dropped event); the
# direct CLI fails closed on a broken install or a refused (hostile) spec dir.
#
# Input validation before any path use (REQ-F1.1, REQ-K1.2): the parsed
# `<spec>` segment must match the spec-id charset (`^[a-z0-9][a-z0-9-]*$`, max
# 64) and the `<id>` segment the D-36 task-id grammar; the resolved tasks.md
# path is containment-checked under <primary>/specs/ after symlink resolution,
# and the shared lock primitive re-validates and containment-checks the lock
# path (defense in depth). The reserved `planwright/<spec>/spec` namespace
# no-ops (D-44). Any validation failure is a clean no-op (hook) or exit 2 (CLI).
#
# Diagnostics go to stderr; hook no-op cases are silent so PostToolUse noise
# never reaches the transcript on unrelated Bash calls.
#
# Portable POSIX sh + awk + git (bash 3.2 / BSD compatible, no eval; untrusted
# input is treated as data only, REQ-F1.1).
set -u

# Pin the C locale: bracket expressions below must mean exactly their ASCII
# range on every host.
LC_ALL=C
export LC_ALL

# A user CDPATH would make cd echo into command substitutions and corrupt the
# derived paths.
unset CDPATH

log() { printf 'tasks-pr-sync: %s\n' "$*" >&2; }

# The shared advisory-lock primitive and the derivation engine both ship beside
# this script (REQ-D1.1; orchestration-concurrency Task 1/6). A missing or
# non-executable sibling is a broken install: the hook stays fail-soft (it is a
# PostToolUse hook), the CLI fails closed.
script_dir=$(cd "$(dirname "$0")" 2>/dev/null && pwd) || script_dir=""
lock_sh="$script_dir/orchestrate-lock.sh"
state_sh="$script_dir/orchestrate-state.sh"

# The placement program. Reads the derivation state map (id<TAB>state) as the
# first file, then tasks.md. Emits the canonical layout on stdout. Fully static
# (no interpolated input) so parsed spec text never reaches the program text.
# shellcheck disable=SC2016 # $0/$1..$3 are awk fields, not shell expansions
AWK_PROG='
function sec_for(id,   s) {
  s = state[id]
  if (s == "completed") return "Completed"
  if (s == "in-progress") return "In progress"
  return "Forward plan"
}
function flush_block() {
  if (bcap && bid != "" && !(bid in seenid)) {
    seenid[bid] = 1
    nblk++
    blkid[nblk] = bid
    sub(/[[:space:]]+$/, "", btext)
    btext = btext "\n"
    blktext[nblk] = btext
  }
  bcap = 0
  bid = ""
  btext = ""
}
function push_lines(t,   n, a, i) {
  n = split(t, a, "\n")
  for (i = 1; i <= n; i++) {
    if (i == n && a[i] == "") continue
    no++
    O[no] = a[i]
  }
}
function emit_human(S,   b) {
  no++
  O[no] = "## " S
  no++
  O[no] = ""
  b = hbody[S]
  sub(/^[[:space:]]+/, "", b)
  sub(/[[:space:]]+$/, "", b)
  if (b == "") {
    no++
    O[no] = "(none yet)"
  } else {
    b = b "\n"
    push_lines(b)
  }
  no++
  O[no] = ""
}
BEGIN {
  TRIAD["Forward plan"] = 1
  TRIAD["In progress"] = 1
  TRIAD["Completed"] = 1
  HUMAN["Awaiting input"] = 1
  HUMAN["Deferred"] = 1
  HUMAN["Out of scope"] = 1
  ORDER[1] = "Forward plan"
  ORDER[2] = "In progress"
  ORDER[3] = "Awaiting input"
  ORDER[4] = "Completed"
  ORDER[5] = "Deferred"
  ORDER[6] = "Out of scope"
  NORD = 6
  inpre = 1
  npre = 0
  nblk = 0
  bcap = 0
  bid = ""
  btext = ""
  curtype = "none"
  noth = 0
}
# First file: the derivation state map (id<TAB>state). Default FS splits on the
# tab, so $1 is the id and $2 the state.
FNR == NR {
  state[$1] = $2
  next
}
# Strip git conflict markers from tasks.md (REQ-C1.3: regenerate from truth, do
# not resolve by ours/theirs/union). Triad task blocks duplicated across the
# sides are deduped by id in flush_block; content inside sticky human-owned /
# unknown sections is preserved as-is (a task parked there and duplicated by the
# conflict keeps both copies — the reconcile does not edit human-owned bodies).
/^<<<<<<</ || /^=======/ || /^>>>>>>>/ || /^\|\|\|\|\|\|\|/ {
  next
}
{
  if (inpre) {
    if ($0 ~ /^## /) {
      # The preamble ends at the first CANONICAL state-section. A `## ` section
      # that precedes it (e.g. a top-of-file `## Dependency graph`, as
      # specs/bootstrap/tasks.md carries) is not a state section: keep it, header
      # and body, in the preamble so its position is preserved rather than being
      # parked after the canonical set with the other unknown sections.
      pre_sec = substr($0, 4)
      if (TRIAD[pre_sec] || HUMAN[pre_sec]) {
        inpre = 0
      } else {
        npre++
        pre[npre] = $0
        next
      }
    } else {
      npre++
      pre[npre] = $0
      next
    }
  }
  if ($0 ~ /^## /) {
    flush_block()
    cur = substr($0, 4)
    seen[cur] = 1
    if (TRIAD[cur]) {
      curtype = "triad"
    } else if (HUMAN[cur]) {
      curtype = "human"
    } else {
      curtype = "other"
      if (!(cur in othseen)) {
        othseen[cur] = 1
        noth++
        oth[noth] = cur
      }
    }
    next
  }
  if (curtype == "triad") {
    if ($0 ~ /^### Task [0-9]/) {
      flush_block()
      bcap = 1
      bid = $3
      btext = $0 "\n"
      next
    }
    if ($0 ~ /^### /) {
      flush_block()
      next
    }
    if (bcap) {
      btext = btext $0 "\n"
      next
    }
    next
  }
  # human / other sections: capture the body verbatim here; emit_human
  # canonicalizes its blank whitespace on output (content kept, no data loss).
  hbody[cur] = hbody[cur] $0 "\n"
  next
}
END {
  flush_block()
  while (npre > 0 && pre[npre] ~ /^[[:space:]]*$/) {
    npre--
  }
  no = 0
  for (i = 1; i <= npre; i++) {
    no++
    O[no] = pre[i]
  }
  no++
  O[no] = ""
  for (k = 1; k <= NORD; k++) {
    S = ORDER[k]
    if (TRIAD[S]) {
      cnt = 0
      for (i = 1; i <= nblk; i++) {
        if (sec_for(blkid[i]) == S) cnt++
      }
      if (!(seen[S] || cnt > 0)) continue
      no++
      O[no] = "## " S
      no++
      O[no] = ""
      if (cnt > 0) {
        first = 1
        for (i = 1; i <= nblk; i++) {
          if (sec_for(blkid[i]) == S) {
            if (!first) {
              no++
              O[no] = ""
            }
            push_lines(blktext[i])
            first = 0
          }
        }
      } else {
        no++
        O[no] = "(none yet)"
      }
      no++
      O[no] = ""
    } else {
      if (!seen[S]) continue
      emit_human(S)
    }
  }
  # Any unknown ## sections (not present in a valid bundle) are preserved after
  # the canonical set so nothing is silently dropped.
  for (k = 1; k <= noth; k++) {
    emit_human(oth[k])
  }
  # Normalize: drop leading blanks, collapse blank runs to one, no trailing
  # blank line.
  prevblank = 0
  started = 0
  for (i = 1; i <= no; i++) {
    if (O[i] ~ /^[[:space:]]*$/) {
      if (started) prevblank = 1
      continue
    }
    if (prevblank) {
      print ""
      prevblank = 0
    }
    print O[i]
    started = 1
  }
}
'

# The bundle-Status derivation program (kickoff-lifecycle Task 6; D-2, D-3;
# REQ-A1.5, REQ-C1.2). Reads the derivation state map (id<TAB>state) as the
# first file, then tasks.md, and prints the derived bundle status on stdout:
#   Active  iff at least one task derives In-progress or Completed;
#   Ready   otherwise (signed off, no progress, startable work remains);
#   Done    iff no Forward-plan / In-progress / Awaiting-input task remains
#           (Done precedence over Ready/Active, REQ-A1.5).
# A task parked in a sticky human section is classified by that section
# (Awaiting input -> pending; Deferred / Out of scope -> ignored); every other
# task is classified by its derived state, matching the placement reconcile.
# Fully static (no interpolated input).
# shellcheck disable=SC2016 # $1..$3 are awk fields, not shell expansions
STATUS_AWK='
FNR == NR { st[$1] = $2; next }
/^## / { sec = substr($0, 4); next }
/^### Task [0-9]/ { seen[$3] = 1; tsec[$3] = sec; next }
END {
  fwd = 0; inp = 0; comp = 0; await = 0
  for (id in seen) {
    s = tsec[id]
    # A task parked in a sticky human section is classified by that section, not
    # by its derived state: Awaiting input is pending startable work; Deferred /
    # Out of scope are out of the live plan and do not count toward Active or
    # pending (so a stray completion marker on a deferred task cannot flip the
    # bundle to Active). Every other task is classified by its derived state,
    # mirroring the placement reconcile.
    if (s == "Awaiting input") { await++; continue }
    if (s == "Deferred" || s == "Out of scope") { continue }
    d = st[id]
    if (d == "completed") comp++
    else if (d == "in-progress") inp++
    else fwd++
  }
  pending = (fwd > 0) || (inp > 0) || (await > 0)
  progress = (inp > 0) || (comp > 0)
  if (!pending) print "Done"
  else if (progress) print "Active"
  else print "Ready"
}
'

# write_status_header <file> <value>: rewrite the bundle **Status:** header (the
# first ^**Status:** line; task-level `- **Status:**` annotations start with
# "- " and are never matched) to <value> via a same-directory temp + rename
# (atomic, REQ-B1.1). A file without the header is a no-op; an already-correct
# value is a no-op (idempotent, REQ-B1.2); a symlinked file is refused.
#
# Tracks its in-flight same-directory temp in the global $wsh_tmp so the
# EXIT/signal trap (rm_lock_and_tmp) can clean it, mirroring $tmpf: a signal
# landing between mktemp and the rename would otherwise leak a
# .tasks-pr-sync-st.* file in the spec dir (the spec-dir temp $tmpf already
# guards against for the placement write).
wsh_tmp=""
write_status_header() {
  wsh_file=$1
  wsh_val=$2
  # Refuse ANY symlink before the missing-file no-op: `-f` follows the link, so a
  # broken symlink or a symlink to a non-regular target (e.g. a directory) would
  # otherwise fail `-f` and be silently treated as "file missing" (return 0)
  # rather than refused, hiding a partial-mirror problem. Order `-L` first so the
  # refusal is unconditional, matching the documented contract.
  if [ -L "$wsh_file" ]; then
    log "refusing symlinked $wsh_file"
    return 1
  fi
  [ -f "$wsh_file" ] || return 0
  wsh_cur=$(awk '/^\*\*Status:\*\* / { print $2; exit }' "$wsh_file") || wsh_cur=""
  [ -n "$wsh_cur" ] || return 0           # no bundle Status header in this file
  [ "$wsh_cur" = "$wsh_val" ] && return 0 # already correct: idempotent no-op
  wsh_tmp=$(mktemp "$(dirname "$wsh_file")/.tasks-pr-sync-st.XXXXXX") || return 1
  if awk -v val="$wsh_val" '
        !did && /^\*\*Status:\*\* / { print "**Status:** " val; did = 1; next }
        { print }
      ' "$wsh_file" >"$wsh_tmp"; then
    if mv "$wsh_tmp" "$wsh_file"; then
      wsh_tmp=""
      return 0
    fi
    rm -f "$wsh_tmp"
    wsh_tmp=""
    log "status rename failed for $wsh_file"
    return 1
  fi
  rm -f "$wsh_tmp"
  wsh_tmp=""
  log "status rewrite failed for $wsh_file"
  return 1
}

# do_status <canonical-spec-dir> <state-map>: derive the bundle Status from the
# task-state evidence (Done > Active > Ready, REQ-A1.5) and reconcile the
# **Status:** header across the four spec files, mirrored. The reconcile owns
# only the {Ready, Active} set: a Draft bundle's flip to Ready is the human-gated
# /spec-kickoff write (REQ-A1.4, never derived) and Done / Retired / Superseded
# are left untouched (REQ-A1.5 "applies only to bundles not already Done"; the
# reopen Done->Draft is the human's, REQ-A1.6). requirements.md is the
# authoritative Status home (spec-format.md): its value gates the reconcile and
# the derived value is mirrored to all four. Best-effort: a failure is logged and
# does not abort placement (status and placement are independent writes).
do_status() {
  dst_dir=$1
  dst_map=$2
  dst_req="$dst_dir/requirements.md"
  [ -f "$dst_req" ] || return 0
  dst_cur=$(awk '/^\*\*Status:\*\* / { print $2; exit }' "$dst_req") || dst_cur=""
  case $dst_cur in
    Ready | Active) ;;
    *) return 0 ;; # Draft / Done / terminal / absent: not reconcile-owned
  esac
  # An empty state map would make awk's FNR==NR file discriminator read the first
  # tasks.md line as a map entry (the classic empty-first-file gotcha) and derive
  # a spurious Done. do_placement only reaches here after a non-zero-task
  # derivation (state_sh exits 2 when taskless), so the map is non-empty in
  # practice; guard anyway rather than rely on that invariant from a distance.
  [ -s "$dst_map" ] || return 0
  dst_val=$(awk "$STATUS_AWK" "$dst_map" "$dst_dir/tasks.md") || return 0
  case $dst_val in
    Ready | Active | Done) ;;
    *) return 0 ;; # derivation produced nothing usable: leave the header alone
  esac
  dst_rc=0
  for dst_f in requirements.md design.md tasks.md test-spec.md; do
    write_status_header "$dst_dir/$dst_f" "$dst_val" || dst_rc=1
  done
  return $dst_rc
}

# do_placement <canonical-spec-dir>: recompute placement from the derivation and
# atomically rewrite tasks.md. Assumes the per-spec lock is already held. Exit
# 0 on a successful rewrite OR a no-op; 1 on any failure that leaves tasks.md
# untouched. Sets the global $tmpf so the caller trap can clean a half-written
# temp on a signal.
tmpf=""
do_placement() {
  dp_dir=$1
  dp_tasks="$dp_dir/tasks.md"
  if [ ! -f "$dp_tasks" ]; then
    log "no tasks.md in $dp_dir; skipping"
    return 1
  fi
  if [ -L "$dp_tasks" ]; then
    log "refusing symlinked tasks.md in $dp_dir"
    return 1
  fi

  # Derive each task's state (the Task 1 backbone). A non-zero exit (taskless /
  # unreadable / invalid spec id) means there is no truth to place from: leave
  # tasks.md untouched.
  dp_raw=$(mktemp "${TMPDIR:-/tmp}/tasks-pr-sync-state.XXXXXX") || return 1
  if ! "$state_sh" "$dp_dir" >"$dp_raw" 2>/dev/null; then
    rm -f "$dp_raw"
    log "derivation failed for $dp_dir; tasks.md unchanged"
    return 1
  fi
  dp_map=$(mktemp "${TMPDIR:-/tmp}/tasks-pr-sync-map.XXXXXX") || {
    rm -f "$dp_raw"
    return 1
  }
  # Keep only the `task` records, projected to `id<TAB>state`; the diagnostic
  # records (contradiction / degraded / refused / malformed-deps) are not
  # placement input. A failed projection (e.g. a full TMPDIR while the spec dir
  # still has space) would leave a partial map, which the placement program
  # below would read as "these tasks have no derived state" and wrongly sink to
  # Forward plan; treat it like any other derivation failure and leave tasks.md
  # untouched (same discipline as the $state_sh check above).
  if ! awk -F'\t' '$1 == "task" { print $2 "\t" $3 }' "$dp_raw" >"$dp_map"; then
    rm -f "$dp_raw" "$dp_map"
    log "state projection failed for $dp_dir; tasks.md unchanged"
    return 1
  fi
  rm -f "$dp_raw"

  # Reconcile the derived bundle Status header (kickoff-lifecycle Task 6;
  # REQ-A1.5, REQ-C1.2) from the same derivation map, before the placement
  # rewrite. Independent of placement: a status failure is logged, not fatal.
  do_status "$dp_dir" "$dp_map" || log "status reconcile incomplete in $dp_dir"

  # Atomic write: a same-directory temp renamed into place (REQ-B1.1).
  tmpf=$(mktemp "$dp_dir/.tasks-pr-sync.XXXXXX") || {
    rm -f "$dp_map"
    return 1
  }
  if awk "$AWK_PROG" "$dp_map" "$dp_tasks" >"$tmpf"; then
    rm -f "$dp_map"
    if [ ! -s "$tmpf" ]; then
      rm -f "$tmpf"
      tmpf=""
      log "empty placement output; $dp_tasks unchanged"
      return 1
    fi
    if cmp -s "$tmpf" "$dp_tasks"; then
      # Idempotent no-op: identical content, skip the rename (no mtime churn).
      rm -f "$tmpf"
      tmpf=""
      return 0
    fi
    if mv "$tmpf" "$dp_tasks"; then
      tmpf=""
      log "reconciled placement in $dp_tasks"
      return 0
    fi
    dp_rc=$?
    rm -f "$tmpf"
    tmpf=""
    log "rename failed (mv exit $dp_rc); $dp_tasks unchanged"
    return 1
  fi
  dp_rc=$?
  rm -f "$dp_map" "$tmpf"
  tmpf=""
  log "placement failed (awk exit $dp_rc); $dp_tasks unchanged"
  return 1
}

# The held lock dir for the EXIT/signal trap (empty when nothing is held).
rr_lockdir=""
# shellcheck disable=SC2329 # invoked indirectly via the EXIT trap in run_reconcile
rm_lock_and_tmp() {
  if [ -n "$rr_lockdir" ]; then
    "$lock_sh" release "$rr_lockdir" >/dev/null 2>&1 || true
  fi
  [ -n "$tmpf" ] && rm -f "$tmpf"
  [ -n "$wsh_tmp" ] && rm -f "$wsh_tmp"
}

# run_reconcile <canonical-spec-dir> <policy>: acquire the shared lock, run
# do_placement under it, release. policy is `soft` (hook: any acquire failure
# or broken install is a clean no-op) or `closed` (CLI: a broken install or a
# lock error returns 2). Returns 0 on a clean run/no-op/soft-skip, 2 on a
# fail-closed error.
run_reconcile() {
  rr_dir=$1
  rr_policy=$2
  if [ ! -x "$lock_sh" ]; then
    log "lock primitive '$lock_sh' missing or not executable; skipping (bookkeeping reconciles)"
    [ "$rr_policy" = closed ] && return 2
    return 0
  fi
  if [ ! -x "$state_sh" ]; then
    log "derivation engine '$state_sh' missing or not executable; skipping (bookkeeping reconciles)"
    [ "$rr_policy" = closed ] && return 2
    return 0
  fi
  rr_rc=0
  "$lock_sh" acquire "$rr_dir" || rr_rc=$?
  if [ "$rr_rc" -ne 0 ]; then
    log "lock unavailable (acquire exit $rr_rc); skipping (bookkeeping reconciles)"
    # acquire 1 = busy (a clean skip); 2 = error/refusal. The CLI surfaces a
    # real error; the hook treats both as a skip.
    if [ "$rr_policy" = closed ] && [ "$rr_rc" = 2 ]; then
      return 2
    fi
    return 0
  fi
  # Set rr_lockdir BEFORE arming the trap so the EXIT trap, once armed, always
  # sees a populated lock dir (closing the trap-armed-but-lockdir-still-empty
  # race). This does NOT make the post-acquire window leak-free: a signal
  # delivered between acquire succeeding and the trap arming still terminates
  # without running cleanup — that residual window falls to the stale-break,
  # exactly like SIGKILL below. Release through the same primitive (idempotent
  # rmdir) and clean any half-written temp. The explicit exit on a fatal signal
  # makes the EXIT cleanup run under shells (dash) that skip EXIT traps on
  # signal-default termination; SIGKILL remains unrecoverable and falls to the
  # stale-break.
  rr_lockdir=$rr_dir
  tmpf=""
  trap 'rm_lock_and_tmp' EXIT
  trap 'exit 130' HUP INT TERM
  do_placement "$rr_dir" || true
  "$lock_sh" release "$rr_dir" >/dev/null 2>&1 || true
  rr_lockdir=""
  trap - EXIT HUP INT TERM
  if [ -n "$tmpf" ]; then
    rm -f "$tmpf"
    tmpf=""
  fi
  return 0
}

# ---------------------------------------------------------------------------
# Direct CLI: `tasks-pr-sync.sh reconcile <spec-dir>`. Fails closed (exit 2) on
# a missing / non-spec / hostile dir so a caller (--bookkeeping, tests) sees a
# real error rather than a silent skip.
if [ "${1:-}" = reconcile ]; then
  cli_arg="${2:-}"
  if [ -z "$cli_arg" ]; then
    echo "usage: tasks-pr-sync.sh reconcile <spec-dir>" >&2
    exit 2
  fi
  cli_dir=$(cd "$cli_arg" 2>/dev/null && pwd -P) || {
    echo "tasks-pr-sync: no such spec dir: $cli_arg" >&2
    exit 2
  }
  if [ ! -f "$cli_dir/tasks.md" ]; then
    echo "tasks-pr-sync: no tasks.md in $cli_dir" >&2
    exit 2
  fi
  # A symlinked tasks.md is unsafe input: do_placement refuses it (-L) but
  # run_reconcile masks that refusal with `|| true`, so the CLI must reject it
  # here to honor the fail-closed contract rather than exit 0 on a silent skip.
  if [ -L "$cli_dir/tasks.md" ]; then
    echo "tasks-pr-sync: refusing symlinked tasks.md in $cli_dir" >&2
    exit 2
  fi
  # Containment + spec-id grammar are enforced by the shared lock primitive
  # (REQ-F1.1): it refuses a spec dir whose canonical parent is not specs/ or
  # whose id fails the charset, with exit 2. run_reconcile (closed) surfaces
  # that as exit 2, so a symlinked / hostile dir never reaches a write.
  run_reconcile "$cli_dir" closed
  exit $?
fi

# ---------------------------------------------------------------------------
# Hook mode: read the PostToolUse payload from stdin. Fast silent no-op on
# anything that is not a `gh pr create` / `gh pr merge` on a convention branch.
input=$(cat 2>/dev/null) || input=""
[ -n "$input" ] || exit 0

command -v git >/dev/null 2>&1 || exit 0
if ! command -v jq >/dev/null 2>&1; then
  log "jq missing; skipping"
  exit 0
fi

# One jq pass covers the tool check and the command extraction: this hook runs
# after every Bash call, so the no-op path stays one process deep.
cmd=$(printf '%s' "$input" \
  | jq -r 'if .tool_name == "Bash" then (.tool_input.command // empty) else empty end' \
    2>/dev/null) || cmd=""
[ -n "$cmd" ] || exit 0

# Match an actual `gh pr create` / `gh pr merge` invocation (at command start or
# after a shell separator), not a mere substring mention.
gh_pr() {
  printf '%s' "$cmd" \
    | grep -qE "(^|[;&|(]|&&|\\|\\|)[[:space:]]*gh[[:space:]]+pr[[:space:]]+$1([[:space:]]|\$)"
}
if gh_pr create; then
  action=create
elif gh_pr merge; then
  action=merge
else
  exit 0
fi

# The command's stdout is only needed to resolve a PR number for the
# merge-from-a-non-convention-branch case (the head ref lookup below). Bash
# sends tool_response as an object with .stdout, but stay shape-defensive.
out=$(printf '%s' "$input" \
  | jq -r '.tool_response | if type == "object" then (.stdout // "") else tostring end' \
    2>/dev/null) || out=""

# --- Branch. `gh pr create` always runs on the head branch; `gh pr merge` often
# runs elsewhere (e.g. main), so fall back to the PR's headRefName (resolved via
# a PR number scraped from stdout / the command / `gh pr view`). The gh-supplied
# value goes through the same validation as a git one.
branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null) || branch=""
case $branch in
  planwright/*) ;;
  *)
    if [ "$action" = merge ] && command -v gh >/dev/null 2>&1; then
      pr_num=$(printf '%s' "$out" \
        | grep -oE 'https://github\.com/[^/[:space:]]+/[^/[:space:]]+/pull/[0-9]+' \
        | head -1 | grep -oE '[0-9]+$') || pr_num=""
      if [ -z "$pr_num" ]; then
        pr_num=$(printf '%s' "$out" | grep -oE '#[0-9]+' | head -1 | tr -d '#') || pr_num=""
      fi
      if [ -z "$pr_num" ]; then
        pr_num=$(printf '%s' "$cmd" \
          | grep -oE "gh[[:space:]]+pr[[:space:]]+merge[[:space:]]+[0-9]+" \
          | head -1 | grep -oE '[0-9]+$') || pr_num=""
      fi
      if [ -n "$pr_num" ]; then
        branch=$(gh pr view "$pr_num" --json headRefName --jq .headRefName 2>/dev/null) \
          || branch=""
      else
        branch=$(gh pr view --json headRefName --jq .headRefName 2>/dev/null) || branch=""
      fi
    fi
    ;;
esac
case $branch in
  planwright/*) ;;
  *) exit 0 ;;
esac

# --- Parse + validate as pure strings, before any path is formed.
rest=${branch#planwright/}
spec=${rest%%/*}
[ "$spec" != "$rest" ] || exit 0 # no second segment
seg=${rest#*/}
case $seg in
  */*) exit 0 ;;  # extra path separators
  spec) exit 0 ;; # reserved spec-authoring namespace (D-44)
  task-*) ;;
  *) exit 0 ;;
esac
ids=${seg#task-}
printf '%s\n' "$spec" | grep -qE '^[a-z0-9][a-z0-9-]{0,63}$' || exit 0
printf '%s\n' "$ids" | grep -qE '^[0-9]+(\.[0-9]+)?(-[0-9]+(\.[0-9]+)?)?$' || exit 0

# --- Resolve the PRIMARY checkout (risk row 3): worktree-resident runs must
# reconcile the canonical tasks.md, not the worktree copy.
common=$(git rev-parse --git-common-dir 2>/dev/null) || exit 0
case $common in
  /*) ;;
  *) common=$PWD/$common ;;
esac
common=$(cd "$common" 2>/dev/null && pwd -P) || exit 0
case $common in
  */.git) primary=${common%/.git} ;;
  *) exit 0 ;; # bare repo: no primary working tree to write
esac

# --- Containment (REQ-F1.1): the resolved spec dir must sit under
# <primary>/specs/ after symlink resolution, and tasks.md must not be a symlink
# pointing elsewhere.
specs_root="$primary/specs"
spec_dir="$specs_root/$spec"
[ -f "$spec_dir/tasks.md" ] || exit 0
[ ! -L "$spec_dir/tasks.md" ] || {
  log "refusing symlinked tasks.md for spec '$spec'"
  exit 0
}
canon_specs=$(cd "$specs_root" 2>/dev/null && pwd -P) || exit 0
canon_dir=$(cd "$spec_dir" 2>/dev/null && pwd -P) || exit 0
case $canon_dir in
  "$canon_specs"/*) ;;
  *)
    log "spec '$spec' resolves outside $canon_specs; refusing"
    exit 0
    ;;
esac

# Reconcile the whole spec's placement from truth (fail-soft: a busy / missing
# lock is a clean no-op that --bookkeeping reconciles).
run_reconcile "$canon_dir" soft
exit 0
