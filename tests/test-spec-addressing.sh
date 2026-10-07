#!/bin/bash
# Spec addressing on the identity seams (custom-spec-location REQ-D1.1,
# REQ-D1.3).
#
#   * the alias mapper (scripts/spec-id-lib.sh) on every accepted and refused
#     form;
#   * each script seam that names a spec (dispatch fetch, the two dispatchers,
#     the fence, the tower marker, the trailer helper, consume) answers the
#     bare identifier, its trailing-slash form, and the specs/<id> alias with
#     and without its slash identically, and refuses a bundle-file path;
#   * the dispatch scope keeps its field grammar: a scope naming the spec as
#     specs/<id> is refused, and the refusal names the expected shape (the
#     scope-grammar observation's reproduction);
#   * the skills that take a spec argument name the bare identifier as the
#     canonical form, and the callers of the seams pass it.
#
# The keyed forms the seams produce (branch, worktree, lock, trailer, and
# Consumed-by strings) are held byte-identical by the golden fixture
# (tests/test-spec-location-golden.sh), REQ-D1.2.
set -u
LC_ALL=C
export LC_ALL
unset CDPATH
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR

here=$(cd "$(dirname "$0")" && pwd -P)
ROOT=$(cd "$here/.." && pwd -P)
S="$ROOT/scripts"

failures=0
ok() { echo "ok: $1"; }
fail() {
  printf 'FAIL: %s\n' "$1" | tr -d '\000-\010\013-\037\177' >&2
  failures=$((failures + 1))
}

tmp=$(mktemp -d "${TMPDIR:-/tmp}/spec-addressing.XXXXXX") || exit 1
tmp=$(cd "$tmp" && pwd -P) || exit 1
trap 'rm -rf "$tmp"' EXIT

FORMS='demo demo/ specs/demo specs/demo/'
BUNDLE_FILE=specs/demo/tasks.md

# Hermetic runs: no inherited planwright variables or plugin root, fleet state
# and HOME inside the fixture, git discovery fenced at $tmp.
inherited_unsets=$(env | sed -n 's/^\(PLANWRIGHT_[A-Za-z0-9_]*\)=.*/-u \1/p')
hermetic() {
  # shellcheck disable=SC2086 # one `-u NAME` pair per word
  env $inherited_unsets -u CLAUDE_PLUGIN_ROOT -u CLAUDE_DIR -u TMUX -u TMUX_PANE \
    HOME="$tmp/home" TMUX_TMPDIR="$tmp/home" GIT_CEILING_DIRECTORIES="$tmp" \
    GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 \
    GIT_AUTHOR_NAME=fixture GIT_AUTHOR_EMAIL=fixture@example.invalid \
    GIT_COMMITTER_NAME=fixture GIT_COMMITTER_EMAIL=fixture@example.invalid \
    PLANWRIGHT_ROOT="$ROOT" PLANWRIGHT_FLEET_STATE_DIR="$tmp/fleet" "$@"
}
mkdir -p "$tmp/home" "$tmp/fleet"

# write_bundle <dir> — the demo bundle's four files in <dir>.
write_bundle() {
  mkdir -p "$1" || return 1
  printf '# Demo — Requirements\n\n**Status:** Ready\n**Format-version:** 2\n\nA fixture.\n' >"$1/requirements.md"
  printf '# Demo — Design\n\nA fixture.\n' >"$1/design.md"
  printf '# Demo — Test spec\n\nA fixture.\n' >"$1/test-spec.md"
  printf '# Demo — Tasks\n\n**Status:** Ready\n**Format-version:** 2\n\n## Tasks\n\n### Task 1 — the unit\n\n- **Deliverables:** a thing\n- **Done when:** it exists\n- **Dependencies:** none\n- **Citations:** D-1\n- **Estimated effort:** 1 day\n' >"$1/tasks.md"
}

# make_repo <dir> — a repository holding the demo bundle on main.
make_repo() {
  hermetic git -c init.defaultBranch=main init -q "$1" || return 1
  write_bundle "$1/specs/demo" || return 1
  hermetic git -C "$1" add -A && hermetic git -C "$1" commit -q -m init
}
make_repo "$tmp/repo" || {
  echo "FAIL: could not build the fixture repository" >&2
  exit 1
}

# outcome <cmd...> — the command's combined output and exit status, with the
# fixture path normalized, run from the fixture repository.
outcome() {
  (
    cd "$tmp/repo" && hermetic "$@" 2>&1
    echo "rc=$?"
  ) | sed "s|$tmp|<TMP>|g"
}

# next_n — a fresh sequence number; a file, since the seam functions run in
# command substitutions.
echo 0 >"$tmp/seq"
next_n() {
  nn=$(($(cat "$tmp/seq") + 1))
  echo "$nn" >"$tmp/seq"
  echo "$nn"
}

# seam_forms <name> <fn> [<rc>] — <fn> <form> prints one invocation's
# outcome. The bare identifier must reach exit <rc> (default 0, the answer a
# well-formed request gets from the fixture), every accepted form must answer
# exactly as it does, and the bundle-file path must be refused (an exit
# other than 0 and <rc>).
seam_forms() {
  sf_name=$1 sf_fn=$2 sf_rc=${3:-0}
  sf_want=$("$sf_fn" demo)
  case $sf_want in
    *"rc=$sf_rc") ;;
    *)
      fail "$sf_name: the bare identifier did not reach exit $sf_rc: $sf_want"
      return
      ;;
  esac
  for sf_form in $FORMS; do
    sf_got=$("$sf_fn" "$sf_form")
    if [ "$sf_got" = "$sf_want" ]; then
      ok "$sf_name: '$sf_form' answers as the bare identifier"
    else
      fail "$sf_name: '$sf_form' differs from the bare identifier: $sf_got"
    fi
  done
  sf_bad=$("$sf_fn" "$BUNDLE_FILE")
  case $sf_bad in
    *"rc=0" | *"rc=$sf_rc") fail "$sf_name: a bundle-file path was not refused: $sf_bad" ;;
    *) ok "$sf_name: a bundle-file path is refused" ;;
  esac
}

# --- The mapper --------------------------------------------------------------

# same <label> <got> <want>
same() {
  if [ "$2" = "$3" ]; then ok "$1"; else fail "$1: got '$2', want '$3'"; fi
}

# shellcheck source=scripts/spec-id-lib.sh
. "$S/spec-id-lib.sh"
canon() {
  spec_id_canon "$1"
  printf '%s' "$SPEC_ID"
}
refcanon() {
  spec_ref_canon "$1"
  printf '%s' "$SPEC_REF"
}
for f in $FORMS; do
  same "spec_id_canon: '$f' is demo" "$(canon "$f")" demo
done
for f in specs/demo/tasks.md demo/tasks.md demo// specs/demo// specs/ / '' ./specs/demo specs/specs/demo; do
  same "spec_id_canon: '$f' passes through unchanged" "$(canon "$f")" "$f"
done
same "spec_ref_canon: specs/demo/1 is demo/1" "$(refcanon specs/demo/1)" demo/1
for f in demo/1 specs/demo; do
  same "spec_ref_canon: '$f' passes through unchanged" "$(refcanon "$f")" "$f"
done
# A deeper path keeps its extra segment, which the ref grammar refuses.
same "spec_ref_canon: specs/x/y/1 keeps its depth" "$(refcanon specs/x/y/1)" x/y/1
# A trailing newline survives the mapping, so the seam's grammar still sees
# and refuses it (a command substitution would have stripped it).
nl='
'
spec_id_canon "specs/demo$nl"
same "spec_id_canon: a trailing newline survives" "$SPEC_ID" "demo$nl"
spec_ref_canon "specs/demo/1$nl"
same "spec_ref_canon: a trailing newline survives" "$SPEC_REF" "demo/1$nl"

# --- The script seams --------------------------------------------------------

fetch_form() { outcome "$S/dispatch-fetch.sh" --spec "$1" .; }
# No remote: the offline answer (exit 3) still carries the anchor.
seam_forms dispatch-fetch fetch_form 3
# The `--spec=` spelling maps the same way.
same "dispatch-fetch: --spec=specs/demo/ answers as the bare identifier" \
  "$(outcome "$S/dispatch-fetch.sh" --spec=specs/demo/ .)" "$(fetch_form demo)"
# The usage names the canonical form.
got=$(outcome "$S/dispatch-fetch.sh" --bogus)
case $got in
  *"--spec <spec>"*) ok "dispatch-fetch: usage names the bare identifier" ;;
  *) fail "dispatch-fetch: usage does not name the bare identifier: $got" ;;
esac

# The bundle's path at the ref follows the spec root the repository resolves:
# the repository root itself and a relocated root inside it answer as the
# default does, while a root no ref of this repository holds (a separate
# repository nested in the checkout, a directory outside it) is refused.
# root_repo <dir> <bundle-parent> <spec_root value> [nested] — a repository
# with the demo bundle under <bundle-parent>, marked as the configured root.
root_repo() {
  rr_d=$1 rr_p=$1/$2
  hermetic git -c init.defaultBranch=main init -q "$rr_d" || return 1
  if [ "${4:-}" = nested ]; then
    printf '%s/\n' "$2" >"$rr_d/.gitignore"
    hermetic git -c init.defaultBranch=main init -q "$rr_p" || return 1
  fi
  write_bundle "$rr_p/demo" || return 1
  printf 'project: fixture\nlayout: 1\n' >"$rr_p/planwright-spec-root.yml"
  mkdir -p "$rr_d/.claude"
  printf 'spec_root: %s\n' "$3" >"$rr_d/.claude/planwright.local.yml"
  hermetic git -C "$rr_d" add -A && hermetic git -C "$rr_d" commit -q -m init
}
root_fetch() {
  (
    cd "$1" && hermetic "$S/dispatch-fetch.sh" --spec demo . 2>&1
    echo "rc=$?"
  )
}
want=$(fetch_form demo)
root_repo "$tmp/root-top" . . || fail "dispatch-fetch: could not build the repository-root fixture"
same "dispatch-fetch: a spec root at the repository root answers as the default" \
  "$(root_fetch "$tmp/root-top")" "$want"
root_repo "$tmp/root-moved" docs/specs docs/specs || fail "dispatch-fetch: could not build the relocated-root fixture"
same "dispatch-fetch: a relocated spec root answers as the default" \
  "$(root_fetch "$tmp/root-moved")" "$want"
root_repo "$tmp/root-nested" store store nested || fail "dispatch-fetch: could not build the nested-repository fixture"
mkdir -p "$tmp/root-far"
root_repo "$tmp/root-out" ../root-far "$tmp/root-far" || fail "dispatch-fetch: could not build the outside-root fixture"
for rr in nested out; do
  case $(root_fetch "$tmp/root-$rr") in
    *"no ref of it holds the bundle"*"rc=2") ok "dispatch-fetch: a spec root this repository does not hold ($rr) is refused" ;;
    *) fail "dispatch-fetch: a spec root this repository does not hold ($rr) was not refused: $(root_fetch "$tmp/root-$rr")" ;;
  esac
done

fence_form() { outcome "$S/fleet-fence.sh" refname --spec "$1" 1; }
seam_forms fleet-fence fence_form

# The single-quoted `sh -c` bodies expand their positional arguments in the
# child shell, which is the point.
# shellcheck disable=SC2016
marker_form() {
  outcome sh -c '"$1" record "$2" --mode unattended --pid 4242 --checkout "$3" >/dev/null &&
    "$1" read "$2"; r=$?; "$1" clear "$2" >/dev/null; exit $r' \
    sh "$S/fleet-tower-marker.sh" "$1" "$tmp/repo" | sed 's/	[0-9]*$/	<EPOCH>/'
}
seam_forms fleet-tower-marker marker_form

headless_form() { outcome "$S/fleet-dispatch-headless.sh" status "$1" 1 --repo-root "$tmp/repo"; }
# A unit never launched is absent, exit 5.
seam_forms fleet-dispatch-headless headless_form 5

# Each dispatch creates its task worktree, so each form gets its own copy of
# the fixture, and the copy's path is normalized away.
dispatch_form() {
  df_r=$tmp/dispatch-$(next_n)
  cp -R "$tmp/repo" "$df_r" || return 1
  (
    cd "$df_r" && hermetic "$S/fleet-dispatch-worktree.sh" dispatch "$1" 1 --no-attach 2>&1
    echo "rc=$?"
  ) | sed -e "s|$df_r|<REPO>|g" -e 's/[0-9a-f]\{40\}/<SHA>/g'
}
seam_forms fleet-dispatch-worktree dispatch_form

# shellcheck disable=SC2016
trailer_form() {
  outcome sh -c 'printf "feat: x\n" | "$1" "$2"' sh "$S/planwright-commit-trailers.sh" "$1"
}
want=$(trailer_form demo/1)
same "planwright-commit-trailers: specs/demo/1 stamps as demo/1" "$(trailer_form specs/demo/1)" "$want"
case $want in
  *"Planwright-Task: demo/1"*"rc=0") ok "planwright-commit-trailers: the trailer form is unchanged" ;;
  *) fail "planwright-commit-trailers: unexpected trailer: $want" ;;
esac
case $(trailer_form specs/demo/requirements.md) in
  *"rc=0") fail "planwright-commit-trailers: a bundle-file path was accepted" ;;
  *) ok "planwright-commit-trailers: a bundle-file path is refused" ;;
esac

# Consume: each form consumes its own fragment and writes the same line.
consume_form() {
  cf_uid=$(printf '%08x' "$(next_n)")
  cf_o=$tmp/obs-$cf_uid
  mkdir -p "$cf_o/entries" "$cf_o/archive"
  printf -- '- 2026-01-01 [fixture] a fixture observation\n' >"$cf_o/entries/2026-01-01-fixture-$cf_uid.md"
  (
    cd "$tmp/repo" && hermetic "$S/obs-consume.sh" --uid "$cf_uid" --spec "$1" \
      --today 2026-01-01 --obs-dir "$cf_o" >/dev/null 2>&1
    rc=$?
    grep -rh '^Consumed-by:' "$cf_o"
    echo "rc=$rc"
  )
}
seam_forms obs-consume consume_form
case $(consume_form demo) in
  "Consumed-by: specs/demo (2026-01-01)"*) ok "obs-consume: the Consumed-by form is unchanged" ;;
  *) fail "obs-consume: unexpected Consumed-by line: $(consume_form demo)" ;;
esac

# --- The scope grammar -------------------------------------------------------

# A scope naming the spec as a path is refused, and the refusal names the
# expected shape; the bare form is accepted.
got=$(outcome "$S/fleet-attention.sh" heartbeat w1 specs/demo:task-1 working)
case $got in
  *"<spec>:<id>"*"rc=2") ok "fleet-attention: a specs/ scope is refused naming the expected shape" ;;
  *) fail "fleet-attention: the refusal does not name the expected shape: $got" ;;
esac
case $(outcome "$S/fleet-attention.sh" heartbeat w1 demo:task-1 working) in
  *"rc=0") ok "fleet-attention: the bare scope is accepted" ;;
  *) fail "fleet-attention: the bare scope was refused" ;;
esac
got=$(outcome "$S/fleet-streamjson.sh" launch w1 specs/demo --prompt-file /dev/null)
case $got in
  *"<spec>:<id>"*"rc=2") ok "fleet-streamjson: a specs/ scope is refused naming the expected shape" ;;
  *) fail "fleet-streamjson: the refusal does not name the expected shape: $got" ;;
esac
got=$(outcome "$S/fleet-streamjson.sh" --bogus)
case $got in
  *"<spec>:<id>"*) ok "fleet-streamjson: usage names the scope shape" ;;
  *) fail "fleet-streamjson: usage does not name the scope shape: $got" ;;
esac
got=$(outcome "$S/fleet-liveness.sh" classify w1 specs/demo:task-1)
case $got in
  *"<spec>:<id>"*"rc=2") ok "fleet-liveness: a specs/ scope is refused naming the expected shape" ;;
  *) fail "fleet-liveness: the refusal does not name the expected shape: $got" ;;
esac
printf 'pane\n' >"$tmp/pane.txt"
got=$(outcome "$S/fleet-pane-detect.sh" classify --pane "$tmp/pane.txt" --backend tmux --worker w1 --scope specs/demo:1)
case $got in
  *"<spec>:<id>"*"rc=2") ok "fleet-pane-detect: a specs/ scope is refused naming the expected shape" ;;
  *) fail "fleet-pane-detect: the refusal does not name the expected shape: $got" ;;
esac
# The shape is one sentence, copied into each script that refuses a scope.
shape_defs=$(grep -h '^SCOPE_SHAPE=' "$S/fleet-attention.sh" "$S/fleet-liveness.sh" \
  "$S/fleet-streamjson.sh" "$S/fleet-pane-detect.sh")
if [ "$(printf '%s\n' "$shape_defs" | wc -l | tr -d ' ')" -ne 4 ]; then
  fail "a scope shape definition is missing: $shape_defs"
elif [ "$(printf '%s\n' "$shape_defs" | sort -u | wc -l | tr -d ' ')" -ne 1 ]; then
  fail "the scope shape differs between its copies: $shape_defs"
else
  ok "the scope shape is byte-identical in every copy"
fi

# --- Callers and skills ------------------------------------------------------

# The watchdog relaunches the tower with the bare identifier.
# shellcheck disable=SC2016 # the relaunch command as written in the watchdog
if grep -Fq '"/orchestrate --watch --unattended $spec"' "$S/fleet-tower-watchdog.sh"; then
  ok "fleet-tower-watchdog: the relaunch names the bare identifier"
else
  fail "fleet-tower-watchdog: the relaunch does not name the bare identifier"
fi
# Skills that take a spec argument advertise the bare identifier, and the
# fetch seam is called with it.
for s in orchestrate execute-task spec-kickoff spec-walkthrough; do
  sk=$ROOT/skills/$s/SKILL.md
  if grep -q '^argument-hint:.*<spec-path>' "$sk"; then
    fail "$s: argument-hint still names a spec path"
  elif grep -q '^argument-hint:.*<spec>' "$sk"; then
    ok "$s: argument-hint names the bare identifier"
  else
    fail "$s: argument-hint names no spec argument"
  fi
done
for s in orchestrate execute-task; do
  if grep -Fq -- '--spec specs/<spec>' "$ROOT/skills/$s/SKILL.md"; then
    fail "$s: calls dispatch-fetch with the alias"
  else
    ok "$s: calls dispatch-fetch with the bare identifier"
  fi
done

if [ "$failures" -ne 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all spec-addressing tests passed"
