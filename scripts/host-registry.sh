#!/bin/sh
# host-registry.sh — the machine-local registry of remote hosts the remote
# worker rung may use, and its validation.
#
#   validate [--for workers|compute] [--host <alias>]
#                       check the registry; --for compute also requires each
#                       checked host to record a compute credential stance
#   get <alias> <field> print one field's effective value (defaults applied)
#   list                print every host alias
#
# The registry path is the machine-local config key remote_hosts_file, read
# through config-get.sh. It is refused when any tracked layer sets that key or
# git tracks the file, so no alias, path or account label is ever committed.
# One host per line (blank lines and # comments ignored):
#   host <alias> account=<label> ceiling=<n> [shared=yes|no] [idle=<min>]
#        [hold=yes|no] [grace=<min>] [compute=login-free|accepted]
#        [clone.<repo-alias>=<absolute path>]...
# The alias is an SSH alias: letters, digits, dot, underscore and dash, no
# leading dash. A host with no compute stance still takes workers; a compute
# run needs compute=login-free (an account holding no hosting-remote or model
# login) or compute=accepted (the operator accepts that the code can read the
# logins the account holds).
#
# Exit: 0 ok · 1 refused (the field is named) · 2 usage · 3 no registry
# configured or readable, or the host or field is not set
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

case $0 in
  */*) script_dir=${0%/*} ;;
  *) script_dir=. ;;
esac
script_dir=$(cd -- "$script_dir" && pwd -P) || exit 2
config_get=$script_dir/config-get.sh

DEFAULT_GRACE=30
DEFAULT_IDLE=10

say() { printf 'host-registry: %s\n' "$(printf '%s' "$1" | tr -d '\000-\037\177')" >&2; }
die() {
  say "$2"
  exit "$1"
}
usage() {
  say "usage: host-registry.sh validate [--for workers|compute] [--host <alias>] | get <alias> <field> | list"
  exit 2
}

valid_label() {
  case $1 in
    "" | [!A-Za-z0-9]* | *[!A-Za-z0-9._-]*) return 1 ;;
  esac
  [ "${#1}" -le 64 ]
}
valid_repo_alias() {
  case $1 in
    "" | [!a-z0-9]* | *[!a-z0-9-]*) return 1 ;;
  esac
  [ "${#1}" -le 64 ]
}
valid_uint() {
  case $1 in
    "" | *[!0-9]*) return 1 ;;
  esac
  [ "${#1}" -le 6 ]
}
valid_yesno() { [ "$1" = yes ] || [ "$1" = no ]; }
valid_path() {
  case $1 in
    /*) ;;
    *) return 1 ;;
  esac
  case $1 in
    *[!A-Za-z0-9._/-]*) return 1 ;;
  esac
  case $1/ in
    *//* | */./* | */../*) return 1 ;;
  esac
}

# registry_file: print the registry path, or exit refusing a tracked source.
registry_file() {
  rf_lines=$(/bin/sh "$config_get" --layers remote_hosts_file)
  rf_rc=$?
  [ "$rf_rc" -eq 3 ] && die 3 "no registry configured (remote_hosts_file is not set in machine-local config)"
  [ "$rf_rc" -eq 0 ] || die 1 "remote_hosts_file: the config could not be read (exit $rf_rc)"
  rf_value=
  while IFS= read -r rf_line; do
    rf_layer=${rf_line%%	*}
    [ "$rf_layer" = machine-local ] \
      || die 1 "remote_hosts_file: set in the $rf_layer config layer; the registry is machine-local only"
    rf_value=${rf_line#*	}
  done <<EOF
$rf_lines
EOF
  [ -n "$rf_value" ] || die 3 "no registry configured (remote_hosts_file is empty)"
  case $rf_value in
    /*) ;;
    *) die 1 "remote_hosts_file: must be an absolute path" ;;
  esac
  [ -f "$rf_value" ] && [ -r "$rf_value" ] || die 3 "registry file is not readable"
  rf_dir=${rf_value%/*}
  [ -n "$rf_dir" ] || rf_dir=/
  git -C "$rf_dir" ls-files --error-unmatch -- "${rf_value##*/}" >/dev/null 2>&1
  case $? in
    0) die 1 "remote_hosts_file: the registry file is tracked by git; keep it machine-local" ;;
    1) ;;
    *)
      if git -C "$rf_dir" rev-parse --git-dir >/dev/null 2>&1; then
        die 1 "remote_hosts_file: could not tell whether git tracks the registry file"
      fi
      ;;
  esac
  printf '%s\n' "$rf_value"
}

# check_field <alias> <name> <value>: refuse a bad value naming the field.
check_field() {
  cf_a=$1
  cf_n=$2
  cf_v=$3
  case $cf_n in
    account) valid_label "$cf_v" || die 1 "host $cf_a: account: not a valid label" ;;
    ceiling)
      valid_uint "$cf_v" && [ "$cf_v" -ge 1 ] || die 1 "host $cf_a: ceiling: not a positive integer"
      ;;
    idle | grace) valid_uint "$cf_v" || die 1 "host $cf_a: $cf_n: not a whole number of minutes" ;;
    shared | hold) valid_yesno "$cf_v" || die 1 "host $cf_a: $cf_n: must be yes or no" ;;
    compute)
      case $cf_v in
        login-free | accepted) ;;
        *) die 1 "host $cf_a: compute: must be login-free or accepted" ;;
      esac
      ;;
    clone.*)
      valid_repo_alias "${cf_n#clone.}" || die 1 "host $cf_a: $cf_n: not a valid repository alias"
      valid_path "$cf_v" || die 1 "host $cf_a: $cf_n: must be a plain absolute path"
      ;;
    *) die 1 "host $cf_a: $cf_n: unknown field" ;;
  esac
}

# load <file>: validate every line, then leave one record per host in $hosts,
# newline-separated "alias<TAB>k=v k=v".
hosts=
load() {
  ld_file=$1
  ld_seen=" "
  ld_n=0
  while IFS= read -r ld_line || [ -n "$ld_line" ]; do
    ld_n=$((ld_n + 1))
    case $ld_line in
      "" | "#"*) continue ;;
    esac
    case $ld_line in
      *[!\ -~]*) die 1 "line $ld_n: control or non-ASCII bytes" ;;
    esac
    set -f
    # shellcheck disable=SC2086
    set -- $ld_line
    set +f
    [ $# -ge 1 ] || continue
    case $1 in
      "#"*) continue ;;
    esac
    [ "$1" = host ] || die 1 "line $ld_n: entry must start with 'host'"
    [ $# -ge 2 ] || die 1 "line $ld_n: alias: missing"
    ld_alias=$2
    shift 2
    case $ld_alias in
      -*) die 1 "line $ld_n: alias: leading dash" ;;
    esac
    valid_label "$ld_alias" || die 1 "line $ld_n: alias: not a valid SSH alias"
    case $ld_seen in
      *" $ld_alias "*) die 1 "host $ld_alias: alias: listed twice" ;;
    esac
    ld_seen="$ld_seen$ld_alias "
    ld_fields=
    for ld_kv in "$@"; do
      case $ld_kv in
        *=*) ;;
        *) die 1 "host $ld_alias: field: '$ld_kv' is not name=value" ;;
      esac
      check_field "$ld_alias" "${ld_kv%%=*}" "${ld_kv#*=}"
      case $ld_fields in
        *" ${ld_kv%%=*}="*) die 1 "host $ld_alias: ${ld_kv%%=*}: given twice" ;;
      esac
      ld_fields="$ld_fields $ld_kv"
    done
    case $ld_fields in
      *" account="*) ;;
      *) die 1 "host $ld_alias: account: required" ;;
    esac
    case $ld_fields in
      *" ceiling="*) ;;
      *) die 1 "host $ld_alias: ceiling: required" ;;
    esac
    hosts="$hosts$ld_alias	$ld_fields
"
  done <"$ld_file"
}

# field_of <alias> <name>: the effective value, defaults applied; 1 if unset.
field_of() {
  fo_rec=$(printf '%s' "$hosts" | while IFS= read -r fo_l; do
    [ "${fo_l%%	*}" = "$1" ] && printf '%s\n' "${fo_l#*	}"
  done)
  [ -n "$fo_rec" ] || return 2
  for fo_kv in $fo_rec; do
    if [ "${fo_kv%%=*}" = "$2" ]; then
      printf '%s\n' "${fo_kv#*=}"
      return 0
    fi
  done
  case $2 in
    shared | hold) echo no ;;
    grace) printf '%s\n' "$DEFAULT_GRACE" ;;
    idle) printf '%s\n' "$DEFAULT_IDLE" ;;
    *) return 1 ;;
  esac
}

[ $# -ge 1 ] || usage
verb=$1
shift
case $verb in
  validate)
    for_what=workers
    only_host=
    while [ $# -gt 0 ]; do
      case $1 in
        --for)
          [ $# -ge 2 ] || usage
          case $2 in
            workers | compute) for_what=$2 ;;
            *) usage ;;
          esac
          shift 2
          ;;
        --host)
          [ $# -ge 2 ] || usage
          valid_label "$2" || die 1 "alias: $2 is not a valid SSH alias"
          only_host=$2
          shift 2
          ;;
        *) usage ;;
      esac
    done
    reg=$(registry_file) || exit $?
    load "$reg"
    if [ -n "$only_host" ]; then
      case $hosts in
        "$only_host	"* | *"
$only_host	"*) ;;
        *) die 3 "host $only_host: not in the registry" ;;
      esac
    fi
    if [ "$for_what" = compute ]; then
      while IFS= read -r v_l; do
        [ -n "$v_l" ] || continue
        v_alias=${v_l%%	*}
        [ -z "$only_host" ] || [ "$only_host" = "$v_alias" ] || continue
        case $v_l in
          *" compute="*) ;;
          *) die 1 "host $v_alias: compute: no credential stance recorded (login-free or accepted); the host takes workers only" ;;
        esac
      done <<EOF
$hosts
EOF
    fi
    ;;
  get)
    [ $# -eq 2 ] || usage
    case $2 in
      "" | *[!a-z0-9._-]*) usage ;;
    esac
    valid_label "$1" || usage
    reg=$(registry_file) || exit $?
    load "$reg"
    field_of "$1" "$2"
    case $? in
      0) ;;
      *) exit 3 ;;
    esac
    ;;
  list)
    [ $# -eq 0 ] || usage
    reg=$(registry_file) || exit $?
    load "$reg"
    printf '%s' "$hosts" | while IFS= read -r l_l; do
      [ -n "$l_l" ] && printf '%s\n' "${l_l%%	*}"
    done
    ;;
  *) usage ;;
esac
