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
assert_contains "notes: name both exports" "exports/pitch.html" "$notes"
assert_contains "notes: publishing is offered, never automatic" "auto-republish" "$notes"
assert_contains "notes: the publish state lives outside the work tree" \
  "the clone's git directory" "$notes"
assert_not_contains "notes: no stale gitignore claim for the publish state" \
  "which is gitignored" "$notes"
# The hook stages the export it regenerates, which git's partial-commit path
# leaves showing as modified afterwards. Surprising, harmless, and worth saying
# once in the notes rather than letting every operator rediscover it.
assert_contains "notes: explain the post-partial-commit status" "git commit <path>" "$notes"

# REQ-G1.8 — the Cowork sync protocol, and its import from CLAUDE.md.
assert_file "local rung: sync protocol" "$v/sync-protocol.md"
assert_file "local rung: CLAUDE.md" "$v/CLAUDE.md"
assert_contains "local rung: reports the protocol" "wrote sync-protocol.md" "$out"
proto="$(cat "$v/sync-protocol.md")"
assert_contains "G1.8 protocol: pull before editing" "git pull" "$proto"
assert_contains "G1.8 protocol: push after committing" "git push" "$proto"
assert_contains "G1.8 protocol: edits land as commits" "git commit" "$proto"
assert_contains "G1.8 protocol: commit messages in plain language" "plain-language" "$proto"
assert_contains "G1.8 protocol: IDs are untouchable" "Never renumber" "$proto"
assert_contains "G1.8 protocol: register statuses are untouchable" "**Status:**" "$proto"
assert_contains "G1.8 protocol: gate records are untouchable" "## Gate log" "$proto"
assert_contains "G1.8 protocol: protected changes become notes for the operator" "under \`proposals/\`" "$proto"
assert_contains "G1.8 protocol: a blocked push degrades to a local commit" "**Push blocked**: keep the commit" "$proto"
assert_contains "G1.8 protocol: says it is advisory, not the enforcement" "validator" "$proto"
assert_contains "G1.8 CLAUDE.md imports the protocol" "@sync-protocol.md" "$(cat "$v/CLAUDE.md")"
assert_contains "notes: name the sync protocol" "sync-protocol.md" "$notes"

# An operator's CLAUDE.md is theirs: the import is appended once, never the
# file replaced, --force included.
v="$tmp/own-claude"
mkdir -p "$v"
printf '# Our venture\n\nHouse rules.\n' >"$v/CLAUDE.md"
out="$("$SCAFFOLD" --rung local "$v" 2>&1)"
assert_eq "G1.8 own CLAUDE.md: exit 0" "0" "$?"
assert_contains "G1.8 own CLAUDE.md: reports the import added" "updated CLAUDE.md" "$out"
claude_md="$(cat "$v/CLAUDE.md")"
assert_contains "G1.8 own CLAUDE.md: the operator's text stays" "House rules." "$claude_md"
assert_contains "G1.8 own CLAUDE.md: the import is appended" "@sync-protocol.md" "$claude_md"
out="$("$SCAFFOLD" --rung local --force "$v" 2>&1)"
assert_contains "G1.8 own CLAUDE.md: a re-run keeps it" "kept CLAUDE.md" "$out"
assert_eq "G1.8 own CLAUDE.md: the import is never duplicated" "1" \
  "$(grep -c '^@sync-protocol.md$' "$v/CLAUDE.md")"
assert_contains "G1.8 own CLAUDE.md: --force keeps the operator's text" "House rules." "$(cat "$v/CLAUDE.md")"

v="$tmp/linked-claude"
mkdir -p "$v"
printf 'elsewhere\n' >"$tmp/outside-claude.md"
ln -s "$tmp/outside-claude.md" "$v/CLAUDE.md"
out="$("$SCAFFOLD" --rung local "$v" 2>&1)"
assert_eq "G1.8 linked CLAUDE.md: the scaffold still succeeds" "0" "$?"
assert_contains "G1.8 linked CLAUDE.md: refused and said" "symbolic link" "$out"
assert_eq "G1.8 linked CLAUDE.md: nothing written through the link" "elsewhere" "$(cat "$tmp/outside-claude.md")"

# No emitted file is written through a symbolic link: not an existing link
# (with or without --force), not a dangling one, not one in a parent directory.
v="$tmp/linked-emit"
mkdir -p "$v" "$tmp/outside-dir"
printf 'theirs\n' >"$tmp/outside-proto.md"
ln -s "$tmp/outside-proto.md" "$v/sync-protocol.md"
ln -s "$tmp/outside-dangling.md" "$v/.gitignore"
ln -s "$tmp/outside-dir" "$v/githooks"
out="$("$SCAFFOLD" --rung local --force "$v" 2>&1)"
assert_eq "linked emit: the scaffold still succeeds" "0" "$?"
assert_contains "linked emit: a linked file is refused and said" "sync-protocol.md is a symbolic link" "$out"
assert_eq "linked emit: --force writes nothing through a file link" "theirs" "$(cat "$tmp/outside-proto.md")"
assert_no_file "linked emit: a dangling link is not followed" "$tmp/outside-dangling.md"
assert_contains "linked emit: a dangling link is refused and said" ".gitignore is a symbolic link" "$out"
assert_no_file "linked emit: nothing written through a linked directory" "$tmp/outside-dir/pre-commit"
assert_contains "linked emit: a linked directory is refused and said" "githooks/pre-commit is under a symbolic link" "$out"
assert_file "linked emit: the unlinked files are still written" "$v/hygiene-wiring.md"

# A last line with no newline must not have the import glued onto it, or the
# keep check would miss it and every re-run would append again.
v="$tmp/unterminated-claude"
mkdir -p "$v"
printf '# Ours\nlast' >"$v/CLAUDE.md"
"$SCAFFOLD" --rung local "$v" >/dev/null 2>&1
"$SCAFFOLD" --rung local "$v" >/dev/null 2>&1
assert_eq "G1.8 unterminated CLAUDE.md: the import is its own line, once" "1" \
  "$(grep -c '^@sync-protocol.md$' "$v/CLAUDE.md")"
assert_eq "G1.8 unterminated CLAUDE.md: the operator's last line stays whole" "1" \
  "$(grep -c '^last$' "$v/CLAUDE.md")"

# A CRLF file that already imports the protocol keeps it, not a second copy.
v="$tmp/crlf-claude"
mkdir -p "$v"
printf '# Ours\r\n@sync-protocol.md\r\n' >"$v/CLAUDE.md"
out="$("$SCAFFOLD" --rung local "$v" 2>&1)"
assert_contains "G1.8 CRLF CLAUDE.md: the existing import is recognised" "kept CLAUDE.md" "$out"
assert_eq "G1.8 CRLF CLAUDE.md: no second import" "1" "$(grep -c 'sync-protocol' "$v/CLAUDE.md")"

v="$tmp/dir-claude"
mkdir -p "$v/CLAUDE.md"
out="$("$SCAFFOLD" --rung local "$v" 2>&1)"
assert_eq "G1.8 CLAUDE.md directory: the scaffold still succeeds" "0" "$?"
assert_contains "G1.8 CLAUDE.md directory: refused and said" "not a regular file" "$out"

# Root reads and writes through any mode, so the mode cases prove nothing there.
if [ "$(id -u)" -ne 0 ]; then
  v="$tmp/readonly-claude"
  mkdir -p "$v"
  printf '# Ours\n' >"$v/CLAUDE.md"
  chmod 444 "$v/CLAUDE.md"
  out="$("$SCAFFOLD" --rung local "$v" 2>&1)"
  assert_eq "G1.8 read-only CLAUDE.md: the scaffold still succeeds" "0" "$?"
  assert_contains "G1.8 read-only CLAUDE.md: said, with the line to add" "@sync-protocol.md to it by hand" "$out"
  assert_file "G1.8 read-only CLAUDE.md: the wiring notes are still written" "$v/hygiene-wiring.md"
  assert_eq "G1.8 read-only CLAUDE.md: left as it was" "# Ours" "$(cat "$v/CLAUDE.md")"

  v="$tmp/writeonly-claude"
  mkdir -p "$v"
  printf '# Ours\n' >"$v/CLAUDE.md"
  chmod 200 "$v/CLAUDE.md"
  "$SCAFFOLD" --rung local "$v" >/dev/null 2>&1
  out="$("$SCAFFOLD" --rung local "$v" 2>&1)"
  chmod 644 "$v/CLAUDE.md"
  assert_eq "G1.8 unreadable CLAUDE.md: nothing appended blind" "# Ours" "$(cat "$v/CLAUDE.md")"
  assert_contains "G1.8 unreadable CLAUDE.md: said" "not readable" "$out"

  v="$tmp/readonly-imported-claude"
  mkdir -p "$v"
  printf '# Ours\n@sync-protocol.md\n' >"$v/CLAUDE.md"
  chmod 444 "$v/CLAUDE.md"
  out="$("$SCAFFOLD" --rung local "$v" 2>&1)"
  assert_contains "G1.8 read-only CLAUDE.md that already imports: kept" "kept CLAUDE.md" "$out"
  assert_not_contains "G1.8 read-only CLAUDE.md that already imports: no by-hand warning" "by hand" "$out"
fi

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
tracked="$(cd "$venture" && git ls-files exports/pitch.html)"
assert_eq "hook: the regenerated pitch was staged into the commit" "exports/pitch.html" "$tracked"

# A bundle edit regenerates the export inside the same commit.
sed 's|^Median incident-handover time drops below ten minutes within one quarter of adoption.$|Median incident-handover time drops below eight minutes.|' \
  "$venture/brief.md" >"$venture/brief.new" && mv "$venture/brief.new" "$venture/brief.md"
out="$(cd "$venture" && git add brief.md && git commit -qm "sharpen the metric" 2>&1)"
rc=$?
assert_eq "hook: a bundle edit commits cleanly" "0" "$rc"
assert_contains "hook: the export followed the edit" "eight minutes" "$(cat "$venture/exports/venture.html")"
changed="$(cd "$venture" && git show --name-only --format= HEAD)"
assert_contains "hook: the export rode the same commit" "exports/venture.html" "$changed"
assert_contains "hook: the pitch followed the edit" "eight minutes" "$(cat "$venture/exports/pitch.html")"
assert_contains "hook: the pitch rode the same commit" "exports/pitch.html" "$changed"

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
  git checkout -q -- brief.md plan.md exports/venture.html exports/pitch.html
) >/dev/null 2>&1

# The same walk-around through a field only the pitch renders, with the
# credential existing ONLY in the rendered page: its key and value sit on two
# source lines, which no per-line pattern matches, and the pitch joins the
# paragraph into one. Only screening the pitch page itself can catch it.
split_key='api_key ='
split_val='AbCdEfGh''IjKlMnOpQrStUvWx12'
sed "s|^Rides the incident-tooling consolidation already funded for the year\\.\$|Rides the consolidation; $split_key\\
$split_val is the relay credential.|" \
  "$venture/brief.md" >"$venture/brief.new" && mv "$venture/brief.new" "$venture/brief.md"
printf '\nAnother planning note.\n' >>"$venture/plan.md"
out="$(cd "$venture" && git add plan.md && git commit -qm "another plan note" 2>&1)"
rc=$?
assert_eq "hook: a secret existing only in the rendered pitch blocks the commit" "1" "$rc"
assert_not_contains "hook: the pitch's blocked secret is not echoed" "AbCdEfGh""IjKl" "$out"
committed="$(cd "$venture" && git show HEAD:exports/pitch.html 2>/dev/null)"
assert_not_contains "hook: no commit carried the secret into the pitch" "AbCdEfGh" "$committed"
(
  cd "$venture" || exit 1
  git reset -q HEAD . >/dev/null 2>&1
  git checkout -q -- brief.md plan.md exports/venture.html exports/pitch.html
) >/dev/null 2>&1

# HTML escaping turns a quoted assignment's quotes into entities, which no
# credential pattern matches, so the regenerated pages alone are not enough to
# screen: the bundle files they were rendered from are screened too.
sed 's|^- \*\*Risk-if-wrong:\*\* the fan-out saves no time|- **Risk-if-wrong:** api_key="AbCdEfGh''IjKlMnOpQrStUvWx12" the fan-out saves no time|' \
  "$venture/assumptions.md" >"$venture/assumptions.new" && mv "$venture/assumptions.new" "$venture/assumptions.md"
printf '\nA third planning note.\n' >>"$venture/plan.md"
out="$(cd "$venture" && git add plan.md && git commit -qm "a third plan note" 2>&1)"
rc=$?
assert_eq "hook: an unstaged quoted credential blocks the commit" "1" "$rc"
assert_not_contains "hook: the quoted credential is not echoed" "AbCdEfGh""IjKlMnOpQrStUvWx12" "$out"
committed="$(cd "$venture" && git show HEAD:exports/venture.html 2>/dev/null)"
assert_not_contains "hook: no commit carried the quoted credential" "AbCdEfGh" "$committed"
(
  cd "$venture" || exit 1
  git reset -q HEAD . >/dev/null 2>&1
  git checkout -q -- assumptions.md plan.md exports/venture.html exports/pitch.html
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
assert_contains "hook: it says the exports were not regenerated" "were not regenerated" "$out"
assert_contains "hook: the renderer's own reason reaches the operator" \
  "inception-render: refusing to render" "$out"

# A staging failure is the other half of step 3, and the one that used to pass
# in silence: the render succeeds, so the operator is told nothing, but the
# export never joins the commit and the published HTML starts drifting from the
# bundle. An ignored `exports/` is the cheapest way to make `git add` refuse.
staged_v="$(mktemp -d "$tmp/ignored-exports.XXXXXX")" || exit 1
inception_fixture_write "$staged_v" >/dev/null 2>&1 || exit 1
(
  cd "$staged_v" || exit 1
  git init -q .
  git config user.email fixture@example.invalid
  git config user.name Fixture
  git config commit.gpgsign false
) >/dev/null 2>&1 || exit 1
"$SCAFFOLD" --rung local --wire "$staged_v" >/dev/null 2>&1
printf 'exports/\n' >>"$staged_v/.gitignore"
out="$(cd "$staged_v" && git add -A && git commit -qm "bundle with exports ignored" 2>&1)"
rc=$?
assert_eq "hook: a staging failure does not block the commit" "0" "$rc"
assert_contains "hook: a staging failure is reported, not swallowed" \
  "could not be staged" "$out"
assert_file "hook: the export was still rendered on disk" "$staged_v/exports/venture.html"
assert_file "hook: the pitch was still rendered on disk" "$staged_v/exports/pitch.html"
assert_contains "hook: the pitch's staging failure is named" \
  "exports/pitch.html could not be staged" "$out"

# Step 1 refuses the commit whether the screen found something or could not run,
# but it must not describe the second as the first: telling an operator their
# staged content "carries a credential" when the screen never executed sends
# them hunting through a bundle for something that is not in it. An unusable
# PLANWRIGHT_SECRET_SCREEN_TOOL is the cheapest way to make the screen exit 2.
env_v="$(mktemp -d "$tmp/screen-env.XXXXXX")" || exit 1
inception_fixture_write "$env_v" >/dev/null 2>&1 || exit 1
(
  cd "$env_v" || exit 1
  git init -q .
  git config user.email fixture@example.invalid
  git config user.name Fixture
  git config commit.gpgsign false
) >/dev/null 2>&1 || exit 1
"$SCAFFOLD" --rung local --wire "$env_v" >/dev/null 2>&1
out="$(cd "$env_v" && git add -A \
  && PLANWRIGHT_SECRET_SCREEN_TOOL=not-a-tool git commit -qm "screen cannot run" 2>&1)"
rc=$?
assert_eq "hook: an unusable secret screen still refuses the commit" "1" "$rc"
assert_contains "hook: it says the screen could not check the content" \
  "could not check the staged content" "$out"
assert_not_contains "hook: it does not claim a credential was found" \
  "looks like it carries a credential" "$out"

# The BSD half of the declared bash-3.2/BSD floor. BSD mktemp supplies no
# default template, so a bare `mktemp` is a usage error there and the scaffold
# would exit 2 without emitting a single file — on a Mac, at venture creation.
mkstub="$tmp/bsdstub"
mkdir -p "$mkstub" || exit 1
cat >"$mkstub/mktemp" <<'MKTEMP'
#!/bin/sh
# BSD mktemp: a template argument (or -t prefix) is required.
have_tmpl=0
want_t=0
for a in "$@"; do
  case $a in
    -t) want_t=1 ;;
    -*) ;;
    *) have_tmpl=1 ;;
  esac
done
if [ "$have_tmpl" -eq 0 ] && [ "$want_t" -eq 0 ]; then
  echo "usage: mktemp [-d] [-q] [-t prefix] [-u] template ..." >&2
  exit 1
fi
exec /usr/bin/mktemp "$@"
MKTEMP
chmod +x "$mkstub/mktemp" || exit 1
if [ -x /usr/bin/mktemp ]; then
  bsd_v="$tmp/bsd-rung"
  mkdir -p "$bsd_v"
  out="$(PATH="$mkstub:$PATH" "$SCAFFOLD" --rung local "$bsd_v" 2>&1)"
  rc=$?
  assert_eq "BSD mktemp: the scaffold still emits" "0" "$rc"
  assert_file "BSD mktemp: the hook landed" "$bsd_v/githooks/pre-commit"
  assert_not_contains "BSD mktemp: no usage error from mktemp" "usage: mktemp" "$out"
else
  echo "ok: BSD mktemp stub skipped (no /usr/bin/mktemp to delegate to)"
fi

# The whole hook, against a planwright tree that lost its executable bits. An
# archive, a container layer or a sync tool can drop +x without dropping the
# file, and the hook used to gate every guard behind -x: the screen then skipped
# itself and a staged credential was committed with no warning at all. Nothing
# in the hook may depend on a file mode.
noexec_pw="$tmp/pw-noexec"
mkdir -p "$noexec_pw/scripts"
cp "$REPO_ROOT/scripts/"inception-*.sh "$noexec_pw/scripts/" || exit 1
cp "$REPO_ROOT/scripts/echo-safety.sh" "$REPO_ROOT/scripts/spec-parse.sh" "$REPO_ROOT/scripts/html-escape.sh" "$noexec_pw/scripts/" || exit 1
chmod -x "$noexec_pw/scripts/"*.sh
nx_v="$tmp/venture-noexec"
mkdir -p "$nx_v"
inception_fixture_write "$nx_v" >/dev/null 2>&1 || exit 1
(
  cd "$nx_v" || exit 1
  git init -q .
  git config user.email fixture@example.invalid
  git config user.name Fixture
  git config commit.gpgsign false
) >/dev/null 2>&1 || exit 1
"$SCAFFOLD" --rung local --wire "$nx_v" >/dev/null 2>&1

printf '%s\n' "token: ghp_""0123456789abcdefghijklmnopqrstuvwxyz" >"$nx_v/leak.md"
out="$(cd "$nx_v" && git add -A \
  && PLANWRIGHT_ROOT="$noexec_pw" PLANWRIGHT_SECRET_SCREEN_TOOL=none \
    git commit -qm "carries a credential" 2>&1)"
rc=$?
assert_eq "no +x anywhere: a staged credential is still refused" "1" "$rc"
assert_contains "no +x anywhere: it says a credential was found" \
  "carries a credential" "$out"
committed="$(cd "$nx_v" && git log --oneline 2>/dev/null | wc -l | tr -d ' ')"
assert_eq "no +x anywhere: nothing was committed" "0" "$committed"

# And the guards must actually RUN, not merely block everything: a clean bundle
# still commits, with the export regenerated and staged.
rm -f "$nx_v/leak.md"
out="$(cd "$nx_v" && git add -A \
  && PLANWRIGHT_ROOT="$noexec_pw" PLANWRIGHT_SECRET_SCREEN_TOOL=none \
    git commit -qm "clean bundle" 2>&1)"
rc=$?
assert_eq "no +x anywhere: a clean bundle still commits" "0" "$rc"
staged_export="$(cd "$nx_v" && git show --name-only --format= HEAD | grep -c 'exports/venture.html')"
assert_eq "no +x anywhere: the export was still regenerated and staged" "1" "$staged_export"

# The CI guard exists to catch a stakeholder edit arriving through the GitHub
# web UI, and an edit made straight to main is a push, not a pull request. So
# the baseline has to be chosen per event: reading only the pull-request
# expression left it empty on push and silently downgraded the run to plain
# validation, with the append-only rules never firing on the one channel they
# were written for.
wf_v="$tmp/wf-remote"
mkdir -p "$wf_v"
(
  cd "$wf_v" || exit 1
  git init -q .
  git remote add origin git@github.com:example/venture.git
) >/dev/null 2>&1 || exit 1
"$SCAFFOLD" --rung remote "$wf_v" >/dev/null 2>&1
wf="$wf_v/.github/workflows/venture-guard.yml"
assert_file "workflow: the remote rung emits the guard" "$wf"
wf_body="$(cat "$wf")"
assert_contains "workflow: falls back to the push baseline" "github.event.before" "$wf_body"
assert_contains "workflow: verifies the baseline commit resolves" "rev-parse --verify" "$wf_body"
assert_contains "workflow: says so when no baseline is usable" "did NOT run" "$wf_body"

# Same blind spot, other artifact: `lint:shell` globs the tracked scripts, and
# the hook this script GENERATES lives inside a quoted heredoc, which shellcheck
# reads as an opaque string. So nothing linted the emitted hook, and an unquoted
# `$HOME` glob in its planwright lookup survived several review rounds — a HOME
# containing a space split into fragments that resolved to nothing, planwright
# read as absent, and every guard skipped itself while a credential committed.
# Lint the generated hook here, or nowhere.
if command -v shellcheck >/dev/null 2>&1; then
  scout="$(shellcheck "$wf_v/githooks/pre-commit" 2>&1)"
  screrc=$?
  assert_eq "hook: the generated hook is shellcheck-clean" "0" "$screrc"
  [ "$screrc" -eq 0 ] || printf '%s\n' "$scout" >&2
else
  echo "ok: hook shellcheck skipped (shellcheck not installed)"
fi

# A $HOME with a space must not disable guard discovery. Driven through the
# emitted hook rather than asserted on its text, so it is the behaviour under
# test and not the spelling.
sp_home="$tmp/spaced home"
mkdir -p "$sp_home/.claude/plugins/cache/planwright/planwright/pw/scripts"
cp "$REPO_ROOT/scripts/"inception-*.sh "$sp_home/.claude/plugins/cache/planwright/planwright/pw/scripts/" || exit 1
cp "$REPO_ROOT/scripts/echo-safety.sh" "$REPO_ROOT/scripts/spec-parse.sh" \
  "$REPO_ROOT/scripts/html-escape.sh" \
  "$sp_home/.claude/plugins/cache/planwright/planwright/pw/scripts/" || exit 1
sp_v="$tmp/venture-spaced-home"
mkdir -p "$sp_v"
inception_fixture_write "$sp_v" >/dev/null 2>&1 || exit 1
(
  cd "$sp_v" || exit 1
  git init -q .
  git config user.email fixture@example.invalid
  git config user.name Fixture
  git config commit.gpgsign false
) >/dev/null 2>&1 || exit 1
"$SCAFFOLD" --rung local --wire "$sp_v" >/dev/null 2>&1
printf '%s\n' "token: ghp_""0123456789abcdefghijklmnopqrstuvwxyz" >"$sp_v/leak.md"
out="$(cd "$sp_v" && git add -A \
  && env -u PLANWRIGHT_ROOT -u CLAUDE_PLUGIN_ROOT HOME="$sp_home" \
    PLANWRIGHT_SECRET_SCREEN_TOOL=none git commit -qm "credential under spaced HOME" 2>&1)"
rc=$?
assert_eq "HOME with a space: the credential is still refused" "1" "$rc"
assert_not_contains "HOME with a space: planwright is still found" \
  "planwright not found" "$out"
sp_commits="$(cd "$sp_v" && git log --oneline 2>/dev/null | wc -l | tr -d ' ')"
assert_eq "HOME with a space: nothing was committed" "0" "$sp_commits"

# The README tells the operator to pin planwright with a bare
# `PLANWRIGHT_ROOT=...` in .planwright-local.sh, which the hook sources as a
# shell variable, never exported. The copy the pin names must stay the one that
# runs even when a second copy sits at the writer-delivery path, where the
# pinned copy's own root helper would land if it could not see the pin.
pin_pw="$tmp/pw-pinned"
mkdir -p "$pin_pw/scripts"
cp "$REPO_ROOT/scripts/"inception-*.sh "$REPO_ROOT/scripts/resolve-root.sh" \
  "$REPO_ROOT/scripts/echo-safety.sh" "$REPO_ROOT/scripts/spec-parse.sh" \
  "$REPO_ROOT/scripts/html-escape.sh" "$pin_pw/scripts/" || exit 1
pin_claude="$tmp/pin-claude"
mkdir -p "$pin_claude/planwright/scripts"
for s in "$REPO_ROOT/scripts/"inception-*.sh; do
  printf '%s\n' '#!/bin/sh' 'echo "WRONG-COPY ran" >&2' 'exit 1' >"$pin_claude/planwright/scripts/${s##*/}"
done
pin_v="$tmp/venture-pinned"
mkdir -p "$pin_v"
inception_fixture_write "$pin_v" >/dev/null 2>&1 || exit 1
(
  cd "$pin_v" || exit 1
  git init -q .
  git config user.email fixture@example.invalid
  git config user.name Fixture
  git config commit.gpgsign false
) >/dev/null 2>&1 || exit 1
"$SCAFFOLD" --rung local --wire "$pin_v" >/dev/null 2>&1
printf 'PLANWRIGHT_ROOT=%s\n' "$pin_pw" >"$pin_v/.planwright-local.sh"
out="$(cd "$pin_v" && git add -A \
  && env -u PLANWRIGHT_ROOT -u CLAUDE_PLUGIN_ROOT CLAUDE_DIR="$pin_claude" \
    PLANWRIGHT_SECRET_SCREEN_TOOL=none git commit -qm "pinned copy" 2>&1)"
rc=$?
assert_not_contains "unexported pin: the writer-delivery copy does not run" "WRONG-COPY" "$out"
assert_eq "unexported pin: the pinned copy's guards pass the clean bundle" "0" "$rc"
pin_staged="$(cd "$pin_v" && git show --name-only --format= HEAD)"
assert_contains "unexported pin: the pinned copy rendered and staged the dashboard" \
  "exports/venture.html" "$pin_staged"
assert_contains "unexported pin: the pinned copy rendered and staged the pitch" \
  "exports/pitch.html" "$pin_staged"

# A writer-mode install under a custom CLAUDE_DIR is an arm of the core root
# chain, so `inception-venture.sh probe` reports it as loaded; the hook must
# find the same copy, or a commit skips the guards that report promised.
cd_claude="$tmp/custom-claude-dir"
mkdir -p "$cd_claude/planwright/scripts" "$tmp/cd-home"
cp "$REPO_ROOT/scripts/"inception-*.sh "$REPO_ROOT/scripts/resolve-root.sh" \
  "$REPO_ROOT/scripts/echo-safety.sh" "$REPO_ROOT/scripts/spec-parse.sh" \
  "$REPO_ROOT/scripts/html-escape.sh" "$cd_claude/planwright/scripts/" || exit 1
cd_v="$tmp/venture-claude-dir"
mkdir -p "$cd_v"
inception_fixture_write "$cd_v" >/dev/null 2>&1 || exit 1
(
  cd "$cd_v" || exit 1
  git init -q .
  git config user.email fixture@example.invalid
  git config user.name Fixture
  git config commit.gpgsign false
) >/dev/null 2>&1 || exit 1
"$SCAFFOLD" --rung local --wire "$cd_v" >/dev/null 2>&1
printf '%s\n' "token: ghp_""0123456789abcdefghijklmnopqrstuvwxyz" >"$cd_v/leak.md"
out="$(cd "$cd_v" && git add -A \
  && env -u PLANWRIGHT_ROOT -u CLAUDE_PLUGIN_ROOT HOME="$tmp/cd-home" CLAUDE_DIR="$cd_claude" \
    PLANWRIGHT_SECRET_SCREEN_TOOL=none git commit -qm "credential, CLAUDE_DIR install" 2>&1)"
rc=$?
assert_eq "CLAUDE_DIR install: the credential is refused" "1" "$rc"
assert_not_contains "CLAUDE_DIR install: planwright is found" "planwright not found" "$out"

# A planwright copy whose renderer predates --mode and --output cannot render
# the pages the hook asks for. That is a failed render: it warns and the commit
# goes through, never refused for an environment reason.
old_pw="$tmp/pw-old-renderer"
mkdir -p "$old_pw/scripts"
cp "$REPO_ROOT/scripts/"inception-*.sh "$REPO_ROOT/scripts/echo-safety.sh" \
  "$REPO_ROOT/scripts/spec-parse.sh" "$old_pw/scripts/" || exit 1
cat >"$old_pw/scripts/inception-render.sh" <<'OLDRENDER'
#!/bin/sh
case $1 in -*) echo "usage: inception-render.sh <venture-dir>" >&2; exit 2 ;; esac
mkdir -p "$1/exports" && printf '<!DOCTYPE html><p>dashboard only</p>\n' >"$1/exports/venture.html"
OLDRENDER
old_v="$tmp/venture-old-renderer"
mkdir -p "$old_v"
inception_fixture_write "$old_v" >/dev/null 2>&1 || exit 1
(
  cd "$old_v" || exit 1
  git init -q .
  git config user.email fixture@example.invalid
  git config user.name Fixture
  git config commit.gpgsign false
) >/dev/null 2>&1 || exit 1
"$SCAFFOLD" --rung local --wire "$old_v" >/dev/null 2>&1
out="$(cd "$old_v" && git add -A \
  && PLANWRIGHT_ROOT="$old_pw" PLANWRIGHT_SECRET_SCREEN_TOOL=none \
    git commit -qm "older planwright" 2>&1)"
rc=$?
assert_eq "older renderer: the commit succeeds" "0" "$rc"
assert_contains "older renderer: it says the exports were not regenerated" "were not regenerated" "$out"

# The bytes staged are the bytes screened. A screen wrapper stands in for a
# concurrent render: while the hook screens, it writes a different page into
# the work tree. The commit must carry the screened page, not the swapped one.
race_pw="$tmp/pw-race"
mkdir -p "$race_pw/scripts"
cp "$REPO_ROOT/scripts/"inception-*.sh "$REPO_ROOT/scripts/echo-safety.sh" \
  "$REPO_ROOT/scripts/spec-parse.sh" "$REPO_ROOT/scripts/html-escape.sh" "$race_pw/scripts/" || exit 1
mv "$race_pw/scripts/inception-secret-screen.sh" "$race_pw/scripts/inception-secret-screen.real.sh"
cat >"$race_pw/scripts/inception-secret-screen.sh" <<'RACESCREEN'
#!/bin/sh
top=$(git rev-parse --show-toplevel)
mkdir -p "$top/exports" && printf 'SWAPPED-IN\n' >"$top/exports/venture.html"
exec /bin/sh "$(dirname "$0")/inception-secret-screen.real.sh" "$@"
RACESCREEN
race_v="$tmp/venture-race"
mkdir -p "$race_v"
inception_fixture_write "$race_v" >/dev/null 2>&1 || exit 1
(
  cd "$race_v" || exit 1
  git init -q .
  git config user.email fixture@example.invalid
  git config user.name Fixture
  git config commit.gpgsign false
) >/dev/null 2>&1 || exit 1
"$SCAFFOLD" --rung local --wire "$race_v" >/dev/null 2>&1
out="$(cd "$race_v" && git add -A \
  && PLANWRIGHT_ROOT="$race_pw" PLANWRIGHT_SECRET_SCREEN_TOOL=none \
    git commit -qm "race" 2>&1)"
rc=$?
assert_eq "screen-to-stage race: the commit succeeds" "0" "$rc"
race_committed="$(cd "$race_v" && git show HEAD:exports/venture.html 2>/dev/null)"
assert_not_contains "screen-to-stage race: the swapped page is not committed" "SWAPPED-IN" "$race_committed"
assert_contains "screen-to-stage race: the screened page is committed" "Northwind Signals" "$race_committed"
assert_eq "screen-to-stage race: the work tree holds the committed page" \
  "$race_committed" "$(cat "$race_v/exports/venture.html")"

# The screened page is staged the way `git add` would stage it: through the
# path's .gitattributes filters, not as raw bytes.
attr_v="$tmp/venture-attr"
mkdir -p "$attr_v"
inception_fixture_write "$attr_v" >/dev/null 2>&1 || exit 1
(
  cd "$attr_v" || exit 1
  git init -q .
  git config user.email fixture@example.invalid
  git config user.name Fixture
  git config commit.gpgsign false
  git config filter.marker.clean "sed s/Northwind/CLEANED/"
  git config filter.marker.smudge cat
) >/dev/null 2>&1 || exit 1
printf 'exports/*.html filter=marker\n' >"$attr_v/.gitattributes"
"$SCAFFOLD" --rung local --wire "$attr_v" >/dev/null 2>&1
out="$(cd "$attr_v" && git add -A && git commit -qm "with attributes" 2>&1)"
rc=$?
assert_eq "gitattributes: the commit succeeds" "0" "$rc"
assert_contains "gitattributes: the page went through the clean filter" "CLEANED" \
  "$(cd "$attr_v" && git show HEAD:exports/venture.html 2>/dev/null)"

# A hook interrupted mid-screen leaves no private render directory in .git.
int_pw="$tmp/pw-int"
mkdir -p "$int_pw/scripts"
cp "$REPO_ROOT/scripts/"inception-*.sh "$REPO_ROOT/scripts/echo-safety.sh" \
  "$REPO_ROOT/scripts/spec-parse.sh" "$REPO_ROOT/scripts/html-escape.sh" "$int_pw/scripts/" || exit 1
mv "$int_pw/scripts/inception-secret-screen.sh" "$int_pw/scripts/inception-secret-screen.real.sh"
cat >"$int_pw/scripts/inception-secret-screen.sh" <<'INTSCREEN'
#!/bin/sh
[ "$1" = --staged ] && exec /bin/sh "$(dirname "$0")/inception-secret-screen.real.sh" "$@"
kill -TERM "$PPID"
exit 2
INTSCREEN
int_v="$tmp/venture-int"
mkdir -p "$int_v"
inception_fixture_write "$int_v" >/dev/null 2>&1 || exit 1
(
  cd "$int_v" || exit 1
  git init -q .
  git config user.email fixture@example.invalid
  git config user.name Fixture
  git config commit.gpgsign false
) >/dev/null 2>&1 || exit 1
"$SCAFFOLD" --rung local --wire "$int_v" >/dev/null 2>&1
(cd "$int_v" && git add -A && PLANWRIGHT_ROOT="$int_pw" PLANWRIGHT_SECRET_SCREEN_TOOL=none \
  git commit -qm "interrupted" >/dev/null 2>&1)
leftover="$(find "$int_v/.git" -maxdepth 1 -name 'planwright-render.*' 2>/dev/null)"
assert_eq "interrupted hook: no private render directory is left" "" "$leftover"

# The two pages are rendered by separate processes, so the hook fixes "today"
# once: a commit that crosses midnight must not give the dashboard and the
# pitch different kill-criterion states. A date stub answers each call with
# the next day.
day_v="$tmp/venture-midnight"
mkdir -p "$day_v"
inception_fixture_write "$day_v" >/dev/null 2>&1 || exit 1
(
  cd "$day_v" || exit 1
  git init -q .
  git config user.email fixture@example.invalid
  git config user.name Fixture
  git config commit.gpgsign false
) >/dev/null 2>&1 || exit 1
"$SCAFFOLD" --rung local --wire "$day_v" >/dev/null 2>&1
datestub="$tmp/datestub"
mkdir -p "$datestub"
real_date="$(command -v date)"
cat >"$datestub/date" <<DATESTUB
#!/bin/sh
case "\$1" in
  +%Y-%m-%d)
    n=\$(cat "$datestub/n" 2>/dev/null || echo 0)
    echo \$((n + 1)) >"$datestub/n"
    if [ "\$n" -eq 0 ]; then echo 2026-09-14; else echo 2026-09-16; fi
    ;;
  *) exec $real_date "\$@" ;;
esac
DATESTUB
chmod +x "$datestub/date"
(cd "$day_v" && git add -A && env -u PLANWRIGHT_INCEPTION_TODAY PATH="$datestub:$PATH" \
  git commit -qm "across midnight" >/dev/null 2>&1)
dash_state="$(cd "$day_v" && git show HEAD:exports/venture.html 2>/dev/null | grep -o 'KC-2</span> — [a-z]*' | head -1)"
pitch_state="$(cd "$day_v" && git show HEAD:exports/pitch.html 2>/dev/null | grep -o 'KC-2</span> — [a-z]*' | head -1)"
assert_eq "midnight: both pages classify KC-2 against the same day" "$dash_state" "$pitch_state"

# The hook renders and screens one snapshot of the bundle, so an edit to the
# work tree between the render and the screen cannot clean the sources the
# screen reads while the escaped page still carries the credential.
snap_pw="$tmp/pw-snap"
mkdir -p "$snap_pw/scripts"
cp "$REPO_ROOT/scripts/"inception-*.sh "$REPO_ROOT/scripts/echo-safety.sh" \
  "$REPO_ROOT/scripts/spec-parse.sh" "$REPO_ROOT/scripts/html-escape.sh" "$snap_pw/scripts/" || exit 1
mv "$snap_pw/scripts/inception-secret-screen.sh" "$snap_pw/scripts/inception-secret-screen.real.sh"
cat >"$snap_pw/scripts/inception-secret-screen.sh" <<'SNAPSCREEN'
#!/bin/sh
if [ "$1" != --staged ]; then
  top=$(git rev-parse --show-toplevel)
  sed 's|api_key=[^ ]*||' "$top/assumptions.md" >"$top/assumptions.new" && mv "$top/assumptions.new" "$top/assumptions.md"
fi
exec /bin/sh "$(dirname "$0")/inception-secret-screen.real.sh" "$@"
SNAPSCREEN
snap_v="$tmp/venture-snap"
mkdir -p "$snap_v"
inception_fixture_write "$snap_v" >/dev/null 2>&1 || exit 1
(
  cd "$snap_v" || exit 1
  git init -q .
  git config user.email fixture@example.invalid
  git config user.name Fixture
  git config commit.gpgsign false
) >/dev/null 2>&1 || exit 1
"$SCAFFOLD" --rung local --wire "$snap_v" >/dev/null 2>&1
(cd "$snap_v" && git add -A && PLANWRIGHT_ROOT="$snap_pw" PLANWRIGHT_SECRET_SCREEN_TOOL=none \
  git commit -qm "clean start" >/dev/null 2>&1)
sed 's|^- \*\*Risk-if-wrong:\*\* the fan-out saves no time|- **Risk-if-wrong:** api_key="AbCdEfGh''IjKlMnOpQrStUvWx12" the fan-out saves no time|' \
  "$snap_v/assumptions.md" >"$snap_v/assumptions.new" && mv "$snap_v/assumptions.new" "$snap_v/assumptions.md"
printf '\nA snapshot note.\n' >>"$snap_v/plan.md"
out="$(cd "$snap_v" && git add plan.md && PLANWRIGHT_ROOT="$snap_pw" PLANWRIGHT_SECRET_SCREEN_TOOL=none \
  git commit -qm "race the screen" 2>&1)"
rc=$?
assert_eq "render-to-screen race: the hook still refuses the commit" "1" "$rc"
assert_not_contains "render-to-screen race: no commit carried the credential" "AbCdEfGh" \
  "$(cd "$snap_v" && git show HEAD:exports/venture.html 2>/dev/null)"

# The blob staged is the one the path's clean filter produces, so that blob is
# what gets screened: a filter that adds bytes must not slip them past the
# screen that checked the page before filtering.
filt_v="$tmp/venture-filter"
mkdir -p "$filt_v"
inception_fixture_write "$filt_v" >/dev/null 2>&1 || exit 1
cred="api_key = AbCdEfGh""IjKlMnOpQrStUvWx12"
(
  cd "$filt_v" || exit 1
  git init -q .
  git config user.email fixture@example.invalid
  git config user.name Fixture
  git config commit.gpgsign false
  git config filter.inject.clean "sed 's/Northwind/$cred/'"
  git config filter.inject.smudge cat
) >/dev/null 2>&1 || exit 1
printf 'exports/*.html filter=inject\n' >"$filt_v/.gitattributes"
"$SCAFFOLD" --rung local --wire "$filt_v" >/dev/null 2>&1
out="$(cd "$filt_v" && git add -A && git commit -qm "filter adds a credential" 2>&1)"
rc=$?
assert_eq "clean filter: a credential it adds is refused" "1" "$rc"
assert_not_contains "clean filter: nothing was committed with it" "AbCdEfGh" \
  "$(cd "$filt_v" && git show HEAD:exports/venture.html 2>/dev/null)"

# A bundle path that is not a regular file is refused before the hook copies
# it, rather than blocking the commit on a FIFO.
# Bounded by timeout (GNU) or gtimeout (Homebrew); stock macOS has neither,
# and the case is skipped there rather than left to hang.
timeout_bin=$(command -v timeout || command -v gtimeout || true)
if [ -z "$timeout_bin" ]; then
  echo "ok: fifo bundle file: skipped (neither timeout nor gtimeout on this host)"
else
  fifo_v="$tmp/venture-fifo"
  mkdir -p "$fifo_v"
  inception_fixture_write "$fifo_v" >/dev/null 2>&1 || exit 1
  (
    cd "$fifo_v" || exit 1
    git init -q .
    git config user.email fixture@example.invalid
    git config user.name Fixture
    git config commit.gpgsign false
  ) >/dev/null 2>&1 || exit 1
  "$SCAFFOLD" --rung local --wire "$fifo_v" >/dev/null 2>&1
  (cd "$fifo_v" && git add -A && git commit -qm "start" >/dev/null 2>&1)
  rm -f "$fifo_v/plan.md"
  mkfifo "$fifo_v/plan.md"
  printf '\nnote\n' >>"$fifo_v/brief.md"
  out="$(cd "$fifo_v" && git add brief.md && "$timeout_bin" 20 git commit -qm "fifo" 2>&1)"
  rc=$?
  assert_eq "fifo bundle file: the hook warns and commits, never hangs" "0" "$rc"
  assert_contains "fifo bundle file: says the exports were not regenerated" "were not regenerated" "$out"
  rm -f "$fifo_v/plan.md"
fi

# exports/ is checked for a symbolic link again at each final write, not only
# before rendering: a screen wrapper stands in for a swap that lands between
# the two, replacing exports/ with a link to a directory outside the checkout.
swap_pw="$tmp/pw-swap"
mkdir -p "$swap_pw/scripts"
cp "$REPO_ROOT/scripts/"inception-*.sh "$REPO_ROOT/scripts/echo-safety.sh" \
  "$REPO_ROOT/scripts/spec-parse.sh" "$REPO_ROOT/scripts/html-escape.sh" "$swap_pw/scripts/" || exit 1
mv "$swap_pw/scripts/inception-secret-screen.sh" "$swap_pw/scripts/inception-secret-screen.real.sh"
cat >"$swap_pw/scripts/inception-secret-screen.sh" <<'SWAPSCREEN'
#!/bin/sh
if [ "$1" != --staged ] && [ -n "${SWAP_OUTSIDE:-}" ]; then
  top=$(git rev-parse --show-toplevel)
  rm -rf "$top/exports" && ln -s "$SWAP_OUTSIDE" "$top/exports"
fi
exec /bin/sh "$(dirname "$0")/inception-secret-screen.real.sh" "$@"
SWAPSCREEN
swap_v="$tmp/venture-swap"
swap_out="$tmp/swap-outside"
mkdir -p "$swap_v" "$swap_out"
inception_fixture_write "$swap_v" >/dev/null 2>&1 || exit 1
(
  cd "$swap_v" || exit 1
  git init -q .
  git config user.email fixture@example.invalid
  git config user.name Fixture
  git config commit.gpgsign false
) >/dev/null 2>&1 || exit 1
"$SCAFFOLD" --rung local --wire "$swap_v" >/dev/null 2>&1
out="$(cd "$swap_v" && git add -A && SWAP_OUTSIDE="$swap_out" PLANWRIGHT_ROOT="$swap_pw" \
  PLANWRIGHT_SECRET_SCREEN_TOOL=none git commit -qm "swap exports" 2>&1)"
leftover="$(find "$swap_out" -type f 2>/dev/null)"
assert_eq "exports swapped for a link mid-hook: nothing is written through it" "" "$leftover"
assert_contains "exports swapped for a link mid-hook: the hook says so" "symbolic link" "$out"

# The repo's own `lint:yaml` covers tracked config, not what this script
# generates, so the emitted workflow is linted here or nowhere.
if command -v yamllint >/dev/null 2>&1; then
  ylout="$(yamllint --strict "$wf" 2>&1)"
  yrc=$?
  assert_eq "workflow: the generated YAML is lint-clean" "0" "$yrc"
  [ "$yrc" -eq 0 ] || printf '%s\n' "$ylout" >&2
else
  echo "ok: workflow yamllint skipped (yamllint not installed)"
fi

if [ "$failures" -ne 0 ]; then
  echo "test-inception-scaffold: $failures assertion(s) failed" >&2
  exit 1
fi
echo "test-inception-scaffold: all assertions passed"
