#!/bin/bash
# Tests for the worker command guard's scratch arm (REQ-F1.4): writes whose
# every target canonicalizes inside the scratch root the session record names,
# a literal `$TMPDIR` resolving to that root and to nothing else, and nothing
# executed or sourced from there; plus the record's scratch field (REQ-G1.2,
# REQ-B1.8). The rows run in the corpus sandbox (tests/lib/
# worker-guard-corpus.sh) with the hook's TMPDIR set to the scratch root, as
# the launcher exports it; a hook whose TMPDIR names anything else gets no
# scratch arm, since that is what the shell would expand.
set -u
unset CDPATH
# shellcheck source=tests/lib/worker-command-guard-harness.sh
. "$(cd "$(dirname "$0")" && pwd)/lib/worker-command-guard-harness.sh"
# shellcheck source=tests/lib/worker-guard-corpus.sh
. "$REPO_ROOT/tests/lib/worker-guard-corpus.sh"

corpus_sandbox "$SANDBOX/box" "$REPO_ROOT" || {
  echo "FAIL: could not build the corpus sandbox" >&2
  exit 1
}
WT=$CORPUS_WORKTREE
SC=$CORPUS_SCRATCH
OUT_DIR=$CORPUS_OUTSIDE
STATE=$CORPUS_BOX/state
GIT_ISO=("GIT_CONFIG_GLOBAL=/dev/null" "GIT_CONFIG_NOSYSTEM=1")
mkdir -p "$SC/work" "$SC/d"
: >"$SC/hard"
ln "$SC/hard" "$SC/hard.2"

under() {
  HOOK_ENV=("${GIT_ISO[@]}" "TMPDIR=${2-$SC}" "PLANWRIGHT_WORKER_SESSION_RECORD=$1")
}
# record_with <name> <policy> [<field=value>...]: the both-arms record with
# the policy replaced and the named fields replaced or (empty value) dropped.
record_with() {
  local f=$STATE/$1.record kv k
  shift
  {
    printf 'policy=%s\n' "$1"
    shift
    grep -v '^policy=' "$STATE/record.4"
  } >"$f.tmp"
  for kv in "$@"; do
    k=${kv%%=*}
    grep -v "^$k=" "$f.tmp" >"$f.tmp2"
    [ -z "${kv#*=}" ] || printf '%s\n' "$kv" >>"$f.tmp2"
    mv "$f.tmp2" "$f.tmp"
  done
  mv "$f.tmp" "$f"
  printf '%s\n' "$f"
}
SCR=$(record_with sc scratch)

echo "### REQ-F1.4 — the scratch arm approves writes inside the scratch root"
under "$SCR"
assert_allow "F1.4: mkdir -p of a literal scratch path" "mkdir -p $SC/x" Bash "$WT"
assert_allow "F1.4: mkdir -p through \$TMPDIR" "mkdir -p \$TMPDIR/x" Bash "$WT"
assert_allow "F1.4: mkdir -p through \${TMPDIR}" "mkdir -p \${TMPDIR}/x/y" Bash "$WT"
assert_allow "F1.4: a quoted \$TMPDIR" "touch \"\$TMPDIR/q\"" Bash "$WT"
assert_allow "F1.4: a write-redirect with 2>&1" "grep -n x f > $SC/out.log 2>&1" Bash "$WT"
assert_allow "F1.4: a redirect through \$TMPDIR" "printf 'x\\n' > \$TMPDIR/msg.txt" Bash "$WT"
assert_allow "F1.4: an appending redirect through \${TMPDIR}" "echo x >> \${TMPDIR}/log" Bash "$WT"
assert_allow "F1.4: rm -r of a scratch directory" "rm -r $SC/work" Bash "$WT"
assert_allow "F1.4: rm -rf through \$TMPDIR" "rm -rf \$TMPDIR/work" Bash "$WT"
assert_allow "F1.4: touch" "touch $SC/marker" Bash "$WT"
assert_allow "F1.4: tee" "grep -n x f | tee \$TMPDIR/out.txt" Bash "$WT"
assert_allow "F1.4: cp from the worktree into the root" "cp f \$TMPDIR/f.copy" Bash "$WT"
assert_allow "F1.4: cp within the root" "cp \$TMPDIR/f.orig \$TMPDIR/f.2" Bash "$WT"
assert_allow "F1.4: cp -r within the root" "cp -r \$TMPDIR/d \$TMPDIR/d2" Bash "$WT"
assert_allow "F1.4: mv within the root" "mv \$TMPDIR/a \$TMPDIR/b" Bash "$WT"
assert_allow "F1.4: mktemp with no template" "mktemp" Bash "$WT"
assert_allow "F1.4: mktemp -d" "mktemp -d" Bash "$WT"
assert_allow "F1.4: mktemp -dq" "mktemp -dq" Bash "$WT"
assert_allow "F1.4: mktemp of a template in the root" "mktemp \"\$TMPDIR/gw.XXXXXX\"" Bash "$WT"
assert_allow "F1.4: mktemp -d of a literal template" "mktemp -d $SC/t.XXXXXX" Bash "$WT"
assert_allow "F1.4: a read through \$TMPDIR" "grep -n x \$TMPDIR/f.orig" Bash "$WT"
assert_allow "F1.4: from a payload directory outside the worktree" "touch $SC/y" Bash "$OUT_DIR"
assert_allow "F1.4: a write, then a read of it" "grep -n x f > \$TMPDIR/o && wc -l \$TMPDIR/o" Bash "$WT"
assert_allow "F1.4: a redirect through a tracked variable" "d=$SC && echo x > \$d/o" Bash "$WT"

echo "### REQ-F1.4 — what the arm still defers"
assert_defer "F1.4: a write to /tmp outside the root" "mkdir -p /tmp/other" Bash "$WT"
assert_defer "F1.4: a redirect outside the root" "echo x > $OUT_DIR/x" Bash "$WT"
assert_defer "F1.4: a symlink in the root pointing outside" "touch \$TMPDIR/escape/x" Bash "$WT"
assert_defer "F1.4: a redirect through the symlink" "echo x > $SC/escape/x" Bash "$WT"
assert_defer "F1.4: rm of the symlink's target tree" "rm -rf $SC/escape/" Bash "$WT"
assert_defer "F1.4: a .. component" "touch \$TMPDIR/../outside/x" Bash "$WT"
assert_defer "F1.4: the root itself" "rm -rf \$TMPDIR" Bash "$WT"
assert_defer "F1.4: cp -l from outside" "cp -l $OUT_DIR/x $SC/x" Bash "$WT"
assert_defer "F1.4: cp -s" "cp -s f \$TMPDIR/x" Bash "$WT"
assert_defer "F1.4: cp -a" "cp -a f \$TMPDIR/x" Bash "$WT"
assert_defer "F1.4: ln -s" "ln -s f \$TMPDIR/l" Bash "$WT"
assert_defer "F1.4: cp from outside both" "cp $OUT_DIR/x \$TMPDIR/x" Bash "$WT"
assert_defer "F1.4: a write to a file with a second hard link" "echo x >> \$TMPDIR/hard" Bash "$WT"
assert_defer "F1.4: mv out of the root needs own-branch" "mv \$TMPDIR/f.orig f" Bash "$WT"
assert_defer "F1.4: mv into the root of a worktree file needs own-branch" "mv g \$TMPDIR/g" Bash "$WT"
assert_defer "F1.4: a worktree write" "touch build/x" Bash "$WT"
assert_defer "F1.4: a write after a recursive copy" "cp -r \$TMPDIR/d \$TMPDIR/d3 && touch \$TMPDIR/d3/x" Bash "$WT"
assert_defer "F1.4: bash of a scratch script" "bash $SC/x.sh" Bash "$WT"
assert_defer "F1.4: bash of a scratch script through \$TMPDIR" "bash \$TMPDIR/run.sh" Bash "$WT"
assert_defer "F1.4: sh of a scratch script" "sh $SC/x.sh" Bash "$WT"
assert_defer "F1.4: sourcing a scratch file" ". $SC/x.sh" Bash "$WT"
assert_defer "F1.4: sourcing through \$TMPDIR" "source \$TMPDIR/env.sh" Bash "$WT"
assert_defer "F1.4: running a scratch file as the verb" "$SC/x.sh" Bash "$WT"
assert_defer "F1.4: running it through \$TMPDIR" "\$TMPDIR/x.sh" Bash "$WT"
assert_defer "F1.4: bats of a scratch file" "bats $SC/x.sh" Bash "$WT"
assert_defer "F1.4: an assignment cannot re-point TMPDIR" "TMPDIR=$OUT_DIR && touch \$TMPDIR/x" Bash "$WT"
assert_defer "F1.4: nor can a prefix assignment" "TMPDIR=$OUT_DIR touch \$TMPDIR/x" Bash "$WT"
assert_defer "F1.4: a \${TMPDIR} modifier is not the root" "touch \${TMPDIR:-/tmp}/x" Bash "$WT"
assert_defer "F1.4: an escaped \$TMPDIR is literal text" "touch \\\$TMPDIR/x" Bash "$WT"
assert_defer "F1.4: a single-quoted \$TMPDIR is literal text" "touch '\$TMPDIR/x'" Bash "$WT"
assert_defer "F1.4: mktemp -p picks another directory" "mktemp -p $OUT_DIR" Bash "$WT"
assert_defer "F1.4: mktemp --tmpdir" "mktemp --tmpdir=$OUT_DIR" Bash "$WT"
assert_defer "F1.4: mktemp -t" "mktemp -t x.XXXXXX" Bash "$WT"
assert_defer "F1.4: mktemp -u" "mktemp -u" Bash "$WT"
assert_defer "F1.4: mktemp of a template outside the root" "mktemp $OUT_DIR/x.XXXXXX" Bash "$WT"
assert_defer "F1.4: mktemp of a relative template (the working directory)" "mktemp x.XXXXXX" Bash "$WT"
assert_defer "F1.4: mktemp of two templates" "mktemp \$TMPDIR/a.XXXXXX \$TMPDIR/b.XXXXXX" Bash "$WT"
assert_defer "F1.4: a write inside a substitution" "echo \$(touch \$TMPDIR/x)" Bash "$WT"
assert_defer "F1.4: a write inside fish -c" "fish -c 'touch $SC/x'" Bash "$WT"
assert_defer "F1.4: sed -i is not a scratch writer" "sed -i s/a/b/ \$TMPDIR/f.orig" Bash "$WT"
assert_defer "F1.4: a redirect on an assignment takes the new value" "X=$SC/ok; X=$OUT_DIR/x >\$X" Bash "$WT"
assert_defer "F1.4: a tracked variable naming outside the root" "d=/tmp && echo x > \$d/o" Bash "$WT"
assert_defer "F1.4: a tracked value holding a space stays unresolved" "d='$SC/a b' && echo x > \$d" Bash "$WT"
assert_defer "F1.4: no .git under the root" "mkdir -p \$TMPDIR/r/.git" Bash "$WT"
assert_defer "F1.4: no mise config under the root" "echo x > \$TMPDIR/mise.toml" Bash "$WT"
assert_defer "F1.4: no lefthook config under the root" "touch \$TMPDIR/r/lefthook.yml" Bash "$WT"
assert_allow "F1.4: a bare assignment beside a redirect through another variable" "X=$SC/o; Y=1 >\$X" Bash "$WT"
mkdir -p "$SC/gd/.git"
assert_defer "F1.4: a move of a tree holding .git" "mv \$TMPDIR/gd \$TMPDIR/gd2" Bash "$WT"
assert_defer "F1.4: a recursive copy of a tree holding .git" "cp -r \$TMPDIR/gd \$TMPDIR/gd3" Bash "$WT"
assert_allow "F1.4: removing that tree stays approvable" "rm -rf \$TMPDIR/gd" Bash "$WT"

echo "### REQ-F1.4 — the shell's TMPDIR must be the recorded root"
ln -s "$SC" "$CORPUS_BOX/scratch.link"
under "$SCR" "$CORPUS_BOX/hook-tmp"
assert_defer "F1.4: a hook TMPDIR naming another directory leaves no scratch arm" "touch $SC/x" Bash "$WT"
assert_defer "F1.4: nor a \$TMPDIR resolution" "touch \$TMPDIR/x" Bash "$WT"
assert_defer "F1.4: nor mktemp" "mktemp" Bash "$WT"
assert_defer "F1.4: nor a write to the hook's own TMPDIR" "touch $CORPUS_BOX/hook-tmp/x" Bash "$WT"
under "$SCR" ""
assert_defer "F1.4: an empty hook TMPDIR leaves no scratch arm" "mktemp -d" Bash "$WT"
under "$SCR" "$CORPUS_BOX/scratch.link"
assert_allow "F1.4: a hook TMPDIR reaching the root through a symlink still names it" "mktemp -d" Bash "$WT"
under "$SCR"

echo "### REQ-F1.4 — \$TMPDIR resolves only under the scratch arm"
under "$(record_with ob own-branch)"
assert_defer "F1.4: own-branch: a redirect on an assignment takes the new value" "X=$WT/build/ok; X=$OUT_DIR/x >\$X" Bash "$WT"
assert_defer "F1.4: own-branch alone leaves \$TMPDIR unresolved" "touch \$TMPDIR/x" Bash "$WT"
assert_defer "F1.4: own-branch alone leaves a literal scratch path outside" "touch $SC/x" Bash "$WT"
assert_defer "F1.4: own-branch alone approves no mktemp" "mktemp" Bash "$WT"
assert_defer "F1.4: a worktree write reached from \$TMPDIR needs the scratch arm" "cp \$TMPDIR/f.orig f" Bash "$WT"
under "$STATE/record.4"
assert_allow "F1.4: both arms: mv out of the root into the worktree" "mv \$TMPDIR/f.orig f" Bash "$WT"
assert_allow "F1.4: both arms: cp from the root into the worktree" "cp \$TMPDIR/a build/a2" Bash "$WT"
assert_allow "F1.4: both arms: a write to each zone" "touch build/x && touch \$TMPDIR/x" Bash "$WT"
assert_defer "F1.4: both arms: still never a worktree excluded path" "cp \$TMPDIR/a mise.toml" Bash "$WT"
under "$(record_with none '')"
assert_defer "F1.4: the empty policy approves no scratch write" "touch $SC/x" Bash "$WT"
assert_defer "F1.4: nor mktemp" "mktemp -d" Bash "$WT"

echo "### REQ-B1.8 / REQ-G1.2 — the scratch root comes from the record"
under "$(record_with noscr scratch scratch_root=)"
assert_defer "B1.8: no scratch root, no scratch write" "touch $SC/x" Bash "$WT"
assert_defer "B1.8: no scratch root, \$TMPDIR stays unresolved" "touch \$TMPDIR/x" Bash "$WT"
assert_allow "B1.8: the read-only arm stays in force" "grep -n x f" Bash "$WT"
under "$(record_with noscr-ob 'own-branch scratch' scratch_root=)"
assert_allow "B1.8: no scratch root leaves the own-branch arm working" "touch build/x" Bash "$WT"
under "$(record_with nowt-sc scratch worktree_root=)"
assert_allow "B1.8: no worktree root leaves the scratch arm working" "touch $SC/x" Bash "$WT"
under "$(record_with nounit-sc scratch unit_branch=)"
assert_allow "B1.8: no unit branch leaves the scratch arm working" "mkdir -p \$TMPDIR/u" Bash "$WT"
# Each bad root is also the hook's TMPDIR, so only the record's own check
# can keep the arm off.
under "$(record_with relsc scratch scratch_root=scratch)" scratch
assert_defer "B1.8: a relative scratch root is dropped" "touch \$TMPDIR/x" Bash "$WT"
assert_defer "B1.8: a relative scratch root approves no mktemp" "mktemp -d" Bash "$WT"
under "$(record_with missc scratch "scratch_root=$CORPUS_BOX/missing")" "$CORPUS_BOX/missing"
assert_defer "B1.8: a missing scratch root is dropped" "mktemp -d" Bash "$WT"
under "$(record_with linksc scratch "scratch_root=$CORPUS_BOX/scratch.link")" "$CORPUS_BOX/scratch.link"
assert_defer "B1.8: a scratch root reached through a symlink is dropped" "touch \$TMPDIR/x" Bash "$WT"
assert_defer "B1.8: a symlinked scratch root approves no mktemp" "mktemp -d" Bash "$WT"
under "$(record_with wtsc scratch "scratch_root=$WT/build")" "$WT/build"
assert_defer "B1.8: a scratch root inside the worktree is dropped" "touch \$TMPDIR/x" Bash "$WT"
assert_defer "B1.8: a scratch root inside the worktree approves no mktemp" "mktemp -d" Bash "$WT"
under "$(record_with boxsc scratch "scratch_root=$CORPUS_BOX")" "$CORPUS_BOX"
assert_defer "B1.8: a scratch root holding the worktree is dropped" "touch \$TMPDIR/x" Bash "$WT"
assert_defer "B1.8: a scratch root holding the worktree approves no mktemp" "mktemp -d" Bash "$WT"
f=$(record_with dupsc scratch)
printf 'scratch_root=%s\n' "$OUT_DIR" >>"$f"
under "$f" "$OUT_DIR"
assert_defer "B1.8: a repeated scratch root is dropped" "touch $OUT_DIR/y" Bash "$WT"
assert_defer "B1.8: a repeated scratch root approves no mktemp" "mktemp -d" Bash "$WT"
under "$f"
assert_defer "B1.8: and neither value stands" "touch $SC/y" Bash "$WT"
cp "$SCR" "$SC/inside.record"
under "$SC/inside.record"
assert_defer "G1.8: a record inside the scratch root it names is no record" "touch \$TMPDIR/x" Bash "$WT"
under "$SCR"
assert_defer "G1.2: the hook's own TMPDIR is never the scratch root" "touch $CORPUS_BOX/hook-tmp/x" Bash "$WT"

finish_suite worker-command-guard-scratch
