# shellcheck shell=sh
# no_timeout_path <dir> — fill <dir> with links to every command on PATH
# except timeout and gtimeout, and print it: the PATH of a host without
# coreutils (stock macOS), on any host. The first of each name wins, as a
# PATH lookup would.
#
# One `ln` per PATH directory rather than per command: a PATH holds thousands
# of commands, and a launch for each was most of the calling suite's own work.
# Each directory's links land before the next directory is read, so the
# existence check still lets the earlier directory win.
no_timeout_path() {
  mkdir -p -- "$1" || return 1
  ntp_ifs=$IFS
  IFS=:
  for ntp_d in $PATH; do
    IFS=$ntp_ifs
    [ -d "$ntp_d" ] || continue
    # shellcheck disable=SC2016 # $0 and $@ belong to the inner shell
    for ntp_f in "$ntp_d"/*; do
      ntp_n=${ntp_f##*/}
      case $ntp_n in
        timeout | gtimeout) continue ;;
      esac
      [ -x "$ntp_f" ] && [ ! -e "$1/$ntp_n" ] && printf '%s\0' "$ntp_f"
    done | xargs -0 sh -c '[ "$#" -eq 0 ] || ln -s "$@" "$0"' "$1"
  done
  IFS=$ntp_ifs
  printf '%s\n' "$1"
}
