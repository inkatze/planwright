# shellcheck shell=sh
# echo-safety.sh — the canonical echo-discipline sanitizer for planwright's
# framework scripts (sourced, never executed). Sourced today by the migrated
# command-tier callers (spec-validate.sh, spec-walkthrough.sh); spec-assemble.sh
# (deliberately self-contained) and spec-scope.sh (a tracked follow-up) keep
# byte-identical inline copies.
#
# Echo discipline (doctrine/security-posture.md, "Framework-script security"):
# untrusted content — spec-file values, branch names, parsed identifiers — must
# never reach the terminal raw, where an embedded escape sequence could drive
# it. Callers strip the non-printable bytes off any such value before echoing.
#
# sanitize_printable <value> [placeholder] — strip C0 control characters and
# DEL (\000-\037\177) from <value> and print the result via `printf '%s'` (no
# trailing newline). When nothing printable remains, print <placeholder>
# instead if one was given, else the stripped (possibly empty) value. Each
# caller passes its own placeholder so its output stays byte-identical.
#
# Note the deliberate scope: this strips C0 + DEL only, matching the shell
# callers. The awk `gsub(/[^[:print:]]/, "")` form (spec-validate.sh
# first_header, and the sibling header parsers) is the in-awk expression of the
# same posture but strips ALL non-printable bytes, including high/UTF-8 bytes
# under the pinned C locale; it cannot call this sourced shell function and is
# intentionally left in place.
sanitize_printable() {
  _sp=$(printf '%s' "$1" | tr -d '\000-\037\177')
  if [ -z "$_sp" ] && [ $# -ge 2 ]; then
    _sp=$2
  fi
  printf '%s' "$_sp"
}
