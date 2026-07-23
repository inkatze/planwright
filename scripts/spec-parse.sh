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
# Naming: exported entry points are namespaced `spec_parse_*` (a
# multi-family lib sourced alongside echo-safety.sh needs namespace
# hygiene; echo-safety predates the convention and keeps its unprefixed
# name). Internal helpers AND working variables are `spec_parse__*`
# (double underscore): POSIX sh has no locals, so a sourced lib's
# assignments land in the consumer's global scope, where a generic name
# would clobber consumer state.
#
# Consumer contract (REQ-B1.6):
#   (a) fail closed when this file cannot be sourced — guard the source with
#       an existence/readability check plus `|| exit`; a bare POSIX `.` of a
#       missing file continuing fail-open is forbidden. Canonical block:
#
#         spec_parse_sh="$here/spec-parse.sh"
#         if [ ! -f "$spec_parse_sh" ] || [ ! -r "$spec_parse_sh" ]; then
#           printf '%s\n' "<caller>: spec-parse.sh missing or unreadable: $spec_parse_sh" >&2
#           exit 2
#         fi
#         # shellcheck source=scripts/spec-parse.sh
#         . "$spec_parse_sh" || exit 2
#
#   (b) stream-record framing is injection-safe. The extraction stream is
#       strictly line-oriented with no out-of-band delimiters to spoof;
#       future tagged-record families must state their framing here.
#   (f) check every lib call's exit status — a truncated stream consumed
#       with an unchecked exit is the named fail-open. Capture via command
#       substitution under `set -e`, or guard with `|| ...` explicitly.
#
# Sanitization boundary (REQ-B1.6c): the emitted stream is raw bytes —
# anchor stability forbids lib-side mutation — and echo discipline remains
# at each caller's output sites. The lib's own stderr diagnostics strip
# non-printables from parsed content and echoed paths before printing
# (printf, never echo).
#
# Portable: POSIX sh + awk + tr + wc (bash 3.2 / BSD compatible, no eval,
# input treated as data only). LC_ALL=C is pinned on the locale-sensitive
# commands (tr, awk); wc -c is byte-counting and locale-free. The awk
# duplicate-id diagnostic uses `print > "/dev/stderr"`, emulated by every
# supported awk (one-true-awk, gawk, mawk, busybox) though not literally
# POSIX. Matches and emitted bytes do not vary by the caller's host locale.

# spec_parse__printable <value> — internal: strip C0 + DEL + C1 bytes
# (echo-safety.sh's canonical range) for the lib's own stderr diagnostics.
# The lib cannot source echo-safety.sh itself (a sourced POSIX-sh file
# cannot portably locate its siblings), so this is a deliberate inline copy
# of the sanitize_printable byte range, spawned only on error paths.
spec_parse__printable() {
  spec_parse__p=$(printf '%s' "$1" | LC_ALL=C tr -d '\000-\037\177\200-\237')
  [ -n "$spec_parse__p" ] || spec_parse__p='(unprintable path)'
  printf '%s' "$spec_parse__p"
}

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
# Id-grammar bounds (shared byte-for-byte with the three pre-lib copies):
# task ids follow the meta-spec grammar `<n>` or `<n>.<m>`. The sort key
# reads at most two numeric components of up to eight digits — ids with a
# third component (`2.5.1`), leading zeros (`007` vs `7`), a trailing `.0`
# (`2.0` vs `2`), or a non-numeric suffix collide onto one key and are
# refused as duplicates; components at or above 10^8 break the numeric
# ordering. Conforming bundles are unaffected.
#
# Fails closed (non-zero return, message on stderr, no partial stream on
# stdout) on: a missing, unreadable, or non-regular file path (reported as
# "missing or unreadable"), NUL-bearing input (REQ-B1.6d, generalizing the
# drain-gates.sh screen — awk truncates records at NUL, which would
# silently hide definition lines), a NUL screen whose own tooling failed,
# or a duplicate task id.
spec_parse_extract_tasks() {
  if [ ! -f "$1" ] || [ ! -r "$1" ]; then
    printf '%s\n' "spec-parse: missing or unreadable: $(spec_parse__printable "$1")" >&2
    return 1
  fi
  # NUL screen before the parse: a byte-count mismatch after tr -d '\000'
  # means at least one NUL is present. Both counts are captured through
  # checked assignments and verified non-empty so a failing wc fails the
  # screen CLOSED — an errored `[ "" -ne "" ]` comparison would otherwise
  # skip the screen and let awk parse a NUL-truncated stream (REQ-B1.6d).
  # A failing tr is not caught by its `||` (a pipeline's exit status is the
  # last command's, wc's); it shortens the kept count instead and trips the
  # mismatch refusal below — still fail-closed.
  # Known bound: the file is read separately by the screen and by awk, so a
  # concurrent rewrite between the reads can produce a spurious (fail-closed)
  # refusal or a screen/parse divergence; no in-repo writer emits NULs, and
  # locked callers (migrate-format-version.sh) close the window entirely.
  spec_parse__total=$(wc -c <"$1") || spec_parse__total=
  spec_parse__kept=$(LC_ALL=C tr -d '\000' <"$1" | wc -c) || spec_parse__kept=
  if [ -z "$spec_parse__total" ] || [ -z "$spec_parse__kept" ]; then
    printf '%s\n' "spec-parse: NUL screen could not read $(spec_parse__printable "$1") (fail closed)" >&2
    return 1
  fi
  if [ "$spec_parse__total" -ne "$spec_parse__kept" ]; then
    printf '%s\n' "spec-parse: NUL byte in $(spec_parse__printable "$1") (malformed input; fail closed)" >&2
    return 1
  fi
  # awk reads via redirection, not a file operand: a path with a valid
  # identifier before `=` would otherwise parse as an awk variable
  # assignment (and `-` as stdin), silently extracting from the wrong
  # stream — an empty-but-successful parse is the named fail-open.
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
  ' <"$1"
}
