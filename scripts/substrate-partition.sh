#!/bin/sh
# substrate-partition.sh — partition the shipped script layer into tiers by who
# invokes each script, derived from the call graph on every run.
#
# THE LAYER. Every file under scripts/ with a `.sh` suffix or a shell shebang,
# plus every file under githooks/ (the tracked git hooks).
#
# CALLERS. A script is named by a caller when a caller's text holds its path
# (`scripts/<name>`, `<anything>/<name>`, or a bare `<name>.sh`). The callers,
# by kind:
#   git       the script is itself a tracked git hook
#   githook   named in a tracked git hook's code
#   hook      named in a hook registration's command (hooks/hooks.json and the
#             worker and tower settings fragments under config/)
#   skill     named anywhere in a skill body (skills/**/SKILL.md)
#   script    named in another layer script's code
#   task      named in the run body of a task in mise.toml
#   workflow  named in a .github/workflows file
#   test      named in a shell file under tests/
# A description, a whole-line comment, a script comment, a heredoc body, and
# any Markdown file that is not a skill body name nothing.
#
# TIER. The first that holds, in this order: hook (git, githook, or hook),
# skill-called (skill), library (script), dev-check (task or workflow),
# tests-only (anything else, a test or nothing at all).
#
# FLAG. `no-live-caller` when the script is unreachable through script calls
# from a live entry point: a hook registration, a tracked git hook, a skill
# body, a task, or a workflow. A test is not a live caller, and neither is a
# flagged script, so a library only a flagged script calls is flagged too.
#
# MUTATION. `shell-mutation` when the script `eval`s an argument holding an
# expansion, or sources (`.`/`source`) a path whose file name holds one. A
# literal eval and a source of a named library are not flagged, and neither is
# a source of `"$var"` when every value the script assigns to `var` ends in a
# literal file name.
#
# PROFILE. Every command word the script runs that is not a shell builtin, a
# function defined by the script, by a script it calls (a sourced library), or
# by a direct caller (a callback), or a layer script: the external processes
# it drives.
# A word reached through `command`, `exec`, `env`, `nohup`, `nice`, `sudo`,
# `time`, `timeout`, or `xargs` counts; `command -v`'s operand is a lookup and
# does not.
#
# UNRESOLVED. A command word or sourced path whose file name is built from an
# expansion (`"$dir/$name.sh"`), so no literal script name can be read from it.
# It is reported, never counted as a caller.
#
# KNOWN LIMITS. The scanner is a tokenizer, not a shell parser: a script name
# in a live line that does not run it (an echo, a message string) still counts
# as a call; the text inside `sh -c '...'`, a trap handler, or a heredoc body is
# not scanned for commands; a command reached only through a variable holding
# its name (`"$TOOL" args`) is not in the profile.
#
# Output: one header line, then one tab-separated row per layer script, sorted
# by path: path, tier, flag, callers, mutation, profile, unresolved; `-` marks
# an empty field, list fields are comma-separated.
#
# Usage: substrate-partition.sh [--repo-root <dir>]
# Exit codes: 0 partition written; 2 usage error; 5 fail-closed (an input that
# would make the partition vacuous or wrong: no layer, a missing or unreadable
# hook registration, task file, skills or workflows directory, a duplicate
# script file name, or a missing jq or mise).
#
# POSIX sh on the macOS + Linux support bar. All input is data.
set -uf

LC_ALL=C
export LC_ALL
unset CDPATH

me=substrate-partition
script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2
repo_root=$(cd "$script_dir/.." && pwd) || exit 2

while [ "$#" -gt 0 ]; do
  case $1 in
    --repo-root)
      [ "$#" -ge 2 ] || {
        printf '%s\n' "$me: --repo-root needs a directory" >&2
        exit 2
      }
      repo_root=$2
      shift 2
      ;;
    -h | --help)
      printf '%s\n' "usage: substrate-partition.sh [--repo-root <dir>]" >&2
      exit 0
      ;;
    *)
      printf '%s\n' "$me: unknown argument" >&2
      exit 2
      ;;
  esac
done

repo_root=$(cd "$repo_root" 2>/dev/null && pwd) || {
  printf '%s\n' "$me: repo root is not a readable directory" >&2
  exit 5
}

fail_closed() {
  printf '%s\n' "$me: $1 — failing closed rather than writing a partition" >&2
  exit 5
}

for tool in jq mise; do
  command -v "$tool" >/dev/null 2>&1 || fail_closed "'$tool' is not on PATH"
done
for need in scripts skills .github/workflows; do
  [ -d "$repo_root/$need" ] && [ -r "$repo_root/$need" ] || fail_closed "$need/ is missing or unreadable"
done
for need in mise.toml hooks/hooks.json; do
  [ -r "$repo_root/$need" ] || fail_closed "$need is missing or unreadable"
done

tab=$(printf '\t')
nl='
'
odd=$(find "$repo_root/scripts" "$repo_root/githooks" -name "*$tab*" -o -name "*$nl*" 2>/dev/null)
[ -z "$odd" ] || fail_closed "a layer path holds a tab or newline"

work=$(mktemp -d "${TMPDIR:-/tmp}/substrate-partition.XXXXXX") || fail_closed "mktemp -d failed"
[ -n "$work" ] && [ -d "$work" ] || fail_closed "mktemp -d produced no directory"
trap 'rm -rf "$work"' EXIT
trap 'exit 1' HUP INT TERM

is_shell_file() {
  case $1 in
    *.sh) return 0 ;;
  esac
  head -n 1 "$1" 2>/dev/null | grep -Eq '^#![[:space:]]*[^[:space:]]*(/|env[[:space:]]+)(ba|da|k|z|a)?sh([[:space:]]|$)'
}

{
  find "$repo_root/scripts" -type f | while IFS= read -r f; do
    is_shell_file "$f" && printf '%s\n' "${f#"$repo_root"/}"
  done
  if [ -d "$repo_root/githooks" ]; then
    find "$repo_root/githooks" -maxdepth 1 -type f | while IFS= read -r f; do
      printf '%s\n' "${f#"$repo_root"/}"
    done
  fi
} | sort >"$work/layer"
[ -s "$work/layer" ] || fail_closed "found no script in the layer"

dups=$(awk '/^scripts\// { b = $0; sub(/.*\//, "", b); print b }' "$work/layer" | sort | uniq -d)
[ -z "$dups" ] || fail_closed "two layer scripts share a file name, so a call to one cannot be told from the other"

# Caller texts, one `T<tab>kind<tab>line` record per line.
caller_lines() {
  awk -v k="$1" '{ gsub(/\t/, " "); print "T\t" k "\t" $0 }'
}

for f in hooks/hooks.json config/worker-settings.json config/tower-settings.json; do
  [ -e "$repo_root/$f" ] || continue
  jq -r '.hooks // {} | [.. | objects | .command? // empty | strings] | .[]' "$repo_root/$f" \
    >"$work/hookcmds" 2>/dev/null || fail_closed "$f is not readable JSON"
  caller_lines hook <"$work/hookcmds" >>"$work/facts"
done

find "$repo_root/skills" -type f -name SKILL.md | sort | while IFS= read -r f; do
  caller_lines skill <"$f"
done >>"$work/facts"

find "$repo_root/.github/workflows" -type f \( -name '*.yml' -o -name '*.yaml' \) | sort | while IFS= read -r f; do
  grep -v '^[[:space:]]*#' "$f" | caller_lines workflow
done >>"$work/facts"

if [ -d "$repo_root/tests" ]; then
  find "$repo_root/tests" -type f | sort | while IFS= read -r f; do
    is_shell_file "$f" && caller_lines test <"$f"
  done >>"$work/facts"
fi

# The run bodies of the tasks mise.toml itself defines, as mise renders them,
# so TOML quoting is mise's business. Descriptions are prose and never read.
# MISE_TRUSTED_CONFIG_PATHS keeps a fixture tree from stopping on the trust
# prompt; this only lists tasks, never runs one.
graph=$(cd "$repo_root" && MISE_TRUSTED_CONFIG_PATHS="$repo_root" mise tasks --json --hidden 2>/dev/null) || graph=''
[ -n "$graph" ] || fail_closed "'mise tasks --json --hidden' produced nothing"
printf '%s' "$graph" | jq -r --arg src "$repo_root/mise.toml" '
  [ .[] | select(.source == $src) ]
  | if length == 0 then "NOTASKS" else
      .[] | (.run // []) | map(select(type == "string")) | join("\n")
    end
' >"$work/runs" 2>/dev/null || fail_closed "could not read the task graph"
[ "$(head -n 1 "$work/runs")" != NOTASKS ] || fail_closed "the task graph holds no task from this repo's mise.toml"
grep -v '^[[:space:]]*#' "$work/runs" | caller_lines task >>"$work/facts"

# The layer's own code, through the tokenizer: W (every word), C (a command
# word), F (a function it defines), M (a non-literal eval or source), U (an
# unresolved invocation).
set --
while IFS= read -r p; do
  set -- "$@" "$repo_root/$p"
done <"$work/layer"

# shellcheck disable=SC2016 # an awk program: the $ names are awk's
awk -v root="$repo_root" '
function out(kind, text) {
  gsub(/\t/, " ", text)
  print kind "\t" path "\t" text
}
function initframe(i, purpose) {
  ctx[i] = "c"; fr[i] = purpose; cmdpos[i] = 1; mode[i] = ""; wrap[i] = ""
  skip[i] = 0; wrapskip[i] = 0; ev[i] = 0; src[i] = 0; decl[i] = 0; w[i] = ""; wexp[i] = 0; wq[i] = 0; wany[i] = 0; nw[i] = 0
}
function findcf(  k) {
  for (k = d; k >= 1; k--) if (ctx[k] == "c") return k
  return 1
}
function reset() {
  d = 1; initframe(1, "top"); cf = 1
  hd_n = 0; hd_i = 0; inhd = 0; cont = 0; hdstrip = 0
}
function push(t) { d++; ctx[d] = t; adep[d] = 0; cf = findcf() }
function pushframe(purpose) { d++; initframe(d, purpose); cf = d }
function pop() { if (d > 1) d--; cf = findcf() }
function popframe(  p, empty) {
  p = fr[cf]; empty = (nw[cf] == 0)
  if (d <= 1) return
  d--; cf = findcf()
  if (p == "cs" || p == "bq") app("$(...)", 1)
  else if (p == "ps") app("<(...)", 1)
  else if (p == "sub") cmdpos[cf] = empty ? 1 : 0
}
function app(s, isexp) {
  w[cf] = w[cf] s; wany[cf] = 1
  if (isexp) wexp[cf] = 1
}
function mut() { out("M", "") }
function endword(  x, e, q, b) {
  if (!wany[cf]) return
  x = w[cf]; e = wexp[cf]; q = wq[cf]
  w[cf] = ""; wexp[cf] = 0; wq[cf] = 0; wany[cf] = 0; nw[cf]++
  out("W", x)
  if (skip[cf] == 1) { skip[cf] = 0; return }
  if (skip[cf] == 2) { skip[cf] = 0; hd_n++; hdd[hd_n] = x; hds[hd_n] = hdstrip; return }
  if (fr[cf] == "arr") return
  if (mode[cf] == "pat") {
    if (x == "esac" && !q) { mode[cf] = ""; cmdpos[cf] = 0 }
    return
  }
  if (mode[cf] == "chead") { if (x == "in") mode[cf] = "pat"; return }
  if (mode[cf] == "forskip") return
  if (mode[cf] == "dbl") { if (x == "]]") { mode[cf] = ""; cmdpos[cf] = 0 }; return }
  if (mode[cf] == "fname") { out("F", x); mode[cf] = ""; cmdpos[cf] = 1; return }
  if (ev[cf]) { if (e) mut(); return }
  if (src[cf]) {
    src[cf] = 0
    if (e && x ~ /^\$\{?[A-Za-z_][A-Za-z0-9_]*\}?$/) {
      b = x; gsub(/[${}]/, "", b); out("S", b)
      return
    }
    b = x; sub(/.*\//, "", b)
    if (b ~ /\$/ || b == "") { mut(); out("U", x) }
    return
  }
  if (decl[cf] && x ~ assignre) { assign(x); return }
  if (!cmdpos[cf]) return
  if (wrap[cf] != "") {
    if (wrapskip[cf]) { wrapskip[cf] = 0; return }
    if (!e && x ~ /^-/) {
      if (wrap[cf] == "command" && x ~ /^-[A-Za-z]*[vV]/) { wrap[cf] = ""; cmdpos[cf] = 0 }
      else if (wrap[cf] == "env" && x ~ /^-[uCS]$/ || wrap[cf] == "timeout" && x ~ /^-[sk]$/ || wrap[cf] == "nice" && x == "-n" || wrap[cf] == "xargs" && x ~ /^-[IinPLsdE]$/) wrapskip[cf] = 1
      return
    }
    if (wrap[cf] == "env" && x ~ /^[A-Za-z_][A-Za-z0-9_]*=/) return
    if (wrap[cf] ~ /^(timeout|nice|xargs)$/ && x ~ /^[0-9][0-9.]*[smhd]?$/) return
    wrap[cf] = ""
  } else if (x ~ assignre) { assign(x); return }
  if (!e && !q) {
    if (x ~ /^(if|then|else|elif|do|while|until|!|\{|time)$/) return
    if (x ~ /^(fi|done|\}|esac)$/) { mode[cf] = ""; cmdpos[cf] = 0; return }
    if (x == "for" || x == "select") { mode[cf] = "forskip"; return }
    if (x == "case") { mode[cf] = "chead"; return }
    if (x == "function") { mode[cf] = "fname"; return }
    if (x == "[[") { mode[cf] = "dbl"; return }
  }
  cmdpos[cf] = 0
  if (e) {
    if (x ~ /\//) { b = x; sub(/.*\//, "", b); if (b ~ /\$/) out("U", x) }
    return
  }
  b = x; sub(/.*\//, "", b)
  out("C", b)
  if (x ~ /^(command|exec|builtin|nohup|nice|env|xargs|timeout|sudo|time)$/) { wrap[cf] = x; cmdpos[cf] = 1 }
  else if (x == "eval") ev[cf] = 1
  else if (x == "." || x == "source") src[cf] = 1
  else if (x ~ /^(local|export|readonly|declare|typeset)$/) decl[cf] = 1
}
# A sourced `$name` resolves when every value the script assigns to `name`
# ends in a literal file name; the A records let the assembly stage judge.
function assign(x,   name, v, b) {
  name = x; sub(/[+[=].*/, "", name)
  v = x; sub(/^[^=]*=/, "", v)
  if (v == "") return
  b = v; sub(/.*\//, "", b)
  out("A", name " " ((b ~ /\$/) ? 0 : 1))
}
function sep() {
  endword()
  if (mode[cf] == "pat" || mode[cf] == "chead" || mode[cf] == "dbl") return
  if (mode[cf] == "forskip" || mode[cf] == "fname") mode[cf] = ""
  cmdpos[cf] = 1; wrap[cf] = ""; wrapskip[cf] = 0; ev[cf] = 0; src[cf] = 0; skip[cf] = 0; decl[cf] = 0
}
function dollar(s, i,   c2) {
  c2 = substr(s, i + 1, 1)
  if (c2 == "(") {
    if (substr(s, i + 2, 1) == "(") { app("$((...))", 1); push("a"); return i + 3 }
    pushframe("cs"); return i + 2
  }
  if (c2 == "{") { app("${", 1); push("p"); return i + 2 }
  if (ctx[d] == "c" && c2 == "\047") { wq[cf] = 1; wany[cf] = 1; push("e"); return i + 2 }
  if (ctx[d] == "c" && c2 == "\"") { wq[cf] = 1; wany[cf] = 1; push("d"); return i + 2 }
  if (c2 ~ /[A-Za-z0-9_@*#?$!-]/) { app("$", 1); return i + 1 }
  app("$", 0); return i + 1
}
function lex(s,   i, n, c, c2, t) {
  n = length(s); i = 1
  while (i <= n) {
    c = substr(s, i, 1); t = ctx[d]
    if (t == "q") { if (c == "\047") pop(); else app(c, 0); i++; continue }
    if (t == "e") {
      if (c == "\\") { app(substr(s, i, 2), 0); i += 2; continue }
      if (c == "\047") pop(); else app(c, 0)
      i++; continue
    }
    if (c == "\\") {
      if (i == n) { cont = 1; i++; continue }
      app(substr(s, i + 1, 1), 0); i += 2; continue
    }
    if (c == "$") { i = dollar(s, i); continue }
    if (c == "`") {
      if (t == "c" && fr[cf] == "bq") popframe(); else pushframe("bq")
      i++; continue
    }
    if (t == "d") { if (c == "\"") pop(); else app(c, 0); i++; continue }
    if (t == "p") {
      if (c == "}") { app("}", 1); pop() }
      else if (c == "\047") push("q")
      else if (c == "\"") push("d")
      else app(c, 1)
      i++; continue
    }
    if (t == "a") {
      if (c == "(") adep[d]++
      else if (c == ")") {
        if (adep[d] == 0) { if (substr(s, i + 1, 1) == ")") i++; pop() }
        else adep[d]--
      }
      i++; continue
    }
    if (c == " " || c == "\t") { endword(); i++; continue }
    if (c == "#" && !wany[cf]) break
    if (c == "\047") { wq[cf] = 1; wany[cf] = 1; push("q"); i++; continue }
    if (c == "\"") { wq[cf] = 1; wany[cf] = 1; push("d"); i++; continue }
    if (c == ";") {
      endword(); c2 = substr(s, i + 1, 1)
      if (c2 == ";" || c2 == "&") {
        i += 2; if (substr(s, i, 1) == "&") i++
        mode[cf] = "pat"; cmdpos[cf] = 0; continue
      }
      sep(); i++; continue
    }
    if (c == "&") {
      endword(); c2 = substr(s, i + 1, 1)
      if (c2 == ">") { i += 2; if (substr(s, i, 1) == ">") i++; skip[cf] = 1; continue }
      if (c2 == "&") i++
      sep(); i++; continue
    }
    if (c == "|") {
      endword()
      if (mode[cf] == "pat") { i++; continue }
      c2 = substr(s, i + 1, 1)
      if (c2 == "|" || c2 == "&") i++
      sep(); i++; continue
    }
    if (c == "<" || c == ">") {
      if (wany[cf] && !wq[cf] && !wexp[cf] && w[cf] ~ /^[0-9]+$/) { w[cf] = ""; wany[cf] = 0 }
      else endword()
      if (mode[cf] == "dbl") { i++; continue }
      c2 = substr(s, i + 1, 1)
      if (c2 == "(") { pushframe("ps"); i += 2; continue }
      if (c == "<" && c2 == "<") {
        if (substr(s, i + 2, 1) == "<") { i += 3; skip[cf] = 1; continue }
        i += 2; hdstrip = 0
        if (substr(s, i, 1) == "-") { hdstrip = 1; i++ }
        skip[cf] = 2; continue
      }
      i++; c2 = substr(s, i, 1)
      if (c2 == ">" || c2 == "&" || c2 == "|") i++
      skip[cf] = 1; continue
    }
    if (c == "(") {
      if (mode[cf] == "pat" || mode[cf] == "chead" || mode[cf] == "dbl") { endword(); i++; continue }
      if (wany[cf] && !wq[cf] && w[cf] ~ /=$/) { endword(); pushframe("arr"); i++; continue }
      endword()
      if ((cmdpos[cf] || mode[cf] == "forskip") && substr(s, i + 1, 1) == "(") {
        cmdpos[cf] = 0; push("a"); i += 2; continue
      }
      pushframe("sub"); i++; continue
    }
    if (c == ")") {
      endword()
      if (mode[cf] == "pat") { mode[cf] = ""; cmdpos[cf] = 1; i++; continue }
      if (mode[cf] == "dbl" || mode[cf] == "chead") { i++; continue }
      if (fr[cf] ~ /^(cs|sub|arr|ps)$/) popframe()
      i++; continue
    }
    app(c, 0); i++
  }
}
function eol() {
  if (cont) { cont = 0; return }
  if (ctx[d] == "c") sep()
  else if (ctx[d] == "d" || ctx[d] == "q" || ctx[d] == "e") app(" ", 0)
}
BEGIN { assignre = "^[A-Za-z_][A-Za-z0-9_]*(\\[[^=]*\\])?\\+?=" }
FNR == 1 {
  if (NR > 1) endword()
  reset()
  path = substr(FILENAME, length(root) + 2)
}
{
  line = $0
  if (inhd) {
    t = line
    if (hds[hd_i]) sub(/^\t+/, "", t)
    if (t == hdd[hd_i]) { hd_i++; if (hd_i > hd_n) { inhd = 0; hd_n = 0 } }
    next
  }
  if (match(line, /^[ \t]*(function[ \t]+)?[A-Za-z_][A-Za-z0-9_:.-]*[ \t]*\(\)/)) {
    fn = substr(line, RSTART, RLENGTH)
    sub(/^[ \t]*(function[ \t]+)?/, "", fn); sub(/[ \t]*\(\)$/, "", fn)
    out("F", fn)
  }
  lex(line)
  eol()
  if (hd_n > 0 && !inhd) { inhd = 1; hd_i = 1 }
}
END { if (NR > 0) endword() }
' "$@" >>"$work/facts" || fail_closed "the tokenizer failed over the layer"

# shellcheck disable=SC2016 # an awk program: the $ names are awk's
awk -F'\t' '
function refs(text,   n, i, m, j, c, res, toks, comps) {
  gsub(/[^A-Za-z0-9_.\/-]/, " ", text)
  n = split(text, toks, " ")
  res = ""
  for (i = 1; i <= n; i++) {
    m = split(toks[i], comps, "/")
    for (j = 1; j <= m; j++) {
      c = comps[j]
      if (!(c in byname)) continue
      if (j == 1 && c !~ /\.sh$/) continue
      if (j > 1 && comps[j - 1] == "tests") continue
      if (j > 2 && comps[j - 1] == "lib" && comps[j - 2] == "tests") continue
      res = res "\n" byname[c]
    }
  }
  return res
}
function sorted(list,   n, a, i, j, x, res) {
  n = split(list, a, "\n")
  for (i = 2; i <= n; i++) {
    x = a[i]
    for (j = i - 1; j >= 1 && a[j] > x; j--) a[j + 1] = a[j]
    a[j + 1] = x
  }
  res = ""
  for (i = 1; i <= n; i++) if (a[i] != "") res = res (res == "" ? "" : ",") a[i]
  return res == "" ? "-" : res
}
BEGIN {
  nb = split(": . [ alias bg break builtin caller cd command compgen complete continue declare dirs disown echo enable eval exec exit export false fc fg getopts hash help history jobs kill let local logout mapfile popd printf pushd pwd read readarray readonly return set shift shopt source suspend test times trap true type typeset ulimit umask unalias unset wait", bl, " ")
  for (i = 1; i <= nb; i++) builtin[bl[i]] = 1
  nk = split("git githook hook skill script task workflow test", kinds, " ")
}
NR == FNR {
  np++; paths[np] = $1
  b = $1; sub(/.*\//, "", b)
  if ($1 ~ /^scripts\//) byname[b] = $1
  else { isgit[$1] = 1; has[$1, "git"] = 1 }
  next
}
$1 == "T" {
  n = split(refs($3), hits, "\n")
  for (i = 1; i <= n; i++) if (hits[i] != "") has[hits[i], $2] = 1
  next
}
$1 == "W" {
  n = split(refs($3), hits, "\n")
  for (i = 1; i <= n; i++) {
    t = hits[i]
    if (t == "" || t == $2) continue
    has[t, ($2 in isgit) ? "githook" : "script"] = 1
    if (!(($2, t) in edge)) { edge[$2, t] = 1; ne++; esrc[ne] = $2; edst[ne] = t }
  }
  next
}
$1 == "C" {
  if (!(($2, $3) in cmd)) { cmd[$2, $3] = 1; clist[$2] = clist[$2] "\n" $3 }
  next
}
$1 == "F" {
  if (!(($2, $3) in fn)) { fn[$2, $3] = 1; flist[$2] = flist[$2] "\n" $3 }
  next
}
$1 == "A" {
  split($3, a, " ")
  assigned[$2, a[1]] = 1
  if (a[2] == 0) nonlit[$2, a[1]] = 1
  next
}
$1 == "S" { ns++; spath[ns] = $2; sname[ns] = $3; next }
$1 == "M" { mut[$2] = 1; next }
$1 == "U" {
  if (!(($2, $3) in unres)) { unres[$2, $3] = 1; ulist[$2] = ulist[$2] "\n" $3 }
  next
}
END {
  for (s = 1; s <= ns; s++) {
    p = spath[s]; x = sname[s]
    if (((p, x) in assigned) && !((p, x) in nonlit)) continue
    mut[p] = 1
    if (!((p, "$" x) in unres)) { unres[p, "$" x] = 1; ulist[p] = ulist[p] "\n$" x }
  }
  for (e = 1; e <= ne; e++) {
    adj[esrc[e]] = adj[esrc[e]] "\n" edst[e]
    radj[edst[e]] = radj[edst[e]] "\n" esrc[e]
  }
  for (i = 1; i <= np; i++) {
    p = paths[i]
    if ((p, "git") in has || (p, "githook") in has || (p, "hook") in has || (p, "skill") in has || (p, "task") in has || (p, "workflow") in has) live[p] = 1
  }
  do {
    changed = 0
    for (e = 1; e <= ne; e++) if ((esrc[e] in live) && !(edst[e] in live)) { live[edst[e]] = 1; changed = 1 }
  } while (changed)
  for (i = 1; i <= np; i++) {
    p = paths[i]
    callers = ""
    for (k = 1; k <= nk; k++) if ((p, kinds[k]) in has) callers = callers (callers == "" ? "" : ",") kinds[k]
    if ((p, "git") in has || (p, "githook") in has || (p, "hook") in has) tier = "hook"
    else if ((p, "skill") in has) tier = "skill-called"
    else if ((p, "script") in has) tier = "library"
    else if ((p, "task") in has || (p, "workflow") in has) tier = "dev-check"
    else tier = "tests-only"
    # A function the script defines, one a script it calls defines (a sourced
    # library), or one a direct caller defines (a callback a sourced library
    # expects) runs in the shell rather than as a process.
    split("", seen); split("", local_fn)
    m = split(radj[p], nx, "\n")
    for (j = 1; j <= m; j++) {
      k = split(flist[nx[j]], fl, "\n")
      for (q = 1; q <= k; q++) if (fl[q] != "") local_fn[fl[q]] = 1
    }
    stack = p; seen[p] = 1
    while (stack != "") {
      r = stack; sub(/\n.*/, "", r)
      if (index(stack, "\n")) stack = substr(stack, index(stack, "\n") + 1); else stack = ""
      m = split(flist[r], fl, "\n")
      for (j = 1; j <= m; j++) if (fl[j] != "") local_fn[fl[j]] = 1
      m = split(adj[r], nx, "\n")
      for (j = 1; j <= m; j++) if (nx[j] != "" && !(nx[j] in seen)) { seen[nx[j]] = 1; stack = stack (stack == "" ? "" : "\n") nx[j] }
    }
    n = split(clist[p], words, "\n"); prof = ""
    for (j = 1; j <= n; j++) {
      x = words[j]
      if (x == "" || (x in builtin) || (x in byname) || (x in local_fn)) continue
      if (x !~ /^[A-Za-z0-9_][A-Za-z0-9_.+-]*$/) continue
      prof = prof "\n" x
    }
    # The path and the unresolved text are read from files; a control byte in
    # either never reaches the terminal.
    shown = p; gsub(/[[:cntrl:]]/, "?", shown)
    unresolved = sorted(ulist[p]); gsub(/[[:cntrl:]]/, "?", unresolved)
    print shown "\t" tier "\t" ((p in live) ? "-" : "no-live-caller") "\t" (callers == "" ? "-" : callers) "\t" ((p in mut) ? "shell-mutation" : "-") "\t" sorted(prof) "\t" unresolved
  }
}
' "$work/layer" "$work/facts" >"$work/rows" || fail_closed "could not assemble the partition"

printf 'path\ttier\tflag\tcallers\tmutation\tprofile\tunresolved\n'
sort "$work/rows"
