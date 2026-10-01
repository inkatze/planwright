# shellcheck shell=sh
# flight-common.sh — helpers shared by flight-dispatch.sh and flight-sweep.sh
# (sourced, never executed), so the two judge a path and report the resolved
# plugin-root pair one way: a tower and its workers running different
# planwright versions is visible at dispatch and in the sweep's render alike.
#
# The sourcing script sets ROOTS to scripts/resolve-installed-roots.sh and LF
# to a newline before calling these.

# has_ctl <text> — true when the text carries a control byte, which would
# break a TAB-separated report line or split it in two.
has_ctl() {
  [ "$(printf '%s' "$1" | tr -d '\000-\037\177')" != "$1" ]
}

# private_dir <dir> — a real directory the invoking user owns that neither
# group nor others can write.
private_dir() {
  [ ! -L "$1" ] && [ -d "$1" ] || return 1
  _pd_uid=$(id -u) || return 1
  [ -n "$(find "$1" -maxdepth 0 -user "$_pd_uid" ! -perm -0020 ! -perm -0002 2>/dev/null)" ]
}

# plugin_version <root> — the plugin manifest's version, `-` when unreadable.
plugin_version() {
  _pj="$1/.claude-plugin/plugin.json"
  [ -r "$_pj" ] || {
    echo -
    return
  }
  _ver=$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$_pj" | head -n 1)
  _ver=$(printf '%s' "$_ver" | tr -d '\000-\037\177')
  printf '%s\n' "${_ver:--}"
}

# worker_root — the first installed root Claude Code records, which is what a
# worker launched through `claude` loads planwright from.
worker_root() {
  _cands=$(/bin/sh "$ROOTS" 2>/dev/null </dev/null) || _cands=''
  _old_ifs=$IFS
  IFS=$LF
  for _r in $_cands; do
    if [ -d "$_r" ]; then
      IFS=$_old_ifs
      (cd "$_r" && pwd -P) | tr -d '\000-\037\177'
      return
    fi
  done
  IFS=$_old_ifs
}

# print_root_pair <tower-root> <worker-root|empty> — the report lines
# `root<TAB>tower|worker<TAB><path><TAB><version>` and `root-skew<TAB>yes|no|unknown`.
print_root_pair() {
  _tv=$(plugin_version "$1")
  printf 'root\ttower\t%s\t%s\n' "$1" "$_tv"
  if [ -n "$2" ]; then
    _wv=$(plugin_version "$2")
    printf 'root\tworker\t%s\t%s\n' "$2" "$_wv"
    if [ "$_tv" = - ] || [ "$_wv" = - ]; then
      printf 'root-skew\tunknown\n'
    elif [ "$_tv" = "$_wv" ]; then
      printf 'root-skew\tno\n'
    else
      printf 'root-skew\tyes\n'
    fi
  else
    printf 'root\tworker\tunknown\t-\n'
    printf 'root-skew\tunknown\n'
  fi
}

# origin_dest <url> — print `<host>/<owner>/<repo>` (lower-cased, `.git`
# dropped) for a network remote URL in the URL or scp-like form; nothing for a
# local path or anything else. Userinfo carrying `#`, `?`, `\` or `:` is
# refused: a parser that ends the authority there reads a different host than
# the one git connects to.
origin_dest() {
  printf '%s\n' "$1" | sed -n -E \
    -e 's~^(https|http|ssh|git|git\+ssh|ssh\+git)://([^/@#?\\:]+@)?([A-Za-z0-9][A-Za-z0-9.-]*)(:[0-9]+)?/([A-Za-z0-9._-]+)/([A-Za-z0-9._-]+)/?$~\3/\5/\6~p' \
    -e 's#^([A-Za-z0-9._-]+@)?([A-Za-z0-9][A-Za-z0-9.-]*):([A-Za-z0-9._-]+)/([A-Za-z0-9._-]+)/?$#\2/\3/\4#p' \
    | head -n 1 | sed 's/\.git$//' | tr '[:upper:]' '[:lower:]'
}
