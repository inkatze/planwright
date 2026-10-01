#!/bin/sh
# fleet-registry-reconcile.sh — the dispatch-record reconcile: the worker
# registry rebuilt from, and retired against, the dispatch markers every seam
# leaves on disk (fleet-lifecycle-closure D-15; REQ-E1.4, REQ-E1.5).
#
# THE REGISTRY IS AN INDEX OF DISK. Every registration leaves a marker,
# <fleet-home>/dispatch-markers/<handle>, beside its store write
# (fleet-register.sh). One pass walks the markers and, per marker:
#
#   HEAL. A marker whose worker has no record, or whose last record is a
#   retirement of other fields (a re-dispatch whose write failed), is rebuilt
#   through `fleet-register.sh --from-marker`: the same field grammar a
#   dispatch meets, and the store's own conditional write, so concurrent passes
#   and a dispatch racing its own write leave exactly one record. This pass
#   never writes the store itself.
#
#   RETIRE. A marker-backed worker whose live record's death evidence is
#   POSITIVE is retired through `fleet-register.sh --retire-marker`, which
#   closes exactly the record that was judged (appended, never deleted, so it
#   stays readable) and then removes the marker while it still names that
#   record. The evidence is the record's death handle through
#   scripts/fleet-death-evidence.sh; a `print` unit has none, so its worktree's
#   removal stands in, and only where the record names one. Alive, unknown,
#   errored, or no evidence at all keeps the record live. Retiring a record
#   kills nothing, so the owning tower's liveness does not enter into it. A
#   record that disagrees with its marker (a superseding write that failed)
#   is judged on its own fields; once it retires, the marker heals.
#
#   REFUSE. A marker that is not a regular file directly inside the marker
#   directory, or that fails the grammar, is refused, audited, and moved aside
#   under the marker directory's `.refused/` (kept for the operator to inspect
#   and delete), so it is reported once rather than every cycle; it is never
#   stored. A marker directory that is itself a link refuses the whole pass.
#
# A RECORD WITH NO MARKER IS NEVER TOUCHED: one written before markers existed
# is neither altered nor retired for lacking one.
#
# The pass terminates nothing, so it runs in both sweep modes. It is a daemon
# action all the same: the operator kill-switch (fleet-daemon-gate.sh) is
# checked at entry and again before each marker, and every heal, retirement
# and refusal is a fleet-audit record under the `registry-reconcile` mechanism.
#
# Usage: fleet-registry-reconcile.sh
#
# Output (stdout, tab-separated):
#   heal    <handle> <backend>
#   retire  <handle> <evidence>     process-dead | tmux-window-dead |
#                                   worktree-removed
#   keep    <handle> <why>          evidence-unknown | evidence-errored |
#                                   worktree-unknown | marker-diverged: a
#                                   record a verdict could not settle, kept
#                                   live and said so
#   refuse  <marker> <why>
#   paused  -        the kill-switch was set mid-pass; the rest waits
#   summary markers=<n> healed=<n> retired=<n> kept=<n> unjudged=<n>
#           refused=<n> status=<ok|degraded|paused>
#   `unjudged` counts live records with no evidence source at all (no death
#   handle, and not a print unit with a worktree): they never retire.
#
# Exit codes: 0 the pass ran (degraded or paused mid-pass included); 2 usage,
#   or no fleet home; 4 the kill-switch is set, or could not be resolved, at
#   entry.
#
# POSIX sh on the macOS + Linux support bar. All input is data; no eval, no
# model or network call in any decision (REQ-K1.5). Pathname expansion is
# disabled except around the one marker glob.
set -uf

LC_ALL=C
export LC_ALL
unset CDPATH

script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2

# shellcheck source=scripts/echo-safety.sh
. "$script_dir/echo-safety.sh"

FS="$script_dir/fleet-state.sh"
REGISTER="$script_dir/fleet-register.sh"
DEATH="$script_dir/fleet-death-evidence.sh"
GATE="$script_dir/fleet-daemon-gate.sh"
AUDIT="$script_dir/fleet-audit.sh"
TAB=$(printf '\t')

warn() { printf 'fleet-registry-reconcile: %s\n' "$*" >&2; }

[ "$#" -eq 0 ] || {
  warn "usage: fleet-registry-reconcile.sh"
  exit 2
}

if ! "$GATE" registry-reconcile 2>/dev/null; then
  warn "daemon layer paused or kill-switch unresolvable — skipping the registry reconcile (unset fleet_daemon_pause to resume)"
  exit 4
fi

root=$(/bin/sh "$FS" root 2>/dev/null) || root=""
[ -n "$root" ] || {
  warn "cannot resolve the fleet home"
  exit 2
}
dir="$root/dispatch-markers"

markers=0
healed=0
retired=0
kept=0
unjudged=0
refused=0
status=ok

audit() {
  "$AUDIT" record registry-reconcile "$1" "registry reconcile" "$2" 2>/dev/null || {
    warn "could not record a '$1' in the audit trail"
    status=degraded
  }
}

summary() {
  printf 'summary\tmarkers=%s\thealed=%s\tretired=%s\tkept=%s\tunjudged=%s\trefused=%s\tstatus=%s\n' \
    "$markers" "$healed" "$retired" "$kept" "$unjudged" "$refused" "$status"
}

if [ -L "$dir" ] || { [ -e "$dir" ] && [ ! -d "$dir" ]; }; then
  warn "the marker directory is not a plain directory; nothing was healed or retired from it"
  printf 'refuse\tdispatch-markers\tnot-a-directory\n'
  refused=1
  status=degraded
  audit refuse-marker "marker directory dispatch-markers refused: not a plain directory"
  summary
  exit 0
fi
if [ ! -d "$dir" ]; then
  summary
  exit 0
fi

# quarantine <path> <name> <why> — move a refused marker aside, and report and
# audit it only when this pass is the one that moved it, so concurrent passes
# and later cycles do not report it again. The link itself is moved, never
# what it points at.
quarantine() {
  q_dir="$dir/.refused"
  if [ -L "$dir" ] || [ -L "$q_dir" ]; then
    warn "the marker or refused-marker directory is a link; leaving '$2' in place"
    status=degraded
    return 0
  fi
  q_umask=$(umask)
  umask 077
  mkdir -p "$q_dir" 2>/dev/null
  umask "$q_umask"
  q_stamp=$(date +%s 2>/dev/null) || q_stamp=0
  if mv -f "$1" "$q_dir/marker.$q_stamp.$$.$refused" 2>/dev/null; then
    refused=$((refused + 1))
    printf 'refuse\t%s\t%s\n' "$2" "$3"
    audit refuse-marker "marker $2 refused and moved aside: $3"
  elif [ -e "$1" ] || [ -L "$1" ]; then
    warn "refused marker '$2' could not be moved aside ($3); it stays in place and is refused again next pass"
    status=degraded
  fi
}

# evidence <backend> <state-dir> <death-handle> — print the retirement
# evidence and return 0 when the worker is positively gone; print why it is
# kept and return 1 when no verdict settled it; return 2 when it is alive,
# and 5 when the record carries nothing a verdict could be asked of.
evidence() {
  case $3 in
    "process "* | "tmux-window "*)
      ev_class=${3%% *}
      ev_rest=${3#* }
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
        1) return 2 ;;
        3)
          printf 'evidence-unknown'
          return 1
          ;;
        *)
          printf 'evidence-errored'
          return 1
          ;;
      esac
      ;;
  esac
  # A print unit spawns nothing, so it has no death handle; its worktree is
  # the unit. Removed means the parent is a searchable directory and the path
  # is in it no longer: an unreadable or missing parent proves nothing.
  if [ "$1" = print ] && [ "$2" != - ]; then
    ev_parent=${2%/*}
    [ -n "$ev_parent" ] || ev_parent=/
    if [ -e "$2" ] || [ -L "$2" ]; then
      return 2
    fi
    if [ -d "$ev_parent" ] && [ -x "$ev_parent" ]; then
      printf 'worktree-removed'
      return 0
    fi
    printf 'worktree-unknown'
    return 1
  fi
  return 5
}

# The last row per handle, read once for the whole pass: <handle>TAB<row>.
if ! lastmap=$(/bin/sh "$FS" registry 2>/dev/null | awk -F'\t' '
  NF >= 2 { if (!($2 in last)) order[++n] = $2; last[$2] = $0 }
  END { for (i = 1; i <= n; i++) print order[i] "\t" last[order[i]] }'); then
  warn "could not read the registry; no record was healed or retired this pass"
  status=degraded
  summary
  exit 0
fi

# The name arrives through the environment: awk processes escapes in a `-v`
# value, so `w\157rker` would match the row for `worker`.
latest() {
  printf '%s\n' "$lastmap" | LW=$1 awk -F'\t' '($1 "") == ENVIRON["LW"] { sub(/^[^\t]*\t/, ""); print; exit }'
}

set +f
for path in "$dir"/*; do
  set -f
  [ -e "$path" ] || [ -L "$path" ] || continue
  if ! "$GATE" registry-reconcile 2>/dev/null; then
    warn "the kill-switch was set mid-pass — stopping before the next marker"
    printf 'paused\t-\n'
    status=paused
    break
  fi
  markers=$((markers + 1))
  name=${path##*/}
  shown=$(sanitize_printable "$name" "(unprintable name)")
  row=$(latest "$name")
  closed=$(printf '%s\n' "$row" | awk -F'\t' '{ print (NF == 8 && $8 == "closed") ? 1 : 0 }')

  # A marker that is a link, not a regular file, or not named as a handle goes
  # through the heal, which refuses it, whatever record its name finds.
  badpath=0
  if [ -L "$path" ] || [ ! -f "$path" ]; then
    badpath=1
  else
    case $name in
      "" | . | .. | -* | *[!A-Za-z0-9._=@:-]*) badpath=1 ;;
    esac
  fi
  # Missing or retired: the marker may be all that is left of a live worker.
  # A live record needs no heal, and the store would refuse to touch it.
  if [ -z "$row" ] || [ "$closed" = 1 ] || [ "$badpath" = 1 ]; then
    h_rc=0
    why=$(/bin/sh "$REGISTER" --from-marker "$path" 2>&1 >/dev/null) || h_rc=$?
    why=$(printf '%s\n' "$why" | awk 'END { sub(/^fleet-register: /, ""); print }')
    case $h_rc in
      0)
        healed=$((healed + 1))
        hb=$(cut -f4 <"$path" 2>/dev/null) || hb=-
        hb=$(sanitize_printable "$hb" "-")
        printf 'heal\t%s\t%s\n' "$name" "$hb"
        audit heal "worker=$name backend=$hb rebuilt from its dispatch marker"
        continue
        ;;
      3) ;;
      4)
        quarantine "$path" "$shown" "$(sanitize_printable "$why" "malformed")"
        continue
        ;;
      *)
        warn "could not heal '$shown': $(sanitize_printable "$why" "no reason given")"
        status=degraded
        continue
        ;;
    esac
    [ -n "$row" ] || continue
  fi

  fields=$(printf '%s\n' "$row" | cut -f2-7)
  if [ "$closed" = 1 ]; then
    # Retired already, by a pass that stopped before its marker went.
    [ "$(cat "$path" 2>/dev/null)" = "$fields" ] \
      && /bin/sh "$REGISTER" --retire-marker "$path" --expect "$fields" >/dev/null 2>&1
    continue
  fi
  IFS="$TAB" read -r _ _ _ r_b r_sd r_dh <<EOF
$fields
EOF
  ev_rc=0
  ev=$(evidence "$r_b" "$r_sd" "$r_dh") || ev_rc=$?
  case $ev_rc in
    0)
      r_rc=0
      /bin/sh "$REGISTER" --retire-marker "$path" --expect "$fields" >/dev/null 2>&1 || r_rc=$?
      case $r_rc in
        0)
          retired=$((retired + 1))
          printf 'retire\t%s\t%s\n' "$name" "$ev"
          audit retire "worker=$name backend=$(sanitize_printable "$r_b" "-") evidence=$ev record marked closed"
          ;;
        3) ;;
        4) quarantine "$path" "$shown" "refused at retirement" ;;
        *)
          warn "could not retire '$shown'; the next pass retries"
          status=degraded
          ;;
      esac
      ;;
    1)
      kept=$((kept + 1))
      printf 'keep\t%s\t%s\n' "$name" "$ev"
      ;;
    5) unjudged=$((unjudged + 1)) ;;
    *)
      if [ "$(cat "$path" 2>/dev/null)" != "$fields" ]; then
        kept=$((kept + 1))
        printf 'keep\t%s\tmarker-diverged\n' "$name"
      fi
      ;;
  esac
done
set -f
summary
exit 0
