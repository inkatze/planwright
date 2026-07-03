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
# sanitize_printable <value> [placeholder] — strip C0 control characters, DEL,
# and C1 control characters (\000-\037\177\200-\237) from <value> and print the
# result via `printf '%s'` (no trailing newline). When nothing printable
# remains, print <placeholder> instead if one was given, else the stripped
# (possibly empty) value. Each caller passes its own placeholder so its output
# stays byte-identical.
#
# Scope: strips C0 + DEL + C1. The C1 range (0x80-0x9F) is included because a
# raw C1 byte drives the terminal too — notably CSI (0x9B), a single-byte
# equivalent of ESC-[ — so leaving it through would reopen the escape-injection
# hole this sanitizer exists to close (doctrine/security-posture.md). Under the
# pinned C locale this is a byte-range strip, so it also removes UTF-8
# continuation bytes in 0x80-0x9F: multibyte punctuation (em-dash, smart quotes)
# in sanitized *display* output is mangled. That is the intended trade — this
# helper only ever runs on untrusted content headed for the terminal, where the
# security posture outranks display fidelity.
#
# The awk `gsub(/[^[:print:]]/, "")` form (spec-validate.sh first_header, and the
# sibling header parsers) is the in-awk expression of the same posture but strips
# ALL non-printable bytes; it cannot call this sourced shell function and is
# intentionally left in place. The inline copies in spec-scope.sh /
# spec-assemble.sh still strip C0 + DEL only — widening them to match is a
# tracked follow-up, out of this change's scope.
sanitize_printable() {
  _sp=$(printf '%s' "$1" | tr -d '\000-\037\177\200-\237')
  if [ -z "$_sp" ] && [ $# -ge 2 ]; then
    _sp=$2
  fi
  printf '%s' "$_sp"
}
