# shellcheck shell=sh
# no_timeout_path <dir> — fill <dir> with links to every command on PATH
# except timeout and gtimeout, and print it: the PATH of a host without
# coreutils (stock macOS), on any host. The first of each name wins, as a
# PATH lookup would.
no_timeout_path() {
  mkdir -p "$1" || return 1
  ntp_ifs=$IFS
  IFS=:
  for ntp_d in $PATH; do
    IFS=$ntp_ifs
    [ -d "$ntp_d" ] || continue
    for ntp_f in "$ntp_d"/*; do
      ntp_n=${ntp_f##*/}
      case $ntp_n in
        timeout | gtimeout) continue ;;
      esac
      [ -x "$ntp_f" ] && [ ! -e "$1/$ntp_n" ] && ln -s "$ntp_f" "$1/$ntp_n"
    done
  done
  IFS=$ntp_ifs
  printf '%s\n' "$1"
}
