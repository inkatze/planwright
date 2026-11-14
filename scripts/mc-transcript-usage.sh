#!/usr/bin/env bash
# mc-transcript-usage.sh — the one parser of a session transcript's usage
# records, shared by scripts/mc-throughput.sh (cost against context) and
# scripts/mc-context.sh (a session's context reading). Read-only; the
# transcript is parsed as data by jq and nothing in it is executed or
# interpolated.
#
# Usage: mc-transcript-usage.sh <file> [<tail bytes>]
#   Each assistant frame with a usage object prints
#     m<TAB><message id><TAB><input><TAB><cache read><TAB><5m cache write>
#       <TAB><1h cache write><TAB><output>
#   (a usage with no cache_creation breakdown reports its cache writes as
#   5-minute ones) and each result frame with a model usage prints
#     w<TAB><largest context window>
#   in file order. A line that does not parse, or a field that is not a
#   number (read as 0), yields nothing alone: every line is judged on its
#   own. With a tail size only that many bytes from the end are read (the
#   first, possibly cut, line then fails to parse and is skipped).
# Exit: 0 done; 1 the file cannot be read; 2 usage.
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

[ $# -ge 1 ] && [ $# -le 2 ] || {
  printf '%s\n' "usage: mc-transcript-usage.sh <file> [<tail bytes>]" >&2
  exit 2
}
f=$1
tail_bytes=${2:-}
case $tail_bytes in
  *[!0-9]*) exit 2 ;;
esac
[ -f "$f" ] && [ ! -L "$f" ] && [ -r "$f" ] || exit 1

# shellcheck disable=SC2016 # a jq program
filter='
def n: if type == "number" and . >= 0 and . <= 1000000000 then floor else 0 end;
def id: (. // "-") | tostring | explode | map(select(. > 31 and . != 127)) | implode;
fromjson? | try (
  if .type == "assistant" and (.message.usage | type) == "object" then
    .message.usage as $u
    | (if ($u.cache_creation | type) == "object"
      then [($u.cache_creation.ephemeral_5m_input_tokens | n), ($u.cache_creation.ephemeral_1h_input_tokens | n)]
      else [($u.cache_creation_input_tokens | n), 0] end) as $w
    | ["m", (.message.id | id), ($u.input_tokens | n), ($u.cache_read_input_tokens | n), $w[0], $w[1],
      ($u.output_tokens | n)] | @tsv
  elif .type == "result" and (.modelUsage | type) == "object" then
    ["w", ([.modelUsage[] | (.contextWindow | n)] | max // 0)] | @tsv
  else empty end) catch empty'

if [ -n "$tail_bytes" ]; then
  tail -c "$tail_bytes" -- "$f" | jq -R -r "$filter" 2>&-
else
  jq -R -r "$filter" "$f" 2>&-
fi
exit $?
