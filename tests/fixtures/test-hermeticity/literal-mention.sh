#!/bin/bash
# Not a read: the names appear only as literal text the suite never expands.
# $PLANWRIGHT_ROOT in a comment
pattern='"$CLAUDE_PLUGIN_ROOT"/scripts/'
msg="spell it \$CLAUDE_PLUGIN_ROOT"
printf '%s %s\n' "$pattern" "$msg"
cat <<'BODY'
${PLANWRIGHT_ROOT}/scripts/x.sh
BODY
