#!/bin/sh
# venture-task.sh — the mechanical half of the venture-task contract
# (inception Task 10; REQ-D1.1–D1.7, REQ-J1.3 · D-7, D-13).
#
# doctrine/venture-task.md is the normative contract; this script is its
# shadow, small subcommands, each data in, data out:
#
#   contract [<kind>]     the kind-keyed contract table in machine form
#   show <venture> <T-n>  the task's kind, status, linked ids, stakeholder
#   brief <venture> <T-n> the dispatch petition for the backend seam
#   deliver <venture> <T-n>
#                         check findings/T-<n>.md against the task, set the
#                         task delivered, commit the findings (PR-less)
#   accept --by <name> <venture> <T-n>
#                         apply the register updates, set the task accepted,
#                         record the acceptance; one commit or no change
#   reject --by <name> --reason <text> [--drop] <venture> <T-n>
#                         record a rejection; the task returns to running
#                         (or dropped), the registers untouched
#   check <venture> [<commit>]
#                         the per-commit atomicity check (default HEAD)
#   spike-init <venture> <T-n>
#                         make spikes/T-<n>/ with its disposable marker
#   spikes <venture> [<seed-path>...]
#                         flag unmarked spike directories, and any reference
#                         to spikes/ from the given seed files or directories
#   worker-settings       a permission deny-list for outward channels
#
# <venture> is a directory (any argument holding a `/`, or `.`) or a venture
# identifier under ventures_root. Output a caller parses is `key<TAB>value`
# lines; bundle text reaches the terminal only through the echo-discipline
# sanitizer. Nothing here reaches the network or spawns a worker: dispatch
# goes through offload-dispatch.sh like any other petition (REQ-J1.3).
#
# On a git venture deliver, accept, and reject commit exactly the files they
# change, and refuse when one of those files already carries an uncommitted
# edit, so the commit holds nothing else. Without git they write the files and
# report `saved plain`. accept and deliver validate the bundle as it would be
# after the change and refuse an update that adds a validator finding.
#
# Exit: 0 success · 1 refused (a task or findings document off the contract,
#   a wrong status, a validator finding the change would add, a check or
#   spikes finding, a failed commit, which is rolled back) · 2 usage or
#   environment error · 3 the validator refuses to read the bundle (an
#   unsupported or unparseable format-version; passed through).
#
# Environment: PLANWRIGHT_INCEPTION_TODAY (YYYY-MM-DD) pins today's date.
#
# Portable POSIX sh + awk; bash 3.2 / BSD tooling floor (REQ-K1.5).
set -u

LC_ALL=C
export LC_ALL
unset CDPATH
# Every git call names its venture with -C; inherited redirection or config
# would point it at another repository.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
unset GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT GIT_NAMESPACE

self_dir=$(cd "$(dirname "$0")" && pwd -P) || exit 2
VALIDATE="$self_dir/inception-validate.sh"
VENTURE="$self_dir/inception-venture.sh"

if [ ! -f "$self_dir/echo-safety.sh" ] || [ ! -r "$self_dir/echo-safety.sh" ]; then
  printf '%s\n' "venture-task.sh: echo-safety.sh is missing or unreadable (broken install)" >&2
  exit 2
fi
# shellcheck source=scripts/echo-safety.sh
. "$self_dir/echo-safety.sh"

KINDS='spike research analysis demand-signal alignment'
GRADES='synthetic opinion stated-intent costly-signal behavior'
MARKER=DISPOSABLE.md
MAXLEN=300

usage() {
  cat >&2 <<'EOF'
usage: venture-task.sh contract [<kind>]
       venture-task.sh show <venture> <T-n>
       venture-task.sh brief <venture> <T-n>
       venture-task.sh deliver <venture> <T-n>
       venture-task.sh accept --by <name> <venture> <T-n>
       venture-task.sh reject --by <name> --reason <text> [--drop] <venture> <T-n>
       venture-task.sh check <venture> [<commit>]
       venture-task.sh spike-init <venture> <T-n>
       venture-task.sh spikes <venture> [<seed-path>...]
       venture-task.sh worker-settings
EOF
  exit 2
}

die() {
  _code=$1
  shift
  printf 'venture-task: %s\n' "$*" >&2
  exit "$_code"
}

work=
cleanup() { [ -n "$work" ] && rm -rf "$work"; }
trap cleanup EXIT
trap 'exit 2' HUP INT TERM
mkwork() {
  [ -n "$work" ] && return 0
  work=$(mktemp -d "${TMPDIR:-/tmp}/venture-task.XXXXXX") || die 2 "cannot create a scratch directory"
}

today() {
  case ${PLANWRIGHT_INCEPTION_TODAY:-} in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) printf '%s\n' "$PLANWRIGHT_INCEPTION_TODAY" ;;
    '') date +%Y-%m-%d ;;
    *) die 2 "PLANWRIGHT_INCEPTION_TODAY must be YYYY-MM-DD" ;;
  esac
}

# clean_value <value> <label> — refuse a value that cannot sit on one line of a
# register: control characters, empty, or longer than MAXLEN.
clean_value() {
  case $1 in
    *[[:cntrl:]]*) die 1 "$2 carries a control character" ;;
    '') die 2 "$2 is empty" ;;
  esac
  [ "${#1}" -le "$MAXLEN" ] || die 1 "$2 is longer than $MAXLEN characters"
}

check_task_id() {
  printf '%s\n' "$1" | grep -Eq '^T-[1-9][0-9]{0,8}$' ||
    die 2 "task id must be T-<n> (a positive integer): $(sanitize_printable "$1" '?')"
}

# resolve_venture <arg> — set vdir to the venture's canonical directory.
resolve_venture() {
  case $1 in
    -*) die 2 "venture must be a directory or an identifier: $(sanitize_printable "$1" '?')" ;;
    . | */*) _vd=$1 ;;
    *)
      "$VENTURE" check-id "$1" >/dev/null 2>&1 ||
        die 2 "not a venture identifier: $(sanitize_printable "$1" '?')"
      _root=$("$VENTURE" root 2>/dev/null) || die 2 "cannot resolve ventures_root"
      _vd="$_root/$1"
      ;;
  esac
  [ -d "$_vd" ] || die 2 "no venture directory at $(sanitize_printable "$_vd" '?')"
  vdir=$(cd "$_vd" && pwd -P) || die 2 "cannot enter the venture directory"
  [ -f "$vdir/plan.md" ] || die 2 "no plan.md in $(sanitize_printable "$vdir" '?')"
}

version_gate() {
  "$VALIDATE" --version-check "$1" >/dev/null 2>"$work/vc"
  _vc=$?
  case $_vc in
    0) ;;
    3)
      sanitize_printable "$(cat "$work/vc")" >&2
      printf '\n' >&2
      exit 3
      ;;
    *) die 2 "the validator could not check the bundle (exit $_vc)" ;;
  esac
}

# The register-entry reader: one H3 block per id, fields as `- **Name:** value`
# with two-space-indented continuation lines joined by a space. Prints
# `field<TAB>value` for the entry, or nothing when the id holds no block.
ENTRY_AWK='
function flush() { if (fld != "") print fld "\t" val; fld = "" }
/^```/ { fence = !fence }
fence { next }
/^#/ {
  flush()
  if (in_entry) exit
  if ($0 ~ /^### /) { h = $2; if (h == id) in_entry = 1 }
  next
}
!in_entry { next }
/^- \*\*[^*]+:\*\*/ {
  flush()
  fld = $0; sub(/^- \*\*/, "", fld); sub(/:\*\*.*$/, "", fld)
  val = $0; sub(/^- \*\*[^*]+:\*\*[ ]*/, "", val)
  next
}
/^  / && fld != "" { s = $0; sub(/^ +/, "", s); val = val " " s; next }
{ flush() }
END { flush() }
'

entry_fields() { awk -v id="$2" "$ENTRY_AWK" "$1"; }
field() { entry_fields "$1" "$2" | awk -F'\t' -v f="$3" '$1 == f { sub(/^[^\t]*\t/, ""); print; exit }'; }

# set_fields <file> <id> <pairs-file> <out> — rewrite <id>'s named fields to
# the values in <pairs-file> (`field<TAB>value` lines), each bullet and its
# continuation lines replaced by one line.
set_fields() {
  awk -v id="$2" -v pairs="$3" '
    BEGIN { while ((getline l < pairs) > 0) { t = index(l, "\t"); NEW[substr(l, 1, t - 1)] = substr(l, t + 1) } }
    /^```/ { fence = !fence }
    fence { print; next }
    /^#/ { in_entry = ($0 ~ /^### / && $2 == id); skip = 0; print; next }
    in_entry && /^- \*\*[^*]+:\*\*/ {
      f = $0; sub(/^- \*\*/, "", f); sub(/:\*\*.*$/, "", f)
      if (f in NEW) { print "- **" f ":** " NEW[f]; skip = 1; next }
      skip = 0; print; next
    }
    in_entry && skip && /^  / { next }
    { skip = 0; print }
  ' "$1" >"$4"
}

bump_reviewed() {
  _today=$(today)
  awk -v d="$_today" '!done && /^\*\*Last reviewed:\*\*/ { print "**Last reviewed:** " d; done = 1; next } { print }' "$1" >"$1.bump" &&
    mv "$1.bump" "$1"
}

# load_task <T-n> — read the task block into t_* variables; refuse when the
# plan holds no live block for it.
load_task() {
  entry_fields "$vdir/plan.md" "$1" >"$work/task"
  [ -s "$work/task" ] || die 1 "plan.md holds no task $1"
  tf() { awk -F'\t' -v f="$1" '$1 == f { sub(/^[^\t]*\t/, ""); print; exit }' "$work/task"; }
  [ -z "$(tf Superseded-by)" ] || die 1 "$1 is superseded"
  t_kind=$(tf Kind)
  t_status=$(tf Status)
  t_tests=$(tf Tests)
  t_target=$(tf Target)
  t_cap=$(tf Cap)
  case " $KINDS " in
    *" $t_kind "*) ;;
    *) die 1 "$1 kind is not one the format names: $(sanitize_printable "$t_kind" '?')" ;;
  esac
  t_ids=$(printf '%s\n' "$t_tests" | tr ',' '\n' | sed 's/^ *//; s/ *$//' | grep -E '^(A|DEC)-[1-9][0-9]*$')
  [ -n "$t_ids" ] || die 1 "$1 traces to no assumption or decision"
  t_stakeholder=
  if [ "$t_kind" = alignment ]; then
    t_stakeholder=$(stakeholder_for "$t_target")
    [ -n "$t_stakeholder" ] ||
      die 1 "$1 is an alignment task whose target names no stakeholder-map row with a Decides name"
  fi
}

# stakeholder_for <area> — the Decides name for a stakeholder-map row.
stakeholder_for() {
  [ -n "$1" ] || return 0
  awk -v area="$1" '
    function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
    /^## / { in_map = ($0 ~ /^## Stakeholder map[ \t]*$/); next }
    in_map && /^\|/ {
      n = split($0, c, "|")
      if (n < 4) next
      if (trim(c[2]) == area && trim(c[3]) != "" && trim(c[3]) != "none") { print trim(c[3]); exit }
    }
  ' "$vdir/disciplines.md"
}

# --- contract ----------------------------------------------------------------

contract_row() {
  case $1 in
    spike)
      deliv='findings from a throwaway build, code under spikes/T-<n>/'
      perf=agent req=none
      acc='the measured result against the linked thresholds' ;;
    research)
      deliv='findings from sources, each claim citing one'
      perf=agent req=none
      acc='every claim traced to a cited source' ;;
    analysis)
      deliv='findings from data or a model, method stated'
      perf=agent req=none
      acc='the method, then the result against the linked thresholds' ;;
    demand-signal)
      deliv='prepared materials, then the observed signal'
      perf=human req=performer
      acc='the signal as a human observed it, graded on the ladder' ;;
    alignment)
      deliv='prepared materials, then the recorded outcome of the conversation'
      perf=human req=stakeholder
      acc="the stakeholder's recorded position" ;;
    *) return 1 ;;
  esac
  printf 'kind\t%s\ndeliverable\t%s\nperformer\t%s\nrequires\t%s\nacceptance\t%s\n' \
    "$1" "$deliv" "$perf" "$req" "$acc"
}

cmd_contract() {
  if [ $# -eq 1 ]; then
    contract_row "$1" || die 2 "unknown kind: $(sanitize_printable "$1" '?') (one of: $KINDS)"
    return 0
  fi
  [ $# -eq 0 ] || usage
  for k in $KINDS; do contract_row "$k"; done
}

# --- show / brief ------------------------------------------------------------

cmd_show() {
  [ $# -eq 2 ] || usage
  check_task_id "$2"
  resolve_venture "$1"
  mkwork
  version_gate "$vdir"
  load_task "$2"
  printf 'task\t%s\n' "$2"
  printf 'kind\t%s\n' "$t_kind"
  printf 'status\t%s\n' "$(sanitize_printable "$t_status" '?')"
  printf 'tests\t%s\n' "$(printf '%s' "$t_ids" | tr '\n' ',' | sed 's/,/, /g')"
  [ -n "$t_stakeholder" ] && printf 'stakeholder\t%s\n' "$(sanitize_printable "$t_stakeholder" '?')"
  printf 'cap\t%s\n' "$(sanitize_printable "$t_cap" 'none')"
}

cmd_brief() {
  [ $# -eq 2 ] || usage
  check_task_id "$2"
  resolve_venture "$1"
  mkwork
  version_gate "$vdir"
  load_task "$2"
  case $vdir in
    *[[:cntrl:]]*) die 2 "the venture path carries a control character" ;;
  esac
  printf '/planwright:execute-task %s %s\n\n' "$2" "$vdir"
  cat <<'EOF'
A dispatched venture task under the venture-task contract
(doctrine/venture-task.md): work it through delivery, then stop. Acceptance
and rejection are the operator's, in the operator's session. Never contact
anyone outside this session: for demand-signal and alignment tasks, prepare
the materials and stop.
EOF
}

# --- the findings document ---------------------------------------------------

# parse_findings <file> — print the document's parts:
#   hdr<TAB><key><TAB><value>   the bold header lines before the first H2
#   body<TAB><n>                non-blank lines under ## Findings
#   update<TAB><id><TAB><status><TAB><value>
#   bad<TAB><n>                 an unparseable line under ## Register updates
#   section<TAB><name>          every H2, in order
parse_findings() {
  awk '
    function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
    /^```/ { fence = !fence }
    /^## / && !fence { sect = trim(substr($0, 4)); print "section\t" sect; next }
    sect == "" && /^\*\*[^*]+:\*\*/ {
      k = $0; sub(/^\*\*/, "", k); sub(/:\*\*.*$/, "", k)
      v = $0; sub(/^\*\*[^*]+:\*\*[ ]*/, "", v)
      print "hdr\t" k "\t" trim(v); next
    }
    sect == "Findings" && $0 ~ /[^ \t]/ { body++ }
    sect == "Register updates" && $0 ~ /[^ \t]/ {
      line = $0
      if (line !~ /^- (A|DEC)-[1-9][0-9]*: /) { print "bad\t" NR; next }
      sub(/^- /, "", line)
      id = substr(line, 1, index(line, ":") - 1)
      rest = trim(substr(line, index(line, ":") + 1))
      sep = index(rest, " — "); w = 5
      if (!sep) { sep = index(rest, " - "); w = 3 }
      if (!sep) { print "bad\t" NR; next }
      print "update\t" id "\t" trim(substr(rest, 1, sep - 1)) "\t" trim(substr(rest, sep + w))
    }
    END { print "body\t" (body + 0) }
  ' "$1"
}

# check_findings <T-n> — refuse a findings document off the contract; leaves
# the parsed updates in $work/updates (`id<TAB>status<TAB>value`).
check_findings() {
  fdoc="$vdir/findings/$1.md"
  [ ! -L "$vdir/findings" ] || die 1 "findings/ is a symbolic link; refusing to read through it"
  [ ! -L "$fdoc" ] || die 1 "findings/$1.md is a symbolic link; refusing to read through it"
  [ -f "$fdoc" ] || die 1 "no findings document at findings/$1.md"
  parse_findings "$fdoc" >"$work/parsed" || die 2 "cannot read findings/$1.md"
  hv() { awk -F'\t' -v k="$1" '$1 == "hdr" && $2 == k { print $3; exit }' "$work/parsed"; }

  [ "$(hv Task)" = "$1" ] || die 1 "findings/$1.md does not name $1 on its Task line"
  [ "$(hv Kind)" = "$t_kind" ] || die 1 "findings/$1.md names a kind other than the plan's ($t_kind)"
  grep -q '^section	Findings$' "$work/parsed" || die 1 "findings/$1.md has no ## Findings section"
  [ "$(awk -F'\t' '$1 == "body" { print $2 }' "$work/parsed")" -gt 0 ] ||
    die 1 "findings/$1.md has an empty ## Findings section"
  grep -q '^section	Register updates$' "$work/parsed" ||
    die 1 "findings/$1.md has no ## Register updates section"
  ! grep -q '^section	Acceptance$' "$work/parsed" ||
    die 1 "findings/$1.md already carries an acceptance record; only accept writes one"
  if grep -q '^bad	' "$work/parsed"; then
    die 1 "findings/$1.md has a register-update line off the '- <id>: <status> — <value>' form (line $(awk -F'\t' '$1 == "bad" { print $2; exit }' "$work/parsed"))"
  fi

  case $t_kind in
    demand-signal | alignment)
      _pb=$(hv Performed-by)
      [ -n "$_pb" ] ||
        die 1 "a $t_kind task is performed by a human: findings/$1.md needs the Performed-by line naming who ran it"
      clean_value "$_pb" "Performed-by"
      ;;
  esac
  if [ "$t_kind" = alignment ]; then
    [ "$(hv Stakeholder)" = "$t_stakeholder" ] ||
      die 1 "findings/$1.md must name the target's decider on its Stakeholder line: $(sanitize_printable "$t_stakeholder" '?')"
  fi

  awk -F'\t' '$1 == "update" { sub(/^update\t/, ""); print }' "$work/parsed" >"$work/updates"
  [ -s "$work/updates" ] || die 1 "findings/$1.md records no register update; every linked entry needs one"
  _dups=$(cut -f1 "$work/updates" | sort | uniq -d)
  [ -z "$_dups" ] || die 1 "findings/$1.md updates an id more than once: $(sanitize_printable "$_dups" '?')"
  for _id in $t_ids; do
    cut -f1 "$work/updates" | grep -qx "$_id" || die 1 "findings/$1.md records no update for $_id, which $1 tests"
  done
  while IFS='	' read -r _id _st _val; do
    printf '%s\n' "$t_ids" | grep -qx "$_id" || die 1 "findings/$1.md updates $_id, which $1 does not test"
    case $_st$_val in
      *[[:cntrl:]]*) die 1 "the $_id update carries a control character" ;;
    esac
    [ "${#_val}" -le "$MAXLEN" ] || die 1 "the $_id update is longer than $MAXLEN characters"
    case $_id in
      A-*)
        case $_st in
          open | testing | validated | invalidated) ;;
          *) die 1 "the $_id update status must be open, testing, validated, or invalidated" ;;
        esac
        case " $GRADES none " in
          *" $_val "*) ;;
          *) die 1 "the $_id update grade must be a ladder grade or none: $(sanitize_printable "$_val" '?')" ;;
        esac
        case $_st:$_val in
          validated:none | invalidated:none) die 1 "a $_st $_id needs a real evidence grade" ;;
        esac
        [ -n "$(entry_fields "$vdir/assumptions.md" "$_id")" ] || die 1 "assumptions.md holds no $_id"
        ;;
      DEC-*)
        case $_st in
          open | decided | deferred) ;;
          *) die 1 "the $_id update status must be open, decided, or deferred" ;;
        esac
        [ -n "$_val" ] || die 1 "the $_id update needs an outcome"
        [ -n "$(entry_fields "$vdir/decisions.md" "$_id")" ] || die 1 "decisions.md holds no $_id"
        ;;
    esac
  done <"$work/updates"
}

# apply_updates <T-n> <dir> — apply $work/updates to the register copies in
# <dir>; print the names of the files changed.
apply_updates() {
  _changed=
  while IFS='	' read -r _id _st _val; do
    : >"$work/pairs"
    case $_id in
      A-*)
        _f=assumptions.md
        printf 'Status\t%s\n' "$_st" >>"$work/pairs"
        [ "$_val" != none ] && printf 'Evidence\t%s — %s findings\n' "$_val" "$1" >>"$work/pairs"
        _tasks=$(field "$2/$_f" "$_id" Tasks)
        case ", $_tasks, " in
          *", $1, "*) ;;
          ", none, " | ", , ") printf 'Tasks\t%s\n' "$1" >>"$work/pairs" ;;
          *) printf 'Tasks\t%s, %s\n' "$_tasks" "$1" >>"$work/pairs" ;;
        esac
        ;;
      DEC-*)
        _f=decisions.md
        printf 'Status\t%s\nOutcome\t%s\n' "$_st" "$_val" >>"$work/pairs"
        ;;
    esac
    if ! set_fields "$2/$_f" "$_id" "$work/pairs" "$2/$_f.new" || ! mv "$2/$_f.new" "$2/$_f"; then
      die 2 "cannot rewrite $_f"
    fi
    case " $_changed " in
      *" $_f "*) ;;
      *) _changed="$_changed $_f" ;;
    esac
  done <"$work/updates"
  for _f in $_changed; do bump_reviewed "$2/$_f" || die 2 "cannot rewrite $_f"; done
  printf '%s\n' "$_changed"
}

# validated_or_refuse <stage-dir> — refuse when the staged bundle carries a
# validator finding the live one does not.
validated_or_refuse() {
  "$VALIDATE" "$vdir" 2>&1 | grep 'ERROR' | sort >"$work/v.before"
  "$VALIDATE" "$1" 2>&1 | grep 'ERROR' | sort >"$work/v.after"
  _new=$(comm -13 "$work/v.before" "$work/v.after")
  if [ -n "$_new" ]; then
    printf 'venture-task: the change would add bundle findings; nothing was written:\n' >&2
    sanitize_printable "$_new" >&2
    printf '\n' >&2
    exit 1
  fi
}

stage_bundle() {
  mkdir -p "$work/stage" || die 2 "cannot stage the bundle"
  for _f in brief.md disciplines.md assumptions.md decisions.md plan.md; do
    cp "$vdir/$_f" "$work/stage/$_f" || die 2 "cannot stage $_f"
  done
}

is_git() {
  command -v git >/dev/null 2>&1 || return 1
  _top=$(git -C "$vdir" rev-parse --show-toplevel 2>/dev/null) || return 1
  [ "$(cd "$_top" && pwd -P)" = "$vdir" ]
}

# require_clean <file>... — on git, refuse files with uncommitted edits.
require_clean() {
  is_git || return 0
  for _f in "$@"; do
    git -C "$vdir" diff --quiet HEAD -- "$_f" 2>/dev/null ||
      die 1 "$_f has uncommitted changes; save or discard them first, so this commit holds only the task's change"
  done
}

# install_and_commit <message> <path>... — move the staged files into place
# (registers and plan from $work/stage, findings already written) and commit
# exactly <path>...; on a failed commit restore every file and unstage.
install_and_commit() {
  _msg=$1
  shift
  mkdir -p "$work/backup"
  for _p in "$@"; do
    case $_p in
      findings/* | spikes/*) ;;
      *) cp "$vdir/$_p" "$work/backup/$_p" || die 2 "cannot back up $_p" ;;
    esac
  done
  [ -f "$fdoc.pending" ] && cp "$fdoc" "$work/backup/findings.md"
  for _p in "$@"; do
    case $_p in
      findings/* | spikes/*) ;;
      *) mv "$work/stage/$_p" "$vdir/$_p" || { restore "$@"; die 2 "cannot write $_p"; } ;;
    esac
  done
  if [ -f "$fdoc.pending" ]; then
    mv "$fdoc.pending" "$fdoc" || { restore "$@"; die 2 "cannot write the findings document"; }
  fi
  if ! is_git; then
    printf 'saved\tplain\n'
    return 0
  fi
  if ! git -C "$vdir" add -- "$@" || ! git -C "$vdir" commit -q -m "$_msg" -- "$@"; then
    git -C "$vdir" reset -q -- "$@" >/dev/null 2>&1
    restore "$@"
    die 1 "the commit did not go through (see git's message above); every file is as it was"
  fi
  printf 'saved\t%s\n' "$(git -C "$vdir" rev-parse HEAD)"
}

restore() {
  for _p in "$@"; do
    [ -f "$work/backup/$_p" ] && cp "$work/backup/$_p" "$vdir/$_p"
  done
  [ -f "$work/backup/findings.md" ] && cp "$work/backup/findings.md" "$fdoc"
  return 0
}

set_task_status() { # set_task_status <T-n> <status> — on the staged plan
  printf 'Status\t%s\n' "$2" >"$work/tpair"
  if ! set_fields "$work/stage/plan.md" "$1" "$work/tpair" "$work/stage/plan.md.new" ||
    ! mv "$work/stage/plan.md.new" "$work/stage/plan.md"; then
    die 2 "cannot rewrite plan.md"
  fi
  bump_reviewed "$work/stage/plan.md" || die 2 "cannot rewrite plan.md"
}

# --- spikes ------------------------------------------------------------------

# spike_dirs_ok — flag every spikes/ entry that is not a marked directory;
# prints `finding` lines, returns 1 when any.
spike_dirs_ok() {
  [ -e "$vdir/spikes" ] || return 0
  [ ! -L "$vdir/spikes" ] && [ -d "$vdir/spikes" ] || {
    printf 'finding\tspikes/ is not a plain directory\n'
    return 1
  }
  _bad=0
  for _s in "$vdir"/spikes/* "$vdir"/spikes/.[!.]*; do
    [ -e "$_s" ] || [ -L "$_s" ] || continue
    _n=${_s##*/}
    if [ -L "$_s" ] || [ ! -d "$_s" ]; then
      printf 'finding\tspikes/%s is not a spike directory\n' "$(sanitize_printable "$_n" '?')"
      _bad=1
    elif [ -L "$_s/$MARKER" ] || [ ! -f "$_s/$MARKER" ]; then
      printf 'finding\tspikes/%s carries no %s marker\n' "$(sanitize_printable "$_n" '?')" "$MARKER"
      _bad=1
    fi
  done
  return $_bad
}

cmd_spike_init() {
  [ $# -eq 2 ] || usage
  check_task_id "$2"
  resolve_venture "$1"
  for _p in "$vdir/spikes" "$vdir/spikes/$2"; do
    [ ! -L "$_p" ] || die 1 "${_p#"$vdir"/} is a symbolic link; refusing to write through it"
  done
  mkdir -p "$vdir/spikes/$2" || die 2 "cannot create spikes/$2"
  if [ ! -f "$vdir/spikes/$2/$MARKER" ]; then
    [ ! -L "$vdir/spikes/$2/$MARKER" ] || die 1 "spikes/$2/$MARKER is a symbolic link"
    cat >"$vdir/spikes/$2/$MARKER" <<EOF || die 2 "cannot write the marker"
# Disposable: $2 spike

Throwaway code for $2. Its findings graduate into the registers through
findings/$2.md; nothing in this directory graduates, and no seed package
references it.
EOF
  fi
  printf 'spike\tspikes/%s\n' "$2"
}

cmd_spikes() {
  [ $# -ge 1 ] || usage
  resolve_venture "$1"
  shift
  _rc=0
  spike_dirs_ok || _rc=1
  for _seed in "$@"; do
    case $_seed in -*) die 2 "seed path must not begin with '-'" ;; esac
    [ -e "$_seed" ] || die 2 "no seed path at $(sanitize_printable "$_seed" '?')"
    _hits=$(grep -rlE '(^|[^A-Za-z0-9_-])spikes/' -- "$_seed" 2>/dev/null)
    if [ -n "$_hits" ]; then
      printf '%s\n' "$_hits" | while IFS= read -r _h; do
        printf 'finding\t%s references spike code\n' "$(sanitize_printable "$_h" '?')"
      done
      _rc=1
    fi
  done
  [ $_rc -eq 0 ] && printf 'spikes\tclean\n'
  return $_rc
}

# --- deliver / accept / reject -----------------------------------------------

cmd_deliver() {
  [ $# -eq 2 ] || usage
  check_task_id "$2"
  resolve_venture "$1"
  mkwork
  version_gate "$vdir"
  load_task "$2"
  case $t_status in
    planned | running) ;;
    *) die 1 "$2 is $(sanitize_printable "$t_status" '?'); only a planned or running task delivers" ;;
  esac
  check_findings "$2"
  _paths="findings/$2.md plan.md"
  if [ "$t_kind" = spike ] || [ -e "$vdir/spikes/$2" ]; then
    spike_dirs_ok >"$work/spikes" || die 1 "$(sanitize_printable "$(cut -f2 "$work/spikes" | head -n 1)" '?'); run spike-init"
    [ -d "$vdir/spikes/$2" ] && _paths="$_paths spikes/$2"
  fi
  require_clean plan.md

  # The proposal must validate once applied, so a bad update is caught here
  # rather than at acceptance; the dry run writes nothing in the venture.
  stage_bundle
  apply_updates "$2" "$work/stage" >/dev/null
  set_task_status "$2" delivered
  validated_or_refuse "$work/stage"

  rm -rf "$work/stage" && stage_bundle
  set_task_status "$2" delivered
  # shellcheck disable=SC2086 # the path list is fixed above, no globbing input
  install_and_commit "$2 findings delivered for acceptance" $_paths
  printf 'task\t%s\nstatus\tdelivered\n' "$2"
}

parse_by() {
  by=
  reason=
  drop=no
  while [ $# -gt 0 ]; do
    case $1 in
      --by) [ $# -ge 2 ] || usage; by=$2; shift 2 ;;
      --reason) [ $# -ge 2 ] || usage; reason=$2; shift 2 ;;
      --drop) drop=yes; shift ;;
      --) shift; break ;;
      -*) usage ;;
      *) break ;;
    esac
  done
  rest_n=$#
  rest_venture=${1:-}
  rest_task=${2:-}
}

cmd_accept() {
  parse_by "$@"
  [ "$rest_n" -eq 2 ] && [ "$drop" = no ] && [ -z "$reason" ] || usage
  [ -n "$by" ] || die 2 "accept needs --by <name>: the person accepting the findings"
  clean_value "$by" "the acceptor's name"
  check_task_id "$rest_task"
  resolve_venture "$rest_venture"
  mkwork
  version_gate "$vdir"
  load_task "$rest_task"
  [ "$t_status" = delivered ] ||
    die 1 "$rest_task is $(sanitize_printable "$t_status" '?'); only a delivered task is accepted"
  check_findings "$rest_task"

  # A one-way door is reserved to its named deciders.
  while IFS='	' read -r _id _st _val; do
    case $_id:$_st in
      DEC-*:decided)
        [ "$(field "$vdir/decisions.md" "$_id" Door)" = one-way ] || continue
        field "$vdir/decisions.md" "$_id" Deciders | tr ',' '\n' | sed 's/^ *//; s/ *$//' | grep -qxF -- "$by" ||
          die 1 "$_id is a one-way door; only one of its Deciders accepts it"
        ;;
    esac
  done <"$work/updates"

  stage_bundle
  _changed=$(apply_updates "$rest_task" "$work/stage") || exit $?
  set_task_status "$rest_task" accepted
  validated_or_refuse "$work/stage"
  # shellcheck disable=SC2086 # file names from a fixed set
  require_clean plan.md $_changed

  { cat "$fdoc"; printf '\n## Acceptance\n\nAccepted-by: %s\nDate: %s\n' "$by" "$(today)"; } >"$fdoc.pending" ||
    die 2 "cannot write the acceptance record"
  # shellcheck disable=SC2086 # file names from a fixed set
  install_and_commit "$rest_task accepted by $by: registers updated" "findings/$rest_task.md" plan.md $_changed
  printf 'task\t%s\nstatus\taccepted\n' "$rest_task"
}

cmd_reject() {
  parse_by "$@"
  [ "$rest_n" -eq 2 ] || usage
  [ -n "$by" ] || die 2 "reject needs --by <name>: the person rejecting the findings"
  [ -n "$reason" ] || die 2 "reject needs --reason <text>"
  clean_value "$by" "the rejector's name"
  clean_value "$reason" "the reason"
  check_task_id "$rest_task"
  resolve_venture "$rest_venture"
  mkwork
  version_gate "$vdir"
  load_task "$rest_task"
  [ "$t_status" = delivered ] ||
    die 1 "$rest_task is $(sanitize_printable "$t_status" '?'); only a delivered task is rejected"
  fdoc="$vdir/findings/$rest_task.md"
  [ ! -L "$vdir/findings" ] && [ ! -L "$fdoc" ] && [ -f "$fdoc" ] ||
    die 1 "no readable findings document at findings/$rest_task.md"
  _next=running
  [ "$drop" = yes ] && _next=dropped
  require_clean plan.md
  stage_bundle
  set_task_status "$rest_task" "$_next"
  { cat "$fdoc"; printf '\n## Rejection\n\nRejected-by: %s\nDate: %s\nReason: %s\n' "$by" "$(today)" "$reason"; } >"$fdoc.pending" ||
    die 2 "cannot write the rejection record"
  install_and_commit "$rest_task findings rejected by $by" "findings/$rest_task.md" plan.md
  printf 'task\t%s\nstatus\t%s\n' "$rest_task" "$_next"
}

# --- check -------------------------------------------------------------------

# task_table <plan-file> — `T-n<TAB>status<TAB>ids` for every live task.
task_table() {
  [ -s "$1" ] || return 0
  awk '
    function flush() { if (id != "" && !sup) print id "\t" st "\t" tests; id = ""; st = ""; tests = ""; sup = 0 }
    /^```/ { fence = !fence }
    fence { next }
    /^#/ { flush(); if ($0 ~ /^### T-[1-9][0-9]* /) id = $2; next }
    id != "" && /^- \*\*Status:\*\* / { st = $0; sub(/^- \*\*Status:\*\* /, "", st); sub(/[ \t]+$/, "", st) }
    id != "" && /^- \*\*Tests:\*\* / { tests = $0; sub(/^- \*\*Tests:\*\* /, "", tests); gsub(/ /, "", tests) }
    id != "" && /^- \*\*Superseded-by:\*\*/ { sup = 1 }
    END { flush() }
  ' "$1"
}

# entry_table <register-file> — `id<TAB>evidence<TAB>block` per entry, the
# block flattened to one line so two versions compare as strings.
entry_table() {
  [ -s "$1" ] || return 0
  awk '
    function flush() { if (id != "") print id "\t" ev "\t" blk; id = ""; ev = ""; blk = "" }
    /^```/ { fence = !fence }
    fence { if (id != "") blk = blk "\034" $0; next }
    /^#/ { flush(); if ($0 ~ /^### (A|DEC)-[1-9][0-9]* /) id = $2; next }
    id != "" {
      blk = blk "\034" $0
      if ($0 ~ /^- \*\*Evidence:\*\* /) { ev = $0; sub(/^- \*\*Evidence:\*\* /, "", ev) }
    }
    END { flush() }
  ' "$1"
}

cmd_check() {
  [ $# -ge 1 ] && [ $# -le 2 ] || usage
  _rev=${2:-HEAD}
  case $_rev in -*) die 2 "commit must not begin with '-'" ;; esac
  resolve_venture "$1"
  mkwork
  is_git || die 2 "check needs a git venture"
  _c=$(git -C "$vdir" rev-parse --verify --quiet "$_rev^{commit}") ||
    die 2 "no commit $(sanitize_printable "$_rev" '?') in the venture"
  _p=$(git -C "$vdir" rev-parse --verify --quiet "$_c^1") || _p=
  for _f in plan.md assumptions.md decisions.md; do
    git -C "$vdir" show "$_c:$_f" >"$work/new.$_f" 2>/dev/null || : >"$work/new.$_f"
    if [ -n "$_p" ]; then
      git -C "$vdir" show "$_p:$_f" >"$work/old.$_f" 2>/dev/null || : >"$work/old.$_f"
    else
      : >"$work/old.$_f"
    fi
  done
  git -C "$vdir" diff-tree --no-commit-id --name-only -r --root "$_c" >"$work/touched" ||
    die 2 "cannot list the commit's files"
  task_table "$work/old.plan.md" >"$work/t.old"
  task_table "$work/new.plan.md" >"$work/t.new"
  { entry_table "$work/old.assumptions.md"; entry_table "$work/old.decisions.md"; } >"$work/e.old"
  { entry_table "$work/new.assumptions.md"; entry_table "$work/new.decisions.md"; } >"$work/e.new"

  awk -F'\t' -v touched="$work/touched" -v eold="$work/e.old" -v enew="$work/e.new" -v told="$work/t.old" '
    BEGIN {
      while ((getline l < touched) > 0) T[l] = 1
      while ((getline l < told) > 0) { split(l, a, "\t"); OLDST[a[1]] = a[2] }
      while ((getline l < eold) > 0) { split(l, a, "\t"); OLDB[a[1]] = l }
      while ((getline l < enew) > 0) {
        split(l, a, "\t"); NEWB[a[1]] = l; NEWEV[a[1]] = a[2]; order[++n] = a[1]
      }
    }
    {
      id = $1; st = $2; NST[id] = st; TESTS[id] = $3
      if (st == "accepted" && OLDST[id] != "accepted") {
        if (!(("findings/" id ".md") in T))
          print "finding\taccepted-without-findings\t" id " is accepted without its findings in the same change"
        m = split($3, ids, ",")
        for (i = 1; i <= m; i++)
          if (ids[i] != "" && OLDB[ids[i]] == NEWB[ids[i]])
            print "finding\taccepted-without-update\t" id " is accepted without its " ids[i] " register update in the same change"
      }
    }
    END {
      for (i = 1; i <= n; i++) {
        e = order[i]
        if (NEWB[e] == OLDB[e]) continue
        ev = NEWEV[e]
        if (match(ev, /T-[1-9][0-9]* findings/)) {
          t = substr(ev, RSTART, RLENGTH - 9)
          if (NST[t] == "accepted" && OLDST[t] != "accepted") continue
          if (index(OLDB[e], t " findings")) continue
          print "finding\tupdate-before-acceptance\t" e " cites " t " findings without accepting " t " in the same change"
        }
      }
    }
  ' "$work/t.new" >"$work/findings"

  # Findings files added for a task whose status the commit leaves undelivered.
  grep -E '^findings/T-[1-9][0-9]*\.md$' "$work/touched" | while IFS= read -r _ff; do
    _t=${_ff#findings/}
    _t=${_t%.md}
    _s=$(awk -F'\t' -v t="$_t" '$1 == t { print $2; exit }' "$work/t.new")
    case $_s in
      delivered | accepted | running | dropped) ;;
      *) printf 'finding\torphaned-findings\t%s findings are committed while %s is %s\n' "$_t" "$_t" "${_s:-absent}" ;;
    esac
  done >>"$work/findings"

  if [ -s "$work/findings" ]; then
    sort -u "$work/findings" | while IFS= read -r _l; do sanitize_printable "$_l"; printf '\n'; done
    return 1
  fi
  printf 'check\tclean\n'
}

# --- worker settings ---------------------------------------------------------

cmd_worker_settings() {
  [ $# -eq 0 ] || usage
  cat <<'EOF'
{
  "permissions": {
    "deny": [
      "mcp__claude_ai_Gmail__send_message",
      "mcp__claude_ai_Gmail__reply",
      "mcp__claude_ai_Gmail__forward",
      "mcp__claude_ai_Slack",
      "mcp__slack",
      "mcp__claude_ai_Google_Calendar__create_event",
      "mcp__claude_ai_Google_Calendar__update_event",
      "mcp__claude_ai_Google_Calendar__respond_to_event",
      "mcp__claude_ai_Google_Drive__share_file",
      "Bash(gh issue create:*)",
      "Bash(gh issue comment:*)",
      "Bash(gh pr comment:*)",
      "Bash(gh pr review:*)",
      "Bash(mail:*)",
      "Bash(mailx:*)",
      "Bash(sendmail:*)"
    ]
  }
}
EOF
}

[ $# -ge 1 ] || usage
sub=$1
shift
case $sub in
  contract) cmd_contract "$@" ;;
  show) cmd_show "$@" ;;
  brief) cmd_brief "$@" ;;
  deliver) cmd_deliver "$@" ;;
  accept) cmd_accept "$@" ;;
  reject) cmd_reject "$@" ;;
  check) cmd_check "$@" ;;
  spike-init) cmd_spike_init "$@" ;;
  spikes) cmd_spikes "$@" ;;
  worker-settings) cmd_worker_settings "$@" ;;
  *) usage ;;
esac
