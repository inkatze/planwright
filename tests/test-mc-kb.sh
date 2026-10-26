#!/bin/bash
# Tests for scripts/mc-kb.sh — a program's knowledge base: the layout under
# the program home, the index and its line budget, capped reads, the
# append-only decisions, undo and would-have logs in monthly segments, the
# one-writer locks, the follow-up ledger, the source table and the mechanism
# inventory (mission-control REQ-D1.7, REQ-F1.10, REQ-K1.1 to REQ-K1.7).
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-mc-kb.sh
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$here/.." && pwd)

failures=0
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}
ok() { echo "ok: $1"; }

[ -f "$repo_root/scripts/mc-kb.sh" ] || {
  echo "FAIL: scripts/mc-kb.sh missing" >&2
  exit 1
}

command -v jq >/dev/null 2>&1 || {
  echo "FAIL: jq is required by the mechanism inventory's hook and permission rows" >&2
  exit 1
}

tmp=$(mktemp -d) || exit 1
if [ -z "$tmp" ] || [ ! -d "$tmp" ]; then
  echo "FAIL: mktemp -d produced no usable directory" >&2
  exit 1
fi
holder_pid=''
cleanup() {
  [ -z "$holder_pid" ] || kill "$holder_pid" 2>/dev/null
  rm -rf "$tmp"
}
trap cleanup EXIT
tmp=$(cd "$tmp" && pwd -P) || exit 1

# shellcheck source=tests/lib/mission-control-fixture.sh
. "$here/lib/mission-control-fixture.sh"

tab=$(printf '\t')
reset_mc_fixture
mkdir -p "$repo/specs" "$core/docs"

alpha_block() { # alpha_block [extra lines on stdin]
  {
    printf '%s\n' "mission_control_programs: [alpha]" \
      "program_alpha_repositories: [$repo]" \
      "program_alpha_spec_root: $repo/specs" \
      "program_alpha_duties: [alpha-duty, beta-duty]"
    cat
  } >"$tracked"
}
alpha_block </dev/null
home="$fixhome/.config/planwright/mission-control/alpha"
kb="$home/kb"
month=$(date -u '+%Y-%m')

# ---------------------------------------------------------------------------
# REQ-K1.1: the layout lives under the program home, never a repository.
# ---------------------------------------------------------------------------
mc_run mc-kb.sh init --program alpha
expect_rc "init creates the layout" 0
for f in index.md followups.tsv sources.tsv mechanisms.tsv; do
  if [ -f "$kb/$f" ]; then ok "init creates kb/$f"; else fail "init did not create kb/$f"; fi
done
if [ -z "$(cd "$repo" && git status --porcelain --untracked-files=all -- . ':!.claude')" ]; then
  ok "init writes nothing into the work repository"
else
  fail "init wrote into the work repository"
fi

printf '%s\n' "program_alpha_home: $repo/mc-home" >>"$tracked"
mc_run mc-kb.sh init --program alpha
expect_rc "a home inside a work repository is refused" 1
if [ -e "$repo/mc-home" ]; then fail "a refused home was still created"; else ok "nothing created inside the repository"; fi
alpha_block </dev/null

mc_run mc-kb.sh init --program nobody
expect_rc "an unconfigured program is not found" 3

mkdir -p "$tmp/linkhome/alpha" "$tmp/elsewhere"
ln -s "$tmp/elsewhere" "$tmp/linkhome/alpha/kb"
printf '%s\n' "program_alpha_home: $tmp/linkhome/alpha" >>"$tracked"
mc_run mc-kb.sh init --program alpha
expect_rc "a knowledge base that is a symlink is refused" 1
if [ -z "$(ls -A "$tmp/elsewhere")" ]; then ok "nothing lands where the link points"; else fail "init wrote through a symlinked knowledge base"; fi
mc_run mc-kb.sh index --program alpha
expect_rc "every verb refuses a symlinked knowledge base" 1
alpha_block </dev/null

# ---------------------------------------------------------------------------
# REQ-K1.3: per-duty files follow enablement.
# ---------------------------------------------------------------------------
if [ -d "$kb/alpha" ]; then ok "an armed duty gets its directory"; else fail "no directory for the armed duty"; fi
if [ -e "$kb/beta" ]; then fail "an off duty got a directory"; else ok "an off duty gets none"; fi
sed 's/^program_alpha_duties: .*/program_alpha_duties: [beta-duty]/' "$tracked" >"$tmp/t" && mv "$tmp/t" "$tracked"
mc_run mc-kb.sh init --program alpha
expect_rc "init after disabling a duty" 0
if [ -e "$kb/alpha" ]; then fail "a disabled duty's empty directory was left"; else ok "disabling leaves no directory"; fi
alpha_block </dev/null
mc_run mc-kb.sh init --program alpha
printf 'note\n' >"$kb/alpha/kept.md"
sed 's/^program_alpha_duties: .*/program_alpha_duties: [beta-duty]/' "$tracked" >"$tmp/t" && mv "$tmp/t" "$tracked"
mc_run mc-kb.sh init --program alpha
expect_rc "init keeps a disabled duty's files" 0
expect_err "a non-empty orphan directory is reported" "alpha"
if [ -f "$kb/alpha/kept.md" ]; then ok "a disabled duty's files are never deleted"; else fail "init deleted a duty's files"; fi
alpha_block </dev/null

# ---------------------------------------------------------------------------
# Format fields (D-8): every store carries one; a reader refuses others.
# ---------------------------------------------------------------------------
for f in index.md followups.tsv sources.tsv mechanisms.tsv; do
  case $(head -n 1 "$kb/$f") in
    *"format: 1"*) ok "kb/$f carries its format field" ;;
    *) fail "kb/$f lacks a format field" ;;
  esac
done
cp "$kb/followups.tsv" "$tmp/followups.keep"
tail -n +2 "$tmp/followups.keep" >"$kb/followups.tsv"
mc_run mc-kb.sh followup list --program alpha
expect_rc "a store with no format field is refused" 1
expect_err "the formatless store is named" "followups.tsv"
{
  printf '# format: 9\n'
  tail -n +2 "$tmp/followups.keep"
} >"$kb/followups.tsv"
mc_run mc-kb.sh followup list --program alpha
expect_rc "a store with an unknown format is refused" 1
expect_err "the unknown format is named" "format 9"
cp "$tmp/followups.keep" "$kb/followups.tsv"
cp "$kb/index.md" "$tmp/index.keep"
tail -n +2 "$tmp/index.keep" >"$kb/index.md"
mc_run mc-kb.sh index --program alpha
expect_rc "an index with no format field is refused" 1
expect_err "the index is named" "kb/index.md"
cp "$tmp/index.keep" "$kb/index.md"
printf '%s\n' "- \`kept\`: a line init must keep" >>"$kb/index.md"
mc_run mc-kb.sh init --program alpha
if grep -q 'a line init must keep' "$kb/index.md"; then ok "a second init keeps the stores' content"; else fail "init clobbered the index"; fi
cp "$tmp/index.keep" "$kb/index.md"

# A home whose path carries a space.
cat >>"$tracked" <<EOF
program_alpha_home: $tmp/my home/alpha
EOF
mc_run mc-kb.sh init --program alpha
mc_run mc-kb.sh append decisions --program alpha --subject spaced --act "in a spaced home"
mc_run mc-kb.sh query decisions --program alpha --subject spaced
expect_out "a home with a space in its path is queried" "in a spaced home"
mc_run mc-kb.sh freshness --program alpha
expect_out "a home with a space in its path reports its logs" "log:decisions"
mc_run mc-kb.sh append undo --program alpha --subject spaced --act "spaced undo" -- true
spaced_id=$OUT
mc_run mc-kb.sh revert --program alpha "$spaced_id"
expect_rc "a home with a space in its path reverts" 0
mc_run mc-kb.sh revert --program alpha "$spaced_id"
expect_err "and knows it already did" "already reverted"
alpha_block </dev/null

# ---------------------------------------------------------------------------
# REQ-K1.2, REQ-K1.6: the index within its budget; capped reads.
# ---------------------------------------------------------------------------
printf 'small body\n' >"$kb/alpha/small.md"
mc_run mc-kb.sh index-add --program alpha alpha/small.md "A small note"
expect_rc "an entry is indexed" 0
mc_run mc-kb.sh index --program alpha
expect_rc "the index loads whole" 0
expect_out "the index lists the entry" "alpha/small.md"
mc_run mc-kb.sh index-add --program alpha alpha/small.md "A renamed note"
mc_run mc-kb.sh index --program alpha
expect_out "re-indexing replaces the line" "A renamed note"
expect_no_out "the old line is gone" "A small note"

mc_run mc-kb.sh read --program alpha alpha/small.md
expect_rc "a body under the cap is read" 0
expect_eq "the body is printed" "small body"

awk 'BEGIN { for (i = 0; i < 300; i++) print "line of filler text in a large body" }' >"$kb/alpha/big.md"
mc_run mc-kb.sh index-add --program alpha alpha/big.md "A large note"
printf '%s\n' "mission_control_kb_entry_cap: 4096" >>"$tracked"
mc_run mc-kb.sh read --program alpha alpha/big.md
expect_rc "a read above the cap is refused" 1
expect_err "the refusal carries the offload hint" "offload"
expect_err "the refusal names the cap" "4096"
if [ -z "$OUT" ]; then ok "a refused read prints none of the body"; else fail "a refused read leaked the body"; fi
alpha_block </dev/null

printf 'unindexed\n' >"$kb/alpha/loose.md"
mc_run mc-kb.sh read --program alpha alpha/loose.md
expect_rc "a body that is not indexed is refused" 1
mkdir -p "$tmp/runtime"
printf 'live state\n' >"$tmp/runtime/snapshot.json"
mc_run mc-kb.sh read --program alpha ../../runtime/snapshot.json
expect_rc "a path leaving the knowledge base is refused" 2
ln -s "$tmp/runtime/snapshot.json" "$kb/alpha/linked.md"
mc_run mc-kb.sh index-add --program alpha alpha/linked.md "A link to live state"
expect_rc "indexing a link out of the knowledge base is refused" 1
# shellcheck disable=SC2016 # the backticks are the index line's literal markup
printf '%s\n' '- `alpha/linked.md`: hand-added link' >>"$kb/index.md"
mc_run mc-kb.sh read --program alpha alpha/linked.md
expect_rc "a link out of the knowledge base is never read" 1
expect_err "the refusal names the link" "symlink"
grep -v 'alpha/linked.md' "$kb/index.md" >"$tmp/idx" && cat "$tmp/idx" >"$kb/index.md"
mc_run mc-kb.sh index-add --program alpha followups.tsv "a store"
expect_rc "a store is never indexed as a body" 1
ln -s . "$kb/top"
mc_run mc-kb.sh index-add --program alpha top/followups.tsv "a store through a link"
expect_rc "a store reached through a link to the root is still a store" 1
mc_run mc-kb.sh lock --program alpha "top/locks-$month.log" --holder 1
expect_rc "the locks log reached through a link to the root is still refused" 2
rm -f "$kb/top"
mc_run mc-kb.sh index-add --program alpha INDEX.md "a store in another case"
expect_rc "a store's name in another case is refused too" 1
expect_err "it is refused as a store" "is a store"
printf '# format: 1\n' >"$kb/decisions-2000-03.log"
mc_run mc-kb.sh index-add --program alpha decisions-2000-03.log "a log"
expect_rc "a log segment is never indexed as a body" 1
expect_err "it is refused as a store" "is a store"
rm -f "$kb/decisions-2000-03.log"
mc_run mc-kb.sh read --program alpha -x
expect_rc "a path with a leading dash is refused" 2

printf '%s\n' "mission_control_kb_index_budget: 3" >>"$tracked"
printf 'x\n' >"$kb/alpha/third.md"
printf 'x\n' >"$kb/alpha/fourth.md"
mc_run mc-kb.sh index-add --program alpha alpha/third.md "Third"
expect_rc "an entry within the budget is added" 0
mc_run mc-kb.sh index-add --program alpha alpha/fourth.md "Fourth"
expect_rc "an entry over the budget is refused" 1
expect_err "the overflow names the budget knob" "mission_control_kb_index_budget"
# shellcheck disable=SC2016 # the backticks are the index line's literal markup
printf '%s\n' '- `alpha/fourth.md`: Fourth, hand-added' >>"$kb/index.md"
mc_run mc-kb.sh index --program alpha
expect_rc "an index over its budget reports the overflow" 1
expect_err "the overflow is counted" "1 line"
expect_no_out "only the lines within the budget load" "Fourth"
alpha_block </dev/null

# ---------------------------------------------------------------------------
# REQ-D1.7: a decision and its undo entry round-trip; the reversal runs.
# ---------------------------------------------------------------------------
mc_run mc-kb.sh append decisions --program alpha --subject pr-42 --act "approved the plan" --grounds "operator rule"
expect_rc "a decision is appended" 0
mc_run mc-kb.sh append undo --program alpha --subject pr-42 --act "resolved a thread"
expect_rc "an undo entry with no reversal stated is refused" 2
# shellcheck disable=SC2016 # the reversal's own expansion runs when it does
mc_run mc-kb.sh append undo --program alpha --subject pr-42 --act "resolved a thread" --target thread-7 \
  --duty alpha-duty -- sh -c 'printf "%s" "$2" >"$1"' sh "$tmp/rev file" "50%25 done"
expect_rc "an undo entry with its reversal is appended" 0
undo_id=$OUT
case $undo_id in
  undo-*) ok "the append prints the entry id" ;;
  *) fail "the append printed no entry id: $undo_id" ;;
esac
mc_run mc-kb.sh append undo --program alpha --subject pr-43 --act "set a label" --no-reversal
expect_rc "an undo entry may record that no reversal exists" 0
none_id=$OUT
mc_run mc-kb.sh append undo --program alpha --subject pr-43 --act reverted --target "$none_id" --no-reversal
expect_rc "revert's own acts cannot be appended by hand" 2
mc_run mc-kb.sh append undo --program alpha --subject pr-43 --act x --no-reversal -- true
expect_rc "an entry states one reversal" 2

mc_run mc-kb.sh query decisions --program alpha --subject pr-42
expect_rc "a decision query" 0
expect_out "the decision comes back by subject" "approved the plan"
mc_run mc-kb.sh query undo --program alpha --subject pr-42
expect_out "the undo entry comes back by subject" "resolved a thread"
expect_out "the entry names the acting duty" "${tab}alpha-duty"
expect_no_out "another subject's entry stays out" "set a label"

mc_run mc-kb.sh revert --program alpha "$undo_id"
expect_rc "the reversal runs from the entry" 0
if [ "$(cat "$tmp/rev file" 2>/dev/null)" = "50%25 done" ]; then
  ok "the reversal's words survive the log, a space and a percent sign included"
else
  fail "the reversal did not run with its words: $(cat "$tmp/rev file" 2>/dev/null)"
fi
mc_run mc-kb.sh query undo --program alpha --subject pr-42
logged=$(printf '%s\n' "$OUT" | I=$undo_id awk -F '\t' '$4 == "reverted" && $5 == ENVIRON["I"]')
if [ -n "$logged" ]; then ok "the reversal is itself logged against the entry"; else fail "no reverted entry for $undo_id"; fi
acts=$(printf '%s\n' "$OUT" | I=$undo_id awk -F '\t' '$5 == ENVIRON["I"] { printf "%s,", $4 }')
if [ "$acts" = "reverting,reverted," ]; then ok "a revert logs its start before its outcome"; else fail "the revert's entries read '$acts'"; fi
mc_run mc-kb.sh revert --program alpha "$undo_id"
expect_rc "an entry is reverted once" 1
expect_err "the second revert says why" "already reverted"
mc_run mc-kb.sh revert --program alpha "$none_id"
expect_rc "an entry with no reversal cannot be reverted" 1
expect_err "the refusal says there is no reversal" "no reversal"
mc_run mc-kb.sh revert --program alpha undo-209901-1
expect_rc "an unknown entry is not found" 1

mc_run mc-kb.sh append undo --program alpha --subject pr-47 --act "a failing reversal" -- false
fail_id=$OUT
mc_run mc-kb.sh revert --program alpha "$fail_id"
expect_rc "a failing reversal is refused" 1
mc_run mc-kb.sh query undo --program alpha --subject pr-47
expect_out "the failed attempt is logged" "revert failed"
mc_run mc-kb.sh revert --program alpha "$fail_id"
expect_rc "a failed revert may be retried" 1
mc_run mc-kb.sh query undo --program alpha --subject pr-47
n=$(printf '%s\n' "$OUT" | grep -c "${tab}revert failed${tab}")
if [ "$n" -eq 2 ]; then ok "the retry ran the reversal again"; else fail "$n failed attempts logged (want 2)"; fi
case $ERR in
  *"already"* | *"no outcome"*) fail "a retry after a failure was refused: $ERR" ;;
  *) ok "a retry after a failure runs the reversal again" ;;
esac
mc_run mc-kb.sh append undo --program alpha --subject pr-55 --act "interrupted" -- true
int_id=$OUT
month=$(date -u '+%Y-%m')
printf '%s\n' "undo-${month%-*}${month#*-}-999${tab}2000-01-01T00:00:00Z${tab}pr-55${tab}reverting${tab}$int_id${tab}-${tab}none${tab}-" \
  >>"$kb/undo-$month.log"
mc_run mc-kb.sh revert --program alpha "$int_id"
expect_rc "a revert that logged no outcome is not run again" 1
expect_err "the refusal says the outcome is unknown" "no outcome"
mc_run mc-kb.sh revert --program alpha "$int_id" --outcome reverted --grounds "checked by hand: it ran"
expect_rc "an interrupted revert is settled by stating its outcome" 0
mc_run mc-kb.sh revert --program alpha "$int_id"
expect_err "a settled revert counts as reverted" "already reverted"
mc_run mc-kb.sh revert --program alpha "$int_id" --outcome failed --grounds again
expect_rc "only a revert awaiting an outcome can be settled" 1
mc_run mc-kb.sh revert --program alpha "$int_id" --outcome maybe --grounds x
expect_rc "an outcome is reverted or failed" 2
mc_run mc-kb.sh append undo --program alpha --subject pr-56 --act "an exec option word" -- -l
mc_run mc-kb.sh revert --program alpha "$OUT"
expect_rc "a reversal starting with an option word is a command, never an exec option" 1

mc_run mc-kb.sh append undo --program alpha --subject pr-48 --act "a planwright script reversal" -- mc-program.sh list
mc_run mc-kb.sh revert --program alpha "$OUT"
expect_rc "a bare planwright script name runs from this installation" 0
case $OUT in
  undo-*[!0-9-]* | *"
"*) fail "revert's stdout is not just the logged id: $OUT" ;;
  undo-*) ok "revert prints only the logged id, the reversal's output on stderr" ;;
  *) fail "revert printed no id: $OUT" ;;
esac
mc_run mc-kb.sh append undo --program alpha --subject pr-52 --act "creates a file" -- touch "$tmp/umask-probe"
probe_id=$OUT
(
  umask 022
  mc_run mc-kb.sh revert --program alpha "$probe_id"
)
case $(ls -l "$tmp/umask-probe" 2>/dev/null) in
  -rw-r--r--*) ok "the reversal runs in the caller's umask" ;;
  *) fail "the reversal's file mode: $(ls -l "$tmp/umask-probe" 2>/dev/null)" ;;
esac
mc_run mc-kb.sh append undo --program alpha --subject pr-53 --act "a victim" -- true
victim_id=$OUT
mc_run mc-kb.sh append undo --program alpha --subject pr-53 --act "names an internal function" \
  -- do_append undo pr-53 reverted "$victim_id" x none -
mc_run mc-kb.sh revert --program alpha "$OUT"
expect_rc "a reversal naming one of the script's functions is never run in-process" 1
mc_run mc-kb.sh revert --program alpha "$victim_id"
expect_rc "the victim still reverts" 0
for act in reverting "revert failed"; do
  mc_run mc-kb.sh append undo --program alpha --subject pr-54 --act "$act" --no-reversal
  expect_rc "the act '$act' is reserved to revert" 2
done

mc_run mc-kb.sh append undo --program alpha --subject pr-49 --act "tampered" -- true
tamper_id=$OUT
month=$(date -u '+%Y-%m')
useg="$kb/undo-$month.log"
sed "s|argv:true|argv:touch $tmp/pwned|" "$useg" >"$tmp/seg" && cat "$tmp/seg" >"$useg"
mc_run mc-kb.sh revert --program alpha "$tamper_id"
expect_rc "a reversal from a rewritten segment is refused" 1
if [ -e "$tmp/pwned" ]; then fail "a tampered reversal ran"; else ok "a tampered reversal never runs"; fi
sed "s|argv:touch $tmp/pwned|argv:true|" "$useg" >"$tmp/seg" && cat "$tmp/seg" >"$useg"

mc_run mc-kb.sh append decisions --program alpha --subject "bad${tab}subject" --act x
expect_rc "a subject carrying a tab is refused" 2
mc_run mc-kb.sh append decisions --program alpha --subject pr-1 --act "two
lines"
expect_rc "an act carrying a newline is refused" 2
mc_run mc-kb.sh append decisions --program alpha --subject "Release  Cadence" --act "set weekly"
expect_rc "a free-text subject is taken" 0
mc_run mc-kb.sh query decisions --program alpha --subject "release cadence"
expect_out "a subject matches with case folded and blanks collapsed" "set weekly"
mc_run mc-kb.sh append decisions --program alpha --subject pr-51 --act --program --grounds x
expect_rc "an option value reading --program stays that option's value" 0
mc_run mc-kb.sh query decisions --program alpha --subject pr-51
expect_out "the value landed as the act" "${tab}--program${tab}"
mc_run mc-kb.sh append would-have --program alpha --subject pr-9 --act "would have re-requested review"
expect_rc "a would-have entry without its duty is refused" 2
mc_run mc-kb.sh append would-have --program alpha --subject pr-9 --act x --duty no-such-duty
expect_rc "a duty outside the catalog is refused" 2
mc_run mc-kb.sh append would-have --program alpha --subject pr-9 --act "would have re-requested review" --duty alpha-duty
expect_rc "the shadow would-have log takes entries" 0
mc_run mc-kb.sh query would-have --program alpha --subject pr-9
expect_out "the would-have log is queried by subject" "re-requested review"

# ---------------------------------------------------------------------------
# REQ-K1.5: subject queries across segments; rewrites refused.
# ---------------------------------------------------------------------------
printf '# format: 1\n%s\n%s\n' \
  "decisions-200001-1${tab}2000-01-03T00:00:00Z${tab}pr-42${tab}an old decision${tab}-${tab}-${tab}none${tab}-" \
  "decisions-200001-2${tab}2000-01-04T00:00:00Z${tab}pr-420${tab}a near miss${tab}-${tab}-${tab}none${tab}-" \
  >"$kb/decisions-2000-01.log"
mc_run mc-kb.sh query decisions --program alpha --subject pr-42
expect_out "a query reads the older segment" "an old decision"
expect_out "a query reads the current segment" "approved the plan"
expect_no_out "a query matches the whole subject" "a near miss"
lines=$(printf '%s\n' "$OUT" | grep -c .)
if [ "$lines" -eq 2 ]; then ok "a query returns only the matching lines"; else fail "a query returned $lines lines"; fi
printf '# format: 9\n' >"$kb/decisions-2000-02.log"
mc_run mc-kb.sh query decisions --program alpha --subject pr-42
expect_rc "a segment with an unknown format is refused" 1
expect_err "the segment is named" "decisions-2000-02.log"
rm -f "$kb/decisions-2000-02.log"

month=$(date -u '+%Y-%m')
seg="$kb/decisions-$month.log"
case $(head -n 1 "$kb/.decisions-$month.seal") in
  "# format: 1") ok "a segment's seal carries its format field" ;;
  *) fail "the seal lacks a format field" ;;
esac
sed 's/approved the plan/rewritten history/' "$seg" >"$tmp/seg" && cat "$tmp/seg" >"$seg"
mc_run mc-kb.sh append decisions --program alpha --subject pr-44 --act "after a rewrite"
expect_rc "an append to a rewritten segment is refused" 1
expect_err "the rewritten segment is named" "decisions-$month.log"
sed 's/rewritten history/approved the plan/' "$seg" >"$tmp/seg" && cat "$tmp/seg" >"$seg"
mc_run mc-kb.sh append decisions --program alpha --subject pr-44 --act "after the restore"
expect_rc "the restored segment takes appends again" 0
printf '%s\n' "would-have-${month%-*}${month#*-}-99${tab}2000-01-01T00:00:00Z${tab}pr-9${tab}crashed before its seal${tab}-${tab}-${tab}none${tab}-" \
  >>"$kb/would-have-$month.log"
mc_run mc-kb.sh append would-have --program alpha --subject pr-9 --act "after a crash" --duty alpha-duty
expect_rc "an entry appended before a crash left its seal behind is not a rewrite" 0
mv "$kb/would-have-$month.log" "$tmp/wh.keep"
mc_run mc-kb.sh append would-have --program alpha --subject pr-9 --act "after a deletion" --duty alpha-duty
expect_rc "a deleted segment whose seal remains is refused" 1
mv "$tmp/wh.keep" "$kb/would-have-$month.log"
printf '%s' "would-have-${month%-*}${month#*-}-98${tab}torn" >>"$kb/would-have-$month.log"
mc_run mc-kb.sh append would-have --program alpha --subject pr-torn --act "after a torn line" --duty alpha-duty
expect_rc "a partial line a crash left is dropped, not joined" 0
expect_err "the drop is reported" "partial line"
mc_run mc-kb.sh query would-have --program alpha --subject pr-torn
expect_out "the entry after the torn line is whole" "after a torn line"

# ---------------------------------------------------------------------------
# REQ-F1.10: the follow-up ledger.
# ---------------------------------------------------------------------------
mc_run mc-kb.sh followup add --program alpha --owner operator --text "send the review summary"
expect_rc "a follow-up without a trigger is refused" 2
mc_run mc-kb.sh followup add --program alpha --trigger date:2000-01-01 --text "no owner"
expect_rc "a follow-up without an owner is refused" 2
mc_run mc-kb.sh followup add --program alpha --owner operator --trigger soon --text "bad trigger"
expect_rc "a trigger outside the grammar is refused" 2
mc_run mc-kb.sh followup add --program alpha --owner mission-control --trigger date:2000-01-01 --text "chase the deferral"
expect_rc "a promise becomes a row" 0
f_date=$OUT
mc_run mc-kb.sh followup add --program alpha --owner operator --trigger event:pr-merged --text "announce the release"
f_event=$OUT
mc_run mc-kb.sh followup add --program alpha --owner operator --trigger date:2999-01-01 --text "far away"

mc_run mc-kb.sh followup due --program alpha
expect_out "a passed date trigger is due" "chase the deferral"
expect_no_out "a future date is not due" "far away"
expect_no_out "an event trigger waits for its event" "announce the release"
mc_run mc-kb.sh followup due --program alpha --event pr-merged
expect_out "the event firing makes its row due" "announce the release"

mc_run mc-kb.sh followup close --program alpha "$f_date"
expect_rc "a row closes only with evidence" 2
mc_run mc-kb.sh followup close --program alpha "$f_date" --evidence "PR comment posted"
expect_rc "a row closes with evidence" 0
mc_run mc-kb.sh followup close --program alpha "$f_date" --evidence again
expect_rc "a closed row is not closed twice" 1
mc_run mc-kb.sh followup due --program alpha
expect_no_out "a closed row is no longer due" "chase the deferral"
mc_run mc-kb.sh followup list --program alpha
expect_out "the closed row keeps its evidence" "PR comment posted"
expect_out "open rows stay listed" "$f_event"
row=$(printf '%s\n' "$OUT" | I=$f_event awk -F '\t' '$1 == ENVIRON["I"] { print $3 " " $4 " " $5 }')
if [ "$row" = "operator event:pr-merged open" ]; then ok "a row carries its owner, trigger and state"; else fail "the row reads '$row'"; fi
mc_run mc-kb.sh followup due --program alpha --date 2999-06-01
expect_out "a due date is read against the given day" "far away"
mc_run mc-kb.sh followup close --program alpha f-999 --evidence x
expect_rc "an unknown row is not found" 1

# ---------------------------------------------------------------------------
# REQ-K1.7: the mechanism inventory and the source table's watermark.
# ---------------------------------------------------------------------------
cat >"$core/docs/options-reference.md" <<'EOF'
# Options

| Key | Default | Meaning | Read by |
|---|---|---|---|
| `alpha_knob` | `1` | A knob. Evidence: fixture. | `scripts/x.sh` |
| `beta_knob` | `on` | Another. Evidence: fixture. | `scripts/y.sh` |
EOF
cat >"$core/config/steps.yaml" <<'EOF'
---
steps:
  - id: fixture-step
    kind: command
    target: scripts/fixture-step.sh
EOF
cat >"$tmp/claude/settings.json" <<'EOF'
{
  "hooks": {"PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command", "command": "guard.sh"}]}]},
  "permissions": {"allow": ["Bash(git status)"], "deny": ["Bash(rm -rf /)"]}
}
EOF
mc_run mc-kb.sh inventory-refresh --program alpha
expect_rc "the inventory refreshes" 0
inv="$kb/mechanisms.tsv"
row_of() { grep "^$1${tab}$2${tab}" "$inv"; }
for pair in "knob alpha_knob" "knob beta_knob" "catalog-step fixture-step" "duty alpha-duty" \
  "duty beta-duty" "hook PreToolUse Bash" "permission allow: Bash(git status)" \
  "permission deny: Bash(rm -rf /)"; do
  kind=${pair%% *}
  mech=${pair#* }
  row=$(row_of "$kind" "$mech")
  if [ -n "$row" ] && [ "$(printf '%s\n' "$row" | awk -F '\t' '{ print NF }')" -eq 4 ] \
    && [ -n "$(printf '%s\n' "$row" | cut -f 3)" ] && [ -n "$(printf '%s\n' "$row" | cut -f 4)" ]; then
    ok "the inventory carries $kind $mech with where and source"
  else
    fail "the inventory lacks a full row for $kind $mech"
  fi
done
for kind in routine rule; do
  if grep -q "^$kind$tab" "$inv"; then ok "the inventory carries the $kind kind"; else fail "no $kind row"; fi
done
dups=$(cut -f 1-3 "$inv" | grep -v '^#' | sort | uniq -d)
if [ -z "$dups" ]; then ok "one row per mechanism and place"; else fail "duplicate inventory rows: $dups"; fi
wm1=$(grep "^mechanism-inventory$tab" "$kb/sources.tsv" | cut -f 3)
if [ -n "$wm1" ]; then ok "the refresh moves the source table's watermark"; else fail "no inventory watermark"; fi

mc_run mc-kb.sh source set --program alpha mechanism-inventory --kind living --ref kb/mechanisms.tsv --watermark 1
wm1=1
# shellcheck disable=SC2016 # the backticks are the reference row's literal markup
printf '%s\n' '| `gamma_knob` | `x` | Added later. Evidence: fixture. | `scripts/z.sh` |' >>"$core/docs/options-reference.md"
mc_run mc-kb.sh inventory-refresh --program alpha
if row_of knob gamma_knob >/dev/null; then ok "a mechanism added later appears after the next refresh"; else fail "gamma_knob missing"; fi
wm2=$(grep "^mechanism-inventory$tab" "$kb/sources.tsv" | cut -f 3)
if [ -n "$wm2" ] && [ "$wm2" != "$wm1" ]; then ok "a second refresh moves the watermark again"; else fail "the watermark did not move ($wm1 -> $wm2)"; fi
n=$(grep -c "^mechanism-inventory$tab" "$kb/sources.tsv")
if [ "$n" -eq 1 ]; then ok "the source table keeps one row per source"; else fail "$n inventory rows in the source table"; fi

cp "$inv" "$tmp/inv.keep"
mv "$core/docs/options-reference.md" "$tmp/opts.keep"
mv "$core/config/steps.yaml" "$tmp/steps.keep"
mv "$core/config/duties.yaml" "$tmp/duties.keep"
mv "$tmp/claude/settings.json" "$tmp/settings.keep"
mc_run mc-kb.sh inventory-refresh --program alpha
expect_rc "an inventory with nothing read from the installed surfaces is refused" 1
if cmp -s "$inv" "$tmp/inv.keep"; then ok "the stored inventory is kept"; else fail "the stored inventory was replaced"; fi
mv "$tmp/opts.keep" "$core/docs/options-reference.md"
mv "$tmp/steps.keep" "$core/config/steps.yaml"
mv "$tmp/duties.keep" "$core/config/duties.yaml"
mv "$tmp/settings.keep" "$tmp/claude/settings.json"

# A settings file that fails partway contributes nothing.
cat >"$tmp/claude/settings.local.json" <<'EOF'
{"hooks": {"Stop": [{"matcher": "partial"}]}, "permissions": {"allow": "notalist"}}
EOF
mc_run mc-kb.sh inventory-refresh --program alpha
expect_err "a failing settings file is reported" "does not parse"
if grep -q "partial" "$inv"; then fail "a failing settings file's earlier rows landed"; else ok "a failing settings file contributes no row"; fi
rm -f "$tmp/claude/settings.local.json"
# The rows and their watermark move together or not at all.
printf '%s\n' "mission_control_kb_lock_wait: 1" >>"$tracked"
sleep 60 &
holder_pid=$!
mc_run mc-kb.sh lock --program alpha sources.tsv --holder "$holder_pid"
src_token=$OUT
cp "$inv" "$tmp/inv.before"
# shellcheck disable=SC2016 # the backticks are the reference row's literal markup
printf '%s\n' '| `delta_knob` | `x` | Held back. Evidence: fixture. | `scripts/w.sh` |' >>"$core/docs/options-reference.md"
mc_run mc-kb.sh inventory-refresh --program alpha
expect_rc "a refresh that cannot move the watermark is refused" 1
if cmp -s "$inv" "$tmp/inv.before"; then ok "and leaves the inventory as it was"; else fail "the inventory moved without its watermark"; fi
mc_run mc-kb.sh unlock --program alpha sources.tsv --token "$src_token"
kill "$holder_pid" 2>/dev/null
wait "$holder_pid" 2>/dev/null
holder_pid=''
alpha_block </dev/null

mc_run mc-kb.sh source set --program alpha tickets --kind consumed --ref "https://example.invalid/board" --watermark 120
expect_rc "a consumed source is recorded" 0
if grep -q "^tickets${tab}consumed${tab}120${tab}https://example.invalid/board\$" "$kb/sources.tsv"; then
  ok "the source table carries the row"
else
  fail "the source row is missing or malformed"
fi
mc_run mc-kb.sh source set --program alpha docs --kind living --ref x --watermark 2026-10-26
expect_rc "a living watermark that is not an epoch second is refused" 2
mc_run mc-kb.sh source set --program alpha tickets --kind sideways --ref x
expect_rc "a source kind outside living and consumed is refused" 2

# ---------------------------------------------------------------------------
# REQ-K1.6: freshness is reported for the panel.
# ---------------------------------------------------------------------------
mc_run mc-kb.sh freshness --program alpha
expect_rc "freshness reports" 0
expect_out "freshness covers the index" "index.md${tab}"
expect_out "freshness covers the inventory watermark" "source:mechanism-inventory${tab}"
expect_out "freshness covers the logs" "log:decisions${tab}"
expect_no_out "a consumed source has no age" "source:tickets"
bad=$(printf '%s\n' "$OUT" | awk -F '\t' 'NF != 3 || $2 !~ /^[0-9]+$/ || $3 !~ /^[0-9]+$/')
if [ -z "$bad" ]; then ok "every freshness row is name, epoch and age"; else fail "malformed freshness rows: $bad"; fi

OUT=$(/bin/bash "$repo_root/scripts/mc-kb.sh" --help 2>&1)
RC=$?
expect_rc "--help prints the usage" 0
expect_out "the help names the exit codes" "Exit codes:"
OUT=$(/bin/bash "$repo_root/scripts/mc-kb.sh" help 2>&1)
RC=$?
expect_rc "help is the same" 0
mc_run mc-kb.sh followup add --program alpha --bogus x
expect_rc "a bad follow-up option is a usage error before the store is read" 2

mc_run mc-kb.sh bogus --program alpha
expect_rc "an unknown verb is a usage error" 2

if [ "$failures" -ne 0 ]; then
  echo "test-mc-kb: $failures failure(s)" >&2
  exit 1
fi
echo "test-mc-kb: all passed"
