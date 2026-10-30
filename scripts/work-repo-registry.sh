#!/bin/sh
# work-repo-registry.sh — the machine-local map from a marked spec root to the
# work repositories registered against it, so a holder can find their
# checkouts. A cache, never a source of truth: every read rechecks each entry
# against the repository's own spec_root pointer and the root's marker.
#
#   register [--root <dir>]   register this repository's primary checkout
#                             against its resolved spec root, or, with --root,
#                             as a holder against a marked root it contains
#   scan <dir>...             register every git checkout at most three
#                             levels below <dir> (a holder re-runs --root)
#   lookup [--explain] --root <spec-root> [<alias>]
#                             the root's live entries, or <alias>'s checkout;
#                             --explain gives every entry's verdict
#   hook session-start        register; speaks only to warn or refuse
#
# The alias is repository_alias from the repo-tracked layer, else the origin
# remote's name lowercased; another layer's value is ignored with a warning,
# and an empty value is unset.
# A default-root repository is never registered. The registry is
# $CLAUDE_PLUGIN_DATA/work-repos/registry.tsv, rewritten whole under a lock.
#
# Exit: 0 done · 1 refused (an alias, a root, a path) · 2 usage · 3 nothing
#   registered or resolved (no repository here; an alias that resolves to
#   nothing, is stale, or is ambiguous) · 6 the registry is unavailable
set -u
LC_ALL=C
export LC_ALL
unset CDPATH
unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
  GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT
umask 077

HEADER='# planwright work-repository registry v1'
TAB=$(printf '\t')
NL='
'
GRAMMAR='^[a-z0-9][a-z0-9-]*$, at most 64 characters'
CTL=$(printf '\001\002\003\004\005\006\007\010\011\012\013\014\015\016\017\020\021\022\023\024\025\026\027\030\031\032\033\034\035\036\037\177_')
CTL=${CTL%_}

case $0 in
  */*) script_dir=${0%/*} ;;
  *) script_dir=. ;;
esac
script_dir=$(cd -- "$script_dir" && pwd -P) || exit 2
self=$script_dir/work-repo-registry.sh
root_helper=$script_dir/resolve-root.sh
config_get=$script_dir/config-get.sh
if [ ! -r "$script_dir/lock-lib.sh" ]; then
  printf 'work-repo-registry: required helper %s/lock-lib.sh is missing\n' "$script_dir" >&2
  exit 2
fi
# shellcheck source=scripts/lock-lib.sh
. "$script_dir/lock-lib.sh"

clean() { printf '%s' "$1" | tr -d '\000-\037\177'; }
say() { printf 'work-repo-registry: %s\n' "$(clean "$1")" >&2; }
die() {
  say "$2"
  exit "$1"
}
usage() {
  say "usage: work-repo-registry.sh register [--root <dir>] | scan <dir>... | lookup [--explain] --root <spec-root> [<alias>] | hook session-start"
  exit 2
}

scratch=$(mktemp -d "${TMPDIR:-/tmp}/work-repo-registry.XXXXXX") || {
  printf 'work-repo-registry: cannot create a scratch directory\n' >&2
  exit 2
}
we_new=""
cleanup() {
  pw_lock_release_all
  rm -rf "$scratch"
  [ -z "$we_new" ] || rm -f "$we_new"
}
trap cleanup EXIT
trap 'cleanup; exit 129' HUP
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM
scratch_file() { printf '%s/%s\n' "$scratch" "$1"; }

valid_id() {
  case $1 in
    "" | [!a-z0-9]* | *[!a-z0-9-]*) return 1 ;;
  esac
  [ "${#1}" -le 64 ]
}

# plain_path <path>: absolute, free of control bytes and tabs, and with no
# empty, . or .. segment, so it can be compared as a string.
plain_path() {
  case $1 in
    /*) ;;
    *) return 1 ;;
  esac
  case $1 in
    *["$CTL"]*) return 1 ;;
  esac
  case $1/ in
    *//* | */./* | */../*) return 1 ;;
  esac
}

# canon <dir>: the physical path; the sentinel keeps a trailing newline in a
# directory name from being stripped into another directory's name.
canon() {
  case $1 in
    /*) cn=$1 ;;
    *) cn=./$1 ;;
  esac
  cn=$(cd -P -- "$cn" 2>/dev/null && pwd -P && printf x) || return 1
  cn=${cn%x}
  cn=${cn%?}
  case $cn in
    *"$NL"*) return 1 ;;
  esac
  printf '%s\n' "$cn"
}

# in_repo <dir> <args...>: run resolve-root.sh from <dir> as that repository
# sees itself, whatever repository the caller named.
in_repo() {
  ir_dir=$1
  shift
  (cd -- "$ir_dir" 2>/dev/null && env -u PLANWRIGHT_REPO_ROOT /bin/sh "$root_helper" "$@" 2>/dev/null)
}

# default_root <dir>: the spec root <dir>'s repository would resolve with
# spec_root cancelled, so a layer naming the default is told apart from a
# relocated root without composing the default path here.
default_root() {
  dr_conf=$(scratch_file no-spec-root.yml)
  printf 'spec_root: ""\n' >"$dr_conf"
  dr_path=$(cd -- "$1" 2>/dev/null \
    && env -u PLANWRIGHT_REPO_ROOT PLANWRIGHT_LOCAL_CONFIG="$dr_conf" /bin/sh "$root_helper" spec --primary 2>/dev/null) \
    || return 1
  canon "$dr_path" || printf '%s\n' "$dr_path"
}

marker_project() {
  mp_dir=$(/bin/sh "$root_helper" marker "$1" 2>/dev/null) || return 1
  sed -n 's/^project:[[:space:]]*//p' "$mp_dir/planwright-spec-root.yml" | head -1 | sed 's/[[:space:]]*$//'
}

home=""
file=""
# data_home create|read: set home and file; only create makes the directory.
data_home() {
  case ${CLAUDE_PLUGIN_DATA:-} in
    "") die 6 "the registry is unavailable: no plugin data directory (CLAUDE_PLUGIN_DATA) is set" ;;
    /*) ;;
    *) die 6 "the registry is unavailable: CLAUDE_PLUGIN_DATA is not an absolute path" ;;
  esac
  home=${CLAUDE_PLUGIN_DATA%/}/work-repos
  file=$home/registry.tsv
  case $1 in
    create | read) ;;
    *) die 2 "data_home: unknown mode $1" ;;
  esac
  if [ "$1" = create ]; then
    mkdir -p "$home" 2>/dev/null && [ -d "$home" ] && [ ! -L "$home" ] \
      || die 6 "the registry is unavailable: cannot create $home"
  fi
  if [ -L "$file" ] || { [ -e "$file" ] && [ ! -f "$file" ]; }; then
    die 6 "the registry is unavailable: something other than a file sits at $file"
  fi
  if [ -e "$file" ] && [ ! -r "$file" ]; then
    die 6 "the registry is unavailable: $file cannot be read"
  fi
}

# registry_rows <dest>: the registry's data rows; a read error is fatal, so
# an unreadable file is never taken for an empty one.
registry_rows() {
  : >"$1"
  [ -f "$file" ] || return 0
  grep -a -v '^#' "$file" >"$1"
  [ "$?" -le 1 ] || die 6 "the registry is unavailable: $file cannot be read"
}

# split_row <line>: set the r_* fields; fails unless there are exactly five.
split_row() {
  case $1 in
    *"$TAB"*"$TAB"*"$TAB"*"$TAB"*"$TAB"*) return 1 ;;
    *"$TAB"*"$TAB"*"$TAB"*"$TAB"*) ;;
    *) return 1 ;;
  esac
  sr=$1
  r_project=${sr%%"$TAB"*}
  sr=${sr#*"$TAB"}
  r_root=${sr%%"$TAB"*}
  sr=${sr#*"$TAB"}
  r_alias=${sr%%"$TAB"*}
  sr=${sr#*"$TAB"}
  r_kind=${sr%%"$TAB"*}
  r_checkout=${sr#*"$TAB"}
}

# malformed <line>: print why a row cannot be used at all; nothing when its
# shape is sound. Rows are hand-editable, so nothing in one is trusted.
malformed() {
  split_row "$1" || {
    printf 'not five tab-separated fields\n'
    return
  }
  valid_id "$r_project" || {
    printf 'the project is outside the identifier grammar\n'
    return
  }
  valid_id "$r_alias" || {
    printf 'the alias is outside the identifier grammar\n'
    return
  }
  case $r_kind in
    work | holder) ;;
    *)
      printf 'the kind is neither work nor holder\n'
      return
      ;;
  esac
  plain_path "$r_root" || {
    printf 'the root is not a plain absolute path\n'
    return
  }
  plain_path "$r_checkout" || printf 'the checkout is not a plain absolute path\n'
}

# stale <r_*>: print why a well-formed entry is not live; nothing when it is.
stale() {
  [ -d "$r_checkout" ] || {
    printf 'the checkout is gone\n'
    return
  }
  st_top=$(in_repo "$r_checkout" repo --primary) || st_top=""
  [ "$st_top" = "$r_checkout" ] || {
    printf 'the checkout is not a primary checkout\n'
    return
  }
  if [ "$r_kind" = work ]; then
    st_root=$(in_repo "$r_checkout" spec --primary) && st_root=$(canon "$st_root") || st_root=""
    [ "$st_root" = "$r_root" ] || {
      printf "the checkout's spec_root no longer names the root\n"
      return
    }
    [ "$(default_root "$r_checkout")" != "$r_root" ] || {
      printf "the root is the checkout's default spec root\n"
      return
    }
  else
    case $r_root in
      "$r_checkout"/*) ;;
      *)
        printf 'the holder checkout does not contain the root\n'
        return
        ;;
    esac
  fi
  st_project=$(marker_project "$r_root") || {
    printf 'the root carries no valid marker\n'
    return
  }
  [ "$st_project" = "$r_project" ] \
    || printf "the root's marker names project %s, not %s\n" "$(clean "$st_project")" "$r_project"
}

# derive_alias <primary>: the alias rule, refusing when neither source gives
# a name in the identifier grammar.
derive_alias() {
  da_layers=$(scratch_file layers)
  da_rc=0
  PLANWRIGHT_REPO_ROOT=$1 PLANWRIGHT_REPO_ROOT_CHECKED=$1 /bin/sh "$config_get" --layers repository_alias \
    >"$da_layers" || da_rc=$?
  case $da_rc in
    0 | 3) ;;
    4) die 1 "repository_alias cannot be read: the repo-tracked config is malformed" ;;
    *) die 1 "repository_alias cannot be read (config-get exit $da_rc)" ;;
  esac
  da_set=0
  da_value=""
  while IFS= read -r da_line; do
    da_layer=${da_line%%"$TAB"*}
    if [ "$da_layer" = repo-tracked ]; then
      da_value=${da_line#*"$TAB"}
      [ -z "$da_value" ] || da_set=1
    else
      say "WARNING ignoring repository_alias from the $da_layer layer: only the repo-tracked layer sets it, so every clone agrees on the name"
    fi
  done <"$da_layers"
  if [ "$da_set" -eq 1 ]; then
    valid_id "$da_value" \
      || die 1 "refusing the repo-tracked repository_alias: it must match $GRAMMAR"
    printf '%s\n' "$da_value"
    return 0
  fi
  da_url=$(git -C "$1" config --get remote.origin.url 2>/dev/null) || da_url=""
  [ -n "$da_url" ] \
    || die 1 "cannot name $1: it has no origin remote; set repository_alias in its .claude/planwright.yml to a name matching $GRAMMAR"
  da_name=$(printf '%s' "$da_url" | tr '[:upper:]' '[:lower:]')
  da_name=${da_name%/}
  da_name=${da_name%/.git}
  da_name=${da_name%.git}
  da_name=${da_name##*/}
  da_name=${da_name##*:}
  valid_id "$da_name" \
    || die 1 "cannot name $1: its origin remote's name does not match $GRAMMAR; set repository_alias in its .claude/planwright.yml"
  printf '%s\n' "$da_name"
}

# write_entry: replace this checkout's entry for the root (cmd_register's
# fields), keeping every other well-formed row; an unchanged result is not
# rewritten.
write_entry() {
  cd -- "$home" || die 6 "the registry is unavailable: cannot enter $home"
  pw_lock_acquire .registry.lock 400
  case $? in
    0) ;;
    1) die 6 "the registry stayed locked by another writer" ;;
    *) die 6 "the registry is unavailable: cannot lock $file" ;;
  esac
  we_rows=$(scratch_file rows)
  registry_rows "$we_rows"
  we_new=$(mktemp "$home/.registry.XXXXXX") || die 6 "the registry is unavailable: cannot write under $home"
  {
    printf '%s\n' "$HEADER"
    {
      while IFS= read -r we_line; do
        we_why=$(malformed "$we_line")
        if [ -n "$we_why" ]; then
          say "WARNING dropping a malformed registry row ($we_why)"
          continue
        fi
        split_row "$we_line"
        [ "$r_root" = "$root" ] && [ "$r_checkout" = "$primary" ] && continue
        printf '%s\n' "$we_line"
      done <"$we_rows"
      printf '%s\t%s\t%s\t%s\t%s\n' "$project" "$root" "$alias" "$kind" "$primary"
    } | sort -u
  } >"$we_new" || {
    die 6 "the registry is unavailable: cannot write under $home"
  }
  if [ -f "$file" ] && cmp -s "$we_new" "$file"; then
    rm -f "$we_new"
  else
    mv -f "$we_new" "$file" || die 6 "the registry is unavailable: cannot replace $file"
  fi
  we_new=""
  pw_lock_release_all
}

cmd_register() {
  rg_root=""
  while [ "$#" -gt 0 ]; do
    case $1 in
      --root)
        [ "$#" -ge 2 ] && [ -n "$2" ] && [ -z "$rg_root" ] || usage
        rg_root=$2
        shift 2
        ;;
      *) usage ;;
    esac
  done
  primary=$(/bin/sh "$root_helper" repo --primary 2>/dev/null) \
    || die 3 "nothing to register: this is not inside a repository with a primary checkout"
  plain_path "$primary" || die 1 "refusing the checkout $primary: its path is not a plain absolute path"
  if [ -z "$rg_root" ]; then
    rg_rc=0
    rg_line=$(/bin/sh "$root_helper" spec --primary --explain 2>/dev/null) || rg_rc=$?
    case $rg_rc in
      0) ;;
      5) die 1 "refusing to register: the configured spec_root is refused (resolve-root.sh spec --explain says why)" ;;
      *) die 3 "nothing to register: the spec root cannot be read here (resolve-root.sh spec --explain says why)" ;;
    esac
    rg_source=${rg_line%%"$TAB"*}
    root=${rg_line#*"$TAB"}
    root=${root%%"$TAB"*}
    if [ "$rg_source" != default ]; then
      root=$(canon "$root") || die 1 "refusing the spec root $root: it cannot be entered"
    fi
    if [ "$rg_source" = default ] || [ "$(default_root .)" = "$root" ]; then
      printf 'skipped\tthe spec root is the default, so nothing is registered\n'
      exit 0
    fi
    kind=work
  else
    case $rg_root in
      /*) ;;
      *) rg_root=$(pwd -P)/$rg_root ;;
    esac
    [ "$(clean "$rg_root")" = "$rg_root" ] \
      || die 1 "refusing the root '$rg_root': its path carries a control byte or tab"
    root=$(canon "$rg_root") || die 1 "refusing the root '$rg_root': no such directory"
    # A root inside a linked worktree of this same repository names the
    # primary checkout's copy.
    rg_top=$(/bin/sh "$root_helper" repo --checkout 2>/dev/null) || rg_top=""
    rg_own=$(env -u PLANWRIGHT_REPO_ROOT /bin/sh "$root_helper" repo --primary 2>/dev/null) || rg_own=""
    if [ -n "$rg_top" ] && [ "$rg_top" != "$primary" ] && [ "$rg_own" = "$primary" ]; then
      case $root in
        "$rg_top"/*)
          root=$(canon "$primary/${root#"$rg_top"/}") \
            || die 1 "refusing the root: the primary checkout ($primary) holds no copy of it"
          ;;
      esac
    fi
    case $root in
      "$primary"/*) ;;
      *) die 1 "refusing the root $root: this checkout ($primary) does not contain it" ;;
    esac
    kind=holder
  fi
  plain_path "$root" || die 1 "refusing the root '$root': its path is not a plain absolute path"
  if ! project=$(marker_project "$root") || ! valid_id "$project"; then
    die 1 "refusing the root $root: it carries no valid planwright-spec-root.yml marker"
  fi
  alias=$(derive_alias "$primary") || exit 1
  data_home create
  write_entry
  printf 'registered\t%s\t%s\t%s\t%s\n' "$project" "$alias" "$kind" "$primary"
}

cmd_scan() {
  [ "$#" -ge 1 ] || usage
  for sc_dir in "$@"; do
    [ -d "$sc_dir" ] || die 1 "refusing to scan '$sc_dir': no such directory"
  done
  sc_partial=0
  sc_list=$(scratch_file checkouts)
  sc_err=$(scratch_file scan-err)
  for sc_dir in "$@"; do
    sc_dir=$(canon "$sc_dir") || die 1 "refusing to scan a directory that cannot be entered"
    # A name carrying a newline would split into two paths when read back.
    sc_find=0
    find "$sc_dir" -maxdepth 4 \( -name "*$NL*" -prune \) -o \( -name .git \( -type d -o -type f \) -prune -print \) \
      >"$sc_list" 2>"$sc_err" || sc_find=1
    [ "$sc_find" -eq 0 ] || sc_partial=1
    while IFS= read -r sc_git; do
      sc_co=${sc_git%/.git}
      [ "$(clean "$sc_co")" = "$sc_co" ] || {
        say "WARNING skipping a checkout whose path carries a control byte: $sc_co"
        continue
      }
      sc_rc=0
      sc_out=$({ cd -- "$sc_co" && env -u PLANWRIGHT_REPO_ROOT /bin/sh "$self" register; } 2>"$sc_err") || sc_rc=$?
      case $sc_rc in
        0)
          grep '^work-repo-registry: WARNING' "$sc_err" >&2
          case $sc_out in
            skipped*) printf 'skipped\t%s\n' "$sc_co" ;;
            *) printf '%s\n' "$sc_out" ;;
          esac
          ;;
        6)
          cat "$sc_err" >&2
          exit 6
          ;;
        *)
          sc_why=$(tail -1 "$sc_err")
          printf 'refused\t%s\t%s\n' "$sc_co" "$(clean "${sc_why#work-repo-registry: }")"
          ;;
      esac
    done <"$sc_list"
  done
  [ "$sc_partial" -eq 0 ] \
    || die 1 "the scan was incomplete: part of a directory tree could not be read, so entries under it may be missing"
}

cmd_lookup() {
  lk_root=""
  lk_alias=""
  lk_explain=0
  while [ "$#" -gt 0 ]; do
    case $1 in
      --explain) lk_explain=1 ;;
      --root)
        [ "$#" -ge 2 ] && [ -n "$2" ] && [ -z "$lk_root" ] || usage
        lk_root=$2
        shift
        ;;
      -*) usage ;;
      *)
        [ -z "$lk_alias" ] || usage
        valid_id "$1" || {
          say "refusing the alias '$1': it must match $GRAMMAR"
          exit 2
        }
        lk_alias=$1
        ;;
    esac
    shift
  done
  [ -n "$lk_root" ] || usage
  if ! root=$(canon "$lk_root") || ! plain_path "$root"; then
    die 3 "nothing is registered against '$lk_root': it is not a plain directory path"
  fi
  marker_project "$root" >/dev/null \
    || die 3 "nothing is registered against $root: it carries no valid planwright-spec-root.yml marker"
  data_home read
  lk_rows=$(scratch_file lookup-rows)
  registry_rows "$lk_rows"
  lk_live=""
  lk_count=0
  lk_dropped=0
  while IFS= read -r lk_line; do
    if split_row "$lk_line" && [ "$r_root" != "$root" ]; then
      continue
    fi
    lk_why=$(malformed "$lk_line")
    if [ -n "$lk_why" ]; then
      say "WARNING ignoring a malformed registry row ($lk_why)"
      [ "$lk_explain" -eq 0 ] || printf 'refused\t%s\t%s\n' "$(clean "$lk_line" | cut -c1-200)" "$lk_why"
      continue
    fi
    split_row "$lk_line"
    [ "$r_root" = "$root" ] || continue
    [ -z "$lk_alias" ] || [ "$r_alias" = "$lk_alias" ] || continue
    lk_why=$(stale)
    if [ -n "$lk_why" ]; then
      lk_dropped=$((lk_dropped + 1))
      [ "$lk_explain" -eq 0 ] || printf 'dropped\t%s\t%s\t%s\n' "$r_alias" "$r_checkout" "$lk_why"
      continue
    fi
    if [ "$lk_explain" -eq 1 ]; then
      printf 'live\t%s\t%s\t%s\n' "$r_alias" "$r_kind" "$r_checkout"
    elif [ -z "$lk_alias" ]; then
      printf 'entry\t%s\t%s\t%s\n' "$r_alias" "$r_kind" "$r_checkout"
    fi
    lk_count=$((lk_count + 1))
    lk_live=${lk_live:+$lk_live, }$r_checkout
  done <"$lk_rows"
  [ -n "$lk_alias" ] || exit 0
  case $lk_count in
    1)
      [ "$lk_explain" -eq 0 ] || printf 'resolved\t'
      printf '%s\n' "$lk_live"
      ;;
    0)
      if [ "$lk_dropped" -gt 0 ]; then
        die 3 "the alias '$lk_alias' resolves to nothing under $root: every entry for it failed revalidation (lookup --explain says why; register again from the checkout)"
      fi
      die 3 "the alias '$lk_alias' resolves to nothing under $root: no repository is registered with it (run work-repo-registry.sh register in its checkout, or scan)"
      ;;
    *) die 3 "the alias '$lk_alias' is ambiguous under $root: $lk_live are all registered with it; remove one or give one a distinct repository_alias" ;;
  esac
}

# The hook speaks only when a configured layout is refused or warned about:
# its stdout becomes session context, so no line echoes a refused value.
cmd_hook() {
  [ "$#" -eq 1 ] && [ "$1" = session-start ] || usage
  hk_err=$(scratch_file hook-err)
  hk_rc=0
  /bin/sh "$self" register >/dev/null 2>"$hk_err" || hk_rc=$?
  grep '^work-repo-registry: WARNING' "$hk_err" | while IFS= read -r hk_line; do
    printf 'planwright: %s\n' "$(clean "${hk_line#work-repo-registry: WARNING }")"
  done
  case $hk_rc in
    0 | 3) ;;
    *)
      hk_why=$(tail -1 "$hk_err")
      printf 'planwright: this repository is not registered for holder dispatch: %s\n' \
        "$(clean "${hk_why#work-repo-registry: }")"
      ;;
  esac
  exit 0
}

[ "$#" -ge 1 ] || usage
verb=$1
shift
case $verb in
  register) cmd_register "$@" ;;
  scan) cmd_scan "$@" ;;
  lookup) cmd_lookup "$@" ;;
  hook) cmd_hook "$@" ;;
  *) usage ;;
esac
