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

put scripts/devtool.sh <<'EOF'
#!/bin/sh
exit 0
EOF

put scripts/wfonly.sh <<'EOF'
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
exit 0
EOF
put scripts/notes.txt <<'EOF'
not a script
EOF

export MISE_TRUSTED_CONFIG_PATHS="$tmp"

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
  scripts/gitcalled.sh scripts/heredoc-only.sh scripts/hook-and-skill.sh scripts/hooked.sh \
  scripts/lib.sh scripts/no-suffix scripts/noone.sh scripts/skilled.sh \
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
expect scripts/devtool.sh dev-check - task - - -
expect scripts/wfonly.sh dev-check - workflow - - -
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
expect scripts/no-suffix tests-only no-live-caller - - - -
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
echo "ok: p7 fails closed on a missing task file or an unreadable hook registration"

# ---------------------------------------------------------------------------
# p8: the repository's own partition runs, and places the script itself in
#     the dev-check tier through its on-demand task.
# ---------------------------------------------------------------------------
run_sp "$REPO_ROOT" >"$tmp/real" || fail "p8: the real partition failed: $(cat "$tmp/err")"
self=$(awk -F'\t' '$1 == "scripts/substrate-partition.sh" { print $2 "\t" $3 }' "$tmp/real")
[ "$self" = "$(printf 'dev-check\t-')" ] || fail "p8: the script's own row is '$self'"
echo "ok: p8 the repository partitions and the script sits in the dev-check tier"
