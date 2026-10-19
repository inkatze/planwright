# shellcheck shell=sh
# shellcheck disable=SC2034 # every variable here is read by the scripts sourcing it
# review-backtest-lib.sh — the vocabulary and row rules the backtest corpus
# scripts share (review-backtest.sh, review-backtest-refresh.sh,
# review-backtest-annotate.sh, review-corpus-screen.sh, review-cost.sh).
# Sourced, never run.
#
# One definition of the corpus columns, the miss-reason classes, the category
# and label-source vocabularies, the miss-ledger grammar, and the catch rule,
# so the writer, the screen, and the readers cannot drift apart.

# The corpus header, tab-separated, in column order.
RBT_HEADER='id	pr	commit	path	line	category	reason	replayable	label_source	gist	dismissal'

# A class is a row's miss reason. The miss-ledger grammar's reason tokens are
# the same list.
RBT_REASONS='outside-diff runtime-tracing claim-vs-code pruned spec-conflict lintable declined other'

# The miss-ledger grammar's lens tokens (doctrine/review-independence.md).
RBT_LENSES='correctness security error-handling performance concurrency naming documentation tests cross-file sibling-sweep reviewer-basics other'

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
# An explicit "<verb> in <sha>" is a fix, even beside a partial decline, unless
# the reply also negates such a phrase anywhere (not, never, cannot, or a
# negative contraction up to two words before the verb, as in "has not been
# fixed in");
# any other fix wording counts only when the reply neither declines nor negates
# a fix verb ("not a false positive" is no decline).
def rbt_negation: "((^|[^a-z])(not|never|cannot)|[a-z]n[\\x27\u2019]t)( [a-z]+){0,2} ";
def rbt_fix_verbs: "(fixed|addressed|applied|corrected|reworded|changed|wrapped|done)";
def rbt_fix_reply: gsub("\\s+"; " ") | (test("\\b" + rbt_fix_verbs + " in `?[0-9a-f]{7,40}`?\\b"; "i")
    and (test(rbt_negation + rbt_fix_verbs + " in `?[0-9a-f]{7,40}`?\\b"; "i") | not))
  or ((test("^\\W*(fixed|addressed|applied|corrected|reworded)\\b"; "i")
       or test("\\b(fixed|addressed|applied)\\b"; "i") or test("\\bin `?[0-9a-f]{7,40}`?\\b"))
      and (test("\\b(declin|won.t fix|deferr)|(?<!not a )false positive"; "i") | not) and (test(rbt_negation + rbt_fix_verbs + "\\b"; "i") | not));
def rbt_fixed_external($author): (.author // "") != $author
  and any(.replies[]?; (.author // "") == $author and (.body | type == "string") and (.body | rbt_fix_reply));
def rbt_bot_reviewed: any(.reviews[]?; .bot == true) or any(.threads[]?; .bot == true);
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
# absolute or home-relative, no `..` segment, no leading dash, and printable
# ASCII only (no control byte, tab, or byte a bidi override could hide in).
# The screen's awk and the refresh's jq apply the same rule.
rbt_safe_relpath() {
  case $1 in
    '' | /* | '~'* | -* | ../* | */../* | */.. | ..) return 1 ;;
  esac
  _rsr_bad=$(printf '%s' "$1" | LC_ALL=C tr -d ' -~')
  [ -z "$_rsr_bad" ]
}

# rbt_miss_row <text> — parse one miss-ledger entry text (the fragment line
# after its `- <date> [<scope>] ` prefix) under the grammar
# doctrine/review-independence.md states:
# `review-miss(<lens>, <reason>): #<pr> <path>: <description>`. Print
# `<pr><TAB><path><TAB><reason><TAB><lens>` and return 0, or set RBT_MISS_WHY
# and return 1.
rbt_miss_row() {
  RBT_MISS_WHY=
  _rmr_row=$(printf '%s\n' "$1" | sed -n 's/^review-miss(\([a-z0-9][a-z0-9-]*\), \([a-z-]*\)): #\([1-9][0-9]*\) \([^ :][^ :]*\): [^ ].*$/\3	\4	\2	\1/p')
  case $1 in
    *"
"*) _rmr_row= ;;
  esac
  if [ -z "$_rmr_row" ]; then
    RBT_MISS_WHY='does not match review-miss(<lens>, <reason>): #<pr> <path>: <description>'
    return 1
  fi
  _rmr_lens=$(printf '%s\n' "$_rmr_row" | cut -f4)
  _rmr_reason=$(printf '%s\n' "$_rmr_row" | cut -f3)
  if ! rbt_in_list "$_rmr_lens" "$RBT_LENSES"; then
    RBT_MISS_WHY="lens '$_rmr_lens' is not one of: $RBT_LENSES"
    return 1
  fi
  if ! rbt_in_list "$_rmr_reason" "$RBT_REASONS"; then
    RBT_MISS_WHY="reason '$_rmr_reason' is not one of: $RBT_REASONS"
    return 1
  fi
  if ! rbt_safe_relpath "$(printf '%s\n' "$_rmr_row" | cut -f2)"; then
    RBT_MISS_WHY='the path is not repository-relative'
    return 1
  fi
  printf '%s\n' "$_rmr_row"
}

# rbt_miss_fragment <file> — classify an observation fragment for the miss
# ledger. Return 1 when it is no miss: its slug is not review-miss and its
# entry text does not begin with review-miss. Otherwise print the entry text
# and return 0, or return 2 when it claims to be a miss but cannot be read or
# carries the text under another slug (RBT_MISS_WHY says which).
rbt_miss_fragment() {
  RBT_MISS_WHY=
  _rmf_named=0
  case ${1##*/} in
    ????-??-??-review-miss-????????.md) _rmf_named=1 ;;
  esac
  _rmf_rc=0
  _rmf_line=$(sed -n '1p' "$1" 2>/dev/null) || _rmf_rc=$?
  if [ "$_rmf_rc" -ne 0 ] || [ ! -r "$1" ]; then
    RBT_MISS_WHY='the fragment cannot be read'
    return 2
  fi
  _rmf_text=$(printf '%s\n' "$_rmf_line" | sed -n 's/^- [0-9-]* \[[^]]*\] //p')
  case $_rmf_text in
    review-miss*) ;;
    *)
      [ "$_rmf_named" -eq 1 ] || return 1
      RBT_MISS_WHY='its first line is not a review-miss entry'
      return 2
      ;;
  esac
  if [ "$_rmf_named" -ne 1 ]; then
    RBT_MISS_WHY='a review-miss entry must use the review-miss slug'
    return 2
  fi
  printf '%s\n' "$_rmf_text"
}

# rbt_read_ledger <out-tsv> <dir>... — parse every miss-ledger fragment in the
# given observation directories (entries and archive both: a drained fragment
# is still a recorded miss) into `<pr><TAB><path><TAB><reason><TAB><lens>`
# rows, by rbt_miss_fragment and rbt_miss_row, the grammar
# scripts/check-review-miss.sh guards. A miss that breaks the grammar, or
# cannot be read, is counted in RBT_LEDGER_MALFORMED, never read. A fragment is
# read once even when a drain left it in both directories for a moment (the
# filename carries its UID).
rbt_read_ledger() {
  _rrl_out=$1
  shift
  : >"$_rrl_out"
  RBT_LEDGER_MALFORMED=0
  _rrl_seen=" "
  for _rrl_d in "$@"; do
    [ -d "$_rrl_d" ] || continue
    for _rrl_f in "$_rrl_d"/*.md; do
      [ -f "$_rrl_f" ] || continue
      case $_rrl_seen in *" ${_rrl_f##*/} "*) continue ;; esac
      _rrl_seen="$_rrl_seen${_rrl_f##*/} "
      _rrl_rc=0
      _rrl_text=$(rbt_miss_fragment "$_rrl_f") || _rrl_rc=$?
      [ "$_rrl_rc" -ne 1 ] || continue
      _rrl_row=
      [ "$_rrl_rc" -ne 0 ] || _rrl_row=$(rbt_miss_row "$_rrl_text") || _rrl_row=
      if [ -z "$_rrl_row" ]; then
        RBT_LEDGER_MALFORMED=$((RBT_LEDGER_MALFORMED + 1))
        continue
      fi
      printf '%s\n' "$_rrl_row" >>"$_rrl_out"
    done
  done
}

# rbt_highest_version_dir <corpus-root> — print the highest N of any v<N>
# directory, filled or not, or 0 when none exists.
rbt_highest_version_dir() {
  _rhv_max=0
  for _rhv_d in "$1"/v*; do
    [ -d "$_rhv_d" ] || continue
    _rhv_n=${_rhv_d##*/v}
    rbt_is_uint "$_rhv_n" || continue
    [ "$_rhv_n" -le "$_rhv_max" ] || _rhv_max=$_rhv_n
  done
  printf '%s\n' "$_rhv_max"
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
