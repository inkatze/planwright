#!/bin/sh
# dispatch-fetch.sh — the bounded, deterministic fetch-before-gate primitive for
# the /orchestrate and /execute-task dispatch path (fleet-hardening Task 8; D-9;
# REQ-D1.1, REQ-D1.2, REQ-E1.3).
#
# Before dispatch, the execution freshness gate and merge detection must be
# evaluated against the CURRENT remote view, not a stale local `main`: a stale
# local `main` bases a dispatch on outdated spec content, misses an upstream
# re-anchor, and re-dispatches a task whose PR already merged on `origin` but
# whose merge trailer has not reached local `main`. This script fetches `origin`
# and reports the currency + (with --spec) the content anchor over the bundle's
# primary view, the fetched remote default branch for a bundle in the work
# repository, WITHOUT advancing local `main` (the shared-checkout read-only-
# local-`main` invariant, orchestration-concurrency). The fetch pins an explicit
# `+refs/heads/*:refs/remotes/origin/*` refspec, so it updates only
# remote-tracking refs (and the recorded remote HEAD) and never fast-forwards a
# local branch, independent of the repo's configured `remote.origin.fetch`. It
# makes no model/API call — the whole decision path is deterministic git
# plumbing (REQ-E1.3).
#
# Scope boundary (D-9): this is git-ref currency for the dispatch/merge path
# only. It RE-POINTS the existing content-anchor computer (scripts/spec-anchor.sh)
# at the bundle's primary view (a fetched ref of the work repository or the
# holder, or a plain root's files); it does not implement anchor-hash
# comparison (that is `anchor-integrity`'s), and it does not touch the
# release-publish version-derivation path (`release-hardening`'s). Merge
# detection itself stays in scripts/orchestrate-state.sh — this primitive only
# makes the work repository's remote-tracking refs current so that engine's
# existing union scan reads a fresh ref.
#
# Usage: dispatch-fetch.sh [--spec <spec>] [--best-effort] <repo-root>
#   <repo-root>            the work repository to fetch in (fetch runs there;
#                          no local branch is ever advanced).
#   --spec <spec>          also compute and print the content anchor over that
#                          bundle's primary view under the spec root <repo-root>
#                          resolves (custom-spec-location D-14): in same-repo the
#                          work repository's default branch, in separate-repo the
#                          holder's default branch (the holder is fetched too,
#                          bounded the same way but never TTL-coalesced), in
#                          plain the directory's files as they are. A default
#                          branch is the remote's HEAD branch where an origin
#                          exists, else the branch the primary checkout's HEAD
#                          names, never assumed to be called main. The
#                          identifier is bare; `specs/<spec>` is accepted as an
#                          alias, with or without one trailing slash.
#   --best-effort          single fetch attempt (no retries) for the reconcile
#                          sweep, so a down remote does not stall each idle cycle.
#
# Output — a tagged TSV stream on stdout (consumers switch on column 1):
#   fetch<TAB><fetched|fresh-within-ttl|no-remote|stale-transient>
#   store-fetch<TAB><fetched|no-remote|stale-transient>   (separate-repo only)
#   anchor<TAB><hash><TAB><ref>   (only with --spec, when an anchor is computed;
#                                  <ref> is the work repository's ref, store:<ref>
#                                  for the holder's, or files for a plain root)
#
# Exit codes (the work repository's currency; with --spec, the anchor rules):
#   0  remote current (fetched, or fresh-within-ttl — a prior fetch is still
#      within the TTL, so no network I/O ran). With --spec an anchor line is
#      guaranteed present, from the fetched remote default branch in same-repo
#      (a success exit never carries a stale or missing anchor).
#   3  no-remote — structurally offline (no `origin` remote). Offline is
#      first-class: the caller proceeds DEGRADED, and in same-repo the anchor
#      is computed against the local default branch, then HEAD. With --spec an
#      exit-3 result ALWAYS carries an anchor line, or fails closed with 4 or 5.
#   4  stale-transient — a present remote's fetch failed after the bounded
#      retries, the work repository's or (with --spec, separate-repo) the
#      holder's. The caller MUST NOT silently proceed against a stale ref:
#      block, or proceed only under an explicit operator stale flag. No anchor
#      is printed (never anchor a stale ref).
#   5  anchor-unresolved — with --spec, the spec content anchor could not be
#      computed from the primary view the gate compares against: ref
#      unresolved, the remote's default branch unknown, the bundle absent
#      there, or the anchor computer failed. No anchor is printed; the caller
#      MUST NOT gate against a stale/missing anchor — park. Fail closed on
#      EVERY path, so the --spec guarantee "an anchor record OR a nonzero park
#      code" holds uniformly online and offline.
#   2  usage / invalid input / internal failure (fail closed), including a
#      --spec whose spec root does not resolve, or lies in a git posture whose
#      repository's top level does not resolve. A root inside a repository
#      that no ref holds (gitignored or never committed) is read at the ref
#      like any other and parks with 5.
#
# Environment overrides (tests, worktree callers):
#   PLANWRIGHT_DISPATCH_FETCH_STATE_DIR  dir holding the last-fetch TTL stamp
#                                        (default <repo>/.claude/orchestrate.local,
#                                        gitignored by `.claude/*.local/`).
#   PLANWRIGHT_DISPATCH_FETCH_TTL        TTL in SECONDS (raw integer); overrides
#                                        the config knob. 0 forces a re-fetch.
#   PLANWRIGHT_DISPATCH_FETCH_RETRIES    retries after the first attempt (default 2).
#   PLANWRIGHT_DISPATCH_FETCH_RETRY_SLEEP seconds between attempts (default 2).
#   PLANWRIGHT_LOCAL_CONFIG              passed through to config-get.sh.
# The config knob `dispatch_fetch_ttl` (config/defaults.yml, `<n>[m]` minutes
# convention) sets the default TTL; the SECONDS env override wins for precision.
#
# Portable POSIX sh + git (bash 3.2 / BSD compatible, no eval; all external
# input is treated as data). Pathname expansion is disabled (set -f).
set -uf
LC_ALL=C
export LC_ALL
unset CDPATH

TAB=$(printf '\t')

# Resolve the install dir up front so the echo-discipline sanitizer is available
# to the arg-parse error paths below (script_dir is reused for the sibling
# helpers further down). Untrusted values (a caller-supplied --spec or repo-root)
# are sanitized AND emitted with printf '%s' (never echo): sanitize_printable
# strips already-formed control bytes, and printf keeps a backslash-interpreting
# sh (dash, macOS /bin/sh under xpg_echo) from re-synthesizing a live escape out
# of a literal backslash sequence that survives the strip
# (doctrine/security-posture.md echo discipline; obs 2026-07-15).
script_dir=$(cd -- "$(dirname -- "$0")" && pwd) || exit 2
if [ -f "$script_dir/echo-safety.sh" ] && [ -r "$script_dir/echo-safety.sh" ]; then
  # shellcheck source=scripts/echo-safety.sh
  . "$script_dir/echo-safety.sh"
else
  # Fallback keeps the script functional if the sibling lib is absent: strips C0,
  # DEL, and C1 (0x80-0x9F, including single-byte CSI 0x9B) — byte-identical scope
  # to the canonical sanitize_printable.
  sanitize_printable() { printf '%s' "$1" | tr -d '\000-\037\177\200-\237'; }
fi

# Unlike echo-safety.sh the mapper has no fallback, so a missing copy is a
# broken install, refused with exit 2: a failed `.` ends the shell with a
# status of the shell's choosing (1 under bash's sh), which this script's exit
# codes give another meaning or none.
if [ -r "$script_dir/spec-id-lib.sh" ]; then
  # shellcheck source=scripts/spec-id-lib.sh
  . "$script_dir/spec-id-lib.sh"
else
  printf '%s\n' "dispatch-fetch: broken install: $(sanitize_printable "$script_dir")/spec-id-lib.sh is missing or not readable" >&2
  exit 2
fi

usage() {
  printf '%s\n' "usage: dispatch-fetch.sh [--spec <spec>] [--best-effort] <repo-root>" >&2
  exit 2
}

spec_arg=""
spec_rel=""
spec_dir=""
spec_posture=""
spec_given=0
repo_root=""
best_effort=0
while [ $# -gt 0 ]; do
  case "$1" in
    --spec)
      [ $# -ge 2 ] || usage
      spec_arg="$2"
      spec_given=1
      shift 2
      ;;
    --spec=*)
      spec_arg="${1#--spec=}"
      spec_given=1
      shift
      ;;
    --best-effort)
      # Single-attempt mode for the reconcile sweep: a down remote must not stall
      # every idle `--watch` cycle on the retry budget (the sweep tolerates
      # staleness; the dispatch gate does not, so it omits this flag).
      best_effort=1
      shift
      ;;
    --)
      shift
      break
      ;;
    -*)
      printf '%s\n' "dispatch-fetch: unknown option '$(sanitize_printable "$1")'" >&2
      usage
      ;;
    *)
      [ -z "$repo_root" ] || usage
      repo_root="$1"
      shift
      ;;
  esac
done
# After option parsing (including a `--` terminator), consume at most ONE
# positional as <repo-root>. Any surplus positional is a mis-invocation: fail
# closed (usage/exit 2) rather than silently ignore it — symmetric with the
# in-loop guard that rejects a second positional before `--`. Without this, a
# `--`-terminated invocation (`dispatch-fetch.sh -- <repo> extra`) or a trailing
# `--` (`dispatch-fetch.sh <repo> -- extra`) would silently drop the surplus.
if [ -z "$repo_root" ] && [ $# -gt 0 ]; then
  repo_root="$1"
  shift
fi
[ $# -eq 0 ] || usage
[ -n "$repo_root" ] || usage

# A supplied-but-empty --spec is invalid input, not "no --spec". Treating an
# empty value as omitted would silently waive the --spec anchor guarantee (a
# success exit is contracted to carry an anchor), so fail closed
# here rather than downgrade to currency-only.
if [ "$spec_given" -eq 1 ] && [ -z "$spec_arg" ]; then
  printf '%s\n' "dispatch-fetch: --spec requires a non-empty spec identifier" >&2
  exit 2
fi

# Validate the identifier against traversal / injection before it reaches a
# path or `git show <ref>:<path>` (the identifier grammar: REQ-A1.8). Anything
# else, a bundle-file path included, fails closed.
if [ "$spec_given" -eq 1 ]; then
  spec_id_canon "$spec_arg"
  spec_name=$SPEC_ID
  case "$spec_name" in
    '' | */* | *[!a-z0-9-]* | [!a-z0-9]*)
      printf '%s\n' "dispatch-fetch: --spec must be a spec identifier matching ^[a-z0-9][a-z0-9-]*\$ (got '$(sanitize_printable "$spec_arg")')" >&2
      exit 2
      ;;
    flight)
      printf '%s\n' "dispatch-fetch: reserved spec name 'flight' (the flight branch segment, tower-front-door D-11)" >&2
      exit 2
      ;;
  esac
  if [ "${#spec_name}" -gt 64 ]; then
    printf '%s\n' "dispatch-fetch: --spec identifier is longer than 64 characters" >&2
    exit 2
  fi
fi

# Repo-root must be inside a git work tree; resolve its top so refs/paths are
# unambiguous regardless of the caller's cwd.
repo_top=$(cd -- "$repo_root" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null) || repo_top=""
if [ -z "$repo_top" ]; then
  printf '%s\n' "dispatch-fetch: '$(sanitize_printable "$repo_root")' is not inside a git work tree" >&2
  exit 2
fi
repo_root=$repo_top

# The bundle's primary view, from the spec root <repo-root> resolves
# (custom-spec-location D-14):
# in same-repo a path at a ref of this repository, in separate-repo a path at
# a ref of the holder that contains the root, in plain the directory itself.
if [ "$spec_given" -eq 1 ]; then
  spec_line=$(cd -- "$repo_root" && env -u PLANWRIGHT_REPO_ROOT /bin/sh "$script_dir/resolve-root.sh" spec --primary --explain) || {
    printf '%s\n' "dispatch-fetch: the spec root for '$(sanitize_printable "$repo_root")' did not resolve" >&2
    exit 2
  }
  # <source> TAB <path> TAB <posture> TAB <view>; the resolver refuses a root
  # whose path carries a tab, so the fields split cleanly.
  spec_rest=${spec_line#*"$TAB"}
  spec_root=${spec_rest%%"$TAB"*}
  spec_rest=${spec_rest#*"$TAB"}
  spec_posture=${spec_rest%%"$TAB"*}
  case $spec_posture in
    same-repo)
      store_top=$(cd -- "$repo_root" && env -u PLANWRIGHT_REPO_ROOT /bin/sh "$script_dir/resolve-root.sh" repo --primary 2>/dev/null) || store_top=""
      ;;
    separate-repo)
      store_top=$(cd -P -- "$spec_root" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null) || store_top=""
      [ -z "$store_top" ] || store_top=$(cd -P -- "$store_top" 2>/dev/null && pwd -P) || store_top=""
      ;;
    *) store_top="" ;;
  esac
  # An empty top level would match any absolute root below, and `git -C ""`
  # reads the caller's own repository: refuse it.
  case $spec_posture:$store_top in
    plain:* | *:?*) ;;
    *)
      printf '%s\n' "dispatch-fetch: the $(sanitize_printable "$spec_posture") spec root '$(sanitize_printable "$spec_root")' lies in no repository whose top level resolves, so no ref holds the bundle" >&2
      exit 2
      ;;
  esac
  case $spec_posture:$spec_root in
    plain:*) spec_dir="$spec_root/$spec_name" ;;
    *:"$store_top") spec_rel=$spec_name ;;
    *:"$store_top"/*) spec_rel="${spec_root#"$store_top"/}/$spec_name" ;;
    *)
      printf '%s\n' "dispatch-fetch: the $(sanitize_printable "$spec_posture") spec root '$(sanitize_printable "$spec_root")' is not inside the repository that should hold it, so no ref holds the bundle" >&2
      exit 2
      ;;
  esac
fi

anchor_script="$script_dir/spec-anchor.sh"
config_get="$script_dir/config-get.sh"

# Numeric-input validation rejects a leading zero on a multi-digit value (the
# `0?*` arm) alongside non-digits and empty. Digits-only is not enough: a value
# like `08`/`09` passes `*[!0-9]*` but is an invalid octal literal inside POSIX
# `$(( ))`, which errors (fatal under dash, and outside this script's
# {0,2,3,4,5} exit contract) — so leading-zero values are treated as malformed
# (warn + default) exactly as any other bad value is. A bare `0` (documented:
# TTL 0 forces a re-fetch; retries 0 is best-effort) is one char and never
# matches `0?*`, so it stays valid.

# --- Resolve the TTL (seconds) ------------------------------------------------
# SECONDS env override wins (raw integer, for test precision); else the config
# knob `dispatch_fetch_ttl` in the `<n>[m]` minutes convention; else 2m.
ttl_sec=""
if [ -n "${PLANWRIGHT_DISPATCH_FETCH_TTL:-}" ]; then
  case "$PLANWRIGHT_DISPATCH_FETCH_TTL" in
    *[!0-9]* | '' | 0?*)
      printf '%s\n' "dispatch-fetch: ignoring malformed PLANWRIGHT_DISPATCH_FETCH_TTL" >&2
      ;;
    *) ttl_sec=$PLANWRIGHT_DISPATCH_FETCH_TTL ;;
  esac
fi
if [ -z "$ttl_sec" ]; then
  ttl_min=2
  cv=""
  if [ -x "$config_get" ]; then
    cv=$("$config_get" dispatch_fetch_ttl 2>/dev/null) || cv=""
  fi
  cv=${cv%m}
  case "$cv" in
    '') ;; # key absent everywhere: the 2m default stands
    *[!0-9]* | 0?*)
      printf '%s\n' "dispatch-fetch: ignoring malformed dispatch_fetch_ttl; using ${ttl_min}m" >&2
      ;;
    *) ttl_min=$cv ;;
  esac
  ttl_sec=$((ttl_min * 60))
fi

# Retry bounds. Best-effort mode (the reconcile sweep) defaults to a single
# attempt so a down remote never stalls an idle cycle; an explicit env override
# still wins in either mode. A malformed override falls back to the SAME
# mode-specific default (0 in best-effort, 2 otherwise), so a bad env value in
# best-effort mode does not silently restore the retry budget the sweep omits.
if [ "$best_effort" -eq 1 ]; then
  retries_default=0
else
  retries_default=2
fi
retries=${PLANWRIGHT_DISPATCH_FETCH_RETRIES:-$retries_default}
case "$retries" in *[!0-9]* | '' | 0?*) retries=$retries_default ;; esac
retry_sleep=${PLANWRIGHT_DISPATCH_FETCH_RETRY_SLEEP:-2}
case "$retry_sleep" in *[!0-9]* | '' | 0?*) retry_sleep=2 ;; esac
max_attempts=$((retries + 1))

state_dir="${PLANWRIGHT_DISPATCH_FETCH_STATE_DIR:-$repo_root/.claude/orchestrate.local}"
stamp_file="$state_dir/last-fetch"

# Read the clock for the TTL age math. On the (near-impossible) failure of
# `date +%s`, leave `now` empty rather than let it default to 0: an empty/zero
# `now` would make `age = now - last` negative and read as fresh — the WRONG
# degrade (it would reuse a stale ref). The within-TTL check below requires a
# numeric `now`, so an unreadable clock forces a fetch instead (the safe
# direction), symmetric with the stamp-write clock read further down.
now=$(date +%s 2>/dev/null) || now=""
case "$now" in '' | *[!0-9]*) now="" ;; esac

# --- Anchor a spec bundle at a git ref ---------------------------------------
# Re-point the EXISTING content-anchor computer at <ref> of <repo> by
# materializing that ref's four spec files under <rel> and running
# scripts/spec-anchor.sh over them. Prints the anchor on success; returns
# non-zero (prints nothing) if the ref does not resolve, a file is missing at
# that ref, or spec-anchor fails. Reuses the shipped anchor computer — no hash
# logic is re-implemented here (D-9).
anchor_at_ref() {
  _repo="$1"
  _ref="$2"
  git -C "$_repo" rev-parse --verify --quiet "$_ref^{commit}" >/dev/null 2>&1 || return 1
  [ -x "$anchor_script" ] || return 1
  _td=$(mktemp -d "${TMPDIR:-/tmp}/dispatch-fetch-anchor.XXXXXX") || return 1
  _ok=1
  for _f in requirements.md design.md tasks.md test-spec.md; do
    if ! git -C "$_repo" show "$_ref:$spec_rel/$_f" >"$_td/$_f" 2>/dev/null; then
      _ok=0
      break
    fi
  done
  if [ "$_ok" -eq 1 ]; then
    _a=$("$anchor_script" "$_td" 2>/dev/null) || _a=""
  else
    _a=""
  fi
  rm -rf -- "$_td"
  [ -n "$_a" ] || return 1
  printf '%s' "$_a"
}

# default_ref <repo>: print the full ref holding <repo>'s default branch
# (custom-spec-location D-14), never assumed to be called main. With an origin
# remote it is the remote's HEAD branch as git recorded it
# (refs/remotes/origin/HEAD, which a fetch below learns when it is missing),
# else the remote-tracking ref of the branch the primary checkout's HEAD names,
# with a note; with no remote, that branch itself, or HEAD when the primary is
# detached. Full names, since a tag or branch called `origin/<b>` shadows the
# short one in git's lookup. Returns non-zero when a remote exists and neither
# names a branch.
default_ref() {
  if git -C "$1" remote get-url origin >/dev/null 2>&1; then
    _dr_b=$(git -C "$1" symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null) || _dr_b=""
    case $_dr_b in
      refs/remotes/origin/?*)
        printf '%s' "$_dr_b"
        return 0
        ;;
    esac
    _dr_head=$(primary_branch "$1")
    [ -n "$_dr_head" ] || return 1
    printf '%s\n' "dispatch-fetch: origin records no HEAD branch for '$(sanitize_printable "$1")'; reading the primary checkout's branch '$(sanitize_printable "$_dr_head")' as its default" >&2
    printf 'refs/remotes/origin/%s' "$_dr_head"
    return 0
  fi
  _dr_head=$(primary_branch "$1")
  if [ -n "$_dr_head" ]; then
    printf 'refs/heads/%s' "$_dr_head"
  else
    printf 'HEAD'
  fi
}

# ref_label <ref>: the short name an anchor record prints for a full ref.
ref_label() {
  case $1 in
    refs/remotes/?*) printf '%s' "${1#refs/remotes/}" ;;
    refs/heads/?*) printf '%s' "${1#refs/heads/}" ;;
    *) printf '%s' "$1" ;;
  esac
}

# primary_branch <repo>: the branch <repo>'s primary checkout has checked out,
# or nothing when it is detached. Run only when the remote names no HEAD, since
# finding the primary costs a resolver run.
primary_branch() {
  _pb_prim=$(cd -- "$1" && env -u PLANWRIGHT_REPO_ROOT /bin/sh "$script_dir/resolve-root.sh" repo --primary 2>/dev/null) || _pb_prim=$1
  _pb_ref=$(git -C "$_pb_prim" symbolic-ref --quiet HEAD 2>/dev/null) || return 0
  case $_pb_ref in
    refs/heads/?*) printf '%s' "${_pb_ref#refs/heads/}" ;;
  esac
}

# fetch_origin <repo> <attempts>: the bounded fetch. `--refmap=''` disables
# config-driven opportunistic ref updates and the explicit
# `+refs/heads/*:refs/remotes/origin/*` pins the update to remote-tracking
# refs, so a non-default refspec can never fast-forward a local branch: the
# read-only-local-`main` invariant holds by construction. Nothing reads
# FETCH_HEAD here, and leaving it alone keeps a gate from replacing the one an
# operator's own fetch-then-merge in a holder is about to read. A remote HEAD git
# has not recorded is learned afterwards (`remote set-head --auto` writes only
# refs/remotes/origin/HEAD), so default_ref reads the remote's own default.
fetch_origin() {
  _fo_try=0
  while [ "$_fo_try" -lt "$2" ]; do
    _fo_try=$((_fo_try + 1))
    if git -C "$1" fetch origin --refmap='' --no-write-fetch-head \
      '+refs/heads/*:refs/remotes/origin/*' --quiet >/dev/null 2>&1; then
      git -C "$1" symbolic-ref --quiet refs/remotes/origin/HEAD >/dev/null 2>&1 \
        || git -C "$1" remote set-head origin --auto >/dev/null 2>&1 || :
      return 0
    fi
    if [ "$_fo_try" -lt "$2" ] && [ "$retry_sleep" -gt 0 ]; then
      sleep "$retry_sleep"
    fi
  done
  return 1
}

# emit_anchor <work-ref>...: print the anchor record from the bundle's primary
# view, or return non-zero with no record: 5 when it cannot be anchored there
# (never gate on a missing anchor, D-9), 4 when the holder's fetch failed
# (never anchor a stale ref). In same-repo the work repository's refs are
# tried in order; a holder is fetched (bounded, no TTL: a holder's fetch is
# never coalesced with the work repository's sweep) and read at its own
# default branch, recorded as store:<ref>; a plain root is read as files.
# Without --spec there is nothing to require: return 0.
emit_anchor() {
  [ "$spec_given" -eq 1 ] || return 0
  [ -x "$anchor_script" ] || printf '%s\n' "dispatch-fetch: anchor computer $(sanitize_printable "$anchor_script") missing/not executable; no anchor emitted" >&2
  case $spec_posture in
    same-repo)
      for _r in "$@"; do
        if _hash=$(anchor_at_ref "$repo_root" "$_r"); then
          printf 'anchor%s%s%s%s\n' "$TAB" "$_hash" "$TAB" "$(ref_label "$_r")"
          return 0
        fi
      done
      printf '%s\n' "dispatch-fetch: the spec anchor is unresolvable at the default branch ($(sanitize_printable "$*")); parking rather than gating on a stale/missing anchor" >&2
      return 5
      ;;
    separate-repo)
      if git -C "$store_top" remote get-url origin >/dev/null 2>&1; then
        if ! fetch_origin "$store_top" "$max_attempts"; then
          printf 'store-fetch%sstale-transient\n' "$TAB"
          printf '%s\n' "dispatch-fetch: the holder's fetch failed; parking rather than gating on a stale holder" >&2
          return 4
        fi
        printf 'store-fetch%sfetched\n' "$TAB"
      else
        printf 'store-fetch%sno-remote\n' "$TAB"
      fi
      if _r=$(default_ref "$store_top") && _hash=$(anchor_at_ref "$store_top" "$_r"); then
        printf 'anchor%s%s%sstore:%s\n' "$TAB" "$_hash" "$TAB" "$(ref_label "$_r")"
        return 0
      fi
      printf '%s\n' "dispatch-fetch: the spec anchor is unresolvable at the holder's default branch; parking rather than gating on a missing anchor" >&2
      return 5
      ;;
    plain)
      if [ -x "$anchor_script" ] && _hash=$("$anchor_script" "$spec_dir" 2>/dev/null) && [ -n "$_hash" ]; then
        printf 'anchor%s%s%sfiles\n' "$TAB" "$_hash" "$TAB"
        return 0
      fi
      printf '%s\n' "dispatch-fetch: the spec anchor is unresolvable over the plain root's files; parking rather than gating on a missing anchor" >&2
      return 5
      ;;
  esac
  return 5
}

# emit_current_anchor: the anchor on a success (exit-0) path, failing CLOSED.
# In same-repo it MUST come from the fetched remote default branch, the very
# ref the gate compares against: there is no fallback to a stale local branch
# under a success exit, which would let the caller gate on a stale anchor (the
# silent-stale-gate D-9 forbids). The caller parks on any nonzero.
emit_current_anchor() {
  [ "$spec_posture" = same-repo ] || {
    emit_anchor
    return
  }
  if _cr=$(default_ref "$repo_root"); then
    emit_anchor "$_cr"
    return
  fi
  printf '%s\n' "dispatch-fetch: fetch succeeded but the remote's default branch is unknown (no recorded origin/HEAD and a detached primary checkout); parking rather than gating on a guessed branch" >&2
  return 5
}

# --- Structural no-remote: offline is first-class ----------------------------
if ! git -C "$repo_root" remote get-url origin >/dev/null 2>&1; then
  printf 'fetch%sno-remote\n' "$TAB"
  # Degrade the anchor to the local default branch (the only view available),
  # then HEAD. With --spec, if neither can be anchored there is no content
  # baseline, so we park (exit 5, or 4 on a failed holder fetch) rather than
  # exit 3 with no anchor — keeping the --spec guarantee (anchor record OR
  # nonzero park) intact offline.
  if [ "$spec_posture" = same-repo ]; then
    emit_anchor "$(default_ref "$repo_root")" HEAD || exit $?
  else
    emit_anchor || exit $?
  fi
  exit 3
fi

# --- TTL bound: reuse a recent fetch, no network on an idle --watch cycle -----
within_ttl=0
if [ -n "$now" ] && [ -f "$stamp_file" ] && [ ! -L "$stamp_file" ]; then
  last=$(cat "$stamp_file" 2>/dev/null || true)
  # Same leading-zero rejection as the numeric env overrides above: `last` is fed
  # straight into `$((now - last))`, so a corrupted stamp like `09` (all digits,
  # passes `*[!0-9]*`) would be an invalid octal literal inside `$(( ))` and abort
  # the script fatally under dash, outside the {0,2,3,4,5} exit contract. Treat a
  # leading-zero stamp as unreadable (re-fetch, the safe direction).
  case "$last" in
    '' | *[!0-9]* | 0?*) last="" ;;
  esac
  if [ -n "$last" ]; then
    age=$((now - last))
    # A stamp in the future (clock skew) reads as fresh, not as an ancient
    # negative age; only a genuinely older-than-TTL stamp re-fetches.
    if [ "$age" -lt 0 ] || [ "$age" -lt "$ttl_sec" ]; then
      within_ttl=1
    fi
  fi
fi

if [ "$within_ttl" -eq 1 ]; then
  printf 'fetch%sfresh-within-ttl\n' "$TAB"
  emit_current_anchor || exit $?
  exit 0
fi

# --- Bounded fetch with retry (fetch_origin). On success stamp the TTL; on
# repeated failure DO NOT stamp (so the next call retries) and report
# stale-transient. ---
fetched=0
fetch_origin "$repo_root" "$max_attempts" && fetched=1

if [ "$fetched" -ne 1 ]; then
  # Present remote, fetch failed after the bounded retries: never a silent stale
  # gate. Report stale-transient and print NO anchor; the caller blocks or
  # proceeds only under an explicit operator stale flag.
  printf 'fetch%sstale-transient\n' "$TAB"
  exit 4
fi

# Success: record the TTL stamp (best-effort; a write failure is non-fatal — it
# only forfeits the coalescing, never correctness). Write to a temp file and
# rename over the target: atomic against a concurrent reader (no torn read), and
# it replaces a pre-planted symlink rather than following it (symmetric with the
# symlink-refusing read above).
if mkdir -p -- "$state_dir" 2>/dev/null; then
  stamp_tmp="$stamp_file.tmp.$$"
  # Stamp the instant the fetch COMPLETED, not the pre-fetch gate-entry instant
  # ($now used for the age check above): the TTL measures time since the ref was
  # made current, so a slow (retried) fetch must not shorten the next window by
  # its own duration. Fall back to $now if this clock read fails; if that too is
  # unavailable (both clock reads failed, $now empty), skip the stamp rather than
  # write a non-numeric one — a missing stamp simply forfeits the next window's
  # coalescing, which is harmless, whereas a blank stamp is dead weight.
  stamp_now=$(date +%s 2>/dev/null) || stamp_now=$now
  case "$stamp_now" in '' | *[!0-9]*) stamp_now="" ;; esac
  if [ -n "$stamp_now" ] && printf '%s\n' "$stamp_now" >"$stamp_tmp" 2>/dev/null; then
    mv -f -- "$stamp_tmp" "$stamp_file" 2>/dev/null || rm -f -- "$stamp_tmp" 2>/dev/null || true
  fi
fi

printf 'fetch%sfetched\n' "$TAB"
emit_current_anchor || exit $?
exit 0
