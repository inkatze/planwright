# shellcheck shell=bash
# notion-fake-api.sh — a stand-in `curl` that answers the Notion adapter from
# canned payloads (sourced, never executed).
#
# The adapter talks to the API only through `curl` on PATH, so a fake one on
# PATH is the whole seam: no base-URL override exists for a test to use, and
# so none exists for anything else to point the token at.
#
# The fake records what it was asked, so a suite can pin the request shape:
#   <log>/argv      one line per call, the arguments joined by spaces
#   <log>/config    everything read from `-K -` (where headers travel)
#   <log>/body.<n>  the request body of call <n>, when one was sent
#
# Routes are lines of `<METHOD> <path-and-query> <fixture> <status> [once]`,
# matched in order; a `once` route answers a single call and is then skipped,
# which is how a suite stages a rate-limit answer before the real one. An
# unrouted request answers 404 object_not_found.
#
# Usage:
#   . tests/lib/notion-fake-api.sh
#   notion_fake_install <bin-dir> <fixture-dir> <routes-file> <log-dir>

notion_fake_install() {
  mkdir -p "$1" "$4" || return 1
  : >"$4/argv"
  : >"$4/config"
  : >"$4/used"
  cat >"$1/curl" <<EOF
#!/bin/bash
fixtures='$2'
routes='$3'
log='$4'
EOF
  cat >>"$1/curl" <<'EOF'
n=$(($(wc -l <"$log/argv") + 1))
printf '%s\n' "$*" >>"$log/argv"
method=GET out= url= data= readcfg=0
while [ $# -gt 0 ]; do
  case $1 in
    -K) [ "$2" = - ] && readcfg=1; shift 2 ;;
    -X) method=$2; shift 2 ;;
    -o) out=$2; shift 2 ;;
    -w | -H | --proto | --max-time | --connect-timeout) shift 2 ;;
    --data-binary) data=${2#@}; shift 2 ;;
    https://*) url=$1; shift ;;
    *) shift ;;
  esac
done
if [ "$readcfg" = 1 ]; then
  cat >>"$log/config"
fi
[ -n "$data" ] && cp "$data" "$log/body.$n"
path=${url#https://api.notion.com}
fixture= status=404 lineno=0
while read -r m p f s once; do
  lineno=$((lineno + 1))
  [ "$m" = "$method" ] && [ "$p" = "$path" ] || continue
  if [ "$once" = once ]; then
    grep -qx "$lineno" "$log/used" && continue
    printf '%s\n' "$lineno" >>"$log/used"
  fi
  fixture=$f status=$s
  break
done <"$routes"
if [ -n "$fixture" ]; then
  cp "$fixtures/$fixture" "$out"
else
  printf '%s\n' '{"object":"error","status":404,"code":"object_not_found","message":"unrouted"}' >"$out"
fi
printf '%s' "$status"
EOF
  chmod +x "$1/curl"
}
