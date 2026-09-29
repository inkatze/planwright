#!/bin/bash
# Tests for scripts/sign-off-checklist.sh (the pending-sign-off checklist
# regenerated from `Planwright-Sign-Off` trailers over base..head) and for the
# `--sign-off` / `--reject` stamping modes of scripts/planwright-commit-trailers.sh.
#
# Verifies human-gates REQ-B1.2, REQ-B1.3, REQ-B1.6 (the shared-commit
# mechanics), and REQ-B1.10.
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
LIST="$here/../scripts/sign-off-checklist.sh"
STAMP="$here/../scripts/planwright-commit-trailers.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -x "$LIST" ] || fail "scripts/sign-off-checklist.sh missing or not executable"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

export GIT_AUTHOR_NAME=T GIT_AUTHOR_EMAIL=t@example.com
export GIT_COMMITTER_NAME=T GIT_COMMITTER_EMAIL=t@example.com
export GIT_AUTHOR_DATE='1700000000 +0000' GIT_COMMITTER_DATE='1700000000 +0000'
export GIT_CONFIG_NOSYSTEM=1 HOME="$tmp"

# new_repo <dir> — a repo with one root commit on `main`.
new_repo() {
  git init -q -b main "$1"
  git -C "$1" config commit.gpgsign false
  git -C "$1" commit -q --allow-empty -m 'chore: root'
}

# commit <dir> <message> — a commit adding its own file (so `git revert` has
# something to undo and a base merge never conflicts), with the literal message.
nfile=0
commit() {
  nfile=$((nfile + 1))
  : >"$1/f$nfile"
  git -C "$1" add "f$nfile"
  printf '%s\n' "$2" | git -C "$1" commit -q -F -
}

# ids <dir> [<base>] — the checklist's ids, comma-joined, in emitted order.
ids() {
  (cd "$1" && /bin/bash "$LIST" list "${2:-main}") | cut -f1 | tr '\n' ',' | sed 's/,$//'
}

# 1. A trailered commit and its revert regenerate to zero items; the legacy
#    subject grep over the same shape counts two (the failing baseline the
#    trailer path replaces). A revert commit is never an item.
r="$tmp/revert"
new_repo "$r"
git -C "$r" checkout -q -b task
commit "$r" "fix: guard the parser

Planwright-Sign-Off: PS-1"
git -C "$r" revert --no-edit HEAD >/dev/null
[ "$(ids "$r")" = "" ] || fail "revert: expected no items, got [$(ids "$r")]"
r2="$tmp/revert-legacy"
new_repo "$r2"
git -C "$r2" checkout -q -b task
commit "$r2" "fix: guard the parser [pending-sign-off]"
git -C "$r2" revert --no-edit HEAD >/dev/null
grepped=$(git -C "$r2" log --format=%s main..task | grep -c 'pending-sign-off')
[ "$grepped" = 2 ] || fail "baseline: the subject grep should count 2, counted $grepped"
[ "$(ids "$r2")" = "" ] || fail "revert-legacy: expected no items, got [$(ids "$r2")]"
echo "ok: a reverted item drops and its revert is never an item (subject grep counts 2)"

# 2. A rejected trailer drops exactly the item it names.
j="$tmp/reject"
new_repo "$j"
git -C "$j" checkout -q -b task
commit "$j" "fix: one

Planwright-Sign-Off: PS-1"
commit "$j" "fix: two

Planwright-Sign-Off: PS-2"
[ "$(ids "$j")" = "PS-1,PS-2" ] || fail "reject: setup expected PS-1,PS-2, got [$(ids "$j")]"
commit "$j" "fix: undo one by hand

Planwright-Sign-Off-Rejected: PS-1"
[ "$(ids "$j")" = "PS-2" ] || fail "reject: expected PS-2 only, got [$(ids "$j")]"
echo "ok: a rejected trailer drops exactly the named item"

# 3. A shared commit carries one trailer per finding: two items, one SHA; a
#    rejected trailer for one leaves the other.
s="$tmp/shared"
new_repo "$s"
git -C "$s" checkout -q -b task
commit "$s" "fix: two interleaved findings

Planwright-Sign-Off: PS-1
Planwright-Sign-Off: PS-2"
out=$(cd "$s" && /bin/bash "$LIST" list main)
[ "$(printf '%s\n' "$out" | cut -f1 | tr '\n' ',')" = "PS-1,PS-2," ] \
  || fail "shared: expected PS-1 and PS-2, got [$out]"
[ "$(printf '%s\n' "$out" | cut -f2 | sort -u | wc -l | tr -d ' ')" = 1 ] \
  || fail "shared: the two items should name one commit [$out]"
commit "$s" "fix: partial undo of PS-1

Planwright-Sign-Off-Rejected: PS-1"
[ "$(ids "$s")" = "PS-2" ] || fail "shared: expected PS-2 after rejecting PS-1, got [$(ids "$s")]"
echo "ok: a shared commit renders one item per trailer and rejects per item"

# 4. Legacy: a suffixed commit with no trailer renders once as
#    PS-legacy-<first seven hex of %H>; a suffixed commit that also carries a
#    trailer is not legacy.
l="$tmp/legacy"
new_repo "$l"
git -C "$l" checkout -q -b task
commit "$l" "fix: legacy finding [pending-sign-off]"
lsha=$(git -C "$l" rev-parse HEAD)
lid="PS-legacy-$(printf '%s' "$lsha" | cut -c1-7)"
commit "$l" "fix: trailered and suffixed [pending-sign-off]

Planwright-Sign-Off: PS-1"
commit "$l" "fix: marker mid-subject [pending-sign-off] is not a suffix"
[ "$(ids "$l")" = "$lid,PS-1" ] || fail "legacy: expected $lid,PS-1, got [$(ids "$l")]"
line=$(cd "$l" && /bin/bash "$LIST" list main | grep "^$lid	")
[ "$(printf '%s' "$line" | cut -f2)" = "$lsha" ] || fail "legacy: item does not name its full SHA [$line]"
[ "$(printf '%s' "$line" | cut -f3)" = "fix: legacy finding [pending-sign-off]" ] \
  || fail "legacy: item does not carry its subject [$line]"
echo "ok: a legacy suffixed commit renders once as PS-legacy-<sha7>"

# 5. The next PS-<n> ignores legacy items and never reuses a reverted id.
[ "$(cd "$l" && /bin/bash "$LIST" next main)" = "PS-2" ] \
  || fail "next: expected PS-2 beside a legacy item"
[ "$(cd "$r" && /bin/bash "$LIST" next main)" = "PS-2" ] \
  || fail "next: a reverted PS-1 must stay a gap, expected PS-2"
[ "$(cd "$r2" && /bin/bash "$LIST" next main)" = "PS-1" ] \
  || fail "next: legacy-only range should allocate PS-1"
echo "ok: allocation is unaffected by legacy items and never reuses an id"

# 6. A rejected trailer drops a legacy item when matched exactly; a revert of a
#    legacy commit drops it too (covered in 1); a near-miss value drops nothing.
commit "$l" "fix: reject near miss

Planwright-Sign-Off-Rejected: ${lid}0"
[ "$(ids "$l")" = "$lid,PS-1" ] || fail "legacy reject: a near-miss value dropped an item [$(ids "$l")]"
commit "$l" "fix: reject the legacy item

Planwright-Sign-Off-Rejected: $lid"
[ "$(ids "$l")" = "PS-1" ] || fail "legacy reject: expected PS-1 only, got [$(ids "$l")]"
echo "ok: a rejected trailer drops a legacy item only on an exact match"

# 7. A base merge that reorders the range leaves every id unchanged, and a
#    trailer arriving from the base never enters the checklist.
m="$tmp/merge"
new_repo "$m"
git -C "$m" checkout -q -b task
commit "$m" "fix: first

Planwright-Sign-Off: PS-1"
commit "$m" "fix: old style [pending-sign-off]"
commit "$m" "fix: second

Planwright-Sign-Off: PS-2"
before=$(ids "$m" | tr ',' '\n' | sort | tr '\n' ',')
git -C "$m" checkout -q main
commit "$m" "feat: landed elsewhere

Planwright-Sign-Off: PS-9"
commit "$m" "fix: landed legacy [pending-sign-off]"
git -C "$m" checkout -q task
git -C "$m" merge -q --no-edit main
after=$(ids "$m" | tr ',' '\n' | sort | tr '\n' ',')
[ "$before" = "$after" ] || fail "base merge: ids changed from [$before] to [$after]"
case "$after" in *PS-9*) fail "base merge: a base trailer entered the checklist" ;; esac
echo "ok: a base merge that reorders the range leaves every id unchanged"

# 8. A revert of a revert reinstates the item.
v="$tmp/reapply"
new_repo "$v"
git -C "$v" checkout -q -b task
commit "$v" "fix: reapplied

Planwright-Sign-Off: PS-1"
git -C "$v" revert --no-edit HEAD >/dev/null
git -C "$v" revert --no-edit HEAD >/dev/null
[ "$(ids "$v")" = "PS-1" ] || fail "reapply: expected PS-1 back, got [$(ids "$v")]"
echo "ok: reverting a revert reinstates the item"

# 9. An unresolvable range fails by name, emits no checklist, and allocation
#    refuses too.
for mode in list next; do
  rc=0
  out=$(cd "$j" && /bin/bash "$LIST" "$mode" origin/main 2>"$tmp/err") || rc=$?
  [ "$rc" = 3 ] || fail "unresolvable $mode: expected exit 3, got $rc"
  [ -z "$out" ] || fail "unresolvable $mode: emitted output [$out]"
  grep -q 'unresolvable range' "$tmp/err" || fail "unresolvable $mode: error not named [$(cat "$tmp/err")]"
done
rc=0
out=$(cd "$j" && /bin/bash "$LIST" list main no-such-head 2>/dev/null) || rc=$?
[ "$rc" = 3 ] && [ -z "$out" ] || fail "unresolvable head: expected exit 3 and no output, got $rc"
orphan="$tmp/orphan"
git init -q -b other "$orphan"
git -C "$orphan" config commit.gpgsign false
git -C "$orphan" commit -q --allow-empty -m 'chore: unrelated'
git -C "$j" fetch -q "$orphan" other:unrelated
rc=0
(cd "$j" && /bin/bash "$LIST" list unrelated >/dev/null 2>&1) || rc=$?
[ "$rc" = 3 ] || fail "unrelated base: expected exit 3, got $rc"
echo "ok: an unresolvable range fails by name with no checklist, and allocation refuses"

# 10. Two legacy commits sharing a seven-hex prefix fail by name. The pair is
#     precomputed: both are siblings of a fixed root, so their hashes are
#     deterministic under the fixed identity and dates above.
c="$tmp/collide"
git init -q -b main "$c"
empty=$(git -C "$c" hash-object -t tree /dev/null)
root=$(git -C "$c" commit-tree "$empty" -m 'chore: root')
a=$(git -C "$c" commit-tree "$empty" -p "$root" -m 'fix: legacy 23012 [pending-sign-off]')
b=$(git -C "$c" commit-tree "$empty" -p "$root" -m 'fix: legacy 28842 [pending-sign-off]')
[ "$(printf '%s' "$a" | cut -c1-7)" = "$(printf '%s' "$b" | cut -c1-7)" ] \
  || fail "collision: fixture no longer collides ($a vs $b)"
head=$(git -C "$c" commit-tree "$empty" -p "$a" -p "$b" -m 'Merge the pair')
git -C "$c" update-ref refs/heads/main "$root"
rc=0
out=$(cd "$c" && /bin/bash "$LIST" list main "$head" 2>"$tmp/err") || rc=$?
[ "$rc" = 4 ] || fail "collision: expected exit 4, got $rc"
[ -z "$out" ] || fail "collision: emitted a checklist [$out]"
grep -q 'legacy id collision' "$tmp/err" || fail "collision: error not named [$(cat "$tmp/err")]"
echo "ok: a legacy prefix collision fails by name with no checklist"

# 11. Usage errors exit 2.
rc=0
(cd "$j" && /bin/bash "$LIST" >/dev/null 2>&1) || rc=$?
[ "$rc" = 2 ] || fail "usage: no args expected exit 2, got $rc"
rc=0
(cd "$j" && /bin/bash "$LIST" list --upload-pack=x >/dev/null 2>&1) || rc=$?
[ "$rc" = 2 ] || fail "usage: an option-shaped base expected exit 2, got $rc"
echo "ok: usage errors exit 2"

# --- Stamping through planwright-commit-trailers.sh ---

# 12. --sign-off allocates the next free id once; the subject is unchanged.
out=$(cd "$l" && printf 'fix: next finding\n' | /bin/bash "$STAMP" --base main --sign-off demo/2)
[ "$(printf '%s\n' "$out" | head -1)" = "fix: next finding" ] || fail "stamp: subject altered [$out]"
got=$(printf '%s\n' "$out" | git interpret-trailers --parse | tr '\n' ',')
[ "$got" = "Planwright-Task: demo/2,Planwright-Sign-Off: PS-2," ] \
  || fail "stamp: expected the task and PS-2 trailers, got [$got]"
out=$(cd "$l" && printf 'fix: shared\n' | /bin/bash "$STAMP" --base main --sign-off --sign-off)
got=$(printf '%s\n' "$out" | git interpret-trailers --parse | tr '\n' ',')
[ "$got" = "Planwright-Sign-Off: PS-2,Planwright-Sign-Off: PS-3," ] \
  || fail "stamp: a shared commit expected PS-2 and PS-3, got [$got]"
echo "ok: --sign-off stamps the next free ids without touching the subject"

# 13. A stamped commit round-trips into the checklist.
(cd "$l" && printf 'fix: round trip\n' | /bin/bash "$STAMP" --base main --sign-off | git commit -q --allow-empty -F -)
[ "$(ids "$l")" = "PS-1,PS-2" ] || fail "round trip: expected PS-1,PS-2, got [$(ids "$l")]"
echo "ok: a stamped commit round-trips into the checklist"

# 14. --reject stamps both id forms; a malformed one is refused unechoed.
got=$(printf 'fix: undo\n' | /bin/bash "$STAMP" --reject PS-3 --reject PS-legacy-abc1234 \
  | git interpret-trailers --parse | tr '\n' ',')
[ "$got" = "Planwright-Sign-Off-Rejected: PS-3,Planwright-Sign-Off-Rejected: PS-legacy-abc1234," ] \
  || fail "reject stamp: got [$got]"
for bad in PS-0 PS-01 PS-x PS-legacy-abc123 PS-legacy-ABC1234 'PS-1
Evil: x'; do
  rc=0
  out=$(printf 'fix: s\n' | /bin/bash "$STAMP" --reject "$bad" 2>"$tmp/err") || rc=$?
  [ "$rc" = 2 ] && [ -z "$out" ] || fail "reject stamp: [$bad] expected exit 2 and no output, got $rc"
  grep -q 'Evil' "$tmp/err" && fail "reject stamp: refusal echoed the candidate"
done
echo "ok: --reject stamps PS-<n> and PS-legacy-<sha7> and refuses anything else"

# 15. Allocation refuses: no --base, an unresolvable base, or a message that
#     already carries an id (the id is written once).
rc=0
out=$(printf 'fix: s\n' | /bin/bash "$STAMP" --sign-off 2>/dev/null) || rc=$?
[ "$rc" = 2 ] && [ -z "$out" ] || fail "stamp: --sign-off without --base expected exit 2, got $rc"
rc=0
out=$(cd "$l" && printf 'fix: s\n' | /bin/bash "$STAMP" --base origin/main --sign-off 2>"$tmp/err") || rc=$?
[ "$rc" = 3 ] && [ -z "$out" ] || fail "stamp: unresolvable base expected exit 3 and no output, got $rc"
grep -q 'unresolvable range' "$tmp/err" || fail "stamp: unresolvable base not named"
rc=0
out=$(cd "$l" && printf 'fix: s\n\nPlanwright-Sign-Off: PS-7\n' \
  | /bin/bash "$STAMP" --base main --sign-off 2>/dev/null) || rc=$?
[ "$rc" = 2 ] && [ -z "$out" ] || fail "stamp: re-stamping an id expected exit 2, got $rc"
echo "ok: allocation refuses without a resolvable base or over an existing id"

echo "all sign-off-checklist tests passed"
