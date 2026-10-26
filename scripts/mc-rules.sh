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
#            it case-folded with its spaces collapsed
#   source   who said it, when and where
#   date     YYYY-MM-DD, or `today` for the current UTC date
#   scope    program (in force everywhere), duty:<duty-id> or
#            repo:<repository-name>; default program
#
# Usage:
#   mc-rules.sh add <program> --text <t> --subject <s> --source <s>
#       --date <d> [--scope <scope>]
#   mc-rules.sh supersede <program> <id> (--text <t> | --withdraw)
#       [--subject <s>] [--scope <scope>] --source <s> --date <d>
#       a replacement inherits the old entry's subject and scope unless given
#   mc-rules.sh list <program>       every entry, oldest first
#   mc-rules.sh active <program>     the active set, in the same shape
#   mc-rules.sh render <program> [--scope <scope>]...
#       the active rules in scope as a markdown block between marker lines,
#       the shape a launched session's brief embeds; program rules are in
#       every scope, and no --scope renders every rule
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
#                    undo  <act>  <subject>  <target id>  <source>  <reversal>
#                    where the reversal is a shell-quoted mc-rules.sh command
#   list, active     <id> <status> <date> <scope> <subject> <text> <source>
#                    <supersedes>; status active, superseded or withdrawal,
#                    and `-` for a withdrawal's text or no supersedes
#   conflicts        shared <subject> <id>,<id>[,...] per subject that more
#                    than one active entry carries
#   render, load     the begin marker names the program, the format, the
#                    scope and the SHA-256 digest of the rendered entries;
#                    load's digest is the one selfcheck compares
#   load, selfcheck  on failure, one line per operator item to raise:
#                    item  <origin>  <aspect>  <what failed>
# --held and --durable hold `item <id>` and `session <handle>` lines.
#
# The store opens with its format field; a store whose format is missing or
# unknown is refused with the field named, as is any line outside the
# grammar this script writes. Writes take the store's lock
# (scripts/lock-lib.sh) and replace the file by rename, so readers take no
# lock and never see a torn store.
#
# Exit codes: 0 done; 1 a refused or unreadable store, an entry that cannot
# be superseded, a failed write or lock, a failed load or self-check;
# 2 usage or an invalid value; 3 the program is not configured.
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

scratch=""
# shellcheck disable=SC2329 # invoked from the EXIT trap
cleanup() {
  pw_lock_release_all
  [ -z "$scratch" ] || rm -f "$scratch"
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
  command -v iconv >/dev/null 2>&1 || die 1 "iconv is missing, so --$1 cannot be checked as UTF-8"
  [ "$(printf '%s' "$2" | iconv -f UTF-8 -t UTF-8 2>/dev/null)" = "$2" ] || die 2 "--$1 is not UTF-8 text"
}

trim() { # trim <value>: without its leading and trailing spaces
  tr_v=$1
  while :; do
    case $tr_v in
      ' '*) tr_v=${tr_v# } ;;
      *' ') tr_v=${tr_v% } ;;
      *) break ;;
    esac
  done
  printf '%s' "$tr_v"
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

check_date() {
  case $1 in
    today)
      DATE=$(date -u +%Y-%m-%d) || die 1 "cannot read the current date"
      ;;
    [0-9][0-9][0-9][0-9]-[01][0-9]-[0-3][0-9]) DATE=$1 ;;
    *) die 2 "--date '$1' is not YYYY-MM-DD or today" ;;
  esac
}

check_id() {
  case $1 in
    r-[1-9] | r-[1-9]*[0-9]) ;;
    *) die 2 "'$1' is not a rule id (r-<n>)" ;;
  esac
  case ${1#r-} in
    *[!0-9]*) die 2 "'$1' is not a rule id (r-<n>)" ;;
  esac
}

# sq <value>: the value single-quoted for a shell.
sq() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }
# yq <value>: the value double-quoted for the store, \ and " escaped.
yq() { printf '"%s"' "$(printf '%s' "$1" | sed 's/[\\"]/\\&/g')"; }

sha256() { # sha256 <file>
  if command -v sha256sum >/dev/null 2>&1; then
    sh_d=$(sha256sum <"$1")
  elif command -v shasum >/dev/null 2>&1; then
    sh_d=$(shasum -a 256 <"$1")
  elif command -v openssl >/dev/null 2>&1; then
    sh_d=$(openssl dgst -sha256 -r <"$1")
  else
    die 1 "no SHA-256 tool (sha256sum, shasum or openssl) is on PATH"
  fi
  sh_d=${sh_d%%[!0-9a-f]*}
  [ "${#sh_d}" -eq 64 ] || die 1 "the SHA-256 tool printed no digest"
  printf '%s\n' "$sh_d"
}

# resolve_home <program>: set HOME_DIR and STORE, or exit with mc-program's
# own code (2 an invalid name, 3 not configured).
resolve_home() {
  HOME_DIR=$(/bin/bash "$script_dir/mc-program.sh" get "$1" home)
  rh_rc=$?
  [ "$rh_rc" -eq 0 ] || exit "$rh_rc"
  case $HOME_DIR in
    /*) ;;
    *) die 1 "the program home '$HOME_DIR' is not absolute" ;;
  esac
  STORE=$HOME_DIR/rules.yaml
}

# read_store: print the store's entries, one per line, the fields in FIELDS
# order and tab separated, with every value unescaped; nothing when no store
# exists yet. A store this script would not have written is refused.
read_store() {
  [ -e "$STORE" ] || [ -L "$STORE" ] || return 0
  [ ! -L "$STORE" ] || die 1 "$STORE is a symbolic link; refusing to read through it"
  [ -f "$STORE" ] && [ -r "$STORE" ] || die 1 "$STORE is not a readable file"
  command -v iconv >/dev/null 2>&1 || die 1 "iconv is missing, so $STORE cannot be checked as UTF-8"
  # Compared, not just run: an iconv that drops invalid bytes may exit 0.
  # shellcheck disable=SC2094 # both sides only read the store
  iconv -f UTF-8 -t UTF-8 <"$STORE" 2>/dev/null | cmp -s - "$STORE" || die 1 "$STORE is not UTF-8 text"
  FILE=$STORE WANT=$FORMAT FIELDS=$FIELDS awk '
    function bad(msg) {
      printf "mc-rules: %s:%d: %s\n", ENVIRON["FILE"], NR, msg > "/dev/stderr"
      failed = 1
      exit 1
    }
    function unq(v,   out, i, c, n) {
      if (length(v) < 2 || v !~ /^".*"$/) bad("a value is not a quoted string")
      v = substr(v, 2, length(v) - 2)
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
        if (v !~ /^r-[1-9][0-9]*$/ && !(key == "supersedes" && v == "-")) bad("\"" v "\" is not a rule id")
      } else if (key == "date") {
        if (v !~ /^[0-9][0-9][0-9][0-9]-[01][0-9]-[0-3][0-9]$/) bad("\"" v "\" is not a YYYY-MM-DD date")
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
  ' "$STORE" || exit 1
}

# rows <entries>: list rows, each entry's status derived.
rows() {
  printf '%s\n' "$1" | awk -F '\t' '
    NF { n++; e[n] = $0; id[n] = $1; sup[n] = $7; wd[n] = $8; if ($7 != "-") gone[$7] = 1 }
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

digest_of() { # digest_of <rows>
  dg_file=$(mktemp) || die 1 "cannot create a scratch file"
  [ -z "$1" ] || printf '%s\n' "$1" >"$dg_file"
  dg=$(sha256 "$dg_file")
  dg_rc=$?
  rm -f "$dg_file"
  [ "$dg_rc" -eq 0 ] || exit 1
  printf '%s\n' "$dg"
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

# append <text> <subject> <source> <date> <scope> <supersedes> <withdrawn>:
# under the store's lock, re-read the store, run $PRECHECK against it, then
# write the store with the entry appended under the next free id, set in
# NEW_ID. Called in this shell, never a subshell, so the hold is this
# process's and the exit trap releases it.
append() {
  if [ ! -d "$HOME_DIR" ]; then
    (umask 077 && mkdir -p "$HOME_DIR") || die 1 "cannot create the program home $HOME_DIR"
  fi
  ap_lock=$HOME_DIR/rules.lock
  ap_rc=0
  pw_lock_acquire "$ap_lock" || ap_rc=$?
  case $ap_rc in
    0) ;;
    1) die 1 "the rule store is busy (another writer holds $ap_lock); try again" ;;
    *) die 1 "cannot take the rule store lock at $ap_lock" ;;
  esac
  ap_entries=$(read_store) || exit 1
  "$PRECHECK" "$ap_entries"
  ap_n=$(printf '%s\n' "$ap_entries" | awk -F '\t' 'NF { n = substr($1, 3) + 0; if (n > m) m = n } END { print m + 1 }')
  NEW_ID=r-$ap_n
  scratch=$(mktemp "$HOME_DIR/.rules.yaml.XXXXXX") || die 1 "cannot create a scratch file in $HOME_DIR"
  {
    if [ -s "$STORE" ]; then
      cat "$STORE"
    else
      printf '%s\n' "# A mission-control program's rule store, written by scripts/mc-rules.sh." "format: $FORMAT" "rules:"
    fi
    printf '%s\n' "  - id: $NEW_ID" \
      "    text: $(yq "$1")" \
      "    subject: $(yq "$2")" \
      "    source: $(yq "$3")" \
      "    date: $4" \
      "    scope: $5" \
      "    supersedes: $6" \
      "    withdrawn: $7"
  } >"$scratch" || die 1 "cannot write $scratch"
  chmod 600 "$scratch" || die 1 "cannot set the mode of $scratch"
  mv -f "$scratch" "$STORE" || die 1 "cannot replace $STORE"
  scratch=""
  pw_lock_release "$ap_lock" || die 1 "the store is written, but its lock at $ap_lock was not released"
}

no_check() { :; }

# The entry being superseded, found active by check_target under the lock.
target_line() {
  rows "$1" | awk -F '\t' -v id="$TARGET" '$1 == id'
}
check_target() {
  ct_line=$(target_line "$1")
  [ -n "$ct_line" ] || die 1 "no entry $TARGET in the store"
  ct_status=$(printf '%s\n' "$ct_line" | cut -f2)
  [ "$ct_status" = active ] || die 1 "entry $TARGET is $ct_status, not active, so it cannot be superseded"
  OLD_LINE=$ct_line
}

# Option parsing for add and supersede.
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
[ $# -ge 1 ] || usage
program=$1
shift

case $verb in
  add)
    parse_opts "$@"
    [ "$WITHDRAW" -eq 0 ] || usage
    TEXT=$(trim "$TEXT")
    SUBJECT=$(trim "$SUBJECT")
    SOURCE=$(trim "$SOURCE")
    need text "$TEXT"
    need subject "$SUBJECT"
    need source "$SOURCE"
    need date "$DATE_ARG"
    check_value text "$TEXT" 2000
    check_value subject "$SUBJECT" 200
    check_value source "$SOURCE" 200
    check_date "$DATE_ARG"
    SCOPE=${SCOPE:-program}
    check_scope "$SCOPE"
    resolve_home "$program"
    PRECHECK=no_check
    append "$TEXT" "$SUBJECT" "$SOURCE" "$DATE" "$SCOPE" - false
    id=$NEW_ID
    printf '%s\n' "rule $id added ($SCOPE): $SUBJECT: $TEXT"
    printf 'undo\trule-add\t%s\t%s\t%s\t%s\n' "$SUBJECT" "$id" "$SOURCE" \
      "mc-rules.sh supersede $program $id --withdraw --source $(sq "undo of $id") --date today"
    ;;
  supersede)
    [ $# -ge 1 ] || usage
    TARGET=$1
    shift
    check_id "$TARGET"
    parse_opts "$@"
    TEXT=$(trim "$TEXT")
    SUBJECT=$(trim "$SUBJECT")
    SOURCE=$(trim "$SOURCE")
    if [ "$WITHDRAW" -eq 1 ]; then
      [ -z "$TEXT" ] && [ -z "$SUBJECT" ] && [ -z "$SCOPE" ] || die 2 "--withdraw takes no --text, --subject or --scope"
    else
      need text "$TEXT"
      check_value text "$TEXT" 2000
    fi
    [ -z "$SUBJECT" ] || check_value subject "$SUBJECT" 200
    [ -z "$SCOPE" ] || check_scope "$SCOPE"
    need source "$SOURCE"
    need date "$DATE_ARG"
    check_value source "$SOURCE" 200
    check_date "$DATE_ARG"
    resolve_home "$program"
    # Checked again under the lock, where it decides; this read names the
    # inherited subject and scope and the old text for the reversal.
    entries=$(read_store) || exit 1
    check_target "$entries"
    old_subject=$(printf '%s\n' "$OLD_LINE" | cut -f5)
    old_scope=$(printf '%s\n' "$OLD_LINE" | cut -f4)
    old_text=$(printf '%s\n' "$OLD_LINE" | cut -f6)
    SUBJECT=${SUBJECT:-$old_subject}
    SCOPE=${SCOPE:-$old_scope}
    PRECHECK=check_target
    if [ "$WITHDRAW" -eq 1 ]; then
      append "" "$SUBJECT" "$SOURCE" "$DATE" "$SCOPE" "$TARGET" true
      id=$NEW_ID
      printf '%s\n' "rule $id withdraws $TARGET: $SUBJECT"
      printf 'undo\trule-withdraw\t%s\t%s\t%s\t%s\n' "$SUBJECT" "$id" "$SOURCE" \
        "mc-rules.sh add $program --text $(sq "$old_text") --subject $(sq "$SUBJECT") --scope $SCOPE --source $(sq "undo of $id") --date today"
    else
      append "$TEXT" "$SUBJECT" "$SOURCE" "$DATE" "$SCOPE" "$TARGET" false
      id=$NEW_ID
      printf '%s\n' "rule $id supersedes $TARGET ($SCOPE): $SUBJECT: $TEXT"
      printf 'undo\trule-supersede\t%s\t%s\t%s\t%s\n' "$SUBJECT" "$id" "$SOURCE" \
        "mc-rules.sh supersede $program $id --text $(sq "$old_text") --subject $(sq "$old_subject") --scope $old_scope --source $(sq "undo of $id") --date today"
    fi
    ;;
  list | active | conflicts | load)
    [ $# -eq 0 ] || usage
    resolve_home "$program"
    if [ "$verb" = load ]; then
      # A load that cannot be confirmed is the operator's to see.
      if ! out=$(render "$program" "" all); then
        printf 'item\trules-load\tload\tthe active rules of program %s could not be loaded from %s\n' "$program" "$STORE"
        exit 1
      fi
      printf '%s\n' "$out"
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
    label=$(trim "$scopes")
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
    resolve_home "$program"
    for f in "$held" "$durable"; do
      [ -f "$f" ] && [ -r "$f" ] || die 1 "$f is not a readable file"
      bad=$(awk '!/^[ ]*$/ && !/^(item|session) [A-Za-z0-9._:-]+$/ { print NR; exit }' "$f")
      [ -z "$bad" ] || die 1 "$f:$bad: not an 'item <id>' or 'session <handle>' line"
    done
    if ! entries=$(read_store); then
      printf 'item\tself-check\trules\tthe rule store of program %s cannot be read\n' "$program"
      exit 1
    fi
    store_digest=$(digest_of "$(active_rows "$entries")") || exit 1
    failed=0
    if [ "$digest" != "$store_digest" ]; then
      printf 'item\tself-check\trules\tthe loaded rules (digest %s) are not the active set (digest %s); reload them\n' \
        "$(sanitize_printable "$digest")" "$store_digest"
      failed=1
    fi
    for kind in item session; do
      missing=$(awk -v k="$kind" 'NR == FNR { if ($1 == k) h[$2] = 1; next } $1 == k && !($2 in h) { printf "%s%s", sep, $2; sep = " " }' "$held" "$durable")
      [ -z "$missing" ] && continue
      case $kind in
        item) printf 'item\tself-check\titems\topen items missing from the working picture: %s\n' "$missing" ;;
        session) printf 'item\tself-check\tsessions\tlive sessions missing from the working picture: %s\n' "$missing" ;;
      esac
      failed=1
    done
    [ "$failed" -eq 0 ] || exit 1
    printf 'self-check passed: rules %s, %s open items, %s live sessions\n' "$store_digest" \
      "$(grep -c '^item ' "$durable")" "$(grep -c '^session ' "$durable")"
    ;;
  *) usage ;;
esac
