#!/bin/sh
# inception-review-cycle.sh — the adapter seam for a venture's stakeholder
# review cycle (inception REQ-G1.6, REQ-G1.7, REQ-G1.9 · D-10).
#
# The cycle is one-way: export a snapshot, harvest feedback as data, triage
# each item, apply the accepted ones as attributed commits, re-export. The
# review surface never writes the bundle; doctrine/review-seam.md is the
# normative contract and this script its mechanical shadow.
#
#   export   offer, or with --confirmed perform, an export of the committed
#            bundle through the adapter. Refused while the previous cycle has
#            an export not yet harvested or an item not yet triaged.
#   harvest  read the review surface's feedback through the adapter and add
#            each item it has not seen to the ledger, pending.
#   list     the ledger's items, one per line, sanitized for the terminal.
#   triage   record the operator's disposition of one item: apply or modify
#            (with the bundle section the change may touch) or skip.
#   apply    commit the staged change for an accepted item, after checking it
#            stays inside the triaged section and passes the stakeholder-commit
#            validator; the commit cites the item's source.
#   status   the ledger's cycle, phase, adapter, and pending count.
#
# The ledger is feedback/ledger.md in the venture, tracked: it is the only
# record of what became of each item, because a review surface may offer no
# way to resolve a comment (Notion's API cannot). Harvested text enters it
# quoted, one `> ` line at a time, with control characters stripped, so it
# cannot forge a heading or a field. export, harvest, and triage commit the
# ledger alone, leaving anything else staged as it was;
# apply commits the change and the ledger together. A step that writes the
# ledger refuses to start while it has uncommitted changes, and restores it
# when its own commit fails (an export, already sent, keeps its record). Every
# writing step holds the venture's bundle lock.
#
# Adapters are a closed set (ADAPTERS below), each a sibling script answering
# `status`, `export <venture> <snapshot>`, and `harvest <venture>` with the
# item records doctrine/review-seam.md defines.
#
# Usage:
#   inception-review-cycle.sh export [--adapter <name>] [--confirmed] <venture-dir>
#   inception-review-cycle.sh harvest <venture-dir>
#   inception-review-cycle.sh list [--pending] <venture-dir>
#   inception-review-cycle.sh triage <FB-n> apply|modify|skip --decider <name>
#                                    [--section <file>#<heading>] [--note <text>] <venture-dir>
#   inception-review-cycle.sh apply <FB-n> <venture-dir>
#   inception-review-cycle.sh status <venture-dir>
#
# A section names a bundle file and one of its `##` or `###` headings, by its
# full text or, for a register entry, by its id alone (`assumptions.md#A-2`).
# The gate log and its records are never a section.
#
# Environment: PLANWRIGHT_INCEPTION_TODAY (YYYY-MM-DD) pins today's date.
#
# Exit: 0 done (an unconfirmed export's offer included) · 1 refused by a cycle
#   or guard rule (out of order, untriaged, outside the section, validator,
#   secret screen) · 2 usage or environment error · 3 the adapter failed or
#   has no destination configured.
#
# POSIX sh + awk.
set -u

LC_ALL=C
export LC_ALL
unset CDPATH

script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2

if [ ! -f "$script_dir/echo-safety.sh" ] || [ ! -r "$script_dir/echo-safety.sh" ]; then
  printf '%s\n' "inception-review-cycle: echo-safety.sh is missing or unreadable (broken install)" >&2
  exit 2
fi
# shellcheck source=scripts/echo-safety.sh
. "$script_dir/echo-safety.sh"

# The shared fence lexer (scripts/spec-parse.sh): a heading inside a column-0
# code fence is not a section, by the same rule every bundle reader applies.
for lib in spec-parse.sh lock-lib.sh; do
  if [ ! -f "$script_dir/$lib" ] || [ ! -r "$script_dir/$lib" ]; then
    printf '%s\n' "inception-review-cycle: $lib is missing or unreadable (broken install)" >&2
    exit 2
  fi
done
# shellcheck source=scripts/spec-parse.sh
. "$script_dir/spec-parse.sh" || exit 2
# shellcheck source=scripts/lock-lib.sh
. "$script_dir/lock-lib.sh" || exit 2

ADAPTERS="notion"
BUNDLE_FILES="brief.md disciplines.md assumptions.md decisions.md plan.md"
LEDGER_REL=feedback/ledger.md
LEDGER_VERSION=1

die() {
  code=$1
  shift
  printf 'inception-review-cycle: %s\n' "$*" >&2
  exit "$code"
}

usage() {
  cat >&2 <<'EOF'
usage: inception-review-cycle.sh export [--adapter <name>] [--confirmed] <venture-dir>
       inception-review-cycle.sh harvest <venture-dir>
       inception-review-cycle.sh list [--pending] <venture-dir>
       inception-review-cycle.sh triage <FB-n> apply|modify|skip --decider <name> [--section <file>#<heading>] [--note <text>] <venture-dir>
       inception-review-cycle.sh apply <FB-n> <venture-dir>
       inception-review-cycle.sh status <venture-dir>
EOF
  exit 2
}

# --- arguments ---------------------------------------------------------------

[ $# -ge 1 ] || usage
cmd=$1
shift
case $cmd in
  export | harvest | list | triage | apply | status) ;;
  *) usage ;;
esac

item=
disp=
if [ "$cmd" = triage ] || [ "$cmd" = apply ]; then
  [ $# -ge 1 ] || usage
  item=$1
  shift
  case $item in
    FB-[1-9] | FB-[1-9]*[0-9]) ;;
    *) die 2 "an item id is FB-<n>" ;;
  esac
  case ${item#FB-} in *[!0-9]*) die 2 "an item id is FB-<n>" ;; esac
fi
if [ "$cmd" = triage ]; then
  [ $# -ge 1 ] || usage
  disp=$1
  shift
  case $disp in apply | modify | skip) ;; *) die 2 "a disposition is apply, modify, or skip" ;; esac
fi

adapter_arg=
confirmed=0
pending_only=0
decider=
decider_set=0
section=
note=
target=
while [ $# -gt 0 ]; do
  case $1 in
    --adapter)
      [ "$cmd" = export ] && [ $# -ge 2 ] || usage
      adapter_arg=$2
      shift 2
      ;;
    --confirmed)
      [ "$cmd" = export ] || usage
      confirmed=1
      shift
      ;;
    --pending)
      [ "$cmd" = list ] || usage
      pending_only=1
      shift
      ;;
    --decider)
      [ "$cmd" = triage ] && [ $# -ge 2 ] || usage
      decider=$2
      decider_set=1
      shift 2
      ;;
    --section)
      [ "$cmd" = triage ] && [ $# -ge 2 ] || usage
      section=$2
      shift 2
      ;;
    --note)
      [ "$cmd" = triage ] && [ $# -ge 2 ] || usage
      note=$2
      shift 2
      ;;
    -*) usage ;;
    *)
      [ -z "$target" ] || usage
      target=$1
      shift
      ;;
  esac
done
[ -n "$target" ] || usage
[ -d "$target" ] || die 2 "venture directory not found"
git -C "$target" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
  || die 2 "the venture is not a git work tree; the review cycle records its ledger in commits"
target=$(cd "$target" && pwd -P) || die 2 "cannot resolve the venture directory"
ledger="$target/$LEDGER_REL"

work=$(mktemp -d "${TMPDIR:-/tmp}/inception-review-cycle.XXXXXX") || die 2 "cannot create a scratch directory"
tmpl=
# shellcheck disable=SC2329 # invoked from the EXIT trap
cleanup() {
  rm -rf "$work"
  [ -z "$tmpl" ] || rm -f "$tmpl"
  [ "${restore_on_exit:-0}" = 0 ] || ledger_restore
  pw_lock_release_all
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
tab=$(printf '\t')

# Resolved here rather than inside today(): a die in a command substitution
# leaves only the subshell, and the step would carry on with an empty date.
today_val=${PLANWRIGHT_INCEPTION_TODAY:-}
if [ -n "$today_val" ]; then
  case $today_val in
    [0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]) ;;
    *) die 2 "PLANWRIGHT_INCEPTION_TODAY must be a YYYY-MM-DD date" ;;
  esac
else
  today_val=$(date +%Y-%m-%d)
fi
today() { printf '%s' "$today_val"; }

# oneline <value> <max> — control characters to spaces, trimmed, capped.
oneline() {
  printf '%s' "$1" | tr '\000-\037\177\200-\237' ' ' \
    | awk -v max="$2" '{ s = s (NR > 1 ? " " : "") $0 } END { gsub(/^ +| +$/, "", s); print substr(s, 1, max) }'
}

git_v() { git -C "$target" "$@"; }

# --- the ledger --------------------------------------------------------------

ledger_guard() {
  [ ! -L "$target/feedback" ] || die 1 "feedback/ is a symbolic link; the ledger is not followed out of the venture"
  [ ! -L "$ledger" ] || die 1 "the ledger is a symbolic link; it is not followed out of the venture"
}

# header <Key> — a ledger header value (before `## Items`).
header() {
  [ -f "$ledger" ] || return 0
  awk -v k="$1" '/^## Items/ { exit } index($0, k ": ") == 1 { print substr($0, length(k) + 3); exit }' "$ledger"
}

# ledger_require_clean — a step that writes the ledger starts from the
# committed one: it reads the work-tree copy and commits all of it, so a
# leftover change (a step whose commit failed, a hand edit) would otherwise be
# read as done, or ride into a commit that says something else.
ledger_require_clean() {
  if git_v cat-file -e "HEAD:./$LEDGER_REL" 2>/dev/null; then
    { git_v diff --quiet HEAD -- "$LEDGER_REL" && git_v diff --cached --quiet HEAD -- "$LEDGER_REL"; } \
      || die 1 "$LEDGER_REL has uncommitted changes; commit them (git add $LEDGER_REL && git commit) or discard them (git checkout HEAD -- $LEDGER_REL) first"
  elif [ -e "$ledger" ]; then
    die 1 "$LEDGER_REL exists but was never committed; commit it (git add $LEDGER_REL && git commit) or remove it first"
  fi
}

# ledger_restore — back to the committed ledger after a failed commit; exact,
# since ledger_require_clean held when the step began.
ledger_restore() {
  git_v checkout -q HEAD -- "$LEDGER_REL" 2>/dev/null
}

# fail_restored <what failed> <what a restore leaves true> — restore the
# ledger, then die saying whether that worked.
restore_on_exit=0
fail_restored() {
  restore_on_exit=0
  if ledger_restore; then
    die 2 "$1; the ledger was restored, $2"
  fi
  die 2 "$1, and the ledger could not be restored: discard its changes (git checkout HEAD -- $LEDGER_REL) before a re-run"
}

ledger_check_version() {
  [ -f "$ledger" ] || return 0
  lv=$(header Ledger-version)
  [ "$lv" = "$LEDGER_VERSION" ] \
    || die 2 "the ledger declares Ledger-version '$(sanitize_printable "$lv")'; this planwright reads version $LEDGER_VERSION"
}

# item_get <FB-id> <Key>
item_get() {
  awk -v id="$1" -v k="$2" '
    /^### / { cur = $2; next }
    cur == id && /^Text:/ { cur = "" }
    cur == id && index($0, k ": ") == 1 { print substr($0, length(k) + 3); exit }' "$ledger"
}

item_exists() {
  grep -q "^### $1 — " "$ledger" 2>/dev/null
}

# ledger_rewrite <awk-program-file> — rewrite the ledger through awk, values
# passed in the environment (never -v, which would interpret backslashes).
ledger_rewrite() {
  tmpl=$(mktemp "$target/feedback/.ledger.XXXXXX") || die 2 "cannot write in feedback/"
  if awk -f "$1" "$ledger" >"$tmpl"; then
    mv "$tmpl" "$ledger" || {
      rm -f "$tmpl"
      die 2 "cannot replace the ledger"
    }
    tmpl=
  else
    rm -f "$tmpl"
    die 2 "cannot rewrite the ledger"
  fi
}

# item_set <FB-id> — set the fields named in $SET_KEYS (space-separated) from
# the SET_<Key> environment variables, within that item only.
item_set() {
  cat >"$work/set.awk" <<'EOF'
BEGIN { n = split(ENVIRON["SET_KEYS"], keys, " "); id = ENVIRON["SET_ID"] }
/^### / { cur = $2 }
/^Text:/ { cur = "" }
{
  if (cur == id) {
    for (i = 1; i <= n; i++) {
      if (index($0, keys[i] ": ") == 1) {
        k = keys[i]
        gsub(/-/, "_", k)
        print keys[i] ": " ENVIRON["SET_" k]
        next
      }
    }
  }
  print
}
EOF
  SET_ID=$1
  export SET_ID SET_KEYS
  ledger_rewrite "$work/set.awk"
}

# header_set — the same for header fields.
header_set() {
  cat >"$work/hset.awk" <<'EOF'
BEGIN { n = split(ENVIRON["SET_KEYS"], keys, " ") }
/^## Items/ { body = 1 }
{
  if (!body) {
    for (i = 1; i <= n; i++) {
      if (index($0, keys[i] ": ") == 1) {
        k = keys[i]
        gsub(/-/, "_", k)
        print keys[i] ": " ENVIRON["SET_" k]
        next
      }
    }
  }
  print
}
EOF
  export SET_KEYS
  ledger_rewrite "$work/hset.awk"
}

# commit_paths <message-file> <path>... — commit exactly these paths. A
# partial commit (`--only`) is used only when something else is staged: it
# builds a temporary index, so whatever a pre-commit hook stages lands in the
# commit but not in the real index, which then shows those paths as staged
# reversions (the venture hook's regenerated exports) and jams the next apply.
commit_paths() {
  _msg=$1
  shift
  git_v add -- "$@" || return 1
  _pfx=$(git_v rev-parse --show-prefix) || return 1
  _staged=$(git_v -c core.quotePath=false diff --cached --name-only) || return 1
  _others=$(printf '%s\n' "$_staged" | while IFS= read -r _p; do
    [ -n "$_p" ] || continue
    _mine=0
    for _a in "$@"; do [ "$_p" != "$_pfx$_a" ] || _mine=1; done
    [ "$_mine" = 1 ] || printf '%s\n' "$_p"
  done)
  if [ -z "$_others" ]; then
    # A commit that fails after the pre-commit hook ran (signing, a commit-msg
    # hook) would otherwise leave the hook's staging behind in the real index.
    _tree=$(git_v write-tree) || return 1
    git_v commit -q -F "$_msg" && return 0
    git_v read-tree "$_tree" 2>/dev/null
    return 1
  else
    git_v commit -q --only -F "$_msg" -- "$@"
  fi
}

# --- adapters ----------------------------------------------------------------

resolve_adapter() {
  for a in $ADAPTERS; do
    if [ "$a" = "$1" ]; then
      adapter_bin="$script_dir/inception-$a.sh"
      [ -f "$adapter_bin" ] && [ -r "$adapter_bin" ] || die 2 "the $a adapter is missing from this install"
      return 0
    fi
  done
  die 2 "unknown adapter '$(sanitize_printable "$1")'; adapters: $ADAPTERS"
}

# --- sections ----------------------------------------------------------------

# section_locate <file> <heading> <source-file> — print `<start> <end>` for
# the one heading that matches, or nothing; exit 3 when it is a gate record or
# the gate log, or the file ends inside a code fence; 4 when the match is
# ambiguous.
section_locate() {
  SEC_FILE=$1 SEC_HEAD=$2
  export SEC_FILE SEC_HEAD
  awk '
    BEGIN { want = ENVIRON["SEC_HEAD"]; brief = (ENVIRON["SEC_FILE"] == "brief.md") }
    '"$spec_parse_awk_fence"'
    /^##+ / {
      lvl = match($0, /[^#]/) - 1
      if (lvl > 3) next
      h = $0; sub(/^#+ /, "", h); sub(/[ \t]+$/, "", h)
      if (lvl == 2) top = h
      if (open && lvl <= openlvl) { end = NR - 1; open = 0 }
      if (h == want || index(h, want " — ") == 1) {
        hits++
        start = NR; openlvl = lvl; open = 1; end = 0
        gate = brief && ((lvl == 2 && h == "Gate log") || (lvl == 3 && top == "Gate log"))
      }
    }
    END {
      spec_parse__fence_eof()
      if (hits == 0) exit 0
      if (hits > 1) exit 4
      if (gate) exit 3
      if (open) end = NR
      print start, end
    }' "$3"
}

# section_check <spec> — validate a `<file>#<heading>` against HEAD; sets
# sec_file, sec_head, sec_start, sec_end.
section_check() {
  case $1 in
    *'#'*) ;;
    *) die 2 "a section is <file>#<heading>" ;;
  esac
  sec_file=${1%%#*}
  sec_head=${1#*#}
  ok=0
  for f in $BUNDLE_FILES; do [ "$f" != "$sec_file" ] || ok=1; done
  [ "$ok" = 1 ] || die 1 "a section must be in a bundle file ($BUNDLE_FILES)"
  [ -n "$sec_head" ] || die 2 "a section names a heading"
  git_v show "HEAD:./$sec_file" >"$work/sec.src" 2>/dev/null || die 1 "$sec_file is not committed at HEAD"
  loc=$(section_locate "$sec_file" "$sec_head" "$work/sec.src")
  case $? in
    0) ;;
    3) die 1 "the gate log and its records are never changed through the review cycle, and a section is never read past an unclosed code fence" ;;
    4) die 1 "more than one heading in $sec_file matches '$(sanitize_printable "$sec_head")'; give the full heading" ;;
    *) die 2 "cannot read $sec_file" ;;
  esac
  [ -n "$loc" ] || die 1 "no heading '$(sanitize_printable "$sec_head")' in $sec_file at HEAD"
  sec_start=${loc%% *}
  sec_end=${loc#* }
}

# --- snapshot ----------------------------------------------------------------

venture_title() {
  t=$(git_v show HEAD:./brief.md 2>/dev/null | sed -n '1s/^# \(.*\) — Brief$/\1/p')
  sanitize_printable "$t" "this venture"
}

build_snapshot() {
  sha=$(git_v rev-parse HEAD) || die 2 "the venture has no commit to export"
  title=$(venture_title)
  {
    printf '> Review copy of %s at commit %s, exported %s. Comment on anything here. Edits to this page are not read back, and the next export replaces it.\n\n' \
      "$title" "$(printf '%s' "$sha" | cut -c1-12)" "$(today)"
    for f in $BUNDLE_FILES; do
      git_v show "HEAD:./$f" || die 2 "$f is not committed at HEAD"
      printf '\n'
    done
  } >"$1"
}

bundle_clean() {
  for f in $BUNDLE_FILES; do
    git_v diff --quiet HEAD -- "$f" 2>/dev/null || return 1
  done
}

pending_items() {
  awk '/^### / { cur = $2 } /^Text:/ { cur = "" } cur != "" && $0 == "Disposition: pending" { print cur }' "$ledger" 2>/dev/null
}

# --- export ------------------------------------------------------------------

cmd_export() {
  ledger_guard
  ledger_check_version
  ledger_require_clean
  existing=$(header Adapter)
  if [ -n "$existing" ] && [ -n "$adapter_arg" ] && [ "$existing" != "$adapter_arg" ]; then
    die 2 "this venture's ledger runs through the $(sanitize_printable "$existing") adapter"
  fi
  adapter=${adapter_arg:-$existing}
  [ -n "$adapter" ] || die 2 "the first export names its adapter: --adapter <name> ($ADAPTERS)"
  resolve_adapter "$adapter"

  if [ -f "$ledger" ]; then
    phase=$(header Phase)
    cycle=$(header Cycle)
    if [ "$phase" = exported ]; then
      die 1 "cycle $cycle was exported and not yet harvested in full; harvest it first, since a re-export replaces the page and may drop feedback nobody has read"
    fi
    pend=$(pending_items | tr '\n' ' ' | sed 's/ $//')
    [ -z "$pend" ] || die 1 "triage every item before the next export; pending: $pend"
  fi
  bundle_clean || die 1 "the bundle has uncommitted changes; an export is a snapshot of a commit, so commit or discard them first"

  snap="$work/snapshot.md"
  build_snapshot "$snap"
  /bin/sh "$script_dir/inception-secret-screen.sh" -- "$snap" >"$work/screen.out" 2>&1
  case $? in
    0) ;;
    1) die 1 "the snapshot looks like it carries a credential; it is not exported (the screen names no text, only that it matched)" ;;
    *) die 2 "the secret screen could not run" ;;
  esac

  dest=$(sh "$adapter_bin" status "$target" 2>/dev/null | awk -F"$tab" '$1 == "page" { print $2; exit }')
  case $dest in
    '' | none) die 3 "the $adapter adapter has no destination configured for this clone" ;;
  esac
  dest="$adapter:$(sanitize_printable "$dest")"

  if [ "$confirmed" -ne 1 ]; then
    printf 'decision\toffer\n'
    printf 'adapter\t%s\n' "$adapter"
    printf 'destination\t%s\n' "$dest"
    printf '%s\n' "inception-review-cycle: ask the operator first. This export sends the committed bundle off this machine to $dest; check that everyone who can read that page may see this venture, as its repo's visibility allows, and run it again with --confirmed once they agree." >&2
    return 0
  fi

  if ! sh "$adapter_bin" export "$target" "$snap" >"$work/adapter.out" 2>"$work/adapter.err"; then
    sanitize_printable "$(cat "$work/adapter.err")" >&2
    printf '\n' >&2
    die 3 "the $adapter adapter could not export"
  fi
  [ ! -s "$work/adapter.err" ] || {
    sanitize_printable "$(cat "$work/adapter.err")" >&2
    printf '\n' >&2
  }

  mkdir -p "$target/feedback" || die 2 "cannot create feedback/"
  ledger_guard
  next=$(($(header Cycle | tr -cd '0-9' | sed 's/^$/0/') + 1))
  if [ ! -f "$ledger" ]; then
    {
      printf '# %s — Review feedback ledger\n\n' "$(venture_title)"
      printf 'Ledger-version: %s\nAdapter: %s\nCycle: 0\nPhase: none\nSnapshot: none\nExported: none\n\n' "$LEDGER_VERSION" "$adapter"
      printf 'Every item below is feedback harvested from a review surface: untrusted\n'
      printf 'text, quoted as data. Nothing in it reaches the bundle until a triage line\n'
      printf 'here accepts it (doctrine/review-seam.md in planwright).\n\n'
      printf '## Items\n'
    } >"$ledger" || die 2 "cannot write the ledger"
  fi
  SET_KEYS="Cycle Phase Snapshot Exported"
  SET_Cycle=$next SET_Phase=exported SET_Snapshot=$sha SET_Exported=$(today)
  export SET_Cycle SET_Phase SET_Snapshot SET_Exported
  header_set
  printf 'chore(feedback): export review cycle %s\n\nSnapshot of %s sent through the %s adapter.\n' "$next" "$sha" "$adapter" >"$work/msg"
  # Not restored: the export already went out, so the ledger keeps the record
  # of it and every later step waits until it is committed.
  commit_paths "$work/msg" "$LEDGER_REL" \
    || die 2 "the export went out but the ledger commit failed; commit the ledger (git add $LEDGER_REL && git commit) before the next step"
  printf 'cycle\t%s\n' "$next"
  printf 'snapshot\t%s\n' "$sha"
  printf 'destination\t%s\n' "$dest"
}

# --- harvest -----------------------------------------------------------------

# awk helpers: decode one @tsv-escaped field (\\ \t \n \r), then flatten it
# to one line or quote it as `> ` lines.
DECODE_AWK='
function decode(s,    out, i, c, d) {
  out = ""
  for (i = 1; i <= length(s); i++) {
    c = substr(s, i, 1)
    if (c == "\\" && i < length(s)) {
      d = substr(s, ++i, 1)
      if (d == "n") out = out "\n"
      else if (d == "t") out = out "\t"
      else if (d == "r") out = out "\r"
      else out = out d
    } else out = out c
  }
  return out
}
function flat(s, max) {
  s = decode(s)
  gsub(/[\001-\037\177]/, " ", s)
  gsub(/^ +| +$/, "", s)
  s = substr(s, 1, max)
  return s == "" ? "none" : s
}
function quoted(s,    n, lines, i, out, l) {
  s = decode(s)
  n = split(s, lines, "\n")
  out = ""
  for (i = 1; i <= n; i++) {
    l = lines[i]
    gsub(/\t/, "    ", l)
    gsub(/[\001-\037\177]/, "", l)
    out = out (l == "" ? ">" : "> " l) "\n"
  }
  if (n == 0) out = ">\n"
  return out
}
'

cmd_harvest() {
  [ -f "$ledger" ] || die 1 "nothing has been exported yet; export a snapshot first, then harvest its feedback"
  ledger_guard
  ledger_check_version
  ledger_require_clean
  phase=$(header Phase)
  cycle=$(header Cycle)
  case $phase in
    exported | harvested) ;;
    *) die 1 "nothing has been exported yet; export a snapshot first, then harvest its feedback" ;;
  esac
  adapter=$(header Adapter)
  resolve_adapter "$adapter"
  if ! sh "$adapter_bin" harvest "$target" >"$work/records" 2>"$work/adapter.err"; then
    sanitize_printable "$(cat "$work/adapter.err")" >&2
    printf '\n' >&2
    die 3 "the $adapter adapter could not harvest"
  fi
  [ ! -s "$work/adapter.err" ] || {
    sanitize_printable "$(cat "$work/adapter.err")" >&2
    printf '\n' >&2
  }
  walk=$(awk -F"$tab" '$1 == "summary" { print $2; exit }' "$work/records")
  case $walk in
    complete | partial) ;;
    *) die 3 "the $adapter adapter's harvest ended without its summary line; nothing was recorded" ;;
  esac

  grep '^Source: ' "$ledger" | sed 's/^Source: //' >"$work/seen"
  maxn=$(grep '^### FB-' "$ledger" | sed 's/^### FB-\([0-9]*\).*/\1/' | sort -n | tail -1)
  HV_CYCLE=$cycle HV_MAX=${maxn:-0} HV_SEEN="$work/seen" HV_COUNT="$work/count"
  export HV_CYCLE HV_MAX HV_SEEN HV_COUNT
  awk -F"$tab" "$DECODE_AWK"'
    BEGIN {
      while ((getline s < ENVIRON["HV_SEEN"]) > 0) seen[s] = 1
      n = ENVIRON["HV_MAX"] + 0
    }
    $1 != "item" || NF < 8 { next }
    {
      src = $2
      if (src !~ /^[a-z]+:[a-z]+:[A-Za-z0-9-]+$/ || (src in seen)) next
      seen[src] = 1
      th = ($3 ~ /^[A-Za-z0-9-]+$/) ? $3 : "none"
      an = ($6 ~ /^[A-Za-z0-9-]+$/) ? $6 : "none"
      cr = ($5 ~ /^[0-9TZ:.+-]+$/) ? $5 : "none"
      text = $8
      for (i = 9; i <= NF; i++) text = text "\\t" $i
      n++
      printf "\n### FB-%d — %s\n\n", n, src
      printf "Source: %s\nThread: %s\nAuthor: %s\nCreated: %s\nAnchor: %s\nAnchor-text: %s\n", src, th, flat($4, 120), cr, an, flat($7, 80)
      printf "Cycle: %s\nDisposition: pending\nSection: none\nDecider: none\nDecided: none\nApplied: none\nNote: none\n\nText:\n\n%s", ENVIRON["HV_CYCLE"], quoted(text)
      added++
    }
    END { print added + 0 > ENVIRON["HV_COUNT"] }' "$work/records" >"$work/new" \
    || die 2 "cannot read the adapter's records; nothing was recorded"
  added=$(cat "$work/count")
  case $added in '' | *[!0-9]*) die 2 "cannot count the harvested items; nothing was recorded" ;; esac

  # Only a complete walk counts as harvested: the next export replaces the
  # page, and a partial one has left feedback unread.
  if [ "$walk" = complete ]; then new_phase=harvested; else new_phase=exported; fi
  if [ "$added" -eq 0 ] && [ "$phase" = "$new_phase" ]; then
    :
  else
    # From the append on, any exit before the commit puts the ledger back.
    restore_on_exit=1
    cat "$work/new" >>"$ledger" || die 2 "cannot append to the ledger"
    SET_KEYS="Phase" SET_Phase=$new_phase
    export SET_Phase
    header_set
    printf 'chore(feedback): harvest review cycle %s\n\n%s new item(s) recorded pending triage; the walk was %s.\n' "$cycle" "$added" "$walk" >"$work/msg"
    commit_paths "$work/msg" "$LEDGER_REL" \
      || fail_restored "the ledger commit failed" "so a re-run harvests the same items"
    restore_on_exit=0
  fi
  printf 'cycle\t%s\n' "$cycle"
  printf 'new\t%s\n' "$added"
  printf 'walk\t%s\n' "$walk"
  [ "$walk" = complete ] \
    || printf '%s\n' "inception-review-cycle: the harvest was partial; feedback past the adapter's bound was not read, so the next export waits for a complete harvest" >&2
}

# --- list / status -----------------------------------------------------------

cmd_list() {
  [ -f "$ledger" ] || return 0
  ledger_guard
  ledger_check_version
  LS_PENDING=$pending_only
  export LS_PENDING
  awk -v OFS="$tab" '
    function flush() {
      if (cur != "" && (!ENVIRON["LS_PENDING"] || d == "pending")) print cur, d, a, substr(t, 1, 72)
    }
    /^### FB-/ { flush(); cur = $2; d = ""; a = ""; t = ""; intext = 0; next }
    cur == "" { next }
    /^Disposition: / { d = substr($0, 14) }
    /^Author: / { a = substr($0, 9) }
    /^Text:/ { intext = 1; next }
    intext && /^>/ { l = $0; sub(/^> ?/, "", l); t = t (t == "" ? "" : " ") l }
    END { flush() }' "$ledger" | tr -d '\000-\010\013-\037\177\200-\237'
}

cmd_status() {
  if [ ! -f "$ledger" ]; then
    printf 'cycle\t0\nphase\tnone\nadapter\tnone\npending\t0\n'
    return 0
  fi
  ledger_guard
  ledger_check_version
  printf 'cycle\t%s\n' "$(sanitize_printable "$(header Cycle)")"
  printf 'phase\t%s\n' "$(sanitize_printable "$(header Phase)")"
  printf 'adapter\t%s\n' "$(sanitize_printable "$(header Adapter)")"
  printf 'pending\t%s\n' "$(pending_items | grep -c .)"
}

# --- triage ------------------------------------------------------------------

cmd_triage() {
  [ -f "$ledger" ] || die 1 "the ledger has no items yet"
  ledger_guard
  ledger_check_version
  ledger_require_clean
  [ "$decider_set" = 1 ] || die 2 "triage records who decided: --decider <name>"
  dec=$(oneline "$decider" 120)
  [ -n "$dec" ] || die 2 "--decider must name someone"
  case $disp in
    apply | modify) [ -n "$section" ] || die 2 "an accepted item names the section it may change: --section <file>#<heading>" ;;
    skip) [ -z "$section" ] || die 2 "a skipped item changes nothing, so it takes no --section" ;;
  esac
  [ "$disp" != modify ] || [ -n "$note" ] || die 2 "a modify records how the change departs from the feedback: --note <text>"
  item_exists "$item" || die 1 "no item $item in the ledger"
  cur=$(item_get "$item" Disposition)
  [ "$cur" = pending ] || die 1 "$item was already triaged ($(sanitize_printable "$cur"))"
  if [ -n "$section" ]; then
    section_check "$section"
    # Stored as given: section_check has matched it to one heading line, and
    # apply matches it again, so any rewrite here would strand the item.
    sec_val=$section
  else
    sec_val=none
  fi
  nt=$(oneline "$note" 300)
  SET_KEYS="Disposition Section Decider Decided Note"
  SET_Disposition=$disp SET_Section=$sec_val SET_Decider=$dec SET_Decided=$(today) SET_Note=${nt:-none}
  export SET_Disposition SET_Section SET_Decider SET_Decided SET_Note
  item_set "$item"
  printf 'chore(feedback): triage %s as %s\n\nDecided by %s.\n' "$item" "$disp" "$dec" >"$work/msg"
  commit_paths "$work/msg" "$LEDGER_REL" \
    || fail_restored "the ledger commit failed" "so the item is still pending"
  printf 'item\t%s\ndisposition\t%s\nsection\t%s\n' "$item" "$disp" "$sec_val"
}

# --- apply -------------------------------------------------------------------

cmd_apply() {
  [ -f "$ledger" ] || die 1 "the ledger has no items yet"
  ledger_guard
  ledger_check_version
  ledger_require_clean
  item_exists "$item" || die 1 "no item $item in the ledger"
  d=$(item_get "$item" Disposition)
  case $d in
    apply | modify) ;;
    pending) die 1 "$item has not been triaged; nothing is applied until triage accepts it" ;;
    skip) die 1 "$item was triaged as skip; there is nothing to apply" ;;
    *) die 1 "$item has no accepting disposition ($(sanitize_printable "$d"))" ;;
  esac
  [ "$(item_get "$item" Applied)" = none ] || die 1 "$item was already applied"
  section_check "$(item_get "$item" Section)"

  staged=$(git_v diff --cached --name-only --relative -- .) || die 2 "cannot read the index"
  staged=$(printf '%s\n' "$staged" | grep -v "^$LEDGER_REL\$" | grep .)
  [ -n "$staged" ] || die 1 "nothing is staged; stage the change for $item in $sec_file first"
  [ "$staged" = "$sec_file" ] || die 1 "only $sec_file may be staged for $item; also staged: $(sanitize_printable "$(printf '%s\n' "$staged" | grep -vx "$sec_file" | tr '\n' ' ')")"
  for f in $BUNDLE_FILES; do
    git_v diff --quiet -- "$f" || die 1 "$f has unstaged changes; the validator reads the work tree, so stage or discard them first"
  done

  git_v diff --cached -U0 -- "$sec_file" >"$work/hunks" || die 2 "cannot read the staged change"
  bad=$(awk -v s="$sec_start" -v e="$sec_end" '
    /^@@ / {
      r = $2; sub(/^-/, "", r)
      n = split(r, p, ",")
      a = p[1] + 0; b = (n > 1) ? p[2] + 0 : 1
      if (b == 0) { if (a < s || a > e) print a }
      else if (a <= s || a + b - 1 > e) print a
    }' "$work/hunks")
  [ -z "$bad" ] || die 1 "the staged change reaches outside $sec_file § $(sanitize_printable "$sec_head") (and the section's heading line is not editable through feedback); restage it inside the section"

  vrc=0
  /bin/sh "$script_dir/inception-validate.sh" --baseline HEAD "$target" >"$work/validate.out" 2>&1 || vrc=$?
  if [ "$vrc" -ne 0 ]; then
    sanitize_printable "$(cat "$work/validate.out")" >&2
    printf '\n' >&2
    case $vrc in
      1) die 1 "the bundle validator refused the change (ids and gate records are untouchable, and the bundle must stay valid)" ;;
      3) die 1 "the bundle validator could not read the changed bundle (an unclosed code fence, a missing file, or its format version), so the change is refused" ;;
      *) die 2 "the bundle validator could not run (exit $vrc)" ;;
    esac
  fi

  src=$(item_get "$item" Source)
  author=$(item_get "$item" Author)
  nt=$(item_get "$item" Note)
  adapter=$(header Adapter)
  SET_KEYS="Applied" SET_Applied=$(today)
  export SET_Applied
  item_set "$item"
  {
    printf 'docs(venture): apply review feedback %s\n\n' "$item"
    printf 'Applies %s feedback to %s § %s, from a %s comment by %s.\n' \
      "$([ "$d" = modify ] && echo modified || echo accepted)" "$sec_file" "$sec_head" "$adapter" "$author"
    [ "$d" != modify ] || printf '\nModified at triage: %s\n' "$nt"
    printf '\nFeedback-Item: %s\nFeedback-Source: %s\nFeedback-Author: %s\n' "$item" "$src" "$author"
  } >"$work/msg"
  commit_paths "$work/msg" "$sec_file" "$LEDGER_REL" \
    || fail_restored "the commit failed" "and the change is still staged"
  printf 'item\t%s\ncommit\t%s\n' "$item" "$(git_v rev-parse HEAD)"
}

# The venture's bundle lock, the one inception-fanout.sh takes: apply writes
# bundle files, and every writing step rewrites the ledger read-modify-write.
case $cmd in
  export | harvest | triage | apply)
    if [ -d "$target/.git" ]; then bl_lock="$target/.git/planwright-bundle.lock"; else bl_lock="$target/.planwright-bundle.lock"; fi
    pw_lock_acquire "$bl_lock" "${PLANWRIGHT_BUNDLE_LOCK_TRIES:-500}" \
      || die 2 "the bundle is busy (another writer holds $bl_lock); try again"
    ;;
esac

case $cmd in
  export) cmd_export ;;
  harvest) cmd_harvest ;;
  list) cmd_list ;;
  status) cmd_status ;;
  triage) cmd_triage ;;
  apply) cmd_apply ;;
esac
