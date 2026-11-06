#!/bin/sh
# fleet-scratch.sh — the scratch roots fleet workers get as their TMPDIR, and
# the fleet home's record of which are the fleet's (docs/fleet.md).
#
# Usage: fleet-scratch.sh make <fleet-home> <key> [--fresh]
#        fleet-scratch.sh kind|release <fleet-home> <root>
#        fleet-scratch.sh reclaim <fleet-home> <worktree-key>
#
# A root is <base>/pw-<the first 16 hex digits of sha1("<fleet-home>/<key>")>,
# <base> being $PLANWRIGHT_FLEET_SCRATCH_BASE, else /tmp, never an inherited
# TMPDIR (a launcher inside a worker would nest the root in its own). <key> is
# a worktree's or one session's (scripts/worker-session-record.sh). Only a
# root <fleet-home>/scratch/<key>.tmpdir names is used or removed.
#
# make     create, record, and print <key>'s root; a recorded usable one
#          stands. --fresh first empties it and the earlier layout's root.
# kind     print `worktree` or `session` for a recorded <root>.
# release  remove a recorded <root> and its record.
# reclaim  release a worktree's root and its sessions', and the earlier
#          layout's root for it.
#
# Exit: 0 done; 1 unrecorded, unusable, or left behind; 2 usage.
set -uf
LC_ALL=C
export LC_ALL
unset CDPATH

me=fleet-scratch.sh
usage="usage: $me make <fleet-home> <key> [--fresh] | kind <fleet-home> <root> | release <fleet-home> <root> | reclaim <fleet-home> <worktree-key>"

die() {
  printf '%s: %s\n' "$me" "$1" >&2
  exit "${2:-1}"
}

[ "$#" -ge 3 ] || die "$usage" 2
verb=$1
fresh=0
case $verb in
  make)
    [ "$#" -le 4 ] || die "$usage" 2
    if [ "$#" -eq 4 ]; then
      [ "$4" = --fresh ] || die "$usage" 2
      fresh=1
    fi
    ;;
  kind | release | reclaim) [ "$#" -eq 3 ] || die "$usage" 2 ;;
  *) die "$usage" 2 ;;
esac

case $2 in
  /*) ;;
  *) die "the fleet home is not an absolute path" 2 ;;
esac
home=$(cd -P -- "$2" 2>/dev/null && pwd -P) || die "the fleet home does not resolve"
smap=$home/scratch

# key_ok <key>: a worktree's key or a session's.
key_ok() {
  case $1 in
    *[!0-9a-f-]*) return 1 ;;
  esac
  case ${#1} in
    40) case $1 in *-*) return 1 ;; esac ;;
    81)
      case $1 in ????????????????????????????????????????-*) ;; *) return 1 ;; esac
      case ${1#*-} in *-*) return 1 ;; esac
      ;;
    *) return 1 ;;
  esac
}

uid=$(id -u) || die "cannot read this user's id"

# root_ok <path>: a root of this script's shape that may be used or removed.
root_ok() {
  case $1 in
    /*/pw-*) ;;
    *) return 1 ;;
  esac
  case $1 in
    *[[:cntrl:]]*) return 1 ;;
  esac
  ro_n=${1##*/}
  ro_n=${ro_n#pw-}
  case $ro_n in
    *[!0-9a-f]*) return 1 ;;
  esac
  [ "${#ro_n}" -eq 16 ] || return 1
  [ -d "$1" ] && [ ! -L "$1" ] || return 1
  [ "$(find "$1" -maxdepth 0 -user "$uid" 2>/dev/null)" = "$1" ] || return 1
  # Every component, not just the last: the canonical path is what the
  # record holds, so a linked parent would spell another.
  [ "$(cd -P -- "${1%/*}" 2>/dev/null && pwd -P)" = "${1%/*}" ]
}

# wipe <dir>: remove a directory tree, opening the directories the worker
# left without write permission first; zero when it is gone.
wipe() {
  if [ -d "$1" ] && [ ! -L "$1" ]; then
    find "$1" -type d ! -perm -700 -exec chmod u+rwx {} \; 2>/dev/null || :
    rm -rf -- "$1" 2>/dev/null || :
  fi
  [ ! -e "$1" ] && [ ! -L "$1" ]
}

# record_read <record-file>: print the root a record names.
record_read() {
  [ -f "$1" ] && [ ! -L "$1" ] || return 1
  rr_line=''
  IFS= read -r rr_line <"$1" 2>/dev/null || [ -n "$rr_line" ] || return 1
  printf '%s\n' "$rr_line"
}

# record_of <root>: print the record file naming <root>.
record_of() {
  [ -d "$smap" ] && [ ! -L "$smap" ] || return 1
  set +f
  for ro_f in "$smap"/*.tmpdir; do
    ro_k=${ro_f##*/}
    key_ok "${ro_k%.tmpdir}" || continue
    [ "$(record_read "$ro_f")" = "$1" ] || continue
    set -f
    printf '%s\n' "$ro_f"
    return 0
  done
  set -f
  return 1
}

# release_record <record-file>: remove the root it names, then the record. A
# root that is gone already leaves only the record to remove; one of another
# shape is refused, record kept.
release_record() {
  rl_root=$(record_read "$1") || return 1
  if [ -e "$rl_root" ] || [ -L "$rl_root" ]; then
    root_ok "$rl_root" || return 1
    wipe "$rl_root" || return 1
  fi
  rm -f -- "$1"
}

case $verb in
  make)
    key=$3
    key_ok "$key" || die "the key is not a worktree's or a session's" 2
    base=${PLANWRIGHT_FLEET_SCRATCH_BASE:-/tmp}
    case $base in
      /*) ;;
      *) die "the scratch base is not an absolute path" ;;
    esac
    base=$(cd -P -- "$base" 2>/dev/null && pwd -P) || die "the scratch base does not resolve"
    umask 077
    [ ! -L "$smap" ] || exit 1
    mkdir -p -- "$smap" 2>/dev/null && [ -d "$smap" ] && [ ! -L "$smap" ] || exit 1
    digest=$(printf '%s/%s' "$home" "$key" | git hash-object --stdin 2>/dev/null) || exit 1
    root=$base/pw-$(printf '%s' "$digest" | cut -c1-16)
    rec=$smap/$key.tmpdir
    if [ "$fresh" = 1 ]; then
      if [ -e "$rec" ] || [ -L "$rec" ]; then
        release_record "$rec" || exit 1
      fi
      legacy=$smap/$(printf '%s' "$key" | tr - /)
      [ -L "$legacy" ] || wipe "$legacy" || exit 1
      if [ -e "$root" ] || [ -L "$root" ]; then
        root_ok "$root" && wipe "$root" || exit 1
      fi
    fi
    # The recorded root stands while it is usable, whatever base this
    # launch would derive.
    if [ "$fresh" = 0 ] && kept=$(record_read "$rec") && root_ok "$kept"; then
      root=$kept
    fi
    # An existing root is kept; the checks below decide either way.
    mkdir -- "$root" 2>/dev/null || : # not-a-lock: creating the scratch root, whose checks follow
    root_ok "$root" || exit 1
    # BSD chmod reads a `--` after the mode as a file; the path is absolute.
    chmod 700 "$root" 2>/dev/null || exit 1
    case $root/ in
      "$home"/*) exit 1 ;;
    esac
    tmp=$(mktemp "$smap/.$key.XXXXXX") || exit 1
    if ! printf '%s\n' "$root" >"$tmp" || ! mv -f -- "$tmp" "$rec"; then
      rm -f -- "$tmp"
      exit 1
    fi
    printf '%s\n' "$root"
    ;;
  kind)
    rec=$(record_of "$3") || exit 1
    k=${rec##*/}
    case ${k%.tmpdir} in
      *-*) echo session ;;
      *) echo worktree ;;
    esac
    ;;
  release)
    rec=$(record_of "$3") || exit 1
    release_record "$rec"
    ;;
  reclaim)
    wkey=$3
    case $wkey in
      *-*) die "the key is not a worktree's" 2 ;;
    esac
    key_ok "$wkey" || die "the key is not a worktree's" 2
    rc=0
    if [ -d "$smap" ] && [ ! -L "$smap" ]; then
      set +f
      for f in "$smap/$wkey.tmpdir" "$smap/$wkey"-*.tmpdir; do
        set -f
        [ -e "$f" ] || [ -L "$f" ] || continue
        k=${f##*/}
        key_ok "${k%.tmpdir}" || continue
        release_record "$f" || rc=1
      done
      set -f
      [ -L "$smap/$wkey" ] || wipe "$smap/$wkey" || rc=1
    fi
    exit "$rc"
    ;;
esac
