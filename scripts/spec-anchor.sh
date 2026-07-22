#!/bin/sh
# spec-anchor.sh — compute the planwright content anchor for a spec bundle.
#
# Canonical form (format-version 1), as defined in doctrine/spec-format.md
# (REQ-F1.9): the anchor is the git hash of the per-file digest list, in
# canonical order (requirements, design, tasks, test-spec), where tasks.md
# contributes its task-definition content only — task headings plus the
# Deliverables / Done when / Dependencies / Citations / Estimated effort
# field bullets (with their continuation lines), task records sorted by
# task id. Orchestration-state placement (which section a block sits in)
# and the Status / Last activity / Dispatch annotations are excluded, so
# /orchestrate state moves never change the anchor while meaning edits
# always do.
#
# Sanctioned command form recorded in anchor entries:
#   scripts/spec-anchor.sh <spec-dir>
#
# Fails closed (non-zero exit, message on stderr, no anchor printed) on a
# missing or unreadable spec file, a failed extraction, or duplicate task
# ids; a successful exit is the only state that yields an anchor (REQ-F1.9).
#
# Portable: POSIX sh + awk + git (bash 3.2 / BSD compatible, no eval, input
# treated as data only).
set -eu

# Pin the C locale: range patterns are collation-dependent under UTF-8
# locales; anchor bytes and matches must not vary by host locale.
LC_ALL=C
export LC_ALL

# A CDPATH-resolved cd would echo the destination into the command
# substitution below, corrupting the derived lib path (house pattern).
unset CDPATH 2>/dev/null || true

# The canonical tasks.md definition-content extraction comes from the shared
# spec-parse grammar lib (format-grammar D-3, REQ-B1.2). Guarded source
# (REQ-B1.6a): fail closed when the lib is missing, unreadable, or
# syntax-erroring — a bare `.` continuing fail-open would let a private-copy
# fallback or an empty extraction hash a wrong anchor.
here=$(cd "$(dirname "$0")" && pwd -P) || exit 2
spec_parse_sh="$here/spec-parse.sh"
if [ ! -f "$spec_parse_sh" ] || [ ! -r "$spec_parse_sh" ]; then
  echo "spec-anchor: spec-parse.sh missing or unreadable: $spec_parse_sh" >&2
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

req_hash=$(git hash-object "$dir/requirements.md")
des_hash=$(git hash-object "$dir/design.md")
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
tst_hash=$(git hash-object "$dir/test-spec.md")

# Capture before printing: git hash-object ignores a failed write to an
# unwritable stdout (still exits 0), but printf's own failure is caught by
# set -e, so success implies the anchor was actually emitted.
anchor=$(printf '%s\n%s\n%s\n%s\n' "$req_hash" "$des_hash" "$tsk_hash" "$tst_hash" \
  | git hash-object --stdin)
printf '%s\n' "$anchor"
