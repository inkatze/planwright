#!/bin/bash
# Tests for scripts/check-commit-msgs.sh — the conventional-commit lint
# (Task 2 deliverable, wired into CI on every PR's commit range).
set -u
unset CDPATH

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECKER="$REPO_ROOT/scripts/check-commit-msgs.sh"

failures=0
assert() {
  if [ "$2" -eq "$3" ]; then
    echo "ok: $1"
  else
    echo "FAIL: $1 (expected exit $2, got $3)" >&2
    failures=$((failures + 1))
  fi
}

if [ ! -f "$CHECKER" ]; then
  echo "FAIL: checker script missing at $CHECKER" >&2
  exit 1
fi

lint() {
  printf '%s\n' "$1" | /bin/bash "$CHECKER" --stdin >/dev/null 2>&1
}

# Length is enforced only with --max-length (used by CI against the PR title,
# the squash-merge subject); per-commit linting checks format only because the
# framework never rewrites history (an overlong WIP subject would be
# permanently unfixable).
lint_len() {
  printf '%s\n' "$1" | /bin/bash "$CHECKER" --stdin --max-length 100 >/dev/null 2>&1
}

# 1. Valid conventional subjects pass.
lint "feat(scaffold): add the packaging skeleton"
assert "typed, scoped subject passes" 0 $?
lint "docs: update the readme"
assert "typed, unscoped subject passes" 0 $?
lint "feat(api)!: change the contract"
assert "breaking-change marker passes" 0 $?
lint "chore(orchestrate): dispatch task 2 via tmux backend, move to In progress"
assert "real repo-history subject passes" 0 $?

# 2. Merge and revert commits are skipped (GitHub builds these subjects;
#    linting them would block the normal merge flow).
lint "Merge pull request #5 from inkatze/planwright/bootstrap/task-7"
assert "merge commit is skipped" 0 $?
lint 'Revert "feat(scaffold): add the packaging skeleton"'
assert "revert commit is skipped" 0 $?

# 3. Violations fail and the output names the offending subject.
out="$(printf 'update some stuff\n' | /bin/bash "$CHECKER" --stdin 2>&1)"
assert "untyped subject fails" 1 $?
case "$out" in
  *"update some stuff"*) echo "ok: failure names the subject" ;;
  *)
    echo "FAIL: output does not name the subject: $out" >&2
    failures=$((failures + 1))
    ;;
esac
lint "feature: wrong type word"
assert "unknown type fails" 1 $?
lint "Fix: capitalized type"
assert "capitalized type fails" 1 $?
lint "fix(scope):"
assert "empty description fails" 1 $?
lint "fix(scope):no space after colon"
assert "missing space after colon fails" 1 $?
lint "fix(UPPER): bad scope charset"
assert "uppercase scope fails" 1 $?

# Length: per-commit (default) checks format only; an overlong but
# well-formed subject passes. With --max-length 100 the same subject fails.
long_subject="feat: $(printf 'x%.0s' $(seq 1 120))"
lint "$long_subject"
assert "overlong but conventional subject passes without --max-length" 0 $?
lint_len "$long_subject"
assert "overlong subject fails with --max-length 100" 1 $?
out="$(printf '%s\n' "$long_subject" | /bin/bash "$CHECKER" --stdin --max-length 100 2>&1)"
case "$out" in
  *"exceeds 100"*) echo "ok: length failure names the limit" ;;
  *)
    echo "FAIL: length failure message unclear: $out" >&2
    failures=$((failures + 1))
    ;;
esac
# A short, well-formed subject still passes under --max-length.
lint_len "feat(scope): short and tidy"
assert "short subject passes under --max-length" 0 $?
# --max-length still enforces format (a malformed subject fails regardless).
printf 'not conventional at all\n' | /bin/bash "$CHECKER" --stdin --max-length 100 >/dev/null 2>&1
assert "--max-length still enforces format" 1 $?
# A non-numeric --max-length value is a usage error, not a silent no-op.
printf 'feat: x\n' | /bin/bash "$CHECKER" --stdin --max-length abc >/dev/null 2>&1
assert "non-numeric --max-length is a usage error" 2 $?

# 4. Multiple subjects on stdin: every bad one is named; one bad among good
#    still fails.
out="$(printf 'feat: good one\nbad one\nalso bad\n' | /bin/bash "$CHECKER" --stdin 2>&1)"
assert "mixed batch fails" 1 $?
case "$out" in
  *"bad one"*"also bad"* | *"also bad"*"bad one"*)
    echo "ok: every violation is named"
    ;;
  *)
    echo "FAIL: not all violations named: $out" >&2
    failures=$((failures + 1))
    ;;
esac

# 5. Empty stdin is a usage error (an empty PR range upstream should be
#    visible, not a silent pass).
printf '' | /bin/bash "$CHECKER" --stdin >/dev/null 2>&1
assert "empty input is a usage error" 2 $?

# 6. Range mode lints git history: a temp repo with one good and one bad
#    commit fails over the full range and passes over the good-only range.
#    The fixture repo must be hermetic: a contributor's global git config
#    (commit signing through an agent socket, hooks, templates) must not be
#    able to break fixture commits.
GIT_CONFIG_GLOBAL=/dev/null
GIT_CONFIG_SYSTEM=/dev/null
export GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM
tmp="$(mktemp -d)" || exit 1
trap 'rm -rf "$tmp"' EXIT
(
  cd "$tmp" || exit 1
  git init -q
  git -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -q --allow-empty -m "feat: good start"
  git -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -q --allow-empty -m "bad subject line"
) || exit 1
(cd "$tmp" && /bin/bash "$CHECKER" "HEAD~1..HEAD" >/dev/null 2>&1)
assert "range mode catches the bad commit" 1 $?
(cd "$tmp" && git -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -q --allow-empty -m "fix: good again" \
  && /bin/bash "$CHECKER" "HEAD~1..HEAD" >/dev/null 2>&1)
assert "range mode passes a clean range" 0 $?

# 7. No arguments at all is a usage error with help text.
/bin/bash "$CHECKER" >/dev/null 2>&1
assert "no arguments is a usage error" 2 $?

# 8. --marker mode (Task 4, REQ-C1.1/C1.3/C1.4): a context-sensitive
#    [pending-sign-off] placement guard layered on the conventional check.
#    Subject context requires canonical end-of-subject placement; title
#    context rejects the marker outright.
marker_subj() {
  printf '%s\n' "$1" | /bin/bash "$CHECKER" --marker subject --stdin >/dev/null 2>&1
}
marker_title() {
  printf '%s\n' "$1" | /bin/bash "$CHECKER" --marker title --stdin >/dev/null 2>&1
}

# 8a. Subject context — the four placements.
marker_subj "feat(gate): resolve the finding [pending-sign-off]"
assert "subject: canonical end-of-subject marker passes" 0 $?
marker_subj "[pending-sign-off] feat(gate): resolve the finding"
assert "subject: pre-prefix marker fails" 1 $?
marker_subj "feat(gate): resolve [pending-sign-off] the finding"
assert "subject: mid-subject marker fails" 1 $?
marker_subj "feat(gate): resolve the finding"
assert "subject: no marker on a well-formed subject passes" 0 $?

# 8b. The misplacement failure names the offending subject.
out="$(printf 'feat(gate): resolve [pending-sign-off] the finding\n' \
  | /bin/bash "$CHECKER" --marker subject --stdin 2>&1)"
case "$out" in
  *"[pending-sign-off]"*"feat(gate): resolve [pending-sign-off] the finding"* | \
    *"feat(gate): resolve [pending-sign-off] the finding"*)
    echo "ok: subject marker failure names the subject"
    ;;
  *)
    echo "FAIL: subject marker failure does not name the subject: $out" >&2
    failures=$((failures + 1))
    ;;
esac

# 8c. A second (duplicate) marker before an otherwise-canonical suffix fails.
marker_subj "feat(gate): [pending-sign-off] resolve it [pending-sign-off]"
assert "subject: duplicate marker fails even with canonical tail" 1 $?

# 8d. Subject context still enforces conventional format and composes with
#     --max-length (the emit-time self-lint is one invocation, not three).
marker_subj "resolve the finding [pending-sign-off]"
assert "subject: non-conventional marked subject fails" 1 $?
printf '%s\n' "feat(gate): resolve the finding [pending-sign-off]" \
  | /bin/bash "$CHECKER" --marker subject --stdin --max-length 100 >/dev/null 2>&1
assert "subject: canonical marker under --max-length passes" 0 $?

# 8e. Title context (REQ-C1.4) — the PR-title case: any marker is rejected,
#     a marker-free title passes, and conventional/length still apply.
marker_title "feat(gate): resolve the finding [pending-sign-off]"
assert "title: any marker is rejected" 1 $?
marker_title "feat(gate): resolve the finding"
assert "title: marker-free title passes" 0 $?
out="$(printf 'feat(gate): resolve the finding [pending-sign-off]\n' \
  | /bin/bash "$CHECKER" --marker title --stdin 2>&1)"
case "$out" in
  *"[pending-sign-off]"*) echo "ok: title marker failure names the marker" ;;
  *)
    echo "FAIL: title marker failure message unclear: $out" >&2
    failures=$((failures + 1))
    ;;
esac
printf '%s\n' "not conventional [pending-sign-off]" \
  | /bin/bash "$CHECKER" --marker title --stdin >/dev/null 2>&1
assert "title: marker mode still enforces conventional format" 1 $?

# 8f. An unknown --marker context is a usage error, not a silent no-op.
printf 'feat: x\n' | /bin/bash "$CHECKER" --marker bogus --stdin >/dev/null 2>&1
assert "unknown --marker context is a usage error" 2 $?
printf 'feat: x\n' | /bin/bash "$CHECKER" --marker --stdin >/dev/null 2>&1
assert "--marker consuming the source token is a usage error" 2 $?

# 8g. Canonical placement is space-anchored: the marker must be the last token,
#     separated from the description by whitespace (the `*" $marker"` glob
#     requires at least one space before the marker and nothing after it). A
#     marker glued to the description (no space) and a marker with trailing
#     whitespace both fail — these pin the end-anchor so a future loosening to
#     `*"$marker"` (which would silently accept mid-glued markers) is caught.
marker_subj "feat(gate): resolve the finding[pending-sign-off]"
assert "subject: marker glued to description (no space) fails" 1 $?
marker_subj "feat(gate): resolve the finding [pending-sign-off] "
assert "subject: marker with trailing whitespace fails" 1 $?

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all check-commit-msgs tests passed"
