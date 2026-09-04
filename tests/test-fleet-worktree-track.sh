#!/bin/bash
# Tests for scripts/fleet-worktree-track.sh — worktree lifecycle tracking
# (Task 4: D-7; REQ-B1.2).
#
# Worktree removal is PUSHED via the `WorktreeRemove` hook the instant it
# occurs (a live registry, no polling). Creation is pushed by `record-create` at
# the dispatch seam, and anything created another way is picked up by the
# `git worktree list` DISK SCAN (`scan`) — the graceful-degradation fallback
# D-7 requires. Tracking is bookkeeping, not a destructive daemon action, so it
# is NOT gated by the kill-switch and does NOT spam the audit trail (kickoff
# risk 31: the trail records daemon actions, not routine lifecycle noise).
#
# THE CORRECTED HOOK CONTRACT. `WorktreeCreate` carries a bare worktree `name`,
# and registering a hook on it REPLACES native creation — the hook becomes the
# creator. Only `WorktreeRemove` carries `worktree_path`. planwright wanted
# passive tracking, that event grants none, so it registers no `WorktreeCreate`
# hook and ships no `hook-create`; section 5 pins the retirement.
# `WorktreeRemove` is genuinely observational: it cannot prevent a removal, so
# `hook-remove` always exits 0.
#
# What is covered:
#   - record-create then record-remove update the live registry (push tracking),
#     observable via `list`, with NO disk scan involved;
#   - record-create is idempotent (no duplicate rows);
#   - the disk-scan fallback (`scan`) discovers a real linked worktree git knows
#     about that no hook ever pushed;
#   - `hook-remove` records a removal from its stdin payload and exits 0, and
#     still does so with jq absent (the sed fallback) — and even when the
#     registry write cannot happen;
#   - `hook-remove` surfaces every reason it recorded nothing — an unreadable
#     payload, and a present-but-malformed `worktree_path`, each with its own
#     message — as `systemMessage` (the channel this event shows the operator)
#     rather than on stderr the harness discards, including when jq, which builds
#     that JSON, is absent or broken; and it fails closed on an un-parseable
#     escaped path rather than dropping a mis-parsed one;
#   - `hook-create` is retired and refused by the CLI;
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

# 4. hook-remove: records a removal from its stdin payload and exits 0.
#    `WorktreeRemove` cannot be prevented by a hook and its failures are logged
#    in debug only, so this handler is observational and always exits 0.
rm -rf "$fleet_home"
wt record-create /work/hooked-wt >/dev/null
payload='{"worktree_path":"/work/hooked-wt","hook_event_name":"WorktreeRemove","session_id":"s1"}'
rc=0
out=$(printf '%s' "$payload" | wt hook-remove) || rc=$?
[ "$rc" = 0 ] || fail "hook-remove exit $rc, expected 0"
[ -z "$out" ] || fail "hook-remove must stay silent on a payload it could read (got: '$out')"
# Assert the read SUCCEEDED before reading absence into it. `case $(wt list)`
# discards the exit status, and a failing `list` prints nothing — which is
# indistinguishable from "the entry is gone", so the assertion would pass on a
# registry it never actually read. Absence checks need the status; the presence
# checks further down already fail closed on empty output.
listing=$(wt list) || fail "list failed after hook-remove, so its absence check would be vacuous"
case $listing in
  *"/work/hooked-wt"*) fail "hook-remove did not drop the worktree" ;;
esac
echo "ok: hook-remove records the removal, stays silent, and exits 0"

# 4b. hook-remove with jq absent: the sed fallback still extracts the path.
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
PLANWRIGHT_FLEET_STATE_DIR="$fleet_home" /bin/bash "$WT" record-create /work/hooked-wt >/dev/null
rc=0
printf '%s' "$payload" | PATH="$nojq" PLANWRIGHT_FLEET_STATE_DIR="$fleet_home" \
  /bin/bash "$WT" hook-remove >/dev/null 2>&1 || rc=$?
[ "$rc" = 0 ] || fail "hook-remove (no jq) exit $rc, expected 0"
# Same reasoning as the absence check in 4: take the status, or a failed read
# reads as a successful removal. The `2>/dev/null` here makes it worse, since it
# hides the diagnostic that would otherwise hint at what happened.
listing=$(PLANWRIGHT_FLEET_STATE_DIR="$fleet_home" /bin/bash "$WT" list 2>/dev/null) \
  || fail "list failed after hook-remove (no jq), so its absence check would be vacuous"
case $listing in
  *"/work/hooked-wt"*) fail "hook-remove (no jq) did not drop the worktree via the sed fallback" ;;
esac
echo "ok: hook-remove extracts the path via the sed fallback when jq is absent"

# 4c. hook-remove never breaks a removal even if the registry write cannot
#     happen (fleet home points at an unwritable location): still exit 0.
rc=0
unwr="$tmp/unwritable"
: >"$unwr" # a FILE where a dir is expected: the registry write cannot succeed
printf '%s' "$payload" | PLANWRIGHT_FLEET_STATE_DIR="$unwr/fleet" \
  /bin/bash "$WT" hook-remove >/dev/null 2>&1 || rc=$?
[ "$rc" = 0 ] || fail "hook-remove must exit 0 even when recording fails (got $rc)"
echo "ok: hook-remove never breaks a removal even when recording fails"

# 4d. hook-remove with an ABSENT worktree_path: nothing to drop, still exit 0,
#     and the reason goes out as `systemMessage` — the channel this event
#     actually surfaces (REQ-H1.3, REQ-K1.1). Stderr is discarded here, so a
#     tracking gap explained only there reaches nobody. That invisibility is
#     what made the create-side outage take a binary inspection to diagnose.
rm -rf "$fleet_home"
rc=0
out=$(printf '%s' '{"hook_event_name":"WorktreeRemove","session_id":"s1"}' | wt hook-remove 2>/dev/null) || rc=$?
[ "$rc" = 0 ] || fail "hook-remove (missing worktree_path) exit $rc, expected 0"
printf '%s' "$out" | jq -e '.systemMessage | test("scan")' >/dev/null 2>&1 \
  || fail "hook-remove must surface a systemMessage naming the remedy (got: '$out')"
echo "ok: hook-remove surfaces an unreadable payload as systemMessage, not on discarded stderr"

# 4e. hook-remove fails CLOSED on an un-parseable escaped path via the sed
#     fallback (jq absent). The `[^"]*` sed capture cannot JSON-unescape, so a
#     worktree_path carrying a backslash-escape (an embedded `"` arrives as `\"`
#     and truncates the capture; an embedded `\` arrives as `\\` and doubles)
#     would yield a WRONG path that still passes valid_path — and a wrong path
#     dropped from the registry is a tree a later reclaim stops tracking.
#     extract_worktree_path treats a backslash in the sed result as
#     untrustworthy and returns nothing, so nothing is recorded. jq (the primary
#     path) unescapes correctly and is unaffected. Reuses the $nojq PATH from 4b.
rm -rf "$fleet_home"
PLANWRIGHT_FLEET_STATE_DIR="$fleet_home" /bin/bash "$WT" record-create /work/keepme >/dev/null
# real path /work/a"b  -> JSON encodes the quote as \"  (sed would yield /work/a\)
esc_q='{"worktree_path":"/work/a\"b","hook_event_name":"WorktreeRemove"}'
rc=0
printf '%s' "$esc_q" | PATH="$nojq" PLANWRIGHT_FLEET_STATE_DIR="$fleet_home" \
  /bin/bash "$WT" hook-remove >/dev/null 2>&1 || rc=$?
[ "$rc" = 0 ] || fail "hook-remove (no jq, escaped-quote path) exit $rc, expected 0"
# real path /work/a\b  -> JSON encodes the backslash as \\ (sed would yield /work/a\\b)
esc_bs='{"worktree_path":"/work/a\\b","hook_event_name":"WorktreeRemove"}'
rc=0
printf '%s' "$esc_bs" | PATH="$nojq" PLANWRIGHT_FLEET_STATE_DIR="$fleet_home" \
  /bin/bash "$WT" hook-remove >/dev/null 2>&1 || rc=$?
[ "$rc" = 0 ] || fail "hook-remove (no jq, backslash path) exit $rc, expected 0"
case $(PLANWRIGHT_FLEET_STATE_DIR="$fleet_home" /bin/bash "$WT" list 2>/dev/null) in
  *"/work/keepme"*) ;;
  *) fail "hook-remove must not act on an un-parseable escaped payload" ;;
esac
echo "ok: hook-remove fails closed on an un-parseable escaped worktree_path via the sed fallback"

# 4f. The same unreadable payload with jq ABSENT still surfaces the reason on
#     stdout. jq is what builds the JSON, so the jq-absent path is exactly where
#     a `systemMessage` handler is most likely to quietly fall back to stderr —
#     the discarded channel REQ-H1.3 exists to keep refusals off. The rest of
#     this handler already degrades without jq (4b's sed path), so the operator
#     message must degrade too. Asserted byte-identical to the jq output so the
#     hand-rolled constant cannot drift from the message jq interpolates.
#     Reuses the $nojq PATH from 4b.
rm -rf "$fleet_home"
rc=0
out_jq=$(printf '%s' '{"hook_event_name":"WorktreeRemove","session_id":"s1"}' | wt hook-remove 2>/dev/null) || rc=$?
[ "$rc" = 0 ] || fail "hook-remove (missing worktree_path, jq present) exit $rc, expected 0"
rm -rf "$fleet_home"
rc=0
out_nojq=$(printf '%s' '{"hook_event_name":"WorktreeRemove","session_id":"s1"}' \
  | PATH="$nojq" PLANWRIGHT_FLEET_STATE_DIR="$fleet_home" /bin/bash "$WT" hook-remove 2>/dev/null) || rc=$?
[ "$rc" = 0 ] || fail "hook-remove (missing worktree_path, no jq) exit $rc, expected 0"
[ -n "$out_nojq" ] \
  || fail "hook-remove (no jq) emitted nothing on stdout; the reason reached only discarded stderr (REQ-H1.3)"
printf '%s' "$out_nojq" | jq -e '.systemMessage | test("scan")' >/dev/null 2>&1 \
  || fail "hook-remove (no jq) must emit a valid systemMessage JSON naming the remedy (got: '$out_nojq')"
[ "$out_nojq" = "$out_jq" ] \
  || fail "hook-remove (no jq) message drifted from the jq one:
  jq:    '$out_jq'
  no-jq: '$out_nojq'"
echo "ok: hook-remove surfaces the unreadable-payload reason as systemMessage with jq absent too"

# 4g. jq ON PATH but BROKEN (exits non-zero / prints nothing) must not make the
#     message vanish: an emitter that trusts jq's exit status alone emits nothing
#     and returns success, which reads to the harness as "the hook had nothing to
#     say" — the same invisibility as stderr, from a different cause
#     (ready-guard.sh's emit_deny_constant discipline).
rm -rf "$fleet_home"
brokenjq="$tmp/brokenjq"
mkdir -p "$brokenjq"
ln -s "$nojq"/* "$brokenjq"/ 2>/dev/null || true
rm -f "$brokenjq/jq"
printf '#!/bin/sh\nexit 3\n' >"$brokenjq/jq"
chmod +x "$brokenjq/jq"
rc=0
out_broken=$(printf '%s' '{"hook_event_name":"WorktreeRemove","session_id":"s1"}' \
  | PATH="$brokenjq" PLANWRIGHT_FLEET_STATE_DIR="$fleet_home" /bin/bash "$WT" hook-remove 2>/dev/null) || rc=$?
[ "$rc" = 0 ] || fail "hook-remove (broken jq) exit $rc, expected 0"
[ "$out_broken" = "$out_jq" ] \
  || fail "hook-remove must fall back to the constant message when jq is present but broken (got: '$out_broken')"
echo "ok: hook-remove still surfaces the reason when jq is on PATH but broken"

# 4h. A payload whose worktree_path is PRESENT but fails the path grammar is a
#     tracking gap too, and it must be as visible as an absent one. do_record
#     refuses such a path and warns — but the handler runs it in a subshell with
#     stderr closed, on an event whose stderr the harness discards anyway, so
#     before this branch existed the operator got nothing on any channel: no
#     record, no message, exit 0. The message is deliberately DISTINCT from the
#     absent-path one (the payload was malformed, not missing) and deliberately
#     does NOT echo the offending path: the jq-less fallback is a constant and
#     cannot interpolate one. Registry untouched, exit still 0, and the jq and
#     no-jq forms stay byte-identical. Reuses the $nojq PATH from 4b.
for bad_path in 'relative/not/absolute' '-leadingdash/path'; do
  rm -rf "$fleet_home"
  wt record-create /work/keepme2 >/dev/null
  bad_payload=$(printf '{"worktree_path":"%s","hook_event_name":"WorktreeRemove"}' "$bad_path")
  rc=0
  out_bad=$(printf '%s' "$bad_payload" | wt hook-remove 2>/dev/null) || rc=$?
  [ "$rc" = 0 ] || fail "hook-remove (malformed path '$bad_path') exit $rc, expected 0"
  [ -n "$out_bad" ] \
    || fail "hook-remove emitted nothing for a malformed worktree_path '$bad_path'; the gap is silent on every channel (REQ-H1.3)"
  printf '%s' "$out_bad" | jq -e '.systemMessage | test("grammar") and test("scan")' >/dev/null 2>&1 \
    || fail "hook-remove (malformed path '$bad_path') must name the grammar and the remedy (got: '$out_bad')"
  printf '%s' "$out_bad" | jq -e '.systemMessage | test("no readable worktree_path") | not' >/dev/null 2>&1 \
    || fail "a malformed worktree_path must not be reported as an absent one (got: '$out_bad')"
  case $(wt list 2>/dev/null) in
    *"/work/keepme2"*) ;;
    *) fail "hook-remove acted on a malformed worktree_path '$bad_path'" ;;
  esac
  rc=0
  out_bad_nojq=$(printf '%s' "$bad_payload" \
    | PATH="$nojq" PLANWRIGHT_FLEET_STATE_DIR="$fleet_home" /bin/bash "$WT" hook-remove 2>/dev/null) || rc=$?
  [ "$rc" = 0 ] || fail "hook-remove (malformed path '$bad_path', no jq) exit $rc, expected 0"
  [ "$out_bad_nojq" = "$out_bad" ] \
    || fail "malformed-path message drifted between the jq and no-jq forms:
  jq:    '$out_bad'
  no-jq: '$out_bad_nojq'"
done
echo "ok: hook-remove surfaces a present-but-malformed worktree_path as its own systemMessage"

# 5. `hook-create` is retired, and the CLI says so rather than silently
#    accepting it. planwright registers no `WorktreeCreate` hook: the event
#    grants no passive mode, and registering one replaces native creation.
rc=0
out=$(printf '%s' '{"name":"wt-1","hook_event_name":"WorktreeCreate"}' | wt hook-create 2>&1) || rc=$?
[ "$rc" != 0 ] || fail "hook-create must not be accepted (it was retired with the WorktreeCreate registration)"
echo "ok: hook-create is retired and refused by the CLI"

# 6. Hostile / non-absolute paths are refused by the direct CLI.
rm -rf "$fleet_home"
for bad in 'relative/path' '-x' ''; do
  rc=0
  wt record-create "$bad" >/dev/null 2>&1 || rc=$?
  [ "$rc" != 0 ] || fail "record-create accepted a hostile path '$bad'"
done
echo "ok: hostile / non-absolute paths are refused by the direct CLI"

echo "ALL PASS: fleet-worktree-track"
