#!/bin/bash
# Tests for scripts/review-reverify.sh — re-running what validated each earlier
# finding against a fresh isolated copy of the current head
# (review-effectiveness REQ-A1.7, REQ-C1.1, D-14).
set -u
unset CDPATH

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REVERIFY="$REPO_ROOT/scripts/review-reverify.sh"

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
assert_lacks() {
  case "$3" in
    *"$2"*) fail "$1 (unexpectedly contains '$2')" ;;
    *) ok "$1" ;;
  esac
}

T=$(mktemp -d "${TMPDIR:-/tmp}/rrv.XXXXXX")
trap 'rm -rf "$T"' EXIT

R=$T/repo
mkdir -p "$R/scripts" "$R/tests"
git init -q "$R"
g() { git -C "$R" -c user.name=t -c user.email=t@t -c commit.gpgsign=false "$@"; }
# The fixed behaviour: --bad is refused with exit 2 and says so.
cat >"$R/scripts/gate.sh" <<'EOF'
#!/bin/sh
case ${1:-} in --bad) printf 'refused: bad input\n' >&2; exit 2 ;; esac
exit 0
EOF
cat >"$R/tests/test-gate.sh" <<'EOF'
#!/bin/bash
sh scripts/gate.sh --bad 2>/dev/null
[ $? -eq 2 ]
EOF
# A branch-controlled hook; a host config pointing core.hooksPath at it must
# never run it while the copy is set up.
mkdir "$R/hk"
printf '#!/bin/sh\ntouch %s/hook-ran\n' "$T" >"$R/hk/post-checkout"
chmod +x "$R/hk/post-checkout"
g add -A
g commit -q -m fixed
g remote add origin https://example.invalid/repo.git

REC=$T/records.txt
cat >"$REC" <<'EOF'
review-repro 1

# The fail-open finding: --bad used to exit 0.
finding F-1
kind reproduction
run sh scripts/gate.sh --bad
exit 2
output-contains refused
output-lacks Traceback

finding F-2
kind test
run bash tests/test-gate.sh
exit 0
EOF

# A private TMPDIR, so the leftover scan below sees only this file's copies,
# and sentinel state homes, so the redirect is asserted whether or not the
# caller's environment sets them.
mkdir "$T/tmp"
rv() {
  (cd "$R" && TMPDIR=$T/tmp CLAUDE_PLUGIN_DATA=/sentinel/plugin-data \
    XDG_CONFIG_HOME=/sentinel/config XDG_STATE_HOME=/sentinel/state \
    XDG_CACHE_HOME=/sentinel/cache XDG_DATA_HOME=/sentinel/data \
    PLANWRIGHT_FLEET_STATE_DIR=/sentinel/fleet CLAUDE_DIR=/sentinel/claude "$REVERIFY" "$@")
}

# --- every fix holds ----------------------------------------------------------
out=$(rv --records "$REC" 2>&1)
assert_exit "every fix holds" 0 $?
assert_contains "the reproduction held" "held	F-1	reproduction" "$out"
assert_contains "the targeted test held" "held	F-2	test" "$out"

# --- the copy is isolated (REQ-C1.1) ------------------------------------------
cat >"$T/iso.txt" <<EOF
review-repro 1
finding ISO-1
kind reproduction
run touch made-in-copy && test -z "\$(git remote)" && test "\$HOME" != "$HOME" && test -n "\$PLANWRIGHT_FLEET_STATE_DIR" && test -n "\$CLAUDE_DIR" && case "\$CLAUDE_PLUGIN_DATA:\$XDG_CONFIG_HOME:\$XDG_STATE_HOME:\$XDG_CACHE_HOME:\$XDG_DATA_HOME:\$PLANWRIGHT_FLEET_STATE_DIR:\$CLAUDE_DIR" in *sentinel*) false ;; esac && printf 'home=%s\n' "\$HOME"
exit 0
output-contains home=
EOF
before=$(git -C "$R" status --porcelain)
out=$(rv --records "$T/iso.txt" 2>&1)
assert_exit "the copy has no remote and a redirected home and state home" 0 $?
if [ ! -e "$R/made-in-copy" ]; then ok "the live worktree is untouched"; else fail "the live worktree is untouched"; fi
if [ "$(git -C "$R" status --porcelain)" = "$before" ]; then ok "live status unchanged"; else fail "live status unchanged"; fi
assert_contains "the live remote is kept" "example.invalid" "$(git -C "$R" remote -v)"
leftover=$(find "$T/tmp" -mindepth 1 -maxdepth 1 2>/dev/null | head -1)
if [ -z "$leftover" ]; then ok "the copy is removed on exit"; else fail "the copy is removed on exit ($leftover)"; fi

# A hook exports the repository's location; the copy must never act on it.
live_head=$(git -C "$R" symbolic-ref -q HEAD)
out=$(GIT_DIR=$R/.git GIT_WORK_TREE=$R GIT_INDEX_FILE=$R/.git/index rv --records "$REC" 2>&1)
assert_exit "an exported GIT_DIR still re-verifies" 0 $?
assert_contains "an exported GIT_DIR leaves the live branch checked out" "$live_head" "$(git -C "$R" symbolic-ref -q HEAD 2>&1)"
assert_contains "an exported GIT_DIR leaves the live remote" "example.invalid" "$(git -C "$R" remote -v)"
# GIT_DIR alone, as many hooks export it, is the case that would act on the
# live repository without failing the clone.
out=$(GIT_DIR=$R/.git rv --records "$REC" 2>&1)
assert_exit "an exported GIT_DIR alone still re-verifies" 0 $?
assert_contains "GIT_DIR alone leaves the live branch checked out" "$live_head" "$(git -C "$R" symbolic-ref -q HEAD 2>&1)"
assert_contains "GIT_DIR alone leaves the live remote" "example.invalid" "$(git -C "$R" remote -v)"

# Credentials, git configuration, and the shared temporary directory stay out.
cat >"$T/env.txt" <<EOF
review-repro 1
finding ENV-1
kind reproduction
run test -z "\${GH_TOKEN-}\${SSH_AUTH_SOCK-}\${ANTHROPIC_API_KEY-}" && ! git config sentinel.key && test -d "\$TMPDIR" && test "\$TMPDIR" != "$T/tmp" && test "\${TMPDIR%/tmp}" = "\${HOME%/home}"
exit 0
EOF
out=$(GH_TOKEN=sentinel-token SSH_AUTH_SOCK=/sentinel/agent ANTHROPIC_API_KEY=sentinel-key \
  GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=sentinel.key GIT_CONFIG_VALUE_0=leaked rv --records "$T/env.txt" 2>&1)
assert_exit "credentials and git config do not reach the copy" 0 $?
assert_contains "the environment record held" "held	ENV-1	reproduction" "$out"

# Host git configuration never reaches the copy's setup either.
printf '[core]\n\thooksPath = hk\n' >"$T/global.gitconfig"
out=$(GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0=hk rv --records "$REC" 2>&1)
assert_exit "an exported hooksPath still re-verifies" 0 $?
if [ ! -e "$T/hook-ran" ]; then ok "an exported hooksPath runs no branch hook at setup"; else fail "an exported hooksPath runs no branch hook at setup"; fi
rm -f "$T/hook-ran"
out=$(GIT_CONFIG_GLOBAL=$T/global.gitconfig rv --records "$REC" 2>&1)
if [ ! -e "$T/hook-ran" ]; then ok "a global hooksPath runs no branch hook at setup"; else fail "a global hooksPath runs no branch hook at setup"; fi
rm -f "$T/hook-ran"

# The record starts with the default INT and QUIT dispositions, so a
# reproduction that signals itself sees what a terminal would.
if env --default-signal=INT true 2>/dev/null; then
  printf "review-repro 1\nfinding SIG\nkind reproduction\nrun sh -c 'kill -INT \$\$; sleep 1; exit 0'\nexit 130\n" >"$T/sig.txt"
  out=$(rv --records "$T/sig.txt" 2>&1)
  assert_contains "a record's INT is not ignored" "held	SIG	reproduction" "$out"
else
  echo "skip: env lacks --default-signal; the signal-disposition case is not run"
fi

# A record that commits has a git identity.
printf 'review-repro 1\nfinding ID\nkind reproduction\nrun git commit -q --allow-empty -m probe\nexit 0\n' >"$T/ident.txt"
out=$(rv --records "$T/ident.txt" 2>&1)
assert_contains "a record can commit in its copy" "held	ID	reproduction" "$out"

# A relative TMPDIR still gives the record absolute homes.
# shellcheck disable=SC2016 # the record's line expands in the record's shell
printf 'review-repro 1\nfinding REL\nkind reproduction\nrun case $HOME:$TMPDIR in /*:/*) test -d "$HOME" ;; *) exit 9 ;; esac\nexit 0\n' >"$T/rel.txt"
mkdir "$R/.reltmp"
out=$(cd "$R" && TMPDIR=.reltmp "$REVERIFY" --records "$T/rel.txt" 2>&1)
assert_contains "a relative TMPDIR gives absolute homes" "held	REL	reproduction" "$out"
rm -rf "$R/.reltmp"

# A record that never started is a setup failure, never its verdict.
mkdir "$T/fakebin"
printf '#!/bin/sh\nexit 127\n' >"$T/fakebin/env"
chmod +x "$T/fakebin/env"
printf 'review-repro 1\nfinding NS\nkind reproduction\nrun true\nexit 127\n' >"$T/ns.txt"
out=$(PATH=$T/fakebin:$PATH rv --records "$T/ns.txt" 2>&1)
assert_exit "a record that never started is exit 4" 4 $?
assert_lacks "a record that never started has no verdict" "held	NS" "$out"

# A record's backgrounded process does not outlive its copy.
if command -v setsid >/dev/null 2>&1; then
  printf 'review-repro 1\nfinding BG\nkind test\nrun sleep 60 >/dev/null 2>&1 & echo $! >%s/bg.pid\nexit 0\n' "$T" >"$T/bg.txt"
  out=$(rv --records "$T/bg.txt" 2>&1)
  bg=$(cat "$T/bg.pid" 2>/dev/null)
  # A killed process may linger briefly as a zombie on a loaded host.
  i=0
  while [ -n "$bg" ] && kill -0 "$bg" 2>/dev/null && [ "$i" -lt 50 ]; do
    case $(cut -d' ' -f3 "/proc/$bg/stat" 2>/dev/null) in Z) break ;; esac
    sleep 0.1
    i=$((i + 1))
  done
  if [ -n "$bg" ] && { ! kill -0 "$bg" 2>/dev/null || [ "$(cut -d' ' -f3 "/proc/$bg/stat" 2>/dev/null)" = Z ]; }; then
    ok "a backgrounded process is ended with its record"
  else
    fail "a backgrounded process is ended with its record (pid ${bg:-none} alive)"
    [ -z "$bg" ] || kill "$bg" 2>/dev/null
  fi
  # A job in its own process group is still in the record's session.
  printf "review-repro 1\nfinding JOB\nkind test\nrun bash -c 'set -m; sleep 60 >/dev/null 2>&1 & echo \$! >%s/job.pid'\nexit 0\n" "$T" >"$T/job.txt"
  out=$(rv --records "$T/job.txt" 2>&1)
  job=$(cat "$T/job.pid" 2>/dev/null)
  i=0
  while [ -n "$job" ] && kill -0 "$job" 2>/dev/null && [ "$i" -lt 50 ]; do
    case $(cut -d' ' -f3 "/proc/$job/stat" 2>/dev/null) in Z) break ;; esac
    sleep 0.1
    i=$((i + 1))
  done
  if [ -n "$job" ] && { ! kill -0 "$job" 2>/dev/null || [ "$(cut -d' ' -f3 "/proc/$job/stat" 2>/dev/null)" = Z ]; }; then
    ok "a job in its own process group is ended with its record"
  else
    fail "a job in its own process group is ended with its record (pid ${job:-none} alive)"
    [ -z "$job" ] || kill "$job" 2>/dev/null
  fi
  # The session sweep does not depend on pkill where /proc lists sessions.
  if [ -d /proc/self ]; then
    mkdir "$T/nopkill"
    printf '#!/bin/sh\nexit 1\n' >"$T/nopkill/pkill"
    chmod +x "$T/nopkill/pkill"
    rm -f "$T/job.pid"
    out=$(PATH=$T/nopkill:$PATH rv --records "$T/job.txt" 2>&1)
    job=$(cat "$T/job.pid" 2>/dev/null)
    i=0
    while [ -n "$job" ] && kill -0 "$job" 2>/dev/null && [ "$i" -lt 50 ]; do
      case $(cut -d' ' -f3 "/proc/$job/stat" 2>/dev/null) in Z) break ;; esac
      sleep 0.1
      i=$((i + 1))
    done
    if [ -n "$job" ] && { ! kill -0 "$job" 2>/dev/null || [ "$(cut -d' ' -f3 "/proc/$job/stat" 2>/dev/null)" = Z ]; }; then
      ok "a job is ended with its record without pkill"
    else
      fail "a job is ended with its record without pkill (pid ${job:-none} alive)"
      [ -z "$job" ] || kill "$job" 2>/dev/null
    fi
  fi
  # A session member whose name holds a newline cannot steer the sweep onto
  # a process outside the session; it sits in its own group, so the group
  # kill does not end it first.
  if [ -d /proc/self ]; then
    sleep 60 >/dev/null 2>&1 &
    victim=$!
    cat >"$T/nl.txt" <<EOF
review-repro 1
finding NL
kind test
run n=\$(printf '\\nx'); n=\${n%x}; f="$T/a\${n}$victim x"; printf '#!/bin/sh\\nsleep 60\\n' >"\$f" && chmod +x "\$f" && bash -c 'set -m; "\$0" >/dev/null 2>&1 & sleep 1' "\$f"
exit 0
EOF
    out=$(rv --records "$T/nl.txt" 2>&1)
    sleep 0.5
    # The victim is this shell's child, so a killed one lingers as a zombie.
    if kill -0 "$victim" 2>/dev/null && [ "$(cut -d' ' -f3 "/proc/$victim/stat" 2>/dev/null)" != Z ]; then
      ok "a newline in a process name never kills a process outside the session"
    else
      fail "a newline in a process name never kills a process outside the session"
    fi
    kill "$victim" 2>/dev/null
    rm -f "$T"/a*"$victim x"
  fi
else
  echo "skip: setsid is not installed; the backgrounded-process case is not run"
fi

# --- the copy is the committed head, never the dirty worktree -----------------
printf 'exit 0\n' >"$R/scripts/gate.sh"
out=$(rv --records "$REC" 2>&1)
assert_exit "an uncommitted edit does not reach the copy" 0 $?
g checkout -q -- scripts/gate.sh

# --- a regressed fix is a finding ---------------------------------------------
cat >"$R/scripts/gate.sh" <<'EOF'
#!/bin/sh
exit 0
EOF
g commit -q -am "regress the fix"
out=$(rv --records "$REC" 2>/dev/null)
assert_exit "a regressed reproduction fails" 1 $?
assert_contains "the reproduction regressed on its exit code" "regressed	F-1	reproduction	exit 0, expected 2" "$out"
assert_contains "the targeted test regressed" "regressed	F-2	test	exit 1, expected 0" "$out"

cat >"$T/out.txt" <<'EOF'
review-repro 1
finding F-3
kind rule
run printf 'warning: SC2086\n'
exit 0
output-lacks SC2086
EOF
out=$(rv --records "$T/out.txt" 2>/dev/null)
assert_exit "a forbidden output line is a regression" 1 $?
assert_contains "names the forbidden text" "regressed	F-3	rule	output holds 'SC2086'" "$out"
cat >"$T/out2.txt" <<'EOF'
review-repro 1
finding F-4
kind rule
run true
exit 0
output-contains clean
EOF
out=$(rv --records "$T/out2.txt" 2>/dev/null)
assert_exit "a missing expected output is a regression" 1 $?
assert_contains "names the missing text" "regressed	F-4	rule	output lacks 'clean'" "$out"

# --- --head pins the copy -----------------------------------------------------
fixed=$(g rev-parse HEAD~1)
out=$(rv --records "$REC" --head "$fixed" 2>&1)
assert_exit "--head re-verifies an earlier commit" 0 $?

# --- an empty record file -----------------------------------------------------
printf 'review-repro 1\n' >"$T/empty.txt"
out=$(rv --records "$T/empty.txt" 2>&1)
assert_exit "no records is nothing to re-verify" 0 $?
assert_contains "says so" "no records" "$out"
: >"$T/zero.txt"
out=$(rv --records "$T/zero.txt" 2>&1)
assert_exit "an empty file is malformed, not a pass" 2 $?

# --- indented lines parse like flush ones ---------------------------------------
printf 'review-repro 1\n  # an indented note\nfinding I\n  kind test\n  run printf indented\n  exit 0\n  output-contains indented\n' >"$T/indent.txt"
out=$(rv --records "$T/indent.txt" 2>&1)
assert_exit "indented field lines are read by their field" 0 $?
assert_contains "the indented record held" "held	I	test" "$out"

# --- a finding id never collides with the script's own files ---------------------
printf 'review-repro 1\nfinding runs\nkind test\nrun true\nexit 0\nfinding expect\nkind test\nrun true\nexit 0\nfinding z\nkind test\nrun true\nexit 0\n' >"$T/names.txt"
out=$(rv --records "$T/names.txt" 2>&1)
assert_exit "ids named like work files all run" 0 $?
assert_contains "the record after them ran" "held	z	test" "$out"

# --- a read-only leftover is cleaned and never a verdict ---------------------------
printf 'review-repro 1\nfinding ro\nkind test\nrun mkdir -p ro/x && touch ro/x/f && chmod 555 ro/x\nexit 0\nfinding after\nkind test\nrun true\nexit 0\n' >"$T/ro.txt"
out=$(rv --records "$T/ro.txt" 2>&1)
assert_exit "a read-only file in the copy does not end the run" 0 $?
assert_contains "the next record still ran" "held	after	test" "$out"
leftover=$(find "$T/tmp" -mindepth 1 -maxdepth 1 2>/dev/null | head -1)
if [ -z "$leftover" ]; then ok "a read-only copy is still removed"; else fail "a read-only copy is still removed ($leftover)"; fi

# --- --log-dir keeps each record's output; --timeout bounds a record -------------
mkdir "$T/logs"
printf 'review-repro 1\nfinding L\nkind test\nrun printf logged-output\nexit 0\n' >"$T/log.txt"
out=$(rv --records "$T/log.txt" --log-dir "$T/logs" 2>&1)
assert_contains "the log holds the record's output" "logged-output" "$(cat "$T/logs/L.log" 2>/dev/null)"
if command -v timeout >/dev/null 2>&1; then
  printf 'review-repro 1\nfinding slow\nkind test\nrun sleep 5\nexit 0\n' >"$T/slow.txt"
  out=$(rv --records "$T/slow.txt" --timeout 1 2>&1)
  assert_contains "a timed-out record reports 124" "regressed	slow	test	exit 124, expected 0" "$out"
fi

out=$(rv --records "$REC" --timeout 00 2>&1)
assert_exit "an all-zero --timeout is refused" 2 $?

# A log that cannot be written is a setup failure, never a regression verdict.
mkdir "$T/ro-logs"
printf 'review-repro 1\nfinding RO\nkind test\nrun chmod a-w %s/ro-logs\nexit 0\n' "$T" >"$T/ro.txt"
out=$(rv --records "$T/ro.txt" --log-dir "$T/ro-logs" 2>&1)
assert_exit "an unwritable log is exit 4, not regressed" 4 $?
chmod u+w "$T/ro-logs"

# Output that cannot be read never passes an output-lacks check.
printf 'review-repro 1\nfinding UNREAD\nkind test\nrun echo forbidden-text; chmod 000 ../out\nexit 0\noutput-lacks forbidden-text\n' >"$T/unread.txt"
out=$(rv --records "$T/unread.txt" 2>&1)
assert_exit "unreadable output is not a held fix" 1 $?
assert_contains "unreadable output is named" "cannot read" "$out"

# --- malformed records are refused before anything runs -----------------------
refused() {
  # refused <label> <needle> <record body>
  printf 'review-repro 1\n%s\n' "$3" >"$T/bad.txt"
  out=$(rv --records "$T/bad.txt" 2>&1)
  assert_exit "$1: refused" 2 $?
  assert_contains "$1: says why" "$2" "$out"
}
refused "unknown kind" "kind" "$(printf 'finding X\nkind vibes\nrun true\nexit 0')"
refused "no run line" "run" "$(printf 'finding X\nkind test\nexit 0')"
refused "two run lines" "run" "$(printf 'finding X\nkind test\nrun true\nrun false\nexit 0')"
refused "no exit line" "exit" "$(printf 'finding X\nkind test\nrun true')"
refused "non-numeric exit" "exit" "$(printf 'finding X\nkind test\nrun true\nexit two')"
refused "bad finding id" "finding" "$(printf 'finding ../x\nkind test\nrun true\nexit 0')"
refused "a field before any finding" "before" "$(printf 'kind test\nfinding X\nkind test\nrun true\nexit 0')"
refused "an unknown field" "unknown" "$(printf 'finding X\nkind test\nrun true\nexit 0\ncolour blue')"
refused "two kind lines" "kind" "$(printf 'finding X\nkind test\nkind rule\nrun true\nexit 0')"
refused "two exit lines" "exit" "$(printf 'finding X\nkind test\nrun true\nexit 0\nexit 1')"
refused "a repeated finding id" "repeated" "$(printf 'finding X\nkind test\nrun true\nexit 0\nfinding X\nkind test\nrun true\nexit 0')"
printf 'something else\n' >"$T/bad.txt"
out=$(rv --records "$T/bad.txt" 2>&1)
assert_exit "a file without the format header is refused" 2 $?
printf 'review-repro 1\nfinding X\nkind test\nrun touch %s/ran-anyway\nexit 0\nfinding Y\nkind vibes\nrun true\nexit 0\n' "$T" >"$T/bad.txt"
out=$(rv --records "$T/bad.txt" 2>&1)
if [ ! -e "$T/ran-anyway" ]; then ok "nothing runs when a later record is malformed"; else fail "nothing runs when a later record is malformed"; fi
printf 'review-repro 1\nfinding X\nkind test\nrun true\nexit 0\noutput-lacks partial-marker\nfinding Y\nkind vibes\n' >"$T/bad.txt"
out=$(rv --records "$T/bad.txt" 2>&1)
assert_lacks "a malformed file's message carries no normalized records" "partial-marker" "$out"
out=$(rv 2>&1)
assert_exit "no records file is a usage error" 2 $?
ESC=$(printf '\033')
out=$(rv --records "$T/no${ESC}[31msuch.txt" 2>&1)
assert_exit "a missing records file is refused" 2 $?
assert_lacks "a refusal carries no control bytes" "$ESC" "$out"

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all review-reverify tests passed"
