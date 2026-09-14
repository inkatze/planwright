# shellcheck shell=sh
# lock-lib.sh — the one advisory-lock primitive for planwright's script layer
# (sourced, never executed).
#
# THE VERBS. Exit codes are uniform: 0 success, 1 the lock stayed with a holder
# (for a release: it is not ours), 2 a real error.
#
#   pw_lock_trap_install                 arm the signal-safe release
#   pw_lock_release_all                  release everything this shell holds
#   pw_lock_try <path>                   one attempt
#   pw_lock_acquire <path> [<tries>]     spin
#   pw_lock_try_detached <path>          one attempt at a hold with no owner
#   pw_lock_acquire_detached <path> [n]  the spinning form
#   pw_lock_acquire_for <path> <pid> [n] acquire on behalf of another process
#   pw_lock_release <path>               ownership-verified, reentrancy-aware
#   pw_lock_release_token <path> <tok>   the same, from another process
#   pw_lock_break_force <path>           clear without proving ownership
#   pw_lock_clear_legacy <path>          clear a retired-shape lock DIRECTORY
#   pw_lock_owner <path>                 print the holder's token
#   pw_lock_owner_alive <token>          0 the owner is running, 1 it is gone
#   PW_LOCK_TOKEN                        set by a successful acquire
#
# THE LOCK-HOLDER LIST. Every script that implements an ADVISORY LOCK sources
# this file and takes its locks through it:
#
#   (none yet: the adopter migrations are their own task)
#
# Everything else that takes an advisory lock does so by calling a script on
# that list, so adopting a listed script adopts the tree under it. The list is
# pinned against the tree, in both directions, by
# tests/test-lock-lib.sh, which is what stops it outliving its accuracy;
# scripts/check-lock-primitive.sh keeps the underlying rule, that `mkdir` is
# retired as an acquisition primitive. Two exclusion mechanisms are outside
# this family on purpose and are not advisory locks: the petition claim in
# scripts/allocation-petition.sh, a rename election over files a consumer may
# be reading, and the expect-absent git-ref lease in scripts/fleet-fence.sh,
# which has to serialize across clones where no local lock can reach.
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
# A LOCK PATH IS A REGISTRY KEY as well as a filename. The registry of held
# locks is one newline-terminated record per lock, so a path carrying a newline
# is refused; and this file derives its working paths beside the lock with a
# `#`, so a path carrying one of those is refused too — otherwise one caller's
# lock could be another's break claim.
#
# THE HOLD BELONGS TO THE PROCESS THAT TAKES IT. `$$` is the parent's pid in a
# subshell, a pipeline stage and a command substitution, so a lock taken in one
# of those names a process that may exit while the hold stands. Acquire in the
# process that will hold it.
#
# STALE MEANS THE OWNER'S PROCESS IS ABSENT — NEVER AN AGE. An age threshold
# answers a question nobody asked: a lock held for twenty minutes by a running
# job is live, and a lock taken one second ago by a process that has since died
# is garbage. Both of those were mishandled by the age rule this replaces, in
# opposite and equally bad directions — it broke live locks under load and left
# dead ones standing for the whole threshold. `pw_lock_owner_alive` probes the
# pid instead, and an EPERM from `kill -0` reads as ALIVE (a process owned by
# another user is still a process), so the probe errs toward refusing to break.
# A running pid is then checked against the token's own mint time, because pids
# are recycled and an unrelated process wearing a dead owner's pid would hold
# the lock forever; that check only ever turns alive into absent, and falls
# back to the pid alone wherever it cannot be made.
#
# THE BREAK CANNOT DOUBLE-GRANT, and the mechanism is a claim link rather than
# a bare unlink. A breaker first takes `<lock>#break#<dead-token>` by the same
# atomic create, so only one caller can be breaking a given owner at a time.
# THE `#` IS LOAD-BEARING: the working paths this library derives sit in the
# same directory as the locks themselves, so a caller that builds lock paths
# out of user input could otherwise name one of them and have its own lock
# deleted by an unrelated breaker. `#` is outside every lock-name grammar in
# the tree, which is what keeps the two namespaces apart.
# Holding that claim, the lock provably still belongs to the dead owner —
# changing it requires a break, and a break requires this claim — so the
# replacement is safe. It unlinks and re-creates rather than renaming over the
# path, because a rename FOLLOWS a link whose target is a directory; the gap
# that opens is harmless, since nobody legitimately holds a lock whose owner is
# gone, and a peer that wins the free path in between takes a lock it is
# entitled to while the breaker's own create fails and it reports busy. A
# breaker that dies holding the claim is itself reclaimed by owner-liveness, by
# an ownership-verified rename that two reclaimers cannot both win.
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
# Exit codes are uniform across the verbs: 0 success, 1 the lock stayed with a
# holder (for release: it is not ours), 2 a real error — an unusable lock path,
# a missing `readlink`, an unwritable parent. An exhausted acquire budget is 1,
# not 2: the caller waited and did not get it, which is the same answer as a
# holder that never let go. A bounded acquire FAILS CLOSED either way — it
# never breaks a lock it could not prove dead.
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
# How many spins between examinations of the holder. Probing every spin forks
# `readlink` fifty times a second per waiter for a condition that cannot become
# true faster than the holder can exit.
PW_LOCK_PROBE_EVERY=50

_pw_lock_usage() {
  printf '%s\n' "lock-lib: $1 needs a lock path" >&2
}

# _pw_lock_path_ok <verb> <path> — 0 usable, 1 refused (with a diagnostic).
# The registry is a newline-delimited record per held lock, so a path carrying
# a newline would forge a second record: the hold would never be found again by
# its own release, and a crafted one names a path the signal handler would
# unlink. Nothing in the tree passes such a path; refusing it here is what
# keeps that true.
_pw_lock_path_ok() {
  if [ -z "$2" ]; then
    _pw_lock_usage "$1"
    return 1
  fi
  case $2 in
    *"$PW_LOCK_NL"*)
      printf '%s\n' "lock-lib: $1 refuses a lock path containing a newline" >&2
      return 1
      ;;
    *'#'*)
      # The break claim, its aside and the legacy aside all hang off the lock
      # path with a `#`. A caller that could name a lock containing one could
      # name another lock's working path, which is exactly the collision the
      # separator was chosen to prevent — so this is enforced here rather than
      # asked of every caller that builds a path out of anything.
      printf '%s\n' "lock-lib: $1 refuses a lock path containing '#', the character this library derives its working paths with" >&2
      return 1
      ;;
  esac
  return 0
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

# _pw_lock_uptime — set _pw_lock_uptime_out to the host's uptime in seconds, or
# to the empty string where it cannot be read. pid 1 has been running for
# exactly as long as the host has, and its elapsed time is reported by the same
# `ps` field every other liveness question here uses.
_pw_lock_uptime() {
  _pw_lock_uptime_out=$(ps -o etimes= -p 1 2>/dev/null | tr -d ' ') || _pw_lock_uptime_out=''
  case $_pw_lock_uptime_out in
    '' | *[!0-9]*) _pw_lock_uptime_out='' ;;
  esac
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
  # The host's uptime at mint, from pid 1's elapsed time: the one quantity both
  # this process and a future checker can read that no clock adjustment moves.
  # It is what lets the mint-time check below compare two ages rather than two
  # wall-clock readings, which is the difference between a rule that is never
  # an age and one that breaks a live lock the next time NTP steps.
  _pw_lock_uptime
  PW_LOCK_SEQ=$((PW_LOCK_SEQ + 1))
  # The minting process's own pid is in there even when the OWNER is somebody
  # else: without it, two short-lived CLIs acquiring for the same owner in the
  # same second mint the same token, and a replayed release of the first hold
  # would unlink the second one's live lock.
  _pw_lock_new_token="$1-$PW_LOCK_EPOCH-$_pw_lock_uptime_out-$$-$PW_LOCK_SEQ"
}

# pw_lock_owner_alive <token> — 0 the token names a running process, 1 it does
# not. A token this library did not mint has no probeable pid and reads as
# absent: it names no process that could be in a critical section, and treating
# it as live would wedge the path forever. A DETACHED token is the deliberate
# exception and always reads alive — see pw_lock_acquire_detached.
pw_lock_owner_alive() {
  [ "$#" -ge 1 ] || return 1
  _pwa_pid=${1%%-*}
  case $_pwa_pid in
    detached) return 0 ;;
    '' | *[!0-9]*) return 1 ;;
  esac
  # Width before value: a digit string wider than any pid a system assigns
  # names no process, and handing it to shell arithmetic below errors out to
  # stderr instead of answering, which would then be read as a verdict.
  [ "${#_pwa_pid}" -le 10 ] || return 1
  [ "$_pwa_pid" -gt 0 ] || return 1
  if kill -0 "$_pwa_pid" 2>/dev/null; then
    _pw_lock_owner_is_minter "$1" "$_pwa_pid"
    return $?
  fi
  # `kill -0` fails for two very different reasons and only one of them means
  # absent. A process owned by another user answers EPERM, and breaking ITS
  # lock is the double-grant this whole file exists to prevent, so an EPERM
  # reads as alive. `ps` is the second opinion where the message is unfamiliar.
  # LC_ALL is pinned for the capture rather than assumed from the caller: the
  # match below is on the error TEXT, and a translated message would read as
  # absent and break a live process's lock.
  _pwa_err=$(LC_ALL=C kill -0 "$_pwa_pid" 2>&1) || :
  case $_pwa_err in
    *[Pp]ermission* | *[Pp]ermitted*)
      # EPERM says the process EXISTS and is not ours. That is an answer to
      # "is it there", not to "is it the one that minted this", so it goes
      # through the same second question every other existing process does —
      # otherwise a pid recycled by another user bypasses the check entirely.
      _pw_lock_owner_is_minter "$1" "$_pwa_pid"
      return $?
      ;;
  esac
  if command -v ps >/dev/null 2>&1 && ps -p "$_pwa_pid" >/dev/null 2>&1; then
    _pw_lock_owner_is_minter "$1" "$_pwa_pid"
    return $?
  fi
  return 1
}

# _pw_lock_owner_is_minter <token> <pid> — 0 the running process could be the
# one that minted this token, 1 it demonstrably is not.
#
# Pids are recycled, and a lock naming a dead owner whose pid has since been
# reused reads as held forever. The token carries the moment it was minted, and
# a process that started AFTER that moment cannot be the one that minted it.
# That is the whole check, and it is deliberately one-directional: it can only
# turn a live-looking owner into an absent one, never the reverse, so a wrong
# answer costs a refused break rather than a broken live lock.
#
# It degrades rather than guessing. A token with no usable mint time, or a host
# whose `ps` reports no elapsed time, leaves the pid alone to decide, exactly as
# before. The slack absorbs the second-granularity of both clocks.
_pw_lock_owner_is_minter() {
  # Field 3 is the host's uptime at mint. A token that does not carry one —
  # anything this library did not mint, and anything minted where `ps` could
  # not answer — says nothing about start times, and the pid alone decides,
  # exactly as it did before.
  _pwn_rest=${1#*-}
  _pwn_rest=${_pwn_rest#*-}
  _pwn_mint_up=${_pwn_rest%%-*}
  case $_pwn_mint_up in
    '' | *[!0-9]*) return 0 ;;
  esac
  case ${_pwn_rest#*-} in
    *-*) ;;
    *) return 0 ;; # too few fields to be one of ours
  esac
  _pwn_elapsed=$(ps -o etimes= -p "$2" 2>/dev/null | tr -d ' ') || _pwn_elapsed=''
  case $_pwn_elapsed in
    '' | *[!0-9]*) return 0 ;;
  esac
  _pw_lock_uptime
  [ -n "$_pw_lock_uptime_out" ] || return 0
  # BOTH SIDES ARE AGES, NOT TIMES. The owner started this many seconds after
  # boot; the token was minted that many seconds after boot. No wall clock is
  # read on either side, so a clock that steps cannot move the answer.
  _pwn_started_up=$((_pw_lock_uptime_out - _pwn_elapsed))
  [ "$_pwn_started_up" -le "$((_pwn_mint_up + 2))" ] || return 1
  return 0
}

# pw_lock_owner <path> — print the holder's token (nothing, and no newline, for
# a path nobody holds).
pw_lock_owner() {
  [ "$#" -ge 1 ] && [ -n "${1:-}" ] || return 1
  _pwo_target=$(readlink "$1" 2>/dev/null) || _pwo_target=''
  printf '%s' "$_pwo_target"
}

# _pw_lock_work_path <lock> <kind> <token> — set _pw_lock_work_path_out to a
# private scratch path beside <lock>, for one caller's own use.
#
# THE ONLY PLACE A WORKING PATH IS BUILT, and it exists because two mistakes
# are easy to make once and impossible to make here.
#
# The token is SLUGGED. A lock's target is whatever some writer put there, and
# the release verbs are handed a token a caller read back off one — so a token
# carrying `../` is concatenated straight into a path that is then given to
# `mv` and `rm -f`. The break already slugged its claim path; nothing else did.
#
# The path is PER CALLER. The break's claim path is shared on purpose — one
# claim per dead owner IS the serialization point, and it is built elsewhere
# for exactly that reason. Every path built here is private scratch, so two
# callers doing the same work on the same lock must not land on the same name
# and delete each other's displaced link mid-release.
_pw_lock_work_path() {
  _pw_lock_slug "$3"
  PW_LOCK_SEQ=$((PW_LOCK_SEQ + 1))
  _pw_lock_work_path_out="$1#$2#$_pw_lock_slug_out.$$-$PW_LOCK_SEQ"
}

# _pw_lock_restore_or_keep <aside> <path> — put a displaced link back at <path>,
# or keep it where it is. 0 restored, 1 kept.
#
# THE RULE EVERY DISPLACEMENT IN THIS FILE OWES, AND THE ONLY PLACE IT IS
# WRITTEN. Moving a link aside to inspect it is how this library makes a
# removal exclusive, and every such move can find the path taken again before
# the link can go back. The link in hand is then the ONLY copy of a hold
# somebody may still be inside, so it is never deleted: it stays on disk under
# the aside name, the caller is told where, and the claim sweep collects it
# later. Litter is recoverable; a deleted lock is not.
#
# Every site that displaces a link calls this. Doing it by hand is how the same
# defect appeared at four sites and was fixed at one.
_pw_lock_restore_or_keep() {
  _pwk2_aside=$1
  _pwk2_path=$2
  _pwk2_back=$(readlink "$_pwk2_aside" 2>/dev/null) || _pwk2_back=''
  if [ -n "$_pwk2_back" ] && ln -s "$_pwk2_back" "$_pwk2_path" 2>/dev/null; then
    rm -f "$_pwk2_aside" 2>/dev/null || :
    return 0
  fi
  printf '%s\n' "lock-lib: $_pwk2_path was taken again before a displaced lock could be put back; the displaced lock is kept at $_pwk2_aside rather than deleted" >&2
  return 1
}

# _pw_lock_slug <token> — set _pw_lock_slug_out to a filename-safe rendering of
# a token that may have come from a foreign writer and may therefore contain
# anything but NUL. In-shell rather than `printf | tr | cut`: this runs inside
# the acquire spin, where three processes per attempt is the difference between
# a waiter that costs nothing and one that costs fifty spawns a second.
_pw_lock_slug() {
  _pwg_in=$1
  _pwg_out=''
  _pwg_n=0
  while [ -n "$_pwg_in" ] && [ "$_pwg_n" -lt 64 ]; do
    _pwg_c=${_pwg_in%"${_pwg_in#?}"}
    _pwg_in=${_pwg_in#?}
    _pwg_n=$((_pwg_n + 1))
    case $_pwg_c in
      [A-Za-z0-9._-]) _pwg_out="$_pwg_out$_pwg_c" ;;
      *) _pwg_out="${_pwg_out}_" ;;
    esac
  done
  _pw_lock_slug_out=$_pwg_out
}

# _pw_lock_publish <lock> <token> [<depth>] — create the link and take the
# hold. 0 held (PW_LOCK_TOKEN set), 1 the path was not won.
#
# THE REGISTRY ENTRY IS WRITTEN FIRST, because the signal handler releases what
# the registry names: between a create that has landed on disk and a registry
# that does not know about it, a signal leaks the lock until somebody breaks
# it. An entry for a create that then fails costs nothing — every release
# re-reads the link and unlinks only its own token, so an entry matching
# nothing does nothing — which is what makes writing it early the cheap side
# of the trade.
_pw_lock_publish() {
  _pwp_lock=$1
  _pwp_token=$2
  _pwp_depth=${3:-1}
  _pw_lock_store "$_pwp_lock" "$_pwp_token" "$_pwp_depth"
  if ln -s "$_pwp_token" "$_pwp_lock" 2>/dev/null \
    && [ "$(readlink "$_pwp_lock" 2>/dev/null)" = "$_pwp_token" ]; then
    PW_LOCK_TOKEN=$_pwp_token
    return 0
  fi
  # `ln -s target dir` files the link INSIDE a directory squatting the path and
  # still exits 0, so an unconfirmed create is not a hold. Drop the stray and
  # the bookkeeping together.
  # The stray only exists when a directory took the create, so ask before
  # spawning `rm`: on a contended lock this runs once per spin, and a process
  # per spin for a condition that is almost never true is the whole cost.
  [ ! -d "$_pwp_lock" ] || rm -f "$_pwp_lock/$_pwp_token" 2>/dev/null || :
  _pw_lock_store "$_pwp_lock" '' 0
  return 1
}

# _pw_lock_break <lock> <dead-token> <our-token> — replace a lock whose owner
# is gone. 0 the lock is now ours, 1 it is not (a peer is breaking it, a peer
# holds it, or the break lost a race and declined to guess).
_pw_lock_break() {
  _pwb_lock=$1
  _pwb_dead=$2
  _pwb_token=$3
  _pwb_depth=${4:-1}
  _pw_lock_slug "$_pwb_dead"
  _pwb_claim="$_pwb_lock#break#$_pw_lock_slug_out"
  # The CLAIM is owned by this process, whatever the lock itself will be owned
  # by. A detached token always reads alive, so a claim minted from one could
  # never be reclaimed: a breaker killed mid-break would leave the path
  # permanently unbreakable. The break is a live, in-process act, so the pid
  # naming it is the honest owner.
  _pw_lock_mint "$$"
  _pwb_claim_token=$_pw_lock_new_token

  if ! ln -s "$_pwb_claim_token" "$_pwb_claim" 2>/dev/null \
    || [ "$(readlink "$_pwb_claim" 2>/dev/null)" != "$_pwb_claim_token" ]; then
    # Either a peer is breaking this same owner — in which case waiting is
    # correct and there is nothing to do — or a breaker died holding the claim,
    # which would wedge the path forever. Reclaim only the second case, and
    # only by an ownership-verified rename: two reclaimers renaming the same
    # path cannot both find their own probe's target behind it, so only one
    # clears the claim and the other comes back on the next spin.
    _pwb_holder=$(readlink "$_pwb_claim" 2>/dev/null) || _pwb_holder=''
    if [ -n "$_pwb_holder" ] && ! pw_lock_owner_alive "$_pwb_holder"; then
      _pw_lock_work_path "$_pwb_claim" dead "$_pwb_claim_token"
      _pwb_aside=$_pw_lock_work_path_out
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
          _pw_lock_restore_or_keep "$_pwb_aside" "$_pwb_claim" || :
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

  # TAKE THE DEAD LINK BY RENAMING IT, and only then publish. The claim above
  # serializes breakers of one dead owner, and until this it was the ONLY thing
  # that did: two callers past it both removed the lock and both published, and
  # the second took the first's freshly minted link while both believed they
  # held it. Measured three times in three. A gate is a bad place for a single
  # point of failure when what it guards is a double grant, so this step is
  # exclusive on its own terms — a rename moves the link, and a second caller's
  # rename finds no source left to move.
  #
  # EVERY STEP HERE ACTS ON THE LINK, NEVER ON WHAT IT POINTS AT. That is why
  # the destination is a fresh path of this caller's own: a rename ONTO an
  # existing path whose link target is a directory files the source inside that
  # directory instead, which is how the lock once became unbreakable.
  _pw_lock_work_path "$_pwb_lock" taken "$_pwb_claim_token"
  _pwb_taken=$_pw_lock_work_path_out
  rm -f "$_pwb_taken" 2>/dev/null || :
  if ! mv "$_pwb_lock" "$_pwb_taken" 2>/dev/null; then
    if [ -L "$_pwb_lock" ] || [ -e "$_pwb_lock" ]; then
      # Still there and unmovable: the parent directory or the filesystem,
      # never a peer. Saying "busy" here would send the caller to wait out a
      # condition that does not clear.
      printf '%s\n' "lock-lib: cannot clear $_pwb_lock after its owner was found absent (parent unwritable or filesystem error)" >&2
      rm -f "$_pwb_claim" 2>/dev/null || :
      return 2
    fi
    # Gone instead: another breaker took the dead link first, and this caller
    # simply is not the one that took it.
    rm -f "$_pwb_claim" 2>/dev/null || :
    return 1
  fi
  if [ "$(readlink "$_pwb_taken" 2>/dev/null)" != "$_pwb_dead" ]; then
    # What moved was not the dead owner's link: the path changed hands between
    # the check and here. Put it back by RE-CREATING it, never by renaming it
    # back, for the reason the legacy clear gives — a rename lands on whatever
    # holds the path by then.
    _pw_lock_restore_or_keep "$_pwb_taken" "$_pwb_lock" || :
    rm -f "$_pwb_claim" 2>/dev/null || :
    return 1
  fi
  rm -f "$_pwb_taken" 2>/dev/null || :
  if _pw_lock_publish "$_pwb_lock" "$_pwb_token" "${_pwb_depth:-1}"; then
    rm -f "$_pwb_claim" 2>/dev/null || :
    return 0
  fi
  rm -f "$_pwb_claim" 2>/dev/null || :
  return 1
}

# _pw_lock_try_core <path> <owner-field> <probe> — one acquisition attempt, no
# waiting. <owner-field> becomes the token's leading field: this process's pid
# for an ordinary hold, the word `detached` for a hold with no owning process.
# <probe> 1 examines a holder and breaks it if its owner is gone; 0 reports
# busy without looking, which is what a spin does between strides.
_pw_lock_try_core() {
  _pwt_lock=$1
  _pwt_owner_field=$2
  _pwt_probe=$3
  # What this shell still owes on this path, carried in from the previous spin.
  # The registry record is gone by then — it had to be, or the reentrancy
  # branch below would keep matching a token no link carries — so the count has
  # to travel out of band or it is simply lost, and the first release then
  # unlinks while the outer sections are still inside.
  _pwt_owed=${4:-0}
  _pw_lock_probe_again=0
  _pw_lock_owed_depth=0
  _pw_lock_require_readlink || return 2

  if [ "$_pwt_owed" -gt 0 ]; then
    # Already counted on an earlier spin; counting again would inflate it.
    _pwt_depth=$_pwt_owed
  else
    _pwt_depth=1
  fi
  if [ "$_pwt_owed" -eq 0 ] && _pw_lock_lookup "$_pwt_lock"; then
    if [ "$(readlink "$_pwt_lock" 2>/dev/null)" = "$_pw_lock_token" ]; then
      _pw_lock_store "$_pwt_lock" "$_pw_lock_token" "$((_pw_lock_depth + 1))"
      PW_LOCK_TOKEN=$_pw_lock_token
      return 0
    fi
    # The registry says we hold it and the path disagrees: the lock was broken
    # or removed under us. Contend like anyone else — but KEEP THE DEPTH. The
    # nested releases this shell still owes have not gone anywhere, and
    # collapsing to 1 would make the first of them unlink while the outer
    # sections are still inside.
    _pwt_depth=$((_pw_lock_depth + 1))
    _pw_lock_store "$_pwt_lock" '' 0
  fi

  _pw_lock_mint "$_pwt_owner_field"
  _pwt_token=$_pw_lock_new_token

  # Only attempt the create when the path looks free. The create is the
  # exclusion, so attempting it blindly is correct but not free: on a contended
  # lock it is a process per spin for a create that cannot win.
  if [ ! -L "$_pwt_lock" ] && [ ! -e "$_pwt_lock" ]; then
    # `ln -s target dir` puts the link INSIDE a directory squatting the path
    # and still exits 0, so the create is confirmed before it is believed. An
    # unconfirmed create would report a lock this caller does not hold and send
    # it into its critical section holding nothing.
    _pw_lock_publish "$_pwt_lock" "$_pwt_token" "$_pwt_depth" && return 0
  fi

  # `-L` and not `-e` asks the right question: the lock IS the link, whatever
  # it points at, and `-e` follows it and reads false for a dangling one.
  if [ -L "$_pwt_lock" ]; then
    # Reading the owner costs a process, and an owner does not stop being alive
    # between one spin and the next. A spin that is not on a probe stride says
    # busy without asking, the way the code this replaces strided its own
    # staleness probe.
    if [ "$_pwt_probe" != 1 ]; then
      _pw_lock_owed_depth=$_pwt_depth
      return 1
    fi
    _pwt_owner=$(readlink "$_pwt_lock" 2>/dev/null) || _pwt_owner=''
    if [ -z "$_pwt_owner" ]; then
      # It vanished between the test and the read. Nothing is proven; the
      # caller's next attempt sees a settled path.
      _pw_lock_owed_depth=$_pwt_depth
      return 1
    fi
    if pw_lock_owner_alive "$_pwt_owner"; then
      _pw_lock_owed_depth=$_pwt_depth
      return 1
    fi
    _pw_lock_break "$_pwt_lock" "$_pwt_owner" "$_pwt_token" "$_pwt_depth"
    _pwt_rc=$?
    # A break that did not win found something in motion — a peer breaking the
    # same owner, or a claim it has just reclaimed — so the next spin looks
    # again rather than waiting out a stride for a situation that is changing.
    if [ "$_pwt_rc" -ne 0 ]; then
      _pw_lock_probe_again=1
      _pw_lock_owed_depth=$_pwt_depth
    fi
    return "$_pwt_rc"
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
  _pw_lock_publish "$_pwt_lock" "$_pwt_token" "$_pwt_depth" && return 0
  if [ ! -L "$_pwt_lock" ] && [ ! -e "$_pwt_lock" ]; then
    # An empty path after two failed creates is ambiguous: the store may be
    # unwritable, or two peers may simply have released in the gaps. Ask the
    # parent directly rather than concluding — under real contention the second
    # reading is the common one, and calling it a broken store aborts a budget
    # that would have succeeded.
    _pwt_parent=${_pwt_lock%/*}
    [ "$_pwt_parent" != "$_pwt_lock" ] || _pwt_parent=.
    [ -n "$_pwt_parent" ] || _pwt_parent=/
    if [ -d "$_pwt_parent" ] && [ -w "$_pwt_parent" ]; then
      _pw_lock_owed_depth=$_pwt_depth
      return 1
    fi
    printf '%s\n' "lock-lib: cannot create $_pwt_lock (parent unwritable or filesystem error)" >&2
    return 2
  fi
  _pw_lock_owed_depth=$_pwt_depth
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
  _pwq_owed=0
  while :; do
    # The first attempt always looks at the holder; after that only every
    # PW_LOCK_PROBE_EVERY-th one does. A holder's liveness cannot change faster
    # than the waiter can notice, and probing it every spin costs a process
    # fifty times a second for an answer that was the same last time.
    if [ "$_pwq_tries" -eq 0 ] \
      || [ "${_pw_lock_probe_again:-0}" -eq 1 ] \
      || [ $((_pwq_tries % PW_LOCK_PROBE_EVERY)) -eq 0 ]; then
      _pwq_probe=1
    else
      _pwq_probe=0
    fi
    _pw_lock_try_core "$_pwq_lock" "$_pwq_owner_field" "$_pwq_probe" "${_pwq_owed:-0}"
    _pwq_rc=$?
    _pwq_owed=${_pw_lock_owed_depth:-0}
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
  _pw_lock_path_ok pw_lock_try "${1:-}" || return 2
  _pw_lock_try_core "$1" "$$" 1
}

# pw_lock_acquire <path> [<max-tries>] — spin until held or the budget runs
# out. 0 held, 1 a live holder kept it for the whole budget, 2 a real error.
pw_lock_acquire() {
  _pw_lock_path_ok pw_lock_acquire "${1:-}" || return 2
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
  _pw_lock_path_ok pw_lock_try_detached "${1:-}" || return 2
  _pw_lock_try_core "$1" "detached-$$" 1
}

# pw_lock_acquire_detached <path> [<max-tries>] — the spinning form.
pw_lock_acquire_detached() {
  _pw_lock_path_ok pw_lock_acquire_detached "${1:-}" || return 2
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
  _pw_lock_path_ok pw_lock_acquire_for "${1:-}" || return 2
  case ${2:-} in
    '' | 0 | *[!0-9]*)
      printf '%s\n' "lock-lib: pw_lock_acquire_for needs a non-zero numeric owner pid" >&2
      return 2
      ;;
  esac
  # A shell that already holds this path cannot hand it to anybody: the hold it
  # would be giving away is the one it is standing in. Taking the reentrancy
  # branch here would report success, leave the lock owned by this shell after
  # all, and then drop the bookkeeping below — so the outer holder could no
  # longer release, and the lock would be wedged for good. Refuse instead, and
  # say which of the two mistakes it was.
  if _pw_lock_lookup "$1"; then
    printf '%s\n' "lock-lib: pw_lock_acquire_for cannot hand $1 to pid $2 — this shell already holds it, and a hold cannot be reassigned from inside its own critical section" >&2
    return 2
  fi
  _pw_lock_acquire_core "$1" "${3:-$PW_LOCK_MAX_TRIES}" "$2" || return $?
  # The hold belongs to the nominated process, not to this one, so it must not
  # sit in this shell's release registry: a trap here would drop a lock the
  # caller is still inside. The entry did its job — it covered the instant
  # between the create and the confirm — and the check above is what makes
  # dropping it safe, because it proves the entry is the one just made.
  _pw_lock_store "$1" '' 0
  return 0
}

# pw_lock_release <path> — give up one depth of this shell's hold, unlinking
# at the outermost. 0 released or deepened-down, 1 this shell does not hold it
# (including the case where the hold was broken underneath it), 2 the unlink
# failed.
pw_lock_release() {
  _pw_lock_path_ok pw_lock_release "${1:-}" || return 2
  _pwr_lock=$1
  _pw_lock_lookup "$_pwr_lock" || return 1
  if [ "$_pw_lock_depth" -gt 1 ]; then
    _pw_lock_store "$_pwr_lock" "$_pw_lock_token" "$((_pw_lock_depth - 1))"
    return 0
  fi
  _pwr_token=$_pw_lock_token
  # THE UNLINK COMES FIRST AND THE BOOKKEEPING AFTER, the mirror image of the
  # acquire: dropping the record first would open an instant where the link is
  # on disk and the armed handler no longer knows to release it, which is the
  # same leak, in the same window, on the way out.
  #
  # A holder whose lock was broken finds a stranger's token here and leaves it
  # alone, which is the whole reason the token exists.
  _pw_lock_take_link "$_pwr_lock" "$_pwr_token"
  _pwr_rc=$?
  if [ "$_pwr_rc" -eq 2 ]; then
    # Still ours and still on disk. Leave the hold recorded so the handler
    # tries again at exit rather than leaving a lock nothing will release.
    return 2
  fi
  _pw_lock_store "$_pwr_lock" '' 0
  return "$_pwr_rc"
}

# _pw_lock_take_link <lock> <token> — remove the lock, but only if it is this
# token's. 0 removed, 1 it is not this token's (including: already gone), 2 a
# real error.
#
# TWO STEPS, AND THE ORDER IS THE WHOLE POINT.
#
# First, look WITHOUT touching. A link that is not ours is the ordinary answer
# on a hold that was already broken, and it must cost no filesystem write at
# all: the rename below VACATES the path, so renaming before knowing whose the
# link was hands the path to anyone watching, in the common case, and the
# restore then has nowhere to put it back. That destroys the one copy of a live
# holder's lock through the verb that exists to protect it.
#
# Second, having seen our own token, take the link by renaming it to a path of
# this caller's own. That is the exclusive act — a second caller's rename finds
# no source — and it closes the window between the look and the removal: if the
# path changed hands in between, what moved is not ours, and the verify catches
# it.
#
# A restore that cannot land is NOT followed by deleting what it was holding.
# Someone took the freed path, so the link in hand is the only copy of a hold
# somebody may still be inside; it stays on disk beside the lock, named, and
# the caller is told. Litter is recoverable and a deleted lock is not.
_pw_lock_take_link() {
  _pwm_lock=$1
  _pwm_token=$2
  [ "$(readlink "$_pwm_lock" 2>/dev/null)" = "$_pwm_token" ] || return 1
  _pw_lock_work_path "$_pwm_lock" taken "$_pwm_token"
  _pwm_taken=$_pw_lock_work_path_out
  rm -f "$_pwm_taken" 2>/dev/null || :
  if ! mv "$_pwm_lock" "$_pwm_taken" 2>/dev/null; then
    if [ -L "$_pwm_lock" ] || [ -e "$_pwm_lock" ]; then
      return 2
    fi
    return 1
  fi
  if [ "$(readlink "$_pwm_taken" 2>/dev/null)" != "$_pwm_token" ]; then
    _pw_lock_restore_or_keep "$_pwm_taken" "$_pwm_lock" || :
    return 1
  fi
  rm -f "$_pwm_taken" 2>/dev/null || return 2
  return 0
}

# pw_lock_release_token <path> <token> — the cross-process release. A CLI that
# hands its caller a token on acquire takes it back here, and the unlink still
# happens only while the link is that token's. 0 released, 1 the lock is not
# that token's (including: already gone), 2 the unlink failed.
pw_lock_release_token() {
  _pw_lock_path_ok pw_lock_release_token "${1:-}" || return 2
  if [ -z "${2:-}" ]; then
    _pw_lock_usage pw_lock_release_token
    return 2
  fi
  _pw_lock_take_link "$1" "$2"
}

# _pw_lock_sweep_claims <lock> — remove the break claims and asides belonging to
# one lock. A breaker killed mid-break leaves one behind, and nothing else
# collects it: it is harmless to an acquire (a claim is reclaimed by its own
# owner-liveness) right up until the breaker's pid is recycled, after which it
# reads alive forever and the stale break for that lock stops working.
_pw_lock_sweep_claims() {
  case $- in
    *f*) _pwk_restore='set -f' ;;
    *) _pwk_restore='set +f' ;;
  esac
  set +f
  for _pwk_p in "$1"'#break#'* "$1"'#taken#'* "$1"'#legacy#'*; do
    # LINKS ONLY. Everything this library puts at these paths is a symlink, so
    # anything else there belongs to somebody else — and recursively deleting
    # somebody else's directory is not a thing a lock primitive does on an
    # operator's behalf, however well the name matches.
    [ -L "$_pwk_p" ] || continue
    rm -f "$_pwk_p" 2>/dev/null || :
  done
  $_pwk_restore
}

# pw_lock_break_force <path> — clear a lock WITHOUT proving ownership. This is
# the operator's escape hatch and the only way to recover a detached hold whose
# owner crashed, so it is deliberately unconditional; a caller that can prove
# ownership must use pw_lock_release or pw_lock_release_token instead. It also
# clears a DIRECTORY left at the path by the retired `mkdir` shape, which is
# what makes an in-place upgrade from that shape possible at all. 0 the path is
# clear, 2 something is there that this cannot safely remove.
pw_lock_break_force() {
  _pw_lock_path_ok pw_lock_break_force "${1:-}" || return 2
  _pw_lock_sweep_claims "$1"
  if [ -L "$1" ]; then
    rm -f "$1" 2>/dev/null || return 2
    return 0
  fi
  if [ -d "$1" ]; then
    rm -rf "$1" 2>/dev/null || return 2
    return 0
  fi
  # A regular file at a lock path is not a lock either, and an acquire refuses
  # to take the path over it. If the escape hatch refused it too, nothing in
  # the tree could clear it.
  if [ -e "$1" ]; then
    rm -f "$1" 2>/dev/null || return 2
  fi
  return 0
}

# pw_lock_clear_legacy <path> — clear a lock DIRECTORY left by the retired
# `mkdir` shape, and nothing else. 0 cleared, 1 there was no legacy directory
# to clear (including: a live lock is there), 2 the removal failed.
#
# A caller cannot do this with a test and pw_lock_break_force: the test and the
# removal are two steps, and a peer taking the path in between would have its
# LIVE lock deleted — a double grant out of a recovery path. The rename below
# is the claim: it moves whatever is at the path in one step, and what moved is
# then inspected before anything is removed.
pw_lock_clear_legacy() {
  _pw_lock_path_ok pw_lock_clear_legacy "${1:-}" || return 2
  [ ! -L "$1" ] || return 1
  [ -d "$1" ] || return 1
  _pw_lock_work_path "$1" legacy "$$"
  _pwc_aside=$_pw_lock_work_path_out
  rm -rf "$_pwc_aside" 2>/dev/null || :
  mv -f "$1" "$_pwc_aside" 2>/dev/null || return 1
  if [ -L "$_pwc_aside" ]; then
    # A peer's live lock, not the legacy directory probed. Put it back by
    # RE-CREATING the link, never by renaming it back: a rename lands whatever
    # is in its way, so the restore that exists to undo a mistake would destroy
    # a second peer that took the freed path in the meantime — the successor
    # clobber this whole family is built to prevent. `mv -n` is no answer
    # either: it reports success whether or not it moved. A create fails when
    # the path is taken, which is the answer this needs.
    _pw_lock_restore_or_keep "$_pwc_aside" "$1" || :
    return 1
  fi
  if [ ! -d "$_pwc_aside" ]; then
    # Neither the legacy directory nor a lock: not this verb's to remove, and
    # not something to move back over whatever holds the path now. Leave it
    # where it is and name where it went.
    printf '%s\n' "lock-lib: $1 changed shape during the legacy clear; what was there is now at $_pwc_aside" >&2
    return 2
  fi
  rm -rf "$_pwc_aside" 2>/dev/null || return 2
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
    # Unlink before forgetting, for the reason pw_lock_release gives: a second
    # signal landing inside this loop re-enters it, and a record dropped ahead
    # of its unlink is a lock the re-entry can no longer see.
    _pw_lock_take_link "$_pwx_path" "$_pwx_token" || :
    _pw_lock_store "$_pwx_path" '' 0
  done
  PW_LOCK_TOKEN=''
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
