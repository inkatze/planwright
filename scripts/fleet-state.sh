#!/bin/sh
# fleet-state.sh — the CROSS-SPEC fleet-coordination-state home, its worker/
# scope registry store, and the named concurrency-control primitive the fleet
# consumes (orchestration-fleet Task 9; D-11, REQ-D1.6, REQ-A1.6).
#
# WHERE (D-11). Fleet coordination state spans specs — the worker/scope
# registry the attention surface reads (Task 12), the fleet-level concurrency
# accounting (Task 6), and any meta-tower bookkeeping — so it cannot live under
# any one spec dir. It resolves through the ${CLAUDE_PLUGIN_DATA} chain (the
# version-stable per-plugin data home, `~/.claude/plugins/data/<id>/`), with the
# writer-mode fallback the overlay resolvers use, under a `fleet/` leaf:
#   1. $PLANWRIGHT_FLEET_STATE_DIR   explicit override (operator/test knob),
#                                    trusted verbatim (mirrors the sibling's
#                                    PLANWRIGHT_ORCH_STATE_DIR).
#   2. $CLAUDE_PLUGIN_DATA/fleet     plugin mode: the plugin-data id IS the
#                                    per-plugin namespace, and it is update-stable
#                                    (distinct from the versioned install root),
#                                    so the home survives a plugin-version change.
#   3. <claude-dir>/planwright/<name>/fleet   writer mode: the namespace is the
#                                    plugin manifest `name`, charset-validated
#                                    before it reaches a path. <claude-dir> is
#                                    $CLAUDE_DIR else $HOME/.claude.
# This is DELIBERATELY DISTINCT from the sibling's PER-spec orchestration runtime
# state (D-11): orchestration-concurrency ships its advisory lock and dispatch
# marker spec-dir-local (`<spec-dir>/.orchestrate.lock`,
# `<spec-dir>/.orchestrate/markers/`), and the per-spec effective-backend
# failover record sits spec-locally with that marker — NOT here. The spec-local
# lock home is the sibling's decision (confirmed against orchestrate-lock.sh /
# orchestrate-marker.sh), not re-decided here; no fleet path ever writes into a
# spec's `.orchestrate/` dir. The two homes differ because their state has
# different scope (cross-spec vs per-spec).
#
# THE NAMED PRIMITIVE. Because the cross-spec store is read by the attention
# surface (Task 12) while the meta-tower's fleet-bound accounting (Task 6)
# writes it, this script exposes a named cross-spec advisory lock at
# `<root>/.fleet.lock`. The MECHANISM is no longer this script's: every take and
# every release goes through scripts/lock-lib.sh, the one lock primitive in the
# tree, whose header carries the design and the measurements behind it. What
# stays here is the NAME and the guarantee — concurrent registry writes are
# serialized (no torn record) and the fleet-bound check-and-increment cannot
# over-count (no two towers exceed the bound). `lock`/`unlock` expose the lock
# for consumers with their own critical sections; `register`/`bound-incr`/
# `bound-decr` are the built-in consumers. The bound VALUE and policy are
# Task 6's.
#
# THE EXPOSED LOCK IS A DETACHED HOLD, AND ITS TOKEN CROSSES THE PROCESS
# BOUNDARY. `lock` takes a hold with no owning process to outlive it and PRINTS
# the token; `unlock <token>` hands that token back, and the unlink happens only
# while the link is still that token's — so a caller returning after its lock
# was cleared cannot delete the CURRENT holder's lock. That crossing is what the
# hand-rolled shape could not do, and its absence is the known limitation this
# header used to record; it is closed. A tokenless `unlock` is still accepted
# and is still unconditional, because it has two jobs the token path cannot do:
# it is the operator's escape hatch for a detached hold whose owner crashed, and
# it is the in-place upgrade path for a lock left as a DIRECTORY by the retired
# `mkdir` shape.
#
# STALENESS IS OWNER-PROCESS ABSENCE, NEVER AGE. The age threshold this lock
# used to consult (`stale_lock_threshold`) is gone from it, in both directions
# it was wrong: it broke LIVE locks held longer than the threshold, and it left
# DEAD ones standing for that threshold's whole span. A detached hold has no
# owning process to probe and so is never auto-broken — which is the other
# reason the tokenless `unlock` exists.
#
# RESERVATION vs SOURCE OF TRUTH. `bound-incr`/`bound-decr` are a same-instant
# RESERVATION primitive, not the authoritative fleet in-flight count. The
# authoritative count is the live git derivation the meta-tower selector
# (orchestrate-meta-select.sh) sums per step — level-triggered and self-healing,
# so it never leaks across a tower crash; that selector reads only the git truth,
# never this counter. This counter's role is to close the sub-second window
# between a meta step deciding and a subordinate tower materializing its
# branch/marker. It is NOT self-healing: a holder that crashes between
# `bound-incr` and `bound-decr` leaks its slot. The LOCK carries an owner token
# and is released by ownership; this COUNTER carries nothing of the kind, and
# its leak is still tracked in specs/_observations as
# fleet-bound-slot-leak. A consumer must not
# treat this counter as a durable occupancy tally; the git-derived count is what
# reconciles.
#
# REQ-F1.1 / REQ-A1.6 (parsed input is data, never an executed path; artifact
# data hygiene). The plugin-namespace `name` is grammar-validated (kebab charset,
# no traversal, no uppercase, ≤64) before it is interpolated into any path, so a
# hostile manifest name is a clean refusal, never an out-of-tree home. Worker and
# scope identifiers are validated against a declared field grammar before a
# record is written, so a traversal token, an embedded tab/newline, or a control
# character is refused rather than tearing the append-only registry.
#
# THE DISPATCH RECORD (fleet-lifecycle-closure Task 3; D-12, REQ-E1.2,
# REQ-D1.5). A record is what a close verb reads when the dispatching tower is
# gone, so it carries what closing a worker needs without its dispatcher:
#
#   <epoch> <worker> <scope> <owner> <backend> <state-dir> <death-handle>
#
# tab-separated, one per line, append-only, last record for a worker wins — so a
# seam that learns a column only after the launch supersedes its own earlier
# record rather than updating one in place.
#
# `state-dir` is the directory that IDENTIFIES the worker on disk, the one a
# close verb matches processes against, where a rung has one: the unit state
# directory on the two session-grade rungs, the worktree on the `/orchestrate`
# tmux rung, and absent on the rungs that keep no directory of their own
# (`/offload`'s tmux and print rungs). It is not the scratch-temp class of the
# coordination floor's resource table.
#
# `owner` is the dispatching tower's identity token (the presence surface's
# `identity`), so two towers are never confused for one another and a record's
# owner is attributable without inference.
#
# `death-handle` is the presence surface's own grammar — `process <pid>` or
# `tmux-window <session> <window>` — plus the literal `none` for a rung that
# spawns no process (the `print` rung: REQ-D1.8 exempts it from reaping, and
# recording that fact is not the same as leaving the column blank). TWO READER
# OBLIGATIONS come with it. `none` is NOT an evidence class:
# fleet-death-evidence.sh takes `process` and `tmux-window` only and exits 2 on
# anything else, so a reader must branch on the value before consulting the
# predicate rather than passing it through. And the column as a whole is an
# untrusted HINT, not an instruction: this store authenticates no caller (any
# process running as the operator can append), a bare pid carries no start-time
# anchor and so cannot be told from a recycled one, and a `tmux-window` pair can
# name a window that has since been reassigned. A destructive verb owes its own
# positive death evidence, self-target guard, and post-canonicalization
# containment check on top of whatever it reads here.
#
# An unsupplied optional field is written as `-`. No OPTIONAL field's grammar
# admits it, so absent is never confused with a value there; `worker` and `scope`
# share the older, more permissive `valid_field`, which does admit it, so a
# caller writing a literal `-` scope is indistinguishable from one that supplied
# none (fleet-register.sh writes exactly that for a scopeless dispatch, on
# purpose). A record predating this shape (three columns) still parses: its owner
# is absent, and a reader classifies it unknown-owner rather than attributing it
# to anyone. A MALFORMED field is a different case and is refused at write — a
# hostile token must not reach the store, and a reaper must never read a
# pseudo-evidence death handle (`timeout <n>`) the evidence predicate itself
# refuses (REQ-A1.7). Refusing rather than blanking makes the whole record fail,
# which is why fleet-register.sh, not this store, owns the per-field degrade that
# keeps a live worker's record from being lost to one bad column.
#
# Usage:
#   fleet-state.sh root                       resolve & print the fleet home.
#   fleet-state.sh lock                       take the advisory lock as a
#                                             detached hold and print its token
#                                             (0 held, 1 a holder has it, 2
#                                             error). One attempt, no waiting:
#                                             the wait policy is the caller's.
#   fleet-state.sh unlock [<token>]           give the lock back. With a token,
#                                             the unlink happens only while the
#                                             link is still that token's (0
#                                             released or already free, 1 a
#                                             different holder has it and
#                                             nothing was removed, 2 the removal
#                                             failed). Without one the clear is
#                                             unconditional and also takes a
#                                             legacy `mkdir` lock DIRECTORY
#                                             (0 the path is clear, 2 it is not).
#   fleet-state.sh register <worker> <scope> [--owner <token>]
#       [--backend <name>] [--state-dir <abs-dir>] [--death-handle <handle>]
#                                             append a dispatch record.
#   fleet-state.sh registry                   print the registry records.
#   fleet-state.sh bound-incr <max>           check-and-increment the fleet
#                                             counter under the bound (0 granted
#                                             + new count on stdout, 1 at bound).
#   fleet-state.sh bound-decr                 release one slot (floors at 0).
#
# Exit codes: 0 success/granted; 1 a holder has the lock (`lock`), a different
#   holder has it (`unlock <token>`), or the bound is reached (`bound-incr`);
#   2 usage error, unresolvable home, refused hostile input, or a
#   filesystem/lock error (fail closed).
#
# POSIX sh targeting the macOS + Linux support bar (bash 3.2 / BSD tooling), not
# strict POSIX: it deliberately uses `date +%s` plus mkdir/mktemp/awk, and it
# inherits lock-lib.sh's own dependencies (`ln -s`, `readlink`, `mv`, and a
# fractional `sleep`) through every verb that takes the lock. `readlink` is the
# sharp one, since acquires confirm with it and releases recognise their own
# with it; the library refuses at the first acquire when it is missing rather
# than reporting locks busy and leaking them. That refusal is at the lock, not
# here: `root`, `registry` and a tokenless `unlock` read no link target and keep
# working without it. No eval, no jq/fish/mise (REQ-K1.5). All input is treated
# as data. Pathname expansion is disabled (set -f): the script does no
# intentional globbing.
set -uf

LC_ALL=C
export LC_ALL
unset CDPATH

script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2

# The canonical echo-discipline sanitizer (doctrine/security-posture.md): every
# untrusted value (a caller's argv, a parsed manifest name) is stripped of C0/DEL
# before it reaches a diagnostic, so an embedded escape sequence can't drive the
# terminal or corrupt a log. Sourced as the sibling command scripts do
# (spec-validate.sh, spec-walkthrough.sh); a missing helper is a broken install.
# shellcheck source=scripts/echo-safety.sh
. "$script_dir/echo-safety.sh"

# The one advisory-lock primitive for the script layer (D-11). Sourced the same
# way, and a missing one is the same broken install.
# shellcheck source=scripts/lock-lib.sh
. "$script_dir/lock-lib.sh"

# The overlay identifier charset (REQ-E1.2, REQ-A1.8), matching
# resolve-overlay-root.sh: a kebab token, no uppercase, no traversal segments,
# no leading dash, at most 64 chars. Used for the plugin-namespace `name` that
# reaches a path.
valid_identifier() {
  vi_n=$1
  case $vi_n in
    "" | -* | *[!a-z0-9-]*) return 1 ;;
  esac
  [ "${#vi_n}" -le 64 ]
}

# The registry FIELD grammar for worker/scope identifiers (REQ-F1.1, REQ-A1.6):
# a conservative handle charset that excludes path separators (so a `.` or `..`
# dot-run is inert: with no slash it can never form a traversal path) and also
# rejects the bare `.`/`..` dot-runs outright (belt-and-suspenders: a `.`/`..`
# handle would still misdirect a per-worker path even without escaping), plus
# whitespace, tabs, newlines, and any control or shell-metacharacter — so a
# hostile field can neither escape a path nor tear the tab-delimited append-only
# record. Covers the backend worker handles the capability contract names
# (`window=<name>`, an agent id) and spec identifiers. Bounded to 128 chars.
valid_field() {
  vf_v=$1
  case $vf_v in
    "" | . | .. | *[!A-Za-z0-9._=@:-]*) return 1 ;;
  esac
  [ "${#vf_v}" -le 128 ]
}

# The OWNER-TOKEN grammar (REQ-D1.5, REQ-K1.4). The presence surface's tower
# identity is a session UUID or the composite `p<pid>.t<hash>.c<hash>`; both sit
# inside this conservative charset. The grammar is stated as a charset rather
# than as those two shapes so this store does not re-decide what a tower
# identity looks like — that is fleet-presence.sh's call — while still refusing
# whitespace, separators, control bytes, and a leading dash, none of which any
# identity shape produces and each of which would tear a record or misdirect a
# path built from it. Bounded to 128 chars, like every other field.
# `unknown-owner` is refused as a VALUE because it is the reader's classification
# for an absent one (fleet-status.sh). Sentinel and value namespaces have to be
# disjoint: if a caller could store the literal string, a forged record would be
# byte-identical to a genuinely unattributed one in the column a destructive verb
# reads, in both directions.
valid_owner() {
  vo_v=$1
  case $vo_v in
    "" | . | .. | unknown-owner | *[!A-Za-z0-9._-]*) return 1 ;;
    -*) return 1 ;;
  esac
  [ "${#vo_v}" -le 128 ]
}

# The BACKEND grammar: a kebab rung name, lowercase, no leading dash, ≤64. The
# rung SET is the capability contract's (doctrine/backend-capability-contract.md)
# and is deliberately not enumerated here — a store that hard-codes it makes
# adding a rung a two-file change and drifts the moment it is missed. What this
# grammar owes is containment: no separator, no metacharacter, no control byte.
valid_backend() {
  vb_v=$1
  case $vb_v in
    "" | -* | *[!a-z0-9-]*) return 1 ;;
  esac
  [ "${#vb_v}" -le 64 ]
}

# The STATE-DIRECTORY grammar (REQ-K1.4). A close verb matches processes against
# this path, so it must be absolute (a relative path means something different
# in every cwd a later reader has) and free of a `..` segment (which would let a
# record name a directory outside the tree it claims). Control bytes, tabs, and
# newlines are refused: they would tear the record or drive the terminal of
# whoever renders it.
# The bare `/` is refused too: a close verb matching processes against it would
# match the operator's whole session. This is a SYNTACTIC check — it does not
# canonicalize, so a path through a symlink still reads as contained here. A
# consumer that acts destructively on this column owes its own post-realpath
# containment check; the store's job is to keep a torn or traversing value out,
# not to vouch for where the path really points.
valid_state_dir() {
  vsd_v=$1
  case $vsd_v in
    / | */../* | */.. | ../*) return 1 ;;
    /*) ;;
    *) return 1 ;;
  esac
  [ "${#vsd_v}" -le 4096 ] || return 1
  # Any C0 control byte or DEL, stripped: if the value changes, it carried one.
  [ "$(printf '%s' "$vsd_v" | tr -d '\000-\037\177')" = "$vsd_v" ]
}

# The tmux token charset fleet-death-evidence.sh validates against (no `:` or
# `/`), so a handle this store accepts is one that predicate can consume.
valid_tmux_token() {
  vtt_v=$1
  case $vtt_v in
    "" | -* | *[!A-Za-z0-9._@%-]*) return 1 ;;
  esac
  [ "${#vtt_v}" -le 128 ]
}

# The DEATH-HANDLE grammar, mirroring fleet-presence.sh's `is_handle` plus the
# `none` arm. A pseudo-evidence class (`timeout`, `silence`, `heartbeat`) is not
# an unrecognized value to be stored and puzzled over later — the evidence
# predicate refuses it outright (REQ-A1.7), so the store refuses it too, and a
# record can never hand a reaper a basis its own predicate would reject.
valid_death_handle() {
  vdh_v=$1
  case $vdh_v in
    none) return 0 ;;
    "process "*)
      vdh_pid=${vdh_v#process }
      case $vdh_pid in
        "" | 0* | *[!0-9]*) return 1 ;;
      esac
      [ "${#vdh_pid}" -le 10 ]
      ;;
    "tmux-window "*)
      vdh_rest=${vdh_v#tmux-window }
      case $vdh_rest in
        *" "*) ;;
        *) return 1 ;;
      esac
      valid_tmux_token "${vdh_rest%% *}" && valid_tmux_token "${vdh_rest#* }"
      ;;
    *) return 1 ;;
  esac
}

# resolve_root — print the fleet home per the D-11 chain, or fail (exit 2) when
# no arm is derivable (a fleet with no durable home is an error for a writer,
# unlike an absent overlay layer which is a normal state). The result is used
# verbatim by callers; an override is trusted as given.
resolve_root() {
  # 1. Explicit override, trusted verbatim.
  if [ -n "${PLANWRIGHT_FLEET_STATE_DIR:-}" ]; then
    printf '%s\n' "$PLANWRIGHT_FLEET_STATE_DIR"
    return 0
  fi
  # 2. Plugin mode: the plugin-data dir IS the update-stable per-plugin
  #    namespace; the fleet home is its `fleet/` leaf.
  if [ -n "${CLAUDE_PLUGIN_DATA:-}" ]; then
    printf '%s\n' "${CLAUDE_PLUGIN_DATA%/}/fleet"
    return 0
  fi
  # 3. Writer mode: derive the namespace from the manifest `name`.
  rr_claude_dir=""
  if [ -n "${CLAUDE_DIR:-}" ]; then
    rr_claude_dir="$CLAUDE_DIR"
  elif [ -n "${HOME:-}" ]; then
    rr_claude_dir="$HOME/.claude"
  fi
  if [ -n "$rr_claude_dir" ]; then
    rr_manifest="$rr_claude_dir/planwright/plugin.json"
    if [ -r "$rr_manifest" ]; then
      # Read the TOP-LEVEL "name" string, tracking brace depth so a nested
      # object's name (e.g. author.name) is never mistaken for the plugin name.
      # Mirrors resolve-overlay-root.sh's dependency-free manifest read (no jq,
      # REQ-K1.5); assumes the key/value sit on one line and string values carry
      # no literal braces (true for this manifest; full JSON parse out of scope).
      rr_name=$(awk '
        {
          line = $0
          while (match(line, /[{}]|"name"[ \t]*:[ \t]*"[^"]*"/)) {
            tok = substr(line, RSTART, RLENGTH)
            if (tok == "{") depth++
            else if (tok == "}") depth--
            else if (depth == 1 && val == "") {
              val = tok
              sub(/^"name"[ \t]*:[ \t]*"/, "", val)
              sub(/".*$/, "", val)
            }
            line = substr(line, RSTART + RLENGTH)
          }
        }
        END { if (val != "") print val }
      ' "$rr_manifest")
      if [ -n "$rr_name" ]; then
        if valid_identifier "$rr_name"; then
          printf '%s\n' "${rr_claude_dir%/}/planwright/$rr_name/fleet"
          return 0
        fi
        # A name that fails the charset is NEVER interpolated into a path
        # (REQ-F1.1): warn and treat the writer arm as underivable.
        printf '%s\n' "fleet-state: plugin manifest name '$(sanitize_printable "$rr_name" "(unprintable name)")' is not a valid identifier; refusing to build a fleet path from it" >&2
      fi
    fi
  fi
  printf '%s\n' "fleet-state: cannot resolve a cross-spec fleet home — set \$PLANWRIGHT_FLEET_STATE_DIR (explicit override) or \$CLAUDE_PLUGIN_DATA (plugin mode), or ensure a readable plugin manifest at <claude-dir>/planwright/plugin.json (writer mode; claude-dir is \$CLAUDE_DIR else \$HOME/.claude)" >&2
  return 2
}

# spin_acquire <lockpath> — the internal consumers' acquire (`register`,
# `bound-incr`, `bound-decr`): wait out a live holder for the library's default
# budget, so a registry append or a check-and-increment is never dropped under
# contention. The exposed `lock` verb keeps the caller's-policy contract instead
# and does not come through here.
#
# An exhausted budget is reported as a real error rather than as busy, because
# every caller treats it as one: proceeding without the lock is the lost update
# the lock exists to prevent, so there is nothing for a caller to decide.
spin_acquire() {
  pw_lock_acquire "$1"
  sa_rc=$?
  [ "$sa_rc" = 0 ] && return 0
  if [ "$sa_rc" = 1 ]; then
    printf '%s\n' "fleet-state: gave up acquiring $1 after contention" >&2
  fi
  return 2
}

# atomic_write <file> <value> — replace <file>'s contents with <value> via a
# same-dir temp + rename, so a concurrent reader never sees a torn file.
atomic_write() {
  aw_file=$1
  aw_val=$2
  # dirname, not ${aw_file%/*}: the latter is the empty string for a single-
  # leading-slash target (`/concurrency` → ""), breaking the same-dir mktemp.
  aw_dir=$(dirname "$aw_file")
  aw_tmp=$(mktemp "$aw_dir/.tmp.XXXXXX") || return 1
  if ! printf '%s\n' "$aw_val" >"$aw_tmp"; then
    rm -f "$aw_tmp"
    return 1
  fi
  if ! mv -f "$aw_tmp" "$aw_file"; then
    rm -f "$aw_tmp"
    return 1
  fi
  return 0
}

# read_counter <file> — print the integer at <file>, or 0 when absent/malformed.
# A leading-zero value (`08`, `010`) is malformed too: this script only ever
# writes canonical decimals, so a leading zero means a tampered/corrupt file.
# Left through, it reaches `$(( ))` as OCTAL — `08` aborts the arithmetic
# ("value too great for base"), which under `set -u` kills bound-incr/-decr
# mid-critical-section and LEAKS the lock; `010` silently miscounts (octal 8).
# So `0?*` (a zero followed by any char — but not the lone legit `0`) joins the
# malformed arm and normalizes to 0, matching the function's stated contract.
read_counter() {
  rc_file=$1
  rc_v=$(cat "$rc_file" 2>/dev/null) || rc_v=""
  case $rc_v in
    "" | *[!0-9]* | 0?*) printf '0\n' ;;
    *) printf '%s\n' "$rc_v" ;;
  esac
}

# ---------------------------------------------------------------------------
# Command dispatch
# ---------------------------------------------------------------------------
cmd="${1:-}"
if [ -z "$cmd" ]; then
  echo "usage: fleet-state.sh root|lock|unlock|register|registry|bound-incr|bound-decr [args]" >&2
  exit 2
fi

case $cmd in
  root)
    resolve_root
    exit $?
    ;;
  lock | unlock | register | registry | bound-incr | bound-decr) ;;
  *)
    # Reject an unknown command HERE, before resolving/creating the fleet home,
    # so a typo is a clean usage error (exit 2) that never materializes any
    # fleet-state artifacts (fail-closed / data hygiene, REQ-A1.6). Without this
    # the unconditional mkdir below would create the fleet home on a typo.
    printf '%s\n' "fleet-state: unknown command '$(sanitize_printable "$cmd" "(unprintable command)")' (root|lock|unlock|register|registry|bound-incr|bound-decr)" >&2
    exit 2
    ;;
esac

# Every command below needs the resolved home to exist. cmd is now guaranteed to
# be one of the six above (unknown was rejected before this point).
root=$(resolve_root) || exit 2
# A home we create is owner-only from birth: `mkdir -p` alone takes the caller's
# umask, so a umask-002 host got 0775, and everything private underneath (the
# registry, the tower-comms surface) is only as private as the directory holding
# it. Consumers that verify their own surface refuse a widened parent, so the
# default has to be tight rather than merely documented. The umask is narrowed
# around the mkdir rather than chmod-ing after it: it is a builtin (so this
# still works where PATH carries no chmod), and it leaves no window in which the
# directory exists group-writable. A home that already exists is untouched —
# mkdir -p is a no-op on it, and its permissions are its owner's call, not ours
# to tighten underneath a deliberately shared one.
_prev_umask=$(umask)
umask 0077
_mkdir_rc=0
mkdir -p "$root" 2>/dev/null || _mkdir_rc=$?
umask "$_prev_umask"
if [ "$_mkdir_rc" != 0 ]; then
  printf '%s\n' "fleet-state: cannot create fleet home $root" >&2
  exit 2
fi
lock="$root/.fleet.lock"
registry="$root/registry"
counter="$root/concurrency"

# Release an internally-held lock on ANY exit path, including a signal
# (fleet-lifecycle-closure Task 3). Registration put the critical section on the
# INTERACTIVE dispatch path, where a Ctrl-C at the wrong instant would otherwise
# leave `.fleet.lock` standing and wedge every fleet writer behind it — and
# nothing breaks a detached hold on its own, so "until someone notices" is the
# whole duration. The library's own handlers are used rather than a local pair:
# this script has no other trap, and the release has to be armed BEFORE the
# first acquire, which is the one thing a caller can get wrong here.
#
# INT/TERM re-exit rather than returning, which is what the library's handlers
# do: a handler that returns would RESUME the interrupted critical section with
# the lock gone, which is the lost update the lock exists to prevent. SIGKILL
# stays unrecoverable — the process's locks die owner-less, and a tokenless
# `unlock` is what clears them.
pw_lock_trap_install

case $cmd in
  lock)
    # The exposed one-shot primitive: caller's-policy exit contract (0/1/2),
    # matching orchestrate-lock.sh, so a budget of one attempt and no waiting.
    # Consumers with a custom critical section acquire here and release with
    # `unlock`.
    #
    # DETACHED, because the hold outlives this process by design: the caller
    # releases from a LATER invocation, so there is no pid here whose absence
    # would prove the lock dead, and a liveness probe that guessed otherwise
    # would break a lock whose owner is mid-critical-section.
    pw_lock_acquire_detached "$lock" 1
    ta_rc=$?
    if [ "$ta_rc" = 0 ]; then
      # Disown before printing: this lock belongs to the CALLER's later
      # `unlock`, not to this process's EXIT handler. Disowning AFTER the
      # acquire rather than never adopting is deliberate — a signal before this
      # line releases the lock and exits non-zero, so a caller that never
      # learned it acquired is never left holding a leaked one.
      # shellcheck disable=SC2034 # lock-lib.sh's release path reads it, not this file
      PW_LOCK_HELD=''
      # The token is the whole point of the verb: it is what lets the caller's
      # release prove the lock is still its own.
      printf '%s\n' "$PW_LOCK_TOKEN"
    fi
    exit $ta_rc
    ;;

  unlock)
    # The external half of the exposed primitive, releasing a lock a PREVIOUS
    # process took via `lock`.
    unlock_token="${2:-}"
    if [ -n "$unlock_token" ]; then
      # Ownership-verified: the unlink happens only while the link is still
      # this token's, so a caller returning after its hold was cleared leaves
      # the CURRENT holder's lock alone instead of deleting it.
      pw_lock_release_token "$lock" "$unlock_token"
      ul_rc=$?
      case $ul_rc in
        0) exit 0 ;;
        1)
          # Not this token's, which is two situations. Already gone is this
          # verb's own success condition and has been all along (a caller that
          # cannot tell a double release from a first one would have to track
          # state this store does not keep). Someone else holding it is the
          # clobber the token exists to prevent, so nothing is removed and the
          # caller is told.
          if [ -e "$lock" ] || [ -L "$lock" ]; then
            printf '%s\n' "fleet-state: $lock is held by another token now; nothing was released" >&2
            exit 1
          fi
          exit 0
          ;;
        *)
          printf '%s\n' "fleet-state: could not release $lock (it is still present after the removal; check its type and the parent directory's permissions)" >&2
          exit 2
          ;;
      esac
    fi
    # No token: the unconditional clear. This is the operator's escape hatch —
    # a detached hold has no owner to probe, so nothing else recovers one whose
    # caller crashed — and it is the in-place upgrade path, because it also
    # takes a lock left as a DIRECTORY by the retired `mkdir` shape, which
    # `rm -f` alone refuses.
    if ! pw_lock_break_force "$lock"; then
      # What is known here is only that the path is still there. WHY is not: a
      # regular file the clear refuses to guess about, or an `rm` that failed on
      # a perfectly ordinary lock symlink because the parent is not writable.
      # The diagnostic reports the observable condition rather than naming a
      # shape this branch never checked, which would send the operator to
      # inspect the wrong thing.
      printf '%s\n' "fleet-state: could not release $lock (it is still present after the removal; check its type and the parent directory's permissions)" >&2
      exit 2
    fi
    exit 0
    ;;

  register)
    shift
    positional=0
    worker=""
    scope=""
    owner="-"
    backend="-"
    state_dir="-"
    death_handle="-"
    while [ "$#" -gt 0 ]; do
      case $1 in
        --owner | --backend | --state-dir | --death-handle)
          if [ "$#" -lt 2 ]; then
            printf '%s\n' "fleet-state: register: $1 needs a value" >&2
            exit 2
          fi
          case $1 in
            --owner) owner=$2 ;;
            --backend) backend=$2 ;;
            --state-dir) state_dir=$2 ;;
            --death-handle) death_handle=$2 ;;
          esac
          shift 2
          ;;
        --*)
          printf '%s\n' "fleet-state: register: unknown flag '$(sanitize_printable "$1" "(unprintable flag)")'" >&2
          exit 2
          ;;
        *)
          # Bind by POSITION COUNT, not by emptiness: an empty second argument
          # is a caller passing an unset variable, and letting the next token
          # slide into its slot would silently store a record under a scope the
          # caller never asked for instead of refusing.
          positional=$((positional + 1))
          case $positional in
            1) worker=$1 ;;
            2) scope=$1 ;;
            *)
              printf '%s\n' "fleet-state: register: unexpected argument" >&2
              exit 2
              ;;
          esac
          shift
          ;;
      esac
    done
    if [ "$positional" -ne 2 ] || [ -z "$worker" ] || [ -z "$scope" ]; then
      printf '%s\n' "usage: fleet-state.sh register <worker> <scope> [--owner <token>] [--backend <name>] [--state-dir <abs-dir>] [--death-handle <handle>]" >&2
      exit 2
    fi
    # Validate EVERY field before any write (REQ-F1.1, REQ-A1.6, REQ-K1.4): a
    # hostile identifier is refused and nothing is written. The `-` sentinel
    # passes each arm untouched because no grammar admits it, so "absent" needs
    # no separate flag to distinguish it from a value.
    if ! valid_field "$worker"; then
      printf '%s\n' "fleet-state: refusing malformed worker handle '$(sanitize_printable "$worker" "(unprintable worker)")' (must match ^[A-Za-z0-9._=@:-]{1,128}\$)" >&2
      exit 2
    fi
    if ! valid_field "$scope"; then
      printf '%s\n' "fleet-state: refusing malformed scope '$(sanitize_printable "$scope" "(unprintable scope)")' (must match ^[A-Za-z0-9._=@:-]{1,128}\$)" >&2
      exit 2
    fi
    if [ "$owner" != "-" ] && ! valid_owner "$owner"; then
      printf '%s\n' "fleet-state: refusing malformed owner token '$(sanitize_printable "$owner" "(unprintable owner)")' (must match ^[A-Za-z0-9._-]{1,128}\$, no leading dash)" >&2
      exit 2
    fi
    if [ "$backend" != "-" ] && ! valid_backend "$backend"; then
      printf '%s\n' "fleet-state: refusing malformed backend '$(sanitize_printable "$backend" "(unprintable backend)")' (must match ^[a-z0-9-]{1,64}\$, no leading dash)" >&2
      exit 2
    fi
    if [ "$state_dir" != "-" ] && ! valid_state_dir "$state_dir"; then
      printf '%s\n' "fleet-state: refusing malformed state directory '$(sanitize_printable "$state_dir" "(unprintable state dir)")' (must be an absolute path with no '..' segment and no control bytes)" >&2
      exit 2
    fi
    if [ "$death_handle" != "-" ] && ! valid_death_handle "$death_handle"; then
      printf '%s\n' "fleet-state: refusing malformed death handle '$(sanitize_printable "$death_handle" "(unprintable death handle)")' (must be 'none', 'process <pid>', or 'tmux-window <session> <window>')" >&2
      exit 2
    fi
    spin_acquire "$lock" || exit 2
    # Stamp the record's time UNDER the lock, so it reflects when the record is
    # committed, not when register was invoked. Append order then matches
    # timestamp order (monotonic non-decreasing): without this, a caller that
    # captured its timestamp early and then blocked on the lock could append an
    # earlier timestamp after a later one under contention. On a bad clock read,
    # release the lock before failing closed.
    now=$(date +%s)
    case $now in
      "" | *[!0-9]*)
        pw_lock_release "$lock"
        printf '%s\n' "fleet-state: could not read a numeric timestamp" >&2
        exit 2
        ;;
    esac
    rc=0
    # Copy-append-rename so a concurrent reader sees only a complete registry.
    reg_tmp=$(mktemp "$root/.registry.XXXXXX") || rc=2
    if [ "$rc" = 0 ]; then
      if [ -f "$registry" ]; then
        cat "$registry" >"$reg_tmp" || rc=2
      fi
    fi
    if [ "$rc" = 0 ]; then
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$now" "$worker" "$scope" \
        "$owner" "$backend" "$state_dir" "$death_handle" >>"$reg_tmp" || rc=2
    fi
    if [ "$rc" = 0 ]; then
      mv -f "$reg_tmp" "$registry" || rc=2
    fi
    [ "$rc" = 0 ] || rm -f "$reg_tmp" 2>/dev/null
    pw_lock_release "$lock"
    if [ "$rc" != 0 ]; then
      printf '%s\n' "fleet-state: failed to append the registry record" >&2
    fi
    exit "$rc"
    ;;

  registry)
    # Read a consistent snapshot: writers rename atomically, so a cat is never
    # torn (read-during-write safe). Absent registry prints nothing.
    if [ -f "$registry" ]; then
      cat "$registry"
    fi
    exit 0
    ;;

  bound-incr)
    max="${2:-}"
    case $max in
      "" | *[!0-9]*)
        printf '%s\n' "fleet-state: bound-incr needs a non-negative integer bound" >&2
        exit 2
        ;;
    esac
    spin_acquire "$lock" || exit 2
    cur=$(read_counter "$counter")
    if [ "$cur" -lt "$max" ]; then
      new=$((cur + 1))
      if atomic_write "$counter" "$new"; then
        pw_lock_release "$lock"
        printf '%s\n' "$new"
        exit 0
      fi
      pw_lock_release "$lock"
      printf '%s\n' "fleet-state: failed to write the fleet counter" >&2
      exit 2
    fi
    # At the bound: no slot granted (the caller must not dispatch another unit).
    pw_lock_release "$lock"
    printf '%s\n' "$cur"
    exit 1
    ;;

  bound-decr)
    spin_acquire "$lock" || exit 2
    cur=$(read_counter "$counter")
    if [ "$cur" -gt 0 ]; then
      new=$((cur - 1))
    else
      new=0
    fi
    if atomic_write "$counter" "$new"; then
      pw_lock_release "$lock"
      printf '%s\n' "$new"
      exit 0
    fi
    pw_lock_release "$lock"
    printf '%s\n' "fleet-state: failed to write the fleet counter" >&2
    exit 2
    ;;

  *)
    # Defensive fallback: unknown commands are already rejected before the fleet
    # home is created (first case above). This guards against the two command
    # lists drifting — a command added to the fall-through list but not handled
    # here fails loudly rather than silently no-op'ing.
    printf '%s\n' "fleet-state: unknown command '$(sanitize_printable "$cmd" "(unprintable command)")' (root|lock|unlock|register|registry|bound-incr|bound-decr)" >&2
    exit 2
    ;;
esac
