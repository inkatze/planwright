#!/bin/bash
# Tests for the shell rule set (scripts/check-shell-*.sh over
# scripts/shell-rule-lib.sh) and its catalog and gate wiring (review-effectiveness
# REQ-F1.1).
#
# Every rule has a fixture pair under tests/fixtures/shell-rules/<rule-id>/: a
# `positive` the rule must flag at the line its `# expect-line:` header names,
# and a `negative` it must pass, the negative carrying the masked look-alikes
# (quoted text, comments, heredoc bodies, annotated sites). The fixtures carry
# no shebang and no .sh suffix so the repository's own sweeps skip them; each
# is copied into a scratch root as scripts/case.sh before the rule runs.
# shellcheck disable=SC2016 # fixture bodies are literal shell text
set -u
unset CDPATH
LC_ALL=C
export LC_ALL

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
FIXTURES="$REPO_ROOT/tests/fixtures/shell-rules"

failures=0
pass() { printf 'ok: %s\n' "$1"; }
fail() {
  printf 'FAIL: %s\n' "$1" >&2
  failures=$((failures + 1))
}

tmp=$(mktemp -d "${TMPDIR:-/tmp}/test-shell-rules.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT

# fresh_root <dir> — an empty scan root with every scope directory.
fresh_root() {
  rm -rf "$1"
  mkdir -p "$1/scripts" "$1/githooks" "$1/tests/lib" || exit 1
}

# run_rule <rule-id> <root> — runs the rule's check, leaving rc and out.
run_rule() {
  out=$(bash "$REPO_ROOT/scripts/check-$1.sh" "$2" 2>&1)
  rc=$?
}

rules=""
for d in "$FIXTURES"/*/; do
  [ -d "$d" ] || continue
  rules="$rules $(basename "$d")"
done
[ -n "$rules" ] || fail "no rule fixtures found under tests/fixtures/shell-rules"

for rule in $rules; do
  [ -f "$REPO_ROOT/scripts/check-$rule.sh" ] || {
    fail "$rule: fixtures exist but scripts/check-$rule.sh does not"
    continue
  }
  for kind in positive negative; do
    src="$FIXTURES/$rule/$kind"
    [ -f "$src" ] || {
      fail "$rule: no $kind fixture"
      continue
    }
    want=$(sed -n 's/^# expect-line: //p' "$src" | head -n 1)
    root="$tmp/$rule-$kind"
    fresh_root "$root"
    cp "$src" "$root/scripts/case.sh" || exit 1
    run_rule "$rule" "$root"
    if [ "$want" = none ]; then
      if [ "$rc" -eq 0 ]; then
        pass "$rule: the negative fixture passes"
      else
        fail "$rule: the negative fixture was flagged (exit $rc): $out"
      fi
      continue
    fi
    if [ "$rc" -ne 1 ]; then
      fail "$rule: the positive fixture exited $rc, not 1: $out"
      continue
    fi
    case "$out" in
      *"check-$rule: scripts/case.sh:$want: "*) pass "$rule: the positive fixture is flagged at line $want" ;;
      *) fail "$rule: the positive fixture was not flagged at line $want: $out" ;;
    esac
    n=$(printf '%s\n' "$out" | grep -c "^check-$rule: ")
    [ "$n" -eq 1 ] || fail "$rule: the positive fixture drew $n reports, not exactly one: $out"
  done
done

# ---------------------------------------------------------------------------
# The shared engine, driven through one rule: the annotation contract and the
# fail-closed arms.
# ---------------------------------------------------------------------------
root="$tmp/engine"
fresh_root "$root"
printf '%s\n' 'set -u' '# shell-mktemp-template:' 'f=$(mktemp) || exit 2' >"$root/scripts/a.sh"
run_rule shell-mktemp-template "$root"
case "$rc:$out" in
  1:*"annotation carries no reason"*) pass "a reasonless annotation exempts nothing and is named" ;;
  *) fail "a reasonless annotation was not reported (exit $rc): $out" ;;
esac

fresh_root "$root"
printf '%s\n' '# shell-mktemp-template: separated by a blank line' '' 'f=$(mktemp) || exit 2' >"$root/scripts/a.sh"
run_rule shell-mktemp-template "$root"
if [ "$rc" -eq 1 ]; then
  pass "an annotation a blank line away does not carry"
else
  fail "an annotation a blank line away exempted the site (exit $rc): $out"
fi

fresh_root "$root"
printf '%s\n' '#!/bin/sh' 'f=$(mktemp) || exit 2' >"$root/githooks/pre-push"
run_rule shell-mktemp-template "$root"
if [ "$rc" -eq 1 ]; then
  pass "an extensionless hook is scanned by its shebang"
else
  fail "an extensionless hook was not scanned (exit $rc): $out"
fi

fresh_root "$root"
printf '%s\n' 'f=$(mktemp) || exit 2' >"$root/tests/lib/helper.sh"
run_rule shell-mktemp-template "$root"
if [ "$rc" -eq 1 ]; then
  pass "a shebang-less library under tests/lib is scanned by its suffix"
else
  fail "a tests/lib library was not scanned (exit $rc): $out"
fi

fresh_root "$root"
printf '%s\n' 'x="a' 'mktemp' 'b"' 'f=$(mktemp) || exit 2' >"$root/scripts/a.sh"
run_rule shell-mktemp-template "$root"
case "$rc:$out" in
  1:*"scripts/a.sh:4: "*) pass "a string spanning lines is masked and the line count survives it" ;;
  *) fail "a multi-line string confused the scanner (exit $rc): $out" ;;
esac

fresh_root "$root"
run_rule shell-mktemp-template "$root"
if [ "$rc" -eq 2 ]; then
  pass "a scan reaching no files fails closed"
else
  fail "a scan reaching no files exited $rc: $out"
fi

fresh_root "$root"
printf '%s\n' 'true' >"$root/scripts/a.sh"
rmdir "$root/tests/lib"
run_rule shell-mktemp-template "$root"
if [ "$rc" -eq 2 ]; then
  pass "a missing scope directory fails closed"
else
  fail "a missing scope directory exited $rc: $out"
fi

run_rule shell-mktemp-template "$tmp/absent"
if [ "$rc" -eq 2 ]; then
  pass "an absent root fails closed"
else
  fail "an absent root exited $rc"
fi

out=$(bash "$REPO_ROOT/scripts/check-shell-mktemp-template.sh" --bogus 2>&1)
if [ $? -eq 2 ]; then
  pass "an unknown option is a usage error"
else
  fail "an unknown option was accepted: $out"
fi

# ---------------------------------------------------------------------------
# Rules the linter carries: shellcheck's own code on the fixture pair.
# ---------------------------------------------------------------------------
if command -v shellcheck >/dev/null 2>&1; then
  for d in "$REPO_ROOT"/tests/fixtures/shell-rules-shellcheck/*/; do
    rule=$(basename "$d")
    want=$(sed -n 's/^# expect: //p' "$d/positive" | head -n 1)
    if shellcheck -f gcc "$d/positive" 2>&1 | grep -q "\[$want\]"; then
      pass "$rule: shellcheck flags the positive fixture with $want"
    else
      fail "$rule: shellcheck did not flag the positive fixture with $want"
    fi
    if out=$(shellcheck "$d/negative" 2>&1); then
      pass "$rule: shellcheck passes the negative fixture"
    else
      fail "$rule: shellcheck flagged the negative fixture: $out"
    fi
  done
elif [ -n "${CI:-}" ]; then
  fail "shellcheck is not on PATH in CI, so the linter-carried rules went unchecked"
else
  printf '%s\n' "skip: linter-carried rules: shellcheck is not on PATH"
fi

# ---------------------------------------------------------------------------
# Catalog and gate wiring: every rule is a guard-catalog entry with a
# disposition, the doctrine names the set, and every scripted rule is its own mise
# task inside the check aggregate (REQ-F1.1: the set runs under the check task).
# ---------------------------------------------------------------------------
CATALOG="$REPO_ROOT/config/guard-catalog.yaml"
DOCTRINE="$REPO_ROOT/doctrine/guard-catalog.md"
MISE="$REPO_ROOT/mise.toml"
all_rules="$rules"
for d in "$REPO_ROOT"/tests/fixtures/shell-rules-shellcheck/*/; do all_rules="$all_rules $(basename "$d")"; done
all_rules="$all_rules shell-raw-echo shell-lock-contention"
for rule in $all_rules; do
  entry=$(awk -v id="$rule" '
    /^  - id:/ { on = ($3 == id) }
    on && /^    disposition:/ { print $2 }
  ' "$CATALOG")
  case "$entry" in
    auto-applicable | needs-sign-off) pass "$rule: catalogued with disposition $entry" ;;
    *) fail "$rule: no guard-catalog entry with a disposition of auto-applicable or needs-sign-off" ;;
  esac
done
if grep -q '`shell-\*` entries' "$DOCTRINE"; then
  pass "doctrine/guard-catalog.md names the shell rule set"
else
  fail "doctrine/guard-catalog.md does not name the shell rule set"
fi
for rule in $rules; do
  if grep -q "^\[tasks\.\"check:$rule\"\]" "$MISE" \
    && grep -q "^run = \"/bin/bash scripts/check-$rule.sh\"" "$MISE" \
    && grep -q "^  \"check:$rule\",$" "$MISE"; then
    pass "$rule: its own mise task, inside the check aggregate"
  else
    fail "$rule: no check:$rule task running scripts/check-$rule.sh in the check aggregate"
  fi
done
for d in "$REPO_ROOT"/tests/fixtures/shell-rules-shellcheck/*/; do
  rule=$(basename "$d")
  if awk -v id="$rule" '/^  - id:/ { on = ($3 == id) } on && /^    tool: shellcheck$/ { f = 1 } END { exit !f }' "$CATALOG"; then
    pass "$rule: catalogued as carried by shellcheck, which lint:shell runs"
  else
    fail "$rule: not catalogued with tool shellcheck"
  fi
done

if [ "$failures" -gt 0 ]; then
  printf '%s failure(s)\n' "$failures" >&2
  exit 1
fi
printf '%s\n' "all shell-rule tests passed"
