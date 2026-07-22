# shellcheck shell=sh
# spec-parse.sh — the shared spec-parse grammar library (sourced, never
# executed; the echo-safety.sh precedent). The single implementation home of
# the spec-parse grammar (format-grammar D-3, D-4 · REQ-B1.1): callers source
# this file and consume stream-emitting functions instead of keeping private
# grammar copies. Parse families land here per the format-grammar task
# sequence — this founding revision ships the canonical `tasks.md`
# definition-content extraction (REQ-B1.2); the header-declaration and
# parked-map parses, fence-awareness, and the line-80 surfaces follow as
# their tasks land.
#
# Surface: internal-only (format-grammar kickoff brief, risk register row 6).
# In-repo scripts are the only supported consumers; no adopter stability
# promise is made for function names or output framing.
#
# Consumer contract (REQ-B1.6):
#   (a) fail closed when this file cannot be sourced — guard the source with
#       an existence/readability check plus `|| exit`; a bare POSIX `.` of a
#       missing file continuing fail-open is forbidden;
#   (f) check every lib call's exit status — a truncated stream consumed
#       with an unchecked exit is the named fail-open. Capture via command
#       substitution under `set -e`, or guard with `|| ...` explicitly.
#
# Sanitization boundary (REQ-B1.6c): the emitted stream is raw bytes —
# anchor stability forbids lib-side mutation — and echo discipline remains
# at each caller's output sites. The lib's own stderr diagnostics strip
# non-printables from parsed content before echoing it.
#
# Portable: POSIX sh + awk (bash 3.2 / BSD compatible, no eval, input
# treated as data only). Locale is pinned per invocation (LC_ALL=C on the
# commands that read untrusted bytes) so matches and emitted bytes do not
# vary by the caller's host locale.

# spec_parse_extract_tasks <tasks.md> — the canonical `tasks.md`
# definition-content extraction (doctrine/spec-format.md). Emits, for each
# task block sorted numerically by task id (component-wise: 2 < 2.5 < 10):
# the heading line and the five definition field bullets — Deliverables,
# Done when, Dependencies, Citations, Estimated effort — with their indented
# continuation lines, each line terminated by a newline, byte-for-byte as in
# the source. Everything else (section headings, intro prose, state
# annotations, Deferred / Out-of-scope bullets, non-task H3 content) is
# excluded.
#
# Fails closed (non-zero return, message on stderr, no partial stream on
# stdout) on: a missing or unreadable file, NUL-bearing input (REQ-B1.6d,
# generalizing the drain-gates.sh screen — awk truncates records at NUL,
# which would silently hide definition lines), or a duplicate task id.
spec_parse_extract_tasks() {
  if [ ! -f "$1" ] || [ ! -r "$1" ]; then
    echo "spec-parse: missing or unreadable: $1" >&2
    return 1
  fi
  # NUL screen before the parse: a byte-count mismatch after tr -d '\000'
  # means at least one NUL is present.
  if [ "$(wc -c <"$1")" -ne "$(LC_ALL=C tr -d '\000' <"$1" | wc -c)" ]; then
    echo "spec-parse: NUL byte in $1 (malformed input; fail closed)" >&2
    return 1
  fi
  LC_ALL=C awk '
    function sortkey(id,    parts, n, major, minor) {
      # "\\." (ERE literal dot) rather than ".": a single-char separator is
      # already literal in POSIX awk, but the escape says so explicitly.
      n = split(id, parts, "\\.")
      major = parts[1] + 0
      minor = (n > 1) ? parts[2] + 0 : 0
      return sprintf("%08d.%08d", major, minor)
    }
    /^## /  { in_task = 0; keep = 0; next }
    /^### Task [0-9]/ {
      in_task = 1
      keep = 0
      key = sortkey($3)
      if (key in buf) {
        # Two blocks with the same id would silently overwrite each other;
        # fail closed rather than emit an incomplete stream (REQ-F1.9).
        # The echoed id is parsed content: strip non-printables first
        # (REQ-B1.6c).
        bad = $3
        gsub(/[^[:print:]]/, "", bad)
        print "spec-parse: duplicate task id " bad > "/dev/stderr"
        dup = 1
        exit 1
      }
      nkeys++
      keys[nkeys] = key
      buf[key] = $0 "\n"
      cur = key
      next
    }
    /^### / { in_task = 0; keep = 0; next }   # non-task H3 ends the block too
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
      if (dup) exit 1
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
