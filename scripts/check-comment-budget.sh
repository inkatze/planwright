#!/bin/sh
# check-comment-budget.sh: the comment-block budget guard. Its rule, the budget
# model, and the argument for both live in doctrine/comment-hygiene.md, the
# normative home; `--help` prints the contract. Every file it reads, the
# suppression list, and the knob values are untrusted data: nothing is
# evaluated, reported text is stripped of control bytes, and a path that could
# leave the root is refused.
set -uf

LC_ALL=C
export LC_ALL
unset CDPATH

me=check-comment-budget
self_dir=$(cd "$(dirname "$0")" && pwd) || exit 2

usage() {
  cat <<'EOF'
usage: check-comment-budget.sh [--root <dir>] [--closeout] [<path>...]
       check-comment-budget.sh [--root <dir>] --audit [<tree>]
       check-comment-budget.sh [--root <dir>] --code-invariant <ref>

Measures, per file of the surface, the largest contiguous run of comment
lines and compares it with the comment_block_warn and comment_block_error
knobs (lines, boundary-inclusive: a run equal to a threshold trips it).

  comment line   optional leading whitespace, then `#`; a shebang (a line
                 starting `#!`, the first line of a script embedded in a
                 heredoc included) is not one.
  code line      a non-blank line that is not a comment line.
  run            ended by a blank line or a code line.
  known limit    the guard reads lines, not a parse tree: a heredoc body line
                 beginning with `#` counts as a comment line. A file where
                 that misfires takes an `exempt` entry saying so.

Surface (tracked files only, or every file under <tree> for --audit):
  *.sh under scripts/, tests/, githooks/, hooks/; the extensionless
  githooks/ files whose first line is a shebang; *.yml and *.yaml under
  config/; lefthook.yml and mise.toml at the root; *.yml and *.yaml under
  .github/workflows/. Nothing else, so the suppression list, JSON, and
  seeds are outside it. A symlinked surface file is refused.

Check (the default). A run at or over the warn threshold is a warning (exit
stays 0); at or over the error threshold, an error (exit 1) unless the
suppression list covers the file. A file with an entry of either form
draws no warning either. Given <path> arguments (the pre-commit job passes
the staged paths), only those that are surface files are measured, as
their working-tree content. Knobs resolve through the configuration chain;
a knob that is missing or not a positive integer, or warn above error,
aborts (exit 2).

Suppression list, config/comment-budget-exemptions.txt (absent = empty;
blank lines and lines starting `#` are skipped; one entry per path):
  exempt|<path>|<reason>
      permanent: an own-surface section the taxonomy gives no split and no
      other home, or a file the heredoc limit misfires on.
  pending-cleanup|<path>|Task <N>|<reason>
      transitional: names the cleanup task that removes it (<N> is a task
      id, digits with an optional .<digits>).
  <path> is repository-relative; an absolute path or a `..` segment is
  refused. A missing reason, an unknown form, a malformed field, or a
  second entry for one path is an error. An entry whose file trips no
  threshold (or is gone) is a cleanup warning, never an error.
  --closeout  every pending-cleanup entry is an error, whatever its file
              measures.

--audit [<tree>]  Inventory of the surface under the working tree, or under
  <tree> (a directory, measured by path, tracked or not). A block here is a
  run of two or more comment lines. Tab-separated rows on stdout:
    file  <largest> <start> <blocks> <block lines> <comment lines> <code lines> <path>
          ranked by largest block, then path
    block <lines> <words> <class> <path>:<start>
          for each block, files in the ranking order
    total <name> <value>...
          files, blocks, block_lines, blocks_at_error, block_lines_at_error,
          comment_lines, code_lines, largest (<lines> <path>:<start>), and
          <class>_blocks and <class>_lines for each class
  Evidence classes, first match wins, matched against the block's text:
    cites      a requirement, decision, task, or observation id:
               REQ-<letters><digit>, D-<digits> not inside a word,
               Task <digits> (either case), obs:<four hex or more>
    rationale  rationale language, matched lowercased: because, otherwise,
               why, deliberate(ly), intentional(ly), workaround, careful,
               caution, warning, unless, since, lest (as whole words); so
               that, rather than, instead of, in order to, to avoid, to
               keep, to prevent, prevents, on purpose, the reason, must not,
               do not, don't, never
    none       neither: evidence-free
  Words per block counts the text after each line's leading `#` marks.

--code-invariant <ref>  For every surface file that differs between the
  merge-base of <ref> and HEAD on one side and the working tree on the
  other (untracked files included), compare the sequence of code lines. A
  changed sequence, or a surface file added or deleted since the
  merge-base, is named and exits 1. githooks/ files without an extension
  count as surface by name here. --root must be the repository's top
  level. The known limit holds here too: a changed heredoc body line
  beginning with `#` is not seen as a code change.

Exit: 0 pass · 1 a budget error, a suppression-list error, or a code
change · 2 usage, a knob that does not resolve, or an input that would make
the run vacuous or unsafe (no surface file outside a <path> run, which
exits 0 when none of its paths is one; an unreadable file; a symlink; a
path carrying a control byte; a ref that does not resolve).
EOF
}

die() {
  printf '%s: %s\n' "$me" "$1" >&2
  exit 2
}

root=""
mode=check
closeout=0
tree=""
ref=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --help | -h)
      usage
      exit 0
      ;;
    --root)
      [ "$#" -ge 2 ] || die "--root needs a directory"
      root=$2
      shift 2
      ;;
    --closeout)
      closeout=1
      shift
      ;;
    --audit)
      [ "$mode" = check ] || die "--audit and --code-invariant are separate modes; give one, once"
      mode=audit
      shift
      if [ "$#" -gt 0 ]; then
        case "$1" in
          -*) ;;
          *)
            tree=$1
            shift
            ;;
        esac
      fi
      ;;
    --code-invariant)
      [ "$#" -ge 2 ] || die "--code-invariant needs a ref"
      [ "$mode" = check ] || die "--audit and --code-invariant are separate modes; give one, once"
      mode=invariant
      ref=$2
      shift 2
      ;;
    --)
      shift
      break
      ;;
    -*) die "unknown option; see --help" ;;
    *) break ;;
  esac
done
if [ "$mode" != check ] && { [ "$#" -gt 0 ] || [ "$closeout" -eq 1 ]; }; then
  die "<path> arguments and --closeout apply to the check mode only"
fi
scoped=0
[ "$#" -eq 0 ] || scoped=1

if [ -z "$root" ]; then
  root=$(cd "$self_dir/.." && pwd) || exit 2
fi
[ -d "$root" ] || die "root is not a directory; failing closed"
root=$(cd "$root" && pwd -P) || exit 2

work=$(mktemp -d) || exit 2
trap 'rm -rf "$work"' EXIT
trap 'exit 2' HUP INT TERM

clean() {
  printf '%s' "$1" | tr -d '\000-\037\177\200-\237'
}

# surface_names: `<tag>TAB<path>` lines in, the surface ones out by name alone.
# A path git had to quote carries a control byte, a quote, or a backslash: a
# surface one comes out tagged Q for the caller to refuse.
surface_names() {
  awk -F '	' '
  function surface(p) {
    return p ~ /^(scripts|tests|githooks|hooks)\/.*\.sh$/ || p ~ /^config\/.*\.ya?ml$/ ||
      p == "lefthook.yml" || p == "mise.toml" || p ~ /^\.github\/workflows\/.*\.ya?ml$/ ||
      (p ~ /^githooks\// && p !~ /^githooks\/.*\./)
  }
  {
    p = substr($0, length($1) + 2)
    if (p ~ /^"/) { q = p; gsub(/^"|"$/, "", q); if (surface(q)) print "Q\t" p; next }
    if (surface(p)) print $1 "\t" p
  }'
}

# keep_files <dir> <out>: read surface_names output; refuse quoted paths and
# symlinks, drop what is gone, and keep a githooks/ hook only with a shebang.
keep_files() {
  : >"$2"
  while IFS= read -r kf_line; do
    kf_tag=${kf_line%%"	"*}
    kf_path=${kf_line#*"	"}
    [ "$kf_tag" != Q ] || die "a surface path carries a byte the guard will not read: $(clean "$kf_path"); failing closed"
    if [ "$kf_tag" = 120000 ] || [ -h "$1/$kf_path" ]; then
      die "surface file $(clean "$kf_path") is a symlink, which the guard does not follow; failing closed"
    fi
    [ -f "$1/$kf_path" ] || continue
    case $kf_path in
      githooks/*.*) ;;
      githooks/*)
        [ -r "$1/$kf_path" ] || die "surface file $(clean "$kf_path") is unreadable; failing closed"
        kf_first=""
        IFS= read -r kf_first <"$1/$kf_path" || [ -n "$kf_first" ] || continue
        case $kf_first in
          '#!'*) ;;
          *) continue ;;
        esac
        ;;
    esac
    printf '%s\n' "$kf_path" >>"$2"
  done
}

require_git() {
  git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "root is not a git work tree; failing closed"
}

# list_tracked <out>: the tracked surface files of $root, one relative path per line.
list_tracked() {
  require_git
  git -C "$root" -c core.quotepath=off ls-files -s >"$work/ls" || die "git ls-files failed; failing closed"
  # A path mid-merge is listed once per conflict stage, each with its own mode.
  sed 's/ .*	/	/' "$work/ls" >"$work/staged" || die "reading the git listing failed; failing closed"
  awk -F '	' '!seen[substr($0, length($1) + 2)]++' "$work/staged" >"$work/unique" \
    || die "reading the git listing failed; failing closed"
  surface_names <"$work/unique" >"$work/names" || die "filtering the surface failed; failing closed"
  keep_files "$root" "$1" <"$work/names"
}

# list_tree <dir> <out>: every surface file under an arbitrary directory.
list_tree() {
  find "$1" \( -type f -o -type l \) -print >"$work/find" || die "listing the tree failed; failing closed"
  B=${1%/}/ awk '
    index($0, ENVIRON["B"]) != 1 { bad = 1; exit }
    { print "-\t" substr($0, length(ENVIRON["B"]) + 1) }
    END { exit bad }' "$work/find" >"$work/rel" || die "a listed path holds a newline; failing closed"
  surface_names <"$work/rel" >"$work/names"
  keep_files "$1" "$2" <"$work/names"
}

# getknob <key>: the knob's value through the configuration chain, or abort.
getknob() {
  gk_val=$(PLANWRIGHT_CONFIG_DEFAULTS="$root/config/defaults.yml" PLANWRIGHT_REPO_ROOT="$root" \
    "$self_dir/resolve-config-knob.sh" --key "$1" --type posint --no-degrade) \
    || die "knob $1 does not resolve to a positive integer through the configuration chain; failing loud"
  printf '%s' "$gk_val"
}

# code_lines: stdin to stdout, keeping only code lines.
code_lines() {
  awk '{ sub(/\r$/, "") } /^#!/ { print; next } /^[ \t]*#/ || /^[ \t]*$/ { next } { print }'
}

code_invariant() {
  case $ref in
    "" | -*) die "--code-invariant needs a ref that does not start with -" ;;
  esac
  case $ref in
    *[[:cntrl:]]*) die "the ref carries a control byte" ;;
  esac
  require_git
  # git diff names paths from the top level, so a deeper root would match nothing.
  [ "$(git -C "$root" rev-parse --show-toplevel)" = "$root" ] || die "--code-invariant needs --root at the repository's top level"
  git -C "$root" rev-parse --verify --quiet "$ref^{commit}" >/dev/null || die "ref $(clean "$ref") does not resolve to a commit"
  merge_base=$(git -C "$root" merge-base "$ref" HEAD) || die "no merge-base between $(clean "$ref") and HEAD"
  git -C "$root" -c core.quotepath=off diff --no-renames --name-status "$merge_base" -- >"$work/diff" \
    || die "git diff against the merge-base failed; failing closed"
  git -C "$root" -c core.quotepath=off ls-files --others --exclude-standard >"$work/untracked" \
    || die "listing untracked files failed; failing closed"
  sed 's/^/A	/' "$work/untracked" >>"$work/diff"
  surface_names <"$work/diff" >"$work/names"
  ci_seen=0
  ci_bad=0
  while IFS= read -r ci_line; do
    ci_status=${ci_line%%"	"*}
    ci_path=${ci_line#*"	"}
    [ "$ci_status" != Q ] || die "a surface path carries a byte the guard will not read: $(clean "$ci_path"); failing closed"
    ci_seen=$((ci_seen + 1))
    case $ci_status in
      M | T)
        if [ -h "$root/$ci_path" ]; then
          die "surface file $(clean "$ci_path") is a symlink, which the guard does not follow; failing closed"
        fi
        git -C "$root" show "$merge_base:$ci_path" >"$work/before" 2>/dev/null \
          || die "could not read $(clean "$ci_path") at the merge-base; failing closed"
        code_lines <"$work/before" >"$work/before.code"
        code_lines <"$root/$ci_path" >"$work/after.code" \
          || die "could not read $(clean "$ci_path"); failing closed"
        if ! cmp -s "$work/before.code" "$work/after.code"; then
          printf '%s: code changed: %s\n' "$me" "$(clean "$ci_path")" >&2
          ci_bad=$((ci_bad + 1))
        fi
        ;;
      A)
        printf '%s: code changed: %s (added since the merge-base)\n' "$me" "$(clean "$ci_path")" >&2
        ci_bad=$((ci_bad + 1))
        ;;
      D)
        printf '%s: code changed: %s (deleted since the merge-base)\n' "$me" "$(clean "$ci_path")" >&2
        ci_bad=$((ci_bad + 1))
        ;;
      *)
        printf '%s: code changed: %s (status %s)\n' "$me" "$(clean "$ci_path")" "$(clean "$ci_status")" >&2
        ci_bad=$((ci_bad + 1))
        ;;
    esac
  done <"$work/names"
  if [ "$ci_bad" -gt 0 ]; then
    printf '%s: %s of %s changed surface file(s) differ in code lines from the merge-base.\n' "$me" "$ci_bad" "$ci_seen" >&2
    exit 1
  fi
  printf '%s: %s changed surface file(s); code lines unchanged since the merge-base.\n' "$me" "$ci_seen"
  exit 0
}

[ "$mode" != invariant ] || code_invariant

warn=$(getknob comment_block_warn) || exit 2
error=$(getknob comment_block_error) || exit 2
[ "$warn" -le "$error" ] || die "comment_block_warn ($warn) is above comment_block_error ($error); failing loud"

list="$work/list"
measure_dir=$root
if [ "$mode" = audit ] && [ -n "$tree" ]; then
  [ -d "$tree" ] || die "the audit tree is not a directory"
  measure_dir=$(cd "$tree" && pwd -P) || exit 2
  list_tree "$measure_dir" "$list"
elif [ "$scoped" -eq 1 ]; then
  list_tracked "$work/tracked"
  : >"$work/args"
  for sp in "$@"; do
    case $sp in
      *[[:cntrl:]]*) die "path $(clean "$sp") carries a control byte; failing closed" ;;
    esac
    case $sp in
      /* | ../* | */../* | .. | */..) die "path $(clean "$sp") leaves the root; failing closed" ;;
    esac
    printf '%s\n' "${sp#./}" >>"$work/args"
  done
  awk 'NR == FNR { tracked[$0] = 1; next } ($0 in tracked) && !seen[$0]++' "$work/tracked" "$work/args" >"$list" \
    || die "filtering the given paths failed; failing closed"
  [ -s "$list" ] || {
    printf '%s: no surface file among the given paths.\n' "$me"
    exit 0
  }
else
  list_tracked "$list"
fi
[ -s "$list" ] || die "zero surface files found; failing closed"

exemptions="$root/config/comment-budget-exemptions.txt"
if [ -h "$exemptions" ]; then
  die "config/comment-budget-exemptions.txt is a symlink; failing closed"
fi
[ -e "$exemptions" ] || exemptions=""
if [ -n "$exemptions" ] && [ ! -r "$exemptions" ]; then
  die "config/comment-budget-exemptions.txt is unreadable; failing closed"
fi

ME=$me MODE=$mode DIR=$measure_dir LIST=$list EXEMPT=$exemptions WARN=$warn ERROR=$error \
  CLOSEOUT=$closeout SCOPED=$scoped awk '
function clean(s) { gsub(/[\001-\037\177]|\302[\200-\237]/, "?", s); return s }
function closed(msg) {
  printf "%s: %s; failing closed.\n", ENVIRON["ME"], msg > "/dev/stderr"
  aborted = 1
  exit 2
}
function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
function bad_entry(msg) {
  printf "%s: ERROR: config/comment-budget-exemptions.txt:%d: %s\n", ENVIRON["ME"], eln, msg > "/dev/stderr"
  errors++
}
function join_from(arr, from, n,   s, i) {
  s = arr[from]
  for (i = from + 1; i <= n; i++) s = s "|" arr[i]
  return s
}
function read_exemptions(path,   line, f, n, kind, p, reason, task, rc) {
  if (path == "") return
  while ((rc = (getline line < path)) > 0) {
    eln++
    sub(/\r$/, "", line)
    if (line ~ /^[ \t]*#/ || line ~ /^[ \t]*$/) continue
    n = split(line, f, "|")
    kind = f[1]
    if (kind == "exempt") {
      if (n < 3) { bad_entry("an exempt entry needs exempt|<path>|<reason>"); continue }
      reason = join_from(f, 3, n); task = ""
    } else if (kind == "pending-cleanup") {
      if (n < 4) { bad_entry("a pending-cleanup entry needs pending-cleanup|<path>|Task <N>|<reason>"); continue }
      task = f[3]
      if (task !~ /^Task [0-9]+(\.[0-9]+)?$/) { bad_entry("the task field is not Task <N>: " clean(task)); continue }
      reason = join_from(f, 4, n)
    } else {
      bad_entry("unknown entry form " clean(kind)); continue
    }
    p = f[2]
    if (p == "" || p != trim(p) || p ~ /[\001-\037\177]/) { bad_entry("a malformed path " clean(p)); continue }
    if (p ~ /^\// || p ~ /(^|\/)\.\.(\/|$)/) { bad_entry("the path " clean(p) " leaves the root; refused"); continue }
    sub(/^\.\//, "", p)
    if (trim(reason) == "") { bad_entry("the entry for " clean(p) " carries no reason"); continue }
    if (p in ekind) { bad_entry("a second entry for " clean(p)); continue }
    ekind[p] = kind; etask[p] = task; eline[p] = eln
    eorder[++nent] = p
  }
  if (rc < 0) closed("config/comment-budget-exemptions.txt could not be read")
  close(path)
}
function words(s,   w) { s = trim(s); return s == "" ? 0 : split(s, w, /[ \t]+/) }
function classify(text,   lt) {
  if (text ~ /REQ-[A-Z]+[0-9]/ || text ~ /(^|[^A-Za-z0-9_-])D-[0-9]/ || text ~ /[Tt]ask [0-9]/ ||
      text ~ /obs:[0-9a-f][0-9a-f][0-9a-f][0-9a-f]/) return "cites"
  lt = tolower(text)
  if (lt ~ /(^|[^a-z])(because|otherwise|why|deliberate|deliberately|intentional|intentionally|workaround|careful|caution|warning|unless|since|lest)([^a-z]|$)/ ||
      lt ~ /so that|rather than|instead of|in order to|to avoid|to keep|to prevent|prevents|on purpose|the reason|must not|do not|don.t|never/) return "rationale"
  return "none"
}
# end_run: close the current run of comment lines in file i.
function end_run(i,   c) {
  if (run == 0) return
  if (run > largest[i] && (run >= 2 || !audit_mode)) { largest[i] = run; lstart[i] = rstart }
  if (run >= 2) {
    nblk[i]++; blines[i] += run
    if (audit_mode) {
      c = classify(rtext)
      nb++; fblock[i, nblk[i]] = nb; bstart[nb] = rstart; blen[nb] = run; bwords[nb] = words(rtext); bclass[nb] = c
      cls_blocks[c]++; cls_lines[c] += run
      if (run >= errth) { at_err++; at_err_lines += run }
    }
  }
  run = 0; rtext = ""
}
function measure(i, path,   line, ln, rc, t) {
  run = 0; rtext = ""; ln = 0
  while ((rc = (getline line < path)) > 0) {
    ln++
    sub(/\r$/, "", line)
    if (line ~ /^#!/) { end_run(i); code[i]++; continue }
    if (line ~ /^[ \t]*#/) {
      if (run == 0) rstart = ln
      run++; com[i]++
      if (audit_mode) { t = line; sub(/^[ \t]*#+/, "", t); rtext = rtext " " t }
      continue
    }
    end_run(i)
    if (line !~ /^[ \t]*$/) code[i]++
  }
  if (rc < 0) closed(clean(rel[i]) " could not be read")
  end_run(i)
  close(path)
}
BEGIN {
  warnth = ENVIRON["WARN"] + 0; errth = ENVIRON["ERROR"] + 0
  closeout = ENVIRON["CLOSEOUT"] == "1"
  audit_mode = ENVIRON["MODE"] == "audit"
  if (!audit_mode) read_exemptions(ENVIRON["EXEMPT"])
  while ((getline p < ENVIRON["LIST"]) > 0) {
    nf++; rel[nf] = p; largest[nf] = 0; lstart[nf] = 0
    measured[p] = nf
    measure(nf, ENVIRON["DIR"] "/" p)
  }
  if (audit_mode) audit()
  else check()
}
function audit(   i, j, k, t, b, f, tot_blocks, tot_lines, tot_com, tot_code, big, bigat) {
  for (i = 1; i <= nf; i++) order[i] = i
  for (i = 2; i <= nf; i++) {
    t = order[i]
    for (j = i - 1; j >= 1; j--) {
      k = order[j]
      if (largest[k] > largest[t] || (largest[k] == largest[t] && rel[k] < rel[t])) break
      order[j + 1] = k
    }
    order[j + 1] = t
  }
  for (j = 1; j <= nf; j++) {
    i = order[j]
    printf "file\t%d\t%d\t%d\t%d\t%d\t%d\t%s\n", largest[i], lstart[i], nblk[i], blines[i], com[i], code[i], clean(rel[i])
    tot_blocks += nblk[i]; tot_lines += blines[i]; tot_com += com[i]; tot_code += code[i]
    if (largest[i] > big) { big = largest[i]; bigat = clean(rel[i]) ":" lstart[i] }
  }
  for (j = 1; j <= nf; j++) {
    f = order[j]
    for (k = 1; k <= nblk[f]; k++) {
      b = fblock[f, k]
      printf "block\t%d\t%d\t%s\t%s:%d\n", blen[b], bwords[b], bclass[b], clean(rel[f]), bstart[b]
    }
  }
  printf "total\tfiles\t%d\n", nf
  printf "total\tblocks\t%d\n", tot_blocks
  printf "total\tblock_lines\t%d\n", tot_lines
  printf "total\tblocks_at_error\t%d\n", at_err
  printf "total\tblock_lines_at_error\t%d\n", at_err_lines
  printf "total\tcomment_lines\t%d\n", tot_com
  printf "total\tcode_lines\t%d\n", tot_code
  printf "total\tlargest\t%d\t%s\n", big, (bigat == "" ? "-" : bigat)
  printf "total\tcites_blocks\t%d\ntotal\tcites_lines\t%d\n", cls_blocks["cites"], cls_lines["cites"]
  printf "total\trationale_blocks\t%d\ntotal\trationale_lines\t%d\n", cls_blocks["rationale"], cls_lines["rationale"]
  printf "total\tnone_blocks\t%d\ntotal\tnone_lines\t%d\n", cls_blocks["none"], cls_lines["none"]
}
function check(   i, p, kind, suppressed, warns, stale, e) {
  for (i = 1; i <= nf; i++) {
    p = rel[i]
    kind = (p in ekind) ? ekind[p] : ""
    if (largest[i] >= errth) {
      if (kind == "exempt" || (kind == "pending-cleanup" && !closeout)) { suppressed++; continue }
      printf "%s: ERROR: %s:%d: a %d-line comment block (error threshold %d); see doctrine/comment-hygiene.md\n", ENVIRON["ME"], clean(p), lstart[i], largest[i], errth > "/dev/stderr"
      errors++
    } else if (largest[i] >= warnth) {
      if (kind != "") { suppressed++; continue }
      printf "%s: WARN: %s:%d: a %d-line comment block (warn threshold %d)\n", ENVIRON["ME"], clean(p), lstart[i], largest[i], warnth > "/dev/stderr"
      warns++
    }
  }
  for (e = 1; e <= nent; e++) {
    p = eorder[e]
    if (closeout && ekind[p] == "pending-cleanup") {
      printf "%s: ERROR: config/comment-budget-exemptions.txt:%d: pending-cleanup entry for %s under --closeout; the cleanup is over\n", ENVIRON["ME"], eline[p], clean(p) > "/dev/stderr"
      errors++
      continue
    }
    if (ENVIRON["SCOPED"] == "1" && !(p in measured)) continue
    if (!(p in measured) || largest[measured[p]] < warnth) {
      printf "%s: WARN: cleanup: %s trips no threshold; remove its %s entry (config/comment-budget-exemptions.txt:%d)\n", ENVIRON["ME"], clean(p), ekind[p], eline[p] > "/dev/stderr"
      stale++
    }
  }
  printf "%s: %d file(s) measured; %d error(s), %d warning(s), %d cleanup warning(s), %d suppressed.\n", ENVIRON["ME"], nf, errors, warns, stale, suppressed
  if (errors > 0) exit 1
}
END { if (aborted) exit 2 }
' </dev/null
