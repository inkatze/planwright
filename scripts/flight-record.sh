#!/bin/sh
# flight-record.sh — render and land a visual flight's audit record
# (tower-front-door Task 6; D-6 · REQ-E1.1, REQ-E1.2, REQ-E1.4, REQ-E1.5).
#
# The flight worker authors the record's human parts (what changed and why,
# how it was verified) and hands over the convergence audit its review
# sequence produced; this script assembles them with the operator's ask and
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
# redacted a whole line at a time, and it is quoted inside a fence longer than
# any backtick run it holds with every non-blank line indented two spaces, so
# no fence, tag, heading, or marker it carries renders, closes the collapse, or
# reaches column zero where a line-anchored reader would take it for
# structure. Worker-authored inputs are stripped the same way and normalized
# for the markdown lint (trailing whitespace, blank-line runs, edge blank
# lines), and refused, never otherwise rewritten, when they carry a
# token-shaped secret or markup that would reshape the record around them (raw
# HTML, a fence other than a closed column-zero backtick fence, a fenced line
# starting with `<`, a heading or setext underline the input may not carry, a
# footnote definition; markup_hazard below is the full rule).
#
# Usage:
#   flight-record.sh render --home pr|file <inputs> [--record-path <path>]
#       Print the record. A `pr` record larger than GitHub's PR-body limit is
#       refused (exit 3) and nothing is printed: a truncated record would drop
#       the contract's tail. The `file` home requires --record-path, the
#       repo-relative path the record names as its home; `pr` refuses it.
#   flight-record.sh land <inputs> --record-path <path> [--repo-root <dir>]
#       The no-remote arm, run in the flight's worktree (or at its top level
#       via --repo-root): write the `file` record to the record path and
#       commit that one file on the flight's own branch, reporting
#       `record<TAB><repo-relative path>` and `commit<TAB><sha>`. Refused
#       (exit 3, nothing written) off the branch `planwright/flight/<flight-id>`,
#       when the record already exists, when a directory on the record path is
#       a symlink or not a directory, or when the index holds other staged
#       changes. A commit git or its hooks refuse takes the record back out of
#       the index and the worktree (exit 4).
#
#   The caller chooses the record path (flight-dispatch.sh computes it), so
#   this script composes no spec-home path of its own. It is repo-relative,
#   or absolute and inside the worktree; its file is `<flight-id>.md`, and it
#   is refused (exit 2) when it carries a byte outside [A-Za-z0-9._/-], an
#   empty, `.`, `..`, `.git`, or dash-led segment, or a trailing slash.
#
#   <inputs>, a later flag overriding an earlier one:
#     --flight-id <id>            grammar-checked by scripts/flight-id.sh
#     --ask-file <file>           the ask as the operator gave it
#     --grounds-file <file>       the route's one-line grounds
#     --summary-file <file>       what changed and why (the lead)
#     --verification-file <file>  how it was verified (the lead)
#     --audit-file <file>         the review sequence's audit record: a heading
#                                 for each of Lens coverage, Auto-applicable,
#                                 Agent-resolvable, Needs sign-off, Needs human
#                                 judgment, Declined log, Pending sign-off, and
#                                 Convergence steps (the record nests them
#                                 under its own `###` heading, so `####`)
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
# by state (over the PR-body limit; for land, the branch, an existing record,
# a symlinked or non-directory directory on the record path, or a staged index) · 4 an
# environment failure (a missing helper, a sanitizer, the secret screen, or git
# could not run, or refused the record commit).
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
usage: flight-record.sh render --home pr|file <inputs>
       flight-record.sh land <inputs> --record-path <path> [--repo-root <dir>]
       (render --home file takes --record-path too)
inputs: --flight-id <id> --ask-file <f> --grounds-file <f> --summary-file <f>
        --verification-file <f> --audit-file <f> --handle <h>
        [--scoping-file <f>] [--revert-file <f>]
EOF
  exit 2
}

# AUDIT_ELEMENTS — the headings the audit input must carry, one per line.
AUDIT_ELEMENTS='Lens coverage
Auto-applicable
Agent-resolvable
Needs sign-off
Needs human judgment
Declined log
Pending sign-off
Convergence steps'

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

# screen_all <file>... — run the repository's secret screen once over every
# input (its built-in pattern set, so the verdict does not vary with the
# host's tools) and write `<path><TAB><line><TAB><rule>` per finding to
# $work/hits. An unusable screen exits 4. The screen never prints the matched
# text, and neither does anything here.
screen_all() {
  _src=0
  PLANWRIGHT_SECRET_SCREEN_TOOL=none /bin/sh "$SCREEN" -- "$@" >/dev/null 2>"$work/screen.err" </dev/null || _src=$?
  : >"$work/hits" || die 4 "cannot write the screen's findings"
  case $_src in
    0) return 0 ;;
    1) ;;
    *) die 4 "the secret screen could not run (exit $_src)" ;;
  esac
  awk '
    match($0, /:[0-9]+: [a-z0-9-]+ \(value redacted\)$/) {
      path = substr($0, 1, RSTART - 1)
      rest = substr($0, RSTART + 1)
      n = index(rest, ": ")
      rule = substr(rest, n + 2)
      sub(/ \(value redacted\)$/, "", rule)
      print path "\t" substr(rest, 1, n - 1) "\t" rule
    }' "$work/screen.err" >"$work/hits" || die 4 "cannot read the secret screen's report"
  [ -s "$work/hits" ] || die 4 "the secret screen reported a finding this script could not place"
}

# hits_for <file> <out> — the screen's `<line><TAB><rule>` findings in <file>;
# true when there are any.
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

# redact <name> <out> — the cleaned text with each line the screen flagged
# replaced whole; REDACTED is 1 when any was.
redact() {
  REDACTED=0
  if hits_for "$work/$1.clean" "$work/$1.hits"; then
    awk -F '\t' '
      NR == FNR { r[$1] = (r[$1] == "" ? $2 : r[$1] ", " $2); next }
      FNR in r { print "[redacted: " r[FNR] ", a token-shaped secret]"; next }
      { print }' "$work/$1.hits" "$work/$1.clean" >"$2" || die 4 "cannot redact --$1"
    REDACTED=1
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

# refuse_secrets <name> <file> — refuse a worker input the screen flagged,
# naming the rules and never the text.
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

# pending_ids — the pending-sign-off checklist IDs, in order, comma-joined.
pending_ids() {
  sed -n -E 's/^[[:space:]]*- \[ \] \*\*(PS-[0-9]+)\*\*.*/\1/p' "$work/audit" \
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
    printf '\n'
    fenced "$work/ask" || return 1
    printf '\n### Route and grounds\n\n'
    printf 'Visual flight. Grounds as the tower stated them:\n'
    [ "$grounds_stripped" -eq 0 ] || printf 'Invisible or bidi-control characters were stripped from them.\n'
    [ "$grounds_redacted" -eq 0 ] || printf 'A token-shaped secret in them was redacted whole.\n'
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
    printf '\n### Convergence audit\n\n'
    cat "$work/audit" || return 1
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
while [ $# -gt 0 ]; do
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
set -- "$work/ask-file.clean" "$work/grounds-file.clean" "$work/summary" "$work/verification" "$work/audit"
if [ -n "$scoping_file" ]; then
  worker_text scoping-file "$scoping_file" "$work/scoping"
  set -- "$@" "$work/scoping"
fi
if [ -n "$revert_file" ]; then
  worker_text revert-file "$revert_file" "$work/revert"
  set -- "$@" "$work/revert"
fi

screen_all "$@"
redact ask-file "$work/ask"
ask_redacted=$REDACTED
redact grounds-file "$work/grounds"
grounds_redacted=$REDACTED
refuse_secrets summary-file "$work/summary"
refuse_secrets verification-file "$work/verification"
refuse_secrets audit-file "$work/audit"
[ -z "$scoping_file" ] || refuse_secrets scoping-file "$work/scoping"
[ -z "$revert_file" ] || refuse_secrets revert-file "$work/revert"

_missing=''
_old_ifs=$IFS
IFS=$LF
for _el in $AUDIT_ELEMENTS; do
  grep -Eiq "^#{1,6}[[:space:]]+$_el" "$work/audit" || _missing="$_missing${_missing:+, }$_el"
done
IFS=$_old_ifs
[ -z "$_missing" ] || die 2 "--audit-file is missing the contract's $_missing (each under its own heading)"

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
      "$_phys"/*) record_rel=${record_path#"$_phys"/} ;;
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
_dir=''
_rest=${rel%/*}
[ "$_rest" != "$rel" ] || _rest=''
while [ -n "$_rest" ]; do
  _seg=${_rest%%/*}
  _dir=${_dir:+$_dir/}$_seg
  if [ -L "$repo_root/$_dir" ] || { [ -e "$repo_root/$_dir" ] && [ ! -d "$repo_root/$_dir" ]; }; then
    die 3 "$_dir is a symlink or not a directory; the record is written inside the checkout only; nothing was written"
  fi
  case $_rest in
    */*) _rest=${_rest#*/} ;;
    *) _rest='' ;;
  esac
done
if [ -e "$repo_root/$rel" ] || [ -L "$repo_root/$rel" ] \
  || git -C "$repo_root" cat-file -e "HEAD:$rel" 2>/dev/null; then
  die 3 "$rel already exists: one flight, one record; nothing was written"
fi
_drc=0
git -C "$repo_root" diff --cached --quiet 2>/dev/null || _drc=$?
case $_drc in
  0) ;;
  1) die 3 "the index holds staged changes; the record commit carries the record alone, so commit or unstage them first; nothing was written" ;;
  *) die 4 "cannot read the index" ;;
esac

render_to "$work/record.md" || die 4 "cannot write the record"
case $rel in
  */*) mkdir -p "$repo_root/${rel%/*}" || die 4 "cannot create ${rel%/*}" ;;
esac
cp "$work/record.md" "$repo_root/$rel" || die 4 "cannot write $rel"
if ! git -C "$repo_root" add -- "$rel" >/dev/null 2>"$work/git.err" \
  || ! git -C "$repo_root" commit -q -m "docs(flight): record flight $flight_id" -- "$rel" >>"$work/git.err" 2>&1; then
  git -C "$repo_root" rm -q --cached --ignore-unmatch -- "$rel" >/dev/null 2>&1 || :
  rm -f "$repo_root/$rel"
  sed 's/^/  /' "$work/git.err" | tr -d '\000-\010\013-\037\177' >&2
  die 4 "could not commit $rel; the record was removed"
fi
# The commit that added the record, not HEAD: a post-commit hook may commit again.
_sha=$(git -C "$repo_root" log -1 --format=%H -- "$rel" 2>/dev/null) && [ -n "$_sha" ] \
  || die 4 "cannot read the record commit"
printf 'record\t%s\n' "$rel"
printf 'commit\t%s\n' "$_sha"
