# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154 # prog and script_dir are the sourcing script's; MC_FORMAT is read there
# mc-lib.sh — helpers mission control's runtime scripts share (sourced, never
# executed). The sourcing script sets `prog` and `script_dir` and has sourced
# echo-safety.sh first.
#
# Runtime state (watcher records, source snapshots, the budget file, wake
# targets) lives under the plugin data home, in the fleet home
# scripts/fleet-state.sh resolves: <fleet-home>/mission-control/<program>/.
# Events live in the attention store beside it:
# <fleet-home>/attention/mission-control/<program>/. Neither is the program
# home, which holds work product only.
#
# Portable bash 3.2 / BSD tooling.

MC_FORMAT=1

mc_fail() {
  printf '%s\n' "$prog: $1" >&2
  exit 1
}
mc_usage_fail() {
  printf '%s\n' "$prog: $1" >&2
  exit 2
}

mc_valid_program() {
  [ "${#1}" -le 64 ] || return 1
  case $1 in
    "" | [!a-z]* | *[!a-z0-9-]* | *- | *--*) return 1 ;;
  esac
}
mc_valid_kebab() {
  case $1 in
    "" | [!a-z0-9]* | *[!a-z0-9-]*) return 1 ;;
  esac
}
# A worker handle, the fleet field grammar.
mc_valid_handle() {
  [ "${#1}" -le 128 ] || return 1
  case $1 in
    "" | -* | . | .. | *[!A-Za-z0-9._=@:-]*) return 1 ;;
  esac
}
# A whole number with no leading zero: shell arithmetic would read one as
# octal.
mc_valid_uint() {
  case $1 in
    "" | *[!0-9]* | 0?*) return 1 ;;
  esac
  [ "${#1}" -le 12 ]
}
# Text with no C0 or DEL byte. A byte in the C1 range is let through, since
# it is also a UTF-8 continuation byte; every reader strips C1 on the way to
# a terminal (sanitize_printable, mc_clean).
mc_valid_text() {
  case $1 in
    *[[:cntrl:]]*) return 1 ;;
  esac
}

# mc_seconds <cadence>: a positive count of s, m, h or d, in seconds.
mc_seconds() {
  ms_n=${1%[smhd]}
  ms_u=${1#"$ms_n"}
  mc_valid_uint "$ms_n" || return 1
  [ "$ms_n" -gt 0 ] || return 1
  case $ms_u in
    s) printf '%s\n' "$ms_n" ;;
    m) printf '%s\n' $((ms_n * 60)) ;;
    h) printf '%s\n' $((ms_n * 3600)) ;;
    d) printf '%s\n' $((ms_n * 86400)) ;;
    *) return 1 ;;
  esac
}

mc_now() { date +%s; }

# mc_now_arg <raw>: NOW set to <raw>, an epoch, or to the clock when empty.
mc_now_arg() {
  if [ -n "$1" ]; then
    mc_valid_uint "$1" || mc_usage_fail "--now takes an epoch"
    NOW=$1
  else
    NOW=$(mc_now)
  fi
}

# mc_require_program <p>: exit 2 on a name outside the grammar, 3 unless the
# program is configured, 1 when the program list cannot be read. The runner
# exports PLANWRIGHT_MC_CHECKED=<p> to the scripts a pass starts, after
# checking once itself.
mc_require_program() {
  mc_valid_program "$1" || mc_usage_fail "invalid program name '$(sanitize_printable "$1")'"
  [ "${PLANWRIGHT_MC_CHECKED:-}" != "$1" ] || return 0
  mrp_list=$(/bin/bash "$script_dir/mc-program.sh" list) || mc_fail "cannot list the configured programs"
  case "
$mrp_list
" in
    *"
$1
"*) return 0 ;;
  esac
  printf '%s\n' "$prog: program '$1' is not configured" >&2
  exit 3
}

# mc_gate <mechanism>: the fleet daemon gate (scripts/fleet-daemon-gate.sh).
# 0 open; 1 paused; 2 blocked by a broken install or an invalid shared
# overlay, the gate's exit kept in MC_GATE_RC. Fails closed either way.
mc_gate() {
  /bin/sh "$script_dir/fleet-daemon-gate.sh" "$1" >/dev/null 2>&1
  MC_GATE_RC=$?
  case $MC_GATE_RC in
    0) return 0 ;;
    1) return 1 ;;
  esac
  return 2
}
# mc_gate_or_exit <mechanism>: print `paused` and exit 0 while paused, print
# `blocked<TAB><exit>` and exit 1 while blocked.
mc_gate_or_exit() {
  mc_gate "$1" && return 0
  if [ "$MC_GATE_RC" -eq 1 ]; then
    printf 'paused\n'
    exit 0
  fi
  printf 'blocked\t%s\n' "$MC_GATE_RC"
  printf '%s\n' "$prog: the fleet daemon gate exited $MC_GATE_RC (an invalid shared overlay or a broken install)" >&2
  exit 1
}

# mc_cadence_factor <rung>: every cadence doubles at any rung above normal.
mc_cadence_factor() {
  if [ "$1" = normal ]; then printf '1\n'; else printf '2\n'; fi
}

mc_cost_rank() {
  case $1 in
    low) printf '1\n' ;;
    medium) printf '2\n' ;;
    high) printf '3\n' ;;
    *) printf '9\n' ;;
  esac
}

# mc_format_ok <file>: the store opens with this format's `format` line.
mc_format_ok() {
  [ -f "$1" ] && [ -r "$1" ] || return 1
  F=$MC_FORMAT awk -F '\t' 'NR == 1 { ok = ($1 == "format" && $2 == ENVIRON["F"]) } END { exit !ok }' "$1"
}

# mc_file_rung <budget-file>: the rung the budget file records; fails on a
# missing file or an unknown format.
mc_file_rung() {
  mc_format_ok "$1" || return 1
  mfr=$(awk -F '\t' '$1 == "rung" { print $2; exit }' "$1")
  [ -n "$mfr" ] || return 1
  printf '%s\n' "$mfr"
}

# mc_resolve_script <relative> <program>: the absolute path of a catalog
# entry's script, looked for under the planwright core root (the root the
# catalogs' core seed comes from) and then under each of the program's
# repositories in order. The path grammar is checked first: relative, no
# `..` segment, no leading `-`, a conservative charset.
mc_resolve_script() {
  case $1 in
    "" | /* | -* | *[!A-Za-z0-9._/-]* | .. | ../* | */.. | */../*) return 1 ;;
  esac
  mrs_core=$(/bin/bash "$script_dir/resolve-overlay-root.sh" core 2>/dev/null) || mrs_core=""
  if [ -n "$mrs_core" ] && [ -f "$mrs_core/$1" ]; then
    printf '%s\n' "$mrs_core/$1"
    return 0
  fi
  mrs_repos=$(/bin/bash "$script_dir/mc-program.sh" get "$2" repositories 2>/dev/null) || return 1
  while IFS= read -r mrs_repo; do
    [ -n "$mrs_repo" ] || continue
    if [ -f "$mrs_repo/$1" ]; then
      printf '%s\n' "$mrs_repo/$1"
      return 0
    fi
  done <<EOF
$mrs_repos
EOF
  return 1
}

# mc_clean: stdin to stdout with every byte that is neither printable nor a
# tab dropped, for a store read back to a terminal.
mc_clean() { awk '{ gsub(/[^[:print:]\t]/, ""); print }'; }

mc_fleet_home() {
  mfh=$(/bin/sh "$script_dir/fleet-state.sh" root 2>/dev/null) && [ -n "$mfh" ] || return 1
  printf '%s\n' "$mfh"
}

# mc_runtime <program>: the program's runtime directory, created.
mc_runtime() {
  mr_home=$(mc_fleet_home) || return 1
  mr_dir="$mr_home/mission-control/$1"
  mkdir -p "$mr_dir" 2>/dev/null || return 1
  printf '%s\n' "$mr_dir"
}

# mc_event_store <program>: the program's event directory in the attention
# store, created.
mc_event_store() {
  me_home=$(mc_fleet_home) || return 1
  me_dir="$me_home/attention/mission-control/$1"
  mkdir -p "$me_dir/events" "$me_dir/marks" 2>/dev/null || return 1
  printf '%s\n' "$me_dir"
}

mc_event() { /bin/bash "$script_dir/mc-event.sh" "$@"; }

# mc_quote <word>: the word single-quoted for a shell, or failure when it
# carries a single quote or a control byte.
mc_quote() {
  case $1 in
    *"'"* | *[[:cntrl:]]*) return 1 ;;
  esac
  printf "'%s'" "$1"
}

# mc_write <file>: stdin to <file> through a sibling temporary and a rename,
# so a reader sees the old file or the new one, never a torn one.
mc_write() {
  mw_tmp=$(mktemp "$1.XXXXXX") || return 1
  if cat >"$mw_tmp" && mv -f "$mw_tmp" "$1"; then
    return 0
  fi
  rm -f "$mw_tmp"
  return 1
}

# mc_upsert <file> <key> [<line>]: rewrite a key<TAB>... store with every
# line for <key> dropped and <line> added. A store that exists but cannot be
# read fails rather than being replaced. The caller holds the lock.
mc_upsert() {
  mu_kept=""
  if [ -e "$1" ]; then
    mu_kept=$(K=$2 awk -F '\t' '$1 != ENVIRON["K"]' "$1") || return 1
  fi
  {
    [ -z "$mu_kept" ] || printf '%s\n' "$mu_kept"
    [ -z "${3:-}" ] || printf '%s\n' "$3"
  } | mc_write "$1"
}

# mc_lock / mc_unlock: the fleet's named lock, held for this shell, waited
# for up to about ten seconds.
MC_LOCK_TOKEN=""
mc_lock() {
  ml_try=0
  while [ "$ml_try" -lt 100 ]; do
    MC_LOCK_TOKEN=$(/bin/sh "$script_dir/fleet-state.sh" lock --owner-pid "$$" 2>/dev/null)
    ml_rc=$?
    [ "$ml_rc" -ne 0 ] || return 0
    [ "$ml_rc" -eq 1 ] || return 1
    ml_try=$((ml_try + 1))
    sleep 0.1 2>/dev/null || sleep 1
  done
  return 1
}
mc_unlock() {
  [ -n "$MC_LOCK_TOKEN" ] || return 0
  /bin/sh "$script_dir/fleet-state.sh" unlock "$MC_LOCK_TOKEN" >/dev/null 2>&1
  MC_LOCK_TOKEN=""
}

# mc_knob <key> <parser>: the highest layer's value of <key> that
# `<parser> <raw>` accepts, printed as the parser prints it. An invalid
# adopter or machine-local value is warned about and the next lower layer
# read, the policy scripts/mc-program.sh applies to a program's keys; an
# invalid repo-tracked or core value, or a key no layer sets, fails.
mc_knob() {
  mk_lines=$(/bin/sh "$script_dir/config-get.sh" --layers "$1" 2>/dev/null)
  mk_rc=$?
  case $mk_rc in
    0) ;;
    3)
      printf '%s\n' "$prog: $1 is not set (broken install)" >&2
      return 1
      ;;
    *)
      printf '%s\n' "$prog: $1: the config read failed (config-get.sh exit $mk_rc)" >&2
      return 1
      ;;
  esac
  mk_rev=$(printf '%s\n' "$mk_lines" | awk '{ l[NR] = $0 } END { for (i = NR; i > 0; i--) print l[i] }')
  while IFS= read -r mk_line; do
    [ -n "$mk_line" ] || continue
    mk_layer=${mk_line%%	*}
    mk_raw=${mk_line#*	}
    if mk_out=$("$2" "$mk_raw"); then
      printf '%s\n' "$mk_out"
      return 0
    fi
    case $mk_layer in
      adopter | machine-local)
        printf '%s\n' "$prog: warning: the $mk_layer value of $1 is invalid ('$(sanitize_printable "$mk_raw")'); degrading to the next lower layer" >&2
        ;;
      *)
        printf '%s\n' "$prog: $1: invalid $mk_layer value '$(sanitize_printable "$mk_raw")'" >&2
        return 1
        ;;
    esac
  done <<EOF
$mk_rev
EOF
  printf '%s\n' "$prog: $1 is not set (broken install)" >&2
  return 1
}

# mc_map <raw>: an inline {key: value, ...} map to key<TAB>value lines, each
# key and value unquoted as scripts/mc-program.sh reads a map; fails on
# anything else, a control byte included.
mc_map() {
  RAW=$1 awk 'BEGIN {
    r = ENVIRON["RAW"]
    if (r ~ /[[:cntrl:]]/) exit 1
    sub(/^[ ]+/, "", r); sub(/[ ]+$/, "", r)
    if (r !~ /^\{.*\}$/) exit 1
    r = substr(r, 2, length(r) - 2)
    if (r ~ /^[ ]*$/) exit 0
    if (r ~ /[][{}]/) exit 1
    n = split(r, a, ",")
    for (i = 1; i <= n; i++) {
      m = a[i]; sub(/^[ ]+/, "", m); sub(/[ ]+$/, "", m)
      if (m == "") { if (i == n) continue; exit 1 }
      p = index(m, ":")
      if (!p) exit 1
      k = substr(m, 1, p - 1); v = substr(m, p + 1)
      sub(/[ ]+$/, "", k); sub(/^[ ]+/, "", v)
      if (k ~ /^".*"$/) k = substr(k, 2, length(k) - 2)
      if (v ~ /^".*"$/) v = substr(v, 2, length(v) - 2)
      if (k == "" || v == "") exit 1
      print k "\t" v
    }
  }'
}

# Parsers for mc_knob: print the value when it is valid.
mc_parse_cadence() {
  mc_seconds "$1" >/dev/null || return 1
  printf '%s\n' "$1"
}
mc_parse_uint() {
  mc_valid_uint "$1" || return 1
  printf '%s\n' "$1"
}

# mc_lookup <key> <key<TAB>value lines>: the value for <key>, if any.
mc_lookup() {
  printf '%s\n' "$2" | K=$1 awk -F '\t' '$1 == ENVIRON["K"] { print $2; exit }'
}
