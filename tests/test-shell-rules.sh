#!/bin/bash
# Tests for the shell rule set (scripts/check-shell-*.sh over
# scripts/shell-rule-lib.sh) and its catalog and gate wiring (review-effectiveness
# REQ-F1.1).
#
# Every rule has a fixture pair under tests/fixtures/shell-rules/<rule-id>/: a
# `positive` the rule must flag at exactly the lines its `# expect-line:` headers name,
# and a `negative` it must pass, the negative carrying the masked look-alikes
# (quoted text, comments, heredoc bodies, annotated sites). The fixtures carry
# no shebang and no .sh suffix so the repository's own sweeps skip them; each
# is copied into a scratch root as scripts/case.sh before the rule runs.
# shellcheck disable=SC2016,SC1003 # fixture bodies are literal shell text
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
    want=$(sed -n 's/^# expect-line: //p' "$src" | sort -n | tr '\n' ' ')
    got=$(printf '%s\n' "$out" | sed -n "s/^check-$rule: scripts\/case\.sh:\([0-9]*\): .*/\1/p" | sort -n | tr '\n' ' ')
    if [ "$got" = "$want" ]; then
      pass "$rule: the positive fixture is flagged at exactly lines $want"
    else
      fail "$rule: the positive fixture was flagged at lines [$got], not [$want]: $out"
    fi
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

# The scratch directory's cleanup trap must not run text from TMPDIR: a quote
# in it once closed the trap's quoting and ran what followed at exit.
fresh_root "$root"
printf '%s\n' 'true' >"$root/scripts/a.sh"
qdir="$tmp/q';touch pwned;'q"
mkdir -p "$qdir" "$tmp/qcwd" || exit 1
out=$(cd "$tmp/qcwd" && TMPDIR=$qdir bash "$REPO_ROOT/scripts/check-shell-mktemp-template.sh" "$root" 2>&1)
rc=$?
if [ -e "$tmp/qcwd/pwned" ]; then
  fail "a quote in TMPDIR ran text from it at exit"
elif [ "$rc" -ne 0 ]; then
  fail "a quote in TMPDIR broke the scan (exit $rc): $out"
elif [ -n "$(ls -A "$qdir")" ]; then
  fail "the scratch directory under a quoted TMPDIR was left behind"
else
  pass "a quote in TMPDIR is only a path to the cleanup trap"
fi

out=$(bash "$REPO_ROOT/scripts/check-shell-mktemp-template.sh" --bogus 2>&1)
if [ $? -eq 2 ]; then
  pass "an unknown option is a usage error"
else
  fail "an unknown option was accepted: $out"
fi

out=$(bash "$REPO_ROOT/scripts/check-shell-mktemp-template.sh" "$root" extra 2>&1)
if [ $? -eq 2 ]; then
  pass "a second operand is a usage error"
else
  fail "a second operand was accepted: $out"
fi

# engine_case <description> <rule> <want> <line>... — scans the lines as
# scripts/a.sh; <want> is the one line the rule must flag, or `exit2`.
engine_case() {
  ec_desc=$1 ec_rule=$2 ec_want=$3
  shift 3
  fresh_root "$root"
  printf '%s\n' "$@" >"$root/scripts/a.sh"
  run_rule "$ec_rule" "$root"
  if [ "$ec_want" = clean ]; then
    if [ "$rc" -eq 0 ]; then pass "$ec_desc"; else fail "$ec_desc (exit $rc): $out"; fi
    return
  fi
  if [ "$ec_want" = exit2 ]; then
    if [ "$rc" -eq 2 ]; then pass "$ec_desc"; else fail "$ec_desc (exit $rc): $out"; fi
    return
  fi
  n=$(printf '%s\n' "$out" | grep -c "^check-$ec_rule: ")
  case "$rc:$n:$out" in
    1:1:*"scripts/a.sh:$ec_want: "*) pass "$ec_desc" ;;
    *) fail "$ec_desc (exit $rc, $n reports, want line $ec_want): $out" ;;
  esac
}

engine_case "a trailing reasonless annotation exempts nothing" shell-mktemp-template 1 \
  'f=$(mktemp) || exit 2 # shell-mktemp-template:'
engine_case "a backslash continuation is one logical line, reported at its start" shell-mktemp-template 1 \
  'f=$(mktemp \' '  -d) || exit 2'
engine_case "a <<- heredoc body is skipped up to its tab-indented end" shell-mktemp-template 5 \
  'cat <<-EOF' '	mktemp' '	EOF' 'true' 'f=$(mktemp) || exit 2'
engine_case "a CRLF file is read as its lines" shell-mktemp-template 2 \
  $'true\r' $'f=$(mktemp) || exit 2\r'
engine_case "an arithmetic shift is not a heredoc, so the lines after it are judged" shell-mktemp-template 2 \
  'm=$((1 << 4))' 'f=$(mktemp) || exit 2'
engine_case "\$'...' quoting with an escaped quote leaves the masker in step" shell-mktemp-template 2 \
  "x=\$'it\\'s'" 'f=$(mktemp) || exit 2'
engine_case "a quoted \${...} holding its own quotes across lines leaves the masker in step" shell-mktemp-template 3 \
  'r="${v#*"' '$k"}"' 'f=$(mktemp) || exit 2'
engine_case "a command word ended by ; takes no operands from the next command" shell-mktemp-template 1 \
  'mktemp; echo x'
engine_case "a subshell in a case body keeps its commands" shell-dash-operand 3 \
  'case $x in' '  a)' '    (cd "$1" && make)' '    ;;' 'esac'
engine_case "a trailing pipe continues the pipeline onto the next line" shell-pipe-status 3 \
  'git log |' '  tail -n 1' 'rc=$?'
engine_case "a shift by a name inside \$(( )) is not a heredoc" shell-mktemp-template 2 \
  'x=$((1 << n))' 'f=$(mktemp) || exit 2'
engine_case "a shift inside (( )) is not a heredoc" shell-mktemp-template 2 \
  '(( m = 1 << bit ))' 'f=$(mktemp) || exit 2'
engine_case "a quoted \${...} whose inner quotes hold a } stays in step" shell-mktemp-template 2 \
  'x="${v%"}"}"' 'f=$(mktemp) || exit 2'
engine_case "a command word ending the line takes no operands from the line" shell-mktemp-template 1 \
  'mktemp'
engine_case "a pipeline continues past a blank and a comment line" shell-pipe-status 5 \
  'git log |' '' '  # keep the last' '  tail -n 1' 'rc=$?'
engine_case "a list continues past a blank and a comment line after a trailing &&" shell-pipe-status 5 \
  'true &&' '' '  # then the pipeline' '  git log | tail -n 1' 'rc=$?'
engine_case "a set +o pipefail ends the pipefail exemption" shell-pipe-status 4 \
  'set -o pipefail' 'set +o pipefail' 'git log | tail -n 1' 'rc=$?'
engine_case "an annotation on a comment line inside a continued pipeline carries" shell-mktemp-template clean \
  'x=$(true |' '  # shell-mktemp-template: a fixture of the carried annotation' '  mktemp)'
engine_case "a quoted line that looks like a comment inside a continuation keeps the quote state" shell-mktemp-template clean \
  'v="${x//a/|' '#}"' 'printf "%s\n" "$v"'
engine_case "a (( inside a parameter default does not hide the heredoc after it" shell-mktemp-template 4 \
  'printf "%s\n" "${a:-((}" && cat <<EOF' 'mktemp' 'EOF' 'f=$(mktemp) || exit 2'
engine_case "an arithmetic shift continued onto the next line opens no heredoc" shell-mktemp-template 3 \
  '(( y = 1 \' '  << n ))' 'f=$(mktemp) || exit 2'
engine_case "a \$'...' never closed fails closed" shell-mktemp-template exit2 \
  "x=\$'open" 'true'
engine_case "a positional default holding a blank is still flagged" shell-dash-operand 1 \
  'mv "${1:-a b}" x'
case "$out" in
  *'takes the positional ${1 with'*) pass "a cut-short positional is named by its head" ;;
  *) fail "a cut-short positional was not named by its head: $out" ;;
esac
engine_case "a heredoc never closed fails closed" shell-mktemp-template exit2 \
  'cat <<EOF' 'body'
engine_case "a quote never closed fails closed" shell-mktemp-template exit2 \
  'x="open' 'true'

fresh_root "$root"
printf '%s\n' 'rmdir "$1/empty"' >"$root/scripts/a.sh"
run_rule shell-dash-operand "$root"
case "$out" in
  *'takes the positional $1 with'*) pass "a report names the positional parameter, not the masked word" ;;
  *) fail "a report did not name the positional alone: $out" ;;
esac

fresh_root "$root"
printf 'cd ${1:-\033[2J}\n' >"$root/scripts/a.sh"
run_rule shell-dash-operand "$root"
case "$rc:$out" in
  *"$(printf '\033')"*) fail "a control byte from the scanned file reached the report" ;;
  1:*) pass "a report quoting the scanned file is stripped of control bytes" ;;
  *) fail "the control-byte case was not flagged (exit $rc): $out" ;;
esac

fresh_root "$root"
printf '%s\n' 'true' >"$root/scripts/a.sh"
mkdir -p "$tmp/elsewhere"
ln -s "$tmp/elsewhere" "$root/scripts/linked"
run_rule shell-mktemp-template "$root"
if [ "$rc" -eq 2 ]; then
  pass "a symlinked directory in scope fails closed rather than being followed"
else
  fail "a symlinked directory in scope exited $rc: $out"
fi

fresh_root "$root"
printf '%s\n' 'true' >"$root/scripts/a.sh"
printf '%s\n' 'true' >"$root/scripts/$(printf 'new\nline').sh"
run_rule shell-mktemp-template "$root"
if [ "$rc" -eq 2 ]; then
  pass "a filename holding a newline fails closed"
else
  fail "a filename holding a newline exited $rc: $out"
fi

fresh_root "$root"
printf '%s\n' 'true' >"$root/scripts/a.sh"
ln -s /dev/null "$root/scripts/dev.sh"
run_rule shell-mktemp-template "$root"
if [ "$rc" -eq 2 ]; then
  pass "a symlink to a device fails closed rather than being read"
else
  fail "a symlink to a device exited $rc: $out"
fi

fresh_root "$root"
printf '%s\n' 'f=$(mktemp) || exit 2' >"$root/scripts/a.sh"
mkdir -p "$tmp/back\\nslash" || exit 1
out=$(TMPDIR="$tmp/back\\nslash" bash "$REPO_ROOT/scripts/check-shell-mktemp-template.sh" "$root" 2>&1)
rc=$?
case "$rc:$out" in
  1:*"scripts/a.sh:1: "*) pass "a backslash in TMPDIR reaches the scanner as a literal path" ;;
  *) fail "a backslash in TMPDIR broke the scan (exit $rc): $out" ;;
esac

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
  # The run line must sit inside the rule's own task block, not anywhere.
  if awk -v t="[tasks.\"check:$rule\"]" -v r="run = \"/bin/bash scripts/check-$rule.sh\"" '
    /^\[/ { on = ($0 == t) }
    on && $0 == r { f = 1 }
    END { exit !f }
  ' "$MISE" && grep -q "^  \"check:$rule\",$" "$MISE"; then
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
