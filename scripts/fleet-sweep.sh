#!/bin/sh
# fleet-sweep.sh — the periodic fleet sweep: the worktree disk-scan reconcile,
# the dirty-tree sweep, the tasks.md reconcile backstop for missed pushes, the
# reap of leaked worker processes, and the flight residues, as one cycle on a
# schedule
# (fleet-autonomy D-8, D-1; fleet-lifecycle-closure D-5, D-14).
#
# ON A SCHEDULE, NEVER ON A THRESHOLD (D-5). A cycle has no precondition: it
# runs every pass whether or not anything looks wrong, because waiting until a
# leak is alarming is what let one run for hours. `--watch` runs a cycle every
# `fleet_sweep_interval`; the bare form runs one cycle. Either is started by a
# tower, which the reap needs (see --tower-id below). The dirty-tree grace (`fleet_dirty_tree_threshold`) defers one
# escalation and never gates a cycle.
#
# FIVE PASSES, ONE CYCLE, in this order.
#
# 1. WORKTREE SCAN. The disk-scan reconcile (fleet-worktree-track.sh scan) over
#    the tower's checkout, so a worktree no dispatch seam recorded is tracked
#    before the dirty-tree pass reads the registry. A failed scan is reported
#    and the cycle continues on the registry as it stands.
#
# 2. DIRTY-TREE SWEEP. Every working tree the fleet tracks — every registered
#    worker worktree AND the tower's OWN checkout, on whatever branch it is
#    currently on — is checked for uncommitted OR unpushed diffs. The tower's
#    own checkout is in scope because the motivating incident was a tower
#    editing a file and never committing it before a handover, which a
#    worker-only sweep would miss. A tree dirty or uninspectable past the grace
#    is ESCALATED to the decision queue (fleet-attention.sh decide), after a
#    re-verification immediately before escalating; a tree that cannot be
#    inspected (git-lock contention, not a repo) is escalated as "could not
#    inspect", never misread as clean. A tree that heals has its escalation
#    retracted.
#
# 3. RECONCILE BACKSTOP. The level-triggered tasks.md reconcile
#    (tasks-pr-sync.sh reconcile) for every spec bundle in the tower's checkout.
#    A dropped `gh pr create`/`merge` PostToolUse hook leaves the snapshot
#    lagging git ground truth; this corrects it from that same ground truth on
#    the next cycle. It runs after the dirty-tree pass, so a correction planted
#    this cycle is not escalated until a later one, past the grace.
#
# 4. PROCESS REAP. The stuck-detector's scan names every worker; each whose
#    session has ended (dead, finished-but-unreaped, or an unclassified
#    completion) is a candidate, handed to fleet-cleanup.sh process, which
#    alone decides and closes. The sweep matches no process and sends no signal
#    of its own. Reaping releases the process only: fence, branch and worktree
#    are untouched, and the reclaim decision stays the operator's.
#
#    OBSERVING BY DEFAULT (D-14). A reap kills nothing unless this machine opts
#    in with `fleet_sweep_reap: terminate` in its machine-local overlay. Set in
#    any shared layer, or in a machine-local file the repository itself
#    supplies (tracked, symlinked, or a nested repository), `terminate` is
#    refused with a warning.
#
#    TERMINATE IS CURRENTLY REFUSED EVERYWHERE. The stream-json close seeds its
#    kill set from the pid files a worker leaves behind, and a crashed worker's
#    pid can be reissued to an unrelated process, which a close would then kill
#    with its subtree. Until that close checks a recorded pid is still the
#    worker's, a `terminate` that passes every check above still observes, and
#    the cycle warns once saying so.
#
#    Observing, each
#    candidate goes through the same decision with `--observe`, and a worker a
#    close would take gets a `would-cleanup` audit record naming
#    `released=none` and what the close would release; an actual close writes
#    `cleanup`. The knob is read every cycle, so flipping it back takes effect
#    on the next one with no restart and no release. A leaked worker met
#    every cycle is recorded once per candidacy and evidence class, not once
#    per cycle; the sweep drops the mark of a worker that stops being a
#    candidate, so its next candidacy is recorded afresh.
#
#    Every candidate the reap does not close is reported with the refusal the
#    actuator gave, so a sweep that declined everything reads differently from
#    one that found nothing.
#
# 5. FLIGHT RESIDUES. A visual flight leaves two residues outside git: its
#    worker brief under the fleet home, retired once its worktree is gone
#    (flight-dispatch.sh retire), and the derived flight index of a checkout
#    that no longer exists (flight-sweep.sh prune). Both are swept here, each
#    removal audited, so neither outlives its flight silently. Flight
#    worktrees themselves are registered worktrees, already in the scope of passes 1 and 2.
#
# KILL-SWITCH + AUDIT. The cycle gates through fleet-daemon-gate.sh at entry
# (a set fleet_daemon_pause pauses the whole cycle; the reap actuator also
# gates on its own). Escalations, reconciles that corrected drift, reaps, and
# flight residue removals are audited through fleet-audit.sh; a no-op is not.
#
# SIGNALS. A watch loop is normally stopped by a signal, so the dirty-since
# temp this script creates beside its marker is removed by the INT/TERM/HUP
# traps as well as on the normal paths, and the loop's wait between cycles is
# interruptible. The stores the cycle writes through do the same for theirs.
#
# Usage:
#   fleet-sweep.sh [--repo <repo-root>] [--tower-id <token>] [--watch]
#     <repo-root> defaults to the caller's own git toplevel (else $PWD): the
#     tower's checkout, always included in the dirty-tree scope. Every knob
#     the cycle reads comes from this checkout's overlay layers, wherever the
#     sweep was started. The wait between watch cycles is never under a
#     second.
#     <token> is the identity of the tower the sweep acts for, handed to the
#     detector and the reap actuator; without it they resolve one from
#     PLANWRIGHT_TOWER_ID, PLANWRIGHT_TOWER_SESSION_ID or PLANWRIGHT_TOWER_PID.
#     The sweep runs only from inside a tower: with none of those, no owner
#     can be told from a live peer, so the reap asks the actuator nothing and
#     declines every candidate in one line naming why (no tower identity).
#
# Output (stdout, tab-separated, per cycle the kill-switch lets through; a
# paused cycle prints only its warning):
#   scan    ok | degraded
#   reap    <worker> <outcome> <detail>
#       outcome: reaped | partial | observed | already-closed | declined |
#       unrecorded | paused. detail is what was (or would be) released, or the
#       refusal the actuator gave. A partial or unrecorded close counts as
#       reaped (observed, when observing): it acted.
#   summary mode=<observe|terminate> workers=<n> candidates=<n> reaped=<n>
#       observed=<n> declined=<n> already-closed=<n>
#       status=<ok|degraded|paused>: degraded when a store could not be read
#       or a close is missing from the audit trail, which outranks paused;
#       paused when the kill-switch was set mid-pass.
#
# Exit codes: 0 sweep completed (a watch loop runs until signalled); 2 usage;
#   4 the kill-switch paused a one-shot sweep. Per-tree inspection failures are
#   escalated, not fatal — one bad tree never fails the cycle.
#
# POSIX sh on the macOS + Linux support bar. All input is data; no eval, no
# model or network call in any decision (REQ-K1.5). Pathname expansion is
# disabled by default (set -f) and enabled only around the one bundle glob.
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
FLIGHT_DISPATCH="$script_dir/flight-dispatch.sh"
FLIGHT_SWEEP="$script_dir/flight-sweep.sh"
CONFIG_GET="$script_dir/config-get.sh"
KNOB="$script_dir/resolve-config-knob.sh"
OVERLAY="$script_dir/resolve-overlay-root.sh"
DET="$script_dir/fleet-stuck-detector.sh"
CLEANUP="$script_dir/fleet-cleanup.sh"
FS="$script_dir/fleet-state.sh"
TAB=$(printf '\t')

warn() { printf 'fleet-sweep: %s\n' "$*" >&2; }

since_tmp=""
sleep_pid=""
on_exit() {
  [ -z "$since_tmp" ] || rm -f "$since_tmp" 2>/dev/null
  [ -z "$sleep_pid" ] || kill "$sleep_pid" 2>/dev/null
}
trap on_exit EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

usage() {
  warn "usage: fleet-sweep.sh [--repo <repo-root>] [--tower-id <token>] [--watch]"
  exit 2
}

repo=""
tower_id=""
watch=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo)
      [ "$#" -ge 2 ] || {
        warn "--repo needs a value"
        exit 2
      }
      repo=$2
      # Screen the operator-supplied value before it reaches cd / git -C: a
      # leading dash would be read as an option, a control byte is never a real
      # repo path.
      case $repo in
        "" | -*)
          warn "refusing a malformed --repo value (empty or leading dash)"
          exit 2
          ;;
      esac
      if [ "$repo" != "$(sanitize_printable "$repo")" ]; then
        warn "refusing a --repo value with a control byte"
        exit 2
      fi
      shift 2
      ;;
    --tower-id)
      [ "$#" -ge 2 ] || {
        warn "--tower-id needs a value"
        exit 2
      }
      tower_id=$2
      # The registry's owner-token grammar (fleet-state.sh valid_owner): the
      # value becomes an argv word of the detector and the actuator.
      case $tower_id in
        "" | . | .. | unknown-owner | -* | *[!A-Za-z0-9._-]*)
          warn "refusing a malformed --tower-id"
          exit 2
          ;;
      esac
      [ "${#tower_id}" -le 128 ] || {
        warn "refusing an over-length --tower-id"
        exit 2
      }
      shift 2
      ;;
    --watch)
      watch=1
      shift
      ;;
    *) usage ;;
  esac
done

command -v git >/dev/null 2>&1 || {
  warn "no git binary on PATH — cannot sweep working trees"
  exit 2
}

# Resolve the tower's checkout: an explicit --repo, else the caller's own
# checkout, else $PWD.
if [ -z "$repo" ]; then
  repo=$(/bin/sh "$script_dir/resolve-root.sh" repo --checkout 2>/dev/null) || repo=$PWD
fi
if [ ! -d "$repo" ]; then
  warn "repo root '$repo' is not a directory"
  exit 2
fi
repo=$(cd "$repo" 2>/dev/null && pwd -P) || {
  warn "cannot resolve repo root"
  exit 2
}

# Grace threshold in seconds: `fleet_dirty_tree_threshold` (minutes, optional `m`
# suffix; the stale_*_threshold convention), default 15m. A tree must be
# continuously dirty past this before it is escalated, so an actively-worked tree
# is not flagged mid-edit.
threshold_seconds() {
  tsv_min=15
  tsv_read=$(cd "$repo" && "$CONFIG_GET" fleet_dirty_tree_threshold 2>/dev/null) || tsv_read=""
  tsv_read=${tsv_read%m}
  case $tsv_read in
    "" | *[!0-9]*) ;;
    *)
      # Strip leading zeros BEFORE the arithmetic below: bash 3.2 / POSIX sh read
      # a leading-zero token like `08` as octal in $(( )) ("value too great for
      # base"), which would leave THRESHOLD empty and break the grace compare.
      while :; do
        case $tsv_read in
          0?*) tsv_read=${tsv_read#0} ;;
          *) break ;;
        esac
      done
      tsv_min=$tsv_read
      ;;
  esac
  printf '%s' $((tsv_min * 60))
}

now_epoch() {
  ne_v=$(date +%s 2>/dev/null)
  case $ne_v in
    "" | *[!0-9]*) printf '' ;;
    *) printf '%s' "$ne_v" ;;
  esac
}

# tree_id <path> — a stable numeric id for the dirty-since marker and the decision
# handle (POSIX cksum / CRC32). A CRC32 collision between two DISTINCT tracked
# trees would share a handle/marker, but with a fleet's handful-to-dozens of
# trees the birthday probability is negligible; a portable stronger hash (md5/sha)
# is not on the support bar.
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
  # The decision-queue question and the audit reasoning both run through a
  # <=512-byte control-free-text grammar. A deeply-nested worktree path
  # (valid_path admits up to 4096) would push either over the cap, so the write
  # would be refused and a genuinely dirty tree would never be queued. Use a
  # tail-truncated path (the distinctive leaf is what an operator needs) so both
  # always fit.
  es_disp=$es_path
  if [ "${#es_disp}" -gt 400 ]; then
    es_disp="...$(printf '%s' "$es_disp" | tail -c 397)"
  fi
  if [ "$es_state" = uninspectable ]; then
    es_q="Could not inspect working tree $es_disp (git-lock contention or not a repo); retrying next sweep."
    es_opts="investigate|ignore"
    es_scope=uninspectable-tree
  else
    es_q="Stale working tree $es_disp has uncommitted or unpushed changes sitting past the threshold."
    es_opts="commit|push|discard|investigate"
    es_scope=dirty-tree
  fi
  # The path is UI-bound text; refuse to escalate rather than tear the queue if
  # it somehow carries a control byte or is over-length (decide validates too).
  if "$ATTN" decide "$es_worker" "$es_scope" "$es_q" investigate "$es_opts" high 2>/dev/null; then
    audit escalate "$es_scope" "working tree $es_disp escalated to the decision queue ($es_state)"
  else
    warn "could not escalate '$es_path' to the decision queue"
  fi
}

# retract <path> — clear any decision-queue escalation this tree raised, once it
# self-heals (dirty/uninspectable -> clean). Keyed on the SAME per-tree handle
# escalate upserts (`sweep-<tree-id>`), so a resolved condition leaves no
# standing false alarm in the queue (the ISA-18.2 rationalization the queue
# targets). Best-effort and idempotent: fleet-attention `clear` is a no-op when
# nothing is queued under that handle, so calling it on a clean-again tree that
# was never actually escalated costs only a filter over the store.
retract() {
  "$ATTN" clear "sweep-$(tree_id "$1")" >/dev/null 2>&1 || true
}

scan_pass() {
  if "$WT" scan "$repo" >/dev/null 2>&1; then
    printf 'scan\tok\n'
  else
    warn "the worktree disk scan failed — the dirty-tree pass reads the registry as it stands, retrying next sweep"
    printf 'scan\tdegraded\n'
  fi
}

# Trees = registry ∪ {tower checkout}, deduped by realpath.
dirty_tree_pass() {
  THRESHOLD=$(threshold_seconds)
  SINCE_DIR=""
  root_home=$("$FS" root 2>/dev/null) || root_home=""
  if [ -n "$root_home" ]; then
    SINCE_DIR="$root_home/worktrees/dirty-since"
  else
    # Fail LOUD, never fail silently open: without a persistable grace store the
    # sweep cannot defer, so it escalates attention-needed trees immediately
    # (below) rather than silently skipping them — the exact fail-open a safety
    # net must not have. (The decision queue lives under the same home, so
    # escalation may itself warn; that surfaces the broken state instead of
    # hiding it.)
    warn "fleet home unresolvable — cannot persist the dirty-tree grace clock; attention-needed trees are escalated without deferral"
  fi

  trees=$(
    {
      "$WT" list 2>/dev/null
      printf '%s\n' "$repo"
    } | awk 'NF' | while IFS= read -r t; do
      [ -e "$t" ] || continue
      # Normalize through realpath for dedup, but keep an existing-but-unreadable
      # path (a dir with search permission stripped, or a worktree path clobbered
      # by a file) AS-IS rather than dropping it — matching `scan`'s prune. A
      # dropped tree is never inspected; kept, inspect_tree escalates it as
      # "could not inspect" instead of the sweep silently skipping it.
      rp=$(cd "$t" 2>/dev/null && pwd -P) || rp=$t
      printf '%s\n' "$rp"
    done | awk '!seen[$0]++'
  )

  now=$(now_epoch)
  if [ -z "$now" ]; then
    warn "could not read a numeric clock (date +%s) — cannot compute the dirty-tree grace; attention-needed trees are escalated without deferral"
  fi
  # `for tree in $trees` field-splits the list ONCE at loop entry using this IFS;
  # restoring IFS inside the body (so command substitutions split on whitespace)
  # does not re-split the already-computed list, so no per-iteration re-set is
  # needed — set it once at the body top.
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
      # A tree that had a dirty-since marker (it was tracked dirty) and is now
      # clean has self-healed: retract any escalation it raised before dropping
      # the marker, so the resolved condition leaves no standing false alarm.
      if [ -n "$marker" ] && [ -f "$marker" ]; then
        retract "$tree"
      fi
      [ -n "$marker" ] && rm -f "$marker" 2>/dev/null
      continue
    fi

    # Attention-needed (dirty or uninspectable): apply the grace via a persistent
    # first-seen marker, so a fresh problem waits one threshold before escalating
    # (a transient lock or an in-progress edit resolves itself by then). If the
    # grace cannot be TRACKED — no marker store, no usable clock, or the marker
    # cannot be persisted — do NOT silently defer (that is the fail-open a safety
    # net must not have): fall through to escalate. `past_grace` defaults to 1 so
    # every untrackable path escalates rather than skips.
    past_grace=1
    if [ -n "$marker" ] && [ -n "$now" ] && mkdir -p "$SINCE_DIR" 2>/dev/null; then
      since=""
      if [ -f "$marker" ]; then
        since=$(cat "$marker" 2>/dev/null)
        # Reject a leading-zero token (0?*) as well as non-digits: a corrupt or
        # legacy marker like `0900000000` would otherwise be read as octal by the
        # `age=$((now - since))` arithmetic below — fatal under a dash `/bin/sh`
        # (aborting the whole sweep mid-loop, so the later passes never run), or
        # silently mis-parsed under bash. This mirrors threshold_seconds above
        # and the sibling integer-reads (fleet-state read_counter,
        # fleet-attention). An invalid marker leaves `since` empty, so the grace
        # clock re-plants below rather than the sweep trusting a garbage age.
        case $since in
          "" | *[!0-9]* | 0?*) since="" ;;
        esac
      fi
      if [ -z "$since" ]; then
        # First time seen in this state: persist the clock ATOMICALLY (temp+rename,
        # the house discipline — a truncating `>` write could be read mid-flight as
        # empty by a concurrent sweep and reset the grace clock). The temp is the
        # trap's to remove until the rename lands.
        since_tmp=$(mktemp "$SINCE_DIR/.since.XXXXXX" 2>/dev/null) || since_tmp=""
        if [ -n "$since_tmp" ] && printf '%s\n' "$now" >"$since_tmp" 2>/dev/null \
          && mv -f "$since_tmp" "$marker" 2>/dev/null; then
          since_tmp=""
          since=$now
        else
          [ -n "$since_tmp" ] && rm -f "$since_tmp" 2>/dev/null
          since_tmp=""
          # Could not persist the grace clock: leave `since` empty so past_grace
          # stays 1 (escalate) — never defer on a grace we cannot track.
        fi
      fi
      if [ -n "$since" ]; then
        age=$((now - since))
        [ "$age" -lt "$THRESHOLD" ] && past_grace=0
      fi
    fi
    [ "$past_grace" = 1 ] || continue

    # Past the grace: re-verify immediately (risk 10). A tree that became clean
    # between the two checks is a transient — drop it, do not escalate.
    reverify=$(inspect_tree "$tree")
    if [ "$reverify" = clean ]; then
      # Became clean between the grace check and re-verify: retract a prior-cycle
      # escalation the same way the top-of-loop clean branch does.
      [ -n "$marker" ] && [ -f "$marker" ] && retract "$tree"
      [ -n "$marker" ] && rm -f "$marker" 2>/dev/null
      continue
    fi
    escalate "$tree" "$reverify"
  done
  IFS=$old_ifs
}

# Re-run the tasks.md reconcile for every spec bundle in the tower's checkout;
# audit only a reconcile that changed the snapshot (a dropped-push drift
# actually corrected). The spec root is the one the checkout resolves; where it
# lies inside the checkout, bundles are named relative to it, as the reconcile
# and the audit trail have always named them.
reconcile_pass() {
  specs_root=""
  if [ -x "$SYNC" ]; then
    sr_rc=0
    specs_root=$(cd "$repo" && env -u PLANWRIGHT_REPO_ROOT /bin/sh "$script_dir/resolve-root.sh" spec 2>/dev/null) || sr_rc=$?
    # No repository is the quiet skip a missing specs/ always was; a refused
    # spec_root silently stops the backstop, so it is said every sweep.
    case $sr_rc in
      0 | 3) ;;
      *)
        specs_root=""
        warn "the spec root did not resolve (resolve-root.sh exit $sr_rc) — missed-push backstop skipped, retrying next sweep"
        ;;
    esac
  fi
  if [ -n "$specs_root" ] && [ -d "$specs_root" ]; then
    case $specs_root in
      "$repo"/*) specs_rel=${specs_root#"$repo"/} ;;
      *) specs_rel=$specs_root ;;
    esac
    # Enable globbing only to expand the bundle set ONCE at loop entry; -f is
    # restored for the body and the glob is not re-expanded per iteration.
    set +f
    for d in "$specs_root"/*/; do
      set -f
      [ -d "$d" ] || continue
      tasks="${d}tasks.md" # $d already ends in '/'
      [ -f "$tasks" ] || continue
      rel="$specs_rel/$(basename "$d")"
      before_sum=$(cksum <"$tasks" 2>/dev/null) || before_sum=""
      rec_rc=0
      (cd "$repo" && "$SYNC" reconcile "$rel") >/dev/null 2>&1 || rec_rc=$?
      after_sum=$(cksum <"$tasks" 2>/dev/null) || after_sum=""
      if [ "$rec_rc" != 0 ]; then
        # A chronically failing backstop must not stay silent (it self-heals
        # next cycle, but a persistent failure needs to surface).
        warn "reconcile of $rel exited $rec_rc — missed-push backstop degraded, retrying next sweep"
      elif [ -n "$before_sum" ] && [ "$before_sum" != "$after_sum" ]; then
        audit reconcile reconcile-backstop "$rel snapshot drift corrected from git ground truth (missed-push backstop)"
      fi
    done
    set -f
  fi
}

# reap_mode — observe | terminate. Only the machine-local layer may say
# terminate: a shared layer saying so is a team or an adopter switching on a
# killer for every machine at once, which is the rollout this knob exists to
# keep per machine. Anything the resolver cannot answer observes, and for now
# so does a terminate that passes every check (see the header).
reap_mode() {
  rm_out=$(cd "$repo" && "$KNOB" --explain --key fleet_sweep_reap --type enum \
    --values 'observe terminate' --fallback observe) || {
    warn "fleet_sweep_reap is unresolvable — observing this cycle"
    printf 'observe'
    return 0
  }
  rm_layer=${rm_out%%"$TAB"*}
  rm_value=${rm_out#*"$TAB"}
  if [ "$rm_value" = terminate ] && [ "$rm_layer" != machine-local ]; then
    warn "fleet_sweep_reap: terminate is honored only from the machine-local layer, not the $(sanitize_printable "$rm_layer" "?") layer — observing this cycle"
    rm_value=observe
  fi
  if [ "$rm_value" = terminate ]; then
    rm_why=$(local_file_distrust)
    if [ -n "$rm_why" ]; then
      warn "fleet_sweep_reap: ignoring terminate in the machine-local file: $rm_why — observing this cycle"
      rm_value=observe
    fi
  fi
  # The stream-json close signals the pids a crashed worker left in its pid
  # files, so a pid the host has since reissued to another process would be
  # killed with its whole subtree. Until the close checks the pid is still the
  # worker's, an unattended sweep does not terminate at all.
  if [ "$rm_value" = terminate ]; then
    warn "fleet_sweep_reap: terminate is refused for now — observing this cycle: a close still trusts the pid a crashed worker left behind, so a pid the host has reissued since would be killed; terminate is honored again once the close checks that pid is still the worker's"
    rm_value=observe
  fi
  case $rm_value in
    terminate) printf 'terminate' ;;
    *) printf 'observe' ;;
  esac
}

# local_file_distrust — why the derived machine-local file is repository
# content rather than this machine's, or nothing when it is the machine's. It
# sits in the work tree, so a repository can commit it past its ignore rule,
# under a case-folded name, or behind a symlinked or nested `.claude`, and a
# committed `terminate` would switch the reaper on for every clone. The
# flight_pr_hosts reader (flight-dispatch.sh) refuses the same shapes. A file
# named explicitly by PLANWRIGHT_LOCAL_CONFIG is the operator's own.
local_file_distrust() {
  [ -z "${PLANWRIGHT_LOCAL_CONFIG:-}" ] || return 0
  lf_dir=$(cd "$repo" && /bin/sh "$OVERLAY" machine-local 2>/dev/null) || lf_dir=""
  if [ -z "$lf_dir" ]; then
    printf 'its location could not be resolved'
    return 0
  fi
  # The resolver echoes an override verbatim, and config-get read it from
  # the checkout, so a relative one is relative to the checkout.
  case $lf_dir in
    /*) ;;
    *) lf_dir="$repo/$lf_dir" ;;
  esac
  if [ -L "$lf_dir" ] || [ -L "$lf_dir/planwright.local.yml" ]; then
    printf 'it is reached through a symlink'
  elif [ -e "$lf_dir/.git" ]; then
    printf '.claude is its own repository'
  elif [ -e "${lf_dir%/*}/.git" ]; then
    # With no repository beside it, none can have supplied the file; with
    # one, anything git cannot answer is distrusted.
    git -C "${lf_dir%/*}" ls-files --error-unmatch -- ':(icase).claude/planwright.local.yml' \
      >/dev/null 2>&1 </dev/null
    case $? in
      0) printf 'the repository tracks that file' ;;
      1) ;;
      *) printf 'git could not say whether the repository tracks it' ;;
    esac
  fi
}

# refusal <captured-output> — the actuator's last diagnostic, as one printable
# line. Its em-dashes are rewritten first: the sanitizer strips bytes in the C1
# range, which would leave half a character behind.
refusal() {
  rf_line=$(printf '%s\n' "$1" | awk '/^fleet-cleanup: / { l = $0 } END { print l }')
  rf_line=${rf_line#fleet-cleanup: }
  rf_line=$(printf '%s' "$rf_line" | sed 's/—/-/g')
  sanitize_printable "$rf_line" "no reason given"
}

reap_pass() {
  rp_mode=$(reap_mode)
  rp_workers=0
  rp_cand=0
  rp_reaped=0
  rp_observed=0
  rp_declined=0
  rp_closed=0
  rp_status=ok
  rp_halted=0
  # Where fleet-cleanup.sh process --observe keeps each worker's last
  # would-have record.
  rp_marks=$("$FS" root 2>/dev/null) && rp_marks="$rp_marks/sweep-observed" || rp_marks=""
  set --
  [ -z "$tower_id" ] || set -- --tower-id "$tower_id"
  # The sweep runs only from inside a tower: without an identity no owner can
  # be told from a live peer, so every candidate is declined, in one line.
  rp_towerless=0
  if [ -z "$tower_id" ] && [ -z "${PLANWRIGHT_TOWER_ID:-}" ] \
    && [ -z "${PLANWRIGHT_TOWER_SESSION_ID:-}" ] && [ -z "${PLANWRIGHT_TOWER_PID:-}" ]; then
    rp_towerless=1
  fi
  rp_scan=$(cd "$repo" && /bin/sh "$DET" scan --checkout "$repo" "$@" 2>/dev/null) || {
    warn "the stuck-detector scan failed — no worker was considered for a reap this cycle"
    printf 'summary\tmode=%s\tworkers=0\tcandidates=0\treaped=0\tobserved=0\tdeclined=0\talready-closed=0\tstatus=degraded\n' "$rp_mode"
    return 0
  }
  case $rp_scan in
    *"anomaly${TAB}-${TAB}registry-unreadable"* | *"anomaly${TAB}-${TAB}store-unreadable"*)
      warn "a fleet store could not be read — the workers it holds were not considered for a reap"
      rp_status=degraded
      ;;
  esac
  # Anything but an explicit terminate observes, so a mode word this pass does
  # not know can never drop the flag that keeps a close from happening.
  [ "$rp_mode" = terminate ] || set -- "$@" --observe
  # The scan also lists decision-queue rows; the strand entries and the
  # sweep's own dirty-tree escalations there are not workers.
  rp_rows=$(printf '%s\n' "$rp_scan" | awk -F'\t' '$1 == "worker" && $2 !~ /^pwfence\./ && $2 !~ /^sweep-[0-9]+$/ { print $2 "\t" $3 "\t" $6 }')
  while IFS="$TAB" read -r rp_w rp_st rp_rs; do
    [ -n "$rp_w" ] || continue
    rp_workers=$((rp_workers + 1))
    case $rp_st/$rp_rs in
      dead/* | finished-but-unreaped/* | unclassified/completion-*) ;;
      *)
        # Out of candidacy: its next would-have close is recorded afresh.
        [ -z "$rp_marks" ] || rm -f "$rp_marks/$rp_w" 2>/dev/null
        continue
        ;;
    esac
    rp_cand=$((rp_cand + 1))
    if [ "$rp_towerless" = 1 ]; then
      rp_declined=$((rp_declined + 1))
      continue
    fi
    if [ "$rp_halted" = 1 ]; then
      printf 'reap\t%s\tpaused\t-\n' "$rp_w"
      continue
    fi
    rp_why=$(sanitize_printable "periodic sweep: session $rp_st ($rp_rs)" "periodic sweep")
    rp_rc=0
    rp_all=$(cd "$repo" && /bin/sh "$CLEANUP" process "$rp_w" periodic-sweep "$rp_why" "$@" 2>&1 </dev/null) \
      || rp_rc=$?
    rp_res=$(printf '%s\n' "$rp_all" | awk -v p="stop $rp_w " 'index($0, p) == 1 { r = $0 } END { print r }')
    rp_res=$(sanitize_printable "${rp_res#"stop $rp_w "}")
    case $rp_rc/$rp_res in
      0/already-closed)
        rp_out=already-closed
        rp_detail=$rp_res
        rp_closed=$((rp_closed + 1))
        ;;
      0/would-release=*)
        rp_out=observed
        rp_detail=$rp_res
        rp_observed=$((rp_observed + 1))
        ;;
      0/* | 5/stopped*)
        # Exit 5 with a full close is one a signal interrupted after it was
        # recorded: a reap all the same.
        rp_out=reaped
        rp_detail=${rp_res#stopped }
        rp_reaped=$((rp_reaped + 1))
        ;;
      4/*)
        printf 'reap\t%s\tpaused\t%s\n' "$rp_w" "$(refusal "$rp_all")"
        rp_halted=1
        # An unrecorded close earlier in the pass outranks the pause.
        [ "$rp_status" = degraded ] || rp_status=paused
        continue
        ;;
      6/*)
        # Acted (or, observing, decided) and could not record it: never left
        # to read as nothing having happened.
        rp_out=unrecorded
        rp_detail=$(refusal "$rp_all")
        if [ "$rp_mode" = observe ]; then
          rp_observed=$((rp_observed + 1))
        else
          rp_reaped=$((rp_reaped + 1))
        fi
        rp_status=degraded
        warn "the reap of '$rp_w' is not in the audit trail: $rp_detail"
        ;;
      5/partial*)
        rp_out=partial
        rp_detail=${rp_res#partial }
        rp_reaped=$((rp_reaped + 1))
        ;;
      *)
        rp_out=declined
        rp_detail=$(refusal "$rp_all")
        rp_declined=$((rp_declined + 1))
        ;;
    esac
    printf 'reap\t%s\t%s\t%s\n' "$rp_w" "$rp_out" "$rp_detail"
  done <<EOF
$rp_rows
EOF
  if [ "$rp_towerless" = 1 ] && [ "$rp_cand" -gt 0 ]; then
    rp_msg="no tower identity: all $rp_cand candidate(s) declined; the sweep runs only from inside a tower (pass --tower-id or set PLANWRIGHT_TOWER_ID)"
    printf 'reap\t-\tdeclined\t%s\n' "$rp_msg"
    warn "$rp_msg"
  fi
  printf 'summary\tmode=%s\tworkers=%s\tcandidates=%s\treaped=%s\tobserved=%s\tdeclined=%s\talready-closed=%s\tstatus=%s\n' \
    "$rp_mode" "$rp_workers" "$rp_cand" "$rp_reaped" "$rp_observed" "$rp_declined" "$rp_closed" "$rp_status"
}

# flight_residue <helper...> — run one residue helper, auditing each removal
# it reports and warning its failure with the reason; contention or a failure
# just means next cycle. Its result lines and its stderr share one capture,
# told apart by their leading field, so no temporary file is left by a signal.
flight_residue() {
  fr_all=$("$@" 2>&1 </dev/null)
  fr_rc=$?
  fr_tab=$(printf '\t')
  if [ "$fr_rc" -ne 0 ]; then
    fr_why=$(printf '%s\n' "$fr_all" | grep -v -e "^retired$fr_tab" -e "^pruned$fr_tab" | tail -n 1)
    warn "$FR_NAME exited $fr_rc${fr_why:+ ($(sanitize_printable "$fr_why"))} — flight residues left for the next sweep"
  fi
  printf '%s\n' "$fr_all" | while IFS="$fr_tab" read -r fr_kind fr_what; do
    case $fr_kind in
      retired) audit flight-brief-retire flight-residue "retired the brief of flight $fr_what (its worktree is gone)" ;;
      pruned)
        # The audit grammar caps the text and refuses some bytes a path can
        # carry; the path's tail is what identifies the checkout.
        [ "${#fr_what}" -le 400 ] || fr_what="...$(printf '%s' "$fr_what" | tail -c 397)"
        audit flight-index-prune flight-residue \
          "pruned the derived flight index of vanished checkout $(sanitize_printable "$fr_what")"
        ;;
    esac
  done
}

# flight_residue_pass — pass 5. The brief retire never waits on a dispatch
# holding the checkout's flight lock, and takes no lock at all in a checkout
# no brief names.
flight_residue_pass() {
  if [ -x "$FLIGHT_DISPATCH" ]; then
    FR_NAME='flight brief retire'
    flight_residue env PLANWRIGHT_FLIGHT_LOCK_WAIT=0 "$FLIGHT_DISPATCH" retire --repo-root "$repo"
  fi
  if [ -x "$FLIGHT_SWEEP" ]; then
    FR_NAME='flight index prune'
    flight_residue "$FLIGHT_SWEEP" prune
  fi
}

# cycle — one sweep; 4 when the kill-switch paused it before any pass.
cycle() {
  # Kill-switch gate: the sweep is a daemon action. A set switch (or an
  # unresolvable one) pauses the whole cycle.
  if ! (cd "$repo" && "$GATE" housekeeping-sweep 2>/dev/null); then
    warn "daemon layer paused or kill-switch unresolvable — skipping the sweep (unset fleet_daemon_pause to resume)"
    return 4
  fi
  scan_pass
  dirty_tree_pass
  reconcile_pass
  reap_pass
  flight_residue_pass
  return 0
}

# The shortest wait between cycles, in seconds. A cycle spawns git, the
# detector and the actuator, so a sub-second interval would run them back to
# back.
interval_floor=1

# interval_seconds — `fleet_sweep_interval` as a number of seconds `sleep`
# takes, re-read every cycle so an overlay edit applies without a restart.
interval_seconds() {
  is_v=$(cd "$repo" && "$KNOB" --key fleet_sweep_interval --type duration --fallback 10m) || is_v=10m
  is_s=$(printf '%s\n' "$is_v" | awk -v floor="$interval_floor" '{
    v = $0; m = 1
    if (v ~ /ms$/) { m = 0.001; sub(/ms$/, "", v) }
    else if (v ~ /s$/) { sub(/s$/, "", v) }
    else if (v ~ /m$/) { m = 60; sub(/m$/, "", v) }
    else if (v ~ /h$/) { m = 3600; sub(/h$/, "", v) }
    else if (v ~ /d$/) { m = 86400; sub(/d$/, "", v) }
    s = v * m
    if (s < floor) { printf "floor\n"; exit }
    printf "%.3f\n", s
  }')
  if [ "$is_s" = floor ]; then
    warn "fleet_sweep_interval $(sanitize_printable "$is_v" "?") is under ${interval_floor}s — waiting ${interval_floor}s"
    is_s=$interval_floor
  fi
  printf '%s\n' "$is_s"
}

if [ "$watch" = 0 ]; then
  cycle || exit 4
  exit 0
fi

while :; do
  cycle || :
  # Backgrounded and waited on, so a signal ends the wait at once instead of
  # after the rest of the interval.
  sleep "$(interval_seconds)" &
  sleep_pid=$!
  wait "$sleep_pid" || :
  sleep_pid=""
done
