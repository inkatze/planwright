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
# any backtick run it holds with every line indented two spaces, so no fence,
# tag, heading, or marker it carries renders, closes the collapse, or reaches
# column zero where a line-anchored reader would take it for structure.
# Worker-authored inputs are stripped the same way and refused, never
# rewritten, when they carry a structural line or a token-shaped secret.
#
# Usage:
#   flight-record.sh render --home pr|file <inputs>
#       Print the record. A `pr` record larger than GitHub's PR-body limit is
#       refused (exit 3) and nothing is printed: a truncated record would drop
#       the contract's tail.
#   flight-record.sh land <inputs> [--repo-root <dir>]
#       The no-remote arm: write the `file` record to
#       `specs/_flights/<flight-id>.md` and commit that one file on the
#       flight's own branch, reporting `record<TAB><path>` and
#       `commit<TAB><sha>`. Refused (exit 3, nothing written) off the branch
#       `planwright/flight/<flight-id>`, when the record already exists, or
#       when the index holds other staged changes.
#
#   <inputs>, a later flag overriding an earlier one:
#     --flight-id <id>            grammar-checked by scripts/flight-id.sh
#     --ask-file <file>           the ask as dispatch cleaned it
#     --grounds-file <file>       the route's one-line grounds
#     --summary-file <file>       what changed and why (the lead)
#     --verification-file <file>  how it was verified (the lead)
#     --audit-file <file>         the review sequence's audit record: a heading
#                                 for each of Lens coverage, Auto-applicable,
#                                 Agent-resolvable, Needs sign-off, Needs human
#                                 judgment, Declined log, Pending sign-off, and
#                                 Convergence steps
#     --handle <handle>           the worker handle
#     --scoping-file <file>       optional: the rigor scoping applied; absent
#                                 means none was
#     --revert-file <file>        optional: the revert path; absent takes the
#                                 home's default
#
# The lead may not restate the ask: a summary or verification carrying the
# whole ask, or one of its longer lines, is refused (exit 2).
#
# Exit codes: 0 rendered or landed · 2 usage or an input refused · 3 refused
# by state (over the PR-body limit; for land, the branch, an existing record,
# or a staged index) · 4 an environment failure (a sanitizer, the secret
# screen, or git could not run).
#
# Portable POSIX sh (the bash 3.2 floor); no eval; pathname expansion off.
set -uf
LC_ALL=C
export LC_ALL
unset CDPATH

prog=flight-record
LF='
'

script_dir=$(cd "$(dirname "$0")" && pwd -P) || exit 2
FLIGHT_ID="$script_dir/flight-id.sh"
SCREEN="$script_dir/inception-secret-screen.sh"

# shellcheck source=scripts/flight-text.sh
. "$script_dir/flight-text.sh"

# The ask dispatch accepts, in bytes; each worker input's cap; GitHub's
# PR-body limit, in characters, which a byte count never undershoots.
ASK_MAX=65536
INPUT_MAX=262144
PR_BODY_MAX=65536

die() {
  _rc=$1
  shift
  printf '%s: %s\n' "$prog" "$*" >&2
  exit "$_rc"
}

usage() {
  cat >&2 <<'EOF'
usage: flight-record.sh render --home pr|file <inputs>
       flight-record.sh land <inputs> [--repo-root <dir>]
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

# worker_text <name> <file> <out> — a worker-authored input: cleaned, and
# refused if it carries a structural line. Its secret check runs with the
# others, in refuse_secrets.
worker_text() {
  read_capped "$1" "$2" "$INPUT_MAX" "$work/$1.raw"
  clean_text "$work/$1.raw" "$3" || die 4 "cannot sanitize --$1"
  ! blank "$3" || die 2 "--$1 is empty"
  if grep -Eiq '^[[:space:]]*(</?details([[:space:]>]|$)|</?summary([[:space:]>]|$)|<!--[[:space:]]*planwright:flight-record)' "$3"; then
    die 2 "--$1 carries a line the record's structure owns (a details or summary tag, or a record marker)"
  fi
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
# of 24 characters or more, verbatim up to case and spacing.
restates_ask() {
  cat "$work/summary" "$work/verification" >"$work/lead.txt" || die 4 "cannot assemble the lead"
  normalize "$work/lead.txt" >"$work/lead.norm"
  normalize "$work/ask" >"$work/ask.norm"
  awk '
    NR == FNR { lead = $0; next }
    FILENAME ~ /ask\.norm$/ { if (length($0) >= 16 && index(lead, $0)) hit = 1; next }
    {
      s = tolower($0)
      gsub(/[ \t\r]+/, " ", s)
      sub(/^ /, "", s)
      sub(/ $/, "", s)
      if (s ~ /^\[redacted: /) next
      if (length(s) >= 24 && index(lead, s)) hit = 1
    }
    END { exit hit ? 0 : 1 }' "$work/lead.norm" "$work/ask.norm" "$work/ask"
}

# fenced <file> — the file as a `text` fence longer than any backtick run it
# holds, each non-blank line indented two spaces.
fenced() {
  _fence=$(awk '
    { s = $0; while (match(s, /`+/)) { if (RLENGTH > m) m = RLENGTH; s = substr(s, RSTART + RLENGTH) } }
    END { n = m + 1; if (n < 3) n = 3; for (i = 0; i < n; i++) printf "`" }' "$1")
  printf '%stext\n' "$_fence"
  sed 's/^\(.\)/  \1/' "$1"
  printf '%s\n' "$_fence"
}

# pending_ids — the pending-sign-off checklist IDs, in order, comma-joined.
pending_ids() {
  grep -E '^[[:space:]]*- \[ \] \*\*PS-[0-9]+\*\*' "$work/audit" \
    | grep -Eo 'PS-[0-9]+' | awk '!seen[$0]++' | tr '\n' ',' | sed 's/,$//;s/,/, /g'
}

# render_to <out> — write the record for $home.
# shellcheck disable=SC2016 # the backticks are Markdown code spans
render_to() {
  branch=planwright/flight/$flight_id
  _pending=$(pending_ids)
  {
    printf '<!-- planwright:flight-record id=%s home=%s -->\n' "$flight_id" "$home"
    printf '## Summary\n\n'
    cat "$work/summary"
    printf '\n## Verification\n\n'
    cat "$work/verification"
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
    [ "$ask_stripped" -eq 0 ] || printf 'Invisible or control characters were stripped from it.\n'
    [ "$ask_redacted" -eq 0 ] || printf 'Lines carrying a token-shaped secret were redacted whole.\n'
    printf '\n'
    fenced "$work/ask"
    printf '\n### Route and grounds\n\n'
    printf 'Visual flight. Grounds as the tower stated them:\n\n'
    fenced "$work/grounds"
    printf '\n### Record home\n\n'
    if [ "$home" = pr ]; then
      printf 'The draft PR body of `%s`, declared at routing time.\n' "$branch"
    else
      printf '`specs/_flights/%s.md`, committed on `%s`, declared at routing time.\n' "$flight_id" "$branch"
    fi
    printf '\n### Rigor scoping\n\n'
    if [ -n "$scoping_file" ]; then
      cat "$work/scoping"
    else
      printf 'None applied: every pass in the convergence sequence ran at full rigor.\n'
    fi
    printf '\n### Worker handle\n\n`%s`\n' "$handle"
    printf '\n### Revert path\n\n'
    if [ -n "$revert_file" ]; then
      cat "$work/revert"
    elif [ "$home" = pr ]; then
      printf 'Close the draft PR unmerged to discard the flight. After a merge, `git revert` the merge (or the flight'"'"'s commits) on the default branch.\n'
    else
      printf 'Leave `%s` unmerged to discard the flight. After a merge, `git revert` the flight'"'"'s commits: the record rides the same branch, so one revert undoes record and work together.\n' "$branch"
    fi
    printf '\n### Convergence audit\n\n'
    cat "$work/audit"
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
for _req in flight-id:"$flight_id" ask-file:"$ask_file" grounds-file:"$grounds_file" \
  summary-file:"$summary_file" verification-file:"$verification_file" \
  audit-file:"$audit_file" handle:"$handle"; do
  [ -n "${_req#*:}" ] || die 2 "--${_req%%:*} is required"
done
/bin/sh "$FLIGHT_ID" check "$flight_id" 2>/dev/null </dev/null || die 2 "refusing a malformed flight id"
case $handle in
  *[!A-Za-z0-9._:-]* | [!A-Za-z0-9]*) die 2 "refusing a malformed worker handle (expected [A-Za-z0-9._:-])" ;;
esac
[ "${#handle}" -le 128 ] || die 2 "refusing an over-long worker handle"
[ -x "$SCREEN" ] || [ -f "$SCREEN" ] || die 4 "the secret screen is missing ($SCREEN)"

work=$(mktemp -d "${TMPDIR:-/tmp}/flight-record.XXXXXX") || die 4 "cannot create a work directory"
trap 'rm -rf "$work"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

operator_text ask-file "$ask_file" "$ASK_MAX"
ask_stripped=$CLEAN_STRIPPED
operator_text grounds-file "$grounds_file" 1024
[ "$(grep -c '' "$work/grounds-file.clean")" -le 1 ] || die 2 "--grounds-file must hold one line"

worker_text summary-file "$summary_file" "$work/summary"
worker_text verification-file "$verification_file" "$work/verification"
worker_text audit-file "$audit_file" "$work/audit"
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
  render_to "$work/record.md"
  if [ "$home" = pr ]; then
    _bytes=$(wc -c <"$work/record.md" | tr -d ' ')
    [ "$_bytes" -le "$PR_BODY_MAX" ] \
      || die 3 "the record is $_bytes bytes, over the PR-body limit of $PR_BODY_MAX; trim the audit input (a truncated record would drop the contract's tail)"
  fi
  cat "$work/record.md"
  exit 0
fi

if [ -z "$repo_root" ]; then
  repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || die 4 "not inside a git worktree"
fi
[ -d "$repo_root" ] || die 2 "--repo-root is not a directory"
_head=$(git -C "$repo_root" symbolic-ref -q --short HEAD 2>/dev/null) || _head=''
[ "$_head" = "planwright/flight/$flight_id" ] \
  || die 3 "land runs on the flight's own branch, planwright/flight/$flight_id; nothing was written"
rel=specs/_flights/$flight_id.md
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

render_to "$work/record.md"
mkdir -p "$repo_root/specs/_flights" || die 4 "cannot create specs/_flights"
cp "$work/record.md" "$repo_root/$rel" || die 4 "cannot write $rel"
if ! git -C "$repo_root" add -- "$rel" >/dev/null 2>"$work/git.err" \
  || ! git -C "$repo_root" commit -q -m "docs(flight): record flight $flight_id" -- "$rel" >/dev/null 2>>"$work/git.err"; then
  git -C "$repo_root" rm -q --cached --ignore-unmatch -- "$rel" >/dev/null 2>&1 || :
  rm -f "$repo_root/$rel"
  sed 's/^/  /' "$work/git.err" | tr -d '\000-\010\013-\037\177' >&2
  die 4 "could not commit $rel; the record was removed"
fi
_sha=$(git -C "$repo_root" rev-parse --verify -q HEAD) || die 4 "cannot read the record commit"
printf 'record\t%s\n' "$rel"
printf 'commit\t%s\n' "$_sha"
