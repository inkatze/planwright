#!/usr/bin/env bash
# classify-ci-failure.sh — classify a failed CI run for adaptive retry
# (REQ-E1.2, D-25). `/execute-task` runs this over captured CI output to
# decide whether to retry (transient) or escalate immediately (logic).
#
# Rule: a failure is `transient` only when a transient indicator is present
# AND no logic indicator is present. Anything else is `logic` — any logic
# indicator (a deterministic failure that merely shares a log with a network
# blip), or no recognized signal at all. Unknown defaults to logic because
# escalating an unclassifiable failure is safer than burning retries on it.
#
# Usage: classify-ci-failure.sh [<file>]
#   Reads CI output from <file>, or from stdin when no file is given.
#
# Output: prints `transient` or `logic` on stdout.
# Exit codes: 0 transient, 1 logic, 2 usage error (a named-but-missing file).
#
# Portable bash 3.2 / BSD tooling; no fish/mise/tmux/Ansible (REQ-K1.5).
# Input is treated as data only: it is matched with fixed grep patterns,
# never evaluated, so shell metacharacters in the log are inert.
set -u

# Pin the C locale so the case-insensitive ASCII matching below means exactly
# its ASCII range on every host (defensive; mirrors the sibling scripts).
LC_ALL=C
export LC_ALL

unset CDPATH

if [ "$#" -gt 1 ]; then
  echo "usage: classify-ci-failure.sh [<file>]" >&2
  exit 2
fi

if [ "$#" -eq 1 ]; then
  if [ ! -f "$1" ] || [ ! -r "$1" ]; then
    echo "classify-ci-failure: file not found or unreadable: $1" >&2
    exit 2
  fi
  input="$(cat "$1")"
else
  input="$(cat)"
fi

# Transient indicators: infrastructure and network failures that a retry can
# plausibly clear. Fixed extended-regex alternation, matched case-insensitively.
transient_re='connection (timed out|refused|reset)'
transient_re="$transient_re|timed out|timeout"
transient_re="$transient_re|network is unreachable|network error|no route to host"
transient_re="$transient_re|could not resolve host|temporary failure in name resolution"
transient_re="$transient_re|name or service not known|eai_again"
transient_re="$transient_re|tls handshake timeout|i/o timeout"
transient_re="$transient_re|503 service unavailable|service unavailable"
transient_re="$transient_re|502 bad gateway|504 gateway|gateway time-?out"
transient_re="$transient_re|429 too many requests|too many requests|rate limit"
transient_re="$transient_re|failed to pull|error pulling image|manifest unknown"
transient_re="$transient_re|the remote end hung up"

# Logic indicators: deterministic, reproducible failures a retry cannot clear
# (assertion/expectation mismatches, type/compile/syntax errors, lint/format
# violations, test-runner failure summaries). These override a transient match.
logic_re='assertion ?(error|failed)|assert_'
logic_re="$logic_re|expected .* (but|to|got)|expected:"
logic_re="$logic_re|type ?error|error ts[0-9]+|syntax ?error|parse error"
logic_re="$logic_re|compile error|compilation (error|failed)"
logic_re="$logic_re|undefined (method|reference|variable|symbol)|unresolved reference"
logic_re="$logic_re|name ?error|panic:|traceback \(most recent call last\)"
logic_re="$logic_re|[0-9]+ (failing|failed)|tests? failed"
logic_re="$logic_re|would reformat|lint (error|violation)|sc[0-9]{4}"

has_transient=0
has_logic=0
printf '%s\n' "$input" | grep -iqE "$transient_re" && has_transient=1
printf '%s\n' "$input" | grep -iqE "$logic_re" && has_logic=1

if [ "$has_transient" -eq 1 ] && [ "$has_logic" -eq 0 ]; then
  echo transient
  exit 0
fi

echo logic
exit 1
