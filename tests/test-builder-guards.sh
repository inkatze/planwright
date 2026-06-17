#!/bin/bash
# Tests for scripts/builder-guards.sh — the testable detection core of the
# builder skill (Task 16). Covers stack detection (REQ-G1.2), data-driven
# catalog extensibility (REQ-G1.5), and the dogfood loop (REQ-G1.7): the
# builder run against planwright itself reproduces the core guard set Task 2
# wired into mise.toml + .github/workflows/ci.yml.
#
# Portable bash 3.2 floor; runs under /bin/bash in CI (REQ-K1.5).
set -u
unset CDPATH

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/builder-guards.sh"
CATALOG="$REPO_ROOT/config/guard-catalog.yaml"

failures=0
pass() { echo "ok: $1"; }
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}
assert_exit() {
  # assert_exit <label> <expected> <actual>
  if [ "$2" -eq "$3" ]; then pass "$1"; else fail "$1 (expected exit $2, got $3)"; fi
}

if [ ! -x "$SCRIPT" ]; then
  echo "FAIL: builder-guards.sh missing or not executable at $SCRIPT" >&2
  exit 1
fi
if [ ! -f "$CATALOG" ]; then
  echo "FAIL: guard catalog missing at $CATALOG" >&2
  exit 1
fi

# emits <tool>? — true if the run output names a guard backed by <tool>.
# The output contract is tab-separated `<id>\t<category>\t<tool>` lines.
tools_of() { awk -F'\t' '{print $3}'; }
cats_of() { awk -F'\t' '{print $2}'; }

# ---------------------------------------------------------------------------
# 1. Dogfood (REQ-G1.7): --core against planwright reproduces Task 2's guards.
# ---------------------------------------------------------------------------
core_out="$(/bin/bash "$SCRIPT" --core "$REPO_ROOT" 2>/dev/null)"
assert_exit "dogfood run exits clean" 0 $?
core_tools="$(printf '%s\n' "$core_out" | tools_of)"

# Each universal core guard Task 2 established must be recommended.
for t in shfmt shellcheck markdownlint yamllint jq shell-test-runner \
  gitleaks conventional-commits github-actions; do
  if printf '%s\n' "$core_tools" | grep -qx "$t"; then
    pass "dogfood recommends core guard: $t"
  else
    fail "dogfood missing core guard: $t"
  fi
done

# planwright is a typed-language-free shell/docs project: no type-checker fires
# (proving detection is real, not a fixed checklist).
if printf '%s\n' "$(printf '%s\n' "$core_out" | cats_of)" | grep -qx "type-checker"; then
  fail "dogfood wrongly recommends a type-checker for a shell-only project"
else
  pass "dogfood recommends no type-checker (shell has none)"
fi

# ---------------------------------------------------------------------------
# 2. Reproduction is grounded in Task 2's actual artifacts, not a constant:
#    every recommended core tool is verifiably wired in this repo.
# ---------------------------------------------------------------------------
wired() {
  # wired <tool> — is this guard actually present in planwright's wiring?
  case "$1" in
    shfmt | shellcheck | markdownlint | yamllint | gitleaks)
      # markdownlint ships as markdownlint-cli2; match the family.
      grep -Eq "^(${1}|${1}-cli2|${1}-cli) " "$REPO_ROOT/mise.toml"
      ;;
    jq) grep -q 'jq ' "$REPO_ROOT/mise.toml" ;;
    shell-test-runner) grep -q '\[tasks.test\]' "$REPO_ROOT/mise.toml" ;;
    conventional-commits) [ -x "$REPO_ROOT/scripts/check-commit-msgs.sh" ] ;;
    github-actions) ls "$REPO_ROOT"/.github/workflows/*.yml >/dev/null 2>&1 ;;
    *) return 1 ;;
  esac
}
for t in shfmt shellcheck markdownlint yamllint jq shell-test-runner \
  gitleaks conventional-commits github-actions; do
  if wired "$t"; then
    pass "core guard wired in planwright (Task 2): $t"
  else
    fail "recommended guard not actually wired in planwright: $t"
  fi
done

# ---------------------------------------------------------------------------
# 3. Stack detection (REQ-G1.2): a Python project gets the Python guard set.
# ---------------------------------------------------------------------------
# Bind every path the EXIT trap references before registering it: under
# `set -u` an early exit (signal, or a future unbound-variable abort) between
# here and the later mktemp assignments would otherwise make the trap itself
# fault on an unset var and mask the original failure. Empty values are inert
# under `rm -rf` with `-f`.
tmp_py="$(mktemp -d)"
tmp_md="" tmp_git="" tmp_ext="" tmp_bad="" tmp_jf="" tmp_bb="" tmp_zp="" tmp_empty="" tmp_zc=""
trap 'rm -rf "$tmp_py" "$tmp_md" "$tmp_git" "$tmp_ext" "$tmp_bad" "$tmp_jf" "$tmp_bb" "$tmp_zp" "$tmp_empty" "$tmp_zc"' EXIT
: >"$tmp_py/app.py"
: >"$tmp_py/pyproject.toml"
py_tools="$(/bin/bash "$SCRIPT" --core "$tmp_py" 2>/dev/null | tools_of)"
if printf '%s\n' "$py_tools" | grep -qx "ruff"; then
  pass "python project detects ruff"
else
  fail "python project missing ruff"
fi
if printf '%s\n' "$py_tools" | grep -qx "mypy"; then
  pass "python project detects a type-checker (mypy)"
else
  fail "python project missing type-checker"
fi
# The full Python guard set, not just the linter/type-checker: the formatter
# (ruff-format) and the test runner (pytest) must fire too, so a regression
# that drops either is caught.
if printf '%s\n' "$py_tools" | grep -qx "ruff-format"; then
  pass "python project detects a formatter (ruff-format)"
else
  fail "python project missing formatter (ruff-format)"
fi
if printf '%s\n' "$py_tools" | grep -qx "pytest"; then
  pass "python project detects a test runner (pytest)"
else
  fail "python project missing test runner (pytest)"
fi
# A python-only dir has no shell, so shellcheck must NOT fire.
if printf '%s\n' "$py_tools" | grep -qx "shellcheck"; then
  fail "python-only project wrongly recommends shellcheck"
else
  pass "python-only project omits shellcheck (no .sh present)"
fi

# ---------------------------------------------------------------------------
# 4. Detection negative: a docs-only, non-git dir gets prose linting only.
# ---------------------------------------------------------------------------
tmp_md="$(mktemp -d)"
: >"$tmp_md/README.md"
md_out="$(/bin/bash "$SCRIPT" --core "$tmp_md" 2>/dev/null)"
md_tools="$(printf '%s\n' "$md_out" | tools_of)"
if printf '%s\n' "$md_tools" | grep -qx "markdownlint"; then
  pass "docs-only project detects markdownlint"
else
  fail "docs-only project missing markdownlint"
fi
for t in shellcheck shfmt ruff gitleaks github-actions conventional-commits; do
  if printf '%s\n' "$md_tools" | grep -qx "$t"; then
    fail "docs-only non-git project wrongly recommends $t"
  else
    pass "docs-only non-git project omits $t"
  fi
done

# ---------------------------------------------------------------------------
# 5. git-signalled guards: secret scan / commit lint / CI gate fire only in a
#    git work tree.
# ---------------------------------------------------------------------------
tmp_git="$(mktemp -d)"
: >"$tmp_git/run.sh"
(cd "$tmp_git" && git init -q && git config user.email t@t && git config user.name t) 2>/dev/null
git_tools="$(/bin/bash "$SCRIPT" --core "$tmp_git" 2>/dev/null | tools_of)"
for t in gitleaks conventional-commits github-actions; do
  if printf '%s\n' "$git_tools" | grep -qx "$t"; then
    pass "git project detects git-signalled guard: $t"
  else
    fail "git project missing git-signalled guard: $t"
  fi
done

# ---------------------------------------------------------------------------
# 6. Extensibility (REQ-G1.5): a new catalog entry fires with no script edit.
# ---------------------------------------------------------------------------
tmp_ext="$(mktemp -d)"
cp "$CATALOG" "$tmp_ext/catalog.yaml"
cat >>"$tmp_ext/catalog.yaml" <<'YAML'
  - id: lint-proto
    category: linter
    tool: buf
    detect: "*.proto"
    core: true
YAML
: >"$tmp_ext/svc.proto"
ext_tools="$(PLANWRIGHT_GUARD_CATALOG="$tmp_ext/catalog.yaml" \
  /bin/bash "$SCRIPT" --core "$tmp_ext" 2>/dev/null | tools_of)"
if printf '%s\n' "$ext_tools" | grep -qx "buf"; then
  pass "adopter-added catalog entry fires without editing the script"
else
  fail "adopter-added catalog entry did not fire"
fi

# ---------------------------------------------------------------------------
# 6b. Overlay merge (Task 5, REQ-D1.1 / REQ-B1.3): with NO explicit --catalog
#     override, the default path reads the guard catalog THROUGH the overlay
#     merge resolver (scripts/resolve-catalog.sh), so a repo-tracked overlay
#     guard (<repo>/.claude/catalogs/guard-catalog.yaml) is unioned onto the
#     shipped core seed rather than replacing it.
# ---------------------------------------------------------------------------
tmp_ovl="$(mktemp -d)"
mkdir -p "$tmp_ovl/.claude/catalogs"
cat >"$tmp_ovl/.claude/catalogs/guard-catalog.yaml" <<'YAML'
guards:
  - id: overlay-extra
    category: linter
    tool: overlay-tool
    detect: "overlay-marker"
    core: true
YAML
: >"$tmp_ovl/overlay-marker"
: >"$tmp_ovl/probe.sh" # triggers the core shfmt guard so the union is observable
ovl_tools="$(PLANWRIGHT_REPO_ROOT="$tmp_ovl" \
  /bin/bash "$SCRIPT" --core "$tmp_ovl" 2>/dev/null | tools_of)"
if printf '%s\n' "$ovl_tools" | grep -qx "overlay-tool"; then
  pass "repo-tracked overlay guard merges through resolve-catalog (default path)"
else
  fail "repo-tracked overlay guard did not merge through the default path"
fi
if printf '%s\n' "$ovl_tools" | grep -qx "shfmt"; then
  pass "overlay merge unions onto the core seed (shfmt still present)"
else
  fail "overlay merge dropped the core seed (shfmt missing)"
fi
rm -rf "$tmp_ovl"

# ---------------------------------------------------------------------------
# 7. Usage hygiene: bad catalog path fails clean, not silently.
# ---------------------------------------------------------------------------
PLANWRIGHT_GUARD_CATALOG="/no/such/catalog.yaml" /bin/bash "$SCRIPT" --core "$REPO_ROOT" >/dev/null 2>&1
assert_exit "missing catalog file errors (non-zero)" 1 $?

# ---------------------------------------------------------------------------
# 8. Malformed catalog entry (missing/empty detect) degrades gracefully
#    (REQ-K1.7, REQ-G1.5): skip the bad entry with a warning, never crash the
#    whole run, and still emit the valid guards. A bare empty-array expansion
#    under `set -u` on the bash 3.2 floor would otherwise abort the script.
# ---------------------------------------------------------------------------
tmp_bad="$(mktemp -d)"
cat >"$tmp_bad/catalog.yaml" <<'YAML'
---
guards:
  - id: missing-detect
    category: linter
    tool: footool
    core: true
  - id: empty-detect
    category: linter
    tool: bartool
    detect: ""
    core: true
  - id: good-shell
    category: linter
    tool: shellcheck
    detect: "*.sh"
    core: true
YAML
: >"$tmp_bad/x.sh"
bad_out="$(PLANWRIGHT_GUARD_CATALOG="$tmp_bad/catalog.yaml" \
  /bin/bash "$SCRIPT" --core "$tmp_bad" 2>"$tmp_bad/err.txt")"
bad_rc=$?
assert_exit "malformed-detect entry does not crash the run" 0 "$bad_rc"
if printf '%s\n' "$bad_out" | tools_of | grep -qx "shellcheck"; then
  pass "valid guards still emitted past a malformed entry"
else
  fail "valid guard dropped by a malformed sibling entry"
fi
if printf '%s\n' "$bad_out" | tools_of | grep -qxE "footool|bartool"; then
  fail "malformed (detect-less) entry was wrongly emitted"
else
  pass "malformed (detect-less) entry omitted, not emitted"
fi
if grep -q "missing-detect" "$tmp_bad/err.txt" && grep -q "empty-detect" "$tmp_bad/err.txt"; then
  pass "skipped entries are named in a stderr warning (not silent)"
else
  fail "malformed entries skipped silently (no stderr warning naming them)"
fi
rm -rf "$tmp_bad"

# A guards entry missing category or tool is equally malformed: skip it with a
# warning rather than emitting a junk line with an empty field.
tmp_jf="$(mktemp -d)"
cat >"$tmp_jf/catalog.yaml" <<'YAML'
---
guards:
  - id: no-tool
    category: linter
    detect: "*.sh"
    core: true
  - id: no-category
    tool: sometool
    detect: "*.sh"
    core: true
  - id: good-shell
    category: linter
    tool: shellcheck
    detect: "*.sh"
    core: true
YAML
: >"$tmp_jf/x.sh"
jf_out="$(PLANWRIGHT_GUARD_CATALOG="$tmp_jf/catalog.yaml" \
  /bin/bash "$SCRIPT" --core "$tmp_jf" 2>"$tmp_jf/err.txt")"
assert_exit "missing category/tool does not crash" 0 $?
# No emitted line may have an empty category or tool column.
if printf '%s\n' "$jf_out" | awk -F'\t' 'NF<3 || $2=="" || $3=="" {bad=1} END{exit bad?0:1}'; then
  fail "a malformed entry emitted a line with an empty column"
else
  pass "no emitted guard line has an empty category/tool column"
fi
if printf '%s\n' "$jf_out" | tools_of | grep -qx "shellcheck"; then
  pass "valid guard still emitted past category/tool-less entries"
else
  fail "valid guard dropped by a category/tool-less sibling"
fi
if grep -q "no-tool" "$tmp_jf/err.txt" && grep -q "no-category" "$tmp_jf/err.txt"; then
  pass "category/tool-less entries named in a stderr warning"
else
  fail "category/tool-less entries skipped silently"
fi
rm -rf "$tmp_jf"

# A breadth entry is emitted unconditionally with category/tool columns, so it
# needs the same required-field guard as a guards entry: a breadth entry
# missing category or tool must be skipped with a warning, never emitted as a
# line with an empty column (REQ-K1.7, REQ-G1.5). Breadth entries legitimately
# carry no real detect signal, so detect is the one field not required of them.
tmp_bb="$(mktemp -d)"
cat >"$tmp_bb/catalog.yaml" <<'YAML'
---
breadth:
  - id: doc-coverage
    category: breadth
    tool: manual-doc-review
    detect: "manual"
  - id: broken-breadth
    category: breadth
    detect: "manual"
YAML
bb_out="$(PLANWRIGHT_GUARD_CATALOG="$tmp_bb/catalog.yaml" \
  /bin/bash "$SCRIPT" "$tmp_bb" 2>"$tmp_bb/err.txt")"
assert_exit "malformed breadth entry does not crash the run" 0 $?
if printf '%s\n' "$bb_out" | awk -F'\t' 'NF<3 || $2=="" || $3=="" {bad=1} END{exit bad?0:1}'; then
  fail "a malformed breadth entry emitted a line with an empty column"
else
  pass "no emitted breadth line has an empty category/tool column"
fi
if printf '%s\n' "$bb_out" | tools_of | grep -qx "manual-doc-review"; then
  pass "valid breadth entry still emitted past a malformed sibling"
else
  fail "valid breadth entry dropped by a malformed sibling"
fi
if grep -q "broken-breadth" "$tmp_bb/err.txt"; then
  pass "malformed breadth entry named in a stderr warning (not silent)"
else
  fail "malformed breadth entry skipped silently (no stderr warning)"
fi
rm -rf "$tmp_bb"

# A guards:/breadth: section whose entries do not parse (reflowed indentation,
# single-quoted scalars, inline comments — none of which the constrained reader
# supports) yields zero guards. That is almost always an adopter format mistake,
# so the reader warns loudly rather than emitting nothing silently (REQ-G1.5
# extensibility: a silent empty result is the worst failure mode for an adopter).
tmp_zp="$(mktemp -d)"
cat >"$tmp_zp/catalog.yaml" <<'YAML'
---
guards:
    - id: over-indented
      category: linter
      tool: shellcheck
      detect: "*.sh"
      core: true
YAML
: >"$tmp_zp/x.sh"
zp_err="$(PLANWRIGHT_GUARD_CATALOG="$tmp_zp/catalog.yaml" \
  /bin/bash "$SCRIPT" --core "$tmp_zp" 2>&1 >/dev/null)"
if printf '%s\n' "$zp_err" | grep -q "no entries parsed"; then
  pass "a guards section that parsed zero entries warns (not a silent empty result)"
else
  fail "zero-parse section produced no warning"
fi
# A genuinely empty catalog (no guards:/breadth: section at all) must NOT warn:
# zero guards is the correct answer there, not a format mistake.
tmp_empty="$(mktemp -d)"
printf -- '---\n' >"$tmp_empty/catalog.yaml"
ze_err="$(PLANWRIGHT_GUARD_CATALOG="$tmp_empty/catalog.yaml" \
  /bin/bash "$SCRIPT" --core "$tmp_zp" 2>&1 >/dev/null)"
if printf '%s\n' "$ze_err" | grep -q "no entries parsed"; then
  fail "a section-less catalog wrongly warned about zero entries"
else
  pass "a section-less catalog does not warn (zero guards is correct there)"
fi
rm -rf "$tmp_zp" "$tmp_empty"

# The zero-parse warning must catch the section header even when it carries a
# trailing inline comment (valid YAML the strict reader does not treat as a
# section start): the warning's detection is deliberately looser than the
# parser's so this silent-empty case still surfaces.
tmp_zc="$(mktemp -d)"
cat >"$tmp_zc/catalog.yaml" <<'YAML'
---
guards:  # an adopter left a comment on the section header
  - id: shell
    category: linter
    tool: shellcheck
    detect: "*.sh"
    core: true
YAML
: >"$tmp_zc/x.sh"
zc_err="$(PLANWRIGHT_GUARD_CATALOG="$tmp_zc/catalog.yaml" \
  /bin/bash "$SCRIPT" --core "$tmp_zc" 2>&1 >/dev/null)"
if printf '%s\n' "$zc_err" | grep -q "no entries parsed"; then
  pass "zero-parse warning fires even when the section header has an inline comment"
else
  fail "zero-parse warning missed a commented section header (silent empty)"
fi
rm -rf "$tmp_zc"

# ---------------------------------------------------------------------------
# 9. --help prints the usage block only, never leaking source code lines.
# ---------------------------------------------------------------------------
help_out="$(/bin/bash "$SCRIPT" --help 2>&1)"
assert_exit "--help exits clean" 0 $?
if printf '%s\n' "$help_out" | grep -q "Usage: builder-guards.sh"; then
  pass "--help shows the usage line"
else
  fail "--help missing the usage line"
fi
if printf '%s\n' "$help_out" | grep -qx "set -u"; then
  fail "--help leaks source code past the comment header"
else
  pass "--help does not leak source code"
fi

# ---------------------------------------------------------------------------
# 10. Usage faults exit 2 (the script header's exit contract: 0 success,
#     1 missing/unreadable catalog, 2 usage error). Distinct from the exit-1
#     path in section 7, these are caller mistakes, not runtime failures.
# ---------------------------------------------------------------------------
/bin/bash "$SCRIPT" --bogus-flag >/dev/null 2>&1
assert_exit "unknown option is a usage error" 2 $?
/bin/bash "$SCRIPT" --catalog >/dev/null 2>&1
assert_exit "--catalog with no argument is a usage error" 2 $?
PLANWRIGHT_GUARD_CATALOG="$CATALOG" /bin/bash "$SCRIPT" --core /no/such/target/dir >/dev/null 2>&1
assert_exit "missing target directory is a usage error" 2 $?
# A second positional argument is a caller mistake, not a silent last-wins
# (matches the repo convention, e.g. scripts/spec-validate.sh).
/bin/bash "$SCRIPT" /tmp /tmp >/dev/null 2>&1
assert_exit "a second positional argument is a usage error" 2 $?
# The flag form must carry a non-empty path: an empty value would otherwise
# fall back to the default catalog silently (e.g. --catalog "$UNSET_VAR").
/bin/bash "$SCRIPT" --catalog "" /tmp >/dev/null 2>&1
assert_exit "an empty --catalog path is a usage error" 2 $?
/bin/bash "$SCRIPT" --catalog= /tmp >/dev/null 2>&1
assert_exit "an empty --catalog= path is a usage error" 2 $?

if [ "$failures" -eq 0 ]; then
  echo "all builder-guards tests passed"
  exit 0
fi
echo "$failures builder-guards test(s) failed" >&2
exit 1
