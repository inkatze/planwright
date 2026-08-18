#!/bin/bash
# Tests for the inception doctrine extensions (inception Task 3; REQ-I1.2,
# REQ-I1.3, REQ-I1.4, REQ-I1.5; D-1, D-17).
#
# Task 3 lands four things: the non-engineering decision-domains additions
# (plus the existing-seam-reuse domain), the artifact-class lens-selection rule,
# the evidence-quality doctrine, and the storage-classes rule. The task's
# `Done when:` conditions are what this file pins:
#
#   - each doc resolves via the rule-doc chain (scripts/resolve-rule-doc.sh);
#   - the seam-reuse domain names the core seams;
#   - the lens-selection rule states when code lenses do not apply.
#
# REQ-I1.2 carries the only [test]-marked arm in test-spec.md (the domains
# resolve through resolve-catalog, and an overlay fixture with a company
# discipline merges); the REQ-I1.3/I1.4/I1.5 arms are [design-level], and the
# structural assertions here are the cheap mechanical floor under that review —
# they pin that each doc exists, resolves, and carries the normative vocabulary
# the format doc and the gate already cite, not that its prose is good.
#
# Plain bash 3.2, inline asserts (sibling convention).
set -u
unset CDPATH
LC_ALL=C
export LC_ALL

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CATALOG="$REPO_ROOT/scripts/resolve-catalog.sh"
RULEDOC="$REPO_ROOT/scripts/resolve-rule-doc.sh"

failures=0
assert() {
  # assert <description> <expected-exit> <actual-exit>
  if [ "$2" -eq "$3" ]; then
    echo "ok: $1"
  else
    echo "FAIL: $1 (expected exit $2, got $3)" >&2
    failures=$((failures + 1))
  fi
}
assert_eq() {
  if [ "$2" = "$3" ]; then
    echo "ok: $1"
  else
    echo "FAIL: $1 (expected '$2', got '$3')" >&2
    failures=$((failures + 1))
  fi
}
assert_contains() {
  # assert_contains <description> <needle> <haystack>
  case "$3" in
    *"$2"*) echo "ok: $1" ;;
    *)
      echo "FAIL: $1 (expected to find '$2' in output)" >&2
      failures=$((failures + 1))
      ;;
  esac
}

for script in "$CATALOG" "$RULEDOC"; do
  if [ ! -f "$script" ]; then
    echo "FAIL: script missing at $script" >&2
    exit 1
  fi
done

tmp="$(cd "$(mktemp -d)" && pwd -P)" || exit 1
trap 'rm -rf "$tmp"' EXIT

# A clean base env: strip every overlay-affecting variable so each case sets
# only the layer roots it exercises.
base() {
  env -u PLANWRIGHT_ROOT -u CLAUDE_PLUGIN_ROOT -u CLAUDE_DIR \
    -u PLANWRIGHT_ADOPTER_OVERLAY -u CLAUDE_PLUGIN_DATA \
    -u PLANWRIGHT_REPO_ROOT -u HOME "$@"
}

# The eight domains inception adds to the eleven-domain seed (REQ-I1.2).
INCEPTION_DOMAINS="product-strategy packaging-pricing knowledge-engineering
org-design ip-posture llm-output-quality human-comprehension
existing-seam-reuse"

# ---------------------------------------------------------------------------
# 1. REQ-I1.2 — the added domains resolve through resolve-catalog off the real
#    core seed, and the pre-existing eleven survive (append, not replace).
# ---------------------------------------------------------------------------
sb="$tmp/core"
mkdir -p "$sb/repo"
out="$(base PLANWRIGHT_ROOT="$REPO_ROOT" PLANWRIGHT_REPO_ROOT="$sb/repo" \
  /bin/bash "$CATALOG" decision-domains 2>/dev/null)"
assert "core seed: exit 0" 0 $?
for id in $INCEPTION_DOMAINS; do
  assert_contains "core seed: $id present" "id: $id" "$out"
done
for id in data-storage caching queues-async api-surface auth secrets-config \
  concurrency observability deploy-migration dependency-adoption \
  versioning-scheme; do
  assert_contains "core seed: pre-existing $id survives" "id: $id" "$out"
done

# ---------------------------------------------------------------------------
# 2. REQ-I1.2 — an overlay fixture carrying a company discipline merges onto
#    the extended seed: the company domain appears, the inception domains
#    survive, and --explain attributes each to its layer.
# ---------------------------------------------------------------------------
sb="$tmp/overlay"
mkdir -p "$sb/adopter/catalogs" "$sb/repo"
cat >"$sb/adopter/catalogs/decision-domains.yaml" <<'YAML'
domains:
  - id: clinical-safety-review
    trigger: "A change touching patient-facing clinical guidance or dosing content"
    considerations: "Named clinical owner, regulatory class, review evidence, recall path"
    disposition: "Always escalated to the clinical safety owner; never auto-defaulted"
YAML
out="$(base PLANWRIGHT_ROOT="$REPO_ROOT" PLANWRIGHT_ADOPTER_OVERLAY="$sb/adopter" \
  PLANWRIGHT_REPO_ROOT="$sb/repo" /bin/bash "$CATALOG" decision-domains 2>/dev/null)"
assert "overlay merge: exit 0" 0 $?
assert_contains "overlay merge: company discipline domain added" \
  "id: clinical-safety-review" "$out"
assert_contains "overlay merge: inception domain survives" \
  "id: product-strategy" "$out"
assert_contains "overlay merge: seed domain survives" "id: auth" "$out"

exp="$(base PLANWRIGHT_ROOT="$REPO_ROOT" PLANWRIGHT_ADOPTER_OVERLAY="$sb/adopter" \
  PLANWRIGHT_REPO_ROOT="$sb/repo" /bin/bash "$CATALOG" decision-domains --explain \
  2>/dev/null)"
assert_contains "overlay merge: --explain attributes the company domain" \
  "clinical-safety-review	adopter" "$exp"
assert_contains "overlay merge: --explain attributes an inception domain to core" \
  "existing-seam-reuse	core" "$exp"

# ---------------------------------------------------------------------------
# 3. REQ-I1.2 / task Done-when — the seam-reuse domain names the core seams.
#    The prose entry is the normative home, so the seam names are asserted
#    there; the machine view only has to carry the id and the three fields.
# ---------------------------------------------------------------------------
domains_doc="$(base PLANWRIGHT_ROOT="$REPO_ROOT" /bin/bash "$RULEDOC" decision-domains)"
assert "decision-domains doc resolves" 0 $?
seam_entry="$(awk '/^### .*[Ss]eam[ -]reuse/{f=1} f&&/^### /&&!/[Ss]eam[ -]reuse/{exit} f' \
  "$domains_doc")"
for seam in "overlay" "config" "catalog" "rule-doc" "backend" "notification" \
  "accumulator"; do
  assert_contains "seam-reuse entry names the $seam seam" "$seam" "$seam_entry"
done

# ---------------------------------------------------------------------------
# 4. Task Done-when — each doc this task lands resolves via the rule-doc chain.
# ---------------------------------------------------------------------------
for doc in artifact-lenses evidence-quality storage-classes; do
  path="$(base PLANWRIGHT_ROOT="$REPO_ROOT" /bin/bash "$RULEDOC" "$doc" 2>/dev/null)"
  assert "rule-doc chain resolves $doc" 0 $?
  assert_eq "rule-doc chain resolves $doc to the core doctrine" \
    "$REPO_ROOT/doctrine/$doc.md" "$path"
done

# ---------------------------------------------------------------------------
# 5. REQ-I1.3 — the lens-selection rule states artifact-class selection and
#    when code lenses do not apply; the rigor doctrine cites it.
# ---------------------------------------------------------------------------
lenses="$(cat "$REPO_ROOT/doctrine/artifact-lenses.md" 2>/dev/null)"
assert_contains "artifact-lenses: selection is by artifact class" \
  "artifact class" "$lenses"
assert_contains "artifact-lenses: states when code lenses do not apply" \
  "do not apply" "$lenses"
for class in "code" "spec" "inception" "human-facing"; do
  assert_contains "artifact-lenses: names the $class artifact class" "$class" "$lenses"
done
assert_contains "discovery-rigor cites the lens-selection rule" \
  "artifact-lenses.md" "$(cat "$REPO_ROOT/doctrine/discovery-rigor.md")"
assert_contains "validation-rigor cites the lens-selection rule" \
  "artifact-lenses.md" "$(cat "$REPO_ROOT/doctrine/validation-rigor.md")"

# ---------------------------------------------------------------------------
# 6. REQ-I1.4 — the evidence-quality doctrine carries the falsifiability
#    skeleton, fail-condition thresholds, the commitment-weighted ladder in
#    order, and the synthetic-grade exclusion from a desirability Graduate.
# ---------------------------------------------------------------------------
evidence="$(cat "$REPO_ROOT/doctrine/evidence-quality.md" 2>/dev/null)"
for keyword in "believe" "verify" "measure" "right if"; do
  assert_contains "evidence-quality: falsifiability skeleton names '$keyword'" \
    "$keyword" "$evidence"
done
assert_contains "evidence-quality: thresholds are expressible as fail conditions" \
  "fail condition" "$evidence"
assert_contains "evidence-quality: the ladder is ordered weakest to strongest" \
  "\`synthetic\` < \`opinion\` < \`stated-intent\` < \`costly-signal\` < \`behavior\`" \
  "$evidence"
assert_contains "evidence-quality: desirability is value plus usability risk" \
  "usability" "$evidence"
assert_contains "evidence-quality: synthetic is excluded from a Graduate threshold" \
  "Graduate" "$evidence"

# ---------------------------------------------------------------------------
# 7. REQ-I1.5 — the storage-classes rule names the three classes and assigns
#    each a canonical home.
# ---------------------------------------------------------------------------
storage="$(cat "$REPO_ROOT/doctrine/storage-classes.md" 2>/dev/null)"
for class in "framework config" "framework runtime state" "user work products"; do
  assert_contains "storage-classes: names the '$class' class" "$class" "$storage"
done
assert_contains "storage-classes: assigns the runtime-state home" \
  "CLAUDE_PLUGIN_DATA" "$storage"
assert_contains "storage-classes: assigns the framework-config home" \
  "config/defaults.yml" "$storage"

# ---------------------------------------------------------------------------
# 8. Every doc this task lands is indexed in the doctrine README, so the
#    resolution convention and the link-check both reach it.
# ---------------------------------------------------------------------------
readme="$(cat "$REPO_ROOT/doctrine/README.md")"
for doc in artifact-lenses evidence-quality storage-classes; do
  assert_contains "doctrine README indexes $doc" "($doc.md)" "$readme"
done

if [ "$failures" -ne 0 ]; then
  echo "test-inception-doctrine: $failures assertion(s) failed" >&2
  exit 1
fi
echo "test-inception-doctrine: all assertions passed"
