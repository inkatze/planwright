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
unset CLAUDE_PLUGIN_DATA
mkdir -p "$HOME" "$CLAUDE_CONFIG_DIR"
fleet_home_pin "$T/fh" || {
  echo "FAIL: could not pin the fleet home" >&2
  exit 1
}
cp -R "$FIX/projects" "$CLAUDE_CONFIG_DIR/projects"
prices="$FIX/prices.tsv"
tab=$(printf '\t')

# A forge stand-in: `gh pr list --repo <o>/<n> ...` prints the fixture's
# merged pull requests for that repository and logs its arguments.
mkdir -p "$T/bin"
cat >"$T/bin/gh" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >>"$T/gh.log"
repo=""
while [ \$# -gt 0 ]; do
  case \$1 in
    --repo) repo=\$2; shift ;;
  esac
  shift
done
f="$FIX/merges/\$(printf '%s' "\$repo" | tr / -).json"
[ -f "\$f" ] || { echo "no such repo" >&2; exit 1; }
cat "\$f"
EOF
chmod +x "$T/bin/gh"
PATH="$T/bin:$PATH"
export PATH

# --- token-spend rows --asks: the operator-facing tool uses ---
"$SPEND" rows "$CLAUDE_CONFIG_DIR/projects/demo/s-hub.jsonl" >"$T/plain.tsv"
assert_exit "rows without --asks" 0 $?
assert_eq "rows without --asks prints no ask line" 0 "$(grep -c "^a$tab" "$T/plain.tsv")"
"$SPEND" rows --asks "$CLAUDE_CONFIG_DIR/projects/demo/s-hub.jsonl" >"$T/asks.tsv"
assert_exit "rows --asks" 0 $?
asks=$(cat "$T/asks.tsv")
assert_contains "rows --asks: an AskUserQuestion use" "$(printf 'a\ttu1\ts-hub\tmain\t2026-11-01T02:00:00.000Z\tAskUserQuestion')" "$asks"
assert_contains "rows --asks: a PushNotification use" "$(printf 'a\ttu2\ts-hub\tmain\t2026-11-02T03:00:00.000Z\tPushNotification')" "$asks"
assert_eq "rows --asks: another tool is not an ask" 0 "$(grep -c 'tu-read' "$T/asks.tsv")"
assert_eq "rows --asks keeps the message lines" "$(grep -c "^m$tab" "$T/plain.tsv")" "$(grep -c "^m$tab" "$T/asks.tsv")"

# --- compute: the fixture log set reproduces the fixture's numbers ---
"$SPEND" rows --asks >"$T/rows.tsv"
assert_exit "rows --asks over the fixture transcripts" 0 $?
for f in "$FIX"/merges/*.json; do
  r=$(basename "$f" .json | tr - /)
  jq -r --arg r "$r" '.[] | ["g", $r, (.number | tostring), .mergedAt] | @tsv' "$f" >>"$T/rows.tsv"
done
"$BASELINE" compute --since 2026-11-01 --until 2026-11-02 --prices "$prices" "$T/rows.tsv" >"$T/computed.tsv" 2>"$T/compute.err"
assert_exit "compute exits 0" 0 $?
if diff -u "$FIX/expected.tsv" "$T/computed.tsv" >"$T/compute.diff"; then
  ok "compute reproduces the fixture's recorded numbers"
else
  fail "compute reproduces the fixture's recorded numbers ($(cat "$T/compute.diff"))"
fi
"$BASELINE" compute --since 2026-11-02 --until 2026-11-01 --prices "$prices" "$T/rows.tsv" >"$T/out" 2>&1
assert_exit "compute: a window ending before it starts is a usage error" 2 $?
"$BASELINE" compute --since 2026-11-1 --until 2026-11-02 "$T/rows.tsv" >"$T/out" 2>&1
assert_exit "compute: a malformed date is a usage error" 2 $?
"$BASELINE" compute --since 2026-11-01 --until 2026-11-02 "$T/missing.tsv" >"$T/out" 2>&1
assert_exit "compute: an unreadable rows file is a usage error" 2 $?
: >"$T/empty-rows.tsv"
"$BASELINE" compute --since 2026-11-01 --until 2026-11-01 --prices "$prices" "$T/empty-rows.tsv" >"$T/empty.out" 2>&1
assert_exit "compute over no rows exits 0" 0 $?
assert_contains "compute over no rows: zero merges per day" "$(printf 'summary\tmerges-per-day\t0.00')" "$(cat "$T/empty.out")"
assert_contains "compute over no rows: zero interruptions per day" "$(printf 'summary\tinterruptions-per-day\t0.00\t0.00')" "$(cat "$T/empty.out")"

# --- record: writes the baseline only to the machine-local location ---
before=$(git -C "$REPO_ROOT" status --porcelain --untracked-files=all)
mkdir -p "$T/tmp"
TMPDIR="$T/tmp" "$BASELINE" record --since 2026-11-01 --until 2026-11-02 --repo example/one --repo example/two --prices "$prices" >"$T/record.out" 2>"$T/record.err"
assert_exit "record exits 0" 0 $?
dest="$T/fh/fleet/control-plane/baseline/2026-11-01--2026-11-02.tsv"
assert_eq "record prints where it wrote" "$(printf 'recorded\t%s' "$dest")" "$(cat "$T/record.out")"
if [ -f "$dest" ] && diff -u "$FIX/expected.tsv" "$dest" >"$T/record.diff"; then
  ok "record writes the fixture's numbers to the machine-local location"
else
  fail "record writes the fixture's numbers to the machine-local location ($(cat "$T/record.diff" 2>&1))"
fi
assert_eq "record leaves no scratch behind" "" "$(find "$T/tmp" -mindepth 1 -print)"
assert_eq "record writes nothing into the repository" "$before" "$(git -C "$REPO_ROOT" status --porcelain --untracked-files=all)"
assert_eq "record writes one file in its location" 1 "$(find "$T/fh/fleet/control-plane" -type f | wc -l | tr -d ' ')"
assert_contains "record asks the forge for merges in the window" "--repo example/one --state merged --search merged:2026-11-01T00:00:00Z..2026-11-02T23:59:59Z" "$(cat "$T/gh.log")"
"$BASELINE" record --since 2026-11-01 --until 2026-11-02 --prices "$prices" >"$T/out" 2>&1
assert_exit "record without a repository is a usage error" 2 $?
"$BASELINE" record --since 2026-11-01 --until 2026-11-02 --repo 'bad repo' --prices "$prices" >"$T/out" 2>&1
assert_exit "record: a malformed repository is a usage error" 2 $?
"$BASELINE" record --since 2026-11-01 --until 2026-11-02 --repo example/none --prices "$prices" >"$T/out" 2>&1
assert_exit "record: a forge read that fails exits 1" 1 $?
assert_contains "record: the failed forge read names the repository" "example/none" "$(cat "$T/out")"
inrepo="$T/work"
git init -q "$inrepo"
PLANWRIGHT_FLEET_STATE_DIR="$inrepo/fleet" "$BASELINE" record --since 2026-11-01 --until 2026-11-02 --repo example/one --prices "$prices" >"$T/out" 2>&1
assert_exit "record refuses a location inside a git work tree" 2 $?
assert_contains "record names the refused location" "inside a git work tree" "$(cat "$T/out")"
assert_eq "the refused record writes nothing" "" "$(find "$inrepo" -path "$inrepo/.git" -prune -o -type f -print)"

# --- check-committed: a committed figure fails the check ---
sk="$T/sk"
git init -q "$sk"
git -C "$sk" config user.email t@example.invalid
git -C "$sk" config user.name t
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
git -C "$sk" rm -q docs/baseline.tsv && git -C "$sk" commit -q -m drop
printf 'The hub ran hot:\n\n%s\n' "$(grep "^summary${tab}turns-per-day" "$FIX/expected.tsv" | head -n 1)" >>"$sk/docs/notes.md"
git -C "$sk" commit -q -am pasted
"$BASELINE" check-committed --repo-root "$sk" >"$T/cc.out" 2>&1
assert_exit "check-committed fails on one pasted row" 1 $?
assert_contains "check-committed names the pasting file" "docs/notes.md" "$(cat "$T/cc.out")"
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
