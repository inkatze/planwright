# control-plane-baseline.awk: the compute stage of control-plane-baseline.sh,
# run after token-spend-lib.awk over token-spend.sh rows (m, s and a lines)
# and the forge's merge lines (g <repo> <number> <merged-at>), in any order.
# Variables: since and until, the window's first and last UTC day. Prints the
# baseline's body rows unsorted; the caller sorts them under its header.

function day_of(ts) { return epoch(ts) > 0 ? substr(ts, 1, 10) : "" }
function in_window(d) { return d != "" && d >= since && d <= until }
function role_of(s) { return (s in head) ? session_kind(head[s], rules[s]) : "unknown" }
function per_day(x) { return sprintf("%.2f", x / days) }

$1 == "s" {
  if ($3 == "main" && !($2 in head)) { head[$2] = $7; rules[$2] = $6 + 0 }
  next
}

# A message counts once, as a turn and at its price, the way
# token-spend-total.awk counts it: a message with no usage is no turn.
$1 == "m" {
  if ($2 != "-") {
    if ($2 in seen) next
    seen[$2] = 1
  }
  d = day_of($5)
  if (!in_window(d)) next
  i = $7 + 0; c5 = $8 + 0; c1 = $9 + 0; ct = $10 + 0; cr = $11 + 0; o = $12 + 0
  if (ct < c5 + c1) ct = c5 + c1
  if (i + ct + cr + o == 0) next
  use_model($6)
  if ($4 == "sub") tsub[$3, d]++
  else tmain[$3, d]++
  spend[$3, d] += usd(i, c5, c1, ct, cr, o)
  active[$3, d] = 1
  next
}

$1 == "a" {
  if ($2 != "-") {
    if ($2 in aseen) next
    aseen[$2] = 1
  }
  d = day_of($5)
  if (!in_window(d)) next
  if ($6 == "AskUserQuestion") asked[$3, d]++
  else if ($6 == "PushNotification") pushed[$3, d]++
  else next
  asking[$3, d] = 1
  next
}

$1 == "g" {
  if (($2, $3) in gseen) next
  gseen[$2, $3] = 1
  d = day_of($4)
  if (!in_window(d)) next
  merges[d, $2]++
  merged++
  next
}

END {
  if (bad_prices) exit 2
  days = (epoch(until "T00:00:00") - epoch(since "T00:00:00")) / 86400 + 1
  for (k in active) {
    split(k, p, SUBSEP)
    r = role_of(p[1])
    roles[r] = 1
    dr[p[2], r] = 1
    Tm[p[2], r] += tmain[k]; Ts[p[2], r] += tsub[k]; Sp[p[2], r] += spend[k]
    RTm[r] += tmain[k]; RTs[r] += tsub[k]; RSp[r] += spend[k]; total += spend[k]
  }
  for (k in dr) {
    split(k, p, SUBSEP)
    printf "turns\t%s\t%s\t%d\t%d\n", p[1], p[2], Tm[k], Ts[k]
    printf "spend\t%s\t%s\t%.2f\n", p[1], p[2], Sp[k]
  }
  for (k in asking) {
    split(k, p, SUBSEP)
    r = role_of(p[1])
    Ia[p[2], r] += asked[k]; Ip[p[2], r] += pushed[k]; idr[p[2], r] = 1
    ta += asked[k]; tp += pushed[k]
  }
  for (k in idr) {
    split(k, p, SUBSEP)
    printf "interruptions\t%s\t%s\t%d\t%d\n", p[1], p[2], Ia[k], Ip[k]
  }
  for (k in merges) {
    split(k, p, SUBSEP)
    printf "merges\t%s\t%s\t%d\n", p[1], p[2], merges[k]
  }
  printf "summary\tdays\t%d\n", days
  for (r in roles) {
    printf "summary\tturns-per-day\t%s\t%s\t%s\n", r, per_day(RTm[r]), per_day(RTs[r])
    printf "summary\tspend-share\t%s\t%.2f\t%.1f\n", r, RSp[r], (total > 0 ? RSp[r] * 100 / total : 0)
  }
  printf "summary\tmerges-per-day\t%s\n", per_day(merged)
  printf "summary\tinterruptions-per-day\t%s\t%s\n", per_day(ta), per_day(tp)
}
