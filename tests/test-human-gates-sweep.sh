#!/bin/bash
# Tests for the human-gates prose sweep and its supersede pointers (human-gates
# Task 12; REQ-A1.3, REQ-H1.1, REQ-H1.2, REQ-H1.3, REQ-H1.4).
#
# Properties: every skill invariant section cites doctrine/human-gates.md; the
# purged-identifier seed refuses a reintroduced retired short phrase anywhere
# in the tree, specs/ included; the `ready_flip_policy` commit carries its
# `BREAKING CHANGE:` footer in the merged history; every surveyed record of a
# Done bundle carries its dated pointer with its body unedited, its bundle a
# changelog entry and an `anchor re-review pending` park; and every surveyed
# live bundle has its gated bullet under this bundle's `## Deferred`.
set -u
unset CDPATH

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
SCAN="$REPO_ROOT/scripts/check-purged-identifiers.sh"

failures=0
ok() { echo "ok: $1"; }
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}

# --- skill invariant sections cite the doctrine source (REQ-H1.1, REQ-A1.3) ---
# The skills that carry an invariant section are pinned, so renaming a heading
# cannot drop a skill from the check; a new section must be added here.
expected="execute-task inception orchestrate polish resume spec-walkthrough tower"
found=""
for f in "$REPO_ROOT"/skills/*/SKILL.md; do
  sec=$(awk '/^## .*[Ii]nvariants/ { on = 1; print; next } on && /^## / { exit } on' "$f")
  [ -n "$sec" ] || continue
  skill=$(basename "$(dirname "$f")")
  found="$found $skill"
  if printf '%s\n' "$sec" | grep -q 'doctrine/human-gates\.md'; then
    ok "the $skill invariant section cites doctrine/human-gates.md"
  else
    fail "the $skill invariant section does not cite doctrine/human-gates.md"
  fi
done
# shellcheck disable=SC2086 # word-split on purpose: one skill per line
if [ "$(printf '%s\n' $found | sort | tr '\n' ' ')" = "$(printf '%s\n' $expected | sort | tr '\n' ' ')" ]; then
  ok "the invariant sections found are exactly the pinned set"
else
  fail "invariant sections found in:$found; expected: $expected"
fi

# --- the purge seed refuses a retired short phrase tree-wide (REQ-H1.2) -----
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
# One fixture per seeded phrase, each read as two lines so this file never
# carries the phrase on one line.
n=0
while IFS= read -r w1 && IFS= read -r w2; do
  n=$((n + 1))
  r="$TMP/repo$n"
  mkdir -p "$r/specs/demo"
  git -C "$r" init -q
  printf '# Demo\n\nThe rule: %s %s.\n' "$w1" "$w2" >"$r/specs/demo/requirements.md"
  git -C "$r" add -A
  (cd "$r" && "$SCAN" --seed-file "$REPO_ROOT/config/purged-identifiers.seed" >"$TMP/out" 2>&1)
  rc=$?
  if [ "$rc" -eq 1 ]; then
    ok "the purge seed refuses retired phrase $n, even under specs/"
  else
    fail "the purge seed did not refuse retired phrase $n (exit $rc)"
  fi
  if grep -qi "$w2" "$TMP/out"; then
    fail "the purge scan echoed retired phrase $n"
  else
    ok "the purge scan reports phrase $n's location without the phrase"
  fi
done <<'EOF'
never a
planwright action
never mark
a pr ready
never
mark ready
drafts for
the human to flip
EOF

# --- the BREAKING CHANGE footer on the knob commit (REQ-H1.3) ---------------
if [ "$(git -C "$REPO_ROOT" rev-parse --is-shallow-repository 2>/dev/null)" = false ]; then
  if git -C "$REPO_ROOT" log --format=%B HEAD | grep -q '^BREAKING CHANGE: ready_flip_policy ships as unit-owner'; then
    ok "the merged history carries the ready_flip_policy BREAKING CHANGE footer"
  else
    fail "no commit in the history carries the ready_flip_policy BREAKING CHANGE footer"
  fi
elif git -C "$REPO_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  echo "skip: a shallow clone cannot show the BREAKING CHANGE footer"
else
  echo "skip: not a git checkout, so the history cannot show the BREAKING CHANGE footer"
fi

# --- pointers into Done bundles (REQ-H1.4) -----------------------------------
# bundle kind id replacing-ids body-cksum, the checksum taken over the record
# with its human-gates pointer paragraph removed, before the pointer landed.
body() { # body <file> <req|dec> <id>
  awk -v kind="$2" -v id="$3" '
    kind == "req" && index($0, "- **" id "**") == 1 { on = 1; print; next }
    kind == "req" && on && (/^- \*\*/ || /^$/ || /^## /) { exit }
    kind == "dec" && index($0, "### " id ":") == 1 { on = 1; print; next }
    kind == "dec" && on && /^#/ { exit }
    on && /^ *\*\*Superseded-by: .*human-gates/ && /2026-10-18/ { skip = 1; next }
    skip && kind == "req" && /^  \*\(Cites:/ { skip = 0 }
    skip && kind == "dec" && /^$/ { skip = 0; next }
    skip { next }
    on { print }
  ' "$1"
}
record() { # record <file> <req|dec> <id>: the whole record
  awk -v kind="$2" -v id="$3" '
    kind == "req" && index($0, "- **" id "**") == 1 { on = 1; print; next }
    kind == "req" && on && (/^- \*\*/ || /^$/ || /^## /) { exit }
    kind == "dec" && index($0, "### " id ":") == 1 { on = 1; print; next }
    kind == "dec" && on && /^#/ { exit }
    on { print }
  ' "$1"
}
while read -r b kind id with sum; do
  [ -n "$b" ] || continue
  f="$REPO_ROOT/specs/$b/requirements.md"
  [ "$kind" = dec ] && f="$REPO_ROOT/specs/$b/design.md"
  with=$(printf '%s' "$with" | tr ',' ' ')
  if [ "$kind" = req ]; then
    want="**Superseded-by: $(printf '%s' "$with" | sed 's/ /, /g') (human-gates)** (2026-10-18)"
  else
    want="**Superseded-by: human-gates $(printf '%s' "$with" | sed 's/ /, /g')** (2026-10-18)"
  fi
  if record "$f" "$kind" "$id" | grep -qF -- "$want"; then
    ok "$b $id carries its human-gates pointer"
  else
    fail "$b $id lacks the pointer $want"
  fi
  got=$(body "$f" "$kind" "$id" | cksum | awk '{ print $1 }')
  if [ "$got" = "$sum" ]; then
    ok "$b $id's body is unedited"
  else
    fail "$b $id's body changed ($got, expected $sum)"
  fi
  for t in $with; do
    case "$t" in
      REQ-*) grep -q "^- \*\*$t\*\*" "$REPO_ROOT/specs/human-gates/requirements.md" ;;
      *) grep -q "^### $t:" "$REPO_ROOT/specs/human-gates/design.md" ;;
    esac || fail "$b $id points at human-gates $t, which does not resolve"
  done
done <<'EOF'
kickoff-lifecycle req REQ-D1.3 REQ-C1.1,REQ-C1.6 2659853875
kickoff-lifecycle dec D-6 D-4,D-6 3455788821
autopilot-reflex req REQ-C1.4 REQ-D1.6,REQ-D1.9 3428213118
autopilot-reflex dec D-5 D-6,D-15 2668884748
bootstrap req REQ-C1.3 REQ-B1.1,REQ-C1.1 41155439
bootstrap dec D-5 D-3,D-4 1919611608
bootstrap dec D-44 D-4,D-6 1369961528
bootstrap dec D-45 D-5,D-6 3141464267
orchestration-fleet req REQ-A1.2 REQ-D1.6,REQ-D1.5 1966049157
orchestration-fleet req REQ-B1.5 REQ-D1.6,REQ-F1.2 2792854552
orchestration-fleet dec D-1 D-6 3666193499
orchestration-fleet dec D-3 D-6,D-8 2550374511
output-hygiene req REQ-C1.1 REQ-B1.2 3962808769
output-hygiene req REQ-C1.2 REQ-B1.2 3416305186
output-hygiene req REQ-C1.3 REQ-B1.4 3302499141
output-hygiene req REQ-C1.4 REQ-B1.2,REQ-B1.3 3816469930
output-hygiene dec D-3 D-3,D-6 294329669
EOF

for b in kickoff-lifecycle autopilot-reflex bootstrap orchestration-fleet output-hygiene; do
  if awk '/^## Changelog/ { on = 1; next } on && /^## / { exit } on' "$REPO_ROOT/specs/$b/requirements.md" \
    | grep -q '^- 2026-10-18 — human-gates Task 12 supersede pointers'; then
    ok "$b has a dated changelog entry for its pointers"
  else
    fail "$b has no dated changelog entry for its human-gates pointers"
  fi
  if awk '/^## Awaiting input/ { on = 1; next } on && /^## / { exit } on' "$REPO_ROOT/specs/$b/tasks.md" \
    | grep -q '^- \*\*anchor re-review pending\*\*'; then
    ok "$b is parked for its anchor re-review"
  else
    fail "$b carries pointers but no anchor re-review pending park"
  fi
  if /bin/bash "$REPO_ROOT/scripts/spec-validate.sh" "$REPO_ROOT/specs/$b" >/dev/null 2>&1; then
    ok "specs/$b still validates"
  else
    fail "specs/$b no longer validates"
  fi
done

# --- live bundles wait as gated Deferred bullets (REQ-H1.4, D-17) ------------
deferred=$(awk '/^## Deferred/ { on = 1; next } on && /^## / { exit } on' "$REPO_ROOT/specs/human-gates/tasks.md")
# bundle record replacing-ids, one row per pointer a Deferred bullet carries.
pins='tower-front-door REQ-G1.1 REQ-D1.6
tower-front-door REQ-G1.3 REQ-F1.1,REQ-F1.2
tower-front-door REQ-G1.4 REQ-B1.1,REQ-C1.1
tower-front-door REQ-H1.3 REQ-C1.1
tower-front-door D-5 D-6
fleet-lifecycle-closure REQ-J1.1 REQ-D1.6
fleet-lifecycle-closure REQ-J1.2 REQ-F1.1,REQ-F1.2
operator-dialogue REQ-F1.4 REQ-D1.6
tower-comms REQ-H1.1 REQ-F1.2
tower-placement REQ-G1.1 REQ-C1.5
tower-placement REQ-G1.3 REQ-F1.1,REQ-F1.2
merge-currency-guard REQ-B1.4 REQ-C1.1,REQ-C1.5
merge-currency-guard D-9 D-4
test-throughput D-5 D-4,D-6
test-throughput D-15 D-4
custom-steps D-2 D-4
fleet-messaging REQ-G1.3 REQ-D1.6
guard-coverage REQ-A1.2 REQ-F1.1
concurrent-orchestrator-coordination REQ-B1.2 REQ-F1.1,REQ-F1.2
concurrent-orchestrator-coordination REQ-D1.3 REQ-C1.1,REQ-D1.6'
for b in tower-front-door fleet-lifecycle-closure operator-dialogue tower-comms tower-placement \
  merge-currency-guard test-throughput custom-steps fleet-messaging \
  guard-coverage concurrent-orchestrator-coordination; do
  # A v2 bundle that derives Done admits no anchor park, so its pointers wait
  # for its reopen cycle instead of the bundle's Done.
  case "$b" in
    guard-coverage | concurrent-orchestrator-coordination) gate="the reopen cycle of $b" ;;
    *) gate="GATE(when: spec $b done)." ;;
  esac
  bullet=$(printf '%s\n' "$deferred" | awk -v h="- **Supersede pointers into $b.**" '
    index($0, h) == 1 { on = 1; print; next }
    on && /^- / { exit }
    on { print }' | tr '\n' ' ' | tr -s ' ')
  if [ -n "$bullet" ] && printf '%s\n' "$bullet" | grep -qF "**Gate:** $gate"; then
    ok "the pointers into $b wait as a gated Deferred bullet"
  else
    fail "no gated Deferred bullet carries the pointers into $b"
  fi
  for pair in $(printf '%s\n' "$pins" | awk -v b="$b" '$1 == b { print $2 "=" $3 }'); do
    rec=${pair%%=*} with=$(printf '%s' "${pair#*=}" | sed 's/,/, /g')
    case "$rec" in
      REQ-*) want="**Superseded-by: $with (human-gates)** (<date>)\` on $rec" ;;
      *) want="**Superseded-by: human-gates $with** (<date>)\` on $rec" ;;
    esac
    if printf '%s\n' "$bullet" | grep -qF -- "$want"; then
      ok "the $b bullet names the pointer on $rec"
    else
      fail "the $b bullet does not name $want"
    fi
  done
  if grep -q '2026-10-18) — human-gates\|(human-gates)\*\* (2026-10-18)\|human-gates D-[0-9]*\*\* (2026-10-18)' \
    "$REPO_ROOT/specs/$b/requirements.md" "$REPO_ROOT/specs/$b/design.md"; then
    fail "a sweep pointer landed in live bundle $b"
  else
    ok "no sweep pointer landed in live bundle $b"
  fi
done

if [ "$failures" -ne 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all human-gates sweep checks passed"
