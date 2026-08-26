#!/bin/bash
# Tests for the venture hygiene scaffold (inception Task 2; REQ-A1.9, REQ-G1.1,
# REQ-G1.5 · D-9, D-12).
#
# The scaffold is a tested helper that EMITS the guard files, rather than a set
# of static copies checked into the plugin — so the emitted content is covered
# by assertions and the rung scaling is a property of one code path.
#
# Two layers of assertions:
#   1. What lands, per rung, and whether re-running is safe.
#   2. What the emitted pre-commit hook actually does in a real repo: block on a
#      staged secret, regenerate and stage the export, and — the REQ-A1.9 clause
#      that matters most — warn WITHOUT blocking when the render fails, so a
#      wrapped-mode commit is never dead-ended by a broken export.
#
# Plain bash 3.2, inline asserts (sibling convention).
set -u
unset CDPATH
LC_ALL=C
export LC_ALL

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCAFFOLD="$REPO_ROOT/scripts/inception-scaffold.sh"

# shellcheck source=tests/lib/inception-fixture.sh
. "$REPO_ROOT/tests/lib/inception-fixture.sh"

failures=0
assert_eq() {
  if [ "$2" = "$3" ]; then
    echo "ok: $1"
  else
    echo "FAIL: $1 (expected '$2', got '$3')" >&2
    failures=$((failures + 1))
  fi
}
assert_contains() {
  case "$3" in
    *"$2"*) echo "ok: $1" ;;
    *)
      echo "FAIL: $1 (expected to find '$2' in output)" >&2
      failures=$((failures + 1))
      ;;
  esac
}
assert_not_contains() {
  case "$3" in
    *"$2"*)
      echo "FAIL: $1 (did not expect '$2' in output)" >&2
      failures=$((failures + 1))
      ;;
    *) echo "ok: $1" ;;
  esac
}
assert_file() {
  if [ -f "$2" ]; then
    echo "ok: $1"
  else
    echo "FAIL: $1 (no file at $2)" >&2
    failures=$((failures + 1))
  fi
}
assert_no_file() {
  if [ -e "$2" ]; then
    echo "FAIL: $1 (unexpected $2)" >&2
    failures=$((failures + 1))
  else
    echo "ok: $1"
  fi
}

if [ ! -x "$SCAFFOLD" ]; then
  echo "FAIL: scaffold missing or not executable at $SCAFFOLD" >&2
  exit 1
fi

tmp="$(cd "$(mktemp -d)" && pwd -P)" || exit 1
trap 'rm -rf "$tmp"' EXIT

# ---------------------------------------------------------------------------
# 1. The local rung: guards that need no remote, and nothing that does.
# ---------------------------------------------------------------------------
v="$tmp/local"
mkdir -p "$v"
out="$("$SCAFFOLD" --rung local "$v" 2>&1)"
rc=$?
assert_eq "local rung: exit 0" "0" "$rc"
assert_file "local rung: .gitignore" "$v/.gitignore"
assert_file "local rung: pre-commit hook" "$v/githooks/pre-commit"
assert_file "local rung: wiring notes" "$v/hygiene-wiring.md"
assert_no_file "local rung: no CI workflow" "$v/.github"
assert_contains "local rung: reports what it wrote" "wrote githooks/pre-commit" "$out"

if [ -x "$v/githooks/pre-commit" ]; then
  echo "ok: local rung: the hook is executable"
else
  echo "FAIL: local rung: the hook is not executable" >&2
  failures=$((failures + 1))
fi

ignore="$(cat "$v/.gitignore")"
assert_contains ".gitignore: machine-local env file" ".planwright-local.sh" "$ignore"
assert_contains ".gitignore: editor and OS droppings" ".DS_Store" "$ignore"

hook="$(cat "$v/githooks/pre-commit")"
assert_contains "hook: screens staged content for secrets" "inception-secret-screen.sh" "$hook"
assert_contains "hook: regenerates the export" "inception-render.sh" "$hook"
assert_contains "hook: stages the regenerated export" "git add" "$hook"
assert_contains "hook: runs the validator" "inception-validate.sh" "$hook"
assert_not_contains "hook: bakes in no machine-specific plugin path" "$REPO_ROOT" "$hook"

notes="$(cat "$v/hygiene-wiring.md")"
assert_contains "notes: name the rung" "local" "$notes"
assert_contains "notes: give the wiring command" "core.hooksPath githooks" "$notes"
assert_contains "notes: name the bypass" "--no-verify" "$notes"
# The hook stages the export it regenerates, which git's partial-commit path
# leaves showing as modified afterwards. Surprising, harmless, and worth saying
# once in the notes rather than letting every operator rediscover it.
assert_contains "notes: explain the post-partial-commit status" "git commit <path>" "$notes"

# ---------------------------------------------------------------------------
# 2. The remote rung adds the CI guard (REQ-A1.9, REQ-G1.5).
# ---------------------------------------------------------------------------
v="$tmp/remote"
mkdir -p "$v"
out="$("$SCAFFOLD" --rung remote "$v" 2>&1)"
rc=$?
assert_eq "remote rung: exit 0" "0" "$rc"
assert_file "remote rung: keeps the local guards" "$v/githooks/pre-commit"
assert_file "remote rung: adds the CI workflow" "$v/.github/workflows/venture-guard.yml"

wf="$(cat "$v/.github/workflows/venture-guard.yml")"
assert_contains "workflow: scans for secrets" "gitleaks" "$wf"
assert_contains "workflow: runs the bundle validator" "inception-validate.sh" "$wf"
assert_contains "workflow: guards stakeholder commits against the base" "--baseline" "$wf"
assert_contains "workflow: is read-only by default" "contents: read" "$wf"
assert_contains "workflow: runs on pull requests" "pull_request" "$wf"
assert_not_contains "workflow: no privileged fork trigger" "pull_request_target" "$wf"

notes="$(cat "$v/hygiene-wiring.md")"
assert_contains "notes: name the remote rung" "remote" "$notes"

if command -v yamllint >/dev/null 2>&1; then
  if yamllint -d relaxed "$v/.github/workflows/venture-guard.yml" >/dev/null 2>&1; then
    echo "ok: workflow: parses under yamllint"
  else
    echo "FAIL: workflow: yamllint rejected the emitted workflow" >&2
    failures=$((failures + 1))
  fi
else
  echo "ok: workflow: yamllint absent, parse check skipped"
fi

# ---------------------------------------------------------------------------
# 3. Re-running is safe; --force is the way to take a new version.
# ---------------------------------------------------------------------------
v="$tmp/again"
mkdir -p "$v"
"$SCAFFOLD" --rung local "$v" >/dev/null 2>&1
printf 'operator edit\n' >>"$v/githooks/pre-commit"
before="$(cat "$v/githooks/pre-commit")"
out="$("$SCAFFOLD" --rung local "$v" 2>&1)"
assert_eq "re-run: exit 0" "0" "$?"
assert_contains "re-run: reports the file as kept" "kept githooks/pre-commit" "$out"
assert_eq "re-run: leaves the operator edit alone" "$before" "$(cat "$v/githooks/pre-commit")"

out="$("$SCAFFOLD" --rung local --force "$v" 2>&1)"
assert_contains "--force: rewrites the file" "wrote githooks/pre-commit" "$out"
assert_not_contains "--force: the operator edit is gone" "operator edit" "$(cat "$v/githooks/pre-commit")"

# ---------------------------------------------------------------------------
# 4. Rung detection: a remote means remote, no remote means local.
# ---------------------------------------------------------------------------
v="$tmp/detect-local"
mkdir -p "$v"
(cd "$v" && git init -q .) >/dev/null 2>&1
out="$("$SCAFFOLD" "$v" 2>&1)"
assert_no_file "detect: no remote means the local rung" "$v/.github"
assert_contains "detect: says which rung it chose" "local" "$out"

v="$tmp/detect-remote"
mkdir -p "$v"
(cd "$v" && git init -q . && git remote add origin https://example.invalid/v.git) >/dev/null 2>&1
out="$("$SCAFFOLD" "$v" 2>&1)"
assert_file "detect: a remote means the remote rung" "$v/.github/workflows/venture-guard.yml"

# --wire is opt-in, and only the wire step touches git config.
v="$tmp/wire"
mkdir -p "$v"
(cd "$v" && git init -q .) >/dev/null 2>&1
"$SCAFFOLD" --rung local "$v" >/dev/null 2>&1
assert_eq "no --wire: hooksPath untouched" "" "$(cd "$v" && git config --local --get core.hooksPath || true)"
"$SCAFFOLD" --rung local --wire "$v" >/dev/null 2>&1
assert_eq "--wire: hooksPath set" "githooks" "$(cd "$v" && git config --local --get core.hooksPath || true)"

# ---------------------------------------------------------------------------
# 5. The emitted hook, exercised in a real venture repo.
# ---------------------------------------------------------------------------
venture="$tmp/venture"
inception_fixture_write "$venture" untracked || exit 1
(
  cd "$venture" || exit 1
  git init -q .
  git config user.email fixture@example.invalid
  git config user.name Fixture
  git config commit.gpgsign false
) >/dev/null 2>&1 || exit 1
"$SCAFFOLD" --rung local --wire "$venture" >/dev/null 2>&1

# The hook resolves planwright from the environment rather than a baked path.
export PLANWRIGHT_ROOT="$REPO_ROOT"
export PLANWRIGHT_INCEPTION_TODAY=2026-08-26
export PLANWRIGHT_SECRET_SCREEN_TOOL=none

out="$(cd "$venture" && git add -A && git commit -qm "open the venture" 2>&1)"
rc=$?
assert_eq "hook: a clean bundle commit succeeds" "0" "$rc"
assert_file "hook: the export was regenerated" "$venture/exports/venture.html"
tracked="$(cd "$venture" && git ls-files exports/venture.html)"
assert_eq "hook: the regenerated export was staged into the commit" "exports/venture.html" "$tracked"

# A bundle edit regenerates the export inside the same commit.
sed 's|^Median incident-handover time drops below ten minutes within one quarter of adoption.$|Median incident-handover time drops below eight minutes.|' \
  "$venture/brief.md" >"$venture/brief.new" && mv "$venture/brief.new" "$venture/brief.md"
out="$(cd "$venture" && git add brief.md && git commit -qm "sharpen the metric" 2>&1)"
rc=$?
assert_eq "hook: a bundle edit commits cleanly" "0" "$rc"
assert_contains "hook: the export followed the edit" "eight minutes" "$(cat "$venture/exports/venture.html")"
changed="$(cd "$venture" && git show --name-only --format= HEAD)"
assert_contains "hook: the export rode the same commit" "exports/venture.html" "$changed"

# A staged secret blocks the commit.
printf 'token: %s\n' "ghp_""0123456789abcdefghijklmnopqrstuvwxyz" >"$venture/spikes-note.md"
out="$(cd "$venture" && git add spikes-note.md && git commit -qm "notes" 2>&1)"
rc=$?
assert_eq "hook: a staged secret blocks the commit" "1" "$rc"
assert_not_contains "hook: the blocked secret is not echoed" "0123456789abcdefghijklmnopqrstuvwxyz" "$out"
(cd "$venture" && git reset -q HEAD spikes-note.md && rm -f spikes-note.md)

# The export is rendered from the WORKING TREE and staged after the secret
# screen has already run over the index, so content the screen never saw can
# ride into the commit inside the generated HTML. A credential sitting unstaged
# in a rendered field is the ordinary way to get there: the bundle is written
# incrementally and the hook is built to tolerate a half-staged one.
sed 's|^Median incident-handover time drops below eight minutes\.$|Median incident-handover time, tracked via aws_key = AKIA'"IOSFODNN7EXAMPLE"'|' \
  "$venture/brief.md" >"$venture/brief.new" && mv "$venture/brief.new" "$venture/brief.md"
printf '\nAn unrelated planning note.\n' >>"$venture/plan.md"
out="$(cd "$venture" && git add plan.md && git commit -qm "a plan note" 2>&1)"
rc=$?
assert_eq "hook: an unstaged secret reaching the export blocks the commit" "1" "$rc"
assert_not_contains "hook: the blocked secret is not echoed" "IOSFODNN7EXAMPLE" "$out"
committed="$(cd "$venture" && git show HEAD:exports/venture.html 2>/dev/null)"
assert_not_contains "hook: no commit carried the secret into the export" "IOSFODNN7EXAMPLE" "$committed"
(
  cd "$venture" || exit 1
  git reset -q HEAD . >/dev/null 2>&1
  git checkout -q -- brief.md plan.md exports/venture.html
) >/dev/null 2>&1

# REQ-A1.9: a render failure warns and lets the commit through. An unsupported
# format-version is the render failure that is easiest to produce on purpose.
for f in brief disciplines assumptions decisions plan; do
  sed 's|^\*\*Format-version:\*\* 1\.0$|**Format-version:** 8.0|' "$venture/$f.md" >"$venture/$f.new" \
    && mv "$venture/$f.new" "$venture/$f.md"
done
out="$(cd "$venture" && git add -A && git commit -qm "bundle from a newer plugin" 2>&1)"
rc=$?
assert_eq "hook: a render failure does not block the commit" "0" "$rc"
assert_contains "hook: it says the export was not regenerated" "export" "$out"

if [ "$failures" -ne 0 ]; then
  echo "test-inception-scaffold: $failures assertion(s) failed" >&2
  exit 1
fi
echo "test-inception-scaffold: all assertions passed"
