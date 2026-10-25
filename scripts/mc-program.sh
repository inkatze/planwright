#!/usr/bin/env bash
# mc-program.sh — read a mission-control program block through the config
# resolver (scripts/config-get.sh, the four overlay layers, last layer wins
# per key).
#
# A program is named in the mission_control_programs list and configured by
# program_<name>_<field> keys, the name's hyphens written as underscores:
#   repositories  [path, ...]   one or more work repositories, absolute or ~/
#   spec_root     path          the spec root, absolute or ~/, in any posture
#   home          path          the program home; default
#                               <mission_control_home_root>/<name>;
#                               never inside a listed repository
#   duties        [id, ...]     enabled duties; default
#                               mission_control_default_duties
#   budget        {key: value}  the program's budget; default empty
#   sources       {class: source:mode, ...}
#                               the state-source map; default
#                               mission_control_default_sources
# A program name is lowercase letters and digits, hyphen separated, starting
# with a letter, at most 64 characters. A budget key is lowercase snake case;
# a source is a kebab name (lowercase letters, digits and hyphens).
#
# The state-source map names, per fact class (work-items, code-state,
# decisions, deadlines, designs), the authoritative source and its mode:
# record, snapshot or cited. A program's own map replaces the default whole,
# and a class the map in force leaves out resolves to cited with no source.
#
# Usage:
#   mc-program.sh list                  configured program names, one per line
#   mc-program.sh get <name> <field>    the resolved field: list members one
#                                       per line, budget as key<TAB>value,
#                                       sources as class<TAB>source<TAB>mode
#                                       for every class in the order above,
#                                       `-` for a class with no source
#   mc-program.sh default <field>       the shipped default a program falls
#                                       back to: home (the home root), duties
#                                       or sources, printed as get prints them
#   mc-program.sh posture <name>        same-repo when the spec root shares a
#                                       program repository's git directory,
#                                       separate-repo when it is in another
#                                       repository, plain when in none; a
#                                       root in a repository while no listed
#                                       repository exists here fails
#   mc-program.sh validate <name>       check every field; each problem on
#                                       stderr as <name>: <field>: <problem>
#
# An invalid value in the adopter or machine-local layer is warned about and
# the next lower layer read instead; one in the repo-tracked layer or the core
# defaults fails, as does a config read that fails. validate fails on an
# invalid value in any layer.
#
# Whether an enabled duty exists is the catalog's question:
# scripts/mc-duties.sh and scripts/check-duties.sh answer it.
#
# Exit codes: 0 resolved; 1 a malformed or missing value, a failed config
# read, or a posture that cannot be told (named on stderr);
# 2 usage, an invalid program name or an unknown field; 3 the program is not
# configured.
#
# Portable bash 3.2 / BSD tooling.
set -u
set -f
LC_ALL=C
export LC_ALL
unset CDPATH

prog=mc-program
script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2
if [ ! -r "$script_dir/echo-safety.sh" ]; then
  printf '%s\n' "$prog: echo-safety.sh is missing or unreadable (broken install)" >&2
  exit 2
fi
# shellcheck source=scripts/echo-safety.sh
. "$script_dir/echo-safety.sh" || exit 2

CLASSES="work-items code-state decisions deadlines designs"
FIELDS="repositories spec_root home duties budget sources"

usage() {
  printf '%s\n' "usage: mc-program.sh list | get <name> <field> | default <field> | posture <name> | validate <name>" >&2
  exit 2
}
problem() { # problem <name> <field> <text>
  printf '%s\n' "$prog: $(sanitize_printable "$1"): $(sanitize_printable "$2"): $(sanitize_printable "$3")" >&2
}

# repeated <lines>: the first line that occurs more than once, if any.
repeated() { printf '%s\n' "$1" | sort | uniq -d | head -n 1; }

# Pattern tests, not grep: grep matches line by line, so a value carrying a
# newline would pass on one good line.
valid_name() {
  [ "${#1}" -le 64 ] || return 1
  case $1 in
    "" | [!a-z]* | *[!a-z0-9-]* | *- | *--*) return 1 ;;
  esac
}
valid_kebab() {
  case $1 in
    "" | [!a-z0-9]* | *[!a-z0-9-]*) return 1 ;;
  esac
}

# split_list <raw>: an inline flow list [a, b] to one member per line.
# Exit 1 not a list, 4 an empty member (a trailing comma is tolerated).
split_list() {
  RAW=$1 awk 'BEGIN {
    r = ENVIRON["RAW"]
    if (r ~ /[[:cntrl:]]/) exit 1
    sub(/^[ ]+/, "", r); sub(/[ ]+$/, "", r)
    if (r !~ /^\[.*\]$/) exit 1
    r = substr(r, 2, length(r) - 2)
    if (r ~ /^[ ]*$/) exit 0
    n = split(r, a, ",")
    for (i = 1; i <= n; i++) {
      m = a[i]; sub(/^[ ]+/, "", m); sub(/[ ]+$/, "", m)
      if (m ~ /^".*"$/) m = substr(m, 2, length(m) - 2)
      if (m == "") { if (i == n) continue; exit 4 }
      out[++k] = m
    }
    for (i = 1; i <= k; i++) print out[i]
  }'
}

# split_map <raw>: an inline flow map {k: v, ...} to key<TAB>value lines,
# split at each entry's first colon. Exit 1 not a map, 2 a malformed entry.
split_map() {
  RAW=$1 awk 'BEGIN {
    r = ENVIRON["RAW"]
    if (r ~ /[[:cntrl:]]/) exit 1
    sub(/^[ ]+/, "", r); sub(/[ ]+$/, "", r)
    if (r !~ /^\{.*\}$/) exit 1
    r = substr(r, 2, length(r) - 2)
    if (r ~ /^[ ]*$/) exit 0
    if (r ~ /[][{}]/) exit 2
    n = split(r, a, ",")
    for (i = 1; i <= n; i++) {
      m = a[i]; sub(/^[ ]+/, "", m); sub(/[ ]+$/, "", m)
      if (m == "") { if (i == n) continue; exit 2 }
      p = index(m, ":")
      if (!p) exit 2
      k = substr(m, 1, p - 1); v = substr(m, p + 1)
      sub(/[ ]+$/, "", k); sub(/^[ ]+/, "", v)
      if (k ~ /^".*"$/) k = substr(k, 2, length(k) - 2)
      if (v ~ /^".*"$/) v = substr(v, 2, length(v) - 2)
      if (k == "" || v == "") exit 2
      out[++c] = k "\t" v
    }
    for (i = 1; i <= c; i++) print out[i]
  }'
}

# expand_path <name> <field> <raw>: an absolute or ~/ path, ~/ expanded. A
# control byte is refused: the paths are printed one per line, and a tab or
# escape would forge a line or reach the terminal.
expand_path() {
  case $3 in
    *[[:cntrl:]]*)
      problem "$1" "$2" "'$3' carries a control character"
      return 1
      ;;
    /*) printf '%s\n' "$3" ;;
    \~/*)
      case ${HOME:-} in
        *[[:cntrl:]]*)
          problem "$1" "$2" "'$3' needs a HOME free of control characters"
          return 1
          ;;
        /*) printf '%s\n' "$HOME/${3#\~/}" ;;
        *)
          problem "$1" "$2" "'$3' needs an absolute HOME"
          return 1
          ;;
      esac
      ;;
    *)
      problem "$1" "$2" "'$3' is not an absolute or ~/ path"
      return 1
      ;;
  esac
}

key_of() { printf 'program_%s_%s' "$(printf '%s' "$1" | tr - _)" "$2"; }

# The placeholder name under which the shipped defaults are read alone.
DEFAULTS="(defaults)"

# read_list <name> <field> <raw>: split a list value or name the problem.
read_list() {
  rl_out=$(split_list "$3")
  case $? in
    0) [ -z "$rl_out" ] || printf '%s\n' "$rl_out" ;;
    4)
      problem "$1" "$2" "an empty member in '$3'"
      return 1
      ;;
    *)
      problem "$1" "$2" "'$3' is not an inline list [a, b]"
      return 1
      ;;
  esac
}
read_map() {
  rm_out=$(split_map "$3")
  case $? in
    0) [ -z "$rm_out" ] || printf '%s\n' "$rm_out" ;;
    2)
      problem "$1" "$2" "a malformed entry in '$3'"
      return 1
      ;;
    *)
      problem "$1" "$2" "'$3' is not an inline map {key: value}"
      return 1
      ;;
  esac
}

# Every read goes through config-get.sh --layers, which prints each layer's
# value, lowest precedence first; the highest valid one wins. An invalid
# value in the adopter or machine-local layer is warned about and the next
# lower layer read instead, the policy the config and catalog readers apply
# to a malformed file; an invalid value in the repo-tracked layer or the core
# defaults fails, and so does a read config-get.sh itself fails. validate
# sets STRICT, failing on any invalid value so a degrade hides nothing.
STRICT=0
scratch_err=$(mktemp) || exit 2
trap 'rm -f "$scratch_err"' EXIT

# layered <name> <field> <key> <parser>: the value of <key>, parsed by
# `<parser> <name> <raw>`. Status 0 printed; 3 no layer sets a valid value;
# 1 a failure, named on stderr.
layered() {
  ly_lines=$(/bin/sh "$script_dir/config-get.sh" --layers "$3" 2>"$scratch_err")
  ly_rc=$?
  cat "$scratch_err" >&2
  case $ly_rc in
    0) ;;
    3) return 3 ;;
    *)
      problem "$1" "$2" "reading $3 failed (config-get.sh exit $ly_rc)"
      return 1
      ;;
  esac
  ly_rev=$(printf '%s\n' "$ly_lines" | awk '{ l[NR] = $0 } END { for (i = NR; i > 0; i--) print l[i] }')
  ly_won=""
  ly_bad=0
  while IFS= read -r ly_line; do
    [ -n "$ly_line" ] || continue
    ly_layer=${ly_line%%	*}
    if ly_out=$("$4" "$1" "${ly_line#*	}" 2>"$scratch_err"); then
      # Strict reads go on to check the layers the winner shadows.
      [ -n "$ly_won" ] || ly_won="ok$ly_out"
      [ "$STRICT" -eq 1 ] || break
      continue
    fi
    if [ "$STRICT" -eq 1 ]; then
      cat "$scratch_err" >&2
      ly_bad=1
      continue
    fi
    [ -z "$ly_won" ] || continue
    case $ly_layer in
      adopter | machine-local)
        problem "$1" "$2" "warning: the $ly_layer value of $3 is invalid ($(head -n 1 "$scratch_err" | sed 's/^[^:]*: //')); degrading to the next lower layer"
        ;;
      *)
        cat "$scratch_err" >&2
        return 1
        ;;
    esac
  done <<EOF
$ly_rev
EOF
  [ "$ly_bad" -eq 0 ] || return 1
  [ -n "$ly_won" ] || return 3
  ly_won=${ly_won#ok}
  [ -z "$ly_won" ] || printf '%s\n' "$ly_won"
}

# with_default <name> <field> <default-key> <parser>: the program's own key,
# else the shipped default; the defaults alone for $DEFAULTS.
with_default() {
  if [ "$1" != "$DEFAULTS" ]; then
    layered "$1" "$2" "$(key_of "$1" "$2")" "$4"
    wd_rc=$?
    [ "$wd_rc" -eq 3 ] || return "$wd_rc"
  fi
  layered "$1" "$2" "$3" "$4"
  wd_rc=$?
  [ "$wd_rc" -eq 3 ] || return "$wd_rc"
  problem "$1" "$2" "$3 is not set (broken install)"
  return 1
}

# required <name> <field> <parser>: a program key with no default.
required() {
  layered "$1" "$2" "$(key_of "$1" "$2")" "$3"
  rq_rc=$?
  [ "$rq_rc" -eq 3 ] || return "$rq_rc"
  problem "$1" "$2" "not set ($(key_of "$1" "$2"))"
  return 1
}

# The parsers: parse_<field> <name> <raw> prints the resolved value, or names
# the problem on stderr and returns 1.
parse_programs() {
  names=$(read_list programs mission_control_programs "$2") || return 1
  while IFS= read -r n; do
    [ -n "$n" ] || continue
    if ! valid_name "$n"; then
      problem programs mission_control_programs "invalid program name '$n'"
      return 1
    fi
  done <<EOF
$names
EOF
  dup=$(repeated "$names")
  if [ -n "$dup" ]; then
    problem programs mission_control_programs "program '$dup' named twice"
    return 1
  fi
  [ -z "$names" ] || printf '%s\n' "$names"
}

parse_repositories() {
  members=$(read_list "$1" repositories "$2") || return 1
  if [ -z "$members" ]; then
    problem "$1" repositories "names no repository"
    return 1
  fi
  dup=$(repeated "$members")
  if [ -n "$dup" ]; then
    problem "$1" repositories "'$dup' named twice"
    return 1
  fi
  rc=0
  while IFS= read -r m; do
    expand_path "$1" repositories "$m" || rc=1
  done <<EOF
$members
EOF
  return $rc
}

parse_spec_root() { expand_path "$1" spec_root "$2"; }
parse_home() { expand_path "$1" home "$2"; }

parse_duties() {
  members=$(read_list "$1" duties "$2") || return 1
  while IFS= read -r m; do
    [ -n "$m" ] || continue
    if ! valid_kebab "$m"; then
      problem "$1" duties "'$m' is not a duty id"
      return 1
    fi
  done <<EOF
$members
EOF
  dup=$(repeated "$members")
  if [ -n "$dup" ]; then
    problem "$1" duties "duty '$dup' enabled twice"
    return 1
  fi
  [ -z "$members" ] || printf '%s\n' "$members"
}

parse_budget() {
  entries=$(read_map "$1" budget "$2") || return 1
  [ -n "$entries" ] || return 0
  if printf '%s\n' "$entries" | cut -f1 | grep -Evq '^[a-z][a-z0-9_]*$'; then
    problem "$1" budget "a key in '$2' is not lowercase snake case"
    return 1
  fi
  dup=$(repeated "$(printf '%s\n' "$entries" | cut -f1)")
  if [ -n "$dup" ]; then
    problem "$1" budget "key '$dup' named twice"
    return 1
  fi
  printf '%s\n' "$entries"
}

parse_sources() {
  entries=$(read_map "$1" sources "$2") || return 1
  rc=0
  while IFS='	' read -r class value; do
    [ -n "$class" ] || continue
    known_class=0
    for c in $CLASSES; do
      [ "$class" != "$c" ] || known_class=1
    done
    if [ "$known_class" -eq 0 ]; then
      problem "$1" sources "unknown fact class '$class' (known: $CLASSES)"
      rc=1
      continue
    fi
    case $value in
      *:*) ;;
      *)
        problem "$1" sources "'$class: $value' is not source:mode"
        rc=1
        continue
        ;;
    esac
    source=${value%:*}
    mode=${value##*:}
    if ! valid_kebab "$source"; then
      problem "$1" sources "source '$source' for '$class' is not a kebab name"
      rc=1
    fi
    case $mode in
      record | snapshot | cited) ;;
      *)
        problem "$1" sources "unknown mode '$mode' for '$class' (known: record snapshot cited)"
        rc=1
        ;;
    esac
  done <<EOF
$entries
EOF
  dup=$(repeated "$(printf '%s\n' "$entries" | cut -f1)")
  if [ -n "$dup" ]; then
    problem "$1" sources "fact class '$dup' named twice"
    rc=1
  fi
  [ "$rc" -eq 0 ] || return 1
  for class in $CLASSES; do
    line=$(printf '%s\n' "$entries" | awk -F '\t' -v c="$class" '$1 == c { print; exit }')
    if [ -n "$line" ]; then
      value=${line#*	}
      printf '%s\t%s\t%s\n' "$class" "${value%:*}" "${value##*:}"
    else
      printf '%s\t-\tcited\n' "$class"
    fi
  done
}

programs() {
  layered programs mission_control_programs mission_control_programs parse_programs
  pg_rc=$?
  [ "$pg_rc" -eq 3 ] && return 0
  return "$pg_rc"
}

field_repositories() { required "$1" repositories parse_repositories; }
field_spec_root() { required "$1" spec_root parse_spec_root; }

home_of() {
  if [ "$1" != "$DEFAULTS" ]; then
    layered "$1" home "$(key_of "$1" home)" parse_home
    fh_rc=$?
    [ "$fh_rc" -eq 3 ] || return "$fh_rc"
  fi
  root=$(with_default "$DEFAULTS" home mission_control_home_root parse_home) || return 1
  if [ "$1" = "$DEFAULTS" ]; then
    printf '%s\n' "$root"
  else
    printf '%s\n' "${root%/}/$1"
  fi
}

# canonical <path>: <path> with its longest existing ancestor resolved
# through symlinks, so a link or a .. segment there cannot hide that one
# path lies inside another.
canonical() {
  cn_head=$1
  while :; do
    case $cn_head in
      */)
        [ "$cn_head" = / ] && break
        cn_head=${cn_head%/}
        ;;
      *) break ;;
    esac
  done
  cn_tail=""
  while [ ! -d "$cn_head" ]; do
    cn_tail="/${cn_head##*/}$cn_tail"
    cn_head=${cn_head%/*}
    [ -n "$cn_head" ] || cn_head=/
  done
  cn_dir=$(cd "$cn_head" 2>/dev/null && pwd -P) || cn_dir=$cn_head
  printf '%s%s\n' "${cn_dir%/}" "$cn_tail"
}

# The home holds company data, so it never sits inside a work repository,
# whichever layers set it and the repositories (REQ-I1.6).
field_home() {
  fh_home=$(home_of "$1") || return 1
  if [ "$1" != "$DEFAULTS" ]; then
    fh_repos=$(field_repositories "$1" 2>/dev/null) || {
      problem "$1" home "cannot be checked against the program's repositories, which do not resolve"
      return 1
    }
    fh_canon=$(canonical "$fh_home")
    while IFS= read -r r; do
      [ -n "$r" ] || continue
      r_canon=$(canonical "$r")
      case $fh_canon/ in
        "${r_canon%/}"/*)
          problem "$1" home "'$fh_home' is inside the work repository '$r'"
          return 1
          ;;
      esac
    done <<EOF
$fh_repos
EOF
  fi
  printf '%s\n' "$fh_home"
}

field_duties() { with_default "$1" duties mission_control_default_duties parse_duties; }

field_budget() {
  layered "$1" budget "$(key_of "$1" budget)" parse_budget
  fb_rc=$?
  [ "$fb_rc" -eq 3 ] && return 0
  return "$fb_rc"
}

field_sources() { with_default "$1" sources mission_control_default_sources parse_sources; }

# common_dir <dir>: the canonical git common directory of <dir>, or nothing.
common_dir() {
  (cd "$1" 2>/dev/null && d=$(env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR -u GIT_INDEX_FILE \
    -u GIT_OBJECT_DIRECTORY -u GIT_CONFIG_PARAMETERS -u GIT_CONFIG_COUNT \
    git rev-parse --git-common-dir 2>/dev/null) && cd "$d" 2>/dev/null && pwd -P)
}

posture() {
  root=$(field_spec_root "$1") || return 1
  if [ ! -d "$root" ]; then
    problem "$1" spec_root "'$root' is not a directory"
    return 1
  fi
  root_git=$(common_dir "$root")
  if [ -z "$root_git" ]; then
    printf '%s\n' plain
    return 0
  fi
  repos=$(field_repositories "$1") || return 1
  present=0
  while IFS= read -r r; do
    [ -d "$r" ] || continue
    present=1
    if [ "$(common_dir "$r")" = "$root_git" ]; then
      printf '%s\n' same-repo
      return 0
    fi
  done <<EOF
$repos
EOF
  if [ "$present" -eq 0 ]; then
    problem "$1" repositories "no listed repository exists on this machine, so the posture is unknown"
    return 1
  fi
  printf '%s\n' separate-repo
}

# require_program <name>: refuse an invalid name, and a name the program list
# does not carry.
require_program() {
  if ! valid_name "$1"; then
    printf '%s\n' "$prog: invalid program name '$(sanitize_printable "$1")'" >&2
    exit 2
  fi
  list=$(programs) || exit 1
  case "
$list
" in
    *"
$1
"*) ;;
    *)
      printf '%s\n' "$prog: program '$1' is not configured (mission_control_programs)" >&2
      exit 3
      ;;
  esac
}

[ $# -ge 1 ] || usage
verb=$1
shift
case $verb in
  list)
    [ $# -eq 0 ] || usage
    programs
    ;;
  get)
    [ $# -eq 2 ] || usage
    case " $FIELDS " in
      *" $2 "*) ;;
      *)
        printf '%s\n' "$prog: unknown field '$(sanitize_printable "$2")' (known: $FIELDS)" >&2
        exit 2
        ;;
    esac
    require_program "$1"
    "field_$2" "$1"
    ;;
  default)
    [ $# -eq 1 ] || usage
    case $1 in
      home | duties | sources) "field_$1" "$DEFAULTS" ;;
      *) usage ;;
    esac
    ;;
  posture)
    [ $# -eq 1 ] || usage
    require_program "$1"
    posture "$1"
    ;;
  validate)
    [ $# -eq 1 ] || usage
    STRICT=1
    require_program "$1"
    status=0
    for f in $FIELDS; do
      ("field_$f" "$1" >/dev/null) || status=1
    done
    exit $status
    ;;
  -h | --help)
    awk 'NR>=2 { if ($0 ~ /^#/) { sub(/^# ?/, ""); print } else exit }' "$0"
    ;;
  *) usage ;;
esac
