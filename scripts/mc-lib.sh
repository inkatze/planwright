# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154 # prog and script_dir are the sourcing script's; MC_FORMAT is read there
# mc-lib.sh — helpers mission control's runtime scripts share (sourced, never
# executed). The sourcing script sets `prog` and `script_dir` and has sourced
# echo-safety.sh first. Sourcing it runs one check: mc_warn_if_stale, below.
# Portable bash 3.2 / BSD tooling.

MC_FORMAT=1

unset CDPATH

# mc_warn_if_stale: a script run from an older cached copy, by a session
# that kept its root across an upgrade, warns on stderr. Checked once per
# process tree and state of the installed record (the marker carries the
# record's stamp, so a session that inherits it still hears of a later
# upgrade), and not at all where stderr is discarded.
mc_warn_if_stale() {
  case $script_dir in
    */plugins/cache/*) ;;
    *) return 0 ;;
  esac
  [ ! /dev/stderr -ef /dev/null ] || return 0
  [ -f "$script_dir/resolve-installed-roots.sh" ] || return 0
  # Canonical, as resolve-root.sh marks it, or a symlinked path warns twice.
  mws_copy=$(cd -P -- "$script_dir/.." 2>/dev/null && pwd -P) || return 0
  mws_rec=${CLAUDE_DIR:-${HOME:-}/.claude}/plugins/installed_plugins.json
  # shell-gnu-only-flag: BSD stat -f is the fallback when GNU stat -c fails
  mws_stamp=$(stat -c %Y "$mws_rec" 2>/dev/null || stat -f %m "$mws_rec" 2>/dev/null)
  [ "${PLANWRIGHT_COPY_CHECKED:-}" != "$mws_copy|$mws_stamp" ] || return 0
  PLANWRIGHT_COPY_CHECKED="$mws_copy|$mws_stamp"
  export PLANWRIGHT_COPY_CHECKED
  /bin/sh "$script_dir/resolve-installed-roots.sh" --check "$mws_copy" >/dev/null || :
}
mc_warn_if_stale

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

# mc_iso <epoch>: the UTC time the knowledge base stamps entries with, which
# compares as a string in time order.
mc_iso() {
  # shell-gnu-only-flag: BSD date -r is the fallback when GNU date -d fails
  date -u -d "@$1" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u -r "$1" '+%Y-%m-%dT%H:%M:%SZ'
}

# The reasons grammar of a decisions-log entry's grounds, scripts/mc-decide.sh
# --help's: `<reason> <class> <rules>: <text>`. MC_GROUNDS_AWK defines
# grounds(g), which sets G_REASON, G_CLASS and G_RULES (`-` for none) and
# returns 1, or returns 0 for grounds outside the grammar: a reason, class
# or rules word scripts/mc-decide.sh never writes.
# shellcheck disable=SC2016 # an awk program, expanded by awk
MC_GROUNDS_AWK='function grounds(g,   p, n, w) {
  G_REASON = ""; G_CLASS = ""; G_RULES = ""
  p = index(g, ": ")
  if (!p) return 0
  n = split(substr(g, 1, p - 1), w, " ")
  if (n != 3 || w[1] !~ /^(settled|ask-first|human-gate|fork|hard-disqualifier|reserved-proposal|revoke|confirm|correction|manual|answer|denial)$/) return 0
  if (w[2] !~ /^(-|auto-applicable|agent-resolvable|needs-sign-off|hygiene)$/) return 0
  if (w[3] != "-" && w[3] !~ /^r-[1-9][0-9]*(,r-[1-9][0-9]*)*$/) return 0
  G_REASON = w[1]; G_CLASS = w[2]; G_RULES = w[3]
  return 1
}
function asked(r) { return r ~ /^(ask-first|human-gate|fork|hard-disqualifier|reserved-proposal)$/ }'

# The subject key scripts/mc-rules.sh groups on and scripts/mc-kb.sh queries
# by; change all three together.
MC_SUBJECT_KEY_AWK='function key(s) { s = tolower(s); gsub(/[ ]+/, " ", s); sub(/^ /, "", s); sub(/ $/, "", s); return s }'

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
# program is configured, 1 when the program list cannot be read. A pass
# exports PLANWRIGHT_MC_CHECKED=<p> once checked, so the scripts it starts
# skip the list.
mc_require_program() {
  mc_valid_program "$1" || mc_usage_fail "invalid program name '$(sanitize_printable "$1")'"
  [ "${PLANWRIGHT_MC_CHECKED:-}" != "$1" ] || return 0
  mrp_list=$(/bin/bash "$script_dir/mc-program.sh" list) || mc_fail "cannot list the configured programs"
  case "
$mrp_list
" in
    *"
$1
"*)
      PLANWRIGHT_MC_CHECKED=$1
      export PLANWRIGHT_MC_CHECKED
      return 0
      ;;
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
# mc_clean_text: the same for UTF-8 text, dropping only the C0 controls but
# tab, DEL and the C1 controls (UTF-8 encodes them \302\200 to \302\237),
# so subjects written in other scripts read back whole.
# A C1 pair is taken with the lead bytes before it and the continuation
# bytes after it (all invalid UTF-8 there), so removing it never joins its
# neighbours into another pair, in one linear pass.
mc_clean_text() { awk '{ gsub(/[\001-\010\013-\037\177]/, ""); gsub(/\302+[\200-\237]+/, ""); print }'; }

mc_fleet_home() {
  mfh=$(/bin/sh "$script_dir/fleet-state.sh" root 2>/dev/null) && [ -n "$mfh" ] || return 1
  printf '%s\n' "$mfh"
}

# mc_usable_tmpdir: a long-lived process started from a launched session
# inherits that session's scratch TMPDIR, which is removed when the session
# retires, and every mktemp under it then fails. A TMPDIR that is no longer a
# writable directory is replaced, for this process and what it starts, by
# <fleet-home>/tmp; an unset one is left alone. Never fails.
mc_usable_tmpdir() {
  [ -n "${TMPDIR:-}" ] || return 0
  if [ -d "$TMPDIR" ] && [ -w "$TMPDIR" ]; then
    return 0
  fi
  mut_home=$(mc_fleet_home) || return 0
  # The runner and its watcher loops reach this together, so a lost mkdir race
  # is fine when the directory is there afterwards.
  if [ ! -d "$mut_home/tmp" ] && ! (umask 077 && mkdir -p "$mut_home/tmp") 2>/dev/null && [ ! -d "$mut_home/tmp" ]; then
    unset TMPDIR
    return 0
  fi
  TMPDIR="$mut_home/tmp"
  export TMPDIR
  return 0
}

# Runtime state (watcher records, source snapshots, the budget file, wake
# targets) lives under the plugin data home, in the fleet home
# scripts/fleet-state.sh resolves; events live in the attention store beside
# it. Neither is the program home, which holds work product only.
#
# mc_runtime <program>: the program's runtime directory,
# <fleet-home>/mission-control/<program>/, created.
mc_runtime() {
  mr_home=$(mc_fleet_home) || return 1
  mr_dir="$mr_home/mission-control/$1"
  mkdir -p "$mr_dir" 2>/dev/null || return 1
  printf '%s\n' "$mr_dir"
}

# mc_event_store <program>: the program's event directory in the attention
# store, <fleet-home>/attention/mission-control/<program>/, created.
mc_event_store() {
  me_home=$(mc_fleet_home) || return 1
  me_dir="$me_home/attention/mission-control/$1"
  mkdir -p "$me_dir/events" "$me_dir/marks" 2>/dev/null || return 1
  printf '%s\n' "$me_dir"
}

mc_event() { /bin/bash "$script_dir/mc-event.sh" "$@"; }

# mc_event_wakes [--routine]: the event rows on stdin (`mc-event.sh list`
# lines, the kind in the third field) whose kind wakes a turn, or with
# --routine only those config/mc-event-classes.tsv classes `routine`. An
# unreadable table fails open: every row wakes, with a warning, since a
# missing wake hides a real alert and an extra one only costs a turn.
mc_event_wakes() {
  mew_routine=0
  [ "${1:-}" = --routine ] && mew_routine=1
  mew_file="$script_dir/../config/mc-event-classes.tsv"
  if [ ! -f "$mew_file" ] || [ ! -r "$mew_file" ]; then
    printf '%s\n' "${prog:-mc}: config/mc-event-classes.tsv is missing or unreadable (broken install); every event wakes" >&2
    mew_file=/dev/null
  fi
  MEW_TABLE=$mew_file MEW_ROUTINE=$mew_routine awk -F '\t' '
    BEGIN {
      f = ENVIRON["MEW_TABLE"]
      while ((getline l < f) > 0) {
        sub(/\r$/, "", l)
        if (l ~ /^#/ || split(l, a, "\t") < 2) continue
        if (a[2] == "routine") r[a[1]] = 1
      }
      close(f)
    }
    NF && (($3 in r) == ENVIRON["MEW_ROUTINE"] + 0)'
}

mc_kb() { /bin/bash "$script_dir/mc-kb.sh" "$@"; }

# mc_sha256: the SHA-256 of stdin in hex; fails with no SHA-256 tool.
mc_sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    msh=$(sha256sum)
  elif command -v shasum >/dev/null 2>&1; then
    msh=$(shasum -a 256)
  elif command -v openssl >/dev/null 2>&1; then
    msh=$(openssl dgst -sha256 -r)
  else
    return 1
  fi
  msh=${msh%%[!0-9a-f]*}
  [ "${#msh}" -eq 64 ] || return 1
  printf '%s\n' "$msh"
}

# mc_kb_entries <program> <log>: every entry of a knowledge-base log, oldest
# first; an unconfigured program exits 3, any other failure 1.
mc_kb_entries() {
  mc_kb entries --program "$1" "$2"
  case $? in
    0) ;;
    3) exit 3 ;;
    *) mc_fail "the $2 log cannot be read" ;;
  esac
}

# mc_kb_lock <program> <kb path>: hold a knowledge-base write lock for this
# shell (MC_KB_LOCK), released by mc_kb_unlock, which the sourcing script's
# EXIT trap calls. The path need not name a store: a lock on a sibling name
# serializes a check-then-append without holding the log's own lock, which
# the append takes itself.
MC_KB_LOCK=''
MC_KB_LOCKED=''
mc_kb_lock() {
  MC_KB_LOCK=$(mc_kb lock --program "$1" "$2" --holder $$) || mc_fail "cannot take the lock on kb/$2"
  MC_KB_LOCKED="$1 $2"
}
mc_kb_unlock() {
  [ -n "$MC_KB_LOCK" ] || return 0
  mc_kb unlock --program "${MC_KB_LOCKED%% *}" "${MC_KB_LOCKED#* }" --token "$MC_KB_LOCK" >/dev/null 2>&1
  MC_KB_LOCK=''
}

# mc_duty_armed <program> <duty>: whether the program arms the duty (enabled,
# lifecycle shadow or live); fails when the duties do not resolve.
mc_duty_armed() {
  mda=$(/bin/bash "$script_dir/mc-duties.sh" files --program "$1") || mc_fail "the duties of program $1 do not resolve"
  printf '%s\n' "$mda" | D=$2 awk -F '\t' '$1 == ENVIRON["D"] { f = 1 } END { exit !f }'
}

# mc_quote <word>: the word single-quoted for a shell, an embedded single
# quote written '\''; fails on a control byte.
mc_quote() {
  case $1 in
    *[[:cntrl:]]*) return 1 ;;
  esac
  mq_close="'\\''"
  printf "'%s'" "${1//\'/$mq_close}"
}

# mc_write <file>: stdin to <file> through a sibling temporary and a rename,
# so a reader sees the old file or the new one, never a torn one.
mc_write() {
  mw_tmp=$(mktemp -- "$1.XXXXXX") || return 1
  if cat >"$mw_tmp" && mv -f -- "$mw_tmp" "$1"; then
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
  # shell-config-pin: mission control's knobs live in the overlay layers of the checkout it runs from
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
mc_parse_count() { # a count of at least one
  mc_valid_uint "$1" && [ "$1" -gt 0 ] || return 1
  printf '%s\n' "$1"
}

# mc_step_timeout <id>: the seconds a watcher run (id: its duty) or the
# snapshot refresh (id: snapshot) may take, the id's entry in
# mission_control_step_timeout_overrides else mission_control_step_timeout.
# An override that is no count of seconds is warned about and ignored.
mc_step_timeout() {
  mst_default=$(mc_knob mission_control_step_timeout mc_parse_count) || return 1
  mst_map=$(mc_knob mission_control_step_timeout_overrides mc_map) || return 1
  mst_v=$(printf '%s\n' "$mst_map" | I=$1 awk -F '\t' '$1 == ENVIRON["I"] { print $2; exit }')
  if [ -z "$mst_v" ]; then
    printf '%s\n' "$mst_default"
  elif mc_valid_uint "$mst_v" && [ "$mst_v" -gt 0 ]; then
    printf '%s\n' "$mst_v"
  else
    printf '%s\n' "${prog:-mc}: mission_control_step_timeout_overrides: '$(sanitize_printable "$1")' is not a count of seconds; using the default" >&2
    printf '%s\n' "$mst_default"
  fi
}

# mc_proc_tree <pid>: every descendant of the process, one pid per line; a
# shell waiting on a command substitution takes no TERM until the
# substitution ends, so a stop has to reach what the command started too.
mc_proc_tree() {
  ps -A -o pid= -o ppid= 2>/dev/null | P=$1 awk '
    { pid[NR] = $1; ppid[NR] = $2 }
    END {
      seen[ENVIRON["P"]] = 1
      do {
        grew = 0
        for (i = 1; i <= NR; i++)
          if (!(pid[i] in seen) && (ppid[i] in seen)) { seen[pid[i]] = 1; print pid[i]; grew = 1 }
      } while (grew)
    }'
}

# mc_run_bounded <seconds> <out> <command...>: run the command with its
# stdout in <out>, stopped when it outlives <seconds>: it and everything it
# started get a TERM, and those that ignored it a KILL two seconds later.
# Sets MRB_RC to its status and MRB_EXPIRED to 1 when it was stopped (a
# command that ended by itself at the deadline is not); MRB_PID is the
# command while it runs, for a caller's own signal handler.
MRB_PID=''
MRB_DOG=''
MRB_RC=0
MRB_EXPIRED=0
mc_run_bounded() {
  mrb_secs=$1
  mrb_out=$2
  shift 2
  MRB_EXPIRED=0
  mrb_flag="$mrb_out.expired"
  rm -f "$mrb_flag"
  "$@" </dev/null >"$mrb_out" &
  MRB_PID=$!
  (
    mrb_sp=''
    trap '[ -z "$mrb_sp" ] || kill "$mrb_sp" 2>/dev/null; exit 0' TERM
    sleep "$mrb_secs" &
    mrb_sp=$!
    wait "$mrb_sp"
    : >"$mrb_flag"
    # The tree is read before the TERM: once the command is gone what it
    # started is reparented and no longer found under it.
    mrb_victims=$(mc_proc_tree "$MRB_PID")
    # shellcheck disable=SC2086 # one pid per word
    kill -TERM $mrb_victims "$MRB_PID" 2>/dev/null
    sleep 2 &
    mrb_sp=$!
    wait "$mrb_sp"
    # shellcheck disable=SC2086 # one pid per word
    kill -KILL $mrb_victims "$MRB_PID" 2>/dev/null
  ) </dev/null >/dev/null 2>&1 &
  MRB_DOG=$!
  wait "$MRB_PID"
  MRB_RC=$?
  if [ -f "$mrb_flag" ] && [ "$MRB_RC" -ge 128 ]; then
    # The watchdog stays to deliver the KILL to what ignored the TERM.
    MRB_EXPIRED=1
  else
    kill "$MRB_DOG" 2>/dev/null
    wait "$MRB_DOG" 2>/dev/null
  fi
  rm -f "$mrb_flag"
  MRB_PID=''
  MRB_DOG=''
  return 0
}

# mc_valid_entry_id <log> <id>: <log>-<YYYYMM>-<n>, as scripts/mc-kb.sh
# numbers entries.
mc_valid_entry_id() {
  mvi=${2#"$1"-}
  case $mvi in
    "$2" | *-*-* | [!0-9]*) return 1 ;;
    *-*) ;;
    *) return 1 ;;
  esac
  case ${mvi%%-*} in
    [0-9][0-9][0-9][0-9][0-9][0-9]) ;;
    *) return 1 ;;
  esac
  mc_valid_uint "${mvi#*-}" && [ "${mvi#*-}" -gt 0 ]
}

# mc_lookup <key> <key<TAB>value lines>: the value for <key>, if any.
mc_lookup() {
  printf '%s\n' "$2" | K=$1 awk -F '\t' '$1 == ENVIRON["K"] { print $2; exit }'
}

# mc_kv <file> <key>: the value of a record's key<TAB>value line, if any.
mc_kv() { K=$2 awk -F '\t' '$1 == ENVIRON["K"] { print substr($0, length($1) + 2); exit }' "$1"; }

# mc_valid_sha <sha>: a full 40-hex commit id.
mc_valid_sha() {
  case $1 in
    *[!0-9a-f]*) return 1 ;;
  esac
  [ "${#1}" -eq 40 ]
}

# mc_valid_slug <owner/name>: a forge repository slug.
mc_valid_slug() {
  case $1 in
    */*/* | /* | */ | -* | */-* | . | ./* | .. | ../* | */. | */.. | *[!A-Za-z0-9._/-]*) return 1 ;;
    ?*/?*) ;;
    *) return 1 ;;
  esac
  [ "${#1}" -le 200 ]
}

# mc_slug_repos <program> <slug>: the program's repositories whose origin
# remote is <slug>, one per line; returns 1 when the repositories do not
# resolve.
mc_slug_repos() {
  msr_repos=$(/bin/bash "$script_dir/mc-program.sh" get "$1" repositories) || return 1
  msr_sl=$(printf '%s' "$2" | tr '[:upper:]' '[:lower:]')
  while IFS= read -r msr_r; do
    [ -n "$msr_r" ] && [ -d "$msr_r" ] || continue
    msr_url=$(mc_untrusted_git -C "$msr_r" remote get-url origin 2>/dev/null | tr '[:upper:]' '[:lower:]') || continue
    msr_url=${msr_url%.git}
    case $msr_url in */"$msr_sl" | *:"$msr_sl") printf '%s\n' "$msr_r" ;; esac
  done <<EOF
$msr_repos
EOF
}

# mc_program_home <program>: the program home, or the script fails.
mc_program_home() {
  /bin/bash "$script_dir/mc-program.sh" get "$1" home || mc_fail "the home of program $1 does not resolve"
}

# mc_store_ok <file>: a program-home store opening with "# format: 1"; an
# empty file fails, so nothing is appended below a missing format line.
mc_store_ok() {
  awk 'NR == 1 { ok = ($0 == "# format: 1"); exit } END { exit !ok }' "$1"
}

# mc_store_init <file>: create the store with its format line, or check the
# one there; fails naming the file.
mc_store_init() {
  if [ -e "$1" ]; then
    mc_store_ok "$1" || mc_fail "the store has a missing or unknown format: $1"
  else
    mkdir -p -- "${1%/*}" || mc_fail "cannot create ${1%/*}"
    printf '# format: 1\n' >"$1" || mc_fail "cannot create $1"
  fi
}

# mc_announce <program> <seen-file> <key> <kind> <subject> <text>: emit the
# event once per key, its text flattened to one line of at most 500
# characters. The key is recorded only once the event store holds the
# event, so a refused or interrupted emit is tried again on the next run.
# Prints `announced<TAB><kind><TAB><subject>`; fails on a refused event or a
# seen file that cannot be read or written. A watcher ends its run with
# mc_announce_prune, so the seen set holds only what is still live.
mc_announce() {
  [ -f "$2" ] || : >"$2" || return 1
  [ -r "$2" ] || return 1
  if K=$3 awk 'BEGIN { k = ENVIRON["K"] } $0 == k { f = 1; exit } END { exit !f }' "$2"; then
    return 0
  fi
  # The event text is one line of printable text within the store's cap.
  ma_text=$(printf '%s' "$6" | tr '\t\n\r' '   ' | mc_clean_text | cut -c1-500)
  mc_event emit --program "$1" -- "$4" "$5" "$ma_text" >/dev/null || return 1
  printf '%s\n' "$3" >>"$2" || return 1
  printf 'announced\t%s\t%s\n' "$4" "$5"
}

# mc_announce_prune <seen-file> <live keys>: keep only the keys this run
# still produced (newline separated), so an item that clears and comes back
# is announced again, and the set never outgrows what is live.
mc_announce_prune() {
  [ -f "$1" ] || return 0
  map_kept=$(LIVE=$2 awk 'BEGIN { n = split(ENVIRON["LIVE"], l, "\n"); for (i = 1; i <= n; i++) if (l[i] != "") live[l[i]] = 1 }
    ($0 in live) && !($0 in seen) { seen[$0] = 1; print }' "$1") || return 1
  { [ -z "$map_kept" ] || printf '%s\n' "$map_kept"; } | mc_write "$1"
}

# mc_untrusted_git <args>: git with what a worker-written checkout's own
# configuration could run turned off (fsmonitor, hooks, a lazy fetch through
# a remote helper or ssh command, signature display) and no inherited
# repository selector. The settings ride the environment, which outranks the
# repository's configuration, so they reach a git a called script runs too:
# export them with mc_untrusted_git_env.
mc_untrusted_git_env() {
  # An inherited repository selector would point git away from the checkout
  # the caller names, and inherited configuration would ride along.
  unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
    GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_CONFIG_PARAMETERS
  GIT_CONFIG_COUNT=4
  GIT_CONFIG_KEY_0=core.fsmonitor GIT_CONFIG_VALUE_0=false
  GIT_CONFIG_KEY_1=core.hooksPath GIT_CONFIG_VALUE_1=/dev/null
  GIT_CONFIG_KEY_2=protocol.allow GIT_CONFIG_VALUE_2=never
  GIT_CONFIG_KEY_3=log.showSignature GIT_CONFIG_VALUE_3=false
  GIT_NO_LAZY_FETCH=1
  export GIT_CONFIG_COUNT GIT_CONFIG_KEY_0 GIT_CONFIG_VALUE_0 GIT_CONFIG_KEY_1 GIT_CONFIG_VALUE_1 \
    GIT_CONFIG_KEY_2 GIT_CONFIG_VALUE_2 GIT_CONFIG_KEY_3 GIT_CONFIG_VALUE_3 GIT_NO_LAZY_FETCH
}
mc_untrusted_git() { (mc_untrusted_git_env && git "$@"); }

# mc_subject <prefix> <key>: a stable event subject for a key outside the
# subject grammar, <prefix>-<checksum>; the readable key goes in the event's
# text.
mc_subject() {
  printf '%s-%s\n' "$1" "$(printf '%s' "$2" | cksum | awk '{ print $1 }')"
}

# mc_pr_subject <owner/name> <n>: a pull request's event subject,
# <owner>:<name>:<n>, or pr-<checksum> outside the subject grammar.
mc_pr_subject() {
  mps_s="${1%%/*}:${1#*/}:$2"
  mc_valid_handle "$mps_s" || mps_s=$(mc_subject pr "$1#$2")
  printf '%s\n' "$mps_s"
}

# mc_code_state <program> [<now>]: the program's code-state snapshot, aged at
# <now> (the clock by default), its status line
# and rows in MC_CS_ROWS and its source in MC_CS_SOURCE. Returns 0 when it is
# at most twice its cadence old (the most any budget rung stretches a
# refresh), 1 when the source map does not resolve, 2 when the snapshot
# cannot be read, 3 with no code-state snapshot source or none taken yet
# (MC_CS_SOURCE empty for the first), 4 when it is older, so it may show a
# head long gone.
mc_code_state() {
  MC_CS_ROWS=""
  MC_CS_SOURCE=""
  mcs_map=$(/bin/bash "$script_dir/mc-program.sh" get "$1" sources) || return 1
  MC_CS_SOURCE=$(printf '%s\n' "$mcs_map" | awk -F '\t' '$1 == "code-state" && $3 == "snapshot" { print $2; exit }')
  [ -n "$MC_CS_SOURCE" ] || return 3
  MC_CS_ROWS=$(/bin/bash "$script_dir/mc-snapshot.sh" read --program "$1" "$MC_CS_SOURCE" ${2:+--now "$2"})
  case $? in
    0) ;;
    3) return 3 ;;
    *) return 2 ;;
  esac
  printf '%s\n' "$MC_CS_ROWS" | head -n 1 | awk -F '\t' '$5 == "age" && $7 == "cadence" { ok = ($6 + 0 <= 2 * ($8 + 0)) } END { exit !ok }' || return 4
}
