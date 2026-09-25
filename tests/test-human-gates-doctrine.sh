#!/bin/bash
# Tests for doctrine/human-gates.md and the pointers that retire the rules it
# replaces (human-gates Task 1; REQ-A1.2, REQ-A1.4, REQ-A1.5, REQ-B1.9,
# REQ-D1.6).
#
# Four properties: every rule in the doc's list carries a kind, and each kind
# names what it must (a policy its knob and default, a composition contract its
# owning skill); bootstrap D-26, REQ-J1.1, and REQ-J1.4 carry their human-gates
# pointers with a dated changelog entry and the bundle still validates; the
# legacy sign-off marker survives in doctrine only on gate-wiring's mapping
# line; and no other doctrine doc restates a retired phrasing.
set -u
unset CDPATH

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DOC="$REPO_ROOT/doctrine/human-gates.md"
BOOT="$REPO_ROOT/specs/bootstrap"

failures=0
ok() { echo "ok: $1"; }
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}

if [ ! -f "$DOC" ]; then
  echo "FAIL: doctrine/human-gates.md missing" >&2
  exit 1
fi

# The list is the first table under the "## The list" heading; its rows are
# `| act | kind | knob and default, or owner |`.
rows=$(awk '
  /^## / { inlist = ($0 == "## The list") ; next }
  inlist && /^\|/ { print }
' "$DOC" | sed '1,2d')

if [ -z "$rows" ]; then
  fail "the list table has no rows"
else
  ok "the list table has rows"
fi

bad_kind=0 bad_policy=0 bad_contract=0 bad_gate=0
seen_gate=0 seen_policy=0 seen_contract=0
while IFS= read -r row; do
  [ -n "$row" ] || continue
  kind=$(printf '%s\n' "$row" | awk -F'|' '{ gsub(/^[ \t]+|[ \t]+$/, "", $3); print $3 }')
  third=$(printf '%s\n' "$row" | awk -F'|' '{ gsub(/^[ \t]+|[ \t]+$/, "", $4); print $4 }')
  case "$kind" in
    "Human gate")
      seen_gate=1
      [ -n "$third" ] || bad_gate=$((bad_gate + 1))
      ;;
    Policy)
      seen_policy=1
      case "$third" in
        *'`'*'`'*default*) ;;
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

check() {
  if [ "$2" = "$3" ]; then ok "$1"; else fail "$4"; fi
}
check "every rule carries a known kind" "$bad_kind" 0 \
  "$bad_kind row(s) carry no kind or an unknown one"
check "every policy names a knob and its default" "$bad_policy" 0 \
  "$bad_policy policy row(s) name no knob or no default"
check "every composition contract names its owning skill" "$bad_contract" 0 \
  "$bad_contract composition-contract row(s) name no owning skill"
check "every human gate states its scope" "$bad_gate" 0 \
  "$bad_gate human-gate row(s) with an empty third column"
check "the list carries all three kinds" "$seen_gate$seen_policy$seen_contract" 111 \
  "the list is missing a kind (gate/policy/contract seen: $seen_gate$seen_policy$seen_contract)"

for knob in ready_flip_policy merge_policy worker_base_merge unpushed_rewrite mark_spec_pr_ready_on_kickoff; do
  if printf '%s\n' "$rows" | grep -q "\`$knob"; then
    ok "the list names $knob"
  else
    fail "the list does not name $knob"
  fi
done

# Bootstrap pointers: D-26 keeps its kickoff-lifecycle line and gains the
# human-gates line beneath it; the two REQs carry theirs; one dated changelog
# entry names all three; the Done bundle still validates.
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
j14=$(req_bullet REQ-J1.4)
if printf '%s\n' "$j14" | grep -q '\*\*Superseded-by: REQ-F1.1, REQ-F1.2, REQ-C1.1 (human-gates)\*\*'; then
  ok "bootstrap REQ-J1.4 names both of its human-gates replacements"
else
  fail "bootstrap REQ-J1.4 lacks its human-gates pointer"
fi

entry=$(awk '
  /^## Changelog/ { on = 1; next }
  on && /^## / { exit }
  on && /^- [0-9]{4}-[0-9]{2}-[0-9]{2}/ { if (buf ~ /human-gates/) print buf; buf = $0; next }
  on && /^  / { buf = buf " " $0; next }
  on && buf != "" { if (buf ~ /human-gates/) print buf; buf = "" }
  END { if (buf ~ /human-gates/) print buf }
' "$BOOT/requirements.md")
missing=""
for id in D-26 REQ-J1.1 REQ-J1.4; do
  printf '%s\n' "$entry" | grep -q -- "$id" || missing="$missing $id"
done
if [ -n "$entry" ] && [ -z "$missing" ]; then
  ok "a dated bootstrap changelog entry names every human-gates pointer"
else
  fail "bootstrap changelog entry missing or incomplete (missing:${missing:- the entry})"
fi

if /bin/bash "$REPO_ROOT/scripts/spec-validate.sh" "$BOOT" >/dev/null 2>&1; then
  ok "specs/bootstrap still validates"
else
  fail "specs/bootstrap no longer validates"
fi

# Retired phrasings: outside human-gates.md, doctrine carries none of them
# except gate-wiring's one mapping line from the legacy marker to the trailer.
# "Act-then-review gate" names the finding gate, not the flip, so it passes.
retired='(^|[^-])review gate|never[- ]auto-merge|no auto-merge|never mark (a PR )?ready|two reserved controls|new commits only|history is never rewritten|drafts for the human to flip|autonomous PR-ready marking|pending-sign-off\]|bootstrap (D-26|REQ-J1\.[14])'
hits=$(grep -rn -i -E "$retired" "$REPO_ROOT/doctrine" --include='*.md' \
  | grep -v "^$REPO_ROOT/doctrine/human-gates.md:")
nonmap=$(printf '%s\n' "$hits" | grep -v '^$' | grep -v 'Planwright-Sign-Off')
maplines=$(printf '%s\n' "$hits" | grep -c 'gate-wiring.md:.*pending-sign-off\].*Planwright-Sign-Off')
if [ -z "$nonmap" ]; then
  ok "no doctrine doc restates a retired phrasing"
else
  fail "retired phrasings remain in doctrine:
$nonmap"
fi
if [ "$maplines" -eq 1 ]; then
  ok "gate-wiring carries exactly one legacy-marker mapping line"
else
  fail "gate-wiring carries $maplines legacy-marker mapping lines, expected 1"
fi

if [ "$failures" -ne 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all human-gates doctrine checks passed"
