#!/bin/bash
# The tower deny floor's git push rows (tower-placement REQ-C1.1): each push
# entry of config/tower-settings.json's deny list, through its
# tests/fixtures/tower-deny-acts.tsv sample, is matched by its entry and
# refused by scripts/tower-session.sh in a marked session with no profile.
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
unset CDPATH
# shellcheck source=tests/lib/tower-floor-harness.sh
. "$(cd "$(dirname "$0")" && pwd)/lib/tower-floor-harness.sh"

echo "# each push entry's sample: matched by its entry, refused in a marked session"
entry_rows '^push$'

no_gh_calls
finish
