#!/usr/bin/env bash
# mc-rules.sh — a mission-control program's rule store: the ground rules and
# standing decisions, kept in rules.yaml in the program home
# (scripts/mc-program.sh resolves the home).
#
# An entry carries id, text, subject, source, date, scope, supersedes and
# withdrawn. A rule is never edited: a changed rule is a new entry that
# supersedes the old one, and a withdrawal is an entry that supersedes one
# with no replacement text. The active set is every entry neither superseded
# nor a withdrawal; list keeps them all.
#
#   subject  free text, one per entry; the shared-subject report groups on
#            its key: ASCII letters lowercased, runs of spaces collapsed,
#            ends trimmed (other letters compare as written)
#   source   who said it, when and where
#   date     YYYY-MM-DD, or `today` for the current UTC date
#   scope    program (in force everywhere), duty:<id> naming a duty the
#            program enables, or repo:<name> where <name> is the last path
#            component of one of the program's repositories; default
#            program. A scope some entry already carries is accepted as is,
#            so a recorded reversal survives a configuration change
#
# Usage:
#   mc-rules.sh add <program> --text <t> --subject <s> --source <s>
#       --date <d> [--scope <scope>]
#   mc-rules.sh supersede <program> <id>
#       (--text <t> [--subject <s>] [--scope <scope>] | --withdraw)
#       --source <s> --date <d>
#       a replacement inherits the old entry's subject and scope unless given
#   mc-rules.sh list <program>       every entry, oldest first
#   mc-rules.sh active <program>     the active set, in the same shape
#   mc-rules.sh render <program> [--scope <scope>]...
#       the active rules in scope as a markdown block between marker lines,
#       the shape a launched session's brief embeds; program rules are in
#       every scope, `--scope program` renders them alone, and no --scope
#       renders every rule
#   mc-rules.sh load <program>       the bring-up load: render with no scope
#   mc-rules.sh conflicts <program>  the shared-subject report
#   mc-rules.sh selfcheck <program> --digest <hex> --held <file>
#       --durable <file>
#       the post-compaction self-check: the digest the session's load
#       carried against the store's, and the open items and live sessions
#       of --durable (read from their stores by the caller) against those
#       the session holds in --held
#
# Output, tab separated:
#   add, supersede   an echo line, then the undo entry:
#                    undo  <act>  <subject>  <new id>  <grounds>  <reversal>
#                    act rule-add, rule-supersede or rule-withdraw; new id the
#                    entry the act wrote; grounds its source; reversal a
#                    shell-quoted command naming this script by its bare
#                    name, run as the installed planwright's scripts/
#                    mc-rules.sh
#   list, active     <id> <status> <date> <scope> <subject> <text> <source>
#                    <supersedes>; status active, superseded or withdrawal,
#                    and `-` for a withdrawal's text or no supersedes
#   conflicts        shared <subject key> <id>,<id>[,...] per key that more
#                    than one active entry carries
#   render, load     the begin marker names the program, the format, the
#                    scope and the SHA-256 digest of the rendered entries;
#                    load's digest is the one selfcheck compares
#   selfcheck        on a pass: self-check passed: rules <digest>,
#                    <n> open items, <n> live sessions
#   load, selfcheck  on any failure, whatever its exit code, at least one
#                    line per operator item to raise:
#                    item  <origin>  <aspect>  <what failed>  <closes>
#                    where closes is the act that settles the item
# --held and --durable hold `item <id>` and `session <handle>` lines.
#
# The store opens with its format field; a store whose format is missing or
# unknown is refused with the field named, as is any line outside the
# grammar this script writes, an absent field included. The field set is
# fixed at format 1: a new field is a new format and its migration. Writes
# take the store's lock (scripts/lock-lib.sh) and replace the file by
# rename, so readers take no lock and never see a torn store; a reader reads
# the file once and checks and parses that one copy.
#
# Exit codes: 0 done; 1 a refused or unreadable store, an entry that cannot
# be superseded, a program home that does not resolve, a missing tool
# (iconv, a SHA-256 tool), a failed write or lock, a failed load or
# self-check; 2 usage or an invalid value; 3 the program is not configured.
# An entry written whose lock then fails to release still exits 0, with a
# warning on stderr: the write landed, and retrying would add it twice.
#
# Portable bash 3.2 / BSD tooling; iconv checks values are UTF-8.
set -u
set -f
LC_ALL=C
export LC_ALL
unset CDPATH

prog=mc-rules
script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2
for dep in echo-safety.sh lock-lib.sh mc-program.sh; do
  if [ ! -r "$script_dir/$dep" ]; then
    printf '%s\n' "$prog: $dep is missing or unreadable (broken install)" >&2
    exit 2
  fi
done
# shellcheck source=scripts/echo-safety.sh
. "$script_dir/echo-safety.sh" || exit 2
# shellcheck source=scripts/lock-lib.sh
. "$script_dir/lock-lib.sh" || exit 2

FORMAT=1
FIELDS="id text subject source date scope supersedes withdrawn"
MAX_TEXT=2000
MAX_SHORT=200

# A load or self-check that fails for any reason is an operator item; the
# exit handler raises the generic one when the verb raised none itself.
ITEM_ORIGIN=""
ITEM_ASPECT=""
ITEM_TEXT=""
ITEM_CLOSES=""
ITEM_RAISED=0
item() { # item <aspect> <what failed> <closes>
  printf 'item\t%s\t%s\t%s\t%s\n' "$ITEM_ORIGIN" "$1" "$(sanitize_printable "$2")" "$3"
  ITEM_RAISED=1
}

scratch=""
# shellcheck disable=SC2329 # invoked from the EXIT trap
cleanup() {
  cl_rc=$?
  pw_lock_release_all
  [ -z "$scratch" ] || rm -f "$scratch"
  if [ "$cl_rc" -ne 0 ] && [ -n "$ITEM_ORIGIN" ] && [ "$ITEM_RAISED" -eq 0 ]; then
    item "$ITEM_ASPECT" "$ITEM_TEXT" "$ITEM_CLOSES"
  fi
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

say() { printf '%s\n' "$prog: $(sanitize_printable "$1")" >&2; }
die() { # die <code> <message>
  say "$2"
  exit "$1"
}
usage() {
  printf '%s\n' "usage: mc-rules.sh add|supersede|list|active|render|load|conflicts|selfcheck <program> ... (mc-rules.sh --help)" >&2
  exit 2
}

# check_value <field> <value> <max-bytes>: a non-empty single-line UTF-8
# value free of control characters (C0, DEL and C1, which drive a terminal
# and would forge a line or a field), within its length.
check_value() {
  [ -n "$2" ] || die 2 "--$1 is empty"
  [ "${#2}" -le "$3" ] || die 2 "--$1 is longer than $3 bytes"
  case $2 in
    *[[:cntrl:]]* | *$'\302'[$'\200'-$'\237']*) die 2 "--$1 carries a control character" ;;
  esac
  utf8 "$2" || die 2 "--$1 is not UTF-8 text"
}

# utf8 <text>: whether the text is valid UTF-8. Compared, not just run: an
# iconv that drops invalid bytes may exit 0.
utf8() {
  command -v iconv >/dev/null 2>&1 || die 1 "iconv is missing, so text cannot be checked as UTF-8"
  u8_rt=$(printf '%s' "$1" | iconv -f UTF-8 -t UTF-8 2>/dev/null && printf x)
  [ "$u8_rt" = "$1"x ]
}

# trim <var>: strip the named variable's leading and trailing spaces.
trim() {
  eval "tm_v=\$$1"
  while :; do
    case $tm_v in
      ' '*) tm_v=${tm_v# } ;;
      *' ') tm_v=${tm_v% } ;;
      *) break ;;
    esac
  done
  eval "$1=\$tm_v"
}

check_scope() {
  case $1 in
    program) return 0 ;;
    duty:*)
      sc_name=${1#duty:}
      case $sc_name in
        "" | [!a-z0-9]* | *[!a-z0-9-]*) die 2 "--scope '$1' does not name a duty id" ;;
      esac
      ;;
    repo:*)
      sc_name=${1#repo:}
      case $sc_name in
        "" | [!A-Za-z0-9]* | *[!A-Za-z0-9._-]*) die 2 "--scope '$1' does not name a repository" ;;
      esac
      ;;
    *) die 2 "--scope '$1' is not program, duty:<id> or repo:<name>" ;;
  esac
  [ "${#sc_name}" -le 64 ] || die 2 "--scope '$1' names more than 64 characters"
}

# scope_known <program> <scope>: a scope new to the store names a duty the
# program enables or one of its repositories, so the launcher can deliver
# it. A scope an entry already carries passes, so a reversal recorded under
# an earlier configuration still runs.
scope_known() {
  case $2 in
    duty:* | repo:*)
      snap_store
      sk_entries=$(parse_store) || exit 1
      printf '%s\n' "$sk_entries" | awk -F '\t' -v s="$2" '$6 == s { f = 1 } END { exit !f }' && return 0
      ;;
  esac
  case $2 in
    duty:*)
      sk_list=$(/bin/bash "$script_dir/mc-program.sh" get "$1" duties) || exit 1
      sk_what="duty '${2#duty:}' is not enabled for program $1"
      ;;
    repo:*)
      sk_repos=$(/bin/bash "$script_dir/mc-program.sh" get "$1" repositories) || exit 1
      sk_list=$(printf '%s\n' "$sk_repos" | sed 's:/*$::; s:.*/::')
      if printf '%s\n' "$sk_list" | sort | uniq -d | grep -Fxq -- "${2#repo:}"; then
        die 2 "--scope '$2' is ambiguous: two of program $1's repositories end in that name"
      fi
      sk_what="no repository of program $1 ends in '${2#repo:}'"
      ;;
    *) return 0 ;;
  esac
  printf '%s\n' "$sk_list" | grep -Fxq -- "${2#*:}" || die 2 "--scope '$2': $sk_what"
}

# resolve_date <arg>: set DATE to a calendar-shaped YYYY-MM-DD.
resolve_date() {
  case $1 in
    today)
      DATE=$(date -u +%Y-%m-%d) || die 1 "cannot read the current date"
      ;;
    [0-9][0-9][0-9][0-9]-0[1-9]-0[1-9] | [0-9][0-9][0-9][0-9]-0[1-9]-[12][0-9] | [0-9][0-9][0-9][0-9]-0[1-9]-3[01] | \
      [0-9][0-9][0-9][0-9]-1[0-2]-0[1-9] | [0-9][0-9][0-9][0-9]-1[0-2]-[12][0-9] | [0-9][0-9][0-9][0-9]-1[0-2]-3[01])
      DATE=$1
      ;;
    *) die 2 "--date '$1' is not a YYYY-MM-DD date or today" ;;
  esac
}

# An id's number stays within nine digits, so awk's arithmetic on it is
# exact and the next id never prints in exponent form.
check_id() {
  case $1 in
    r-[1-9] | r-[1-9]*[0-9]) ;;
    *) die 2 "'$1' is not a rule id (r-<n>)" ;;
  esac
  case ${1#r-} in
    *[!0-9]* | ??????????*) die 2 "'$1' is not a rule id (r-<n>, at most nine digits)" ;;
  esac
}

shell_quote() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }
# store_quote <value>: the value double-quoted for the store, \ and " escaped.
store_quote() { printf '"%s"' "$(printf '%s' "$1" | sed 's/[\\"]/\\&/g')"; }

sha256() { # sha256: the SHA-256 of stdin in hex
  if command -v sha256sum >/dev/null 2>&1; then
    dg_d=$(sha256sum)
  elif command -v shasum >/dev/null 2>&1; then
    dg_d=$(shasum -a 256)
  elif command -v openssl >/dev/null 2>&1; then
    dg_d=$(openssl dgst -sha256 -r)
  else
    die 1 "no SHA-256 tool (sha256sum, shasum or openssl) is on PATH"
  fi
  dg_d=${dg_d%%[!0-9a-f]*}
  [ "${#dg_d}" -eq 64 ] || die 1 "the SHA-256 tool printed no digest"
  printf '%s\n' "$dg_d"
}
# digest_of <rows>: hashed from a pipe, so no copy of the rules leaves the
# program home.
digest_of() {
  if [ -n "$1" ]; then
    printf '%s\n' "$1" | sha256
  else
    sha256 </dev/null
  fi
}

# resolve_home <program>: set HOME_DIR and STORE, or exit 2 (an invalid
# name), 3 (not configured) or 1 (any other failure).
resolve_home() {
  HOME_DIR=$(/bin/bash "$script_dir/mc-program.sh" get "$1" home)
  rh_rc=$?
  case $rh_rc in
    0) ;;
    2 | 3) exit "$rh_rc" ;;
    *) die 1 "the home of program $1 does not resolve (mc-program.sh exit $rh_rc)" ;;
  esac
  case $HOME_DIR in
    /*) ;;
    *) die 1 "the program home '$HOME_DIR' is not absolute" ;;
  esac
  STORE=$HOME_DIR/rules.yaml
}

# snap_store: read the store once into STORE_TEXT (empty when there is no
# store yet), refusing a link, a file that is not UTF-8 text, or one this
# script would not have written; every later check and parse reads that one
# copy, so a rename landing mid-read cannot pair one version's check with
# another's parse. Runs in this shell, never a subshell.
snap_store() {
  STORE_TEXT=""
  STORE_PRESENT=0
  [ -e "$STORE" ] || [ -L "$STORE" ] || return 0
  [ ! -L "$STORE" ] || die 1 "$STORE is a symbolic link; refusing to read through it"
  [ -f "$STORE" ] && [ -r "$STORE" ] || die 1 "$STORE is not a readable file"
  STORE_PRESENT=1
  # A NUL would vanish in the substitution; as \001 the grammar refuses it.
  STORE_TEXT=$(tr '\000' '\001' <"$STORE" && printf x) || die 1 "cannot read $STORE"
  STORE_TEXT=${STORE_TEXT%x}
  utf8 "$STORE_TEXT" || die 1 "$STORE is not UTF-8 text"
}

# parse_store: print STORE_TEXT's entries, one per line, the fields in FIELDS
# order and tab separated, with every value unescaped.
parse_store() {
  [ "$STORE_PRESENT" -eq 1 ] || return 0
  printf '%s' "$STORE_TEXT" | FILE=$(sanitize_printable "$STORE") WANT=$FORMAT FIELDS=$FIELDS awk '
    function bad(msg) {
      printf "mc-rules: %s:%d: %s\n", ENVIRON["FILE"], NR, msg > "/dev/stderr"
      failed = 1
      exit 1
    }
    function unq(v,   out, i, c, n) {
      if (length(v) < 2 || v !~ /^".*"$/) bad("a value is not a quoted string")
      v = substr(v, 2, length(v) - 2)
      if (index(v, "\\") == 0) {
        if (index(v, "\"")) bad("an unescaped quote inside a quoted value")
        return v
      }
      out = ""
      n = length(v)
      for (i = 1; i <= n; i++) {
        c = substr(v, i, 1)
        if (c == "\\") {
          c = substr(v, ++i, 1)
          if (c != "\\" && c != "\"") bad("an unknown escape in a quoted value")
        } else if (c == "\"") bad("an unescaped quote inside a quoted value")
        out = out c
      }
      return out
    }
    function flush(   i, k) {
      if (!open) return
      for (i = 1; i <= nf; i++)
        if (!(F[i] in cur)) bad("entry " cur["id"] " lacks its " F[i] " field")
      if (cur["withdrawn"] == "false" && cur["text"] == "") bad("entry " cur["id"] " has empty text")
      if (cur["withdrawn"] == "true" && cur["supersedes"] == "-") bad("withdrawal " cur["id"] " names no entry")
      if (cur["subject"] == "") bad("entry " cur["id"] " has an empty subject")
      if (cur["source"] == "") bad("entry " cur["id"] " has an empty source")
      if (cur["supersedes"] != "-" && !(cur["supersedes"] in ids)) bad("entry " cur["id"] " supersedes " cur["supersedes"] ", which no earlier entry is")
      if (cur["id"] in ids) bad("entry " cur["id"] " appears twice")
      ids[cur["id"]] = 1
      row = cur[F[1]]
      for (i = 2; i <= nf; i++) row = row "\t" cur[F[i]]
      print row
      for (k in cur) delete cur[k]
      open = 0
    }
    BEGIN {
      nf = split(ENVIRON["FIELDS"], F, " ")
      for (i = 1; i <= nf; i++) known[F[i]] = 1
    }
    /[\001-\037\177]|\302[\200-\237]/ { bad("a control character") }
    /^#/ || /^[ ]*$/ { next }
    !have_format {
      if ($0 !~ /^format:/) bad("format: the store does not open with its format field")
      v = $0; sub(/^format:[ ]*/, "", v); sub(/[ ]+$/, "", v)
      if (v != ENVIRON["WANT"]) bad("format: unknown format '\''" v "'\'' (known: " ENVIRON["WANT"] ")")
      have_format = 1
      next
    }
    !have_rules {
      if ($0 != "rules:") bad("expected the rules: list after the format field")
      have_rules = 1
      next
    }
    /^  - id: / {
      flush()
      open = 1
      key = "id"; v = substr($0, 9)
    }
    !/^  - id: / {
      if (!open || $0 !~ /^    [a-z]+: /) bad("a line outside the store grammar")
      key = $0; sub(/^    /, "", key); sub(/:.*/, "", key)
      v = $0; sub(/^    [a-z]+: /, "", v)
      if (!(key in known) || key == "id") bad("an unknown field \"" key "\"")
      if (key in cur) bad("entry " cur["id"] " repeats its " key " field")
    }
    {
      if (key == "text" || key == "subject" || key == "source") v = unq(v)
      else if (key == "id" || key == "supersedes") {
        if ((v !~ /^r-[1-9][0-9]*$/ || length(v) > 11) && !(key == "supersedes" && v == "-")) bad("\"" v "\" is not a rule id")
      } else if (key == "date") {
        if (v !~ /^[0-9][0-9][0-9][0-9]-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])$/) bad("\"" v "\" is not a YYYY-MM-DD date")
      } else if (key == "scope") {
        if (v != "program" && v !~ /^duty:[a-z0-9][a-z0-9-]*$/ && v !~ /^repo:[A-Za-z0-9][A-Za-z0-9._-]*$/) bad("\"" v "\" is not a scope")
      } else if (key == "withdrawn") {
        if (v != "true" && v != "false") bad("withdrawn is \"" v "\", not true or false")
      }
      cur[key] = v
    }
    END {
      if (failed) exit 1
      if (!have_format) bad("format: the store does not open with its format field")
      if (!have_rules) bad("the store has no rules: list")
      flush()
    }
  ' || exit 1
}

# read_store: snap and parse, for a caller in a command substitution.
read_store() {
  snap_store
  parse_store
}

# rows <entries>: list rows, each entry's status derived.
rows() {
  printf '%s\n' "$1" | awk -F '\t' '
    NF { n++; e[n] = $0; id[n] = $1; wd[n] = $8; if ($7 != "-") gone[$7] = 1 }
    END {
      for (i = 1; i <= n; i++) {
        split(e[i], f, "\t")
        st = wd[i] == "true" ? "withdrawal" : (id[i] in gone ? "superseded" : "active")
        text = wd[i] == "true" ? "-" : f[2]
        printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n", f[1], st, f[5], f[6], f[3], text, f[4], f[7]
      }
    }'
}
active_rows() { rows "$1" | awk -F '\t' '$2 == "active"'; }

# in_scope <scopes>: the active rows (stdin) a session in those scopes
# carries; no scopes keeps every row.
in_scope() {
  SCOPES=$1 awk -F '\t' '
    BEGIN { n = split(ENVIRON["SCOPES"], s, " "); for (i = 1; i <= n; i++) want[s[i]] = 1 }
    n == 0 || $4 == "program" || ($4 in want)'
}

render() { # render <program> <scopes> <scope label>
  rd_entries=$(read_store) || exit 1
  rd_rows=$(active_rows "$rd_entries" | in_scope "$2")
  rd_digest=$(digest_of "$rd_rows") || exit 1
  printf '%s\n' "<!-- mc-rules begin: program $1, format $FORMAT, scope $3, digest $rd_digest -->"
  printf '%s\n' "## Standing rules" ""
  if [ -z "$rd_rows" ]; then
    printf '%s\n' "No standing rule is in force."
  else
    printf '%s\n' "$rd_rows" | awk -F '\t' '{ printf "- **%s**: %s (%s, %s, %s, %s)\n", $5, $6, $1, $7, $3, $4 }'
  fi
  printf '%s\n' "<!-- mc-rules end -->"
}

# append <precheck> <text> <subject> <source> <date> <scope> <supersedes>
# <withdrawn>: under the store's lock, re-read the store, run the precheck
# function against its entries, then write the store with the entry
# appended under the next free id, set in NEW_ID. The precheck may refine
# the entry through ENTRY_SUBJECT and ENTRY_SCOPE. Called in this shell,
# never a subshell, so the hold is this process's and the exit trap
# releases it; the caller releases it with release_store once it has
# reported the write.
append() {
  ap_precheck=$1
  ENTRY_SUBJECT=$3
  ENTRY_SCOPE=$6
  if [ ! -d "$HOME_DIR" ]; then
    (umask 077 && mkdir -p "$HOME_DIR") || die 1 "cannot create the program home $HOME_DIR"
  fi
  STORE_LOCK=$HOME_DIR/rules.lock
  ap_rc=0
  pw_lock_acquire "$STORE_LOCK" || ap_rc=$?
  case $ap_rc in
    0) ;;
    1) die 1 "the rule store is busy (another writer holds $STORE_LOCK); try again" ;;
    *) die 1 "cannot take the rule store lock at $STORE_LOCK" ;;
  esac
  snap_store
  ap_entries=$(parse_store) || exit 1
  "$ap_precheck" "$ap_entries"
  ap_n=$(printf '%s\n' "$ap_entries" | awk -F '\t' 'NF { n = substr($1, 3) + 0; if (n > m) m = n } END { print m + 1 }')
  NEW_ID=r-$ap_n
  check_id "$NEW_ID"
  scratch=$(mktemp "$HOME_DIR/.rules.yaml.XXXXXX") || die 1 "cannot create a scratch file in $HOME_DIR"
  {
    if [ -n "$STORE_TEXT" ]; then
      printf '%s' "$STORE_TEXT"
      # A hand edit can leave the last line unterminated.
      case $STORE_TEXT in
        *"
") ;;
        *) printf '\n' ;;
      esac
    else
      printf '%s\n' "# A mission-control program's rule store, written by scripts/mc-rules.sh." "format: $FORMAT" "rules:"
    fi
    printf '%s\n' "  - id: $NEW_ID" \
      "    text: $(store_quote "$2")" \
      "    subject: $(store_quote "$ENTRY_SUBJECT")" \
      "    source: $(store_quote "$4")" \
      "    date: $5" \
      "    scope: $ENTRY_SCOPE" \
      "    supersedes: $7" \
      "    withdrawn: $8"
  } >"$scratch" || die 1 "cannot write $scratch"
  chmod 600 "$scratch" || die 1 "cannot set the mode of $scratch"
  mv -f "$scratch" "$STORE" || die 1 "cannot replace $STORE"
  scratch=""
}

release_store() {
  pw_lock_release "$STORE_LOCK" \
    || say "warning: entry $NEW_ID is written, but the lock at $STORE_LOCK was not released; do not retry the write"
}

no_check() { :; }

# check_target <entries>: the entry TARGET names is active; its fields
# become the replacement's defaults (OLD_*, ENTRY_SUBJECT, ENTRY_SCOPE).
check_target() {
  ct_line=$(rows "$1" | awk -F '\t' -v id="$TARGET" '$1 == id')
  [ -n "$ct_line" ] || die 1 "no entry $TARGET in the store"
  IFS='	' read -r _ ct_status _ OLD_SCOPE OLD_SUBJECT OLD_TEXT _ _ <<EOF
$ct_line
EOF
  [ "$ct_status" = active ] || die 1 "entry $TARGET is $ct_status, not active, so it cannot be superseded"
  ENTRY_SUBJECT=${SUBJECT:-$OLD_SUBJECT}
  ENTRY_SCOPE=${SCOPE:-$OLD_SCOPE}
}

undo_line() { # undo_line <act> <reversal>
  printf 'undo\t%s\t%s\t%s\t%s\t%s\n' "$1" "$ENTRY_SUBJECT" "$NEW_ID" "$SOURCE" "$2"
}

TEXT="" SUBJECT="" SOURCE="" DATE_ARG="" SCOPE="" WITHDRAW=0
parse_opts() {
  while [ $# -gt 0 ]; do
    case $1 in
      --text | --subject | --source | --date | --scope)
        [ $# -ge 2 ] || usage
        case $1 in
          --text) TEXT=$2 ;;
          --subject) SUBJECT=$2 ;;
          --source) SOURCE=$2 ;;
          --date) DATE_ARG=$2 ;;
          --scope) SCOPE=$2 ;;
        esac
        shift 2
        ;;
      --withdraw)
        WITHDRAW=1
        shift
        ;;
      *) usage ;;
    esac
  done
  trim TEXT
  trim SUBJECT
  trim SOURCE
}

need() { # need <field> <value>
  [ -n "$2" ] || die 2 "--$1 is required"
}

[ $# -ge 1 ] || usage
verb=$1
shift
case $verb in
  -h | --help)
    awk 'NR>=2 { if ($0 ~ /^#/) { sub(/^# ?/, ""); print } else exit }' "$0"
    exit 0
    ;;
esac
program=${1:-}
case $verb in
  load)
    ITEM_ORIGIN=rules-load ITEM_ASPECT=load
    ITEM_TEXT="the active rules of program ${program:-(none named)} could not be loaded"
    ITEM_CLOSES="repair the rule store, then reload the rules"
    ;;
  selfcheck)
    ITEM_ORIGIN=self-check ITEM_ASPECT=run
    ITEM_TEXT="the self-check of program ${program:-(none named)} could not run"
    ITEM_CLOSES="repair what failed, then rerun the self-check"
    ;;
esac
[ $# -ge 1 ] || usage
shift

case $verb in
  add)
    parse_opts "$@"
    [ "$WITHDRAW" -eq 0 ] || usage
    need text "$TEXT"
    need subject "$SUBJECT"
    need source "$SOURCE"
    need date "$DATE_ARG"
    check_value text "$TEXT" "$MAX_TEXT"
    check_value subject "$SUBJECT" "$MAX_SHORT"
    check_value source "$SOURCE" "$MAX_SHORT"
    resolve_date "$DATE_ARG"
    SCOPE=${SCOPE:-program}
    check_scope "$SCOPE"
    resolve_home "$program"
    scope_known "$program" "$SCOPE"
    append no_check "$TEXT" "$SUBJECT" "$SOURCE" "$DATE" "$SCOPE" - false
    printf '%s\n' "rule $NEW_ID added ($ENTRY_SCOPE): $ENTRY_SUBJECT: $TEXT"
    undo_line rule-add "mc-rules.sh supersede $program $NEW_ID --withdraw --source $(shell_quote "undo of $NEW_ID") --date today"
    release_store
    ;;
  supersede)
    [ $# -ge 1 ] || usage
    TARGET=$1
    shift
    check_id "$TARGET"
    parse_opts "$@"
    if [ "$WITHDRAW" -eq 1 ]; then
      [ -z "$TEXT" ] && [ -z "$SUBJECT" ] && [ -z "$SCOPE" ] || die 2 "--withdraw takes no --text, --subject or --scope"
    else
      need text "$TEXT"
      check_value text "$TEXT" "$MAX_TEXT"
    fi
    [ -z "$SUBJECT" ] || check_value subject "$SUBJECT" "$MAX_SHORT"
    [ -z "$SCOPE" ] || check_scope "$SCOPE"
    need source "$SOURCE"
    need date "$DATE_ARG"
    check_value source "$SOURCE" "$MAX_SHORT"
    resolve_date "$DATE_ARG"
    resolve_home "$program"
    [ -z "$SCOPE" ] || scope_known "$program" "$SCOPE"
    if [ "$WITHDRAW" -eq 1 ]; then
      append check_target "" "" "$SOURCE" "$DATE" "" "$TARGET" true
      printf '%s\n' "rule $NEW_ID withdraws $TARGET: $ENTRY_SUBJECT"
      undo_line rule-withdraw "mc-rules.sh add $program --text $(shell_quote "$OLD_TEXT") --subject $(shell_quote "$OLD_SUBJECT") --scope $OLD_SCOPE --source $(shell_quote "undo of $NEW_ID") --date today"
    else
      append check_target "$TEXT" "" "$SOURCE" "$DATE" "" "$TARGET" false
      printf '%s\n' "rule $NEW_ID supersedes $TARGET ($ENTRY_SCOPE): $ENTRY_SUBJECT: $TEXT"
      undo_line rule-supersede "mc-rules.sh supersede $program $NEW_ID --text $(shell_quote "$OLD_TEXT") --subject $(shell_quote "$OLD_SUBJECT") --scope $OLD_SCOPE --source $(shell_quote "undo of $NEW_ID") --date today"
    fi
    release_store
    ;;
  list | active | conflicts | load)
    [ $# -eq 0 ] || usage
    resolve_home "$program"
    if [ "$verb" = load ]; then
      render "$program" "" all
      exit 0
    fi
    entries=$(read_store) || exit 1
    case $verb in
      list) [ -z "$entries" ] || rows "$entries" ;;
      active) [ -z "$entries" ] || active_rows "$entries" ;;
      conflicts)
        [ -z "$entries" ] || active_rows "$entries" | awk -F '\t' '
          {
            k = tolower($5); gsub(/[ ]+/, " ", k); sub(/^ /, "", k); sub(/ $/, "", k)
            if (k in ids) ids[k] = ids[k] "," $1
            else { order[++n] = k; ids[k] = $1 }
            count[k]++
          }
          END { for (i = 1; i <= n; i++) if (count[order[i]] > 1) printf "shared\t%s\t%s\n", order[i], ids[order[i]] }'
        ;;
    esac
    ;;
  render)
    scopes=""
    while [ $# -gt 0 ]; do
      [ "$1" = --scope ] && [ $# -ge 2 ] || usage
      check_scope "$2"
      scopes="$scopes $2"
      shift 2
    done
    resolve_home "$program"
    label=${scopes# }
    render "$program" "$scopes" "${label:-all}"
    ;;
  selfcheck)
    digest="" held="" durable=""
    while [ $# -gt 0 ]; do
      [ $# -ge 2 ] || usage
      case $1 in
        --digest) digest=$2 ;;
        --held) held=$2 ;;
        --durable) durable=$2 ;;
        *) usage ;;
      esac
      shift 2
    done
    need digest "$digest"
    need held "$held"
    need durable "$durable"
    # A relative name shaped like name=value is an assignment to awk.
    case $held in /*) ;; *) held=./$held ;; esac
    case $durable in /*) ;; *) durable=./$durable ;; esac
    for f in "$held" "$durable"; do
      [ -f "$f" ] && [ -r "$f" ] || die 1 "$f is not a readable file"
      bad_line=$(awk '!/^[ ]*$/ && !/^(item|session) [A-Za-z0-9._:-]+$/ { print NR; exit }' <"$f")
      [ -z "$bad_line" ] || die 1 "$f:$bad_line: not an 'item <id>' or 'session <handle>' line"
    done
    resolve_home "$program"
    if ! entries=$(read_store); then
      item rules "the rule store of program $program cannot be read" "repair the rule store, then reload the rules"
      exit 1
    fi
    store_digest=$(digest_of "$(active_rows "$entries")") || exit 1
    failed=0
    if [ "$digest" != "$store_digest" ]; then
      item rules "the loaded rules (digest $digest) are not the active set (digest $store_digest)" "reload the rules"
      failed=1
    fi
    for kind in item session; do
      missing=$(H=$held awk -v k="$kind" '
        FILENAME == ENVIRON["H"] { if ($1 == k) h[$2] = 1; next }
        $1 == k && !($2 in h) { printf "%s%s", sep, $2; sep = " " }' "$held" "$durable")
      [ -z "$missing" ] && continue
      case $kind in
        item) item items "open items missing from the held picture: $missing" "re-derive the open items from the queue" ;;
        session) item sessions "live sessions missing from the held picture: $missing" "re-derive the live sessions from the registry" ;;
      esac
      failed=1
    done
    [ "$failed" -eq 0 ] || exit 1
    printf 'self-check passed: rules %s, %s open items, %s live sessions\n' "$store_digest" \
      "$(grep -c '^item ' "$durable")" "$(grep -c '^session ' "$durable")"
    ;;
  *) usage ;;
esac
