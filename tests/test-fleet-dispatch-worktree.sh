#!/bin/bash
# Tests for the tmux-backend dispatch primitive that produces a worker worktree
# on the canonical D-36 branch `planwright/<spec>/task-<id>` deterministically at
# launch (fleet-hardening Task 10; D-7 amended 2026-07-20; REQ-B1.4, and
# REQ-C1.1 / REQ-C1.2 / REQ-E1.3 for the tower-guard interaction).
#
# Coverage (mapped to the Task-10 Done-when):
#   c1  (REQ-B1.4): the resulting branch matches the D-36 grammar
#       `planwright/<spec>/task-<id>`, created by the SINGLE scoped
#       `git worktree add -b` call with NO post-launch `git branch -m`; the
#       mangled `worktree-<suffix>` name is provably NOT the output.
#   c2  (REQ-B1.4 / D-9): `<base>` is the freshly-fetched `origin/main`, not the
#       stale local `main` — a diverged origin is picked up.
#   c3  (REQ-B1.4): a metacharacter-bearing token is REJECTED before
#       interpolation — no shell execution, no branch, no path escape (exit 2).
#   c4  (REQ-B1.4): a `..`-bearing token is REJECTED (no path traversal, exit 2).
#   c5  (REQ-B1.4 collision): a LIVE concurrent/repeat dispatch aborts as
#       already-in-flight via `git worktree add -b`'s atomic non-zero exit (exit
#       3), NOT a pre-check.
#   c6  (REQ-B1.4 orphan): a STALE orphan with commits and no live session is
#       GC-adopted (its work preserved) and the dispatch proceeds.
#   c7  (REQ-B1.4 orphan): a leftover EMPTY `<suffix>` dir is cleaned, not
#       silently reused, and the dispatch proceeds on the fresh base.
#   c8  (REQ-B1.4 orphan): a partial create (branch made, no worktree, no
#       commits, no session) is rolled back and recreated; the dispatch proceeds.
#   c9  (REQ-B1.4): the create exit-code GATES the attach — a non-zero create
#       (live collision / unresolvable base) prints NO attach plan.
#   c10 (REQ-B1.4): the client-switch mitigation is present in the constructed
#       attach (capture-and-restore), and `--tmux=classic` is used (not plain
#       `--tmux`), composed through the ghost-text pin wrapper.
#   c11 (REQ-C1.2): the tower deny floor denies the dangerous `git worktree`
#       forms (default-branch / detach / `--force`).
#   c12 (REQ-B1.4 exception scope): the dispatch primitive is the ONLY
#       worktree-CREATION (`git worktree add`) path in the bundle's shipped
#       scripts — the D-7 exception stays narrow.
#   c13 (REQ-E1.3): no model/API call in the branch-naming decision path — it is
#       deterministic string logic (same inputs -> same branch), and the create
#       path invokes no model/API binary for naming.
#   c14 (REQ-C1.1 defense-in-depth): the tower command-guard DEFERS (does not
#       allow) a raw `git worktree add`, so the deny floor (c11) is the blocker.
#
# The primitive's own `git worktree add` runs INSIDE this literal-path script
# (auto-approved wholesale by the worker/tower guard's `is_repo_script`), so its
# inner git call is never a classifier-exposed Bash string (c12 + c14 together).
#
# NOT covered here (the Done-when's `[manual]` arm): confirming on a REAL
# dispatch that `--tmux=classic` opens relay-targetable panes and the
# client-switch restore holds — that needs a live tmux + `claude` and is a
# manual confirmation, recorded in the PR body.
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-fleet-dispatch-worktree.sh
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

# Deterministic, signing-free git identity; never touch the machine's real git
# config or fleet state.
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_SYSTEM=/dev/null

here=$(cd "$(dirname "$0")" && pwd)
PRIM="$here/../scripts/fleet-dispatch-worktree.sh"
SETTINGS="$here/../config/tower-settings.json"
TOWER_HOOK="$here/../scripts/tower-command-guard.sh"
SCRIPTS_DIR="$here/../scripts"
TAB=$(printf '\t')

fails=0
fail() {
  echo "FAIL: $1" >&2
  fails=$((fails + 1))
}

[ -x "$PRIM" ] || {
  echo "FAIL: scripts/fleet-dispatch-worktree.sh missing or not executable" >&2
  exit 1
}

gitc() {
  _r=$1
  shift
  git -C "$_r" -c user.name=test -c user.email=test@example.invalid \
    -c commit.gpgsign=false -c init.defaultBranch=main "$@"
}

# Per-case state isolation: fresh fleet/marker/fetch state dirs so a case never
# touches the real machine's fleet home (whose lock would otherwise contend).
# Also disable the live-tmux liveness probe: the tmux session namespace is
# global and NOT sandboxed by the state dirs, so a developer/CI box that happens
# to hold a session named `task-10`/`task-7` would otherwise flip a stale-orphan
# case (c6/c7/c8) into a spurious already-in-flight. Cases that need liveness=true
# (c5/c9) force it deterministically via the fresh marker, not tmux.
iso_env() {
  _t=$1
  export PLANWRIGHT_FLEET_STATE_DIR="$_t/fleet"
  export PLANWRIGHT_ORCH_STATE_DIR="$_t/markers"
  export PLANWRIGHT_DISPATCH_FETCH_STATE_DIR="$_t/fstate"
  export PLANWRIGHT_DISPATCH_LIVENESS_SKIP_TMUX=1
}

# Seed a bare origin + a primary clone carrying a minimal spec bundle, with main
# pushed. Echoes nothing; the caller uses "$1/primary" and "$1/origin.git".
seed_repo() {
  _t=$1
  git -c init.defaultBranch=main init -q --bare "$_t/origin.git"
  git clone -q "$_t/origin.git" "$_t/primary" 2>/dev/null
  mkdir -p "$_t/primary/specs/demo"
  printf 'v1\n' >"$_t/primary/specs/demo/requirements.md"
  gitc "$_t/primary" add -A
  gitc "$_t/primary" commit -q -m "spec v1"
  gitc "$_t/primary" branch -M main
  gitc "$_t/primary" push -q origin main
}

# Pull a `dispatch<TAB><key><TAB><value>` field out of dry-run output.
dfield() {
  printf '%s\n' "$1" | awk -F"$TAB" -v k="$2" '$1=="dispatch" && $2==k {print $3; exit}'
}

run_prim() {
  # Sets OUT and RC; stdin from /dev/null (a dispatch must never block on stdin).
  OUT=$("$PRIM" "$@" </dev/null 2>/dev/null)
  RC=$?
}

# ---------------------------------------------------------------------------
# c1 — D-36 grammar, single `git worktree add -b`, no mangled name, no rename.
# ---------------------------------------------------------------------------
c1() {
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/dw.c1.XXXXXX")
  trap 'rm -rf "$tmp"' RETURN
  iso_env "$tmp"
  seed_repo "$tmp"

  run_prim dispatch demo 10 --repo-root "$tmp/primary" --attach-dry-run
  [ "$RC" -eq 0 ] || {
    fail "c1: dispatch exited $RC (expected 0)"
    return
  }
  [ "$(dfield "$OUT" branch)" = "planwright/demo/task-10" ] \
    || fail "c1: branch '$(dfield "$OUT" branch)' != planwright/demo/task-10"

  # The branch really exists in the repo, on the exact D-36 name.
  gitc "$tmp/primary" show-ref --verify --quiet refs/heads/planwright/demo/task-10 \
    || fail "c1: refs/heads/planwright/demo/task-10 was not created"
  # The mangled `worktree-<suffix>` name a native `claude --worktree` would
  # produce is provably NOT the output — no such branch exists.
  if gitc "$tmp/primary" for-each-ref --format='%(refname:short)' refs/heads/ \
    | grep -q '^worktree-'; then
    fail "c1: a mangled worktree-<suffix> branch exists (rename footgun not avoided)"
  fi
  # The worktree is placed at .claude/worktrees/task-10 (branch's final segment).
  [ -d "$tmp/primary/.claude/worktrees/task-10" ] \
    || fail "c1: worktree dir .claude/worktrees/task-10 not created"
  # The primitive contains NO `git branch -m` rename (the Done-when's zero-rename
  # clause) — the D-36 name is a create-time output, never a post-launch rename.
  # Strip comments first (the header comment names the rename it AVOIDS).
  if grep -v '^[[:space:]]*#' "$SCRIPTS_DIR/fleet-dispatch-worktree.sh" \
    | grep -Eq 'git( -C [^ ]+)? branch -m'; then
    fail "c1: the primitive contains a 'git branch -m' rename (zero-rename violated)"
  fi
}

# ---------------------------------------------------------------------------
# c2 — <base> is the freshly-fetched origin/main, not the stale local main.
# ---------------------------------------------------------------------------
c2() {
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/dw.c2.XXXXXX")
  trap 'rm -rf "$tmp"' RETURN
  iso_env "$tmp"
  seed_repo "$tmp"

  stale_local=$(gitc "$tmp/primary" rev-parse main)

  # A second worker advances origin/main; the primary's local main stays stale.
  git clone -q "$tmp/origin.git" "$tmp/dev2" 2>/dev/null
  printf 'v2\n' >"$tmp/dev2/specs/demo/requirements.md"
  gitc "$tmp/dev2" add -A
  gitc "$tmp/dev2" commit -q -m "spec v2 (advance origin/main)"
  gitc "$tmp/dev2" branch -M main
  gitc "$tmp/dev2" push -q origin main
  fresh_origin=$(gitc "$tmp/dev2" rev-parse main)
  [ "$stale_local" != "$fresh_origin" ] || {
    fail "c2: fixture broken — stale and fresh are equal"
    return
  }

  run_prim dispatch demo 10 --repo-root "$tmp/primary" --attach-dry-run
  [ "$RC" -eq 0 ] || {
    fail "c2: dispatch exited $RC"
    return
  }
  got_base=$(dfield "$OUT" base)
  [ "$got_base" = "$fresh_origin" ] \
    || fail "c2: base '$got_base' != freshly-fetched origin/main '$fresh_origin'"
  [ "$got_base" != "$stale_local" ] \
    || fail "c2: base is the STALE local main, not origin/main"
  # The created branch actually points at the fresh origin/main commit.
  branch_tip=$(gitc "$tmp/primary" rev-parse planwright/demo/task-10)
  [ "$branch_tip" = "$fresh_origin" ] \
    || fail "c2: branch tip '$branch_tip' is not the fresh origin/main"
  # And local main was NOT advanced (read-only-local-main, D-9).
  [ "$(gitc "$tmp/primary" rev-parse main)" = "$stale_local" ] \
    || fail "c2: local main advanced (read-only invariant broken)"
}

# ---------------------------------------------------------------------------
# c3 — a metacharacter token is rejected before interpolation (no shell exec).
# ---------------------------------------------------------------------------
c3() {
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/dw.c3.XXXXXX")
  trap 'rm -rf "$tmp"' RETURN
  iso_env "$tmp"
  seed_repo "$tmp"

  # A spec value that, if ever reached a shell, would create the marker file.
  run_prim dispatch "demo;touch $tmp/EVIL" 10 --repo-root "$tmp/primary" --attach-dry-run
  [ "$RC" -eq 2 ] || fail "c3: metacharacter spec accepted (exit $RC, expected 2)"
  [ ! -e "$tmp/EVIL" ] || fail "c3: shell metacharacter EXECUTED (marker created)"
  # No worktree / no branch leaked.
  gitc "$tmp/primary" for-each-ref --format='%(refname:short)' refs/heads/ \
    | grep -q '^planwright/' \
    && fail "c3: a branch was created from a rejected token"

  # A `$(...)` command-substitution shape is likewise rejected. The literal
  # `$(...)` is intentional test INPUT (it must NOT expand), so single quotes.
  # shellcheck disable=SC2016
  run_prim dispatch 'demo' '1$(touch '"$tmp"'/EVIL2)' --repo-root "$tmp/primary" --attach-dry-run
  [ "$RC" -eq 2 ] || fail "c3: command-substitution id accepted (exit $RC)"
  [ ! -e "$tmp/EVIL2" ] || fail "c3: command substitution EXECUTED"
}

# ---------------------------------------------------------------------------
# c4 — a `..` path-traversal token is rejected (no path escape).
# ---------------------------------------------------------------------------
c4() {
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/dw.c4.XXXXXX")
  trap 'rm -rf "$tmp"' RETURN
  iso_env "$tmp"
  seed_repo "$tmp"

  run_prim dispatch demo '../../etc' --repo-root "$tmp/primary" --attach-dry-run
  [ "$RC" -eq 2 ] || fail "c4: '..'-bearing id accepted (exit $RC, expected 2)"

  run_prim dispatch '../evil' 10 --repo-root "$tmp/primary" --attach-dry-run
  [ "$RC" -eq 2 ] || fail "c4: '..'-bearing spec accepted (exit $RC, expected 2)"
  # No worktree escaped the .claude/worktrees tree.
  [ ! -e "$tmp/primary/../evil" ] || fail "c4: path traversal materialized a dir"
}

# ---------------------------------------------------------------------------
# c5 — a LIVE repeat dispatch aborts as already-in-flight (exit 3), via git's
# atomic non-zero exit, not a pre-check.
# ---------------------------------------------------------------------------
c5() {
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/dw.c5.XXXXXX")
  trap 'rm -rf "$tmp"' RETURN
  iso_env "$tmp"
  seed_repo "$tmp"

  # First dispatch creates the worktree + branch + a fresh dispatch marker (the
  # liveness signal). --attach-dry-run avoids launching claude.
  run_prim dispatch demo 10 --repo-root "$tmp/primary" --attach-dry-run
  [ "$RC" -eq 0 ] || {
    fail "c5: first dispatch exited $RC"
    return
  }
  [ -f "$tmp/markers/10" ] || fail "c5: dispatch marker not written by first dispatch"

  # Second dispatch collides. The marker is fresh -> LIVE -> already-in-flight.
  run_prim dispatch demo 10 --repo-root "$tmp/primary" --attach-dry-run
  [ "$RC" -eq 3 ] || fail "c5: live collision did not abort as already-in-flight (exit $RC, expected 3)"
}

# ---------------------------------------------------------------------------
# c6 — a STALE orphan branch with commits and no live session is GC-adopted
# (work preserved) and the dispatch proceeds.
# ---------------------------------------------------------------------------
c6() {
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/dw.c6.XXXXXX")
  trap 'rm -rf "$tmp"' RETURN
  iso_env "$tmp"
  seed_repo "$tmp"

  base=$(gitc "$tmp/primary" rev-parse main)
  # A prior dispatch that died: branch + worktree exist and carry real work, but
  # there is NO live session and NO dispatch marker (an orphan).
  gitc "$tmp/primary" worktree add -q -b planwright/demo/task-10 \
    "$tmp/primary/.claude/worktrees/task-10" "$base"
  printf 'orphan work\n' >"$tmp/primary/.claude/worktrees/task-10/work.txt"
  gitc "$tmp/primary/.claude/worktrees/task-10" add -A
  gitc "$tmp/primary/.claude/worktrees/task-10" commit -q -m "orphaned work"
  work_tip=$(gitc "$tmp/primary" rev-parse planwright/demo/task-10)

  run_prim dispatch demo 10 --repo-root "$tmp/primary" --attach-dry-run
  [ "$RC" -eq 0 ] || {
    fail "c6: stale-orphan dispatch did not proceed (exit $RC, expected 0 — a wedge)"
    return
  }
  # The branch still exists and still carries the orphan's work (adopted, not
  # discarded).
  now_tip=$(gitc "$tmp/primary" rev-parse planwright/demo/task-10)
  [ "$now_tip" = "$work_tip" ] \
    || fail "c6: adopted branch lost its work ($work_tip -> $now_tip)"
  [ -d "$tmp/primary/.claude/worktrees/task-10" ] \
    || fail "c6: no worktree placed after adoption"
}

# ---------------------------------------------------------------------------
# c7 — a leftover EMPTY <suffix> dir is cleaned, not silently reused; proceeds.
# ---------------------------------------------------------------------------
c7() {
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/dw.c7.XXXXXX")
  trap 'rm -rf "$tmp"' RETURN
  iso_env "$tmp"
  seed_repo "$tmp"

  fresh_origin=$(gitc "$tmp/primary" rev-parse origin/main)
  # A leftover empty dir where the worktree would go (git worktree add would
  # otherwise SILENTLY create into it).
  mkdir -p "$tmp/primary/.claude/worktrees/task-10"

  run_prim dispatch demo 10 --repo-root "$tmp/primary" --attach-dry-run
  [ "$RC" -eq 0 ] || {
    fail "c7: leftover-empty-dir dispatch did not proceed (exit $RC)"
    return
  }
  gitc "$tmp/primary" show-ref --verify --quiet refs/heads/planwright/demo/task-10 \
    || fail "c7: branch not created over the cleaned empty dir"
  # The freshly created branch is based on origin/main (not a silent reuse).
  [ "$(gitc "$tmp/primary" rev-parse planwright/demo/task-10)" = "$fresh_origin" ] \
    || fail "c7: created branch not based on the fresh origin/main"
}

# ---------------------------------------------------------------------------
# c8 — a partial create (branch made, no worktree, no commits, no session) is
# rolled back and recreated; the dispatch proceeds.
# ---------------------------------------------------------------------------
c8() {
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/dw.c8.XXXXXX")
  trap 'rm -rf "$tmp"' RETURN
  iso_env "$tmp"
  seed_repo "$tmp"

  # A bare partial branch made from a STALE base: origin/main is then advanced,
  # so a real rollback+recreate must land the branch on the FRESH origin/main,
  # not silently keep the stale partial.
  stale=$(gitc "$tmp/primary" rev-parse main)
  gitc "$tmp/primary" branch planwright/demo/task-10 "$stale"
  git clone -q "$tmp/origin.git" "$tmp/dev2" 2>/dev/null
  printf 'v2\n' >"$tmp/dev2/specs/demo/requirements.md"
  gitc "$tmp/dev2" add -A
  gitc "$tmp/dev2" commit -q -m "advance origin/main"
  gitc "$tmp/dev2" branch -M main
  gitc "$tmp/dev2" push -q origin main
  fresh=$(gitc "$tmp/dev2" rev-parse main)
  [ "$stale" != "$fresh" ] || {
    fail "c8: fixture broken — stale==fresh"
    return
  }

  run_prim dispatch demo 10 --repo-root "$tmp/primary" --attach-dry-run
  [ "$RC" -eq 0 ] || {
    fail "c8: partial-create dispatch did not proceed (exit $RC — a wedge)"
    return
  }
  gitc "$tmp/primary" show-ref --verify --quiet refs/heads/planwright/demo/task-10 \
    || fail "c8: branch missing after rollback+recreate"
  [ -d "$tmp/primary/.claude/worktrees/task-10" ] \
    || fail "c8: worktree not placed after rollback+recreate"
  # The recreated (rolled-back) branch is based on the FRESH origin/main.
  [ "$(gitc "$tmp/primary" rev-parse planwright/demo/task-10)" = "$fresh" ] \
    || fail "c8: recreated branch not rebased onto the fresh origin/main"
}

# ---------------------------------------------------------------------------
# c9 — the create exit-code GATES the attach: a non-zero create prints NO attach
# plan.
# ---------------------------------------------------------------------------
c9() {
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/dw.c9.XXXXXX")
  trap 'rm -rf "$tmp"' RETURN
  iso_env "$tmp"
  seed_repo "$tmp"

  # Live collision (as in c5) -> exit 3 -> no attach.
  run_prim dispatch demo 10 --repo-root "$tmp/primary" --attach-dry-run
  [ "$RC" -eq 0 ] || {
    fail "c9: setup dispatch exited $RC"
    return
  }
  run_prim dispatch demo 10 --repo-root "$tmp/primary" --attach-dry-run
  [ "$RC" -ne 0 ] || fail "c9: expected non-zero create on collision"
  printf '%s\n' "$OUT" | grep -q 'attach-plan' \
    && fail "c9: an attach plan was printed despite a non-zero create (attach not gated)"

  # Unresolvable fresh base (no remote reachable AND no local main) -> non-zero,
  # no attach. Use a repo with a spec bundle (so it passes the spec-dir gate) but
  # no commits and no remote: origin/main and local main are both unresolvable.
  bare=$(mktemp -d "${TMPDIR:-/tmp}/dw.c9b.XXXXXX")
  git -c init.defaultBranch=main init -q "$bare/repo"
  mkdir -p "$bare/repo/specs/demo"
  run_prim dispatch demo 10 --repo-root "$bare/repo" --attach-dry-run
  [ "$RC" -ne 0 ] || fail "c9: unresolvable-base dispatch unexpectedly succeeded"
  printf '%s\n' "$OUT" | grep -q 'attach-plan' \
    && fail "c9: attach plan printed despite unresolvable base"
  rm -rf "$bare"
}

# ---------------------------------------------------------------------------
# c10 — client-switch mitigation present (capture-and-restore) and --tmux=classic
# used (not plain --tmux), composed through the ghost-text pin wrapper.
# ---------------------------------------------------------------------------
c10() {
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/dw.c10.XXXXXX")
  trap 'rm -rf "$tmp"' RETURN
  iso_env "$tmp"
  seed_repo "$tmp"

  run_prim dispatch demo 10 --repo-root "$tmp/primary" --attach-dry-run
  [ "$RC" -eq 0 ] || {
    fail "c10: dispatch exited $RC"
    return
  }
  plan=$(printf '%s\n' "$OUT" | grep '^attach-plan')
  # Capture the prior client session before the launch.
  if ! { printf '%s\n' "$plan" | grep -q 'capture' \
    && printf '%s\n' "$plan" | grep -q 'client_session'; }; then
    fail "c10: no client-session CAPTURE step in the attach plan"
  fi
  # Restore the client to the prior session after the launch.
  if ! { printf '%s\n' "$plan" | grep -q 'restore' \
    && printf '%s\n' "$plan" | grep -q 'switch-client'; }; then
    fail "c10: no client RESTORE (switch-client) step in the attach plan"
  fi
  # --tmux=classic is mandatory; plain `--tmux` (space-terminated) is a bug.
  launch=$(printf '%s\n' "$plan" | grep 'launch')
  printf '%s\n' "$launch" | grep -q -- '--tmux=classic' \
    || fail "c10: launch does not use --tmux=classic"
  printf '%s\n' "$launch" | grep -Eq -- '--tmux($|[^=])' \
    && fail "c10: launch uses plain --tmux (non-classic — non-relay-targetable)"
  # The pin wrapper (fleet-dispatch-env.sh) is the launch verb, so the ghost-text
  # pin is applied structurally.
  printf '%s\n' "$launch" | grep -q 'fleet-dispatch-env.sh' \
    || fail "c10: launch not routed through the fleet-dispatch-env.sh pin wrapper"
}

# ---------------------------------------------------------------------------
# c11 — the tower deny floor denies the dangerous git worktree forms.
# ---------------------------------------------------------------------------
c11() {
  [ -f "$SETTINGS" ] || {
    fail "c11: config/tower-settings.json missing"
    return
  }
  command -v jq >/dev/null 2>&1 || {
    echo "ok c11: skipped (jq absent)"
    return
  }
  # Read the deny array with jq (a repo hard-dependency, as c14 and the rest of
  # the suite use), not python3 which the suite does not otherwise require.
  deny=$(jq -r '.permissions.deny[]' "$SETTINGS" 2>/dev/null)
  [ -n "$deny" ] || {
    fail "c11: could not read tower-settings deny array"
    return
  }
  # --force (add), --detach (add), default-branch (add ... main) must all be denied.
  printf '%s\n' "$deny" | grep -q 'git worktree add --force' \
    || fail "c11: deny floor missing 'git worktree add --force'"
  printf '%s\n' "$deny" | grep -q 'git worktree add --detach' \
    || fail "c11: deny floor missing 'git worktree add --detach'"
  printf '%s\n' "$deny" | grep -Eq 'git worktree add \* main' \
    || fail "c11: deny floor missing default-branch 'git worktree add * main'"
  printf '%s\n' "$deny" | grep -q 'git worktree remove --force' \
    || fail "c11: deny floor missing 'git worktree remove --force'"
}

# ---------------------------------------------------------------------------
# c12 — the dispatch primitive is the ONLY worktree-CREATION path in the bundle.
# ---------------------------------------------------------------------------
c12() {
  # Any shipped SHELL file that shells out to `git worktree add` (creation) other
  # than the primitive violates the narrow D-7 exception. `remove`/`list`/`prune`
  # (non-creation) are out of scope. Scan every .sh under the bundle (scripts/ +
  # hooks/), so a creation shell-out hiding in a hook script is caught too; JSON
  # deny rules and Markdown prose (config/, skills/) don't shell out and are not
  # scanned (a "git worktree add" substring there is a deny glob or an example).
  bundle_root=$(cd "$here/.." && pwd)
  offenders=$(find "$bundle_root/scripts" "$bundle_root/hooks" -name '*.sh' \
    -exec grep -lE '^[^#]*git( -C [^ ]+)? worktree add' {} + 2>/dev/null \
    | grep -v '/fleet-dispatch-worktree.sh$' || true)
  [ -z "$offenders" ] \
    || fail "c12: extra git-worktree-add creation path(s) in the bundle: $offenders"
  # And the primitive DOES contain the sanctioned creation call.
  grep -Eq '^[^#]*git( -C [^ ]+)? worktree add -b' "$SCRIPTS_DIR/fleet-dispatch-worktree.sh" \
    || fail "c12: the primitive does not contain the sanctioned 'git worktree add -b' call"
}

# ---------------------------------------------------------------------------
# c13 — no model/API call in the branch-naming decision path (REQ-E1.3).
# ---------------------------------------------------------------------------
c13() {
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/dw.c13.XXXXXX")
  trap 'rm -rf "$tmp"' RETURN
  iso_env "$tmp"
  seed_repo "$tmp"

  # Deterministic naming: two dispatches of the same (spec,id) derive the exact
  # same D-36 branch — pure string logic, no stochastic/model step. (Run in
  # separate clones so the second is not a collision.) Assert each dispatch
  # SUCCEEDED before reading its branch, so a real dispatch failure surfaces as
  # itself, not a misleading "not deterministic" with empty values.
  run_prim dispatch demo 7 --repo-root "$tmp/primary" --attach-dry-run
  [ "$RC" -eq 0 ] || {
    fail "c13: first dispatch exited $RC (expected 0)"
    return
  }
  b1=$(dfield "$OUT" branch)
  git clone -q "$tmp/origin.git" "$tmp/primary2" 2>/dev/null
  run_prim dispatch demo 7 --repo-root "$tmp/primary2" --attach-dry-run
  [ "$RC" -eq 0 ] || {
    fail "c13: second dispatch exited $RC (expected 0)"
    return
  }
  b2=$(dfield "$OUT" branch)
  [ "$b1" = "planwright/demo/task-7" ] && [ "$b2" = "planwright/demo/task-7" ] \
    || fail "c13: branch naming is not deterministic ('$b1' vs '$b2')"

  # Static: the naming/create path invokes no model/API binary. The one `claude`
  # token is the WORKER launch (the attach, not the naming decision), and it is
  # routed through the pin wrapper — assert there is no anthropic/curl/API call
  # anywhere in the primitive.
  grep -Eqi 'anthropic|api\.anthropic|curl .*(anthropic|api)|/v1/messages' \
    "$SCRIPTS_DIR/fleet-dispatch-worktree.sh" \
    && fail "c13: an API/model call appears in the primitive"
  # And `claude` appears only as the launched worker verb inside do_attach, never
  # in the create / reconcile / naming logic. Strip comments AND the do_attach
  # body, then assert no `claude` token remains in the naming/create path.
  naming=$(sed '/^do_attach()/,/^}/d' "$SCRIPTS_DIR/fleet-dispatch-worktree.sh" \
    | grep -v '^[[:space:]]*#')
  # `.claude/worktrees` (a path) is not the `claude` binary — exclude it.
  if printf '%s\n' "$naming" | grep 'claude' | grep -qv '\.claude'; then
    fail "c13: a 'claude' invocation appears in the naming/create path (outside do_attach)"
  fi
  return 0
}

# ---------------------------------------------------------------------------
# c14 — the tower command-guard DEFERS (does not allow) a raw git worktree add,
# so the deny floor is the blocker (defense-in-depth). Needs jq.
# ---------------------------------------------------------------------------
c14() {
  command -v jq >/dev/null 2>&1 || {
    echo "ok c14: skipped (jq absent)"
    return 0
  }
  [ -x "$TOWER_HOOK" ] || {
    fail "c14: tower-command-guard.sh missing"
    return
  }
  sandbox=$(mktemp -d "${TMPDIR:-/tmp}/dw.c14.XXXXXX")
  trap 'rm -rf "$sandbox"' RETURN
  plugin_root=$(cd "$here/.." && pwd)
  guard() {
    payload=$(jq -n --arg c "$1" --arg w "$sandbox" \
      '{tool_name:"Bash", tool_input:{command:$c}, cwd:$w}')
    printf '%s' "$payload" | CLAUDE_PLUGIN_ROOT="$plugin_root" /bin/bash "$TOWER_HOOK" 2>/dev/null
  }
  guard_allows() {
    printf '%s' "$1" | grep -Eq '"permissionDecision"[[:space:]]*:[[:space:]]*"allow"'
  }
  # Positive control: a known-safe read-only command IS allowed, proving the
  # guard actually runs (so the negative assertions below are meaningful, not
  # vacuously satisfied by a broken/silent guard).
  guard_allows "$(guard 'git status')" \
    || fail "c14: positive control failed — the tower guard did not allow 'git status' (guard not running?)"
  # Negative: raw dangerous git worktree forms are NOT allowed (they DEFER, and
  # the deny floor c11 blocks them).
  for cmd in \
    'git worktree add -b planwright/demo/task-10 .claude/worktrees/task-10 origin/main' \
    'git worktree add --force /tmp/x main' \
    'git worktree add --detach /tmp/y'; do
    if guard_allows "$(guard "$cmd")"; then
      fail "c14: tower guard ALLOWED a raw git worktree add: $cmd"
    fi
  done
}

# ---------------------------------------------------------------------------
# c15 — a dotted-decimal id (3.5) is a valid D-36 token and yields task-3.5.
# ---------------------------------------------------------------------------
c15() {
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/dw.c15.XXXXXX")
  trap 'rm -rf "$tmp"' RETURN
  iso_env "$tmp"
  seed_repo "$tmp"

  run_prim dispatch demo 3.5 --repo-root "$tmp/primary" --attach-dry-run
  [ "$RC" -eq 0 ] || {
    fail "c15: dotted-id dispatch exited $RC (expected 0)"
    return
  }
  [ "$(dfield "$OUT" branch)" = "planwright/demo/task-3.5" ] \
    || fail "c15: dotted-id branch '$(dfield "$OUT" branch)' != planwright/demo/task-3.5"
  gitc "$tmp/primary" show-ref --verify --quiet refs/heads/planwright/demo/task-3.5 \
    || fail "c15: refs/heads/planwright/demo/task-3.5 not created"
  [ -d "$tmp/primary/.claude/worktrees/task-3.5" ] \
    || fail "c15: worktree dir task-3.5 not created"
}

# ---------------------------------------------------------------------------
# c16 — the extra launch-arg allowlist refuses escalation flags (SEC), a
# bundle-id is rejected, and a benign --model flows through.
# ---------------------------------------------------------------------------
c16() {
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/dw.c16.XXXXXX")
  trap 'rm -rf "$tmp"' RETURN
  iso_env "$tmp"
  seed_repo "$tmp"

  # An escalation flag after `--` is REFUSED (exit 2) and never reaches claude —
  # the tower approves this script wholesale, so the per-flag pin lives here.
  for bad in --dangerously-skip-permissions "--permission-mode" "--settings" "--mcp-config" "--add-dir"; do
    run_prim dispatch demo 20 --repo-root "$tmp/primary" --attach-dry-run -- "$bad" x
    [ "$RC" -eq 2 ] || fail "c16: escalation flag '$bad' not refused (exit $RC, expected 2)"
    printf '%s\n' "$OUT" | grep -q 'attach-plan' \
      && fail "c16: an attach plan was printed for a refused escalation flag '$bad'"
  done

  # A bundle id ("5 6") is rejected by the id grammar (space) with exit 2.
  run_prim dispatch demo "5 6" --repo-root "$tmp/primary" --attach-dry-run
  [ "$RC" -eq 2 ] || fail "c16: bundle id '5 6' accepted (exit $RC, expected 2)"

  # A flag-shaped value is refused in BOTH the space-separated and the attached
  # (`--model=-x`) forms (symmetric validation).
  run_prim dispatch demo 22 --repo-root "$tmp/primary" --attach-dry-run -- --model -opus
  [ "$RC" -eq 2 ] || fail "c16: '--model -opus' (flag-shaped value) not refused (exit $RC)"
  run_prim dispatch demo 23 --repo-root "$tmp/primary" --attach-dry-run -- --model=-opus
  [ "$RC" -eq 2 ] || fail "c16: '--model=-opus' (attached flag-shaped value) not refused (exit $RC)"
  # An empty attached value (`--model=`) is refused, matching the space form.
  run_prim dispatch demo 24 --repo-root "$tmp/primary" --attach-dry-run -- --model=
  [ "$RC" -eq 2 ] || fail "c16: empty '--model=' not refused (exit $RC)"

  # A benign --model VALUE is accepted and flows into the launch.
  run_prim dispatch demo 21 --repo-root "$tmp/primary" --attach-dry-run -- --model opus
  [ "$RC" -eq 0 ] || {
    fail "c16: benign --model launch refused (exit $RC)"
    return
  }
  printf '%s\n' "$OUT" | grep 'attach-plan' | grep 'launch' | grep -q 'opus' \
    || fail "c16: --model opus did not flow into the launch plan"
}

# ---------------------------------------------------------------------------
# c17 — a symlinked .claude/worktrees (or .claude) is refused (path-escape
# guard): git worktree add / the reconcile rm -rf must never follow it outside
# the repo root.
# ---------------------------------------------------------------------------
c17() {
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/dw.c17.XXXXXX")
  trap 'rm -rf "$tmp"' RETURN
  iso_env "$tmp"
  seed_repo "$tmp"

  # .claude/worktrees -> an external dir outside the repo.
  mkdir -p "$tmp/EXTERNAL" "$tmp/primary/.claude"
  ln -s "$tmp/EXTERNAL" "$tmp/primary/.claude/worktrees"

  run_prim dispatch demo 10 --repo-root "$tmp/primary" --attach-dry-run
  [ "$RC" -ne 0 ] || fail "c17: symlinked .claude/worktrees was NOT refused (exit 0 — path escape)"
  [ -z "$(ls -A "$tmp/EXTERNAL" 2>/dev/null)" ] \
    || fail "c17: a worktree escaped into the external symlink target"
  printf '%s\n' "$OUT" | grep -q 'attach-plan' \
    && fail "c17: an attach plan was printed despite the refused path-escape"

  # A symlinked .claude itself is also refused.
  rm -rf "$tmp/primary/.claude"
  mkdir -p "$tmp/EXTERNAL2"
  ln -s "$tmp/EXTERNAL2" "$tmp/primary/.claude"
  run_prim dispatch demo 11 --repo-root "$tmp/primary" --attach-dry-run
  [ "$RC" -ne 0 ] || fail "c17: symlinked .claude was NOT refused"
  [ -z "$(ls -A "$tmp/EXTERNAL2" 2>/dev/null)" ] \
    || fail "c17: a worktree escaped into the .claude symlink target"
}

# ---------------------------------------------------------------------------
# c18 — a standalone git repo (`.git` is a DIRECTORY) left under the worktree
# path is treated as foreign data and refused, never rm -rf'd (the remnant check
# requires a gitlink FILE, not any `.git`).
# ---------------------------------------------------------------------------
c18() {
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/dw.c18.XXXXXX")
  trap 'rm -rf "$tmp"' RETURN
  iso_env "$tmp"
  seed_repo "$tmp"

  # A non-empty, unregistered dir at the worktree path that is a STANDALONE repo
  # (its `.git` is a directory), not a worktree remnant (gitlink file). No branch.
  wt="$tmp/primary/.claude/worktrees/task-30"
  mkdir -p "$wt"
  git -c init.defaultBranch=main init -q "$wt"
  printf 'precious\n' >"$wt/keep.txt"
  [ -d "$wt/.git" ] || {
    fail "c18: fixture broken — .git is not a directory"
    return
  }

  run_prim dispatch demo 30 --repo-root "$tmp/primary" --attach-dry-run
  [ "$RC" -eq 5 ] || fail "c18: standalone repo under the path not refused (exit $RC, expected 5)"
  [ -f "$wt/keep.txt" ] && [ -d "$wt/.git" ] \
    || fail "c18: the standalone repo was destroyed (data loss)"
}

# ---------------------------------------------------------------------------
# c19 — --no-attach: the create-only arm (execution-backends Task 3). A
# backend that launches its own worker into the created worktree (the
# headless-oneshot rung) needs the full create machinery — grammar, fetch,
# collision reconcile, marker — with NO tmux attach and NO attach plan. The
# dispatch record lines still print, so the caller learns the worktree path.
# ---------------------------------------------------------------------------
c19() {
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/dw.c19.XXXXXX")
  trap 'rm -rf "$tmp"' RETURN
  iso_env "$tmp"
  seed_repo "$tmp"

  run_prim dispatch demo 40 --repo-root "$tmp/primary" --no-attach
  [ "$RC" -eq 0 ] || {
    fail "c19: dispatch --no-attach exited $RC (expected 0)"
    return
  }
  [ "$(dfield "$OUT" branch)" = "planwright/demo/task-40" ] \
    || fail "c19: branch '$(dfield "$OUT" branch)' != planwright/demo/task-40"
  # The primitive reports PHYSICAL paths (pwd -P); compare in kind.
  _phys=$(cd "$tmp/primary" && pwd -P)
  [ "$(dfield "$OUT" worktree)" = "$_phys/.claude/worktrees/task-40" ] \
    || fail "c19: worktree line missing or wrong: '$(dfield "$OUT" worktree)'"
  [ -d "$tmp/primary/.claude/worktrees/task-40" ] \
    || fail "c19: --no-attach did not create the worktree"
  gitc "$tmp/primary" show-ref --verify --quiet refs/heads/planwright/demo/task-40 \
    || fail "c19: --no-attach did not create the D-36 branch"
  # No attach plan and no launch: the output carries no attach/exec lines.
  if printf '%s\n' "$OUT" | grep -qv '^dispatch	'; then
    fail "c19: --no-attach printed non-dispatch-record output (an attach plan?): $OUT"
  fi
}

for c in c1 c2 c3 c4 c5 c6 c7 c8 c9 c10 c11 c12 c13 c14 c15 c16 c17 c18 c19; do
  _before=$fails
  "$c"
  [ "$fails" -eq "$_before" ] && echo "ok $c" || true
done

if [ "$fails" -ne 0 ]; then
  echo "FAILED: $fails assertion(s)" >&2
  exit 1
fi
echo "PASS: all fleet-dispatch-worktree cases"
