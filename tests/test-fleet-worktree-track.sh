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
# `<repo>/.claude/worktrees/<name>` on a fresh `worktree-<flattened-name>`
# branch, echoes the created path, and ALWAYS exits 0 — every refusal echoes
# nothing.
# `WorktreeRemove` keeps its genuinely different `worktree_path` shape and is
# fire-and-forget.
#
# What is covered:
#   - record-create then record-remove update the live registry (push tracking),
#     observable via `list`, with NO disk scan involved;
#   - record-create is idempotent (no duplicate rows);
#   - the disk-scan fallback (`scan`) discovers a real linked worktree git knows
#     about that no hook ever pushed;
#   - `list` enforces the emitted-path grammar, skipping a malformed registry
#     line with a warning instead of handing it to a caller;
#   - `hook-create` CREATES the worktree from the stdin `name` (flat, nested,
#     and at the 64-char grammar boundary), echoes its physical path, records
#     it, exits 0 — and is idempotent on an already-created target; the sed
#     fallback covers a jq-less host, and a failed registry write never fails
#     creation;
#   - `hook-create` refusals echo NOTHING, create nothing, and still exit 0:
#     malformed names (control byte, traversal, dot-only or dash-led segment,
#     absolute, over-length), an absent name, a non-git cwd, a branch
#     collision (which leaves the pre-existing branch untouched), an existing
#     non-worktree target, and the un-parseable escaped names on the sed
#     fallback;
#   - `hook-remove` records a removal from its stdin payload and exits 0,
#     including via the sed fallback on a jq-less host;
#   - hostile / non-absolute paths are refused by the direct CLI (exit non-zero);
#   - the hardening arms: a failed `git worktree add` leaves no branch behind
#     (the name self-heals), jq-present parsing is authoritative (a nested
#     "name" decoy never promotes), symlinked worktrees roots and dangling
#     symlink targets refuse untouched, a stale registered worktree never
#     reattaches to a dead path, a dangling `origin/HEAD` falls back to HEAD,
#     dot-led segments and refname-invalid flattenings refuse cleanly, and
#     creation from inside a linked worktree lands under the primary checkout.
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

tmp=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$tmp"' EXIT
# Pin repo discovery inside the fixture: without a ceiling, a TMPDIR that
# resolves inside a real checkout would let the "non-git cwd" case walk up,
# find that repo, and create a stray worktree in it instead of refusing.
GIT_CEILING_DIRECTORIES="$tmp"
export GIT_CEILING_DIRECTORIES
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
[ -d "$out3" ] || fail "nested name did not create the worktree directory"
(cd "$main_repo" && git worktree list --porcelain | grep -Fxq "worktree $out3") \
  || fail "nested worktree is not a registered git worktree"
case $(wt list) in
  *"$out3"*) ;;
  *) fail "hook-create did not record the nested worktree" ;;
esac
# The name grammar's 64-char boundary: exactly 64 chars must be ACCEPTED (a
# refusal here would mean an off-by-one against the documented max).
b64=$(printf 'b%.0s' $(seq 1 64))
rc=0
out4=$(cd "$main_repo" \
  && printf '{"hook_event_name":"WorktreeCreate","name":"%s"}' "$b64" | wt hook-create) || rc=$?
[ "$rc" = 0 ] || fail "hook-create (64-char name) exit $rc, expected 0"
[ "$out4" = "$main_real/.claude/worktrees/$b64" ] \
  || fail "a 64-char name must be accepted at the boundary (got: '$out4')"
echo "ok: hook-create reattaches idempotently, nests multi-segment names, and accepts the 64-char boundary"

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
[ -d "$out" ] || fail "hook-create (no jq) echoed a path it did not create"
(cd "$main_repo" && git show-ref --verify --quiet refs/heads/worktree-nojq-wt) \
  || fail "hook-create (no jq) did not create the worktree-nojq-wt branch"
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
refuse "dot-only segment" '{"hook_event_name":"WorktreeCreate","name":"a/./b"}'
refuse "dash-led segment" '{"hook_event_name":"WorktreeCreate","name":"a/-x"}'
refuse "absolute name" '{"hook_event_name":"WorktreeCreate","name":"/etc/oops"}'
# Over-length at the boundary: 65 chars (one past the documented 64-char max,
# whose accept side is pinned in 4a) must refuse.
refuse "over-length name (65 chars)" "$(printf '{"hook_event_name":"WorktreeCreate","name":"%s"}' \
  "$(printf 'a%.0s' $(seq 1 65))")"
refuse "absent name" '{"hook_event_name":"WorktreeCreate"}'
refuse "non-git cwd" '{"hook_event_name":"WorktreeCreate","name":"stray-wt"}' "$tmp"
# Branch collision: a pre-existing worktree-clash branch refuses the name clash,
# leaves that branch's tip untouched, and attaches no worktree to it.
(cd "$main_repo" && git_env git branch worktree-clash >/dev/null 2>&1)
clash_tip=$(cd "$main_repo" && git rev-parse refs/heads/worktree-clash)
refuse "branch collision" '{"hook_event_name":"WorktreeCreate","name":"clash"}'
[ "$(cd "$main_repo" && git rev-parse refs/heads/worktree-clash)" = "$clash_tip" ] \
  || fail "branch-collision refusal moved the pre-existing branch"
(cd "$main_repo" && git worktree list --porcelain | grep -Fq "/.claude/worktrees/clash") \
  && fail "branch-collision refusal still attached a worktree" || true
[ ! -e "$main_repo/.claude/worktrees/clash" ] \
  || fail "branch-collision refusal still created the target dir"
# Existing non-worktree directory at the target refuses, and the squatted dir
# is neither adopted as a worktree nor removed.
mkdir -p "$main_repo/.claude/worktrees/squatter"
refuse "existing non-worktree target" '{"hook_event_name":"WorktreeCreate","name":"squatter"}'
(cd "$main_repo" && git worktree list --porcelain | grep -Fq "/.claude/worktrees/squatter") \
  && fail "squatter refusal still registered the squatted dir as a worktree" || true
[ -d "$main_repo/.claude/worktrees/squatter" ] || fail "squatter refusal removed the squatted dir"
[ ! -e "$main_repo/.claude/worktrees/a" ] \
  || fail "a refused a/-prefixed name still created its parent segment"
# A traversal name that slipped the grammar would materialize at the ESCAPED
# location (`.claude/worktrees/escape` after `a/..` collapses), not at `.../a`
# — assert the actual escape targets, inside and outside the worktrees root.
[ ! -e "$main_repo/.claude/worktrees/escape" ] || fail "traversal name created the escaped target"
[ ! -e "$main_repo/escape" ] || fail "traversal name escaped the worktrees root"
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
# The other escape shape: a doubled backslash (JSON `a\\b`) survives the sed
# capture as raw backslashes and must be refused the same way.
esc_b='{"hook_event_name":"WorktreeCreate","name":"a\\b"}'
rc=0
out=$(cd "$main_repo" && printf '%s' "$esc_b" \
  | PATH="$nojq" PLANWRIGHT_FLEET_STATE_DIR="$fleet_home" /bin/bash "$WT" hook-create 2>/dev/null) || rc=$?
[ "$rc" = 0 ] || fail "hook-create (no jq, escaped-backslash name) exit $rc, expected 0"
[ -z "$out" ] || fail "hook-create (no jq, escaped-backslash name) must echo NOTHING (fail-closed), got: '$out'"
[ -z "$(PLANWRIGHT_FLEET_STATE_DIR="$fleet_home" /bin/bash "$WT" list 2>/dev/null)" ] \
  || fail "hook-create must not record an un-parseable escaped payload"
echo "ok: hook-create fails closed on un-parseable escaped names via the sed fallback"

# 5. hook-remove: records a removal from stdin and exits 0 (fire-and-forget).
rm -rf "$fleet_home"
wt record-create /work/going >/dev/null
rc=0
printf '%s' '{"worktree_path":"/work/going","session_id":"s1"}' | wt hook-remove || rc=$?
[ "$rc" = 0 ] || fail "hook-remove exit $rc, expected 0"
case $(wt list) in
  *"/work/going"*) fail "hook-remove did not drop the worktree" ;;
esac
# The sed fallback serves hook-remove's `.worktree_path` extraction on a
# jq-less host too (reuses the $nojq PATH built in 4b).
wt record-create /work/going2 >/dev/null
rc=0
printf '%s' '{"worktree_path":"/work/going2","session_id":"s2"}' \
  | PATH="$nojq" PLANWRIGHT_FLEET_STATE_DIR="$fleet_home" /bin/bash "$WT" hook-remove || rc=$?
[ "$rc" = 0 ] || fail "hook-remove (no jq) exit $rc, expected 0"
case $(wt list) in
  *"/work/going2"*) fail "hook-remove (no jq) did not drop the worktree via the sed fallback" ;;
esac
echo "ok: hook-remove records the removal and exits 0 (jq and sed-fallback paths)"

# 13. Invoked from INSIDE a linked worktree (the normal fleet case: a worker
#     session requesting a sibling), the new worktree must land under the
#     PRIMARY checkout's worktrees root — not nest inside the current
#     worktree, where removing the parent would silently delete it.
rm -rf "$fleet_home"
inside="$main_real/.claude/worktrees/hooked-wt"
[ -d "$inside" ] || fail "from-inside setup: the hooked-wt worktree from test 4 is missing"
rc=0
out=$(cd "$inside" && printf '%s' '{"hook_event_name":"WorktreeCreate","name":"from-inside"}' \
  | wt hook-create 2>/dev/null) || rc=$?
[ "$rc" = 0 ] || fail "hook-create (from inside a linked worktree) exit $rc, expected 0"
[ "$out" = "$main_real/.claude/worktrees/from-inside" ] \
  || fail "creation from inside a worktree must target the primary checkout (got: '$out')"
[ ! -e "$inside/.claude" ] || fail "creation nested a worktree tree inside the invoking worktree"
echo "ok: creation from inside a linked worktree lands under the primary checkout"

# 12. Grammar tightening: a dot-led segment (`.git` would sit inside the
#     worktrees root and confuse git discovery) refuses, and a name whose
#     flattened `worktree-<name>` branch is refname-invalid (`a..b`) refuses
#     CLEANLY — no branch left behind, nothing created.
rm -rf "$fleet_home"
refuse "dot-led segment (.git)" '{"hook_event_name":"WorktreeCreate","name":".git"}'
[ ! -e "$main_repo/.claude/worktrees/.git" ] || fail "a .git name still created something"
refuse "refname-invalid flattening (a..b)" '{"hook_event_name":"WorktreeCreate","name":"a..b"}'
(cd "$main_repo" && git show-ref --verify --quiet refs/heads/worktree-a..b) \
  && fail "the refname-invalid refusal left a branch behind" || true
[ ! -e "$main_repo/.claude/worktrees/a..b" ] || fail "a refname-invalid name still created something"
echo "ok: dot-led segments and refname-invalid flattenings refuse cleanly"

# 11. A DANGLING origin/HEAD (symref present, its target ref gone — a renamed
#     or pruned remote default branch) must fall back to HEAD, not turn every
#     creation into a refusal: `symbolic-ref --quiet` still succeeds on a
#     dangling symref, so resolvability needs its own gate.
base_repo="$tmp/base-fb"
git_env git init -q -b main "$base_repo"
(cd "$base_repo" && echo seed >f && git_env git add f && git_env git commit -qm seed)
(cd "$base_repo" && git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/gone)
base_real=$(cd "$base_repo" && pwd -P)
rc=0
out=$(cd "$base_repo" && printf '%s' '{"hook_event_name":"WorktreeCreate","name":"fb-wt"}' \
  | wt hook-create 2>/dev/null) || rc=$?
[ "$rc" = 0 ] || fail "hook-create (dangling origin/HEAD) exit $rc, expected 0"
[ "$out" = "$base_real/.claude/worktrees/fb-wt" ] \
  || fail "a dangling origin/HEAD must fall back to HEAD and still create (got: '$out')"
echo "ok: a dangling origin/HEAD falls back to HEAD instead of refusing all creation"

# 10. A STALE registered worktree (admin entry present, directory gone) must
#     not reattach: echoing the dead path reports success on a tree that does
#     not exist. The acceptable outcomes are a fresh create or a refusal —
#     never a non-existent path on the decision channel.
rm -rf "$fleet_home"
stale_payload='{"hook_event_name":"WorktreeCreate","name":"stale-wt"}'
out=$(cd "$main_repo" && printf '%s' "$stale_payload" | wt hook-create) \
  || fail "stale-reattach setup: initial create failed"
[ -d "$out" ] || fail "stale-reattach setup: no directory created"
rm -rf "$out"
rc=0
out=$(cd "$main_repo" && printf '%s' "$stale_payload" | wt hook-create 2>/dev/null) || rc=$?
[ "$rc" = 0 ] || fail "hook-create (stale registered entry) exit $rc, expected 0"
if [ -n "$out" ] && [ ! -d "$out" ]; then
  fail "hook-create echoed a nonexistent directory for a stale entry (got: '$out')"
fi
echo "ok: a stale registered worktree never reattaches to a dead path"

# 9. Symlink screens: a dangling symlink at the target (invisible to `-e`) is
#    refused and PRESERVED — the failure path must not `rm -rf` an object this
#    hook did not create. A symlinked worktrees root is likewise refused
#    before anything materializes on the far side.
rm -rf "$fleet_home"
ln -s /nonexistent-planwright-probe "$main_repo/.claude/worktrees/dangle"
rc=0
out=$(cd "$main_repo" && printf '%s' '{"hook_event_name":"WorktreeCreate","name":"dangle"}' \
  | wt hook-create 2>/dev/null) || rc=$?
[ "$rc" = 0 ] || fail "hook-create (dangling symlink target) exit $rc, expected 0"
[ -z "$out" ] || fail "a dangling symlink at the target must refuse (got: '$out')"
[ -L "$main_repo/.claude/worktrees/dangle" ] \
  || fail "the refusal deleted the operator's symlink at the target"
rm -f "$main_repo/.claude/worktrees/dangle"
symroot_repo="$tmp/symroot"
git_env git init -q -b main "$symroot_repo"
(cd "$symroot_repo" && echo seed >f && git_env git add f && git_env git commit -qm seed)
outside="$tmp/outside-target"
mkdir -p "$outside" "$symroot_repo/.claude"
ln -s "$outside" "$symroot_repo/.claude/worktrees"
rc=0
out=$(cd "$symroot_repo" && printf '%s' '{"hook_event_name":"WorktreeCreate","name":"escapee"}' \
  | wt hook-create 2>/dev/null) || rc=$?
[ "$rc" = 0 ] || fail "hook-create (symlinked worktrees root) exit $rc, expected 0"
[ -z "$out" ] || fail "a symlinked worktrees root must refuse (got: '$out')"
[ -z "$(ls -A "$outside")" ] || fail "the symlinked root materialized content outside the repo"
[ -L "$symroot_repo/.claude/worktrees" ] || fail "the refusal disturbed the symlinked root"
echo "ok: symlinked worktrees roots and dangling symlink targets are refused untouched"

# 8. jq is AUTHORITATIVE where present: a payload whose top-level `name` is
#    empty (or absent) must refuse even when a NESTED "name" key exists —
#    falling through to the unanchored sed capture would promote the nested
#    key to the created worktree name.
command -v jq >/dev/null 2>&1 || fail "this suite needs jq on PATH (the authoritative-parse case)"
rm -rf "$fleet_home"
nested_evil='{"hook_event_name":"WorktreeCreate","name":"","meta":{"name":"evil"}}'
rc=0
out=$(cd "$main_repo" && printf '%s' "$nested_evil" | wt hook-create 2>/dev/null) || rc=$?
[ "$rc" = 0 ] || fail "hook-create (empty name, nested decoy) exit $rc, expected 0"
[ -z "$out" ] || fail "an empty top-level name must refuse, not promote a nested key (got: '$out')"
[ ! -e "$main_repo/.claude/worktrees/evil" ] \
  || fail "the nested decoy name was created despite jq being present"
echo "ok: jq-present parsing is authoritative — a nested name key is never promoted"

# 7. A failed `git worktree add` cleans up the branch it created: the refusal
#    leaves no `worktree-<flattened>` ref behind, so the same name self-heals
#    once the obstruction is gone (instead of hitting the branch-collision
#    refusal forever). Driven by a FILE squatting the nested name's parent
#    path, which makes `add` fail creating leading directories.
rm -rf "$fleet_home"
: >"$main_repo/.claude/worktrees/parent"
blocked='{"hook_event_name":"WorktreeCreate","name":"parent/child"}'
rc=0
out=$(cd "$main_repo" && printf '%s' "$blocked" | wt hook-create 2>/dev/null) || rc=$?
[ "$rc" = 0 ] || fail "hook-create (blocked add) exit $rc, expected 0"
[ -z "$out" ] || fail "hook-create (blocked add) must echo NOTHING (got: '$out')"
(cd "$main_repo" && git show-ref --verify --quiet refs/heads/worktree-parent-child) \
  && fail "a failed git worktree add left the worktree-parent-child branch behind" || true
rm -f "$main_repo/.claude/worktrees/parent"
rc=0
out=$(cd "$main_repo" && printf '%s' "$blocked" | wt hook-create 2>/dev/null) || rc=$?
[ "$rc" = 0 ] || fail "hook-create (retry after unblocking) exit $rc, expected 0"
[ "$out" = "$main_real/.claude/worktrees/parent/child" ] \
  || fail "the name must self-heal once the obstruction is gone (got: '$out')"
echo "ok: a failed git worktree add leaves no branch behind, so the name self-heals"

# 14. An INTERMEDIATE symlink component under the worktrees root (a nested
#     name's parent pre-planted as a symlink) is refused BEFORE any write: the
#     refusal comes from the symlink screen (not from the post-create
#     containment teardown, which would mean content already landed outside),
#     and nothing is registered or left behind on either side.
rm -rf "$fleet_home"
mid_outside="$tmp/mid-outside"
mkdir -p "$mid_outside"
ln -s "$mid_outside" "$main_repo/.claude/worktrees/midlink"
rc=0
out=$(cd "$main_repo" && printf '%s' '{"hook_event_name":"WorktreeCreate","name":"midlink/wt"}' \
  | wt hook-create 2>"$tmp/err14") || rc=$?
[ "$rc" = 0 ] || fail "hook-create (intermediate symlink) exit $rc, expected 0"
[ -z "$out" ] || fail "an intermediate symlink component must refuse (got: '$out')"
grep -qi "symlink" "$tmp/err14" \
  || fail "the refusal must come from the symlink screen, not the post-create teardown (stderr: '$(cat "$tmp/err14")')"
[ -z "$(ls -A "$mid_outside")" ] || fail "content materialized outside via the intermediate symlink"
[ -L "$main_repo/.claude/worktrees/midlink" ] || fail "the refusal disturbed the intermediate symlink"
(cd "$main_repo" && git show-ref --verify --quiet refs/heads/worktree-midlink-wt) \
  && fail "the intermediate-symlink refusal left a branch behind" || true
rm -f "$main_repo/.claude/worktrees/midlink"
echo "ok: an intermediate symlink component refuses before any write"

# 15. A non-string `.name` (the WorktreeCreate contract types it as a string)
#     is a refusal, never a coercion: `{"name": 0}` must not become a
#     worktree named `0`.
rm -rf "$fleet_home"
rc=0
out=$(cd "$main_repo" && printf '%s' '{"hook_event_name":"WorktreeCreate","name":0}' \
  | wt hook-create 2>/dev/null) || rc=$?
[ "$rc" = 0 ] || fail "hook-create (non-string name) exit $rc, expected 0"
[ -z "$out" ] || fail "a non-string name must refuse, not coerce (got: '$out')"
[ ! -e "$main_repo/.claude/worktrees/0" ] || fail "a numeric name payload was coerced and created"
echo "ok: a non-string name refuses instead of coercing"

# 6. Hostile / non-absolute paths are refused by the direct CLI.
rm -rf "$fleet_home"
for bad in 'relative/path' '-x' ''; do
  rc=0
  wt record-create "$bad" >/dev/null 2>&1 || rc=$?
  [ "$rc" != 0 ] || fail "record-create accepted a hostile path '$bad'"
done
echo "ok: hostile / non-absolute paths are refused by the direct CLI"

echo "ALL PASS: fleet-worktree-track"
