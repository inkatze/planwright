#!/bin/bash
# No push to main may cancel another push's run: release-publish.sh tags only
# when every check on the release commit succeeded (rl_ci_state), so a merge
# cancelling the release commit's macOS jobs blocks the release. For each
# push-triggered workflow that gate judges (all but the lock workflow it
# excludes by name, read from release-lib.sh):
#   P1  `cancel-in-progress:` is `false` or cancels pull_request runs only;
#   P2  a push run gets a group of its own commit, since a group keeps one
#       pending run and cancels it when a newer one queues.
# release-please is exempt from P2 only: its fixed group stops two runs editing
# the release PR at once. Canonical spellings are matched, not evaluated.
set -u
unset CDPATH
LC_ALL=C
export LC_ALL

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
RELEASE_LIB="$REPO_ROOT/scripts/release-lib.sh"

CANCEL_PR_ONLY="\${{ github.event_name == 'pull_request' }}"
GROUP_PER_COMMIT="\${{ github.event_name == 'pull_request' && github.ref || github.sha }}"
GROUP_PER_REF="\${{ github.ref }}"
P2_EXEMPT="release-please"

failures=0
pass() { echo "ok: $1"; }
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}

work="$(mktemp -d "${TMPDIR:-/tmp}/test-workflow-push-concurrency.XXXXXX")" || exit 1
trap 'rm -rf "$work"' EXIT

lock_workflow="$(sed -n 's/^RL_CI_WINDOW_LOCK_WORKFLOW="\(.*\)"$/\1/p' "$RELEASE_LIB")"
if [ -n "$lock_workflow" ]; then
  pass "read the excluded lock workflow name ('$lock_workflow') from release-lib.sh"
else
  fail "no RL_CI_WINDOW_LOCK_WORKFLOW in scripts/release-lib.sh; the scope below cannot be drawn"
fi

# Emits, for one workflow file, tab-separated facts:
#   name <workflow name>
#   push                 the workflow has a push trigger
#   cancel <line> <value>
#   group <line> <value>
# Comments are stripped first, so a comment naming a value never satisfies a
# check. A scalar `concurrency: <group>` is a group with cancellation off.
facts() {
  sed 's/[[:space:]]#.*$//; s/^[[:space:]]*#.*$//' "$1" | awk -v q="\"'" '
    function strip(v) {
      sub(/^[ \t]+/, "", v); sub(/[ \t]+$/, "", v)
      if (length(v) >= 2 && substr(v, 1, 1) == substr(v, length(v), 1) && index(q, substr(v, 1, 1)) > 0)
        v = substr(v, 2, length(v) - 2)
      gsub(/[ \t]+/, " ", v)
      return v
    }
    {
      n = match($0, /[^ ]/)
      if (n == 0) next
      indent = n - 1
      if (inon && indent <= onindent) inon = 0
      if (incc && indent <= ccindent) incc = 0
      if (indent == 0 && $0 ~ /^name:/) { v = $0; sub(/^name:/, "", v); printf "name\t%s\n", strip(v) }
      if (indent == 0 && $0 ~ /^("on"|'"'"'on'"'"'|on):/) {
        v = $0; sub(/^[^:]*:/, "", v); v = strip(v)
        if (v == "") { inon = 1; onindent = 0; onchild = -1 }
        else printf "unparsed\t%d\t%s\n", NR, "inline on: value"
        next
      }
      if (inon) {
        if (onchild < 0) onchild = indent
        if (indent == onchild && $0 ~ /^[ ]*push:/) print "push"
        next
      }
      if ($0 ~ /^[ ]*concurrency:/) {
        v = $0; sub(/^[^:]*:/, "", v); v = strip(v)
        if (v == "") { incc = 1; ccindent = indent }
        else printf "group\t%d\t%s\n", NR, v
        next
      }
      if (incc && $0 ~ /^[ ]*cancel-in-progress:/) { v = $0; sub(/^[^:]*:/, "", v); printf "cancel\t%d\t%s\n", NR, strip(v) }
      if (incc && $0 ~ /^[ ]*group:/) { v = $0; sub(/^[^:]*:/, "", v); printf "group\t%d\t%s\n", NR, strip(v) }
    }
  '
}

# check_dir <workflows-dir> — prints one violation per line and the checked
# workflow names as `checked <name>`; the caller judges both.
check_dir() {
  local wf label f name
  for wf in "$1"/*.yml "$1"/*.yaml; do
    [ -f "$wf" ] || continue
    label="${wf##*/}"
    f="$work/facts"
    facts "$wf" >"$f"
    if grep -q '^unparsed	' "$f"; then
      echo "$label: $(grep '^unparsed	' "$f" | cut -f3) is outside what this test reads (failing closed)"
      continue
    fi
    grep -qx 'push' "$f" || continue
    name="$(grep '^name	' "$f" | head -n 1 | cut -f2)"
    [ -n "$lock_workflow" ] && [ "$name" = "$lock_workflow" ] && continue
    echo "checked ${name:-$label}"
    while IFS=$'\t' read -r _ ln v; do
      [ -n "${ln:-}" ] || continue
      [ "$v" = "false" ] || [ "$v" = "$CANCEL_PR_ONLY" ] \
        || echo "$label:$ln: P1 cancel-in-progress '$v' can cancel a push run in progress; use false or $CANCEL_PR_ONLY"
    done <<EOF
$(grep '^cancel	' "$f")
EOF
    [ "$name" = "$P2_EXEMPT" ] && continue
    while IFS=$'\t' read -r _ ln v; do
      [ -n "${ln:-}" ] || continue
      case "$v" in
        *"$GROUP_PER_COMMIT"*) ;;
        *) echo "$label:$ln: P2 concurrency group '$v' is shared by push runs, so a newer push cancels a pending one; key it on $GROUP_PER_COMMIT" ;;
      esac
    done <<EOF
$(grep '^group	' "$f")
EOF
  done
}

# fixture <dir> <cancel-in-progress> <group> [<name>] — a push-and-PR workflow.
fixture() {
  mkdir -p "$1"
  cat >"$1/ci.yml" <<EOF
---
name: ${4:-ci}
"on":
  pull_request:
  push:
    branches: [main]
concurrency:
  group: $3
  cancel-in-progress: $2
jobs:
  check:
    runs-on: ubuntu-latest
    steps:
      - run: echo ok
EOF
}

violations() { grep -v '^checked ' "$1" || true; }

# --- the defect shape fails both properties ---------------------------------
fixture "$work/before" true "ci-$GROUP_PER_REF"
check_dir "$work/before" >"$work/out.before"
if violations "$work/out.before" | grep -q ' P1 ' && violations "$work/out.before" | grep -q ' P2 '; then
  pass "the ref-keyed group with cancel-in-progress on fails P1 and P2"
else
  fail "the defect shape was not caught: $(cat "$work/out.before")"
fi

fixture "$work/nocancel" false "ci-$GROUP_PER_REF"
check_dir "$work/nocancel" >"$work/out.nocancel"
if violations "$work/out.nocancel" | grep -q ' P2 ' && ! violations "$work/out.nocancel" | grep -q ' P1 '; then
  pass "turning cancellation off without a per-commit group still fails P2"
else
  fail "a shared push group with cancellation off was not caught by P2 alone: $(cat "$work/out.nocancel")"
fi

fixture "$work/comment" "true  # $CANCEL_PR_ONLY" "ci-$GROUP_PER_REF  # $GROUP_PER_COMMIT"
check_dir "$work/comment" >"$work/out.comment"
if violations "$work/out.comment" | grep -q ' P1 ' && violations "$work/out.comment" | grep -q ' P2 '; then
  pass "a trailing comment naming the canonical value satisfies neither property"
else
  fail "a comment satisfied a property: $(cat "$work/out.comment")"
fi

# --- the fixed shape passes -------------------------------------------------
fixture "$work/after" "$CANCEL_PR_ONLY" "ci-$GROUP_PER_COMMIT"
check_dir "$work/after" >"$work/out.after"
if [ -z "$(violations "$work/out.after")" ] && grep -qx 'checked ci' "$work/out.after"; then
  pass "a per-commit push group cancelling pull_request runs only passes"
else
  fail "the fixed shape was refused or not checked: $(cat "$work/out.after")"
fi

# --- scope ------------------------------------------------------------------
if [ -n "$lock_workflow" ]; then
  fixture "$work/lock" true "release-window-$GROUP_PER_REF" "$lock_workflow"
  check_dir "$work/lock" >"$work/out.lock"
  if [ ! -s "$work/out.lock" ]; then
    pass "the excluded lock workflow is out of scope"
  else
    fail "the excluded lock workflow was checked: $(cat "$work/out.lock")"
  fi
fi

fixture "$work/exempt" false 'release-please' "$P2_EXEMPT"
check_dir "$work/exempt" >"$work/out.exempt"
if [ -z "$(violations "$work/out.exempt")" ]; then
  pass "$P2_EXEMPT keeps its fixed group with cancellation off"
else
  fail "$P2_EXEMPT's serializing group was refused: $(cat "$work/out.exempt")"
fi
fixture "$work/exempt-p1" true 'release-please' "$P2_EXEMPT"
check_dir "$work/exempt-p1" >"$work/out.exempt-p1"
if violations "$work/out.exempt-p1" | grep -q ' P1 '; then
  pass "$P2_EXEMPT is still held to P1"
else
  fail "$P2_EXEMPT escaped P1: $(cat "$work/out.exempt-p1")"
fi

# --- the repository's own workflows -----------------------------------------
check_dir "$REPO_ROOT/.github/workflows" >"$work/out.repo"
if grep -qx 'checked ci' "$work/out.repo"; then
  pass "ci.yml is among the push workflows checked"
else
  fail "ci.yml was not checked (renamed, or its push trigger is gone): $(cat "$work/out.repo")"
fi
repo_violations="$(violations "$work/out.repo")"
if [ -z "$repo_violations" ]; then
  pass "no push-triggered workflow the release gate judges can cancel a push run"
else
  fail "a push run on main can be cancelled:
$repo_violations"
fi

if [ "$failures" -eq 0 ]; then
  echo "All workflow push-concurrency tests passed."
  exit 0
fi
echo "$failures test(s) failed." >&2
exit 1
