#!/bin/bash
# Tests for scripts/mc-inbox.sh and scripts/mc-packet.sh — the one status
# form, the item shape, drafts to the clipboard with nothing sent, and the
# prepared packet with the readiness result first (mission-control REQ-F1.3,
# REQ-F1.7, REQ-F1.11, REQ-F1.14; D-19, D-25).
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-mc-inbox.sh
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

tmp=$(mktemp -d) || exit 1
tmp=$(cd "$tmp" && pwd -P) || exit 1
trap 'rm -rf "$tmp"' EXIT

# shellcheck source=tests/lib/mission-control-fixture.sh
. "$here/lib/mission-control-fixture.sh"

tab=$(printf '\t')
reset_mc_fixture
mchome="$tmp/mchome"
cat >"$tracked" <<EOF
mission_control_programs: [alpha]
program_alpha_repositories: [$repo]
program_alpha_spec_root: $repo
program_alpha_home: $mchome
mission_control_clipboard: $tmp/bin/clip
EOF

# ---------------------------------------------------------------------------
# REQ-F1.3: decisions, then landed, then moving, never history.
# ---------------------------------------------------------------------------
printf 'moving\tTask 4 in review\nhistory\tyesterday we did things\nlanded\tTask 2 merged\ndecision\tPick the retry policy\n' >"$tmp/status"
OUT=$(mc_env /bin/bash "$repo_root/scripts/mc-inbox.sh" status <"$tmp/status" 2>"$tmp/stderr")
RC=$?
ERR=$(cat "$tmp/stderr")
expect_rc "status" 0
expect_eq "REQ-F1.3: the one fixed form" "Decisions
- Pick the retry policy

Landed
- Task 2 merged

Moving
- Task 4 in review"
expect_err "history is dropped and said so" "status carries no history"
OUT=$(mc_env /bin/bash "$repo_root/scripts/mc-inbox.sh" status </dev/null 2>/dev/null)
expect_out "an empty section reads none" "Decisions
- none"

# ---------------------------------------------------------------------------
# REQ-F1.7: an item is answerable alone, every field present.
# ---------------------------------------------------------------------------
item_args=(--link https://example.invalid/acme/web/pull/7 --does "Adds invoice export"
  --asked "Merge it now or after the API change" --right "Yes: the walk passed at the head"
  --option "now=ships today, API change rebases" --option "later=waits a day, no rebase"
  --recommend "now" --checked "readiness walk at 1111111, merge order")
mc_run mc-inbox.sh item "${item_args[@]}"
expect_rc "REQ-F1.7: a complete item renders" 0
expect_out "with the full link" "https://example.invalid/acme/web/pull/7"
expect_out "what it does" "What it does: Adds invoice export"
expect_out "each option's effect" "- later: waits a day, no rebase"
expect_out "what was checked" "Checked: readiness walk at 1111111, merge order"
mc_run mc-inbox.sh item --link https://example.invalid/x --does d --asked a --right r --option a=b --option c=d --recommend a
expect_rc "REQ-F1.7: an item without what was checked is refused" 1
expect_err "named" "lacks --checked"
mc_run mc-inbox.sh item --link "#7" --does d --asked a --right r --option a=b --option c=d --recommend a --checked c
expect_rc "a link that is not a full link is refused" 1
mc_run mc-inbox.sh item --link https://example.invalid/x --does d --asked a --right r --option a=b --recommend a --checked c
expect_rc "one option is not a choice" 1

# ---------------------------------------------------------------------------
# REQ-F1.11: a draft lands on the clipboard and nothing is sent.
# ---------------------------------------------------------------------------
mkdir -p "$tmp/bin"
printf '#!/bin/sh\ncat >"%s/clipboard"\n' "$tmp" >"$tmp/bin/clip"
for s in gh curl mail sendmail; do
  printf '#!/bin/sh\nprintf "%%s\\n" "%s $*" >>"%s/sent"\n' "$s" "$tmp" >"$tmp/bin/$s"
done
chmod +x "$tmp"/bin/*
printf 'Hi Sam, the export is ready for a look.\n' >"$tmp/draft"
PATH="$tmp/bin:$PATH" mc_run mc-inbox.sh draft --program alpha --to "Sam (reviewer)" --file "$tmp/draft"
expect_rc "REQ-F1.11: a draft" 0
expect_out "reported on the clipboard" "clipboard${tab}Sam (reviewer)${tab}40"
if cmp -s "$tmp/draft" "$tmp/clipboard"; then ok "REQ-F1.11: the draft lands on the clipboard"; else fail "REQ-F1.11: the clipboard does not hold the draft"; fi
if [ ! -e "$tmp/sent" ]; then ok "REQ-F1.11: nothing is sent"; else fail "REQ-F1.11: something was sent: $(cat "$tmp/sent")"; fi
log="$mchome/kb/inbox/drafts.tsv"
if [ -f "$log" ] && ! grep -q "export is ready" "$log" && grep -q "Sam (reviewer)" "$log"; then
  ok "the draft is logged by recipient and size, never its text"
else
  fail "the drafts log is wrong"
fi
printf 'mission_control_clipboard: clip\n' >>"$tracked"
mc_run mc-inbox.sh draft --program alpha --to Sam --file "$tmp/draft"
expect_rc "a relative clipboard command degrades to the layer below" 0

# ---------------------------------------------------------------------------
# REQ-F1.14: the packet, the readiness result first.
# ---------------------------------------------------------------------------
w="$tmp/w"
git init -q "$w"
gw() { git -C "$w" -c user.name=t -c user.email=t@example.invalid "$@"; }
gw commit -q --allow-empty -m "first change"
h1=$(git -C "$w" rev-parse HEAD)
gw commit -q --allow-empty -m "second change"
h2=$(git -C "$w" rev-parse HEAD)
printf 'ready\t%s\n' "$h2" >"$tmp/readiness"
printf -- '- The export button on the invoices page\n' >"$tmp/look"
printf -- '- Large exports may time out\n' >"$tmp/risks"
printf 'order\t1\tweb\tfeat-a\n' >"$tmp/order"
mc_run mc-packet.sh assemble --program alpha --unit web#7 --readiness "$tmp/readiness" --look "$tmp/look" --repo "$w" --head "$h2" --risks "$tmp/risks" --order "$tmp/order"
expect_rc "REQ-F1.14: a packet assembles from fixtures" 0
sections=$(printf '%s\n' "$OUT" | grep -E '^(Readiness|What to look at|Changed since you last looked|Risks|Order)$' | tr '\n' '|')
if [ "$sections" = "Readiness|What to look at|Changed since you last looked|Risks|Order|" ]; then ok "REQ-F1.14: the sections in order"; else fail "REQ-F1.14: the sections are $sections"; fi
second=$(printf '%s\n' "$OUT" | sed -n 3p)
if [ "$second" = "Readiness" ] && [ "$(printf '%s\n' "$OUT" | sed -n 4p)" = "ready${tab}$h2" ]; then
  ok "REQ-F1.14: the readiness result is first"
else
  fail "REQ-F1.14: the readiness result is not first"
fi
expect_out "a first look says so" "- first look"
mc_run mc-packet.sh look --program alpha --unit web#7 --head "$h1"
expect_rc "a look is recorded" 0
mc_run mc-packet.sh assemble --program alpha --unit web#7 --readiness "$tmp/readiness" --repo "$w" --head "$h2"
expect_out "REQ-F1.14: what changed since the last look" "second change"
expect_no_out "and nothing from before it" "first change"
expect_out "an absent section reads none" "Risks
- none"
mc_run mc-packet.sh look --program alpha --unit web#7 --head "$h2"
mc_run mc-packet.sh assemble --program alpha --unit web#7 --readiness "$tmp/readiness" --repo "$w" --head "$h2"
expect_out "nothing changed at the same head" "- nothing"
printf 'all good, trust me\n' >"$tmp/bad"
mc_run mc-packet.sh assemble --program alpha --unit web#7 --readiness "$tmp/bad"
expect_rc "a packet without a readiness result is refused" 1

if [ "$failures" -ne 0 ]; then
  echo "test-mc-inbox: $failures failure(s)" >&2
  exit 1
fi
echo "test-mc-inbox: all passed"
