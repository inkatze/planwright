# shellcheck shell=sh
# flight-text.sh — the operator-text screen shared by the visual-flight
# scripts (sourced, never executed): flight-dispatch.sh cleans the ask and the
# grounds before they reach the worker brief, and flight-record.sh cleans them
# again, with the worker's own inputs, before they reach a committed or remote
# record.

# The largest ask a flight carries, in bytes: the brief quotes it whole and
# the record fences it whole.
# shellcheck disable=SC2034 # read by the sourcing scripts
ASK_MAX=65536

# INVIS_SED deletes the invisible and bidi-control code points (their UTF-8
# byte sequences, matched bytewise under LC_ALL=C): NEL, soft hyphen, Arabic
# letter mark, the Hangul and Khmer fillers, Mongolian vowel separator,
# zero-width joiners and directional marks, line and paragraph separators,
# embeddings and overrides, invisible operators, isolates and the deprecated
# format controls, variation selectors, the byte-order mark, interlinear
# annotation controls, and the tag block. Either could hide or reorder
# operator text in the brief or the record.
INVIS_SED=$(printf 's/\302[\205\255]//g;s/\330\234//g;s/\341\205[\237\240]//g;s/\341\236[\264\265]//g;s/\341\240\216//g;s/\342\200[\213-\217\250-\256]//g;s/\342\201[\240-\244\246-\257]//g;s/\343\205\244//g;s/\357\270[\200-\217]//g;s/\357\273\277//g;s/\357\276\240//g;s/\357\277[\271-\273]//g;s/\363\240[\200\201][\200-\277]//g;s/\363\240[\204-\206][\200-\277]//g;s/\363\240\207[\200-\257]//g')

# clean_text <in> <out> — write <in> with CRLF and lone CR line endings made
# LF, other control bytes (but tab) dropped, then the invisible and bidi code
# points stripped until the text is stable: one deletion can join the bytes
# around it into another code point. CLEAN_STRIPPED is 1 when the invisible
# strip removed anything; a line ending is not a stripped character.
FLIGHT_CR=$(printf '\r')
CLEAN_STRIPPED=0
# shellcheck disable=SC2034 # CLEAN_STRIPPED is read by the sourcing script
clean_text() {
  # The sed pass also gives the base the same final-newline handling the
  # strip loop's sed passes apply, so the comparisons are like with like.
  sed "s/$FLIGHT_CR\$//" <"$1" | tr "$FLIGHT_CR" '\n' | tr -d '\000-\010\013-\037\177' >"$2.base" || return 1
  cp "$2.base" "$2" || return 1
  while :; do
    sed "$INVIS_SED" <"$2" >"$2.next" || return 1
    cmp -s "$2" "$2.next" && break
    mv "$2.next" "$2" || return 1
  done
  CLEAN_STRIPPED=0
  cmp -s "$2.base" "$2" || CLEAN_STRIPPED=1
  rm -f "$2.base" "$2.next"
}
