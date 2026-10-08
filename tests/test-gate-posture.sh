#!/bin/bash
# The execution freshness gate's read surface in each posture of the spec root
# (custom-spec-location REQ-E1.5, D-14): scripts/dispatch-fetch.sh --spec
# computes the anchor the gate compares against from the bundle's primary view,
# the default branch's committed view of the work repository in same-repo and
# of the holder in separate-repo, and the directory's files in plain. The
# default branch is the remote's HEAD branch where a remote exists, else the
# branch the primary checkout's HEAD names, never assumed to be `main`.
#
# The gate halts when the recomputed anchor differs from the brief's recorded
# one and passes when they match, so each case compares the printed anchor
# against the anchor recorded at fixture time.
set -u
unset CDPATH
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY \
  GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
S="$REPO_ROOT/scripts"
TAB=$(printf '\t')

failures=0
ok() { echo "ok: $1"; }
fail() {
  printf 'FAIL: %s\n' "$1" | tr -d '\000-\010\013-\037\177' >&2
  failures=$((failures + 1))
}

tmp=$(mktemp -d "${TMPDIR:-/tmp}/gate-posture.XXXXXX") || exit 1
tmp=$(cd "$tmp" && pwd -P) || exit 1
trap 'rm -rf "$tmp"' EXIT

inherited_unsets=$(env | sed -n 's/^\(PLANWRIGHT_[A-Za-z0-9_]*\)=.*/-u \1/p')
mkdir -p "$tmp/home"
hermetic() {
  # shellcheck disable=SC2086 # one `-u NAME` pair per word
  env $inherited_unsets -u CLAUDE_PLUGIN_ROOT -u CLAUDE_PLUGIN_DATA -u CLAUDE_DIR \
    HOME="$tmp/home" GIT_CEILING_DIRECTORIES="$tmp" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 \
    GIT_AUTHOR_NAME=fixture GIT_AUTHOR_EMAIL=fixture@example.invalid \
    GIT_COMMITTER_NAME=fixture GIT_COMMITTER_EMAIL=fixture@example.invalid \
    PLANWRIGHT_ROOT="$REPO_ROOT" PLANWRIGHT_DISPATCH_FETCH_RETRIES=0 \
    PLANWRIGHT_DISPATCH_FETCH_RETRY_SLEEP=0 "$@"
}
gitq() { hermetic git "$@" >/dev/null 2>&1; }

# gate <dir> [<args>...] — dispatch-fetch --spec demo, run from <dir> against
# <dir>, with its own TTL state; sets out and rc.
gate() {
  g_dir=$1
  shift
  out=$(cd "$g_dir" && hermetic env PLANWRIGHT_DISPATCH_FETCH_STATE_DIR="$tmp/state.$$.$RANDOM" \
    "$S/dispatch-fetch.sh" --spec demo "$@" . 2>&1)
  rc=$?
}
field() { printf '%s\n' "$out" | awk -F"$TAB" -v t="$1" -v c="$2" '$1==t {print $c; exit}'; }

# make_bundle <dir> <marker> — the four files and a brief; <marker> sits in
# anchored content, so changing it changes the anchor.
make_bundle() {
  mkdir -p "$1"
  printf '# Demo — Requirements\n\n**Status:** Ready\n**Format-version:** 2\n\n## Goal\n\n%s\n' "$2" >"$1/requirements.md"
  printf '# Demo — Design\n\n%s\n' "$2" >"$1/design.md"
  printf '# Demo — Test spec\n\n%s\n' "$2" >"$1/test-spec.md"
  cat >"$1/tasks.md" <<'EOF'
# Demo — Tasks

**Status:** Ready
**Format-version:** 2

## Tasks

### Task 1 — the unit

- **Deliverables:** a thing
- **Done when:** the thing exists
- **Dependencies:** none
- **Citations:** D-1 · REQ-A1.1
- **Estimated effort:** 1 day
EOF
  printf '# Demo — Kickoff brief\n' >"$1/kickoff-brief.md"
}
anchor_of() { hermetic "$S/spec-anchor.sh" "$1"; }

# expect_gate <label> <want-ref> <want: match|mismatch> <recorded>
expect_gate() {
  eg_ref=$(field anchor 3)
  eg_hash=$(field anchor 2)
  if [ "$eg_ref" != "$2" ]; then
    fail "$1: anchor read at '$eg_ref', expected '$2' (rc=$rc): $out"
    return
  fi
  if [ "$3" = match ] && [ "$eg_hash" = "$4" ]; then
    ok "$1: passes on a match at $2"
  elif [ "$3" = mismatch ] && [ -n "$eg_hash" ] && [ "$eg_hash" != "$4" ]; then
    ok "$1: halts on a mismatch at $2"
  else
    fail "$1: expected a $3 at $2 against the recorded anchor: $out"
  fi
}

# set_root <work> <value> — spec_root in the work repository's machine-local
# layer.
set_root() {
  mkdir -p "$1/.claude"
  printf 'spec_root: %s\n' "$2" >"$1/.claude/planwright.local.yml"
}
mark_root() { printf 'project: fixture\nlayout: 1\n' >"$1/planwright-spec-root.yml"; }
commit_all() { gitq -C "$1" add -A && gitq -C "$1" commit -q -m "$2"; }

# --- same-repo: a remote whose HEAD branch is `trunk` --------------------------
gitq -c init.defaultBranch=trunk init -q --bare "$tmp/same/origin.git"
gitq clone -q "$tmp/same/origin.git" "$tmp/same/work"
w=$tmp/same/work
gitq -C "$w" checkout -q -b trunk
make_bundle "$w/specs/demo" v1
commit_all "$w" "spec v1"
gitq -C "$w" push -q origin trunk
gitq -C "$w" remote set-head origin trunk
recorded=$(anchor_of "$w/specs/demo")
gitq -C "$w" worktree add -q "$w/.claude/worktrees/wt" -b wt

gate "$w"
[ "$rc" -eq 0 ] || fail "same-repo: the gate exited $rc: $out"
expect_gate "same-repo" origin/trunk match "$recorded"
gate "$w/.claude/worktrees/wt"
expect_gate "same-repo, from a linked worktree" origin/trunk match "$recorded"

# A worker's own uncommitted copy is not the read surface.
printf 'edited\n' >>"$w/.claude/worktrees/wt/specs/demo/requirements.md"
gate "$w"
expect_gate "same-repo, a worktree's uncommitted edit" origin/trunk match "$recorded"

# A re-anchor pushed by another clone moves the default branch's view.
gitq clone -q "$tmp/same/origin.git" "$tmp/same/other"
make_bundle "$tmp/same/other/specs/demo" v2
commit_all "$tmp/same/other" "spec v2"
gitq -C "$tmp/same/other" push -q origin trunk
gate "$w"
expect_gate "same-repo, an edit on the remote default branch" origin/trunk mismatch "$recorded"

# With no recorded remote HEAD, the fetch learns it from the remote.
gitq -c init.defaultBranch=main init -q "$tmp/same/learn"
gitq -C "$tmp/same/learn" remote add origin "$tmp/same/origin.git"
gitq -C "$tmp/same/learn" fetch -q origin
gitq -C "$tmp/same/learn" checkout -q -b trunk origin/trunk
v2=$(anchor_of "$tmp/same/learn/specs/demo")
gitq -C "$tmp/same/learn" checkout -q -b feature
gate "$tmp/same/learn"
expect_gate "same-repo, a remote HEAD learned at fetch" origin/trunk match "$v2"

# A remote whose HEAD names no pushed branch leaves the gate on the primary
# checkout's branch, and it says so rather than guess silently.
gitq -c init.defaultBranch=master init -q --bare "$tmp/same/dangle.git"
gitq -c init.defaultBranch=main init -q "$tmp/same/dangle"
make_bundle "$tmp/same/dangle/specs/demo" v1
commit_all "$tmp/same/dangle" "spec v1"
gitq -C "$tmp/same/dangle" remote add origin "$tmp/same/dangle.git"
gitq -C "$tmp/same/dangle" push -q origin main
gitq -C "$tmp/same/dangle" checkout -q -b feature
gitq -C "$tmp/same/dangle" push -q origin feature
gate "$tmp/same/dangle"
case $rc:$out in
  0:*"records no HEAD"*"feature"*) expect_gate "same-repo, a remote HEAD that names no branch" origin/feature match "$recorded" ;;
  *) fail "same-repo, a remote HEAD that names no branch: no fallback note (rc=$rc): $out" ;;
esac

# No remote: the branch the primary checkout's HEAD names.
gitq -c init.defaultBranch=trunk init -q "$tmp/same/solo"
make_bundle "$tmp/same/solo/specs/demo" v1
commit_all "$tmp/same/solo" "spec v1"
gate "$tmp/same/solo"
[ "$rc" -eq 3 ] || fail "same-repo, no remote: expected the offline exit 3, got $rc: $out"
expect_gate "same-repo, no remote" trunk match "$recorded"

# --- separate-repo: a holder whose default branch is `trunk` -------------------
gitq -c init.defaultBranch=main init -q "$tmp/sep/work"
w=$tmp/sep/work
printf 'x\n' >"$w/file"
commit_all "$w" init
gitq -c init.defaultBranch=trunk init -q "$tmp/sep/holder"
h=$tmp/sep/holder
mkdir -p "$h/work-specs"
mark_root "$h/work-specs"
make_bundle "$h/work-specs/demo" v1
commit_all "$h" "spec v1"
set_root "$w" "$h/work-specs"

gate "$w"
[ "$rc" -eq 3 ] || fail "separate-repo: expected the work repository's offline exit 3, got $rc: $out"
expect_gate "separate-repo, holder without a remote" store:trunk match "$recorded"

# An uncommitted holder edit is outside the read surface; a committed one is not.
printf 'edited\n' >>"$h/work-specs/demo/design.md"
gate "$w"
expect_gate "separate-repo, an uncommitted holder edit" store:trunk match "$recorded"
commit_all "$h" "spec edited"
gate "$w"
expect_gate "separate-repo, a committed holder edit" store:trunk mismatch "$recorded"
gitq -C "$h" reset -q --hard HEAD~1

# A holder on a feature branch still reads its default branch's view when it
# has a remote; the fetch refreshes the remote view, never the local branch.
gitq -c init.defaultBranch=trunk init -q --bare "$tmp/sep/holder-origin.git"
gitq -C "$h" remote add origin "$tmp/sep/holder-origin.git"
gitq -C "$h" push -q origin trunk
gitq clone -q "$tmp/sep/holder-origin.git" "$tmp/sep/holder-other"
make_bundle "$tmp/sep/holder-other/work-specs/demo" v2
commit_all "$tmp/sep/holder-other" "spec v2"
gitq -C "$tmp/sep/holder-other" push -q origin trunk
gitq -C "$h" checkout -q -b feature
holder_trunk=$(hermetic git -C "$h" rev-parse trunk)
gate "$w"
expect_gate "separate-repo, an edit on the holder's remote default branch" store:origin/trunk mismatch "$recorded"
[ "$(field store-fetch 2)" = fetched ] || fail "separate-repo: the holder fetch was not reported: $out"
if [ "$(hermetic git -C "$h" rev-parse trunk)" = "$holder_trunk" ]; then
  ok "separate-repo: the holder's local default branch is not advanced"
else
  fail "separate-repo: the holder's local trunk moved"
fi

# A holder fetch that fails is never a silent stale gate.
gitq -C "$h" remote set-url origin "$tmp/sep/missing.git"
gate "$w"
if [ "$rc" -eq 4 ] && [ -z "$(field anchor 2)" ] && [ "$(field store-fetch 2)" = stale-transient ]; then
  ok "separate-repo: a failed holder fetch parks with no anchor"
else
  fail "separate-repo: a failed holder fetch (rc=$rc): $out"
fi

# A holder whose top level git cannot name (a root inside a bare repository)
# is refused outright, never read or fetched as the caller's own repository.
gitq -c init.defaultBranch=main init -q --bare "$tmp/sep/bare-origin.git"
gitq -C "$w" remote add origin "$tmp/sep/bare-origin.git"
gitq -C "$w" push -q origin main
gitq -c init.defaultBranch=trunk init -q --bare "$tmp/sep/bare.git"
mark_root_dir=$tmp/sep/bare.git/specs
mkdir -p "$mark_root_dir"
mark_root "$mark_root_dir"
make_bundle "$mark_root_dir/demo" v1
set_root "$w" "$mark_root_dir"
gate "$w"
if [ "$rc" -eq 2 ] && [ -z "$(field store-fetch 2)" ] && [ -z "$(field anchor 2)" ]; then
  ok "separate-repo: a holder with no resolvable top level is refused"
else
  fail "separate-repo: a bare holder (rc=$rc): $out"
fi

# With a remote-backed work repository the gate exits 0, and a success exit
# still carries the holder's anchor; within the work repository's TTL the
# holder is fetched again, never coalesced.
gitq -C "$h" remote set-url origin "$tmp/sep/holder-origin.git"
set_root "$w" "$h/work-specs"
ttl_state=$tmp/state.sep-ttl
for pass in fetched fresh-within-ttl; do
  out=$(cd "$w" && hermetic env PLANWRIGHT_DISPATCH_FETCH_STATE_DIR="$ttl_state" \
    "$S/dispatch-fetch.sh" --spec demo . 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ] && [ "$(field fetch 2)" = "$pass" ] && [ "$(field store-fetch 2)" = fetched ]; then
    expect_gate "separate-repo, a remote-backed work repository ($pass)" store:origin/trunk mismatch "$recorded"
  else
    fail "separate-repo, a remote-backed work repository ($pass, rc=$rc): $out"
  fi
done

# --- plain: the directory's files as they are --------------------------------
gitq -c init.defaultBranch=main init -q "$tmp/plain/work"
w=$tmp/plain/work
printf 'x\n' >"$w/file"
commit_all "$w" init
p=$tmp/plain/store
mkdir -p "$p"
mark_root "$p"
make_bundle "$p/demo" v1
set_root "$w" "$p"
gate "$w"
[ "$rc" -eq 3 ] || fail "plain: expected the work repository's offline exit 3, got $rc: $out"
expect_gate "plain" files match "$recorded"
printf 'edited\n' >>"$p/demo/test-spec.md"
gate "$w"
expect_gate "plain, an edited file" files mismatch "$recorded"
gitq -c init.defaultBranch=main init -q --bare "$tmp/plain/origin.git"
gitq -C "$w" remote add origin "$tmp/plain/origin.git"
gitq -C "$w" push -q origin main
gate "$w"
if [ "$rc" -eq 0 ]; then
  expect_gate "plain, a remote-backed work repository" files mismatch "$recorded"
else
  fail "plain, a remote-backed work repository (rc=$rc): $out"
fi
rm -f "$p/demo/tasks.md"
gate "$w"
if [ "$rc" -eq 5 ] && [ -z "$(field anchor 2)" ]; then
  ok "plain: a bundle that cannot be anchored parks"
else
  fail "plain: an unanchorable bundle (rc=$rc): $out"
fi

if [ "$failures" -ne 0 ]; then
  echo "FAIL: test-gate-posture.sh ($failures failure(s))" >&2
  exit 1
fi
echo "PASS: test-gate-posture.sh"
