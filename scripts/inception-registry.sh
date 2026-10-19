#!/bin/sh
# inception-registry.sh — the machine-local state the /inception skill keeps
# across ventures: the venture registry, catalog telemetry, and the
# pending-observations drop, plus the status and portfolio views read from
# them (inception REQ-A1.6, REQ-A1.7, REQ-A1.8, REQ-H1.6, REQ-J1.4, REQ-J1.7,
# REQ-J1.8 · D-8).
#
#   add <id> <venture-dir>  register a venture (or refresh its path and status)
#   set <id> [--status <s>] [--flags <f,g>|none]
#                           update a registered venture
#   get <id>                one registry row
#   list                    every registry row
#   rebuild [--root <dir>]  re-derive the registry by scanning ventures_root
#   overlap                 each registered venture's framing, for the skill's
#                           extend-vs-new judgment
#   status <id>             the per-venture status view
#   portfolio [--cards <dir>]
#                           every venture with attention flags, then the
#                           catalog-health notes; writes the flags back
#   telemetry <id> frame-discipline|unstaffed <discipline>
#                           record one catalog-telemetry occurrence
#   drop <id> <text>        record a planwright-about observation
#   drop-read               the drop, neutralized, for planwright-side seed
#                           gathering
#
# Everything lives under one home, interim per D-8 and doctrine/storage-
# classes.md: $PLANWRIGHT_INCEPTION_DATA_DIR when set, else
# $CLAUDE_PLUGIN_DATA/inception. With neither, every subcommand prints a
# `degraded` line and exits 6, and the skill proceeds without the registry
# (REQ-H1.6).
#
# The registry is runtime state, so it must be losable. Every mutation is
# write-temp-then-rename in the registry's own directory, so no reader sees a
# torn file; a lost update from two racing sessions is tolerated, because a
# registry that is missing, torn, or carries a row that fails validation is
# rebuilt from a ventures_root scan the moment it is read, with every
# recovered identifier re-validated (REQ-A1.6, REQ-A1.8). Rows are unscreened
# input: an identifier must pass the venture grammar and the path must be
# absolute and named for it.
#
# Output is `key<TAB>value` lines; bundle and drop text is stripped of control
# bytes and tabs before it is printed.
#
# Exit: 0 success · 1 refused input (an identifier, a status, a flag list, a
#   path, drop text) or an unregistered venture · 2 usage or environment
#   error · 3 the validator refuses to read the venture's bundle (status,
#   passed through) · 6 no plugin-data home, so the registry is unavailable.
#
# Environment: PLANWRIGHT_INCEPTION_TODAY (YYYY-MM-DD) pins today's date;
#   ventures_root resolves through scripts/inception-venture.sh root.
#
# Portable POSIX sh + awk; bash 3.2 / BSD tooling floor (REQ-K1.5).
set -u

LC_ALL=C
export LC_ALL
unset CDPATH

self_dir=$(cd "$(dirname "$0")" && pwd -P) || exit 2

HEADER='# planwright inception registry v1'
STATUSES='Exploring On-hold Graduated Killed Abandoned'
CLOSED='Graduated Killed Abandoned'

usage() {
  cat >&2 <<'EOF'
usage: inception-registry.sh add <id> <venture-dir>
       inception-registry.sh set <id> [--status <status>] [--flags <flag,...>|none]
       inception-registry.sh get <id>
       inception-registry.sh list
       inception-registry.sh rebuild [--root <dir>]
       inception-registry.sh overlap
       inception-registry.sh status <id>
       inception-registry.sh portfolio [--cards <dir>]
       inception-registry.sh telemetry <id> frame-discipline|unstaffed <discipline>
       inception-registry.sh drop <id> <text>
       inception-registry.sh drop-read
EOF
  exit 2
}

die() {
  printf 'inception-registry: %s\n' "$2" >&2
  exit "$1"
}

tmp_path=
cleanup_tmp() {
  if [ -n "$tmp_path" ]; then rm -f "$tmp_path"; fi
}
trap cleanup_tmp EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

printable() { printf '%s' "$1" | tr -d '\000-\037\177\200-\237'; }

today() {
  td=${PLANWRIGHT_INCEPTION_TODAY:-}
  case $td in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) printf '%s\n' "$td" ;;
    *) date +%Y-%m-%d ;;
  esac
}

valid_id() {
  case $1 in
    '' | -* | *[!a-z0-9-]*) return 1 ;;
  esac
  [ "${#1}" -le 64 ]
}

check_id() {
  valid_id "$1" && return 0
  printf 'inception-registry: invalid venture identifier (want ^[a-z0-9][a-z0-9-]*$, at most 64 characters); refused before any use\n' >&2
  exit 1
}

in_list() {
  for w in $2; do [ "$w" = "$1" ] && return 0; done
  return 1
}

valid_flags() {
  [ "$1" = none ] && return 0
  case $1 in
    '' | ,* | *, | *,,* | *[!a-z,-]*) return 1 ;;
  esac
  return 0
}

# --- the data home -----------------------------------------------------------

data_dir=
resolve_data() {
  if [ -n "${PLANWRIGHT_INCEPTION_DATA_DIR:-}" ]; then
    data_dir=$PLANWRIGHT_INCEPTION_DATA_DIR
  elif [ -n "${CLAUDE_PLUGIN_DATA:-}" ]; then
    data_dir=${CLAUDE_PLUGIN_DATA%/}/inception
  else
    printf 'degraded\tthe venture registry is unavailable: no plugin data directory (CLAUDE_PLUGIN_DATA) is set%s\n' "$1"
    exit 6
  fi
  mkdir -p "$data_dir" 2>/dev/null || {
    printf 'degraded\tthe venture registry is unavailable: cannot create its directory%s\n' "$1"
    exit 6
  }
  registry=$data_dir/registry.tsv
}

# write_atomic <dest> — stdin to a temp file beside <dest>, then renamed over
# it: rename is atomic only within one filesystem.
write_atomic() {
  tmp_path=$(mktemp "$data_dir/.registry.XXXXXX") || die 2 "cannot write under the plugin data directory"
  cat >"$tmp_path" || die 2 "cannot write under the plugin data directory"
  chmod 600 "$tmp_path" || die 2 "cannot write under the plugin data directory"
  mv -f "$tmp_path" "$1" || die 2 "cannot write under the plugin data directory"
  tmp_path=
}

# registry_ok — the registry exists and every row passes validation.
registry_ok() {
  [ -f "$registry" ] && [ ! -h "$registry" ] || return 1
  awk -F '\t' -v header="$HEADER" -v statuses="$STATUSES unknown" '
    BEGIN { n = split(statuses, s, " "); for (i = 1; i <= n; i++) ST[s[i]] = 1 }
    NR == 1 { if ($0 != header) exit 1; next }
    {
      if (NF != 5) exit 1
      if ($1 !~ /^[a-z0-9][a-z0-9-]*$/ || length($1) > 64) exit 1
      if ($2 !~ /^\// || $2 ~ /[[:cntrl:]]/ || $2 ~ /(^|\/)\.\.?(\/|$)/) exit 1
      base = $2; sub(/^.*\//, "", base); if (base != $1) exit 1
      if (!($3 in ST)) exit 1
      if ($4 != "none" && $4 !~ /^[a-z-]+(,[a-z-]+)*$/) exit 1
      if ($5 !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/) exit 1
    }
    END { if (NR < 1) exit 1 }
  ' "$registry"
}

# bundle_status <venture-dir> — the brief's declared status, or `unknown`.
bundle_status() {
  bs=$(awk '
    /^\*\*Status:\*\*/ { v = $0; sub(/^\*\*Status:\*\*[ \t]*/, "", v); sub(/[ \t]+$/, "", v); print v; exit }
    /^## / { exit }
  ' "$1/brief.md" 2>/dev/null)
  if in_list "$bs" "$STATUSES"; then printf '%s\n' "$bs"; else printf 'unknown\n'; fi
}

is_bundle() { [ -f "$1/brief.md" ] && [ ! -h "$1/brief.md" ]; }

ventures_root() {
  /bin/sh "$self_dir/inception-venture.sh" root
}

# scan <root> — rebuild the registry from the directories under <root>.
scan() {
  [ -d "$1" ] || {
    printf '%s\n' "$HEADER" | write_atomic "$registry"
    return 0
  }
  d=$(today)
  body=
  for sdir in "$1"/* "$1"/.[!.]*; do
    [ -d "$sdir" ] && [ ! -h "$sdir" ] || continue
    is_bundle "$sdir" || continue
    name=${sdir##*/}
    if ! valid_id "$name"; then
      printf 'rejected\t%s\n' "$(printable "$name")"
      continue
    fi
    body="$body$name	$sdir	$(bundle_status "$sdir")	none	$d
"
  done
  printf '%s\n%s' "$HEADER" "$body" | write_atomic "$registry"
}

# ensure_registry — read-time self-heal (REQ-A1.6): a missing, torn, or
# invalid registry is rebuilt before anything reads it.
ensure_registry() {
  registry_ok && return 0
  if [ -e "$registry" ]; then reason='the registry was unreadable or failed validation'; else reason='there was no registry'; fi
  root=$(ventures_root) || die 2 "cannot resolve ventures_root to rebuild the registry"
  scan "$root" >/dev/null
  printf 'rebuilt\t%s; recovered from a scan of ventures_root\n' "$reason"
}

rows() { awk 'NR > 1' "$registry"; }

row_of() {
  awk -F '\t' -v id="$1" 'NR > 1 && $1 == id { print; found = 1; exit } END { exit !found }' "$registry"
}

# --- subcommands -------------------------------------------------------------

cmd_add() {
  [ $# -eq 2 ] || usage
  check_id "$1"
  dir=$2
  while [ "$dir" != "${dir%/}" ]; do dir=${dir%/}; done
  case $dir in
    /*) ;;
    *) dir=$(cd "$dir" 2>/dev/null && pwd -P) || die 1 "not a directory: $(printable "$2")" ;;
  esac
  case $dir in
    *[[:cntrl:]]* | */./* | */../* | */. | */..) die 1 "the venture path must be a plain absolute path" ;;
  esac
  [ "${dir##*/}" = "$1" ] || die 1 "the venture directory must be named for its identifier"
  is_bundle "$dir" || die 1 "no inception bundle at that path"
  resolve_data ''
  ensure_registry
  st=$(bundle_status "$dir")
  rows | awk -F '\t' -v OFS='\t' -v id="$1" -v path="$dir" -v st="$st" -v d="$(today)" -v header="$HEADER" '
    BEGIN { print header }
    $1 == id { $2 = path; $3 = st; print; done = 1; next }
    { print }
    END { if (!done) print id, path, st, "none", d }
  ' | write_atomic "$registry"
  printf 'registered\t%s\n' "$1"
}

cmd_set() {
  [ $# -ge 1 ] || usage
  id=$1
  shift
  check_id "$id"
  new_status=
  new_flags=
  while [ $# -gt 0 ]; do
    case $1 in
      --status)
        [ $# -ge 2 ] || usage
        in_list "$2" "$STATUSES" || die 1 "status must be one of: $STATUSES"
        new_status=$2
        shift 2
        ;;
      --flags)
        [ $# -ge 2 ] || usage
        valid_flags "$2" || die 1 "flags are a comma-separated list of lowercase words, or none"
        new_flags=$2
        shift 2
        ;;
      *) usage ;;
    esac
  done
  [ -n "$new_status$new_flags" ] || usage
  resolve_data ''
  ensure_registry
  row_of "$id" >/dev/null || die 1 "$id is not registered"
  rows | awk -F '\t' -v OFS='\t' -v id="$id" -v st="$new_status" -v fl="$new_flags" -v header="$HEADER" '
    BEGIN { print header }
    $1 == id { if (st != "") $3 = st; if (fl != "") $4 = fl }
    { print }
  ' | write_atomic "$registry"
}

cmd_get() {
  [ $# -eq 1 ] || usage
  check_id "$1"
  resolve_data ''
  ensure_registry
  r=$(row_of "$1") || die 1 "$1 is not registered"
  printf 'venture\t%s\n' "$r"
}

cmd_list() {
  [ $# -eq 0 ] || usage
  resolve_data ''
  ensure_registry
  rows | awk '{ print "venture\t" $0 }'
}

cmd_rebuild() {
  root=
  case $# in
    0) ;;
    2)
      [ "$1" = --root ] || usage
      root=$2
      ;;
    *) usage ;;
  esac
  resolve_data ''
  if [ -z "$root" ]; then root=$(ventures_root) || die 2 "cannot resolve ventures_root"; fi
  scan "$root"
  rows | awk '{ print "venture\t" $0 }'
}

# The framing the skill compares a new idea against: the brief's Framing and
# Who-hurts fields, one line, bounded.
framing() {
  awk '
    /^## / { ins = ($0 ~ /^## Opportunity[ \t]*$/); f = ""; next }
    !ins { next }
    /^- \*\*(Framing|Who hurts):\*\*/ { f = $0; sub(/^- \*\*[^*]+:\*\*[ \t]*/, "", f); out = out (out == "" ? "" : " / ") f; cont = 1; next }
    /^- / { cont = 0; next }
    cont && /^  +[^ ]/ { l = $0; sub(/^ +/, "", l); out = out " " l; next }
    { cont = 0 }
    END { gsub(/\t/, " ", out); gsub(/[^[:print:]]/, "", out); print substr(out, 1, 400) }
  ' "$1/brief.md"
}

cmd_overlap() {
  [ $# -eq 0 ] || usage
  resolve_data '; overlap scan skipped'
  ensure_registry
  rows | while IFS='	' read -r id path st _fl _d; do
    if ! valid_id "$id" || ! is_bundle "$path" || [ ! -r "$path/brief.md" ]; then
      printf 'degraded\toverlap scan skipped %s: its brief could not be read\n' "$(printable "$id")"
      continue
    fi
    fr=$(framing "$path" 2>/dev/null) || {
      printf 'degraded\toverlap scan skipped %s: its brief could not be read\n' "$id"
      continue
    }
    printf 'overlap\t%s\t%s\t%s\n' "$id" "$st" "$fr"
  done
}

# status_of <venture-dir> — the renderer's status mode (one classifier for the
# dashboard, this view, and the portfolio).
status_of() {
  /bin/sh "$self_dir/inception-render.sh" --mode status "$1"
}

cmd_status() {
  [ $# -eq 1 ] || usage
  check_id "$1"
  resolve_data ''
  ensure_registry
  r=$(row_of "$1") || die 1 "$1 is not registered"
  path=$(printf '%s\n' "$r" | cut -f2)
  printf 'venture\t%s\n' "$1"
  status_of "$path"
}

cmd_telemetry() {
  [ $# -eq 3 ] || usage
  check_id "$1"
  case $2 in
    frame-discipline | unstaffed) ;;
    *) die 1 "telemetry kind must be frame-discipline or unstaffed" ;;
  esac
  valid_id "$3" || die 1 "a discipline is a catalog id: lowercase letters, digits, and hyphens"
  resolve_data ''
  printf '%s\t%s\t%s\t%s\n' "$(today)" "$1" "$2" "$3" >>"$data_dir/telemetry.tsv" \
    || die 2 "cannot write the telemetry log"
}

cmd_drop() {
  [ $# -eq 2 ] || usage
  check_id "$1"
  case $2 in *[![:space:]]*) ;; *) die 1 "the observation text is empty" ;; esac
  [ "$2" = "$(printable "$2")" ] || die 1 "the observation must be one line of printable text"
  case $2 in *'	'*) die 1 "the observation must not contain a tab" ;; esac
  resolve_data ''
  printf '%s\t%s\t%s\n' "$(today)" "$1" "$2" >>"$data_dir/drop.tsv" \
    || die 2 "cannot write the observation drop"
}

# The planwright-side reader. Mechanical neutralization runs before any text
# leaves: registered venture identifiers, absolute and home-relative paths,
# email addresses, URLs, and long opaque tokens become placeholders. The
# reader still summarizes without names before anything is committed; this
# pass only guarantees the obvious identifiers never reach it raw.
cmd_drop_read() {
  [ $# -eq 0 ] || usage
  resolve_data ''
  [ -f "$data_dir/drop.tsv" ] || {
    printf 'entry\tnone\n'
    return 0
  }
  ids=
  if registry_ok; then ids=$(rows | cut -f1 | tr '\n' ' '); fi
  awk -F '\t' -v ids="$ids" '
    BEGIN { n = split(ids, I, " "); for (i = 1; i <= n; i++) V[I[i]] = 1 }
    function opaque(w) { return length(w) >= 24 && w ~ /[0-9]/ && w ~ /^[A-Za-z0-9_+\/=-]+$/ }
    function neutral(w,   core, pre, post) {
      if (w ~ /:\/\//) return "<url>"
      if (w ~ /^[^@]+@[^@]+\.[A-Za-z]+/) return "<email>"
      core = w; pre = ""; post = ""
      if (match(core, /^[("'"'"']+/)) { pre = substr(core, 1, RLENGTH); core = substr(core, RLENGTH + 1) }
      if (match(core, /[.,;:)"'"'"'!?]+$/)) { post = substr(core, RSTART); core = substr(core, 1, RSTART - 1) }
      if (core ~ /^(\/|~\/)/) return pre "<path>" post
      if (core in V || core == VID) return pre "<venture>" post
      if (opaque(core)) return pre "<redacted>" post
      return w
    }
    NF >= 3 {
      VID = $2; t = $3
      gsub(/[^[:print:]]/, "", t)
      m = split(t, W, " "); out = ""
      for (i = 1; i <= m; i++) out = out (i > 1 ? " " : "") neutral(W[i])
      d = $1; if (d !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/) d = "undated"
      print "entry\t" d "\t" out; seen = 1
    }
    END { if (!seen) print "entry\tnone" }
  ' "$data_dir/drop.tsv"
}

cmd_portfolio() {
  cards=$self_dir/../cards
  case $# in
    0) ;;
    2)
      [ "$1" = --cards ] || usage
      cards=$2
      ;;
    *) usage ;;
  esac
  resolve_data ''
  ensure_registry
  td=$(today)
  report=$(rows | while IFS='	' read -r id path st _fl _d; do
    valid_id "$id" || continue
    if in_list "$st" "$CLOSED"; then
      printf 'venture\t%s\t%s\tnone\t-\t-\n' "$id" "$st"
      continue
    fi
    sv=$(status_of "$path" 2>/dev/null) || {
      printf 'venture\t%s\t%s\tunreadable\t-\t-\n' "$id" "$st"
      continue
    }
    printf '%s\n' "$sv" | awk -F '\t' -v id="$id" -v st="$st" -v today="$td" '
      function days(d,   y, m, dd, era, yoe, doy, doe) {
        y = substr(d, 1, 4) + 0; m = substr(d, 6, 2) + 0; dd = substr(d, 9, 2) + 0
        y -= (m <= 2)
        era = int((y >= 0 ? y : y - 399) / 400)
        yoe = y - era * 400
        doy = int((153 * (m + (m > 2 ? -3 : 9)) + 2) / 5) + dd - 1
        doe = yoe * 365 + int(yoe / 4) - int(yoe / 100) + doy
        return era * 146097 + doe - 719468
      }
      $1 == "kill" && $4 == "tripped" { trip = 1 }
      $1 == "kill" && $4 == "approaching" { near = 1 }
      $1 == "blocking" && $3 > 0 { blocked = 1 }
      $1 == "started" { started = $2 }
      $1 == "appetite" { appetite = $2 }
      END {
        age = "-"
        if (started ~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/) age = days(today) - days(started)
        f = ""
        if (trip) f = f ",kill-tripped"
        if (near) f = f ",kill-approaching"
        if (blocked) f = f ",blocked"
        if (age != "-" && appetite ~ /^[0-9]+$/ && age > appetite + 0) f = f ",over-appetite"
        f = (f == "" ? "none" : substr(f, 2))
        print "venture\t" id "\t" st "\t" f "\t" age "\t" (appetite == "" ? "-" : appetite)
        if (started != "") print "started\t" id "\t" started
      }
    '
  done)
  if [ -z "$report" ]; then
    printf 'venture\tnone\n'
  else
    printf '%s\n' "$report" | grep '^venture	'
    rows | awk -F '\t' -v OFS='\t' -v header="$HEADER" -v rep="$report" '
      BEGIN {
        print header
        n = split(rep, L, "\n")
        for (i = 1; i <= n; i++) { split(L[i], c, "\t"); if (c[1] == "venture" && c[4] != "unreadable") F[c[2]] = c[4] }
      }
      ($1 in F) { $4 = F[$1] }
      { print }
    ' | write_atomic "$registry"
  fi

  # Catalog health: cards past their rot rate, then unstaffed frequency.
  newest=$(printf '%s\n' "$report" | awk -F '\t' '$1 == "started" && $3 > m { m = $3 } END { print m }')
  notes=
  if [ -d "$cards" ]; then
    for c in "$cards"/*.md; do
      [ -f "$c" ] || continue
      notes="$notes$(awk -v today="$td" -v newest="$newest" '
        function days(d,   y, m, dd, era, yoe, doy, doe) {
          y = substr(d, 1, 4) + 0; m = substr(d, 6, 2) + 0; dd = substr(d, 9, 2) + 0
          y -= (m <= 2)
          era = int((y >= 0 ? y : y - 399) / 400)
          yoe = y - era * 400
          doy = int((153 * (m + (m > 2 ? -3 : 9)) + 2) / 5) + dd - 1
          doe = yoe * 365 + int(yoe / 4) - int(yoe / 100) + doy
          return era * 146097 + doe - 719468
        }
        /^\*\*Card-id:\*\*/ { id = $2 }
        /^\*\*Reviewed:\*\*/ { rv = $2 }
        /^\*\*Rot-rate:\*\*/ { rot = $2 }
        /^## / { exit }
        END {
          if (id !~ /^[a-z0-9][a-z0-9-]*$/ || rv !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/) exit
          due = 0
          if (rot == "medium" && days(today) - days(rv) > 365) due = 1
          if (rot == "fast" && newest != "" && newest > rv) due = 1
          if (due) print "card-review\t" id "\t" rv "\t" rot
        }
      ' "$c")
"
    done
  fi
  notes=$(printf '%s' "$notes" | grep . || true)
  if [ -n "$notes" ]; then printf '%s\n' "$notes"; else printf 'card-review\tnone\n'; fi

  if [ -f "$data_dir/telemetry.tsv" ]; then
    un=$(awk -F '\t' '$3 == "unstaffed" && $4 ~ /^[a-z0-9][a-z0-9-]*$/ { C[$4]++ } END { for (k in C) print C[k] "\t" k }' \
      "$data_dir/telemetry.tsv" | sort -k1,1nr -k2,2 | awk -F '\t' '{ print "unstaffed\t" $2 "\t" $1 }')
  else
    un=
  fi
  if [ -n "$un" ]; then printf '%s\n' "$un"; else printf 'unstaffed\tnone\n'; fi
}

[ $# -ge 1 ] || usage
cmd=$1
shift
case $cmd in
  add) cmd_add "$@" ;;
  set) cmd_set "$@" ;;
  get) cmd_get "$@" ;;
  list) cmd_list "$@" ;;
  rebuild) cmd_rebuild "$@" ;;
  overlap) cmd_overlap "$@" ;;
  status) cmd_status "$@" ;;
  portfolio) cmd_portfolio "$@" ;;
  telemetry) cmd_telemetry "$@" ;;
  drop) cmd_drop "$@" ;;
  drop-read) cmd_drop_read "$@" ;;
  *) usage ;;
esac
