#!/bin/bash
# Tests for doctrine/human-gates.md and the pointers that retire the rules it
# replaces (human-gates Task 1; REQ-A1.1, REQ-A1.2, REQ-A1.4, REQ-A1.5,
# REQ-B1.1, REQ-B1.9, REQ-D1.6).
#
# Five properties: every rule in the doc's list carries a kind, and each kind
# names what it must (a gate its arm, a policy its knob and default, a
# composition contract its owning skill); bootstrap D-26, REQ-J1.1, and
# REQ-J1.4 carry human-gates pointers that resolve, with one dated changelog
# entry naming all three, and the bundle still validates; approval is the
# approval act, never the flip; the legacy sign-off marker survives in
# doctrine only on gate-wiring's mapping line; and no other doctrine doc
# restates a retired phrasing or states the merge floor without citing the
# doc.
set -u
unset CDPATH

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DOC="$REPO_ROOT/doctrine/human-gates.md"
BOOT="$REPO_ROOT/specs/bootstrap"
HG="$REPO_ROOT/specs/human-gates"

failures=0
ok() { echo "ok: $1"; }
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}
check() {
  if [ "$2" = "$3" ]; then ok "$1"; else fail "$4"; fi
}

if [ ! -f "$DOC" ]; then
  echo "FAIL: doctrine/human-gates.md missing" >&2
  exit 1
fi

# The list is the table directly under the "## The list" heading; its rows are
# `| act | kind | arm and scope, knob and default, or owner |`.
rows=$(awk '
  /^## / { inlist = ($0 == "## The list"); next }
  inlist && /^\|/ { seen = 1; print; next }
  inlist && seen { exit }
' "$DOC" | sed '1,2d')

if [ -z "$rows" ]; then
  fail "the list table has no rows"
else
  ok "the list table has rows"
fi

field() { printf '%s\n' "$1" | awk -F'|' -v n="$2" '{ gsub(/^[ \t]+|[ \t]+$/, "", $n); print $n }'; }

bad_kind=0 bad_policy=0 bad_contract=0 bad_gate=0
seen_gate=0 seen_policy=0 seen_contract=0
while IFS= read -r row; do
  [ -n "$row" ] || continue
  kind=$(field "$row" 3)
  third=$(field "$row" 4)
  case "$kind" in
    "Human gate")
      seen_gate=1
      case "$third" in
        "Approval arm"* | "Irreversible arm"*) ;;
        *) bad_gate=$((bad_gate + 1)) ;;
      esac
      ;;
    Policy)
      seen_policy=1
      case "$third" in
        '`'*'`, default '*) ;;
        *) bad_policy=$((bad_policy + 1)) ;;
      esac
      ;;
    "Composition contract")
      seen_contract=1
      case "$third" in
        *'`/'*) ;;
        *) bad_contract=$((bad_contract + 1)) ;;
      esac
      ;;
    *) bad_kind=$((bad_kind + 1)) ;;
  esac
done <<EOF
$rows
EOF

check "every rule carries a known kind" "$bad_kind" 0 \
  "$bad_kind row(s) carry no kind or an unknown one"
check "every human gate names the arm it meets" "$bad_gate" 0 \
  "$bad_gate human-gate row(s) name no arm"
check "every policy opens with its knob and default" "$bad_policy" 0 \
  "$bad_policy policy row(s) do not open with a knob and its default"
check "every composition contract names its owning skill" "$bad_contract" 0 \
  "$bad_contract composition-contract row(s) name no owning skill"
check "the list carries all three kinds" "$seen_gate$seen_policy$seen_contract" 111 \
  "the list is missing a kind (gate/policy/contract seen: $seen_gate$seen_policy$seen_contract)"

kind_rows() {
  printf '%s\n' "$rows" | awk -F'|' -v want="$1" '{ k = $3; gsub(/^[ \t]+|[ \t]+$/, "", k); if (k == want) print }'
}

# Each knob sits in a Policy row, not merely somewhere in the table.
policy_rows=$(kind_rows Policy)
for knob in ready_flip_policy mark_spec_pr_ready_on_kickoff merge_policy \
  worker_base_merge worker_merge_conflict_policy unpushed_rewrite protected_branches; do
  if printf '%s\n' "$policy_rows" | grep -q "\`$knob\`"; then
    ok "$knob is a policy row"
  else
    fail "$knob is not named in a policy row"
  fi
done

# The gates REQ-A1.2 names are gate rows.
gate_rows=$(kind_rows "Human gate")
for act in "Authorizing a PR merge" "Signing off a Needs-sign-off finding"; do
  if printf '%s\n' "$gate_rows" | grep -q "^| $act |"; then
    ok "\"$act\" is a human gate"
  else
    fail "\"$act\" is not a human-gate row"
  fi
done

# Approval is the approval act; the flip approves nothing.
for f in "$DOC" "$REPO_ROOT/doctrine/gate-wiring.md" "$REPO_ROOT/doctrine/finding-categorization.md"; do
  if tr '\n' ' ' <"$f" | grep -q 'approval act'; then
    ok "$(basename "$f") names the approval act"
  else
    fail "$(basename "$f") does not name the approval act"
  fi
done
for f in "$DOC" "$REPO_ROOT/doctrine/finding-categorization.md"; do
  if tr '\n' ' ' <"$f" | grep -q 'flip approves nothing'; then
    ok "$(basename "$f") states the flip approves nothing"
  else
    fail "$(basename "$f") does not state the flip approves nothing"
  fi
done
if grep -q 'Planwright-Sign-Off-Rejected: PS-<n>' "$REPO_ROOT/doctrine/gate-wiring.md"; then
  ok "gate-wiring states the rejected-trailer rule"
else
  fail "gate-wiring does not state the rejected-trailer rule"
fi

# Bootstrap pointers: D-26 keeps its kickoff-lifecycle line and gains the
# human-gates line beneath it; the two REQs carry theirs; every target
# resolves in the human-gates bundle; one dated changelog entry names all
# three; the Done bundle still validates.
d26=$(awk '/^### D-26:/ { on = 1; next } on && /^### / { exit } on' "$BOOT/design.md")
kl=$(printf '%s\n' "$d26" | grep -n '^\*\*Superseded-by: kickoff-lifecycle D-6\*\*' | cut -d: -f1)
hg=$(printf '%s\n' "$d26" | grep -n '^\*\*Superseded-by: human-gates D-2\*\*' | cut -d: -f1)
dec=$(printf '%s\n' "$d26" | grep -n '^\*\*Decision:\*\*' | cut -d: -f1)
if [ -n "$kl" ] && [ -n "$hg" ] && [ -n "$dec" ] && [ "$kl" -lt "$hg" ] && [ "$hg" -lt "$dec" ]; then
  ok "bootstrap D-26 carries the human-gates pointer beneath the kickoff-lifecycle one"
else
  fail "bootstrap D-26 pointer lines missing or out of order (kl=$kl hg=$hg decision=$dec)"
fi

req_bullet() {
  awk -v id="$1" '
    index($0, "- **" id "**") == 1 { on = 1; print; next }
    on && /^- \*\*REQ-/ { exit }
    on && /^$/ { exit }
    on { print }
  ' "$BOOT/requirements.md"
}
if req_bullet REQ-J1.1 | grep -q '\*\*Superseded-by: REQ-D1.6 (human-gates)\*\*'; then
  ok "bootstrap REQ-J1.1 points at human-gates REQ-D1.6"
else
  fail "bootstrap REQ-J1.1 lacks its human-gates pointer"
fi
if req_bullet REQ-J1.4 | grep -q '\*\*Superseded-by: REQ-F1.1, REQ-F1.2, REQ-C1.1 (human-gates)\*\*'; then
  ok "bootstrap REQ-J1.4 names both of its human-gates replacements"
else
  fail "bootstrap REQ-J1.4 lacks its human-gates pointer"
fi

if grep -q '^### D-2:' "$HG/design.md"; then
  ok "pointer target human-gates D-2 resolves"
else
  fail "pointer target human-gates D-2 does not resolve"
fi
for id in REQ-D1.6 REQ-F1.1 REQ-F1.2 REQ-C1.1; do
  if grep -q "^- \*\*$id\*\*" "$HG/requirements.md"; then
    ok "pointer target human-gates $id resolves"
  else
    fail "pointer target human-gates $id does not resolve"
  fi
done

# One changelog entry per output line, continuation lines joined; ids compared
# as whole tokens so REQ-J1.1 never matches REQ-J1.10.
entries=$(awk '
  /^## Changelog/ { on = 1; next }
  on && /^## / { exit }
  on && /^- [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/ { if (buf != "") print buf; buf = $0; next }
  on && /^  / && buf != "" { buf = buf " " $0; next }
  on && buf != "" { print buf; buf = "" }
  END { if (buf != "") print buf }
' "$BOOT/requirements.md")
named=0
while IFS= read -r entry; do
  case "$entry" in *human-gates*) ;; *) continue ;; esac
  miss=0
  for id in D-26 REQ-J1.1 REQ-J1.4; do
    printf '%s\n' "$entry" | tr -c 'A-Za-z0-9.-' '\n' | sed 's/\.$//' | grep -qx -- "$id" || miss=1
  done
  [ "$miss" -eq 0 ] && named=1
done <<EOF
$entries
EOF
check "one dated bootstrap changelog entry names every human-gates pointer" "$named" 1 \
  "no single dated bootstrap changelog entry names D-26, REQ-J1.1, and REQ-J1.4"

if /bin/bash "$REPO_ROOT/scripts/spec-validate.sh" "$BOOT" >/dev/null 2>&1; then
  ok "specs/bootstrap still validates"
else
  fail "specs/bootstrap no longer validates"
fi

# Retired phrasings: outside human-gates.md, doctrine carries none of them
# except gate-wiring's one mapping line from the legacy marker to the trailer.
# "Act-then-review gate" names the finding gate, not the flip, so it passes.
retired='(^|[^-])review gate|universal gate|never[- ]auto-merge|no auto-merge|never[- ]force-push|never mark (a PR )?ready|two reserved controls|new commits only|history is never rewritten|drafts for the human to flip|autonomous PR-ready marking|never a planwright action|pending-sign-off\]|bootstrap (D-26|REQ-J1\.[14])'
fired=$(printf '%s\n' 'the flip is the review gate' 'never auto-merge' 'x [pending-sign-off]' | grep -c -i -E "$retired")
check "the retired-phrasing screen fires on known-bad lines" "$fired" 3 \
  "the retired-phrasing screen fired on $fired of 3 known-bad lines"
ndocs=$(find "$REPO_ROOT/doctrine" -name '*.md' | wc -l | tr -d ' ')
[ "$ndocs" -gt 1 ] || fail "no doctrine docs found to scan"

# shellcheck disable=SC2016 # an awk program, expanded by awk
is_mapline='$1 ~ /\/doctrine\/gate-wiring\.md$/ && /pending-sign-off\]/ && /Planwright-Sign-Off/'
hits=$(grep -rn -i -E "$retired" --include='*.md' --exclude='human-gates.md' "$REPO_ROOT/doctrine")
mapcount=$(printf '%s\n' "$hits" | awk -F: "$is_mapline" | grep -c .)
others=$(printf '%s\n' "$hits" | grep -v '^$' | awk -F: "!($is_mapline)")
if [ -z "$others" ]; then
  ok "no doctrine doc restates a retired phrasing"
else
  fail "retired phrasings remain in doctrine:
$others"
fi
check "gate-wiring carries exactly one legacy-marker mapping line" "$mapcount" 1 \
  "gate-wiring carries $mapcount legacy-marker mapping lines, expected 1"

# Every doctrine doc that states the merge floor cites the doc that owns it.
for f in "$REPO_ROOT"/doctrine/*.md; do
  case "$f" in */README.md | */human-gates.md) continue ;; esac
  if tr '\n' ' ' <"$f" | grep -q -i 'merge floor'; then
    if grep -q '(human-gates\.md)' "$f"; then
      ok "$(basename "$f") cites human-gates where it states the merge floor"
    else
      fail "$(basename "$f") states the merge floor without citing human-gates"
    fi
  fi
done

if [ "$failures" -ne 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all human-gates doctrine checks passed"
