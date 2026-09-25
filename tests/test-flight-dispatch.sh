#!/bin/bash
# Tests for scripts/flight-dispatch.sh — the visual-flight dispatch path
# (tower-front-door Task 5; D-7, D-11 · REQ-B1.5, REQ-C1.1–C1.6, REQ-G1.5).
#
# Properties verified:
#   1. `home` declares the record's home from the one predicate: `pr` with an
#      `origin` remote and an authenticated `gh`, `file` otherwise.
#   2. Rung selection stays in /offload (REQ-C1.2): `dispatch` takes the rung
#      as an input, refuses to run without one, refuses the rungs a flight
#      cannot fly on, and never reads the host's backend set itself.
#   3. A print-rung dispatch places the flight on `planwright/flight/<id>` in
#      `.claude/worktrees/flight-<id>` (REQ-C1.1) and reports the launch the
#      human runs, the record home, the brief, and the plugin-root pair.
#   4. The worker brief carries the doctrine load (the /execute-task manifest
#      set plus flight-rules), the configured review_sequence in order, each
#      skill `--nested` (REQ-C1.3), the audit-record contract, draft-only
#      landing with no ready flip or merge (REQ-C1.4), and the gate-wiring hard
#      pause whatever the grounds said (REQ-B1.5).
#   5. Concurrency (REQ-C1.5): a flight beyond `max_parallel_units` is declined
#      with a re-ask line and nothing placed; a freed slot admits the re-ask.
#   6. Two flights from one slug never collide (REQ-C1.1).
#   7. The tmux rung hands the worker its brief through the native
#      `claude --worktree` attach.
#   8. A read-only offload mints no flight identity (REQ-C1.6).
#   9. Hostile or malformed input is refused before anything is placed.
#
# The live end-to-end run (a real worker converging and landing) is the
# acceptance demo's, not this suite's.
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
set -u
LC_ALL=C
export LC_ALL
unset CDPATH
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_SYSTEM=/dev/null

here=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$here/.." && pwd -P)
SCRIPT="$ROOT/scripts/flight-dispatch.sh"
OFFLOAD="$ROOT/scripts/offload-dispatch.sh"
TAB=$(printf '\t')

fails=0
fail() {
  echo "FAIL: $1" >&2
  fails=$((fails + 1))
}

[ -x "$SCRIPT" ] || {
  echo "FAIL: scripts/flight-dispatch.sh missing or not executable" >&2
  exit 1
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
tmp=$(cd "$tmp" && pwd -P)

gitc() {
  _r=$1
  shift
  git -C "$_r" -c user.name=test -c user.email=test@example.invalid \
    -c commit.gpgsign=false -c init.defaultBranch=main "$@"
}

# A stub `gh` whose `auth status` answers per GH_STUB_AUTH, on a PATH that
# otherwise keeps the real tools.
mkdir -p "$tmp/bin"
cat >"$tmp/bin/gh" <<'EOF'
#!/bin/sh
[ "$1 $2" = "auth status" ] && exit "${GH_STUB_AUTH:-0}"
exit 0
EOF
chmod +x "$tmp/bin/gh"
export PATH="$tmp/bin:$PATH"

# A fresh case directory: a bare origin, a primary clone with main pushed, and
# isolated fleet/fetch state so no case touches the machine's fleet home or
# contends on its lock.
n=0
new_case() {
  n=$((n + 1))
  c="$tmp/c$n"
  mkdir -p "$c"
  git -c init.defaultBranch=main init -q --bare "$c/origin.git"
  git clone -q "$c/origin.git" "$c/primary" 2>/dev/null
  printf 'x\n' >"$c/primary/README.md"
  gitc "$c/primary" add -A
  gitc "$c/primary" commit -q -m init
  gitc "$c/primary" branch -M main
  gitc "$c/primary" push -q origin main
  export PLANWRIGHT_FLEET_STATE_DIR="$c/fleet"
  export PLANWRIGHT_DISPATCH_FETCH_STATE_DIR="$c/fstate"
  export PLANWRIGHT_DISPATCH_LIVENESS_SKIP_TMUX=1
  export PLANWRIGHT_REPO_ROOT="$c/primary"
  export CLAUDE_DIR="$c/claude"
  printf 'Fix the typo in the README heading.\n' >"$c/ask.txt"
  printf 'visual flight: a one-line wording change, one revert from undone\n' >"$c/grounds.txt"
}

# grounds <text> — write a one-off grounds file and print its path.
grounds() {
  printf '%s\n' "$1" >"$c/g.txt"
  printf '%s' "$c/g.txt"
}

# run <args...> — sets OUT, ERR, RC.
run() {
  OUT=$("$SCRIPT" "$@" </dev/null 2>"$tmp/err")
  RC=$?
  ERR=$(cat "$tmp/err")
}

field() {
  printf '%s\n' "$1" | awk -F"$TAB" -v k="$2" '$1==k {print $2; exit}'
}

dispatch_print() {
  run dispatch readme-typo --backend print --ask-file "$c/ask.txt" \
    --grounds-file "$c/grounds.txt" --repo-root "$c/primary"
}

# --- 1. home ----------------------------------------------------------------
new_case
run home --repo-root "$c/primary"
[ "$RC" -eq 0 ] && [ "$(field "$OUT" home)" = pr ] \
  || fail "home: origin + authenticated gh must declare pr (rc $RC, out: $OUT)"
GH_STUB_AUTH=1 run home --repo-root "$c/primary"
[ "$(field "$OUT" home)" = file ] \
  || fail "home: an unauthenticated gh must declare file (out: $OUT)"
gitc "$c/primary" remote remove origin
run home --repo-root "$c/primary"
[ "$(field "$OUT" home)" = file ] \
  || fail "home: no origin remote must declare file (out: $OUT)"

# --- 2. rung selection stays in /offload -------------------------------------
new_case
run dispatch readme-typo --ask-file "$c/ask.txt" --grounds-file "$c/grounds.txt" --repo-root "$c/primary"
[ "$RC" -eq 2 ] || fail "dispatch without --backend must be a usage error (rc $RC)"
for b in subagent in-session stream-json-persistent headless-oneshot bogus; do
  run dispatch readme-typo --backend "$b" --ask-file "$c/ask.txt" --grounds-file "$c/grounds.txt" \
    --repo-root "$c/primary"
  [ "$RC" -eq 2 ] || fail "dispatch --backend $b must be refused (rc $RC)"
done
if gitc "$c/primary" for-each-ref --format='%(refname)' 'refs/heads/planwright/flight/' | grep -q .; then
  fail "a refused dispatch placed a flight branch"
fi
if grep -v '^[[:space:]]*#' "$SCRIPT" | grep -Eq 'orchestrate-backends|allocation-select|resolve-dispatch-backend'; then
  fail "flight-dispatch.sh reads the backend set itself: rung selection belongs to /offload"
fi

# --- 3 + 4. print rung: placement, report, brief ----------------------------
new_case
dispatch_print
[ "$RC" -eq 0 ] || fail "print dispatch exited $RC: $ERR"
fid=$(field "$OUT" flight)
"$ROOT/scripts/flight-id.sh" check "$fid" 2>/dev/null \
  || fail "report carries no grammar-valid flight id (out: $OUT)"
case $fid in readme-typo-*) ;; *) fail "flight id does not carry the slug: $fid" ;; esac
[ "$(field "$OUT" branch)" = "planwright/flight/$fid" ] \
  || fail "report branch is not planwright/flight/<id>"
gitc "$c/primary" show-ref --verify --quiet "refs/heads/planwright/flight/$fid" \
  || fail "the flight branch was not created"
[ -d "$c/primary/.claude/worktrees/flight-$fid" ] \
  || fail "the flight worktree .claude/worktrees/flight-<id> was not placed"
[ "$(field "$OUT" home)" = pr ] || fail "report home is not pr with origin + gh"
[ "$(field "$OUT" record)" = "draft PR body" ] || fail "pr home must name the draft PR body as the record"
launch=$(field "$OUT" launch)
case $launch in
  *"claude --worktree flight-$fid"*) ;;
  *) fail "print rung must report the native worktree launch, got: $launch" ;;
esac
brief=$(field "$OUT" brief)
[ -f "$brief" ] || fail "the worker brief was not written ($brief)"
case $brief in
  "$c/fleet/"*) ;;
  *) fail "the brief must live under the fleet home, never in the checkout: $brief" ;;
esac
[ -z "$(git -C "$c/primary/.claude/worktrees/flight-$fid" status --porcelain)" ] \
  || fail "the flight worktree is dirty after dispatch"
printf '%s\n' "$OUT" | grep -q "^root${TAB}tower${TAB}$ROOT${TAB}" \
  || fail "report must surface the tower's resolved plugin root (out: $OUT)"
printf '%s\n' "$OUT" | grep -q "^root${TAB}worker${TAB}" \
  || fail "report must surface the worker's plugin root"
[ "$(field "$OUT" root-skew)" = unknown ] \
  || fail "with no installed plugin the skew must read unknown, got $(field "$OUT" root-skew)"

b=$(cat "$brief")
for doc in $(grep -E '^Doctrine: (run-start|point-of-use) ' "$ROOT/skills/execute-task/SKILL.md" | awk '{print $3}') flight-rules; do
  printf '%s\n' "$b" | grep -q -- "- $doc" || fail "brief does not load doctrine '$doc'"
done
printf '%s\n' "$b" | grep -q -- "/planwright:polish --nested" \
  || fail "brief does not carry the configured review_sequence (default polish) --nested"
printf '%s\n' "$b" | grep -q "Fix the typo in the README heading." \
  || fail "brief does not carry the ask"
printf '%s\n' "$b" | grep -q "one revert from undone" \
  || fail "brief does not carry the stated grounds"
printf '%s\n' "$b" | grep -q "planwright/flight/$fid" || fail "brief does not name the branch"
printf '%s\n' "$b" | grep -q "gh pr create --draft" || fail "brief must land a draft PR"
if printf '%s\n' "$b" | grep -Eq 'gh pr ready|gh pr merge'; then
  fail "brief must never carry a ready flip or merge command"
fi
for item in "quoted ask" "routing decision" "lens coverage" "rigor scoping" "worker handle" "revert path" "security-posture" "markup-neutralize"; do
  printf '%s\n' "$b" | grep -qi "$item" || fail "brief audit-record contract is missing '$item'"
done
printf '%s\n' "$b" | grep -q "gate-wiring" || fail "brief does not keep the gate-wiring hard pauses"
printf '%s\n' "$b" | grep -q "steps_convergence" || fail "brief does not name the flight convergence point"
printf '%s\n' "$b" | grep -q "FLIGHT-RESULT:" || fail "brief does not fix the result line"
if grep -v '^[[:space:]]*#' "$SCRIPT" | grep -Eq 'gh pr (ready|merge)'; then
  fail "flight-dispatch.sh must never flip or merge a PR"
fi

# --- 4b. an overridden zone ask still hard-pauses (REQ-B1.5) ----------------
new_case
run dispatch auth-tweak --backend print --ask-file "$c/ask.txt" \
  --grounds-file "$(grounds "visual flight on the operator's override (reservation stated: auth middleware, zone work)")" \
  --repo-root "$c/primary"
[ "$RC" -eq 0 ] || fail "override dispatch exited $RC: $ERR"
grep -q "gate-wiring" "$(field "$OUT" brief)" \
  || fail "an overridden zone flight lost the gate-wiring hard pause"

# --- 4c. configured review_sequence, in order; file home ---------------------
new_case
mkdir -p "$c/primary/.claude"
printf 'review_sequence: [polish, self-review]\n' >"$c/primary/.claude/planwright.local.yml"
gitc "$c/primary" remote remove origin
dispatch_print
[ "$RC" -eq 0 ] || fail "file-home dispatch exited $RC: $ERR"
fid=$(field "$OUT" flight)
[ "$(field "$OUT" home)" = file ] || fail "no remote must declare the file home"
[ "$(field "$OUT" record)" = "specs/_flights/$fid.md" ] \
  || fail "file home must name specs/_flights/<id>.md, got $(field "$OUT" record)"
b=$(cat "$(field "$OUT" brief)")
seq=$(printf '%s\n' "$b" | grep -Eo '/planwright:[a-z-]+ --nested' | tr '\n' ' ')
[ "$seq" = "/planwright:polish --nested /planwright:self-review --nested " ] \
  || fail "brief review_sequence is not the configured order: '$seq'"
printf '%s\n' "$b" | grep -q "specs/_flights/$fid.md" || fail "file-home brief must name the record file"
printf '%s\n' "$b" | grep -qi "do not push" || fail "file-home brief must not push"

# --- 5. concurrency ---------------------------------------------------------
new_case
mkdir -p "$c/primary/.claude"
printf 'max_parallel_units: 1\n' >"$c/primary/.claude/planwright.local.yml"
dispatch_print
[ "$RC" -eq 0 ] || fail "first flight under a bound of 1 exited $RC: $ERR"
first=$(field "$OUT" flight)
dispatch_print
[ "$RC" -eq 3 ] || fail "a flight beyond max_parallel_units must be declined (rc $RC)"
printf '%s\n' "$OUT" | grep -q "^declined${TAB}1${TAB}1$" \
  || fail "decline must report live and bound (out: $OUT)"
[ -n "$(field "$OUT" reask)" ] || fail "decline must state the re-ask path"
count=$(gitc "$c/primary" for-each-ref --format='%(refname)' 'refs/heads/planwright/flight/' | grep -c .)
[ "$count" -eq 1 ] || fail "a declined flight placed a branch ($count flight branches)"
git -C "$c/primary" worktree remove --force "$c/primary/.claude/worktrees/flight-$first"
dispatch_print
[ "$RC" -eq 0 ] || fail "a freed slot must admit the re-asked flight (rc $RC: $ERR)"
if grep -v '^[[:space:]]*#' "$SCRIPT" | grep -Eo 'config-get\.sh"? [a-z_]+' | grep -v 'max_parallel_units' | grep -q .; then
  fail "flight-dispatch.sh reads a config key other than max_parallel_units"
fi

# --- 6. no collision --------------------------------------------------------
new_case
dispatch_print
a=$(field "$OUT" flight)
dispatch_print
b2=$(field "$OUT" flight)
[ -n "$a" ] && [ -n "$b2" ] && [ "$a" != "$b2" ] \
  || fail "two flights from one slug collided ('$a' vs '$b2')"
[ -d "$c/primary/.claude/worktrees/flight-$a" ] && [ -d "$c/primary/.claude/worktrees/flight-$b2" ] \
  || fail "two flights did not get two worktrees"

# --- 7. tmux rung: the brief rides the native attach -------------------------
new_case
run dispatch readme-typo --backend tmux --ask-file "$c/ask.txt" --grounds-file "$c/grounds.txt" \
  --repo-root "$c/primary" --attach-dry-run
[ "$RC" -eq 0 ] || fail "tmux dry-run dispatch exited $RC: $ERR"
fid=$(field "$OUT" flight)
brief=$(field "$OUT" brief)
plan=$(printf '%s\n' "$OUT" | awk -F"$TAB" '$1=="attach-plan" && $2=="launch"')
case $plan in
  *"claude${TAB}--worktree${TAB}flight-$fid${TAB}--tmux=classic${TAB}--${TAB}Read $brief and follow it exactly."*) ;;
  *) fail "tmux attach must launch claude --worktree flight-<id> with the brief prompt, got: $plan" ;;
esac

# --- 8. a read-only offload mints no flight identity -------------------------
new_case
printf 'Summarize the README; change nothing.\n' >"$c/petition.txt"
(cd "$c/primary" && "$OFFLOAD" dispatch print "$c/petition.txt" --unit readonly >/dev/null 2>&1) || true
if gitc "$c/primary" for-each-ref --format='%(refname)' 'refs/heads/planwright/flight/' | grep -q .; then
  fail "a read-only offload created a flight branch"
fi
for _w in "$c/primary/.claude/worktrees"/flight-*; do
  [ ! -e "$_w" ] || fail "a read-only offload placed a flight worktree"
done
[ ! -e "$c/primary/specs/_flights" ] || fail "a read-only offload wrote a flight record"

# --- 9. hostile input -------------------------------------------------------
new_case
for slug in 'Bad' '-x' 'a/b' '../x' 'flight id'; do
  run dispatch "$slug" --backend print --ask-file "$c/ask.txt" --grounds-file "$c/grounds.txt" --repo-root "$c/primary"
  [ "$RC" -eq 2 ] || fail "malformed slug '$slug' must be refused (rc $RC)"
done
run dispatch readme-typo --backend print --ask-file "$c/nope.txt" --grounds-file "$c/grounds.txt" --repo-root "$c/primary"
[ "$RC" -eq 2 ] || fail "a missing ask file must be refused (rc $RC)"
: >"$c/empty.txt"
run dispatch readme-typo --backend print --ask-file "$c/empty.txt" --grounds-file "$c/grounds.txt" --repo-root "$c/primary"
[ "$RC" -eq 2 ] || fail "an empty ask file must be refused (rc $RC)"
run dispatch readme-typo --backend print --ask-file "$c/ask.txt" --grounds-file "$(grounds "$(printf 'two\nlines')")" --repo-root "$c/primary"
[ "$RC" -eq 2 ] || fail "multi-line grounds must be refused (rc $RC)"
run dispatch readme-typo --backend print --ask-file "$c/ask.txt" --grounds-file "$(grounds "")" --repo-root "$c/primary"
[ "$RC" -eq 2 ] || fail "empty grounds must be refused: a route is never silent (rc $RC)"
run dispatch readme-typo --backend print --ask-file "$c/ask.txt" --repo-root "$c/primary"
[ "$RC" -eq 2 ] || fail "a dispatch without grounds must be refused (rc $RC)"
if gitc "$c/primary" for-each-ref --format='%(refname)' 'refs/heads/planwright/flight/' | grep -q .; then
  fail "a refused dispatch placed a flight branch"
fi
run bogus
[ "$RC" -eq 2 ] || fail "an unknown subcommand must be a usage error (rc $RC)"

# --- plugin-root pair with an installed plugin -------------------------------
new_case
inst="$c/claude/plugins/cache/mk/planwright/9.9.9"
mkdir -p "$inst/.claude-plugin"
printf '{"name":"planwright","version":"9.9.9"}\n' >"$inst/.claude-plugin/plugin.json"
dispatch_print
printf '%s\n' "$OUT" | grep -q "^root${TAB}worker${TAB}$inst${TAB}9.9.9$" \
  || fail "report must name the installed worker root and version (out: $OUT)"
tower_v=$(printf '%s\n' "$OUT" | awk -F"$TAB" '$1=="root" && $2=="tower" {print $4}')
if [ "$tower_v" = 9.9.9 ]; then
  [ "$(field "$OUT" root-skew)" = no ] || fail "equal versions must read no skew"
else
  [ "$(field "$OUT" root-skew)" = yes ] || fail "differing versions must read skew yes (tower $tower_v)"
fi

if [ "$fails" -gt 0 ]; then
  echo "test-flight-dispatch: $fails failure(s)" >&2
  exit 1
fi
echo "test-flight-dispatch: ok"
