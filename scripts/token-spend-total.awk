# token-spend-total.awk: one session's totals for spend-record.sh, run after
# token-spend-lib.awk over that session's rows (its transcript and its
# sub-agents'). Variables: now, unit, sid, kind. Prints one store row; exits 1
# when the rows hold no usage.

$1 == "m" {
  if ($2 != "-") {
    if ($2 in seen) next
    seen[$2] = 1
  }
  i = $7 + 0; c5 = $8 + 0; c1 = $9 + 0; ct = $10 + 0; cr = $11 + 0; o = $12 + 0
  if (ct < c5 + c1) ct = c5 + c1
  if (i + ct + cr + o == 0) next
  use_model($6)
  n++; ti += i; tcw += ct; tcr += cr; to += o; tusd += usd(i, c5, c1, ct, cr, o)
  if ($4 == "main") {
    turns++
    if ($14 != "") { bc[$14]++; if (bc[$14] > bb) { bb = bc[$14]; br = $14 } }
  }
  if (epoch($5) > 0) {
    if (first == "" || $5 < first) first = $5
    if ($5 > last) last = $5
  }
}

END {
  if (bad_prices) exit 2
  if (!n) exit 1
  printf "%s\t%s\t%s\t%s\t%s\t%d\t%s\t%s\t%d\t%d\t%d\t%d\t%.4f\n", now, unit, sid, kind, (br == "" ? "-" : br), turns, (first == "" ? "-" : first), (last == "" ? "-" : last), ti, tcw, tcr, to, tusd
}
