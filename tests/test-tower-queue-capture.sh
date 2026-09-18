#!/bin/bash
# Tests for scripts/tower-queue.sh's `capture` verb — inbound capture of the
# operator's own asks and their standing decisions, the pre-ship fallback that
# holds them until the action-item ledger ships, the coverage grammar, and the
# reserved-control refusal (REQ-A1.3, REQ-E1.1, REQ-E1.2, REQ-E1.3, REQ-E1.9,
# REQ-G1.8, REQ-H1.1, REQ-H1.3; D-11, D-12).
#
# Contract under test:
#   capture --kind request|approval|standing --text <text>
#           [--covers <free text> | --covers-command <prefix> ...]
#           [--subject <key>] [--origin <who>] [--urgency u] [--closes <text>]
#       Writes the content to its durable home, registers the queue record that
#       points at it, and prints ONE echo line: `captured`, the id, the kind,
#       the subject, the coverage kind, and the text as the operator is shown
#       it. No confirmation is asked for.
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
TQ="$here/../scripts/tower-queue.sh"

errf=""

fail() {
  echo "FAIL: $1" >&2
  if [ -n "${errf:-}" ] && [ -s "$errf" ]; then
    echo "--- stderr of the last tower-queue run ---" >&2
    cat "$errf" >&2
  fi
  exit 1
}

[ -x "$TQ" ] || fail "scripts/tower-queue.sh missing or not executable"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
errf="$tmp/stderr"

home="$tmp/fleet-home"
mkdir -p "$home"
chmod 0700 "$home"
adopter="$tmp/adopter"
mkdir -p "$adopter"
local_cfg="$tmp/local.yml"
: >"$local_cfg"

surface="$home/tower-comms"
ledger="$surface/ledger"
store="$surface/queue"

TAB=$(printf '\t')

run() {
  : >"$errf"
  PLANWRIGHT_FLEET_STATE_DIR="$home" \
    PLANWRIGHT_ADOPTER_OVERLAY="$adopter" \
    PLANWRIGHT_REPO_ROOT="$tmp" \
    PLANWRIGHT_LOCAL_CONFIG="$local_cfg" \
    PLANWRIGHT_ACTION_LEDGER="${LEDGER_HELPER:-}" \
    /bin/sh "$TQ" "$@" 2>"$errf"
}

# f <line> <n> — the nth tab-separated field of a line.
f() {
  printf '%s' "$1" | cut -d"$TAB" -f"$2"
}

# rec <id> <n> — the nth field of the queue record with that id.
rec() {
  awk -F "$TAB" -v i="$1" -v n="$2" '($1 "") == (i "") { print $n; exit }' "$store"
}

# --- a request ---------------------------------------------------------------

out=$(run capture --kind request --text 'rerun the flaky settle test on task 5' --now 1000) \
  || fail "capture of a request failed"
[ "$(f "$out" 1)" = captured ] || fail "the echo line is not tagged captured: $out"
id=$(f "$out" 2)
case $id in
  i????????) ;;
  *) fail "the echo line carries no item id: $out" ;;
esac
[ "$(f "$out" 3)" = request ] || fail "the echo line names the wrong kind: $out"
[ "$(f "$out" 6)" = 'rerun the flaky settle test on task 5' ] || fail "the echo does not repeat what was recorded: $out"
[ -f "$ledger" ] || fail "the pre-ship fallback was not created"
# shellcheck disable=SC2012 # the mode column is what this reads, and the path is ours
mode=$(ls -l "$ledger" | cut -c1-10)
case $mode in
  -rw-------) ;;
  *) fail "the fallback is not owner-only ($mode)" ;;
esac
grep -q 'rerun the flaky settle test' "$ledger" || fail "the request's text is not in the fallback"
[ "$(rec "$id" 2)" = request ] || fail "the queue record is not a request"
[ "$(rec "$id" 6)" = path ] || fail "the queue record does not point at a path home"
[ "$(rec "$id" 7)" = ledger ] || fail "the queue record does not point at the fallback"
echo "ok: a request lands in the fallback with a record pointing at it"

# The content home is written BEFORE the record: the record's own pointer
# resolves to a file that exists.
[ -f "$(rec "$id" 9)/$(rec "$id" 7)" ] || fail "the record points at nothing"
echo "ok: the content is at its home before the record that points at it"

# --- an approval, into the same file, as its own item ------------------------

out2=$(run capture --kind approval --text 'go ahead and land PR 471' --subject pr:471 --now 1001) \
  || fail "capture of an approval failed"
id2=$(f "$out2" 2)
[ "$id2" != "$id" ] || fail "two captures into one ledger collapsed to one item"
[ "$(f "$out2" 4)" = pr:471 ] || fail "the echo line does not carry the subject: $out2"
[ "$(rec "$id2" 21)" = pr:471 ] || fail "the record does not carry the subject"
grep -q 'go ahead and land PR 471' "$ledger" || fail "the approval's text is not in the fallback"
grep -q 'rerun the flaky settle test' "$ledger" || fail "the approval overwrote the request"
echo "ok: a second capture into the same file is its own item"

# The same words captured twice are the same item, not a second one.
out3=$(run capture --kind request --text 'rerun the flaky settle test on task 5' --now 1002) \
  || fail "a repeated capture failed"
[ "$(f "$out3" 2)" = "$id" ] || fail "a repeated capture minted a second id"
echo "ok: the same words captured twice are one item"

# --- a standing decision with command coverage ------------------------------

out4=$(run capture --kind standing --text 'always let the workers run read-only git' \
  --covers-command 'git status' --covers-command 'git log' --now 1003) \
  || fail "capture of a standing decision failed"
id4=$(f "$out4" 2)
[ "$(f "$out4" 5)" = command ] || fail "the echo does not name the coverage kind: $out4"
[ "$(rec "$id4" 2)" = standing ] || fail "the record is not a standing decision"
[ "$(rec "$id4" 11)" = "the operator revokes the rule" ] || fail "the standing record's closing condition is wrong"
grep -q "^covers$TAB.*${TAB}git status$" "$ledger" || fail "the first prefix is not in the fallback"
grep -q "^covers$TAB.*${TAB}git log$" "$ledger" || fail "the second prefix is not in the fallback"
echo "ok: a standing decision records its rule, its prefixes and its date"

# The date it was said.
grep -q "^item$TAB.*${TAB}standing${TAB}1003$TAB" "$ledger" || fail "the standing record carries no date"
echo "ok: the standing record carries when it was said"

# --- the coverage grammar ---------------------------------------------------

for bad in 'git *' 'git?' 'git[a-z]' ' git' '^git' 'git|ls'; do
  rc=0
  run capture --kind standing --text "always allow $bad" --covers-command "$bad" --now 1004 >/dev/null || rc=$?
  [ "$rc" = 2 ] || fail "a pattern-shaped coverage '$bad' was not refused (exit $rc)"
done
echo "ok: a glob- or regex-shaped coverage is refused"

rc=0
run capture --kind standing --text 'always allow this' --covers-command '' --now 1004 >/dev/null || rc=$?
[ "$rc" = 2 ] || fail "an empty coverage was not refused (exit $rc)"
rc=0
run capture --kind standing --text 'always allow this' --covers-command "$(printf 'git\tstatus')" --now 1004 >/dev/null || rc=$?
[ "$rc" = 2 ] || fail "a coverage carrying a control byte was not refused (exit $rc)"
echo "ok: an empty or control-carrying coverage is refused"

# --- the reserved controls --------------------------------------------------

for res in 'git merge' 'gh pr merge' 'gh pr ready' 'git rebase' 'git commit --amend' \
  'git push --force' 'git push origin main'; do
  rc=0
  run capture --kind standing --text 'always allow the safe ones' --covers-command "$res" --now 1005 >/dev/null || rc=$?
  [ "$rc" = 2 ] || fail "a coverage reaching a reserved control ('$res') was not refused (exit $rc)"
  grep -q 'reserved human control' "$errf" || fail "the refusal of '$res' did not name the reserved control"
done
echo "ok: a coverage reaching a reserved control is refused at capture"

# Free coverage text reaches one too, and is refused the same way.
rc=0
run capture --kind standing --text 'a rule' --covers 'anything about merging branches' --now 1005 >/dev/null || rc=$?
[ "$rc" = 2 ] || fail "free coverage reaching a reserved control was not refused (exit $rc)"
echo "ok: free coverage reaching a reserved control is refused too"

# --- a non-command rule -----------------------------------------------------

out5=$(run capture --kind standing --text 'always prefer the smaller PR on task 5' \
  --covers 'anything about task 5' --subject worker:w5 --now 1006) \
  || fail "capture of a non-command standing decision failed"
id5=$(f "$out5" 2)
[ "$(f "$out5" 5)" = free ] || fail "the echo does not name free coverage: $out5"
[ "$(rec "$id5" 21)" = worker:w5 ] || fail "the record does not carry the explicit subject key"
echo "ok: a non-command rule is stored with free coverage and an explicit subject"

# Coverage belongs to a standing decision alone.
rc=0
run capture --kind request --text 'do a thing' --covers-command 'git status' --now 1007 >/dev/null || rc=$?
[ "$rc" = 2 ] || fail "coverage on a request was not refused (exit $rc)"
echo "ok: coverage on a request is refused"

# The two coverage forms are mutually exclusive.
rc=0
run capture --kind standing --text 'a rule' --covers 'some text' --covers-command 'git status' --now 1007 >/dev/null || rc=$?
[ "$rc" = 2 ] || fail "mixed coverage forms were not refused (exit $rc)"
echo "ok: the two coverage forms are mutually exclusive"

# --- hygiene ----------------------------------------------------------------

out6=$(run capture --kind request --text 'use token ghp_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa for it' --now 1008) \
  || fail "capture of a secret-shaped text failed"
case $out6 in
  *ghp_aaaaaaaa*) fail "the echo line carried the secret through: $out6" ;;
  *'[redacted:github-token]'*) ;;
  *) fail "the echo line neither redacted nor carried the secret: $out6" ;;
esac
grep -q 'ghp_aaaaaaaa' "$ledger" && fail "the fallback carried the secret through"
echo "ok: a secret-shaped capture is redacted on the screen and in its home"

# Non-ASCII text is shown escaped, with a warning.
out7=$(run capture --kind request --text 'rerun the caf√© test' --now 1009) || fail "capture of non-ASCII text failed"
case $(f "$out7" 6) in
  *'\x'*) ;;
  *) fail "non-ASCII text was not escaped for the operator: $out7" ;;
esac
grep -q 'outside printable ASCII' "$errf" || fail "the escape came with no warning"
echo "ok: non-ASCII text is shown escaped beside a warning"

# --- the ledger helper, once it ships ---------------------------------------

mkdir -p "$tmp/led"
cat >"$tmp/led/action-ledger.sh" <<'HELPER'
#!/bin/sh
# A stub standing in for the action-item ledger's own helper: it writes the
# same ledger-shaped record and names the home it wrote.
set -u
root=$(dirname "$0")
out="$root/items"
key=""; kind=""; when=""; text=""; subject="-"; covers=""
while [ "$#" -gt 0 ]; do
  case $1 in
    put) shift ;;
    --key) key=$2; shift 2 ;;
    --kind) kind=$2; shift 2 ;;
    --when) when=$2; shift 2 ;;
    --text) text=$2; shift 2 ;;
    --subject) subject=$2; shift 2 ;;
    --covers) covers="$covers$2
"; shift 2 ;;
    *) exit 2 ;;
  esac
done
{
  printf 'item\t%s\t%s\t%s\t%s\tcommand\n' "$key" "$kind" "$when" "$subject"
  printf 'text\t%s\t%s\n' "$key" "$text"
  printf '%s' "$covers" | while IFS= read -r c; do
    [ -n "$c" ] || continue
    printf 'covers\t%s\t%s\n' "$key" "$c"
  done
} >>"$out"
chmod 0600 "$out"
printf '%s\t%s\n' "$root" items
HELPER
chmod +x "$tmp/led/action-ledger.sh"

LEDGER_HELPER="$tmp/led/action-ledger.sh"
out8=$(run capture --kind standing --text 'always let the workers list files' \
  --covers-command 'ls' --now 1010) || fail "capture through the ledger helper failed"
LEDGER_HELPER=""
id8=$(f "$out8" 2)
[ -f "$tmp/led/items" ] || fail "the ledger helper wrote nothing"
grep -q 'always let the workers list files' "$tmp/led/items" || fail "the helper's item has no text"
[ "$(rec "$id8" 7)" = items ] || fail "the queue record does not point at the helper's home"
[ "$(rec "$id8" 9)" = "$tmp/led" ] || fail "the queue record does not name the helper's root"
grep -q 'always let the workers list files' "$ledger" && fail "the fallback was written while a helper was installed"
echo "ok: with a ledger helper installed, capture writes through it instead"

echo "PASS: $(basename "$0")"
