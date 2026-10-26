# shellcheck shell=bash
# dead-owner.sh — a PID no process can hold, for a fixture that needs an owner
# that is gone (sourced, never executed).
#
# A PID the test spawned and reaped is not dead for long: the host may hand
# it to another process before the code under test probes it, and on a busy
# machine it does, so the fixture then reads as a live owner. A PID above the
# host's assignable range can never be reused. Where the code reads an owner
# through the lock library, a token that library minted for a holder that has
# since exited is the other conforming shape: its mint time separates it from
# a later process that reuses the PID.
#
#   dead_owner_pid   print a PID above every supported host's range: Linux
#                    caps pid_max at 2^22, macOS and the BSDs at 99999. Fails,
#                    printing nothing, if a process somehow answers to it

dead_owner_pid() {
  if kill -0 4194305 2>/dev/null; then
    return 1
  fi
  printf '%s\n' 4194305
}
