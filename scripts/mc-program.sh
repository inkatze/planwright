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
#                               <mission_control_home_root>/<name>
#   duties        [id, ...]     enabled duties; default
#                               mission_control_default_duties
#   budget        {key: value}  the program's budget; default empty
#   sources       {class: source:mode, ...}
#                               the state-source map; default
#                               mission_control_default_sources
# A program name is lowercase letters and digits, hyphen separated, at most
# 64 characters.
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
#                                       repository, plain when in none
#   mc-program.sh validate <name>       check every field; each problem on
#                                       stderr as <name>: <field>: <problem>
#
# Whether an enabled duty exists is the catalog's question:
# scripts/mc-duties.sh and scripts/check-duties.sh answer it.
#
# Exit codes: 0 resolved; 1 a malformed or missing value (named on stderr);
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

# cfg <key>: the merged value; exit 3 when no layer sets it.
cfg() { /bin/sh "$script_dir/config-get.sh" "$1"; }

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

# pcfg <name> <field>: a program key, or unset (exit 3) for the defaults.
DEFAULTS="(defaults)"
pcfg() {
  [ "$1" != "$DEFAULTS" ] || return 3
  cfg "$(key_of "$1" "$2")"
}

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

programs() {
  if ! raw=$(cfg mission_control_programs); then
    return 0
  fi
  names=$(read_list programs mission_control_programs "$raw") || return 1
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

field_repositories() {
  if ! raw=$(cfg "$(key_of "$1" repositories)"); then
    problem "$1" repositories "not set ($(key_of "$1" repositories))"
    return 1
  fi
  members=$(read_list "$1" repositories "$raw") || return 1
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

field_spec_root() {
  if ! raw=$(cfg "$(key_of "$1" spec_root)"); then
    problem "$1" spec_root "not set ($(key_of "$1" spec_root))"
    return 1
  fi
  expand_path "$1" spec_root "$raw"
}

field_home() {
  if raw=$(pcfg "$1" home); then
    expand_path "$1" home "$raw"
    return
  fi
  if ! raw=$(cfg mission_control_home_root); then
    problem "$1" home "mission_control_home_root is not set (broken install)"
    return 1
  fi
  root=$(expand_path "$1" home "$raw") || return 1
  if [ "$1" = "$DEFAULTS" ]; then
    printf '%s\n' "$root"
  else
    printf '%s\n' "${root%/}/$1"
  fi
}

field_duties() {
  if ! raw=$(pcfg "$1" duties); then
    if ! raw=$(cfg mission_control_default_duties); then
      problem "$1" duties "mission_control_default_duties is not set (broken install)"
      return 1
    fi
  fi
  members=$(read_list "$1" duties "$raw") || return 1
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

field_budget() {
  raw=$(cfg "$(key_of "$1" budget)") || raw="{}"
  entries=$(read_map "$1" budget "$raw") || return 1
  [ -n "$entries" ] || return 0
  if printf '%s\n' "$entries" | cut -f1 | grep -Evq '^[a-z][a-z0-9_]*$'; then
    problem "$1" budget "a key in '$raw' is not lowercase snake case"
    return 1
  fi
  dup=$(repeated "$(printf '%s\n' "$entries" | cut -f1)")
  if [ -n "$dup" ]; then
    problem "$1" budget "key '$dup' named twice"
    return 1
  fi
  printf '%s\n' "$entries"
}

field_sources() {
  if ! raw=$(pcfg "$1" sources); then
    if ! raw=$(cfg mission_control_default_sources); then
      problem "$1" sources "mission_control_default_sources is not set (broken install)"
      return 1
    fi
  fi
  entries=$(read_map "$1" sources "$raw") || return 1
  rc=0
  seen=" "
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
    case $seen in
      *" $class "*)
        problem "$1" sources "fact class '$class' named twice"
        rc=1
        continue
        ;;
    esac
    seen="$seen$class "
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
