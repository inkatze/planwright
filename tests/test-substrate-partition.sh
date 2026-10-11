#!/bin/bash
# Tests for scripts/substrate-partition.sh — the call-graph tier partition of
# the script layer.
#
# One fixture tree carries a script per tier, the tie-break, the shell-mutation
# cases and the no-live-caller cases; a second copy adds the task that clears a
# flag. Every row is asserted whole, so a column drifting is caught alongside a
# tier drifting.
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-substrate-partition.sh
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$here/.." && pwd)
SP="$REPO_ROOT/scripts/substrate-partition.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -x "$SP" ] || fail "scripts/substrate-partition.sh missing or not executable"
for t in jq mise; do
  command -v "$t" >/dev/null 2>&1 || fail "$t is required to read the fixture's hook and task surfaces"
done

# BSD mktemp supplies no default template, so a bare `mktemp -d` is a usage
# error on macOS.
tmp=$(mktemp -d "${TMPDIR:-/tmp}/test-substrate-partition.XXXXXX") || fail "mktemp -d failed"
[ -n "$tmp" ] && [ -d "$tmp" ] || fail "mktemp -d produced no directory"
trap 'rm -rf "$tmp"' EXIT
# The physical path, as mise reports task sources (macOS's $TMPDIR sits
# behind a symlink).
tmp=$(cd "$tmp" && pwd -P) || fail "cannot resolve the temp directory"

# put <relative-path>: write stdin to a file in the fixture tree.
put() {
  mkdir -p "$(dirname "$fx/$1")"
  cat >"$fx/$1"
}

fx="$tmp/fx"
mkdir -p "$fx/scripts" "$fx/githooks" "$fx/hooks" "$fx/skills" "$fx/.github/workflows" "$fx/tests" "$fx/docs"

put hooks/hooks.json <<'EOF'
{"hooks": {"PreToolUse": [{"matcher": "Bash", "hooks": [
  {"type": "command", "command": "\"${CLAUDE_PLUGIN_ROOT}\"/scripts/hooked.sh bash"},
  {"type": "command", "command": "\"${CLAUDE_PLUGIN_ROOT}\"/scripts/hook-and-skill.sh"}
]}]}}
EOF

put githooks/pre-commit <<'EOF'
#!/bin/sh
top=$(git rev-parse --show-toplevel) || exit 1
exec /bin/sh "$top/scripts/gitcalled.sh" "$@"
EOF

put skills/demo/SKILL.md <<'EOF'
# demo

Run `scripts/skilled.sh` by its resolved path, then `scripts/both.sh`, then
`scripts/hook-and-skill.sh`.
EOF

put mise.toml <<'EOF'
[tasks."check:devtool"]
description = "names scripts/described.sh in prose only"
run = "/bin/sh scripts/devtool.sh"

[tasks.commented]
run = '''
# /bin/sh scripts/described.sh
true
'''

[tasks.filetask]
file = "scripts/filetask.sh"
EOF

put .github/workflows/ci.yml <<'EOF'
jobs:
  build:
    steps:
      # - run: /bin/sh scripts/described.sh
      - run: /bin/sh scripts/wfonly.sh
EOF

put docs/guide.md <<'EOF'
Run `scripts/doconly.sh` by hand when you need it.
EOF

put tests/test-helper.sh <<'EOF'
#!/bin/bash
/bin/sh "$REPO_ROOT/scripts/testhelper.sh"
EOF

put scripts/hooked.sh <<'EOF'
#!/bin/sh
# Mentions in comments are not calls: scripts/commented.sh
set -u
here=$(cd "$(dirname "$0")" && pwd)
. "$here/lib.sh"
cb_fn() { :; }
helper() {
  printf '%s\n' "$1" | tr a-z A-Z
}
out=$(git rev-parse HEAD | awk '{ print $1 }') || exit 1
if command -v sed >/dev/null 2>&1; then
  helper "$out"
  lib_fn "$out"
fi
case $1 in
  bash) env -u BAR FOO=1 jq -n '1' ;;
  -h | --help) "$here/both.sh" ;;
  *) local_var=1 ;;
esac
cat <<MSG
  sort scripts/heredoc-only.sh
MSG
"$here/$1-plugin.sh" run
for f in a b; do
  wc -c "$f"
done
EOF

put scripts/lib.sh <<'EOF'
lib_fn() { grep -q x "$1"; cb_fn; }
EOF

put scripts/gitcalled.sh <<'EOF'
#!/bin/sh
exit 0
EOF

put scripts/skilled.sh <<'EOF'
#!/bin/sh
cmd=$1
eval "$cmd"
EOF

put scripts/both.sh <<'EOF'
#!/bin/sh
eval 'x=1'
lp="$(dirname "$0")/lib.sh"
. "$lp"
. "$(dirname "$0")/lib.sh"
EOF

put scripts/hook-and-skill.sh <<'EOF'
#!/bin/sh
name=$1
. "$(dirname "$0")/$name.sh"
EOF

# A `;;` ends the arm's pending eval; functions defined mid-line are not
# commands; a script handed to sh by a built name is unresolved; a heredoc
# opened on a continued line starts after the continuation.
put scripts/devtool.sh <<'EOF'
#!/bin/sh
here=$(dirname "$0")
case $1 in
  a) eval ;; b) curl "$x" ;;
esac
a() { :; }; b() { wc -l; }
b
/bin/sh "$here/$rung" stop
"$here/${pre}glued.sh" run
cat <<EOT \
  | tr a b
body-cmd
EOT
EOF

put scripts/wfonly.sh <<'EOF'
#!/bin/sh
. "${LIB:-$d/lib.sh}"
EOF

put scripts/filetask.sh <<'EOF'
#!/bin/sh
exit 0
EOF

# Interpreter options that take a value, a slashless built name, wrapper
# options that take a value (sudo -u, exec -a, time -p, a timeout duration
# held in a variable, env options in an unquoted expansion), a command run by
# find -exec, `name ()` with a
# space, a `name()` line inside a quoted string, a slashless built name, and
# a variable run as a command: unresolved unless it holds a literal path.
put scripts/interp.sh <<'EOF'
#!/bin/sh
bash -o pipefail "$d/$n"
sh "$name.sh"
sudo -u root make
x=1; bar () { :; }
bar
usage='
date() is printed
'
date
time -p gzip -c x
"${variant}.sh"
L="$d/x1.sh"
/bin/sh "$L"
"$L" go
tool=$(pick "$1")
"$tool" go
gh_t=$(pick)
timeout "$gh_t" gh pr view
opts=""
env $opts /bin/sh x
find . -type f -exec cat {} +
find . -exec /bin/sh -c 'true' {} \;
exec -a myname curl x
EOF

# Named only through a built name (`$name.sh`, `${pre}glued.sh`): not callers.
put scripts/glued.sh <<'EOF'
#!/bin/sh
exit 0
EOF

put scripts/name.sh <<'EOF'
#!/bin/sh
exit 0
EOF

put scripts/noone.sh <<'EOF'
#!/bin/sh
"$(dirname "$0")/deadlib.sh"
conf=$1
. "$conf"
EOF

put scripts/deadlib.sh <<'EOF'
#!/bin/sh
exit 0
EOF

for s in testhelper doconly described commented heredoc-only; do
  put "scripts/$s.sh" <<'EOF'
#!/bin/sh
exit 0
EOF
done

# A shell script without the suffix is in the layer; a non-shell file is not.
put scripts/no-suffix <<'EOF'
#!/usr/bin/env bash
shopt -s nullglob
EOF
ln -s lib.sh "$fx/scripts/linked.sh"
put scripts/notes.txt <<'EOF'
not a script
EOF

# The script grants mise no trust itself, so the test trusts its own trees.
export MISE_TRUSTED_CONFIG_PATHS="$tmp:$REPO_ROOT"

run_sp() { /bin/sh "$SP" --repo-root "$1" 2>"$tmp/err"; }

run_sp "$fx" >"$tmp/out1" || fail "the fixture partition failed: $(cat "$tmp/err")"

# row <path>: the output row for one script, or nothing.
row() { awk -F'\t' -v p="$1" '$1 == p' "$tmp/out1"; }

# expect <path> <tier> <flag> <callers> <mutation> <profile> <unresolved>
expect() {
  want=$(printf '%s\t%s\t%s\t%s\t%s\t%s\t%s' "$@")
  got=$(row "$1")
  [ "$got" = "$want" ] || fail "row for $1
  want: $want
  got:  $got"
}

# ---------------------------------------------------------------------------
# p0: the header names the columns, and every layer script has exactly one row.
# ---------------------------------------------------------------------------
[ "$(head -n 1 "$tmp/out1")" = "$(printf 'path\ttier\tflag\tcallers\tmutation\tprofile\tunresolved')" ] \
  || fail "p0: header is $(head -n 1 "$tmp/out1")"
want_paths=$(printf '%s\n' githooks/pre-commit scripts/both.sh scripts/commented.sh \
  scripts/deadlib.sh scripts/described.sh scripts/devtool.sh scripts/doconly.sh \
  scripts/filetask.sh scripts/gitcalled.sh scripts/glued.sh scripts/heredoc-only.sh \
  scripts/hook-and-skill.sh scripts/hooked.sh scripts/interp.sh scripts/lib.sh scripts/linked.sh \
  scripts/name.sh scripts/no-suffix scripts/noone.sh scripts/skilled.sh \
  scripts/testhelper.sh scripts/wfonly.sh)
got_paths=$(tail -n +2 "$tmp/out1" | cut -f1)
[ "$got_paths" = "$want_paths" ] || fail "p0: the layer is
$got_paths"
bad_tiers=$(tail -n +2 "$tmp/out1" | awk -F'\t' '$2 !~ /^(hook|skill-called|library|dev-check|tests-only)$/')
[ -z "$bad_tiers" ] || fail "p0: rows without exactly one tier: $bad_tiers"
echo "ok: p0 every script in the layer gets one row and one tier"

# ---------------------------------------------------------------------------
# p1: one case per tier (REQ-A1.1).
# ---------------------------------------------------------------------------
expect githooks/pre-commit hook - git - git,sh -
expect scripts/gitcalled.sh hook - githook - - -
# shellcheck disable=SC2016 # the literal text the partition reports
expect scripts/hooked.sh hook - hook - awk,cat,dirname,env,git,jq,tr,wc '$here/$1-plugin.sh'
expect scripts/skilled.sh skill-called - skill shell-mutation - -
expect scripts/lib.sh library - script - grep -
# shellcheck disable=SC2016 # the literal text the partition reports
expect scripts/devtool.sh dev-check - task - cat,curl,dirname,sh,tr,wc '$here/$rung,$here/${pre}glued.sh'
expect scripts/filetask.sh dev-check - task - - -
# shellcheck disable=SC2016 # the literal text the partition reports
expect scripts/wfonly.sh dev-check - workflow shell-mutation - '${LIB:-$d/lib.sh}'
expect scripts/testhelper.sh tests-only no-live-caller test - - -
echo "ok: p1 one script lands in each tier"

# ---------------------------------------------------------------------------
# p2: a script matching two definitions takes the first in the listed order.
# ---------------------------------------------------------------------------
expect scripts/both.sh skill-called - skill,script - dirname -
# shellcheck disable=SC2016 # the literal text the partition reports
expect scripts/hook-and-skill.sh hook - hook,skill shell-mutation dirname '$(...)/$name.sh'
echo "ok: p2 the two-definition tie-break takes the first tier"

# ---------------------------------------------------------------------------
# p3: the shell-mutation flag is set by an eval or a source of non-literal
#     text, and not by an eval of a literal or a source of a literal file.
# ---------------------------------------------------------------------------
[ "$(row scripts/skilled.sh | cut -f5)" = shell-mutation ] || fail "p3: eval of a variable not flagged"
[ "$(row scripts/hook-and-skill.sh | cut -f5)" = shell-mutation ] || fail "p3: source of a composed name not flagged"
[ "$(row scripts/both.sh | cut -f5)" = - ] || fail "p3: literal eval or literal source flagged"
[ "$(row scripts/hooked.sh | cut -f5)" = - ] || fail "p3: a literal library source flagged"
[ "$(row scripts/noone.sh | cut -f5)" = shell-mutation ] || fail "p3: source of a parameter not flagged"
row scripts/hooked.sh | cut -f6 | grep -q 'lib_fn' && fail "p3: a sourced library's function counted as a process"
echo "ok: p3 the shell-mutation flag tracks non-literal eval and source"

# ---------------------------------------------------------------------------
# p4: the five no-live-caller cases (REQ-A1.3).
# ---------------------------------------------------------------------------
# shellcheck disable=SC2016 # the literal text the partition reports
expect scripts/noone.sh tests-only no-live-caller - shell-mutation dirname '$conf'
expect scripts/deadlib.sh library no-live-caller script - - -
expect scripts/doconly.sh tests-only no-live-caller - - - -
# Mentions that are not calls: a task description, a commented-out run line, a
# commented-out workflow step, a script comment, and a heredoc body.
expect scripts/described.sh tests-only no-live-caller - - - -
expect scripts/commented.sh tests-only no-live-caller - - - -
expect scripts/heredoc-only.sh tests-only no-live-caller - - - -
expect scripts/no-suffix tests-only no-live-caller - - shopt -
expect scripts/name.sh tests-only no-live-caller - - - -
expect scripts/glued.sh tests-only no-live-caller - - - -
# shellcheck disable=SC2016 # the literal text the partition reports
expect scripts/interp.sh tests-only no-live-caller - - bash,cat,curl,date,env,find,gh,gzip,make,pick,sh,sudo,timeout '$d/$n,$name.sh,$tool,${variant}.sh'
# A symlink is in the layer as the file it names.
expect scripts/linked.sh tests-only no-live-caller - - cb_fn,grep -
echo "ok: p4 no caller, a library reachable only from a flagged script, a test-only helper, and a docs-only script are flagged"

# ---------------------------------------------------------------------------
# p5: the flag clears on the same script once a task names it.
# ---------------------------------------------------------------------------
cp -R "$fx" "$tmp/fx2"
cat >>"$tmp/fx2/mise.toml" <<'EOF'

[tasks."tool:doconly"]
run = "/bin/sh scripts/doconly.sh"
EOF
run_sp "$tmp/fx2" >"$tmp/out2" || fail "p5: the second fixture failed: $(cat "$tmp/err")"
got=$(awk -F'\t' '$1 == "scripts/doconly.sh"' "$tmp/out2")
[ "$got" = "$(printf 'scripts/doconly.sh\tdev-check\t-\ttask\t-\t-\t-')" ] \
  || fail "p5: the flag did not clear once a task named the script: $got"
echo "ok: p5 a task naming the script clears its flag"

# ---------------------------------------------------------------------------
# p6: two runs are byte-identical.
# ---------------------------------------------------------------------------
run_sp "$fx" >"$tmp/out3" || fail "p6: the second run failed: $(cat "$tmp/err")"
cmp -s "$tmp/out1" "$tmp/out3" || fail "p6: two runs over the same tree differ"
echo "ok: p6 two runs produce byte-identical output"

# ---------------------------------------------------------------------------
# p7: fails closed on a tree that would make the scan vacuous.
# ---------------------------------------------------------------------------
cp -R "$fx" "$tmp/fx3"
rm "$tmp/fx3/mise.toml"
rc=0
run_sp "$tmp/fx3" >/dev/null || rc=$?
[ "$rc" = 5 ] || fail "p7: a tree without mise.toml exited $rc, want 5"
cp -R "$fx" "$tmp/fx4"
printf '{not json' >"$tmp/fx4/hooks/hooks.json"
rc=0
run_sp "$tmp/fx4" >/dev/null || rc=$?
[ "$rc" = 5 ] || fail "p7: an unparseable hook registration exited $rc, want 5"
rc=0
/bin/sh "$SP" --bogus >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "p7: an unknown argument exited $rc, want 2"
cp -R "$fx" "$tmp/fx6"
printf '{}\n' >"$tmp/fx6/hooks/hooks.json"
rc=0
run_sp "$tmp/fx6" >/dev/null || rc=$?
[ "$rc" = 5 ] || fail "p7: a hook registration with no command exited $rc, want 5"
if [ "$(id -u)" != 0 ]; then
  cp -R "$fx" "$tmp/fx7"
  chmod 000 "$tmp/fx7/skills/demo/SKILL.md"
  rc=0
  run_sp "$tmp/fx7" >/dev/null || rc=$?
  chmod 644 "$tmp/fx7/skills/demo/SKILL.md"
  [ "$rc" = 5 ] || fail "p7: an unreadable skill body exited $rc, want 5"
fi
rc=0
/bin/sh "$SP" --repo-root "" >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "p7: an empty --repo-root exited $rc, want 2"
cp -R "$fx" "$tmp/fx8"
mkdir -p "$tmp/fx8/scripts/sub"
cp "$fx/scripts/devtool.sh" "$tmp/fx8/scripts/sub/devtool.sh"
rc=0
run_sp "$tmp/fx8" >/dev/null || rc=$?
[ "$rc" = 5 ] || fail "p7: a duplicate script file name exited $rc, want 5"
cp -R "$fx" "$tmp/fx9"
rm "$tmp/fx9/.github/workflows/ci.yml"
rc=0
run_sp "$tmp/fx9" >/dev/null || rc=$?
[ "$rc" = 5 ] || fail "p7: a workflows directory with no workflow exited $rc, want 5"
cp -R "$fx" "$tmp/fx10"
: >"$tmp/fx10/hooks/hooks.json"
mkdir -p "$tmp/fx10/config"
printf '%s\n' '{"hooks": {"Stop": [{"hooks": [{"type": "command", "command": "scripts/gitcalled.sh"}]}]}}' \
  >"$tmp/fx10/config/worker-settings.json"
rc=0
run_sp "$tmp/fx10" >/dev/null || rc=$?
[ "$rc" = 5 ] || fail "p7: an empty hooks.json beside a live settings fragment exited $rc, want 5"
echo "ok: p7 fails closed on a missing task file, an unreadable or empty hook registration, an unreadable skill body, a duplicate name, no workflow, and an empty root"

# ---------------------------------------------------------------------------
# p8: the repository's own partition runs, and places the script itself in
#     the dev-check tier through its on-demand task.
# ---------------------------------------------------------------------------
run_sp "$REPO_ROOT" >"$tmp/real" || fail "p8: the real partition failed: $(cat "$tmp/err")"
self=$(awk -F'\t' '$1 == "scripts/substrate-partition.sh" { print $2 "\t" $3 }' "$tmp/real")
[ "$self" = "$(printf 'dev-check\t-')" ] || fail "p8: the script's own row is '$self'"
echo "ok: p8 the repository partitions and the script sits in the dev-check tier"

# ---------------------------------------------------------------------------
# p9: a control byte in an unresolved invocation never reaches the output.
# ---------------------------------------------------------------------------
cp -R "$fx" "$tmp/fx5"
# shellcheck disable=SC2016 # the planted script text, not an expansion
printf '#!/bin/sh\n"$(dirname "$0")/$x\033[2J.sh"\n' >"$tmp/fx5/scripts/ctl.sh"
run_sp "$tmp/fx5" >"$tmp/out5" || fail "p9: the partition failed: $(cat "$tmp/err")"
LC_ALL=C grep -q "$(printf '\033')" "$tmp/out5" && fail "p9: a control byte reached the output"
grep -q 'scripts/ctl.sh' "$tmp/out5" || fail "p9: the planted script has no row"
echo "ok: p9 control bytes in file-derived text are replaced"

# ---------------------------------------------------------------------------
# p10: a root reached through a symlink partitions the same as its real path.
# ---------------------------------------------------------------------------
ln -s "$fx" "$tmp/link"
run_sp "$tmp/link" >"$tmp/out6" || fail "p10: a symlinked root failed: $(cat "$tmp/err")"
cmp -s "$tmp/out1" "$tmp/out6" || fail "p10: a symlinked root partitions differently"
echo "ok: p10 a symlinked root gives the same partition"

# ---------------------------------------------------------------------------
# p11: a machine-local mise overlay redefining a task does not hide the
#      tracked task's caller.
# ---------------------------------------------------------------------------
cp -R "$fx" "$tmp/fx11"
cat >"$tmp/fx11/mise.local.toml" <<'EOF'
[tasks."check:devtool"]
run = "true"
EOF
run_sp "$tmp/fx11" >"$tmp/out11" || fail "p11: the partition failed: $(cat "$tmp/err")"
got=$(awk -F'\t' '$1 == "scripts/devtool.sh" { print $2 "\t" $3 "\t" $4 }' "$tmp/out11")
[ "$got" = "$(printf 'dev-check\t-\ttask')" ] || fail "p11: a local overlay hid the tracked task: $got"
echo "ok: p11 a machine-local overlay does not hide a tracked task"
