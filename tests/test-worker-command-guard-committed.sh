#!/bin/bash
# Tests for scripts/worker-command-guard.sh: a repository script, a bats file,
# and a script under a planwright root that is a git checkout are trusted only
# when HEAD commits them with the same bytes (committed_blob). A worker can
# Write any file under scripts/ or tests/, so a script it wrote or edited and
# has not committed prompts, through every invocation form and every path
# spelling that reaches it, while committed, unmodified scripts keep their
# approval.
set -u
unset CDPATH
# shellcheck source=tests/lib/worker-command-guard-harness.sh
. "$(cd "$(dirname "$0")" && pwd)/lib/worker-command-guard-harness.sh"

R=$(cd "$SANDBOX" && pwd -P)/committed
mkdir -p "$R/scripts" "$R/tests" "$R/sub/scripts" "$R/sub/deep"
fixture_git init -q "$R"
printf '#!/bin/sh\nprintf ok\\n\n' >"$R/scripts/clean.sh"
printf '#!/bin/sh\nprintf ok\\n\n' >"$R/tests/clean.sh"
printf '#!/bin/sh\nprintf ok\\n\n' >"$R/scripts/edited.sh"
printf '#!/bin/sh\nprintf ok\\n\n' >"$R/tests/edited.sh"
printf '#!/bin/sh\nprintf ok\\n\n' >"$R/sub/scripts/clean.sh"
printf '@test x { true; }\n' >"$R/tests/clean.bats"
printf '@test x { true; }\n' >"$R/tests/edited.bats"
chmod +x "$R/scripts/clean.sh" "$R/tests/clean.sh"
fixture_commit "$R" scripts tests sub || exit 1
# What a worker's Write leaves behind: new files, edits to committed ones, a
# copy of a committed script under a new name, a staged but uncommitted file.
pw='#!/bin/sh\nprintf pwned\\n > lefthook.yml\n'
printf '%b' "$pw" >"$R/scripts/new.sh"
printf '%b' "$pw" >"$R/tests/new.sh"
printf '%b' "$pw" >"$R/sub/scripts/new.sh"
printf '%b' "$pw" >>"$R/scripts/edited.sh"
printf '%b' "$pw" >>"$R/tests/edited.sh"
printf '@test y { true; }\n' >>"$R/tests/edited.bats"
printf '@test y { true; }\n' >"$R/tests/new.bats"
cp "$R/scripts/clean.sh" "$R/scripts/copy.sh"
printf '%b' "$pw" >"$R/scripts/staged.sh"
fixture_git -C "$R" add scripts/staged.sh
# A directory symlink inside the repository resolves to scripts/, so the
# canonical path, not the spelling, is what HEAD is asked about.
ln -s scripts "$R/via"
# A `cd` is followed only into the worktree the session record names.
write_record "$SANDBOX/committed.record" "$R" || exit 1
HOOK_ENV=("GIT_CONFIG_GLOBAL=/dev/null" "GIT_CONFIG_NOSYSTEM=1"
  "PLANWRIGHT_WORKER_SESSION_RECORD=$SANDBOX/committed.record")

echo "### a committed, unmodified repository script keeps its approval"
for f in scripts/clean.sh tests/clean.sh sub/scripts/clean.sh; do
  assert_allow "sh $f" "sh $f" Bash "$R"
  assert_allow "bash $f" "bash $f" Bash "$R"
  assert_allow "direct $f" "$f" Bash "$R"
  assert_allow "./$f" "./$f" Bash "$R"
  assert_allow "absolute $f" "$R/$f" Bash "$R"
done
assert_allow "through a directory symlink to scripts/" "bash via/clean.sh" Bash "$R"
assert_allow "through .. from a subdirectory" "bash ../../scripts/clean.sh" Bash "$R/sub/deep"
assert_allow "after a cd inside the repository" "cd sub && bash ../tests/clean.sh" Bash "$R"
assert_allow "inside fish -c" "fish -c 'bash scripts/clean.sh'" Bash "$R"
assert_allow "behind timeout" "timeout 60 bash tests/clean.sh" Bash "$R"
assert_allow "in a loop" "for f in scripts/clean.sh tests/clean.sh; do bash \$f; done" Bash "$R"
assert_allow "bats on a committed file" "bats tests/clean.bats" Bash "$R"

echo "### a script the worker wrote or edited prompts"
for f in scripts/new.sh tests/new.sh sub/scripts/new.sh scripts/edited.sh tests/edited.sh \
  scripts/copy.sh scripts/staged.sh; do
  assert_defer "sh $f" "sh $f" Bash "$R"
  assert_defer "bash $f" "bash $f" Bash "$R"
  assert_defer "direct $f" "$f" Bash "$R"
  assert_defer "./$f" "./$f" Bash "$R"
  assert_defer "absolute $f" "$R/$f" Bash "$R"
  assert_defer "inside fish -c: $f" "fish -c 'bash $f'" Bash "$R"
  assert_defer "behind timeout: $f" "timeout 60 bash $f" Bash "$R"
done
assert_defer "untracked, through a directory symlink" "bash via/new.sh" Bash "$R"
assert_defer "edited, through a directory symlink" "via/edited.sh" Bash "$R"
assert_defer "untracked, through .." "bash ../../scripts/new.sh" Bash "$R/sub/deep"
assert_defer "untracked, through a .. segment inside the path" "bash sub/../tests/new.sh" Bash "$R"
assert_defer "untracked, after a cd" "cd sub && bash ../tests/new.sh" Bash "$R"
assert_defer "untracked, in a loop beside a committed one" \
  "for f in scripts/clean.sh scripts/new.sh; do bash \$f; done" Bash "$R"
assert_defer "untracked, through a variable" "f=scripts/new.sh && bash \$f" Bash "$R"
assert_defer "bats on an untracked file" "bats tests/new.bats" Bash "$R"
assert_defer "bats on an edited file" "bats tests/edited.bats" Bash "$R"
assert_defer "bats beside a committed file" "bats tests/clean.bats tests/new.bats" Bash "$R"
assert_defer "bats on a directory, which runs whatever it holds" "bats tests" Bash "$R"

echo "### the edit is undone or committed"
cp "$R/scripts/clean.sh" "$R/scripts/edited.sh"
assert_allow "an edit put back byte for byte" "bash scripts/edited.sh" Bash "$R"
fixture_commit "$R" scripts/new.sh || exit 1
assert_allow "a script HEAD commits" "bash scripts/new.sh" Bash "$R"
rm -f "$R/scripts/clean.sh"
mkdir "$R/scripts/clean.sh"
assert_defer "a directory where HEAD has the file" "bash scripts/clean.sh" Bash "$R"

echo "### a repository with no commit trusts no script"
E=$(cd "$SANDBOX" && pwd -P)/empty
mkdir -p "$E/scripts"
fixture_git init -q "$E"
printf '%b' "$pw" >"$E/scripts/untracked-new.sh"
assert_defer "sh on a fresh repository" "sh scripts/untracked-new.sh" Bash "$E"
assert_defer "bash on a fresh repository" "bash scripts/untracked-new.sh" Bash "$E"
assert_defer "direct on a fresh repository" "scripts/untracked-new.sh" Bash "$E"
assert_defer "the write it would make" "printf x > lefthook.yml" Bash "$E"

echo "### a planwright root that is a git checkout"
C=$(cd "$SANDBOX" && pwd -P)/pwcheckout
mkdir -p "$C/scripts" "$SANDBOX/elsewhere"
fixture_git init -q "$C"
printf '#!/bin/sh\n' >"$C/scripts/plug.sh"
fixture_commit "$C" scripts || exit 1
printf '%b' "$pw" >"$C/scripts/planted.sh"
HOOK_ENV=("GIT_CONFIG_GLOBAL=/dev/null" "GIT_CONFIG_NOSYSTEM=1" "PLANWRIGHT_ROOT=$C")
assert_allow "a committed root script" "bash $C/scripts/plug.sh" Bash "$SANDBOX/elsewhere"
assert_defer "a script planted in the root" "bash $C/scripts/planted.sh" Bash "$SANDBOX/elsewhere"
assert_defer "a script planted in the root, run directly" "$C/scripts/planted.sh" Bash "$SANDBOX/elsewhere"
HOOK_ENV=("PLANWRIGHT_ROOT=$PLUGIN_ROOT")
assert_allow "an install copy with no checkout of its own keeps its approval" \
  "bash $PLUGIN_ROOT/scripts/plug.sh" Bash "$PLUGIN_CWD"
HOOK_ENV=()

finish_suite worker-command-guard-committed
