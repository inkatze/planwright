#!/bin/bash
# Tests for scripts/planwright-commit-trailers.sh — the shared commit helper
# that stamps `Planwright-Task: <spec>/<id>` footer trailers onto a commit
# message (Task 2, REQ-C1.4, D-2).
#
# Trailer contract (D-2, REQ-C1.4):
#   - the helper reads a commit message on stdin and writes it back with one
#     `Planwright-Task: <spec>/<id>` footer trailer per task ref given as an
#     argument (a bundled commit passes several refs → one trailer each);
#   - trailers land in the footer via git's native interpret-trailers, never
#     the subject line (D-2: "discreet by design — footer only");
#   - Task 1's derivation parses them back via git's trailer mechanism, so a
#     round-tripped commit yields the ids via `%(trailers:key=Planwright-Task)`;
#   - the message body is preserved and no Claude/co-author attribution is
#     introduced (the no-attribution rule is unaffected);
#   - each ref is grammar-validated before use: spec `^[a-z0-9][a-z0-9-]*$`
#     (≤64), id `^[0-9]+(\.[0-9]+)?$`; a malformed ref or no ref is refused
#     (exit 2) and nothing is emitted (never interpolated);
#   - re-piping an already-stamped message is idempotent (no duplicate).
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
SCRIPT="$here/../scripts/planwright-commit-trailers.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -x "$SCRIPT" ] || fail "scripts/planwright-commit-trailers.sh missing or not executable"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# trailers_of reads a message on stdin and prints its Planwright-Task values,
# one per line, using git's own trailer parser (the mechanism Task 1 uses).
trailers_of() {
  git interpret-trailers --only-trailers --only-input 2>/dev/null \
    | sed -n 's/^Planwright-Task: //p'
}

# 1. Single ref: the trailer is appended in the footer and parses back.
out=$(printf 'feat(x): subject\n\nbody line\n' \
  | /bin/bash "$SCRIPT" orchestration-concurrency/2)
echo "$out" | grep -q '^body line$' || fail "single: body not preserved"
got=$(printf '%s\n' "$out" | trailers_of)
[ "$got" = "orchestration-concurrency/2" ] \
  || fail "single: expected one trailer orchestration-concurrency/2, got [$got]"
# Footer only — the subject line must not carry the trailer (D-2).
echo "$out" | head -1 | grep -q 'Planwright-Task' \
  && fail "single: trailer leaked into the subject line"
echo "ok: single ref appends one footer trailer that parses back"

# 2. Bundle: one trailer per task, both parse back, order preserved.
out=$(printf 'feat: bundled subject\n' \
  | /bin/bash "$SCRIPT" demo/5 demo/6)
got=$(printf '%s\n' "$out" | trailers_of | tr '\n' ',')
[ "$got" = "demo/5,demo/6," ] \
  || fail "bundle: expected demo/5 then demo/6, got [$got]"
echo "ok: a bundled commit carries one trailer per task"

# 3. Idempotent: re-piping with the same ref does not duplicate it.
out2=$(printf '%s\n' "$out" | /bin/bash "$SCRIPT" demo/5 demo/6)
got=$(printf '%s\n' "$out2" | trailers_of | tr '\n' ',')
[ "$got" = "demo/5,demo/6," ] \
  || fail "idempotent: re-stamp duplicated trailers, got [$got]"
echo "ok: re-stamping an already-trailered message is idempotent"

# 4. Dotted task ids are valid (the `^[0-9]+(\.[0-9]+)?$` grammar).
got=$(printf 'feat: s\n' | /bin/bash "$SCRIPT" demo/3.5 | trailers_of)
[ "$got" = "demo/3.5" ] || fail "dotted id: expected demo/3.5, got [$got]"
echo "ok: dotted task ids round-trip"

# 5. The no-attribution rule is unaffected: only Planwright-Task is added.
out=$(printf 'feat: s\n\nbody\n' | /bin/bash "$SCRIPT" demo/2)
echo "$out" | grep -qiE 'co-authored-by|generated with|claude' \
  && fail "no-attribution: helper introduced an attribution line"
echo "ok: helper adds no Claude/co-author attribution"

# 6. Malformed refs and missing args are refused (exit 2), nothing emitted.
assert_refused() {
  label=$1
  shift
  rc=0
  out=$(printf 'feat: s\n' | /bin/bash "$SCRIPT" "$@" 2>/dev/null) || rc=$?
  [ "$rc" = 2 ] || fail "$label: expected exit 2, got $rc"
  [ -z "$out" ] || fail "$label: emitted output on refusal [$out]"
}
assert_refused "no args" # (no ref)
assert_refused "no slash" demo2
assert_refused "empty spec" /2
assert_refused "empty id" demo/
assert_refused "non-numeric id" demo/x
assert_refused "uppercase spec" Demo/2
assert_refused "path-escape spec" ../etc/2
assert_refused "command injection" 'demo/2; rm -rf x'
echo "ok: malformed refs and missing args are refused without emitting"

# 7. Round-trip through a real commit: git's %(trailers) reader recovers the
#    ids, and the subject line is clean (the Task 1 derivation's view).
repo="$tmp/repo"
mkdir -p "$repo"
(
  cd "$repo"
  git init -q
  git config user.email t@example.com
  git config user.name Tester
  git config commit.gpgsign false
  : >file
  git add file
  printf 'feat: real subject\n\nexplanatory body\n' \
    | /bin/bash "$SCRIPT" demo/7 demo/8 | git commit -q -F -
)
subj=$(cd "$repo" && git log -1 --format='%s')
[ "$subj" = "feat: real subject" ] \
  || fail "round-trip: subject altered to [$subj]"
got=$(cd "$repo" && git log -1 --format='%(trailers:key=Planwright-Task,valueonly)' | tr '\n' ',' | sed 's/,*$//')
[ "$got" = "demo/7,demo/8" ] \
  || fail "round-trip: git trailer reader got [$got], expected demo/7,demo/8"
echo "ok: a real commit round-trips through git's trailer reader"

echo "all planwright-commit-trailers tests passed"
