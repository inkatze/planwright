# shellcheck shell=sh
# html-escape.sh — the shared HTML escaper that spec-assemble.sh and
# inception-render.sh splice in (sourced, never executed). fleet-dashboard.sh
# still carries a byte-equivalent copy of its own.
#
#   $html_escape_awk     awk source defining esc(s), spliced into a renderer's
#                        program so every page escapes bundle text the same way
#   html_escape_value    the same escape over a single shell value, for the
#                        handful of values a renderer interpolates outside awk
#
# Bundle text is data, never markup: everything a renderer prints from a bundle
# goes through esc(). The ampersand is replaced first so the entities the other
# replacements introduce are not themselves re-escaped. \047 is the apostrophe,
# written as an escape because the source is single-quoted shell. Bytes >= 0x80
# pass through untouched, which is only true under LC_ALL=C: callers pin it.

# shellcheck disable=SC2016 # awk source, not a shell expansion
html_escape_awk='
  function esc(s) {
    gsub(/&/, "\\&amp;", s)
    gsub(/</, "\\&lt;", s)
    gsub(/>/, "\\&gt;", s)
    gsub(/"/, "\\&quot;", s)
    gsub(/\047/, "\\&#39;", s)
    return s
  }'

# html_escape_value <string> — print <string> escaped, no trailing newline. The
# value reaches awk on stdin, never through -v, which would expand its
# backslash sequences.
html_escape_value() {
  printf '%s' "$1" | awk "$html_escape_awk"'{ printf "%s", esc($0) }'
}
