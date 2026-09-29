#!/bin/bash
# Tests for scripts/flight-sweep.sh — the shared flight sweep and its derived
# index (tower-front-door Task 7; D-9 · REQ-E1.3, REQ-F1.3, REQ-F1.4, REQ-F1.6).
#
# Properties verified:
#   1. One sweep derives every flight of the checkout from durable evidence
#      alone: flight branches (local and remote-tracking), the checkout's
#      worktrees, a committed record file on the branch, the forge's PRs, the
#      dispatch registry's death handle, and the decision queue. A fresh
#      session reads what landed (PR or record) and what is queued on the
#      operator from it (REQ-F1.4).
#   2. Backend liveness is consulted before a flight is called dead: only
#      positive death evidence says `dead`; no registry record, a print-rung
#      `none`, or an unreachable query mechanism is `unknown`, never dead.
#   3. The render carries the resolved plugin-root pair and the skew verdict.
#   4. The index is a derived cache (REQ-E1.3): it lives under the fleet home,
#      outside the checkout, so it is never tracked; deleting it and
#      re-sweeping reproduces it byte for byte; a corrupted index never feeds
#      the next sweep; stdout is the index.
#   5. A forge that cannot be read is named unknown, never read as "no PR".
#   6. Hostile evidence (an off-grammar branch, a malformed forge row) never
#      reaches the render.
#   7. The SessionStart hook is the deterministic arm: it is registered, it is
#      silent and exits 0 always, it writes nothing in a checkout without
#      flights, and it refreshes the index in one with them.
#   8. The tower's bring-up reads this sweep, and flight residues ride the
#      fleet cleanup sweep: a vanished checkout's index is pruned there.
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
set -u
LC_ALL=C
export LC_ALL
unset CDPATH
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_SYSTEM=/dev/null
unset CLAUDE_PLUGIN_DATA CLAUDE_PLUGIN_ROOT PLANWRIGHT_ROOT PLANWRIGHT_ADOPTER_OVERLAY \
  PLANWRIGHT_LOCAL_CONFIG PLANWRIGHT_CONFIG_DEFAULTS PLANWRIGHT_SKILLS_ROOT \
  PLANWRIGHT_WORKER_HANDLE PLANWRIGHT_WORKER_SCOPE PLANWRIGHT_TOWER_ID

here=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$here/.." && pwd -P)
SCRIPT="$ROOT/scripts/flight-sweep.sh"
STATE="$ROOT/scripts/fleet-state.sh"
ATTN="$ROOT/scripts/fleet-attention.sh"
TAB=$(printf '\t')

fails=0
fail() {
  echo "FAIL: $1" >&2
  fails=$((fails + 1))
}

[ -x "$SCRIPT" ] || {
  echo "FAIL: scripts/flight-sweep.sh missing or not executable" >&2
  exit 1
}

tmp=$(mktemp -d)
live_pid=''
cleanup() {
  [ -z "$live_pid" ] || kill "$live_pid" 2>/dev/null
  rm -rf "$tmp"
}
trap cleanup EXIT
tmp=$(cd "$tmp" && pwd -P)

gitc() {
  _r=$1
  shift
  git -C "$_r" -c user.name=test -c user.email=test@example.invalid \
    -c commit.gpgsign=false -c init.defaultBranch=main "$@"
}

# A stub `gh` answering `pr list --head <branch>` from $GH_STUB_PRS (rows of
# `<branch><TAB><the row the sweep's --jq asks for>`), failing when
# $GH_STUB_FAIL is set.
mkdir -p "$tmp/bin"
cat >"$tmp/bin/gh" <<'EOF'
#!/bin/sh
[ -z "${GH_STUB_LOG:-}" ] || printf '%s\n' "$*" >>"$GH_STUB_LOG"
[ -z "${GH_STUB_FAIL:-}" ] || exit 1
if [ "$1 $2" = "pr list" ]; then
  head=''
  prev=''
  for a in "$@"; do
    [ "$prev" != --head ] || head=$a
    prev=$a
  done
  [ -z "${GH_STUB_PRS:-}" ] || awk -F '\t' -v h="$head" '$1 == h { sub(/^[^\t]*\t/, ""); print }' "$GH_STUB_PRS"
  exit 0
fi
exit 0
EOF
chmod +x "$tmp/bin/gh"
# A tmux that cannot reach a server, so a tmux-window handle reads unknown.
cat >"$tmp/bin/tmux" <<'EOF'
#!/bin/sh
exit 1
EOF
chmod +x "$tmp/bin/tmux"
export PATH="$tmp/bin:$PATH"
export CLAUDE_DIR="$tmp/claude"

# The fixture checkout: a bare origin, a primary clone, and one flight of each
# evidence shape.
c="$tmp/case"
mkdir -p "$c"
git -c init.defaultBranch=main init -q --bare "$c/origin.git"
git clone -q "$c/origin.git" "$c/primary" 2>/dev/null
repo="$c/primary"
printf 'x\n' >"$repo/README.md"
gitc "$repo" add -A
gitc "$repo" commit -q -m init
gitc "$repo" branch -M main
gitc "$repo" push -q origin main
export PLANWRIGHT_FLEET_STATE_DIR="$c/fleet"
(umask 077 && mkdir -p "$c/fleet")

REC=rec-aaaaaaa1
PR=pr-aaaaaaa2
AIR=air-aaaaaaa3
DEAD=dead-aaaaaaa4
STRAND=strand-aaaaaaa5
QUEUED=queued-aaaaaaa6
PRINT=print-aaaaaaa7
TMUXF=tmuxf-aaaaaaa8
NOREG=noreg-aaaaaaa9
EVIL=evil-aaaaaab1

# Landed on the no-remote arm: a committed record file, worktree removed.
gitc "$repo" branch "planwright/flight/$REC" main
gitc "$repo" worktree add -q "$c/scratch" "planwright/flight/$REC"
mkdir -p "$c/scratch/specs/_flights"
printf '# record\n' >"$c/scratch/specs/_flights/$REC.md"
gitc "$c/scratch" add -A
gitc "$c/scratch" commit -q -m "chore(flight): land the record"
gitc "$repo" worktree remove "$c/scratch"
# Landed on the PR arm: pushed, so only the remote-tracking branch is left.
gitc "$repo" branch "planwright/flight/$PR" main
gitc "$repo" push -q origin "planwright/flight/$PR"
gitc "$repo" branch -D -q "planwright/flight/$PR"
gitc "$repo" fetch -q origin
# Stranded: a branch with no worktree and no landing.
gitc "$repo" branch "planwright/flight/$STRAND" main
# A branch whose forge reply is malformed.
gitc "$repo" branch "planwright/flight/$EVIL" main
# An off-grammar flight branch never reaches the render.
gitc "$repo" branch "planwright/flight/NOT_AN_ID" main

place() {
  gitc "$repo" worktree add -q -b "planwright/flight/$1" "$repo/.claude/worktrees/flight-$1" main
}
for f in "$AIR" "$DEAD" "$QUEUED" "$PRINT" "$TMUXF" "$NOREG"; do place "$f"; done

sleep 300 &
live_pid=$!
dead_pid=99999
while kill -0 "$dead_pid" 2>/dev/null; do dead_pid=$((dead_pid - 1)); done
reg() {
  /bin/sh "$STATE" register "$1" "flight:$2" --backend "$3" --death-handle "$4" >/dev/null \
    || fail "fixture: could not register $1"
}
reg "tmux-flight-$AIR" "$AIR" tmux "process $live_pid"
reg "tmux-flight-$DEAD" "$DEAD" tmux "process $dead_pid"
reg "tmux-flight-$QUEUED" "$QUEUED" tmux "process $live_pid"
reg "print-flight-$PRINT" "$PRINT" print none
reg "tmux-flight-$TMUXF" "$TMUXF" tmux "tmux-window w1 @1"
/bin/sh "$ATTN" decide "tmux-flight-$QUEUED" "flight:$QUEUED" "Which way?" a "a|b" >/dev/null \
  || fail "fixture: could not queue a decision"

prs="$c/prs.tsv"
{
  printf 'planwright/flight/%s\tOPEN\ttrue\thttps://github.com/acme/widgets/pull/7\n' "$PR"
  printf 'planwright/flight/%s\tOPEN\ttrue\thttps://evil.example/x y\n' "$EVIL"
  printf 'feature/unrelated\tOPEN\tfalse\thttps://github.com/acme/widgets/pull/8\n'
} >"$prs"
export GH_STUB_PRS="$prs"

row() { printf '%s\n' "$1" | awk -F "$TAB" -v id="$2" '$1 == "flight" && $2 == id'; }
field() { printf '%s\n' "$1" | cut -f"$2"; }

# --- 1–3. The sweep derives each flight from evidence ----------------------
status_before=$(gitc "$repo" status --porcelain)
out=$(cd "$repo" && "$SCRIPT" sweep 2>"$c/err")
rc=$?
[ "$rc" -eq 0 ] || fail "sweep exited $rc: $(cat "$c/err")"

r=$(row "$out" "$REC")
[ "$(field "$r" 3)" = landed ] || fail "a committed record file reads as landed (got: $r)"
[ "$(field "$r" 4)" = "record:specs/_flights/$REC.md" ] || fail "the record landing names its path (got: $r)"
r=$(row "$out" "$PR")
[ "$(field "$r" 3)" = landed ] || fail "a PR on a remote-only flight branch reads as landed (got: $r)"
[ "$(field "$r" 4)" = "pr:https://github.com/acme/widgets/pull/7" ] || fail "the PR landing names its URL (got: $r)"
r=$(row "$out" "$STRAND")
[ "$(field "$r" 3)" = stranded ] || fail "a branch with no worktree and no landing is stranded (got: $r)"
case $out in
  *evil.example*) fail "a malformed forge row reached the render" ;;
esac
r=$(row "$out" "$EVIL")
[ "$(field "$r" 3)" = unknown ] && [ "$(field "$r" 4)" = unknown ] \
  || fail "a malformed forge reply reads unknown, never 'no PR' (got: $r)"
case $out in
  *NOT_AN_ID*) fail "an off-grammar flight branch reached the render" ;;
esac
r=$(row "$out" "$AIR")
[ "$(field "$r" 3)" = in-air ] && [ "$(field "$r" 5)" = alive ] \
  || fail "a live worker's flight reads in-air and alive (got: $r)"
[ "$(field "$r" 6)" = "tmux-flight-$AIR" ] || fail "the render names the worker handle (got: $r)"
r=$(row "$out" "$DEAD")
[ "$(field "$r" 3)" = dead ] && [ "$(field "$r" 5)" = dead ] \
  || fail "positive death evidence reads dead (got: $r)"
r=$(row "$out" "$QUEUED")
[ "$(field "$r" 3)" = awaiting-operator ] || fail "a queued decision reads awaiting-operator (got: $r)"
r=$(row "$out" "$PRINT")
[ "$(field "$r" 3)" = in-air ] && [ "$(field "$r" 5)" = unknown ] \
  || fail "a print-rung flight is never dead: its liveness is unknown (got: $r)"
r=$(row "$out" "$TMUXF")
[ "$(field "$r" 5)" = unknown ] || fail "an unreachable tmux server reads unknown, never dead (got: $r)"
r=$(row "$out" "$NOREG")
[ "$(field "$r" 3)" = in-air ] && [ "$(field "$r" 5)" = unknown ] \
  || fail "a flight with no registry record reads unknown, never dead (got: $r)"

printf '%s\n' "$out" | grep -q "^root${TAB}tower${TAB}$ROOT${TAB}" || fail "the render names the tower's plugin root"
printf '%s\n' "$out" | grep -q "^root${TAB}worker${TAB}" || fail "the render names the worker's plugin root"
printf '%s\n' "$out" | grep -Eq "^root-skew${TAB}(yes|no|unknown)$" || fail "the render states the root skew"
printf '%s\n' "$out" | grep -q "^forge${TAB}partial${TAB}query-failed$" \
  || fail "a forge with one malformed reply is reported partial"
printf '%s\n' "$out" | grep -q "^checkout${TAB}$repo$" || fail "the render names its checkout"

# --- 4. The index is a derived, untracked cache ----------------------------
idx=$(cd "$repo" && "$SCRIPT" path)
[ -n "$idx" ] && [ -f "$idx" ] || fail "the sweep writes the index at the path it reports ($idx)"
case $idx in
  "$c/fleet"/*) ;;
  *) fail "the index lives under the fleet home (got: $idx)" ;;
esac
case $idx in
  "$repo"/*) fail "the index lives inside the checkout" ;;
esac
[ "$(gitc "$repo" status --porcelain)" = "$status_before" ] || fail "the sweep leaves the checkout untouched"
[ "$(cat "$idx")" = "$out" ] || fail "stdout is the index"
cp "$idx" "$c/first"
rm -f "$idx"
(cd "$repo" && "$SCRIPT" sweep >/dev/null 2>&1) || fail "re-sweep after deleting the index failed"
cmp -s "$idx" "$c/first" || fail "deleting the index and re-sweeping reproduces it byte for byte"
printf 'flight\tghost-bbbbbbb1\tlanded\tpr:x\talive\tx\n' >"$idx"
(cd "$repo" && "$SCRIPT" sweep >/dev/null 2>&1) || fail "re-sweep over a corrupted index failed"
cmp -s "$idx" "$c/first" || fail "a corrupted index never feeds the next sweep"
if grep -q '[0-9]\{10\}' "$idx"; then
  fail "the index carries no timestamp"
fi
[ -z "$(find "$(dirname "$idx")" -maxdepth 0 -perm -0002 2>/dev/null)" ] || fail "the index directory is private"

# --- 5. An unreadable forge is unknown, never "no PR" ----------------------
out=$(cd "$repo" && GH_STUB_FAIL=1 "$SCRIPT" sweep 2>/dev/null)
printf '%s\n' "$out" | grep -q "^forge${TAB}unavailable" || fail "a failing forge is reported unavailable"
r=$(row "$out" "$PR")
[ "$(field "$r" 3)" = unknown ] && [ "$(field "$r" 4)" = unknown ] \
  || fail "with the forge unread, a worktree-less flight's landing is unknown (got: $r)"
r=$(row "$out" "$REC")
[ "$(field "$r" 3)" = landed ] || fail "a committed record still reads landed without the forge (got: $r)"
out=$(cd "$repo" && "$SCRIPT" sweep --no-forge 2>/dev/null)
printf '%s\n' "$out" | grep -q "^forge${TAB}skipped" || fail "--no-forge reports the forge skipped"
(cd "$repo" && "$SCRIPT" sweep >/dev/null 2>&1)

# --- 6. Usage and hostile arguments ----------------------------------------
"$SCRIPT" >/dev/null 2>&1
[ $? -eq 2 ] || fail "no subcommand is a usage error"
"$SCRIPT" sweep --repo-root "$tmp/nowhere" >/dev/null 2>&1
[ $? -eq 2 ] || fail "a missing --repo-root is a usage error"
"$SCRIPT" sweep --bogus >/dev/null 2>&1
[ $? -eq 2 ] || fail "an unknown flag is a usage error"

# --- 7. The SessionStart hook ----------------------------------------------
jq -e '.hooks.SessionStart[].hooks[].command | select(test("flight-sweep.sh hook session-start"))' \
  "$ROOT/hooks/hooks.json" >/dev/null 2>&1 || fail "the flight sweep hook sits under SessionStart"

bare="$tmp/bare"
git -c init.defaultBranch=main init -q "$bare"
gitc "$bare" commit -q --allow-empty -m init
hout=$(cd "$bare" && PLANWRIGHT_FLEET_STATE_DIR="$tmp/nohome" "$SCRIPT" hook session-start </dev/null 2>&1)
rc=$?
[ "$rc" -eq 0 ] && [ -z "$hout" ] || fail "the hook is silent and exits 0 without flights (rc=$rc: $hout)"
[ ! -e "$tmp/nohome" ] || fail "the hook creates nothing in a checkout without flights"

rm -f "$idx"
hout=$(cd "$repo" && echo '{"source":"startup"}' | "$SCRIPT" hook session-start 2>&1)
rc=$?
[ "$rc" -eq 0 ] && [ -z "$hout" ] || fail "the hook is silent and exits 0 with flights (rc=$rc: $hout)"
cmp -s "$idx" "$c/first" || fail "the hook refreshes the index"

(cd "$repo" && PLANWRIGHT_FLEET_STATE_DIR="$c/README.md" "$SCRIPT" hook session-start </dev/null >/dev/null 2>&1) \
  || fail "the hook exits 0 on a broken fleet home"
hout=$(cd "$tmp" && "$SCRIPT" hook session-start </dev/null 2>&1)
rc=$?
[ "$rc" -eq 0 ] && [ -z "$hout" ] || fail "the hook is silent outside a git work tree"

# --- 8. Call sites and residues --------------------------------------------
grep -q 'scripts/flight-sweep.sh' "$ROOT/skills/tower/SKILL.md" \
  || fail "the tower's bring-up reads the shared flight sweep"
grep -q 'flight-sweep.sh' "$ROOT/scripts/fleet-sweep.sh" \
  || fail "the fleet cleanup sweep carries the flight residues"

gone="$tmp/gone"
git -c init.defaultBranch=main init -q "$gone"
gitc "$gone" commit -q --allow-empty -m init
gitc "$gone" branch "planwright/flight/$STRAND"
(cd "$gone" && "$SCRIPT" sweep --no-forge >/dev/null 2>&1) || fail "fixture: sweep of the doomed checkout"
gone_idx=$(cd "$gone" && "$SCRIPT" path)
[ -f "$gone_idx" ] || fail "fixture: the doomed checkout's index exists"
rm -rf "$gone"
out=$("$SCRIPT" prune 2>&1) || fail "prune exited non-zero: $out"
[ ! -e "$gone_idx" ] || fail "prune removes a vanished checkout's index"
[ -f "$idx" ] || fail "prune keeps a live checkout's index"
printf '%s\n' "$out" | grep -q "^pruned${TAB}" || fail "prune names what it removed"

if [ "$fails" -gt 0 ]; then
  echo "test-flight-sweep: $fails failure(s)" >&2
  exit 1
fi
echo "test-flight-sweep: all checks passed"
