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
if [ -d "$kb/logs" ]; then ok "init creates the log directory"; else fail "no kb/logs"; fi
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
mc_run mc-kb.sh read --program alpha alpha/linked.md
expect_rc "a link out of the knowledge base is never read" 1

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
mc_run mc-kb.sh append decision --program alpha --subject pr-42 --act "approved the plan" --grounds "operator rule"
expect_rc "a decision is appended" 0
mc_run mc-kb.sh append undo --program alpha --subject pr-42 --act "resolved a thread"
expect_rc "an undo entry with no reversal stated is refused" 2
# shellcheck disable=SC2016 # the reversal's own expansion runs when it does
mc_run mc-kb.sh append undo --program alpha --subject pr-42 --act "resolved a thread" --target thread-7 \
  -- sh -c 'printf reverted >"$1"' sh "$tmp/rev file"
expect_rc "an undo entry with its reversal is appended" 0
undo_id=$OUT
case $undo_id in
  undo-*) ok "the append prints the entry id" ;;
  *) fail "the append printed no entry id: $undo_id" ;;
esac
mc_run mc-kb.sh append undo --program alpha --subject pr-43 --act "set a label" --no-reversal
expect_rc "an undo entry may record that no reversal exists" 0
none_id=$OUT

mc_run mc-kb.sh query decision --program alpha --subject pr-42
expect_rc "a decision query" 0
expect_out "the decision comes back by subject" "approved the plan"
mc_run mc-kb.sh query undo --program alpha --subject pr-42
expect_out "the undo entry comes back by subject" "resolved a thread"
expect_no_out "another subject's entry stays out" "set a label"

mc_run mc-kb.sh revert --program alpha "$undo_id"
expect_rc "the reversal runs from the entry" 0
if [ "$(cat "$tmp/rev file" 2>/dev/null)" = reverted ]; then
  ok "the reversal's arguments survive the log, a space included"
else
  fail "the reversal did not run with its arguments"
fi
mc_run mc-kb.sh query undo --program alpha --subject pr-42
expect_out "the reversal is itself logged" "$undo_id"
mc_run mc-kb.sh revert --program alpha "$undo_id"
expect_rc "an entry is reverted once" 1
mc_run mc-kb.sh revert --program alpha "$none_id"
expect_rc "an entry with no reversal cannot be reverted" 1
mc_run mc-kb.sh revert --program alpha undo-209901-1
expect_rc "an unknown entry is not found" 1

mc_run mc-kb.sh append decision --program alpha --subject "bad${tab}subject" --act x
expect_rc "a subject carrying a tab is refused" 2
mc_run mc-kb.sh append decision --program alpha --subject pr-1 --act "two
lines"
expect_rc "an act carrying a newline is refused" 2
mc_run mc-kb.sh append would-have --program alpha --subject pr-9 --act "would have re-requested review"
expect_rc "the shadow would-have log takes entries" 0

# ---------------------------------------------------------------------------
# REQ-K1.5: subject queries across segments; rewrites refused.
# ---------------------------------------------------------------------------
printf '# format: 1\n%s\n%s\n' \
  "decision-200001-1${tab}2000-01-03T00:00:00Z${tab}pr-42${tab}an old decision${tab}-${tab}-${tab}none" \
  "decision-200001-2${tab}2000-01-04T00:00:00Z${tab}pr-420${tab}a near miss${tab}-${tab}-${tab}none" \
  >"$kb/logs/decision-2000-01.log"
mc_run mc-kb.sh query decision --program alpha --subject pr-42
expect_out "a query reads the older segment" "an old decision"
expect_out "a query reads the current segment" "approved the plan"
expect_no_out "a query matches the subject exactly" "a near miss"
lines=$(printf '%s\n' "$OUT" | grep -c .)
if [ "$lines" -eq 2 ]; then ok "a query returns only the matching lines"; else fail "a query returned $lines lines"; fi

seg="$kb/logs/decision-$month.log"
sed 's/approved the plan/rewritten history/' "$seg" >"$tmp/seg" && cat "$tmp/seg" >"$seg"
mc_run mc-kb.sh append decision --program alpha --subject pr-44 --act "after a rewrite"
expect_rc "an append to a rewritten segment is refused" 1
expect_err "the rewritten segment is named" "decision-$month.log"
sed 's/rewritten history/approved the plan/' "$seg" >"$tmp/seg" && cat "$tmp/seg" >"$seg"
mc_run mc-kb.sh append decision --program alpha --subject pr-44 --act "after the restore"
expect_rc "the restored segment takes appends again" 0

# ---------------------------------------------------------------------------
# REQ-K1.5: one writer per file; a dead holder's lock is released and logged.
# ---------------------------------------------------------------------------
printf '%s\n' "mission_control_kb_lock_wait: 1" >>"$tracked"
sleep 60 &
holder_pid=$!
mc_run mc-kb.sh lock --program alpha "logs/decision-$month.log" --holder "$holder_pid"
expect_rc "a live process claims a file's write lock" 0
token=$OUT
before=$(cat "$seg")
mc_run mc-kb.sh append decision --program alpha --subject pr-45 --act "under a held lock"
expect_rc "an append under a held lock fails once the wait is spent" 1
expect_err "the refusal names the holder's pid" "$holder_pid"
if [ "$(cat "$seg")" = "$before" ]; then ok "the held segment is untouched"; else fail "an append landed under a held lock"; fi
mc_run mc-kb.sh unlock --program alpha "logs/decision-$month.log" --token "$token"
expect_rc "the holder releases its lock by token" 0

mc_run mc-kb.sh lock --program alpha "logs/decision-$month.log" --holder "$holder_pid"
kill "$holder_pid" 2>/dev/null
wait "$holder_pid" 2>/dev/null
dead_pid=$holder_pid
holder_pid=''
mc_run mc-kb.sh append decision --program alpha --subject pr-46 --act "after the holder died"
expect_rc "the next writer releases a dead holder's lock" 0
expect_err "the release is reported" "$dead_pid"
mc_run mc-kb.sh query lock --program alpha --subject "logs/decision-$month.log"
expect_out "the release is logged by the locked file" "$dead_pid"

alpha_block </dev/null
for i in 1 2 3 4 5 6 7 8; do
  (cd "$repo" && env -u CLAUDE_PLUGIN_ROOT -u CLAUDE_PLUGIN_DATA -u PLANWRIGHT_SKILLS_ROOT \
    -u PLANWRIGHT_CONFIG_DEFAULTS -u PLANWRIGHT_REPO_ROOT_CHECKED -u XDG_CONFIG_HOME \
    PLANWRIGHT_ROOT="$core" PLANWRIGHT_REPO_ROOT="$repo" PLANWRIGHT_ADOPTER_OVERLAY="$adopter" \
    PLANWRIGHT_LOCAL_CONFIG="$tmp/absent.yml" CLAUDE_DIR="$tmp/claude" HOME="$fixhome" \
    /bin/bash "$repo_root/scripts/mc-kb.sh" append decision --program alpha \
    --subject concurrent --act "writer $i" >/dev/null 2>&1) &
done
wait
mc_run mc-kb.sh query decision --program alpha --subject concurrent
n=$(printf '%s\n' "$OUT" | grep -c "${tab}concurrent${tab}writer [1-8]${tab}-${tab}-${tab}none\$")
ids=$(printf '%s\n' "$OUT" | cut -f 1 | sort -u | grep -c .)
if [ "$n" -eq 8 ] && [ "$ids" -eq 8 ]; then
  ok "concurrent appends land whole, one line each, never interleaved"
else
  fail "concurrent appends: $n whole lines, $ids distinct ids (want 8 and 8)"
fi

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
    && [ -n "$(printf '%s\n' "$row" | cut -f 4)" ]; then
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

sleep 1
# shellcheck disable=SC2016 # the backticks are the reference row's literal markup
printf '%s\n' '| `gamma_knob` | `x` | Added later. Evidence: fixture. | `scripts/z.sh` |' >>"$core/docs/options-reference.md"
mc_run mc-kb.sh inventory-refresh --program alpha
if row_of knob gamma_knob >/dev/null; then ok "a mechanism added later appears after the next refresh"; else fail "gamma_knob missing"; fi
wm2=$(grep "^mechanism-inventory$tab" "$kb/sources.tsv" | cut -f 3)
if [ -n "$wm2" ] && [ "$wm2" != "$wm1" ]; then ok "a second refresh moves the watermark again"; else fail "the watermark did not move ($wm1 -> $wm2)"; fi
n=$(grep -c "^mechanism-inventory$tab" "$kb/sources.tsv")
if [ "$n" -eq 1 ]; then ok "the source table keeps one row per source"; else fail "$n inventory rows in the source table"; fi

mc_run mc-kb.sh source set --program alpha tickets --kind consumed --ref "https://example.invalid/board"
expect_rc "a consumed source is recorded" 0
mc_run mc-kb.sh source set --program alpha tickets --kind sideways --ref x
expect_rc "a source kind outside living and consumed is refused" 2

# ---------------------------------------------------------------------------
# REQ-K1.6: freshness is reported for the panel.
# ---------------------------------------------------------------------------
mc_run mc-kb.sh freshness --program alpha
expect_rc "freshness reports" 0
expect_out "freshness covers the index" "index.md${tab}"
expect_out "freshness covers the inventory watermark" "source:mechanism-inventory${tab}"
bad=$(printf '%s\n' "$OUT" | awk -F '\t' 'NF != 3 || $2 !~ /^[0-9]+$/ || $3 !~ /^[0-9]+$/')
if [ -z "$bad" ]; then ok "every freshness row is name, epoch and age"; else fail "malformed freshness rows: $bad"; fi

mc_run mc-kb.sh bogus --program alpha
expect_rc "an unknown verb is a usage error" 2

if [ "$failures" -ne 0 ]; then
  echo "test-mc-kb: $failures failure(s)" >&2
  exit 1
fi
echo "test-mc-kb: all passed"
