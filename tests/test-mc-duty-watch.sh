#!/bin/bash
# Tests for scripts/mc-duty-watch.sh — the watcher the undo-ledger,
# self-audit and proposals duties arm: a read-only pass that raises an event
# only when its report changed (mission-control REQ-C1.8, REQ-C1.4).
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-mc-duty-watch.sh
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

[ -f "$repo_root/scripts/mc-duty-watch.sh" ] || {
  echo "FAIL: scripts/mc-duty-watch.sh missing" >&2
  exit 1
}

tmp=$(mktemp -d "${TMPDIR:-/tmp}/test-mc-duty-watch.XXXXXX") || exit 1
if [ -z "$tmp" ] || [ ! -d "$tmp" ]; then
  echo "FAIL: mktemp -d produced no usable directory" >&2
  exit 1
fi
trap 'rm -rf "$tmp"' EXIT
tmp=$(cd "$tmp" && pwd -P) || exit 1

# shellcheck source=tests/lib/mission-control-fixture.sh
. "$here/lib/mission-control-fixture.sh"
# shellcheck source=tests/lib/mc-autonomy-fixture.sh
. "$here/lib/mc-autonomy-fixture.sh"

tab=$(printf '\t')

# The three duties, as the shipped catalog arms them, beside the fixture's.
for d in undo-ledger self-audit proposals; do
  printf '%s\n' '  - id: '"$d" '    summary: "x"' '    triggers: []' '    watchers: [scripts/mc-duty-watch.sh@1h/low]' \
    '    wake: none' '    rules: []' '    kinds: []' "    files: $d" '    lifecycle: live' '    never-propose: false' \
    >>"$repo/.claude/catalogs/duties.yaml"
done
mc_run mc-kb.sh init --program alpha
[ "$RC" -eq 0 ] || fail "the fixture knowledge base did not re-initialize: $ERR"

watch() { mc_run mc-duty-watch.sh watch --program alpha --duty "$1"; }
rule() { mc_run mc-rules.sh add alpha --text "$2" --subject "$1" --source "the operator, fixture" --date "$3"; }
today=$(date -u '+%Y-%m-%d')

# ---------------------------------------------------------------------------
# self-audit: a finding raises one event, the same finding raises none, and a
# finding that went away is cleared.
# ---------------------------------------------------------------------------
watch self-audit
expect_rc "REQ-C1.8: a clean audit runs" 0
expect_eq "REQ-C1.8: a clean audit raises nothing" "checked${tab}self-audit${tab}0"

rule "Ready flips" "never flip a PR ready without the readiness walk" 2026-01-01
mc_run mc-decide.sh decide --program alpha --class needs-sign-off --subject "Ready flips" --act "flipped PR 12 ready" --grounds "ci green"
rules_sum=$(cksum <"$home/rules.yaml")
watch self-audit
expect_rc "REQ-C1.8: the audit watcher runs over a finding" 0
expect_out "REQ-C1.8: it counts the finding" "checked${tab}self-audit${tab}1"
expect_out "REQ-C1.8: it raises one self-audit-finding event" "event${tab}self-audit-finding${tab}self-audit${tab}1 finding(s)"
expect_out "REQ-C1.8: the event names the command that shows the finding" "scripts/mc-audit.sh run --program alpha"
watch self-audit
expect_eq "REQ-C1.8: the same finding is not raised again" "checked${tab}self-audit${tab}1"
if [ "$(cksum <"$home/rules.yaml")" = "$rules_sum" ]; then ok "the watcher edits no rule"; else fail "the watcher changed the rule store"; fi

mc_run mc-rules.sh supersede alpha r-1 --withdraw --source "the operator, fixture" --date "$today"
watch self-audit
expect_out "REQ-C1.8: a finding that went away is cleared" "cleared${tab}self-audit"
expect_no_out "REQ-C1.8: clearing raises no event" "event${tab}"

# ---------------------------------------------------------------------------
# proposals: a repeat at the threshold raises one event.
# ---------------------------------------------------------------------------
watch proposals
expect_eq "REQ-C1.8: no repeat raises nothing" "checked${tab}proposals${tab}0"
mc_run mc-decide.sh note --program alpha --shape correction --subject "Pushes" --text "do not push main"
mc_run mc-decide.sh note --program alpha --shape correction --subject "pushes" --text "again: not main"
watch proposals
expect_out "REQ-C1.8: a repeat raises a proposal-repeat event" "event${tab}proposal-repeat${tab}proposals${tab}1 finding(s)"
watch proposals
expect_eq "REQ-C1.8: the same repeat is not raised again" "checked${tab}proposals${tab}1"

# ---------------------------------------------------------------------------
# undo-ledger: a revert that logged `reverting` and no outcome is stuck.
# ---------------------------------------------------------------------------
watch undo-ledger
expect_eq "REQ-C1.8: an empty undo ledger raises nothing" "checked${tab}undo-ledger${tab}0"
month=$(date -u '+%Y-%m')
id="undo-$(date -u '+%Y%m')-1"
seg_write undo "$month" \
  "$id${tab}${today}T10:00:00Z${tab}pushes${tab}pushed a branch${tab}-${tab}fixture${tab}reversal true${tab}-" \
  "undo-$(date -u '+%Y%m')-2${tab}${today}T10:05:00Z${tab}pushes${tab}reverting${tab}$id${tab}-${tab}none${tab}-"
watch undo-ledger
expect_out "REQ-C1.8: a stuck revert raises an undo-revert-stuck event" "event${tab}undo-revert-stuck${tab}undo-ledger${tab}1 finding(s)"
seg_write undo "$month" \
  "$id${tab}${today}T10:00:00Z${tab}pushes${tab}pushed a branch${tab}-${tab}fixture${tab}reversal true${tab}-" \
  "undo-$(date -u '+%Y%m')-2${tab}${today}T10:05:00Z${tab}pushes${tab}reverting${tab}$id${tab}-${tab}none${tab}-" \
  "undo-$(date -u '+%Y%m')-3${tab}${today}T10:06:00Z${tab}pushes${tab}reverted${tab}$id${tab}-${tab}none${tab}-"
watch undo-ledger
expect_out "REQ-C1.8: a settled revert is cleared" "cleared${tab}undo-ledger"

# ---------------------------------------------------------------------------
# The runner's way: no arguments, the program and duty from its environment.
# ---------------------------------------------------------------------------
OUT=$(mc_env env PLANWRIGHT_MC_PROGRAM=alpha PLANWRIGHT_MC_DUTY=proposals /bin/bash "$repo_root/scripts/mc-duty-watch.sh" 2>"$tmp/stderr")
RC=$?
ERR=$(cat "$tmp/stderr")
expect_rc "REQ-C1.8: a run with its environment set works" 0
expect_eq "REQ-C1.8: it reads the same state" "checked${tab}proposals${tab}1"

mc_run mc-duty-watch.sh watch --program alpha --duty alpha-duty
expect_rc "a duty the watcher does not serve is a usage error" 2
mc_run mc-duty-watch.sh watch --program nosuch --duty proposals
expect_rc "a program that is not configured is exit 3" 3
mc_run mc-duty-watch.sh watch --duty proposals
expect_rc "no program is a usage error" 2
mc_run mc-duty-watch.sh bogus
expect_rc "an unknown verb is a usage error" 2

if [ "$failures" -ne 0 ]; then
  echo "test-mc-duty-watch: $failures failure(s)" >&2
  exit 1
fi
echo "test-mc-duty-watch: all passed"
