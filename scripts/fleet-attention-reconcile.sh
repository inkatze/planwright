#!/bin/sh
# fleet-attention-reconcile.sh — the level-triggered clear of attention rows
# nobody alive will clear: the rows a dead or finished earlier tower wrote
# (doctrine/orchestration-modes.md, the attention surface: `clear` any row
# whose unit is no longer in flight or awaiting input).
#
# A tower clears the rows it wrote at teardown. A tower that died first leaves
# them `working` forever, and no later tower clears a row it did not write, so
# stalled-looking workers survive every restart. This pass judges every row in
# the store on durable evidence alone, the same on any tower:
#
#   CLEAR when the row claims a live worker (working, idle, hung, ended) and
#   the worker's registry death handle is positively dead through
#   scripts/fleet-death-evidence.sh (its tmux window or process is gone), or
#   when nothing on record can still be running for it (no death handle on
#   record, or a status row: pr-ready, merged, done) and its spec unit
#   derives completed through scripts/orchestrate-state.sh (every task of a
#   bundle range).
#
#   KEEP everything else: an awaiting-input row (a queued decision is the
#   human's, whatever its unit or worker show), a worker that is alive or
#   whose death verdict is unknown or errored (even on a completed unit: it
#   may still run, and its own tower clears it), every row while the
#   registry cannot be read, and a row whose unit is still in flight.
#   Silence is never evidence.
#
# The unit rule reads this checkout's spec root, and the fleet home is shared
# by every checkout on the machine: a row whose worker record names a state
# directory outside this checkout is not judged by this checkout's
# derivation, so a same-named spec elsewhere cannot clear it. A row with no
# record (an earlier tower's window-id handle) is judged here.
#
# The verdict is reached outside the store lock (a derivation can take
# seconds), so each clear goes through `fleet-attention.sh clear --if-row`,
# which removes the row only while it still carries the judged scope, state
# and stamp: a worker that wrote since keeps its new row. The operator
# kill-switch (fleet-daemon-gate.sh) is checked at entry and again before
# each clear, and every clear is a fleet-audit record under the
# `attention-reconcile` mechanism.
#
# Usage: fleet-attention-reconcile.sh [--repo <checkout>]
#   <checkout> defaults to the caller's own git toplevel (else $PWD); its spec
#   root holds the bundles the unit rule derives.
#
# Output (stdout, tab-separated):
#   clear   <worker> unit-completed | process-dead | tmux-window-dead
#   keep    <worker> awaiting-input | alive | evidence-unknown |
#                    evidence-errored | no-evidence | in-flight | changed |
#                    malformed | duplicate | clear-failed
#   paused  -        the kill-switch was set mid-pass; the rest waits
#   summary rows=<n> cleared=<n> kept=<n> status=<ok|degraded|paused>
#   degraded when the store, the registry, or a derivation could not be read,
#   a handle holds more than one row, or a clear or its audit record failed;
#   every such row is kept.
#
# Exit codes: 0 the pass ran (degraded included); 2 usage, or no fleet home;
#   4 the kill-switch is set, or could not be resolved.
#
# POSIX sh on the macOS + Linux support bar. All input is data; no eval, no
# model or network call of its own in any decision (the derivation's own gh
# probe aside). Pathname expansion is disabled (set -f).
set -uf

LC_ALL=C
export LC_ALL
unset CDPATH

script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2

# shellcheck source=scripts/echo-safety.sh
. "$script_dir/echo-safety.sh"

FS="$script_dir/fleet-state.sh"
FA="$script_dir/fleet-attention.sh"
STATE="$script_dir/orchestrate-state.sh"
DEATH="$script_dir/fleet-death-evidence.sh"
GATE="$script_dir/fleet-daemon-gate.sh"
AUDIT="$script_dir/fleet-audit.sh"
TAB=$(printf '\t')

warn() { printf 'fleet-attention-reconcile: %s\n' "$*" >&2; }

repo=""
while [ "$#" -gt 0 ]; do
  case $1 in
    --repo)
      [ "$#" -ge 2 ] || {
        warn "usage: fleet-attention-reconcile.sh [--repo <checkout>]"
        exit 2
      }
      repo=$2
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
    *)
      warn "usage: fleet-attention-reconcile.sh [--repo <checkout>]"
      exit 2
      ;;
  esac
done

if [ -z "$repo" ]; then
  repo=$(/bin/sh "$script_dir/resolve-root.sh" repo --checkout 2>/dev/null) || repo=$PWD
fi
repo=$(cd "$repo" 2>/dev/null && pwd -P) || {
  warn "cannot resolve the checkout"
  exit 2
}

if ! (cd "$repo" && "$GATE" attention-reconcile 2>/dev/null); then
  warn "daemon layer paused or kill-switch unresolvable — skipping the attention reconcile (unset fleet_daemon_pause to resume)"
  exit 4
fi

root=$(/bin/sh "$FS" root 2>/dev/null) || root=""
[ -n "$root" ] || {
  warn "cannot resolve the fleet home"
  exit 2
}
store="$root/attention/state"

rows=0
cleared=0
kept=0
status=ok

summary() {
  printf 'summary\trows=%s\tcleared=%s\tkept=%s\tstatus=%s\n' "$rows" "$cleared" "$kept" "$status"
}

[ -f "$store" ] || {
  summary
  exit 0
}
snapshot=$(cat "$store" 2>/dev/null) || {
  warn "could not read the attention store; nothing was cleared"
  status=degraded
  summary
  exit 0
}

# The handles holding more than one row: corruption the store's one-row-per-
# worker invariant rules out, kept rather than judged on either row.
dups=$(printf '%s\n' "$snapshot" | awk -F'\t' 'NF { n[$1 ""]++ } END { for (w in n) if (n[w] > 1) print w }')
if [ -n "$dups" ]; then
  status=degraded
  warn "the attention store holds more than one row for: $(sanitize_printable "$(printf '%s' "$dups" | tr '\n' ' ')" "(unprintable handle)")"
fi

# The last registry record per handle, read once: <handle>TAB<record>. An
# unreadable registry leaves the death rule without evidence (every row it
# would judge is kept), and the pass says so.
reg_ok=1
reg_raw=$(/bin/sh "$FS" registry 2>/dev/null) || reg_ok=0
if [ -e "$root/registry" ] && [ ! -r "$root/registry" ]; then
  reg_ok=0
fi
lastmap=""
if [ "$reg_ok" = 1 ]; then
  lastmap=$(printf '%s\n' "$reg_raw" | awk -F'\t' '
    NF >= 2 { if (!($2 in last)) order[++n] = $2; last[$2] = $0 }
    END { for (i = 1; i <= n; i++) print order[i] "\t" last[order[i]] }') || reg_ok=0
fi
if [ "$reg_ok" = 0 ]; then
  warn "could not read the registry; no row is cleared this pass, since any of them may have a live worker on record"
  status=degraded
  lastmap=""
fi

# The name arrives through the environment: awk processes escapes in a `-v`
# value.
latest() {
  printf '%s\n' "$lastmap" | LW=$1 awk -F'\t' '($1 "") == ENVIRON["LW"] { sub(/^[^\t]*\t/, ""); print; exit }'
}

# This checkout's spec root, and the roots a worker of this checkout records
# its state under: the checkout itself and the primary checkout its worktrees
# hang off.
specs_root=""
sr_rc=0
specs_root=$(cd "$repo" && env -u PLANWRIGHT_REPO_ROOT /bin/sh "$script_dir/resolve-root.sh" spec 2>/dev/null) || sr_rc=$?
case $sr_rc in
  0 | 3) ;;
  *)
    specs_root=""
    warn "the spec root did not resolve (resolve-root.sh exit $sr_rc) — no row is cleared on unit completion this pass"
    status=degraded
    ;;
esac
primary=$(cd "$repo" && common=$(git rev-parse --git-common-dir 2>/dev/null) && cd "$common" 2>/dev/null && pwd -P) || primary=""
case $primary in
  */.git) primary=${primary%/.git} ;;
  *) primary="" ;;
esac

# ours <state-dir> — true when a worker record's state directory is this
# checkout's, or the record names none. The writer refuses `..` segments; a
# record carrying one anyway is judged foreign rather than prefix-matched.
ours() {
  case $1 in
    "" | -) return 0 ;;
    .. | ../* | */.. | */../*) return 1 ;;
    "$repo" | "$repo"/*) return 0 ;;
  esac
  if [ -n "$primary" ]; then
    case $1 in "$primary" | "$primary"/*) return 0 ;; esac
  fi
  return 1
}

# The per-spec derivations, cached for the pass: <spec>TAB<id>TAB<state>
# lines, and the specs whose derivation failed.
derived=""
derived_specs=" "
failed_specs=" "

# derive <spec> — ensure the spec's derivation is cached; 1 when it failed.
derive() {
  case $derived_specs in *" $1 "*) return 0 ;; esac
  case $failed_specs in *" $1 "*) return 1 ;; esac
  # From the checkout, as the spec root was resolved: the derivation finds its
  # work repository from the current one.
  dv_out=$(cd "$repo" && env -u PLANWRIGHT_REPO_ROOT /bin/sh "$STATE" "$specs_root/$1" 2>/dev/null </dev/null) || {
    failed_specs="$failed_specs$1 "
    warn "the derivation of spec $1 failed — its rows are kept this pass"
    status=degraded
    return 1
  }
  dv_lines=$(printf '%s\n' "$dv_out" | awk -F'\t' -v s="$1" '$1 == "task" && NF >= 3 { print s "\t" $2 "\t" $3 }')
  derived="$derived
$dv_lines"
  derived_specs="$derived_specs$1 "
  return 0
}

# unit_completed <scope> — true when the scope names a spec unit of this
# checkout whose every task derives completed. A bundle range `<a>-<b>` covers
# every task id between its ends, both ends included and required.
unit_completed() {
  uc_spec=${1%%:*}
  uc_unit=${1#*:}
  [ "$uc_spec" != "$1" ] || return 1
  uc_unit=${uc_unit#task-}
  case $uc_spec in
    "" | flight | -* | *[!a-z0-9-]*) return 1 ;;
  esac
  [ "${#uc_spec}" -le 64 ] || return 1
  printf '%s' "$uc_unit" | grep -Eq '^[0-9]+(\.[0-9]+)?(-[0-9]+(\.[0-9]+)?)?$' || return 1
  [ -n "$specs_root" ] && [ -f "$specs_root/$uc_spec/tasks.md" ] || return 1
  derive "$uc_spec" || return 1
  uc_lo=${uc_unit%-*}
  uc_hi=${uc_unit#*-}
  printf '%s\n' "$derived" | awk -F'\t' -v s="$uc_spec" -v lo="$uc_lo" -v hi="$uc_hi" '
    function key(id,  p, n) { n = split(id, p, "."); return sprintf("%012d.%012d", p[1], (n > 1 ? p[2] : 0)) }
    BEGIN { klo = key(lo); khi = key(hi) }
    ($1 "") == (s "") {
      k = key($2)
      if (k < klo || k > khi) next
      if (k == klo) seen_lo = 1
      if (k == khi) seen_hi = 1
      if ($3 != "completed") open = 1
    }
    END { exit !(seen_lo && seen_hi && !open) }'
}

# evidence <death-handle> — print the clear evidence and return 0 when the
# worker is positively gone; print why it is kept and return 1 otherwise.
evidence() {
  case $1 in
    "process "* | "tmux-window "*) ;;
    *)
      printf 'no-evidence'
      return 1
      ;;
  esac
  ev_class=${1%% *}
  ev_rest=${1#* }
  ev_rc=0
  if [ "$ev_class" = process ]; then
    "$DEATH" process "$ev_rest" >/dev/null 2>&1 || ev_rc=$?
  else
    "$DEATH" tmux-window "${ev_rest%% *}" "${ev_rest#* }" >/dev/null 2>&1 || ev_rc=$?
  fi
  case $ev_rc in
    0)
      printf '%s-dead' "$ev_class"
      return 0
      ;;
    1) printf 'alive' ;;
    3) printf 'evidence-unknown' ;;
    *) printf 'evidence-errored' ;;
  esac
  return 1
}

keep() {
  kept=$((kept + 1))
  printf 'keep\t%s\t%s\n' "$(sanitize_printable "$1" "(unprintable worker)")" "$2"
}

while IFS="$TAB" read -r w scope state stamp _; do
  [ -n "$w$scope$state" ] || continue
  rows=$((rows + 1))
  row_ok=1
  case $w in
    "" | . | .. | *[!A-Za-z0-9._=@:-]*) row_ok=0 ;;
  esac
  case $scope in
    "" | . | .. | *[!A-Za-z0-9._=@:-]*) row_ok=0 ;;
  esac
  case $stamp in
    "" | *[!0-9]*) row_ok=0 ;;
  esac
  case $state in
    working | idle | hung | ended | pr-ready | merged | done | awaiting-input) ;;
    *) row_ok=0 ;;
  esac
  if [ "$row_ok" = 0 ] || [ "${#w}" -gt 128 ]; then
    keep "$w" malformed
    continue
  fi
  if printf '%s\n' "$dups" | grep -Fqx -- "$w"; then
    keep "$w" duplicate
    continue
  fi
  if [ "$state" = awaiting-input ]; then
    keep "$w" awaiting-input
    continue
  fi
  if [ "$reg_ok" = 0 ]; then
    keep "$w" evidence-unknown
    continue
  fi
  record=$(latest "$w")
  r_sd=""
  r_dh=""
  if [ -n "$record" ]; then
    IFS="$TAB" read -r _ _ _ _ _ r_sd r_dh _ <<REC
$record
REC
  fi
  # The worker's own evidence first: it is cheap, and any verdict but
  # no-evidence settles a row that claims a live worker. Only a row it
  # leaves open pays for a derivation.
  why=""
  case $state in
    working | idle | hung | ended)
      if [ -z "$record" ]; then
        ev=no-evidence
      elif ev=$(evidence "$r_dh"); then
        why=$ev
      elif [ "$ev" != no-evidence ]; then
        keep "$w" "$ev"
        continue
      fi
      ;;
    *) ev=in-flight ;;
  esac
  if [ -z "$why" ]; then
    if ours "$r_sd" && unit_completed "$scope"; then
      why=unit-completed
    else
      keep "$w" "$ev"
      continue
    fi
  fi
  # Re-checked before each clear, as the gate asks of a multi-resource
  # mechanism: a verdict can take a derivation's seconds to reach.
  if ! (cd "$repo" && "$GATE" attention-reconcile 2>/dev/null); then
    warn "the kill-switch was set mid-pass — stopping before the next clear"
    printf 'paused\t-\n'
    status=paused
    break
  fi
  c_rc=0
  /bin/sh "$FA" clear "$w" --if-row "$scope" "$state" "$stamp" >/dev/null 2>&1 </dev/null || c_rc=$?
  case $c_rc in
    0)
      cleared=$((cleared + 1))
      printf 'clear\t%s\t%s\n' "$w" "$why"
      "$AUDIT" record attention-reconcile clear-row "attention reconcile" \
        "worker=$w scope=$scope state=$state evidence=$why row cleared" >/dev/null 2>&1 </dev/null || {
        warn "could not record the clear of '$w' in the audit trail"
        status=degraded
      }
      ;;
    3) keep "$w" changed ;;
    *)
      warn "could not clear the row of '$w' ($why); the next pass retries"
      status=degraded
      keep "$w" clear-failed
      ;;
  esac
done <<EOF
$snapshot
EOF
summary
exit 0
