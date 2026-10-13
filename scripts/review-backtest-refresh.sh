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
#      `ledger`), read from the observation entries and archive alike, in the
#      grammar review-backtest-lib.sh's rbt_read_ledger parses;
#   2. the same finding in the latest earlier version (same PR, path, line,
#      and commit), whose category, gist, class and dismissal are carried; a
#      ledger entry for it that now exists replaces only the class and its
#      label source;
#   3. a match against the PR body's declined log, judged by the annotator
#      (`declined-log`), carrying a paraphrased dismissal;
#   4. otherwise reason `other` (`fallback`), counted and reported so ledger
#      coverage is visible; with --label-reasons the annotator assigns the
#      class instead (`model`), the bootstrap used where no ledger exists yet.
#
# HYGIENE. Every gist and dismissal is a paraphrase written by the annotator,
# except the fixed dismissal a declined row gets when none was recorded. One
# sharing an eight-word run with the comment or the reply it came from,
# or containing the whole of either when it is short, is dropped as verbatim;
# one naming any login the history holds is dropped too. Both checks run on
# carried rows as well, so a rule added later reaches the rows already held. The written rows
# then pass review-corpus-screen.sh with the product-name list required; a
# refused row is dropped. Every drop is counted. The list lives in the
# machine-local state home and this script refuses to run without it.
# Reviewer logins, comment text, and PR bodies never reach stdout or stderr.
#
# REPLAYABLE. Each row's PR head ref (refs/pull/<N>/head) is fetched from the
# remote into a temporary bare mirror; a row whose pre-fix commit is not in
# that ref's history, whose PR has no head ref, or whose commit shares no
# history with the remote's main (a PR from before a history rewrite, which
# leaves no base to diff against), or that is already on main (a PR merged with
# its commits, which leaves an empty change) is marked unreplayable.
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
#     "truncated", "threads": [{"path", "line", "side", "commit", "author",
#                  "bot", "body", "replies": [{"author", "body"}]}]}]}
# A thread on the base side of the diff (side LEFT) points at a line HEAD no
# longer has, so it is skipped with the malformed locations; a PR whose
# reviews, threads, or comments exceeded the fetch's page is counted as
# truncated.
# Every PR number must be a positive integer, or the run is refused. A dump
# holds raw review text and logins: keep it outside the repository.
# --fetch-only stops after the fetch and the dump, writing no corpus and
# needing neither the name list nor an annotator (review-cost.sh uses it).
#
# Usage:
#   review-backtest-refresh.sh [--history <file> | --repo <owner/name>]
#       [--remote <url-or-path>] [--corpus-root <dir>] [--ledger-dir <dir>]...
#       [--names <file>] [--annotate-cmd <executable>] [--batch <n>]
#       [--label-reasons] [--dump-history <file>]
#   review-backtest-refresh.sh --fetch-only --dump-history <file>
#       [--repo <owner/name>]
#
#   --corpus-root   default tests/fixtures/review-backtest in this checkout
#   --ledger-dir    default the observation entries and archive under the
#                   spec root
#   --names         default $CLAUDE_PLUGIN_DATA/review-backtest/product-names.txt
#   --remote        default https://github.com/<repo>.git
#   --batch         annotation requests per annotator call, default 20
#
# Exit codes: 0 a new version written (or, with --fetch-only, the history
#   dumped); 1 gh, a git fetch, or the annotator failed, another refresh
#   claimed the same version first, or the screened rows still fail the
#   screen; 2 usage, a
#   missing name list, an unreadable or malformed history (a non-integer PR
#   number included), or a refresh that would write zero rows.
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
         [--corpus-root <dir>] [--ledger-dir <dir>]... [--names <file>]
         [--annotate-cmd <executable>] [--batch <n>] [--label-reasons]
         [--dump-history <file>]
       $prog --fetch-only --dump-history <file> [--repo <owner/name>]
EOF
  exit 2
}
die() {
  printf '%s\n' "$prog: $2" >&2
  exit "$1"
}

tmp=$(mktemp -d "${TMPDIR:-/tmp}/rbt-refresh.XXXXXX")
claimed=
apid=
# A version claimed but never filled is removed; an interrupt also ends a
# running annotator, which runs in the background so the TERM can reach it.
trap 'rm -rf "$tmp"; [ -z "$claimed" ] || [ -f "$claimed/corpus.tsv" ] || rm -rf "$claimed"' EXIT
trap '[ -z "$apid" ] || kill "$apid" 2>/dev/null; exit 130' INT
trap '[ -z "$apid" ] || kill "$apid" 2>/dev/null; exit 143' TERM

history=
repo=
remote=
corpus_root=$repo_root/tests/fixtures/review-backtest
: >"$tmp/ledger-dirs"
names=
annotate=$here/review-backtest-annotate.sh
batch=20
label_reasons=false
fetch_only=0
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
        --ledger-dir) printf '%s\n' "$2" >>"$tmp/ledger-dirs" ;;
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
    --fetch-only)
      fetch_only=1
      shift
      ;;
    *) usage ;;
  esac
done
rbt_is_uint "$batch" || die 2 "--batch must be a positive integer"

if [ "$fetch_only" -eq 1 ]; then
  [ -n "$dump" ] || die 2 "--fetch-only needs --dump-history <file>"
  [ -z "$history" ] || die 2 "--fetch-only fetches; it takes no --history"
else
  if [ -z "$names" ]; then
    [ -n "${CLAUDE_PLUGIN_DATA:-}" ] \
      || die 2 "no product-name list: pass --names or set CLAUDE_PLUGIN_DATA (the list lives at <state home>/review-backtest/product-names.txt)"
    names=${CLAUDE_PLUGIN_DATA%/}/review-backtest/product-names.txt
  fi
  [ -f "$names" ] && [ -r "$names" ] \
    || die 2 "the product-name list is missing; the refresh refuses to run without it (one name per line, kept machine-local, never committed)"
  [ -x "$annotate" ] || die 2 "the annotate command is not an executable file"
  if [ ! -s "$tmp/ledger-dirs" ]; then
    spec_root=$("$here/resolve-root.sh" spec) || die 2 "cannot resolve the spec root for the miss ledger; pass --ledger-dir"
    printf '%s\n%s\n' "$spec_root/_observations/entries" "$spec_root/_observations/archive" >"$tmp/ledger-dirs"
  fi
fi

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
        reviews(first: 60) { totalCount nodes { author { login __typename } submittedAt } }
        reviewThreads(first: 100) { totalCount nodes { path originalLine diffSide
          comments(first: 40) { totalCount nodes { author { login __typename } body originalCommit { oid } } } } }
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
        truncated: ((.reviews.totalCount // 0) > (.reviews.nodes | length)
          or (.reviewThreads.totalCount // 0) > (.reviewThreads.nodes | length)
          or any(.reviewThreads.nodes[]; (.comments.totalCount // 0) > (.comments.nodes | length))),
        reviews: [ .reviews.nodes[] | { author: who, bot: (.author.__typename == "Bot"), submitted_at: .submittedAt } ],
        threads: [ .reviewThreads.nodes[] | select((.comments.nodes | length) > 0) | {
          path, line: .originalLine, side: (.diffSide // "RIGHT"),
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
[ "$fetch_only" -eq 0 ] || exit 0
[ -n "$repo" ] || repo=$(jq -r '.repo // ""' "$tmp/history.json")
if [ -z "$remote" ]; then
  case $repo in
    */*) remote=https://github.com/$repo.git ;;
    *) die 2 "no --remote and the history names no repository" ;;
  esac
fi
case $remote in -*) die 2 "--remote may not begin with a dash" ;; esac

# --- candidates: every fixed external finding with a well-formed location ----

jq -c "$RBT_JQ_DEFS"'
  def declined_lines: split("\n") | reduce .[] as $l ({in: false, out: []};
    if ($l | test("^\\s*(#{1,6}\\s|\\*\\*[^*]+\\*\\*:?\\s*$)")) then .in = ($l | test("declin"; "i"))
    elif .in then .out += [$l] else . end) | .out;
  def wellformed: (.commit | type == "string" and test("^[0-9a-f]{40}$"))
    and ((.side // "RIGHT") != "LEFT")
    and (.line | type == "number" and . == floor and . >= 1)
    and (.path | type == "string" and length > 0 and (test("^[/~-]") | not)
         and (test("(^|/)\\.\\.(/|$)") | not) and (test("[^ -~]") | not));
  .prs[] | . as $pr | ($pr.body | declined_lines) as $dl
  | $pr.threads[] | select(rbt_fixed_external($pr.author))
  | { pr: $pr.number, path, line, commit, finding: (.body | if type == "string" then . else "" end),
      reply: ([ .replies[] | select(.author == $pr.author and (.body | type == "string") and (.body | rbt_fix_reply)) | .body ][0] // ""),
      declined_log: ((.path // "") as $p | ($p | split("/") | last) as $base
        | [ $dl[] | select($base != "" and index($base)) | .[0:300] ][0:5]),
      ok: wellformed }
' "$tmp/history.json" >"$tmp/cand-all.jsonl" || die 2 "could not read the PR history"
jq -c 'select(.ok) | del(.ok) | .key = "\(.pr):\(.path):\(.line):\(.commit)"' "$tmp/cand-all.jsonl" >"$tmp/cand-dup.jsonl"
# Two reviewers flagging one line of one commit are one finding to replay; the
# first thread stands for both.
jq -c -s 'reduce .[] as $c ({seen: {}, out: []}; if .seen[$c.key] then . else .seen[$c.key] = true | .out += [$c] end) | .out[]' \
  "$tmp/cand-dup.jsonl" >"$tmp/cand.jsonl"
duplicates=$(($(wc -l <"$tmp/cand-dup.jsonl") - $(wc -l <"$tmp/cand.jsonl")))
truncated=$(jq '[.prs[] | select(.truncated == true)] | length' "$tmp/history.json")
malformed_loc=$(jq -c 'select(.ok | not)' "$tmp/cand-all.jsonl" | wc -l | tr -d ' ')
jq -c '[ .prs[] | .author, (.reviews[]?.author), (.threads[]? | .author, (.replies[]?.author)) ]
  | map(select(type == "string") | ascii_downcase | sub("\\[bot\\]$"; "") | select(length >= 3 and . != "ghost")) | unique' \
  "$tmp/history.json" >"$tmp/logins.json"

# --- the miss ledger ---------------------------------------------------------

set --
while IFS= read -r d; do set -- "$@" "$d"; done <"$tmp/ledger-dirs"
rbt_read_ledger "$tmp/ledger.tsv" "$@"
malformed_miss=$RBT_LEDGER_MALFORMED
jq -R -s -c '[ split("\n")[] | select(length > 0) | split("\t") | {key: "\(.[0]):\(.[1])", reason: .[2]} ]
  | map({(.key): .reason}) | add // {}' "$tmp/ledger.tsv" >"$tmp/ledger.json"

# --- the latest earlier version ----------------------------------------------

prev=$(rbt_latest_version "$corpus_root")
# The next version is past every v<N> directory, a filled one or an abandoned
# empty claim alike, so a refresh that died mid-publish never blocks the next.
next=$(($(rbt_highest_version_dir "$corpus_root") + 1))
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
    "$annotate" <"$b" >"$tmp/answer.part" &
    apid=$!
    arc=0
    wait "$apid" || arc=$?
    apid=
    [ "$arc" -eq 0 ] || die 1 "the annotate command failed"
    # Keep only JSON objects; an annotator's chatter around them is ignored.
    jq -c -R 'fromjson? | select(type == "object" and (.key | type) == "string")' "$tmp/answer.part" >>"$tmp/answers.jsonl" || true
  done
fi

# --- the replayable flag -----------------------------------------------------

mirror=$tmp/mirror.git
git init -q --bare "$mirror"
jq -r '.pr' "$tmp/cand.jsonl" | sort -un >"$tmp/prs.txt"
git ls-remote "$remote" 'refs/pull/*/head' >"$tmp/heads.txt" 2>/dev/null || die 1 "git ls-remote failed against the remote"
: >"$tmp/refspecs.txt"
git -C "$mirror" fetch -q --no-tags "$remote" "+refs/heads/main:refs/heads/main" || die 1 "git fetch of the remote's main failed"
awk -F '\t' 'FILENAME == ARGV[1] { want[$1] = 1; next }
  { n = $2; sub(/^refs\/pull\//, "", n); sub(/\/head$/, "", n); if (n in want) printf "+refs/pull/%s/head:refs/backtest/pr/%s\n", n, n }' \
  "$tmp/prs.txt" "$tmp/heads.txt" >"$tmp/refspecs.txt"
if [ -s "$tmp/refspecs.txt" ]; then
  split -l 200 "$tmp/refspecs.txt" "$tmp/refs."
  for r in "$tmp"/refs.*; do
    # shellcheck disable=SC2046 # one refspec per line, no spaces by construction
    git -C "$mirror" fetch -q --no-tags "$remote" $(cat "$r") || die 1 "git fetch of the PR head refs failed"
  done
fi
jq -r '[.key, (.pr | tostring), .commit] | join("\t")' "$tmp/cand.jsonl" | while IFS='	' read -r key n commit; do
  flag=no
  if git -C "$mirror" rev-parse -q --verify "refs/backtest/pr/$n" >/dev/null 2>&1 \
    && git -C "$mirror" merge-base --is-ancestor "$commit" "refs/backtest/pr/$n" 2>/dev/null \
    && git -C "$mirror" merge-base "$commit" main >/dev/null 2>&1 \
    && ! git -C "$mirror" merge-base --is-ancestor "$commit" main 2>/dev/null; then
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
  --slurpfile logins "$tmp/logins.json" \
  --arg reasons "$RBT_REASONS" --arg categories "$RBT_CATEGORIES" --argjson label "$label_reasons" '
  def words: ascii_downcase | [scan("[a-z0-9]+")];
  def shingles: . as $w | [range(0; ($w | length) - 7) | $w[.:(. + 8)] | join(" ")];
  def copies($src): ($src | words) as $sw | (. | words) as $gw
    | (($gw | shingles) - (($gw | shingles) - ($sw | shingles)) | length > 0)
      or (($sw | length) >= 3 and (($gw | join(" ")) | contains($sw | join(" "))))
      or (($sw | length) > 0 and $gw == $sw);
  def verbatim($c): copies($c.finding) or copies($c.reply);
  def names_login: (ascii_downcase | [scan("[a-z0-9][a-z0-9_-]*")]) as $t | any($logins[0][]; . as $l | $t | index([$l]) != null);
  def text: type == "string" and length > 0;
  def oneline: gsub("[\\t\\r\\n]+"; " ") | gsub("^ +| +$"; "");
  ($reasons | split(" ")) as $R | ($categories | split(" ")) as $C
  | . as $c | ($ledger[0]["\($c.pr):\($c.path)"]) as $lr
  | ($replay[0][$c.key] // "no") as $rp
  | if $prev[0][$c.key] then
      $prev[0][$c.key] as $p
      | ($lr // $p.reason) as $reason
      | if ($p.gist | verbatim($c)) or ($p.dismissal != "-" and ($p.dismissal | verbatim($c))) then {status: "verbatim"}
        elif ($p.gist | names_login) or ($p.dismissal != "-" and ($p.dismissal | names_login)) then {status: "login"}
        else
      {status: "carried", pr, path, line, commit, replayable: $rp, category: $p.category,
         reason: $reason, label_source: (if $lr then "ledger" else $p.label_source end), gist: $p.gist,
         dismissal: (if $reason != "declined" then "-"
                     elif $p.dismissal != "-" then $p.dismissal
                     else "the convergence pass declined it" end)}
        end
    else
      ($ans[0][$c.key]) as $a
      | if ($a | type) != "object" or (($a.gist // null) | text | not)
           or (($a.category // null) as $k | any($C[]; . == $k) | not) then {status: "unannotated"}
        else
          ($a.gist | oneline) as $g
          | (if $a.declined == true and (($a.dismissal // null) | text) then ($a.dismissal | oneline) else null end) as $d
          | (if $lr then {reason: $lr, src: "ledger"}
             elif $d then {reason: "declined", src: "declined-log"}
             elif $label and (($a.reason // null) as $k | any($R[]; . == $k)) then {reason: $a.reason, src: "model"}
             else {reason: "other", src: "fallback"} end) as $lab
          | if ($g | verbatim($c)) or ($d and ($d | verbatim($c))) then {status: "verbatim"}
            elif ($g | names_login) or ($d and ($d | names_login)) then {status: "login"}
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

# Joined with tabs, never @tsv: @tsv escapes a backslash, and a carried row
# read back raw would gain one more on every refresh.
jq -r 'select(.pr != null) | [.pr, .path, .line, .commit, .category, .reason, .replayable, .label_source, .gist, .dismissal]
  | map(tostring) | join("\t")' \
  "$tmp/rows.jsonl" | sort -t '	' -k1,1n -k2,2 -k3,3n -k4,4 \
  | awk -F '\t' '{ printf "r%04d\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n", NR, $1, $4, $2, $3, $5, $6, $7, $8, $9, $10 }' \
    >"$tmp/body.tsv"
[ -s "$tmp/body.tsv" ] || die 2 "the refresh would write zero rows; nothing written"
{
  printf '%s\n' "$RBT_HEADER"
  cat "$tmp/body.tsv"
} >"$tmp/corpus.tsv"

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

# mkdir claims the version atomically; the file is staged beside it and
# renamed within the same filesystem, so a reader never sees a partial corpus.
dest=$corpus_root/v$next
mkdir -p "$corpus_root"
# not-a-lock: claims the new version directory once; it is never released or waited on
mkdir "$dest" 2>/dev/null || die 1 "could not create corpus version v$next (it exists, or the corpus root is not writable); nothing written"
claimed=$dest
cp "$tmp/corpus.tsv" "$dest/.corpus.tsv.partial"
mv "$dest/.corpus.tsv.partial" "$dest/corpus.tsv"

unrep=$(awk -F '\t' 'NR > 1 && $8 == "no"' "$dest/corpus.tsv" | wc -l | tr -d ' ')
fallback=$(awk -F '\t' 'NR > 1 && $9 == "fallback"' "$dest/corpus.tsv" | wc -l | tr -d ' ')
printf '%s\n' "$prog: wrote corpus v$next ($kept rows)"
printf '%s\n' "  candidates: $(wc -l <"$tmp/cand.jsonl" | tr -d ' ')"
printf '%s\n' "  carried: $(count carried)"
printf '%s\n' "  ledger-labelled: $(count ledger)"
printf '%s\n' "  declined-log: $(count declined)"
printf '%s\n' "  model-labelled: $(count model)"
printf '%s\n' "  fallback other: $fallback"
printf '%s\n' "  unreplayable: $unrep"
printf '%s\n' "  dropped unannotated: $(count unannotated)"
printf '%s\n' "  dropped verbatim: $(count verbatim)"
printf '%s\n' "  dropped naming a login: $(count login)"
printf '%s\n' "  dropped by screen: $screened"
printf '%s\n' "  skipped malformed location: $malformed_loc"
printf '%s\n' "  merged duplicate threads: $duplicates"
if [ "$truncated" -gt 0 ]; then
  printf '%s\n' "$prog: warning: $truncated PR(s) had more reviews, threads, or comments than one fetch page holds; their extra findings are missing" >&2
fi
if [ "$malformed_miss" -gt 0 ]; then
  printf '%s\n' "$prog: warning: $malformed_miss malformed review-miss fragment(s) ignored (grammar: review-miss(<lens>, <reason>): #<pr> <path>: ...)" >&2
fi
