#!/bin/sh
# review-backtest-refresh.sh — rebuild the review backtest corpus into a new
# version from this repository's PR history plus the miss ledger
# (review-effectiveness REQ-H1.2, REQ-E1.5, D-7, D-8, D-16).
#
# OPERATOR-LOCAL, NEVER CI. It reads the PR history with the operator's own
# GitHub login, fetches pull-request head refs, and sends review comments to
# an annotating command for paraphrase; it is registered as an `eval:` task so
# check:no-ci-evals keeps it out of CI.
#
# A ROW is one fixed external finding: a review thread opened by someone other
# than the PR's author and answered by the author with a fix reply ("Fixed
# in", "Addressed in", "Applied in"). Its pre-fix commit is the commit the
# thread was opened on, its line the thread's line in that commit. Findings
# that live only in a review body carry no path or line and are not rows.
#
# LABELS, in order:
#   1. a miss-ledger fragment keyed on the PR number and path (label source
#      `ledger`): `review-miss(<lens>, <reason>): #<pr> <path>: ...`;
#   2. the same finding in the latest earlier version (same PR, path, line,
#      and commit), whose labels, gist and dismissal are carried unchanged, so
#      a refresh never relabels a row it already holds;
#   3. a match against the PR body's declined log, judged by the annotator
#      (`declined-log`), carrying a paraphrased dismissal;
#   4. otherwise reason `other` (`fallback`), counted and reported so ledger
#      coverage is visible; with --label-reasons the annotator assigns the
#      class instead (`model`), the bootstrap used where no ledger exists yet.
#
# HYGIENE. Every gist and dismissal is a paraphrase written by the annotator.
# A paraphrase sharing an eight-word run with the comment or reply it came
# from, or containing the whole of a short one, is dropped as verbatim. The
# written rows then pass review-corpus-screen.sh with the product-name list
# required; a refused row is dropped. Both drops are counted. The list lives
# in the machine-local state home and this script refuses to run without it.
# Reviewer logins, comment text, and PR bodies never reach stdout or stderr.
#
# REPLAYABLE. Each row's PR head ref (refs/pull/<N>/head) is fetched from the
# remote into a temporary bare mirror; a row whose pre-fix commit is not in
# that ref's history, whose PR has no head ref, or whose commit shares no
# history with the remote's main (a PR from before a history rewrite, which
# leaves no base to diff against) is marked unreplayable.
#
# THE ANNOTATOR is an executable reading JSON lines on stdin, one request per
# row: {key, pr, path, line, finding, reply, declined_log, label_reason}. It
# prints one JSON line per request: {key, category, gist, declined,
# dismissal?, reason?} (reason only when label_reason is true). The default is
# review-backtest-annotate.sh beside this script. A request it does not answer
# validly is dropped and counted.
#
# THE HISTORY is fetched with `gh api graphql` (merged PRs, their reviews and
# review threads) unless --history names a recorded file of the normalized
# shape this script writes with --dump-history:
#   {"repo": "<owner>/<name>", "prs": [{"number", "author", "merged_at", "body",
#     "reviews": [{"author", "bot", "submitted_at"}],
#     "threads": [{"path", "line", "commit", "author", "bot", "body",
#                  "replies": [{"author", "body"}]}]}]}
# Every PR number must be a positive integer, or the run is refused.
#
# Usage:
#   review-backtest-refresh.sh [--history <file> | --repo <owner/name>]
#       [--remote <url-or-path>] [--corpus-root <dir>] [--ledger-dir <dir>]
#       [--names <file>] [--annotate-cmd <executable>] [--batch <n>]
#       [--label-reasons] [--dump-history <file>]
#
#   --corpus-root   default tests/fixtures/review-backtest in this checkout
#   --ledger-dir    default the observation entries under the spec root
#   --names         default $CLAUDE_PLUGIN_DATA/review-backtest/product-names.txt
#   --remote        default https://github.com/<repo>.git
#   --batch         annotation requests per annotator call, default 20
#
# Exit codes: 0 a new version written; 1 the annotator or a git fetch failed,
#   or the screened rows still fail the screen; 2 usage, a missing name list,
#   an unreadable or malformed history (a non-integer PR number included), or
#   a refresh that would write zero rows.
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

prog=review-backtest-refresh
here=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$here/.." && pwd)
# shellcheck source=scripts/review-backtest-lib.sh
. "$here/review-backtest-lib.sh"

usage() {
  cat >&2 <<EOF
usage: $prog [--history <file> | --repo <owner/name>] [--remote <url-or-path>]
         [--corpus-root <dir>] [--ledger-dir <dir>] [--names <file>]
         [--annotate-cmd <executable>] [--batch <n>] [--label-reasons]
         [--dump-history <file>]
EOF
  exit 2
}
die() {
  printf '%s\n' "$prog: $2" >&2
  exit "$1"
}

history=
repo=
remote=
corpus_root=$repo_root/tests/fixtures/review-backtest
ledger_dir=
names=
annotate=$here/review-backtest-annotate.sh
batch=20
label_reasons=false
dump=
while [ $# -gt 0 ]; do
  case $1 in
    --history | --repo | --remote | --corpus-root | --ledger-dir | --names | --annotate-cmd | --batch | --dump-history)
      [ $# -ge 2 ] || usage
      case $1 in
        --history) history=$2 ;;
        --repo) repo=$2 ;;
        --remote) remote=$2 ;;
        --corpus-root) corpus_root=$2 ;;
        --ledger-dir) ledger_dir=$2 ;;
        --names) names=$2 ;;
        --annotate-cmd) annotate=$2 ;;
        --batch) batch=$2 ;;
        --dump-history) dump=$2 ;;
      esac
      shift 2
      ;;
    --label-reasons)
      label_reasons=true
      shift
      ;;
    *) usage ;;
  esac
done
rbt_is_uint "$batch" || die 2 "--batch must be a positive integer"

if [ -z "$names" ]; then
  [ -n "${CLAUDE_PLUGIN_DATA:-}" ] \
    || die 2 "no product-name list: pass --names or set CLAUDE_PLUGIN_DATA (the list lives at <state home>/review-backtest/product-names.txt)"
  names=${CLAUDE_PLUGIN_DATA%/}/review-backtest/product-names.txt
fi
[ -f "$names" ] && [ -r "$names" ] \
  || die 2 "the product-name list is missing; the refresh refuses to run without it (one name per line, kept machine-local, never committed)"
[ -x "$annotate" ] || die 2 "the annotate command is not an executable file"

if [ -z "$ledger_dir" ]; then
  spec_root=$("$here/resolve-root.sh" spec) || die 2 "cannot resolve the spec root for the miss ledger; pass --ledger-dir"
  ledger_dir=$spec_root/_observations/entries
fi

tmp=$(mktemp -d "${TMPDIR:-/tmp}/rbt-refresh.XXXXXX")
trap 'rm -rf "$tmp"' EXIT INT TERM

# --- the history -------------------------------------------------------------

fetch_history() {
  if [ -z "$repo" ]; then
    repo=$(gh repo view --json nameWithOwner --jq .nameWithOwner) || die 1 "gh could not name the repository; pass --repo"
  fi
  case $repo in
    */*) ;;
    *) die 2 "--repo must be <owner>/<name>" ;;
  esac
  # shellcheck disable=SC2016 # GraphQL variables, not shell expansions
  q='query($owner: String!, $name: String!, $endCursor: String) {
  repository(owner: $owner, name: $name) {
    pullRequests(states: MERGED, first: 20, after: $endCursor, orderBy: {field: CREATED_AT, direction: ASC}) {
      pageInfo { hasNextPage endCursor }
      nodes {
        number mergedAt body author { login }
        reviews(first: 60) { nodes { author { login __typename } submittedAt } }
        reviewThreads(first: 100) { nodes { path originalLine
          comments(first: 40) { nodes { author { login __typename } body originalCommit { oid } } } } }
      }
    }
  }
}'
  gh api graphql --paginate -F owner="${repo%%/*}" -F name="${repo#*/}" -f query="$q" >"$tmp/pages.json" \
    || die 1 "gh api graphql failed fetching the PR history"
  jq -s --arg repo "$repo" '
    def who: (.author.login // "ghost");
    { repo: $repo,
      prs: [ .[].data.repository.pullRequests.nodes[] | {
        number, author: who, merged_at: .mergedAt, body: (.body // ""),
        reviews: [ .reviews.nodes[] | { author: who, bot: (.author.__typename == "Bot"), submitted_at: .submittedAt } ],
        threads: [ .reviewThreads.nodes[] | select((.comments.nodes | length) > 0) | {
          path, line: .originalLine,
          commit: (.comments.nodes[0].originalCommit.oid // null),
          author: (.comments.nodes[0] | who),
          bot: (.comments.nodes[0].author.__typename == "Bot"),
          body: (.comments.nodes[0].body // ""),
          replies: [ .comments.nodes[1:][] | { author: who, body: (.body // "") } ] } ] } ] }
  ' "$tmp/pages.json" >"$tmp/history.json" || die 1 "could not normalize the fetched PR history"
}

if [ -n "$history" ]; then
  [ -f "$history" ] && [ -r "$history" ] || die 2 "the history file is not readable"
  cp "$history" "$tmp/history.json"
else
  fetch_history
fi
jq -e 'type == "object" and (.prs | type == "array")' "$tmp/history.json" >/dev/null 2>&1 \
  || die 2 "the history is not the normalized shape (an object with a prs array)"
jq -e '.prs | all(.number | type == "number" and . == floor and . > 0)' "$tmp/history.json" >/dev/null 2>&1 \
  || die 2 "the history carries a PR number that is not a positive integer; refused"
[ -z "$dump" ] || cp "$tmp/history.json" "$dump"
[ -n "$repo" ] || repo=$(jq -r '.repo // ""' "$tmp/history.json")
if [ -z "$remote" ]; then
  case $repo in
    */*) remote=https://github.com/$repo.git ;;
    *) die 2 "no --remote and the history names no repository" ;;
  esac
fi

# --- candidates: every fixed external finding with a well-formed location ----

jq -c "$RBT_JQ_DEFS"'
  def declined_lines: split("\n") | reduce .[] as $l ({in: false, out: []};
    if ($l | test("^\\s*(#{1,6}\\s|\\*\\*[^*]+\\*\\*:?\\s*$)")) then .in = ($l | test("declin"; "i"))
    elif .in then .out += [$l] else . end) | .out;
  def wellformed: (.commit | type == "string" and test("^[0-9a-f]{40}$"))
    and (.line | type == "number" and . == floor and . >= 1)
    and (.path | type == "string" and length > 0 and (test("^[/~-]") | not)
         and (test("(^|/)\\.\\.(/|$)") | not) and (test("[[:cntrl:]]") | not));
  .prs[] | . as $pr | ($pr.body | declined_lines) as $dl
  | $pr.threads[] | select(rbt_fixed_external($pr.author))
  | { pr: $pr.number, path, line, commit, finding: .body,
      reply: ([ .replies[] | select(.author == $pr.author and (.body | rbt_fix_reply)) | .body ][0] // ""),
      declined_log: ((.path // "") as $p | ($p | split("/") | last) as $base
        | [ $dl[] | select($base != "" and index($base)) | .[0:300] ][0:5]),
      ok: wellformed }
' "$tmp/history.json" >"$tmp/cand-all.jsonl" || die 2 "could not read the PR history"
jq -c 'select(.ok) | del(.ok) | .key = "\(.pr):\(.path):\(.line):\(.commit)"' "$tmp/cand-all.jsonl" >"$tmp/cand.jsonl"
malformed_loc=$(jq -c 'select(.ok | not)' "$tmp/cand-all.jsonl" | wc -l | tr -d ' ')

# --- the miss ledger ---------------------------------------------------------

: >"$tmp/ledger.tsv"
malformed_miss=0
if [ -d "$ledger_dir" ]; then
  for f in "$ledger_dir"/*.md; do
    [ -f "$f" ] || continue
    grep -q 'review-miss' "$f" || continue
    line=$(grep -m1 'review-miss' "$f")
    parsed=$(printf '%s\n' "$line" | sed -n 's/^- [0-9-]* \[[^]]*\] review-miss(\([a-z0-9-]*\), \([a-z-]*\)): #\([1-9][0-9]*\) \([^ :][^ :]*\): .*$/\3	\4	\2	\1/p')
    reason=$(printf '%s\n' "$parsed" | cut -f3)
    if [ -z "$parsed" ] || ! rbt_in_list "$reason" "$RBT_REASONS" || ! rbt_safe_relpath "$(printf '%s\n' "$parsed" | cut -f2)"; then
      malformed_miss=$((malformed_miss + 1))
      continue
    fi
    printf '%s\n' "$parsed" >>"$tmp/ledger.tsv"
  done
fi
jq -R -s -c '[ split("\n")[] | select(length > 0) | split("\t") | {key: "\(.[0]):\(.[1])", reason: .[2]} ]
  | map({(.key): .reason}) | add // {}' "$tmp/ledger.tsv" >"$tmp/ledger.json"

# --- the latest earlier version ----------------------------------------------

prev=$(rbt_latest_version "$corpus_root")
next=$((${prev:-0} + 1))
if [ -n "$prev" ]; then
  jq -R -s -c '[ split("\n")[1:][] | select(length > 0) | split("\t")
    | {key: "\(.[1]):\(.[3]):\(.[4]):\(.[2])", category: .[5], reason: .[6], label_source: .[8], gist: .[9], dismissal: .[10]} ]
    | map({(.key): .}) | add // {}' "$corpus_root/v$prev/corpus.tsv" >"$tmp/prev.json"
else
  printf '{}\n' >"$tmp/prev.json"
fi

# --- annotation of the rows not carried --------------------------------------

jq -c --slurpfile prev "$tmp/prev.json" --argjson label "$label_reasons" '
  select($prev[0][.key] == null)
  | {key, pr, path, line, finding, reply, declined_log, label_reason: $label}
' "$tmp/cand.jsonl" >"$tmp/requests.jsonl"
: >"$tmp/answers.jsonl"
if [ -s "$tmp/requests.jsonl" ]; then
  split -l "$batch" "$tmp/requests.jsonl" "$tmp/batch."
  for b in "$tmp"/batch.*; do
    "$annotate" <"$b" >"$tmp/answer.part" || die 1 "the annotate command failed"
    # Keep only JSON objects; an annotator's chatter around them is ignored.
    jq -c -R 'fromjson? | select(type == "object" and has("key"))' "$tmp/answer.part" >>"$tmp/answers.jsonl" || true
  done
fi

# --- the replayable flag -----------------------------------------------------

mirror=$tmp/mirror.git
git init -q --bare "$mirror"
jq -r '.pr' "$tmp/cand.jsonl" | sort -un >"$tmp/prs.txt"
git ls-remote "$remote" 'refs/pull/*/head' >"$tmp/heads.txt" 2>/dev/null || die 1 "git ls-remote failed against the remote"
: >"$tmp/refspecs.txt"
git -C "$mirror" fetch -q --no-tags "$remote" "+refs/heads/main:refs/heads/main" || die 1 "git fetch of the remote's main failed"
while IFS= read -r n; do
  if grep -q "	refs/pull/$n/head\$" "$tmp/heads.txt"; then
    printf '+refs/pull/%s/head:refs/backtest/pr/%s\n' "$n" "$n" >>"$tmp/refspecs.txt"
  fi
done <"$tmp/prs.txt"
if [ -s "$tmp/refspecs.txt" ]; then
  split -l 200 "$tmp/refspecs.txt" "$tmp/refs."
  for r in "$tmp"/refs.*; do
    # shellcheck disable=SC2046 # one refspec per line, no spaces by construction
    git -C "$mirror" fetch -q --no-tags "$remote" $(cat "$r") || die 1 "git fetch of the PR head refs failed"
  done
fi
: >"$tmp/replay.tsv"
jq -r '[.key, (.pr | tostring), .commit] | @tsv' "$tmp/cand.jsonl" | while IFS='	' read -r key n commit; do
  flag=no
  if git -C "$mirror" rev-parse -q --verify "refs/backtest/pr/$n" >/dev/null 2>&1 \
    && git -C "$mirror" merge-base --is-ancestor "$commit" "refs/backtest/pr/$n" 2>/dev/null \
    && git -C "$mirror" merge-base "$commit" main >/dev/null 2>&1; then
    flag=yes
  fi
  printf '%s\t%s\n' "$key" "$flag"
done >"$tmp/replay.tsv"
jq -R -s -c '[ split("\n")[] | select(length > 0) | split("\t") | {(.[0]): .[1]} ] | add // {}' "$tmp/replay.tsv" >"$tmp/replay.json"

# --- assemble the rows -------------------------------------------------------

jq -s -c 'map({(.key): .}) | add // {}' "$tmp/answers.jsonl" >"$tmp/answers.json"
jq -c \
  --slurpfile prev "$tmp/prev.json" --slurpfile ans "$tmp/answers.json" \
  --slurpfile ledger "$tmp/ledger.json" --slurpfile replay "$tmp/replay.json" \
  --arg reasons "$RBT_REASONS" --arg categories "$RBT_CATEGORIES" --argjson label "$label_reasons" '
  def words: ascii_downcase | [scan("[a-z0-9]+")];
  def shingles: . as $w | [range(0; ($w | length) - 7) | $w[.:(. + 8)] | join(" ")];
  def verbatim($src): ($src | words) as $sw | (. | words) as $gw
    | (($gw | shingles) - (($gw | shingles) - ($sw | shingles)) | length > 0)
      or (($sw | length) >= 3 and (($gw | join(" ")) | contains($sw | join(" "))));
  def oneline: gsub("[\\t\\r\\n]+"; " ") | gsub("^ +| +$"; "");
  ($reasons | split(" ")) as $R | ($categories | split(" ")) as $C
  | . as $c | ($ledger[0]["\($c.pr):\($c.path)"]) as $lr
  | ($replay[0][$c.key] // "no") as $rp
  | if $prev[0][$c.key] then
      $prev[0][$c.key] as $p
      | {status: "carried", pr, path, line, commit, replayable: $rp, category: $p.category,
         reason: ($lr // $p.reason), label_source: (if $lr then "ledger" else $p.label_source end),
         gist: $p.gist, dismissal: (if ($lr // $p.reason) == "declined" then $p.dismissal else "-" end)}
    else
      ($ans[0][$c.key]) as $a
      | if ($a == null) or (($a.gist // "") | type != "string" or length == 0)
           or ([$a.category] | inside($C) | not) then {status: "unannotated"}
        else
          (($a.gist | oneline)) as $g
          | (if ($a.declined == true) and (($a.dismissal // "") | length > 0) then ($a.dismissal | oneline) else null end) as $d
          | (if $lr then {reason: $lr, src: "ledger"}
             elif $d then {reason: "declined", src: "declined-log"}
             elif $label and ([$a.reason] | inside($R)) then {reason: $a.reason, src: "model"}
             else {reason: "other", src: "fallback"} end) as $lab
          | if ($g | verbatim($c.finding + " " + $c.reply)) or ($d and ($d | verbatim($c.finding + " " + $c.reply))) then {status: "verbatim"}
            else
              {status: (if $lab.src == "fallback" then "fallback" elif $lab.src == "ledger" then "ledger" elif $lab.src == "declined-log" then "declined" else "model" end),
               pr, path, line, commit, replayable: $rp, category: $a.category, reason: $lab.reason,
               label_source: $lab.src, gist: $g,
               dismissal: (if $lab.reason == "declined" then ($d // "the convergence pass declined it") else "-" end)}
            end
        end
    end
' "$tmp/cand.jsonl" >"$tmp/rows.jsonl"

count() { jq -c "select(.status == \"$1\")" "$tmp/rows.jsonl" | wc -l | tr -d ' '; }

jq -r 'select(.pr != null) | [.pr, .path, .line, .commit, .category, .reason, .replayable, .label_source, .gist, .dismissal] | @tsv' \
  "$tmp/rows.jsonl" | sort -t '	' -k1,1n -k2,2 -k3,3n -k4,4 \
  | awk -F '\t' 'BEGIN { OFS = "\t" } { printf "r%04d\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n", NR, $1, $4, $2, $3, $5, $6, $7, $8, $9, $10 }' \
    >"$tmp/body.tsv"
{
  printf '%s\n' "$RBT_HEADER"
  cat "$tmp/body.tsv"
} >"$tmp/corpus.tsv"

[ -s "$tmp/body.tsv" ] || die 2 "the refresh would write zero rows; nothing written"

# --- the hygiene screen: drop each refused row, then the rest must pass ------

screened=0
if ! "$here/review-corpus-screen.sh" --names "$names" --require-names "$tmp/corpus.tsv" >/dev/null 2>"$tmp/screen.err"; then
  sed -n 's/^review-corpus-screen: row \(r[0-9]*\): .*/\1/p' "$tmp/screen.err" | sort -u >"$tmp/refused.txt"
  screened=$(wc -l <"$tmp/refused.txt" | tr -d ' ')
  awk -F '\t' 'FILENAME == ARGV[1] { bad[$1] = 1; next } FNR == 1 || !($1 in bad)' "$tmp/refused.txt" "$tmp/corpus.tsv" >"$tmp/corpus.kept"
  mv "$tmp/corpus.kept" "$tmp/corpus.tsv"
  "$here/review-corpus-screen.sh" --names "$names" --require-names "$tmp/corpus.tsv" >/dev/null 2>&1 \
    || die 1 "rows still fail the hygiene screen after dropping the refused ones; nothing written"
fi
kept=$(($(wc -l <"$tmp/corpus.tsv") - 1))
[ "$kept" -gt 0 ] || die 2 "the refresh would write zero rows; nothing written"

# --- publish v<next> ---------------------------------------------------------

dest=$corpus_root/v$next
[ ! -e "$dest" ] || die 1 "corpus version v$next already exists; nothing written"
mkdir -p "$corpus_root"
mkdir "$tmp/v"
cp "$tmp/corpus.tsv" "$tmp/v/corpus.tsv"
mv "$tmp/v" "$dest"

unrep=$(awk -F '\t' 'NR > 1 && $8 == "no"' "$dest/corpus.tsv" | wc -l | tr -d ' ')
fallback=$(awk -F '\t' 'NR > 1 && $9 == "fallback"' "$dest/corpus.tsv" | wc -l | tr -d ' ')
# Every value printed below is an integer from wc or awk.
printf '%s\n' "$prog: wrote corpus v$next ($kept rows)" # trusted: integers and a fixed name
printf '%s\n' "  candidates: $(wc -l <"$tmp/cand.jsonl" | tr -d ' ')"
printf '%s\n' "  carried: $(count carried)"
printf '%s\n' "  ledger-labelled: $(count ledger)"
printf '%s\n' "  declined-log: $(count declined)"
printf '%s\n' "  model-labelled: $(count model)"
printf '%s\n' "  fallback other: $fallback" # trusted: integer from awk
printf '%s\n' "  unreplayable: $unrep"      # trusted: integer from awk
printf '%s\n' "  dropped unannotated: $(count unannotated)"
printf '%s\n' "  dropped verbatim: $(count verbatim)"
printf '%s\n' "  dropped by screen: $screened"               # trusted: integer from wc
printf '%s\n' "  skipped malformed location: $malformed_loc" # trusted: integer from wc
if [ "$malformed_miss" -gt 0 ]; then
  printf '%s\n' "$prog: warning: $malformed_miss malformed review-miss fragment(s) ignored (grammar: review-miss(<lens>, <reason>): #<pr> <path>: ...)" >&2 # trusted: integer
fi
