#!/bin/sh
# spec-anchor.sh — compute the planwright content anchor for a spec bundle.
#
# Canonical form, as defined in doctrine/spec-format.md (REQ-F1.9;
# anchor-integrity REQ-A1.1, REQ-A1.2, REQ-A1.3): the anchor is the git hash
# of the per-file digest list, in canonical order (requirements, design,
# tasks, test-spec), where
#
#   * requirements.md, design.md, and test-spec.md each contribute their whole
#     content minus exactly one line — the `**Status:**` declaration inside the
#     single leading header block, dropped together with its line terminator so
#     the bytes around it join unchanged. Nothing else is excluded from them:
#     `Format-version:`, `Superseded-by:`, `Last reviewed:` and every body line
#     stay anchored, and a `**Status:**` line in body prose or inside a
#     column-0 fence is not a header declaration at all, so it stays anchored
#     too. A well-formed block that declares no `**Status:**` excludes nothing
#     and hashes whole. The exclusion is universal — the meta-spec defines it
#     once in the version-1 body and every later format version inherits it, so
#     this script parses no `Format-version:` at all.
#   * tasks.md contributes its task-definition content only — task headings
#     plus the Deliverables / Done when / Dependencies / Citations / Estimated
#     effort field bullets (with their continuation lines), task records sorted
#     by task id. Orchestration-state placement (which section a block sits in)
#     and the Status / Last activity / Dispatch annotations are outside that
#     extraction already, and so is its header block, so tasks.md needs no
#     separate Status carve-out.
#
# Together: /orchestrate's state moves and the bundle's lifecycle Status flips
# (stored Draft->Ready, derived Ready<->Active, and the header mirrors those
# flips write into the other three files) never change the anchor, while
# meaning edits always do.
#
# Sanctioned command form recorded in anchor entries:
#   scripts/spec-anchor.sh <spec-dir>
#
# Fails closed (non-zero exit, message on stderr, no anchor printed) on a
# missing or unreadable spec file, a failed extraction, duplicate task ids,
# a missing/unreadable/syntax-erroring scripts/spec-parse.sh (the extraction
# lib this script sources, exit 2), NUL-bearing content in any of the four
# files, or a malformed, unterminated, or duplicate-`**Status:**` header block
# in one of the three whole-content files; a successful exit is the only state
# that yields an anchor (REQ-F1.9, REQ-A1.2).
# The NUL refusal is a deliberate behavior change from the pre-lib
# revisions, which silently computed an anchor over an awk-NUL-truncated
# stream (REQ-B1.6d); such an anchor was wrong and can no longer be
# reproduced. The header-block refusals are likewise deliberate: a block the
# meta-spec's extent definition calls malformed leaves the exclusion undefined,
# and silently hashing the whole file would make the anchor depend on how badly
# a header was written.
#
# Portable: POSIX sh + awk + git + head + tail, plus tr + wc via the sourced
# lib (bash 3.2 / BSD compatible, no eval, input treated as data only). head
# and tail are the digest's line slice; both are given only a numeric -n and
# read through a redirection, never a path operand.
set -eu

# Pin the C locale: range patterns are collation-dependent under UTF-8
# locales; anchor bytes and matches must not vary by host locale.
LC_ALL=C
export LC_ALL

# A CDPATH-resolved cd would echo the destination into the command
# substitution below, corrupting the derived lib path.
unset CDPATH 2>/dev/null || true

# The canonical tasks.md definition-content extraction comes from the shared
# spec-parse grammar lib (format-grammar D-3, REQ-B1.2). Guarded source
# (REQ-B1.6a): fail closed when the lib is missing, unreadable, or
# syntax-erroring — a bare `.` continuing fail-open would let a private-copy
# fallback or an empty extraction hash a wrong anchor.
here=$(cd "$(dirname "$0")" && pwd -P) || exit 2
spec_parse_sh="$here/spec-parse.sh"
if [ ! -f "$spec_parse_sh" ] || [ ! -r "$spec_parse_sh" ]; then
  # Sanitize the echoed path inline (echo-safety.sh's canonical C0+DEL+C1
  # byte range): this guard runs before any lib is sourced, so no sanitizer
  # function is available, and a checkout path carrying ESC/BEL bytes would
  # otherwise drive the operator's terminal. printf, not echo: an echo that
  # interprets backslash escapes could turn printable path bytes into
  # control bytes at output time.
  lib_disp=$(printf '%s' "$spec_parse_sh" | tr -d '\000-\037\177\200-\237')
  [ -n "$lib_disp" ] || lib_disp='(unprintable path)'
  printf '%s\n' "spec-anchor: spec-parse.sh missing or unreadable: $lib_disp" >&2
  exit 2
fi
# shellcheck source=scripts/spec-parse.sh
. "$spec_parse_sh" || exit 2

if [ $# -ne 1 ]; then
  echo "usage: spec-anchor.sh <spec-dir>" >&2
  exit 2
fi

dir=$1
for f in requirements.md design.md tasks.md test-spec.md; do
  if [ ! -f "$dir/$f" ] || [ ! -r "$dir/$f" ]; then
    echo "spec-anchor: missing or unreadable: $dir/$f" >&2
    exit 1
  fi
done

# spec_anchor__digest <file> — the per-file digest for the three whole-content
# files: the file's bytes minus its header-block `**Status:**` line, hashed with
# git hash-object (anchor-integrity D-2, REQ-A1.1, REQ-A1.2).
#
# Byte-exact by construction. The kept lines are sliced out with head/tail
# rather than re-emitted through awk, so every remaining byte — a CRLF ending, a
# missing final newline — reaches git untouched, and `--stdin` is used even on
# the exclude-nothing path so a single hashing route serves all three cases and
# no .gitattributes input filter can make them disagree.
#
# The locator's captured assignment is the REQ-B1.6f exit-status check: under
# `set -e` a malformed, unterminated, or duplicate-Status block aborts the run
# before anything is hashed, so a refused block never degrades into an anchor
# over the whole file.
#
# Known bound: head/tail re-read the file after the locator read it, so a
# concurrent rewrite between the two can slice against a line number that no
# longer holds. Same shape as the lib's own screen-then-parse window, and no
# in-repo writer rewrites a spec file underneath a running anchor computation.
#
# Known bound: the slice reaches git through a pipeline, so a head or tail that
# fails mid-read has its status masked by `git hash-object`, which would hash
# the short stream and exit 0. The remedy the tasks.md extraction below uses —
# capture first, hash second — is unavailable here: command substitution strips
# trailing newlines, and the byte-exactness above is the whole point of the
# head/tail route. Accepted rather than staged through a temp file: the inputs
# are small regular files read from local disk, where a partial read that still
# exits non-zero is disk-failure territory.
spec_anchor__digest() {
  # The locator's status is captured rather than left to `set -e` so a refusal
  # can name the file first: three files run through this helper, and the lib's
  # own message states the grammar fault without saying which one carried it.
  # `spec_parse_printable` is the lib's exported sanitizer — echoing raw path
  # bytes here is the REQ-B1.6c hazard, and duplicating the byte range would be
  # a second copy to keep in step.
  sa_rc=0
  sa_line=$(spec_parse_header_status_line "$1") || sa_rc=$?
  if [ "$sa_rc" -ne 0 ]; then
    printf '%s\n' "spec-anchor: header-block parse failed for $(spec_parse_printable "$1")" >&2
    exit "$sa_rc"
  fi
  # Belt-and-braces: the locator either fails closed (caught above) or prints a
  # number, so this refuses a lib that has started returning something else
  # rather than feeding it to arithmetic.
  case $sa_line in
    '' | *[!0-9]*)
      printf '%s\n' "spec-anchor: header-block Status locator returned no line number" >&2
      exit 2
      ;;
  esac
  if [ "$sa_line" -eq 0 ]; then
    git hash-object --stdin <"$1"
  elif [ "$sa_line" -eq 1 ]; then
    # `head -n 0` is unspecified in POSIX; the Status line opening the file has
    # no preceding lines to keep, so the head slice is simply skipped.
    tail -n "+2" <"$1" | git hash-object --stdin
  else
    {
      head -n "$((sa_line - 1))" <"$1"
      tail -n "+$((sa_line + 1))" <"$1"
    } | git hash-object --stdin
  fi
}

req_hash=$(spec_anchor__digest "$dir/requirements.md")
des_hash=$(spec_anchor__digest "$dir/design.md")
# Capture the extraction (the lib's canonical definition-content stream)
# first so a parse failure aborts under set -e (a failure inside
# `extract | git hash-object` would otherwise be masked by the pipeline's
# last command and hash an empty stream — fail-open). The captured-assignment
# form is the REQ-B1.6f exit-status check.
extracted=$(spec_parse_extract_tasks "$dir/tasks.md")
if [ -n "$extracted" ]; then
  # printf restores the single trailing newline command substitution strips,
  # keeping the hashed bytes identical to the raw extraction stream.
  tsk_hash=$(printf '%s\n' "$extracted" | git hash-object --stdin)
else
  tsk_hash=$(printf '' | git hash-object --stdin)
fi
tst_hash=$(spec_anchor__digest "$dir/test-spec.md")

# Capture before printing: git hash-object ignores a failed write to an
# unwritable stdout (still exits 0), but printf's own failure is caught by
# set -e, so success implies the anchor was actually emitted.
anchor=$(printf '%s\n%s\n%s\n%s\n' "$req_hash" "$des_hash" "$tsk_hash" "$tst_hash" \
  | git hash-object --stdin)
printf '%s\n' "$anchor"
