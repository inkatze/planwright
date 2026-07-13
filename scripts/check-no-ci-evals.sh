#!/bin/sh
# check-no-ci-evals.sh — the standing CI-exclusion guard (prompt-hygiene Task 4;
# REQ-C1.6, D-8). The kept prompt-eval suite is deliberately on-demand: it costs
# tokens, gates nondeterministically, and needs an API key that has no place in a
# public repo's CI. That "evals never run in CI" invariant is enforced here
# structurally — not by the eval task's mere absence from the `check` aggregate,
# which a future edit could silently undo — by scanning the workflow files for
# any wiring of an eval task and failing loud if one is found.
#
# What counts as an eval task: any mise task in the `eval:` namespace (the
# sibling of `check:`, `lint:`, `scan:`), invoked as `mise run eval:<x>` or the
# bare `mise eval:<x>`. Matching the namespace (not the substring "eval")
# avoids flagging a legitimately-named task like `evaluate-release` or a comment
# that merely mentions evaluation.
#
# Untrusted input: workflow files are PR-controllable. They are read as text and
# matched with grep only; no content is ever executed. The scanned directory is
# the sole positional argument; the only glob is the fixed `*.yml` / `*.yaml`
# pattern under that directory, so no file content is subject to expansion.
#
# Usage: check-no-ci-evals.sh [<workflows-dir>]   (default: .github/workflows)
# Exit: 0 no eval task wired into any workflow (or the dir is absent — vacuously
#   clean); 1 an eval task is wired into CI (offending file:line on stderr);
#   2 usage error.
#
# Portable POSIX sh + grep; bash 3.2 / BSD tooling. C locale pinned so the ERE
# character classes do not vary by host locale.
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

if [ $# -gt 1 ]; then
  echo "usage: check-no-ci-evals.sh [<workflows-dir>]" >&2
  exit 2
fi

dir="${1:-.github/workflows}"

# No workflow directory at all: nothing can wire an eval into CI. Vacuously
# clean (a repo may legitimately ship no workflows).
if [ ! -d "$dir" ]; then
  echo "check-no-ci-evals: no workflow directory at '$dir'; nothing to scan."
  exit 0
fi

# Enumerate the workflow files into the positional parameters. A non-matching
# glob stays literal, so each candidate is existence-checked before use.
set --
for f in "$dir"/*.yml "$dir"/*.yaml; do
  [ -f "$f" ] && set -- "$@" "$f"
done

if [ "$#" -eq 0 ]; then
  echo "check-no-ci-evals: no workflow files under '$dir'; nothing to scan."
  exit 0
fi

# An eval-task invocation: `mise`, optional `run`, then a task in the `eval:`
# namespace. [[:space:]] rather than a literal space so tabs and multiple
# spaces match; `eval:` (namespace colon) rather than a bare `eval` word so
# only real eval tasks trip the guard. -H forces the filename prefix even when a
# single file is scanned, giving a file:line:match report.
pattern='mise([[:space:]]+run)?[[:space:]]+eval:'
hits="$(grep -HnE "$pattern" "$@" 2>/dev/null || true)"

if [ -n "$hits" ]; then
  echo "check-no-ci-evals: an eval task is wired into a CI workflow (D-8 forbids it)." >&2
  echo "The kept prompt-eval suite runs on demand via 'mise run eval:skill', never in CI." >&2
  echo "Offending references:" >&2
  printf '%s\n' "$hits" | while IFS= read -r h; do
    [ -n "$h" ] && echo "  $h" >&2
  done
  exit 1
fi

echo "check-no-ci-evals: no eval task wired into any workflow under '$dir'."
exit 0
