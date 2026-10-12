#!/bin/bash
# Tests for the shared HTML escaper (scripts/html-escape.sh), the one escaper
# the HTML renderers splice in rather than each carrying a copy (inception D-9;
# spec-comprehension REQ-E1.7).
#
# Plain bash 3.2, inline asserts (sibling convention).
set -u
unset CDPATH
LC_ALL=C
export LC_ALL

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LIB="$REPO_ROOT/scripts/html-escape.sh"

failures=0
assert_eq() {
  if [ "$2" = "$3" ]; then
    echo "ok: $1"
  else
    echo "FAIL: $1 (expected '$2', got '$3')" >&2
    failures=$((failures + 1))
  fi
}

if [ ! -r "$LIB" ]; then
  echo "FAIL: escaper library missing at $LIB" >&2
  exit 1
fi
# shellcheck source=scripts/html-escape.sh
. "$LIB"

# The five characters, ampersand first so the entities the others introduce are
# not themselves re-escaped.
assert_eq "value: the five specials" \
  "&lt;a href=&quot;x&quot; title=&#39;y&#39;&gt;&amp;&lt;/a&gt;" \
  "$(html_escape_value "<a href=\"x\" title='y'>&</a>")"
assert_eq "value: an existing entity is escaped, not trusted" \
  "&amp;amp;" "$(html_escape_value "&amp;")"
assert_eq "value: plain text passes through" "plain text" "$(html_escape_value "plain text")"
assert_eq "value: multibyte bytes pass through" "café — ≤" "$(html_escape_value "café — ≤")"
assert_eq "value: awk escape sequences stay literal" 'a\nb\\c' "$(html_escape_value 'a\nb\\c')"
assert_eq "value: empty in, empty out" "" "$(html_escape_value "")"

# The awk source, spliced into a caller's program.
got="$(printf '%s\n' "<b>&'\"" | awk "$html_escape_awk"'{ print esc($0) }')"
assert_eq "awk: esc() over a record" "&lt;b&gt;&amp;&#39;&quot;" "$got"

# Consolidation: the renderers splice the shared escaper rather than carrying
# their own copy, so a fix to it reaches every page.
for s in inception-render.sh spec-assemble.sh; do
  if grep -q 'function esc(' "$REPO_ROOT/scripts/$s"; then
    echo "FAIL: $s defines its own esc() instead of using html-escape.sh" >&2
    failures=$((failures + 1))
  else
    echo "ok: $s carries no private esc() copy"
  fi
done

if [ "$failures" -ne 0 ]; then
  echo "test-html-escape: $failures assertion(s) failed" >&2
  exit 1
fi
echo "test-html-escape: all assertions passed"
