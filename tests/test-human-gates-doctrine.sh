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
  worker_base_merge worker_merge_conflict_policy unpushed_rewrite protected_branches \
  ready_guard_behind_base; do
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
if tr '\n' ' ' <"$REPO_ROOT/doctrine/gate-wiring.md" | grep -q 'never by the  *draft→ready  *flip'; then
  ok "gate-wiring states the checklist is never approved by the flip"
else
  fail "gate-wiring does not state the checklist is never approved by the flip"
fi
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

# The pointed records' bodies are unedited: their text up to the pointer (or,
# for D-26, from the Decision line on) matches the checksum taken before the
# pointers landed.
body_sum() { cksum | awk '{ print $1 }'; }
req_body() {
  awk -v id="$1" '
    index($0, "- **" id "**") == 1 { on = 1 }
    on && /\*\*Superseded-by:|Cites/ { exit }
    on { print }
  ' "$BOOT/requirements.md"
}
check "bootstrap REQ-J1.1's body is unedited" "$(req_body REQ-J1.1 | body_sum)" 275188903 \
  "bootstrap REQ-J1.1's body changed"
check "bootstrap REQ-J1.4's body is unedited" "$(req_body REQ-J1.4 | body_sum)" 29303271 \
  "bootstrap REQ-J1.4's body changed"
d26body=$(printf '%s\n' "$d26" | awk '/^\*\*Decision:\*\*/ { d = 1 } d' | body_sum)
check "bootstrap D-26's body is unedited" "$d26body" 3015923973 \
  "bootstrap D-26's body changed"

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

# Retired phrasings: scripts/check-retired-phrasings.sh owns the screen
# (tests/test-check-retired-phrasings.sh); here it runs over the real tree, and
# gate-wiring keeps its one mapping line from the legacy marker to the trailer.
if /bin/sh "$REPO_ROOT/scripts/check-retired-phrasings.sh" >/dev/null 2>&1; then
  ok "no doctrine doc, skill, or doc restates a retired phrasing"
else
  fail "retired phrasings remain: run scripts/check-retired-phrasings.sh"
fi

maplines=$(grep -n 'pending-sign-off\]' "$REPO_ROOT/doctrine/gate-wiring.md" | grep 'Planwright-Sign-Off')
mapcount=$(printf '%s\n' "$maplines" | grep -c .)
check "gate-wiring carries exactly one legacy-marker mapping line" "$mapcount" 1 \
  "gate-wiring carries $mapcount legacy-marker mapping lines, expected 1"
# The mapping line and the doc's README row name the id a legacy commit
# renders under (REQ-B1.10).
legacy_named=$(printf '%s\n' "$maplines" | grep -c 'PS-legacy-<sha7>' || true)
check "the legacy-marker mapping line names PS-legacy-<sha7>" "$legacy_named" 1 \
  "the legacy-marker mapping line does not name PS-legacy-<sha7>"
if grep '^| \[gate-wiring\.md\]' "$REPO_ROOT/doctrine/README.md" | grep -q 'PS-legacy-<sha7>'; then
  ok "the gate-wiring README row names PS-legacy-<sha7>"
else
  fail "the gate-wiring README row does not name PS-legacy-<sha7>"
fi

# floor_citations <root> <citation-ere>: every .md under <root> (its README and
# human-gates.md aside) that states the merge floor or the merge policy also
# carries the citation, in the form that root uses. Prints one ok/FAIL line per
# floor-stating doc, then the count of such docs on the last line.
floor_citations() {
  local root=$1 cite=$2 f n=0
  for f in "$root"/*.md; do
    [ -f "$f" ] || continue
    case "$f" in */README.md | */human-gates.md) continue ;; esac
    if tr '\n' ' ' <"$f" | grep -q -i -E 'merge floor|merge policy|no agent merges'; then
      n=$((n + 1))
      if grep -q -E "$cite" "$f"; then
        echo "ok: $(basename "$f") cites human-gates where it states the merge floor"
      else
        echo "FAIL: $(basename "$f") states the merge floor without citing human-gates"
      fi
    fi
  done
  echo "$n"
}
run_floor_citations() {
  local out
  out=$(floor_citations "$1" "$2")
  printf '%s\n' "$out" | sed '$d' | while IFS= read -r line; do
    case "$line" in ok:*) echo "$line" ;; *) echo "$line" >&2 ;; esac
  done
  floor_fails=$((floor_fails + $(printf '%s\n' "$out" | sed '$d' | grep -c '^FAIL:')))
  floor_docs=$((floor_docs + $(printf '%s\n' "$out" | tail -n 1)))
}

floor_fails=0 floor_docs=0
run_floor_citations "$REPO_ROOT/doctrine" '\(human-gates\.md'
run_floor_citations "$REPO_ROOT/docs" 'doctrine/human-gates\.md'
failures=$((failures + floor_fails))
[ "$floor_docs" -gt 0 ] || fail "no doctrine doc or doc states the merge floor, so the citation check ran on nothing"

# The check refuses a docs/ fixture stating the floor without the citation,
# and accepts it once cited.
fx=$(mktemp -d)
printf '# Fixture\n\nNo agent merges outside a policy the human configured.\n' >"$fx/floor.md"
fx_out=$(floor_citations "$fx" 'doctrine/human-gates\.md')
if printf '%s\n' "$fx_out" | grep -q '^FAIL: floor.md states the merge floor'; then
  ok "the floor-citation check fails a docs/ fixture stating the floor uncited"
else
  fail "the floor-citation check passed a docs/ fixture stating the floor uncited"
fi
printf 'See [the floor](../doctrine/human-gates.md#the-floor).\n' >>"$fx/floor.md"
if floor_citations "$fx" 'doctrine/human-gates\.md' | grep -q '^FAIL:'; then
  fail "the floor-citation check refused a cited docs/ fixture"
else
  ok "the floor-citation check accepts the cited docs/ fixture"
fi
rm -rf "$fx"

if [ "$failures" -ne 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all human-gates doctrine checks passed"
