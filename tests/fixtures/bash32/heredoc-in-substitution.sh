#!/bin/bash
# A quoted heredoc written inside a command substitution, its body holding an
# unbalanced backtick: bash 3.2 scans the body for quotes and backticks and
# runs off the end of the file. Every later bash parses it.
program="$(
  cat <<'AWK'
# the `check task reaches it
{ print }
AWK
)"
printf '%s\n' "$program"
