# shellcheck shell=sh
# shellcheck disable=SC2034 # every variable here is read by the scripts sourcing it
# review-backtest-lib.sh — the vocabulary and row rules the backtest corpus
# scripts share (review-backtest.sh, review-backtest-refresh.sh,
# review-corpus-screen.sh, review-cost.sh). Sourced, never run.
#
# One definition of the corpus columns, the miss-reason classes, the category
# and label-source vocabularies, the miss-ledger grammar, and the catch rule,
# so the writer, the screen, and the readers cannot drift apart.

# The corpus header, tab-separated, in column order.
RBT_HEADER='id	pr	commit	path	line	category	reason	replayable	label_source	gist	dismissal'

# A class is a row's miss reason. The miss-ledger grammar's reason tokens are
# the same list.
RBT_REASONS='outside-diff runtime-tracing claim-vs-code pruned spec-conflict lintable declined other'

RBT_CATEGORIES='correctness security portability error-handling concurrency tests docs performance style other'

# Where a row's labels came from: an annotating model, a miss-ledger entry, a
# match against the PR body's declined log, or the `other` fallback for a fixed
# finding with no ledger entry.
RBT_LABEL_SOURCES='model ledger declined-log fallback'

# The catch rule: a finding citing the row's file within this many lines of
# the row's line catches the row. Fixed before the baseline run; changing it
# invalidates every recorded baseline.
RBT_CATCH_LINES=10

RBT_DEFAULT_CAP=5

# jq definitions over the normalized PR history (review-backtest-refresh.sh
# documents its shape). A fixed external finding is a review thread opened by
# someone other than the PR's author and answered by the author with a fix
# reply; the same predicate feeds the corpus and the finding-rate metric.
# shellcheck disable=SC2016 # jq program text, expanded by jq, not the shell
RBT_JQ_DEFS='
def rbt_fix_reply: test("^\\W*(fixed|addressed|applied|corrected|reworded)\\b"; "i")
  or test("\\b(fixed|addressed|applied|corrected|reworded|changed|wrapped|done) in `?[0-9a-f]{7,40}`?\\b"; "i")
  or ((test("\\b(fixed|addressed|applied)\\b"; "i") or test("\\bin `?[0-9a-f]{7,40}`?\\b"))
      and (test("\\b(declin|not fixed|won.t fix|false positive|deferr)"; "i") | not));
def rbt_fixed_external($author): (.author // "") != $author
  and any(.replies[]?; (.author // "") == $author and ((.body // "") | rbt_fix_reply));
def rbt_external_reviewed: . as $pr
  | any(.reviews[]?; (.author // "") != $pr.author)
    or any(.threads[]?; (.author // "") != $pr.author);
'

# rbt_in_list <word> <space-separated list> — 0 when word is a member.
rbt_in_list() {
  case " $2 " in
    *" $1 "*) return 0 ;;
  esac
  return 1
}

# rbt_is_uint <value> — 0 for a positive decimal integer with no leading zero.
rbt_is_uint() {
  case $1 in
    '' | 0* | *[!0-9]*) return 1 ;;
  esac
  return 0
}

# rbt_is_sha <value> — 0 for a full 40-hex lowercase commit id.
rbt_is_sha() {
  [ "${#1}" -eq 40 ] || return 1
  case $1 in
    *[!0-9a-f]*) return 1 ;;
  esac
  return 0
}

# rbt_safe_relpath <path> — 0 for a repository-relative path: not empty, not
# absolute or home-relative, no `..` segment, no leading dash, no control byte
# or whitespace other than a plain space.
rbt_safe_relpath() {
  case $1 in
    '' | /* | '~'* | -* | ../* | */../* | */.. | ..) return 1 ;;
  esac
  _rsr_bad=$(printf '%s' "$1" | LC_ALL=C tr -d '[:print:]')
  [ -z "$_rsr_bad" ] || return 1
  case $1 in
    *'	'*) return 1 ;;
  esac
  return 0
}

# rbt_latest_version <corpus-root> — print the highest N of a v<N> directory
# holding a corpus.tsv, or nothing when none exists.
rbt_latest_version() {
  _rlv_max=
  for _rlv_d in "$1"/v*; do
    [ -f "$_rlv_d/corpus.tsv" ] || continue
    _rlv_n=${_rlv_d##*/v}
    rbt_is_uint "$_rlv_n" || continue
    if [ -z "$_rlv_max" ] || [ "$_rlv_n" -gt "$_rlv_max" ]; then
      _rlv_max=$_rlv_n
    fi
  done
  [ -n "$_rlv_max" ] && printf '%s\n' "$_rlv_max"
  return 0
}
