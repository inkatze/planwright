#!/bin/sh
# tasks-pr-sync.sh — PostToolUse hook (matcher: Bash). Syncs the matching
# spec's tasks.md when `gh pr create` / `gh pr merge` runs on a
# convention-named branch (Task 6: REQ-K1.2, REQ-K1.4, D-36, D-44).
#
# Transition map: `gh pr create` moves the task block to "## In progress"
# with `- **Status:** PR #<n> draft`; `gh pr merge` moves it to
# "## Completed" with `- **Status:** Completed · PR #<n> merged <date>`.
# The full task block moves intact — definition content (Deliverables /
# Done when / Dependencies / Citations / Estimated effort) is preserved
# byte-for-byte so a hook move never changes the spec content anchor
# (REQ-F1.9; scripts/spec-anchor.sh excludes placement and annotations).
#
# Input validation before any path use (REQ-K1.2): the parsed `<spec>`
# segment must match the REQ-A1.8 charset (`^[a-z0-9][a-z0-9-]*$`, max 64)
# and the `<id>` segment the D-36 task-id grammar
# (`^[0-9]+(\.[0-9]+)?(-[0-9]+(\.[0-9]+)?)?$`); the resolved tasks.md path
# is containment-checked under <primary>/specs/ after symlink resolution.
# The reserved `planwright/<spec>/spec` namespace no-ops (D-44). Any
# validation failure is a clean silent no-op (exit 0).
#
# Worker sessions: the hook fires inside worktrees, so it resolves and
# writes the canonical tasks.md in the PRIMARY checkout (kickoff brief risk
# row 3), under the per-spec advisory lock at specs/<spec>/.orchestrate.lock.
# That lock is acquired and released through the ONE shared primitive,
# scripts/orchestrate-lock.sh (D-4, REQ-D1.1) — the hook carries no acquire or
# stale-break logic of its own. A busy or unavailable lock is a clean no-op
# (`/orchestrate --bookkeeping` reconciles the dropped event); the primitive
# breaks a lock older than stale_lock_threshold (D-10; default 15m, local
# override in <primary>/.claude/planwright.local.yml). The hook never commits:
# commit ownership for hook writes is an open design item (kickoff brief,
# deferred backlog), and D-41's commit_on_state_move toggle belongs to
# /orchestrate.
#
# Diagnostics go to stderr; no-op cases are silent so PostToolUse noise
# never reaches the transcript on unrelated Bash calls.
#
# Portable POSIX sh + awk + git (bash 3.2 / BSD compatible, no eval;
# untrusted input is treated as data only, REQ-K1.5).
set -eu

# Pin the C locale: bracket expressions below must mean exactly their ASCII
# range on every host.
LC_ALL=C
export LC_ALL

# A user CDPATH would make cd echo into command substitutions and corrupt
# the derived paths.
unset CDPATH

log() { printf 'tasks-pr-sync: %s\n' "$*" >&2; }

# The shared advisory-lock primitive ships beside this hook (REQ-D1.1). A
# missing/non-executable sibling is a broken install: stay fail-soft (this is
# a PostToolUse hook) and let the lock step skip below rather than aborting.
hook_dir=$(cd "$(dirname "$0")" 2>/dev/null && pwd) || hook_dir=""
lock_sh="$hook_dir/orchestrate-lock.sh"

input=$(cat 2>/dev/null) || input=""
[ -n "$input" ] || exit 0

command -v git >/dev/null 2>&1 || exit 0
if ! command -v jq >/dev/null 2>&1; then
  log "jq missing; skipping"
  exit 0
fi

# One jq pass covers the tool check and the command extraction: this hook
# runs after every Bash call, so the no-op path stays one process deep.
cmd=$(printf '%s' "$input" \
  | jq -r 'if .tool_name == "Bash" then (.tool_input.command // empty) else empty end' \
    2>/dev/null) || cmd=""
[ -n "$cmd" ] || exit 0

# Match an actual `gh pr create` / `gh pr merge` invocation (at command
# start or after a shell separator), not a mere substring mention:
# PostToolUse fires after every Bash call, and a loose match would rewrite
# tasks.md on unrelated commands that merely quote the string.
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

# The command's stdout is only needed past this point (PR-number
# extraction); Bash sends tool_response as an object with .stdout, but stay
# shape-defensive (risk row 17).
out=$(printf '%s' "$input" \
  | jq -r '.tool_response | if type == "object" then (.stdout // "") else tostring end' \
    2>/dev/null) || out=""

# --- PR number, from (in order): the PR URL in the command's stdout, a
# "#<n>" in stdout, an explicit number argument, `gh pr view` (REQ-K1.6:
# gh absent or unauthenticated degrades to a clean no-op).
pr_num=$(printf '%s' "$out" \
  | grep -oE 'https://github\.com/[^/[:space:]]+/[^/[:space:]]+/pull/[0-9]+' \
  | head -1 | grep -oE '[0-9]+$') || pr_num=""
if [ -z "$pr_num" ]; then
  pr_num=$(printf '%s' "$out" | grep -oE '#[0-9]+' | head -1 | tr -d '#') || pr_num=""
fi
if [ -z "$pr_num" ]; then
  pr_num=$(printf '%s' "$cmd" \
    | grep -oE "gh[[:space:]]+pr[[:space:]]+${action}[[:space:]]+[0-9]+" \
    | head -1 | grep -oE '[0-9]+$') || pr_num=""
fi
if [ -z "$pr_num" ] && command -v gh >/dev/null 2>&1; then
  pr_num=$(gh pr view --json number --jq .number 2>/dev/null) || pr_num=""
fi
case $pr_num in
  '' | *[!0-9]*)
    log "could not determine PR number; skipping ($action)"
    exit 0
    ;;
esac

# --- Branch. `gh pr create` always runs on the head branch; `gh pr merge`
# often runs elsewhere (e.g. main), so fall back to the PR's headRefName.
# The gh-supplied value goes through the same validation as a git one.
branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null) || branch=""
case $branch in
  planwright/*) ;;
  *)
    if [ "$action" = merge ] && command -v gh >/dev/null 2>&1; then
      branch=$(gh pr view "$pr_num" --json headRefName --jq .headRefName 2>/dev/null) \
        || branch=""
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

# --- Resolve the PRIMARY checkout (risk row 3): worktree-resident runs
# must write the canonical tasks.md, not the worktree copy.
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

# --- Containment (REQ-K1.2): the resolved spec dir must sit under
# <primary>/specs/ after symlink resolution, and tasks.md must not itself
# be a symlink pointing elsewhere.
specs_root="$primary/specs"
spec_dir="$specs_root/$spec"
tasks_md="$spec_dir/tasks.md"
[ -f "$tasks_md" ] || exit 0
[ ! -L "$tasks_md" ] || {
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
tasks_md="$canon_dir/tasks.md"

# --- Advisory lock (D-10), acquired through the ONE shared primitive
# (REQ-D1.1): no inline mkdir/stale-break logic lives here. The primitive owns
# threshold resolution (stale_lock_threshold via config-get, default 15m),
# the atomic mkdir, the stale-break, and the REQ-F1.1 grammar/containment
# checks on the lock path. $canon_dir is already validated + contained under
# <primary>/specs above; the primitive re-validates it (defense in depth).
#
# The hook's failure policy is fail-soft: ANY non-zero acquire (busy=1,
# error/refusal=2, or a broken-install 127) is a clean no-op that
# `/orchestrate --bookkeeping` reconciles — the policy lives here, off the
# primitive's one exit-code contract (REQ-D1.2).
if [ ! -x "$lock_sh" ]; then
  log "lock primitive '$lock_sh' missing or not executable; skipping (bookkeeping reconciles)"
  exit 0
fi
lock_rc=0
"$lock_sh" acquire "$canon_dir" || lock_rc=$?
if [ "$lock_rc" -ne 0 ]; then
  log "lock unavailable (acquire exit $lock_rc); skipping (bookkeeping reconciles)"
  exit 0
fi
tmpf=""
# Release through the same primitive (idempotent rmdir), and clean any
# half-written rewrite temp. An explicit exit on a fatal signal makes the EXIT
# cleanup run under shells (dash) that skip EXIT traps on signal-default
# termination; SIGKILL remains unrecoverable and falls to the stale-break.
trap '"$lock_sh" release "$canon_dir" >/dev/null 2>&1 || true; [ -n "$tmpf" ] && rm -f "$tmpf"' EXIT
trap 'exit 130' HUP INT TERM

today=$(date -u +%Y-%m-%d)
if [ "$action" = create ]; then
  target="In progress"
  status_line="- **Status:** PR #$pr_num draft"
else
  target="Completed"
  status_line="- **Status:** Completed · PR #$pr_num merged $today"
fi
last_line="- **Last activity:** $today"

# move_block <task-id>: relocate the task's block into $target, rewriting
# only the Status / Last activity annotation bullets (other annotations,
# e.g. Dispatch, and all definition content move untouched). Atomic write
# via a same-directory temp file. awk exit codes: 3 = no such task block,
# 4 = no target section; both are logged no-ops.
move_block() {
  tmpf=$(mktemp "$canon_dir/.tasks-pr-sync.XXXXXX") || return 0
  if awk -v id="$1" -v status_line="$status_line" -v last_line="$last_line" \
    -v target="$target" '
    function is_h2(s) { return substr(s, 1, 3) == "## " }
    function is_h3(s) { return substr(s, 1, 4) == "### " }
    function is_blank(s) { return s ~ /^[[:space:]]*$/ }
    { L[NR] = $0 }
    END {
      n = NR
      p = "### Task " id " "
      h = 0
      for (i = 1; i <= n; i++) if (index(L[i], p) == 1) { h = i; break }
      if (!h) exit 3
      e = n + 1
      for (i = h + 1; i <= n; i++) if (is_h2(L[i]) || is_h3(L[i])) { e = i; break }
      be = e - 1
      while (be > h && is_blank(L[be])) be--

      # Rewrite annotations: replace the first Status / Last activity
      # bullet in place (dropping any duplicates and their wrapped
      # continuation lines), append whichever is missing at block end.
      bn = 0
      drop = 0
      done_status = 0
      done_last = 0
      for (i = h; i <= be; i++) {
        s = L[i]
        if (index(s, "- **Status:**") == 1) {
          drop = 1
          if (!done_status) { B[++bn] = status_line; done_status = 1 }
          continue
        }
        if (index(s, "- **Last activity:**") == 1) {
          drop = 1
          if (!done_last) { B[++bn] = last_line; done_last = 1 }
          continue
        }
        if (drop && s !~ /^- / && !is_blank(s)) continue
        drop = 0
        B[++bn] = s
      }
      if (!done_status) B[++bn] = status_line
      if (!done_last) B[++bn] = last_line

      th = "## " target
      ts = 0
      for (i = 1; i <= n; i++) if (L[i] == th) { ts = i; break }
      if (!ts) exit 4
      te = n + 1
      for (i = ts + 1; i <= n; i++) if (is_h2(L[i])) { te = i; break }

      # Emit: skip the old block, drop a "(none yet)" placeholder in the
      # target section, append the block at the section end with exactly
      # one blank line on each side.
      on = 0
      for (i = 1; i <= n; i++) {
        if (i >= h && i < e) continue
        if (i > ts && i < te && L[i] == "(none yet)") continue
        if (i == te) {
          while (on > 0 && is_blank(O[on])) on--
          O[++on] = ""
          for (j = 1; j <= bn; j++) O[++on] = B[j]
          O[++on] = ""
        }
        O[++on] = L[i]
      }
      if (te == n + 1) {
        while (on > 0 && is_blank(O[on])) on--
        O[++on] = ""
        for (j = 1; j <= bn; j++) O[++on] = B[j]
      }
      for (i = 1; i <= on; i++) print O[i]
      exit 0
    }
  ' "$tasks_md" >"$tmpf"; then
    # A successful rewrite of a non-empty tasks.md is never empty; an empty
    # temp file means the write itself failed (e.g. ENOSPC some awks do not
    # report). Refuse to clobber the canonical file with it.
    if [ ! -s "$tmpf" ]; then
      rm -f "$tmpf"
      tmpf=""
      log "empty rewrite output; $tasks_md unchanged"
      return 0
    fi
    mv "$tmpf" "$tasks_md"
    tmpf=""
    log "Task $1 → $target (PR #$pr_num) in $tasks_md"
  else
    rc=$?
    rm -f "$tmpf"
    tmpf=""
    case $rc in
      3) log "no Task $1 block in $tasks_md; skipping" ;;
      4) log "no '## $target' section in $tasks_md; skipping" ;;
      *) log "rewrite failed (exit $rc); $tasks_md unchanged" ;;
    esac
  fi
  return 0
}

# A bundle id (`3-4`, D-36) names two tasks; move each block.
for tid in $(printf '%s' "$ids" | tr '-' ' '); do
  move_block "$tid"
done

exit 0
