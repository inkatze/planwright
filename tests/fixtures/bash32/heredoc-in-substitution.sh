#!/bin/bash
# A heredoc written inside a double-quoted command substitution, its body
# holding an unbalanced backtick: bash 3.2 lexes the body as shell and runs
# off the end of the file. The double quotes matter: in a bare $( ) it skips
# the body's `#` line as a comment and parses. Every later bash parses both.
program="$(
  cat <<'AWK'
# the `check task reaches it
{ print }
AWK
)"
printf '%s\n' "$program"
