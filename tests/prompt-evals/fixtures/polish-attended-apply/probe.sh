#!/bin/sh
# probe.sh — the side effects an attended /polish run should leave in $1: a
# commit ahead of `main` carrying a Planwright-Sign-Off trailer, its short SHA
# (so the assert can find it in the handoff text), and whether the
# missing-argument path now honours the documented exit status.
set -u
work="$1"

ids=$(git -C "$work" log --format='%(trailers:key=Planwright-Sign-Off,valueonly)' main..HEAD 2>/dev/null | grep -c 'PS-')
sha=$(git -C "$work" log --format='%h%x09%(trailers:key=Planwright-Sign-Off,valueonly,separator=%x2C)' main..HEAD 2>/dev/null \
  | awk -F '\t' '$2 ~ /PS-/ { print substr($1, 1, 7); exit }')
suffixed=$(git -C "$work" log --format=%s main..HEAD 2>/dev/null | grep -c 'pending-sign-off\]')

exit_fixed=false
if [ -x "$work/greet.sh" ]; then
  rc=0
  (cd "$work" && ./greet.sh >/dev/null 2>&1) || rc=$?
  [ "$rc" -eq 2 ] && exit_fixed=true
fi

printf '{"signoff_ids": %s, "signoff_sha7": "%s", "suffixed_commits": %s, "exit_fixed": %s}\n' \
  "${ids:-0}" "$sha" "${suffixed:-0}" "$exit_fixed"
