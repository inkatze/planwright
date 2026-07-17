#!/bin/sh
# fleet-sweep.sh — the periodic dirty-tree sweep that ALSO doubles as the
# REQ-A1.8 reconcile-from-ground-truth backstop for missed pushes (Task 4: D-8,
# D-1; REQ-B1.3, REQ-A1.8).
#
# TWO PASSES, ONE CYCLE.
#
# 1. DIRTY-TREE SWEEP (REQ-B1.3, D-8). Every working tree the fleet tracks —
#    every registered worker worktree (fleet-worktree-track.sh list) AND the
#    tower's OWN checkout, on whatever branch it is currently on — is checked for
#    uncommitted OR unpushed diffs. The tower's-own-checkout scope is the point of
#    D-8: the motivating incident was a tower directly editing a file and never
#    committing it before a handover, which a worker-only sweep would miss. A tree
#    that has been in a dirty/uninspectable state past a configured GRACE
#    threshold (`fleet_dirty_tree_threshold`) is ESCALATED to the decision queue
#    (fleet-attention.sh decide), never silently left. The state is RE-VERIFIED
#    immediately before escalating (kickoff risk 10), and a tree that cannot be
#    inspected — git-lock contention or not a repo — is treated as attention-
#    needed and escalated ("could not inspect"), never misread as clean.
#
# 2. RECONCILE BACKSTOP (REQ-A1.8, D-1). The same cycle re-runs the level-
#    triggered tasks.md reconcile (tasks-pr-sync.sh reconcile) for every spec
#    bundle in the tower's checkout. A dropped `gh pr create`/`merge` PostToolUse
#    hook (a failed hook execution) leaves the tasks.md snapshot lagging git
#    ground truth; this re-run corrects it from that same ground truth on the next
#    cycle, WITHOUT a second push. The dirty-tree pass runs FIRST, so a drift
#    correction this cycle plants is not re-escalated until a later cycle (past the
#    grace), by which point the tower's normal flow has committed it.
#
# KILL-SWITCH + AUDIT (D-15, D-16). The sweep is a daemon action: it gates
# through fleet-daemon-gate.sh at entry (a set fleet_daemon_pause pauses the whole
# cycle) and audits each escalation, and each reconcile that ACTUALLY corrected
# drift, through fleet-audit.sh. A no-op reconcile is not audited (kickoff risk
# 31: the trail records real actions, not routine sweeps).
#
# Usage:
#   fleet-sweep.sh [--repo <repo-root>]
#     <repo-root> defaults to the caller's own git toplevel (else $PWD): the
#     tower's checkout, always included in the dirty-tree scope.
#
# Exit codes: 0 sweep completed; 2 usage; 4 the kill-switch paused the sweep.
#   Per-tree inspection failures are escalated, not fatal — one bad tree never
#   fails the cycle.
#
# POSIX sh on the macOS + Linux support bar. All input is data; no eval (REQ-K1.5).
# Pathname expansion is disabled by default (set -f) and enabled only around the
# one bundle glob.
set -uf

LC_ALL=C
export LC_ALL
unset CDPATH

script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2

# shellcheck source=scripts/echo-safety.sh
. "$script_dir/echo-safety.sh"

GATE="$script_dir/fleet-daemon-gate.sh"
AUDIT="$script_dir/fleet-audit.sh"
ATTN="$script_dir/fleet-attention.sh"
WT="$script_dir/fleet-worktree-track.sh"
SYNC="$script_dir/tasks-pr-sync.sh"
CONFIG_GET="$script_dir/config-get.sh"
FS="$script_dir/fleet-state.sh"

warn() { printf 'fleet-sweep: %s\n' "$*" >&2; }

repo=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo)
      [ "$#" -ge 2 ] || {
        warn "--repo needs a value"
        exit 2
      }
      repo=$2
      shift 2
      ;;
    *)
      warn "usage: fleet-sweep.sh [--repo <repo-root>]"
      exit 2
      ;;
  esac
done

command -v git >/dev/null 2>&1 || {
  warn "no git binary on PATH — cannot sweep working trees"
  exit 2
}

# Resolve the tower's checkout: an explicit --repo, else the caller's own git
# toplevel, else $PWD.
if [ -z "$repo" ]; then
  repo=$(git rev-parse --show-toplevel 2>/dev/null) || repo=$PWD
fi
if [ ! -d "$repo" ]; then
  warn "repo root '$repo' is not a directory"
  exit 2
fi
repo=$(cd "$repo" 2>/dev/null && pwd -P) || {
  warn "cannot resolve repo root"
  exit 2
}

# Kill-switch gate: the sweep is a daemon action. A set switch (or an
# unresolvable one) pauses the whole cycle.
if ! "$GATE" housekeeping-sweep 2>/dev/null; then
  warn "daemon layer paused or kill-switch unresolvable — skipping the sweep (unset fleet_daemon_pause to resume)"
  exit 4
fi

# Grace threshold in seconds: `fleet_dirty_tree_threshold` (minutes, optional `m`
# suffix; the stale_*_threshold convention), default 15m. A tree must be
# continuously dirty past this before it is escalated, so an actively-worked tree
# is not flagged mid-edit.
threshold_seconds() {
  tsv_min=15
  tsv_read=$("$CONFIG_GET" fleet_dirty_tree_threshold 2>/dev/null) || tsv_read=""
  tsv_read=${tsv_read%m}
  case $tsv_read in
    "" | *[!0-9]*) ;;
    *) tsv_min=$tsv_read ;;
  esac
  printf '%s' $((tsv_min * 60))
}
THRESHOLD=$(threshold_seconds)

now_epoch() {
  ne_v=$(date +%s 2>/dev/null)
  case $ne_v in
    "" | *[!0-9]*) printf '' ;;
    *) printf '%s' "$ne_v" ;;
  esac
}

# tree_id <path> — a stable numeric id for the dirty-since marker (POSIX cksum).
tree_id() {
  printf '%s' "$1" | cksum | awk '{print $1}'
}

# inspect_tree <path> — echo clean | dirty | uninspectable. Uncommitted changes
# OR any commit not on a remote-tracking branch is dirty; a git error (lock
# contention, not a repo) is uninspectable (never silently clean).
inspect_tree() {
  it_t=$1
  git -C "$it_t" rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
    printf 'uninspectable'
    return 0
  }
  it_porc=$(git -C "$it_t" status --porcelain 2>/dev/null) || {
    printf 'uninspectable'
    return 0
  }
  it_unpushed=$(git -C "$it_t" rev-list --count HEAD --not --remotes 2>/dev/null) || {
    printf 'uninspectable'
    return 0
  }
  case $it_unpushed in
    "" | *[!0-9]*)
      printf 'uninspectable'
      return 0
      ;;
  esac
  if [ -n "$it_porc" ] || [ "$it_unpushed" != 0 ]; then
    printf 'dirty'
  else
    printf 'clean'
  fi
}

SINCE_DIR=""
root_home=$("$FS" root 2>/dev/null) || root_home=""
if [ -n "$root_home" ]; then
  SINCE_DIR="$root_home/worktrees/dirty-since"
fi

audit() {
  "$AUDIT" record housekeeping-sweep "$1" "$2" "$3" 2>/dev/null \
    || warn "could not record a '$1' action in the audit trail"
}

escalate() {
  es_path=$1
  es_state=$2
  # fleet-attention keys a decision row on the WORKER HANDLE alone (one row per
  # worker, upsert). So the handle must be UNIQUE PER TREE (`sweep-<tree-id>`) —
  # else two dirty trees would collapse to one queue entry — while a re-sweep of
  # the same still-dirty tree re-uses the handle and upserts (no duplicate).
  es_worker="sweep-$(tree_id "$es_path")"
  if [ "$es_state" = uninspectable ]; then
    es_q="Could not inspect working tree $es_path (git-lock contention or not a repo); retrying next sweep."
    es_opts="investigate|ignore"
    es_scope=uninspectable-tree
  else
    es_q="Stale working tree $es_path has uncommitted or unpushed changes sitting past the threshold."
    es_opts="commit|push|discard|investigate"
    es_scope=dirty-tree
  fi
  # The path is UI-bound text; refuse to escalate rather than tear the queue if
  # it somehow carries a control byte or is over-length (decide validates too).
  if "$ATTN" decide "$es_worker" "$es_scope" "$es_q" investigate "$es_opts" high 2>/dev/null; then
    audit escalate "$es_scope" "working tree $es_path escalated to the decision queue ($es_state)"
  else
    warn "could not escalate '$es_path' to the decision queue"
  fi
}

# --- Pass 1: the dirty-tree sweep. Trees = registry ∪ {tower checkout}, deduped
#     by realpath.
trees=$(
  {
    "$WT" list 2>/dev/null
    printf '%s\n' "$repo"
  } | awk 'NF' | while IFS= read -r t; do
    [ -e "$t" ] || continue
    rp=$(cd "$t" 2>/dev/null && pwd -P) || continue
    printf '%s\n' "$rp"
  done | awk '!seen[$0]++'
)

now=$(now_epoch)
old_ifs=$IFS
IFS='
'
for tree in $trees; do
  IFS=$old_ifs
  state=$(inspect_tree "$tree")
  id=$(tree_id "$tree")
  marker=""
  [ -n "$SINCE_DIR" ] && marker="$SINCE_DIR/$id"

  if [ "$state" = clean ]; then
    [ -n "$marker" ] && rm -f "$marker" 2>/dev/null
    IFS='
'
    continue
  fi

  # Attention-needed (dirty or uninspectable): apply the grace via a persistent
  # first-seen marker, so a fresh problem waits one threshold before escalating
  # (a transient lock or an in-progress edit resolves itself by then).
  since=""
  if [ -n "$marker" ]; then
    mkdir -p "$SINCE_DIR" 2>/dev/null || true
    if [ -f "$marker" ]; then
      since=$(cat "$marker" 2>/dev/null)
      case $since in
        "" | *[!0-9]*) since="" ;;
      esac
    fi
    if [ -z "$since" ]; then
      since=$now
      [ -n "$now" ] && printf '%s\n' "$now" >"$marker" 2>/dev/null || true
    fi
  else
    since=$now
  fi

  age=0
  if [ -n "$now" ] && [ -n "$since" ]; then
    age=$((now - since))
  fi
  if [ "$age" -lt "$THRESHOLD" ]; then
    IFS='
'
    continue
  fi

  # Past the grace: re-verify immediately (risk 10). A tree that became clean
  # between the two checks is a transient — drop it, do not escalate.
  reverify=$(inspect_tree "$tree")
  if [ "$reverify" = clean ]; then
    [ -n "$marker" ] && rm -f "$marker" 2>/dev/null
    IFS='
'
    continue
  fi
  escalate "$tree" "$reverify"
  IFS='
'
done
IFS=$old_ifs

# --- Pass 2: the reconcile backstop. Re-run the tasks.md reconcile for every
#     spec bundle in the tower's checkout; audit only a reconcile that changed
#     the snapshot (a dropped-push drift actually corrected).
if [ -x "$SYNC" ] && [ -d "$repo/specs" ]; then
  set +f
  for d in "$repo"/specs/*/; do
    set -f
    [ -d "$d" ] || {
      set +f
      continue
    }
    tasks="$d/tasks.md"
    if [ ! -f "$tasks" ]; then
      set +f
      continue
    fi
    rel="specs/$(basename "$d")"
    before_sum=$(cksum <"$tasks" 2>/dev/null) || before_sum=""
    (cd "$repo" && "$SYNC" reconcile "$rel") >/dev/null 2>&1 || true
    after_sum=$(cksum <"$tasks" 2>/dev/null) || after_sum=""
    if [ -n "$before_sum" ] && [ "$before_sum" != "$after_sum" ]; then
      audit reconcile reconcile-backstop "$rel snapshot drift corrected from git ground truth (missed-push backstop)"
    fi
    set +f
  done
  set -f
fi

exit 0
