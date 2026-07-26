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
#
# v1 fence-awareness of the canonical extraction and the line-80 surfaces
# (REQ bullets, D-headings, `Dependencies:`/`Citations:` tokens) follow as
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

# spec_parse__readable <path> — internal: refuse a missing, unreadable, or
# non-regular source path. Shared by every path-taking entry point so the
# refusal wording is identical across families.
spec_parse__readable() {
  if [ ! -f "$1" ] || [ ! -r "$1" ]; then
    printf '%s\n' "spec-parse: missing or unreadable: $(spec_parse__printable "$1")" >&2
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
    printf '%s\n' "spec-parse: NUL screen could not read $(spec_parse__printable "$1") (fail closed)" >&2
    return 1
  fi
  if [ "$spec_parse__total" -ne "$spec_parse__kept" ]; then
    printf '%s\n' "spec-parse: NUL byte in $(spec_parse__printable "$1") (malformed input; fail closed)" >&2
    return 1
  fi
  return 0
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
  spec_parse__readable "$1" || return 1
  spec_parse__nul_screen "$1" || return 1
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

# --- Header-block declaration parse (Task 2; REQ-B1.3, REQ-A1.2, REQ-A1.3,
# --- REQ-D1.9 · D-6, D-7) ----------------------------------------------------
#
# The header block's extent, as this lib implements it until the REQ-A1.3
# meta-spec amendment lands (format-grammar Task 5): the file's LEADING
# region, made up of the H1, blank lines, and bolded `**Key:** value` header
# lines, ending at the first line that is none of those. `Format-version:` and
# `Status:` are recognized only inside it, so a column-0 BODY line carrying the
# same literal is inert content and can no longer mask a MISSING header
# declaration (obs:89cf2853, the latent bug D-7 closes).
#
# The H1 is optional here. D-7 describes the block as running "from the H1",
# but partial files and fixture bundles legitimately open with the header
# lines themselves, and requiring an H1 would fail those closed for a reason
# the format does not care about. An H1 is accepted, never required.
#
# Fences (D-5) need no separate guard: a column-0 fence line is neither blank,
# an H1, nor a header line, so it ENDS the header block — a fenced example
# declaration is already outside every recognized block, whether it sits above
# or below the real one. A CR-only line on a CRLF checkout is normalized to
# blank first, so line endings alone cannot close the block early.
#
# One awk program serves both entry points, in two modes: with `key` set it
# prints that one declaration's value (spec_parse_header_value); with `key`
# EMPTY it emits the whole block as a record stream (spec_parse_header_block).
# One implementation, so the batched and single-key forms cannot disagree about
# the grammar — which is the whole point of the lib. It is held in a variable
# rather than inlined because the file and stdin forms differ only in the
# redirection.
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
            }
          }
        }
      }
      next
    }
    past = 1
  }
  END {
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
      printf '%s\n' "spec-parse: invalid header key '$(spec_parse__printable "$spec_parse__hk")' (must match ^[A-Za-z][A-Za-z-]*\$)" >&2
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

# --- Parked-map / reference-bullet parse (Task 2; REQ-B1.4, REQ-C1.1,
# --- REQ-C1.3 · D-5, D-8) ----------------------------------------------------
#
# The single v2 posture (D-8), the one all four v2 parsers consume so it cannot
# re-diverge:
#
#   * a column-0 code-fence line toggles illustration mode, and no fenced line
#     parses as anything — heading, bullet, or otherwise (format-grammar D-5 is
#     the interim provenance; REQ-A1.1's meta-spec amendment in Task 5 replaces
#     it, and Task 6 flips these citations). End-of-file inside an open
#     fence is MALFORMED input, not illustration-to-end-of-file: an
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
  /^```/ { fence = !fence; next }
  fence { next }
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
    if (fence) {
      print "spec-parse: end of file inside an open column-0 code fence (malformed input; fail closed)" > "/dev/stderr"
      exit 3
    }
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
    LC_ALL=C awk "$spec_parse__parked_awk"
    return $?
  fi
  spec_parse__readable "$1" || return 1
  spec_parse__nul_screen "$1" || return 1
  LC_ALL=C awk "$spec_parse__parked_awk" <"$1"
}
