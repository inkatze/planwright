#!/bin/bash
# The tower's operator-requested force-push path and the purge preparation:
# scripts/tower-force-push.sh against a fixture origin, and the tower queue's
# refusal of a standing decision that would run it.
#
# Verifies human-gates REQ-F1.2 (the refusal arms and the confirmation shape;
# the live run is the [manual] half), REQ-F1.4, and the legacy-id handoff of
# D-16.
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
FP="$here/../scripts/tower-force-push.sh"
CC="$here/../scripts/check-confirmation.sh"
TQ="$here/../scripts/tower-queue.sh"
failures=0

fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}
ok() { echo "ok: $1"; }

[ -x "$FP" ] || {
  echo "FAIL: scripts/tower-force-push.sh missing or not executable" >&2
  exit 1
}

tmp=$(mktemp -d)
trap 'chmod -R u+rwx "$tmp" 2>/dev/null; rm -rf "$tmp"' EXIT
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null HOME="$tmp"
export GIT_AUTHOR_NAME=Author GIT_AUTHOR_EMAIL=author@example.com
export GIT_COMMITTER_NAME=Committer GIT_COMMITTER_EMAIL=committer@example.com
export PLANWRIGHT_CONFIG_DEFAULTS="$tmp/core.yml" PLANWRIGHT_ADOPTER_OVERLAY="$tmp/adopter"
export PLANWRIGHT_LOCAL_CONFIG=""
printf 'protected_branches:\n' >"$tmp/core.yml"
mkdir -p "$tmp/adopter"

BR=planwright/demo/task-1
git init -q --bare -b main "$tmp/origin.git"
git clone -q "$tmp/origin.git" "$tmp/w" 2>/dev/null
W="$tmp/w"
export PLANWRIGHT_REPO_ROOT="$W"
g() { git -C "$W" "$@"; }
g config commit.gpgsign false
g commit -q --allow-empty -m 'chore: root'
g push -q origin main
g checkout -q -b "$BR"
echo one >"$W/a"
g add a
GIT_AUTHOR_DATE='1700000000 +0000' g commit -q -m 'Bad subject that fails the range lint'
BAD=$(g rev-parse HEAD)
echo two >"$W/b"
g add b
GIT_AUTHOR_DATE='1700000100 +0000' g commit -q -m 'fix: a legacy finding [pending-sign-off]'
LEGACY=$(g rev-parse HEAD)
echo three >"$W/c"
g add c
GIT_AUTHOR_DATE='1700000200 +0000' g commit -q -m 'feat: the last commit'
g push -q -u origin "$BR"
TIP=$(g rev-parse HEAD)

fp() { (cd "$W" && "$FP" "$@"); }
rc_of() {
  _rc=0
  "$@" >"$tmp/out" 2>"$tmp/err" || _rc=$?
  echo "$_rc"
}

# --- refusals: main, protected, spec ----------------------------------------
mkdir -p "$W/.claude"
printf 'protected_branches: release/*\n' >"$W/.claude/planwright.yml"
for b in main master planwright/demo/spec refs/heads/main release/v1; do
  for verb in confirm push; do
    if [ "$verb" = confirm ]; then
      rc=$(rc_of fp confirm --branch "$b" --to "$TIP")
    else
      rc=$(rc_of fp push --branch "$b" --to "$TIP" --lease "$TIP")
    fi
    # The refusal names the protected set, not a failure to read it: a broken
    # overlay also exits 1, with "the protected set could not be read".
    if ! { [ "$rc" = 1 ] && grep -q 'no tier rewrites it' "$tmp/err"; }; then
      fail "$verb on '$b' was not refused as protected (exit $rc: $(cat "$tmp/err"))"
    fi
  done
  rc=$(rc_of fp reword --branch "$b" --commit "$TIP" --message-file "$W/a")
  if ! { [ "$rc" = 1 ] && grep -q 'no tier rewrites it' "$tmp/err"; }; then
    fail "reword on '$b' was not refused as protected (exit $rc: $(cat "$tmp/err"))"
  fi
done
[ "$failures" = 0 ] && ok "every verb refuses main, master, a spec branch, and a protected_branches addition"
rm -f "$W/.claude/planwright.yml"

# --- reword: objects only ----------------------------------------------------
refs_before=$(g show-ref)
status_before=$(g status --porcelain)
printf 'feat: a subject that passes the range lint\n' >"$tmp/msg"
rc=$(rc_of fp reword --branch "$BR" --commit "$BAD" --message-file "$tmp/msg")
[ "$rc" = 0 ] || fail "reword failed (exit $rc: $(cat "$tmp/err"))"
NEW=$(awk -F '\t' '$1 == "to" { print $2 }' "$tmp/out")
[ "$(awk -F '\t' '$1 == "lease" { print $2 }' "$tmp/out")" = "$TIP" ] || fail "reword did not report the remote tip as the lease"
if [ -z "$NEW" ] || [ "$NEW" = "$TIP" ]; then fail "reword printed no new tip"; fi
if [ "$(g show-ref)" = "$refs_before" ] && [ "$(g status --porcelain)" = "$status_before" ]; then
  ok "reword changes no ref and no working tree"
else
  fail "reword moved a ref or the working tree"
fi
[ "$(g rev-parse "$NEW^{tree}")" = "$(g rev-parse "$TIP^{tree}")" ] || fail "reword changed the tip's tree"
[ "$(g log --format=%s "main..$NEW" | tail -1)" = 'feat: a subject that passes the range lint' ] \
  || fail "the reworded commit does not carry the new message"
[ "$(g log --format='%an %ad' --date=raw "main..$NEW")" = "$(g log --format='%an %ad' --date=raw "main..$TIP")" ] \
  || fail "reword did not keep each commit's author and date"
if [ "$(g log --format=%s "main..$NEW" | sed -n 1,2p)" = "$(g log --format=%s "main..$TIP" | sed -n 1,2p)" ]; then
  ok "reword replaces one message and replays the rest with tree, author, and message kept"
else
  fail "reword changed a later commit's message"
fi

rc=$(rc_of fp reword --branch "$BR" --commit "$(g rev-parse main)" --message-file "$tmp/msg")
if [ "$rc" = 1 ] && grep -q 'which is protected' "$tmp/err"; then
  ok "reword refuses a commit a protected branch contains"
else
  fail "reword of a commit on main was not refused (exit $rc)"
fi
g checkout -q -b elsewhere main
g commit -q --allow-empty -m 'chore: elsewhere'
rc=$(rc_of fp reword --branch "$BR" --commit "$(g rev-parse HEAD)" --message-file "$tmp/msg")
if [ "$rc" = 1 ]; then
  ok "reword refuses a commit that is not on the branch"
else
  fail "an off-branch commit was not refused (exit $rc)"
fi
g checkout -q "$BR"
printf ' \n\t\n' >"$tmp/blank"
rc=$(rc_of fp reword --branch "$BR" --commit "$BAD" --message-file "$tmp/blank")
if [ "$rc" = 2 ]; then
  ok "reword refuses an empty message file"
else
  fail "a blank message file was not a usage error (exit $rc)"
fi

# --- confirm: the shape, the dropped commits, the legacy ids -----------------
rc=$(rc_of fp confirm --branch "$BR" --to "$NEW")
[ "$rc" = 0 ] || fail "confirm failed (exit $rc: $(cat "$tmp/err"))"
cp "$tmp/out" "$tmp/confirm.json"
if "$CC" "$tmp/confirm.json" >/dev/null 2>&1; then
  ok "the confirmation passes check-confirmation.sh"
else
  fail "the confirmation fails check-confirmation.sh"
fi
q=$(jq -r .question "$tmp/confirm.json")
for c in "$BAD" "$LEGACY" "$TIP"; do
  case $q in
    *"$(printf '%s' "$c" | cut -c1-7)"*) ;;
    *) fail "the question does not name the dropped commit $(printf '%s' "$c" | cut -c1-7)" ;;
  esac
done
if [ "$(jq '.dropped | length' "$tmp/confirm.json")" = 3 ]; then
  ok "the confirmation names every remote commit the push drops"
else
  fail "the confirmation's dropped list is wrong"
fi
NEWLEG=$(g log --format=%H --grep='legacy finding' "main..$NEW")
want_from="PS-legacy-$(printf '%s' "$LEGACY" | cut -c1-7)"
want_to="PS-legacy-$(printf '%s' "$NEWLEG" | cut -c1-7)"
if [ "$(jq -r '.legacy[0].from + " " + .legacy[0].to' "$tmp/confirm.json")" = "$want_from $want_to" ]; then
  ok "the confirmation pairs the changed legacy id with its replacement"
else
  fail "the legacy id change is wrong: $(jq -c .legacy "$tmp/confirm.json")"
fi
[ "$(jq -r '.push | .[1:] | join(" ")' "$tmp/confirm.json")" = "push --remote origin --branch $BR --to $NEW --lease $TIP" ] \
  || fail "the push argv does not carry this confirmation's lease"
[ "$(jq '[.options[] | select(.reject == true)] | length' "$tmp/confirm.json")" = 1 ] \
  || fail "the confirmation has no single reject option"

rc=$(rc_of fp confirm --branch "$BR" --to "$TIP")
rc2=$(rc_of fp push --branch "$BR" --to "$TIP" --lease "$TIP")
if [ "$rc" = 1 ] && [ "$rc2" = 1 ] && grep -q 'nothing is dropped' "$tmp/err"; then
  ok "confirm and push refuse a tip that drops nothing"
else
  fail "a no-op force was not refused (confirm exit $rc, push exit $rc2)"
fi

# --- push: only on the confirmed lease ----------------------------------------
rc=$(rc_of fp push --branch "$BR" --to "$NEW")
[ "$rc" = 2 ] || fail "push without --lease was not a usage error (exit $rc)"
# A --to that is not a commit is a usage error before any push: an empty
# source would push `:<branch>`, which deletes the remote branch.
for verb in push confirm; do
  if [ "$verb" = push ]; then
    rc=$(rc_of fp push --branch "$BR" --to no-such-rev --lease "$TIP")
  else
    rc=$(rc_of fp confirm --branch "$BR" --to no-such-rev)
  fi
  [ "$rc" = 2 ] && [ "$(git -C "$tmp/origin.git" rev-parse --verify -q "refs/heads/$BR")" = "$TIP" ] \
    || fail "$verb with a --to that is not a commit exited $rc or moved the remote branch"
done
rc=$(rc_of fp reword --branch "$BR" --commit no-such-rev --message-file "$tmp/msg")
[ "$rc" = 2 ] || fail "reword of a --commit that is not a commit was not a usage error (exit $rc)"
[ "$failures" = 0 ] && ok "a --to or --commit that is not a commit is refused before anything runs"
git clone -q -b "$BR" "$tmp/origin.git" "$tmp/other" 2>/dev/null
git -C "$tmp/other" config commit.gpgsign false
git -C "$tmp/other" commit -q --allow-empty -m 'feat: someone else pushed'
git -C "$tmp/other" push -q origin "$BR"
MOVED=$(git -C "$tmp/other" rev-parse HEAD)
rc=$(rc_of fp push --branch "$BR" --to "$NEW" --lease "$TIP")
if [ "$rc" = 1 ] && grep -q 'moved since the confirmation' "$tmp/err" \
  && [ "$(git -C "$tmp/origin.git" rev-parse "refs/heads/$BR")" = "$MOVED" ]; then
  ok "push refuses when the remote moved since the confirmation, and leaves it alone"
else
  fail "a push over a moved remote was not refused (exit $rc)"
fi
git -C "$tmp/origin.git" update-ref "refs/heads/$BR" "$TIP"

rc=$(rc_of fp push --branch "$BR" --to "$NEW" --lease "$TIP")
[ "$rc" = 0 ] || fail "the confirmed push failed (exit $rc: $(cat "$tmp/err"))"
if [ "$(git -C "$tmp/origin.git" rev-parse "refs/heads/$BR")" = "$NEW" ]; then
  ok "the confirmed push lands the new tip"
else
  fail "the remote is not at the new tip"
fi
[ "$(grep -c '^dropped' "$tmp/out")" = 3 ] || fail "the push handoff does not list the dropped commits"
if grep -q "^legacy	$want_from	$want_to\$" "$tmp/out" && grep -q 're-stamp' "$tmp/out"; then
  ok "the push handoff names the changed legacy id for re-stamping"
else
  fail "the push handoff does not name the legacy id change: $(cat "$tmp/out")"
fi

# --- purge: printed, never run -------------------------------------------------
mkdir -p "$tmp/stub"
for t in git git-filter-repo gh; do
  printf '#!/bin/sh\necho "%s $*" >>"%s/calls"\nexit 0\n' "$t" "$tmp" >"$tmp/stub/$t"
  chmod +x "$tmp/stub/$t"
done
: >"$tmp/calls"
rc=0
PATH="$tmp/stub:$PATH" "$FP" purge --path 'config/secrets.env' --replace-text "it's.txt" >"$tmp/out" 2>"$tmp/err" || rc=$?
[ "$rc" = 0 ] || fail "purge failed (exit $rc)"
if [ ! -s "$tmp/calls" ]; then
  ok "purge runs no git, filter-repo, or host command"
else
  fail "purge ran: $(cat "$tmp/calls")"
fi
if grep -qF "git filter-repo --sensitive-data-removal --invert-paths --path 'config/secrets.env' --replace-text 'it'\\''s.txt'" "$tmp/out"; then
  ok "purge prints the quoted command"
else
  fail "purge printed no usable command: $(cat "$tmp/out")"
fi
if grep -q 'Revoke or rotate' "$tmp/out" && grep -q 'nothing here was executed' "$tmp/out"; then
  ok "purge prints the rotation checklist and says it ran nothing"
else
  fail "purge printed no rotation checklist"
fi
rc=$(rc_of "$FP" purge)
[ "$rc" = 2 ] || fail "purge with nothing to purge was not a usage error (exit $rc)"
rc=$(rc_of "$FP" purge --path "$(printf 'a\033[31mb')")
[ "$rc" = 2 ] || fail "purge took a path carrying a control character (exit $rc)"

# --- the tower queue: no standing decision runs it ------------------------------
qhome="$tmp/qhome"
mkdir -m 0700 "$qhome"
: >"$tmp/local.yml"
tq() {
  PLANWRIGHT_FLEET_STATE_DIR="$qhome" PLANWRIGHT_ADOPTER_OVERLAY="$tmp/adopter" \
    PLANWRIGHT_REPO_ROOT=none PLANWRIGHT_LOCAL_CONFIG="$tmp/local.yml" /bin/sh "$TQ" "$@"
}
for cov in 'scripts/tower-force-push.sh push' 'scripts/tower-force-push.sh'; do
  rc=0
  tq capture --kind standing --text 'force-push my branch whenever it fails the lint' \
    --covers-command "$cov" --now 1000 >/dev/null 2>"$tmp/err" || rc=$?
  [ "$rc" = 2 ] || fail "a standing decision covering '$cov' was captured (exit $rc)"
done
[ "$failures" = 0 ] && ok "a standing decision covering the force-push path is refused at capture"
rule=$(tq capture --kind standing --text 'let the tower run its own scripts' --covers-command 'scripts/' --now 1010 2>/dev/null \
  | awk -F '\t' '{ print $2 }')
for cmd in "scripts/tower-force-push.sh push --branch $BR --to $NEW --lease $TIP" \
  "scripts/tower-force-push.sh confirm --branch $BR --to $NEW"; do
  rc=0
  out=$(tq match --decision "$rule" --command "$cmd" 2>/dev/null) || rc=$?
  [ "$rc" = 1 ] && [ "$out" = reserved ] || fail "a covering rule matched '$cmd' (exit $rc, '$out')"
done
[ "$failures" = 0 ] && ok "a standing decision covering scripts/ never answers the force-push path"

# --- the gate-failure handoff names the path (REQ-F1.3, the CI grep half) -------
# flat <file> [<from heading> <to heading>] — the section collapsed to one
# line, lowercased, so a statement matches however the markdown wraps it.
flat() {
  awk -v a="${2:-}" -v b="${3:-}" 'a == "" || index($0, a) == 1 { on = 1 } on && b != "" && index($0, b) == 1 { on = 0 } on' "$1" \
    | tr '\n\t' '  ' | tr -s ' ' | tr '[:upper:]' '[:lower:]'
}
# shellcheck disable=SC2016 # the backticks are markdown, matched literally
REWORD='such a commit is reworded only through the tower'"'"'s force-push path (`scripts/tower-force-push.sh`, on the operator'"'"'s request, [human gates](human-gates.md)), so name that path as the reason and add no commit for it.'
# /execute-task halts a logic CI failure through gate-wiring's pause protocol,
# which it loads at that point, so the rule lives there.
section=$(flat "$here/../doctrine/gate-wiring.md" '## Pause protocol' '## Loop-end handoff')
case $section in
  *"$(printf '%s' "$REWORD" | tr '[:upper:]' '[:lower:]')"*) ok "the gate-failure handoff rule names the tower reword path" ;;
  *) fail "gate-wiring's pause protocol does not name the tower reword path" ;;
esac
tower=$(flat "$here/../skills/tower/SKILL.md" '## Refusals' '## Survival')
# shellcheck disable=SC2016 # the backticks are markdown, matched literally
for want in 'scripts/tower-force-push.sh confirm' 'never from a standing decision' 'run its `push` line only on the yes, in the same turn' 'its `purge` prints; the operator runs it'; do
  case $tower in
    *"$want"*) ;;
    *) fail "the tower's refusals do not carry: $want" ;;
  esac
done
[ "$failures" = 0 ] && ok "the tower's refusals carry the force-push path and its limits"

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all tower-force-push checks passed"
