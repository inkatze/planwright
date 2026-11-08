#!/bin/bash
# The shell rules a stream-json launch appends (config/launch-shell-rules.txt)
# must not ban a shape the doctrine they cite (doctrine/plugin-script-invocation.md)
# leaves unnamed: each ban in the rules file has its keyword in the doctrine's
# "One plain command per Bash call" section.
set -u
LC_ALL=C
export LC_ALL
unset CDPATH
here=$(cd "$(dirname "$0")" && pwd -P) || exit 1
root=$(cd "$here/.." && pwd -P) || exit 1
rules=$root/config/launch-shell-rules.txt
doc=$root/doctrine/plugin-script-invocation.md
rc=0
fail() { printf 'FAIL: %s\n' "$1" >&2; rc=1; }

section=$(sed -n '/^## One plain command per Bash call/,/^## Invoke by the shebang/p' "$doc")
[ -n "$section" ] || fail "the doctrine has no One plain command per Bash call section"

# keyword in the rules file | keyword the doctrine section must carry
while IFS='|' read -r in_rules in_doc; do
  grep -qiF -e "$in_rules" "$rules" || fail "the rules file no longer names '$in_rules' (update this table)"
  printf '%s\n' "$section" | grep -qiF -e "$in_doc" \
    || fail "the rules file bans '$in_rules' but the doctrine section never names '$in_doc'"
done <<'TABLE'
No cd|No `cd`
no loop|loop
background job|background
Write tool|Write tool
heredoc|heredoc
no variables of your own|No variable assignments
Never stage a script|No staged scripts
no pipe to trim output|No display pipes
TABLE

[ "$rc" -eq 0 ] && echo "launch-shell-rules-parity: ok"
exit "$rc"
