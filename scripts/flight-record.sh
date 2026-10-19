#!/bin/sh
# flight-record.sh — render and land a visual flight's audit record
# (tower-front-door Tasks 6 and 14; D-6, D-18 · REQ-E1.2, REQ-E1.4, REQ-E1.5,
# REQ-E1.6, REQ-C1.11).
#
# The flight worker authors the record's human parts (what changed and why,
# how it was verified) and hands over the review audit and the step tables of
# the points it fired; this script assembles them with the operator's ask and
# the route's grounds into the one record layout both homes share, per
# flight-rules' *The audit record* and gate-wiring's *PR-body assembly*:
#
#   <!-- planwright:flight-record id=<flight-id> home=<pr|file> -->
#   ## Summary / ## Verification / a short fact list      (the human lead)
#   <details> ... </details>                              (the full contract)
#   <!-- planwright:flight-record-end -->
#
# Every structural line (the markers, the headings, the collapse tags, the
# fences) sits at column zero. The ask and the grounds are operator text: each
# is stripped of control and invisible characters, its token-shaped secrets
# and personal data (identity, account, and contact numbers) redacted a whole
# line (a private key its whole block) at a time, and it is quoted inside a
# fence longer than any backtick run it holds with every non-blank line
# indented two spaces, so no fence, tag, heading, or marker it carries
# renders, closes the collapse, or reaches column zero where a line-anchored
# reader would take it for structure. Worker-authored inputs are stripped the same way and normalized
# for the markdown lint (trailing whitespace, blank-line runs, edge blank
# lines), and refused, never otherwise rewritten, when they carry a
# token-shaped secret or markup that would reshape the record around them (raw
# HTML, a fence other than a closed column-zero backtick fence, a fenced line
# starting with `<`, a heading or setext underline the input may not carry, a
# footnote definition; markup_hazard below is the full rule).
#
# Usage:
#   flight-record.sh render --home pr <inputs> [--post-pr]
#   flight-record.sh render --home file <inputs> --record-path <path>
#       Print the record. --post-pr marks the pr home's re-emit after the
#       post-pr point and requires its step table. A `pr` record larger than
#       GitHub's PR-body limit is refused (exit 3) and nothing is printed: a
#       truncated record would drop the contract's tail. The `file` home
#       requires --record-path, the repo-relative path the record names as
#       its home; `pr` refuses it.
#   flight-record.sh land <inputs> --record-path <path> [--repo-root <dir>]
#       The no-remote arm, run in the flight's worktree (or at its top level
#       via --repo-root): write the `file` record to the record path and
#       commit that one file on the flight's own branch, reporting
#       `record<TAB><repo-relative path>` and `commit<TAB><sha>`. Refused
#       (exit 3, nothing written) off the branch
#       `planwright/flight/<flight-id>`, when the record already exists or
#       appears while land runs, when a directory on the record path is a
#       symlink or not a directory (checked again, one component at a time, as
#       land creates them), or when the index holds other staged changes. A
#       re-run whose record matches its render, both committed and in the
#       checkout (compared through git), reports that record and succeeds, as
#       does a run whose commit finds a concurrent run already committed the
#       same render. The record is created only if absent, so a concurrent
#       run's record is never overwritten. A commit git or its hooks refuse
#       (exit 4), or an interrupt, rolls back while HEAD lacks the record: it
#       unstages it and deletes it when it is still the file this run wrote,
#       reporting on stderr what it removed, kept, or could not unstage.
#
#   The caller chooses the record path (flight-dispatch.sh computes it), so
#   this script composes no spec-home path of its own. It is repo-relative,
#   or absolute and inside the worktree (under its physical top level, or
#   under --repo-root as given); its file is `<flight-id>.md`, and it
#   is refused (exit 2) when it carries a byte outside [A-Za-z0-9._/-], an
#   empty, `.`, `..`, `.git`, or dash-led segment, or a trailing slash.
#
#   <inputs>, a later flag overriding an earlier one:
#     --flight-id <id>            grammar-checked by scripts/flight-id.sh
#     --ask-file <file>           the ask as the operator gave it
#     --grounds-file <file>       the route's one-line grounds
#     --summary-file <file>       what changed and why (the lead)
#     --verification-file <file>  how it was verified (the lead)
#     --audit-file <file>         the convergence steps' audit record: a heading
#                                 for each of Lens coverage, Auto-applicable,
#                                 Agent-resolvable, Needs sign-off, Needs human
#                                 judgment, Declined log, and Pending sign-off,
#                                 then the step table of every point fired so
#                                 far, headed "Steps at `<point>`" as
#                                 step-record.sh renders it: pre-implementation,
#                                 pre-ci, convergence, and pre-pr always, and
#                                 post-pr on the pr home once it has fired (the
#                                 re-emit). The file home refuses a post-pr
#                                 table and writes that point's not-fired row
#                                 itself. The record nests them under its own
#                                 `###` heading, so `####`.
#     --handle <handle>           the worker handle
#     --scoping-file <file>       optional: the rigor scoping applied; absent
#                                 means none was
#     --revert-file <file>        optional: the revert path; absent takes the
#                                 home's default
#
# The lead may not restate the ask: a summary or verification carrying the
# whole ask (of RESTATE_WHOLE_MIN characters or more) or one of its lines (of
# RESTATE_LINE_MIN characters and RESTATE_LINE_WORDS words or more), up to case
# and spacing, is refused (exit 2).
#
# Exit codes: 0 rendered or landed · 2 usage or an input refused · 3 refused
# by state (over the PR-body limit; for land, the branch, an existing record
# other than a matching re-run, a record that appeared while land ran, a
# symlink or non-directory on the record path, or a staged index) · 4 an
# environment failure (a missing helper, a sanitizer, the secret screen, or
# git could not run, or refused the record commit; the screen reported a
# finding in no input it was given; or the work directory, the record, or a
# directory on its path could not be resolved, created, entered, or
# written).
#
# Portable POSIX sh (the bash 3.2 floor); no eval; pathname expansion off.
set -uf
LC_ALL=C
export LC_ALL
unset CDPATH

prog=flight-record
LF='
'

script_dir=$(cd "$(dirname "$0")" && pwd -P) || exit 4
FLIGHT_ID="$script_dir/flight-id.sh"
SCREEN="$script_dir/inception-secret-screen.sh"
TEXT="$script_dir/flight-text.sh"
for _h in "$FLIGHT_ID" "$SCREEN" "$TEXT"; do
  [ -f "$_h" ] && [ -r "$_h" ] || {
    printf '%s: required helper missing: %s\n' "$prog" "$_h" >&2
    exit 4
  }
done

# shellcheck source=scripts/flight-text.sh
. "$TEXT"

# Each worker input's cap; GitHub's PR-body limit, in characters, which a
# byte count never undershoots; the grounds' cap, with room over dispatch's
# one line for a hand-run render. ASK_MAX comes from flight-text.sh.
INPUT_MAX=262144
PR_BODY_MAX=65536
GROUNDS_MAX=1024

# The shortest whole ask, and the shortest ask line (in characters and in
# words), the restated-prompt check compares: below them an overlap is
# ordinary wording, or a file name or error the lead has to name, not a
# restatement.
RESTATE_WHOLE_MIN=16
RESTATE_LINE_MIN=24
RESTATE_LINE_WORDS=5

die() {
  _rc=$1
  shift
  printf '%s: %s\n' "$prog" "$*" >&2
  exit "$_rc"
}

usage() {
  cat >&2 <<'EOF'
usage: flight-record.sh render --home pr <inputs> [--post-pr]
       flight-record.sh render --home file <inputs> --record-path <path>
       flight-record.sh land <inputs> --record-path <path> [--repo-root <dir>]
inputs: --flight-id <id> --ask-file <f> --grounds-file <f> --summary-file <f>
        --verification-file <f> --audit-file <f> --handle <h>
        [--scoping-file <f>] [--revert-file <f>]
EOF
  exit 2
}

# AUDIT_ELEMENTS — the headings the audit input must carry, one per line: the
# review audit, then the step table of each in-run point that fires before
# the record's first render, headed as scripts/step-record.sh renders it.
# shellcheck disable=SC2016 # the backticks are Markdown code spans
AUDIT_ELEMENTS='Lens coverage
Auto-applicable
Agent-resolvable
Needs sign-off
Needs human judgment
Declined log
Pending sign-off
Steps at `pre-implementation`
Steps at `pre-ci`
Steps at `convergence`
Steps at `pre-pr`'
# shellcheck disable=SC2016 # the backticks are Markdown code spans
POST_PR_HEADING='Steps at `post-pr`'

# read_capped <name> <file> <cap> <out> — copy a readable regular file of at
# most <cap> bytes to <out>, read once so every later check sees one copy.
read_capped() {
  [ -f "$2" ] && [ -r "$2" ] || die 2 "--$1 must name a readable regular file"
  head -c "$(($3 + 1))" <"$2" >"$4" || die 2 "cannot read --$1"
  [ "$(wc -c <"$4" | tr -d ' ')" -le "$3" ] || die 2 "--$1 is larger than $3 bytes"
}

# blank <file> — true when the file holds nothing but whitespace.
blank() {
  [ -z "$(tr -d ' \t\n\r' <"$1")" ]
}

# screen_all <name>... — run the repository's secret screen once over every
# input, named relative to $work (its built-in pattern set, so the verdict
# does not vary with the host's tools), and write `<name><TAB><line><TAB><rule>`
# per finding to $work/hits. The screen runs inside $work on those fixed ASCII
# names because it strips bytes from the paths it reports, so a work directory
# under a non-ASCII TMPDIR would report paths no input matches. A finding
# naming anything but an input, or an unusable screen, exits 4. The screen
# never prints the matched text, and neither does anything here.
screen_all() {
  _src=0
  (cd "$work" && TMPDIR=$work PLANWRIGHT_SECRET_SCREEN_TOOL=none exec /bin/sh "$SCREEN" -- "$@") \
    >/dev/null 2>"$work/screen.err" </dev/null || _src=$?
  : >"$work/hits" || die 4 "cannot write the screen's findings"
  case $_src in
    0) return 0 ;;
    1) ;;
    *) die 4 "the secret screen could not run (exit $_src)" ;;
  esac
  _inputs=''
  for _n in "$@"; do _inputs="$_inputs$_n$LF"; done
  awk -v inputs="$_inputs" '
    BEGIN { n = split(inputs, a, "\n"); for (i = 1; i <= n; i++) if (a[i] != "") ok[a[i]] = 1 }
    match($0, /:[0-9]+: [a-z0-9-]+ \(value redacted\)$/) {
      path = substr($0, 1, RSTART - 1)
      rest = substr($0, RSTART + 1)
      n = index(rest, ": ")
      rule = substr(rest, n + 2)
      sub(/ \(value redacted\)$/, "", rule)
      if (!(path in ok)) { stray = 1; exit }
      print path "\t" substr(rest, 1, n - 1) "\t" rule
    }
    END { exit stray ? 3 : 0 }' "$work/screen.err" >"$work/hits"
  case $? in
    0) ;;
    3) die 4 "the secret screen reported a finding in no input this script screened; refusing to pass the inputs" ;;
    *) die 4 "cannot read the secret screen's report" ;;
  esac
  [ -s "$work/hits" ] || die 4 "the secret screen reported a finding this script could not place"
}

# personal_data <name> — append to $work/hits a `<name><TAB><line><TAB><rule>`
# finding for each personal-data rule a line of the operator text <name>
# matches: a US social security number (personal-data-identity), a payment
# card that passes its Luhn check or an uppercase IBAN that passes its mod-97
# check (personal-data-account), and a NANP or `+`-prefixed international
# phone number (personal-data-contact). Sentence punctuation around a number
# and its neighbours' separators are accepted; the shapes are strict (issued
# SSN ranges, NANP area and exchange digits, card issuer digits and group
# layouts, the checksums), which keeps version strings, dates, PR numbers,
# timestamps, and hashes out. Deliberately missed: a card separated by
# anything but spaces or dashes (a dotted card), an unseparated card glued to
# another number by a separator, a NANP exchange starting with 0 or 1, and a
# lowercase IBAN. awk without interval expressions, which POSIX awk does not
# promise.
personal_data() {
  awk -v name="$1" '
    function luhn(d,   i, x, s, alt) {
      s = 0
      alt = 0
      for (i = length(d); i >= 1; i--) {
        x = substr(d, i, 1) + 0
        if (alt) { x *= 2; if (x > 9) x -= 9 }
        s += x
        alt = !alt
      }
      return s % 10 == 0
    }
    function iban(s,   r, i, c) {
      s = substr(s, 5) substr(s, 1, 4)
      r = 0
      for (i = 1; i <= length(s); i++) {
        c = substr(s, i, 1)
        if (c ~ /[0-9]/) r = (r * 10 + c) % 97
        else r = (r * 100 + index("ABCDEFGHIJKLMNOPQRSTUVWXYZ", c) + 9) % 97
      }
      return r == 1
    }
    function hit(rule) {
      if (!(rule in seen)) print name "\t" FNR "\t" rule
      seen[rule] = 1
    }
    # each(re) — the matches of re in s, one per call, with the byte before
    # and after each; false when there are no more.
    function each(re,   t) {
      t = substr(s, off + 1)
      if (!match(t, re)) return 0
      st = off + RSTART
      m = substr(s, st, RLENGTH)
      pre = substr(s, st - 1, 1)
      post = substr(s, st + RLENGTH, 1)
      off = st + RLENGTH - 1
      return 1
    }
    # alone — the match is not part of a longer number or a word: no digit,
    # letter, or underscore beside it, and no `.` or `-` joining another digit.
    # A trailing `.` or `,` that ends the sentence is fine.
    function alone() {
      if (pre ~ /[A-Za-z0-9_]/ || post ~ /[A-Za-z0-9_]/) return 0
      if (pre ~ /[.-]/ && substr(s, st - 2, 1) ~ /[0-9]/) return 0
      if (post ~ /[.-]/ && substr(s, st + length(m) + 1, 1) ~ /[0-9]/) return 0
      return 1
    }
    # ibanat(j) — the groups of the IBAN candidate g[] from group j form an
    # IBAN: unseparated, or in groups of four with the last shorter.
    function ibanat(j,   c, q) {
      if (length(g[j]) > 4)
        return length(g[j]) >= 15 && length(g[j]) <= 34 && (j < ng || post !~ /[a-z_]/) && iban(g[j])
      c = g[j]
      for (q = j + 1; q <= ng && length(g[q]) <= 4; q++) {
        c = c g[q]
        if (length(c) > 34) return 0
        if (length(c) >= 15 && (q < ng || post !~ /[a-z_]/) && iban(c)) return 1
        if (length(g[q]) < 4) return 0
      }
      return 0
    }
    # card(d) — a payment card: an issuer digit (2 to 6) and a valid Luhn sum.
    function card(d) { return d ~ /^[2-6]/ && luhn(d) }
    {
      split("", seen)
      s = " " $0 " "
      # A social security number: one separator, dash or space, and an area,
      # group, and serial the SSA issues. Known false positive, kept by the
      # operator: a spaced triple of the same shape, such as ports or sizes
      # (`443 80 8080`), is redacted too.
      off = 0
      while (each("[0-9][0-9][0-9][ -][0-9][0-9][ -][0-9][0-9][0-9][0-9]")) {
        if (!alone() || substr(m, 4, 1) != substr(m, 7, 1)) continue
        a = substr(m, 1, 3)
        if (a == "000" || a == "666" || a ~ /^9/ || substr(m, 5, 2) == "00" || substr(m, 8, 4) == "0000") continue
        hit("personal-data-identity")
      }
      # A NANP number, optionally 1-prefixed: area and exchange start 2 to 9,
      # and an unparenthesized area uses the exchange'"'"'s separator.
      off = 0
      while (each("(1[ .-])?([(][2-9][0-9][0-9][)][ .-]?|[2-9][0-9][0-9][ .-])[2-9][0-9][0-9][ .-][0-9][0-9][0-9][0-9]")) {
        if (!alone()) continue
        c = m
        if (c ~ /^1[ .-]/) c = substr(c, 3)
        if (c !~ /^[(]/ && substr(c, 4, 1) != substr(c, 8, 1)) continue
        hit("personal-data-contact")
      }
      # An international number: `+`, a country digit, 8 to 15 digits, and
      # single separators. A word or more digits running on after it end the
      # number at an earlier group (`... 0958 24h`).
      off = 0
      while (each("[+][1-9][0-9 .()-]*[0-9]")) {
        if (pre ~ /[A-Za-z0-9_+]/) continue
        # One forward pass: dg[i] is the i-th digit group, sep[i + 1] the
        # separator after it. A word right after drops the last group; the
        # number then ends at the last group boundary within 15 digits.
        ng = split(m, dg, "[ .()-]+")
        split(m, sep, "[0-9]+")
        if (post ~ /[A-Za-z0-9_]/) {
          if (ng < 2) continue
          ng--
        }
        n = 0
        for (i = 1; i <= ng; i++) {
          d = length(dg[i]) - (i == 1)
          if (n + d > 15) break
          if (i > 1 && sep[i] ~ /[ .-][ .-]/) { n = 0; break }
          n += d
        }
        if (n >= 8 && n <= 15) hit("personal-data-contact")
      }
      # A card: 13 to 19 digits unseparated, or a standard group layout
      # (4-4-4-4, 4-4-4-4-3, 4-6-5, 4-6-4) under one separator, found
      # anywhere in a run of groups, whatever separates its neighbours, so a
      # date or an expiry beside it does not hide it.
      off = 0
      while (each("[0-9]+([ -][0-9]+)*")) {
        if (pre ~ /[A-Za-z_]/ || post ~ /[A-Za-z_]/) continue
        if (pre == "." && substr(s, st - 2, 1) ~ /[0-9]/) continue
        if (m !~ /[ -]/) {
          if (length(m) >= 13 && length(m) <= 19 && card(m)) hit("personal-data-account")
          continue
        }
        # g[j] is the j-th group, sp[j] the single separator before it. Every
        # layout opens with four digits, so only such a group starts a
        # window, and a run is scanned for its first 64 windows: a longer run
        # of digit groups is a table or a dump, not prose.
        ng = split(m, g, "[ -]")
        pos = 1
        for (j = 1; j <= ng; j++) {
          sp[j] = j > 1 ? substr(m, pos - 1, 1) : ""
          pos += length(g[j]) + 1
        }
        nl = split("4 4 4 4 3|4 4 4 4|4 6 5|4 6 4", lay, "|")
        tried = 0
        for (i = 1; i <= ng && tried < 64 && !("personal-data-account" in seen); i++) {
          if (length(g[i]) != 4) continue
          tried++
          for (l = 1; l <= nl; l++) {
            k = split(lay[l], w, " ")
            if (i + k - 1 > ng) continue
            d = ""
            for (j = 1; j <= k && length(g[i + j - 1]) == w[j] && (j < 3 || sp[i + j - 1] == sp[i + 1]); j++) d = d g[i + j - 1]
            if (j > k && card(d)) { hit("personal-data-account"); break }
          }
        }
      }
      # An IBAN, unseparated or in groups of four, the last shorter; the
      # groups stop at 34 characters so a long uppercase run costs little.
      off = 0
      # A candidate that is no IBAN is retried from its later IBAN-shaped
      # groups, so a token like `AB12` before an IBAN does not hide it; at
      # most 64 retries per candidate, each bounded at 34 characters.
      while (each("[A-Z][A-Z][0-9][0-9]( ?[A-Z0-9])+")) {
        ng = split(m, g, " ")
        if (pre !~ /[A-Za-z0-9_]/ && ibanat(1)) { hit("personal-data-account"); continue }
        tried = 0
        for (i = 2; i <= ng && tried < 64; i++) {
          if (g[i] !~ /^[A-Z][A-Z][0-9][0-9]/) continue
          tried++
          if (ibanat(i)) { hit("personal-data-account"); break }
        }
      }
    }' "$work/$1" >>"$work/hits" || die 4 "cannot screen --${1%.clean} for personal data"
}

# hits_for <name> <out> — the `<line><TAB><rule>` findings, the screen's and
# the personal-data pass's, in the input <name>; true when there are any.
hits_for() {
  awk -F '\t' -v p="$1" '$1 == p { print $2 "\t" $3 }' "$work/hits" >"$2" || die 4 "cannot read the screen's findings"
  [ -s "$2" ]
}

# operator_text <name> <file> <cap> — the ask or the grounds, read and cleaned
# into $work/<name>.clean; CLEAN_STRIPPED records whether the strip removed
# anything.
operator_text() {
  read_capped "$1" "$2" "$3" "$work/$1.raw"
  clean_text "$work/$1.raw" "$work/$1.clean" || die 4 "cannot sanitize --$1"
  ! blank "$work/$1.clean" || die 2 "--$1 is empty once sanitized"
}

# The private-key block markers, one begin and end pair per format (PEM and
# PGP, SSH2, PuTTY): the begins together match what the screen's
# private-key-block rule flags, and each end is its own format's last line,
# the SSH2 and PuTTY ends only at the start of a line (after any indent or
# `>` quoting). A PEM or PGP block ends only at the END line naming its own
# key type, derived from its BEGIN line; the PEM end here documents the shape.
KEY_FORMATS='-----BEGIN ([A-Z0-9]+ )*PRIVATE KEY( BLOCK)?-----	-----END ([A-Z0-9]+ )*PRIVATE KEY( BLOCK)?-----
---- BEGIN SSH2 ENCRYPTED PRIVATE KEY ----	^[[:blank:]>]*---- END SSH2 ENCRYPTED PRIVATE KEY ----
PuTTY-User-Key-File-[0-9]+:	^[[:blank:]>]*Private-MAC:'

# redact <name> <out> — the cleaned text with each line the screen flagged
# replaced whole; REDACTED is 1 when a secret was, REDACTED_PERSONAL when
# personal data was. The screen flags only a key block's BEGIN line, so every
# line after it is dropped through that format's own END line, or to the end
# of the text when there is none; a line is read marker by marker, so the
# last one on it decides, and another format's end inside a key ends nothing.
redact() {
  REDACTED=0
  REDACTED_PERSONAL=0
  if hits_for "$1.clean" "$work/$1.hits"; then
    awk -F '\t' -v formats="$KEY_FORMATS" '
      BEGIN {
        nk = split(formats, f, "\n")
        for (k = 1; k <= nk; k++) {
          split(f[k], pair, "\t")
          kb[k] = pair[1]
          ke[k] = pair[2]
          # The same end anywhere on a line, for the line that opened the block.
          kf[k] = ke[k]
          sub(/^\^\[\[:blank:\]>\]\*/, "", kf[k])
        }
      }
      # at(s, re, from) — where re first matches s at or after from, its
      # length in RL; 0 when it does not. An re anchored with ^ matches only
      # at the start of the line.
      function at(s, re, from,   t) {
        if (re ~ /^\^/ && from > 1) return 0
        t = substr(s, from)
        if (!match(t, re)) return 0
        RL = RLENGTH
        return from + RSTART - 1
      }
      NR == FNR {
        r[$1] = (r[$1] == "" ? $2 : r[$1] ", " $2)
        if ($2 !~ /^personal-data-/) secret[$1] = 1
        next
      }
      {
        was = inkey
        if (was || FNR in r) {
          pos = 1
          opened = 0
          while (1) {
            if (inkey) {
              # On lines after the one that opened the block, a PEM or PGP
              # Comment header is free text, never the end, and the SSH2
              # and PuTTY ends count only at the start of the line.
              if (!opened && kind == 1 && $0 ~ /^[[:blank:]>]*Comment:/) break
              if (kind == 1) {
                # A PEM or PGP block ends only at the END line of its own
                # key type, found as literal text.
                p = index(substr($0, pos), pemend)
                if (p) { p += pos - 1; RL = length(pemend) }
              } else p = at($0, opened ? kf[kind] : ke[kind], pos)
              if (!p) break
              inkey = 0
              pos = p + RL
            } else {
              best = 0
              for (k = 1; k <= nk; k++) {
                p = at($0, kb[k], pos)
                if (p && (!best || p < best)) { best = p; bk = k; bl = RL }
              }
              if (!best) break
              inkey = 1
              kind = bk
              opened = 1
              if (kind == 1) {
                pemend = substr($0, best, bl)
                sub(/-----BEGIN /, "-----END ", pemend)
              }
              pos = best + bl
            }
          }
        }
        # A line inside a block goes with the block, unmarked: its key is
        # already marked, and its findings raise no note of their own.
        if (was) next
        if (FNR in r) {
          print "[redacted: " r[FNR] ((FNR in secret) ? ", a token-shaped secret]" : ", personal data]")
          if (r[FNR] ~ /personal-data-/) personal = 1
          if (FNR in secret) sec = 1
        } else print
      }
      END { print sec + 2 * personal >flags }' flags="$work/$1.flags" "$work/$1.hits" "$work/$1.clean" >"$2" \
      || die 4 "cannot redact --$1"
    _flags=$(cat "$work/$1.flags") || die 4 "cannot redact --$1"
    REDACTED=$((_flags % 2))
    REDACTED_PERSONAL=$((_flags / 2))
  else
    cp "$work/$1.clean" "$2" || die 4 "cannot copy --$1"
  fi
}

# markup_hazard <file> <headings> — name the first construct in a worker
# input that could reshape the record around it, printing nothing when there
# is none. Outside a fence: raw HTML of any kind (a `<` opening a tag,
# comment, declaration, or processing instruction), since no line-based check
# can be sure which container a line sits in, and a comment or HTML block
# that escapes one hides or flattens the rest of the record; a fence indented
# one to three spaces, which a list item can end early and leave a
# column-zero fence line open behind it; a tilde fence, which the markdown
# lint's one fence style refuses beside the record's backtick fences; a
# footnote definition, at any container depth, which renders after the
# collapse; and a heading, ATX
# or setext, at any container depth, that the input may not carry: `none`
# refuses every heading, `audit` those above level four, since the audit
# nests under the record's own level-three heading. Inside a column-zero
# backtick fence, whose extent is reliable once those fences are the only
# kind, a line is code; only one starting with `<` is refused, so no marker
# or collapse tag reaches column zero for a line-anchored reader. A fence
# left open is refused.
markup_hazard() {
  awk -v headings="$2" '
    function hazard(what) { print what; found = 1; exit }
    {
      l = $0
      if (fence) {
        if (l ~ /^</) hazard("a fenced line starting with < at column zero (indent it)")
        if (match(l, /^ ? ? ?`+[ \t]*$/)) {
          f = l
          gsub(/[ \t]/, "", f)
          if (length(f) >= fl) fence = 0
        }
        prev = 0
        next
      }
      if (l ~ /<[A-Za-z\/!?]/) hazard("raw HTML (a < before a letter, /, !, or ?; write &lt; in prose, or put code in a fence)")
      if (l ~ /^ ? ? ?(```|~~~)/ && l !~ /^```/) hazard("a fence other than backticks at column zero")
      if (match(l, /^```+/)) {
        fl = RLENGTH
        if (index(substr(l, RSTART + RLENGTH), "`")) {
          prev = 1
          next
        }
        fence = 1
        prev = 0
        next
      }
      h = l
      while (match(h, /^[ \t]*(>|[-*+][ \t]|[0-9]+[.)][ \t])[ \t]*/)) h = substr(h, RSTART + RLENGTH)
      if (l ~ /^ ? ? ?\[\^[^]]*\]:/ || (h != l && h ~ /^\[\^[^]]*\]:/)) hazard("a footnote definition (it renders after the collapse)")
      if (headings == "none" && h ~ /^[ \t]*#+([ \t]|$)/) hazard("a heading (the record supplies its own)")
      if (headings == "audit" && h ~ /^[ \t]*(#|##|###)([ \t]|$)/) hazard("a heading above level four (the audit nests under the record'"'"'s ### heading)")
      if (prev && l ~ /^[ \t>]*(=+|-+)[ \t]*$/) hazard("a setext heading underline (put a blank line above a thematic break)")
      prev = (l ~ /[^ \t]/)
    }
    END {
      if (!found && fence) print "an unclosed fence"
    }' "$1"
}

# worker_text <name> <file> <out> [<headings>] — a worker-authored input:
# cleaned, normalized (trailing whitespace trimmed, blank-line runs collapsed
# to one, leading and trailing blank lines dropped) so a landed record passes
# the markdown lint, and refused if it carries markup that would reshape the
# record (markup_hazard; <headings> defaults to none). Its secret check runs
# with the others, in refuse_secrets.
worker_text() {
  read_capped "$1" "$2" "$INPUT_MAX" "$work/$1.raw"
  clean_text "$work/$1.raw" "$work/$1.clean" || die 4 "cannot sanitize --$1"
  awk '
    { sub(/[ \t]+$/, "") }
    !NF { if (seen) held = 1; next }
    { if (held) print ""; held = 0; seen = 1; print }' "$work/$1.clean" >"$3" \
    || die 4 "cannot normalize --$1"
  ! blank "$3" || die 2 "--$1 is empty"
  _why=$(markup_hazard "$3" "${4:-none}") || die 4 "cannot read --$1"
  [ -z "$_why" ] || die 2 "--$1 carries $_why, which would alter the record's structure; remove it and render again"
}

# refuse_secrets <flag> <name> — refuse the worker input <name> the screen
# flagged, naming the rules and never the text.
refuse_secrets() {
  if hits_for "$2" "$work/$1.hits"; then
    die 2 "--$1 carries a token-shaped secret ($(cut -f2 "$work/$1.hits" | sort -u | tr '\n' ' ' | sed 's/ $//')); remove it and render again"
  fi
}

# normalize <file> — lowercased, whitespace collapsed, on one line.
normalize() {
  tr '[:upper:]' '[:lower:]' <"$1" | tr '\t\r\n' '   ' | tr -s ' ' | sed 's/^ //;s/ $//'
}

# restates_ask — true when the lead carries the whole ask, or one of its lines
# verbatim up to case and spacing (the RESTATE_ thresholds above).
restates_ask() {
  cat "$work/summary" "$work/verification" >"$work/lead.txt" || die 4 "cannot assemble the lead"
  normalize "$work/lead.txt" >"$work/lead.norm"
  normalize "$work/ask" >"$work/ask.norm"
  awk -v whole="$RESTATE_WHOLE_MIN" -v line="$RESTATE_LINE_MIN" -v words="$RESTATE_LINE_WORDS" '
    NR == FNR { lead = $0; next }
    FILENAME ~ /ask\.norm$/ { if (length($0) >= whole && index(lead, $0)) hit = 1; next }
    {
      s = tolower($0)
      gsub(/[ \t\r]+/, " ", s)
      sub(/^ /, "", s)
      sub(/ $/, "", s)
      if (s ~ /^\[redacted: /) next
      if (length(s) >= line && split(s, w, " ") >= words && index(lead, s)) hit = 1
    }
    END { exit hit ? 0 : 1 }' "$work/lead.norm" "$work/ask.norm" "$work/ask"
}

# fenced <file> — the file as a `text` fence longer than any backtick run it
# holds, each non-blank line indented two spaces and every line, the last
# included, newline-terminated so the closing fence stands on its own line.
fenced() {
  _fence=$(awk '
    { s = $0; while (match(s, /`+/)) { if (RLENGTH > m) m = RLENGTH; s = substr(s, RSTART + RLENGTH) } }
    END { n = m + 1; if (n < 3) n = 3; for (i = 0; i < n; i++) printf "`" }' "$1") || return 1
  printf '%stext\n' "$_fence" || return 1
  awk '{ print (length($0) ? "  " $0 : "") }' "$1" || return 1
  printf '%s\n' "$_fence"
}

# pending_ids — the pending-sign-off checklist IDs, in order, comma-joined. The
# generated checklist carries no checkbox; an older `- [ ]` entry still counts
# and a checked `- [x]` one does not.
pending_ids() {
  sed -n -E 's/^[[:space:]]*- (\[ \] )?\*\*(PS-[0-9]+)\*\*.*/\2/p' "$work/audit" \
    | awk '!seen[$0]++' | tr '\n' ',' | sed 's/,$//;s/,/, /g'
}

RECORD_RULE="refusing --record-path: it must be repo-relative (or absolute inside the worktree), end in the file <flight-id>.md, and carry only [A-Za-z0-9._/-] with no empty, '.', '..', '.git', or dash-led segment"

# record_ok <rel> — the repo-relative record path is well-formed and names
# this flight's record.
record_ok() {
  case $1 in
    '' | /* | */) return 1 ;;
    *[!A-Za-z0-9._/-]*) return 1 ;;
  esac
  case /$1/ in
    *//* | */./* | */../* | */.[Gg][Ii][Tt]/* | */-*) return 1 ;;
  esac
  [ "${1##*/}" = "$flight_id.md" ]
}

# render_to <out> — write the record for $home.
# shellcheck disable=SC2016 # the backticks are Markdown code spans
render_to() {
  _pending=$(pending_ids)
  {
    printf '<!-- planwright:flight-record id=%s home=%s -->\n' "$flight_id" "$home"
    printf '## Summary\n\n'
    cat "$work/summary" || return 1
    printf '\n## Verification\n\n'
    cat "$work/verification" || return 1
    printf '\n'
    printf -- '- **Flight:** `%s` on `%s` · **Worker:** `%s`\n' "$flight_id" "$branch" "$handle"
    if [ -n "$_pending" ]; then
      printf -- '- **Pending sign-off:** %s (see the collapsed checklist)\n' "$_pending"
    else
      printf -- '- **Pending sign-off:** none\n'
    fi
    printf '\n<details>\n<summary>Flight record</summary>\n\n'
    printf '### The ask\n\n'
    printf 'Quoted as the operator gave it, fenced so its markup stays inert.\n'
    [ "$ask_stripped" -eq 0 ] || printf 'Invisible or bidi-control characters were stripped from it.\n'
    [ "$ask_redacted" -eq 0 ] || printf 'Lines carrying a token-shaped secret were redacted whole.\n'
    [ "$ask_personal" -eq 0 ] || printf 'Lines carrying personal data were redacted whole.\n'
    printf '\n'
    fenced "$work/ask" || return 1
    printf '\n### Route and grounds\n\n'
    printf 'Visual flight. Grounds as the tower stated them:\n'
    [ "$grounds_stripped" -eq 0 ] || printf 'Invisible or bidi-control characters were stripped from them.\n'
    [ "$grounds_redacted" -eq 0 ] || printf 'A token-shaped secret in them was redacted whole.\n'
    [ "$grounds_personal" -eq 0 ] || printf 'Personal data in them was redacted whole.\n'
    printf '\n'
    fenced "$work/grounds" || return 1
    printf '\n### Record home\n\n'
    if [ "$home" = pr ]; then
      printf 'The draft PR body of `%s`, declared at routing time.\n' "$branch"
    else
      printf '`%s`, committed on `%s`, declared at routing time.\n' "$record_rel" "$branch"
    fi
    printf '\n### Rigor scoping\n\n'
    if [ -n "$scoping_file" ]; then
      cat "$work/scoping" || return 1
    else
      printf 'None applied: every pass in the convergence sequence ran at full rigor.\n'
    fi
    printf '\n### Worker handle\n\n`%s`\n' "$handle"
    printf '\n### Revert path\n\n'
    if [ -n "$revert_file" ]; then
      cat "$work/revert" || return 1
    elif [ "$home" = pr ]; then
      printf 'Close the draft PR unmerged to discard the flight. After a merge, `git revert` the merge (or the flight'"'"'s commits) on the default branch.\n'
    else
      printf 'Leave `%s` unmerged to discard the flight. After a merge, `git revert` the flight'"'"'s commits: the record rides the same branch, so one revert undoes record and work together.\n' "$branch"
    fi
    printf '\n### Review and step audit\n\n'
    cat "$work/audit" || return 1
    if [ "$home" = file ]; then
      # step-record.sh has no not-fired outcome, so the row is written here,
      # in the columns its tables carry.
      printf '\n#### %s\n\n' "$POST_PR_HEADING"
      printf '| # | Step | Kind | Target | Hosting | Backend | Session | Head | Start | End | Outcome | Excerpt | Output |\n'
      printf '| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |\n'
      printf '| not fired | | | | | | | | | | not fired: the file home opens no PR, and the point fires only once a draft PR exists | | |\n'
    fi
    printf '\n</details>\n\n<!-- planwright:flight-record-end -->\n'
  } >"$1" || die 4 "cannot write the record"
}

[ $# -ge 1 ] || usage
cmd=$1
shift
case $cmd in
  render | land) ;;
  -h | --help) usage ;;
  *) usage ;;
esac

flight_id=''
home=''
home_given=0
ask_file=''
grounds_file=''
summary_file=''
verification_file=''
audit_file=''
handle=''
scoping_file=''
revert_file=''
repo_root=''
record_path=''
record_given=0
post_pr=0
while [ $# -gt 0 ]; do
  if [ "$1" = --post-pr ]; then
    post_pr=1
    shift
    continue
  fi
  [ $# -ge 2 ] || usage
  case $1 in
    --flight-id) flight_id=$2 ;;
    --home)
      home=$2
      home_given=1
      ;;
    --ask-file) ask_file=$2 ;;
    --grounds-file) grounds_file=$2 ;;
    --summary-file) summary_file=$2 ;;
    --verification-file) verification_file=$2 ;;
    --audit-file) audit_file=$2 ;;
    --handle) handle=$2 ;;
    --scoping-file) scoping_file=$2 ;;
    --revert-file) revert_file=$2 ;;
    --repo-root) repo_root=$2 ;;
    --record-path)
      record_path=$2
      record_given=1
      ;;
    *) usage ;;
  esac
  shift 2
done

if [ "$cmd" = land ]; then
  [ "$home_given" -eq 0 ] || die 2 "land lands the file home; a pr record is rendered and handed to gh"
  home='file'
else
  case $home in
    pr | file) ;;
    *) die 2 "--home must be pr or file" ;;
  esac
  [ -z "$repo_root" ] || die 2 "--repo-root is a land option"
fi
if [ "$home" = file ]; then
  [ -n "$record_path" ] || die 2 "--record-path is required for the file home: the caller chooses where the record lands"
else
  [ "$record_given" -eq 0 ] || die 2 "--record-path names the file home's record; a pr record lives in the PR body"
fi
if [ "$post_pr" -eq 1 ] && { [ "$cmd" != render ] || [ "$home" != pr ]; }; then
  die 2 "--post-pr marks the pr home's re-emit after the post-pr point; the file home never fires it"
fi
for _req in flight-id:"$flight_id" ask-file:"$ask_file" grounds-file:"$grounds_file" \
  summary-file:"$summary_file" verification-file:"$verification_file" \
  audit-file:"$audit_file" handle:"$handle"; do
  [ -n "${_req#*:}" ] || die 2 "--${_req%%:*} is required"
done
/bin/sh "$FLIGHT_ID" check "$flight_id" 2>/dev/null </dev/null || die 2 "refusing a malformed flight id"
branch=planwright/flight/$flight_id
record_rel=''
if [ "$home" = file ]; then
  [ "${#record_path}" -le 1024 ] || die 2 "refusing an over-long --record-path"
  case $record_path in
    /*) [ "$cmd" = land ] || die 2 "render takes a repo-relative --record-path" ;;
    *) record_ok "$record_path" || die 2 "$RECORD_RULE" ;;
  esac
  record_rel=$record_path
fi
case $handle in
  *[!A-Za-z0-9._:-]* | [!A-Za-z0-9]*) die 2 "refusing a malformed worker handle (expected [A-Za-z0-9._:-])" ;;
esac
[ "${#handle}" -le 128 ] || die 2 "refusing an over-long worker handle"

work=$(mktemp -d "${TMPDIR:-/tmp}/flight-record.XXXXXX") || die 4 "cannot create a work directory"
trap 'rm -rf "$work"' EXIT
# Absolute, so the screen run from inside it, and its own temp files under
# TMPDIR, resolve whatever TMPDIR was.
work=$(cd "$work" && pwd -P) || die 4 "cannot resolve the work directory"
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

operator_text ask-file "$ask_file" "$ASK_MAX"
ask_stripped=$CLEAN_STRIPPED
operator_text grounds-file "$grounds_file" "$GROUNDS_MAX"
grounds_stripped=$CLEAN_STRIPPED
[ "$(grep -c '' "$work/grounds-file.clean")" -le 1 ] || die 2 "--grounds-file must hold one line"

worker_text summary-file "$summary_file" "$work/summary"
worker_text verification-file "$verification_file" "$work/verification"
worker_text audit-file "$audit_file" "$work/audit" audit
set -- ask-file.clean grounds-file.clean summary verification audit
if [ -n "$scoping_file" ]; then
  worker_text scoping-file "$scoping_file" "$work/scoping"
  set -- "$@" scoping
fi
if [ -n "$revert_file" ]; then
  worker_text revert-file "$revert_file" "$work/revert"
  set -- "$@" revert
fi

screen_all "$@"
personal_data ask-file.clean
personal_data grounds-file.clean
redact ask-file "$work/ask"
ask_redacted=$REDACTED
ask_personal=$REDACTED_PERSONAL
redact grounds-file "$work/grounds"
grounds_redacted=$REDACTED
grounds_personal=$REDACTED_PERSONAL
refuse_secrets summary-file summary
refuse_secrets verification-file verification
refuse_secrets audit-file audit
[ -z "$scoping_file" ] || refuse_secrets scoping-file scoping
[ -z "$revert_file" ] || refuse_secrets revert-file revert

_missing=''
_old_ifs=$IFS
IFS=$LF
for _el in $AUDIT_ELEMENTS; do
  grep -Eiq "^#{1,6}[[:space:]]+$_el" "$work/audit" || _missing="$_missing${_missing:+, }$_el"
done
IFS=$_old_ifs
[ -z "$_missing" ] || die 2 "--audit-file is missing the contract's $_missing (each under its own heading)"
if [ "$post_pr" -eq 1 ] && ! grep -Eiq "^#{1,6}[[:space:]]+$POST_PR_HEADING" "$work/audit"; then
  die 2 "--audit-file is missing the post-pr step table the re-emit after post-pr must carry (its own heading)"
fi
if [ "$home" = file ] && grep -Eiq "^#{1,6}[[:space:]]+$POST_PR_HEADING" "$work/audit"; then
  die 2 "--audit-file carries a post-pr step table, but post-pr never fires on the file home (no PR exists); remove it, the record states it was not fired"
fi

! restates_ask || die 2 "the summary or verification restates the ask; say what changed, why, and how it was verified in your own words (the ask is quoted in the collapsed record)"

if [ "$cmd" = render ]; then
  render_to "$work/record.md" || die 4 "cannot write the record"
  if [ "$home" = pr ]; then
    _bytes=$(wc -c <"$work/record.md" | tr -d ' ')
    _ask_bytes=$(wc -c <"$work/ask" | tr -d ' ')
    [ "$_bytes" -le "$PR_BODY_MAX" ] \
      || die 3 "the record is $_bytes bytes, over the PR-body limit of $PR_BODY_MAX, and the ask alone is $_ask_bytes; trim the worker inputs, or park the flight when the ask leaves too little room (a truncated record would drop the contract's tail)"
  fi
  cat "$work/record.md" || die 4 "cannot print the record"
  exit 0
fi

if [ -z "$repo_root" ]; then
  repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || die 4 "not inside a git worktree"
fi
[ -d "$repo_root" ] || die 2 "--repo-root is not a directory"
_top=$(git -C "$repo_root" rev-parse --show-toplevel 2>/dev/null) || die 4 "--repo-root is not inside a git worktree"
[ "$(cd "$repo_root" && pwd -P)" = "$(cd "$_top" && pwd -P)" ] \
  || die 2 "--repo-root must be the worktree's top level ($_top), which the record path is relative to"
case $record_path in
  /*)
    _phys=$(cd "$repo_root" && pwd -P) || die 4 "cannot resolve --repo-root"
    case $record_path in
      "${_phys%/}"/*) record_rel=${record_path#"${_phys%/}"/} ;;
      "$repo_root"/*) record_rel=${record_path#"$repo_root"/} ;;
      *) die 2 "refusing --record-path: it is outside the worktree ($_phys)" ;;
    esac
    record_ok "$record_rel" || die 2 "$RECORD_RULE"
    ;;
esac
_head=$(git -C "$repo_root" symbolic-ref -q HEAD 2>/dev/null) || _head=''
[ "$_head" = "refs/heads/$branch" ] \
  || die 3 "land runs on the flight's own branch, $branch; nothing was written"
rel=$record_rel
parent=${rel%/*}
[ "$parent" != "$rel" ] || parent=''
base=${rel##*/}
phys=$(cd "$repo_root" && pwd -P) || die 4 "cannot resolve --repo-root"
# Absolute from here on: land changes its working directory below.
repo_root=$phys
# Without its trailing slash, so a worktree at / composes as /<path>.
root=${phys%/}

# bad_dir — print the first directory on the record path that is a symlink or
# not a directory; false when there is none.
bad_dir() {
  _dir=''
  _rest=$parent
  while [ -n "$_rest" ]; do
    _dir=${_dir:+$_dir/}${_rest%%/*}
    if [ -L "$repo_root/$_dir" ] || { [ -e "$repo_root/$_dir" ] && [ ! -d "$repo_root/$_dir" ]; }; then
      printf '%s' "$_dir"
      return 0
    fi
    case $_rest in
      */*) _rest=${_rest#*/} ;;
      *) _rest='' ;;
    esac
  done
  return 1
}

# enter_parent — make the record's parent the working directory, one
# component at a time from the physical root: each is created when absent,
# refused when it is a symlink or not a directory, entered physically, and
# checked to be the one inside the checkout. A symlink swapped onto any
# component can then neither redirect the record nor make a directory outside
# the checkout, and every later step on the record runs from here.
enter_parent() {
  cd -P "$phys" 2>/dev/null || die 4 "cannot enter the worktree"
  _at=$root
  _rest=$parent
  while [ -n "$_rest" ]; do
    _seg=${_rest%%/*}
    case $_rest in
      */*) _rest=${_rest#*/} ;;
      *) _rest='' ;;
    esac
    _at=$_at/$_seg
    if [ ! -e "$_seg" ] && [ ! -L "$_seg" ]; then
      # not-a-lock: one path component created on the way to the record; a concurrent creator is fine
      mkdir -- "$_seg" 2>/dev/null || [ -e "$_seg" ] || [ -L "$_seg" ] || die 4 "cannot create ${_at#"$root"/}"
    fi
    if [ -L "$_seg" ] || [ ! -d "$_seg" ]; then
      die 3 "${_at#"$root"/} became a symlink or not a directory during land; the record is written inside the checkout only; nothing was written"
    fi
    cd -P -- "$_seg" 2>/dev/null || die 4 "cannot enter ${_at#"$root"/}"
    [ "$(pwd -P)" = "$_at" ] \
      || die 3 "${_at#"$root"/} became a symlink or not a directory during land; the record is written inside the checkout only; nothing was written"
  done
}

# inode <path> — the inode number of <path> itself, never a symlink's target.
# One known name, and POSIX has no stat, so SC2012's find does not apply.
# shellcheck disable=SC2012
inode() {
  ls -di -- "$1" 2>/dev/null | awk '{ print $1 }'
}

# is_mine — the record's name holds the regular file this run created, by
# identity rather than content, so a hook that edits it in place leaves it
# this run's.
is_mine() {
  [ -n "$rino" ] && [ -f "$base" ] && [ ! -L "$base" ] && [ "$(inode "$base")" = "$rino" ]
}

# matches_head — HEAD holds the record exactly as this run renders it,
# compared through git so line-ending conversion does not matter.
matches_head() {
  _hb=$(git -C "$repo_root" rev-parse -q --verify "HEAD:$rel" 2>/dev/null) && [ -n "$_hb" ] \
    && [ "$(git -C "$repo_root" hash-object --path="$rel" -- "$work/record.md" 2>/dev/null)" = "$_hb" ]
}

# rollback — run on every exit, signals ignored so a second one cannot cut it
# short. The temp file goes. While HEAD lacks the record, a record this run
# staged is unstaged (the index held nothing else when land began), and the
# file is deleted when it is still this run's, so a refused commit or an
# interrupt leaves nothing a re-run trips over; a record in HEAD stays, and a
# file a hook put in the record's place is left on disk and named. The file is
# deleted only once it is unstaged, never leaving the index adding a missing
# file.
tmpname=''
rino=''
staged=0
rollback() {
  trap '' INT TERM HUP
  if [ -n "$tmpname" ]; then
    rm -f -- "$tmpname"
    if [ -d "$base" ] && [ "$(inode "$base/$tmpname")" = "$rino" ]; then rm -f -- "$base/$tmpname"; fi
  fi
  if [ -n "$rino" ] && ! git -C "$repo_root" cat-file -e "HEAD:$rel" 2>/dev/null; then
    if [ "$staged" -eq 1 ] && ! git -C "$repo_root" rm -q --cached -f --ignore-unmatch -- "$rel" >/dev/null 2>&1; then
      if git -C "$repo_root" ls-files --error-unmatch -- "$rel" >/dev/null 2>&1; then
        printf '%s: could not unstage %s, so it stays on disk and staged; remove it with: git rm -f -- %s\n' \
          "$prog" "$rel" "$rel" >&2
      else
        printf '%s: could not roll back %s, which is not staged; remove it with: rm -- %s\n' \
          "$prog" "$rel" "$rel" >&2
      fi
    elif is_mine; then
      rm -f -- "$base" && printf '%s: the uncommitted record was removed\n' "$prog" >&2
    elif [ "$staged" -eq 1 ] && { [ -e "$base" ] || [ -L "$base" ]; }; then
      printf '%s: a hook replaced %s, so it is unstaged and left on disk\n' "$prog" "$rel" >&2
    fi
  fi
  rm -rf "$work"
}
trap rollback EXIT

report() {
  # The commit that added the record, not HEAD: a post-commit hook may commit again.
  _sha=$(git -C "$repo_root" log -1 --format=%H -- "$rel" 2>/dev/null) && [ -n "$_sha" ] \
    || die 4 "cannot read the record commit"
  printf 'record\t%s\n' "$rel"
  printf 'commit\t%s\n' "$_sha"
}

if _bad=$(bad_dir); then
  die 3 "$_bad is a symlink or not a directory; the record is written inside the checkout only; nothing was written"
fi
render_to "$work/record.md" || die 4 "cannot write the record"
if [ -e "$repo_root/$rel" ] || [ -L "$repo_root/$rel" ] \
  || git -C "$repo_root" cat-file -e "HEAD:$rel" 2>/dev/null; then
  # A re-run whose record is already committed, and checked out, as this render.
  if matches_head && git -C "$repo_root" diff --quiet HEAD -- "$rel" 2>/dev/null; then
    report
    exit 0
  fi
  die 3 "$rel already exists: one flight, one record; nothing was written"
fi
_drc=0
git -C "$repo_root" diff --cached --quiet 2>/dev/null || _drc=$?
case $_drc in
  0) ;;
  1) die 3 "the index holds staged changes; the record commit carries the record alone, so commit or unstage them first; nothing was written" ;;
  *) die 4 "cannot read the index" ;;
esac

enter_parent
# The record is linked from a filled temp file beside it: link(2) fails when
# the name exists, a dangling symlink included, so it is created only when
# absent. A directory at the name would take the link inside it instead, so
# the result is checked to be the temp file itself.
tmpname=$(mktemp ".$base.XXXXXX") || die 4 "cannot write $rel"
cat "$work/record.md" >"$tmpname" || die 4 "cannot write $rel"
chmod "$(printf '%o' $((0666 & ~$(umask))))" "$tmpname" || die 4 "cannot write $rel"
rino=$(inode "$tmpname")
[ -n "$rino" ] || die 4 "cannot read the record's inode"
if ! ln -- "$tmpname" "$base" 2>"$work/ln.err"; then
  if [ ! -e "$base" ] && [ ! -L "$base" ]; then
    sed 's/^/  /' "$work/ln.err" | tr -d '\000-\010\013-\037\177' >&2
    die 4 "cannot write $rel"
  fi
  die 3 "$rel appeared while land ran: one flight, one record; nothing was written"
fi
is_mine || die 3 "$rel appeared while land ran: one flight, one record; nothing was written"
rm -f -- "$tmpname"
tmpname=''
staged=1
if ! git -C "$repo_root" add -- "$rel" >/dev/null 2>"$work/git.err" \
  || ! git -C "$repo_root" commit -q -m "docs(flight): record flight $flight_id" -- "$rel" >>"$work/git.err" 2>&1; then
  # A concurrent run that committed this same render has landed the record.
  if matches_head; then
    report
    exit 0
  fi
  sed 's/^/  /' "$work/git.err" | tr -d '\000-\010\013-\037\177' >&2
  die 4 "could not commit $rel"
fi
report
