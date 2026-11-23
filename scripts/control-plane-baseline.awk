# control-plane-baseline.awk: the compute stage of control-plane-baseline.sh,
# loaded after token-spend-lib.awk. The first input is the price table, the
# second the sorted rows: token-spend.sh rows (m, s and a lines) and the
# forge's merge lines (g <repo> <number> <merged-at>). Variables: since and
# until, the window's first and last UTC day, and prog. Prints the body rows
# unsorted; the caller sorts them under its header.

function day_of(ts) { return epoch(ts) > 0 ? substr(ts, 1, 10) : "" }
function in_window(d) { return d != "" && d >= since && d <= until }
function role_of(s) { return (s in head) ? session_kind(head[s], rules[s]) : "unknown" }
function per_day(x) { return sprintf("%.2f", x / days) }

$1 == "s" {
  if ($3 == "main" && !($2 in head)) { head[$2] = $7; rules[$2] = $6 + 0 }
  next
}

# A message counts once, as a turn and at its price, the way
# token-spend-total.awk counts it: a message with no usage is no turn. The id
# is marked only once a line counts, so a zero-usage or out-of-window line
# never hides a sibling line that does.
$1 == "m" {
  if ($2 != "-" && ($2 in seen)) next
  d = day_of($5)
  if (!in_window(d)) next
  i = $7 + 0; c5 = $8 + 0; c1 = $9 + 0; ct = $10 + 0; cr = $11 + 0; o = $12 + 0
  if (ct < c5 + c1) ct = c5 + c1
  if (i + ct + cr + o == 0) next
  if ($2 != "-") seen[$2] = 1
  use_model($6)
  if ($4 == "sub") sess_turns_sub[$3, d]++
  else sess_turns_main[$3, d]++
  sess_usd[$3, d] += usd(i, c5, c1, ct, cr, o)
  sess_active[$3, d] = 1
  next
}

$1 == "a" {
  if ($6 != "AskUserQuestion" && $6 != "PushNotification") next
  if ($2 != "-" && ($2 in ask_seen)) next
  d = day_of($5)
  if (!in_window(d)) next
  if ($2 != "-") ask_seen[$2] = 1
  if ($6 == "AskUserQuestion") sess_asked[$3, d]++
  else sess_pushed[$3, d]++
  sess_asking[$3, d] = 1
  next
}

$1 == "g" {
  if (($2, $3) in merge_seen) next
  d = day_of($4)
  if (!in_window(d)) next
  merge_seen[$2, $3] = 1
  merges[d, $2]++
  merges_total++
  next
}

END {
  if (bad_prices) exit 2
  days = (epoch(until "T00:00:00") - epoch(since "T00:00:00")) / 86400 + 1
  for (k in sess_active) {
    split(k, p, SUBSEP)
    r = role_of(p[1])
    roles[r] = 1
    day_role[p[2], r] = 1
    turns_main[p[2], r] += sess_turns_main[k]
    turns_sub[p[2], r] += sess_turns_sub[k]
    usd_day[p[2], r] += sess_usd[k]
    role_turns_main[r] += sess_turns_main[k]
    role_turns_sub[r] += sess_turns_sub[k]
    role_usd[r] += sess_usd[k]
    usd_total += sess_usd[k]
  }
  for (k in day_role) {
    split(k, p, SUBSEP)
    printf "turns\t%s\t%s\t%d\t%d\n", p[1], p[2], turns_main[k], turns_sub[k]
    printf "spend\t%s\t%s\t%.2f\n", p[1], p[2], usd_day[k]
  }
  for (k in sess_asking) {
    split(k, p, SUBSEP)
    r = role_of(p[1])
    asked[p[2], r] += sess_asked[k]
    pushed[p[2], r] += sess_pushed[k]
    ask_day_role[p[2], r] = 1
    asked_total += sess_asked[k]
    pushed_total += sess_pushed[k]
  }
  for (k in ask_day_role) {
    split(k, p, SUBSEP)
    printf "interruptions\t%s\t%s\t%d\t%d\n", p[1], p[2], asked[k], pushed[k]
  }
  for (k in merges) {
    split(k, p, SUBSEP)
    printf "merges\t%s\t%s\t%d\n", p[1], p[2], merges[k]
  }
  printf "summary\tdays\t%d\n", days
  for (r in roles) {
    printf "summary\tturns-per-day\t%s\t%s\t%s\n", r, per_day(role_turns_main[r]), per_day(role_turns_sub[r])
    printf "summary\tspend-share\t%s\t%.2f\t%.1f\n", r, role_usd[r], (usd_total > 0 ? role_usd[r] * 100 / usd_total : 0)
  }
  printf "summary\tmerges-per-day\t%s\n", per_day(merges_total)
  printf "summary\tinterruptions-per-day\t%s\t%s\n", per_day(asked_total), per_day(pushed_total)
}
