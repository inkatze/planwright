#!/bin/bash
# Tests for scripts/allocation-ladder.sh — the ROSTER contract specifically
# (model-allocation D-6, D-8; REQ-C1.1).
#
# The ladder's arithmetic (successor, mirror, replay, net displacement) is
# covered by tests/test-allocation-ledger.sh. This file covers the one property
# that file cannot: that the model roster is stated ONCE and stays APPEND-ONLY.
#
# Why that needs its own guard. Rank is the roster list's index, and replay is
# memoryless — it re-derives a unit's tier by stepping the DIRECTIONS its ledger
# recorded back through the successor rule, never from a stored tier. Inserting
# a model between two existing ones therefore renumbers every rank above it and
# silently changes what every past run replays to, while every existing test
# still passes because they all read the same renumbered map. Pinning each
# shipped alias to its rank BY NAME is what separates an insertion (fails here)
# from an append (passes here).
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-allocation-ladder.sh
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
LADDER="$here/../scripts/allocation-ladder.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -r "$LADDER" ] || fail "scripts/allocation-ladder.sh missing or not readable"

# shellcheck source=scripts/allocation-ladder.sh
. "$LADDER"

# ---------------------------------------------------------------------------
# r1: every shipped alias pins to its rank BY NAME. An insertion renumbers the
#     aliases above it and fails here; an append leaves all of these untouched.
# ---------------------------------------------------------------------------
for pair in haiku:0 sonnet:1 opus:2 fable:3; do
  alias=${pair%%:*}
  want=${pair##*:}
  got=$(alloc_model_rank "$alias") || fail "r1: $alias is not in the roster at all"
  [ "$got" = "$want" ] \
    || fail "r1: $alias ranks $got, not $want — the roster was reordered or a model was INSERTED (it is append-only)"
  back=$(alloc_model_at "$want") || fail "r1: rank $want resolves to no alias"
  [ "$back" = "$alias" ] || fail "r1: rank $want resolves to $back, not $alias"
done
echo "ok: r1 each shipped alias holds its rank by name (insertion is refused, append is not)"

# ---------------------------------------------------------------------------
# r2: the derived constants agree with the roster they are derived from, so a
#     future append moves the top rather than leaving it pinned behind.
# ---------------------------------------------------------------------------
count=0
last=''
for m in $ALLOC_MODELS; do
  count=$((count + 1))
  last=$m
done
[ "$ALLOC_MODEL_TOP" = "$((count - 1))" ] \
  || fail "r2: ALLOC_MODEL_TOP is $ALLOC_MODEL_TOP for a $count-model roster"
[ "$(alloc_model_at "$ALLOC_MODEL_TOP")" = "$last" ] \
  || fail "r2: the top rank does not resolve to the roster's last entry ($last)"
ecount=0
elast=''
for e in $ALLOC_EFFORTS; do
  ecount=$((ecount + 1))
  elast=$e
done
[ "$ALLOC_EFFORT_TOP" = "$((ecount - 1))" ] \
  || fail "r2: ALLOC_EFFORT_TOP is $ALLOC_EFFORT_TOP for a $ecount-effort roster"
alloc_is_top "$last" "$elast" || fail "r2: the derived ends are not the ladder top"
first_m=${ALLOC_MODELS%% *}
first_e=${ALLOC_EFFORTS%% *}
alloc_is_bottom "$first_m" "$first_e" || fail "r2: the derived starts are not the ladder floor"
alloc_is_top "$first_m" "$elast" && fail "r2: the ladder floor's model reads as the top"
echo "ok: r2 the derived top/floor track the roster instead of a pinned alias"

# ---------------------------------------------------------------------------
# r3: the reversed spelling is exactly the roster reversed. Consumers hand it
#     to the shared knob resolver as a column enum, so a divergence would let a
#     model be configurable in one script and refused in another.
# ---------------------------------------------------------------------------
rev=''
for m in $ALLOC_MODELS; do
  rev="$m${rev:+ }$rev"
done
[ "$ALLOC_MODELS_DESC" = "$rev" ] \
  || fail "r3: ALLOC_MODELS_DESC is '$ALLOC_MODELS_DESC', not the reverse '$rev'"
echo "ok: r3 the expensive-first enum is the roster reversed, not a second list"

# ---------------------------------------------------------------------------
# r4: the starting roster is the roster minus the ladder top, in both
#     spellings. This IS the escalation-only rule: the top alias must not be
#     offerable as a configured starting tier.
# ---------------------------------------------------------------------------
case " $ALLOC_START_MODELS " in
  *" $last "*) fail "r4: the ladder top ($last) is offered as a starting tier — it is escalation-only" ;;
esac
case " $ALLOC_START_MODELS_DESC " in
  *" $last "*) fail "r4: the ladder top ($last) is offered as a starting tier in the reversed spelling" ;;
esac
for m in $ALLOC_MODELS; do
  [ "$m" = "$last" ] && continue
  case " $ALLOC_START_MODELS " in
    *" $m "*) ;;
    *) fail "r4: $m is a legal starting tier but missing from ALLOC_START_MODELS" ;;
  esac
  case " $ALLOC_START_MODELS_DESC " in
    *" $m "*) ;;
    *) fail "r4: $m is missing from ALLOC_START_MODELS_DESC" ;;
  esac
done
echo "ok: r4 the starting roster is the roster minus the escalation-only top"

# ---------------------------------------------------------------------------
# r5: both maps fail closed off the roster rather than defaulting to a tier.
# ---------------------------------------------------------------------------
out=$(alloc_model_rank 'gpt-9' 2>&1) && fail "r5: an unknown alias resolved to a rank"
[ -z "$out" ] || fail "r5: the unknown-alias path printed '$out' instead of nothing"
out=$(alloc_model_at "$((ALLOC_MODEL_TOP + 1))" 2>&1) && fail "r5: a rank past the top resolved to an alias"
[ -z "$out" ] || fail "r5: the out-of-range path printed '$out' instead of nothing"
out=$(alloc_model_at -1 2>&1) && fail "r5: a negative rank resolved to an alias"
[ -z "$out" ] || fail "r5: the negative-rank path printed '$out' instead of nothing"
echo "ok: r5 both roster maps fail closed off the roster"

# ---------------------------------------------------------------------------
# r6: NON-VACUITY. r1 is the whole point of this file, so prove it can fail:
#     source a copy of the ladder whose roster has a model INSERTED mid-list
#     and assert the by-name pin no longer holds. Without this, r1 would keep
#     passing if the roster were ever derived from something that renumbered
#     silently, and nothing here would notice.
# ---------------------------------------------------------------------------
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
#     Anchored on the cheapest alias rather than the whole roster line: the
#     roster is append-only, so matching it in full would make a legitimate
#     append fail this control even though the contract still holds.
sed "s/^ALLOC_MODELS='haiku /ALLOC_MODELS='haiku inserted /" \
  "$LADDER" >"$tmp/mutated.sh"
grep -q "inserted" "$tmp/mutated.sh" \
  || fail "r6: the mutation did not apply — the roster line no longer matches, so this control proves nothing"
mutated_rank=$(
  # shellcheck source=/dev/null
  . "$tmp/mutated.sh"
  alloc_model_rank opus
)
[ "$mutated_rank" = 2 ] \
  && fail "r6: opus still ranks 2 after a model was inserted below it — the rank is not the roster's index, so r1 cannot catch an insertion"
echo "ok: r6 an inserted model renumbers the ranks, so r1 is a check that can fail"

echo "ok: allocation-ladder roster contract (6 groups)"
