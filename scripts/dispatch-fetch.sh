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
# and reports the currency + (with --spec) the content anchor over the fetched
# `origin/main`, WITHOUT advancing local `main` (the shared-checkout read-only-
# local-`main` invariant, orchestration-concurrency). The fetch pins an explicit
# `+refs/heads/*:refs/remotes/origin/*` refspec, so it updates only
# remote-tracking refs and never fast-forwards local `main`, independent of the
# repo's configured `remote.origin.fetch`. It makes no model/API call — the whole
# decision path is deterministic git plumbing (REQ-E1.3).
#
# Scope boundary (D-9): this is git-ref currency for the dispatch/merge path
# only. It RE-POINTS the existing content-anchor computer (scripts/spec-anchor.sh)
# at the fetched ref; it does not implement anchor-hash comparison (that is
# `anchor-integrity`'s), and it does not touch the release-publish version-
# derivation path (`release-hardening`'s). Merge detection itself stays in
# scripts/orchestrate-state.sh — this primitive only makes `origin/main` current
# so that engine's existing union scan reads a fresh ref.
#
# Usage: dispatch-fetch.sh [--spec <repo-rel-spec-dir>] [--best-effort] <repo-root>
#   <repo-root>            the primary checkout to fetch in (fetch runs there;
#                          local `main` is never advanced).
#   --spec <specs/<name>>  also compute and print the content anchor over the
#                          resolved ref's version of that spec bundle.
#   --best-effort          single fetch attempt (no retries) for the reconcile
#                          sweep, so a down remote does not stall each idle cycle.
#
# Output — a tagged TSV stream on stdout (consumers switch on column 1):
#   fetch<TAB><fetched|fresh-within-ttl|no-remote|stale-transient>
#   anchor<TAB><hash><TAB><ref>   (only with --spec, when an anchor is computed)
#
# Exit codes:
#   0  remote current (fetched, or fresh-within-ttl — a prior fetch is still
#      within the TTL, so no network I/O ran). The gate proceeds against
#      origin/main; with --spec, an `origin/main` anchor line is guaranteed
#      present (a success exit never carries a stale or missing anchor).
#   3  no-remote — structurally offline (no `origin` remote). Offline is
#      first-class: the caller proceeds DEGRADED, and with --spec the anchor is
#      computed against local `main` (the only ref available).
#   4  stale-transient — a present remote's fetch failed after the bounded
#      retries. The caller MUST NOT silently proceed against a stale ref: block,
#      or proceed only under an explicit operator stale flag. No anchor is
#      printed (never anchor a stale ref).
#   5  anchor-unresolved — the fetch/currency succeeded but, with --spec, the
#      spec content anchor could not be computed at origin/main (ref unresolved,
#      bundle absent there, or the anchor computer failed). No anchor is printed;
#      the caller MUST NOT gate against a stale/missing anchor — park. Fail
#      closed rather than fall back to a stale local `main` under a success exit.
#   2  usage / invalid input / internal failure (fail closed).
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
script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2
if [ -r "$script_dir/echo-safety.sh" ]; then
  # shellcheck source=scripts/echo-safety.sh
  . "$script_dir/echo-safety.sh"
else
  # Fallback keeps the script functional if the sibling lib is absent: strips C0,
  # DEL, and C1 (0x80-0x9F, including single-byte CSI 0x9B) — byte-identical scope
  # to the canonical sanitize_printable.
  sanitize_printable() { printf '%s' "$1" | tr -d '\000-\037\177\200-\237'; }
fi

usage() {
  printf '%s\n' "usage: dispatch-fetch.sh [--spec <specs/<name>>] [--best-effort] <repo-root>" >&2
  exit 2
}

spec_rel=""
spec_given=0
repo_root=""
best_effort=0
while [ $# -gt 0 ]; do
  case "$1" in
    --spec)
      [ $# -ge 2 ] || usage
      spec_rel="$2"
      spec_given=1
      shift 2
      ;;
    --spec=*)
      spec_rel="${1#--spec=}"
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
# success exit is contracted to carry an origin/main anchor), so fail closed
# here rather than downgrade to currency-only. (A realistic `--spec specs/<name>`
# with an empty name is already caught by the grammar below; this closes the
# literally-empty flag.)
if [ "$spec_given" -eq 1 ] && [ -z "$spec_rel" ]; then
  printf '%s\n' "dispatch-fetch: --spec requires a non-empty 'specs/<name>' value" >&2
  exit 2
fi

# Validate the spec path against traversal / injection before it reaches
# `git show <ref>:<path>`. It must be a plain `specs/<identifier>` under the
# repo (the identifier grammar: REQ-A1.8). Anything else fails closed.
if [ -n "$spec_rel" ]; then
  case "$spec_rel" in
    specs/*) : ;;
    *)
      printf '%s\n' "dispatch-fetch: --spec must be 'specs/<name>' (got '$(sanitize_printable "$spec_rel")')" >&2
      exit 2
      ;;
  esac
  spec_name="${spec_rel#specs/}"
  case "$spec_name" in
    '' | */* | *[!a-z0-9-]* | [!a-z0-9]*)
      printf '%s\n' "dispatch-fetch: invalid spec name in '$(sanitize_printable "$spec_rel")'" >&2
      exit 2
      ;;
  esac
fi

# Repo-root must be inside a git work tree; resolve its top so refs/paths are
# unambiguous regardless of the caller's cwd.
repo_top=$(cd "$repo_root" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null) || repo_top=""
if [ -z "$repo_top" ]; then
  printf '%s\n' "dispatch-fetch: '$(sanitize_printable "$repo_root")' is not inside a git work tree" >&2
  exit 2
fi
repo_root=$repo_top

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
# Re-point the EXISTING content-anchor computer at <ref> by materializing that
# ref's four spec files and running scripts/spec-anchor.sh over them. Prints the
# anchor on success; returns non-zero (prints nothing) if the ref does not
# resolve, a file is missing at that ref, or spec-anchor fails. Reuses the
# shipped anchor computer — no hash logic is re-implemented here (D-9).
anchor_at_ref() {
  _ref="$1"
  git -C "$repo_root" rev-parse --verify --quiet "$_ref^{commit}" >/dev/null 2>&1 || return 1
  [ -x "$anchor_script" ] || return 1
  _td=$(mktemp -d "${TMPDIR:-/tmp}/dispatch-fetch-anchor.XXXXXX") || return 1
  _ok=1
  for _f in requirements.md design.md tasks.md test-spec.md; do
    if ! git -C "$repo_root" show "$_ref:$spec_rel/$_f" >"$_td/$_f" 2>/dev/null; then
      _ok=0
      break
    fi
  done
  if [ "$_ok" -eq 1 ]; then
    _a=$("$anchor_script" "$_td" 2>/dev/null) || _a=""
  else
    _a=""
  fi
  rm -rf "$_td"
  [ -n "$_a" ] || return 1
  printf '%s' "$_a"
}

# Emit the anchor record for a resolved ref, falling back through a ref list.
# Prints nothing (no record) if none of the refs can be anchored.
emit_anchor() {
  [ -n "$spec_rel" ] || return 0
  # Distinguish an unusable anchor computer from "files absent at the ref": both
  # yield no anchor line, but only the former is a tooling fault worth a note.
  [ -x "$anchor_script" ] || printf '%s\n' "dispatch-fetch: anchor computer $anchor_script missing/not executable; no anchor emitted" >&2
  for _r in "$@"; do
    if _hash=$(anchor_at_ref "$_r"); then
      printf 'anchor%s%s%s%s\n' "$TAB" "$_hash" "$TAB" "$_r"
      return 0
    fi
  done
  return 0
}

# Emit the anchor over the CURRENT origin/main on a success (exit-0) path,
# failing CLOSED. With --spec the anchor MUST come from origin/main — the very
# ref the gate compares against: if it cannot be computed there (origin/main
# unresolved, the bundle absent at that ref, or the anchor computer failing),
# there is no current baseline, so we must not silently fall back to a stale
# local `main` or emit nothing under a success exit — either would let the caller
# gate on a stale or missing anchor (the silent-stale-gate D-9 forbids). Print no
# anchor, note the reason, return 5 (the caller parks on any nonzero). With no
# --spec there is nothing to require: return 0.
emit_anchor_strict() {
  [ -n "$spec_rel" ] || return 0
  if _hash=$(anchor_at_ref origin/main); then
    printf 'anchor%s%s%sorigin/main\n' "$TAB" "$_hash" "$TAB"
    return 0
  fi
  [ -x "$anchor_script" ] || printf '%s\n' "dispatch-fetch: anchor computer $anchor_script missing/not executable" >&2
  printf '%s\n' "dispatch-fetch: fetch succeeded but the spec anchor is unresolvable at origin/main; parking rather than gating on a stale/missing anchor" >&2
  return 5
}

# --- Structural no-remote: offline is first-class ----------------------------
if ! git -C "$repo_root" remote get-url origin >/dev/null 2>&1; then
  printf 'fetch%sno-remote\n' "$TAB"
  # Degrade the anchor to local main (the only ref available), then HEAD.
  emit_anchor main HEAD
  exit 3
fi

# --- TTL bound: reuse a recent fetch, no network on an idle --watch cycle -----
within_ttl=0
if [ -n "$now" ] && [ -f "$stamp_file" ] && [ ! -L "$stamp_file" ]; then
  last=$(cat "$stamp_file" 2>/dev/null || echo "")
  case "$last" in
    '' | *[!0-9]*) last="" ;;
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
  emit_anchor_strict || exit $?
  exit 0
fi

# --- Bounded fetch with retry. `git fetch origin` updates remote-tracking refs
# only and never advances local `main`. On success stamp the TTL; on repeated
# failure DO NOT stamp (so the next call retries) and report stale-transient. ---
attempt=0
max_attempts=$((retries + 1))
fetched=0
while [ "$attempt" -lt "$max_attempts" ]; do
  attempt=$((attempt + 1))
  # Isolate the fetch from the repo's configured `remote.origin.fetch`:
  # `--refmap=''` disables config-driven opportunistic ref updates, and the
  # explicit `+refs/heads/*:refs/remotes/origin/*` pins the update to
  # remote-tracking refs. Together they guarantee a non-default refspec (e.g. one
  # mapping into `refs/heads/*`) can never fast-forward local `main` — the
  # read-only-local-`main` invariant holds by construction, not by config
  # convention or git's checked-out-branch guard.
  if git -C "$repo_root" fetch origin --refmap='' \
    '+refs/heads/*:refs/remotes/origin/*' --quiet >/dev/null 2>&1; then
    fetched=1
    break
  fi
  if [ "$attempt" -lt "$max_attempts" ] && [ "$retry_sleep" -gt 0 ]; then
    sleep "$retry_sleep"
  fi
done

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
if mkdir -p "$state_dir" 2>/dev/null; then
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
    mv -f "$stamp_tmp" "$stamp_file" 2>/dev/null || rm -f "$stamp_tmp" 2>/dev/null || true
  fi
fi

printf 'fetch%sfetched\n' "$TAB"
# The gate reads the fetched origin/main. With --spec the anchor must come from
# origin/main; fail closed (exit 5, no anchor) rather than fall back to a stale
# local `main` under this success exit, so the caller never gates on a
# stale/missing anchor. The caller parks on any nonzero.
emit_anchor_strict || exit $?
exit 0
