#!/bin/bash
# Tests for scripts/resolve-catalog.sh — the catalog discovery path that
# unions a catalog's core seed with the adopter / repo-tracked / machine-local
# overlay catalogs (Task 5; REQ-A1.2, REQ-B1.3, REQ-B1.4, REQ-B1.5, REQ-B1.6,
# REQ-D1.1, REQ-E1.4; D-2, D-4, D-5, D-7, D-9). Merge contract: append/union,
# supersede-by-id; malformed-by-layer (degrade+warn for adopter/machine-local,
# hard-fail for repo-tracked); supersede-of-nonexistent-target hard-fails under
# the same by-layer policy. Plain bash 3.2, inline asserts (sibling convention).
set -u
unset CDPATH
LC_ALL=C
export LC_ALL

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RESOLVER="$REPO_ROOT/scripts/resolve-catalog.sh"

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
assert_absent() {
  # assert_absent <description> <needle> <haystack>
  case "$3" in
    *"$2"*)
      echo "FAIL: $1 (did not expect '$2' in output)" >&2
      failures=$((failures + 1))
      ;;
    *) echo "ok: $1" ;;
  esac
}

if [ ! -f "$RESOLVER" ]; then
  echo "FAIL: resolver script missing at $RESOLVER" >&2
  exit 1
fi

tmp="$(cd "$(mktemp -d)" && pwd -P)" || exit 1
trap 'rm -rf "$tmp"' EXIT

# A clean base env: strip every overlay-affecting variable so each case sets
# only the layer roots it exercises.
base() {
  env -u PLANWRIGHT_ROOT -u CLAUDE_PLUGIN_ROOT -u CLAUDE_DIR \
    -u PLANWRIGHT_ADOPTER_OVERLAY -u CLAUDE_PLUGIN_DATA \
    -u PLANWRIGHT_REPO_ROOT -u HOME "$@"
}

# Run resolve-catalog with the four layer roots wired to a per-case sandbox.
# <sandbox> holds: core/ (PLANWRIGHT_ROOT), adopter/ (PLANWRIGHT_ADOPTER_OVERLAY),
# repo/ (PLANWRIGHT_REPO_ROOT, holding .claude/catalogs + .claude/catalogs.local).
rc() {
  sb="$1"
  shift
  base PLANWRIGHT_ROOT="$sb/core" PLANWRIGHT_ADOPTER_OVERLAY="$sb/adopter" \
    PLANWRIGHT_REPO_ROOT="$sb/repo" /bin/bash "$RESOLVER" "$@"
}

# Write a catalog file with one `entries:` section from id=note pairs.
# write_cat <path> <id1> <note1> [<id2> <note2> ...]
write_cat() {
  wc_path="$1"
  shift
  mkdir -p "$(dirname "$wc_path")"
  {
    echo "entries:"
    while [ $# -ge 2 ]; do
      printf '  - id: %s\n' "$1"
      printf '    note: "%s"\n' "$2"
      shift 2
    done
  } >"$wc_path"
}

core_seed() { echo "$1/core/config/$2.yaml"; }
adopter_cat() { echo "$1/adopter/catalogs/$2.yaml"; }
repo_cat() { echo "$1/repo/.claude/catalogs/$2.yaml"; }
local_cat() { echo "$1/repo/.claude/catalogs.local/$2.yaml"; }

# ---------------------------------------------------------------------------
# 1. append/union: an overlay adds a new entry; core entries survive (REQ-B1.3)
# ---------------------------------------------------------------------------
sb="$tmp/append"
write_cat "$(core_seed "$sb" testcat)" alpha "core-a" beta "core-b"
write_cat "$(adopter_cat "$sb" testcat)" gamma "adopter-g"
out="$(rc "$sb" testcat)"
assert "append: exit 0" 0 $?
assert_contains "append: core alpha survives" "id: alpha" "$out"
assert_contains "append: core beta survives" "id: beta" "$out"
assert_contains "append: adopter gamma added" "id: gamma" "$out"

# ---------------------------------------------------------------------------
# 2. supersede-by-id: an overlay supersede entry replaces its target; the
#    other core entry survives (REQ-B1.3)
# ---------------------------------------------------------------------------
sb="$tmp/supersede"
write_cat "$(core_seed "$sb" testcat)" alpha "core-a" beta "core-b"
mkdir -p "$(dirname "$(adopter_cat "$sb" testcat)")"
cat >"$(adopter_cat "$sb" testcat)" <<'YAML'
entries:
  - id: alpha
    supersede: true
    note: "overlay-a"
YAML
out="$(rc "$sb" testcat)"
assert "supersede: exit 0" 0 $?
assert_contains "supersede: alpha replaced (overlay note)" "overlay-a" "$out"
assert_absent "supersede: alpha old note gone" "core-a" "$out"
assert_contains "supersede: beta survives" "core-b" "$out"
assert_absent "supersede: marker stripped from output" "supersede:" "$out"

# ---------------------------------------------------------------------------
# 2b. `supersede: false` (or any non-`true` value) is NOT a supersede marker
#     (value-equality, like the guard catalog's `core: true`): the entry is a
#     plain append, not an attempt to replace a target.
# ---------------------------------------------------------------------------
sb="$tmp/supersede-false"
write_cat "$(core_seed "$sb" testcat)" alpha "core-a"
mkdir -p "$(dirname "$(adopter_cat "$sb" testcat)")"
cat >"$(adopter_cat "$sb" testcat)" <<'YAML'
entries:
  - id: beta
    supersede: false
    note: "appended"
YAML
out="$(rc "$sb" testcat 2>/dev/null)"
assert "supersede:false: exit 0 (append, not supersede)" 0 $?
assert_contains "supersede:false: new id appended" "appended" "$out"
assert_contains "supersede:false: core survives" "core-a" "$out"
assert_absent "supersede:false: marker not re-emitted" "supersede:" "$out"

# ---------------------------------------------------------------------------
# 2c. a duplicate id WITHOUT a supersede marker is a slip: the merge warns and
#     skips the duplicate (the established lower-precedence entry wins), exit 0.
#     The only sanctioned override is `supersede: true` (covered by case 2).
# ---------------------------------------------------------------------------
sb="$tmp/dup-no-supersede"
write_cat "$(core_seed "$sb" testcat)" alpha "core-a"
mkdir -p "$(dirname "$(adopter_cat "$sb" testcat)")"
cat >"$(adopter_cat "$sb" testcat)" <<'YAML'
entries:
  - id: alpha
    note: "overlay-dup"
YAML
err="$(rc "$sb" testcat 2>&1 1>/dev/null)"
rc "$sb" testcat >/dev/null 2>&1
assert "dup-no-supersede: exit 0 (slip, degrade)" 0 $?
out="$(rc "$sb" testcat 2>/dev/null)"
assert_contains "dup-no-supersede: warns about the duplicate" "alpha" "$err"
assert_contains "dup-no-supersede: established core entry wins" "core-a" "$out"
assert_absent "dup-no-supersede: overlay duplicate dropped" "overlay-dup" "$out"

# ---------------------------------------------------------------------------
# 3. supersede-of-nonexistent-target, adopter layer → degrade+warn, exit 0,
#    offending entry skipped, core entries intact (pinned by-layer policy)
# ---------------------------------------------------------------------------
sb="$tmp/badsup-adopter"
write_cat "$(core_seed "$sb" testcat)" alpha "core-a"
mkdir -p "$(dirname "$(adopter_cat "$sb" testcat)")"
cat >"$(adopter_cat "$sb" testcat)" <<'YAML'
entries:
  - id: ghost
    supersede: true
    note: "no-target"
YAML
err="$(rc "$sb" testcat 2>&1 1>/dev/null)"
rc "$sb" testcat >/dev/null 2>&1
assert "bad-supersede adopter: exit 0 (degrade)" 0 $?
out="$(rc "$sb" testcat 2>/dev/null)"
assert_contains "bad-supersede adopter: warns" "ghost" "$err"
assert_absent "bad-supersede adopter: ghost skipped" "no-target" "$out"
assert_contains "bad-supersede adopter: core intact" "core-a" "$out"

# ---------------------------------------------------------------------------
# 4. supersede-of-nonexistent-target, repo-tracked layer → hard-fail (pinned)
# ---------------------------------------------------------------------------
sb="$tmp/badsup-repo"
write_cat "$(core_seed "$sb" testcat)" alpha "core-a"
mkdir -p "$(dirname "$(repo_cat "$sb" testcat)")"
cat >"$(repo_cat "$sb" testcat)" <<'YAML'
entries:
  - id: ghost
    supersede: true
    note: "no-target"
YAML
rc "$sb" testcat >/dev/null 2>&1
assert "bad-supersede repo-tracked: hard-fail nonzero" 1 $?

# ---------------------------------------------------------------------------
# 5. four-layer precedence: a supersede chain — machine-local wins (REQ-A1.2)
# ---------------------------------------------------------------------------
sb="$tmp/precedence"
write_cat "$(core_seed "$sb" testcat)" alpha "v-core"
mkdir -p "$(dirname "$(adopter_cat "$sb" testcat)")" \
  "$(dirname "$(repo_cat "$sb" testcat)")" \
  "$(dirname "$(local_cat "$sb" testcat)")"
for f in "$(adopter_cat "$sb" testcat):v-adopter" \
  "$(repo_cat "$sb" testcat):v-repo" \
  "$(local_cat "$sb" testcat):v-local"; do
  path="${f%:*}"
  val="${f##*:}"
  printf 'entries:\n  - id: alpha\n    supersede: true\n    note: "%s"\n' "$val" >"$path"
done
out="$(rc "$sb" testcat)"
assert "precedence: exit 0" 0 $?
assert_contains "precedence: machine-local wins" "v-local" "$out"
assert_absent "precedence: core value gone" "v-core" "$out"
assert_absent "precedence: adopter value gone" "v-adopter" "$out"

# ---------------------------------------------------------------------------
# 6. absent layers degrade (REQ-A1.4): only core present → merged = core
# ---------------------------------------------------------------------------
sb="$tmp/absent"
write_cat "$(core_seed "$sb" testcat)" alpha "core-a"
out="$(rc "$sb" testcat 2>/dev/null)"
assert "absent layers: exit 0" 0 $?
assert_contains "absent layers: core survives" "core-a" "$out"

# Catalog absent in every layer → empty output, exit 0.
sb="$tmp/empty"
mkdir -p "$sb/core" "$sb/adopter" "$sb/repo"
out="$(rc "$sb" testcat 2>/dev/null)"
assert "fully-absent catalog: exit 0" 0 $?
assert_eq "fully-absent catalog: empty output" "" "$out"

# ---------------------------------------------------------------------------
# 7. malformed-by-layer (REQ-E1.4, D-7): a present-but-unparseable overlay file
# ---------------------------------------------------------------------------
# adopter malformed → degrade+warn, exit 0, core survives.
sb="$tmp/malformed-adopter"
write_cat "$(core_seed "$sb" testcat)" alpha "core-a"
mkdir -p "$(dirname "$(adopter_cat "$sb" testcat)")"
printf 'this is not a catalog\n' >"$(adopter_cat "$sb" testcat)"
err="$(rc "$sb" testcat 2>&1 1>/dev/null)"
rc "$sb" testcat >/dev/null 2>&1
assert "malformed adopter: exit 0 (degrade)" 0 $?
assert_contains "malformed adopter: warns" "adopter" "$err"
out="$(rc "$sb" testcat 2>/dev/null)"
assert_contains "malformed adopter: core survives" "core-a" "$out"

# machine-local malformed → degrade+warn, exit 0.
sb="$tmp/malformed-local"
write_cat "$(core_seed "$sb" testcat)" alpha "core-a"
mkdir -p "$(dirname "$(local_cat "$sb" testcat)")"
printf 'garbage\n' >"$(local_cat "$sb" testcat)"
rc "$sb" testcat >/dev/null 2>&1
assert "malformed machine-local: exit 0 (degrade)" 0 $?

# repo-tracked malformed → hard-fail nonzero.
sb="$tmp/malformed-repo"
write_cat "$(core_seed "$sb" testcat)" alpha "core-a"
mkdir -p "$(dirname "$(repo_cat "$sb" testcat)")"
printf 'garbage\n' >"$(repo_cat "$sb" testcat)"
rc "$sb" testcat >/dev/null 2>&1
assert "malformed repo-tracked: hard-fail nonzero" 1 $?

# ---------------------------------------------------------------------------
# 8. --explain names each entry's supplying layer (REQ-B1.6)
# ---------------------------------------------------------------------------
sb="$tmp/explain"
write_cat "$(core_seed "$sb" testcat)" alpha "core-a" beta "core-b"
write_cat "$(adopter_cat "$sb" testcat)" gamma "adopter-g"
mkdir -p "$(dirname "$(local_cat "$sb" testcat)")"
cat >"$(local_cat "$sb" testcat)" <<'YAML'
entries:
  - id: alpha
    supersede: true
    note: "local-a"
YAML
out="$(rc "$sb" testcat --explain 2>/dev/null)"
assert "explain: exit 0" 0 $?
assert_contains "explain: beta from core" "beta	core" "$out"
assert_contains "explain: gamma from adopter" "gamma	adopter" "$out"
assert_contains "explain: alpha now from machine-local (superseded)" "alpha	machine-local" "$out"

# ---------------------------------------------------------------------------
# 9. deterministic / order-independent (REQ-B1.5): repeated runs are identical,
#    and precedence is by layer rule, not by file creation order.
# ---------------------------------------------------------------------------
sb="$tmp/determinism"
write_cat "$(core_seed "$sb" testcat)" alpha "core-a" beta "core-b"
write_cat "$(adopter_cat "$sb" testcat)" gamma "adopter-g" delta "adopter-d"
run1="$(rc "$sb" testcat 2>/dev/null)"
run2="$(rc "$sb" testcat 2>/dev/null)"
assert_eq "determinism: repeated runs identical" "$run1" "$run2"

# ---------------------------------------------------------------------------
# 10. invalid catalog name rejected before any path interpolation (REQ-E1.2)
# ---------------------------------------------------------------------------
sb="$tmp/append"
rc "$sb" "../evil" >/dev/null 2>&1
assert "invalid name (traversal): usage error" 2 $?
rc "$sb" "Bad_Name" >/dev/null 2>&1
assert "invalid name (uppercase/underscore): usage error" 2 $?
base /bin/bash "$RESOLVER" >/dev/null 2>&1
assert "missing name: usage error" 2 $?

# ---------------------------------------------------------------------------
# 11. real decision-domains seed resolves to the ten domains (smoke)
# ---------------------------------------------------------------------------
sb="$tmp/realdd"
mkdir -p "$sb/repo"
out="$(base PLANWRIGHT_ROOT="$REPO_ROOT" PLANWRIGHT_REPO_ROOT="$sb/repo" \
  /bin/bash "$RESOLVER" decision-domains 2>/dev/null)"
assert "real decision-domains: exit 0" 0 $?
for id in data-storage caching queues-async api-surface auth secrets-config \
  concurrency observability deploy-migration dependency-adoption; do
  assert_contains "real decision-domains: $id present" "id: $id" "$out"
done
exp="$(base PLANWRIGHT_ROOT="$REPO_ROOT" PLANWRIGHT_REPO_ROOT="$sb/repo" \
  /bin/bash "$RESOLVER" decision-domains --explain 2>/dev/null | grep -c '	core$')"
assert_eq "real decision-domains: ten core entries via --explain" "10" "$exp"

# ---------------------------------------------------------------------------
# 12. fast-path is byte-identical to the core seed (REQ-B1.2): with only the
#     core layer present, yaml mode emits the seed verbatim — comments and
#     blank lines preserved, NOT reflowed through the awk merge path.
# ---------------------------------------------------------------------------
sb="$tmp/fastpath"
mkdir -p "$(dirname "$(core_seed "$sb" testcat)")"
cat >"$(core_seed "$sb" testcat)" <<'YAML'
---
# a leading comment the awk path would strip
entries:
  - id: alpha
    note: "core-a"

  - id: beta
    note: "core-b"
YAML
out="$(rc "$sb" testcat 2>/dev/null)"
assert "fast-path: exit 0" 0 $?
assert_eq "fast-path: byte-identical to the core seed" \
  "$(cat "$(core_seed "$sb" testcat)")" "$out"

# ---------------------------------------------------------------------------
# 13. an overlay entry with an empty id warns and is skipped (F3): the typo'd
#     entry vanishes from the merge but the operator sees it, and surrounding
#     entries survive.
# ---------------------------------------------------------------------------
sb="$tmp/emptyid"
write_cat "$(core_seed "$sb" testcat)" alpha "core-a"
mkdir -p "$(dirname "$(adopter_cat "$sb" testcat)")"
cat >"$(adopter_cat "$sb" testcat)" <<'YAML'
entries:
  - id:
    note: "orphan"
  - id: gamma
    note: "adopter-g"
YAML
err="$(rc "$sb" testcat 2>&1 1>/dev/null)"
rc "$sb" testcat >/dev/null 2>&1
assert "empty-id: exit 0 (degrade)" 0 $?
out="$(rc "$sb" testcat 2>/dev/null)"
assert_contains "empty-id: warns about the empty id" "empty id" "$err"
assert_absent "empty-id: orphan note dropped" "orphan" "$out"
assert_contains "empty-id: core survives" "core-a" "$out"
assert_contains "empty-id: sibling entry survives" "adopter-g" "$out"

# ---------------------------------------------------------------------------
# 14. a malformed CORE-only seed hard-fails on the fast path too (F2): the
#     documented "malformed core is a broken install" contract holds even when
#     no overlay forces the awk path.
# ---------------------------------------------------------------------------
sb="$tmp/malformed-core-fastpath"
mkdir -p "$(dirname "$(core_seed "$sb" testcat)")"
printf 'this is not a catalog\n' >"$(core_seed "$sb" testcat)"
rc "$sb" testcat >/dev/null 2>&1
assert "malformed core (fast path): hard-fail nonzero" 1 $?

# ---------------------------------------------------------------------------
# 15. canonicalize-then-contain (D-8, REQ-E1.5, R8): an overlay catalog file
#     that is a symlink escaping its overlay root is treated as malformed for
#     its layer and NEVER read. A symlink that stays under the root resolves
#     normally (containment rejects escapes, not symlinks per se).
# ---------------------------------------------------------------------------
# repo-tracked symlink escape → hard-fail, no outside content emitted.
sb="$tmp/symlink-escape-repo"
write_cat "$(core_seed "$sb" testcat)" alpha "core-a"
printf 'entries:\n  - id: leaked\n    note: "OUTSIDE-ROOT"\n' >"$sb/secret.yaml"
mkdir -p "$(dirname "$(repo_cat "$sb" testcat)")"
ln -s "$sb/secret.yaml" "$(repo_cat "$sb" testcat)"
out="$(rc "$sb" testcat 2>/dev/null)"
rc "$sb" testcat >/dev/null 2>&1
assert "symlink-escape repo-tracked: hard-fail nonzero" 1 $?
assert_absent "symlink-escape repo-tracked: outside content not emitted" "OUTSIDE-ROOT" "$out"

# adopter symlink escape → degrade+warn, exit 0, core survives, no leak.
sb="$tmp/symlink-escape-adopter"
write_cat "$(core_seed "$sb" testcat)" alpha "core-a"
printf 'entries:\n  - id: leaked\n    note: "OUTSIDE-ROOT"\n' >"$sb/secret.yaml"
mkdir -p "$(dirname "$(adopter_cat "$sb" testcat)")"
ln -s "$sb/secret.yaml" "$(adopter_cat "$sb" testcat)"
err="$(rc "$sb" testcat 2>&1 1>/dev/null)"
rc "$sb" testcat >/dev/null 2>&1
assert "symlink-escape adopter: exit 0 (degrade)" 0 $?
out="$(rc "$sb" testcat 2>/dev/null)"
assert_contains "symlink-escape adopter: warns about the escape" "outside its overlay root" "$err"
assert_absent "symlink-escape adopter: outside content not emitted" "OUTSIDE-ROOT" "$out"
assert_contains "symlink-escape adopter: core survives" "core-a" "$out"

# within-root symlink → resolves normally (not over-rejected).
sb="$tmp/symlink-inside"
write_cat "$(core_seed "$sb" testcat)" alpha "core-a"
mkdir -p "$(dirname "$(adopter_cat "$sb" testcat)")"
write_cat "$(dirname "$(adopter_cat "$sb" testcat)")/real.yaml" gamma "adopter-g"
ln -s "real.yaml" "$(adopter_cat "$sb" testcat)"
out="$(rc "$sb" testcat 2>/dev/null)"
assert "within-root symlink: exit 0" 0 $?
assert_contains "within-root symlink: target read" "adopter-g" "$out"

# ---------------------------------------------------------------------------
echo
if [ "$failures" -eq 0 ]; then
  echo "All resolve-catalog tests passed."
  exit 0
fi
echo "$failures resolve-catalog test(s) FAILED." >&2
exit 1
