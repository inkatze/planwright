#!/usr/bin/env bash
# mc-duties.sh — read mission control's merged duties catalog: the core seed
# config/duties.yaml unioned with the adopter, repo-tracked and machine-local
# overlay catalogs by scripts/resolve-catalog.sh (append/union,
# supersede-by-id). config/duties.yaml's header holds the entry grammar.
#
# Usage:
#   mc-duties.sh list                     <id><TAB><layer> per merged entry
#   mc-duties.sh get <id> <field>         one field of the merged entry, as
#                                         written (surrounding quotes dropped)
#   mc-duties.sh watchers --program <p>   <id><TAB><script><TAB><cadence>
#                                         <TAB><cost> per watcher an armed
#                                         duty runs
#   mc-duties.sh files --program <p>      <id><TAB><directory> per armed duty
#   mc-duties.sh validate                 check every merged entry; each
#                                         problem on stderr as
#                                         <id>: <field>: <problem>
#
# An armed duty is one the program enables (scripts/mc-program.sh) whose
# lifecycle is shadow or live. A disabled duty, or an `off` one, arms no
# watcher and owns no directory. watchers and files skip, with a warning, an
# invalid entry an adopter or machine-local catalog supplied, and refuse the
# catalog over one from the core seed or the repo-tracked catalog, and over
# an enabled id the catalog lacks. A repeated id reads its first entry, as
# the resolver keeps it.
#
# Exit codes: 0 resolved; 1 an invalid catalog, an unknown enabled duty, a
# missing field or a control character in a value (get), or a resolver,
# reader or program failure; 2 usage, an unknown field, or an invalid program
# name; 3 no such duty (get), or the program is not configured.
#
# Portable bash 3.2 / BSD tooling.
set -u
set -f
LC_ALL=C
export LC_ALL
unset CDPATH

prog=mc-duties
script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2
if [ ! -r "$script_dir/echo-safety.sh" ]; then
  printf '%s\n' "$prog: echo-safety.sh is missing or unreadable (broken install)" >&2
  exit 2
fi
# shellcheck source=scripts/echo-safety.sh
. "$script_dir/echo-safety.sh" || exit 2

# Every entry field after id is required.
FIELDS="id summary triggers watchers wake rules kinds files lifecycle never-propose"
export FIELDS

usage() {
  printf '%s\n' "usage: mc-duties.sh list | get <id> <field> | watchers --program <p> | files --program <p> | validate" >&2
  exit 2
}
fail() {
  printf '%s\n' "$prog: $1" >&2
  exit 1
}

catalog() { bash "$script_dir/resolve-catalog.sh" duties "$@"; }

# walk <mode>: one awk pass over the merged catalog on stdin. Modes:
#   get       print field FIELD of entry ID; exit 3 when ID is absent, 4 when
#             the entry lacks the field
#   validate  print <id>: <field>: <problem> per problem; exit 1 when any
#   watchers  for the ids in ENABLED (newline separated), print the armed
#   files     ones' watchers or directory; a missing id is a
#             `missing<TAB><id>` line
# Any other exit status is a reader failure.
walk() {
  MODE=$1 awk '
    function trim(s) { sub(/^[ ]+/, "", s); sub(/[ ]+$/, "", s); return s }
    function unq(s) { if (s ~ /^".*"$/) s = substr(s, 2, length(s) - 2); return s }
    function kebab(s) { return s ~ /^[a-z0-9][a-z0-9-]*$/ }
    function bad(id, f, msg) { print id ": " f ": " msg; nbad++ }
    BEGIN {
      mode = ENVIRON["MODE"]; want_id = ENVIRON["ID"]; want_f = ENVIRON["FIELD"]
      nfields = split(ENVIRON["FIELDS"], field, " ")
      for (j = 1; j <= nfields; j++) known[field[j]] = 1
      n = 0
    }
    /^[ ]*#/ || /^[ ]*$/ || /^---/ { next }
    /^  - id:/ {
      v = $0; sub(/^  - id:[ ]*/, "", v); v = unq(trim(v))
      n++; ids[n] = v; nf[n] = 0
      if (v in idx) dupid[n] = 1; else idx[v] = n
      next
    }
    /^    [^ ]/ && n > 0 {
      line = substr($0, 5); p = index(line, ":")
      if (!p) { k = line; v = "" } else { k = substr(line, 1, p - 1); v = unq(trim(substr(line, p + 1))) }
      if ((n, k) in has) dupf[n, k] = 1
      val[n, k] = v; has[n, k] = 1; nf[n]++; fk[n, nf[n]] = k
      next
    }
    # members(s, arr): an inline list into arr; returns the count, -1 when s
    # is not a list, -2 for an empty member before the last.
    function members(s, arr,    body, parts, c, i, m, k) {
      if (s !~ /^\[.*\]$/) return -1
      body = substr(s, 2, length(s) - 2)
      if (body ~ /^[ ]*$/) return 0
      c = split(body, parts, ","); k = 0
      for (i = 1; i <= c; i++) {
        m = unq(trim(parts[i]))
        if (m == "") { if (i == c) continue; return -2 }
        arr[++k] = m
      }
      return k
    }
    # watcher_parts(w, out): split <script>@<cadence>/<cost> into out[1..3];
    # returns 0 when w does not have that shape.
    function watcher_parts(w, out,    at) {
      if (w !~ /^[A-Za-z0-9._\/-]+@[1-9][0-9]*[smhd]\/[a-z]+$/) return 0
      at = index(w, "@")
      out[1] = substr(w, 1, at - 1)
      out[2] = substr(w, at + 1); sub(/\/.*/, "", out[2])
      out[3] = w; sub(/.*\//, "", out[3])
      return 1
    }
    function check_list(i, f, kind,    arr, c, j, w, wp) {
      c = members(val[i, f], arr)
      if (c == -1) { bad(ids[i], f, "\"" val[i, f] "\" is not an inline list [a, b]"); return }
      if (c == -2) { bad(ids[i], f, "an empty member in \"" val[i, f] "\""); return }
      for (j = 1; j <= c; j++) {
        if (kind == "watcher") {
          w = arr[j]
          if (!watcher_parts(w, wp)) {
            bad(ids[i], f, "\"" w "\" is not <script>@<cadence>/<cost>, cadence a positive count of s, m, h or d")
            continue
          }
          if (wp[1] ~ /^[\/-]/ || ("/" wp[1] "/") ~ /\/\.\.\//)
            bad(ids[i], f, "watcher script \"" wp[1] "\" starts with / or - or has a .. segment")
          if (wp[3] != "low" && wp[3] != "medium" && wp[3] != "high")
            bad(ids[i], f, "unknown cost class \"" wp[3] "\" (known: low medium high)")
        } else if (!kebab(arr[j])) {
          bad(ids[i], f, "\"" arr[j] "\" is not a kebab name")
        }
      }
    }
    function validate(    i, j, k, f, owner) {
      for (i = 1; i <= n; i++) {
        if (ids[i] ~ /[[:cntrl:]]/) { bad("(entry " i ")", "id", "carries a control character"); continue }
        if (!kebab(ids[i])) bad(ids[i], "id", "not a kebab name")
        if (i in dupid) bad(ids[i], "id", "duplicate id; the resolver keeps the first entry")
        for (j = 1; j <= nf[i]; j++) {
          k = fk[i, j]
          if (!(k in known)) bad(ids[i], k, "unknown field")
          else if ((i, k) in dupf) { bad(ids[i], k, "named twice"); delete dupf[i, k] }
          if (val[i, k] ~ /[[:cntrl:]]/) bad(ids[i], k, "carries a control character")
        }
        for (j = 2; j <= nfields; j++) {
          f = field[j]
          if (!has[i, f]) bad(ids[i], f, "missing")
        }
        if (has[i, "summary"] && val[i, "summary"] == "") bad(ids[i], "summary", "empty")
        if (has[i, "triggers"]) check_list(i, "triggers", "kebab")
        if (has[i, "rules"]) check_list(i, "rules", "kebab")
        if (has[i, "kinds"]) check_list(i, "kinds", "kebab")
        if (has[i, "watchers"]) check_list(i, "watchers", "watcher")
        if (has[i, "wake"] && val[i, "wake"] != "none" && !kebab(val[i, "wake"]))
          bad(ids[i], "wake", "\"" val[i, "wake"] "\" is not a kebab event or none")
        if (has[i, "lifecycle"] && val[i, "lifecycle"] !~ /^(off|shadow|live)$/)
          bad(ids[i], "lifecycle", "\"" val[i, "lifecycle"] "\" is not off, shadow or live")
        if (has[i, "never-propose"] && val[i, "never-propose"] !~ /^(true|false)$/)
          bad(ids[i], "never-propose", "\"" val[i, "never-propose"] "\" is not true or false")
        if (has[i, "files"] && !(i in dupid)) {
          f = val[i, "files"]
          if (!kebab(f)) bad(ids[i], "files", "\"" f "\" is not a kebab directory name")
          else if (f in owner) bad(ids[i], "files", "\"" f "\" is already owned by " owner[f])
          else owner[f] = ids[i]
        }
      }
    }
    function armed(    en, c, j, i, arr, w, k, wp, sk, ns, skipped) {
      c = split(ENVIRON["ENABLED"], en, "\n")
      ns = split(ENVIRON["SKIP"], sk, "\n")
      for (j = 1; j <= ns; j++) skipped[sk[j]] = 1
      for (j = 1; j <= c; j++) {
        if (en[j] == "" || en[j] in skipped) continue
        if (!(en[j] in idx)) { print "missing\t" en[j]; continue }
        i = idx[en[j]]
        if (val[i, "lifecycle"] == "off") continue
        if (mode == "files") { print ids[i] "\t" val[i, "files"]; continue }
        k = members(val[i, "watchers"], arr)
        for (w = 1; w <= k; w++)
          if (watcher_parts(arr[w], wp)) print ids[i] "\t" wp[1] "\t" wp[2] "\t" wp[3]
      }
    }
    END {
      if (mode == "get") {
        if (!(want_id in idx)) exit 3
        i = idx[want_id]
        if (want_f == "id") { print ids[i]; exit 0 }
        if (!has[i, want_f]) exit 4
        print val[i, want_f]; exit 0
      }
      if (mode == "validate") { validate(); exit (nbad > 0) }
      armed()
    }
  '
}

# merged: the merged catalog, or exit 1 naming the resolver failure.
merged() {
  catalog || fail "the duties catalog does not resolve (scripts/resolve-catalog.sh duties)"
}

# problems_of <catalog>: every problem in an already-resolved catalog, one
# <id>: <field>: <problem> line each; status 0 clean, 1 problems, 2 the
# reader failed (named on stderr).
problems_of() {
  printf '%s\n' "$1" | walk validate
  case $? in
    0) return 0 ;;
    1) return 1 ;;
    *)
      printf '%s\n' "$prog: the catalog reader failed" >&2
      return 2
      ;;
  esac
}

report() { # report <problem-lines>
  printf '%s\n' "$1" | while IFS= read -r p; do
    printf '%s\n' "$prog: $(sanitize_printable "$p")" >&2
  done
}

# armed <watchers|files> <program>. An invalid entry an adopter or
# machine-local catalog supplied is skipped with a warning, the policy the
# catalog resolver applies to a malformed overlay file; one from the core
# seed or the repo-tracked catalog refuses the whole catalog.
armed() {
  cat_out=$(merged) || exit 1
  skip=""
  problems=$(problems_of "$cat_out")
  case $? in
    0) ;;
    1) skip_or_refuse ;;
    *) exit 1 ;;
  esac
  enabled=$(bash "$script_dir/mc-program.sh" get "$2" duties)
  rc=$?
  [ "$rc" -eq 0 ] || exit "$rc"
  armed_rest "$1" "$2"
}

# skip_or_refuse: sort $problems by the layer that supplied each entry,
# setting $skip or refusing the catalog.
skip_or_refuse() {
  layers=$(catalog --explain 2>/dev/null)
  skip=""
  refuse=""
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    id=${p%%: *}
    layer=$(printf '%s\n' "$layers" | ID=$id awk -F '\t' '$1 == ENVIRON["ID"] { print $2; exit }')
    case $layer in
      adopter | machine-local)
        skip="$skip$id
"
        printf '%s\n' "$prog: warning: $(sanitize_printable "$p")" >&2
        ;;
      *) refuse="$refuse$p
" ;;
    esac
  done <<EOF
$problems
EOF
  if [ -n "$refuse" ]; then
    report "${refuse%?}"
    fail "refusing an invalid catalog; run scripts/check-duties.sh"
  fi
  printf '%s' "$skip" | sort -u | while IFS= read -r id; do
    layer=$(printf '%s\n' "$layers" | ID=$id awk -F '\t' '$1 == ENVIRON["ID"] { print $2; exit }')
    printf '%s\n' "$prog: warning: skipping duty '$(sanitize_printable "$id")' from the $layer layer; its entry is invalid" >&2
  done
}

armed_rest() { # armed_rest <watchers|files> <program>
  out=$(printf '%s\n' "$cat_out" | ENABLED=$enabled SKIP=${skip:-} walk "$1") || fail "the catalog reader failed"
  missing=$(printf '%s\n' "$out" | awk -F '\t' '$1 == "missing" { print $2 }')
  if [ -n "$missing" ]; then
    printf '%s\n' "$missing" | while IFS= read -r m; do
      printf '%s\n' "$prog: program '$2' enables '$(sanitize_printable "$m")', which the duties catalog lacks" >&2
    done
    exit 1
  fi
  [ -z "$out" ] || printf '%s\n' "$out"
}

[ $# -ge 1 ] || usage
verb=$1
shift
case $verb in
  list)
    [ $# -eq 0 ] || usage
    catalog --explain
    ;;
  get)
    [ $# -eq 2 ] || usage
    case " $FIELDS " in
      *" $2 "*) ;;
      *)
        printf '%s\n' "$prog: unknown field '$(sanitize_printable "$2")' (known: $FIELDS)" >&2
        exit 2
        ;;
    esac
    cat_out=$(merged) || exit 1
    out=$(printf '%s\n' "$cat_out" | ID=$1 FIELD=$2 walk get)
    case $? in
      0) ;;
      3)
        printf '%s\n' "$prog: no duty '$(sanitize_printable "$1")' in the merged catalog" >&2
        exit 3
        ;;
      4) fail "duty '$(sanitize_printable "$1")' carries no '$2' field" ;;
      *) fail "the catalog reader failed" ;;
    esac
    case $out in
      *[[:cntrl:]]*) fail "duty '$1' field '$2' carries a control character; run scripts/check-duties.sh" ;;
    esac
    printf '%s\n' "$out"
    ;;
  watchers | files)
    [ $# -eq 2 ] && [ "$1" = --program ] || usage
    armed "$verb" "$2"
    ;;
  validate)
    [ $# -eq 0 ] || usage
    cat_out=$(merged) || exit 1
    problems=$(problems_of "$cat_out")
    case $? in
      0) ;;
      1)
        report "$problems"
        exit 1
        ;;
      *) exit 1 ;;
    esac
    ;;
  -h | --help)
    awk 'NR>=2 { if ($0 ~ /^#/) { sub(/^# ?/, ""); print } else exit }' "$0"
    ;;
  *) usage ;;
esac
