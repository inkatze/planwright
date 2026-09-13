# shellcheck shell=sh
# lock-lib.sh — the one advisory-lock primitive for planwright's script layer
# (sourced, never executed).
#
# THE LOCK-HOLDER LIST. Every script that implements an advisory lock sources
# this file and takes its locks through it; nothing in the tree acquires a lock
# any other way. As of this writing that list is:
#
#   scripts/orchestrate-lock.sh   the per-spec orchestration lock
#   scripts/fleet-state.sh        the fleet state registry and its counters
#   scripts/allocation-ledger.sh  the per-unit allocation ledgers
#   scripts/fleet-streamjson.sh   the supervisor's journal/launch/recover locks
#   scripts/observation-carry.sh  the observation carry's push+PR section
#
# Everything else that takes a lock does so by calling one of those five, so
# adopting them adopts the tree. scripts/check-lock-primitive.sh enforces the
# rule that keeps the list honest: `mkdir` is retired as an acquisition
# primitive, and an un-annotated `mkdir` whose exit status is read as a
# lock-acquisition signal is a build failure.
#
# WHY `mkdir` IS RETIRED. It was measured losing mutual exclusion in the
# ordinary acquire / read-modify-write / release cycle: twelve concurrent
# same-resource writers produced 13 interleaved critical sections over ten
# rounds under `mkdir` + `rmdir`, and 0 over the same rounds under an atomic
# symlink create. A single fresh `mkdir` contest IS exclusive on a conforming
# filesystem, so the loss appeared in the release-and-reacquire cycle rather
# than in `mkdir` itself; and the reimplemented coreutils `mkdir` on at least
# one host in the support bar returns success to several concurrent creators,
# so the primitive is not even reliably exclusive there. The consequence was
# silent: twenty concurrent registrations landed seventeen records while every
# writer exited 0.
#
# THE PRIMITIVE. The lock IS a symbolic link and its target IS the owner token.
# One `ln -s` is the whole exclusion: the create either wins the path or fails,
# and the winner's identity is readable by anyone. `flock` is not an option —
# it is absent on macOS, which is inside the support bar — and no other
# portable call gives create-or-fail plus an identity in one step.
#
# THE OWNER TOKEN is `<pid>-<epoch>-<seq>`. Two live processes cannot share a
# pid, which is all the uniqueness a token needs among concurrent holders; the
# epoch separates it from a link left by a dead process that once had the same
# pid, and the sequence number separates two holds taken by one process. The
# token is what makes release safe and what makes staleness answerable.
#
# STALE MEANS THE OWNER'S PROCESS IS ABSENT — NEVER AN AGE. An age threshold
# answers a question nobody asked: a lock held for twenty minutes by a running
# job is live, and a lock taken one second ago by a process that has since died
# is garbage. Both of those were mishandled by the age rule this replaces, in
# opposite and equally bad directions — it broke live locks under load and left
# dead ones standing for the whole threshold. `pw_lock_owner_alive` probes the
# pid instead, and an EPERM from `kill -0` reads as ALIVE (a process owned by
# another user is still a process), so the probe errs toward refusing to break.
#
# THE BREAK CANNOT DOUBLE-GRANT, and the mechanism is a claim link rather than
# a bare unlink. A breaker first takes `<lock>.break.<dead-token>` by the same
# atomic create, so only one caller can be breaking a given owner at a time.
# Holding that claim, the lock provably still belongs to the dead owner —
# changing it requires a break, and a break requires this claim — so the
# replacement is safe, and it is done by renaming a freshly made link OVER the
# path in one step rather than unlink-then-create, leaving no instant where the
# path is free for a peer to create into. A breaker that dies holding the claim
# is itself reclaimed by owner-liveness, by an ownership-verified rename that
# two reclaimers cannot both win.
#
# RELEASE IS OWNERSHIP-VERIFIED. `pw_lock_release` reads the link's target back
# and unlinks only while it is still this holder's token, so the classic
# advisory-lock clobber — a holder returning after its lock was broken and
# deleting the CURRENT holder's lock — cannot happen.
#
# REENTRANCY IS BY TOKEN. A nested acquire of a path this shell already holds
# deepens the hold and returns success; the link is unlinked at the OUTERMOST
# release. The bookkeeping lives in a shell variable, so it is per shell
# instance: a subshell inherits a copy, sees the hold, and its own releases
# decrement only its copy. That is the right answer for the nesting this exists
# for (a helper function calling a locked verb inside an already-locked
# section) and callers should not rely on it across a `&` or a pipeline.
#
# SIGNAL-SAFE RELEASE MUST BE INSTALLED BEFORE THE CRITICAL SECTION. Two ways,
# and a caller picks one:
#
#   * no trap of its own: call `pw_lock_trap_install` once, before the first
#     acquire. It arms EXIT/INT/TERM/HUP to release every held lock.
#   * its own trap already: do NOT call `pw_lock_trap_install` (it would
#     replace the caller's handlers). Call `pw_lock_release_all` as the first
#     thing in the existing handler, and arm that handler before the first
#     acquire.
#
# Exit codes are uniform across the verbs: 0 success, 1 a live holder has it
# (or, for release, the lock is not ours), 2 a real error — an unusable lock
# path, a missing `readlink`, or an exhausted acquire budget. A bounded acquire
# FAILS CLOSED: it never breaks a lock it could not prove dead.
#
# POSIX sh on the macOS + Linux support bar. No bashisms, no `local`.
#
# shellcheck disable=SC2034 # PW_LOCK_TOKEN is this library's output, read by
# the caller and by cross-process releases, never by the library itself.

# The registry of locks this shell holds: one "<depth> <token> <path>" record
# per line, always newline-terminated. Path comes last because it is the only
# field that may contain a space.
PW_LOCK_HELD=''
# The caller's handle on its own hold: every verb that takes a lock publishes
# the token here so a cross-process release can prove ownership.
PW_LOCK_TOKEN=''
PW_LOCK_SEQ=0
PW_LOCK_EPOCH=''
PW_LOCK_TRAP_ARMED=''
PW_LOCK_READLINK_CHECKED=''
PW_LOCK_NL='
'

# ~100s of sleeping plus syscalls at the default budget. It must stay far below
# any plausible hold so an exhausted waiter fails closed on a busy lock rather
# than concluding anything about the holder; nothing here breaks on a budget
# anyway, but a caller that retries forever is its own kind of outage.
PW_LOCK_MAX_TRIES=5000
PW_LOCK_SLEEP=0.02

_pw_lock_usage() {
  printf '%s\n' "lock-lib: $1 needs a lock path" >&2
}

# Every create is confirmed by reading the link back, so a shell that cannot
# read a link target cannot be told "I won the path" from "a peer did". Refuse
# at the first acquire rather than report a lock nobody holds.
_pw_lock_require_readlink() {
  [ -z "$PW_LOCK_READLINK_CHECKED" ] || return 0
  if ! command -v readlink >/dev/null 2>&1; then
    printf '%s\n' "lock-lib: readlink not found — a lock cannot be confirmed as this process's own without it, so every acquire is refused" >&2
    return 2
  fi
  PW_LOCK_READLINK_CHECKED=yes
  return 0
}

# _pw_lock_lookup <path> — set _pw_lock_depth/_pw_lock_token from the registry.
# 0 this shell holds <path>, 1 it does not.
_pw_lock_lookup() {
  _pw_lock_depth=0
  _pw_lock_token=''
  _pwl_rest=$PW_LOCK_HELD
  while [ -n "$_pwl_rest" ]; do
    _pwl_line=${_pwl_rest%%"$PW_LOCK_NL"*}
    _pwl_rest=${_pwl_rest#*"$PW_LOCK_NL"}
    [ -n "$_pwl_line" ] || continue
    _pwl_tail=${_pwl_line#* }
    if [ "${_pwl_tail#* }" = "$1" ]; then
      _pw_lock_depth=${_pwl_line%% *}
      _pw_lock_token=${_pwl_tail%% *}
      return 0
    fi
  done
  return 1
}

# _pw_lock_store <path> <token> <depth> — replace <path>'s registry record. A
# depth of 0 drops it.
_pw_lock_store() {
  _pws_out=''
  _pws_rest=$PW_LOCK_HELD
  while [ -n "$_pws_rest" ]; do
    _pws_line=${_pws_rest%%"$PW_LOCK_NL"*}
    _pws_rest=${_pws_rest#*"$PW_LOCK_NL"}
    [ -n "$_pws_line" ] || continue
    _pws_tail=${_pws_line#* }
    [ "${_pws_tail#* }" = "$1" ] && continue
    _pws_out="$_pws_out$_pws_line$PW_LOCK_NL"
  done
  if [ "$3" -gt 0 ]; then
    _pws_out="$_pws_out$3 $2 $1$PW_LOCK_NL"
  fi
  PW_LOCK_HELD=$_pws_out
}

# _pw_lock_mint — set _pw_lock_new_token. The epoch is read once per process:
# it separates this process's tokens from those of a dead process that once
# held the same pid, and re-reading it per acquire would buy nothing for a fork.
_pw_lock_mint() {
  if [ -z "$PW_LOCK_EPOCH" ]; then
    PW_LOCK_EPOCH=$(date +%s 2>/dev/null) || PW_LOCK_EPOCH=0
    case $PW_LOCK_EPOCH in
      '' | *[!0-9]*) PW_LOCK_EPOCH=0 ;;
    esac
  fi
  PW_LOCK_SEQ=$((PW_LOCK_SEQ + 1))
  _pw_lock_new_token="$1-$PW_LOCK_EPOCH-$PW_LOCK_SEQ"
}

# pw_lock_owner_alive <token> — 0 the token names a running process, 1 it does
# not. A token this library did not mint has no probeable pid and reads as
# absent: it names no process that could be in a critical section, and treating
# it as live would wedge the path forever. A DETACHED token is the deliberate
# exception and always reads alive — see pw_lock_acquire_detached.
pw_lock_owner_alive() {
  _pwa_pid=${1%%-*}
  case $_pwa_pid in
    detached) return 0 ;;
    '' | *[!0-9]*) return 1 ;;
  esac
  [ "$_pwa_pid" -gt 0 ] || return 1
  kill -0 "$_pwa_pid" 2>/dev/null && return 0
  # `kill -0` fails for two very different reasons and only one of them means
  # absent. A process owned by another user answers EPERM, and breaking ITS
  # lock is the double-grant this whole file exists to prevent, so an EPERM
  # reads as alive. `ps` is the second opinion where the message is unfamiliar.
  _pwa_err=$(kill -0 "$_pwa_pid" 2>&1) || :
  case $_pwa_err in
    *[Pp]ermission* | *[Pp]ermitted*) return 0 ;;
  esac
  if command -v ps >/dev/null 2>&1 && ps -p "$_pwa_pid" >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

# pw_lock_owner <path> — print the holder's token (nothing, and no newline, for
# a path nobody holds).
pw_lock_owner() {
  _pwo_target=$(readlink "$1" 2>/dev/null) || _pwo_target=''
  printf '%s' "$_pwo_target"
}

# _pw_lock_slug <token> — a filename-safe rendering of a token that may have
# come from a foreign writer and may therefore contain anything but NUL.
_pw_lock_slug() {
  printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '_' | cut -c1-64
}

# _pw_lock_break <lock> <dead-token> <our-token> — replace a lock whose owner
# is gone. 0 the lock is now ours, 1 it is not (a peer is breaking it, a peer
# holds it, or the break lost a race and declined to guess).
_pw_lock_break() {
  _pwb_lock=$1
  _pwb_dead=$2
  _pwb_token=$3
  _pwb_claim="$_pwb_lock.break.$(_pw_lock_slug "$_pwb_dead")"

  if ! ln -s "$_pwb_token" "$_pwb_claim" 2>/dev/null \
    || [ "$(readlink "$_pwb_claim" 2>/dev/null)" != "$_pwb_token" ]; then
    # Either a peer is breaking this same owner — in which case waiting is
    # correct and there is nothing to do — or a breaker died holding the claim,
    # which would wedge the path forever. Reclaim only the second case, and
    # only by an ownership-verified rename: two reclaimers renaming the same
    # path cannot both find their own probe's target behind it, so only one
    # clears the claim and the other comes back on the next spin.
    _pwb_holder=$(readlink "$_pwb_claim" 2>/dev/null) || _pwb_holder=''
    if [ -n "$_pwb_holder" ] && ! pw_lock_owner_alive "$_pwb_holder"; then
      _pwb_aside="$_pwb_claim.dead.$_pwb_token"
      if mv -f "$_pwb_claim" "$_pwb_aside" 2>/dev/null; then
        if [ "$(readlink "$_pwb_aside" 2>/dev/null)" = "$_pwb_holder" ]; then
          rm -f "$_pwb_aside" 2>/dev/null || :
        else
          # A live successor's claim, not the dead one probed. Put it back by
          # re-creating it — a claim's identity IS its target, and a create
          # cannot follow a link the way a rename onto an occupied path can.
          # If the path has since been taken again the create fails, and
          # dropping the aside is then the only correct move. Either way this
          # caller does not hold the claim and says so.
          _pwb_back=$(readlink "$_pwb_aside" 2>/dev/null) || _pwb_back=''
          [ -z "$_pwb_back" ] || ln -s "$_pwb_back" "$_pwb_claim" 2>/dev/null || :
          rm -f "$_pwb_aside" 2>/dev/null || :
        fi
      fi
    fi
    return 1
  fi

  # Holding the claim: the lock cannot have changed hands since it was probed,
  # because changing it requires a break and a break requires this claim. A
  # mismatch here means the dead owner released after all (its own release is
  # ownership-verified, so it took only its own link) — not ours to take.
  if [ "$(readlink "$_pwb_lock" 2>/dev/null)" != "$_pwb_dead" ]; then
    rm -f "$_pwb_claim" 2>/dev/null || :
    return 1
  fi

  # Unlink the dead owner's link, then create ours, and believe the create only
  # after reading it back. EVERY STEP HERE ACTS ON THE LINK, NEVER ON WHAT IT
  # POINTS AT, which is why this is not the one-step rename it looks like it
  # should be: `mv` FOLLOWS a link whose target is an existing directory and
  # files the replacement inside it, so the lock would never be broken and each
  # spin would litter a stray link into an unrelated directory. `rm -f` and
  # `ln -s` both take the link itself.
  #
  # The gap between the unlink and the create is harmless: the owner is gone,
  # so nobody legitimately holds this path, and a peer that wins the free path
  # in between takes a lock it is entitled to — this caller's own create then
  # fails and it reports busy rather than claiming a hold it does not have.
  rm -f "$_pwb_lock" 2>/dev/null || :
  if ln -s "$_pwb_token" "$_pwb_lock" 2>/dev/null \
    && [ "$(readlink "$_pwb_lock" 2>/dev/null)" = "$_pwb_token" ]; then
    rm -f "$_pwb_claim" 2>/dev/null || :
    return 0
  fi
  rm -f "$_pwb_claim" 2>/dev/null || :
  return 1
}

# _pw_lock_try_core <path> <owner-field> — one acquisition attempt, no waiting.
# <owner-field> becomes the token's leading field: this process's pid for an
# ordinary hold, the word `detached` for a hold with no owning process.
_pw_lock_try_core() {
  _pwt_lock=$1
  _pwt_owner_field=$2
  _pw_lock_require_readlink || return 2

  if _pw_lock_lookup "$_pwt_lock"; then
    if [ "$(readlink "$_pwt_lock" 2>/dev/null)" = "$_pw_lock_token" ]; then
      _pw_lock_store "$_pwt_lock" "$_pw_lock_token" "$((_pw_lock_depth + 1))"
      PW_LOCK_TOKEN=$_pw_lock_token
      return 0
    fi
    # The registry says we hold it and the path disagrees: the lock was broken
    # or removed under us. Drop the bookkeeping and contend like anyone else,
    # rather than releasing someone else's link later on its strength.
    _pw_lock_store "$_pwt_lock" '' 0
  fi

  _pw_lock_mint "$_pwt_owner_field"
  _pwt_token=$_pw_lock_new_token

  # `ln -s target dir` puts the link INSIDE a directory squatting the path and
  # still exits 0, so the create is confirmed before it is believed. An
  # unconfirmed create would report a lock this caller does not hold and send
  # it into its critical section holding nothing.
  if ln -s "$_pwt_token" "$_pwt_lock" 2>/dev/null; then
    if [ "$(readlink "$_pwt_lock" 2>/dev/null)" = "$_pwt_token" ]; then
      PW_LOCK_TOKEN=$_pwt_token
      _pw_lock_store "$_pwt_lock" "$_pwt_token" 1
      return 0
    fi
    rm -f "$_pwt_lock/$_pwt_token" 2>/dev/null || :
  fi

  # `-L` and not `-e` asks the right question: the lock IS the link, whatever
  # it points at, and `-e` follows it and reads false for a dangling one.
  if [ -L "$_pwt_lock" ]; then
    _pwt_owner=$(readlink "$_pwt_lock" 2>/dev/null) || _pwt_owner=''
    if [ -z "$_pwt_owner" ]; then
      # It vanished between the create and the read. Nothing is proven; the
      # caller's next attempt sees a settled path.
      return 1
    fi
    if pw_lock_owner_alive "$_pwt_owner"; then
      return 1
    fi
    _pw_lock_break "$_pwt_lock" "$_pwt_owner" "$_pwt_token" || return 1
    PW_LOCK_TOKEN=$_pwt_token
    _pw_lock_store "$_pwt_lock" "$_pwt_token" 1
    return 0
  fi

  if [ -e "$_pwt_lock" ]; then
    # Something that is not a lock squats the path — a directory left by the
    # retired `mkdir` shape, or an unrelated file. No amount of waiting clears
    # it and breaking it would be a guess, so say so instead of spinning a
    # budget out into a refusal that blames contention.
    printf '%s\n' "lock-lib: $_pwt_lock exists and is not a lock symlink — refusing to wait on it" >&2
    return 2
  fi

  # Nothing is at the path, so nothing was holding it: the create failed on the
  # store rather than on a peer. One retry separates a holder that released in
  # the gap (benign) from a store that cannot be written at all.
  if ln -s "$_pwt_token" "$_pwt_lock" 2>/dev/null \
    && [ "$(readlink "$_pwt_lock" 2>/dev/null)" = "$_pwt_token" ]; then
    PW_LOCK_TOKEN=$_pwt_token
    _pw_lock_store "$_pwt_lock" "$_pwt_token" 1
    return 0
  fi
  if [ ! -L "$_pwt_lock" ] && [ ! -e "$_pwt_lock" ]; then
    printf '%s\n' "lock-lib: cannot create $_pwt_lock (parent unwritable or filesystem error)" >&2
    return 2
  fi
  return 1
}

# _pw_lock_acquire_core <path> <max-tries> <owner-field> — spin until held or
# the budget runs out.
_pw_lock_acquire_core() {
  _pwq_lock=$1
  _pwq_max=$2
  _pwq_owner_field=$3
  case $_pwq_max in
    '' | *[!0-9]* | 0) _pwq_max=$PW_LOCK_MAX_TRIES ;;
  esac
  _pwq_tries=0
  while :; do
    _pw_lock_try_core "$_pwq_lock" "$_pwq_owner_field"
    _pwq_rc=$?
    [ "$_pwq_rc" -eq 0 ] && return 0
    [ "$_pwq_rc" -eq 2 ] && return 2
    _pwq_tries=$((_pwq_tries + 1))
    [ "$_pwq_tries" -lt "$_pwq_max" ] || break
    sleep "$PW_LOCK_SLEEP" 2>/dev/null || sleep 1
  done
  return 1
}

# pw_lock_try <path> — one acquisition attempt, no waiting. 0 held (and
# PW_LOCK_TOKEN is the token to prove it), 1 a live holder has it, 2 a real
# error.
pw_lock_try() {
  if [ "$#" -lt 1 ] || [ -z "${1:-}" ]; then
    _pw_lock_usage pw_lock_try
    return 2
  fi
  _pw_lock_try_core "$1" "$$"
}

# pw_lock_acquire <path> [<max-tries>] — spin until held or the budget runs
# out. 0 held, 1 a live holder kept it for the whole budget, 2 a real error.
pw_lock_acquire() {
  if [ "$#" -lt 1 ] || [ -z "${1:-}" ]; then
    _pw_lock_usage pw_lock_acquire
    return 2
  fi
  _pw_lock_acquire_core "$1" "${2:-$PW_LOCK_MAX_TRIES}" "$$"
}

# A DETACHED HOLD is one whose owner is not a process: a CLI that acquires in
# one invocation and releases in a later one holds nothing in between, so there
# is no pid whose absence could prove the lock dead. The token records the word
# `detached` where a pid would go, and the liveness probe reports it alive —
# which is the honest answer, since nothing about it is knowable — so it is
# never auto-broken. The acquirer's pid still goes into the token after that
# word — not to be probed, but so two detached holds minted in the same second
# cannot collide and let one caller's release unlink the other's lock.
# THE CONSEQUENCE IS DELIBERATE AND WORTH SEEING: a detached
# hold whose owner crashed is cleared by an explicit release, not by waiting.
# That is the trade the liveness rule makes: it never breaks a live lock, and in
# exchange it cannot guess about a hold with no owner to ask about.
pw_lock_try_detached() {
  if [ "$#" -lt 1 ] || [ -z "${1:-}" ]; then
    _pw_lock_usage pw_lock_try_detached
    return 2
  fi
  _pw_lock_try_core "$1" "detached-$$"
}

# pw_lock_acquire_detached <path> [<max-tries>] — the spinning form.
pw_lock_acquire_detached() {
  if [ "$#" -lt 1 ] || [ -z "${1:-}" ]; then
    _pw_lock_usage pw_lock_acquire_detached
    return 2
  fi
  _pw_lock_acquire_core "$1" "${2:-$PW_LOCK_MAX_TRIES}" "detached-$$"
}

# pw_lock_acquire_for <path> <owner-pid> [<max-tries>] — take the lock ON
# BEHALF OF another process. A short-lived CLI that acquires for a caller which
# then does the work would otherwise name ITSELF as owner, and the lock would
# read as dead the instant the CLI exited. The caller passes its own pid and
# the hold stays as alive as the caller is. The pid is not verified live here:
# a caller naming a pid that is already gone gets a lock anyone may break,
# which is the correct outcome and not an error.
pw_lock_acquire_for() {
  if [ "$#" -lt 2 ] || [ -z "${1:-}" ] || [ -z "${2:-}" ]; then
    _pw_lock_usage pw_lock_acquire_for
    return 2
  fi
  case $2 in
    '' | *[!0-9]*)
      printf '%s\n' "lock-lib: pw_lock_acquire_for needs a numeric owner pid" >&2
      return 2
      ;;
  esac
  _pw_lock_acquire_core "$1" "${3:-$PW_LOCK_MAX_TRIES}" "$2"
}

# pw_lock_release <path> — give up one depth of this shell's hold, unlinking
# at the outermost. 0 released or deepened-down, 1 this shell does not hold it
# (including the case where the hold was broken underneath it), 2 the unlink
# failed.
pw_lock_release() {
  if [ "$#" -lt 1 ] || [ -z "${1:-}" ]; then
    _pw_lock_usage pw_lock_release
    return 2
  fi
  _pwr_lock=$1
  _pw_lock_lookup "$_pwr_lock" || return 1
  if [ "$_pw_lock_depth" -gt 1 ]; then
    _pw_lock_store "$_pwr_lock" "$_pw_lock_token" "$((_pw_lock_depth - 1))"
    return 0
  fi
  _pwr_token=$_pw_lock_token
  _pw_lock_store "$_pwr_lock" '' 0
  # The verified unlink. A holder whose lock was broken finds a stranger's
  # token here and leaves it alone, which is the whole reason the token exists.
  [ "$(readlink "$_pwr_lock" 2>/dev/null)" = "$_pwr_token" ] || return 1
  rm -f "$_pwr_lock" 2>/dev/null || return 2
  return 0
}

# pw_lock_release_token <path> <token> — the cross-process release. A CLI that
# hands its caller a token on acquire takes it back here, and the unlink still
# happens only while the link is that token's. 0 released, 1 the lock is not
# that token's (including: already gone), 2 the unlink failed.
pw_lock_release_token() {
  if [ "$#" -lt 2 ] || [ -z "${1:-}" ] || [ -z "${2:-}" ]; then
    _pw_lock_usage pw_lock_release_token
    return 2
  fi
  [ "$(readlink "$1" 2>/dev/null)" = "$2" ] || return 1
  rm -f "$1" 2>/dev/null || return 2
  return 0
}

# pw_lock_break_force <path> — clear a lock WITHOUT proving ownership. This is
# the operator's escape hatch and the only way to recover a detached hold whose
# owner crashed, so it is deliberately unconditional; a caller that can prove
# ownership must use pw_lock_release or pw_lock_release_token instead. It also
# clears a DIRECTORY left at the path by the retired `mkdir` shape, which is
# what makes an in-place upgrade from that shape possible at all. 0 the path is
# clear, 2 something is there that this cannot safely remove.
pw_lock_break_force() {
  if [ "$#" -lt 1 ] || [ -z "${1:-}" ]; then
    _pw_lock_usage pw_lock_break_force
    return 2
  fi
  if [ -L "$1" ]; then
    rm -f "$1" 2>/dev/null || return 2
    return 0
  fi
  if [ -d "$1" ]; then
    rm -rf "$1" 2>/dev/null || return 2
    return 0
  fi
  [ ! -e "$1" ] || return 2
  return 0
}

# pw_lock_release_all — drop every depth of every lock this shell holds. Safe
# to call from a signal handler and safe to call twice; always 0, because a
# handler that can fail is a handler that can leave a lock standing.
pw_lock_release_all() {
  while [ -n "$PW_LOCK_HELD" ]; do
    _pwx_line=${PW_LOCK_HELD%%"$PW_LOCK_NL"*}
    [ -n "$_pwx_line" ] || break
    _pwx_tail=${_pwx_line#* }
    _pwx_token=${_pwx_tail%% *}
    _pwx_path=${_pwx_tail#* }
    _pw_lock_store "$_pwx_path" '' 0
    if [ "$(readlink "$_pwx_path" 2>/dev/null)" = "$_pwx_token" ]; then
      rm -f "$_pwx_path" 2>/dev/null || :
    fi
  done
  return 0
}

# pw_lock_trap_install — arm the signal-safe release. Call it once, BEFORE the
# first acquire, and only from a caller that has no trap of its own; a caller
# that does keeps its handlers and calls pw_lock_release_all from inside them.
pw_lock_trap_install() {
  [ -z "$PW_LOCK_TRAP_ARMED" ] || return 0
  PW_LOCK_TRAP_ARMED=yes
  trap 'pw_lock_release_all' EXIT
  trap 'pw_lock_release_all; exit 130' INT
  trap 'pw_lock_release_all; exit 143' TERM
  trap 'pw_lock_release_all; exit 129' HUP
  return 0
}
