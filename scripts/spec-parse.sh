# shellcheck shell=sh
# spec-parse.sh — the shared spec-parse grammar library (sourced, never
# executed; the echo-safety.sh precedent). The single implementation home of
# the spec-parse grammar (format-grammar D-3, D-4 · REQ-B1.1): callers source
# this file and consume stream-emitting functions instead of keeping private
# grammar copies. Parse families land here per the format-grammar task
# sequence. Shipped so far:
#
#   spec_parse_extract_tasks    the canonical `tasks.md` definition-content
#                               extraction (Task 1; REQ-B1.2)
#   spec_parse_header_value     the header-block-scoped header-declaration
#                               parse for `Format-version:` and `Status:`
#                               (Task 2; REQ-B1.3, REQ-A1.2, REQ-A1.3)
#   spec_parse_header_block     the same parse, batched: every declaration in
#                               one pass, for multi-key consumers (Task 2; D-3)
#   spec_parse_parked_map       the parked-map/reference-bullet parse in the
#                               single v2 posture (Task 2; REQ-B1.4,
#                               REQ-C1.1, REQ-C1.3)
#   spec_parse_header_status_line
#                               the header-block `**Status:**` line locator the
#                               content anchor's exclusion is computed from
#                               (anchor-integrity Task 2; REQ-A1.1, REQ-A1.2)
#   spec_parse_printable        the stderr path sanitizer the lib's own
#                               diagnostics use, exported so a caller adding
#                               context to a refusal reuses this byte range
#                               instead of copying it (anchor-integrity Task 2;
#                               REQ-B1.6c)
#   $spec_parse_awk_fence       the fence lexer, as awk source every parser of
#                               spec bundles prepends (Task 6; REQ-C1.2)
#   spec_parse_fence_balance    the fence-imbalance probe behind the
#                               validator's REQ-D1.11 flag (Task 6)
#   $spec_parse_awk_grammar     the line-80 families — REQ bullets, D-ID
#                               headings, task headings, the five task
#                               definition fields, and the
#                               `Dependencies:`/`Citations:` token extractions
#                               — as awk source, the same prepend shape
#                               (Task 8; REQ-B1.5)
#
# With Task 8 the lib holds every family D-4 named, so the grammar has one
# home rather than a decided one.
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
#       strictly line-oriented with no out-of-band delimiters to spoof. The
#       parked-map stream is TAB-separated with fixed-position fields and the
#       only variable-length field (the bullet payload) last; tabs inside
#       parsed content are folded to spaces before emission, and an awk
#       record cannot hold a newline, so no parsed byte can spoof or split a
#       record.
#   (f) check every lib call's exit status — a truncated stream consumed
#       with an unchecked exit is the named fail-open. Capture via command
#       substitution under `set -e`, or guard with `|| ...` explicitly.
#   (g) a `-` source argument reads the CALLER's snapshot from stdin. The lib
#       cannot re-read stdin, so it runs NO NUL screen on that path and the
#       caller owns it. Two in-repo reasons to take it, with different
#       postures:
#         * a single-snapshot property that forbids a second read of the file
#           (orchestrate-select.sh). It screens the file, then snapshots it, so
#           screen and parse see the same bytes — tighter than the path form on
#           the TOCTOU window, though the screen itself is the caller's own
#           inline form, not this lib's fail-closed one.
#         * no file to hand at all: a git blob (spec-validate.sh's baseline
#           `Status:` read). Nothing is screened there, and the shell's command
#           substitution has already dropped any NUL from the blob, so a
#           NUL-bearing baseline parses spliced rather than refused. Accepted:
#           the only consumer is the baseline terminal-transition check, whose
#           failure mode is a check that silently does not run, and the current
#           file's own declaration carries its own finding either way. A new
#           `-` caller with a stake above that must screen before snapshotting.
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

# spec_parse_printable <value> — strip C0 + DEL + C1 bytes (echo-safety.sh's
# canonical range) so a path is safe to echo on stderr, falling back to
# `(unprintable path)` when nothing printable survives. The lib cannot source
# echo-safety.sh itself (a sourced POSIX-sh file cannot portably locate its
# siblings), so this is a deliberate inline copy of the sanitize_printable byte
# range, spawned only on error paths.
#
# Exported rather than lib-internal because a caller that adds context to a
# refusal needs the same byte range: spec-anchor.sh names which of the three
# files carried a malformed header block, and a second copy of the range there
# would be one more thing to keep in step (REQ-B1.6c).
spec_parse_printable() {
  spec_parse__p=$(printf '%s' "$1" | LC_ALL=C tr -d '\000-\037\177\200-\237')
  [ -n "$spec_parse__p" ] || spec_parse__p='(unprintable path)'
  printf '%s' "$spec_parse__p"
}

# spec_parse__readable <path> — internal: refuse a missing, unreadable, or
# non-regular source path. Shared by every path-taking entry point so the
# refusal wording is identical across families.
spec_parse__readable() {
  if [ ! -f "$1" ] || [ ! -r "$1" ]; then
    printf '%s\n' "spec-parse: missing or unreadable: $(spec_parse_printable "$1")" >&2
    return 1
  fi
  return 0
}

# spec_parse__nul_screen <path> — internal: refuse NUL-bearing input
# (REQ-B1.6d, generalizing the drain-gates.sh screen — awk truncates records
# at NUL, which would silently hide parsed lines).
#
# A byte-count mismatch after tr -d '\000' means at least one NUL is present.
# Both counts are captured through checked assignments and verified non-empty
# so a failing wc fails the screen CLOSED — an errored `[ "" -ne "" ]`
# comparison would otherwise skip the screen and let awk parse a NUL-truncated
# stream. A failing tr is not caught by its `||` (a pipeline's exit status is
# the last command's, wc's); it shortens the kept count instead and trips the
# mismatch refusal below — still fail-closed.
#
# Known bound: the file is read separately by the screen and by awk, so a
# concurrent rewrite between the reads can produce a spurious (fail-closed)
# refusal or a screen/parse divergence; no in-repo writer emits NULs, locked
# callers (migrate-format-version.sh) close the window entirely, and snapshot
# callers close it by screening then parsing the snapshot (contract clause g).
spec_parse__nul_screen() {
  spec_parse__total=$(wc -c <"$1") || spec_parse__total=
  spec_parse__kept=$(LC_ALL=C tr -d '\000' <"$1" | wc -c) || spec_parse__kept=
  if [ -z "$spec_parse__total" ] || [ -z "$spec_parse__kept" ]; then
    printf '%s\n' "spec-parse: NUL screen could not read $(spec_parse_printable "$1") (fail closed)" >&2
    return 1
  fi
  if [ "$spec_parse__total" -ne "$spec_parse__kept" ]; then
    printf '%s\n' "spec-parse: NUL byte in $(spec_parse_printable "$1") (malformed input; fail closed)" >&2
    return 1
  fi
  return 0
}

# --- The fence lexer (Task 6; REQ-C1.2, REQ-D1.11 · D-5) ---------------------
#
# doctrine/spec-format.md, *Fenced illustration*, states the rule universally:
# no line inside a fence parses as any element of this format, in ANY parser of
# spec bundles. A rule that broad has to have one implementation, or every
# parser re-derives it and the divergence this lib exists to end simply grows a
# new copy — so the lexer ships as awk SOURCE that each program prepends,
# rather than as a filter process each program pipes through. Prepending keeps
# NR the source line number, which the findings that cite `tasks.md:<n>` need,
# and keeps the parse a single process with a single exit status (REQ-B1.6f).
#
# Usage: put it FIRST in the program text — awk runs pattern-action rules in
# order, so the toggle and the skip have to precede the consumer's own rules —
# and call spec_parse__fence_eof() at the top of the consumer's END block when
# the consumer's contract is to fail closed on malformed input:
#
#   LC_ALL=C awk "$spec_parse_awk_fence"'
#     /^### / { ... }
#     END { spec_parse__fence_eof(); ... }
#   ' <"$file"
#
# The marker is the doctrine's: three or more backticks at column 0. The match
# is prefix-anchored, so a CRLF checkout's trailing CR is irrelevant and the
# lexer needs no CR trim of its own — which matters, because the canonical
# extraction emits source bytes verbatim and must not gain one (a CR-trimming
# lexer would silently move the anchor of every CRLF checkout). A tilde fence is
# deliberately not a toggle, and an INDENTED fence is ordinary content: that is
# what lets doctrine and bundles show a fence as an example without opening one.
#
# `next` rather than blanking: a skipped line reaches no consumer rule at all,
# so a fenced line cannot be mistaken for a blank one either (some consumers
# treat a blank line as ending a bullet's continuation).
#
# The working variable is `spec_parse__fence`, the lib's internal-name
# convention: an awk program's variables are global, and a consumer prepending
# this source would otherwise have to know that a bare `fence` is taken.
# shellcheck disable=SC2016 # awk source, not a shell expansion
spec_parse_awk_fence='
  function spec_parse__fence_eof() {
    if (spec_parse__fence) {
      print "spec-parse: end of file inside an open column-0 code fence (malformed input; fail closed)" > "/dev/stderr"
      exit 3
    }
  }
  /^```/ { spec_parse__fence = !spec_parse__fence; spec_parse__fence_line = NR; next }
  spec_parse__fence { next }
'

# spec_parse_fence_balance <file|-> — the fence-imbalance probe behind the
# validator's REQ-D1.11 flag. An unbalanced column-0 fence count is a
# malformation, never a silent illustration-to-end-of-file: one stray fence
# would otherwise swallow the remainder of a bundle from every reader with no
# signal at all.
#
# Separate from the parse entry points because the two callers want opposite
# things from the same fact. A parse whose output feeds the anchor or the
# derivation must REFUSE (and does, via spec_parse__fence_eof). The validator
# must REPORT, naming the file and the line the fence opened on — so it needs
# the imbalance as data rather than as a refusal.
#
# Exit status:
#   0  balanced; nothing on stdout
#   1  the source could not be read, or is NUL-bearing (REQ-B1.6d)
#   2  usage: wrong argument count
#   3  unbalanced; the opening line number of the unclosed fence on stdout
spec_parse_fence_balance() {
  if [ "$#" -ne 1 ]; then
    printf '%s\n' "spec-parse: usage: spec_parse_fence_balance <file|->" >&2
    return 2
  fi
  if [ "$1" = - ]; then
    LC_ALL=C awk "$spec_parse_awk_fence"'
      END { if (spec_parse__fence) { print spec_parse__fence_line; exit 3 } }
    '
    return $?
  fi
  spec_parse__readable "$1" || return 1
  spec_parse__nul_screen "$1" || return 1
  LC_ALL=C awk "$spec_parse_awk_fence"'
    END { if (spec_parse__fence) { print spec_parse__fence_line; exit 3 } }
  ' <"$1"
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
# Fenced illustration is excluded like any other non-definition content
# (Task 6, REQ-C1.2 — the v1 fence-awareness landing): a fenced column-0 task
# heading conjures no phantom record, and a fenced definition bullet is not
# kept. This is the shipped grammar amendment applied to the anchor path, so a
# bundle that documents the task-block format in a fence anchors on its real
# blocks alone.
#
# Fails closed (non-zero return, message on stderr, no partial stream on
# stdout) on: a missing, unreadable, or non-regular file path (reported as
# "missing or unreadable"), NUL-bearing input (REQ-B1.6d, generalizing the
# drain-gates.sh screen — awk truncates records at NUL, which would
# silently hide definition lines), a NUL screen whose own tooling failed,
# end of file inside an open column-0 fence (return 3), or a duplicate task
# id.
spec_parse_extract_tasks() {
  spec_parse__readable "$1" || return 1
  spec_parse__nul_screen "$1" || return 1
  # awk reads via redirection, not a file operand: a path with a valid
  # identifier before `=` would otherwise parse as an awk variable
  # assignment (and `-` as stdin), silently extracting from the wrong
  # stream — an empty-but-successful parse is the named fail-open.
  LC_ALL=C awk "$spec_parse_awk_fence"'
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
      spec_parse__fence_eof()
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

# --- Header-block declaration parse (Task 2; REQ-B1.3, REQ-A1.2, REQ-A1.3,
# --- REQ-D1.9 · D-6, D-7) ----------------------------------------------------
#
# The header block's extent, per doctrine/spec-format.md *Header-block extent*
# (the REQ-A1.3 amendment has landed and defines this): the file's LEADING
# region, made up of the H1, blank lines, and bolded `**Key:** value` header
# lines, ending at the first line that is none of those. `Format-version:` and
# `Status:` are recognized only inside it, so a column-0 BODY line carrying the
# same literal is inert content and can no longer mask a MISSING header
# declaration (obs:89cf2853, the latent bug D-7 closes).
#
# The H1 is optional here, as the meta-spec's extent definition now states
# explicitly: a conforming file opens with its H1, but partial files and fixture
# bundles legitimately open with the header lines themselves, and requiring an H1
# would fail those closed for a reason the format does not care about.
#
# Fences need no separate guard: a column-0 fence line is neither blank,
# an H1, nor a header line, so it ENDS the header block — a fenced example
# declaration is already outside every recognized block, whether it sits above
# or below the real one. A CR-only line on a CRLF checkout is normalized to
# blank first, so line endings alone cannot close the block early.
#
# One awk program serves all three entry points. `mode` selects the family:
# unset (the default the two original entry points leave it at) is the
# declaration parse, where `key` set prints that one declaration's value
# (spec_parse_header_value) and `key` empty emits the whole block as a record
# stream (spec_parse_header_block); `mode=statusline` prints the `**Status:**`
# line NUMBER instead (spec_parse_header_status_line). One implementation, so
# the forms cannot disagree about where the header block starts and ends —
# which is the whole point of the lib, and load-bearing for the content anchor,
# whose exclusion must land on exactly the line the value parse reads. It is
# held in a variable rather than inlined because the file and stdin forms
# differ only in the redirection.
#
# The block's positional extent is tracked by two flags the declaration modes
# ignore: `hdrlines` counts the lines the leading region actually consumed (0
# means there is no such region — the file opens with body content), and `body`
# records that at least one line followed it. The meta-spec calls a block with
# neither a leading region at all, nor any body content after it, MALFORMED;
# `mode=statusline` is the consumer that fails closed on it.
#
# Keys are extracted at the first `:**` and screened against the header-key
# grammar `^[A-Za-z][A-Za-z-]*$`, so a malformed key emits no record and cannot
# forge one; the value is raw bytes and sits LAST in the record, so an embedded
# tab cannot split it (REQ-B1.6b) and the batched form stays byte-faithful to
# the single-key form.
#
# Known bound: that grammar admits no SPACE, so `**Last reviewed:**` — a key the
# meta-spec header block does define — is not lookupable through either entry
# point and emits no batched record. No in-repo consumer reads it, and the two
# load-bearing keys plus `Execution:` and `Superseded-by:` all conform; a future
# consumer that needs a space-bearing key widens the grammar here (and in
# spec_parse_header_value's argument screen) rather than working around it, so
# the screen stays the single definition.
# shellcheck disable=SC2016 # $0 is an awk field, not a shell expansion
spec_parse__header_awk='
  function loadbearing(k) { return (k == "Format-version" || k == "Status") }
  { sub(/\r$/, "") }
  !past {
    if (/^[ \t]*$/ || /^# / || /^\*\*[^*]+:\*\*/) {
      hdrlines++
      if (/^\*\*[^*]+:\*\*/) {
        p = index($0, ":**")
        if (p > 3) {
          k = substr($0, 3, p - 3)
          if (k ~ /^[A-Za-z][A-Za-z-]*$/) {
            n[k]++
            if (n[k] == 1) {
              v = substr($0, p + 3)
              sub(/^[ \t]*/, "", v)
              sub(/[ \t\r]+$/, "", v)
              val[k] = v
              ord[++nk] = k
              if (k == "Status") statusnr = NR
            }
          }
        }
      }
      next
    }
    past = 1
  }
  { body = 1 }
  END {
    if (mode == "statusline") {
      if (hdrlines == 0) {
        print "spec-parse: no leading header block (malformed; fail closed)" > "/dev/stderr"
        exit 4
      }
      if (!body) {
        print "spec-parse: header block reaches end of file with no body content (malformed; fail closed)" > "/dev/stderr"
        exit 4
      }
      if (n["Status"] > 1) {
        printf "spec-parse: %d in-header Status: declarations (a contradictory duplicate has no honest positional winner; fail closed)\n", n["Status"] > "/dev/stderr"
        exit 3
      }
      print statusnr + 0
      exit 0
    }
    if (key != "") {
      if (strict && n[key] > 1) {
        printf "spec-parse: %d in-header %s: declarations (a contradictory duplicate has no honest positional winner; fail closed)\n", n[key], key > "/dev/stderr"
        exit 3
      }
      if (n[key] > 0) print val[key]
      exit 0
    }
    for (i = 1; i <= nk; i++) {
      k = ord[i]
      if (loadbearing(k) && n[k] > 1) printf "hdrdup\t%s\t%d\n", k, n[k]
      else printf "hdr\t%s\t%s\n", k, val[k]
    }
  }
'

# spec_parse_header_value <file|-> <key> — print the value of the `**<key>:**`
# declaration found in the source's header block, with the trailing CR and
# hard-break whitespace trimmed and every other byte raw (REQ-B1.6c: anchor
# stability forbids lib-side mutation, so echo discipline stays at the
# caller's output sites).
#
# The duplicate-declaration rule (REQ-A1.2, REQ-D1.9, D-6) applies to the two
# LOAD-BEARING header keys, `Format-version:` and `Status:`: more than one
# in-header declaration of either makes that declaration unparseable, so the
# parse fails closed rather than picking a positional winner each consumer
# could pick differently. Any other key keeps first-match-wins — D-6 scopes
# the rule to the two keys that drive version keying and the stored-status
# whitelists, and the validator owns the findings for the rest.
#
# Exit status:
#   0  the declaration's value on stdout, or EMPTY when the header block
#      carries no such declaration (an absent declaration is a fact the
#      caller distinguishes from a bad one, exactly as before the re-point)
#   1  the source could not be read, or is NUL-bearing (REQ-B1.6d)
#   2  usage: wrong argument count, or a key failing the header-key grammar
#      `^[A-Za-z][A-Za-z-]*$` (validated before it is interpolated anywhere)
#   3  a duplicate in-header declaration of a load-bearing key (fail closed)
spec_parse_header_value() {
  if [ "$#" -ne 2 ]; then
    printf '%s\n' "spec-parse: usage: spec_parse_header_value <file|-> <key>" >&2
    return 2
  fi
  spec_parse__hk="$2"
  case "$spec_parse__hk" in
    '' | *[!A-Za-z-]* | [!A-Za-z]*)
      printf '%s\n' "spec-parse: invalid header key '$(spec_parse_printable "$spec_parse__hk")' (must match ^[A-Za-z][A-Za-z-]*\$)" >&2
      return 2
      ;;
  esac
  case "$spec_parse__hk" in
    Format-version | Status) spec_parse__hstrict=1 ;;
    *) spec_parse__hstrict=0 ;;
  esac
  if [ "$1" = - ]; then
    LC_ALL=C awk -v key="$spec_parse__hk" -v strict="$spec_parse__hstrict" \
      "$spec_parse__header_awk"
    return $?
  fi
  spec_parse__readable "$1" || return 1
  spec_parse__nul_screen "$1" || return 1
  LC_ALL=C awk -v key="$spec_parse__hk" -v strict="$spec_parse__hstrict" \
    "$spec_parse__header_awk" <"$1"
}

# spec_parse_header_block <file|-> — emit EVERY header-block declaration in one
# pass, for consumers that need more than one key from the same file. This is
# D-3's batchability clause made operational: a caller that needs Status and
# Format-version (and the Execution pointer) pays ONE lib invocation for the
# file instead of one per key, so a whole-corpus sweep does not multiply file
# reads or process spawns.
#
# Records, in file order (values raw, last field, tabs inside a value therefore
# harmless):
#   hdr<TAB><key><TAB><value>
#   hdrdup<TAB><key><TAB><count>
#
# The fail-closed duplicate posture survives batching BY CONSTRUCTION: a
# LOAD-BEARING key (`Format-version:`, `Status:`) declared more than once emits
# no `hdr` record at all, only `hdrdup`, so a consumer looking the key up finds
# it ABSENT and the `hdrdup` record says why — there is no positional winner
# sitting in the stream for a forgetful consumer to read (REQ-A1.2, REQ-D1.9,
# D-6). A non-load-bearing key keeps first-match-wins and emits its first
# value, matching the single-key form.
#
# Exit status: 0 the stream on stdout (empty when the block declares nothing);
# 1 the source could not be read or is NUL-bearing (REQ-B1.6d); 2 usage.
spec_parse_header_block() {
  if [ "$#" -ne 1 ]; then
    printf '%s\n' "spec-parse: usage: spec_parse_header_block <file|->" >&2
    return 2
  fi
  if [ "$1" = - ]; then
    LC_ALL=C awk -v key="" -v strict=0 "$spec_parse__header_awk"
    return $?
  fi
  spec_parse__readable "$1" || return 1
  spec_parse__nul_screen "$1" || return 1
  LC_ALL=C awk -v key="" -v strict=0 "$spec_parse__header_awk" <"$1"
}

# spec_parse_header_status_line <file|-> — print the 1-based line number of the
# `**Status:**` declaration inside the source's single leading header block, or
# `0` when a well-formed block declares none. The content anchor's Status
# exclusion is computed from this number (anchor-integrity D-2, REQ-A1.1,
# REQ-A1.2): the caller drops exactly that line, so the grammar decision (which
# line, if any, is the header declaration) stays here with the rest of the
# header family and the byte surgery stays at the caller.
#
# A line number rather than a reduced stream on purpose: the anchor's input must
# be byte-exact, and a stream captured through command substitution loses a
# missing final newline. A small integer survives the round trip intact.
#
# The bounding rules are the header family's, unchanged: a `**Status:**` line in
# body prose or inside a column-0 fence is outside every header block and is
# never reported, so it stays anchored content.
#
# Exit status:
#   0  the line number on stdout (`0` when the block declares no `**Status:**` —
#      the benign case the anchor treats as "exclude nothing")
#   1  the source could not be read, or is NUL-bearing (REQ-B1.6d)
#   2  usage: wrong argument count
#   3  a duplicate in-header `**Status:**` declaration (fail closed, matching
#      spec_parse_header_value's posture on the load-bearing keys)
#   4  a malformed header block: no leading header region at all, or one that
#      reaches end of file with no body content after it (doctrine's
#      *Header-block extent*). Fail closed — never a silent fallback to
#      hashing the whole file.
spec_parse_header_status_line() {
  if [ "$#" -ne 1 ]; then
    printf '%s\n' "spec-parse: usage: spec_parse_header_status_line <file|->" >&2
    return 2
  fi
  if [ "$1" = - ]; then
    LC_ALL=C awk -v key="" -v strict=0 -v mode=statusline "$spec_parse__header_awk"
    return $?
  fi
  spec_parse__readable "$1" || return 1
  spec_parse__nul_screen "$1" || return 1
  LC_ALL=C awk -v key="" -v strict=0 -v mode=statusline "$spec_parse__header_awk" <"$1"
}

# --- Parked-map / reference-bullet parse (Task 2; REQ-B1.4, REQ-C1.1,
# --- REQ-C1.3 · D-8, and doctrine/spec-format.md *Fenced illustration*) -------
#
# The single v2 posture (D-8), the one all four v2 parsers consume so it cannot
# re-diverge:
#
#   * a column-0 code-fence line toggles illustration mode, and no fenced line
#     parses as anything — heading, bullet, or otherwise. The normative rule is
#     doctrine/spec-format.md, *Fenced illustration*, which this parse
#     implements. End-of-file inside an open fence is MALFORMED input, not
#     illustration-to-end-of-file: an
#     unterminated fence would otherwise swallow the rest of a bundle from
#     every parser with no signal, so the parse fails closed.
#   * every line is CRLF-trimmed before matching, so a CRLF checkout cannot
#     hide a payload section (the defect that let a live Awaiting-input bullet
#     stop blocking derived Done, REQ-C1.3) or a reference bullet.
#   * a `## ` heading sets the section, trailing whitespace tolerated; the
#     three human-payload sections are `Awaiting input`, `Deferred`, and
#     `Out of scope`. Suffixed variants ("## Deferred (legacy)") stay ordinary
#     headings.
#   * a reference bullet is a complete `**Task <token>**` bold lead whose token
#     has no inner whitespace. A lead WITH inner whitespace is normally a plain
#     prose bullet the format allows in Deferred / Out of scope
#     ("**Task force assembled.**") and is silently tolerated — but a NEAR-MISS
#     (the whitespace-trimmed remainder is a valid id, or the token is only
#     digits, dots, and whitespace) is a park a human meant and failed to
#     write, so it is emitted as rejected rather than silently skipped.
#   * an unterminated bold lead is malformed Markdown, which markdown lint
#     owns; it is neither a reference nor a rejection.
#
# Classification is the lib's job; what to DO with each record is the
# consumer's. Records are emitted in file order with no de-duplication: the
# validator needs both bullets of a twice-parked task, while the readers apply
# first-match-wins on their own (membership and first-hit lookups both make
# repeats harmless).
#
# Record framing (REQ-B1.6b) — TAB-separated, fixed-position fields, the only
# variable-length field last, tabs inside parsed content folded to spaces:
#   ref<TAB><id><TAB><class><TAB><line><TAB><payload>
#   refbad<TAB><raw-token><TAB><class><TAB><line>
# <class> is one of awaiting-input | deferred | out-of-scope. <id> has passed
# the task-id grammar `^[0-9]+(\.[0-9]+)?$`; <raw-token> has NOT, and is raw
# untrusted content the consumer sanitizes at its output site (REQ-B1.6c).
# Reference-bullet CLASSIFICATION and task-id grammar validation stay distinct
# gates (REQ-B1.6e): an emitted id is still the consumer's to re-validate
# before use.
#
# Records are buffered and emitted in END, so a fail-closed refusal never
# leaves a partial stream on stdout (the extract_tasks property, REQ-B1.6f).
# shellcheck disable=SC2016 # $0 is an awk field, not a shell expansion
spec_parse__parked_awk='
  function classof(s) {
    if (s == "Awaiting input") return "awaiting-input"
    if (s == "Deferred") return "deferred"
    if (s == "Out of scope") return "out-of-scope"
    return ""
  }
  { sub(/\r$/, "") }
  /^## / { sec = substr($0, 4); sub(/[ \t]+$/, "", sec); next }
  /^- \*\*Task / {
    cls = classof(sec)
    if (cls == "") next
    line = $0
    sub(/^- \*\*Task /, "", line)
    i = index(line, "**")
    if (i == 0) next             # unterminated bold lead: markdown lint owns it
    id = substr(line, 1, i - 1)
    payload = substr(line, i + 2)
    sub(/^[ \t]+/, "", payload)
    if (id ~ /[ \t]/) {
      probe = id
      sub(/^[ \t]+/, "", probe)
      sub(/[ \t]+$/, "", probe)
      if (probe !~ /^[0-9]+(\.[0-9]+)?$/ && id !~ /^[0-9. \t]+$/) next
    }
    gsub(/\t/, " ", id)          # tabs would split the record
    gsub(/\t/, " ", payload)
    if (id !~ /^[0-9]+(\.[0-9]+)?$/) {
      out = out sprintf("refbad\t%s\t%s\t%d\n", id, cls, NR)
      next
    }
    out = out sprintf("ref\t%s\t%s\t%d\t%s\n", id, cls, NR, payload)
    next
  }
  END {
    spec_parse__fence_eof()
    printf "%s", out
  }
'

# spec_parse_parked_map <file|-> — emit the source's parked-map record stream
# (framing and posture above). Exit status:
#   0  the stream on stdout (empty when nothing is parked)
#   1  the source could not be read, or is NUL-bearing (REQ-B1.6d)
#   2  usage: wrong argument count
#   3  end-of-file inside an open column-0 fence (fail closed, no stream)
spec_parse_parked_map() {
  if [ "$#" -ne 1 ]; then
    printf '%s\n' "spec-parse: usage: spec_parse_parked_map <file|->" >&2
    return 2
  fi
  if [ "$1" = - ]; then
    LC_ALL=C awk "$spec_parse_awk_fence$spec_parse__parked_awk"
    return $?
  fi
  spec_parse__readable "$1" || return 1
  spec_parse__nul_screen "$1" || return 1
  LC_ALL=C awk "$spec_parse_awk_fence$spec_parse__parked_awk" <"$1"
}

# --- The line-80 grammar (Task 8; REQ-B1.5 · D-4) ----------------------------
#
# The last families D-4 named: requirement bullets, D-ID headings, task
# headings, the five task definition fields, and the `Dependencies:` /
# `Citations:` token extractions. Named for the frozen legacy observation
# (line 80) that recorded them living in three independent encodings across
# scripts/spec-validate.sh, scripts/orchestrate-select.sh, and
# scripts/spec-model.sh.
#
# Shipped as awk SOURCE each program prepends, the $spec_parse_awk_fence
# precedent and for the same reasons: those three consumers each drive their
# own awk program over the file, so a filter process would cost them NR (which
# the validator's findings cite as `<file>:<n>`) and split one parse into two
# exit statuses (REQ-B1.6f). Composes with the fence lexer by concatenation —
# put the fence source FIRST, since its rules must run before any consumer
# rule, and function definitions are order-free:
#
#   LC_ALL=C awk "$spec_parse_awk_fence$spec_parse_awk_grammar"'
#     spec_parse_is_task_heading($0) { id = spec_parse_task_id($0); ... }
#   ' <"$file"
#
# Every function takes the WHOLE line and returns a scalar, so a consumer never
# re-derives a lead pattern to slice past: `spec_parse_dec_title` gives what
# follows the decision id, `spec_parse_task_field_value` what follows a
# definition bullet's bolded lead. The list-returning functions
# (`spec_parse_req_tokens`, `spec_parse_dep_ids`, `spec_parse_cite_ids`) return
# a SPACE-PADDED list (" 1 6 "), which the callers either split or membership-
# test with `index(list, " " x " ")` — the space padding is what makes that test
# whole-token.
#
# Known bound, deliberate: no CR trim. The task-heading parse reads the third
# whitespace field exactly as the three pre-lib copies did, and the canonical
# extraction (spec_parse_extract_tasks) reads the same field for its sort key,
# where a CR trim would move the content anchor of every CRLF checkout
# (REQ-B1.2 forbids that). CRLF tolerance lives in the families that CAN carry
# it — the header-block and parked-map parses, which trim before matching.
#
# Grammars, all pinned to the meta-spec (doctrine/spec-format.md):
#   REQ id      REQ-<letter><n>.<m>, bulleted as `- **<id>**` at column 0
#   D id        D-<n>, headed as `### D-<n>: <title>`
#   task id     <n> or <n>.<m>, headed as `### Task <id> — <title>`
# shellcheck disable=SC2016,SC2034 # awk source, not a shell expansion; the
# consumers that prepend it to their own awk program are the only users, and
# they live outside this file
spec_parse_awk_grammar='
  # --- Requirement bullets -------------------------------------------------
  # The id lead of a requirement bullet, or "" when the line is not one. The
  # bolded lead is `- **` <id> `**`, so a caller wanting the text after it
  # slices from length(id) + 7 rather than reading RLENGTH back out.
  function spec_parse_req_bullet_id(s) {
    if (match(s, /^- \*\*REQ-[A-Z][0-9]+\.[0-9]+\*\*/))
      return substr(s, 5, RLENGTH - 6)
    return ""
  }
  # Every REQ id token anywhere on the line, space-padded and in line order.
  # A test-spec entry heading may name more than one, and coverage counts them
  # all — the property the single-match form below cannot express.
  function spec_parse_req_tokens(s,   out) {
    out = " "
    while (match(s, /REQ-[A-Z][0-9]+\.[0-9]+/)) {
      out = out substr(s, RSTART, RLENGTH) " "
      s = substr(s, RSTART + RLENGTH)
    }
    return out
  }
  # The FIRST REQ id token on the line, or "" — for callers that model one
  # entry per heading.
  function spec_parse_req_token(s) {
    if (match(s, /REQ-[A-Z][0-9]+\.[0-9]+/)) return substr(s, RSTART, RLENGTH)
    return ""
  }

  # --- Decision headings ---------------------------------------------------
  # An ATTEMPT at a decision heading: the `### D-` lead, conforming or not.
  # The distinction the malformed-heading finding rests on — without it a typo
  # ("### D-four: …") reads as ordinary prose and is never reported.
  function spec_parse_dec_attempt(s) { return (s ~ /^### D-/) }
  # The decision id of a CONFORMING heading (`### D-<n>: <title>`, colon
  # required), or "".
  function spec_parse_dec_id(s) {
    if (s !~ /^### D-[0-9]+:/) return ""
    match(s, /^### D-[0-9]+/)
    return substr(s, 5, RLENGTH - 4)
  }
  # What follows the id: the title, colon and surrounding whitespace removed.
  function spec_parse_dec_title(s,   id, line) {
    id = spec_parse_dec_id(s)
    if (id == "") return ""
    line = substr(s, length(id) + 5)
    sub(/^:[ \t]*/, "", line)
    sub(/[ \t]+$/, "", line)
    return line
  }

  # --- Task headings -------------------------------------------------------
  function spec_parse_is_task_id(s) { return (s ~ /^[0-9]+(\.[0-9]+)?$/) }
  function spec_parse_is_task_heading(s) { return (s ~ /^### Task /) }
  # The task id of a heading whose third field passes the id grammar, or "".
  # Classification and grammar validation stay distinct gates (REQ-B1.6e): a
  # line can BE a task heading and still yield no id.
  function spec_parse_task_id(s,   a, n) {
    if (!spec_parse_is_task_heading(s)) return ""
    n = split(s, a, " ")
    if (n < 3) return ""
    if (!spec_parse_is_task_id(a[3])) return ""
    return a[3]
  }
  # The title past the id and its em dash, or "" when the heading carries no
  # conforming id.
  function spec_parse_task_title(s,   id, t) {
    id = spec_parse_task_id(s)
    if (id == "") return ""
    t = s
    sub(/^### Task [0-9]+(\.[0-9]+)?[[:space:]]*/, "", t)
    sub(/^—[[:space:]]*/, "", t)
    return t
  }

  # --- Task definition fields ----------------------------------------------
  # The canonical name of the definition field a bullet declares, or "" for
  # anything else (a state annotation, a prose bullet). The same five fields
  # the canonical extraction keeps.
  function spec_parse_task_field(s) {
    if (s ~ /^- \*\*Deliverables:\*\*/) return "deliverables"
    if (s ~ /^- \*\*Done when:\*\*/) return "donewhen"
    if (s ~ /^- \*\*Dependencies:\*\*/) return "dependencies"
    if (s ~ /^- \*\*Citations:\*\*/) return "citations"
    if (s ~ /^- \*\*Estimated effort:\*\*/) return "effort"
    return ""
  }
  # The payload after the bolded lead of a definition bullet, leading
  # whitespace left intact (a caller that folds whitespace does it at its own
  # output site).
  function spec_parse_task_field_value(s) {
    sub(/^- \*\*[^*]+:\*\*/, "", s)
    return s
  }

  # --- Dependency tokens ---------------------------------------------------
  # The local dependency ids a `**Dependencies:**` bullet declares, space-
  # padded and in line order. One extraction where there had been two, so the
  # selector graph and the model graph cannot disagree about an edge.
  #
  # Rules, each inherited from one of the two pre-lib copies and kept for the
  # reason it was there:
  #   * a parenthetical is dropped whole, together with any cross-spec carry
  #     clause it introduces ("(REQ-A1.8 / D-9 - the producer is elsewhere)"),
  #     so ids from another bundle are never extracted (from the selector);
  #   * commas AND semicolons separate, because a prose list uses both;
  #   * tokens are grammar-validated whole rather than digit-scraped out of
  #     the residue (from the bundle reader) - so an unqualified "D-9" sitting
  #     outside a parenthetical contributes no phantom edge 9;
  #   * a trailing run of sentence periods is stripped per token, so a prose
  #     entry ("Task 1.", "2.1.") still yields its id. A task id always ends
  #     in a digit, so this only ever removes punctuation.
  # (No apostrophes in this awk program: it is single-quoted in the shell.)
  function spec_parse_dep_ids(s,   n, a, i, tok, out) {
    sub(/.*\*\*Dependencies:\*\*/, "", s)
    sub(/\(.*/, "", s)
    gsub(/[,;]/, " ", s)
    n = split(s, a, " ")
    out = " "
    for (i = 1; i <= n; i++) {
      tok = a[i]
      sub(/\.+$/, "", tok)
      if (spec_parse_is_task_id(tok)) out = out tok " "
    }
    return out
  }

  # --- Citation tokens -----------------------------------------------------
  # Every D-id and REQ-id token on the line, space-padded and in line order,
  # with `owner` (the id of the citing element) skipped so an inline
  # `*(Cites: ...)*` on a requirement bullet never self-cites. Deliberately
  # reads the WHOLE line rather than slicing past a lead: the two shapes that
  # carry citations are a `- **Citations:**` bullet and an inline annotation,
  # and scraping the line serves both. Duplicates are preserved - the grammar
  # classifies, and de-duplication is left to each consumer.
  function spec_parse_cite_ids(s, owner,   n, a, i, tok, out) {
    gsub(/[^A-Za-z0-9.-]+/, " ", s)
    n = split(s, a, " ")
    out = " "
    for (i = 1; i <= n; i++) {
      tok = a[i]
      sub(/\.$/, "", tok)
      if (tok == owner) continue
      if (tok ~ /^D-[0-9]+$/ || tok ~ /^REQ-[A-Z][0-9]+\.[0-9]+$/) out = out tok " "
    }
    return out
  }
'
