#!/bin/sh
# A case pattern without its leading `(` inside a command substitution: bash
# 3.2 reads the pattern's `)` as the end of the substitution. Every later bash
# parses it.
marks=$(
  for f in a .b; do
    case "$f" in .*) continue ;; esac
    printf 'x'
  done
)
printf '%s\n' "$marks"
