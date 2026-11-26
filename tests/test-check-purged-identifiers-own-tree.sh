#!/bin/bash
# The purged-identifier guard run against this repository's own tracked tree
# (REQ-B1.1). It is a file of its own because the scan hashes every word
# window of every tracked file, which costs most of the purged-identifier
# suites' time; the fixture cases are the sibling suites sharing
# tests/lib/purged-identifiers-harness.sh.
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
# shellcheck source=tests/lib/purged-identifiers-harness.sh
. "$(cd "$(dirname "$0")" && pwd)/lib/purged-identifiers-harness.sh"

# The repo's own tree against its own guard. Two states are legitimate right
# now, and the suite refuses to call either one a silent pass:
#
#   armed   - the committed seed carries min-max-words and the tree is clean;
#   pending - the seed predates that directive, so the guard fails closed until
#             an operator re-seeds. Provisioning needs the plaintext, which is
#             deliberately unavailable to anything but a human at a terminal,
#             so this suite cannot arm it and must not paper over it either.
#
# Anything else is a real failure. The pending arm disappears on the first
# re-seed, and this whole branch collapses back to a plain pass.
out="$(cd "$REPO_ROOT" && "$SCAN" 2>&1)"
rc=$?
if [ "$rc" -eq 0 ]; then
  echo "ok: the repo's own tracked tree passes its own guard (seed armed)"
elif [ "$rc" -eq 2 ] && [ -z "${out##*min-max-words*}" ]; then
  echo "ok: the committed seed predates min-max-words, so the guard fails closed pending an operator re-seed"
  echo "    remedy: scripts/seed-purged-identifiers.sh (reads the plaintext from stdin)"
else
  echo "FAIL: the repo's own tracked tree neither passes nor fails closed for the known pending reason (exit $rc)" >&2
  printf '%s\n' "$out" >&2
  failures=$((failures + 1))
fi

finish check-purged-identifiers-own-tree
