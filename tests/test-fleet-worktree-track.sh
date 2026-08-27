#!/bin/bash
# Tests for scripts/fleet-worktree-track.sh — worktree lifecycle tracking
# (Task 4: D-7; REQ-B1.2).
#
# Worktree lifecycle is PUSHED via the `WorktreeCreate`/`WorktreeRemove` hook
# events the instant they occur (a live registry, no polling), degrading to a
# manual `git worktree list` DISK SCAN (`scan`) CLI on a backend that cannot
# register the hook pair (not yet wired to run periodically — a tracked
# follow-up). Tracking is bookkeeping, not a destructive daemon action, so it is
# NOT gated by the kill-switch and does NOT spam the audit trail (kickoff risk
# 31: the trail records daemon actions, not routine lifecycle noise).
#
# THE VERIFIED HOOK CONTRACT (operator-verified across CLI 2.1.226–2.1.234;
# obs:2036d463 / obs:16facd5b). `WorktreeCreate` input is
# `{hook_event_name, name}` — never `worktree_path` — and a registered hook
# REPLACES native creation: the hook IS the creator and its stdout path is the
# decision-control result (missing path or non-zero exit fails creation). So
# `hook-create` reads `.name`, grammar-checks it, creates
# `<repo>/.claude/worktrees/<name>` on a fresh `worktree-<flattened>` branch,
# echoes the created path, and ALWAYS exits 0 — every refusal echoes nothing.
# `WorktreeRemove` keeps its genuinely different `worktree_path` shape and is
# fire-and-forget.
#
# What is covered:
#   - record-create then record-remove update the live registry (push tracking),
#     observable via `list`, with NO disk scan involved;
#   - record-create is idempotent (no duplicate rows);
#   - the disk-scan fallback (`scan`) discovers a real linked worktree git knows
#     about that no hook ever pushed;
#   - `hook-create` CREATES the worktree from the stdin `name` (flat and nested),
#     echoes its physical path, records it, exits 0 — and is idempotent on an
#     already-created target; the sed fallback covers a jq-less host, and a
#     failed registry write never fails creation;
#   - `hook-create` refusals echo NOTHING, create nothing, and still exit 0:
#     malformed names (control byte, traversal, dash-led or dot-only segment,
#     over-length), an absent name, a non-git cwd, a branch collision, an
#     existing non-worktree target, and the un-parseable escaped name on the
#     sed fallback;
#   - `hook-remove` records a removal from its stdin payload and exits 0;
#   - hostile / non-absolute paths are refused by the direct CLI (exit non-zero).
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

# 3b. list enforces the emitted-path grammar (valid_path), not just control-byte
#     stripping. A malformed registry line (non-absolute, or a leading dash) —
#     from a corrupted store or a scan write that bypassed the grammar — is
#     SKIPPED with a warning, never emitted to a caller like fleet-sweep.sh that
#     would `cd` into it relative to its own cwd. Valid entries still emit.
rm -rf "$fleet_home"
wt record-create /work/worktrees/good >/dev/null || fail "list-grammar: record-create (good) failed"
reg="$fleet_home/worktrees/registry"
[ -f "$reg" ] || fail "list-grammar: registry file not found at $reg"
# Inject malformed lines directly, bypassing record-create's own valid_path.
printf '%s\n' 'relative/not/absolute' '-leadingdash/path' >>"$reg"
listing=$(wt list 2>/dev/null)
case $listing in
  *"/work/worktrees/good"*) ;;
  *) fail "list-grammar: dropped a valid entry (got: '$listing')" ;;
esac
case $listing in
  *"relative/not/absolute"*) fail "list emitted a non-absolute registry entry" ;;
esac
case $listing in
  *"-leadingdash/path"*) fail "list emitted a leading-dash registry entry" ;;
esac
# The skip must surface a warning on stderr, not drop silently.
warned=$(wt list 2>&1 >/dev/null)
case $warned in
  *"malformed worktree registry entry"*) ;;
  *) fail "list-grammar: no warning emitted for a skipped malformed entry" ;;
esac
echo "ok: list enforces valid_path on read, skipping malformed registry entries with a warning"

# 4. hook-create: the creator contract — create <repo>/.claude/worktrees/<name>
#    from the stdin name, echo the created physical path, exit 0, AND record it.
rm -rf "$fleet_home"
main_real=$(cd "$main_repo" && pwd -P)
payload='{"hook_event_name":"WorktreeCreate","name":"hooked-wt"}'
rc=0
out=$(cd "$main_repo" && printf '%s' "$payload" | wt hook-create) || rc=$?
[ "$rc" = 0 ] || fail "hook-create exit $rc, expected 0 (must never fail creation)"
[ "$out" = "$main_real/.claude/worktrees/hooked-wt" ] \
  || fail "hook-create must echo the created path (got: '$out')"
[ -d "$out" ] || fail "hook-create did not create the worktree directory"
(cd "$main_repo" && git worktree list --porcelain | grep -Fxq "worktree $out") \
  || fail "created directory is not a registered git worktree"
(cd "$main_repo" && git show-ref --verify --quiet refs/heads/worktree-hooked-wt) \
  || fail "hook-create did not create the worktree-hooked-wt branch"
case $(wt list) in
  *"$out"*) ;;
  *) fail "hook-create did not record the worktree" ;;
esac
echo "ok: hook-create creates the worktree, echoes its path, exits 0, and records"

# 4a. hook-create idempotent reattach: the same payload again echoes the SAME
#     path (no re-create, no failure), exit 0. Then a NESTED name creates the
#     nested placement on a flattened branch.
rc=0
out2=$(cd "$main_repo" && printf '%s' "$payload" | wt hook-create) || rc=$?
[ "$rc" = 0 ] || fail "hook-create (reattach) exit $rc, expected 0"
[ "$out2" = "$out" ] || fail "hook-create reattach must echo the same path (got: '$out2')"
nested='{"hook_event_name":"WorktreeCreate","name":"planwright/demo/task-1"}'
rc=0
out3=$(cd "$main_repo" && printf '%s' "$nested" | wt hook-create) || rc=$?
[ "$rc" = 0 ] || fail "hook-create (nested name) exit $rc, expected 0"
[ "$out3" = "$main_real/.claude/worktrees/planwright/demo/task-1" ] \
  || fail "hook-create nested path wrong (got: '$out3')"
(cd "$main_repo" && git show-ref --verify --quiet refs/heads/worktree-planwright-demo-task-1) \
  || fail "nested name did not flatten into the worktree-planwright-demo-task-1 branch"
echo "ok: hook-create reattaches idempotently and nests multi-segment names"

# 4b. hook-create with jq absent: the sed fallback still extracts the name.
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
out=$(cd "$main_repo" && printf '%s' '{"hook_event_name":"WorktreeCreate","name":"nojq-wt"}' \
  | PATH="$nojq" PLANWRIGHT_FLEET_STATE_DIR="$fleet_home" /bin/bash "$WT" hook-create) || rc=$?
[ "$rc" = 0 ] || fail "hook-create (no jq) exit $rc, expected 0"
[ "$out" = "$main_real/.claude/worktrees/nojq-wt" ] \
  || fail "hook-create (no jq) must create via the sed fallback (got: '$out')"
echo "ok: hook-create extracts the name via the sed fallback when jq is absent"

# 4c. hook-create never fails creation even if the registry write cannot happen
#     (fleet home points at an unwritable location): still creates + echoes,
#     exit 0.
rc=0
unwr="$tmp/unwritable"
: >"$unwr" # a FILE where a dir is expected: the registry write cannot succeed
out=$(cd "$main_repo" && printf '%s' '{"hook_event_name":"WorktreeCreate","name":"unrec-wt"}' \
  | PLANWRIGHT_FLEET_STATE_DIR="$unwr/fleet" /bin/bash "$WT" hook-create) || rc=$?
[ "$rc" = 0 ] || fail "hook-create must exit 0 even when recording fails (got $rc)"
[ "$out" = "$main_real/.claude/worktrees/unrec-wt" ] \
  || fail "hook-create must still create and echo on a record failure (got: '$out')"
echo "ok: hook-create never fails worktree creation even when recording fails"

# 4d. hook-create refusals: every one must put NOTHING on stdout (no raw bytes
#     and no forged path on the decision channel), CREATE nothing, and STILL
#     exit 0 (never a non-zero exit, which would surface a scarier harness
#     error), recording nothing.
rm -rf "$fleet_home"
refuse() {
  # refuse <label> <payload> [<cwd>]
  r_label=$1 r_payload=$2 r_cwd=${3:-$main_repo}
  rc=0
  out=$(cd "$r_cwd" && printf '%s' "$r_payload" | wt hook-create 2>/dev/null) || rc=$?
  [ "$rc" = 0 ] || fail "hook-create ($r_label) exit $rc, expected 0"
  [ -z "$out" ] || fail "hook-create ($r_label) must echo NOTHING (got: '$out')"
}
ctrl=$(printf 'bad\001name')
refuse "control-byte name" "$(printf '{"hook_event_name":"WorktreeCreate","name":"%s"}' "$ctrl")"
refuse "traversal name" '{"hook_event_name":"WorktreeCreate","name":"a/../escape"}'
refuse "dash-led segment" '{"hook_event_name":"WorktreeCreate","name":"a/-x"}'
refuse "absolute name" '{"hook_event_name":"WorktreeCreate","name":"/etc/oops"}'
refuse "over-length name" "$(printf '{"hook_event_name":"WorktreeCreate","name":"%s"}' \
  "$(printf 'a%.0s' $(seq 1 70))")"
refuse "absent name" '{"hook_event_name":"WorktreeCreate"}'
refuse "non-git cwd" '{"hook_event_name":"WorktreeCreate","name":"stray-wt"}' "$tmp"
# Branch collision: a pre-existing worktree-clash branch refuses the name clash.
(cd "$main_repo" && git_env git branch worktree-clash >/dev/null 2>&1)
refuse "branch collision" '{"hook_event_name":"WorktreeCreate","name":"clash"}'
# Existing non-worktree directory at the target refuses.
mkdir -p "$main_repo/.claude/worktrees/squatter"
refuse "existing non-worktree target" '{"hook_event_name":"WorktreeCreate","name":"squatter"}'
[ ! -e "$main_repo/.claude/worktrees/a" ] || fail "a refused name still created something"
[ ! -e "$tmp/.claude" ] || fail "non-git cwd still created something"
[ -z "$(wt list 2>/dev/null)" ] \
  || fail "hook-create must not record a refused payload (list: '$(wt list 2>/dev/null)')"
echo "ok: hook-create refuses malformed names, non-git cwds, and collisions — nothing echoed, still exit 0"

# 4e. hook-create fails CLOSED on an un-parseable escaped name via the sed
#     fallback (jq absent). The `[^"]*` sed capture cannot JSON-unescape, so a
#     name carrying a backslash-escape would yield a WRONG name; extract_name
#     treats a backslash in the sed result as untrustworthy and returns
#     nothing, so hook-create echoes NOTHING and creates nothing. jq (the
#     primary path) unescapes correctly, and the decoded name then fails the
#     grammar anyway. Reuses the $nojq PATH built in 4b.
rm -rf "$fleet_home"
esc_q='{"hook_event_name":"WorktreeCreate","name":"a\"b"}'
rc=0
out=$(cd "$main_repo" && printf '%s' "$esc_q" \
  | PATH="$nojq" PLANWRIGHT_FLEET_STATE_DIR="$fleet_home" /bin/bash "$WT" hook-create 2>/dev/null) || rc=$?
[ "$rc" = 0 ] || fail "hook-create (no jq, escaped-quote name) exit $rc, expected 0"
[ -z "$out" ] || fail "hook-create (no jq, escaped-quote name) must echo NOTHING (fail-closed), got: '$out'"
[ -z "$(PLANWRIGHT_FLEET_STATE_DIR="$fleet_home" /bin/bash "$WT" list 2>/dev/null)" ] \
  || fail "hook-create must not record an un-parseable escaped payload"
echo "ok: hook-create fails closed on an un-parseable escaped name via the sed fallback"

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
