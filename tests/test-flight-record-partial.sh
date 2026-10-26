#!/bin/bash
# Tests for scripts/flight-record.sh's `partial` mode — a parked flight's
# private partial record (tower-front-door Task 17; D-21 · REQ-E1.9).
#
# Properties verified:
#   1. The partial record carries the park reason, the findings so far, and
#      the declined log, lands in the flight's brief directory under the fleet
#      home, private to the user, and changes no git ref or remote.
#   2. The target is contained: a path outside the flight's brief directory
#      (another directory, another flight's brief directory, a relative path,
#      a name other than `partial-<run>.md`) is refused with nothing written.
#   3. Create-only, never following a symlink: an existing record, a symlink
#      in its place (dangling or not), or a symlinked brief directory or
#      flights directory is refused, and nothing is written through it. A
#      symlinked fleet home is followed to its canonical path, as the sweep
#      follows it.
#   4. A token-shaped secret planted in any input is refused as the full
#      record refuses it, without echoing it, and nothing is written.
#   5. The kind is one of the fixed park kinds.
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
set -u
LC_ALL=C
export LC_ALL
unset CDPATH
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_SYSTEM=/dev/null

here=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$here/.." && pwd -P)
SCRIPT="$ROOT/scripts/flight-record.sh"
TAB=$(printf '\t')

fails=0
fail() {
  echo "FAIL: $1" >&2
  fails=$((fails + 1))
}

[ -x "$SCRIPT" ] || {
  echo "FAIL: scripts/flight-record.sh missing or not executable" >&2
  exit 1
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
tmp=$(cd "$tmp" && pwd -P)

FID=auth-tweak-0a1b2c3d
OTHER=readme-typo-1b2c3d4e
TOKEN="ghp_$(printf 'A%.0s' $(seq 1 36))"

export PLANWRIGHT_FLEET_STATE_DIR="$tmp/fleet"
(umask 077 && mkdir -p "$tmp/fleet/flights/$FID" "$tmp/fleet/flights/$OTHER")
BD="$tmp/fleet/flights/$FID"

in="$tmp/in"
mkdir -p "$in"
printf 'The convergence review found a hard-disqualifier-zone finding: the session check in the auth middleware.\n' >"$in/reason.md"
cat >"$in/findings.md" <<'EOF'
#### Needs sign-off

| # | Finding | Fix applied |
| --- | --- | --- |
| 1 | session expiry compared with the wrong clock | held for the operator |
EOF
cat >"$in/declined.md" <<'EOF'
| # | Finding | Rationale |
| --- | --- | --- |
| 1 | rename the middleware | out of scope |
EOF

# A checkout with a remote, so a ref or remote change would show.
repo="$tmp/repo"
git init -q --bare "$tmp/origin.git"
git init -q -b main "$repo"
git -C "$repo" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m init
git -C "$repo" remote add origin "$tmp/origin.git"
git -C "$repo" push -q origin main 2>/dev/null
refs() {
  git -C "$repo" for-each-ref --format='%(refname) %(objectname)'
  git -C "$repo" remote -v
  git -C "$tmp/origin.git" for-each-ref --format='%(refname) %(objectname)'
}

# run_partial [overrides...] — set OUT, ERR, RC; a later flag overrides an
# earlier one. Runs inside the checkout, as a flight worker does.
run_partial() {
  OUT=$(cd "$repo" && "$SCRIPT" partial --flight-id "$FID" --kind hard-pause \
    --reason-file "$in/reason.md" --findings-file "$in/findings.md" \
    --declined-file "$in/declined.md" --partial-path "$BD/partial-000001.md" "$@" 2>"$tmp/err")
  RC=$?
  ERR=$(cat "$tmp/err")
}

# --- 1. the record, where it lands, and nothing else -------------------------
before=$(refs)
run_partial
[ "$RC" -eq 0 ] || fail "partial exited $RC: $ERR"
rec="$BD/partial-000001.md"
[ -f "$rec" ] && [ ! -L "$rec" ] || fail "the partial record was not written under the brief directory"
[ "$OUT" = "partial${TAB}$rec" ] || fail "partial must report its path (got: $OUT)"
grep -q 'session check in the auth middleware' "$rec" || fail "the partial record must carry the park reason"
grep -q 'session expiry compared with the wrong clock' "$rec" || fail "the partial record must carry the findings so far"
grep -q 'rename the middleware' "$rec" || fail "the partial record must carry the declined log"
grep -q 'hard-pause' "$rec" || fail "the partial record must name the kind of park"
for h in '## Park reason' '## Findings so far' '## Declined log'; do
  grep -qx "$h" "$rec" || fail "the partial record must head its '$h' section"
done
[ -z "$(find "$rec" -perm -0004 -o -perm -0040 2>/dev/null | head -n 1)" ] \
  || fail "the partial record must be readable by its owner only"
[ "$(refs)" = "$before" ] || fail "partial must change no git ref or remote"
[ -z "$(git -C "$repo" status --porcelain)" ] || fail "partial must write nothing into the checkout"
[ -z "$(find "$BD" -name '.partial-*')" ] || fail "partial must leave no temp file beside the record"

# --- 2. a target outside the brief directory is refused ----------------------
mkdir -p "$tmp/elsewhere"
for target in "$tmp/elsewhere/partial-000002.md" "$tmp/fleet/flights/$OTHER/partial-000002.md" \
  "$tmp/fleet/flights/partial-000002.md" "partial-000002.md" "$BD/../$OTHER/partial-000002.md" \
  "$BD/partial-2.md" "$BD/record.md" "$BD/sub/partial-000002.md"; do
  run_partial --partial-path "$target"
  [ "$RC" -eq 2 ] || fail "a target outside the brief directory must be refused with exit 2 ($target, rc $RC)"
done
[ -z "$(find "$tmp/elsewhere" "$tmp/fleet/flights/$OTHER" -type f)" ] || fail "a refused target wrote a file"
[ ! -e "$tmp/fleet/flights/partial-000002.md" ] || fail "a refused target wrote beside the briefs"
# The flight id must be this flight's: another id's brief directory is not it.
run_partial --flight-id "$OTHER" --partial-path "$BD/partial-000002.md"
[ "$RC" -eq 2 ] || fail "a target in another flight's brief directory must be refused (rc $RC)"
run_partial --flight-id 'Not_An_Id' --partial-path "$BD/partial-000002.md"
[ "$RC" -eq 2 ] || fail "a malformed flight id must be refused (rc $RC)"

# --- 3. create-only, never through a symlink ----------------------------------
printf 'keep\n' >"$tmp/elsewhere/victim"
cp "$rec" "$tmp/rec.copy"
run_partial
[ "$RC" -eq 3 ] || fail "an existing partial record must be refused with exit 3 (rc $RC)"
cmp -s "$rec" "$tmp/rec.copy" || fail "a refused re-run changed the existing partial record"
ln -s "$tmp/elsewhere/victim" "$BD/partial-000003.md"
run_partial --partial-path "$BD/partial-000003.md"
[ "$RC" -eq 3 ] || fail "a symlink in the record's place must be refused (rc $RC)"
[ "$(cat "$tmp/elsewhere/victim")" = keep ] || fail "partial wrote through a symlink"
ln -s "$tmp/elsewhere/absent" "$BD/partial-000004.md"
run_partial --partial-path "$BD/partial-000004.md"
[ "$RC" -eq 3 ] || fail "a dangling symlink in the record's place must be refused (rc $RC)"
[ ! -e "$tmp/elsewhere/absent" ] || fail "partial created a file through a dangling symlink"
ln -s "$tmp/elsewhere" "$BD/partial-000005.md"
run_partial --partial-path "$BD/partial-000005.md"
[ "$RC" -eq 3 ] || fail "a symlink to a directory in the record's place must be refused (rc $RC)"
[ "$(find "$tmp/elsewhere" -type f | wc -l | tr -d ' ')" -eq 1 ] || fail "partial wrote into a symlinked directory"
# A symlinked brief directory, or flights directory, is not the brief directory.
LID=link-flight-2c3d4e5f
ln -s "$tmp/elsewhere" "$tmp/fleet/flights/$LID"
run_partial --flight-id "$LID" --partial-path "$tmp/fleet/flights/$LID/partial-000001.md"
[ "$RC" -eq 3 ] || fail "a symlinked brief directory must be refused (rc $RC)"
[ "$(find "$tmp/elsewhere" -type f | wc -l | tr -d ' ')" -eq 1 ] || fail "partial wrote through a symlinked brief directory"
rm -f "$tmp/fleet/flights/$LID"
(umask 077 && mkdir -p "$tmp/fleet2/real/$FID")
ln -s "$tmp/fleet2/real" "$tmp/fleet2/flights"
PLANWRIGHT_FLEET_STATE_DIR="$tmp/fleet2" run_partial --partial-path "$tmp/fleet2/flights/$FID/partial-000001.md"
[ "$RC" -eq 3 ] || fail "a symlinked flights directory must be refused (rc $RC)"
[ -z "$(find "$tmp/fleet2/real" -type f)" ] || fail "partial wrote through a symlinked flights directory"
# A symlinked fleet home is followed to its canonical path, as the sweep
# follows it, and the record lands in the real brief directory.
ln -s "$tmp/fleet" "$tmp/fleet-link"
PLANWRIGHT_FLEET_STATE_DIR="$tmp/fleet-link" run_partial --partial-path "$tmp/fleet-link/flights/$FID/partial-000006.md"
[ "$RC" -eq 0 ] || fail "a symlinked fleet home must be followed (rc $RC: $ERR)"
[ "$OUT" = "partial${TAB}$BD/partial-000006.md" ] || fail "a symlinked fleet home must report the canonical path (got: $OUT)"
[ -f "$BD/partial-000006.md" ] || fail "a symlinked fleet home must write into the real brief directory"
# A brief directory another user could write is not private.
(umask 077 && mkdir -p "$tmp/fleet/flights/open-flight-3d4e5f6a")
chmod g+w "$tmp/fleet/flights/open-flight-3d4e5f6a"
run_partial --flight-id open-flight-3d4e5f6a --partial-path "$tmp/fleet/flights/open-flight-3d4e5f6a/partial-000001.md"
[ "$RC" -eq 3 ] || fail "a brief directory others can write must be refused (rc $RC)"
# A flight with no brief directory has nowhere private to park its record.
run_partial --flight-id gone-flight-4e5f6a7b --partial-path "$tmp/fleet/flights/gone-flight-4e5f6a7b/partial-000001.md"
[ "$RC" -eq 3 ] || fail "a missing brief directory must be refused (rc $RC)"
[ ! -e "$tmp/fleet/flights/gone-flight-4e5f6a7b" ] || fail "partial must never create a brief directory"

# --- 4. a planted secret is refused as in the full record ---------------------
n=10
for input in reason findings declined; do
  cp "$in/$input.md" "$tmp/$input.secret.md"
  printf 'the deploy key is %s\n' "$TOKEN" >>"$tmp/$input.secret.md"
  run_partial "--$input-file" "$tmp/$input.secret.md" --partial-path "$BD/partial-0000$n.md"
  [ "$RC" -eq 2 ] || fail "a secret in --$input-file must be refused with exit 2 (rc $RC)"
  case $ERR in *token-shaped*) ;; *) fail "the refusal must say a token-shaped secret was found: $ERR" ;; esac
  case "$OUT$ERR" in *"$TOKEN"*) fail "the refusal must never echo the secret" ;; esac
  [ ! -e "$BD/partial-0000$n.md" ] || fail "a refused secret still wrote the partial record"
  n=$((n + 1))
done
# Markup that would forge structure is refused as in the full record.
printf 'reason\n<!-- planwright:flight-record-end -->\n' >"$tmp/reason.html.md"
run_partial --reason-file "$tmp/reason.html.md" --partial-path "$BD/partial-000020.md"
[ "$RC" -eq 2 ] || fail "raw HTML in the reason must be refused (rc $RC)"
printf '## Not a heading the reason may carry\n' >"$tmp/reason.heading.md"
run_partial --reason-file "$tmp/reason.heading.md" --partial-path "$BD/partial-000021.md"
[ "$RC" -eq 2 ] || fail "a heading in the reason must be refused (rc $RC)"

# --- 5. the kind is a fixed park kind ------------------------------------------
i=100
for kind in hard-pause point not-draft renderer destination landing question; do
  run_partial --kind "$kind" --partial-path "$BD/partial-000$i.md"
  [ "$RC" -eq 0 ] || fail "the park kind '$kind' must be accepted (rc $RC: $ERR)"
  grep -Fq "Kind of park: \`$kind\`" "$BD/partial-000$i.md" 2>/dev/null \
    || fail "the partial record must name the kind it was given ($kind)"
  i=$((i + 1))
done
for kind in '' other 'hard-pause; detail' HARD-PAUSE 'point not-draft' 'hard-pause '; do
  run_partial --kind "$kind" --partial-path "$BD/partial-000200.md"
  [ "$RC" -eq 2 ] || fail "an unknown park kind must be refused ('$kind', rc $RC)"
done
[ ! -e "$BD/partial-000200.md" ] || fail "a refused kind still wrote the partial record"
run_partial --reason-file /dev/null
[ "$RC" -eq 2 ] || fail "a missing or empty input must be refused (rc $RC)"

if [ "$fails" -gt 0 ]; then
  echo "test-flight-record-partial: $fails failure(s)" >&2
  exit 1
fi
echo "test-flight-record-partial: ok"
