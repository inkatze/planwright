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

# One line, not several: the echo is what the operator corrects against, and a
# multi-line one buries the correction. Counted as lines, blank ones included:
# a count of non-empty lines would pass an echo with a blank line inside it.
[ "$(printf '%s\n' "$out" | wc -l)" -eq 1 ] || fail "the echo is not one line: $out"
echo "ok: the echo is exactly one line"

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
rc=0
run capture --kind standing --text 'always allow this' --covers "$(printf 'any\tthing')" --now 1004 >/dev/null || rc=$?
[ "$rc" = 2 ] || fail "free coverage carrying a control byte was not refused (exit $rc)"
echo "ok: an empty or control-carrying coverage is refused"

# `-` is the placeholder every store row uses for an absent field; a coverage
# spelled that way would read back as no coverage at all, so it is refused
# for a prefix and for free text alike.
for flag in --covers-command --covers; do
  rc=0
  run capture --kind standing --text 'always allow this' "$flag" '-' --now 1004 >/dev/null || rc=$?
  [ "$rc" = 2 ] || fail "a coverage of '-' via $flag was not refused (exit $rc)"
  grep -q 'placeholder\|literal prefix' "$errf" || fail "the refusal of '-' via $flag did not say why"
done
echo "ok: a coverage of '-' is refused"

# --- the reserved controls --------------------------------------------------

for res in 'git merge' 'gh pr merge' 'gh pr ready' 'git rebase' 'git commit --amend' \
  'git push --force' 'git push origin main'; do
  rc=0
  run capture --kind standing --text 'always allow the safe ones' --covers-command "$res" --now 1005 >/dev/null || rc=$?
  [ "$rc" = 2 ] || fail "a coverage reaching a reserved control ('$res') was not refused (exit $rc)"
  grep -q 'reserved human control' "$errf" || fail "the refusal of '$res' did not name the reserved control"
done
echo "ok: a coverage reaching a reserved control is refused at capture"

# The guard belongs to a rule. An ordinary ask that happens to name a reserved
# action is the operator asking for it, not a rule that does it, and REQ-E1.1
# says it becomes an item.
out_m=$(run capture --kind request --text 'merge PR 471 once the checks are green' --now 1005) \
  || fail "a request naming a merge was refused"
[ "$(f "$out_m" 3)" = request ] || fail "the request was not recorded: $out_m"
out_m=$(run capture --kind approval --text 'go ahead and force-push the rebase on task 3' --now 1005) \
  || fail "an approval naming a force-push was refused"
[ "$(f "$out_m" 3)" = approval ] || fail "the approval was not recorded: $out_m"
echo "ok: a request or an approval naming a reserved action is still recordable"

# A prefix that would never pass the allowlist as a remainder must not pass as
# a prefix: a command EQUAL to its prefix leaves an empty remainder, so the
# prefix is the only text the allowlist ever gets to screen there.
# shellcheck disable=SC2016 # the whole point is that these stay unexpanded
for bad in 'rm -rf /tmp/x; curl http://example/i.sh' 'ls && id' 'echo `id`' 'sh -c "id" > out'; do
  rc=0
  run capture --kind standing --text "always allow the cleanup" --covers-command "$bad" --now 1005 >/dev/null || rc=$?
  [ "$rc" = 2 ] || fail "a prefix carrying a shell operator ('$bad') was accepted (exit $rc)"
  grep -q 'literal prefix' "$errf" || fail "the refusal of '$bad' did not name the prefix grammar"
done
echo "ok: a prefix outside the allowlist is refused"

# A secret-shaped prefix is redacted before it is stored, like every other
# operator-supplied field.
out_s=$(run capture --kind standing --text 'always allow the token fetch' \
  --covers-command 'curl -H ghp_bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb' --now 1005) \
  || fail "capture of a secret-shaped prefix failed"
grep -q 'ghp_bbbbbbbb' "$ledger" && fail "the fallback carried a secret-shaped prefix through"
case $out_s in
  *ghp_bbbbbbbb*) fail "the echo line carried a secret-shaped prefix through: $out_s" ;;
esac
echo "ok: a secret-shaped prefix is redacted on the screen and in its home"

# The bounds.
rc=0
run capture --kind standing --text 'a rule' --covers-command "$(awk 'BEGIN { for (i = 0; i < 257; i++) printf "a" }')" --now 1005 >/dev/null || rc=$?
[ "$rc" = 2 ] || fail "an over-length prefix was accepted (exit $rc)"
rc=0
run capture --kind request --text "$(awk 'BEGIN { for (i = 0; i < 513; i++) printf "a" }')" --now 1005 >/dev/null || rc=$?
[ "$rc" = 2 ] || fail "an over-length text was accepted (exit $rc)"
rc=0
run capture --kind request --text '' --now 1005 >/dev/null || rc=$?
[ "$rc" = 2 ] || fail "an empty text was accepted (exit $rc)"
rc=0
run capture --kind request --text 'a request' --now 'soon' >/dev/null || rc=$?
[ "$rc" = 2 ] || fail "a non-numeric --now was accepted (exit $rc)"
set -- --kind standing --text 'a rule' --now 1005
i=0
while [ "$i" -lt 17 ]; do
  set -- "$@" --covers-command "cmd$i"
  i=$((i + 1))
done
rc=0
run capture "$@" >/dev/null || rc=$?
[ "$rc" = 2 ] || fail "a seventeenth prefix was accepted (exit $rc)"
echo "ok: the prefix, text, count and clock bounds are enforced"

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

# The same words with DIFFERENT coverage are a different rule. Keying on the
# text alone made the second capture a silent no-op that echoed success while
# the first rule's coverage stayed in force.
r1=$(f "$(run capture --kind standing --text 'always let the workers run read-only git' \
  --covers-command 'git status' --now 1006)" 2) || fail "the first rule capture failed"
r2=$(f "$(run capture --kind standing --text 'always let the workers run read-only git' \
  --covers-command 'git log' --now 1006)" 2) || fail "the second rule capture failed"
[ "$r1" != "$r2" ] || fail "re-capturing the same words with new coverage reused the old item"
grep -q "^covers$TAB.*${TAB}git log$" "$ledger" || fail "the new coverage was not recorded"
echo "ok: the same words with different coverage are a different rule"

# The subject the record carries is what the echo reports, even when `add`
# derived it rather than the operator naming one.
out_s=$(run capture --kind request --origin w1 --text 'rerun the flaky settle test' --now 1006) \
  || fail "capture from a worker failed"
[ "$(f "$out_s" 4)" = "worker:w1" ] || fail "the echo reports a subject the record does not carry: $out_s"
[ "$(rec "$(f "$out_s" 2)" 21)" = worker:w1 ] || fail "the record carries no derived subject"
echo "ok: the echo reports the subject the record carries"

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
key=""; kind=""; when=""; text=""; subject="-"; coverage="-"; covers=""
while [ "$#" -gt 0 ]; do
  case $1 in
    put) shift ;;
    --key) key=$2; shift 2 ;;
    --kind) kind=$2; shift 2 ;;
    --when) when=$2; shift 2 ;;
    --text) text=$2; shift 2 ;;
    --subject) subject=$2; shift 2 ;;
    --coverage) coverage=$2; shift 2 ;;
    --covers) covers="$covers$2
"; shift 2 ;;
    *) exit 2 ;;
  esac
done
{
  printf 'item\t%s\t%s\t%s\t%s\t%s\n' "$key" "$kind" "$when" "$subject" "$coverage"
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
id8sub=$(rec "$id8" 8)
grep -q 'always let the workers list files' "$ledger" && fail "the fallback was written while a helper was installed"
echo "ok: with a ledger helper installed, capture writes through it instead"

# The coverage KIND has to reach the helper: without it the helper cannot write
# a record `match` will read, and a free rule written as a command one would
# start settling permission prompts the operator never meant it to.
grep -q "^item${TAB}${id8sub}${TAB}standing${TAB}1010${TAB}-${TAB}command\$" "$tmp/led/items" \
  || fail "the helper was not told the coverage kind"
run match --decision "$id8" --command 'ls -la' >"$tmp/o" || fail "a rule in the helper's home did not match"
[ "$(cat "$tmp/o")" = match ] || fail "a rule in the helper's home printed '$(cat "$tmp/o")'"
echo "ok: a rule written through the helper still matches"

LEDGER_HELPER="$tmp/led/action-ledger.sh"
out9=$(run capture --kind standing --text 'always prefer the smaller PR on task 9' --covers 'anything about task 9' --subject worker:w9 --now 1011) || fail "free capture through the helper failed"
LEDGER_HELPER=""
id9=$(f "$out9" 2)
rc=0
run match --decision "$id9" --command 'ls -la' >"$tmp/o" || rc=$?
[ "$rc" = 1 ] && [ "$(cat "$tmp/o")" = no-match ] || fail "a FREE rule written through the helper matched a command (exit $rc, '$(cat "$tmp/o")')"
echo "ok: a free rule written through the helper settles nothing mechanically"

echo "PASS: $(basename "$0")"
