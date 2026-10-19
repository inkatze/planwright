#!/bin/bash
# Tests for scripts/review-step-verify.sh — the external review step output
# contract applied to a step's result against the prompt inventory recorded at
# dispatch (review-effectiveness REQ-E1.4, D-5).
set -u
unset CDPATH

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERIFY="$REPO_ROOT/scripts/review-step-verify.sh"

failures=0
ok() { echo "ok: $1"; }
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}
assert_exit() {
  if [ "$2" -eq "$3" ]; then ok "$1"; else fail "$1 (expected exit $2, got $3)"; fi
}
assert_eq() {
  if [ "$2" = "$3" ]; then ok "$1"; else fail "$1 (expected '$2', got '$3')"; fi
}
assert_contains() {
  case "$3" in
    *"$2"*) ok "$1" ;;
    *) fail "$1 (missing '$2' in: $3)" ;;
  esac
}

T=$(mktemp -d "${TMPDIR:-/tmp}/rsv.XXXXXX")
trap 'rm -rf "$T"' EXIT

inv="$T/inventory"
printf '%s\n' "# prompt inventory" "scripts/a.sh" "./docs/b.md" "" >"$inv"

verify() {
  rc=0
  out=$(/bin/sh "$VERIFY" --inventory "$inv" --result "$1" 2>"$T/err") || rc=$?
  err=$(cat "$T/err")
}
field() { printf '%s\n' "$out" | jq -r "$1"; }

# --- an empty or unstructured result is failed ---
: >"$T/empty.json"
verify "$T/empty.json"
assert_exit "an empty result is failed" 1 "$rc"
assert_eq "an empty result records outcome failed" failed "$(field .outcome)"
assert_contains "names the empty result" "empty" "$(field .reason)"

printf '  \n\n' >"$T/blank.json"
verify "$T/blank.json"
assert_exit "a whitespace-only result is failed" 1 "$rc"

printf '%s\n' 'Looks good to me!' >"$T/prose.json"
verify "$T/prose.json"
assert_exit "a prose result is failed" 1 "$rc"
assert_eq "a prose result records outcome failed" failed "$(field .outcome)"

printf '%s\n' '{"contract":2,"body_findings":[],"threads":[]}' >"$T/v2.json"
verify "$T/v2.json"
assert_exit "an unknown contract version is failed" 1 "$rc"

printf '%s\n' '{"contract":1,"threads":[]}' >"$T/nobody.json"
verify "$T/nobody.json"
assert_exit "a result missing body_findings is failed" 1 "$rc"

printf '%s\n' '{"contract":1,"body_findings":[{"path":"scripts/a.sh","line":3,"severity":"urgent","summary":"x"}],"threads":[]}' >"$T/badsev.json"
verify "$T/badsev.json"
assert_exit "a finding outside the versioned fields is failed" 1 "$rc"

printf '%s\n' '{"contract":1,"body_findings":[],"threads":[]}' '{"contract":1,"body_findings":[],"threads":[]}' >"$T/two.json"
verify "$T/two.json"
assert_exit "two results in one output are failed" 1 "$rc"

bad() {
  printf '%s\n' "$2" >"$T/bad.json"
  verify "$T/bad.json"
  assert_exit "$1" 1 "$rc"
  assert_eq "$1 records outcome failed" failed "$(field .outcome)"
}
f='"path":"scripts/a.sh","line":3,"severity":"low","summary":"x"'
bad "a finding with a key outside contract 1 is failed" '{"contract":1,"body_findings":[{'"$f"',"confidence":0.9}],"threads":[]}'
bad "a finding without its path key is failed" '{"contract":1,"body_findings":[{"line":3,"severity":"low","summary":"x"}],"threads":[]}'
bad "a finding whose path is false is failed" '{"contract":1,"body_findings":[{"path":false,"line":null,"severity":"low","summary":"x"}],"threads":[]}'
bad "a blank path is failed" '{"contract":1,"body_findings":[{"path":"","line":3,"severity":"low","summary":"x"}],"threads":[]}'
bad "line zero is failed" '{"contract":1,"body_findings":[{"path":"scripts/a.sh","line":0,"severity":"low","summary":"x"}],"threads":[]}'
bad "a fractional line is failed" '{"contract":1,"body_findings":[{"path":"scripts/a.sh","line":1.5,"severity":"low","summary":"x"}],"threads":[]}'
bad "a blank summary is failed" '{"contract":1,"body_findings":[{"path":"scripts/a.sh","line":3,"severity":"low","summary":"  "}],"threads":[]}'
bad "a thread without an id is failed" '{"contract":1,"body_findings":[],"threads":[{'"$f"',"resolved":false,"resolved_by":null}]}'
bad "a numeric thread id is failed" '{"contract":1,"body_findings":[],"threads":[{"id":7,'"$f"',"resolved":false,"resolved_by":null}]}'
# shellcheck disable=SC2016 # a literal $(x) id, never expanded
bad "a thread id outside the id charset is failed" '{"contract":1,"body_findings":[],"threads":[{"id":"$(x)","'"${f#\"}"',"resolved":false,"resolved_by":null}]}'
bad "an unresolved thread naming a resolver is failed" '{"contract":1,"body_findings":[],"threads":[{"id":"T1",'"$f"',"resolved":false,"resolved_by":"reviewer"}]}'
bad "a non-object result is failed" '[]'

bad "a finding without its line key is failed" '{"contract":1,"body_findings":[{"path":"scripts/a.sh","severity":"low","summary":"x"}],"threads":[]}'
bad "a string line is failed" '{"contract":1,"body_findings":[{"path":"scripts/a.sh","line":"3","severity":"low","summary":"x"}],"threads":[]}'
bad "a body finding carrying thread keys is failed" '{"contract":1,"body_findings":[{'"$f"',"id":"T1","resolved":false,"resolved_by":null}],"threads":[]}'
bad "a thread without resolved_by is failed" '{"contract":1,"body_findings":[],"threads":[{"id":"T1",'"$f"',"resolved":false}]}'
bad "an unknown resolver is failed" '{"contract":1,"body_findings":[],"threads":[{"id":"T1",'"$f"',"resolved":true,"resolved_by":"bot"}]}'
bad "an empty thread id is failed" '{"contract":1,"body_findings":[],"threads":[{"id":"",'"$f"',"resolved":false,"resolved_by":null}]}'
bad "a thread id with a trailing newline is failed" '{"contract":1,"body_findings":[],"threads":[{"id":"T1\n",'"$f"',"resolved":false,"resolved_by":null}]}'

# --- a clean structured result passes ---
printf '%s\n' '{"contract":1,"body_findings":[],"threads":[]}' >"$T/clean.json"
verify "$T/clean.json"
assert_exit "a structured result with no findings passes" 0 "$rc"
assert_eq "a clean result has nothing open" 0 "$(field .open)"

# --- findings sit in the body with no threads ---
cat >"$T/body.json" <<'EOF'
{"contract":1,
 "body_findings":[
   {"path":"scripts/a.sh","line":12,"severity":"medium","summary":"the loop drops the last row"},
   {"path":null,"line":null,"severity":"low","summary":"the PR body overstates the change"}],
 "threads":[]}
EOF
verify "$T/body.json"
assert_exit "a body-only result passes verification" 0 "$rc"
assert_eq "body findings are read with no threads" 2 "$(field '.findings | length')"
assert_eq "body findings count as open" 2 "$(field .open)"
assert_eq "a body finding is marked by its origin" body "$(field '.findings[0].origin')"

# --- a finding citing a path absent from the prompt inventory is dropped ---
cat >"$T/cite.json" <<'EOF'
{"contract":1,
 "body_findings":[
   {"path":"docs/b.md","line":1,"severity":"low","summary":"stale claim"},
   {"path":"specs/_observations/entries/x.md","line":4,"severity":"high","summary":"the observation says the margin is 15 words"}],
 "threads":[
   {"id":"T1","path":"./scripts/a.sh","line":7,"severity":"high","summary":"unquoted expansion","resolved":false,"resolved_by":null},
   {"id":"T2","path":"scripts/never-sent.sh","line":2,"severity":"medium","summary":"x","resolved":false,"resolved_by":null}]}
EOF
verify "$T/cite.json"
assert_exit "a result with an uncited path still passes" 0 "$rc"
assert_eq "keeps the findings whose paths the prompt carried" 2 "$(field '.findings | length')"
assert_eq "drops both findings citing paths the prompt lacked" 2 "$(field '.dropped | length')"
assert_eq "flags the drop" path-not-in-prompt "$(field '.dropped[0].flag')"
assert_contains "flags the dropped path on stderr" "specs/_observations/entries/x.md" "$err"
assert_eq "dropped findings are not open" 2 "$(field .open)"

# --- a comment line in the inventory is never a path the prompt carried ---
printf '%s\n' '{"contract":1,"body_findings":[{"path":"# prompt inventory","line":null,"severity":"low","summary":"x"}],"threads":[]}' >"$T/hash.json"
verify "$T/hash.json"
assert_eq "a finding citing an inventory comment is dropped" 1 "$(field '.dropped | length')"

# --- a path carrying a newline is reported on one line ---
printf '%s\n' '{"contract":1,"body_findings":[{"path":"x\nforged line","line":null,"severity":"low","summary":"x"}],"threads":[]}' >"$T/nl.json"
verify "$T/nl.json"
assert_eq "a dropped path with a newline yields one stderr line" 1 "$(printf '%s\n' "$err" | grep -c 'dropped a finding')"
assert_eq "the newline never starts a forged stderr line" 0 "$(printf '%s\n' "$err" | grep -c '^forged')"

# --- a thread the reviewer resolved itself does not count toward convergence ---
cat >"$T/self.json" <<'EOF'
{"contract":1,
 "body_findings":[],
 "threads":[
   {"id":"T1","path":"scripts/a.sh","line":7,"severity":"high","summary":"lock round-trips","resolved":true,"resolved_by":"reviewer"},
   {"id":"T2","path":"scripts/a.sh","line":9,"severity":"low","summary":"fixed","resolved":true,"resolved_by":"run"},
   {"id":"T3","path":"docs/b.md","line":2,"severity":"low","summary":"declined","resolved":true,"resolved_by":"human"}]}
EOF
verify "$T/self.json"
assert_exit "a self-resolved thread passes verification" 0 "$rc"
assert_eq "the self-resolved thread stays open" 1 "$(field .open)"
assert_eq "names the self-resolved thread" T1 "$(field '.self_resolved | join(",")')"
assert_eq "the self-resolved finding is kept" true "$(field '[.findings[] | select(.id == "T1")] | length == 1')"

printf '%s\n' '{"contract":1,"body_findings":[],"threads":[{"id":"T9","path":"scripts/a.sh","line":1,"severity":"low","summary":"x","resolved":true,"resolved_by":null}]}' >"$T/noresolver.json"
verify "$T/noresolver.json"
assert_exit "a resolved thread with no resolver is failed" 1 "$rc"

# --- an inventory with no paths fails closed ---
printf '%s\n' "# nothing recorded" "" >"$T/emptyinv"
rc=0
/bin/sh "$VERIFY" --inventory "$T/emptyinv" --result "$T/cite.json" >/dev/null 2>&1 || rc=$?
assert_exit "an inventory naming no path is an error, never a clean review" 2 "$rc"

# --- option-shaped file names and padded inventory lines ---
mkdir -p "$T/dash"
printf '%s\n' "  scripts/a.sh  " >"$T/dash/-inv"
cp "$T/body.json" "$T/dash/-result.json"
rc=0
out=$(cd "$T/dash" && /bin/sh "$VERIFY" --inventory -inv --result -result.json 2>/dev/null) || rc=$?
assert_exit "option-shaped inventory and result names are read as files" 0 "$rc"
assert_eq "a padded inventory line still carries its path" 0 "$(field '.dropped | length')"

# --- a jq that cannot run the check is an environment error ---
mkdir -p "$T/shim"
real_jq=$(command -v jq)
cat >"$T/shim/jq" <<EOF
#!/bin/sh
case "\$*" in *fields_ok*) exit 3 ;; esac
exec "$real_jq" "\$@"
EOF
chmod +x "$T/shim/jq"
rc=0
PATH="$T/shim:$PATH" /bin/sh "$VERIFY" --inventory "$inv" --result "$T/body.json" >/dev/null 2>&1 || rc=$?
assert_exit "a jq failure in the contract run is exit 2, never a failed review" 2 "$rc"

# --- usage ---
rc=0
/bin/sh "$VERIFY" --result "$T/clean.json" >/dev/null 2>&1 || rc=$?
assert_exit "a missing inventory flag is a usage error" 2 "$rc"
rc=0
/bin/sh "$VERIFY" --inventory "$T/absent" --result "$T/clean.json" >/dev/null 2>&1 || rc=$?
assert_exit "an unreadable inventory is an error, never a pass" 2 "$rc"
rc=0
/bin/sh "$VERIFY" --inventory "$inv" --result "$T/absent.json" >/dev/null 2>&1 || rc=$?
assert_exit "an absent result file is failed" 1 "$rc"

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all passed"
