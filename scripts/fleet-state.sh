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
# THE NAMED PRIMITIVE (reshaped R1). Because the cross-spec store is read by the
# attention surface (Task 12) while the meta-tower's fleet-bound accounting
# (Task 6) writes it, this script provides a named cross-spec concurrency-control
# primitive — a fleet-level advisory lock (à la the sibling's orchestrate-lock.sh)
# at `<root>/.fleet.lock`, taken with an atomic mkdir and broken when stale. Its
# guarantee: concurrent registry writes are serialized (no torn record) and the
# fleet-bound check-and-increment cannot over-count (no two towers exceed the
# bound). `lock`/`unlock` expose the primitive for consumers with their own
# critical sections; `register`/`bound-incr`/`bound-decr` are the built-in
# consumers. The bound VALUE and policy are Task 6's; the atomic MECHANISM is
# here.
#
# RESERVATION vs SOURCE OF TRUTH. `bound-incr`/`bound-decr` are a same-instant
# RESERVATION primitive, not the authoritative fleet in-flight count. The
# authoritative count is the live git derivation the meta-tower selector
# (orchestrate-meta-select.sh) sums per step — level-triggered and self-healing,
# so it never leaks across a tower crash; that selector reads only the git truth,
# never this counter. This counter's role is to close the sub-second window
# between a meta step deciding and a subordinate tower materializing its
# branch/marker. It is NOT self-healing: a holder that crashes between
# `bound-incr` and `bound-decr` leaks its slot (same crash-recovery gap as the
# stale-lock break — a known limitation deferred to the lock-family owner-token
# redesign; tracked in specs/_observations, fleet-bound-slot-leak /
# shared-lock-stale-break-race). A consumer must not treat this counter as a
# durable occupancy tally; the git-derived count is what reconciles.
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
#   fleet-state.sh lock                       acquire the advisory lock (0 held,
#                                             1 a live holder has it, 2 error).
#   fleet-state.sh unlock                     release the lock (idempotent, 0).
#   fleet-state.sh register <worker> <scope> [--owner <token>]
#       [--backend <name>] [--state-dir <abs-dir>] [--death-handle <handle>]
#                                             append a dispatch record.
#   fleet-state.sh registry                   print the registry records.
#   fleet-state.sh bound-incr <max>           check-and-increment the fleet
#                                             counter under the bound (0 granted
#                                             + new count on stdout, 1 at bound).
#   fleet-state.sh bound-decr                 release one slot (floors at 0).
#
# Exit codes: 0 success/granted; 1 lock busy (one-shot `lock`) or bound reached
#   (`bound-incr`); 2 usage error, unresolvable home, refused hostile input, or a
#   filesystem/lock error (fail closed).
#
# POSIX sh targeting the macOS + Linux support bar (bash 3.2 / BSD tooling), not
# strict POSIX: it deliberately uses a few widely-portable extensions — `date
# +%s`, `find -mmin`, and a fractional `sleep` (each documented at its use site)
# — plus mkdir/mktemp/awk. No eval, no jq/fish/mise (REQ-K1.5). All input is
# treated as data. Pathname expansion is disabled (set -f): the script does no
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

# stale_lock_threshold in minutes (the sibling advisory-lock knob). Resolved via
# config-get.sh with PLANWRIGHT_REPO_ROOT pinned to the fleet home ($root, which
# carries no .claude/ overlay of its own), which NEUTRALIZES the CWD's git-derived
# repo-tracked / machine-local layers. This matters because the fleet lock is
# cross-spec: without the pin the stale-break threshold would vary by whichever
# repo a tower happens to run from (config-get resolves those layers from the
# caller's cwd git toplevel), so two towers on the SAME fleet lock could disagree
# on staleness — one even disabling crash recovery under a pathological repo-local
# override. The CWD-independent layers still apply: the tracked default, the
# per-operator adopter layer, and an EXPLICIT PLANWRIGHT_LOCAL_CONFIG override (a
# deliberate, non-cwd-derived knob). An absent key or broken read falls back to
# 15m. config-get's stderr is intentionally NOT suppressed (matching the sibling
# orchestrate-lock.sh): it is silent on a found/absent key, and the one thing it
# emits — the broken-install diagnostic when the tracked defaults are missing or
# unreadable — must surface for the operator, not be swallowed into a silent 15m
# fallback. stderr does not affect the numeric stdout capture below.
fleet_stale_min() {
  fsm_v=15
  fsm_read=$(PLANWRIGHT_REPO_ROOT="$root" "$script_dir/config-get.sh" stale_lock_threshold) || fsm_read=""
  fsm_read=${fsm_read%m}
  case $fsm_read in
    "") ;;
    *[!0-9]*) ;;
    *) fsm_v=$fsm_read ;;
  esac
  printf '%s\n' "$fsm_v"
}

# mkdir_failure_kind <lockdir> — classify a failed `mkdir <lockdir>` when the
# lock dir does NOT exist afterwards. Two causes are indistinguishable from the
# mkdir exit alone: a REAL error (the parent is missing or unwritable) versus a
# benign RACE (a live holder released the lock in the window between our mkdir
# attempt and this check, so the dir it held is now gone). Probe the parent's
# writability to tell them apart: a writable, existing parent means the failure
# was transient contention the caller should retry (prints "busy"); otherwise it
# is a real filesystem error (prints "error"). This matters because the lock is
# spun under contention with frequent releases — misreading the race as fatal
# drops the caller's update (a lost registry write / a skipped increment).
mkdir_failure_kind() {
  # dirname (already a dependency, see script_dir above) rather than ${1%/*}:
  # the in-shell trim yields the empty string for a single-leading-slash path
  # (`/.fleet.lock` → ""), which would misclassify the probe; dirname is correct
  # for every path shape.
  mfk_parent=$(dirname "$1")
  if [ -d "$mfk_parent" ] && [ -w "$mfk_parent" ]; then
    printf 'busy\n'
  else
    printf 'error\n'
  fi
}

# try_acquire <lockdir> — one atomic mkdir with a stale-break retry, matching
# orchestrate-lock.sh. Exit 0 held, 1 a live holder has it (or a transient
# create race the caller should retry), 2 a real error (parent unwritable /
# filesystem fault — never masked as a clean "busy").
try_acquire() {
  ta_lock=$1
  if mkdir "$ta_lock" 2>/dev/null; then
    return 0
  fi
  if [ ! -d "$ta_lock" ]; then
    if [ "$(mkdir_failure_kind "$ta_lock")" = busy ]; then
      return 1
    fi
    printf '%s\n' "fleet-state: cannot create $ta_lock (home unwritable or filesystem error)" >&2
    return 2
  fi
  ta_min=$(fleet_stale_min)
  if [ -n "$(find "$ta_lock" -maxdepth 0 -mmin +"$ta_min" 2>/dev/null)" ]; then
    # Break a stale lock (a holder that crashed >stale_lock_threshold ago and
    # never released) and re-acquire, byte-for-byte as the sibling
    # orchestrate-lock.sh does. KNOWN LIMITATION (shared with that sibling; see
    # the observation logged for orchestration-fleet Task 9): this
    # check-then-remove is not atomic, so if ≥2 towers race the break of the
    # SAME genuinely-stale lock at the same instant, one can remove/replace the
    # other's freshly-created lock and both mkdir-succeed — two holders on the
    # crash-recovery path only. Closing it correctly needs a different lock
    # discipline (owner token + ownership re-verified across the critical
    # section) applied to the whole planwright lock family, which is a design
    # decision left to a follow-up rather than a unilateral divergence here. The
    # NORMAL contention path (no stale lock) is fully serialized and is what the
    # register/bound-incr guarantees rely on; the crash-recovery window requires
    # a SIGKILL at the microsecond a tower holds this ms-long lock plus a
    # simultaneous multi-tower break, so the residual is narrow.
    rm -rf "$ta_lock"
    if mkdir "$ta_lock" 2>/dev/null; then
      return 0
    fi
    if [ ! -d "$ta_lock" ]; then
      if [ "$(mkdir_failure_kind "$ta_lock")" = busy ]; then
        return 1
      fi
      printf '%s\n' "fleet-state: cannot create $ta_lock after stale break (home unwritable or filesystem error)" >&2
      return 2
    fi
    return 1
  fi
  return 1
}

# spin_acquire <lockdir> — retry try_acquire until held, for a bounded budget,
# so a check-and-increment or a registry append is never dropped under
# contention (the one-shot `lock` command keeps the caller's-policy contract; an
# internal consumer must not lose its update). A real error (rc 2) aborts at
# once; only a live-holder busy (rc 1) is retried. Exhausting the budget fails
# closed (rc 2) rather than proceeding without the lock.
#
# The 20ms backoff uses a sub-second `sleep`, which is a BSD/GNU extension, not
# strict POSIX (POSIX `sleep` takes integer seconds). This is deliberate and in
# scope: macOS and Linux — where both `sleep 0.02` and the already-relied-on
# `date +%s` work — are planwright's support bar; a fractional-second backoff is
# what keeps brief lock contention cheap (20ms, not a full second).
spin_acquire() {
  sa_lock=$1
  sa_tries=0
  while [ "$sa_tries" -lt 1000 ]; do
    try_acquire "$sa_lock"
    sa_rc=$?
    case $sa_rc in
      0)
        # Record ownership so the EXIT trap releases what THIS process holds,
        # and only that. try_acquire is deliberately not the place for it: the
        # exposed one-shot `lock` command uses it to hand the lock to a caller
        # who releases it in a later process.
        HOLD_LOCK=1
        return 0
        ;;
      2) return 2 ;;
    esac
    sa_tries=$((sa_tries + 1))
    sleep 0.02
  done
  printf '%s\n' "fleet-state: gave up acquiring $sa_lock after contention" >&2
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
if ! mkdir -p "$root" 2>/dev/null; then
  printf '%s\n' "fleet-state: cannot create fleet home $root" >&2
  exit 2
fi
lock="$root/.fleet.lock"
registry="$root/registry"
counter="$root/concurrency"

# Release an internally-held lock on ANY exit path, including a signal
# (fleet-lifecycle-closure Task 3). The consumers that take this lock from
# outside — fleet-attention.sh, fleet-throttle.sh — have carried this discipline
# all along; this script did not, which was survivable while `register` had no
# caller and `bound-incr`/`bound-decr` were sub-millisecond machine-to-machine
# calls. Registration put the critical section on the INTERACTIVE dispatch path,
# where a Ctrl-C at the wrong instant would leave `.fleet.lock` standing until
# the stale-break threshold and wedge every fleet writer behind it for that whole
# window. HOLD_LOCK is set only while this process owns the lock, so the handler
# can never rmdir a lock someone else holds.
#
# INT/TERM re-exit rather than returning: a bare `trap release_lock INT` would
# run the handler and then RESUME the interrupted critical section with the lock
# gone, which is the lost update the lock exists to prevent. Byte-for-byte the
# sibling discipline in fleet-attention.sh. SIGKILL stays unrecoverable and falls
# to the stale break, as it does everywhere else in the lock family.
HOLD_LOCK=0
release_lock() {
  if [ "$HOLD_LOCK" = 1 ]; then
    HOLD_LOCK=0
    rmdir "$lock" 2>/dev/null || true
  fi
}
trap 'release_lock' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

case $cmd in
  lock)
    # The exposed one-shot primitive: caller's-policy exit contract (0/1/2),
    # matching orchestrate-lock.sh. Consumers with a custom critical section
    # acquire here and release with `unlock`.
    try_acquire "$lock"
    exit $?
    ;;

  unlock)
    # Unconditional, NOT release_lock: this is the external half of the exposed
    # primitive, releasing a lock a previous process took via `lock`. HOLD_LOCK
    # is about what THIS process holds and is always 0 here.
    rmdir "$lock" 2>/dev/null || true
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
        release_lock
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
    release_lock
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
        release_lock
        printf '%s\n' "$new"
        exit 0
      fi
      release_lock
      printf '%s\n' "fleet-state: failed to write the fleet counter" >&2
      exit 2
    fi
    # At the bound: no slot granted (the caller must not dispatch another unit).
    release_lock
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
      release_lock
      printf '%s\n' "$new"
      exit 0
    fi
    release_lock
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
