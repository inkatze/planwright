#!/bin/sh
# Tests for scripts/isolated-hosting.sh, the run-time degradation of an
# `isolated` step whose backend cannot spawn a fresh session (custom-steps
# REQ-D1 and doctrine/custom-steps.md, Hosting: "degrades to in-session and
# records it"). Every backend presence is pinned so the outcome does not depend
# on the host's installed CLIs.
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$here/.." && pwd)
IH="$repo_root/scripts/isolated-hosting.sh"

failures=0
fail() {
  printf '%s\n' "FAIL: $1" >&2
  failures=$((failures + 1))
}
ok() { printf '%s\n' "ok: $1"; }
TAB=$(printf '\t')

[ -f "$IH" ] || {
  echo "FAIL: scripts/isolated-hosting.sh missing" >&2
  exit 1
}

tmp=$(mktemp -d "${TMPDIR:-/tmp}/test-isolated-hosting.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT

stubbin="$tmp/bin"
mkdir -p "$stubbin"
# A pluggable adapter that answers advertise with a session-grade set.
cat >"$stubbin/planwright-backend-grader" <<'ADAPTER'
#!/bin/sh
echo "true true true false true yes full-session true both"
ADAPTER
# A pluggable adapter that is session-grade-false (in-harness).
cat >"$stubbin/planwright-backend-inharness" <<'ADAPTER'
#!/bin/sh
echo "false false false false true no light false model"
ADAPTER
chmod +x "$stubbin/planwright-backend-grader" "$stubbin/planwright-backend-inharness"

# ih <backend>: run resolve with presence pinned; the stdout is the answer.
ih() {
  env PATH="$stubbin:/usr/bin:/bin" \
    PLANWRIGHT_BACKEND_TMUX=0 \
    PLANWRIGHT_BACKEND_SUBAGENT=1 \
    PLANWRIGHT_BACKEND_STREAM_JSON_PERSISTENT=0 \
    PLANWRIGHT_BACKEND_HEADLESS_ONESHOT=0 \
    /bin/sh "$IH" resolve "$1"
}

# field <output> <key>: the value of one key<TAB>value line.
field() {
  printf '%s\n' "$1" | awk -F "$TAB" -v k="$2" '$1 == k { print $2; found = 1 }
    END { if (!found) exit 3 }'
}

# 1. A pluggable backend with no adapter on PATH cannot spawn: it degrades.
out=$(ih claude-code) || {
  fail "resolve of an unadapted backend exited nonzero"
  out=''
}
[ "$(field "$out" hosting)" = in-session ] \
  || fail "unadapted claude-code did not degrade to in-session: $out"
case "$(field "$out" reason)" in
  *claude-code*) ok "an unadapted backend degrades to in-session with a reason naming it" ;;
  *) fail "degrade reason does not name the backend: $out" ;;
esac

# 2. A session-grade pluggable adapter keeps the step isolated, reason empty.
out=$(ih grader) || fail "resolve of a session-grade adapter exited nonzero"
[ "$(field "$out" hosting)" = isolated ] \
  || fail "session-grade adapter did not stay isolated: $out"
[ -z "$(field "$out" reason)" ] \
  || fail "an isolated resolve carries a reason: $out"
ok "a session-grade backend keeps its isolated hosting, no reason"

# 3. An in-harness backend (session_grade no) cannot spawn: it degrades.
out=$(ih inharness) || fail "resolve of an in-harness adapter exited nonzero"
[ "$(field "$out" hosting)" = in-session ] \
  || fail "in-harness backend did not degrade: $out"
ok "an in-harness backend degrades to in-session"

# 4. The shipped subagent rung is in-harness too, so it degrades; the shipped
#    session-grade tmux rung is absent here (pinned off), so it degrades too.
out=$(ih subagent)
[ "$(field "$out" hosting)" = in-session ] || fail "subagent did not degrade: $out"
out=$(ih tmux)
[ "$(field "$out" hosting)" = in-session ] || fail "an absent tmux did not degrade: $out"
ok "absent or in-harness shipped rungs degrade to in-session"

# 5. Hostile or malformed names are refused with exit 2 and no hosting line.
for bad in 'claude;id' '../evil' 'TMUX' ''; do
  rc=0
  out=$(ih "$bad" 2>/dev/null) || rc=$?
  [ "$rc" -eq 2 ] || fail "hostile backend '$bad' exited $rc, expected 2"
  [ -z "$out" ] || fail "hostile backend '$bad' printed output: $out"
done
ok "hostile backend names are refused with exit 2"

# 6. The output carries exactly the two keys, in order.
out=$(ih claude-code)
[ "$(printf '%s\n' "$out" | awk -F "$TAB" '{ printf "%s ", $1 }')" = "hosting reason " ] \
  || fail "unexpected output keys: $out"
ok "resolve prints hosting then reason"

# 7. Usage errors exit 2; a copy without its sibling helper exits 5.
rc=0
sh "$IH" resolve >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 2 ] || fail "resolve with no backend exited $rc, expected 2"
rc=0
sh "$IH" bogus claude-code >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 2 ] || fail "unknown subcommand exited $rc, expected 2"
mkdir -p "$tmp/alone"
cp "$IH" "$tmp/alone/isolated-hosting.sh"
rc=0
sh "$tmp/alone/isolated-hosting.sh" resolve claude-code >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 5 ] || fail "missing orchestrate-backends.sh exited $rc, expected 5"
ok "usage errors exit 2 and a missing sibling helper exits 5"

if [ "$failures" -ne 0 ]; then
  printf '%s\n' "$failures failure(s)" >&2
  exit 1
fi
echo "all isolated-hosting tests passed"
