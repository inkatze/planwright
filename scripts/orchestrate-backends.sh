#!/bin/sh
# orchestrate-backends.sh — host-backend AUTODETECTION, unattended SELECTION,
# and the attended two-seam PRESENTATION for /orchestrate (orchestration-fleet
# Task 2 + Task 10; D-3, D-9, D-12, REQ-B1.4, REQ-E1.2).
#
# This is the scripts-level realization of the Task 1 backend capability
# contract's advertisement mechanism (doctrine/backend-capability-contract.md,
# D-2): it reports which dispatch backends are actually PRESENT on the host,
# each with its advertised capability set, and makes the autonomous (no human
# to ask) backend pick in unattended mode. The attended present-and-ask flow
# lives in the /orchestrate skill, which calls `detect` for the candidate set
# and asks the operator — this script never silently picks for an attended run.
#
# Subcommands:
#   detect [pluggable-name...]
#       Print one TSV row per PRESENT backend, richest rung first:
#         backend<TAB>interactive<TAB>can_observe<TAB>can_steer_inflight<TAB>\
#         provides_attention_surface<TAB>supports_parallel<TAB>session_grade<TAB>\
#         overhead<TAB>hook_registration
#       The five advertised booleans are true|false|na (na = a capability that
#       is structurally inapplicable, distinct from an absent one); session_grade
#       is yes|no|deferred; overhead is the pinned cost-class enum
#       none|light|full-session|full-session+supervisor and hook_registration is
#       true|false (execution-backends REQ-A1.1, REQ-A1.8). `in-session` and
#       `print` are always present; `subagent` is present by default (the
#       harness-native runtime); `tmux` is present iff it resolves on PATH. Both
#       execution-backends rows now have dispatch support and are present iff
#       the installed CLI resolves on PATH: `headless-oneshot` (REQ-A1.2, its
#       dispatch support fleet-dispatch-headless.sh, execution-backends Task 3)
#       and `stream-json-persistent` (REQ-A1.3, the fleet-streamjson.sh
#       supervisor, Task 4). All four probes are overridable with
#       PLANWRIGHT_BACKEND_{SUBAGENT,TMUX,STREAM_JSON_PERSISTENT,HEADLESS_ONESHOT}
#       (1/0) so a host or test can force presence. Each pluggable-name arg is present iff a
#       `planwright-backend-<name>` adapter on PATH answers `advertise` with a
#       well-formed capability set; an absent or malformed adapter is reported
#       absent (fail-safe — a backend whose capabilities are unknown is never
#       advertised), a malformed advertise line additionally carrying a visible
#       diagnostic (REQ-A1.7, never a silent absence). A pluggable arg naming a
#       shipped backend, or a hostile/invalid name, is skipped.
#
#   select-unattended [--tmux-candidate] <configured>
#       Print the dispatch-time backend pick (execution-backends Task 5; D-8,
#       REQ-B1.1, REQ-B1.4, REQ-B1.5). The SEMANTIC value `full-session`
#       resolves to the richest PRESENT non-interactive session-grade rung via
#       the pinned ladder (REQ-A1.8: stream-json-persistent >
#       headless-oneshot), degrading past the session-grade rungs to subagent
#       then the always-present in-session terminal rung (a NOTE on stderr,
#       exit 0); tmux joins the candidate set only under --tmux-candidate (the
#       operator's tmux-context answer, passed by the config resolver), and the
#       manual `print` rung is never a candidate. An EXPLICIT LITERAL is
#       honored-or-halted: present, it is printed verbatim (interactive and
#       manual included — explicit config is the operator's standing answer,
#       never a silent pick); not advertised on the host, exit 6 with the
#       missing backend named on stderr and nothing on stdout (dispatch-time
#       ladders apply to semantic values only). Runtime failover stays
#       orchestrate-degrade.sh's logged one-rung descent.
#
#   present
#       Read detect-format TSV rows on stdin and render the TWO-SEAM
#       presentation the entry command shows an attended operator (Task 10;
#       D-9, D-12, REQ-E1.2, REQ-E1.5): picking a backend chooses only how
#       workers are hosted (the execution seam); the decision queue is the
#       default attention surface for every pick (the attention seam). Each
#       backend renders as one block, in input (richest-first) order, with an
#       execution-quality summary derived from its advertised set — never from
#       its name. An interactive backend's block carries the
#       detached-background-plumbing note (the tower can drive it as a detached
#       server nobody attaches to), so the approachable path is the default
#       presentation, not a fallback behind multiplexer fluency. A backend
#       advertising provides_attention_surface=true is marked as owning the
#       operator's surface and planwright's queue defers (--surface-provided,
#       D-13). present's stdin is detect's own output, so a malformed row is a
#       framework bug: it fails closed (exit 2, sanitized diagnostic), never
#       silently skips. Compose as:
#         orchestrate-backends.sh detect | orchestrate-backends.sh present
#
# Every backend token is treated as DATA: a pluggable name is validated against
# the anchored identifier charset before it is ever spliced into the
# `planwright-backend-<name>` command, so a hostile name is refused, never run.
#
# Exit codes: 0 success (including a full-session degrade past the
# session-grade rungs); 2 usage error (no/unknown subcommand, or a
# select-unattended configured argument that is empty or fails the identifier
# charset); 6 fail-closed halt (an explicitly configured literal not
# advertised on the host, REQ-B1.5 — the caller parks the dispatch to
# Awaiting input). No subcommand mutates any file.
#
# Portable POSIX sh + coreutils (bash 3.2 / BSD compatible): no eval, no gawk
# extensions, input treated as data only (REQ-K1.5).
set -u

# Pin the C locale so the charset checks below mean exactly their ASCII range
# on every host (defensive; mirrors the sibling scripts).
LC_ALL=C
export LC_ALL
unset CDPATH

# An invalid backend name is untrusted DATA: it must be stripped of non-printable
# bytes before it reaches a diagnostic, so an embedded escape sequence cannot
# drive the operator's terminal (doctrine/security-posture.md, "Echo
# discipline"). Sourced like the other framework callers (spec-validate.sh).
# shellcheck source=scripts/echo-safety.sh
. "$(dirname "$0")/echo-safety.sh"

# ---------------------------------------------------------------------------
# The advertised capability set of each shipped backend, verbatim from the
# contract table (doctrine/backend-capability-contract.md). Fields, in order:
# interactive can_observe can_steer_inflight provides_attention_surface
# supports_parallel session_grade overhead hook_registration
# (the 6->8 extension: execution-backends D-13, REQ-A1.1-A1.4, REQ-A1.8).
# Keep in lockstep with that table — the drift guard in
# tests/test-orchestrate-backends.sh fails CI on any divergence (REQ-A1.6).
# ---------------------------------------------------------------------------
caps_for() {
  case "$1" in
    tmux) echo "true true true false true yes full-session true" ;;
    stream-json-persistent) echo "false true true false true yes full-session+supervisor true" ;;
    headless-oneshot) echo "false false false false true yes full-session true" ;;
    subagent) echo "false false false false true no light false" ;;
    print) echo "false false false false na deferred none false" ;;
    in-session) echo "false na na false false no none false" ;;
    *) return 1 ;;
  esac
}

# A backend name that names one of the shipped six.
is_known() {
  case "$1" in
    tmux | stream-json-persistent | headless-oneshot | subagent | print | in-session) return 0 ;;
    *) return 1 ;;
  esac
}

# Anchored identifier charset for a pluggable backend name: lowercase alnum and
# hyphen, must start alnum, <=64 chars (mirrors the spec-id grammar). This runs
# BEFORE the name is used to build the adapter command, so a traversal, glob, or
# shell metacharacter is refused rather than interpolated.
valid_name() {
  case "$1" in
    '') return 1 ;;
    [!a-z0-9]*) return 1 ;;
    *[!a-z0-9-]*) return 1 ;;
  esac
  [ "${#1}" -le 64 ]
}

# Resolve an env override to presence. $1 = raw env value (possibly empty);
# $2 = default action when the value is empty/unrecognized:
#   yes -> present, no -> absent, tmux -> `command -v tmux`,
#   claude -> `command -v claude` (the installed-CLI probe).
env_present() {
  case "$1" in
    1 | true | TRUE | on | yes | YES) return 0 ;;
    0 | false | FALSE | off | no | NO) return 1 ;;
  esac
  case "$2" in
    yes) return 0 ;;
    no) return 1 ;;
    tmux) command -v tmux >/dev/null 2>&1 ;;
    claude) command -v claude >/dev/null 2>&1 ;;
  esac
}

# Is a shipped backend present on this host? Both execution-backends contract
# rows now have dispatch support, so both default to the installed-CLI probe:
# `headless-oneshot` (execution-backends Task 3: fleet-dispatch-headless.sh)
# and `stream-json-persistent` (Task 4: the fleet-streamjson.sh supervisor).
# The env overrides let tests (and an early-adopting host) force presence
# either way.
is_present() {
  case "$1" in
    in-session | print) return 0 ;;
    subagent) env_present "${PLANWRIGHT_BACKEND_SUBAGENT-}" yes ;;
    tmux) env_present "${PLANWRIGHT_BACKEND_TMUX-}" tmux ;;
    stream-json-persistent) env_present "${PLANWRIGHT_BACKEND_STREAM_JSON_PERSISTENT-}" claude ;;
    headless-oneshot) env_present "${PLANWRIGHT_BACKEND_HEADLESS_ONESHOT-}" claude ;;
    *) return 1 ;;
  esac
}

# A malformed advertise line fails closed WITH a visible diagnostic
# (execution-backends REQ-A1.7: never a silent absence). $1 = validated backend
# name (charset-checked by every caller before adapter_caps runs), $2 = reason.
# Only the name and the fixed reason text are echoed — never line content.
advertise_malformed() {
  printf '%s\n' "orchestrate-backends: planwright-backend-$1: malformed advertise line ($2); backend not selectable" >&2
  return 1
}

# The advertised set of a pluggable backend, obtained from its adapter. Echoes
# the eight validated fields — a legacy six-field line is accepted with the
# fail-safe defaults (hook_registration=false, overhead=full-session+supervisor,
# the most conservative class; execution-backends D-13) — or returns 1 when
# there is no adapter on PATH or its output is not a well-formed six- or
# eight-field capability set (the fail-safe absent case; a malformed line is
# additionally diagnosed via advertise_malformed). The advertise line is
# untrusted input (REQ-A1.9): first line only, length-bounded, and stripped of
# non-printable bytes BEFORE any parse, use, or echo.
adapter_caps() {
  ac_cmd="planwright-backend-$1"
  command -v "$ac_cmd" >/dev/null 2>&1 || return 1
  # The capture trusts the adapter process itself (a PATH-installed executable
  # the operator chose to ship — the adapter trust model): output is slurped
  # before the first-line/length handling below, and a hanging adapter blocks
  # the caller. The hygiene bounds below govern what is PARSED and ECHOED, not
  # the capture.
  ac_raw=$("$ac_cmd" advertise 2>/dev/null) || return 1
  # First line only.
  ac_line=''
  IFS= read -r ac_line <<EOF
$ac_raw
EOF
  # Length-bound the parsed line: an overlong line is refused, not
  # truncated-then-parsed.
  if [ "${#ac_line}" -gt 512 ]; then
    advertise_malformed "$1" "line exceeds 512 bytes"
    return 1
  fi
  # Strip control bytes before use or echo (REQ-A1.9): tabs are folded to
  # spaces first so a tab-separated line still tokenizes; the C0/DEL/C1 strip
  # then mirrors echo-safety's sanitize_printable range (high bytes 0xA0-0xFF
  # survive into tokens and are refused by the enum validation below, never
  # echoed — no diagnostic reproduces line content).
  ac_line=$(printf '%s' "$ac_line" | tr '\t' ' ' | tr -d '\000-\037\177\200-\237')
  case "$ac_line" in
    *[!\ ]*) ;;
    *)
      advertise_malformed "$1" "empty advertise line"
      return 1
      ;;
  esac
  # Tokenize: a well-formed set is six or eight known tokens (6->8
  # back-compatible grammar; seven or nine-plus is malformed). Arity is judged
  # on the POST-strip tokens — a token stripped to nothing drops out of the
  # count, degrading conservatively (a 7th all-control-byte token parses as a
  # legacy six-field line taking the most conservative defaults). The read
  # targets are `f_`-prefixed so this helper never clobbers a caller's loop
  # variable (`p`, `rung`) — sh has no lexical scope.
  f_i='' f_o='' f_s='' f_a='' f_p='' f_g='' f_ov='' f_hr='' f_rest=''
  read -r f_i f_o f_s f_a f_p f_g f_ov f_hr f_rest <<EOF
$ac_line
EOF
  if [ -n "$f_rest" ]; then
    advertise_malformed "$1" "expected 6 or 8 whitespace-separated fields, got 9 or more"
    return 1
  fi
  if [ -n "$f_ov" ] && [ -z "$f_hr" ]; then
    advertise_malformed "$1" "expected 6 or 8 whitespace-separated fields, got 7"
    return 1
  fi
  for f in "$f_i" "$f_o" "$f_s" "$f_a" "$f_p"; do
    case "$f" in
      true | false | na) ;;
      *)
        advertise_malformed "$1" "invalid capability token"
        return 1
        ;;
    esac
  done
  case "$f_g" in
    yes | no | deferred) ;;
    *)
      advertise_malformed "$1" "invalid session_grade token"
      return 1
      ;;
  esac
  if [ -z "$f_ov" ]; then
    # Legacy six-field line: fail-safe defaults (D-13).
    f_ov='full-session+supervisor'
    f_hr='false'
  else
    case "$f_ov" in
      none | light | full-session | full-session+supervisor) ;;
      *)
        advertise_malformed "$1" "invalid overhead class"
        return 1
        ;;
    esac
    case "$f_hr" in
      true | false) ;;
      *)
        advertise_malformed "$1" "invalid hook_registration token"
        return 1
        ;;
    esac
  fi
  echo "$f_i $f_o $f_s $f_a $f_p $f_g $f_ov $f_hr"
}

# Echo the advertised set of a backend IF it is present, else return 1. Handles
# both shipped backends (presence probe + static caps) and pluggable ones
# (adapter presence IS backend presence).
resolve_caps() {
  if is_known "$1"; then
    is_present "$1" || return 1
    caps_for "$1"
  else
    valid_name "$1" || return 1
    adapter_caps "$1"
  fi
}

# Unattended-eligible: an autonomous tower may silently pick it. True iff the
# advertised set has interactive=false (never strand a run waiting on a human)
# AND session_grade!=deferred (excludes the manual `print` rung, whose spawn is
# deferred to a human). Reads the eight-field caps string on $1 (fields 1 and
# 6; the trailing fields land in f_rest and are not consulted).
eligible() {
  f_i='' f_g='' f_rest=''
  read -r f_i f_o f_s f_a f_p f_g f_rest <<EOF
$1
EOF
  [ "$f_i" = false ] && [ "$f_g" != deferred ]
}

# Print one detect TSV row: $1 backend, $2 eight-field caps string. Read targets
# are `f_`-prefixed so this helper never clobbers a caller's loop variable.
emit_row() {
  er_b=$1
  read -r f_i f_o f_s f_a f_p f_g f_ov f_hr f_rest <<EOF
$2
EOF
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$er_b" "$f_i" "$f_o" "$f_s" "$f_a" "$f_p" "$f_g" "$f_ov" "$f_hr"
}

cmd_detect() {
  # Richest rung first, per the contract's pinned ladder ordering (REQ-A1.8):
  # tmux, the two execution-backends session-grade rungs, then advertised
  # pluggables (arg order), the shipped autonomous rung, the terminal rung, and
  # the manual rung.
  is_present tmux && emit_row tmux "$(caps_for tmux)"
  is_present stream-json-persistent \
    && emit_row stream-json-persistent "$(caps_for stream-json-persistent)"
  is_present headless-oneshot && emit_row headless-oneshot "$(caps_for headless-oneshot)"
  seen=' '
  for p in "$@"; do
    is_known "$p" && continue
    if ! valid_name "$p"; then
      printf '%s\n' "orchestrate-backends: ignoring invalid backend name: $(sanitize_printable "$p" "(unprintable name)")" >&2
      continue
    fi
    case "$seen" in
      *" $p "*) continue ;;
    esac
    seen="$seen$p "
    if ! caps=$(adapter_caps "$p"); then
      echo "orchestrate-backends: no usable adapter (absent, crashed, or malformed) for pluggable backend: $p" >&2
      continue
    fi
    emit_row "$p" "$caps"
  done
  is_present subagent && emit_row subagent "$(caps_for subagent)"
  emit_row in-session "$(caps_for in-session)"
  emit_row print "$(caps_for print)"
  return 0
}

cmd_select_unattended() {
  # Usage: select-unattended [--tmux-candidate] <configured>. The flag is the
  # operator's tmux-context answer (execution-backends D-8): it adds tmux to
  # the FULL-SESSION candidate set only — it never rescues an explicit literal
  # and never widens anything else. Exactly one positional after the flag;
  # missing OR extra args fail closed (exit 2) rather than being silently
  # ignored, so a caller's mistake surfaces instead of being masked.
  su_tmux_candidate=0
  if [ "${1-}" = "--tmux-candidate" ]; then
    su_tmux_candidate=1
    shift
  fi
  if [ "$#" -ne 1 ]; then
    echo "usage: orchestrate-backends.sh select-unattended [--tmux-candidate] <configured>" >&2
    return 2
  fi
  configured=${1-}
  if [ -z "$configured" ]; then
    echo "usage: orchestrate-backends.sh select-unattended [--tmux-candidate] <configured>" >&2
    return 2
  fi

  # The `full-session` SEMANTIC value (execution-backends D-8, REQ-B1.1,
  # REQ-B1.4): resolve to the richest PRESENT non-interactive session-grade
  # rung via the pinned ladder ordering (REQ-A1.8) — tmux only when the
  # operator's tmux-context answer admitted it as a candidate — degrading past
  # the session-grade rungs to today's behavior (subagent, then the
  # always-present in-session terminal rung). Never the manual `print` rung,
  # and never a silently-chosen interactive backend: without the flag the
  # interactive rung is simply not a candidate. Runtime failover stays a
  # separate mechanism (orchestrate-degrade.sh's logged one-rung descent).
  if [ "$configured" = full-session ]; then
    if [ "$su_tmux_candidate" -eq 1 ] && is_present tmux; then
      printf '%s\n' tmux
      return 0
    fi
    for rung in stream-json-persistent headless-oneshot; do
      if is_present "$rung"; then
        printf '%s\n' "$rung"
        return 0
      fi
    done
    for rung in subagent in-session; do
      if is_present "$rung"; then
        echo "NOTE: no non-interactive session-grade backend is advertised on this host (tmux is session-grade but joins the candidate set only when the tmux-context ask admits it); 'full-session' degraded to '$rung' (capability, never safety)." >&2
        printf '%s\n' "$rung"
        return 0
      fi
    done
    # in-session is always present, so this is an unreachable fail-closed guard.
    echo "orchestrate-backends: no eligible backend (the in-session terminal rung was unavailable)" >&2
    return 1
  fi

  # An EXPLICIT LITERAL (shipped or pluggable). A pluggable configured name
  # must be a valid identifier before it reaches the adapter command; a hostile
  # name is a usage error, not a silent degrade.
  if ! is_known "$configured" && ! valid_name "$configured"; then
    printf '%s\n' "orchestrate-backends: invalid backend name: $(sanitize_printable "$configured" "(unprintable name)")" >&2
    return 2
  fi

  # Honored-or-halted (REQ-B1.5): an explicit literal is the operator's
  # standing answer — present, it is honored verbatim (interactive and manual
  # rungs included; an explicit pick is never a *silent* one); not advertised
  # on the host, it FAILS CLOSED with the missing backend named, never a
  # substitute. Dispatch-time degradation ladders apply to semantic values
  # only, a declared narrowing of orchestration-fleet REQ-B1.4's
  # degrade-on-absence clause.
  if resolve_caps "$configured" >/dev/null; then
    printf '%s\n' "$configured"
    return 0
  fi
  printf '%s\n' "orchestrate-backends: configured backend '$configured' is not advertised on this host; halting fail-closed (REQ-B1.5) — never a silent substitute. Remedy: install/enable the backend or change dispatch_backend." >&2
  return 6
}

# Render one backend's presentation block from its validated nine fields.
# $1..$9 = backend interactive can_observe can_steer_inflight
# provides_attention_surface supports_parallel session_grade overhead
# hook_registration. The summary is derived from the advertised set only
# (adapt-to-advertised, never name-keyed). The overhead class renders on every
# block (the smallest-sufficient-rung input an operator weighs);
# hook_registration is liveness plumbing, consumed by fleet-liveness, and is
# deliberately not rendered.
emit_block() {
  pb_feats=''
  pb_add() {
    if [ -z "$pb_feats" ]; then pb_feats=$1; else pb_feats="$pb_feats, $1"; fi
  }
  [ "$2" = true ] && pb_add "interactive"
  [ "$3" = true ] && pb_add "observe in-flight"
  [ "$4" = true ] && pb_add "steer in-flight"
  [ "$6" = true ] && pb_add "parallel workers"
  case "$7" in
    yes) pb_add "session-grade workers" ;;
    deferred) pb_add "manual dispatch (the launch command is printed for you to paste)" ;;
  esac
  [ -n "$pb_feats" ] \
    || pb_feats="synchronous, in the tower's own session (no parallel, no in-flight observe/steer)"
  printf '* %s: %s\n' "$1" "$pb_feats"
  printf '    overhead: %s\n' "$8"
  if [ "$5" = true ]; then
    printf '    attention: provides its own attention surface; planwright defers its decision queue to it (--surface-provided)\n'
  else
    printf '    attention: planwright decision queue (default)\n'
  fi
  if [ "$2" = true ]; then
    printf '    plumbing: the tower can drive this backend as a detached background server nobody attaches to; attaching is optional, never required\n'
  fi
}

cmd_present() {
  # No positionals: present reads detect rows on stdin only. A stray argument
  # is a caller mistake and fails closed rather than being silently ignored.
  if [ "$#" -ne 0 ]; then
    echo "usage: orchestrate-backends.sh detect [...] | orchestrate-backends.sh present" >&2
    return 2
  fi
  pr_input=$(cat)
  if [ -z "$pr_input" ]; then
    echo "orchestrate-backends: present expects detect rows on stdin (detect always emits rows)" >&2
    return 2
  fi

  # Validate every row BEFORE rendering anything: stdin is our own detect
  # output, so any malformed row means a broken producer (or a hand-corrupted
  # pipe) and the whole presentation is untrustworthy — fail closed, emit
  # nothing (no partial surface an operator could act on).
  #
  # Strict field-count guard first: TAB is IFS whitespace, so the token split
  # below collapses consecutive tabs (an empty field) and could re-align a
  # hand-corrupted row into nine valid-looking tokens. A well-formed detect
  # row has exactly eight tabs; anything else fails closed here.
  pr_tab=$(printf '\t')
  while IFS= read -r pr_line; do
    pr_tabs=$(printf '%s' "$pr_line" | tr -cd "$pr_tab")
    if [ "${#pr_tabs}" -ne 8 ]; then
      # Show at most the first field, capped: a zero-tab line has no field
      # boundary to strip at, and an uncapped echo would reproduce an
      # arbitrarily long corrupted line in the diagnostic.
      pr_show=$(printf '%.64s' "${pr_line%%"$pr_tab"*}")
      printf '%s\n' "orchestrate-backends: present: malformed detect row: $(sanitize_printable "$pr_show" "(unprintable name)")" >&2
      return 2
    fi
  done <<EOF
$pr_input
EOF
  while IFS="$pr_tab" read -r p_b p_i p_o p_s p_a p_p p_g p_ov p_hr p_rest; do
    if ! valid_name "$p_b" || [ -n "$p_rest" ]; then
      printf '%s\n' "orchestrate-backends: present: malformed detect row: $(sanitize_printable "$p_b" "(unprintable name)")" >&2
      return 2
    fi
    for f in "$p_i" "$p_o" "$p_s" "$p_a" "$p_p"; do
      case "$f" in
        true | false | na) ;;
        *)
          printf '%s\n' "orchestrate-backends: present: malformed capability field in row: $(sanitize_printable "$p_b" "(unprintable name)")" >&2
          return 2
          ;;
      esac
    done
    case "$p_g" in
      yes | no | deferred) ;;
      *)
        printf '%s\n' "orchestrate-backends: present: malformed session_grade in row: $(sanitize_printable "$p_b" "(unprintable name)")" >&2
        return 2
        ;;
    esac
    case "$p_ov" in
      none | light | full-session | full-session+supervisor) ;;
      *)
        printf '%s\n' "orchestrate-backends: present: malformed overhead in row: $(sanitize_printable "$p_b" "(unprintable name)")" >&2
        return 2
        ;;
    esac
    case "$p_hr" in
      true | false) ;;
      *)
        printf '%s\n' "orchestrate-backends: present: malformed hook_registration in row: $(sanitize_printable "$p_b" "(unprintable name)")" >&2
        return 2
        ;;
    esac
  done <<EOF
$pr_input
EOF

  # The two-seam framing (D-12): the pick below is the execution seam only;
  # the attention seam is independent and defaults to the decision queue.
  printf 'Execution backends present on this host, richest rung first. Picking one\n'
  printf 'chooses only how workers are hosted (the execution seam). What you watch\n'
  printf 'is independent: the decision queue is the default attention surface for\n'
  printf 'every pick; a backend that provides its own surface is marked below and\n'
  printf 'deferred to.\n\n'
  while IFS="$pr_tab" read -r p_b p_i p_o p_s p_a p_p p_g p_ov p_hr p_rest; do
    emit_block "$p_b" "$p_i" "$p_o" "$p_s" "$p_a" "$p_p" "$p_g" "$p_ov" "$p_hr"
  done <<EOF
$pr_input
EOF
  return 0
}

# caps <backend>: print the eight-field advertised capability set for one
# backend (interactive can_observe can_steer_inflight provides_attention_surface
# supports_parallel session_grade overhead hook_registration) — the read
# accessor a capability-gated
# consumer (Task 5's peer-pane /context corroboration reads can_observe) asks
# instead of re-deriving the contract table (avoids the duplication the
# knob-resolver-dedup observation warns against). Presence-AGNOSTIC for a
# shipped backend: advertisement is a static property of the backend TYPE, not
# of whether it is running on this host, so the gate can ask "does this backend
# type observe in-flight" without forcing the backend present. A pluggable name
# still resolves through its adapter (the adapter's presence IS the backend's).
cmd_caps() {
  if [ "$#" -ne 1 ]; then
    echo "usage: orchestrate-backends.sh caps <backend>" >&2
    return 2
  fi
  cp_b=$1
  if is_known "$cp_b"; then
    caps_for "$cp_b"
    return 0
  fi
  if ! valid_name "$cp_b"; then
    printf '%s\n' "orchestrate-backends: invalid backend name: $(sanitize_printable "$cp_b" "(unprintable name)")" >&2
    return 2
  fi
  if ! cp_caps=$(adapter_caps "$cp_b"); then
    echo "orchestrate-backends: no usable adapter (absent, crashed, or malformed) for pluggable backend: $cp_b" >&2
    return 1
  fi
  printf '%s\n' "$cp_caps"
}

sub=${1-}
[ "$#" -gt 0 ] && shift
case "$sub" in
  detect) cmd_detect "$@" ;;
  select-unattended) cmd_select_unattended "$@" ;;
  present) cmd_present "$@" ;;
  caps) cmd_caps "$@" ;;
  '' | help | -h | --help)
    echo "usage: orchestrate-backends.sh {detect [pluggable-name...] | select-unattended [--tmux-candidate] <configured> | present | caps <backend>}" >&2
    exit 2
    ;;
  *)
    printf '%s\n' "orchestrate-backends: unknown subcommand: $(sanitize_printable "$sub" "(unprintable)")" >&2
    exit 2
    ;;
esac
