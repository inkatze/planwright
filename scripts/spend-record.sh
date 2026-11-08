#!/bin/sh
# spend-record.sh: the per-unit spend record. `record` totals one session's
# tokens (its transcript and its sub-agents', each message once) and appends
# one row to the program's spend store; `read` sums the store per unit.
# `spend-record.sh --help` prints the contract.
#
# Usage: spend-record.sh record --program <p> (--session <id> | --launch <name>)
#            [--unit <unit>] [--kind <kind>] [--prices <tsv>]
#        spend-record.sh read --program <p> [--unit <unit>]
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

prog=spend-record
here=$(cd "$(dirname "$0")" && pwd) || exit 2

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
        one row to <fleet-home>/mission-control/<p>/spend.tsv:
          <recorded-epoch> <unit> <session> <kind> <branch> <turns>
          <first-ts> <last-ts> <input> <cache-write> <cache-read> <output>
          <usd>
        --launch <name> reads a mission-control launch record: the session
        id from its stream-json worker directory, the unit from its scope
        and the kind from its kind (--unit and --kind override). Recording a
        session again appends a fresh row; read keeps the latest per session.
        Dollars use --prices (default config/token-prices.tsv).
read    Prints one line per unit (or the one --unit names): unit, sessions,
        turns, input, cache-write, cache-read, output, usd; then a total.

Exit: 0 done; 1 the session, transcript or launch was not found;
      2 usage or an unwritable store.
EOF
}

die() {
  printf '%s: %s\n' "$prog" "$2" >&2
  exit "$1"
}

field() { awk -F '\t' -v k="$2" '$1 == k { print $2; exit }' "$1"; }

safe() {
  case $1 in
    '' | *[!A-Za-z0-9._:/@+-]*) return 1 ;;
  esac
}

store_of() {
  home=$(/bin/sh "$here/fleet-state.sh" root 2>/dev/null) && [ -n "$home" ] \
    || die 2 "the fleet home does not resolve"
  dir=$home/mission-control/$1
  mkdir -p "$dir" 2>/dev/null || die 2 "cannot create $dir"
  printf '%s\n' "$dir/spend.tsv"
}

cmd_record() {
  program="" session="" launch="" unit="" kind="" prices=$here/../config/token-prices.tsv
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
  safe "$program" || die 2 "--program takes a plain name"
  if { [ -n "$session" ] && [ -n "$launch" ]; } || [ -z "$session$launch" ]; then usage; fi
  if [ -n "$launch" ]; then
    safe "$launch" || die 2 "--launch takes a plain name"
    home=$(/bin/sh "$here/fleet-state.sh" root 2>/dev/null) || die 2 "the fleet home does not resolve"
    rec=$home/mission-control/sessions/$launch
    [ -r "$rec" ] || die 1 "no launch record: $launch"
    handle=$(field "$rec" handle)
    [ -n "$unit" ] || unit=$(field "$rec" scope)
    [ -n "$kind" ] || kind=$(field "$rec" kind)
    session=$(cat "$home/streamjson/$handle/session" 2>/dev/null) || session=""
    [ -n "$session" ] || die 1 "launch $launch has no recorded session id"
  fi
  safe "$session" || die 2 "the session id is not a plain name"
  [ -n "$unit" ] || unit=$session
  [ -n "$kind" ] || kind=-
  safe "$unit" || die 2 "--unit takes a plain name"
  safe "$kind" || die 2 "--kind takes a plain name"
  root=${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects
  main=$(find "$root" -mindepth 2 -maxdepth 2 -type f -name "$session.jsonl" 2>/dev/null | head -n 1)
  [ -n "$main" ] || die 1 "no transcript for session $session under $root"
  store=$(store_of "$program")
  [ -s "$store" ] || printf '# format: 1\n' >"$store" || die 2 "cannot write $store"
  {
    "$here/token-spend.sh" rows "$main"
    find "${main%.jsonl}/subagents" -type f -name '*.jsonl' 2>/dev/null | while IFS= read -r f; do
      "$here/token-spend.sh" rows "$f"
    done
  } | awk -F '\t' -v now="$(date +%s)" -v unit="$unit" -v sid="$session" -v kind="$kind" '
    FNR == NR {
      if ($0 !~ /^#/ && $1 != "model" && NF >= 6) { P[$1, 1] = $2; P[$1, 2] = $3; P[$1, 3] = $4; P[$1, 4] = $5; P[$1, 5] = $6 }
      next
    }
    $1 != "m" || ($2 != "" && ($2 in seen)) { next }
    {
      seen[$2] = 1; mdl = $6; sub(/\[.*$/, "", mdl)
      ct = $10 + 0; if (ct < $8 + $9) ct = $8 + $9; rest = ct - $8 - $9
      if ($7 + ct + $11 + $12 == 0) next
      i += $7; cw += ct; cr += $11; o += $12
      usd += ($7 * P[mdl, 1] + $12 * P[mdl, 2] + $11 * P[mdl, 3] + ($8 + rest) * P[mdl, 4] + $9 * P[mdl, 5]) / 1e6
      if ($4 == "main") { turns++; if ($14 != "") { bc[$14]++; if (bc[$14] > bb) { bb = bc[$14]; br = $14 } } }
      if (first == "" || $5 < first) first = $5
      if ($5 > last) last = $5
    }
    END {
      if (br == "") br = "-"
      printf "%s\t%s\t%s\t%s\t%s\t%d\t%s\t%s\t%d\t%d\t%d\t%d\t%.4f\n", now, unit, sid, kind, br, turns, (first == "" ? "-" : first), (last == "" ? "-" : last), i, cw, cr, o, usd
    }' "$prices" - >>"$store" || die 2 "cannot append to $store"
  tail -n 1 "$store"
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
  safe "$program" || die 2 "--program takes a plain name"
  store=$(store_of "$program")
  [ -r "$store" ] || return 0
  awk -F '\t' -v want="$unit" '
    /^#/ || NF < 13 { next }
    { row[$3] = $0; if (!($3 in order)) { order[$3] = ++n; ids[n] = $3 } }
    END {
      for (k = 1; k <= n; k++) {
        split(row[ids[k]], f, "\t")
        if (want != "" && f[2] != want) continue
        u = f[2]; if (!(u in S)) { units[++m] = u }
        S[u]++; T[u] += f[6]; I[u] += f[9]; W[u] += f[10]; R[u] += f[11]; O[u] += f[12]; D[u] += f[13]
      }
      for (k = 1; k <= m; k++) {
        u = units[k]
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
