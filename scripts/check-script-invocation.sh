#!/bin/sh
# check-script-invocation.sh — no skill instruction runs a bash-shebanged
# script through `sh`, and every script it runs is run the way the script's
# usage header says.
#
# Called by its path, a script gets the interpreter its shebang names. `sh
# <path>` overrides that with whatever /bin/sh is, and where that is dash
# (Debian, Ubuntu) a bash-only script fails on its first bashism: a catalog
# walk degrades, a budget audit fails, with a syntax error that names the
# script rather than the invocation. The rule lives in
# doctrine/plugin-script-invocation.md (*Invoke by the shebang*); this is its
# mechanical half.
#
# THE SHEBANG IS THE DECLARATION. A top-level scripts/*.sh whose first line is
# a `#!` naming bash is bash-only. Sourced libraries carry no shebang and are
# never run, so they are not compared against.
#
# WHAT COUNTS AS AN OFFENSE. In any .md file under skills/ or doctrine/, an
# `sh` command word (bare, quoted, or a path ending /sh such as /bin/sh)
# whose operand, past any options, `--`, and redirects, names
# `scripts/<name>` for a bash-shebanged <name>. The operand may be quoted, a
# variable, or a `<placeholder>` such as `<root>/scripts/<name>`, and a
# redirect may be glued to it. Not offenses: `sh -c <string>` (the string
# runs the script by path), a call by path, a call through `bash`. Not read:
# a script piped into `sh` on stdin, and an invocation split by a
# backslash-newline.
#
# THE USAGE HEADER IS THE CONTRACT. A script a code span or fenced command
# line in that prose runs, in command position, is checked against its `#
# Usage` header: the subcommand one it lists, every flag one it accepts, every
# required argument supplied or standing as a <placeholder>. A script with no
# header the grammar reads fails each invocation. The grammar, and what counts
# as an invocation, are stated once, in config/guard-catalog.yaml's
# script-invocation-house-pattern entry; the header is read as text, never
# run.
#
# FAILS CLOSED on anything that would narrow the scan: no scripts/, no
# shebanged script, no instruction file, a file it cannot read, and a symbolic
# link or a name containing a newline under scripts/, skills/, or doctrine/
# (the lists below are newline-separated, so such a name could forge an entry,
# and a link's target would go unscanned).
#
# Untrusted input: the scanned files and their names are PR-controllable.
# awk reads them as data and takes every path through ENVIRON or a list file,
# never its command line; nothing is executed or interpolated into program
# text, and output reaches the terminal with control bytes stripped.
#
# Usage:
#   check-script-invocation.sh [--repo-root <dir>]   default: this script's parent
#   check-script-invocation.sh --help | -h
#
# Exit codes: 0 clean, 1 an instruction runs a bash script through sh or an
# invocation its usage header does not accept, 2 usage or a scan that could
# not cover what it claims.
#
# POSIX sh + awk; no fish/mise/tmux.
set -u

LC_ALL=C
export LC_ALL

unset CDPATH

self_dir="$(cd "$(dirname "$0")" && pwd -P)"

strip_controls() {
  tr -d '\000-\010\013-\037\177\200-\237'
}

fail_closed() {
  printf 'check-script-invocation: %s\n' "$1" | strip_controls >&2
  exit 2
}

usage() {
  cat <<'EOF'
check-script-invocation.sh — no skill instruction runs a bash-shebanged script
through `sh`, or runs a script other than as its usage header says.

Usage:
  check-script-invocation.sh [--repo-root <dir>]   default: this script's parent
  check-script-invocation.sh --help | -h

Scans the .md files under skills/ and doctrine/ for an `sh` invocation whose
operand is a scripts/*.sh whose shebang names bash, and checks each script a
code span or fenced line runs against the script's `# Usage` header (the
grammar is in config/guard-catalog.yaml's script-invocation-house-pattern
entry). Fix a
flagged line by calling the script by its path, or through the interpreter
its shebang names; fix a usage finding in the prose or in the header,
whichever is wrong.

Exit codes: 0 clean, 1 a flagged invocation, 2 usage or a scan that could not
cover what it claims.
EOF
}

root="$self_dir/.."
while [ $# -gt 0 ]; do
  case "$1" in
    --repo-root)
      [ $# -ge 2 ] || {
        usage >&2
        exit 2
      }
      root="$2"
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
done

[ -d "$root" ] || fail_closed "root is not a directory: $root"
root="$(cd "$root" && pwd -P)" || fail_closed "cannot resolve the root"
[ -d "$root/scripts" ] || fail_closed "no scripts/ under $root"

work="$(mktemp -d "${TMPDIR:-/tmp}/check-script-invocation.XXXXXX")" \
  || fail_closed "cannot create a temporary directory"
trap 'rm -rf "$work"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

nl='
'
for d in scripts skills doctrine; do
  [ -e "$root/$d" ] || continue
  find "$root/$d" \( -name "*$nl*" -o -type l \) -print >"$work/odd" \
    || fail_closed "cannot list $root/$d"
  [ ! -s "$work/odd" ] \
    || fail_closed "a symbolic link or a name containing a newline under $d/: $(head -n 1 "$work/odd")"
done

# Lists go through files rather than pipes so a failing `find` is seen: a pipe
# would hand awk a short list and exit 0.
find "$root/scripts/." ! -name . -prune -type f -name '*.sh' >"$work/scripts" \
  || fail_closed "cannot list $root/scripts"
: >"$work/docs"
for d in skills doctrine; do
  [ -d "$root/$d" ] || continue
  find "$root/$d" -type f -name '*.md' >>"$work/docs" \
    || fail_closed "cannot list $root/$d"
done
sort -o "$work/docs" "$work/docs" || fail_closed "cannot sort the instruction list"

: >"$work/err" || fail_closed "cannot write to $work"
rc=0
CSI_ROOT="$root/" CSI_SCRIPTS="$work/scripts" CSI_DOCS="$work/docs" \
  CSI_ERR="$work/err" CSI_SUMMARY="$work/summary" awk '
  function fatal(msg) {
    print "check-script-invocation: " msg > errfile
    failed = 1
    exit
  }
  function is_syn(t, name,    w) {
    w = t
    sub(/[ \t].*/, "", w)
    return w == name || substr(w, length(w) - length(name)) == "/" name
  }
  # The rest of a synopsis line past a run of three blanks and a word, or a
  # parenthesis opening one, is its gloss.
  function cut_gloss(t) {
    if (match(t, /[ \t][ \t][ \t]+([^- \t[<(|]|\([^-<[])/)) t = substr(t, 1, RSTART - 1)
    sub(/[ \t]*\\$/, "", t)
    return t
  }
  # Whether a synopsis so far leaves a [ or ( open, so the next line must
  # continue it.
  function open_group(s,    o, c) {
    o = gsub(/[[(]/, "&", s)
    c = gsub(/[])]/, "&", s)
    return o > c
  }
  function load_header(name,    f, line, r, inb, t, col, scol, cont, n, k) {
    hdone[name] = 1
    f = spath[name]
    inb = 0
    n = 0
    cont = 0
    while ((r = (getline line < f)) > 0) {
      sub(/\r$/, "", line)
      if (!inb) {
        if (line !~ /^#[ \t]*Usage([ \t(:]|$)/) continue
        inb = 1
        t = line
        sub(/^#[ \t]*Usage:?[ \t]*/, "", t)
        if (t != "" && is_syn(t, name)) {
          ftext[name, ++n] = cut_gloss(t)
          scol = length(line) - length(t)
          cont = 1
        }
        continue
      }
      if (line !~ /^#/) break
      t = substr(line, 2)
      sub(/^[ \t]+/, "", t)
      col = length(line) - length(t)
      if (is_syn(t, name)) {
        ftext[name, ++n] = cut_gloss(t)
        scol = col
        cont = 1
      } else if (cont && col > scol && (open_group(ftext[name, n]) || (t ~ /^([[<|-]|\.\.\.)/ && t !~ /[ \t][ \t][ \t]/))) {
        ftext[name, n] = ftext[name, n] " " cut_gloss(t)
      } else {
        cont = 0
      }
    }
    if (r < 0) fatal("cannot read " spath[name])
    close(f)
    nform[name] = n
    hok[name] = n > 0
    for (k = 1; k <= n; k++)
      if (!parse_form(name SUBSEP k, ftext[name, k])) hok[name] = 0
  }
  # A synopsis, its name dropped: literal words (the subcommand), flags with
  # an optional <value> or a|b value, <placeholders>, [optional] groups,
  # (required choices), alternatives joined by |, a ... repeat, and a --
  # separator. 0 when the grammar cannot read it.
  function parse_form(key, s,    tk, nt, i, t, d, prevk, alt, np, parts, j, allf, allw, fl, val, ph, gt, gr, gi, gf, gm, gp, gs, lastp, seenpos, kind) {
    while (match(s, /<[^<> \t][^<>]* [^<>]*[^<> \t]>/)) {
      ph = substr(s, RSTART, RLENGTH)
      gsub(/[ \t]+/, "_", ph)
      s = substr(s, 1, RSTART - 1) ph substr(s, RSTART + RLENGTH)
    }
    gsub(/\.\.\.>/, ">...", s)
    gsub(/\[/, " [ ", s)
    gsub(/\]/, " ] ", s)
    gsub(/\(/, " ( ", s)
    gsub(/\)/, " ) ", s)
    gsub(/\.\.\./, " ... ", s)
    nt = split(s, tk, /[ \t]+/)
    nRF[key] = 0
    nLS[key] = 0
    P[key] = 0
    PO[key] = 0
    PU[key] = 0
    DD[key] = 0
    d = 0
    gr[0] = 1
    prevk = ""
    alt = 0
    lastp = 0
    seenpos = 0
    for (i = 1; i <= nt && tk[i] == ""; i++) ;
    for (i++; i <= nt; i++) {
      t = tk[i]
      if (t == "") continue
      if (t == "[" || t == "(") {
        d++
        gt[d] = t
        gr[d] = t == "(" && gr[d - 1]
        gp[d] = 0
        gm[d] = 0
        gf[d] = 1
        gs[d] = 0
        if (gr[d] && d > 1 && gr[d - 1] && gf[d - 1]) {
          # A choice opening an alternative of a choice lends it its flags.
          gi[d] = gi[d - 1]
          gs[d] = 1
          gf[d - 1] = 0
        } else if (gr[d] && d > 1) {
          # Required only under the alternative it sits in: not checked.
          gr[d] = 0
        } else if (gr[d]) {
          gi[d] = ++nRF[key]
          RF[key, gi[d]] = "|"
        }
        prevk = ""
        alt = 0
        continue
      }
      if (t == "]" || t == ")") {
        if (d < 1 || (t == "]") != (gt[d] == "[")) return 0
        # An alternative holding nothing required meets the choice by itself.
        if (gr[d] && gf[d]) gm[d] = 1
        if (gs[d]) {
          if (gm[d]) gm[d - 1] = 1
        } else if (gr[d] && (gm[d] || RF[key, gi[d]] == "|")) RF[key, gi[d]] = ""
        lastp = gp[d]
        if (gp[d]) gp[d - 1] = 1
        d--
        prevk = "grp"
        alt = 0
        continue
      }
      if (t == "|") {
        if (prevk == "") return 0
        if (d && gr[d]) {
          if (gf[d]) gm[d] = 1
          gf[d] = 1
        }
        alt = 1
        continue
      }
      if (t == "...") {
        if (prevk == "") return 0
        if (prevk == "pos" || (prevk == "grp" && lastp)) PU[key] = 1
        continue
      }
      if (t == "--") { DD[key] = 1; prevk = "dd"; alt = 0; continue }
      # A lone < or > notes what the script reads or writes, not an argument.
      if (t == "<" || t == ">") break
      np = split(t, parts, "|")
      allf = 1
      allw = 1
      for (j = 1; j <= np; j++) {
        if (parts[j] !~ /^--?[A-Za-z0-9][A-Za-z0-9_-]*(=<[^<>]+>)?$/) allf = 0
        if (parts[j] !~ /^[A-Za-z0-9_][A-Za-z0-9_.:,@+=\/-]*$/) allw = 0
      }
      kind = ""
      if ((t ~ /<[^<>]+>/ && t !~ /^-/) || t == "-") kind = "pos"
      else if (allf) kind = "flag"
      else if (allw) kind = seenpos ? "pos" : "lit"
      else return 0
      # A choice between kinds is written inside ( ), never bare.
      if (!d && alt && prevk != kind) return 0
      if (d && gr[d] && gf[d]) {
        if (kind == "flag") {
          for (j = 1; j <= np; j++) {
            fl = parts[j]
            sub(/=.*/, "", fl)
            RF[key, gi[d]] = RF[key, gi[d]] fl "|"
          }
        } else gm[d] = 1
        gf[d] = 0
      }
      if (kind == "pos") {
        if (!(alt && prevk == "pos")) {
          if (d) PO[key]++
          else PN[key, ++P[key]] = t
        }
        for (j = d; j > 0; j--) gp[j] = 1
        seenpos = 1
      } else if (kind == "flag") {
        val = 0
        if (i < nt && tk[i + 1] !~ /^-/ && (tk[i + 1] ~ /<[^<>]+>/ || tk[i + 1] ~ /^[A-Za-z0-9_.-]+(\|[A-Za-z0-9_.-]+)+$/)) {
          val = 1
          i++
        }
        for (j = 1; j <= np; j++) {
          fl = parts[j]
          if (fl ~ /=/) { sub(/=.*/, "", fl); FL[key, fl] = 1 }
          else if (!((key SUBSEP fl) in FL) || val) FL[key, fl] = val
          if (!d) {
            if (j > 1 || (alt && prevk == "flag")) RF[key, nRF[key]] = RF[key, nRF[key]] fl "|"
            else RF[key, ++nRF[key]] = "|" fl "|"
          }
        }
      } else {
        for (j = 1; j <= np; j++) {
          if (d) OL[key, parts[j]] = 1
          else if (j > 1 || (alt && prevk == "lit")) LS[key, nLS[key]] = LS[key, nLS[key]] parts[j] "|"
          else LS[key, ++nLS[key]] = "|" parts[j] "|"
        }
      }
      prevk = kind
      alt = 0
    }
    return d == 0
  }
  function isph(a) { return a ~ /<[^<>]+>/ }
  # "" when the invocation in IA[1..NA] fits the form, else a rank digit, a
  # space, and the reason; a higher rank is a nearer miss.
  function match_form(key,    seen, i, a, fl, hasv, li, pos, dd, g, nm, mem, j, ok, extra) {
    split("", seen)
    li = 1
    pos = 0
    dd = 0
    extra = ""
    for (i = 1; i <= NA; i++) {
      a = IA[i]
      if (a == "..." || a == "\342\200\246") continue
      if (dd) { pos++; continue }
      if (a == "--") {
        if (!DD[key]) return "2 flag \047--\047 is not in its usage header"
        dd = 1
        continue
      }
      if (a ~ /^--?[A-Za-z0-9]/) {
        fl = a
        hasv = 0
        if (fl ~ /=/) { sub(/=.*/, "", fl); hasv = 1 }
        if (!((key SUBSEP fl) in FL)) return "2 flag \047" fl "\047 is not in its usage header"
        if (FL[key, fl] && !hasv) {
          if (i == NA || IA[i + 1] ~ /^--?[A-Za-z0-9]/) return "4 missing a value for " fl
          i++
        }
        seen[fl] = 1
        continue
      }
      if (li <= nLS[key]) {
        if (index(LS[key, li], "|" a "|") || isph(a)) { li++; continue }
        return "1 unknown subcommand \047" a "\047"
      }
      if ((key SUBSEP a) in OL) continue
      if (++pos > P[key] + PO[key] && extra == "") extra = a
    }
    if (li <= nLS[key]) return "1 missing a subcommand"
    for (g = 1; g <= nRF[key]; g++) {
      if (RF[key, g] == "") continue
      nm = split(RF[key, g], mem, "|")
      ok = 0
      for (j = 1; j <= nm; j++) if (mem[j] != "" && (mem[j] in seen)) ok = 1
      if (!ok) return "4 missing required flag " substr(RF[key, g], 2, length(RF[key, g]) - 2)
    }
    if (pos < P[key]) return "4 missing required argument " PN[key, pos + 1]
    if (!PU[key] && extra != "") return "3 unexpected argument \047" extra "\047"
    return ""
  }
  function subcommands(name,    k, s, l) {
    s = ""
    for (k = 1; k <= nform[name]; k++) {
      if (!nLS[name, k]) continue
      l = LS[name, k, 1]
      gsub(/\|/, " ", l)
      sub(/^ /, "", l)
      sub(/ $/, "", l)
      gsub(/ /, ", ", l)
      if (index(", " s ", ", ", " l ", ")) continue
      s = s (s == "" ? "" : ", ") l
    }
    return s
  }
  function finding(ln, name, msg) {
    printf "check-script-invocation: %s:%d: scripts/%s: %s\n", rel, ln, name, msg
    found++
  }
  function valflag(name, fl,    k) {
    for (k = 1; k <= nform[name]; k++) if ((name SUBSEP k SUBSEP fl) in FL && FL[name, k, fl]) return 1
    return 0
  }
  function check_inv(name, ln,    k, err, best, bscore, sc, a1, i, nlit, haslit, ok, fl) {
    ninv++
    if (!(name in hdone)) load_header(name)
    if (!hok[name]) {
      finding(ln, name, "has no usage header the grammar parses (the guard catalog entry script-invocation-house-pattern states it)")
      return
    }
    best = ""
    bscore = -1
    haslit = 0
    a1 = ""
    for (i = 1; i <= NA; i++) {
      if (IA[i] == "..." || IA[i] == "\342\200\246") continue
      if (IA[i] ~ /^-/) {
        fl = IA[i]
        if (fl !~ /=/ && valflag(name, fl)) i++
        continue
      }
      a1 = IA[i]
      break
    }
    for (k = 1; k <= nform[name]; k++) {
      err = match_form(name SUBSEP k)
      if (err == "") return
      if (nLS[name, k]) haslit = 1
      sc = substr(err, 1, 1) * 10
      nlit = nLS[name, k] && a1 != "" && index(LS[name, k, 1], "|" a1 "|")
      sc += nlit * 100
      if (sc > bscore) { bscore = sc; best = substr(err, 3) }
    }
    if (haslit && a1 == "" && bscore != 20) best = "missing a subcommand (its usage header lists: " subcommands(name) ")"
    else if (haslit && a1 != "" && bscore < 100 && !isph(a1)) {
      ok = 0
      for (k = 1; k <= nform[name]; k++) if (nLS[name, k] && index(LS[name, k, 1], "|" a1 "|")) ok = 1
      if (!ok) best = "unknown subcommand \047" a1 "\047 (its usage header lists: " subcommands(name) ")"
    }
    finding(ln, name, best)
  }
  function script_of(w,    name) {
    if (w !~ /(^|\/)scripts\/[A-Za-z0-9_.-]+\.sh$/) return ""
    name = w
    sub(/.*\//, "", name)
    return (name in spath) ? name : ""
  }
  # The index of the ) closing a $( whose body starts at s[i], else 0.
  function close_paren(s, i,    d, c, L, j) {
    d = 1
    L = length(s)
    for (; i <= L; i++) {
      c = substr(s, i, 1)
      if (c == "\\") { i++; continue }
      if (c == "\047") { j = index(substr(s, i + 1), "\047"); if (!j) return 0; i += j; continue }
      if (c == "\042") {
        for (i++; i <= L && substr(s, i, 1) != "\042"; i++) if (substr(s, i, 1) == "\\") i++
        continue
      }
      if (c == "(") d++
      else if (c == ")" && --d == 0) return i
    }
    return 0
  }
  # Shell words and operators of s into TK/TY[1..NT]; quotes are removed, a
  # $( ) stays in its word and its body is queued for its own scan.
  function tokenize(s,    L, i, c, w, inw, j, e, op, nocl, nobt) {
    NT = 0
    nocl = 0
    nobt = 0
    w = ""
    inw = 0
    L = length(s)
    for (i = 1; i <= L; i++) {
      c = substr(s, i, 1)
      if (c == "\047") {
        j = index(substr(s, i + 1), "\047")
        if (!j) { w = w substr(s, i + 1); inw = 1; break }
        w = w substr(s, i + 1, j - 1)
        i += j
        inw = 1
        continue
      }
      if (c == "\042") {
        for (j = i + 1; j <= L; j++) {
          c = substr(s, j, 1)
          if (c == "\\") { w = w substr(s, j + 1, 1); j++; continue }
          if (c == "\042") break
          # An unmatched $( or ` closes nothing later on the line either, so
          # it is looked for once.
          if (c == "$" && substr(s, j + 1, 1) == "(" && !nocl) {
            if ((e = close_paren(s, j + 2))) {
              QT[++NQ] = substr(s, j + 2, e - j - 2)
              w = w substr(s, j, e - j + 1)
              j = e
              continue
            }
            nocl = 1
          }
          if (c == "`" && !nobt) {
            if ((e = index(substr(s, j + 1), "`"))) {
              QT[++NQ] = substr(s, j + 1, e - 1)
              w = w substr(s, j, e + 1)
              j += e
              continue
            }
            nobt = 1
          }
          w = w c
        }
        i = j
        inw = 1
        continue
      }
      if (c == "$" && substr(s, i + 1, 1) == "(" && !nocl) {
        if ((e = close_paren(s, i + 2))) {
          QT[++NQ] = substr(s, i + 2, e - i - 2)
          w = w substr(s, i, e - i + 1)
          i = e
          inw = 1
          continue
        }
        nocl = 1
      }
      if (c == "`" && !nobt) {
        if ((e = index(substr(s, i + 1), "`"))) {
          QT[++NQ] = substr(s, i + 1, e - 1)
          w = w substr(s, i, e + 1)
          i += e
          inw = 1
          continue
        }
        nobt = 1
      }
      # A placeholder may hold blanks, but not end on a redirection (<in 2>).
      if (c == "<" && ((match(substr(s, i), /^<[A-Za-z0-9_][^<>\t`]*[^<> \t`]>/) && substr(s, i, RLENGTH) !~ /[ \t][0-9&]*>$/) || match(substr(s, i), /^<[A-Za-z0-9_][^<> \t`]*>/))) {
        w = w substr(s, i, RLENGTH)
        i += RLENGTH - 1
        inw = 1
        continue
      }
      if (c == " " || c == "\t") {
        if (inw) { TK[++NT] = w; TY[NT] = "w"; w = ""; inw = 0 }
        continue
      }
      if (c == "&" && w ~ /[<>]$/) { w = w c; continue }
      if (c == "|" || c == ";" || c == "&" || c == "(" || c == ")") {
        if (inw) { TK[++NT] = w; TY[NT] = "w"; w = ""; inw = 0 }
        op = c
        if ((c == "|" || c == "&" || c == ";") && substr(s, i + 1, 1) == c) { op = op c; i++ }
        TK[++NT] = op
        TY[NT] = "o"
        continue
      }
      if (c == "#" && !inw) break
      if (c == "\\") { w = w substr(s, i + 1, 1); i++; inw = 1; continue }
      w = w c
      inw = 1
    }
    if (inw) { TK[++NT] = w; TY[NT] = "w" }
  }
  # Check every script run in command position in s, the body of a code span or
  # a fenced command line.
  function scan_cmds(s, ln, fenced,    i, j, a, w, p, name, ran, skipc) {
    tokenize(s)
    i = 1
    while (i <= NT) {
      while (i <= NT && TY[i] == "o") i++
      if (i > NT) break
      ran = fenced || NT > 1
      skipc = 0
      # What may stand before a command: a prompt, keywords, assignments,
      # wrappers and their options, and redirections.
      do {
        p = i
        if (i > NT || TY[i] != "w") break
        w = TK[i]
        if (w ~ /^([$!{]|if|then|elif|else|do|while|until)$/ || w ~ /^[A-Za-z_][A-Za-z0-9_]*=/) i++
        else if (w ~ /^(env|exec|command|time|nohup|setsid)$/)
          for (i++; i <= NT && TY[i] == "w" && TK[i] ~ /^-/; i++) {
            # command -v or -V names a path, it runs nothing.
            if (w == "command" && TK[i] ~ /^-[A-Za-z]*[vV]/) skipc = 1
            if ((w == "env" && TK[i] ~ /^-[uCS]$/) || (w == "exec" && TK[i] == "-a")) i++
          }
        else if (w ~ /^[0-9]*[<>]/ && !isph(w)) {
          i++
          if (w ~ /^[0-9]*[<>]+&?$/) i++
        }
      } while (i > p)
      if (i <= NT && TY[i] == "w" && TK[i] ~ /(^|\/)(ba|da|z)?sh$/) {
        ran = 1
        for (i++; i <= NT && TY[i] == "w" && TK[i] ~ /^[-+]/; i++) {
          # -c runs a string, -n reads without running.
          if (TK[i] ~ /^-[A-Za-z]*[cn]/) skipc = 1
          if (TK[i] ~ /^[-+][A-Za-z]*[oO]$/ || TK[i] ~ /^--(rcfile|init-file)$/) i++
        }
      }
      if (!skipc && i <= NT && TY[i] == "w" && (name = script_of(TK[i])) != "") {
        NA = 0
        for (j = i + 1; j <= NT && TY[j] == "w"; j++) {
          a = TK[j]
          if (a ~ /^[0-9]*<</) break
          if (a ~ /^[0-9]*[<>]/ && !isph(substr(a, 1, index(a, ">")))) {
            if (a ~ /^[0-9]*[<>]+&?$/) j++
            continue
          }
          # Prose may mark an argument [optional] as a synopsis does.
          if (a ~ /^\[/ || a ~ /\](\.\.\.)?$/) gsub(/^\[+|(\]|\.\.\.)+$/, "", a)
          if (a != "") IA[++NA] = a
        }
        if (NA || ran) check_inv(name, ln)
        i = j
        continue
      }
      while (i <= NT && TY[i] == "w") i++
    }
  }
  # The delimiters of the heredocs a command line opens, from its unquoted
  # words, in order, each ended by SUBSEP: the bodies follow one another.
  function heredoc(s,    i, d, q) {
    tokenize(s)
    q = ""
    for (i = 1; i <= NT; i++) {
      if (TY[i] != "w") continue
      d = ""
      if (TK[i] ~ /^[0-9]*<<-?$/ && i < NT && TY[i + 1] == "w") d = TK[++i]
      else if (TK[i] ~ /^[0-9]*<<-?[^<-]/) { d = TK[i]; sub(/^[0-9]*<<-?/, "", d) }
      else continue
      # The delimiter is a word; a redirection may follow it unspaced.
      sub(/[<>].*/, "", d)
      if (d != "") q = q d SUBSEP
    }
    return q
  }
  function scan(s, ln, fenced,    q) {
    NQ = 0
    scan_cmds(s, ln, fenced)
    for (q = 1; q <= NQ; q++) scan_cmds(QT[q], ln, 1)
  }
  # The code spans of s from pos, reported at line ln; an opener without a
  # closer on the line leaves a span open for the next line of its block.
  function scan_spans(s, pos, ln,    os, ol, rest, off, cs, cl, got) {
    while (match(substr(s, pos), /`+/)) {
      os = pos + RSTART - 1
      ol = RLENGTH
      rest = substr(s, os + ol)
      off = 0
      got = 0
      while (match(substr(rest, off + 1), /`+/)) {
        cs = off + RSTART
        cl = RLENGTH
        if (cl == ol) { got = 1; break }
        off = cs + cl - 1
      }
      if (!got) {
        popen = ol
        pend = rest
        pline = ln
        return
      }
      scan(substr(rest, 1, cs - 1), ln, 0)
      pos = os + ol + cs + cl - 1
    }
  }
  # A block ended with a span still open: its opener was literal text, so
  # the rest of the block is read again without it.
  function flush_spans(    s) {
    while (popen) {
      popen = 0
      s = pend
      pend = ""
      scan_spans(s, 1, pline)
    }
  }
  function spans(line,    off, cs, cl) {
    if (popen) {
      off = 0
      while (match(substr(line, off + 1), /`+/)) {
        cs = off + RSTART
        cl = RLENGTH
        if (cl == popen) {
          popen = 0
          scan(pend " " substr(line, 1, cs - 1), pline, 0)
          pend = ""
          scan_spans(line, cs + cl, FNR)
          return
        }
        off = cs + cl - 1
      }
      pend = pend " " line
      return
    }
    scan_spans(line, 1, FNR)
  }
  BEGIN {
    root = ENVIRON["CSI_ROOT"]
    errfile = ENVIRON["CSI_ERR"]
    list = ENVIRON["CSI_SCRIPTS"]
    while ((r = (getline f < list)) > 0) {
      first = ""
      if ((getline first < f) < 0) fatal("cannot read " f)
      close(f)
      sub(/\r$/, "", first)
      if (first !~ /^#!/) continue
      shebanged++
      name = f
      sub(/.*\//, "", name)
      spath[name] = f
      if (first ~ /^#!(.*[\/ \t])?bash([ \t]|$)/) {
        bash[name] = 1
        nbash++
      }
    }
    if (r < 0) fatal("cannot read the script list")
    close(list)
    if (!shebanged) fatal("no shebanged scripts/*.sh under " root)
    list = ENVIRON["CSI_DOCS"]
    while ((r = (getline f < list)) > 0) {
      if (substr(f, 1, length(root)) != root) fatal("listed file outside the root: " f)
      if ((getline probe < f) < 0) fatal("cannot read " f)
      close(f)
      ARGV[ARGC++] = f
      ndocs++
    }
    if (r < 0) fatal("cannot read the instruction list")
    close(list)
    if (!ndocs) fatal("no .md file under skills/ or doctrine/ in " root)
  }
  FNR == 1 {
    if (NR > 1) flush_spans()
    rel = substr(FILENAME, length(root) + 1)
    infence = 0
    pend = ""
    popen = 0
    fcont = ""
    hdoc = ""
  }
  /sh/ {
    line = $0
    sub(/\r$/, "", line)
    n = split(line, w, /[ \t]+/)
    for (i = 1; i <= n; i++) {
      # An sh command word: the token, unquoted and cut at a redirect glued
      # to it, ends in sh, preceded by nothing, any path ending in /, or
      # punctuation that opens a command.
      cw = w[i]
      gsub(/[\042\047]/, "", cw)
      rd = ""
      if (match(cw, /sh[0-9]*[<>]/)) {
        rd = substr(cw, RSTART + 2)
        cw = substr(cw, 1, RSTART + 1)
      }
      if (cw !~ /(^|[^A-Za-z0-9_.-])([^ \t]*\/)?sh$/) continue
      skip = 0
      op = ""
      j = i + 1
      if (rd ~ /^</ && rd ~ /scripts\//) {
        op = rd
        j = n + 1
      } else if (rd ~ /^[0-9]*[<>]+$/) {
        if (!(rd == "<" && j <= n && w[j] ~ /scripts\//)) j++
      }
      for (; j <= n; j++) {
        a = w[j]
        if (a == "--" || a == "-") continue
        # `sh < scripts/x.sh` reads the script on stdin; `sh < in x.sh` runs x.sh.
        if (a == "<") {
          if (j < n && w[j + 1] !~ /scripts\//) j++
          continue
        }
        if (a ~ /^[-+]o$/) { j++; continue }
        if (a ~ /^[0-9]*>+$/ || a ~ /^[0-9]+<$/) { j++; continue }
        if (a ~ /^--[A-Za-z]/ || a ~ /^[0-9]*>/ || a ~ /^[0-9]+</) continue
        if (a ~ /^[-+][A-Za-z]+</) {
          op = a
          sub(/^[^<]*/, "", op)
          break
        }
        if (a ~ /^[-+][A-Za-z]+$/) {
          if (a ~ /^-[A-Za-z]*c/) skip = 1
          if (skip) break
          continue
        }
        op = a
        break
      }
      if (skip || op == "") continue
      gsub(/[\042\047]/, "", op)
      # A <placeholder> is part of the path; any other < or > is a redirect,
      # before the operand or glued after it.
      gsub(/<[A-Za-z0-9_-]+>/, "R", op)
      sub(/^</, "", op)
      sub(/[]`;|&<>].*$/, "", op)
      sub(/[).,:*}]+$/, "", op)
      if (op !~ /(^|\/)scripts\/[^\/]+$/) continue
      name = op
      sub(/.*\//, "", name)
      if (name in bash) {
        printf "check-script-invocation: %s:%d: runs scripts/%s through sh, but its shebang names bash; call it by its path or through bash\n", rel, FNR, name
        found++
      }
    }
  }
  {
    line = $0
    sub(/\r$/, "", line)
    t = line
    sub(/^[ \t]+/, "", t)
    # A fence may open inside a list item or a quote.
    ft = t
    sub(/^(>[ \t]*)+/, "", ft)
    sub(/^([-*+]|[0-9]+[.)])[ \t]+/, "", ft)
    if (infence) {
      if (index(ft, fmark) == 1 && ft ~ /^(`+|~+)[ \t]*$/) {
        if (fcont != "") scan(fcont, fline, 1)
        infence = 0
        fcont = ""
        hdoc = ""
      } else if (hdoc != "") {
        if (fquote) sub(/^(>[ \t]*)+/, "", t)
        if (t SUBSEP == substr(hdoc, 1, length(t) + 1)) hdoc = substr(hdoc, length(t) + 2)
      } else {
        if (fquote) sub(/^(>[ \t]*)+/, "", t)
        if (fcont == "") fline = FNR
        t = fcont t
        if (t ~ /\\$/) fcont = substr(t, 1, length(t) - 1) " "
        else {
          fcont = ""
          scan(t, fline, 1)
          # A heredoc body is data, not commands.
          hdoc = heredoc(t)
        }
      }
    } else if ((match(ft, /^```+/) && substr(ft, RLENGTH + 1) !~ /`/) || match(ft, /^~~~+/)) {
      flush_spans()
      infence = 1
      fmark = substr(ft, 1, RLENGTH)
      fquote = t ~ /^>/
      fcont = ""
      hdoc = ""
    } else if (t == "") flush_spans()
    else {
      if (t ~ /^#+([ \t]|$)/ || t ~ /^([-*+]|[0-9]+[.)])[ \t]/) flush_spans()
      spans(line)
      # A heading is a block of one line.
      if (t ~ /^#+([ \t]|$)/) flush_spans()
    }
  }
  END {
    if (failed) exit 2
    flush_spans()
    print ndocs + 0, nbash + 0, ninv + 0 > ENVIRON["CSI_SUMMARY"]
    exit found ? 1 : 0
  }
' </dev/null >"$work/out" 2>"$work/awkerr" || rc=$?

strip_controls <"$work/out" >&2
cat "$work/err" "$work/awkerr" | strip_controls >&2
case "$rc" in
  0) ;;
  1)
    n=$(grep -c '' "$work/out") || n=0
    [ "$n" -gt 0 ] || fail_closed "the scan did not complete (awk exit 1, no findings)"
    printf 'check-script-invocation: %s flagged invocation(s)\n' "$n" >&2
    exit 1
    ;;
  *) fail_closed "the scan did not complete (awk exit $rc)" ;;
esac
read -r ndocs nbash ninv <"$work/summary" || fail_closed "the scan wrote no summary"
printf 'check-script-invocation: clean (%s instruction files, %s bash scripts, %s invocations checked against usage headers)\n' \
  "$ndocs" "$nbash" "$ninv"
