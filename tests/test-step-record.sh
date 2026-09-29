#!/bin/sh
# Tests for scripts/step-record.sh — the custom-steps record helper
# (custom-steps Task 4; REQ-D1.5, REQ-E1.2, REQ-H1.3; D-12, D-16).
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
refuse "a skipped step with no reason" "--skip-reason" --run "$run2" --point pre-ci --step s \
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
  --skip-reason "needs $tok")
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

# A completion that fails before its record exists releases its claim.
shim="$tmp/shim"
mkdir -p "$shim"
printf '#!/bin/sh\nexit 1\n' >"$shim/ln"
chmod +x "$shim/ln"
r8=$(sr2 new-run)
env PATH="$shim:$PATH" "$SR" --worktree "$w2" write --completion --run "$r8" --point pre-ci \
  --head "$HEAD_SHA" >/dev/null 2>&1
[ $? -eq 1 ]
verdict "a completion whose link fails exits 1" "failed link not reported"
sr2 write --completion --run "$r8" --point pre-ci --head "$HEAD_SHA" >/dev/null
verdict "a retried completion after a failed one succeeds" "the failed completion kept its claim"

# A missing secret screen withholds, never passes.
lone="$tmp/lone"
mkdir -p "$lone"
cp "$SR" "$repo_root/scripts/echo-safety.sh" "$lone/"
w6="$tmp/w6"
fresh "$w6"
r6=$("$lone/step-record.sh" --worktree "$w6" new-run)
recl2=$("$lone/step-record.sh" --worktree "$w6" write --run "$r6" --point pre-ci --step s \
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
# A step refused after claiming its sequence number releases the claim; a
# completion with no warning runs no screen.
slow="$tmp/slow"
mkdir -p "$slow"
cp "$SR" "$repo_root/scripts/echo-safety.sh" "$slow/"
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
r9=$("$slow/step-record.sh" --worktree "$w9" new-run)
"$slow/step-record.sh" --worktree "$w9" write --run "$r9" --point pre-ci --step s --kind command \
  --target slowstep --hosting isolated --backend runner --head "$HEAD_SHA" \
  --start 2026-09-28T15:00:00Z --end 2026-09-28T15:00:01Z --outcome passed >/dev/null 2>&1 &
i=0
while [ ! -e "$slow/slow-started" ] && [ "$i" -lt 60 ]; do
  sleep 1
  i=$((i + 1))
done
"$slow/step-record.sh" --worktree "$w9" write --completion --run "$r9" --point pre-ci \
  --head "$HEAD_SHA" >/dev/null
[ ! -s "$slow/calls" ]
verdict "a completion with no warning runs no screen" "the screen ran for a warning-free completion"
wait
nseq=$(find "$w9/.claude/steps/$r9" -name '.seq-*' | wc -l | tr -d ' ')
nrec=$(find "$w9/.claude/steps/$r9" -name '[0-9]*.rec' | wc -l | tr -d ' ')
[ "$nseq" -eq "$nrec" ]
verdict "a step refused after its claim releases it" "$nseq claims for $nrec records"

# A done marker that cannot be made is a runtime failure, not a completed point.
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
[ "$(printf '%s\n' "$cl" | sed -n 's/^- \[ \] \*\*\([^*]*\)\*\*.*/\1/p' | tr '\n' ' ')" = "PS-4 PS-5 PS-10000000000 legacy legacy " ]
verdict "legacy entries sort after every id, however large" "entries out of order"
# shellcheck disable=SC2016 # literal backticks in the expected line
has "Reject with: \`git revert -m 1 $M8\`"
verdict "a legacy merge commit's recipe reverts against its first parent" "no first-parent revert recipe"

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

# --- the cache path is ignored ------------------------------------------------------
git -C "$repo_root" check-ignore -q ".claude/steps/000001/x.rec"
verdict "this repository ignores the record cache" ".claude/steps/ is not ignored"

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all step-record tests passed"
