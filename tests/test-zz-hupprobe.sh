#!/bin/bash
# TEMPORARY diagnostic probe, never merged: does an empty or odd pid operand
# make /bin/sh's or /bin/bash's kill signal the caller's whole group?
set -u
for shell in /bin/sh /bin/bash; do
  for arg in '' ' ' '-' '--' 'x'; do
    out=$(mktemp)
    perl -e 'setpgrp(0, 0) or die; exec @ARGV' -- "$shell" -c '
      got=$1
      trap "echo GROUP-GOT-HUP >>$got" HUP
      bash -c "trap \"echo SIBLING-GOT-HUP >>$got; exit 0\" HUP; sleep 3" &
      sleep 0.3
      kill -HUP "$2"
      echo "kill rc=$?" >>"$got"
      sleep 0.5
    ' probe "$out" "$arg" >"$out.err" 2>&1
    printf '%s kill -HUP [%s]: %s | %s\n' "$shell" "$arg" "$(tr '\n' ' ' <"$out")" "$(tr '\n' ' ' <"$out.err")"
  done
done
