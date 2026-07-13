#!/bin/sh
# check-no-ci-evals.sh — the standing CI-exclusion guard (prompt-hygiene Task 4;
# REQ-C1.6, D-8). The kept prompt-eval suite is deliberately on-demand: it costs
# tokens, gates nondeterministically, and needs an API key that has no place in a
# public repo's CI. That "evals never run in CI" invariant is enforced here
# structurally — not by the eval task's mere absence from the `check` aggregate,
# which a future edit could silently undo — by scanning the workflow files for
# any wiring of an eval task and failing loud if one is found.
#
# What counts as an eval task being wired in — two forms, both caught:
#   1. Any mise task in the `eval:` namespace (the sibling of `check:`, `lint:`,
#      `scan:`), in ANY invocation form: `mise run eval:<x>`, the `run` alias
#      `mise r eval:<x>`, the implicit `mise eval:<x>`, a flag or quote between
#      `run` and the task (`mise run --verbose eval:<x>`, `mise run "eval:<x>"`).
#      The rule is "a `mise` invocation whose line reaches an `eval:` task",
#      matched by `mise` followed anywhere on the line by `eval:` — deliberately
#      permissive, because a security control should fail loud on a near-miss
#      rather than let a novel invocation form through. Matching the `eval:`
#      namespace (not the bare substring "eval") still spares a legitimately
#      named task like `evaluate-release` and prose that merely says "eval".
#   2. Invoking the runner script directly, bypassing mise entirely
#      (`sh scripts/prompt-eval.sh …`, `./scripts/prompt-eval.sh …`).
# A residual this guard does NOT cover (out of REQ-C1.6's "workflow files"
# scope): an eval task reached transitively through a mise.toml `depends` chain
# from a CI-run task. That is recorded as an observation, not enforced here.
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

# Two alternatives (see the header):
#   * a `mise` invocation whose line names an `eval:` task — matched in two
#     stages so BOTH conditions hold on the line: the line invokes `mise` (at a
#     TOKEN BOUNDARY, so a word merely ending in `mise` like `premise` does not
#     trigger), and it carries an `eval:` at a TOKEN BOUNDARY (preceded by a
#     non-word char, so the `eval` namespace triggers but a substring inside
#     `retrieval:` / `medieval:` / `evaluate-release` does not). Both stages use
#     the same `(^|[^[:alnum:]_-])` anchor. This covers the `run`/`r`
#     alias, an interposed flag, and a quoted task, since `eval:` always sits at
#     an argument boundary. A residual, accepted in the fail-loud direction: a
#     contrived line that both invokes mise AND writes the literal `eval:` after
#     a boundary elsewhere (a trailing `echo "eval: …"`) over-blocks. That is far
#     rarer than a real `retrieval:` task and only causes a spurious CI failure,
#     never a silent bypass.
#   * a direct call to the runner script, bypassing mise entirely.
# -H forces the filename prefix even for a single file (file:line:match report).
mise_eval="$(grep -HnE '(^|[^[:alnum:]_-])mise[[:space:]]' "$@" 2>/dev/null | grep -E '(^|[^[:alnum:]_-])eval:' || true)"
direct="$(grep -HnE 'prompt-eval\.sh' "$@" 2>/dev/null || true)"
hits="$(printf '%s\n%s' "$mise_eval" "$direct" | grep -v '^[[:space:]]*$' | sort -u || true)"

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
