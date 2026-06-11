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
# Portable: POSIX sh + awk + git (bash 3.2 / BSD compatible, no eval, input
# treated as data only).
set -eu

if [ $# -ne 1 ]; then
  echo "usage: spec-anchor.sh <spec-dir>" >&2
  exit 2
fi

dir=$1
for f in requirements.md design.md tasks.md test-spec.md; do
  if [ ! -f "$dir/$f" ]; then
    echo "spec-anchor: missing $dir/$f" >&2
    exit 1
  fi
done

# Canonical tasks.md definition-content extraction (doctrine/spec-format.md).
# Emits, for each task block sorted by id: the heading line and the five
# definition field bullets with their continuation lines, each terminated by
# a newline. Everything else (section headings, intro prose, state
# annotations, Deferred/Out-of-scope bullets) is excluded.
extract_tasks() {
  awk '
    function sortkey(id,    parts, n, major, minor) {
      n = split(id, parts, ".")
      major = parts[1] + 0
      minor = (n > 1) ? parts[2] + 0 : 0
      return sprintf("%08d.%08d", major, minor)
    }
    /^## /  { in_task = 0; keep = 0; next }
    /^### Task [0-9]/ {
      in_task = 1
      keep = 0
      key = sortkey($3)
      nkeys++
      keys[nkeys] = key
      buf[key] = $0 "\n"
      cur = key
      next
    }
    !in_task { next }
    /^- \*\*(Deliverables|Done when|Dependencies|Citations|Estimated effort):\*\*/ {
      keep = 1
      buf[cur] = buf[cur] $0 "\n"
      next
    }
    /^- /      { keep = 0; next }   # any other top-level bullet (Status, Last activity, Dispatch, unknown)
    /^[ \t]+[^ \t]/ {                # continuation line of the current bullet
      if (keep) buf[cur] = buf[cur] $0 "\n"
      next
    }
    { keep = 0 }                     # blank line or non-bullet prose ends the bullet
    END {
      # insertion sort of keys (POSIX awk has no asort)
      for (i = 2; i <= nkeys; i++) {
        v = keys[i]
        j = i - 1
        while (j >= 1 && keys[j] > v) { keys[j + 1] = keys[j]; j-- }
        keys[j + 1] = v
      }
      for (i = 1; i <= nkeys; i++) printf "%s", buf[keys[i]]
    }
  ' "$1"
}

req_hash=$(git hash-object "$dir/requirements.md")
des_hash=$(git hash-object "$dir/design.md")
tsk_hash=$(extract_tasks "$dir/tasks.md" | git hash-object --stdin)
tst_hash=$(git hash-object "$dir/test-spec.md")

printf '%s\n%s\n%s\n%s\n' "$req_hash" "$des_hash" "$tsk_hash" "$tst_hash" |
  git hash-object --stdin
