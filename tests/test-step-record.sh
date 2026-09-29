#!/bin/sh
# Tests for scripts/step-record.sh — the custom-steps record helper
# (custom-steps Task 4; REQ-D1.5, REQ-E1.2, REQ-H1.3; D-12, D-16).
#
# Every fixture lives under a temporary directory: a fixture worktree (a git
# repository, so `regenerate` has a range to read) holding the record cache.
# The one case that reads a shipped file is the ignore check, which asks this
# repository's own ignore list about the cache path.
#
# Runs standalone under /bin/sh (the bash 3.2 / dash floor):
#   ./tests/test-step-record.sh
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$here/.." && pwd)
SR="$repo_root/scripts/step-record.sh"
GOLDEN="$here/fixtures/step-record/checklist.golden"
TAB=$(printf '\t')

# The built-in screen, so the outcome does not depend on whether this host
# has gitleaks installed.
PLANWRIGHT_SECRET_SCREEN_TOOL=none
export PLANWRIGHT_SECRET_SCREEN_TOOL

failures=0
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}
ok() { echo "ok: $1"; }
# verdict <ok-message> <fail-message>: judged on the exit status of the
# command that precedes the call.
verdict() {
  if [ $? -eq 0 ]; then
    ok "$1"
  else
    fail "$2"
  fi
}

[ -x "$SR" ] || {
  echo "FAIL: scripts/step-record.sh missing or not executable" >&2
  exit 1
}

tmp="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/test-step-record.XXXXXX")" && pwd -P)" || exit 1
trap 'rm -rf "$tmp"' EXIT

wt="$tmp/wt"
mkdir -p "$wt"
git -C "$wt" init -q -b main
git -C "$wt" config user.name "Fixture"
git -C "$wt" config user.email "fixture@example.invalid"
git -C "$wt" config commit.gpgsign false
printf 'base\n' >"$wt/file.txt"
git -C "$wt" add file.txt
git -C "$wt" commit -q -m "chore: base"
HEAD_SHA=$(git -C "$wt" rev-parse HEAD)

sr() { "$SR" --worktree "$wt" "$@"; }

# --- new-run -------------------------------------------------------------------
run1=$(sr new-run)
printf '%s\n' "$run1" | grep -Eq '^[0-9]{6}$'
verdict "new-run issues a six-digit run id" "new-run printed '$run1'"
[ -d "$wt/.claude/steps/$run1" ]
verdict "new-run creates the run directory under the cache" "no $wt/.claude/steps/$run1"
run2=$(sr new-run)
[ "$((1$run2))" -gt "$((1$run1))" ]
verdict "a later run id sorts after an earlier one" "run ids '$run1' then '$run2'"

# --- write + list round trip -----------------------------------------------------
printf 'line one\nline two\n' >"$tmp/out1.txt"
mkdir -p "$wt/.claude/steps/$run1"
cp "$tmp/out1.txt" "$wt/.claude/steps/$run1/polish.out"
rec=$(sr write --run "$run1" --point convergence --step polish --kind skill \
  --target polish --hosting isolated --backend terminal --session sess-42 \
  --head "$HEAD_SHA" --start 2026-09-28T10:00:00Z --end 2026-09-28T10:05:00Z \
  --outcome applied --excerpt-file "$tmp/out1.txt" \
  --output "$wt/.claude/steps/$run1/polish.out")
rc=$?
[ "$rc" -eq 0 ] && [ -f "$rec" ]
verdict "write prints the new record's path" "write rc=$rc path='$rec'"

listing=$(sr list --run "$run1")
for pair in "type${TAB}step" "run${TAB}$run1" "point${TAB}convergence" \
  "step${TAB}polish" "kind${TAB}skill" "target${TAB}polish" \
  "hosting${TAB}isolated" "backend${TAB}terminal" "session${TAB}sess-42" \
  "head${TAB}$HEAD_SHA" "start${TAB}2026-09-28T10:00:00Z" \
  "end${TAB}2026-09-28T10:05:00Z" "outcome${TAB}applied" \
  "output${TAB}.claude/steps/$run1/polish.out" \
  "excerpt${TAB}line one" "excerpt${TAB}line two"; do
  printf '%s\n' "$listing" | grep -Fxq "$pair"
  verdict "list round-trips '$pair'" "list lacks '$pair'"
done

sr write --completion --run "$run1" --point convergence --head "$HEAD_SHA" \
  --warning "steps_convergence is also set at the adopter layer" >/dev/null
verdict "write --completion succeeds" "write --completion failed"
listing=$(sr list --run "$run1")
printf '%s\n' "$listing" | grep -Fxq "type${TAB}completion"
verdict "list shows the completion record" "no completion record listed"
printf '%s\n' "$listing" | grep -Fxq "warning${TAB}steps_convergence is also set at the adopter layer"
verdict "list round-trips the completion warning" "completion warning missing"

# --- render: every field ----------------------------------------------------------
table=$(sr render --run "$run1")
printf '%s\n' "$table" | grep -Fq "## Steps at \`convergence\` (run \`$run1\`)"
verdict "render heads the table with the point and run id" "render heading missing"
row=$(printf '%s\n' "$table" | grep '^| 1 |')
for cell in polish skill isolated terminal sess-42 "$(printf '%s' "$HEAD_SHA" | cut -c1-12)" \
  2026-09-28T10:00:00Z 2026-09-28T10:05:00Z applied "line one / line two" \
  ".claude/steps/$run1/polish.out"; do
  case $row in
    *"$cell"*) ok "rendered row carries '$cell'" ;;
    *) fail "rendered row lacks '$cell': $row" ;;
  esac
done
printf '%s\n' "$table" | grep -Fq "Ended on \`$(printf '%s' "$HEAD_SHA" | cut -c1-12)\`"
verdict "render names the head the point ended on" "no ended-on line"
printf '%s\n' "$table" | grep -Fq -- '- Warning: steps\_convergence is also set at the adopter layer'
verdict "render carries the point's warnings" "warning not rendered"

# --- excerpt screening --------------------------------------------------------------
tok="ghp_$(printf 'a%.0s' 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36)"
printf 'deploying\ntoken is %s\n' "$tok" >"$tmp/secret.txt"
sr write --run "$run2" --point pre-ci --step lint --kind command --target lint \
  --hosting isolated --backend runner --head "$HEAD_SHA" \
  --start 2026-09-28T11:00:00Z --end 2026-09-28T11:00:01Z --outcome failed \
  --excerpt-file "$tmp/secret.txt" >/dev/null
verdict "write accepts an excerpt carrying a token" "write refused the token excerpt"
if grep -rFq "$tok" "$wt/.claude/steps/$run2"; then
  fail "the token reached the stored record"
else
  ok "the stored record never carries the token"
fi
sr render --run "$run2" | grep -Fq "withheld: the secret screen flagged this excerpt"
verdict "a token-shaped excerpt renders withheld" "token excerpt not withheld"

esc=$(printf '\033')
bel=$(printf '\007')
# shellcheck disable=SC2016 # literal backticks are the fixture
printf 'red %s[31mtext%s end\na | b @alice fixes #7 <b>x</b> https://example.com `code`\n' "$esc" "$bel" >"$tmp/ctl.txt"
sr write --run "$run2" --point pre-ci --step fmt --kind command --target fmt \
  --hosting isolated --backend runner --head "$HEAD_SHA" \
  --start 2026-09-28T11:01:00Z --end 2026-09-28T11:01:01Z --outcome passed \
  --excerpt-file "$tmp/ctl.txt" >/dev/null
if grep -rq "$esc\|$bel" "$wt/.claude/steps/$run2"; then
  fail "a control byte reached the stored record"
else
  ok "control bytes are stripped before storage"
fi
row=$(sr render --run "$run2" --point pre-ci | grep '^| 2 |')
case $row in
  *'a \| b'*) ok "a pipe renders escaped" ;;
  *) fail "pipe not escaped: $row" ;;
esac
# shellcheck disable=SC2016 # literal backticks in the pattern
case $row in
  *'&#64;alice'*'&#35;7'*'&lt;b&gt;'*'https:&#47;&#47;'*'\`code\`'*) ok "mentions, issue refs, markup, and links render neutralized" ;;
  *) fail "neutralization missing: $row" ;;
esac
cells=$(printf '%s\n' "$row" | sed 's/\\|//g' | tr -cd '|' | wc -c | tr -d ' ')
[ "$cells" -eq 14 ]
verdict "an escaped row keeps its column count" "row has $cells pipes: $row"

# The length bound: a long output keeps only its tail.
i=0
: >"$tmp/long.txt"
while [ "$i" -lt 200 ]; do
  printf 'output line %03d with some padding to make it longer\n' "$i" >>"$tmp/long.txt"
  i=$((i + 1))
done
recl=$(sr write --run "$run2" --point pre-ci --step long --kind command --target long \
  --hosting isolated --backend runner --head "$HEAD_SHA" \
  --start 2026-09-28T11:02:00Z --end 2026-09-28T11:02:01Z --outcome passed \
  --excerpt-file "$tmp/long.txt")
n=$(grep -c "^excerpt${TAB}" "$recl")
bytes=$(grep "^excerpt${TAB}" "$recl" | wc -c | tr -d ' ')
[ "$n" -le 20 ] && [ "$bytes" -le 2400 ] && grep -Fq "output line 199" "$recl" \
  && ! grep -Fq "output line 000" "$recl"
verdict "a long excerpt keeps only its bounded tail" "bound not applied: $n lines, $bytes bytes"

# --- skipped and none -------------------------------------------------------------
sr write --run "$run2" --point pre-pr --step extra --kind command --target extra \
  --hosting isolated --backend runner --head "$HEAD_SHA" \
  --start 2026-09-28T11:03:00Z --end 2026-09-28T11:03:00Z --outcome skipped \
  --skip-reason "requires executable not on PATH" >/dev/null
verdict "write accepts a skipped record with a reason" "skipped write failed"
sr render --run "$run2" --point pre-pr | grep '^| 1 |' \
  | grep -Fq "skipped: requires executable not on PATH"
verdict "a record with a skip reason renders as skipped" "skip not rendered"

sr write --run "$run2" --point pre-pr --step extra2 --kind command --target extra \
  --hosting isolated --backend runner --head "$HEAD_SHA" \
  --start 2026-09-28T11:03:00Z --end 2026-09-28T11:03:00Z --outcome skipped \
  2>/dev/null >/dev/null
[ $? -eq 2 ]
verdict "a skipped record without a reason is refused" "reasonless skip accepted"

sr write --completion --run "$run2" --point post-pr --head "$HEAD_SHA" \
  --warning "steps_post_pr set at the machine-local layer | shadowed" >/dev/null
none=$(sr render --run "$run2" --point post-pr)
printf '%s\n' "$none" | grep -Eq '^\| none \|( \|){12}$'
verdict "a point with only a completion record renders its none row" "no none row: $none"
printf '%s\n' "$none" | grep -Fq -- '- Warning: steps\_post\_pr set at the machine-local layer \| shadowed'
verdict "the none row keeps its warnings, table-safe" "warning missing on none table"

# --- validation refusals -------------------------------------------------------------
refuse() {
  # refuse <label> <field-name> <args...>: write must exit 2, name the field,
  # and never echo the rejected value.
  label=$1
  field=$2
  shift 2
  err=$(sr write "$@" 2>&1 >/dev/null)
  rc=$?
  if [ "$rc" -eq 2 ] && printf '%s' "$err" | grep -Fq -- "$field" \
    && ! printf '%s' "$err" | grep -Fq "EVIL"; then
    ok "write refuses $label"
  else
    fail "write $label: rc=$rc err=$err"
  fi
}
base_args="--run $run2 --kind command --target t --hosting isolated --backend runner --head $HEAD_SHA --start 2026-09-28T11:00:00Z --end 2026-09-28T11:00:00Z --outcome passed"
# shellcheck disable=SC2086 # base_args is a fixed word list
refuse "an unknown point" "--point" $base_args --point EVILpoint --step s
# shellcheck disable=SC2086
refuse "a malformed step id" "--step" $base_args --point pre-ci --step "EVIL/../x"
# shellcheck disable=SC2086
refuse "the reserved implementation id" "--step" $base_args --point pre-ci --step implementation
# shellcheck disable=SC2086
refuse "a target carrying a newline" "--target" --run "$run2" --point pre-ci --step s \
  --kind command --target "EVIL
x" --hosting isolated --backend runner --head "$HEAD_SHA" \
  --start 2026-09-28T11:00:00Z --end 2026-09-28T11:00:00Z --outcome passed
# shellcheck disable=SC2086
refuse "an output path outside the worktree" "--output" $base_args --point pre-ci \
  --step s --output "/etc/EVIL"
# shellcheck disable=SC2086
refuse "an unknown outcome" "--outcome" --run "$run2" --point pre-ci --step s \
  --kind command --target t --hosting isolated --backend runner --head "$HEAD_SHA" \
  --start 2026-09-28T11:00:00Z --end 2026-09-28T11:00:00Z --outcome EVIL
# shellcheck disable=SC2086
refuse "an unissued run id" "--run" --run 999999 --point pre-ci --step s \
  --kind command --target t --hosting isolated --backend runner --head "$HEAD_SHA" \
  --start 2026-09-28T11:00:00Z --end 2026-09-28T11:00:00Z --outcome passed

# --- the fixture PR body -------------------------------------------------------------
{
  printf '## Summary\n\nFixture.\n\n<details>\n<summary>Audit record</summary>\n\n'
  sr render --run "$run1"
  printf '\n</details>\n'
} >"$tmp/body.md"
awk '/^<details>/{d=1} /^<\/details>/{d=0} /^\| 1 \| polish \|/{ if (d) found=1 } END{exit found ? 0 : 1}' "$tmp/body.md"
verdict "the rendered table sits inside the collapsed audit block" "table outside <details>"

# --- regenerate against the golden checklist --------------------------------------
BASE=$(git -C "$wt" rev-parse HEAD)
commit() {
  # commit <message>: an empty commit carrying the message verbatim.
  git -C "$wt" commit -q --allow-empty -F - <<EOF
$1
EOF
  git -C "$wt" rev-parse --short=7 HEAD
}
C1=$(commit "fix(stamp): reword the degraded case

Route reason: meaning-class prose, pre-existing surface

Planwright-Sign-Off: PS-1")
commit "fix(x): a fix later reverted

Route reason: behaviour change

Planwright-Sign-Off: PS-2" >/dev/null
C2FULL=$(git -C "$wt" rev-parse HEAD)
commit "Revert \"fix(x): a fix later reverted\"

This reverts commit $C2FULL." >/dev/null
C4=$(commit "docs(guide): two prose fixes @someone fixes #12

Route reason: meaning-class prose on surfaces that predate the PR

- \`docs/a.md\` — before: absent · after: the rule
- \`docs/b.md\` — before: the old rule · after: the new rule

Planwright-Sign-Off: PS-3")
commit "fix(y): a fix later rejected

Route reason: public contract

Planwright-Sign-Off: PS-4" >/dev/null
C6=$(commit "fix(old): a legacy-marked fix [pending-sign-off]")
commit "chore: reject one item

Planwright-Sign-Off-Rejected: PS-4" >/dev/null
commit "chore: an unmarked commit" >/dev/null
HEAD2=$(git -C "$wt" rev-parse HEAD)

sed -e "s/@C1@/$C1/g" -e "s/@C4@/$C4/g" -e "s/@C6@/$C6/g" "$GOLDEN" >"$tmp/expected.md"
sr regenerate --base "$BASE" --head "$HEAD2" --run "$run1" >"$tmp/regen.md"
verdict "regenerate succeeds over the fixture range" "regenerate failed"
awk '/^## Steps at /{exit} {print}' "$tmp/regen.md" | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}' >"$tmp/regen-checklist.md"
if diff -u "$tmp/expected.md" "$tmp/regen-checklist.md" >"$tmp/diff.out"; then
  ok "regenerate reproduces the golden checklist"
else
  fail "regenerate differs from the golden checklist:"
  cat "$tmp/diff.out" >&2
fi
grep -Fq "## Steps at \`convergence\` (run \`$run1\`)" "$tmp/regen.md"
verdict "regenerate re-emits the per-point tables from the records" "no step tables after the checklist"

empty=$(sr regenerate --base "$HEAD2" --head "$HEAD2" --run "$run1")
printf '%s\n' "$empty" | grep -Fxq -- "- none"
verdict "an empty range emits the checklist's none row" "no none row for an empty range"

sr regenerate --base no-such-ref --head "$HEAD2" >/dev/null 2>"$tmp/err"
rc=$?
[ "$rc" -eq 1 ] && grep -Fq -- "--base" "$tmp/err"
verdict "an unresolvable range fails by name" "rc=$rc err=$(cat "$tmp/err")"

# --- the cache path is ignored ------------------------------------------------------
git -C "$repo_root" check-ignore -q ".claude/steps/000001/x.rec"
verdict "this repository ignores the record cache" ".claude/steps/ is not ignored"

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all step-record tests passed"
