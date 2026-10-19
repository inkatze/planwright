#!/bin/sh
# Tests for scripts/step-record.sh — the custom-steps record helper
# (custom-steps Tasks 4 and 13; REQ-D1.5, REQ-D1.10, REQ-D1.12, REQ-E1.2,
# REQ-E1.6, REQ-H1.3, REQ-I1.5, REQ-I1.7–I1.10, REQ-J1.1, REQ-J1.2; D-12,
# D-16, D-25–D-27, D-31, D-32).
#
# Every fixture lives under a temporary directory: a fixture worktree (a git
# repository, so `regenerate` has a range to read) holding the record cache.
# The shipped files it reads are the golden checklist fixture and this
# repository's own ignore list, asked about the cache path.
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
  printf '%s\n' "FAIL: $1" >&2
  failures=$((failures + 1))
}
ok() { printf '%s\n' "ok: $1"; }
# verdict <ok-message> <fail-message>: judged on the exit status of the
# command that precedes the call.
verdict() {
  if [ $? -eq 0 ]; then
    ok "$1"
  else
    fail "$2"
  fi
}
# verdict_of <status> <ok-message> <fail-message>: the same, judged on a status
# passed in, for a fail message that runs a command substitution. Expanding the
# substitution resets $? under bash before verdict could read it; $? as the
# first word expands before the substitution runs.
verdict_of() {
  if [ "$1" -eq 0 ]; then
    ok "$2"
  else
    fail "$3"
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
cp "$tmp/out1.txt" "$wt/.claude/steps/$run1/polish.out"
rec=$(sr write --run "$run1" --point convergence --step polish --kind skill \
  --target planwright:polish --hosting isolated --backend terminal --session sess-42 \
  --head "$HEAD_SHA" --start 2026-09-28T10:00:00Z --end 2026-09-28T10:05:00Z \
  --outcome applied --excerpt-file "$tmp/out1.txt" \
  --output "$wt/.claude/steps/$run1/polish.out")
rc=$?
[ "$rc" -eq 0 ] && [ -f "$rec" ]
verdict "write prints the new record's path" "write rc=$rc path='$rec'"

listing=$(sr list --run "$run1")
for pair in "type${TAB}step" "run${TAB}$run1" "point${TAB}convergence" \
  "step${TAB}polish" "kind${TAB}skill" "target${TAB}planwright:polish" \
  "hosting${TAB}isolated" "backend${TAB}terminal" "session${TAB}sess-42" \
  "head${TAB}$HEAD_SHA" "start${TAB}2026-09-28T10:00:00Z" \
  "end${TAB}2026-09-28T10:05:00Z" "outcome${TAB}applied" \
  "output${TAB}.claude/steps/$run1/polish.out" \
  "excerpt${TAB}line one" "excerpt${TAB}line two" "seq${TAB}001" \
  "skip-reason${TAB}"; do
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
h12=$(printf '%s' "$HEAD_SHA" | cut -c1-12)
want="| 1 | polish | skill | planwright:polish | isolated | terminal | sess-42 | $h12 | 2026-09-28T10:00:00Z | 2026-09-28T10:05:00Z | applied | line one / line two | .claude/steps/$run1/polish.out |"
[ "$row" = "$want" ]
verdict "the rendered row carries every field in column order" "row: $row"
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

recp=$(sr write --run "$run2" --point pre-ci --step prompted --kind prompt \
  --target "review with $tok" --hosting isolated --backend runner --head "$HEAD_SHA" \
  --start 2026-09-28T11:00:00Z --end 2026-09-28T11:00:01Z --outcome passed)
if [ ! -f "$recp" ] || grep -rFq "$tok" "$wt/.claude/steps/$run2"; then
  fail "a token in a target reached the stored record"
else
  ok "a token in a target is withheld before storage"
fi

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
row=$(sr render --run "$run2" --point pre-ci | grep '^| 3 |')
case $row in
  *'a \| b'*) ok "a pipe renders escaped" ;;
  *) fail "pipe not escaped: $row" ;;
esac
# shellcheck disable=SC2016 # literal backticks in the pattern
case $row in
  *'@&#8203;alice'*'#&#8203;7'*'&lt;b&gt;'*'https:/&#8203;/'*'\`code\`'*) ok "mentions, issue refs, markup, and links render neutralized" ;;
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
[ "$n" -le 20 ] && [ "$bytes" -le 2200 ] && grep -Fq "output line 199" "$recl" \
  && ! grep -Fq "output line 000" "$recl"
verdict "a long excerpt keeps only its bounded tail" "bound not applied: $n lines, $bytes bytes"

# --- skipped and none -------------------------------------------------------------
sr write --run "$run2" --point pre-pr --step extra --kind command --target extra \
  --hosting isolated --backend runner --head "$HEAD_SHA" \
  --start 2026-09-28T11:03:00Z --end 2026-09-28T11:03:00Z --outcome skipped \
  --skip-code missing --skip-reason "requires executable not on PATH" >/dev/null
verdict "write accepts a skipped record with a reason" "skipped write failed"
sr render --run "$run2" --point pre-pr | grep '^| 1 |' \
  | grep -Fq "skipped: missing \\(requires executable not on PATH\\)"
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
needle=''
refuse() {
  # refuse <label> <field-name> <args...>: write must exit 2, name the field,
  # and never echo the rejected value (EVIL, or $needle when set).
  label=$1
  field=$2
  shift 2
  err=$(sr write "$@" 2>&1 >/dev/null)
  rc=$?
  if [ "$rc" -eq 2 ] && printf '%s' "$err" | grep -Fq -- "step-record.sh: $field:" \
    && ! printf '%s' "$err" | grep -Fq -- "${needle:-EVIL}"; then
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
refuse "a target carrying a newline" "--target" --run "$run2" --point pre-ci --step s \
  --kind command --target "EVIL
x" --hosting isolated --backend runner --head "$HEAD_SHA" \
  --start 2026-09-28T11:00:00Z --end 2026-09-28T11:00:00Z --outcome passed
# shellcheck disable=SC2086
refuse "an output path outside the record cache" "--output" $base_args --point pre-ci \
  --step s --output "/etc/EVIL"
refuse "an unknown outcome" "--outcome" --run "$run2" --point pre-ci --step s \
  --kind command --target t --hosting isolated --backend runner --head "$HEAD_SHA" \
  --start 2026-09-28T11:00:00Z --end 2026-09-28T11:00:00Z --outcome EVIL
refuse "an unissued run id" "--run" --run 999999 --point pre-ci --step s \
  --kind command --target t --hosting isolated --backend runner --head "$HEAD_SHA" \
  --start 2026-09-28T11:00:00Z --end 2026-09-28T11:00:00Z --outcome passed

# --- hardening -------------------------------------------------------------------------
refuse "a backend carrying a newline" "--backend" --run "$run2" --point pre-ci --step s \
  --kind command --target t --hosting isolated --backend "b
typeEVIL" --head "$HEAD_SHA" \
  --start 2026-09-28T11:00:00Z --end 2026-09-28T11:00:00Z --outcome passed
needle=$(printf '%s' "$HEAD_SHA" | cut -c1-12)
refuse "an abbreviated head" "--head" --run "$run2" --point pre-ci --step s \
  --kind command --target t --hosting isolated --backend runner \
  --head "$needle" \
  --start 2026-09-28T11:00:00Z --end 2026-09-28T11:00:00Z --outcome passed
needle=

# A secret the cut would drop out of the kept tail is still caught: the whole
# cleaned output is screened before it is cut.
{
  printf 'password=%s\n' "$(printf 'Q7xR2mK9pL4vN8sT1wY6zB3cF5hJ0dG2aE7uI9oP')"
  i=0
  while [ "$i" -lt 30 ]; do
    printf 'filler line %02d\n' "$i"
    i=$((i + 1))
  done
} >"$tmp/early-secret.txt"
recs=$(sr write --run "$run2" --point pre-ci --step early --kind command --target early \
  --hosting isolated --backend runner --head "$HEAD_SHA" \
  --start 2026-09-28T11:04:00Z --end 2026-09-28T11:04:01Z --outcome passed \
  --excerpt-file "$tmp/early-secret.txt")
grep -Fq "withheld: the secret screen flagged this excerpt" "$recs"
verdict "a secret outside the kept tail still withholds the excerpt" "early secret not caught"

# C1 controls, bidi overrides, and invalid UTF-8 are stripped.
printf 'a\302\233b\342\200\256c\377d\342\200\224e\n' >"$tmp/c1.txt"
recc=$(sr write --run "$run2" --point pre-ci --step c1 --kind command --target c1 \
  --hosting isolated --backend runner --head "$HEAD_SHA" \
  --start 2026-09-28T11:05:00Z --end 2026-09-28T11:05:01Z --outcome passed \
  --excerpt-file "$tmp/c1.txt")
expect=$(printf 'excerpt\tabcd\342\200\224e')
grep -Fxq "$expect" "$recc"
verdict "C1, bidi, and invalid bytes are stripped and UTF-8 text kept" "C1, bidi, or invalid bytes kept in $recc"

# No scratch survives a write, the unscreened excerpt least of all.
mkdir "$tmp/tmpd"
env TMPDIR="$tmp/tmpd" "$SR" --worktree "$wt" write --run "$run2" --point pre-ci --step scratch --kind command \
  --target scratch --hosting isolated --backend runner --head "$HEAD_SHA" \
  --start 2026-09-28T11:06:00Z --end 2026-09-28T11:06:01Z --outcome passed \
  --excerpt-file "$tmp/secret.txt" >/dev/null
rc=$?
left=$(find "$tmp/tmpd" -mindepth 1 | wc -l | tr -d ' ')
[ "$rc" -eq 0 ] && [ "$left" -eq 0 ]
verdict "a write leaves nothing in TMPDIR" "$left entries left in TMPDIR"

# A failure partway writes no record and exits non-zero.
before=$(find "$wt/.claude/steps/$run2" -name '*.rec' | wc -l | tr -d ' ')
env TMPDIR="$tmp/no-such-dir" "$SR" --worktree "$wt" write --run "$run2" --point pre-ci --step nomk --kind command \
  --target nomk --hosting isolated --backend runner --head "$HEAD_SHA" \
  --start 2026-09-28T11:07:00Z --end 2026-09-28T11:07:01Z --outcome passed \
  >/dev/null 2>&1
rc=$?
after=$(find "$wt/.claude/steps/$run2" -name '*.rec' | wc -l | tr -d ' ')
[ "$rc" -eq 1 ] && [ "$before" -eq "$after" ]
verdict "a write that cannot make its scratch exits 1 and writes nothing" "rc=$rc records $before -> $after"

# Records are private, and sequence numbers stay unique under concurrent
# writers.
[ -n "$(find "$recc" -perm 0600)" ]
verdict "a record is mode 0600" "record mode is not 0600"
run3=$(sr new-run)
i=1
while [ "$i" -le 8 ]; do
  sr write --run "$run3" --point pre-implementation --step "c$i" --kind command --target t \
    --hosting isolated --backend runner --head "$HEAD_SHA" \
    --start 2026-09-28T12:00:00Z --end 2026-09-28T12:00:01Z --outcome passed >/dev/null &
  i=$((i + 1))
done
wait
dups=$(sr list --run "$run3" | sed -n "s/^seq${TAB}//p" | sort | uniq -d | wc -l | tr -d ' ')
count=$(sr list --run "$run3" | grep -c "^seq${TAB}")
[ "$dups" -eq 0 ] && [ "$count" -eq 8 ]
verdict "concurrent writers get unique sequence numbers" "$count records, $dups duplicate seqs"

# A point fires once per run.
sr write --completion --run "$run3" --point pre-implementation --head "$HEAD_SHA" >/dev/null
sr write --completion --run "$run3" --point pre-implementation --head "$HEAD_SHA" >/dev/null 2>&1
[ $? -eq 2 ]
verdict "a second completion of a point in one run is refused" "second completion accepted"
sr write --run "$run3" --point pre-implementation --step late --kind command --target t \
  --hosting isolated --backend runner --head "$HEAD_SHA" \
  --start 2026-09-28T12:00:00Z --end 2026-09-28T12:00:01Z --outcome passed >/dev/null 2>&1
[ $? -eq 2 ]
verdict "a step record after its point completed is refused" "late step accepted"

# A symlinked cache is refused, never read or written through.
lw="$tmp/linked"
mkdir -p "$lw/.claude" "$tmp/elsewhere"
ln -s "$tmp/elsewhere" "$lw/.claude/steps"
"$SR" --worktree "$lw" new-run >/dev/null 2>&1
[ $? -eq 1 ] && [ -z "$(ls "$tmp/elsewhere")" ]
verdict "a symlinked cache is refused" "symlinked cache used"

# --- more refusals ----------------------------------------------------------------------
long=$(printf 'x%.0s' $(seq 1 1100))
refuse "an unknown kind" "--kind" --run "$run2" --point pre-ci --step s --kind EVIL \
  --target t --hosting isolated --backend runner --head "$HEAD_SHA" \
  --start 2026-09-28T11:00:00Z --end 2026-09-28T11:00:00Z --outcome passed
refuse "an unknown hosting" "--hosting" --run "$run2" --point pre-ci --step s --kind command \
  --target t --hosting EVIL --backend runner --head "$HEAD_SHA" \
  --start 2026-09-28T11:00:00Z --end 2026-09-28T11:00:00Z --outcome passed
refuse "a malformed session" "--session" --run "$run2" --point pre-ci --step s --kind command \
  --target t --hosting isolated --backend runner --session "EVIL session" --head "$HEAD_SHA" \
  --start 2026-09-28T11:00:00Z --end 2026-09-28T11:00:00Z --outcome passed
refuse "a malformed start time" "--start" --run "$run2" --point pre-ci --step s --kind command \
  --target t --hosting isolated --backend runner --head "$HEAD_SHA" \
  --start "2026-09-28 EVIL" --end 2026-09-28T11:00:00Z --outcome passed
refuse "an over-long target" "--target" --run "$run2" --point pre-ci --step s --kind command \
  --target "EVIL$long" --hosting isolated --backend runner --head "$HEAD_SHA" \
  --start 2026-09-28T11:00:00Z --end 2026-09-28T11:00:00Z --outcome passed
refuse "a skip reason on a step that ran" "--skip-reason" --run "$run2" --point pre-ci --step s \
  --kind command --target t --hosting isolated --backend runner --head "$HEAD_SHA" \
  --start 2026-09-28T11:00:00Z --end 2026-09-28T11:00:00Z --outcome passed --skip-reason "EVIL"
refuse "a skipped step with no code" "--skip-code" --run "$run2" --point pre-ci --step s \
  --kind command --target t --hosting isolated --backend runner --head "$HEAD_SHA" \
  --start 2026-09-28T11:00:00Z --end 2026-09-28T11:00:00Z --outcome skipped
refuse "a missing excerpt file" "--excerpt-file" --run "$run2" --point pre-ci --step s \
  --kind command --target t --hosting isolated --backend runner --head "$HEAD_SHA" \
  --start 2026-09-28T11:00:00Z --end 2026-09-28T11:00:00Z --outcome passed \
  --excerpt-file "$tmp/EVIL-missing"
: >"$wt/EVIL-out.txt"
refuse "a relative output outside the cache" "--output" --run "$run2" --point pre-ci --step s \
  --kind command --target t --hosting isolated --backend runner --head "$HEAD_SHA" \
  --start 2026-09-28T11:00:00Z --end 2026-09-28T11:00:00Z --outcome passed \
  --output "EVIL-out.txt"
refuse "step fields on a completion" "--completion" --completion --run "$run2" \
  --point pre-pr --head "$HEAD_SHA" --step EVIL
refuse "a warning on a step" "--warning" --run "$run2" --point pre-ci --step s \
  --kind command --target t --hosting isolated --backend runner --head "$HEAD_SHA" \
  --start 2026-09-28T11:00:00Z --end 2026-09-28T11:00:00Z --outcome passed --warning "EVIL"
"$SR" --worktree "$wt" no-such-verb >/dev/null 2>&1
[ $? -eq 2 ]
verdict "an unknown verb is a usage error" "unknown verb not exit 2"

# A relative output inside the cache resolves against the worktree.
run4=$(sr new-run)
: >"$wt/.claude/steps/$run4/rel.out"
recr=$(sr write --run "$run4" --point pre-pr --step rel --kind command --target t \
  --hosting isolated --backend runner --head "$HEAD_SHA" \
  --start 2026-09-28T13:00:00Z --end 2026-09-28T13:00:01Z --outcome passed \
  --output ".claude/steps/$run4/rel.out")
grep -Fxq "output${TAB}.claude/steps/$run4/rel.out" "$recr"
verdict "a relative output inside the cache is stored worktree-relative" "relative output not stored"

# Skip reasons and warnings pass the screen too; a screen that cannot run
# withholds rather than passes.
recsk=$(sr write --run "$run4" --point pre-pr --step skipped-tok --kind command --target t \
  --hosting isolated --backend runner --head "$HEAD_SHA" \
  --start 2026-09-28T13:00:00Z --end 2026-09-28T13:00:00Z --outcome skipped \
  --skip-code missing --skip-reason "needs $tok")
grep -Fq "skip-reason${TAB}[withheld: the secret screen flagged this value]" "$recsk"
verdict "a token in a skip reason is withheld" "skip reason not withheld"
sr write --completion --run "$run4" --point pre-pr --head "$HEAD_SHA" \
  --warning "layer set $tok" --warning "a plain warning" >/dev/null
if grep -rFq "$tok" "$wt/.claude/steps/$run4"; then
  fail "a token in a skip reason or warning reached the store"
else
  ok "skip reasons and warnings are screened"
fi
grep -Fxq "warning${TAB}a plain warning" "$wt/.claude/steps/$run4/"*-done-pre-pr.rec
verdict "a clean warning beside a flagged one is kept" "clean warning lost"
recu=$(env PLANWRIGHT_SECRET_SCREEN_TOOL=broken "$SR" --worktree "$wt" write --run "$run4" \
  --point pre-ci --step unscreened --kind command --target plain --hosting isolated \
  --backend runner --head "$HEAD_SHA" --start 2026-09-28T13:00:00Z \
  --end 2026-09-28T13:00:00Z --outcome passed --excerpt-file "$tmp/out1.txt")
grep -Fq "withheld: the excerpt could not be screened" "$recu" \
  && grep -Fq "target${TAB}[withheld: the value could not be screened]" "$recu"
verdict "a screen that cannot run withholds every screened value" "unscreened values stored"

# The byte bound and the tab rule.
: >"$tmp/wide.txt"
i=0
while [ "$i" -lt 20 ]; do
  printf 'w%03d\t%s\n' "$i" "$(printf 'y%.0s' $(seq 1 180))" >>"$tmp/wide.txt"
  i=$((i + 1))
done
recw=$(sr write --run "$run4" --point pre-ci --step wide --kind command --target t \
  --hosting isolated --backend runner --head "$HEAD_SHA" \
  --start 2026-09-28T13:00:00Z --end 2026-09-28T13:00:01Z --outcome passed \
  --excerpt-file "$tmp/wide.txt")
wbytes=$(sed -n "s/^excerpt${TAB}//p" "$recw" | wc -c | tr -d ' ')
[ "$wbytes" -le 2000 ] && grep -Fq "w019 y" "$recw" && ! grep -Fq "w000" "$recw"
verdict "the excerpt is cut to its byte bound, tabs as spaces" "$wbytes bytes kept"

# list filters and render ordering.
listed=$(sr list --point pre-pr)
! printf '%s\n' "$listed" | grep -q "^point${TAB}pre-ci$" \
  && printf '%s\n' "$listed" | grep -q "^point${TAB}pre-pr$"
verdict "list --point shows that point only" "list --point leaked another point"
listed=$(sr list)
printf '%s\n' "$listed" | grep -Fq "run${TAB}$run1" \
  && printf '%s\n' "$listed" | grep -Fq "run${TAB}$run4"
verdict "list without --run covers every run" "list missed a run"
headings() { sed -n 's/^## Steps at .\([a-z-]*\). .*/\1/p' | tr '\n' ' '; }
order=$(sr render --run "$run4" | headings)
[ "$order" = "pre-pr pre-ci " ]
verdict "render orders points as they first recorded" "order: $order"
order=$(sr render --run "$run4" --point pre-ci --point pre-pr | headings)
[ "$order" = "pre-ci pre-pr " ]
verdict "render orders named points as given" "order: $order"
bare=$(sr render --run "$run3" --point pre-implementation)
printf '%s\n' "$bare" | grep -Fq "## Steps at" && ! printf '%s\n' "$bare" | grep -Fq -- "- Warning:"
verdict "a completion without warnings renders no warning" "a warning rendered"
[ -n "$(find "$wt/.claude/steps" -maxdepth 0 -perm 0700)" ]
verdict "the cache is mode 0700" "cache mode is not 0700"

# --- iteration-two hardening -----------------------------------------------------------
fresh() {
  # fresh <dir>: a new git worktree with one commit.
  mkdir -p "$1"
  git -C "$1" init -q -b main
  git -C "$1" config user.name Fixture
  git -C "$1" config user.email fixture@example.invalid
  git -C "$1" config commit.gpgsign false
  git -C "$1" commit -q --allow-empty -m "chore: base"
}
w2="$tmp/w2"
fresh "$w2"
sr2() { "$SR" --worktree "$w2" "$@"; }
r=$(sr2 new-run)
args2="--run $r --kind command --target t --hosting isolated --backend runner --head $HEAD_SHA --start 2026-09-28T14:00:00Z --end 2026-09-28T14:00:01Z --outcome passed"

# The grammar edges.
# shellcheck disable=SC2086 # args2 is a fixed word list
sr2 write $args2 --point pre-ci --step edge-a --end "not-a-time" >/dev/null 2>&1
[ $? -eq 2 ]
verdict "a malformed end time is refused" "bad --end accepted"
h64=$(printf '%064d' 0 | tr 0 a)
sr2 write --run "$r" --point pre-ci --step edge-b --kind command --target t --hosting isolated \
  --backend runner --head "$h64" --start 2026-09-28T14:00:00Z --end 2026-09-28T14:00:01Z \
  --outcome passed >/dev/null
verdict "a 64-hex head is accepted" "64-hex head refused"
t1024=$(printf 'x%.0s' $(seq 1 1024))
# shellcheck disable=SC2086
sr2 write $args2 --point pre-ci --step edge-c --target "$t1024" >/dev/null
verdict "a target of exactly the bound is accepted" "1024-byte target refused"
# shellcheck disable=SC2086
sr2 write $args2 --point pre-ci --step edge-d --target "${t1024}x" >/dev/null 2>&1
[ $? -eq 2 ]
verdict "a target one byte over the bound is refused" "1025-byte target accepted"
long65=$(printf 'a%.0s' $(seq 1 65))
# shellcheck disable=SC2086
sr2 write $args2 --point pre-ci --step "$long65" >/dev/null 2>&1
[ $? -eq 2 ]
verdict "a 65-byte step id is refused" "65-byte step id accepted"
sr2 write --completion --run "$r" --point post-pr --head "$HEAD_SHA" --warning "$(printf 'a\033b')" >/dev/null 2>&1
[ $? -eq 2 ]
verdict "a warning carrying a control byte is refused" "control-byte warning accepted"
zw=$(printf '\342\200\213\342\200\256')
# shellcheck disable=SC2086
sr2 write $args2 --point pre-ci --step edge-e --target "$zw" >/dev/null 2>&1
[ $? -eq 2 ]
verdict "a target that cleans to nothing is refused" "invisible-only target accepted"
sr2 regenerate --base -x --head HEAD >/dev/null 2>&1
[ $? -eq 2 ]
verdict "a base beginning with a dash is refused" "dash base accepted"
sr2 regenerate --base HEAD --head -x >/dev/null 2>&1
[ $? -eq 2 ]
verdict "a head beginning with a dash is refused" "dash head accepted"

# The record name never carries the step id.
recn=$(sr2 write --run "$r" --point pre-pr --step xoxb-1234567890abcdefgh --kind command --target t \
  --hosting isolated --backend runner --head "$HEAD_SHA" --start 2026-09-28T14:00:00Z \
  --end 2026-09-28T14:00:01Z --outcome passed)
case $recn in
  *xoxb*) fail "the record path carries the step id: $recn" ;;
  *) ok "the record path carries no step id" ;;
esac
grep -Fq "step${TAB}[withheld: the secret screen flagged this value]" "$recn"
verdict "a token-shaped step id is withheld in the record" "step id not withheld"

# Cleaning edges: CR and DEL dropped, a join formed by one deletion caught on
# the next pass, a character the byte cut splits dropped.
printf 'a\rb\177c\342\200\342\200\213\213d\n' >"$tmp/edge.txt"
rece=$(sr2 write --run "$r" --point pre-ci --step edge-f --kind command --target t \
  --hosting isolated --backend runner --head "$HEAD_SHA" --start 2026-09-28T14:00:00Z \
  --end 2026-09-28T14:00:01Z --outcome passed --excerpt-file "$tmp/edge.txt")
grep -Fxq "excerpt${TAB}abcd" "$rece"
verdict "CR, DEL, and a joined invisible are stripped" "CR, DEL, or a joined invisible kept in $rece"
{
  printf '\342\202\254'
  printf 'z%.0s' $(seq 1 1998)
  printf '\n'
} >"$tmp/cut.txt"
recx=$(sr2 write --run "$r" --point pre-ci --step edge-g --kind command --target t \
  --hosting isolated --backend runner --head "$HEAD_SHA" --start 2026-09-28T14:00:00Z \
  --end 2026-09-28T14:00:01Z --outcome passed --excerpt-file "$tmp/cut.txt")
sed -n "s/^excerpt${TAB}//p" "$recx" | iconv -f UTF-8 -t UTF-8 >/dev/null 2>&1
verdict "a character the byte cut splits is dropped" "the cut left invalid UTF-8"

# Neutralizing edges.
: >"$w2/.claude/steps/$r/n.out"
# shellcheck disable=SC2016 # literal markup is the fixture
recm=$(sr2 write --run "$r" --point pre-pr --step edge-h --kind command \
  --target '1. a & b www.x.io GH-3 \ *s* ~t~ !i $m$ +p' --hosting isolated --backend runner \
  --head "$HEAD_SHA" --start 2026-09-28T14:00:00Z --end 2026-09-28T14:00:01Z --outcome passed)
row=$(sr2 render --run "$r" --point pre-pr | grep '^| 2 |')
# shellcheck disable=SC2016 # literal markup in the pattern
case $row in
  *'| 1\. a &amp; b www&#8203;.x.io GH&#8203;-3 \\ \*s\* \~t\~ \!i \$m\$ \+p |'*) ok "leading numbers, &, www., GH-, and markup are neutralized" ;;
  *) fail "neutralizing edge: $row" ;;
esac
[ -n "$recm" ]
verdict "the neutralizing fixture was written" "fixture write failed"

# An output path carrying invisible characters is refused.
bad_out="$w2/.claude/steps/$r/out$(printf '\342\200\256')x.log"
: >"$bad_out"
# shellcheck disable=SC2086
sr2 write $args2 --point pre-ci --step edge-i --output "$bad_out" >/dev/null 2>&1
[ $? -eq 2 ]
verdict "an output path carrying invisible characters is refused" "bidi output path accepted"

# Records are read as untrusted: control bytes planted in a record do not
# reach list or render.
recz=$(sr2 write --run "$r" --point pre-implementation --step edge-j --kind command --target t \
  --hosting isolated --backend runner --head "$HEAD_SHA" --start 2026-09-28T14:00:00Z \
  --end 2026-09-28T14:00:01Z --outcome passed)
printf 'excerpt\t\033[31mred\n' >>"$recz"
if sr2 list --run "$r" | grep -q "$esc" || sr2 render --run "$r" | grep -q "$esc"; then
  fail "a planted control byte reached list or render"
else
  ok "list and render drop control bytes a record carries"
fi

# A point named twice renders once; --checklist-only renders no tables.
twice=$(sr2 render --run "$r" --point pre-pr --point pre-pr | grep -c '^## Steps at')
[ "$twice" -eq 1 ]
verdict "a point named twice renders once" "$twice tables"
only=$(sr2 regenerate --base HEAD --head HEAD --checklist-only)
printf '%s\n' "$only" | grep -q '^## Pending sign-off' && ! printf '%s\n' "$only" | grep -q '^## Steps at'
verdict "--checklist-only renders the checklist alone" "--checklist-only rendered tables"

# The point vocabulary matches the resolver's.
vocab=$(sed -n 's/^\(UN\)\{0,1\}WIRED_POINTS="\(.*\)"$/\2/p' "$repo_root/scripts/resolve-steps.sh" | tr ' ' '\n')
[ "$(printf '%s\n' "$vocab" | grep -c .)" -eq 15 ]
verdict "the resolver's vocabulary reads as fifteen points" "resolver vocabulary unreadable"
for p in $vocab; do
  sr2 list --point "$p" >/dev/null 2>&1 || fail "step-record refuses the resolver's point $p"
done
ok "every resolver point is a step-record point"

# Completions race to one winner, and no step record lands after it.
r5=$(sr2 new-run)
i=1
while [ "$i" -le 4 ]; do
  sr2 write --completion --run "$r5" --point pre-ci --head "$HEAD_SHA" --warning "w$i" >/dev/null 2>&1 &
  sr2 write --run "$r5" --point pre-ci --step "s$i" --kind command --target t --hosting isolated \
    --backend runner --head "$HEAD_SHA" --start 2026-09-28T14:00:00Z --end 2026-09-28T14:00:01Z \
    --outcome passed >/dev/null 2>&1 &
  i=$((i + 1))
done
wait
names=$(find "$w2/.claude/steps/$r5" -name '[0-9]*.rec' | sed 's#.*/##' | sort | tr '\n' ' ')
ndone=$(printf '%s' "$names" | tr ' ' '\n' | grep -c 'done')
last=$(printf '%s' "$names" | tr ' ' '\n' | grep . | tail -n 1)
[ "$ndone" -eq 1 ] && case $last in *-done-pre-ci.rec) true ;; *) false ;; esac
verdict "one completion wins and sorts after every step" "records: $names"

# Refusals of the cache itself.
w3="$tmp/w3"
fresh "$w3"
mkdir -p "$tmp/real-claude"
ln -s "$tmp/real-claude" "$w3/.claude"
"$SR" --worktree "$w3" new-run >/dev/null 2>&1
[ $? -eq 1 ]
verdict "a symlinked .claude is refused" "symlinked .claude used"
w4="$tmp/w4"
fresh "$w4"
r4=$("$SR" --worktree "$w4" new-run)
ln -s /etc/hosts "$w4/.claude/steps/$r4/001-done-pre-ci.rec"
"$SR" --worktree "$w4" render --run "$r4" >/dev/null 2>&1
[ $? -eq 1 ]
verdict "a symlinked record is refused" "symlinked record read"
rm -f "$w4/.claude/steps/$r4/001-done-pre-ci.rec"
: >"$tmp/target.out"
ln -s "$tmp/target.out" "$w4/.claude/steps/$r4/link.out"
"$SR" --worktree "$w4" write --run "$r4" --point pre-ci --step s --kind command --target t \
  --hosting isolated --backend runner --head "$HEAD_SHA" --start 2026-09-28T14:00:00Z \
  --end 2026-09-28T14:00:01Z --outcome passed --output "$w4/.claude/steps/$r4/link.out" >/dev/null 2>&1
[ $? -eq 2 ]
verdict "a symlinked output is refused" "symlinked output accepted"
git -C "$w4" add -f ".claude/steps/$r4/link.out" >/dev/null 2>&1
"$SR" --worktree "$w4" list >/dev/null 2>&1
[ $? -eq 1 ]
verdict "a cache git tracks is refused" "tracked cache read"
w5="$tmp/w5"
fresh "$w5"
mkdir -p "$w5/.claude/steps/999999"
"$SR" --worktree "$w5" new-run >/dev/null 2>&1
[ $? -eq 1 ]
verdict "an exhausted run-id counter exits 1" "run id issued past 999999"
mkdir "$w5/.claude/steps/999999/.seq-999"
"$SR" --worktree "$w5" write --completion --run 999999 --point pre-ci --head "$HEAD_SHA" >/dev/null 2>&1
[ $? -eq 1 ]
verdict "an exhausted record counter exits 1" "record written past seq 999"

# An excerpt of nothing but invalid UTF-8 is stored empty, not refused.
printf '\377\376' >"$tmp/invalid.txt"
sr2 write --run "$r" --point pre-ci --step edge-k --kind command --target t --hosting isolated \
  --backend runner --head "$HEAD_SHA" --start 2026-09-28T14:00:00Z --end 2026-09-28T14:00:01Z \
  --outcome passed --excerpt-file "$tmp/invalid.txt" >/dev/null
verdict "an all-invalid excerpt still writes its record" "all-invalid excerpt refused"

# A completion that fails before its record exists leaves nothing claimed.
shim="$tmp/shim"
mkdir -p "$shim"
# Only the record's hard link fails; the cache lock's symlink still goes through.
# shellcheck disable=SC2016 # the shim's own $1 and $@, expanded when it runs
printf '#!/bin/sh\n[ "$1" = -s ] && exec "%s" "$@"\nexit 1\n' "$(command -v ln)" >"$shim/ln"
chmod +x "$shim/ln"
r8=$(sr2 new-run)
env PATH="$shim:$PATH" "$SR" --worktree "$w2" write --completion --run "$r8" --point pre-ci \
  --head "$HEAD_SHA" >/dev/null 2>"$tmp/err8"
[ $? -eq 1 ] && grep -q "cannot write to the record cache" "$tmp/err8"
verdict_of $? "a completion whose link fails exits 1" "failed link not reported: $(cat "$tmp/err8")"
[ -z "$(find "$w2/.claude/steps/$r8" -mindepth 1)" ] && [ ! -L "$w2/.claude/steps/.lock" ]
verdict "a failed completion leaves no temp file and no lock" "leftovers after a failed completion"
sr2 write --completion --run "$r8" --point pre-ci --head "$HEAD_SHA" >/dev/null
verdict "a retried completion after a failed one succeeds" "the failed completion left its point completed"

# A missing secret screen withholds, never passes.
lone="$tmp/lone"
mkdir -p "$lone"
cp "$SR" "$repo_root/scripts/echo-safety.sh" "$repo_root/scripts/lock-lib.sh" "$lone/"
w6="$tmp/w6"
fresh "$w6"
r6=$(/bin/sh "$lone/step-record.sh" --worktree "$w6" new-run)
recl2=$(/bin/sh "$lone/step-record.sh" --worktree "$w6" write --run "$r6" --point pre-ci --step s \
  --kind command --target plain --hosting isolated --backend runner --head "$HEAD_SHA" \
  --start 2026-09-28T14:00:00Z --end 2026-09-28T14:00:01Z --outcome passed)
grep -Fq "target${TAB}[withheld: the value could not be screened]" "$recl2"
verdict "a missing screen withholds every screened value" "value passed unscreened"

# Checklist edges over a second range.
w7="$tmp/w7"
fresh "$w7"
c7() { git -C "$w7" commit -q --allow-empty -F -; }
B7=$(git -C "$w7" rev-parse HEAD)
printf '%s\n' "fix(a): folded trailer" "" "Route reason: first" "Route reason: second" "" \
  "Planwright-Sign-Off: PS-2" "  PS-9" "Planwright-Sign-Off-Rejected: PS-3" | c7
printf '%s\n' "fix(b): rejected by the folded commit" "" "Planwright-Sign-Off: PS-3" | c7
printf '%s\n' "fix(c): two ids, comma-separated" "" "Planwright-Sign-Off: PS-4, PS-5" | c7
printf '%s\n' "fix(d): reverted by reference" "" "Planwright-Sign-Off: PS-6" | c7
D7=$(git -C "$w7" rev-parse --short=7 HEAD)
printf '%s\n' "Revert \"fix(d)\"" "" "This reverts commit $D7 (fix(d), 2026-09-28)." | c7
printf '%s\n' "chore: a rejection later reverted" "" "Planwright-Sign-Off-Rejected: PS-4" | c7
RJ=$(git -C "$w7" rev-parse HEAD)
printf '%s\n' "Revert \"chore\"" "" "This reverts commit $RJ." | c7
printf 'fix(e): a live subject with \033[31m a control byte\n\nPlanwright-Sign-Off: PS-8\n' | c7
git -C "$w7" checkout -q -b base "$B7"
printf '%s\n' "fix(base): merged in from the base" "" "Planwright-Sign-Off: PS-11" | c7
git -C "$w7" checkout -q -b topic main
printf '%s\n' "fix(topic): merged in from a topic branch" "" "Planwright-Sign-Off: PS-13" | c7
git -C "$w7" checkout -q main
git -C "$w7" merge -q --no-ff base -m "Merge base into main" >/dev/null
git -C "$w7" merge -q --no-ff topic -m "Merge topic into main" -m "Planwright-Sign-Off: PS-12" >/dev/null
H7=$(git -C "$w7" rev-parse HEAD)
cl=$("$SR" --worktree "$w7" regenerate --base base --head "$H7" --checklist-only)
has() { printf '%s\n' "$cl" | grep -Fq -- "$1"; }
has "**PS-2** fix\(a\): folded trailer"
verdict "a folded trailer keeps its entry" "PS-2 missing"
! has "**PS-3**"
verdict "a folded commit's rejection still applies" "PS-3 still listed"
has "**PS-9**"
verdict "a folded continuation value is its own id" "PS-9 missing"
has "  - Route reason: first"
verdict "the first route reason line is the one rendered" "route reason not the first"
has "**PS-4**" && has "**PS-5**"
verdict "every id in a comma-separated trailer renders" "an id of the pair missing"
! has "**PS-6**"
verdict "a --reference revert drops its target" "PS-6 still listed"
! printf '%s\n' "$cl" | grep -q "$esc"
verdict "commit text is cleaned of control bytes" "a control byte reached the checklist"
has "**PS-8**"
verdict "the cleaned live commit still renders" "PS-8 missing"
! has "**PS-11**"
verdict "a trailer merged in from the base never enters" "PS-11 listed"
has "**PS-13**"
verdict "a trailer merged in from a topic branch enters" "PS-13 missing"
# shellcheck disable=SC2016 # literal backticks in the expected line
has 'Reject with: a later commit carrying `Planwright-Sign-Off-Rejected: PS-12`'
verdict "a merge commit's entry names the rejection trailer" "merge recipe missing"

# --- third-round edges ---------------------------------------------------------------
# A step refused because its point completed while it was screening leaves
# nothing behind; a completion with no warning runs no screen.
slow="$tmp/slow"
mkdir -p "$slow"
cp "$SR" "$repo_root/scripts/echo-safety.sh" "$repo_root/scripts/lock-lib.sh" "$slow/"
cat >"$slow/inception-secret-screen.sh" <<'STUB'
#!/bin/sh
if grep -q slowstep "$2"; then
  : >"${0%/*}/slow-started"
  sleep 6
  exit 0
fi
printf 'call\n' >>"${0%/*}/calls"
exit 0
STUB
w9="$tmp/w9"
fresh "$w9"
r9=$(/bin/sh "$slow/step-record.sh" --worktree "$w9" new-run)
/bin/sh "$slow/step-record.sh" --worktree "$w9" write --run "$r9" --point pre-ci --step s --kind command \
  --target slowstep --hosting isolated --backend runner --head "$HEAD_SHA" \
  --start 2026-09-28T15:00:00Z --end 2026-09-28T15:00:01Z --outcome passed >/dev/null 2>"$tmp/err9" &
slowpid=$!
i=0
while [ ! -e "$slow/slow-started" ] && [ "$i" -lt 60 ]; do
  sleep 1
  i=$((i + 1))
done
[ -e "$slow/slow-started" ]
verdict "the slow step reached its screen before the completion" "the slow step never screened"
/bin/sh "$slow/step-record.sh" --worktree "$w9" write --completion --run "$r9" --point pre-ci \
  --head "$HEAD_SHA" >/dev/null
[ ! -s "$slow/calls" ]
verdict "a completion with no warning runs no screen" "the screen ran for a warning-free completion"
wait "$slowpid"
rc=$?
left=$(find "$w9/.claude/steps/$r9" -mindepth 1 -exec basename {} \; | sort | tr '\n' ' ')
[ "$rc" -eq 2 ] && grep -q "already completed" "$tmp/err9" && [ "$left" = "001-done-pre-ci.rec " ] \
  && [ ! -L "$w9/.claude/steps/.lock" ]
verdict "a step refused after its point completed leaves nothing behind" "rc=$rc, run holds: $left"

# A completion that cannot be written is a runtime failure, not a completed point.
r10=$(sr2 new-run)
chmod 500 "$w2/.claude/steps/$r10"
sr2 write --completion --run "$r10" --point pre-ci --head "$HEAD_SHA" >/dev/null 2>"$tmp/err10"
rc=$?
chmod 700 "$w2/.claude/steps/$r10"
[ "$rc" -eq 1 ] && ! grep -q "already completed" "$tmp/err10"
verdict "an unwritable run dir fails a completion with exit 1" "rc=$rc, or reported as already completed"

# A run id or record path that cannot be printed.
nbefore=$(find "$w2/.claude/steps" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')
sr2 new-run >&- 2>/dev/null
rc=$?
nafter=$(find "$w2/.claude/steps" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')
[ "$rc" -eq 1 ] && [ "$nbefore" -eq "$nafter" ]
verdict "a run id that cannot be printed leaves no run" "rc=$rc runs $nbefore -> $nafter"
rbefore=$(find "$w2/.claude/steps/$r" -name '[0-9]*.rec' | wc -l | tr -d ' ')
# shellcheck disable=SC2086 # args2 is a fixed word list
sr2 write $args2 --point pre-ci --step noprint >&- 2>/dev/null
rc=$?
rafter=$(find "$w2/.claude/steps/$r" -name '[0-9]*.rec' | wc -l | tr -d ' ')
[ "$rc" -eq 1 ] && [ "$rafter" -eq $((rbefore + 1)) ]
verdict "a record path that cannot be printed keeps its record" "rc=$rc records $rbefore -> $rafter"

# Run ids of the wrong shape are refused before they name a path.
for bad_run in .. 12; do
  for v in "write --point pre-ci --step s --kind command --target t --hosting isolated --backend runner --head $HEAD_SHA --start 2026-09-28T14:00:00Z --end 2026-09-28T14:00:01Z --outcome passed" list render; do
    # shellcheck disable=SC2086 # v is a fixed word list
    sr2 $v --run "$bad_run" >/dev/null 2>"$tmp/errr"
    rc=$?
    [ "$rc" -eq 2 ] && grep -Fq -- "--run: not a run id" "$tmp/errr"
    verdict "a run id '$bad_run' is refused by ${v%% *}" "rc=$rc"
  done
done
[ -z "$(find "$w2/.claude" -maxdepth 1 -name '*.rec')" ]
verdict "no record lands outside the cache" "a record escaped the cache"

# More grammar edges.
# shellcheck disable=SC2086
refuse "an uppercase backend" "--backend" $args2 --point pre-ci --step s --backend EVILRunner
# shellcheck disable=SC2086
refuse "a 65-byte backend" "--backend" $args2 --point pre-ci --step s --backend "evil$(printf 'a%.0s' $(seq 1 61))"
# shellcheck disable=SC2086
refuse "a 129-byte session" "--session" $args2 --point pre-ci --step s --session "EVIL$(printf 'a%.0s' $(seq 1 125))"
needle="${HEAD_SHA}a"
# shellcheck disable=SC2086
refuse "a 41-hex head" "--head" --run "$r" --point pre-ci --step s --kind command --target t \
  --hosting isolated --backend runner --head "$needle" --start 2026-09-28T14:00:00Z \
  --end 2026-09-28T14:00:01Z --outcome passed
needle=$(printf '%s' "$HEAD_SHA" | tr a-f A-F)
refuse "an uppercase head" "--head" --run "$r" --point pre-ci --step s --kind command --target t \
  --hosting isolated --backend runner --head "$needle" --start 2026-09-28T14:00:00Z \
  --end 2026-09-28T14:00:01Z --outcome passed
needle=''

# Backend and session pass the screen; a broken screen withholds the backend.
recb=$(sr2 write --run "$r" --point pre-pr --step tokfields --kind command --target t \
  --hosting isolated --backend xoxb-1234567890-abcdefghij --session xoxb-1234567890-abcdefghij \
  --head "$HEAD_SHA" --start 2026-09-28T14:00:00Z --end 2026-09-28T14:00:01Z --outcome passed)
grep -Fxq "backend${TAB}[withheld: the secret screen flagged this value]" "$recb" \
  && grep -Fxq "session${TAB}[withheld: the secret screen flagged this value]" "$recb"
verdict "a token-shaped backend and session are withheld" "backend or session stored"
grep -Fxq "backend${TAB}[withheld: the value could not be screened]" "$recu"
verdict "a screen that cannot run withholds the backend" "backend passed unscreened"

# The bounds bind exactly.
[ "$n" -eq 20 ]
verdict "a long excerpt keeps exactly its 20-line tail" "$n lines kept"
[ "$wbytes" -gt 1800 ]
verdict "a wide excerpt keeps close to its byte bound" "$wbytes bytes kept"
[ "$(sed -n "s/^excerpt${TAB}//p" "$recx")" = "$(printf 'z%.0s' $(seq 1 1998))" ]
verdict "the byte cut keeps every whole character" "the cut lost text"
recv=$(find "$w2/.claude/steps/$r" -name '*.rec' -exec grep -l "^step${TAB}edge-k$" {} +)
[ -n "$recv" ] && ! grep -q "^excerpt${TAB}" "$recv"
verdict "an all-invalid excerpt is stored empty" "an all-invalid excerpt kept text"

# Blank excerpt lines join like any other.
printf '\nfirst\n\nthird\n' >"$tmp/blank.txt"
sr2 write --run "$r" --point pre-dispatch --step blanks --kind command --target t --hosting isolated \
  --backend runner --head "$HEAD_SHA" --start 2026-09-28T14:00:00Z --end 2026-09-28T14:00:01Z \
  --outcome passed --excerpt-file "$tmp/blank.txt" >/dev/null
sr2 render --run "$r" --point pre-dispatch | grep -Fq '|  / first /  / third |'
verdict "blank excerpt lines are joined, leading ones too" "blank excerpt lines joined unevenly"

# list's record line, render's empty point, the ended-on line.
[ "$(sr list --run "$run1" | head -n 1)" = "record${TAB}.claude/steps/$run1/001-step-convergence.rec" ]
verdict "list heads a record with its worktree-relative path" "list header is not the relative record line"
[ -z "$(sr render --run "$run1" --point post-pr)" ]
verdict "a named point with no record renders nothing" "an empty point rendered"
! sr render --run "$run2" --point pre-ci | grep -q "Ended on"
verdict "a point without a completion names no ended-on head" "an ended-on line without a completion"
[ "$((1$run2))" -eq "$((1$run1 + 1))" ]
verdict "new-run issues one past the highest id" "run ids '$run1' then '$run2'"

# Neutralizing a leading dash and a leading number's parenthesis; C1 in a
# planted record is dropped by render.
sr2 write --run "$r" --point unit-selected --step lead-a --kind command --target '- item' \
  --hosting isolated --backend runner --head "$HEAD_SHA" --start 2026-09-28T14:00:00Z \
  --end 2026-09-28T14:00:01Z --outcome passed >/dev/null
recpl=$(sr2 write --run "$r" --point unit-selected --step lead-b --kind command --target '3) x' \
  --hosting isolated --backend runner --head "$HEAD_SHA" --start 2026-09-28T14:00:00Z \
  --end 2026-09-28T14:00:01Z --outcome passed)
printf 'excerpt\tp\302\233q\n' >>"$recpl"
lead=$(sr2 render --run "$r" --point unit-selected)
printf '%s\n' "$lead" | grep -Fq '| \- item |' && printf '%s\n' "$lead" | grep -Fq '| 3\) x |'
verdict "a leading dash and a leading number's ) are escaped" "$lead"
printf '%s\n' "$lead" | grep -Fq '| pq |'
verdict "render drops C1 a planted record carries" "a planted C1 byte reached render"

# A symlinked or unreadable run directory is refused.
w10="$tmp/w10"
fresh "$w10"
mkdir -p "$w10/.claude/steps" "$tmp/foreign-run"
ln -s "$tmp/foreign-run" "$w10/.claude/steps/000001"
"$SR" --worktree "$w10" render --run 000001 >/dev/null 2>&1
[ $? -eq 1 ]
verdict "a symlinked run directory is refused" "symlinked run read"
rm -f "$w10/.claude/steps/000001"
mkdir "$w10/.claude/steps/000001"
chmod 000 "$w10/.claude/steps/000001"
"$SR" --worktree "$w10" list >/dev/null 2>&1
rc=$?
chmod 700 "$w10/.claude/steps/000001"
[ "$rc" -eq 1 ]
verdict "an unreadable run directory is refused" "rc=$rc"

# The default worktree is the enclosing top level; outside git it is a usage
# error. --excerpt-file resolves against the caller's directory.
mkdir -p "$w10/sub" "$tmp/caller"
printf 'from the caller\n' >"$tmp/caller/rel.txt"
printf 'from the worktree\n' >"$w10/sub/rel.txt"
r11=$(cd "$w10/sub" && "$SR" new-run)
[ -d "$w10/.claude/steps/$r11" ]
verdict "the default worktree is the git top level" "no run under $w10"
rec11=$(cd "$tmp/caller" && "$SR" --worktree "$w10" write --run "$r11" --point pre-ci --step rel \
  --kind command --target t --hosting isolated --backend runner --head "$HEAD_SHA" \
  --start 2026-09-28T14:00:00Z --end 2026-09-28T14:00:01Z --outcome passed --excerpt-file rel.txt)
grep -Fxq "excerpt${TAB}from the caller" "$rec11"
verdict "a relative excerpt file resolves against the caller" "the excerpt did not come from the caller directory"
mkdir -p "$tmp/nogit"
(cd "$tmp/nogit" && GIT_CEILING_DIRECTORIES="$tmp" "$SR" new-run >/dev/null 2>&1)
[ $? -eq 2 ]
verdict "outside a git work tree the default worktree is a usage error" "no usage error"

# More checklist edges over a third range.
w8="$tmp/w8"
fresh "$w8"
c8() { git -C "$w8" commit -q --allow-empty -F -; }
B8=$(git -C "$w8" rev-parse HEAD)
printf '%s\n' "fix(t): reverted on a topic dated earlier" "" "Planwright-Sign-Off: PS-1" \
  | env GIT_COMMITTER_DATE="2030-01-01T00:00:00Z" git -C "$w8" commit -q --allow-empty -F -
T8=$(git -C "$w8" rev-parse HEAD)
git -C "$w8" checkout -q -b topic
printf '%s\n' "Revert \"fix(t)\"" "" "This reverts commit $T8." \
  | env GIT_COMMITTER_DATE="2026-01-01T00:00:00Z" git -C "$w8" commit -q --allow-empty -F -
git -C "$w8" checkout -q main
printf '%s\n' "chore: main work" | c8
git -C "$w8" merge -q --no-ff topic -m "Merge topic" >/dev/null
printf '%s\n' "fix(z): a leading-zero id" "" "Planwright-Sign-Off: PS-01" | c8
printf '%s\n' "fix(w): reverted with a comma" "" "Planwright-Sign-Off: PS-2" | c8
W8=$(git -C "$w8" rev-parse HEAD)
printf '%s\n' "Revert \"fix(w)\"" "" "This reverts commit $W8, reversing" "changes." | c8
printf '%s\n' "fix(v): reverted at the line's end" "" "Planwright-Sign-Off: PS-3" | c8
V8=$(git -C "$w8" rev-parse HEAD)
printf '%s\n' "Revert \"fix(v)\"" "" "This reverts commit $V8" | c8
printf '%s\n' "fix(u): a revert too short to name it" "" "Planwright-Sign-Off: PS-4" | c8
U8=$(git -C "$w8" rev-parse --short=6 HEAD)
printf '%s\n' "Revert \"fix(u)\"" "" "This reverts commit $U8." | c8
printf '%s\n' "fix(s): both markers [pending-sign-off]" "" "Planwright-Sign-Off: PS-5" | c8
printf '%s\n' "fix(r): a huge id" "" "Planwright-Sign-Off: PS-10000000000" | c8
printf '%s\n' "fix(q): legacy [pending-sign-off]" | c8
git -C "$w8" checkout -q -b topic2
printf '%s\n' "fix(p): on the second topic" | c8
git -C "$w8" checkout -q main
git -C "$w8" merge -q --no-ff topic2 -m "Merge topic2 [pending-sign-off]" >/dev/null
M8=$(git -C "$w8" rev-parse --short=7 HEAD)
cl=$("$SR" --worktree "$w8" regenerate --base "$B8" --head HEAD --checklist-only)
! has "**PS-1**"
verdict "a revert dated before its target still drops it" "PS-1 still listed"
! has "PS-01"
verdict "a leading-zero id is not an entry" "PS-01 listed"
! has "**PS-2**" && ! has "**PS-3**"
verdict "revert lines ending in a comma or at the line's end drop their target" "PS-2 or PS-3 listed"
has "**PS-4**"
verdict "a revert naming fewer than 7 hex digits drops nothing" "PS-4 dropped"
has "**PS-5** fix\(s\): both markers · commit"
verdict "the legacy suffix is dropped beside a trailer" "the suffix survived beside PS-5"
[ "$(printf '%s\n' "$cl" | sed -n 's/^- \*\*\([^*]*\)\*\*.*/\1/p' | tr '\n' ' ')" = "PS-4 PS-5 PS-10000000000 legacy legacy " ]
verdict "legacy entries sort after every id, however large" "entries out of order"
# shellcheck disable=SC2016 # literal backticks in the expected line
has "Reject with: \`git revert -m 1 $M8\`"
verdict "a legacy merge commit's recipe reverts against its first parent" "no first-parent revert recipe"

# Approval semantics inside the section, and a shared commit's disclosure and
# per-item recipe (human-gates REQ-B1.5, REQ-B1.6).
APPROVAL="The approval act that lets the PR merge signs off every pending-sign-off item, never the ready flip; reject one before it by its printed recipe."
w9="$tmp/w9"
fresh "$w9"
c9() { git -C "$w9" commit -q --allow-empty -F -; }
B9=$(git -C "$w9" rev-parse HEAD)
printf '%s\n' "fix(m): two interleaved findings, one regression test" "" \
  "Planwright-Sign-Off: PS-1" "Planwright-Sign-Off: PS-2" | c9
S9=$(git -C "$w9" rev-parse --short=7 HEAD)
S9FULL=$(git -C "$w9" rev-parse HEAD)
printf '%s\n' "fix(n): an isolable finding" "" "Planwright-Sign-Off: PS-3" | c9
N9=$(git -C "$w9" rev-parse --short=7 HEAD)
cl=$("$SR" --worktree "$w9" regenerate --base "$B9" --head HEAD --checklist-only)
[ "$(printf '%s\n' "$cl" | sed -n 3p)" = "$APPROVAL" ]
verdict "the section states the approval act and the rejection rule under its heading" "no approval statement inside the section"
! printf '%s\n' "$cl" | grep -Fq -- '[ ]'
verdict "no checkbox reads as the approval control" "a checkbox survived"
[ "$(printf '%s\n' "$cl" | grep -c "· commit \`$S9\`")" = 2 ]
verdict "a shared commit renders one entry per finding" "the shared commit is not two entries"
has "  - Shared commit: also carries PS-2" && has "  - Shared commit: also carries PS-1"
verdict "each entry of a shared commit discloses it" "a shared-commit disclosure missing"
# shellcheck disable=SC2016 # literal backticks in the expected lines
has '  - Reject with: a commit undoing its part, carrying `Planwright-Sign-Off-Rejected: PS-1`' \
  && has '  - Reject with: a commit undoing its part, carrying `Planwright-Sign-Off-Rejected: PS-2`'
verdict "each finding of a shared commit gets its own rejection recipe" "a per-item recipe missing"
! has "git revert $S9" && has "Reject with: \`git revert $N9\`"
verdict "only an isolable commit's recipe is a whole revert" "a shared commit offered a whole revert"
printf '%s\n' "Revert part of \"fix(m)\"" "" "This reverts commit $S9FULL." "" \
  "Planwright-Sign-Off-Rejected: PS-1" | c9
cl=$("$SR" --worktree "$w9" regenerate --base "$B9" --head HEAD --checklist-only)
! has "**PS-1**" && has "**PS-2**" && has "**PS-3**"
verdict "a partial revert carrying the rejected trailer drops only its item" "the partial revert dropped the wrong items"
! has "also carries PS-1"
verdict "a rejected sibling drops out of the shared-commit line" "the shared-commit line still names a rejected sibling"
has "  - Shared commit: its other findings were rejected"
verdict "a shared commit with no live sibling still discloses it" "the lone survivor's entry hides the shared commit"
# shellcheck disable=SC2016 # literal backticks in the expected line
has '  - Reject with: a commit undoing its part, carrying `Planwright-Sign-Off-Rejected: PS-2`'
verdict "the last live finding of a shared commit keeps the part-undo recipe" "the lone survivor lost its part-undo recipe"
printf '%s\n' "fix(t): three findings, one test" "" "Planwright-Sign-Off: PS-4" \
  "Planwright-Sign-Off: PS-5" "Planwright-Sign-Off: PS-6" | c9
printf '%s\n' "chore: reject PS-4 by hand" "" "Planwright-Sign-Off-Rejected: PS-4" | c9
cl=$("$SR" --worktree "$w9" regenerate --base "$B9" --head HEAD --checklist-only)
has "  - Shared commit: also carries PS-6" && has "  - Shared commit: also carries PS-5" && ! has "PS-4"
verdict "a shared-commit line lists only the live siblings" "a rejected id stayed in a shared-commit line"
empty=$("$SR" --worktree "$w9" regenerate --base HEAD --head HEAD --checklist-only)
! printf '%s\n' "$empty" | grep -Fq "$APPROVAL"
verdict "an empty checklist carries no approval statement" "the none row carries the statement"
w10="$tmp/w10"
fresh "$w10"
B10=$(git -C "$w10" rev-parse HEAD)
printf '%s\n' "fix(d): one finding, its id stamped twice" "" \
  "Planwright-Sign-Off: PS-1" "Planwright-Sign-Off: PS-1" | git -C "$w10" commit -q --allow-empty -F -
D10=$(git -C "$w10" rev-parse --short=7 HEAD)
cl=$("$SR" --worktree "$w10" regenerate --base "$B10" --head HEAD --checklist-only)
! has "Shared commit" && has "Reject with: \`git revert $D10\`"
verdict "an id stamped twice is not a shared commit" "a lone finding disclosed itself as shared"
D10FULL=$(git -C "$w10" rev-parse HEAD)
printf '%s\n' "Revert \"fix(d)\"" "" "This reverts commit $D10FULL." "" \
  "Planwright-Sign-Off-Rejected: PS-9" | git -C "$w10" commit -q --allow-empty -F -
git -C "$w10" checkout -q -b side
git -C "$w10" commit -q --allow-empty -m "fix(e): on the side branch"
git -C "$w10" checkout -q main
git -C "$w10" commit -q --allow-empty -m "chore: main work"
git -C "$w10" merge -q --no-ff side -m "Merge side" \
  -m "$(printf '%s\n' "Planwright-Sign-Off: PS-2" "Planwright-Sign-Off: PS-3")" >/dev/null
cl=$("$SR" --worktree "$w10" regenerate --base "$B10" --head HEAD --checklist-only)
! has "**PS-1**"
verdict "a revert whose rejected trailer names no id of its target undoes it whole" "the revert read as partial"
# shellcheck disable=SC2016 # literal backticks in the expected line
has "  - Shared commit: also carries PS-3" \
  && has '  - Reject with: a later commit carrying `Planwright-Sign-Off-Rejected: PS-2`'
verdict "a shared merge commit discloses it and keeps the merge recipe" "the shared merge entry is wrong"

# The resolver's vocabulary and step-record's are the same list.
mine=$(sed -n '/^is_point() {/,/return 0 ;;/p' "$SR" | tr -d '\134' | tr '|' '\n' \
  | sed -e 's/.*case .1 in//' -e 's/) return 0 ;;//' -e 's/^ *//' -e 's/ *$//' | grep -E '^[a-z-]+$' | sort)
[ "$mine" = "$(printf '%s\n' "$vocab" | sort)" ]
verdict "step-record's point list equals the resolver's" "lists differ"

# The invisible list matches flight-text.sh's, C1 prefix aside.
ft=$(sed -n "s/^INVIS_SED=\$(printf '\(.*\)')$/\1/p" "$repo_root/scripts/flight-text.sh")
sr_full=$(sed -n "s/^INVIS_SED=\$(printf '\(.*\)')$/\1/p" "$SR")
sr_list=${sr_full#'s/\302[\200-\237]//g;'}
[ -n "$ft" ] && [ "$ft" = "$sr_list" ]
verdict "the invisible list matches flight-text.sh's" "the lists diverged"

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
commit "fix(early): committed before PS-1 but numbered after it

Route reason: behaviour change @reviewer

Planwright-Sign-Off: PS-7" >/dev/null
C0=$(git -C "$wt" rev-parse --short=7 HEAD)
commit "chore: a malformed trailer value

Planwright-Sign-Off: TODO" >/dev/null
C1=$(commit "fix(stamp): reword the degraded case

Route reason: meaning-class prose, pre-existing surface

Planwright-Sign-Off: PS-1")
commit "fix(x): a fix later reverted

Route reason: behaviour change

Planwright-Sign-Off: PS-2" >/dev/null
C2FULL=$(git -C "$wt" rev-parse HEAD)
commit "Revert \"fix(x): a fix later reverted\"

This reverts commit $C2FULL." >/dev/null
C4=$(commit "docs(guide): two prose fixes @someone fixes #12 see [x](https://evil.example)

Route reason: meaning-class prose on surfaces that predate the PR

- \`docs/a.md\` — before: absent · after: the rule
- \`docs/b.md\` — before: the old rule
  · after: the new rule

Planwright-Sign-Off: PS-3")
commit "fix(y): a fix later rejected

Route reason: public contract

Planwright-Sign-Off: PS-4" >/dev/null
C6=$(commit "fix(old): a legacy-marked fix [pending-sign-off]")
commit "chore: reject one item

Planwright-Sign-Off-Rejected: PS-4" >/dev/null
commit "chore: an unmarked commit

- an ordinary bullet, not a manifest line" >/dev/null
C9=$(commit "fix(z): a fix whose revert was reverted

Planwright-Sign-Off: PS-5")
C9FULL=$(git -C "$wt" rev-parse HEAD)
commit "Revert \"fix(z)\"

This reverts commit $C9FULL." >/dev/null
R9FULL=$(git -C "$wt" rev-parse HEAD)
commit "Reapply \"fix(z)\"

This reverts commit $R9FULL." >/dev/null
commit "$(printf 'fix(dup): the same id again\033[31m')

Planwright-Sign-Off: PS-1" >/dev/null
commit "chore: a rejection naming no PS id

Planwright-Sign-Off-Rejected: legacy" >/dev/null
HEAD2=$(git -C "$wt" rev-parse HEAD)

sed -e "s/@C1@/$C1/g" -e "s/@C4@/$C4/g" -e "s/@C6@/$C6/g" -e "s/@C9@/$C9/g" -e "s/@C0@/$C0/g" "$GOLDEN" >"$tmp/expected.md"
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

sr regenerate --base "$BASE" --head "$HEAD2" | grep -Fq "## Steps at \`pre-pr\` (run \`$run4\`)"
verdict "regenerate defaults to the latest run" "default run not rendered"
awk '/^## Steps at /{print prev; exit} {prev = $0}' "$tmp/regen.md" | grep -q '^$'
verdict "a blank line separates the checklist from the tables" "no blank line before the tables"
sr regenerate --base "$BASE" --head no-such-ref >/dev/null 2>"$tmp/err2"
rc=$?
[ "$rc" -eq 1 ] && grep -Fq -- "--head" "$tmp/err2"
verdict "an unresolvable head fails by name" "rc=$rc"
empty=$(sr regenerate --base "$HEAD2" --head "$HEAD2" --run "$run1")
printf '%s\n' "$empty" | grep -Fxq -- "- none"
verdict "an empty range emits the checklist's none row" "no none row for an empty range"

sr regenerate --base no-such-ref --head "$HEAD2" >/dev/null 2>"$tmp/err"
rc=$?
[ "$rc" -eq 1 ] && grep -Fq -- "--base" "$tmp/err"
verdict "an unresolvable range fails by name" "rc=$rc, or --base not named"

# The latest run is the highest id, whether or not it holds a record.
sr new-run >/dev/null
[ -z "$(sr render)" ]
verdict "render defaults to the latest run, even an empty one" "render showed an older run"
! sr regenerate --base "$BASE" --head "$HEAD2" | grep -q '^## Steps at'
verdict "regenerate defaults to the latest run, even an empty one" "regenerate showed an older run"

# --- a mkdir that tells every racer it won ---------------------------------------------
# Some coreutils reimplementations report success to several concurrent
# creators of one directory. The shim makes that the rule rather than the race,
# so a writer that still takes its claims by mkdir status shows it every run.
multi="$tmp/multi-mkdir"
mkdir -p "$multi"
real_mkdir=$(command -v mkdir)
printf '#!/bin/sh\n"%s" -p "$@" 2>/dev/null\nexit 0\n' "$real_mkdir" >"$multi/mkdir"
chmod +x "$multi/mkdir"
wm="$tmp/wm"
fresh "$wm"
srm() { env PATH="$multi:$PATH" "$SR" --worktree "$wm" "$@"; }
i=1
while [ "$i" -le 4 ]; do
  srm new-run >>"$tmp/multi-runs" 2>/dev/null &
  i=$((i + 1))
done
wait
nruns=$(grep -c . "$tmp/multi-runs")
druns=$(sort "$tmp/multi-runs" | uniq -d | grep -c .)
[ "$nruns" -eq 4 ] && [ "$druns" -eq 0 ]
verdict "concurrent new-runs issue distinct ids under a multi-winner mkdir" \
  "$nruns ids issued, $druns duplicated"
rm6=$(srm new-run)
i=1
while [ "$i" -le 8 ]; do
  srm write --run "$rm6" --point pre-implementation --step "m$i" --kind command --target t \
    --hosting isolated --backend runner --head "$HEAD_SHA" \
    --start 2026-09-28T16:00:00Z --end 2026-09-28T16:00:01Z --outcome passed >/dev/null 2>&1 &
  i=$((i + 1))
done
wait
dups=$(srm list --run "$rm6" | sed -n "s/^seq${TAB}//p" | sort | uniq -d | wc -l | tr -d ' ')
count=$(srm list --run "$rm6" | grep -c "^seq${TAB}")
[ "$dups" -eq 0 ] && [ "$count" -eq 8 ]
verdict "concurrent writers keep unique sequence numbers under a multi-winner mkdir" \
  "$count records, $dups duplicate seqs"
rm7=$(srm new-run)
i=1
while [ "$i" -le 4 ]; do
  {
    srm write --completion --run "$rm7" --point pre-ci --head "$HEAD_SHA" >/dev/null 2>&1
    echo $? >>"$tmp/rc7"
  } &
  i=$((i + 1))
done
wait
ndone=$(find "$wm/.claude/steps/$rm7" -name '[0-9]*-done-pre-ci.rec' | wc -l | tr -d ' ')
rcs=$(sort "$tmp/rc7" | tr '\n' ' ')
[ "$ndone" -eq 1 ] && [ "$rcs" = "0 2 2 2 " ] && [ ! -L "$wm/.claude/steps/.lock" ] \
  && [ -z "$(find "$wm/.claude/steps" -name '.rec-*')" ]
verdict "one completion wins under a multi-winner mkdir" "$ndone completion records, exits $rcs"

# --- caches holding directory-shaped markers ------------------------------------------
# A .seq- directory counts as a used sequence number and a .done- directory as a
# completed point, with or without the record they were claimed for.
wl="$tmp/wl"
fresh "$wl"
rl="$wl/.claude/steps/000007"
mkdir -p "$rl/.seq-001" "$rl/.seq-002" "$rl/.seq-003" "$rl/.done-pre-ci"
printf 'type\tstep\nrun\t000007\nseq\t001\npoint\tpre-ci\nstep\told\nkind\tcommand\ntarget\tt\nhosting\tisolated\nbackend\trunner\nsession\t\nhead\t%s\nstart\t2026-09-28T09:00:00Z\nend\t2026-09-28T09:00:01Z\noutcome\tpassed\noutput\t\nskip-reason\t\n' \
  "$HEAD_SHA" >"$rl/001-step-pre-ci.rec"
"$SR" --worktree "$wl" render --run 000007 | grep -q '^| 1 | old |'
verdict "a pre-existing run's records still render" "legacy run did not render"
"$SR" --worktree "$wl" write --run 000007 --point pre-ci --step late --kind command --target t \
  --hosting isolated --backend runner --head "$HEAD_SHA" --start 2026-09-28T09:00:02Z \
  --end 2026-09-28T09:00:03Z --outcome passed >/dev/null 2>"$tmp/errl"
[ $? -eq 2 ] && grep -q "already completed" "$tmp/errl"
verdict "a directory-shaped completion marker still closes its point" "a step landed after a legacy completion"
recl=$("$SR" --worktree "$wl" write --run 000007 --point pre-pr --step next --kind command --target t \
  --hosting isolated --backend runner --head "$HEAD_SHA" --start 2026-09-28T09:00:04Z \
  --end 2026-09-28T09:00:05Z --outcome passed)
[ "${recl##*/}" = "004-step-pre-pr.rec" ]
verdict "a new record numbers past directory-shaped sequence markers" "new record at '${recl##*/}'"
mkdir -p "$wl/.claude/steps/000008/.done-post-pr"
"$SR" --worktree "$wl" write --completion --run 000008 --point post-pr --head "$HEAD_SHA" >/dev/null 2>"$tmp/errl"
[ $? -eq 2 ] && grep -q "already completed" "$tmp/errl"
verdict "a completion marker with no record still claims its point" "a second completion landed"
[ "$("$SR" --worktree "$wl" new-run)" = 000009 ]
verdict "new-run numbers past a pre-existing cache" "new-run reused or skipped an id"
# No writer ever left a .done- marker that is not a directory, so a stray file
# completes nothing.
: >"$wl/.claude/steps/000009/.done-pre-ci"
"$SR" --worktree "$wl" write --run 000009 --point pre-ci --step stray --kind command --target t \
  --hosting isolated --backend runner --head "$HEAD_SHA" --start 2026-09-28T09:00:06Z \
  --end 2026-09-28T09:00:07Z --outcome passed >/dev/null 2>"$tmp/errl"
verdict "a stray .done- file does not close its point" "a step was refused after a stray .done- file"

# A sequence counter used up by records alone is exhausted too.
mkdir -p "$wl/.claude/steps/000010"
cp "$rl/001-step-pre-ci.rec" "$wl/.claude/steps/000010/999-step-pre-ci.rec"
"$SR" --worktree "$wl" write --completion --run 000010 --point pre-pr --head "$HEAD_SHA" >/dev/null 2>"$tmp/errl"
[ $? -eq 1 ] && grep -q "exhausted" "$tmp/errl"
verdict "an exhausted record counter counts records as well as markers" "record written past seq 999"

# --- the cache lock ---------------------------------------------------------------------
# A lock left by a writer that died is broken, not waited out.
wk="$tmp/wk"
fresh "$wk"
mkdir -p "$wk/.claude/steps"
sh -c 'exit 0' &
deadpid=$!
wait "$deadpid"
ln -s "$deadpid-1700000000-1" "$wk/.claude/steps/.lock"
rk=$("$SR" --worktree "$wk" new-run 2>/dev/null)
[ "$rk" = 000001 ] && [ ! -L "$wk/.claude/steps/.lock" ]
verdict "a dead writer's cache lock is broken" "new-run printed '$rk' past a dead writer's lock"
# The lock lives inside the cache so a worktree path carrying `#` still writes.
wh="$tmp/w#hash"
fresh "$wh"
rh=$("$SR" --worktree "$wh" new-run 2>"$tmp/errh") \
  && "$SR" --worktree "$wh" write --completion --run "$rh" --point pre-ci --head "$HEAD_SHA" >/dev/null 2>>"$tmp/errh"
verdict_of $? "a worktree path carrying # still writes records" "$(cat "$tmp/errh")"

# A relative TMPDIR still writes: the scratch is resolved before the cache lock
# moves the writer into the cache.
wr="$tmp/wr"
fresh "$wr"
mkdir -p "$wr/reltmp"
rr=$("$SR" --worktree "$wr" new-run)
(cd "$wr" && TMPDIR=reltmp "$SR" write --run "$rr" --point pre-ci --step rel --kind command \
  --target t --hosting isolated --backend runner --head "$HEAD_SHA" --start 2026-09-28T17:00:00Z \
  --end 2026-09-28T17:00:01Z --outcome passed >/dev/null 2>"$tmp/errrel")
rc=$?
st=1
if [ "$rc" -eq 0 ] && [ -z "$(find "$wr/reltmp" -mindepth 1)" ]; then st=0; fi
verdict_of "$st" "a relative TMPDIR writes its record and leaves no scratch behind" "rc=$rc: $(cat "$tmp/errrel")"

# --- status: the flip-point evidence (custom-steps REQ-E1.5) -------------------------
# A fresh worktree so earlier sections' runs cannot hold a completion for these
# heads, and a gh stub that logs each argument on its own line and fails on demand.
wt2="$tmp/wt2"
mkdir -p "$wt2"
git -C "$wt2" init -q -b main
git -C "$wt2" -c user.name=Fixture -c user.email=fixture@example.invalid -c commit.gpgsign=false \
  commit -q --allow-empty -m "chore: base"
stub="$tmp/ghstub"
mkdir -p "$stub"
cat >"$stub/gh" <<'STUB'
#!/bin/sh
: >"$GH_STUB_LOG"
for a in "$@"; do printf '%s\n' "$a" >>"$GH_STUB_LOG"; done
if [ "${GH_STUB_FAIL:-0}" -ne 0 ]; then
  echo 'HTTP 403: Resource not accessible by integration' >&2
  exit 1
fi
printf '{"state":"posted"}\n'
STUB
chmod +x "$stub/gh"
GH_STUB_LOG="$tmp/gh.args"
GH_STUB_FAIL=0
export GH_STUB_LOG GH_STUB_FAIL

sr2() { PATH="$stub:$PATH" "$SR" --worktree "$wt2" "$@"; }
H_A=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
H_B=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
H_C=cccccccccccccccccccccccccccccccccccccccc
H_D=dddddddddddddddddddddddddddddddddddddddd
H_E=eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
H_F=ffffffffffffffffffffffffffffffffffffffff
H_G=1111111111111111111111111111111111111111

# step_rec <run> <point> <outcome> <head>: one step record at the point.
step_rec() {
  if [ "$3" = skipped ]; then
    set -- "$@" --skip-code missing
  else
    set -- "$@" --session fixture
  fi
  sr2 write --run "$1" --point "$2" --step "s-$3" --kind command --target "true" \
    --hosting in-session --backend terminal --head "$4" \
    --start 2026-10-01T10:00:00Z --end 2026-10-01T10:00:01Z --outcome "$3" "$5" "$6" >/dev/null \
    || fail "fixture: cannot write a $3 step record"
}
done_rec() {
  sr2 write --completion --run "$1" --point "$2" --head "$3" >/dev/null \
    || fail "fixture: cannot write a $2 completion record"
}
# post_state <point> <head>: run the verb against the fixture base repository;
# sets ST_RC and ST_OUT, and leaves the gh call in $GH_STUB_LOG.
post_state() {
  rm -f "$GH_STUB_LOG"
  ST_OUT=$(sr2 status --point "$1" --head "$2" --repo acme/widgets 2>"$tmp/st.err")
  ST_RC=$?
}
gh_arg() { [ -f "$GH_STUB_LOG" ] && grep -Fxq -- "$1" "$GH_STUB_LOG"; }

# An empty attempt: the point completed with no step record.
r=$(sr2 new-run)
done_rec "$r" pre-ready-flip "$H_A"
post_state pre-ready-flip "$H_A"
[ "$ST_RC" -eq 0 ] && gh_arg state=success && gh_arg context=planwright/pre-ready-flip
verdict_of $? "status derives success over an empty attempt" "rc=$ST_RC: $(cat "$tmp/st.err")"
gh_arg "repos/acme/widgets/statuses/$H_A" && gh_arg POST
verdict_of $? "the posting call names the base repository and the exact head" "gh args: $(tr '\n' ' ' <"$GH_STUB_LOG" 2>/dev/null)"
printf '%s\n' "$ST_OUT" | grep -Fxq "posted${TAB}planwright/pre-ready-flip${TAB}success${TAB}$H_A"
verdict "status prints the posted context, state, and head" "printed '$ST_OUT'"
! grep -Fq "$wt2" "$GH_STUB_LOG" && ! grep -q '^target_url=' "$GH_STUB_LOG"
verdict "the status carries no local path and no target" "gh args carry a path or target"
grep -Fxq "description=pre-ready-flip: no step halted or failed (run $r)" "$GH_STUB_LOG"
verdict_of $? "the status carries the pinned description" "description: $(grep '^description=' "$GH_STUB_LOG")"

# Passed, applied, and skipped records all derive success.
r=$(sr2 new-run)
step_rec "$r" pre-ready-flip passed "$H_B"
step_rec "$r" pre-ready-flip applied "$H_B"
step_rec "$r" pre-ready-flip skipped "$H_B"
done_rec "$r" pre-ready-flip "$H_B"
post_state pre-ready-flip "$H_B"
[ "$ST_RC" -eq 0 ] && gh_arg state=success
verdict "status derives success over passed, applied, and skipped records" "rc=$ST_RC"

# A halted or a failed record derives failure, the description saying so.
for o in halted failed; do
  r=$(sr2 new-run)
  h=$H_C
  [ "$o" = failed ] && h=$H_D
  step_rec "$r" pre-ready-flip passed "$h"
  step_rec "$r" pre-ready-flip "$o" "$h"
  done_rec "$r" pre-ready-flip "$h"
  post_state pre-ready-flip "$h"
  [ "$ST_RC" -eq 0 ] && gh_arg state=failure \
    && grep -Fxq "description=pre-ready-flip: a step halted or failed (run $r)" "$GH_STUB_LOG"
  verdict_of $? "status derives failure over a $o record" "rc=$ST_RC: $(cat "$tmp/st.err")"
done

# A step that moved the head still belongs to the attempt the completion names.
r=$(sr2 new-run)
step_rec "$r" pre-ready-flip failed "$H_A"
done_rec "$r" pre-ready-flip "$H_E"
post_state pre-ready-flip "$H_E"
[ "$ST_RC" -eq 0 ] && gh_arg state=failure
verdict "a step recorded on the starting head counts for the head the list ended on" "rc=$ST_RC"

# The latest attempt for the head wins, either way round; a later run that
# completed on another head, or another point, does not displace it.
r=$(sr2 new-run)
step_rec "$r" pre-ready-flip failed "$H_F"
done_rec "$r" pre-ready-flip "$H_F"
r=$(sr2 new-run)
step_rec "$r" pre-ready-flip passed "$H_F"
done_rec "$r" pre-ready-flip "$H_F"
r=$(sr2 new-run)
step_rec "$r" pre-ready-flip failed "$H_G"
done_rec "$r" pre-ready-flip "$H_G"
step_rec "$r" pre-spec-ready-flip failed "$H_F"
done_rec "$r" pre-spec-ready-flip "$H_F"
sr2 new-run >/dev/null
post_state pre-ready-flip "$H_F"
[ "$ST_RC" -eq 0 ] && gh_arg state=success
verdict "status ignores an earlier attempt's failure for the same head" "rc=$ST_RC"
r=$(sr2 new-run)
step_rec "$r" pre-ready-flip halted "$H_F"
done_rec "$r" pre-ready-flip "$H_F"
post_state pre-ready-flip "$H_F"
[ "$ST_RC" -eq 0 ] && gh_arg state=failure
verdict "a later attempt's failure replaces an earlier success" "rc=$ST_RC"

# The spec-PR flip point posts its own context.
post_state pre-spec-ready-flip "$H_F"
[ "$ST_RC" -eq 0 ] && gh_arg context=planwright/pre-spec-ready-flip && gh_arg state=failure
verdict "the spec-PR flip point posts the pre-spec-ready-flip context" "rc=$ST_RC"

# Only the queried point's records count: another point's failure in the same
# run leaves this point's status green.
H_X=3333333333333333333333333333333333333333
r=$(sr2 new-run)
step_rec "$r" pre-ready-flip failed "$H_X"
done_rec "$r" pre-ready-flip "$H_X"
step_rec "$r" pre-spec-ready-flip passed "$H_X"
done_rec "$r" pre-spec-ready-flip "$H_X"
post_state pre-spec-ready-flip "$H_X"
[ "$ST_RC" -eq 0 ] && gh_arg state=success
verdict "another point's failed record does not fail this point's status" "rc=$ST_RC"

# A head with no completion record is refused, with no post.
r=$(sr2 new-run)
step_rec "$r" pre-ready-flip passed 2222222222222222222222222222222222222222
post_state pre-ready-flip 2222222222222222222222222222222222222222
[ "$ST_RC" -eq 1 ] && [ ! -f "$GH_STUB_LOG" ] && grep -Fq 'no completion record' "$tmp/st.err"
verdict_of $? "status refuses a head with no completion record, posting nothing" "rc=$ST_RC: $(cat "$tmp/st.err")"
post_state pre-spec-ready-flip "$H_A"
[ "$ST_RC" -eq 1 ] && [ ! -f "$GH_STUB_LOG" ]
verdict "another flip point's completion does not stand in for this one's" "rc=$ST_RC"

# A failed post fails the verb and names the permission the login needs, as
# one possible cause: an outage or an unknown repository fails the same way.
GH_STUB_FAIL=1
post_state pre-ready-flip "$H_A"
GH_STUB_FAIL=0
[ "$ST_RC" -eq 1 ] && grep -Fq 'repo:status' "$tmp/st.err" && grep -Fq 'Commit statuses' "$tmp/st.err" \
  && grep -Fq 'acme/widgets' "$tmp/st.err" && grep -Fq 'if the cause is a missing permission' "$tmp/st.err"
verdict_of $? "a failed post exits 1 naming the permission as a possible cause and the repository" "rc=$ST_RC: $(cat "$tmp/st.err")"

# Field validation: only the two flip points, a full head, an owner/name repo.
for args in "--point convergence --head $H_A --repo acme/widgets" \
  "--point pre-ready-flip --head abc --repo acme/widgets" \
  "--point pre-ready-flip --head $H_A --repo widgets" \
  "--point pre-ready-flip --head $H_A --repo acme/../widgets" \
  "--point pre-ready-flip --head $H_A --repo -acme/widgets" \
  "--point pre-ready-flip --head $H_A --repo acme/-widgets" \
  "--point pre-ready-flip --head $H_A --repo acme/" \
  "--point pre-ready-flip --head $H_A --repo /widgets" \
  "--point pre-ready-flip --head $H_A --repo acme/." \
  "--point pre-ready-flip --head $H_A --repo acme/.." \
  "--point pre-ready-flip --head $H_A --repo ac_me/widgets" \
  "--point pre-ready-flip --head $H_A --repo acme/wid@gets" \
  "--point pre-ready-flip --head $H_A --repo $(printf 'o%.0s' $(seq 1 40))/widgets" \
  "--point pre-ready-flip --head $H_A --repo acme/$(printf 'n%.0s' $(seq 1 101))" \
  "--point pre-ready-flip --head $H_A --repo" \
  "--point pre-ready-flip --head $H_A --repo acme/widgets --bogus x" \
  "--point pre-ready-flip --head $H_A"; do
  rm -f "$GH_STUB_LOG"
  # shellcheck disable=SC2086 # split into flags by design
  sr2 status $args >/dev/null 2>&1
  rc=$?
  [ "$rc" -eq 2 ] && [ ! -f "$GH_STUB_LOG" ]
  verdict "status refuses '$args' as a usage error" "rc=$rc for '$args'"
done
o39=$(printf 'o%.0s' $(seq 1 39))
n100=$(printf 'n%.0s' $(seq 1 100))
rm -f "$GH_STUB_LOG"
sr2 status --point pre-ready-flip --head "$H_A" --repo "$o39/$n100" >/dev/null 2>"$tmp/st.err"
rc=$?
[ "$rc" -eq 0 ] && gh_arg "repos/$o39/$n100/statuses/$H_A"
verdict_of $? "status accepts a 39-byte owner and a 100-byte name" "rc=$rc: $(cat "$tmp/st.err")"

# --- self-resolved defaults (worker-permission-ergonomics REQ-H1.1) -----------------
# An omitted --head is the worktree's current HEAD, read when the verb runs, and
# an omitted write --end is the time the record is written, so a caller never
# needs a command substitution to fill either.
wd="$tmp/wd"
mkdir -p "$wd"
git -C "$wd" init -q -b main
git -C "$wd" config user.name "Fixture"
git -C "$wd" config user.email "fixture@example.invalid"
git -C "$wd" config commit.gpgsign false
git -C "$wd" commit -q --allow-empty -m "chore: first"
git -C "$wd" commit -q --allow-empty -m "chore: second"
WD_HEAD=$(git -C "$wd" rev-parse HEAD)
srd() { PATH="$stub:$PATH" "$SR" --worktree "$wd" "$@"; }
rd=$(srd new-run)

recd=$(srd write --run "$rd" --point pre-ci --step nohead --kind command --target true \
  --hosting in-session --backend terminal --start 2026-10-06T10:00:00Z \
  --end 2026-10-06T10:00:01Z --outcome passed 2>"$tmp/wd.err")
verdict_of $? "write accepts an omitted --head" "rc!=0: $(cat "$tmp/wd.err")"
grep -Fxq "head${TAB}$WD_HEAD" "$recd" 2>/dev/null
verdict "an omitted --head records the worktree's current HEAD" "record head: $(grep "^head${TAB}" "$recd" 2>/dev/null)"

srd write --completion --run "$rd" --point pre-ci >/dev/null 2>"$tmp/wd.err"
verdict_of $? "write --completion accepts an omitted --head" "rc!=0: $(cat "$tmp/wd.err")"
cat "$wd/.claude/steps/$rd/"*-done-pre-ci.rec 2>/dev/null | grep -Fxq "head${TAB}$WD_HEAD"
verdict "an omitted completion --head records the current HEAD" "completion head not $WD_HEAD"

# The default is read per call, not fixed by an earlier one: it follows a new commit.
git -C "$wd" commit -q --allow-empty -m "chore: third"
WD_HEAD2=$(git -C "$wd" rev-parse HEAD)
recd2=$(srd write --run "$rd" --point pre-pr --step later --kind command --target true \
  --hosting in-session --backend terminal --start 2026-10-06T10:01:00Z \
  --end 2026-10-06T10:01:01Z --outcome passed 2>"$tmp/wd.err")
verdict_of $? "a second defaulted write succeeds" "rc!=0: $(cat "$tmp/wd.err")"
grep -Fxq "head${TAB}$WD_HEAD2" "$recd2" 2>/dev/null
verdict "the --head default follows the HEAD at write time" "record head: $(grep "^head${TAB}" "$recd2" 2>/dev/null)"

# An explicit --head still wins over the default.
recd3=$(srd write --run "$rd" --point pre-pr --step pinned --kind command --target true \
  --hosting in-session --backend terminal --head "$WD_HEAD" --start 2026-10-06T10:02:00Z \
  --end 2026-10-06T10:02:01Z --outcome passed 2>"$tmp/wd.err")
grep -Fxq "head${TAB}$WD_HEAD" "$recd3" 2>/dev/null
verdict "an explicit --head is recorded as given" "record head: $(grep "^head${TAB}" "$recd3" 2>/dev/null)"

# An explicit empty --head (a substitution that printed nothing) is refused, not
# defaulted.
srd write --completion --run "$rd" --point pre-pr --head "" >/dev/null 2>"$tmp/wd.err"
rc=$?
[ "$rc" -eq 2 ] && grep -Fq -- "step-record.sh: --head:" "$tmp/wd.err"
verdict_of $? "an explicit empty --head is refused, never defaulted" "rc=$rc: $(cat "$tmp/wd.err")"
srd write --run "$rd" --point convergence --step emptyend --kind command --target true \
  --hosting in-session --backend terminal --start 2026-10-06T10:00:00Z --end "" \
  --outcome passed >/dev/null 2>"$tmp/wd.err"
rc=$?
[ "$rc" -eq 2 ] && grep -Fq -- "step-record.sh: --end:" "$tmp/wd.err"
verdict_of $? "an explicit empty --end is refused, never defaulted" "rc=$rc: $(cat "$tmp/wd.err")"

# A defaulted --end earlier than --start (a start from a skewed clock) is
# refused rather than recording a negative duration.
srd write --run "$rd" --point convergence --step future --kind command --target true \
  --hosting in-session --backend terminal --start 2999-01-01T00:00:00Z \
  --outcome passed >/dev/null 2>"$tmp/wd.err"
rc=$?
[ "$rc" -eq 2 ] && grep -Fq -- "step-record.sh: --end:" "$tmp/wd.err"
verdict_of $? "a defaulted --end earlier than --start is refused" "rc=$rc: $(cat "$tmp/wd.err")"

stamp_digits() { printf '%s' "$1" | tr -d -- '-:TZ'; }
before=$(date -u +%Y-%m-%dT%H:%M:%SZ)
recd4=$(srd write --run "$rd" --point convergence --step noend --kind command --target true \
  --hosting in-session --backend terminal --start "$before" --outcome passed 2>"$tmp/wd.err")
verdict_of $? "write accepts an omitted --end" "rc!=0: $(cat "$tmp/wd.err")"
after=$(date -u +%Y-%m-%dT%H:%M:%SZ)
endv=$(sed -n "s/^end${TAB}//p" "$recd4" 2>/dev/null)
case $endv in
  [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z)
    if [ "$(stamp_digits "$endv")" -lt "$(stamp_digits "$before")" ] \
      || [ "$(stamp_digits "$endv")" -gt "$(stamp_digits "$after")" ]; then
      fail "an omitted --end recorded '$endv', outside $before..$after"
    else
      ok "an omitted --end records the write time in UTC"
    fi
    ;;
  *) fail "an omitted --end recorded '$endv'" ;;
esac

# A worktree with no commit has no HEAD to default to: refused as a usage error
# naming the field, never recorded with an empty head.
wu="$tmp/wu"
mkdir -p "$wu"
git -C "$wu" init -q -b main
ru=$("$SR" --worktree "$wu" new-run)
[ -n "$ru" ] && [ -d "$wu/.claude/steps/$ru" ]
verdict "the no-commit fixture has a run to write into" "new-run in the no-commit worktree printed '$ru'"
err=$("$SR" --worktree "$wu" write --run "$ru" --point pre-ci --step x --kind command \
  --target true --hosting in-session --backend terminal --start 2026-10-06T10:00:00Z \
  --end 2026-10-06T10:00:01Z --outcome passed 2>&1 >/dev/null)
rc=$?
[ "$rc" -eq 2 ] && printf '%s' "$err" | grep -Fq -- "step-record.sh: --head:" \
  && [ -z "$(ls -A "$wu/.claude/steps/$ru")" ]
verdict_of $? "an omitted --head with no commit is refused and writes nothing" "rc=$rc: $err"
err=$("$SR" --worktree "$wu" write --completion --run "$ru" --point pre-ci 2>&1 >/dev/null)
rc=$?
[ "$rc" -eq 2 ] && printf '%s' "$err" | grep -Fq -- "step-record.sh: --head:" \
  && [ -z "$(ls -A "$wu/.claude/steps/$ru")" ]
verdict_of $? "an omitted completion --head with no commit is refused" "rc=$rc: $err"
rm -f "$GH_STUB_LOG"
err=$(PATH="$stub:$PATH" "$SR" --worktree "$wu" status --point pre-ready-flip --repo acme/widgets 2>&1 >/dev/null)
rc=$?
[ "$rc" -eq 2 ] && printf '%s' "$err" | grep -Fq -- "step-record.sh: --head:" && [ ! -f "$GH_STUB_LOG" ]
verdict_of $? "an omitted status --head with no commit is refused and posts nothing" "rc=$rc: $err"

# The default names the worktree's own repository: a plain directory inside
# another repository, or an inherited GIT_DIR naming another one, is refused
# rather than recording a foreign commit.
mkdir -p "$wd/plain"
rp=$("$SR" --worktree "$wd/plain" new-run)
err=$("$SR" --worktree "$wd/plain" write --completion --run "$rp" --point pre-ci 2>&1 >/dev/null)
rc=$?
[ "$rc" -eq 2 ] && printf '%s' "$err" | grep -Fq -- "step-record.sh: --head:"
verdict_of $? "a --worktree inside another repository never defaults to its HEAD" "rc=$rc: $err"
rg=$(srd new-run)
GIT_DIR="$wt/.git" "$SR" --worktree "$wd" write --completion --run "$rg" --point pre-ci \
  >/dev/null 2>"$tmp/wd.err"
verdict_of $? "a defaulted write under an inherited GIT_DIR succeeds" "rc!=0: $(cat "$tmp/wd.err")"
cat "$wd/.claude/steps/$rg/"*-done-pre-ci.rec 2>/dev/null | grep -Fxq "head${TAB}$WD_HEAD2"
verdict "an inherited GIT_DIR does not redirect the --head default" "completion head is not the worktree's own"
rw=$(srd new-run)
GIT_DIR="$wt/.git" GIT_WORK_TREE="$wt" "$SR" --worktree "$wd" write --completion --run "$rw" \
  --point pre-ci >/dev/null 2>"$tmp/wd.err"
verdict_of $? "a defaulted write under an inherited GIT_WORK_TREE succeeds" "rc!=0: $(cat "$tmp/wd.err")"
cat "$wd/.claude/steps/$rw/"*-done-pre-ci.rec 2>/dev/null | grep -Fxq "head${TAB}$WD_HEAD2"
verdict "an inherited GIT_WORK_TREE does not redirect the --head default" "completion head is not the worktree's own"

# status: an omitted --head is the current HEAD, the completion naming it found.
rs=$(srd new-run)
srd write --completion --run "$rs" --point pre-ready-flip >/dev/null
rm -f "$GH_STUB_LOG"
srd status --point pre-ready-flip --repo acme/widgets >/dev/null 2>"$tmp/st.err"
rc=$?
[ "$rc" -eq 0 ] && gh_arg "repos/acme/widgets/statuses/$WD_HEAD2" && gh_arg state=success
verdict_of $? "status posts on the current HEAD when --head is omitted" "rc=$rc: $(cat "$tmp/st.err")"
# It is re-read per call: after a new commit no completion names the default,
# so status refuses and posts nothing.
git -C "$wd" commit -q --allow-empty -m "chore: fourth"
rm -f "$GH_STUB_LOG"
srd status --point pre-ready-flip --repo acme/widgets >/dev/null 2>"$tmp/st.err"
rc=$?
if [ "$rc" -eq 1 ] && [ ! -f "$GH_STUB_LOG" ]; then
  ok "status re-reads HEAD for its default"
else
  fail "rc=$rc: $(cat "$tmp/st.err")"
fi
rm -f "$GH_STUB_LOG"
srd status --point pre-ready-flip --head "" --repo acme/widgets >/dev/null 2>"$tmp/st.err"
rc=$?
if [ "$rc" -eq 2 ] && [ ! -f "$GH_STUB_LOG" ]; then
  ok "status refuses an explicit empty --head, never defaulting it"
else
  fail "rc=$rc: $(cat "$tmp/st.err")"
fi

# --- excerpt: the record excerpt screen, outside any worktree -----------------------
mkdir -p "$tmp/nowt"
ex=$(cd "$tmp/nowt" && "$SR" excerpt "$tmp/wide.txt")
verdict_of $? "excerpt runs outside a git work tree" "excerpt failed outside a work tree"
[ "$ex" = "$(sed -n "s/^excerpt${TAB}//p" "$recw")" ]
verdict "excerpt prints exactly what write stores" "excerpt differs from the stored one"
ex=$("$SR" excerpt "$tmp/secret.txt")
exrc=$?
[ "$exrc" -eq 0 ] && [ "$ex" = "[withheld: the secret screen flagged this excerpt]" ]
verdict "excerpt withholds a token-shaped text" "excerpt exited $exrc and printed: $ex"
ex=$(env PLANWRIGHT_SECRET_SCREEN_TOOL=broken "$SR" excerpt "$tmp/wide.txt")
exrc=$?
[ "$exrc" -eq 0 ] && [ "$ex" = "[withheld: the excerpt could not be screened]" ]
verdict "excerpt withholds what cannot be screened" "excerpt exited $exrc and printed: $ex"
"$SR" excerpt "$tmp/no-such-file" >/dev/null 2>&1
[ $? -eq 2 ]
verdict "excerpt refuses an unreadable file" "excerpt accepted a missing file"
"$SR" excerpt >/dev/null 2>&1
[ $? -eq 2 ]
verdict "excerpt without a file is a usage error" "excerpt ran without a file"
"$SR" excerpt "$tmp/wide.txt" "$tmp/wide.txt" >/dev/null 2>&1
[ $? -eq 2 ]
verdict "excerpt with two files is a usage error" "excerpt ran with two files"
"$SR" --worktree "$tmp/nowt" excerpt "$tmp/wide.txt" >/dev/null 2>&1
[ $? -eq 2 ]
verdict "excerpt with --worktree is a usage error" "excerpt ran with --worktree"

# --- the extension fields (custom-steps REQ-D1.10, REQ-D1.12, REQ-I1.10) ------------
# A fresh worktree, so no earlier section's run can stand behind a lookup.
wx="$tmp/wx"
fresh "$wx"
srx() { "$SR" --worktree "$wx" "$@"; }
# legacy_rec <file> <run> <point> <step> <outcome> <head> [<line>]...: a
# hand-written record in the form written before end heads, its sequence the
# file name's, plus any extra key<TAB>value lines.
legacy_rec() {
  _lf=$1 _lr=$2 _lp=$3 _ls=$4 _lo=$5 _lh=$6
  shift 6
  _lq=${_lf##*/}
  {
    printf 'type\tstep\nrun\t%s\nseq\t%s\npoint\t%s\nstep\t%s\nkind\tcommand\ntarget\tt\n' \
      "$_lr" "${_lq%%-*}" "$_lp" "$_ls"
    printf 'hosting\tisolated\nbackend\trunner\nsession\t\nhead\t%s\n' "$_lh"
    printf 'start\t2026-09-28T09:00:00Z\nend\t2026-09-28T09:00:01Z\noutcome\t%s\noutput\t\nskip-reason\t\n' "$_lo"
    for _ll in "$@"; do printf '%s\n' "$_ll"; done
  } >"$_lf" || fail "fixture: cannot write $_lf"
}
X_HEAD=$(git -C "$wx" rev-parse HEAD)
HX_A=4444444444444444444444444444444444444444
HX_B=5555555555555555555555555555555555555555
DIG_ABC=ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad
FP_1=6666666666666666666666666666666666666666
FP_2=7777777777777777777777777777777777777777
xbase="--kind command --target t --hosting isolated --backend runner --start 2026-10-06T10:00:00Z --end 2026-10-06T10:00:01Z"

rx=$(srx new-run)
# shellcheck disable=SC2086 # xbase is a fixed word list
rec=$(srx write --run "$rx" --point pre-ci --step plain $xbase --head "$HX_A" --end-head "$HX_B" --outcome passed)
grep -Fxq "end-head${TAB}$HX_B" "$rec" && grep -Fxq "head${TAB}$HX_A" "$rec"
verdict "a step record round-trips its end head beside its start head" "end head not stored"
# shellcheck disable=SC2086
rec=$(srx write --run "$rx" --point pre-ci --step dflt $xbase --head "$HX_A" --outcome passed)
grep -Fxq "end-head${TAB}$X_HEAD" "$rec"
verdict "an omitted end head is the worktree's HEAD when the record is written" "end head not defaulted"
# shellcheck disable=SC2086
srx write --run "$rx" --point pre-ci --step e $xbase --end-head "" --outcome passed >/dev/null 2>&1
[ $? -eq 2 ]
verdict "an explicit empty end head is refused, never defaulted" "empty --end-head accepted"
# shellcheck disable=SC2086
srx write --run "$rx" --point pre-ci --step e $xbase --end-head "abc123" --outcome passed >/dev/null 2>&1
[ $? -eq 2 ]
verdict "a short end head is refused" "short --end-head accepted"

# The outcome enum is closed at the six names, limited among them.
# shellcheck disable=SC2086
rec=$(srx write --run "$rx" --point pre-ci --step lim $xbase --outcome limited)
grep -Fxq "outcome${TAB}limited" "$rec"
verdict "write accepts a limited outcome" "limited refused"
srx render --run "$rx" --point pre-ci | grep '^| 3 |' | grep -Fq '| limited |'
verdict "a limited record renders its outcome" "limited not rendered"
for o in passed applied halted failed limited; do
  # shellcheck disable=SC2086
  srx write --run "$rx" --point convergence --step "o-$o" $xbase --outcome "$o" >/dev/null 2>&1
  verdict "the outcome '$o' is accepted" "outcome '$o' refused"
done
# shellcheck disable=SC2086
srx write --run "$rx" --point convergence --step o-x $xbase --outcome deferred >/dev/null 2>&1
[ $? -eq 2 ]
verdict "an outcome outside the six is refused" "a seventh outcome accepted"

# Skip codes: exactly one, the detail optional, a standing-on reference for
# reuse and resume only.
# The records the skips stand on, in a run of their own.
rref=$(srx new-run)
# shellcheck disable=SC2086
srx write --run "$rref" --point pre-ci --step sk-r $xbase --outcome passed >/dev/null
# shellcheck disable=SC2086
srx write --run "$rref" --point pre-ci --step sk-s $xbase --head "$HX_A" --end-head "$HX_B" --outcome applied >/dev/null
# shellcheck disable=SC2086
srx write --run "$rref" --point pre-ci --step sk-f $xbase --outcome failed >/dev/null
# shellcheck disable=SC2086
rec=$(srx write --run "$rx" --point pre-pr --step sk-m $xbase --outcome skipped --skip-code missing)
grep -Fxq "skip-code${TAB}missing" "$rec" && grep -Fxq "skip-reason${TAB}" "$rec"
verdict "a skipped record takes a code with no free-text detail" "code-only skip refused or misstored"
srx render --run "$rx" --point pre-pr | grep '^| 1 |' | grep -Fq '| skipped: missing |'
verdict "a coded skip renders its code" "coded skip not rendered"
# shellcheck disable=SC2086
rec=$(srx write --run "$rx" --point pre-pr --step sk-r $xbase --outcome skipped --skip-code reuse \
  --stands-on "$rref:pre-ci:001" --skip-reason "same fingerprint | twice")
grep -Fxq "stands-on${TAB}$rref:pre-ci:001" "$rec" && grep -Fxq "skip-code${TAB}reuse" "$rec"
verdict "a reuse skip round-trips the run, point, and sequence it stands on" "stands-on not stored"
srx render --run "$rx" --point pre-pr | grep '^| 2 |' \
  | grep -Fq "| skipped: reuse on $rref:pre-ci:001 \\(same fingerprint \\| twice\\) |"
verdict_of $? "a reuse skip renders its code, its record, and its detail table-safe" \
  "row: $(srx render --run "$rx" --point pre-pr | grep '^| 2 |')"
# shellcheck disable=SC2086
rec=$(srx write --run "$rx" --point pre-pr --step sk-s $xbase --outcome skipped --skip-code resume \
  --stands-on "$rref:pre-ci:002" --head "$HX_A" --end-head "$HX_B")
grep -Fxq "stands-on${TAB}$rref:pre-ci:002" "$rec" && grep -Fxq "end-head${TAB}$HX_B" "$rec"
verdict "a resume skip round-trips its reference and copied heads" "resume skip misstored"
# shellcheck disable=SC2086
srx write --run "$rx" --point pre-pr --step sk-a $xbase --outcome skipped --skip-code answered >/dev/null
verdict "an answered skip needs no reference" "answered skip refused"
xrefuse() {
  label=$1 field=$2
  shift 2
  # shellcheck disable=SC2086
  err=$(srx write --run "$rx" $xbase "$@" 2>&1 >/dev/null)
  rc=$?
  if [ "$rc" -eq 2 ] && printf '%s' "$err" | grep -Fq -- "step-record.sh: $field:" \
    && ! printf '%s' "$err" | grep -Fq EVIL; then
    ok "write refuses $label"
  else
    fail "write $label: rc=$rc err=$err"
  fi
}
xrefuse "a skipped step with no code" --skip-code --point pre-pr --step s --outcome skipped \
  --skip-reason "free text only"
xrefuse "a skipped step with two codes" --skip-code --point pre-pr --step s --outcome skipped \
  --skip-code missing --skip-code answered
xrefuse "an unknown skip code" --skip-code --point pre-pr --step s --outcome skipped --skip-code EVIL
xrefuse "a skip code on a step that ran" --skip-code --point pre-pr --step s --outcome passed \
  --skip-code missing
xrefuse "a reuse skip with no reference" --stands-on --point pre-pr --step s --outcome skipped \
  --skip-code reuse
xrefuse "a missing skip with a reference" --stands-on --point pre-pr --step s --outcome skipped \
  --skip-code missing --stands-on "$rx:pre-ci:001"
xrefuse "a malformed reference" --stands-on --point pre-pr --step s --outcome skipped \
  --skip-code reuse --stands-on "EVIL:pre-ci:001"
xrefuse "a reference to no record" --stands-on --point pre-pr --step s --outcome skipped \
  --skip-code resume --stands-on "$rx:pre-ci:099"
xrefuse "a reference naming the wrong point" --stands-on --point pre-pr --step s --outcome skipped \
  --skip-code resume --stands-on "$rx:convergence:001"
xrefuse "a reuse skip standing on another step's record" --stands-on --point pre-pr --step sk-s \
  --outcome skipped --skip-code reuse --stands-on "$rref:pre-ci:001"
xrefuse "a reuse skip standing on a failed record" --stands-on --point pre-pr --step sk-f \
  --outcome skipped --skip-code reuse --stands-on "$rref:pre-ci:003"
xrefuse "a reuse skip standing on an applied record" --stands-on --point pre-pr --step sk-s \
  --outcome skipped --skip-code reuse --stands-on "$rref:pre-ci:002"
xrefuse "a resume skip ending on another head than its record" --stands-on --point pre-pr \
  --step sk-s --outcome skipped --skip-code resume --stands-on "$rref:pre-ci:002" --end-head "$HX_A"
for f in --skip-code --stands-on --pool --wait --fingerprint --args-digest --refire-of; do
  xrefuse "an empty $f" "$f" --point post-pr --step s --outcome passed "$f" ""
done
xrefuse "an end earlier than the start" --end --point pre-pr --step s --outcome passed \
  --start 2026-10-06T10:00:00Z --end 2026-10-06T09:00:00Z
xrefuse "a re-fire record with no fingerprint" --fingerprint --point post-pr --step s \
  --outcome passed --refire-of pre-pr

# Pool, paths, and re-fire fields round-trip and render table-safe.
holder="pid 4242 step suite-long | @someone #12"
# shellcheck disable=SC2086
rec=$(srx write --run "$rx" --point pre-pr --step pooled $xbase --outcome passed \
  --pool suite --wait 37 --holder "$holder" --holder "pid 7 (full-suite)" --unpooled \
  --fingerprint "$FP_1" --args-digest "$DIG_ABC")
for pair in "pool${TAB}suite" "wait${TAB}37" "holder${TAB}$holder" "holder${TAB}pid 7 (full-suite)" \
  "unpooled${TAB}yes" "fingerprint${TAB}$FP_1" "args-digest${TAB}$DIG_ABC" "refire-of${TAB}"; do
  grep -Fxq "$pair" "$rec"
  verdict "a pooled paths record round-trips '$pair'" "record lacks '$pair'"
done
# shellcheck disable=SC2086
rec=$(srx write --run "$rx" --point pre-pr --step nofp $xbase --outcome passed \
  --fingerprint none --args-digest "$DIG_ABC")
grep -Fxq "fingerprint${TAB}none" "$rec" && grep -Fxq "pool${TAB}" "$rec" && grep -Fxq "unpooled${TAB}" "$rec"
verdict "a record round-trips an absent fingerprint, unpooled" "absent fingerprint misstored"
tbl=$(srx render --run "$rx" --point pre-pr)
printf '%s\n' "$tbl" | grep -Fq -- "- Row 5: pool \`suite\`; waited 37 s; holders: pid 4242 step suite-long \\| @&#8203;someone #&#8203;12 / pid 7 \\(full-suite\\); ran unpooled; fingerprint \`666666666666\`; args digest \`ba7816bf8f01\`"
verdict_of $? "the pool and paths fields render table-safe below the table" "detail: $(printf '%s\n' "$tbl" | grep -- '- Row 5')"
printf '%s\n' "$tbl" | grep -Fq -- "- Row 6: fingerprint none; args digest \`ba7816bf8f01\`"
verdict_of $? "an absent fingerprint renders as none" "detail: $(printf '%s\n' "$tbl" | grep -- '- Row 6')"
xrefuse "a malformed pool" --pool --point pre-pr --step s --outcome passed --pool "EVIL pool" --wait 1
xrefuse "a pool with no wait" --wait --point pre-pr --step s --outcome passed --pool suite
xrefuse "a wait with no pool" --pool --point pre-pr --step s --outcome passed --wait 3
xrefuse "a negative wait" --wait --point pre-pr --step s --outcome passed --pool suite --wait -EVIL
xrefuse "a holder with no pool" --pool --point pre-pr --step s --outcome passed --holder "pid 1"
xrefuse "a malformed fingerprint" --fingerprint --point pre-pr --step s --outcome passed \
  --fingerprint EVIL --args-digest "$DIG_ABC"
xrefuse "a fingerprint with no args digest" --args-digest --point pre-pr --step s --outcome passed \
  --fingerprint "$FP_1"
xrefuse "an args digest with no fingerprint" --fingerprint --point pre-pr --step s --outcome passed \
  --args-digest "$DIG_ABC"
xrefuse "a short args digest" --args-digest --point pre-pr --step s --outcome passed \
  --fingerprint "$FP_1" --args-digest "abc"
xrefuse "a non-hex args digest" --args-digest --point pre-pr --step s --outcome passed \
  --fingerprint "$FP_1" --args-digest "EVIL${DIG_ABC#????}"
xrefuse "an empty holder" --holder --point pre-pr --step s --outcome passed --pool suite --wait 1 \
  --holder ""
xrefuse "a re-fire record outside post-pr" --refire-of --point pre-pr --step s --outcome passed \
  --refire-of pre-ci
xrefuse "a re-fire naming another point" --refire-of --point post-pr --step s --outcome passed \
  --refire-of EVIL
# Re-fire records land under post-pr before its completion, which follows them.
# shellcheck disable=SC2086
srx write --run "$rx" --point post-pr --step push $xbase --head "$HX_A" --end-head "$HX_B" --outcome applied >/dev/null
# shellcheck disable=SC2086
rec=$(srx write --run "$rx" --point post-pr --step pooled $xbase --outcome passed --refire-of pre-pr \
  --fingerprint "$FP_1" --args-digest "$DIG_ABC")
grep -Fxq "refire-of${TAB}pre-pr" "$rec"
verdict "a re-fire record is written under post-pr before its completion" "re-fire record refused"
srx write --completion --run "$rx" --point post-pr >/dev/null
verdict "the post-pr completion follows the re-fire pass" "completion refused after re-fire"
tbl=$(srx render --run "$rx" --point post-pr)
printf '%s\n' "$tbl" | grep '^| 1 |' | grep -Fq "| 444444444444 to 555555555555 |"
verdict_of $? "a step that moved the head renders both heads" "row: $(printf '%s\n' "$tbl" | grep '^| 1 |')"
printf '%s\n' "$tbl" | grep -Fq -- "- Row 2: fingerprint \`666666666666\`; args digest \`ba7816bf8f01\`; re-fire of \`pre-pr\`"
verdict_of $? "a re-fire record renders its declaring point" "detail: $(printf '%s\n' "$tbl" | grep -- '- Row 2')"
# shellcheck disable=SC2086
srx write --run "$rx" --point post-pr --step late $xbase --outcome passed --refire-of pre-pr \
  >/dev/null 2>&1
[ $? -eq 2 ]
verdict "a re-fire record after the post-pr completion is refused" "late re-fire accepted"
srx write --completion --run "$rx" --point pre-ci --end-head "$HX_B" >/dev/null 2>&1
[ $? -eq 2 ]
verdict "a completion takes no end head of its own" "completion accepted --end-head"

# The full-suite record: written beside the point records and rendered as its
# own row of the audit fold.
rf=$(srx new-run)
rec=$(srx write --full-suite --run "$rf" --pool suite --wait 12 --wait-outcome taken \
  --holder "pid 99 (full-suite) | other" --start 2026-10-06T11:00:00Z --end 2026-10-06T11:09:00Z)
for pair in "type${TAB}full-suite" "pool${TAB}suite" "wait${TAB}12" "wait-outcome${TAB}taken" \
  "holder${TAB}pid 99 (full-suite) | other" "unpooled${TAB}no" \
  "start${TAB}2026-10-06T11:00:00Z" "end${TAB}2026-10-06T11:09:00Z"; do
  grep -Fxq "$pair" "$rec"
  verdict "a full-suite record round-trips '$pair'" "full-suite record lacks '$pair'"
done
srx write --full-suite --run "$rf" --pool suite --wait 0 --wait-outcome unpooled \
  --start 2026-10-06T11:10:00Z --end 2026-10-06T11:20:00Z >/dev/null
# shellcheck disable=SC2086
srx write --run "$rf" --point pre-ci --step c $xbase --outcome passed >/dev/null
tbl=$(srx render --run "$rf")
printf '%s\n' "$tbl" | grep -Fq "## Full-suite runs (run \`$rf\`)" \
  && printf '%s\n' "$tbl" | grep -Fxq "| 1 | suite | taken | 12 | pid 99 \\(full-suite\\) \\| other | no | 2026-10-06T11:00:00Z | 2026-10-06T11:09:00Z |" \
  && printf '%s\n' "$tbl" | grep -Fxq "| 2 | suite | unpooled | 0 |  | yes | 2026-10-06T11:10:00Z | 2026-10-06T11:20:00Z |"
verdict "render folds the full-suite records in as full-suite rows" "render: $tbl"
printf '%s\n' "$tbl" | grep -Fq "## Steps at \`pre-ci\`" && ! printf '%s\n' "$tbl" | grep -Fq 'Steps at ``'
verdict "full-suite records open no point table" "render: $tbl"
! srx render --run "$rf" --point pre-ci | grep -Fq "Full-suite"
verdict "a render of named points leaves the full-suite rows out" "full-suite rows under a named point"
for bad in "--pool EVIL! --wait 1 --wait-outcome taken" "--pool suite --wait 1 --wait-outcome EVIL" \
  "--pool suite --wait-outcome taken" "--pool suite --wait 1 --wait-outcome taken --point pre-ci" \
  "--pool suite --wait 1"; do
  # shellcheck disable=SC2086 # fixed word lists
  srx write --full-suite --run "$rf" $bad --start 2026-10-06T11:00:00Z --end 2026-10-06T11:00:01Z >/dev/null 2>&1
  [ $? -eq 2 ]
  verdict "a full-suite write refuses '$bad'" "full-suite write accepted '$bad'"
done

# --- fingerprint and args-digest (REQ-I1.7, REQ-I1.10) -------------------------------
wfp="$tmp/wfp"
fresh "$wfp"
mkdir -p "$wfp/a" "$wfp/b" "$wfp/c"
printf 'one\n' >"$wfp/a/x"
printf 'two\n' >"$wfp/b/y"
printf 'one\n' >"$wfp/c/x"
printf 'build/\n' >"$wfp/.gitignore"
git -C "$wfp" add -A && git -C "$wfp" commit -q -m "chore: content"
fp() { "$SR" --worktree "$wfp" fingerprint --paths "$1"; }
fpa=$(fp a)
printf '%s\n' "$fpa" | grep -Eq '^([0-9a-f]{40}|[0-9a-f]{64})$'
verdict "fingerprint prints a commit-id-shaped digest" "fingerprint printed '$fpa'"
printf 'three\n' >"$wfp/b/y" && git -C "$wfp" commit -q -am "chore: outside"
[ "$(fp a)" = "$fpa" ]
verdict "a commit outside the paths leaves the fingerprint unchanged" "fingerprint moved"
printf 'four\n' >"$wfp/a/x" && git -C "$wfp" commit -q -am "chore: inside"
fpa2=$(fp a)
[ "$fpa2" != "$fpa" ]
verdict "a commit touching a declared path changes the fingerprint" "fingerprint did not move"
printf 'dirty\n' >"$wfp/a/x"
[ "$(fp a)" = none ] && [ "$(fp b)" != none ]
verdict "an uncommitted change under a declared path leaves no fingerprint" "dirty tree fingerprinted"
git -C "$wfp" checkout -q -- a/x
: >"$wfp/a/untracked"
[ "$(fp a)" = none ]
verdict "an untracked file under a declared path leaves no fingerprint" "untracked file ignored"
rm -f "$wfp/a/untracked"
mkdir -p "$wfp/a/build" && : >"$wfp/a/build/out"
[ "$(fp a)" = "$fpa2" ] && [ "$(fp .)" != none ]
verdict "an ignored file never voids a fingerprint" "ignored file voided it"
fpn=$(fp "a nope")
printf '%s\n' "$fpn" | grep -Eq '^[0-9a-f]+$' && [ "$fpn" != "$fpa2" ]
verdict "an absent path contributes its marker" "absent path: '$fpn'"
[ "$(fp c)" != "$(fp a)" ] || fail "fixture: c and a should differ before the copy"
printf 'four\n' >"$wfp/c/x" && git -C "$wfp" commit -q -am "chore: same content"
[ "$(fp c)" != "$(fp a)" ] && [ "$(fp "a c")" != "$(fp "c a")" ]
verdict "two path word sets over the same content fingerprint differently" "word sets collided"
for w in "/a" "-a" "a/../b" ".." "a*" "a b/../c" ""; do
  "$SR" --worktree "$wfp" fingerprint --paths "$w" >/dev/null 2>&1
  [ $? -eq 2 ]
  verdict "fingerprint refuses the path words '$w'" "fingerprint accepted '$w'"
done
[ "$("$SR" args-digest abc)" = "$DIG_ABC" ] \
  && [ "$("$SR" args-digest "")" = e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 ]
verdict "args-digest prints the SHA-256 of the args string as written" "args-digest wrong"

# --- lookup: reuse (REQ-I1.8) ---------------------------------------------------------
wlk="$tmp/wlk"
fresh "$wlk"
srk() { "$SR" --worktree "$wlk" "$@"; }
kbase="--kind command --hosting isolated --backend runner --start 2026-10-06T12:00:00Z --end 2026-10-06T12:00:01Z"
reuse() { srk lookup reuse --step chk --target "suite run" --args-digest "${1:-$DIG_ABC}" --fingerprint "${2:-$FP_1}"; }
k1=$(srk new-run)
# shellcheck disable=SC2086
srk write --run "$k1" --point pre-ci --step chk --target "suite run" $kbase --outcome failed \
  --fingerprint "$FP_1" --args-digest "$DIG_ABC" >/dev/null
reuse >/dev/null
[ $? -eq 3 ]
verdict "reuse never stands on a failed record" "a failed record was reusable"
# A legacy record carrying the fields but no end head matches nothing.
legacy_rec "$wlk/.claude/steps/$k1/002-step-pre-ci.rec" "$k1" pre-ci chk passed "$HX_A" \
  "fingerprint${TAB}$FP_1" "args-digest${TAB}$DIG_ABC"
sed -i.bak "s/^target${TAB}t\$/target${TAB}suite run/" "$wlk/.claude/steps/$k1/002-step-pre-ci.rec" \
  && rm -f "$wlk/.claude/steps/$k1/002-step-pre-ci.rec.bak"
reuse >/dev/null
[ $? -eq 3 ]
verdict "a record written before the extension matches no reuse lookup" "a legacy record was reusable"
k2=$(srk new-run)
# shellcheck disable=SC2086
srk write --run "$k2" --point pre-pr --step chk --target "suite run" $kbase --outcome passed \
  --fingerprint "$FP_1" --args-digest "$DIG_ABC" >/dev/null
out=$(reuse)
rc=$?
[ "$rc" -eq 0 ] && printf '%s\n' "$out" | grep -q "^record${TAB}$k2:pre-pr:001${TAB}chk${TAB}"
verdict "reuse matches a passed record of the same step, target, digest, and fingerprint" "rc=$rc out=$out"
k3=$(srk new-run)
out=$(reuse) && printf '%s\n' "$out" | grep -q "^record${TAB}$k2:pre-pr:001"
verdict "reuse matches across runs" "out=$out"
reuse "$(printf 'f%.0s' 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37 38 39 40 41 42 43 44 45 46 47 48 49 50 51 52 53 54 55 56 57 58 59 60 61 62 63 64)" >/dev/null
[ $? -eq 3 ]
verdict "reuse never matches another args digest" "digest ignored"
reuse "$DIG_ABC" "$FP_2" >/dev/null
[ $? -eq 3 ]
verdict "reuse never matches another fingerprint" "fingerprint ignored"
reuse "$DIG_ABC" none >/dev/null
[ $? -eq 3 ]
verdict "a step with no fingerprint is never reused" "none matched"
srk lookup reuse --step chk --target "other run" --args-digest "$DIG_ABC" --fingerprint "$FP_1" >/dev/null
[ $? -eq 3 ]
verdict "reuse never matches another target" "target ignored"
srk lookup reuse --step chk2 --target "suite run" --args-digest "$DIG_ABC" --fingerprint "$FP_1" >/dev/null
[ $? -eq 3 ]
verdict "reuse never matches another step id" "step id ignored"
# Within the current run, and a re-fire record, both qualify.
# shellcheck disable=SC2086
srk write --run "$k3" --point post-pr --step chk --target "suite run" $kbase --outcome passed \
  --fingerprint "$FP_2" --args-digest "$DIG_ABC" --refire-of pre-pr >/dev/null
out=$(reuse "$DIG_ABC" "$FP_2") && printf '%s\n' "$out" | grep -q "^record${TAB}$k3:post-pr:001"
verdict "reuse matches a re-fire record of the current run" "out=$out"
srk lookup reuse --step "EVIL step" --target t --args-digest "$DIG_ABC" --fingerprint "$FP_1" >/dev/null 2>&1
[ $? -eq 2 ]
verdict "a reuse lookup refuses a malformed step id" "malformed step accepted"

# --- lookup: resume (REQ-J1.1) -------------------------------------------------------
wrs="$tmp/wrs"
fresh "$wrs"
srs() { "$SR" --worktree "$wrs" "$@"; }
sbase="--kind command --target t --hosting in-session --backend terminal --start 2026-10-06T13:00:00Z --end 2026-10-06T13:00:01Z"
i1=$(srs new-run)
# shellcheck disable=SC2086
srs write --run "$i1" --point pre-pr --step one $sbase --head "$HX_A" --end-head "$HX_A" --outcome passed >/dev/null
# shellcheck disable=SC2086
srs write --run "$i1" --point pre-pr --step two $sbase --head "$HX_A" --end-head "$HX_B" --outcome applied --session s-2 >/dev/null
# shellcheck disable=SC2086
srs write --run "$i1" --point pre-pr --step three $sbase --head "$HX_B" --end-head "$HX_B" --outcome limited >/dev/null
# shellcheck disable=SC2086
srs write --run "$i1" --point pre-pr --step four $sbase --head "$HX_B" --end-head "$HX_B" --outcome passed >/dev/null
out=$(srs lookup resume --run "$i1" --point pre-pr --head "$HX_B")
[ $? -eq 3 ] && [ -z "$out" ]
verdict "resume skips nothing when the leading record ended on another head" "out=$out"
# A run whose leading steps all ended on the current head.
i2=$(srs new-run)
# shellcheck disable=SC2086
srs write --run "$i2" --point post-pr --step one $sbase --head "$HX_A" --end-head "$HX_B" --outcome passed >/dev/null
# shellcheck disable=SC2086
srs write --run "$i2" --point post-pr --step two $sbase --head "$HX_B" --end-head "$HX_B" --outcome applied --session s-2 >/dev/null
# shellcheck disable=SC2086
srs write --run "$i2" --point post-pr --step three $sbase --head "$HX_B" --end-head "$HX_B" --outcome limited >/dev/null
# shellcheck disable=SC2086
srs write --run "$i2" --point post-pr --step four $sbase --head "$HX_B" --end-head "$HX_B" --outcome passed >/dev/null
out=$(srs lookup resume --run "$i2" --point post-pr --head "$HX_B")
rc=$?
want="record${TAB}$i2:post-pr:001${TAB}one${TAB}$HX_A${TAB}$HX_B${TAB}in-session${TAB}${TAB}.claude/steps/$i2/001-step-post-pr.rec
record${TAB}$i2:post-pr:002${TAB}two${TAB}$HX_B${TAB}$HX_B${TAB}in-session${TAB}s-2${TAB}.claude/steps/$i2/002-step-post-pr.rec"
[ "$rc" -eq 0 ] && [ "$out" = "$want" ]
verdict "resume returns the leading passed or applied prefix ending on the head" "rc=$rc out=$out"
srs lookup resume --run "$i2" --point post-pr --head "$HX_A" >/dev/null
[ $? -eq 3 ]
verdict "resume skips nothing once the head moved" "a moved head matched"
srs lookup resume --run "$i2" --point pre-pr --head "$HX_B" >/dev/null
[ $? -eq 3 ]
verdict "resume reads only the named point" "another point matched"
# A chained resume: the skips stand for the records they stood on.
i3=$(srs new-run)
# shellcheck disable=SC2086
srs write --run "$i3" --point post-pr --step one $sbase --head "$HX_A" --end-head "$HX_B" --outcome skipped \
  --skip-code resume --stands-on "$i2:post-pr:001" >/dev/null
# shellcheck disable=SC2086
srs write --run "$i3" --point post-pr --step two $sbase --head "$HX_B" --end-head "$HX_B" --outcome skipped \
  --skip-code resume --stands-on "$i2:post-pr:002" >/dev/null
# shellcheck disable=SC2086
srs write --run "$i3" --point post-pr --step three $sbase --head "$HX_B" --end-head "$HX_B" --outcome limited >/dev/null
out=$(srs lookup resume --run "$i3" --point post-pr --head "$HX_B") && [ "$out" = "$want" ]
verdict "a chained resume stands on the original records" "out=$out"
# A legacy record (no end head) leads nothing.
i4=$(srs new-run)
legacy_rec "$wrs/.claude/steps/$i4/001-step-pre-ci.rec" "$i4" pre-ci one passed "$HX_B"
srs lookup resume --run "$i4" --point pre-ci --head "$HX_B" >/dev/null
[ $? -eq 3 ]
verdict "a record written before the extension matches no resume lookup" "a legacy record resumed"
for bad in "--run EVIL --point pre-pr" "--run 999999 --point pre-pr" "--run $i2 --point pre-ready-flip" \
  "--run $i2 --point unit-selected"; do
  # shellcheck disable=SC2086 # fixed word lists
  srs lookup resume $bad --head "$HX_B" >/dev/null 2>&1
  [ $? -eq 2 ]
  verdict "a resume lookup refuses '$bad'" "resume lookup accepted '$bad'"
done

# --- status: limited records (REQ-E1.6, REQ-J1.2) -------------------------------------
# Each scenario its own worktree: the scan reads every run in the cache.
lim_n=0
lim_wt() {
  lim_n=$((lim_n + 1))
  wlm="$tmp/wlim$lim_n"
  fresh "$wlm"
}
srl() { PATH="$stub:$PATH" "$SR" --worktree "$wlm" "$@"; }
lrec() {
  # lrec <run> <point> <step> <outcome> <end-head> [extra...]
  _r=$1 _p=$2 _s=$3 _o=$4 _e=$5
  shift 5
  srl write --run "$_r" --point "$_p" --step "$_s" --kind command --target t --hosting in-session \
    --backend terminal --head "$_e" --end-head "$_e" --start 2026-10-06T14:00:00Z \
    --end 2026-10-06T14:00:01Z --outcome "$_o" "$@" >/dev/null || fail "fixture: cannot write $_o record"
}
lstate() {
  rm -f "$GH_STUB_LOG"
  srl status --point "${2:-pre-ready-flip}" --head "$1" --repo acme/widgets >/dev/null 2>"$tmp/st.err"
  ST_RC=$?
}
flip() {
  # flip <head> [<outcome> [<step>]]: one flip attempt on the head, one step
  # (default gate) of the outcome.
  _f=$(srl new-run)
  [ -z "${2:-}" ] || lrec "$_f" pre-ready-flip "${3:-gate}" "$2" "$1"
  srl write --completion --run "$_f" --point pre-ready-flip --head "$1" >/dev/null
}
lim_wt
flip "$HX_A" limited
lstate "$HX_A"
[ "$ST_RC" -eq 0 ] && gh_arg state=failure
verdict_of $? "an attempt holding a limited record derives failure" "rc=$ST_RC $(cat "$tmp/st.err")"
grep -Eq "^description=pre-ready-flip: a step stayed limited \(run [0-9]{6}\)$" "$GH_STUB_LOG"
verdict_of $? "a limited failure says so in the description" "description: $(grep '^description=' "$GH_STUB_LOG")"
lim_wt
f=$(srl new-run)
lrec "$f" pre-ready-flip a passed "$HX_A"
lrec "$f" pre-ready-flip b limited "$HX_A"
srl write --completion --run "$f" --point pre-ready-flip --head "$HX_A" >/dev/null
lstate "$HX_A"
[ "$ST_RC" -eq 0 ] && gh_arg state=failure
verdict "a limited record beside passed records derives failure" "rc=$ST_RC"
lim_wt
u=$(srl new-run)
lrec "$u" post-pr review limited "$HX_A"
flip "$HX_A" passed
lstate "$HX_A"
[ "$ST_RC" -eq 0 ] && gh_arg state=failure
verdict "an earlier unit run's limited record on the flipped head derives failure" "rc=$ST_RC"
flip "$HX_B" passed
lstate "$HX_B"
[ "$ST_RC" -eq 0 ] && gh_arg state=success
verdict "a limited record ending on another head does not count" "rc=$ST_RC"
lim_wt
flip "$HX_A" limited
flip "$HX_A" passed other
lstate "$HX_A"
[ "$ST_RC" -eq 0 ] && gh_arg state=failure
verdict "an earlier flip attempt's limited record on the head derives failure" "rc=$ST_RC"
lim_wt
flip "$HX_A" failed
flip "$HX_A" passed
lstate "$HX_A"
[ "$ST_RC" -eq 0 ] && gh_arg state=success
verdict "an earlier flip attempt's failed record is still ignored" "rc=$ST_RC"
for ret in passed applied resume; do
  lim_wt
  u0=$(srl new-run)
  lrec "$u0" post-pr review2 passed "$HX_A"
  u=$(srl new-run)
  lrec "$u" post-pr review2 limited "$HX_A"
  v=$(srl new-run)
  if [ "$ret" = resume ]; then
    lrec "$v" post-pr review2 skipped "$HX_A" --skip-code resume --stands-on "$u0:post-pr:001"
  else
    lrec "$v" post-pr review2 "$ret" "$HX_A"
  fi
  flip "$HX_A" passed
  lstate "$HX_A"
  [ "$ST_RC" -eq 0 ] && gh_arg state=success
  verdict "a later run's $ret record of the step on the head retires the limited one" "rc=$ST_RC"
done
lim_wt
u0=$(srl new-run)
lrec "$u0" post-pr review2 passed "$HX_A"
u=$(srl new-run)
lrec "$u" post-pr review2 limited "$HX_A"
flip "$HX_A" passed
lstate "$HX_A"
[ "$ST_RC" -eq 0 ] && gh_arg state=failure
verdict "an earlier run's pass of the step retires nothing" "rc=$ST_RC"
v=$(srl new-run)
lrec "$v" post-pr review2 passed "$HX_B"
flip "$HX_A" passed
lstate "$HX_A"
[ "$ST_RC" -eq 0 ] && gh_arg state=failure
verdict "a later pass ending on another head retires nothing" "rc=$ST_RC"
# A record claiming a higher run than its directory, or carrying a withheld
# step id, retires nothing.
w=$(srl new-run)
legacy_rec "$wlm/.claude/steps/$w/001-step-post-pr.rec" 999999 post-pr review2 passed "$HX_A" "end-head${TAB}$HX_A"
flip "$HX_A" passed
lstate "$HX_A"
[ "$ST_RC" -eq 0 ] && gh_arg state=failure
verdict "a record whose stored run disagrees with its path retires nothing" "rc=$ST_RC"
# A resume skip whose named record is missing or another step's retires nothing.
# Each fresh worktree numbers its runs from 000001: u0, u, v, then the flip.
for target in 000001:post-pr:009 000002:post-pr:001; do
  lim_wt
  u0=$(srl new-run)
  lrec "$u0" post-pr review2 passed "$HX_A"
  u=$(srl new-run)
  lrec "$u" post-pr review2 limited "$HX_A"
  v=$(srl new-run)
  legacy_rec "$wlm/.claude/steps/$v/001-step-post-pr.rec" "$v" post-pr review2 skipped "$HX_A" \
    "end-head${TAB}$HX_A" "skip-code${TAB}resume" "stands-on${TAB}$target"
  flip "$HX_A" passed
  lstate "$HX_A"
  [ "$ST_RC" -eq 0 ] && gh_arg state=failure
  verdict "a resume skip standing on $target retires nothing" "rc=$ST_RC"
done
lim_wt
u=$(srl new-run)
v=$(srl new-run)
PLANWRIGHT_SECRET_SCREEN_TOOL=broken srl write --run "$v" --point post-pr --step other --kind command \
  --target t --hosting in-session --backend terminal --head "$HX_A" --end-head "$HX_A" \
  --start 2026-10-06T14:00:00Z --end 2026-10-06T14:00:01Z --outcome passed >/dev/null
PLANWRIGHT_SECRET_SCREEN_TOOL=broken srl write --run "$u" --point post-pr --step review3 --kind command \
  --target t --hosting in-session --backend terminal --head "$HX_A" --end-head "$HX_A" \
  --start 2026-10-06T14:00:00Z --end 2026-10-06T14:00:01Z --outcome limited >/dev/null
flip "$HX_A" passed
lstate "$HX_A"
[ "$ST_RC" -eq 0 ] && gh_arg state=failure
verdict "withheld step ids never retire one another" "rc=$ST_RC"
lim_wt
u=$(srl new-run)
lrec "$u" post-pr review limited "$HX_A"
v=$(srl new-run)
lrec "$v" post-pr other passed "$HX_A"
lrec "$v" post-pr review skipped "$HX_A" --skip-code answered
flip "$HX_A" passed
lstate "$HX_A"
[ "$ST_RC" -eq 0 ] && gh_arg state=failure
verdict "another step's pass, or a non-resume skip, retires nothing" "rc=$ST_RC"
lim_wt
u=$(srl new-run)
mkdir -p "$wlm/.claude/steps/$u"
legacy_rec "$wlm/.claude/steps/$u/001-step-post-pr.rec" "$u" post-pr review limited "$HX_A"
flip "$HX_A" passed
lstate "$HX_A"
[ "$ST_RC" -eq 0 ] && gh_arg state=success
verdict "a record with no end head never counts toward the limited scan" "rc=$ST_RC"

# --- readers: untrusted records, empty caches, and the edges of each lookup ----------
wed="$tmp/wed"
fresh "$wed"
sre() { "$SR" --worktree "$wed" "$@"; }
e1=$(sre new-run)
out=$(printf 'type\tstep\nend-head\t%s\noutcome\tpassed\nstep\tchk\ntarget\tt\nargs-digest\t%s\nfingerprint\t%s\n' \
  "$HX_A" "$DIG_ABC" "$FP_1" | sre lookup reuse --step chk --target t \
  --args-digest "$DIG_ABC" --fingerprint "$FP_1" 2>/dev/null)
rc=$?
[ "$rc" -eq 3 ] && [ -z "$out" ]
verdict "a reuse lookup over runs holding no record finds nothing and reads no stdin" "rc=$rc out=$out"
ebase="--kind command --target t --hosting isolated --backend runner --start 2026-10-06T15:00:00Z --end 2026-10-06T15:00:01Z --fingerprint $FP_1 --args-digest $DIG_ABC"
for o in applied limited failed; do
  # shellcheck disable=SC2086 # ebase is a fixed word list
  sre write --run "$e1" --point pre-ci --step chk $ebase --outcome "$o" >/dev/null
done
# shellcheck disable=SC2086
sre write --run "$e1" --point pre-ci --step base $ebase --outcome passed >/dev/null
sre lookup reuse --step chk --target t --args-digest "$DIG_ABC" --fingerprint "$FP_1" >/dev/null
[ $? -eq 3 ]
verdict "reuse stands only on a passed record, never applied, limited, or failed" "matched"
e1s="$wed/.claude/steps/$e1/005-step-pre-ci.rec"
legacy_rec "$e1s" "$e1" pre-ci chk skipped "$HX_A" "end-head${TAB}$HX_A" "skip-code${TAB}reuse" \
  "stands-on${TAB}$e1:pre-ci:004" "fingerprint${TAB}$FP_1" "args-digest${TAB}$DIG_ABC"
sre lookup reuse --step chk --target t --args-digest "$DIG_ABC" --fingerprint "$FP_1" >/dev/null
[ $? -eq 3 ]
verdict "reuse never stands on a skipped record" "a skip matched"
# A planted record whose stored run disagrees with its directory, or whose
# session carries a tab, is never printed.
e2=$(sre new-run)
legacy_rec "$wed/.claude/steps/$e2/001-step-pre-ci.rec" 000001 pre-ci chk passed "$HX_A" \
  "end-head${TAB}$HX_A" "fingerprint${TAB}$FP_1" "args-digest${TAB}$DIG_ABC"
sre lookup reuse --step chk --target t --args-digest "$DIG_ABC" --fingerprint "$FP_1" >/dev/null
[ $? -eq 3 ]
verdict "reuse never stands on a record whose stored run disagrees with its path" "forged run matched"
legacy_rec "$wed/.claude/steps/$e2/002-step-pre-ci.rec" "$e2" pre-ci chk passed "$HX_A" \
  "end-head${TAB}$HX_A" "fingerprint${TAB}$FP_1" "args-digest${TAB}$DIG_ABC"
sed -i.bak "s/^session${TAB}\$/session${TAB}s-1${TAB}EXTRA/" "$wed/.claude/steps/$e2/002-step-pre-ci.rec" \
  && rm -f "$wed/.claude/steps/$e2/002-step-pre-ci.rec.bak"
out=$(sre lookup reuse --step chk --target t --args-digest "$DIG_ABC" --fingerprint "$FP_1")
[ $? -eq 3 ] && [ -z "$out" ]
verdict "reuse never prints a record whose session breaks its grammar" "out=$out"
# Resume: a leading record that does not qualify ends the prefix.
for lead in failed halted reuse resume-on-failed resume-on-other-head; do
  e3=$(sre new-run)
  f1="$wed/.claude/steps/$e3/001-step-pre-pr.rec"
  case $lead in
    failed | halted) legacy_rec "$f1" "$e3" pre-pr one "$lead" "$HX_A" "end-head${TAB}$HX_A" ;;
    reuse)
      legacy_rec "$f1" "$e3" pre-pr one skipped "$HX_A" "end-head${TAB}$HX_A" \
        "skip-code${TAB}reuse" "stands-on${TAB}$e3:pre-pr:003"
      ;;
    resume-on-failed)
      legacy_rec "$f1" "$e3" pre-pr one skipped "$HX_A" "end-head${TAB}$HX_A" \
        "skip-code${TAB}resume" "stands-on${TAB}$e3:pre-pr:004"
      ;;
    resume-on-other-head)
      legacy_rec "$f1" "$e3" pre-pr one skipped "$HX_A" "end-head${TAB}$HX_A" \
        "skip-code${TAB}resume" "stands-on${TAB}$e3:pre-pr:003"
      ;;
  esac
  legacy_rec "$wed/.claude/steps/$e3/002-step-pre-pr.rec" "$e3" pre-pr two passed "$HX_A" "end-head${TAB}$HX_A"
  legacy_rec "$wed/.claude/steps/$e3/003-step-pre-pr.rec" "$e3" pre-pr one passed "$HX_B" "end-head${TAB}$HX_B"
  legacy_rec "$wed/.claude/steps/$e3/004-step-pre-pr.rec" "$e3" pre-pr one failed "$HX_A" "end-head${TAB}$HX_A"
  out=$(sre lookup resume --run "$e3" --point pre-pr --head "$HX_A")
  [ $? -eq 3 ] && [ -z "$out" ]
  verdict "a leading $lead record ends the resume prefix" "out=$out"
done
# A skipped record from before skip codes renders its free text as written.
e4=$(sre new-run)
legacy_rec "$wed/.claude/steps/$e4/001-step-pre-ci.rec" "$e4" pre-ci old skipped "$HX_A"
sed -i.bak "s/^skip-reason${TAB}\$/skip-reason${TAB}needs gitleaks | on PATH/" "$wed/.claude/steps/$e4/001-step-pre-ci.rec" \
  && rm -f "$wed/.claude/steps/$e4/001-step-pre-ci.rec.bak"
sre render --run "$e4" | grep '^| 1 |' | grep -Fq '| skipped: needs gitleaks \| on PATH |'
verdict_of $? "a skip from before skip codes renders its reason as written" "row: $(sre render --run "$e4" | grep '^| 1 |')"

# Fingerprint edges: spellings git normalizes, files git stops looking at,
# words reaching through a symbolic link, and a worktree with no commit.
for w in "a//x" "a/./x" "./a/x"; do
  fw=$(fp "$w")
  printf 'five\n' >"$wfp/a/x" && git -C "$wfp" commit -q -am "chore: touch a/x"
  [ "$(fp "$w")" != "$fw" ] && [ "$fw" != none ]
  verdict "the spelling '$w' still tracks its content" "'$w' fingerprint did not move"
  printf 'four\n' >"$wfp/a/x" && git -C "$wfp" commit -q -am "chore: restore a/x"
done
git -C "$wfp" update-index --skip-worktree a/x
printf 'hidden\n' >"$wfp/a/x"
[ "$(fp a)" = none ]
verdict "a skip-worktree file under a word leaves no fingerprint" "skip-worktree change fingerprinted"
git -C "$wfp" update-index --no-skip-worktree a/x
git -C "$wfp" checkout -q -- a/x
git -C "$wfp" update-index --assume-unchanged a/x
[ "$(fp a)" = none ]
verdict "an assume-unchanged file under a word leaves no fingerprint" "assume-unchanged fingerprinted"
git -C "$wfp" update-index --no-assume-unchanged a/x
ln -s a "$wfp/al" && git -C "$wfp" add al && git -C "$wfp" commit -q -m "chore: link"
[ "$(fp al/x)" = none ] && [ "$(fp al)" != none ]
verdict "a word reaching through a symbolic link leaves no fingerprint" "al/x did not refuse"
wun="$tmp/wun"
mkdir -p "$wun" && git -C "$wun" init -q -b main
"$SR" --worktree "$wun" fingerprint --paths a >/dev/null 2>&1
[ $? -eq 1 ]
verdict "fingerprint in a worktree with no commit is a runtime failure" "not exit 1"
if [ -w /dev/full ]; then
  "$SR" args-digest abc >/dev/full 2>/dev/null
  [ $? -eq 1 ]
  verdict "args-digest fails when it cannot print" "a failed print exited non-1"
  "$SR" --worktree "$wfp" fingerprint --paths . >/dev/full 2>/dev/null
  [ $? -eq 1 ]
  verdict "fingerprint fails when it cannot print" "a failed print exited non-1"
fi

# --- iteration-two edges: the loader's checks, the attempt, and holders ---------------
wld="$tmp/wld"
fresh "$wld"
srd2() { PATH="$stub:$PATH" "$SR" --worktree "$wld" "$@"; }
l1=$(srd2 new-run)
lgood() {
  # lgood <file> <run> [<line>]...: a well-formed passed chk record, plus lines.
  _gf=$1 _gr=$2
  shift 2
  legacy_rec "$_gf" "$_gr" pre-ci chk passed "$HX_A" "end-head${TAB}$HX_A" \
    "fingerprint${TAB}$FP_1" "args-digest${TAB}$DIG_ABC" "$@"
}
rlook() { srd2 lookup reuse --step chk --target t --args-digest "$DIG_ABC" --fingerprint "$FP_1" >/dev/null 2>&1; }
n=0
for bad in seq point dup-key no-tab hosting end-head type; do
  n=$((n + 1))
  f="$wld/.claude/steps/$l1/00$n-step-pre-ci.rec"
  lgood "$f" "$l1"
  case $bad in
    seq) sed -i.bak "s/^seq${TAB}.*/seq${TAB}099/" "$f" ;;
    point) sed -i.bak "s/^point${TAB}.*/point${TAB}pre-pr/" "$f" ;;
    dup-key) printf 'outcome\tpassed\n' >>"$f" ;;
    no-tab) printf 'stray line\n' >>"$f" ;;
    hosting) sed -i.bak "s/^hosting${TAB}.*/hosting${TAB}EVIL/" "$f" ;;
    end-head) sed -i.bak "s/^end-head${TAB}.*/end-head${TAB}zzz/" "$f" ;;
    type) sed -i.bak "s/^type${TAB}.*/type${TAB}stepx/" "$f" ;;
  esac
  rm -f "$f.bak"
  rlook
  [ $? -eq 3 ]
  verdict "reuse never stands on a record with a bad $bad" "a bad $bad matched"
  rm -f "$f"
done
# A withheld target matches nothing, even when the caller passes its placeholder.
srd2 write --run "$l1" --point pre-ci --step chk --kind command --target "run $tok" --hosting isolated \
  --backend runner --start 2026-10-06T16:00:00Z --end 2026-10-06T16:00:01Z --outcome passed \
  --fingerprint "$FP_1" --args-digest "$DIG_ABC" >/dev/null
for tgt in "run $tok" "[withheld: the secret screen flagged this value]"; do
  srd2 lookup reuse --step chk --target "$tgt" --args-digest "$DIG_ABC" --fingerprint "$FP_1" >/dev/null 2>&1
  [ $? -eq 3 ]
  verdict "a withheld target never matches a reuse lookup" "a withheld target matched"
done
# The lookup reads record paths from its own list, never from stdin.
mkdir -p "$tmp/outside/999999"
lgood "$tmp/outside/999999/001-step-pre-ci.rec" 999999
l2=$(srd2 new-run)
out=$(printf '%s\n' "$tmp/outside/999999/001-step-pre-ci.rec" | srd2 lookup reuse --step chk --target t \
  --args-digest "$DIG_ABC" --fingerprint "$FP_1" 2>/dev/null)
[ $? -eq 3 ] && [ -z "$out" ]
verdict "a reuse lookup never reads record paths from stdin" "out=$out"
# Holders pass the secret screen, in order, on step and full-suite records.
rec=$(srd2 write --run "$l2" --point pre-ci --step h --kind command --target t --hosting isolated \
  --backend runner --start 2026-10-06T16:00:00Z --end 2026-10-06T16:00:01Z --outcome passed \
  --pool suite --wait 1 --holder "pid 1 $tok" --holder "pid 2 plain")
recf=$(srd2 write --full-suite --run "$l2" --pool suite --wait 1 --wait-outcome taken \
  --holder "pid 1 $tok" --holder "pid 2 plain" --start 2026-10-06T16:00:00Z --end 2026-10-06T16:00:01Z)
for r in "$rec" "$recf"; do
  [ "$(sed -n "s/^holder${TAB}//p" "$r" | tr '\n' '|')" = "[withheld: the secret screen flagged this value]|pid 2 plain|" ] \
    && ! grep -Fq "$tok" "$r"
  verdict "a token holder is withheld and the next holder kept in order" "holders: $(grep '^holder' "$r" | tr '\n' ' ')"
done
# Stands-on refusals for a resume skip and a record from before end heads.
legacy_rec "$wld/.claude/steps/$l2/009-step-pre-ci.rec" "$l2" pre-ci old passed "$HX_A"
# The rref records live in wx: sk-r passed, sk-s applied ending on HX_B, sk-f
# failed. Each refusal names --stands-on.
for case_ in "resume:sk-f:$rref:pre-ci:003" "resume:sk-r:$rref:pre-ci:002"; do
  code=${case_%%:*} rest=${case_#*:}
  st=${rest%%:*} ref=${rest#*:}
  err=$(srx write --run "$rx" --point convergence --step "$st" --kind command --target t \
    --hosting isolated --backend runner --start 2026-10-06T16:00:00Z --end 2026-10-06T16:00:01Z \
    --end-head "$HX_B" --outcome skipped --skip-code "$code" --stands-on "$ref" 2>&1 >/dev/null)
  [ $? -eq 2 ] && printf '%s' "$err" | grep -Fq -- "--stands-on: names no $code-qualifying record"
  verdict "a $code skip of $st refuses to stand on $ref" "err=$err"
done
srd2 write --run "$l2" --point pre-pr --step old --kind command --target t --hosting isolated \
  --backend runner --start 2026-10-06T16:00:00Z --end 2026-10-06T16:00:01Z --outcome skipped \
  --skip-code reuse --stands-on "$l2:pre-ci:009" >/dev/null 2>&1
[ $? -eq 2 ]
verdict "a reuse skip refuses to stand on a record from before end heads" "accepted"
# Every new flag refuses an empty value by name.
for fl in --skip-code --stands-on --pool --wait --fingerprint --args-digest --refire-of --wait-outcome; do
  err=$(srd2 write --run "$l2" --full-suite "$fl" "" 2>&1 >/dev/null)
  printf '%s' "$err" | grep -Fq -- "$fl: given empty"
  verdict "an empty $fl is refused as given empty" "err=$err"
done
# Resume reads every run, refusing a cache holding an unreadable record.
l3=$(srd2 new-run)
ln -s /etc/hostname "$wld/.claude/steps/$l3/001-step-pre-ci.rec"
srd2 lookup resume --run "$l2" --point pre-pr --head "$HX_A" >/dev/null 2>&1
[ $? -eq 1 ]
verdict "a resume lookup refuses a cache holding a symlinked record" "not exit 1"
rm -f "$wld/.claude/steps/$l3/001-step-pre-ci.rec"
# A resume skip standing on another step's record ends the prefix.
l4=$(srd2 new-run)
legacy_rec "$wld/.claude/steps/$l4/001-step-pre-pr.rec" "$l4" pre-pr one skipped "$HX_A" "end-head${TAB}$HX_A" \
  "skip-code${TAB}resume" "stands-on${TAB}$l4:pre-pr:002"
legacy_rec "$wld/.claude/steps/$l4/002-step-pre-pr.rec" "$l4" pre-pr two passed "$HX_A" "end-head${TAB}$HX_A"
out=$(srd2 lookup resume --run "$l4" --point pre-pr --head "$HX_A")
[ $? -eq 3 ] && [ -z "$out" ]
verdict "a resume skip standing on another step's record ends the prefix" "out=$out"
# Status: the attempt is the highest well-formed completion; a malformed
# record in it, or a malformed limited record anywhere, fails the flip.
lim_wt
flip "$HX_A" failed
f2=$(srl new-run)
cp "$wlm/.claude/steps/000001/002-done-pre-ready-flip.rec" "$wlm/.claude/steps/$f2/001-done-pre-ready-flip.rec"
lstate "$HX_A"
[ "$ST_RC" -eq 0 ] && gh_arg state=failure
verdict "a completion copied into a newer run is not the attempt" "rc=$ST_RC"
lim_wt
flip "$HX_A" passed
printf 'outcome\tpassed\n' >>"$wlm/.claude/steps/000001/001-step-pre-ready-flip.rec"
lstate "$HX_A"
[ "$ST_RC" -eq 0 ] && gh_arg state=failure
verdict "a malformed step record in the attempt fails the flip" "rc=$ST_RC"
lim_wt
flip "$HX_A" passed
sed -i.bak "s/^type${TAB}.*/type${TAB}stepx/" "$wlm/.claude/steps/000001/001-step-pre-ready-flip.rec"
rm -f "$wlm/.claude/steps/000001/001-step-pre-ready-flip.rec.bak"
lstate "$HX_A"
[ "$ST_RC" -eq 0 ] && gh_arg state=failure
verdict "a step record with a garbled type fails the flip" "rc=$ST_RC"
for garble in "s/^outcome${TAB}.*/outcome${TAB}FAILED/" "/^outcome${TAB}/d"; do
  lim_wt
  flip "$HX_A" failed
  sed -i.bak "$garble" "$wlm/.claude/steps/000001/001-step-pre-ready-flip.rec"
  rm -f "$wlm/.claude/steps/000001/001-step-pre-ready-flip.rec.bak"
  lstate "$HX_A"
  [ "$ST_RC" -eq 0 ] && gh_arg state=failure
  verdict "an attempt record edited by '$garble' fails the flip" "rc=$ST_RC"
done
# A newer completion with a garbled or missing head fails closed too.
for garble in "s/^head${TAB}.*/head${TAB}deadbeef/" "/^head${TAB}/d"; do
  lim_wt
  flip "$HX_A" passed
  f2=$(srl new-run)
  lrec "$f2" pre-ready-flip gate halted "$HX_A"
  srl write --completion --run "$f2" --point pre-ready-flip --head "$HX_A" >/dev/null
  sed -i.bak "$garble" "$wlm/.claude/steps/$f2/002-done-pre-ready-flip.rec"
  rm -f "$wlm/.claude/steps/$f2/002-done-pre-ready-flip.rec.bak"
  lstate "$HX_A"
  [ "$ST_RC" -eq 0 ] && gh_arg state=failure
  verdict "a newer completion edited by '$garble' fails the flip" "rc=$ST_RC"
done
# A newer completion that cannot be read fails closed rather than handing the
# verdict to an older passing attempt.
lim_wt
flip "$HX_A" passed
f2=$(srl new-run)
lrec "$f2" pre-ready-flip gate halted "$HX_A"
srl write --completion --run "$f2" --point pre-ready-flip --head "$HX_A" >/dev/null
printf 'stray line\n' >>"$wlm/.claude/steps/$f2/002-done-pre-ready-flip.rec"
lstate "$HX_A"
[ "$ST_RC" -eq 0 ] && gh_arg state=failure \
  && grep -Fxq "description=pre-ready-flip: a later completion record is malformed (run $f2)" "$GH_STUB_LOG"
verdict_of $? "a malformed newer completion fails the flip" "rc=$ST_RC $(grep '^description=' "$GH_STUB_LOG")"
lim_wt
u=$(srl new-run)
lrec "$u" post-pr review limited "$HX_A"
sed -i.bak "s/^point${TAB}.*/point${TAB}pre-pr/" "$wlm/.claude/steps/$u/001-step-post-pr.rec"
rm -f "$wlm/.claude/steps/$u/001-step-post-pr.rec.bak"
v=$(srl new-run)
lrec "$v" post-pr review passed "$HX_A"
flip "$HX_A" passed
lstate "$HX_A"
[ "$ST_RC" -eq 0 ] && gh_arg state=failure
verdict "a malformed limited record is never retired" "rc=$ST_RC"
# Fingerprint: a foreign index changes nothing, an ignored path absent at HEAD
# keeps its marker, and a dirty submodule leaves no fingerprint whatever its
# ignore setting.
fpa=$(fp a)
git -C "$wfp" read-tree --index-output="$tmp/foreign.idx" --empty
[ "$(GIT_INDEX_FILE="$tmp/foreign.idx" fp a)" = "$fpa" ]
verdict "fingerprint ignores an inherited GIT_INDEX_FILE" "a foreign index changed it"
mkdir -p "$wfp/build" && : >"$wfp/build/out"
fb=$(fp build)
printf '%s\n' "$fb" | grep -Eq '^([0-9a-f]{40}|[0-9a-f]{64})$'
verdict "an ignored path absent at HEAD keeps its absent marker" "build: '$fb'"
mkdir -p "$wfp/fresh"
[ "$(fp fresh)" = none ]
verdict "an unignored path absent at HEAD but present here leaves no fingerprint" "fresh: $(fp fresh)"
rmdir "$wfp/fresh"
git -C "$wfp" config core.ignorecase true
[ "$(fp build)" = none ]
verdict "on a case-insensitive checkout a present path absent at HEAD leaves no fingerprint" "build stayed"
git -C "$wfp" config core.ignorecase false
wsub="$tmp/wsub"
fresh "$wsub"
printf 'x\n' >"$wsub/f" && git -C "$wsub" add f && git -C "$wsub" commit -q -m "chore: sub"
git -C "$wfp" -c protocol.file.allow=always submodule -q add "$wsub" lib >/dev/null 2>&1 \
  && git -C "$wfp" config -f .gitmodules submodule.lib.ignore all \
  && git -C "$wfp" add .gitmodules && git -C "$wfp" commit -q -m "chore: submodule"
if [ -f "$wfp/lib/f" ]; then
  fl=$(fp lib)
  printf 'changed\n' >"$wfp/lib/f"
  printf '%s\n' "$fl" | grep -Eq '^([0-9a-f]{40}|[0-9a-f]{64})$' && [ "$(fp lib)" = none ]
  verdict "a dirty submodule leaves no fingerprint despite ignore = all" "lib stayed fingerprinted"
else
  fail "fixture: cannot add the submodule"
fi

# An unreadable HEAD is a runtime failure, never an unborn one; so is a clock
# that prints no stamp.
wbh="$tmp/wbh"
fresh "$wbh"
printf '%s\n' 0123456789abcdef0123456789abcdef01234567 >"$wbh/.git/refs/heads/main"
err=$("$SR" --worktree "$wbh" fingerprint --paths . 2>&1 >/dev/null)
[ $? -eq 1 ] && printf '%s' "$err" | grep -Fq "cannot read the worktree's HEAD"
verdict "fingerprint over an unreadable HEAD exits 1" "err=$err"
"$SR" --worktree "$wbh" new-run >/dev/null
"$SR" --worktree "$wbh" write --completion --run 000001 --point pre-ci >/dev/null 2>&1
[ $? -eq 1 ]
verdict "a defaulted head over an unreadable HEAD exits 1" "not exit 1"
mkdir -p "$tmp/datestub"
printf '#!/bin/sh\necho junk\n' >"$tmp/datestub/date"
chmod +x "$tmp/datestub/date"
err=$(PATH="$tmp/datestub:$PATH" "$SR" --worktree "$wx" write --run "$rx" --point convergence --step clk \
  --kind command --target t --hosting isolated --backend runner --start 2026-10-06T10:00:00Z \
  --outcome passed 2>&1 >/dev/null)
[ $? -eq 1 ] && printf '%s' "$err" | grep -Fq "the clock printed no UTC stamp"
verdict "a clock that prints no stamp exits 1" "err=$err"

# --- /execute-task's missing-matrix skip carries its code -----------------------------
# shellcheck disable=SC2016 # literal backticks of the skill text
grep -Fq 'a `skip` line records `skipped`, code `missing`' "$repo_root/skills/execute-task/SKILL.md"
verdict "/execute-task records a missing-matrix skip with code missing" "the skill's skip call names no code"

# --- the cache path is ignored ------------------------------------------------------
git -C "$repo_root" check-ignore -q ".claude/steps/000001/x.rec"
verdict "this repository ignores the record cache" ".claude/steps/ is not ignored"

if [ "$failures" -gt 0 ]; then
  printf '%s\n' "$failures failure(s)" >&2
  exit 1
fi
echo "all step-record tests passed"
