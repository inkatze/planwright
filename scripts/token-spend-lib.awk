# token-spend-lib.awk: what token-spend-report.awk and token-spend-total.awk
# share, loaded first with `awk -f token-spend-lib.awk -f <stage>.awk`. The
# first input is the price table, the rest token-spend.sh rows. Portable awk.

# epoch(<ISO-8601 UTC>): seconds since 1970 by the days-from-civil formula;
# 0 for anything else, which callers treat as no timestamp.
function epoch(iso,    y, m, d, era, yoe, doy, doe) {
  if (iso !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]/) return 0
  y = substr(iso, 1, 4) + 0; m = substr(iso, 6, 2) + 0; d = substr(iso, 9, 2) + 0
  if (m <= 2) y--
  era = int(y / 400)
  yoe = y - era * 400
  doy = int((153 * (m > 2 ? m - 3 : m + 9) + 2) / 5) + d - 1
  doe = yoe * 365 + int(yoe / 4) - int(yoe / 100) + doy
  return ((era * 146097 + doe - 719468) * 86400) + substr(iso, 12, 2) * 3600 + substr(iso, 15, 2) * 60 + substr(iso, 18, 2)
}

# price(<model>, in|out|cr|w5|w1): USD per million tokens; the exact id
# first, then the id without a `[...]` context suffix. An unpriced model is
# named once on stderr and priced at zero.
function price(model, k,    base) {
  if ((model, k) in P) return P[model, k]
  base = model
  sub(/\[.*$/, "", base)
  if ((base, k) in P) return P[base, k]
  if (!(model in unpriced)) {
    unpriced[model] = 1
    printf "%s: no price for model %s, priced at zero\n", prog, model > "/dev/stderr"
  }
  return 0
}

# use_model(<model>): load the model's prices into Pin, Pout, Pcr, Pw5, Pw1,
# looked up again only when the model changes.
function use_model(model) {
  if (model == cur_model && cur_set) return
  cur_model = model; cur_set = 1
  Pin = price(model, "in"); Pout = price(model, "out"); Pcr = price(model, "cr")
  Pw5 = price(model, "w5"); Pw1 = price(model, "w1")
}

# usd(...): one message's dollars at the current model's prices; a cache
# write the transcript does not split by lifetime is priced at 5 minutes.
function usd(i, c5, c1, ct, cr, o,    rest) {
  rest = ct - c5 - c1
  if (rest < 0) rest = 0
  return (i * Pin + (c5 + rest) * Pw5 + c1 * Pw1 + cr * Pcr + o * Pout) / 1e6
}

FILENAME == ARGV[1] {
  if ($0 ~ /^#/ || $1 == "model" || NF < 6) next
  P[$1, "in"] = $2; P[$1, "out"] = $3; P[$1, "cr"] = $4; P[$1, "w5"] = $5; P[$1, "w1"] = $6
  priced++
  next
}

# Transcript text is untrusted: drop C0 controls but tab, DEL and the UTF-8
# C1 controls before any field is stored or printed.
{
  gsub(/[\001-\010\013-\037\177]/, "")
  gsub(/\302[\200-\237]/, "")
  if (!priced) {
    printf "%s: the price table defines no model\n", prog > "/dev/stderr"
    bad_prices = 1
    exit 2
  }
}
