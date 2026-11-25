#!/bin/bash
# Tests for scripts/control-plane-baseline.sh: compute over a fixture log set
# reproduces the fixture's recorded numbers, record writes only to the
# machine-local location, and check-committed fails on a committed figure.
set -u
unset CDPATH
LC_ALL=C
export LC_ALL

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BASELINE="$REPO_ROOT/scripts/control-plane-baseline.sh"
SPEND="$REPO_ROOT/scripts/token-spend.sh"
FIX="$REPO_ROOT/tests/fixtures/control-plane-baseline"
# shellcheck source=tests/lib/hermetic-env.sh
. "$REPO_ROOT/tests/lib/hermetic-env.sh"

failures=0
ok() { echo "ok: $1"; }
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}
assert_exit() {
  if [ "$2" -eq "$3" ]; then ok "$1"; else fail "$1 (expected exit $2, got $3)"; fi
}
assert_contains() {
  case "$3" in
    *"$2"*) ok "$1" ;;
    *) fail "$1 (missing '$2' in: $3)" ;;
  esac
}
assert_eq() {
  if [ "$2" = "$3" ]; then ok "$1"; else fail "$1 (expected '$2', got '$3')"; fi
}

T=$(mktemp -d "${TMPDIR:-/tmp}/cpbase.XXXXXX") || exit 1
trap 'rm -rf "$T"' EXIT
export HOME="$T/home"
export CLAUDE_CONFIG_DIR="$T/claude"
export GIT_CONFIG_NOSYSTEM=1
unset CLAUDE_PLUGIN_DATA XDG_CONFIG_HOME
mkdir -p "$HOME" "$CLAUDE_CONFIG_DIR"
fleet_home_pin "$T/fh" || {
  echo "FAIL: could not pin the fleet home" >&2
  exit 1
}
cp -R "$FIX/projects" "$CLAUDE_CONFIG_DIR/projects"
proj="$CLAUDE_CONFIG_DIR/projects/demo"
prices="$FIX/prices.tsv"
tab=$(printf '\t')

# A forge stand-in: `gh pr list --repo <o>/<n> ...` logs its arguments and
# prints the fixture's merged pull requests for that repository; example/many
# returns a full page, and a call without the fields record asks for fails.
mkdir -p "$T/bin"
cat >"$T/bin/gh" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >>"$T/gh.log"
case " \$* " in
  *" --limit 1000 --json number,mergedAt "*) ;;
  *) echo "unexpected arguments" >&2; exit 1 ;;
esac
repo=""
while [ \$# -gt 0 ]; do
  case \$1 in
    --repo) repo=\$2; shift ;;
  esac
  shift
done
if [ "\$repo" = example/many ]; then
  jq -n '[range(1000) | {number: ., mergedAt: "2026-11-01T00:00:00Z"}]'
  exit 0
fi
if [ "\$repo" = example/object ]; then
  echo '{"message": "not a list"}'
  exit 0
fi
f="$FIX/merges/\$(printf '%s' "\$repo" | tr / -).json"
[ -f "\$f" ] || { echo "no such repo" >&2; exit 1; }
cat "\$f"
EOF
chmod +x "$T/bin/gh"
PATH="$T/bin:$PATH"
export PATH

# --- token-spend rows --asks: the tool uses that reach the operator ---
"$SPEND" rows "$proj/s-hub.jsonl" >"$T/plain.tsv"
assert_exit "rows without --asks" 0 $?
assert_eq "rows without --asks prints no ask line" 0 "$(grep -c "^a$tab" "$T/plain.tsv")"
"$SPEND" rows --asks "$proj/s-hub.jsonl" >"$T/asks.tsv"
assert_exit "rows --asks" 0 $?
asks=$(cat "$T/asks.tsv")
assert_contains "rows --asks: an AskUserQuestion use" "$(printf 'a\ttu1\ts-hub\tmain\t2026-11-01T02:00:00.000Z\tAskUserQuestion')" "$asks"
assert_contains "rows --asks: a PushNotification use" "$(printf 'a\ttu2\ts-hub\tmain\t2026-11-02T03:00:00.000Z\tPushNotification')" "$asks"
assert_eq "rows --asks: another tool is not an ask" 0 "$(grep -c 'tu-read' "$T/asks.tsv")"
assert_eq "rows --asks keeps the message lines" "$(grep -c "^m$tab" "$T/plain.tsv")" "$(grep -c "^m$tab" "$T/asks.tsv")"
sub=$("$SPEND" rows --asks "$proj/s-wk/subagents/agent-ag1.jsonl")
assert_contains "rows --asks: a sub-agent's use is on the sub chain" "$(printf 'a\ttu5\ts-wk\tsub\t')" "$sub"

# --- compute: the fixture log set reproduces the fixture's numbers ---
TZ=UTC0 touch -t 202611010300 "$proj/s-edge.jsonl"
"$SPEND" rows --asks >"$T/rows.tsv"
assert_exit "rows --asks over the fixture transcripts" 0 $?
for f in "$FIX"/merges/*.json; do
  r=$(basename "$f" .json | tr - /)
  jq -r --arg r "$r" '.[] | ["g", $r, (.number | tostring), (.mergedAt // "")] | @tsv' "$f" >>"$T/rows.tsv"
done
grep "^g${tab}example/one${tab}1${tab}" "$T/rows.tsv" >"$T/dup.tsv"
cat "$T/dup.tsv" >>"$T/rows.tsv"
"$BASELINE" compute --since 2026-11-01 --until 2026-11-02 --prices "$prices" "$T/rows.tsv" >"$T/computed.tsv" 2>"$T/compute.err"
assert_exit "compute exits 0" 0 $?
if diff -u "$FIX/expected.tsv" "$T/computed.tsv" >"$T/compute.diff"; then
  ok "compute reproduces the fixture's recorded numbers"
else
  fail "compute reproduces the fixture's recorded numbers ($(cat "$T/compute.diff"))"
fi
assert_contains "compute names an unpriced model" "no price for model m9" "$(cat "$T/compute.err")"
sort -r "$T/rows.tsv" >"$T/reversed.tsv"
"$BASELINE" compute --since 2026-11-01 --until 2026-11-02 --prices "$prices" "$T/reversed.tsv" >"$T/reversed.out" 2>"$T/reversed.err"
assert_eq "compute does not depend on the order of its rows" "$(cat "$T/computed.tsv")" "$(cat "$T/reversed.out")"
"$BASELINE" compute --since 2026-11-02 --until 2026-11-01 --prices "$prices" "$T/rows.tsv" >"$T/out" 2>&1
assert_exit "compute: a window ending before it starts is a usage error" 2 $?
assert_contains "compute: the reversed window is named" "--until is before --since" "$(cat "$T/out")"
"$BASELINE" compute --since 2026-11-1 --until 2026-11-02 --prices "$prices" "$T/rows.tsv" >"$T/out" 2>&1
assert_exit "compute: a malformed date is a usage error" 2 $?
assert_contains "compute: the malformed date is named" "--since takes a real YYYY-MM-DD date" "$(cat "$T/out")"
"$BASELINE" compute --since 2026-02-01 --until 2026-02-30 --prices "$prices" "$T/rows.tsv" >"$T/out" 2>&1
assert_exit "compute: a day the month does not have is a usage error" 2 $?
"$BASELINE" compute --since 2028-02-28 --until 2028-03-01 --prices "$prices" "$T/rows.tsv" >"$T/out" 2>&1
assert_exit "compute: a leap day is a real date" 0 $?
assert_contains "compute: a window across a leap day counts its days" "$(printf 'summary\tdays\t3')" "$(cat "$T/out")"
"$BASELINE" compute --since 2026-10-31 --until 2026-11-01 --prices "$prices" "$T/rows.tsv" >"$T/out" 2>&1
assert_contains "compute: a window across a month end counts its days" "$(printf 'summary\tdays\t2')" "$(cat "$T/out")"
"$BASELINE" compute --since 2026-11-01 --until 2026-11-02 --prices "$prices" "$T/missing.tsv" >"$T/out" 2>&1
assert_exit "compute: an unreadable rows file is a usage error" 2 $?
assert_contains "compute: the unreadable rows file is named" "unreadable rows file" "$(cat "$T/out")"
printf 'model\tinput\nm1\tx\n' >"$T/bad-prices.tsv"
"$BASELINE" compute --since 2026-11-01 --until 2026-11-02 --prices "$T/bad-prices.tsv" "$T/rows.tsv" >"$T/out" 2>&1
assert_exit "compute: a malformed price table exits 2" 2 $?
: >"$T/empty-rows.tsv"
"$BASELINE" compute --since 2026-11-01 --until 2026-11-01 --prices "$prices" "$T/empty-rows.tsv" >"$T/empty.out" 2>&1
assert_exit "compute over no rows exits 0" 0 $?
assert_contains "compute over no rows: zero merges per day" "$(printf 'summary\tmerges-per-day\t0.00')" "$(cat "$T/empty.out")"
assert_contains "compute over no rows: zero interruptions per day" "$(printf 'summary\tinterruptions-per-day\t0.00\t0.00')" "$(cat "$T/empty.out")"

# --- record: writes the baseline only to the machine-local location ---
# A file last written before the window opened is not read; one written after
# UTC midnight but before local midnight in a zone behind UTC still is.
cp "$proj/s-int.jsonl" "$proj/s-old.jsonl"
sed -i.bak 's/"s-int"/"s-old"/g; s/"u1"/"o1"/; s/"i2"/"o2"/; s/"i3"/"o3"/; s/"tu3"/"to3"/; s/"tu4"/"to4"/' "$proj/s-old.jsonl"
rm -f "$proj/s-old.jsonl.bak"
TZ=UTC0 touch -t 202001010000 "$proj/s-old.jsonl"
snapshot() { find "$T/fh" "$HOME" "$CLAUDE_CONFIG_DIR" -print | sort; }
snapshot >"$T/before.lst"
before=$(git -C "$REPO_ROOT" status --porcelain --untracked-files=all)
mkdir -p "$T/tmp"
TZ=EST+8 TMPDIR="$T/tmp" "$BASELINE" record --since 2026-11-01 --until 2026-11-02 --repo example/one --repo example/two --prices "$prices" >"$T/record.out" 2>"$T/record.err"
assert_exit "record exits 0" 0 $?
base="$T/fh/fleet/control-plane/baseline"
dest="$base/2026-11-01--2026-11-02.tsv"
assert_eq "record prints where it wrote" "$(printf 'recorded\t%s' "$dest")" "$(cat "$T/record.out")"
if [ -f "$dest" ] && diff -u "$FIX/expected.tsv" "$dest" >"$T/record.diff"; then
  ok "record writes the fixture's numbers to the machine-local location"
else
  fail "record writes the fixture's numbers to the machine-local location ($(cat "$T/record.diff" 2>&1))"
fi
snapshot >"$T/after.lst"
assert_eq "record adds only its location and file" "$(printf '%s\n%s\n%s\n%s' "$T/fh/fleet" "$T/fh/fleet/control-plane" "$base" "$dest")" "$(comm -13 "$T/before.lst" "$T/after.lst")"
assert_eq "record leaves no scratch behind" "" "$(find "$T/tmp" -mindepth 1 -print)"
assert_eq "record writes nothing into the repository" "$before" "$(git -C "$REPO_ROOT" status --porcelain --untracked-files=all)"
case $(ls -ld "$dest") in
  -rw-------*) ok "the recording is readable by its owner only" ;;
  *) fail "the recording is readable by its owner only ($(ls -ld "$dest"))" ;;
esac
case $(ls -ld "$base") in
  drwx------*) ok "the location is its owner's only" ;;
  *) fail "the location is its owner's only ($(ls -ld "$base"))" ;;
esac
assert_contains "record asks the forge for merges in the window" "--repo example/one --state merged --search merged:2026-11-01T00:00:00Z..2026-11-02T23:59:59Z --limit 1000 --json number,mergedAt" "$(cat "$T/gh.log")"
"$BASELINE" record --since 2026-11-01 --until 2026-11-02 --repo example/one --repo example/two --prices "$prices" >"$T/out" 2>&1
assert_exit "record of the same window again exits 0" 0 $?
assert_eq "record of the same window replaces the earlier one" "$(cat "$FIX/expected.tsv")" "$(cat "$dest")"
"$BASELINE" record --since 2026-11-01 --until 2026-11-02 --prices "$prices" >"$T/out" 2>&1
assert_exit "record without a repository is a usage error" 2 $?
"$BASELINE" record --since 2026-11-01 --until 2026-11-02 --repo 'bad repo' --prices "$prices" >"$T/out" 2>&1
assert_exit "record: a malformed repository is a usage error" 2 $?
assert_contains "record: the malformed repository is named" "--repo takes <owner>/<name>" "$(cat "$T/out")"
"$BASELINE" record --since 2026-11-01 --until 2026-11-03 --repo example/none --prices "$prices" >"$T/out" 2>&1
assert_exit "record: a forge read that fails exits 1" 1 $?
assert_contains "record: the failed forge read names the repository" "example/none" "$(cat "$T/out")"
"$BASELINE" record --since 2026-11-01 --until 2026-11-03 --repo example/many --prices "$prices" >"$T/out" 2>&1
assert_exit "record: a forge read at its limit exits 1" 1 $?
assert_contains "record: the limit is named" "hit its 1000-row limit" "$(cat "$T/out")"
"$BASELINE" record --since 2026-11-01 --until 2026-11-03 --repo example/object --prices "$prices" >"$T/out" 2>&1
assert_exit "record: a forge reply that is not a list exits 1" 1 $?
assert_contains "record: the reply is named" "the forge returned no list for example/object" "$(cat "$T/out")"
assert_eq "failed records leave the location as it was" "$dest" "$(find "$base" -type f -print)"
inrepo="$T/work"
git init -q "$inrepo"
PLANWRIGHT_FLEET_STATE_DIR="$inrepo/fleet" "$BASELINE" record --since 2026-11-01 --until 2026-11-02 --repo example/one --prices "$prices" >"$T/out" 2>&1
assert_exit "record refuses a location inside a git work tree" 2 $?
assert_contains "record names the refused location" "inside a git work tree" "$(cat "$T/out")"
assert_eq "the refused record writes nothing" "" "$(find "$inrepo" -path "$inrepo/.git" -prune -o -type f -print)"
PLANWRIGHT_FLEET_STATE_DIR="$T/absent/../work/fleet" "$BASELINE" record --since 2026-11-01 --until 2026-11-02 --repo example/one --prices "$prices" >"$T/out" 2>&1
assert_exit "record refuses a fleet home with a .. component" 2 $?
assert_eq "the refused .. record creates nothing" "$inrepo" "$(find "$inrepo" -path "$inrepo/.git" -prune -o -print)"
mkdir -p "$inrepo/sub"
ln -s "$inrepo/sub" "$T/linked-fleet"
PLANWRIGHT_FLEET_STATE_DIR="$T/linked-fleet" "$BASELINE" record --since 2026-11-01 --until 2026-11-02 --repo example/one --prices "$prices" >"$T/out" 2>&1
assert_exit "record refuses a location a symbolic link puts inside a work tree" 2 $?
assert_contains "record names the linked location as refused" "inside a git work tree" "$(cat "$T/out")"
assert_eq "the refused linked record writes nothing" "" "$(find "$inrepo" -path "$inrepo/.git" -prune -o -type f -print)"
PLANWRIGHT_FLEET_STATE_DIR="relative/fleet" "$BASELINE" record --since 2026-11-01 --until 2026-11-02 --repo example/one --prices "$prices" >"$T/out" 2>&1
assert_exit "record refuses a relative fleet home" 2 $?

# --- check-committed: a committed figure fails the check ---
sk="$T/sk"
git init -q "$sk"
git -C "$sk" config user.email t@example.invalid
git -C "$sk" config user.name t
git -C "$sk" config commit.gpgsign false
mkdir -p "$sk/docs" "$sk/tests/fixtures/control-plane-baseline"
printf '# notes\n' >"$sk/docs/notes.md"
cp "$FIX/expected.tsv" "$sk/tests/fixtures/control-plane-baseline/expected.tsv"
git -C "$sk" add -A && git -C "$sk" commit -q -m init
"$BASELINE" check-committed --repo-root "$sk" >"$T/cc.out" 2>&1
assert_exit "check-committed passes with figures only in the fixture set" 0 $?
cp "$FIX/expected.tsv" "$sk/docs/baseline.tsv"
"$BASELINE" check-committed --repo-root "$sk" >"$T/cc.out" 2>&1
assert_exit "check-committed ignores an untracked file" 0 $?
git -C "$sk" add docs/baseline.tsv && git -C "$sk" commit -q -m figures
"$BASELINE" check-committed --repo-root "$sk" >"$T/cc.out" 2>&1
assert_exit "check-committed fails on a committed baseline file" 1 $?
assert_contains "check-committed names the file" "docs/baseline.tsv" "$(cat "$T/cc.out")"
rm "$sk/docs/baseline.tsv"
"$BASELINE" check-committed --repo-root "$sk" >"$T/cc.out" 2>&1
assert_exit "check-committed reads the committed copy of a file deleted locally" 1 $?
git -C "$sk" rm -q docs/baseline.tsv && git -C "$sk" commit -q -m drop
"$BASELINE" check-committed --repo-root "$sk" >"$T/cc.out" 2>&1
assert_exit "check-committed passes once the figures are gone" 0 $?
printf '*.dat binary\n' >"$sk/.gitattributes"
cp "$FIX/expected.tsv" "$sk/docs/figures.dat"
git -C "$sk" add .gitattributes docs/figures.dat && git -C "$sk" commit -q -m binary
"$BASELINE" check-committed --repo-root "$sk/docs" >"$T/cc.out" 2>&1
assert_exit "check-committed reads a file git treats as binary" 1 $?
assert_contains "check-committed scans the whole work tree from a subdirectory" "docs/figures.dat" "$(cat "$T/cc.out")"
git -C "$sk" rm -q docs/figures.dat .gitattributes && git -C "$sk" commit -q -m unbinary
empty="$T/empty-repo"
git init -q "$empty"
"$BASELINE" check-committed --repo-root "$empty" >"$T/cc.out" 2>&1
assert_exit "check-committed passes in a repository with no commits" 0 $?
printf 'plain\n' >"$empty/a.txt"
git -C "$empty" add a.txt && git -C "$empty" -c user.email=t@example.invalid -c user.name=t -c commit.gpgsign=false commit -q -m a
git -C "$empty" checkout -q --orphan orphan
"$BASELINE" check-committed --repo-root "$empty" >"$T/cc.out" 2>&1
assert_exit "check-committed passes on a branch with no commit yet" 0 $?
bad="$T/bad-head"
git init -q "$bad"
printf '0123456789012345678901234567890123456789\n' >"$bad/.git/HEAD"
"$BASELINE" check-committed --repo-root "$bad" >"$T/cc.out" 2>&1
assert_exit "check-committed fails on a HEAD that names no commit" 2 $?
assert_eq "the unresolvable HEAD is named without an empty reason" "control-plane-baseline: HEAD does not resolve to a commit" "$(cat "$T/cc.out")"
printf '#!/bin/sh\ntouch "%s"\n' "$T/fsmonitor-ran" >"$T/fsmonitor.sh"
chmod +x "$T/fsmonitor.sh"
git -C "$sk" config core.fsmonitor "$T/fsmonitor.sh"
"$BASELINE" check-committed --repo-root "$sk" >"$T/cc.out" 2>&1
assert_exit "check-committed runs under a planted fsmonitor" 0 $?
if [ -e "$T/fsmonitor-ran" ]; then fail "the checkout's fsmonitor never runs"; else ok "the checkout's fsmonitor never runs"; fi
git -C "$sk" config --unset core.fsmonitor
chmod 000 "$sk/docs/notes.md"
if hermetic_access_denied r "$sk/docs/notes.md"; then
  "$BASELINE" check-committed --repo-root "$sk" >"$T/cc.out" 2>&1
  assert_exit "check-committed fails when git cannot read a tracked file" 2 $?
else
  ok "check-committed fails when git cannot read a tracked file (skipped: reads are not denied here)"
fi
chmod 644 "$sk/docs/notes.md"
cp "$sk/docs/notes.md" "$T/notes.clean"
while IFS= read -r row; do
  printf 'The hub ran hot:\n\n%s\n' "$row" >>"$sk/docs/notes.md"
  "$BASELINE" check-committed --repo-root "$sk" >"$T/cc.out" 2>&1
  assert_exit "check-committed fails on a tracked file's uncommitted row: ${row%%"$tab"*} ${row#*"$tab"}" 1 $?
  assert_contains "check-committed names the pasting file" "docs/notes.md" "$(cat "$T/cc.out")"
  cp "$T/notes.clean" "$sk/docs/notes.md"
done <<EOF
$(printf '# control-plane-baseline: %s 1' format)
$(printf 'turns\t2026-11-01\tmission-control\t2\t0')
$(printf 'spend\t2026-11-01\tunknown\t4.00')
$(printf 'interruptions\t2026-11-02\tinteractive\t1\t0')
$(printf 'merges\t2026-11-02\texample/two\t1')
$(printf 'summary\tdays\t2')
$(printf 'summary\tturns-per-day\tinteractive\t1.00\t0.00')
$(printf 'summary\tspend-share\tunknown\t4.00\t21.1')
$(printf 'summary\tmerges-per-day\t1.50')
$(printf 'summary\tinterruptions-per-day\t1.50\t0.50')
EOF
"$BASELINE" check-committed --repo-root "$T/claude" >"$T/cc.out" 2>&1
assert_exit "check-committed outside a work tree is a usage error" 2 $?
"$BASELINE" check-committed --repo-root "$REPO_ROOT" >"$T/cc.out" 2>&1
assert_exit "check-committed passes on this repository" 0 $?

"$BASELINE" bogus >"$T/out" 2>&1
assert_exit "an unknown verb is a usage error" 2 $?
"$BASELINE" --help >"$T/help.out" 2>&1
assert_exit "--help exits 0" 0 $?
assert_contains "--help names the location" "control-plane/baseline" "$(cat "$T/help.out")"

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all passed"
