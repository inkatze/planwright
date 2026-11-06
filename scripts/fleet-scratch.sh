#!/bin/sh
# fleet-scratch.sh — the scratch roots fleet workers get as their TMPDIR, and
# the fleet home's record of which are the fleet's (docs/fleet.md).
#
# Usage: fleet-scratch.sh make <fleet-home> <key> [--fresh]
#        fleet-scratch.sh release <fleet-home> <root>
#        fleet-scratch.sh reclaim <fleet-home> <worktree-key>
#
# A root is <base>/<the first 16 hex digits of git hash-object of
# "<fleet-home>/<key>", in the repository's object format>. <base> is
# $PLANWRIGHT_FLEET_SCRATCH_BASE, else /tmp/planwright-<uid>, made when
# absent; never an inherited TMPDIR (a launcher inside a worker would nest the
# root in its own). It must be this user's and closed to others, as tmux's
# socket directory is, so no one else can see or recreate a root inside it.
# <key> is a worktree's or a session's (scripts/worker-session-record.sh);
# <fleet-home>/scratch/<key>.tmpdir records its root, and release acts on no
# root a record does not name.
#
# make     create, record, and print <key>'s root; a usable recorded one stands
#          (--fresh removes it, the derived one and the earlier layout's first).
# release  remove a recorded <root> and its record; a root already gone is done.
# reclaim  release a worktree's root and its sessions', and remove its
#          earlier-layout root and a killed make's temporary records.
#
# Exit: 0 done; 1 unrecorded, unusable, or left behind; 2 usage.
set -uf
LC_ALL=C
export LC_ALL
unset CDPATH

me=fleet-scratch.sh
usage="usage: $me make <fleet-home> <key> [--fresh] | release <fleet-home> <root> | reclaim <fleet-home> <worktree-key>"

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
  release | reclaim) [ "$#" -eq 3 ] || die "$usage" 2 ;;
  *) die "$usage" 2 ;;
esac

# Before the substitution below, which would strip a trailing newline.
case $2 in
  *[[:cntrl:]]*) die "the fleet home holds a control character" 2 ;;
  /*) ;;
  *) die "the fleet home is not an absolute path" 2 ;;
esac
home=$(cd -P -- "$2" 2>/dev/null && pwd -P) || die "the fleet home does not resolve"
smap=$home/scratch

# key_ok <key>: a worktree's key or a session's.
key_ok() {
  ko_w=${1%%-*}
  ko_s=${1#"$ko_w"}
  ko_s=${ko_s#-}
  [ -n "$ko_s" ] || [ "$1" = "$ko_w" ] || return 1
  hash_ok "$ko_w" && { [ -z "$ko_s" ] || hash_ok "$ko_s"; }
}

# hash_ok <word>: an object name, SHA-1 or SHA-256 (a repository's own
# format decides what `git hash-object` prints).
hash_ok() {
  case $1 in
    '' | *[!0-9a-f]*) return 1 ;;
  esac
  [ "${#1}" -eq 40 ] || [ "${#1}" -eq 64 ]
}

uid=$(id -u) || die "cannot read this user's id"
nl='
'

# owned_private <dir>: a directory, reached through no symlink, that this
# user owns and no one else may read, write, or enter.
owned_private() {
  [ -d "$1" ] && [ ! -L "$1" ] || return 1
  [ "$(find "$1" -maxdepth 0 -user "$uid" ! -perm -040 ! -perm -020 ! -perm -010 \
    ! -perm -004 ! -perm -002 ! -perm -001 2>/dev/null)" = "$1" ]
}

# root_ok <path>: a root of this script's shape that may be used or removed.
root_ok() {
  case $1 in
    /*/*) ;;
    *) return 1 ;;
  esac
  case $1 in
    *[[:cntrl:]]*) return 1 ;;
  esac
  ro_n=${1##*/}
  case $ro_n in
    *[!0-9a-f]*) return 1 ;;
  esac
  [ "${#ro_n}" -eq 16 ] || return 1
  [ -d "$1" ] && [ ! -L "$1" ] || return 1
  [ "$(find "$1" -maxdepth 0 -user "$uid" 2>/dev/null)" = "$1" ] || return 1
  # The record holds the canonical path, so a linked parent would spell
  # another; a parent others may write lets them swap the root.
  [ "$(cd -P -- "${1%/*}" 2>/dev/null && pwd -P)" = "${1%/*}" ] && owned_private "${1%/*}"
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

# record_read <record-file>: set rr_line to the root a record names.
record_read() {
  rr_line=''
  [ -f "$1" ] && [ ! -L "$1" ] || return 1
  { IFS= read -r rr_line <"$1"; } 2>/dev/null || [ -n "$rr_line" ]
}

# record_of <root>: set rf_rec to the record file naming <root>. Reads each
# record in this shell: a close runs this over every record in the fleet
# home, which every repository on the machine shares.
record_of() {
  rf_rec=''
  [ -d "$smap" ] && [ ! -L "$smap" ] || return 1
  set +f
  for rf_f in "$smap"/*.tmpdir; do
    rf_k=${rf_f##*/}
    key_ok "${rf_k%.tmpdir}" || continue
    record_read "$rf_f" && [ "$rr_line" = "$1" ] || continue
    set -f
    rf_rec=$rf_f
    return 0
  done
  set -f
  return 1
}

# release_record <record-file>: remove the root it names, then the record. A
# root that is gone already leaves only the record to remove; one of another
# shape is refused, record kept.
release_record() {
  record_read "$1" || return 1
  rl_root=$rr_line
  if [ -e "$rl_root" ] || [ -L "$rl_root" ]; then
    root_ok "$rl_root" || return 1
    wipe "$rl_root" || return 1
  fi
  rm -f -- "$1" 2>/dev/null
}

case $verb in
  make)
    key=$3
    key_ok "$key" || die "the key is not a worktree's or a session's" 2
    umask 077
    [ ! -L "$smap" ] || die "the fleet home's scratch directory is a symlink"
    mkdir -p -- "$smap" 2>/dev/null && [ -d "$smap" ] && [ ! -L "$smap" ] \
      || die "cannot create the fleet home's scratch directory"
    rec=$smap/$key.tmpdir
    if [ -L "$rec" ] || { [ -e "$rec" ] && [ ! -f "$rec" ]; }; then
      die "the root's record is not a regular file"
    fi
    # The recorded root stands while it is usable, whatever base this
    # launch would derive, or whether that base is usable at all.
    if [ "$fresh" = 0 ] && record_read "$rec" && root_ok "$rr_line"; then
      chmod 700 "$rr_line" 2>/dev/null || die "cannot close the root $rr_line to others"
      printf '%s\n' "$rr_line"
      exit 0
    fi
    if [ -n "${PLANWRIGHT_FLEET_SCRATCH_BASE-}" ]; then
      base=$PLANWRIGHT_FLEET_SCRATCH_BASE
      # Checked raw as well: command substitution strips a trailing newline,
      # which would resolve the base to its sibling.
      case $base in
        *[[:cntrl:]]*) die "PLANWRIGHT_FLEET_SCRATCH_BASE holds a control character" ;;
        /*) ;;
        *) die "PLANWRIGHT_FLEET_SCRATCH_BASE is not an absolute path" ;;
      esac
      # The trailing dot keeps a resolved name's own trailing newline, which
      # the substitution would strip, for the check below.
      base=$(cd -P -- "$base" 2>/dev/null && pwd -P && echo .) || die "PLANWRIGHT_FLEET_SCRATCH_BASE names no directory"
      base=${base%.}
      base=${base%"$nl"}
      case $base in
        *[[:cntrl:]]*) die "PLANWRIGHT_FLEET_SCRATCH_BASE resolves through a control character" ;;
      esac
    else
      tmp_dir=$(cd -P /tmp 2>/dev/null && pwd -P) || die "/tmp does not resolve"
      base=$tmp_dir/planwright-$uid
      [ -L "$base" ] || mkdir -- "$base" 2>/dev/null || : # not-a-lock: creating the scratch base, whose checks follow
      # Ours whatever umask made it; a symlink, a hard link to a file, or
      # another user's entry stays refused.
      if ! owned_private "$base" && [ ! -L "$base" ] \
        && [ "$(find "$base" -maxdepth 0 -type d -user "$uid" 2>/dev/null)" = "$base" ]; then
        chmod 700 "$base" 2>/dev/null || :
      fi
    fi
    owned_private "$base" || die "the scratch base $base is not this user's own directory closed to others"
    case $base/ in
      "$home"/*) die "the scratch base lies inside the fleet home" ;;
    esac
    digest=$(printf '%s/%s' "$home" "$key" | git hash-object --stdin 2>/dev/null) || die "cannot name the root"
    root=$base/${digest%"${digest#????????????????}"}
    if [ "$fresh" = 1 ]; then
      if [ -e "$rec" ]; then
        # A record that cannot be read names no root to empty; the rename
        # below replaces it.
        if record_read "$rec"; then
          release_record "$rec" || die "the recorded root would not empty"
        fi
      fi
      # The earlier layout nested a session's root in its worktree's.
      [ ! -L "$smap/${key%%-*}" ] || die "the earlier layout's worktree root is a symlink"
      legacy=$smap/$(printf '%s' "$key" | tr - /)
      [ -L "$legacy" ] || wipe "$legacy" || die "the earlier layout's root would not empty"
      if [ -e "$root" ] || [ -L "$root" ]; then
        if ! root_ok "$root" || ! wipe "$root"; then
          die "the root $root would not empty"
        fi
      fi
    fi
    made=0
    # An existing root is kept; the checks below decide either way.
    if mkdir -- "$root" 2>/dev/null; then # not-a-lock: creating the scratch root, whose checks follow
      made=1
    fi
    if ! root_ok "$root"; then
      [ "$made" = 0 ] || rmdir -- "$root" 2>/dev/null
      die "the root $root is not this user's own directory"
    fi
    # BSD chmod reads a `--` after the mode as a file; the path is absolute.
    chmod 700 "$root" 2>/dev/null || die "cannot close the root $root to others"
    tmp=$(mktemp "$smap/.$key.XXXXXX" 2>/dev/null) || tmp=''
    if [ -z "$tmp" ] || ! { printf '%s\n' "$root" >"$tmp"; } 2>/dev/null || ! mv -f -- "$tmp" "$rec" 2>/dev/null; then
      [ -z "$tmp" ] || rm -f -- "$tmp" 2>/dev/null
      [ "$made" = 0 ] || rmdir -- "$root" 2>/dev/null
      die "cannot record the root"
    fi
    printf '%s\n' "$root"
    ;;
  release)
    if ! record_of "$3"; then
      # A reclaim or an earlier release took both; an unrecorded root that
      # still exists stays.
      [ ! -e "$3" ] && [ ! -L "$3" ]
      exit
    fi
    release_record "$rf_rec"
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
      # A make killed between its temporary record and the rename.
      set +f
      for f in "$smap/.$wkey".* "$smap/.$wkey"-*; do
        set -f
        [ ! -f "$f" ] || [ -L "$f" ] || rm -f -- "$f"
      done
      set -f
      [ -L "$smap/$wkey" ] || wipe "$smap/$wkey" || rc=1
    fi
    exit "$rc"
    ;;
esac
