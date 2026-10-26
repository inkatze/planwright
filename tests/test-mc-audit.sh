#!/bin/bash
# Tests for scripts/mc-audit.sh — the self-audit: a mechanical compare of
# the decisions and undo logs against the active rule set, flagging acts
# against a rule, rules with no act for the configured period and active
# entries sharing a subject, and editing nothing (mission-control REQ-B1.6).
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-mc-audit.sh
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

[ -f "$repo_root/scripts/mc-audit.sh" ] || {
  echo "FAIL: scripts/mc-audit.sh missing" >&2
  exit 1
}

tmp=$(mktemp -d) || exit 1
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
audit() { mc_run mc-audit.sh "$@"; }
rule() { # rule <subject> <text> <date>
  mc_run mc-rules.sh add alpha --text "$2" --subject "$1" --source "the operator, fixture" --date "$3"
  [ "$RC" -eq 0 ] || fail "fixture rule '$1' was not added: $ERR"
}
decide() { mc_run mc-decide.sh decide --program alpha "$@"; }
field() { printf '%s\n' "$1" | cut -f "$2"; }
today=$(date -u '+%Y-%m-%d')

audit run --program alpha
expect_rc "an audit over empty stores runs" 0
expect_eq "it reports no finding" "audit${tab}0 findings"

rule "Ready flips" "never flip a PR ready without the readiness walk" 2026-01-01
rule "Worktree reclaim" "reclaim a merged worker's worktree once idle" "$today"
rule "Pushes" "push only named branches" "$today"
rule "pushes" "never push a protected branch" "$today"
rule "Retired" "an old habit" 2026-01-01
mc_run mc-rules.sh supersede alpha r-5 --withdraw --source "the operator, fixture" --date "$today"

seg_write decisions 2025-12 \
  "decisions-202512-1${tab}2025-12-20T10:00:00Z${tab}ready flips${tab}flipped PR 9${tab}-${tab}settled needs-sign-off -: ci green${tab}none${tab}-"
decide --class needs-sign-off --subject "Ready Flips" --act "flipped PR 12 ready" --grounds "ci green"
flagged=$(field "$OUT" 2)
decide --class hygiene --subject "Worktree reclaim" --act "reclaimed wt-3" --grounds "merged, idle" --rule r-2
mc_run mc-kb.sh append undo --program alpha --subject "Pushes" --act "pushed main" --grounds "fast-forward" --no-reversal
undo_flag=$OUT
mc_run mc-kb.sh append undo --program alpha --subject "Pushes" --act rule-add --target r-3 --grounds "the operator" --no-reversal
mc_run mc-decide.sh note --program alpha --shape correction --subject "Ready flips" --text "walk first"
rules_sum=$(cksum <"$home/rules.yaml")

audit run --program alpha
expect_rc "the audit runs" 0
expect_out "an act on a ruled subject that cites no rule is flagged" "finding${tab}against-rule${tab}r-1${tab}$flagged${tab}ready flips"
expect_no_out "an act before the rule was stated is not flagged" "decisions-202512-1"
expect_no_out "an act citing its rule is not flagged" "${tab}r-2${tab}decisions-"
expect_out "an undo-logged act is compared too" "finding${tab}against-rule${tab}r-3${tab}$undo_flag${tab}pushes"
expect_no_out "the rule store's own maintenance is not an act against it" "${tab}undo-$(date -u '+%Y%m')-2${tab}"
expect_no_out "an operator's noted correction is not an act" "walk first"
expect_out "two active entries sharing a subject are flagged" "finding${tab}shared-subject${tab}r-3,r-4${tab}-${tab}pushes"
expect_no_out "a rule stated inside the period is not idle" "idle-rule${tab}r-2"
expect_no_out "a withdrawn rule is not audited" "${tab}r-5${tab}"

printf '%s\n' "mission_control_audit_idle_after: 1d" >>"$tracked"
seg_write decisions 2026-02 \
  "decisions-202602-1${tab}2026-02-01T10:00:00Z${tab}Ready flips${tab}walked and flipped${tab}-${tab}settled needs-sign-off r-1: walked${tab}none${tab}-"
audit run --program alpha --now "$(iso_epoch 2026-02-10T00:00:00Z)"
expect_out "a rule with no act for the period is idle" "finding${tab}idle-rule${tab}r-1${tab}-${tab}ready flips"
audit run --program alpha --now "$(iso_epoch 2026-02-01T12:00:00Z)"
expect_no_out "a rule acted on inside the period is not idle" "idle-rule${tab}r-1"

if [ "$(cksum <"$home/rules.yaml")" = "$rules_sum" ]; then ok "the audit writes no rule"; else fail "the audit edited the rule store"; fi

audit run --program nobody
expect_rc "an unconfigured program is not found" 3

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all mc-audit tests passed"
