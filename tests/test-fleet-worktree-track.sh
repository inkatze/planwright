#!/bin/bash
# Tests for scripts/fleet-worktree-track.sh — worktree lifecycle tracking
# (Task 4: D-7; REQ-B1.2).
#
# Worktree lifecycle is PUSHED via the `WorktreeCreate`/`WorktreeRemove` hook
# events the instant they occur (a live registry, no polling), degrading to a
# periodic `git worktree list` DISK SCAN on a backend that cannot register the
# hook pair. Tracking is bookkeeping, not a destructive daemon action, so it is
# NOT gated by the kill-switch and does NOT spam the audit trail (kickoff risk
# 31: the trail records daemon actions, not routine lifecycle noise).
#
# THE VERIFIED HOOK CONTRACT (code.claude.com/docs/en/hooks.md). `WorktreeCreate`
# is a DECISION hook: a non-zero exit or missing stdout path FAILS worktree
# creation. So `hook-create` is a strict pass-through — it echoes the stdin
# `worktree_path` unchanged and ALWAYS exits 0, recording as an isolated
# best-effort side effect. `WorktreeRemove` is fire-and-forget.
#
# What is covered:
#   - record-create then record-remove update the live registry (push tracking),
#     observable via `list`, with NO disk scan involved;
#   - record-create is idempotent (no duplicate rows);
#   - the disk-scan fallback (`scan`) discovers a real linked worktree git knows
#     about that no hook ever pushed;
#   - `hook-create` echoes the stdin worktree_path and exits 0 (the decision-
#     control contract), records the path, and still does so with jq absent
#     (the sed fallback) — and even when the registry write cannot happen;
#   - `hook-create` with a malformed (control-byte / non-absolute) or absent
#     worktree_path echoes NOTHING and still exits 0, recording nothing (the
#     decision-channel blast-radius guard);
#   - `hook-remove` records a removal from its stdin payload and exits 0;
#   - hostile / non-absolute paths are refused by the direct CLI (exit non-zero)
#     yet never break the create hook's pass-through.
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-fleet-worktree-track.sh
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

# Isolate git fully from the host's global/system config: signing
# (commit.gpgsign + a 1Password/GPG signer that blocks non-interactively) and
# branch.autosetuprebase would otherwise hang or reshape the fixture commits.
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_SYSTEM=/dev/null

here=$(cd "$(dirname "$0")" && pwd)
WT="$here/../scripts/fleet-worktree-track.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -x "$WT" ] || fail "scripts/fleet-worktree-track.sh missing or not executable"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fleet_home="$tmp/fleet"

wt() {
  PLANWRIGHT_FLEET_STATE_DIR="$fleet_home" /bin/bash "$WT" "$@"
}

# 1. Push tracking: record-create makes a path show up in `list`; record-remove
#    drops it — no disk scan involved.
rm -rf "$fleet_home"
wt record-create /work/worktrees/task-2 >/dev/null || fail "record-create failed"
wt record-create /work/worktrees/task-3 >/dev/null || fail "record-create #2 failed"
listing=$(wt list)
case $listing in
  *"/work/worktrees/task-2"*) ;;
  *) fail "list did not show the created worktree (got: '$listing')" ;;
esac
case $listing in
  *"/work/worktrees/task-3"*) ;;
  *) fail "list missing the second worktree" ;;
esac
wt record-remove /work/worktrees/task-2 >/dev/null || fail "record-remove failed"
listing=$(wt list)
case $listing in
  *"/work/worktrees/task-2"*) fail "list still shows a removed worktree" ;;
esac
case $listing in
  *"/work/worktrees/task-3"*) ;;
  *) fail "record-remove dropped the wrong worktree" ;;
esac
echo "ok: record-create/record-remove push worktree lifecycle into a live registry"

# 2. record-create is idempotent (no duplicate rows).
rm -rf "$fleet_home"
wt record-create /work/wt-a >/dev/null
wt record-create /work/wt-a >/dev/null
n=$(wt list | grep -c '^/work/wt-a$' || true)
[ "$n" = 1 ] || fail "record-create not idempotent: $n rows for one path"
echo "ok: record-create is idempotent"

# 3. Disk-scan fallback: a real linked worktree git knows about, never pushed
#    by any hook, is discovered by `scan`.
git_env() {
  GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t \
    GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t "$@"
}
main_repo="$tmp/main"
git_env git init -q -b main "$main_repo"
(cd "$main_repo" && echo seed >f && git_env git add f && git_env git commit -qm seed)
linked="$tmp/linked-wt"
(cd "$main_repo" && git_env git worktree add -q -b feat "$linked" >/dev/null 2>&1)
rm -rf "$fleet_home"
wt scan "$main_repo" >/dev/null || fail "scan failed"
listing=$(wt list)
linked_real=$(cd "$linked" && pwd -P)
case $listing in
  *"$linked_real"*) ;;
  *) fail "scan did not discover the linked worktree (got: '$listing')" ;;
esac
echo "ok: the disk-scan fallback discovers a worktree no hook pushed"

# 4. hook-create: the decision-control contract — echo the stdin worktree_path
#    unchanged and exit 0, AND record it.
rm -rf "$fleet_home"
payload='{"worktree_path":"/work/hooked-wt","isolation":"worktree","session_id":"s1"}'
rc=0
out=$(printf '%s' "$payload" | wt hook-create) || rc=$?
[ "$rc" = 0 ] || fail "hook-create exit $rc, expected 0 (must never fail creation)"
[ "$out" = "/work/hooked-wt" ] || fail "hook-create must echo the worktree_path (got: '$out')"
case $(wt list) in
  *"/work/hooked-wt"*) ;;
  *) fail "hook-create did not record the worktree" ;;
esac
echo "ok: hook-create echoes the path, exits 0, and records"

# 4b. hook-create with jq absent: the sed fallback still extracts the path.
#     Build a PATH mirroring the real one MINUS jq (robust against which exact
#     coreutils the script reaches for), so only jq's absence is simulated.
rm -rf "$fleet_home"
nojq="$tmp/nojq"
mkdir -p "$nojq"
old_ifs=$IFS
IFS=:
for d in $PATH; do
  [ -d "$d" ] || continue
  for f in "$d"/*; do
    [ -e "$f" ] || continue
    b=${f##*/}
    [ "$b" = jq ] && continue
    [ -e "$nojq/$b" ] || ln -s "$f" "$nojq/$b" 2>/dev/null || true
  done
done
IFS=$old_ifs
[ ! -e "$nojq/jq" ] || fail "nojq PATH still exposes jq"
rc=0
out=$(printf '%s' "$payload" | PATH="$nojq" PLANWRIGHT_FLEET_STATE_DIR="$fleet_home" \
  /bin/bash "$WT" hook-create) || rc=$?
[ "$rc" = 0 ] || fail "hook-create (no jq) exit $rc, expected 0"
[ "$out" = "/work/hooked-wt" ] || fail "hook-create (no jq) must echo path via sed fallback (got: '$out')"
echo "ok: hook-create extracts the path via the sed fallback when jq is absent"

# 4c. hook-create never fails creation even if the registry write cannot happen
#     (fleet home points at an unwritable location): still echoes path, exit 0.
rc=0
unwr="$tmp/unwritable"
: >"$unwr" # a FILE where a dir is expected: the registry write cannot succeed
out=$(printf '%s' "$payload" | PLANWRIGHT_FLEET_STATE_DIR="$unwr/fleet" \
  /bin/bash "$WT" hook-create) || rc=$?
[ "$rc" = 0 ] || fail "hook-create must exit 0 even when recording fails (got $rc)"
[ "$out" = "/work/hooked-wt" ] || fail "hook-create must still echo the path on a record failure"
echo "ok: hook-create never fails worktree creation even when recording fails"

# 4d. hook-create with a MALFORMED or EMPTY worktree_path: the decision-control
#     safety mitigation the whole hook wiring rests on. A control-byte,
#     non-absolute, or absent worktree_path must put NOTHING on stdout (no raw
#     bytes and no forged path on the decision channel) and STILL exit 0 (never a
#     non-zero exit, which would break creation fleet-wide), recording nothing.
rm -rf "$fleet_home"
# (a) a control byte in the path: jq rejects the payload, the sed fallback yields
#     the raw path, the grammar check refuses it -> nothing echoed, exit 0.
ctrl=$(printf '/work/bad\001path')
rc=0
out=$(printf '{"worktree_path":"%s","isolation":"worktree"}' "$ctrl" | wt hook-create 2>/dev/null) || rc=$?
[ "$rc" = 0 ] || fail "hook-create (control-byte path) exit $rc, expected 0"
[ -z "$out" ] || fail "hook-create (control-byte path) must echo NOTHING on the decision channel (got: '$out')"
# (b) a non-absolute path: refused by the grammar check -> nothing echoed, exit 0.
rc=0
out=$(printf '%s' '{"worktree_path":"relative/wt","isolation":"worktree"}' | wt hook-create 2>/dev/null) || rc=$?
[ "$rc" = 0 ] || fail "hook-create (non-absolute path) exit $rc, expected 0"
[ -z "$out" ] || fail "hook-create (non-absolute path) must echo nothing (got: '$out')"
# (c) no worktree_path at all: nothing echoed, exit 0.
rc=0
out=$(printf '%s' '{"isolation":"worktree","session_id":"s1"}' | wt hook-create 2>/dev/null) || rc=$?
[ "$rc" = 0 ] || fail "hook-create (missing worktree_path) exit $rc, expected 0"
[ -z "$out" ] || fail "hook-create (missing worktree_path) must echo nothing (got: '$out')"
# None of the three may have recorded anything.
[ -z "$(wt list 2>/dev/null)" ] || fail "hook-create must not record a malformed/empty payload (list: '$(wt list 2>/dev/null)')"
echo "ok: hook-create refuses a malformed/empty worktree_path — nothing on the decision channel, still exit 0"

# 5. hook-remove: records a removal from stdin and exits 0 (fire-and-forget).
rm -rf "$fleet_home"
wt record-create /work/going >/dev/null
rc=0
printf '%s' '{"worktree_path":"/work/going","session_id":"s1"}' | wt hook-remove || rc=$?
[ "$rc" = 0 ] || fail "hook-remove exit $rc, expected 0"
case $(wt list) in
  *"/work/going"*) fail "hook-remove did not drop the worktree" ;;
esac
echo "ok: hook-remove records the removal and exits 0"

# 6. Hostile / non-absolute paths are refused by the direct CLI.
rm -rf "$fleet_home"
for bad in 'relative/path' '-x' ''; do
  rc=0
  wt record-create "$bad" >/dev/null 2>&1 || rc=$?
  [ "$rc" != 0 ] || fail "record-create accepted a hostile path '$bad'"
done
echo "ok: hostile / non-absolute paths are refused by the direct CLI"

echo "ALL PASS: fleet-worktree-track"
