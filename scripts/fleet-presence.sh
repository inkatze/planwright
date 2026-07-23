#!/bin/sh
# fleet-presence.sh — the cross-tower presence signal: publish, discover,
# liveness-classify, GC, and fence-owner attribution
# (concurrent-orchestrator-coordination Task 2: D-2 · REQ-A1.1–REQ-A1.7).
#
# WHAT THIS IS (D-2, D-11). Awareness only, never correctness: the dispatch-
# exclusion object is the per-unit fence ref on `origin` (D-8), so nothing on
# this surface can free a fenced unit or cause a double dispatch. Presence
# exists so a tower (a) never assumes solitude and (b) can attribute an
# orphan fence ref to its owner through the record's currently-fenced
# unit-ids field (REQ-C1.3).
#
# THE SURFACE. One file per tower — never a shared registry — at a fixed
# machine-local path outside every checkout, shared by all co-located clones
# (single-host scope). It lives under the cross-spec fleet home
# (fleet-state.sh root; PLANWRIGHT_FLEET_STATE_DIR is the operator/test
# override), partitioned per repository:
#   <home>/presence/<repo-id>/<tower-id>   the records (surface, 0700)
#   <home>/presence.sentinel               host persistence sentinel
#   <home>/presence.sentinels/<repo-id>    per-repo persistence sentinels
#   <home>/presence.cadence/<...>          per-tower discovery-scan stamps
# The sentinels sit OUTSIDE the surface so deleting the surface cannot also
# delete the proof it once existed: sentinel-present + directory-gone is a
# VANISHED surface and fails closed (never read as first-run solitude), while
# no-sentinel + no-directory is the healthy first-run bootstrap (REQ-A1.5).
# Sentinels are written BEFORE their directory is created, and a sentinel
# write failure itself fails closed. The 0700 mode IS the same-operator trust
# enforcement (REQ-A1.4): directories are created with an atomic
# mode-explicit mkdir (a concurrent-bootstrap EEXIST is success), and a
# pre-existing over-broad surface is REFUSED, never chmod-narrowed and
# reused (verify-or-refuse).
#
# THE RECORD. A single line, ten tab-separated fields, at most 8191 bytes
# plus the newline (the writer refuses an over-cap record; readers classify
# an over-cap file malformed), written atomically (mktemp in the
# sub-surface, then rename) so a reader never sees a torn record:
#   1 schema tag        pw-presence-v1
#   2 repo id           16 lowercase hex — origin-anchored (below)
#   3 tower identity    the record's key and filename (REQ-A1.7)
#   4 checkout path     absolute, control-free
#   5 specs             comma-separated spec ids, or `-`
#   6 fenced unit-ids   comma-separated <spec>/<unit-id>, or `-` — the
#                       strand-attribution field, refreshed each heartbeat
#   7 start epoch       preserved across heartbeat re-publishes
#   8 beat epoch        stamped at each publish
#   9 death handle      `process <pid>` or `tmux-window <session> <window>`
#                       — exactly the two fleet-death-evidence.sh forms; a
#                       tower under tmux passes the reuse-resistant
#                       tmux-window flags, bare process <pid> is the
#                       documented degraded fallback (REQ-A1.2, REQ-A1.3)
#  10 meta marker       true|false — the record's OWN validated field,
#                       stamped from the tower's --meta mode (never read
#                       from the orthogonal recovery-mode marker store)
#
# REPO IDENTITY (REQ-A1.2). Derived from the normalized `origin` remote URL
# (trailing slashes and one `.git` stripped) hashed via `git hash-object`,
# truncated to 16 hex — identical across separate clones of one repository
# and never the checkout path (which would split genuine peers). Documented
# constraint: clones are assumed to share one origin URL FORM; mixed
# ssh/https forms of one repo derive different ids and split the peer set
# (awareness-only, never a safety effect). No `origin` remote is the genuine
# solo posture: exit 5, no surface use; a non-repository checkout is a
# refused misconfiguration (exit 2), never solo.
#
# TOWER IDENTITY (REQ-A1.7). The session id (UUID) where present, validated
# against the UUID grammar; else the composite p<pid>.t<start-time-hash>.
# c<checkout-path-hash> — never the bare pid (reuse-prone) nor the checkout
# path alone (two towers on one checkout would collide). The start time is a
# targeted per-pid `ps -p <pid> -o lstart=` query, never a process-listing
# scan.
#
# DISCOVERY (REQ-A1.1, REQ-A1.3, REQ-A1.6). Scans only the current repo-id
# sub-surface (each record's repo id re-verified as a defensive cross-check),
# excludes the tower's own record by identity, and classifies each peer
# through fleet-death-evidence.sh — tri-state: alive / positively-dead /
# unknown, where ONLY positively-dead permits GC (unknown and a merely stale
# heartbeat are not-dead; staleness is a hint, not a death proof). Verdicts
# are memoized per pass (≤1 predicate subprocess per handle per pass) and
# the scan runs on a capped cadence (--min-interval; a capped pass prints
# `cadence-capped` and nothing else). A positively-dead record is GC'd under
# a best-effort re-read-and-skip guard: the file is re-read immediately
# before the unlink and the delete is skipped unless the re-read matches the
# classified dead record byte-for-byte within the bounded 8 KiB read window
# (both reads share the record-cap bound). No lock is taken — a benign
# TOCTOU remains, and a rare racing delete of a dead-then-restarted tower's
# fresh record self-heals on its next heartbeat re-publish (awareness-only,
# D-13). Malformed, truncated, or schema-skewed records are peers that exist
# but whose details are unreadable: surfaced with an error, assume-live,
# never GC'd on a guess, never read as "no such peer" (scoped to entries the
# scan can list — names a conforming publisher can create; the 0700 surface
# is same-operator trust, so a dotfile or newline-bearing name planted there
# by hand sits outside this guarantee). There is no claim record
# and no parking sub-surface for unparseable records here — the only
# correctness object is the fence ref, which has no schema to skew.
#
# Usage (every command except `surface` needs an identity: --session-id, or
# --pid for the composite; publish additionally needs a death handle — the
# tmux pair when under tmux (preferred), else --pid doubles as the handle,
# so a tmux-only publish still needs --session-id or --pid for identity.
# Publish and discover must be invoked with the SAME identity flags, or the
# discover identity will not match the published record and self-exclusion
# fails — the tower would count itself as a peer):
#   fleet-presence.sh publish  --checkout <dir> (--session-id <uuid> |
#       --pid <pid>) [--tmux-session <name> --tmux-window <name>]
#       [--specs <csv>] [--fenced <csv>] [--meta]
#   fleet-presence.sh discover --checkout <dir> (--session-id <uuid> |
#       --pid <pid>) [--min-interval <sec>]   (default 30; 0 disables the cap)
#   fleet-presence.sh owner    --checkout <dir> (--session-id <uuid> |
#       --pid <pid>) <spec>/<unit-id>
#   fleet-presence.sh identity --checkout <dir> (--session-id <uuid> | --pid <pid>)
#   fleet-presence.sh surface  --checkout <dir>
#
# discover output (tab-separated):
#   peer <tower-id> <live|unknown> <checkout> <specs> <fenced> <meta>
#   peer-unreadable <name> <malformed|schema-skew|unreadable>
#   foreign-record <name> <repo-id>    (wrong-repo record: surfaced, excluded)
#   gc <tower-id> | gc-skip <tower-id> | gc-fail <tower-id> | cadence-capped
#   summary peers=<n> sole-tower=<yes|no>     (n counts live + unknown +
#       unreadable + gc-skip: anything not positively dead argues against
#       solitude; foreign records and gc/gc-fail outcomes do not)
#
# owner output: `owner <tower-id>` from LIVE records only, else
# `unknown-owner` (REQ-C1.3; an unknown-liveness holder surfaces through the
# Task 4 strand path, and the durable-sink wiring for unclassifiable
# awareness anomalies (REQ-C1.7) lands with Task 4 — surfaced on stderr
# here). The querying tower's own record is identity-excluded from the scan,
# so a tower asking about a fence it itself holds gets `unknown-owner`.
#
# Exit codes:
#   0  success (incl. healthy-empty and cadence-capped)
#   2  usage / refused hostile input / not-a-repository / write failure /
#      unresolvable identity (e.g. --pid with no queryable start time)
#      (fail closed)
#   3  unknown peer status: vanished, unreadable, or obstructed surface —
#      awareness and strand-attribution degrade for the step while dispatch
#      proceeds (D-10; the origin fence, not this surface, is the floor)
#   4  security refusal: over-broad, ACL-bearing, mis-owned, or
#      symlink-tampered surface or sentinel (verify-or-refuse, REQ-A1.4)
#   5  no origin remote — the genuine solo posture
#
# POSIX sh on the macOS + Linux support bar (bash 3.2 / BSD tooling). All
# input is data; no eval (REQ-K1.5). Pathname expansion is disabled (set -f).
set -uf

LC_ALL=C
export LC_ALL
unset CDPATH

script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2

# shellcheck source=scripts/echo-safety.sh
. "$script_dir/echo-safety.sh"

# Temp hygiene on ANY exit, signals included (the fleet-attention.sh trap
# discipline the sibling fleet scripts share): a SIGINT/SIGTERM between a
# mktemp and its rename must not leak `.pub.*` / `.memo.*` / `.stamp.*`
# files — a leaked publish temp is a dotfile the discovery scan never
# lists, so it would otherwise accumulate invisibly, forever.
pub_tmp=""
memo=""
stamp_tmp=""
trap '[ -z "$pub_tmp" ] || rm -f "$pub_tmp"; [ -z "$memo" ] || rm -f "$memo"; [ -z "$stamp_tmp" ] || rm -f "$stamp_tmp"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

usage() {
  cat >&2 <<'USAGE'
usage: fleet-presence.sh publish  --checkout <dir> (--session-id <uuid> | --pid <pid>) [--tmux-session <name> --tmux-window <name>] [--specs <csv>] [--fenced <csv>] [--meta]
       fleet-presence.sh discover --checkout <dir> (--session-id <uuid> | --pid <pid>) [--min-interval <sec>]
       fleet-presence.sh owner    --checkout <dir> (--session-id <uuid> | --pid <pid>) <spec>/<unit-id>
       fleet-presence.sh identity --checkout <dir> (--session-id <uuid> | --pid <pid>)
       fleet-presence.sh surface  --checkout <dir>
(publish needs a death handle: the tmux pair, or --pid; flags irrelevant to a subcommand are refused)
USAGE
}

err() {
  echo "fleet-presence: $1" >&2
}

# --- grammars (validated BEFORE any path or command use, REQ-D1.5) ---------

# The session-id UUID shape (8-4-4-4-12 hex). The glob pins length 36 and the
# four dash positions, but `?` also admits `-`; the residue check requires
# exactly 32 hex characters, so a dash-heavy non-UUID is refused — the same
# charset + 32-non-dash residue discipline the sibling marker and signpost
# grammars enforce.
is_uuid() {
  [ "${#1}" -eq 36 ] || return 1
  case "$1" in
    ????????-????-????-????-????????????) ;;
    *) return 1 ;;
  esac
  iu_hex=$(printf '%s' "$1" | tr -d -- '-')
  [ "${#iu_hex}" -eq 32 ] || return 1
  case "$iu_hex" in
    *[!0-9a-fA-F]*) return 1 ;;
  esac
  return 0
}

is_pid() {
  case "$1" in
    "" | *[!0-9]* | 0*) return 1 ;;
  esac
  [ "${#1}" -le 10 ]
}

is_spec_id() {
  case "$1" in
    "" | -* | *[!a-z0-9-]*) return 1 ;;
  esac
  [ "${#1}" -le 64 ]
}

is_unit_id() {
  printf '%s' "$1" | grep -Eq '^[0-9]+(\.[0-9]+)?(-[0-9]+(\.[0-9]+)?)?$'
}

# <spec>/<unit-id> — exactly one slash, both halves on-grammar.
is_unit_ref() {
  case "$1" in
    */*/*) return 1 ;;
    */*) ;;
    *) return 1 ;;
  esac
  is_spec_id "${1%/*}" && is_unit_id "${1##*/}"
}

# The fleet-death-evidence tmux-token charset (no `:` or `/`).
is_tmux_token() {
  case "$1" in
    "" | -* | *[!A-Za-z0-9_@%.-]*) return 1 ;;
  esac
  [ "${#1}" -le 128 ]
}

is_epoch() {
  case "$1" in
    "" | *[!0-9]*) return 1 ;;
  esac
  [ "${#1}" -le 12 ]
}

is_repo_id() {
  [ "${#1}" -eq 16 ] || return 1
  case "$1" in
    *[!0-9a-f]*) return 1 ;;
  esac
  return 0
}

# Control-free (C0 + DEL): a value that sanitizes to itself carries none.
is_control_free() {
  [ "$(printf '%s' "$1" | tr -d '\000-\037\177')" = "$1" ]
}

# csv of spec ids / unit refs, or the `-` placeholder.
is_csv_of() {
  icf_pred=$1
  icf_val=$2
  [ "$icf_val" = "-" ] && return 0
  case "$icf_val" in
    "" | ,* | *, | *,,*) return 1 ;;
  esac
  icf_ifs=$IFS
  IFS=,
  # shellcheck disable=SC2086
  set -- $icf_val
  IFS=$icf_ifs
  for icf_tok in "$@"; do
    "$icf_pred" "$icf_tok" || return 1
  done
  return 0
}

is_handle() {
  case "$1" in
    "process "*)
      is_pid "${1#process }"
      ;;
    "tmux-window "*)
      ih_rest=${1#tmux-window }
      case "$ih_rest" in
        *" "*) ;;
        *) return 1 ;;
      esac
      is_tmux_token "${ih_rest%% *}" && is_tmux_token "${ih_rest#* }"
      ;;
    *) return 1 ;;
  esac
}

# Tower identity: a UUID, or the composite p<pid>.t<hash>.c<hash>.
is_tower_id() {
  if is_uuid "$1"; then
    return 0
  fi
  printf '%s' "$1" | grep -Eq '^p[0-9]{1,10}\.t[0-9]+\.c[0-9]+$'
}

# --- argument parsing ------------------------------------------------------

cmd="${1:-}"
case "$cmd" in
  publish | discover | owner | identity | surface) ;;
  *)
    usage
    exit 2
    ;;
esac
shift

checkout=""
pid=""
session_id=""
specs="-"
fenced="-"
tmux_session=""
tmux_window=""
meta=false
min_interval=30
unit_ref=""

# Strict per-command grammar: a flag irrelevant to the subcommand is a usage
# error, never a silent no-op (a `publish --min-interval` or `discover
# --fenced` that validated-then-ignored its value would mask operator error;
# the sibling marker script's per-command surplus-arg refusal is the model).
refuse_for() {
  case " $1 " in
    *" $cmd "*) ;;
    *)
      usage
      exit 2
      ;;
  esac
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --checkout)
      checkout="${2:-}"
      shift 2 || {
        usage
        exit 2
      }
      ;;
    --pid)
      refuse_for "publish discover owner identity"
      pid="${2:-}"
      shift 2 || {
        usage
        exit 2
      }
      ;;
    --session-id)
      refuse_for "publish discover owner identity"
      session_id="${2:-}"
      shift 2 || {
        usage
        exit 2
      }
      ;;
    --specs)
      refuse_for "publish"
      specs="${2:-}"
      shift 2 || {
        usage
        exit 2
      }
      ;;
    --fenced)
      refuse_for "publish"
      fenced="${2:-}"
      shift 2 || {
        usage
        exit 2
      }
      ;;
    --tmux-session)
      refuse_for "publish"
      tmux_session="${2:-}"
      shift 2 || {
        usage
        exit 2
      }
      ;;
    --tmux-window)
      refuse_for "publish"
      tmux_window="${2:-}"
      shift 2 || {
        usage
        exit 2
      }
      ;;
    --meta)
      refuse_for "publish"
      meta=true
      shift
      ;;
    --min-interval)
      refuse_for "discover"
      min_interval="${2:-}"
      shift 2 || {
        usage
        exit 2
      }
      ;;
    --*)
      usage
      exit 2
      ;;
    *)
      if [ "$cmd" = owner ] && [ -z "$unit_ref" ]; then
        unit_ref=$1
        shift
      else
        usage
        exit 2
      fi
      ;;
  esac
done

# --- input validation ------------------------------------------------------

case "$checkout" in
  /*) ;;
  *)
    err "refusing checkout: an existing absolute directory is required"
    exit 2
    ;;
esac
if ! is_control_free "$checkout" || [ ! -d "$checkout" ]; then
  err "refusing checkout: an existing absolute directory is required"
  exit 2
fi
checkout=$(cd "$checkout" && pwd -P) || {
  err "refusing checkout: cannot canonicalize $(sanitize_printable "$checkout" "(unprintable)")"
  exit 2
}
# Re-validate after canonicalization: a symlinked component can resolve to a
# physical path carrying a control byte, and a tab in record field 4 would
# skew every peer's field count (the writer-side mirror of the reader guard).
if ! is_control_free "$checkout"; then
  err "refusing checkout: the canonical path carries control bytes"
  exit 2
fi

if [ -n "$session_id" ] && ! is_uuid "$session_id"; then
  err "refusing malformed session id (a UUID, or omit the flag)"
  exit 2
fi
if [ -n "$pid" ] && ! is_pid "$pid"; then
  err "refusing malformed pid (a positive integer, no leading zero)"
  exit 2
fi
if ! is_csv_of is_spec_id "$specs"; then
  err "refusing malformed --specs (comma-separated spec ids, or omit)"
  exit 2
fi
if ! is_csv_of is_unit_ref "$fenced"; then
  err "refusing malformed --fenced (comma-separated <spec>/<unit-id>, or omit)"
  exit 2
fi
if [ -n "$tmux_session" ] || [ -n "$tmux_window" ]; then
  if ! is_tmux_token "$tmux_session" || ! is_tmux_token "$tmux_window"; then
    err "refusing malformed tmux session/window token (both required together, death-evidence charset)"
    exit 2
  fi
fi
if ! is_epoch "$min_interval"; then
  err "refusing malformed --min-interval (seconds)"
  exit 2
fi
if [ "$cmd" = owner ]; then
  if [ -z "$unit_ref" ] || ! is_unit_ref "$unit_ref"; then
    err "refusing malformed unit ref (owner takes one <spec>/<unit-id>)"
    exit 2
  fi
fi

# --- repo identity (origin-anchored, REQ-A1.2) -----------------------------

# A non-repository checkout is a misconfiguration (exit 2), never the genuine
# solo posture: exit 5 is reserved for a real repository with no origin remote
# (REQ-A1.2), so a typo'd path can never silently authorize solo behavior.
if ! git -C "$checkout" rev-parse --git-dir >/dev/null 2>&1; then
  err "refusing checkout: $(sanitize_printable "$checkout" "(unprintable)") is not a git repository"
  exit 2
fi
origin_url=$(git -C "$checkout" config --get remote.origin.url 2>/dev/null) || {
  err "no origin remote on $(sanitize_printable "$checkout" "(unprintable)") — genuine solo posture; the presence surface is not used (REQ-A1.2)"
  exit 5
}
# Minimal, deterministic normalization: strip trailing slashes and one `.git`.
# Clones of one repository are assumed to share one origin URL FORM (the
# same-operator norm); mixed ssh/https forms of one repo split the peer set —
# an awareness-only degradation, documented, never a safety effect.
while :; do
  case "$origin_url" in
    */) origin_url=${origin_url%/} ;;
    *) break ;;
  esac
done
origin_url=${origin_url%.git}
# An origin URL that is (or normalizes to) empty cannot anchor a repository
# identity: hashing the empty string would converge every such repo on one
# shared sub-surface. Treat it as the no-usable-origin solo posture (REQ-A1.2).
if [ -z "$origin_url" ]; then
  err "origin URL on $(sanitize_printable "$checkout" "(unprintable)") is (or normalizes to) empty — genuine solo posture; the presence surface is not used (REQ-A1.2)"
  exit 5
fi
repo_id=$(printf '%s' "$origin_url" | git hash-object --stdin 2>/dev/null | cut -c1-16) || repo_id=""
if ! is_repo_id "$repo_id"; then
  err "could not derive a repository id from the origin URL (git hash-object failed)"
  exit 2
fi

# --- surface layout --------------------------------------------------------

home=$("$script_dir/fleet-state.sh" root) || {
  err "cannot resolve the fleet home (fleet-state.sh root failed)"
  exit 2
}
# `fleet-state.sh root` only resolves the path; on a genuinely fresh host no
# fleet command has materialized it yet, and first-run bootstrap must succeed
# there (REQ-A1.5). Created 0700 when we create it; an existing home's own
# mode is fleet-state.sh's concern, not re-litigated here.
if [ ! -d "$home" ]; then
  mkdir -p "$home" 2>/dev/null || true
  chmod 0700 "$home" 2>/dev/null || true
fi
if [ ! -d "$home" ]; then
  err "cannot create the fleet home $home — failing closed; fix its parent's writability and retry"
  exit 2
fi
# Hoisted once: the ownership discriminant every check_private call compares
# against. An unresolvable uid fails closed (the trust gate needs it).
my_uid=$(id -u) || {
  err "cannot resolve the current uid (id -u failed) — failing closed"
  exit 2
}
surface_root="$home/presence"
host_sentinel="$home/presence.sentinel"
sentinel_dir="$home/presence.sentinels"
cadence_dir="$home/presence.cadence"
sub="$surface_root/$repo_id"
repo_sentinel="$sentinel_dir/$repo_id"

if [ "$cmd" = surface ]; then
  printf '%s\n' "$sub"
  exit 0
fi

# check_private <dir> — the verify-or-refuse gate (REQ-A1.4). Refused, never
# chmod-narrowed or reused on a guess: any group/other access bit; a `+`
# mode suffix (an ACL is present — on macOS NFSv4 ACLs do NOT surface in the
# mode bits, so an ACL-bearing dir is unverifiable and therefore refused;
# `@` xattrs and `.` SELinux-context suffixes stay accepted); a non-directory
# (a symlinked surface lists as `l…` and is refused); and a directory owned
# by a different uid (an attacker-planted 0700 dir must be refused
# explicitly, not fail incidentally later). A dir that vanished between
# create and check is the unknown-peer-status posture (exit 3), not a
# security refusal.
check_private() {
  cp_dir=$1
  # ls -ld[n] is the portable mode/owner read (stat's flags differ across
  # BSD/GNU); only the mode and numeric-uid columns are parsed, never a
  # filename (SC2012 n/a).
  # shellcheck disable=SC2012
  cp_line=$(ls -ldn "$cp_dir" 2>/dev/null) || cp_line=""
  if [ -z "$cp_line" ]; then
    err "unknown peer status: coordination surface $cp_dir disappeared while being verified — failing closed (REQ-A1.5)"
    exit 3
  fi
  # Word-split the listing line (set -f is on; the mode and uid columns
  # precede the filename, so a path with spaces cannot shift them).
  # shellcheck disable=SC2086
  set -- $cp_line
  cp_perms=${1:-}
  cp_uid=${3:-}
  case "$cp_perms" in
    d???------ | d???------[@.]*) ;;
    *)
      err "security: coordination surface $cp_dir is not verifiably user-private (mode $cp_perms; group/other access and ACL-bearing modes are refused) — verify-or-refuse, REQ-A1.4: halt coordination-surface use, investigate how it widened, then chmod 700 (and strip any ACL) yourself"
      exit 4
      ;;
  esac
  if [ "$cp_uid" != "$my_uid" ]; then
    err "security: coordination surface $cp_dir is owned by uid $cp_uid, not this user — refusing an attacker-planted or mis-owned surface (verify-or-refuse, REQ-A1.4); investigate and remove it yourself"
    exit 4
  fi
}

# check_sentinel_untampered <file> — a symlink (including dangling — the
# redirect would create a file at an attacker-chosen target) or any
# non-regular object at the sentinel path is never a sentinel this script
# wrote: refuse it outright in EVERY state (REQ-A1.4), before it can read
# as mere vanished evidence downstream.
check_sentinel_untampered() {
  if [ -L "$1" ] || { [ -e "$1" ] && [ ! -f "$1" ]; }; then
    err "security: sentinel path $1 is a symlink or non-regular object — refusing to trust or write through it (REQ-A1.4/REQ-A1.5); investigate and remove it yourself"
    exit 4
  fi
}

# write_sentinel <file> — fail closed on a write failure: proceeding without
# the sentinel would let a later vanished surface read as a healthy first
# run. Tampered paths are refused via check_sentinel_untampered, never
# written through.
write_sentinel() {
  check_sentinel_untampered "$1"
  if [ ! -f "$1" ]; then
    if ! date +%s >"$1" 2>/dev/null; then
      err "could not write the persistence sentinel $1 — failing closed (REQ-A1.5); fix the fleet home's writability and retry"
      exit 2
    fi
  fi
}

# ensure_infra_dir <dir> — sentinel-less infrastructure dirs (sentinels,
# cadence stamps): mode-explicit create, EEXIST is success, verify-or-refuse.
ensure_infra_dir() {
  if [ ! -d "$1" ]; then
    mkdir -m 0700 "$1" 2>/dev/null || true
  fi
  if [ ! -d "$1" ]; then
    err "cannot create $1 — failing closed; fix the fleet home's writability and retry"
    exit 2
  fi
  check_private "$1"
}

# ensure_surface_dir <dir> <sentinel> — the first-run-vs-vanished state
# machine (REQ-A1.5), applied at both the host and per-repo level:
#   dir present            → verify mode, backfill a missing sentinel
#   dir missing + sentinel → VANISHED: fail closed (exit 3), never solitude
#   dir missing, no sent.  → first-run bootstrap: sentinel FIRST (a crash
#                            between the two fails closed later, never open),
#                            then an atomic mode-explicit mkdir; a concurrent
#                            peer's EEXIST is success
ensure_surface_dir() {
  esd_dir=$1
  esd_sentinel=$2
  # Tamper check FIRST, in every state: a symlinked or non-regular sentinel
  # must exit 4 (security refusal) even when the surface dir is missing —
  # never fall through to the vanished check below and read as exit-3
  # evidence (docs promise exit 4 for symlink-tampered; REQ-A1.4).
  check_sentinel_untampered "$esd_sentinel"
  if [ -d "$esd_dir" ]; then
    check_private "$esd_dir"
    write_sentinel "$esd_sentinel"
    return 0
  fi
  if [ -e "$esd_dir" ]; then
    err "unknown peer status: $esd_dir exists but is not a directory — failing closed (REQ-A1.5); investigate and remove the obstruction"
    exit 3
  fi
  # -e, not -f: any surviving object at the sentinel path means the surface
  # once existed (a content-corrupted sentinel still reads as present — fail
  # closed). Symlinks and non-regular objects never reach here: the tamper
  # check at the top of this function already refused them (exit 4).
  # Transient corner, accepted: a peer mid-bootstrap between its
  # sentinel-write and mkdir reads here as vanished for one pass; the next
  # invocation sees the directory (awareness-only, self-correcting).
  if [ -e "$esd_sentinel" ]; then
    err "unknown peer status: presence surface $esd_dir vanished (its persistence sentinel survives) — failing closed, never read as solitude (REQ-A1.5); awareness degrades for this step while dispatch proceeds (D-10); investigate, then remove $esd_sentinel to re-bootstrap"
    exit 3
  fi
  write_sentinel "$esd_sentinel"
  if ! mkdir -m 0700 "$esd_dir" 2>/dev/null; then
    if [ ! -d "$esd_dir" ]; then
      err "cannot create presence surface $esd_dir — failing closed; fix the fleet home's writability and retry"
      exit 2
    fi
    # EEXIST: a peer bootstrapped it a moment earlier — success (D-10).
  fi
  check_private "$esd_dir"
}

ensure_infra_dir "$sentinel_dir"
ensure_surface_dir "$surface_root" "$host_sentinel"
ensure_surface_dir "$sub" "$repo_sentinel"

# --- tower identity (REQ-A1.7) ---------------------------------------------

derive_identity() {
  if [ -n "$session_id" ]; then
    printf '%s\n' "$session_id"
    return 0
  fi
  if [ -z "$pid" ]; then
    err "identity needs --session-id or --pid (the composite falls back to pid + start-time + checkout hash)"
    exit 2
  fi
  # Targeted per-pid start-time query — never a process-listing scan.
  di_start=$(ps -p "$pid" -o lstart= 2>/dev/null)
  if [ -z "$di_start" ]; then
    err "cannot derive the composite identity: no start time for pid $pid (is the tower process alive?)"
    exit 2
  fi
  di_t=$(printf '%s' "$di_start" | cksum | awk '{print $1}')
  di_c=$(printf '%s' "$checkout" | cksum | awk '{print $1}')
  printf 'p%s.t%s.c%s\n' "$pid" "$di_t" "$di_c"
}

identity=$(derive_identity) || exit 2
# Defensive self-check: a cksum/awk failure inside the composite derivation
# would otherwise silently publish a malformed identity (p<pid>.t.c) that
# every peer then classifies unreadable — refuse it here, at the writer.
if ! is_tower_id "$identity"; then
  err "derived tower identity is malformed ('$(sanitize_printable "$identity" "(unprintable)")') — failing closed (cksum/ps failure?)"
  exit 2
fi

if [ "$cmd" = identity ]; then
  printf '%s\n' "$identity"
  exit 0
fi

# --- publish ---------------------------------------------------------------

if [ "$cmd" = publish ]; then
  if [ -n "$tmux_session" ]; then
    handle="tmux-window $tmux_session $tmux_window"
  elif [ -n "$pid" ]; then
    handle="process $pid"
  else
    err "publish needs a death handle: --tmux-session/--tmux-window (preferred under tmux) or --pid (degraded fallback, REQ-A1.2)"
    exit 2
  fi
  now=$(date +%s)
  if ! is_epoch "$now"; then
    err "cannot stamp the heartbeat epoch (date +%s failed) — failing closed"
    exit 2
  fi
  start=$now
  own="$sub/$identity"
  if [ -f "$own" ]; then
    prev_line=$(head -n 1 "$own" 2>/dev/null) || prev_line=""
    case "$prev_line" in
      "pw-presence-v1	"*)
        prev_start=$(printf '%s' "$prev_line" | awk -F'\t' '{print $7}')
        if is_epoch "$prev_start"; then
          start=$prev_start
        fi
        ;;
    esac
  fi
  # Publish-side mirror of the reader's 8192-byte record cap: an oversize
  # record would publish "successfully" yet read as malformed by every peer,
  # silently degrading this tower's strand attribution — refuse it HERE, at
  # the writer, where the operator gets the signal.
  record=$(printf 'pw-presence-v1\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s' \
    "$repo_id" "$identity" "$checkout" "$specs" "$fenced" \
    "$start" "$now" "$handle" "$meta")
  if [ "${#record}" -gt 8191 ]; then
    err "refusing to publish an oversize presence record (${#record} bytes > the 8191-byte record cap peers enforce); trim --specs/--fenced"
    exit 2
  fi
  pub_tmp=$(mktemp "$sub/.pub.XXXXXX") || {
    err "cannot create a temp record in $sub — failing closed"
    exit 2
  }
  if ! printf '%s\n' "$record" >"$pub_tmp" 2>/dev/null; then
    rm -f "$pub_tmp"
    err "cannot write the presence record — failing closed"
    exit 2
  fi
  chmod 600 "$pub_tmp" 2>/dev/null || true
  if ! mv -f "$pub_tmp" "$own" 2>/dev/null; then
    rm -f "$pub_tmp"
    err "cannot publish the presence record (rename failed) — failing closed"
    exit 2
  fi
  pub_tmp="" # renamed away; nothing for the exit trap to collect
  exit 0
fi

# --- discover / owner ------------------------------------------------------

# Surface readability is proven BEFORE the cadence cap, so a surface that
# broke inside the cap window fails closed on the very next call instead of
# hiding behind `cadence-capped` (the ls is cheap; the cap exists to bound
# the per-record death-predicate fan-out, which stays capped).
listing=$(ls "$sub" 2>/dev/null) || {
  err "unknown peer status: presence sub-surface $sub is unreadable — failing closed, never read as solitude (REQ-A1.5); awareness degrades for this step while dispatch proceeds (D-10); investigate the surface's permissions"
  exit 3
}

# Cadence cap (REQ-A1.1): a discover inside --min-interval is a no-op that
# prints only `cadence-capped` (deliberately no summary line, so a capped
# pass can never be misread as an empty peer set). The stamp is written only
# after a completed scan; a future-dated stamp (clock step) is ignored so
# skew can never lock discovery out. owner is a targeted query, never capped.
ensure_infra_dir "$cadence_dir"
stamp="$cadence_dir/$repo_id.$identity"
if [ "$cmd" = discover ] && [ "$min_interval" -gt 0 ]; then
  now=$(date +%s)
  last=$(cat "$stamp" 2>/dev/null) || last=""
  if is_epoch "$last" && [ "$last" -le "$now" ] && [ $((now - last)) -lt "$min_interval" ]; then
    printf 'cadence-capped\n'
    exit 0
  fi
fi

fde="$script_dir/fleet-death-evidence.sh"
# The per-pass memo lives in the private cadence dir, not shared $TMPDIR
# (sibling convention: surface-local temp templates).
memo=$(mktemp "$cadence_dir/.memo.XXXXXX") || {
  memo=""
  err "cannot create the per-pass liveness memo in $cadence_dir — failing closed"
  exit 2
}

# classify_handle <handle> — tri-state verdict, memoized per pass so the
# per-record subprocess fan-out is bounded (≤1 per distinct handle per pass).
classify_handle() {
  ch_handle=$1
  ch_hit=$(awk -F'\t' -v h="$ch_handle" '$2 == h { print $1; exit }' "$memo")
  if [ -n "$ch_hit" ]; then
    printf '%s\n' "$ch_hit"
    return 0
  fi
  # The handle grammar was validated above; word-split it back into the
  # predicate's argv form. The predicate's stderr flows through: an unknown
  # or refused verdict keeps its lost-observability reason visible.
  # shellcheck disable=SC2086
  set -- $ch_handle
  ch_verdict=$("$fde" "$@")
  case "$ch_verdict" in
    dead | alive) ;;
    *) ch_verdict=unknown ;; # incl. a refused handle: lost observability, fail closed
  esac
  printf '%s\t%s\n' "$ch_verdict" "$ch_handle" >>"$memo" 2>/dev/null || true
  printf '%s\n' "$ch_verdict"
}

peers=0
found_owner=""

emit_unreadable_peer() {
  eup_name=$(sanitize_printable "$1" "(unprintable name)")
  err "skipping unreadable presence record '$eup_name' ($2) — a peer exists but its details are unreadable: assume-live, surfaced, never GC'd (REQ-A1.6)"
  if [ "$cmd" = discover ]; then
    printf 'peer-unreadable\t%s\t%s\n' "$eup_name" "$2"
  fi
  peers=$((peers + 1))
}

# owner_match <tower-id> <fenced-csv> — attribute from LIVE records only
# (REQ-A1.2, REQ-C1.3: a fence no live record lists is unknown-owner; an
# unknown-liveness holder surfaces through the strand path, Task 4). A
# second live claimant is surfaced, first match kept (deterministic).
owner_match() {
  case ",$2," in
    *",$unit_ref,"*)
      if [ -z "$found_owner" ]; then
        found_owner=$1
      else
        err "unit $unit_ref is listed by a second live record ('$1' after '$found_owner') — duplicate fence claim surfaced, first match kept"
      fi
      ;;
  esac
}

while IFS= read -r name; do
  [ -z "$name" ] && continue
  [ "$name" = "$identity" ] && continue
  file="$sub/$name"
  # Bounded read: one byte past the record cap is enough to classify
  # oversize as malformed without slurping an arbitrarily large file.
  content=$(head -c 8192 "$file" 2>/dev/null) || {
    # cat/head failure conflates ENOENT with EACCES/EISDIR: only a genuinely
    # ABSENT file is the benign mid-scan vanish; anything still present is a
    # peer whose details are unreadable (REQ-A1.6) — surfaced, assume-live.
    if [ -e "$file" ]; then
      emit_unreadable_peer "$name" unreadable
    fi
    continue
  }
  # Byte-true over-cap probe: the command substitution above strips
  # trailing newlines, so ${#content} alone cannot see bytes hiding behind
  # a newline at exactly byte 8192 (a max-length line + newline + junk
  # would read as a legal record). Counting the first 8193 bytes through a
  # pipe (nothing is stripped) makes any byte past the 8192-byte file cap
  # classify malformed (REQ-A1.6), still without slurping an arbitrarily
  # large file.
  over_cap=$(head -c 8193 "$file" 2>/dev/null | wc -c | tr -d ' ')
  # One awk parses the whole record: exact field count enforced, the ten
  # fields emitted one per line (fields never contain newlines — the record
  # is single-line by construction; interior extra lines fail NR>1, while
  # trailing blank lines are stripped by the command substitution above and
  # tolerated within the file cap the probe above enforces).
  parsed=$(printf '%s\n' "$content" | awk -F'\t' '
    NR == 1 { if (NF != 10) bad = 1; else for (i = 1; i <= 10; i++) print $i }
    NR > 1 { bad = 1 }
    END { exit bad }') || parsed=""
  ok=1
  kind=malformed
  if [ "${#content}" -ge 8192 ] || [ "$over_cap" -gt 8192 ]; then
    # Oversize is malformed regardless of its tag: a version sniff on a
    # truncated read would mislabel it schema-skew.
    ok=0
  elif [ -z "$parsed" ]; then
    ok=0
    tag=$(printf '%s\n' "$content" | awk -F'\t' 'NR==1{print $1}')
    case "$tag" in
      pw-presence-v1) ;;
      pw-presence-v*)
        if printf '%s' "$tag" | grep -Eq '^pw-presence-v[0-9]+$'; then
          kind=schema-skew
        fi
        ;;
    esac
  else
    {
      IFS= read -r tag
      IFS= read -r r_repo
      IFS= read -r r_id
      IFS= read -r r_checkout
      IFS= read -r r_specs
      IFS= read -r r_fenced
      IFS= read -r r_start
      IFS= read -r r_beat
      IFS= read -r r_handle
      IFS= read -r r_meta
    } <<PARSED_EOF
$parsed
PARSED_EOF
    if [ "$tag" != "pw-presence-v1" ]; then
      ok=0
      if printf '%s' "$tag" | grep -Eq '^pw-presence-v[0-9]+$'; then
        kind=schema-skew
      fi
    elif ! is_repo_id "$r_repo" \
      || ! is_tower_id "$r_id" \
      || [ "$r_id" != "$name" ]; then
      ok=0
    else
      case "$r_checkout" in
        /*) ;;
        *) ok=0 ;;
      esac
      is_control_free "$r_checkout" || ok=0
      is_csv_of is_spec_id "$r_specs" || ok=0
      is_csv_of is_unit_ref "$r_fenced" || ok=0
      is_epoch "$r_start" || ok=0
      is_epoch "$r_beat" || ok=0
      is_handle "$r_handle" || ok=0
      case "$r_meta" in
        true | false) ;;
        *) ok=0 ;;
      esac
    fi
  fi
  if [ "$ok" != 1 ]; then
    emit_unreadable_peer "$name" "$kind"
    continue
  fi
  if [ "$r_repo" != "$repo_id" ]; then
    # Defensive cross-check (REQ-A1.1): a record inside this sub-surface
    # claiming another repository is an anomaly, not a peer of this repo —
    # surfaced (stderr + a machine-readable line), excluded from the peer
    # count, never GC'd on a guess.
    err "presence record '$(sanitize_printable "$name" "(unprintable name)")' carries repo id $r_repo inside the $repo_id sub-surface — anomaly surfaced, excluded from the peer set, left in place"
    if [ "$cmd" = discover ]; then
      printf 'foreign-record\t%s\t%s\n' "$(sanitize_printable "$name" "(unprintable name)")" "$r_repo"
    fi
    continue
  fi
  verdict=$(classify_handle "$r_handle")
  # The checkout field is the one loose-charset record value; it is
  # sanitized (echo discipline: C0+DEL+C1 stripped) before reaching stdout.
  case "$verdict" in
    alive)
      peers=$((peers + 1))
      if [ "$cmd" = discover ]; then
        printf 'peer\t%s\tlive\t%s\t%s\t%s\t%s\n' \
          "$r_id" "$(sanitize_printable "$r_checkout" "-")" "$r_specs" "$r_fenced" "$r_meta"
      elif [ "$cmd" = owner ]; then
        owner_match "$r_id" "$r_fenced"
      fi
      ;;
    unknown)
      # Not-dead (fail closed): lost observability never authorizes reclaim,
      # and an unclassifiable peer still argues against solitude — but it is
      # NOT an attribution source: owner resolves from live records only.
      peers=$((peers + 1))
      if [ "$cmd" = discover ]; then
        printf 'peer\t%s\tunknown\t%s\t%s\t%s\t%s\n' \
          "$r_id" "$(sanitize_printable "$r_checkout" "-")" "$r_specs" "$r_fenced" "$r_meta"
      fi
      ;;
    dead)
      if [ "$cmd" = owner ]; then
        # owner is a read-only query: no GC side effects.
        continue
      fi
      # Best-effort re-read-and-skip guard (REQ-A1.3): delete only a file
      # whose bounded re-read (the same 8 KiB record-cap window) is still
      # byte-identical to the classified dead record. No lock — the
      # residual TOCTOU is benign: a racing fresh record self-heals on the
      # tower's next heartbeat re-publish (awareness-only, D-13).
      reread=$(head -c 8192 "$file" 2>/dev/null) || reread=""
      if [ ! -e "$file" ]; then
        # A peer's sweep unlinked it first: the dead record is gone — the
        # GC outcome holds, nothing argues against solitude.
        printf 'gc\t%s\n' "$r_id"
      elif [ "$reread" = "$content" ]; then
        if rm -f "$file" 2>/dev/null; then
          printf 'gc\t%s\n' "$r_id"
        else
          # Never claim a delete that did not happen: surface the failure;
          # the record's owner is positively dead, so it still does not
          # count as a peer.
          err "could not GC positively-dead record '$(sanitize_printable "$name" "(unprintable name)")' (unlink failed) — left in place, surfaced"
          printf 'gc-fail\t%s\n' "$r_id"
        fi
      else
        printf 'gc-skip\t%s\n' "$r_id"
        peers=$((peers + 1))
      fi
      ;;
  esac
done <<LISTING_EOF
$listing
LISTING_EOF

# Scan completed: stamp the cadence window (see the cap above), atomically
# (temp + rename), matching the surface's write discipline.
if [ "$cmd" = discover ] && [ "$min_interval" -gt 0 ]; then
  stamp_tmp=$(mktemp "$cadence_dir/.stamp.XXXXXX" 2>/dev/null) || stamp_tmp=""
  if [ -n "$stamp_tmp" ]; then
    if date +%s >"$stamp_tmp" 2>/dev/null; then
      mv -f "$stamp_tmp" "$stamp" 2>/dev/null || rm -f "$stamp_tmp"
    else
      rm -f "$stamp_tmp"
    fi
    stamp_tmp="" # renamed or removed; nothing for the exit trap to collect
  fi
fi

if [ "$cmd" = owner ]; then
  if [ -n "$found_owner" ]; then
    printf 'owner\t%s\n' "$found_owner"
  else
    printf 'unknown-owner\n'
  fi
  exit 0
fi

if [ "$peers" -gt 0 ]; then
  sole=no
else
  sole=yes
fi
printf 'summary\tpeers=%s\tsole-tower=%s\n' "$peers" "$sole"
exit 0
