#!/usr/bin/env bash
# spend-record.sh: the per-unit spend record. `record` totals one session's
# tokens (its transcript and its sub-agents', each message once) and appends
# one row to the program's spend store; `read` sums the store per unit.
# `spend-record.sh --help` prints the contract.
#
# Usage: spend-record.sh record --program <p> (--session <id> | --launch <name>)
#            [--unit <unit>] [--kind <kind>] [--prices <tsv>]
#        spend-record.sh read --program <p> [--unit <unit>]
set -u
set -f
LC_ALL=C
export LC_ALL
unset CDPATH

prog=spend-record
script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2
for lib in echo-safety.sh mc-lib.sh lock-lib.sh; do
  if [ ! -r "$script_dir/$lib" ]; then
    printf '%s\n' "$prog: $lib is missing or unreadable (broken install)" >&2
    exit 2
  fi
done
# shellcheck source=scripts/echo-safety.sh
. "$script_dir/echo-safety.sh" || exit 2
# shellcheck source=scripts/mc-lib.sh
. "$script_dir/mc-lib.sh" || exit 2
# shellcheck source=scripts/lock-lib.sh
. "$script_dir/lock-lib.sh" || exit 2

usage() {
  cat >&2 <<'EOF'
usage: spend-record.sh record --program <p> (--session <id> | --launch <name>)
           [--unit <unit>] [--kind <kind>] [--prices <tsv>]
       spend-record.sh read --program <p> [--unit <unit>]
EOF
  exit 2
}

help_text() {
  cat <<'EOF'
spend-record.sh: what each unit of work cost, where mission control reads it.

record  Finds the session's transcript under $CLAUDE_CONFIG_DIR/projects
        (default ~/.claude/projects) with its sub-agent transcripts, totals
        them through token-spend.sh rows (each message id once) and appends
        one row, under the store's lock, to
        <fleet-home>/mission-control/<p>/spend.tsv (first line `# format: 1`):
          <recorded-epoch> <unit> <session> <launch-kind> <branch> <turns>
          <first-ts> <last-ts> <input> <cache-write> <cache-read> <output>
          <usd>
        and prints it. --launch <name> reads that program's mission-control
        launch record: the session id from its stream-json worker directory,
        the unit from its scope and the launch kind from its kind (--unit and
        --kind override). The unit defaults to the session id. Recording a
        session again appends a fresh row. Dollars use --prices (default
        config/token-prices.tsv); a model missing from it is priced at zero
        and named on stderr.
read    Prints one line per unit (or the one --unit names): unit, sessions,
        turns, input, cache-write, cache-read, output, usd; then a total
        line. Per session it keeps the row with the latest last-ts, then the
        latest recorded-epoch. A program with no store prints a zero total.

Names: --program is a mission-control program name; --launch a launch
name (mc-<kebab>); the session id, unit and kind are plain fields (letters,
digits and . _ = @ : -, never starting with - or a dot alone).

Exit: 0 done; 1 the launch record, its session id, the transcript or any
      usage in it was not found, or a transcript could not be read;
      2 usage, an unreadable or malformed price table, an unresolved fleet
      home, or a store that is a symlink, cannot be read or written, or has
      an unknown format.
EOF
}

die() {
  printf '%s: %s\n' "$prog" "$2" >&2
  exit "$1"
}

valid_launch() {
  [ "${#1}" -le 64 ] || return 1
  case $1 in mc-?*) mc_valid_kebab "${1#mc-}" ;; *) return 1 ;; esac
}

need() { # need <what> <value> <validator>
  "$3" "$2" || die 2 "$1 is not a valid name: $(sanitize_printable "$2" '(unprintable)')"
}

cmd_record() {
  program="" session="" launch="" unit="" kind="" prices=$script_dir/../config/token-prices.tsv
  while [ $# -gt 0 ]; do
    [ $# -ge 2 ] || usage
    case $1 in
      --program) program=$2 ;;
      --session) session=$2 ;;
      --launch) launch=$2 ;;
      --unit) unit=$2 ;;
      --kind) kind=$2 ;;
      --prices) prices=$2 ;;
      *) usage ;;
    esac
    shift 2
  done
  if { [ -n "$session" ] && [ -n "$launch" ]; } || [ -z "$session$launch" ]; then usage; fi
  need --program "$program" mc_valid_program
  [ -z "$unit" ] || need --unit "$unit" mc_valid_handle
  [ -z "$kind" ] || need --kind "$kind" mc_valid_handle
  [ -f "$prices" ] && [ -r "$prices" ] && [ -s "$prices" ] \
    || die 2 "unreadable or empty price table: $(sanitize_printable "$prices" '(unprintable)')"
  home=$(mc_fleet_home) || die 2 "the fleet home does not resolve"
  if [ -n "$launch" ]; then
    need --launch "$launch" valid_launch
    rec=$home/mission-control/sessions/$launch
    [ -f "$rec" ] && [ ! -L "$rec" ] && [ -r "$rec" ] || die 1 "no launch record: $launch"
    [ "$(mc_kv "$rec" format)" = 1 ] || die 1 "launch $launch has an unknown record format"
    [ "$(mc_kv "$rec" program)" = "$program" ] || die 1 "launch $launch belongs to another program"
    handle=$(mc_kv "$rec" handle)
    mc_valid_handle "$handle" || die 1 "launch $launch has no valid handle"
    [ -n "$unit" ] || unit=$(mc_kv "$rec" scope)
    [ -n "$kind" ] || kind=$(mc_kv "$rec" kind)
    session=$(cat "$home/streamjson/$handle/session" 2>/dev/null) || session=""
    [ -n "$session" ] || die 1 "launch $launch has no recorded session id"
  fi
  need "the session id" "$session" mc_valid_handle
  [ -n "$unit" ] || unit=$session
  need "the unit" "$unit" mc_valid_handle
  if [ -n "$kind" ]; then need "the kind" "$kind" mc_valid_handle; else kind=-; fi
  root=${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects
  main=$(find "$root" -mindepth 2 -maxdepth 2 -type f -name "$session.jsonl" -print -quit 2>/dev/null)
  [ -n "$main" ] || die 1 "no transcript for session $session"
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/spend-record.XXXXXX") || die 2 "mktemp failed"
  trap 'rm -rf "$tmp"' EXIT
  "$script_dir/token-spend.sh" rows "$main" >"$tmp/rows" || die 1 "reading the transcript failed"
  if [ -d "${main%.jsonl}/subagents" ]; then
    find "${main%.jsonl}/subagents" -type f -name '*.jsonl' -exec "$script_dir/token-spend.sh" rows {} + >>"$tmp/rows" \
      || die 1 "reading the sub-agent transcripts failed"
  fi
  row=$(awk -F '\t' -v prog="$prog" -v now="$(date +%s)" -v unit="$unit" -v sid="$session" -v kind="$kind" \
    -f "$script_dir/token-spend-lib.awk" -f "$script_dir/token-spend-total.awk" "$prices" "$tmp/rows")
  case $? in
    0) ;;
    1) die 1 "no usage found for session $session" ;;
    *) die 2 "totalling the session failed" ;;
  esac
  rm -rf "$tmp"
  trap - EXIT
  store=$home/mission-control/$program/spend.tsv
  lock=$store.lock
  mkdir -p -- "${store%/*}" || die 2 "cannot create ${store%/*}"
  pw_lock_trap_install
  pw_lock_acquire "$lock" || die 2 "cannot take the spend store lock"
  [ ! -L "$store" ] || die 2 "the store is a symlink: $store"
  if [ -e "$store" ]; then
    mc_store_ok "$store" || die 2 "the store has a missing or unknown format: $store"
  else
    printf "# format: 1\n" >"$store" || die 2 "cannot create $store"
  fi
  # A row torn by an earlier failed write would swallow this one.
  [ -z "$(tail -c 1 "$store")" ] || printf '\n' >>"$store" || die 2 "cannot write $store"
  printf '%s\n' "$row" >>"$store" || die 2 "cannot append to $store"
  pw_lock_release "$lock" >/dev/null 2>&1
  printf '%s\n' "$row"
}

cmd_read() {
  program="" unit=""
  while [ $# -gt 0 ]; do
    [ $# -ge 2 ] || usage
    case $1 in
      --program) program=$2 ;;
      --unit) unit=$2 ;;
      *) usage ;;
    esac
    shift 2
  done
  need --program "$program" mc_valid_program
  [ -z "$unit" ] || need --unit "$unit" mc_valid_handle
  home=$(mc_fleet_home) || die 2 "the fleet home does not resolve"
  store=$home/mission-control/$program/spend.tsv
  [ ! -L "$store" ] || die 2 "the store is a symlink: $store"
  if [ ! -e "$store" ]; then
    printf 'total\t0\t0\t0\t0\t0\t0\t0.00\n'
    return 0
  fi
  [ -f "$store" ] && [ -r "$store" ] || die 2 "cannot read $store"
  mc_store_ok "$store" || die 2 "the store has a missing or unknown format: $store"
  awk -F '\t' -v want="$unit" '
    /^#/ || NF != 13 { next }
    {
      k = $3
      if (!(k in row) || $8 > last[k] || ($8 == last[k] && $1 + 0 >= at[k])) { row[k] = $0; last[k] = $8; at[k] = $1 + 0 }
      if (!(k in order)) { order[k] = ++n; ids[n] = k }
    }
    END {
      for (j = 1; j <= n; j++) {
        split(row[ids[j]], f, "\t")
        if (want != "" && f[2] != want) continue
        u = f[2]; if (!(u in S)) units[++m] = u
        S[u]++; T[u] += f[6]; I[u] += f[9]; W[u] += f[10]; R[u] += f[11]; O[u] += f[12]; D[u] += f[13]
      }
      for (j = 1; j <= m; j++) {
        u = units[j]
        printf "%s\t%d\t%d\t%d\t%d\t%d\t%d\t%.2f\n", u, S[u], T[u], I[u], W[u], R[u], O[u], D[u]
        ts += S[u]; tt += T[u]; ti += I[u]; tw += W[u]; tr += R[u]; to += O[u]; td += D[u]
      }
      printf "total\t%d\t%d\t%d\t%d\t%d\t%d\t%.2f\n", ts, tt, ti, tw, tr, to, td
    }' "$store"
}

[ $# -ge 1 ] || usage
verb=$1
shift
case $verb in
  record) cmd_record "$@" ;;
  read) cmd_read "$@" ;;
  -h | --help) help_text ;;
  *) usage ;;
esac
