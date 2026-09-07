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

# 6. Range mode REPORTS rather than fails. A commit that already exists cannot
#    be corrected without the history rewrite the framework forbids, so a
#    non-conventional subject there is surfaced and the range still passes —
#    the same treatment subject length has always had, for the same reason.
#    githooks/commit-msg is what refuses the subject while it is still a file
#    on disk; case 10 pins the two to the same verdict.
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
assert "range mode does not fail on frozen history" 0 $?
#    Reported, though — silence here would hide it entirely, since the range
#    lint is the only place an already-pushed subject is ever looked at.
out="$(cd "$tmp" && /bin/bash "$CHECKER" "HEAD~1..HEAD" 2>&1)"
case "$out" in
  *"not conventional"*"bad subject line"*) ;;
  *)
    echo "FAIL: range mode must still REPORT the bad subject, got: $out" >&2
    failures=$((failures + 1))
    ;;
esac
case "$out" in
  *"1 non-conventional"*) ;;
  *)
    echo "FAIL: range mode must summarise the count it reported, got: $out" >&2
    failures=$((failures + 1))
    ;;
esac
#    Control: the SAME subject through the editable path still fails, so the
#    exemption above is scoped to frozen history and is not the rule going
#    slack everywhere.
printf 'bad subject line\n' | /bin/bash "$CHECKER" --stdin >/dev/null 2>&1
assert "the same subject still fails on the editable path" 1 $?
(cd "$tmp" && git -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -q --allow-empty -m "fix: good again" \
  && /bin/bash "$CHECKER" "HEAD~1..HEAD" >/dev/null 2>&1)
assert "range mode passes a clean range" 0 $?

# 10. The hook and this script must agree on what "conventional" means.
#     Enforcement now lives in two places on purpose — the hook refuses a
#     subject while it can still be edited, this script reports one that
#     cannot — and two implementations of one rule is precisely how a rule
#     starts meaning two things. Every subject below must get the same verdict
#     from both. Merge/Revert and the squash!/fixup!/amend! subjects are
#     excluded: the hook owns refusals this script deliberately skips.
HOOK="$(cd "$(dirname "$0")/.." && pwd)/githooks/commit-msg"
if [ ! -f "$HOOK" ]; then
  echo "FAIL: githooks/commit-msg missing at $HOOK" >&2
  failures=$((failures + 1))
else
  hook_msg="$tmp/hookmsg"
  agree=0
  for corpus_subject in \
    'feat: a plain one' \
    'fix(scope): with a scope' \
    'feat(a.b-c)!: breaking with a dotted scope' \
    'chore: ok' \
    'docs: ok' \
    'wip: not a type' \
    'notatype: nope' \
    'no colon at all' \
    'feat:missing the space' \
    'feat: ' \
    'FEAT: uppercase type' \
    'feat(SCOPE): uppercase scope'; do
    printf '%s\n' "$corpus_subject" >"$hook_msg"
    script_rc=0
    printf '%s\n' "$corpus_subject" | /bin/bash "$CHECKER" --stdin >/dev/null 2>&1 || script_rc=1
    hook_rc=0
    (cd "$(dirname "$HOOK")/.." && /bin/sh "$HOOK" "$hook_msg" >/dev/null 2>&1) || hook_rc=1
    if [ "$script_rc" != "$hook_rc" ]; then
      echo "FAIL: hook and script disagree on '$corpus_subject' (script=$script_rc hook=$hook_rc)" >&2
      failures=$((failures + 1))
    else
      agree=$((agree + 1))
    fi
  done
  #  A corpus that stopped reaching either implementation would agree
  #  vacuously, so require that it actually exercised both verdicts.
  if [ "$agree" -lt 12 ]; then
    echo "FAIL: only $agree of 12 corpus subjects were compared" >&2
    failures=$((failures + 1))
  fi
  printf '%s\n' 'feat: a plain one' >"$hook_msg"
  (cd "$(dirname "$HOOK")/.." && /bin/sh "$HOOK" "$hook_msg" >/dev/null 2>&1) \
    || {
      echo "FAIL: the hook rejects a valid subject — the agreement above proves nothing" >&2
      failures=$((failures + 1))
    }
  printf '%s\n' 'wip: nope' >"$hook_msg"
  if (cd "$(dirname "$HOOK")/.." && /bin/sh "$HOOK" "$hook_msg" >/dev/null 2>&1); then
    echo "FAIL: the hook accepts a non-conventional subject — it is not screening at all" >&2
    failures=$((failures + 1))
  fi
  echo "ok: the hook and the range lint agree on what conventional means"
fi

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

# 8h. --marker is an emit-time guard and requires --stdin: pairing it with a
#     git range is a usage error, never a range scan. A range-time marker check
#     would scan history and recreate the unfixable-red trap REQ-C1.3 forbids,
#     so the CLI refuses the combination outright. Reuse the fixture repo from
#     section 6.
(cd "$tmp" && /bin/bash "$CHECKER" --marker subject "HEAD~1..HEAD" >/dev/null 2>&1)
assert "--marker subject with a git range is a usage error" 2 $?
(cd "$tmp" && /bin/bash "$CHECKER" --marker title "HEAD~1..HEAD" >/dev/null 2>&1)
assert "--marker title with a git range is a usage error" 2 $?

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all check-commit-msgs tests passed"
