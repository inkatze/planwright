#!/bin/sh
# substrate-bakeoff.sh — the bake-off harness: measures every candidate in a
# bake-off directory against the same differential fixtures and writes one
# report row per candidate, plus a rendered comparison view of that report.
#
# The input layout, the report schema (every field, its unit and the classes
# that require it), the log formats and the validation rules are documented
# in docs/substrate-bakeoff-report.md. The schema is add-only.
#
# Usage: substrate-bakeoff.sh run --bakeoff <dir> --out-dir <dir> [--run-id <id>] [--platform <name>]
#        substrate-bakeoff.sh validate <report.tsv>
#        substrate-bakeoff.sh render <report.tsv>
# `run` writes <out-dir>/report.tsv and <out-dir>/view.md, validating the
# report before either lands. `validate` checks a report against the schema;
# `render` prints its view.
# Exit codes: 0 ok; 1 a refused candidate or an invalid report (each reason
# printed); 2 usage error; 5 fail-closed (an unreadable or malformed input,
# perl or Time::HiRes missing, or a failed step); 128 plus the signal number
# on HUP, INT or TERM.

# POSIX sh plus awk and perl (Time::HiRes, a core module) for timed
# execution. Inputs are data: configuration is parsed, never sourced, and a
# candidate runs only through the literal argv its configuration names.
set -uf

LC_ALL=C
export LC_ALL
unset CDPATH

me=substrate-bakeoff

usage() {
  printf '%s\n' "usage: substrate-bakeoff.sh run --bakeoff <dir> --out-dir <dir> [--run-id <id>] [--platform <name>]" \
    "       substrate-bakeoff.sh validate <report.tsv>" \
    "       substrate-bakeoff.sh render <report.tsv>" >&2
  exit 2
}

# Messages quote configuration values and file names, so control bytes are
# stripped before they reach the terminal.
say() {
  printf '%s\n' "$1" | tr -cd '[:print:]\n' >&2
}

fail_closed() {
  say "$me: $1; failing closed"
  exit 5
}

refuse() {
  say "$me: refused: $1"
  exit 1
}

TAB=$(printf '\t')

# The schema, in column order. New fields are appended, never inserted.
run_fields="schema run_id platform tier runs timeout_s fixture_set_count"
shared_fields="candidate class platform_result delivery_marketplace delivery_writer dependency_count dependency_listing"
primitive_fields="literal_path offline_replay tests_passed tests_failed fixtures_executed fixture_results latency_median_ms latency_spread_ms spawns_per_invocation distinct_commands source_bytes implementation_minutes review_runs review_findings review_findings_per_kib review_qualification porting_rate_min_per_kib baseline_run_id baseline_latency_median_ms baseline_latency_spread_ms hook_budget latency_status_mismatches"
comparison_fields="trivial_result cold_start_median_ms cold_start_spread_ms binary_size_bytes cold_start_status_mismatches"
all_fields="$run_fields $shared_fields $primitive_fields $comparison_fields"
baseline_fields="baseline_run_id baseline_latency_median_ms baseline_latency_spread_ms hook_budget"

# --- validate ---------------------------------------------------------------

validate_report() {
  [ -f "$1" ] && [ -r "$1" ] || fail_closed "the report $1 is missing or unreadable"
  BK_ALL=$all_fields BK_RUN=$run_fields BK_SHARED=$shared_fields BK_PRIM=$primitive_fields \
    BK_CMP=$comparison_fields BK_BASE=$baseline_fields BK_ME=$me \
    awk -F '\t' '
function clean(s) { gsub(/[^[:print:]]/, "", s); return s }
function bad(m) { print ENVIRON["BK_ME"] ": invalid report: " clean(m); err = 1 }
function num(s) { return s ~ /^[0-9]+(\.[0-9]+)?$/ }
BEGIN {
  na = split(ENVIRON["BK_ALL"], all, " ")
  split(ENVIRON["BK_RUN"], t, " "); for (i in t) isrun[t[i]] = 1
  split(ENVIRON["BK_SHARED"], t, " "); for (i in t) shared[t[i]] = 1
  split(ENVIRON["BK_PRIM"], t, " "); for (i in t) prim[t[i]] = 1
  split(ENVIRON["BK_CMP"], t, " "); for (i in t) cmp[t[i]] = 1
  split(ENVIRON["BK_BASE"], t, " "); for (i in t) base[t[i]] = 1
  split("runs timeout_s fixture_set_count dependency_count tests_passed tests_failed fixtures_executed latency_median_ms latency_spread_ms spawns_per_invocation distinct_commands source_bytes implementation_minutes review_runs review_findings review_findings_per_kib porting_rate_min_per_kib baseline_latency_median_ms baseline_latency_spread_ms cold_start_median_ms cold_start_spread_ms binary_size_bytes latency_status_mismatches cold_start_status_mismatches", t, " ")
  for (i in t) numeric[t[i]] = 1
  split("dependency_count tests_passed tests_failed fixtures_executed spawns_per_invocation distinct_commands source_bytes review_findings binary_size_bytes latency_status_mismatches cold_start_status_mismatches", t, " ")
  for (i in t) whole[t[i]] = 1
}
NR == 1 {
  nh = NF
  for (i = 1; i <= NF; i++) col[$i] = i
  for (i = 1; i <= na; i++) {
    if ($i != all[i]) { bad("header field " i " is \"" $i "\", the schema needs \"" all[i] "\" (the schema is add-only: a field is never renamed, removed or moved)"); hdrbad = 1; exit }
  }
  next
}
{
  rows++
  if (NF != nh) { bad("row " NR " has " NF " fields, the header " nh); next }
  for (i = 1; i <= na; i++) v[all[i]] = $i
  c = v["candidate"]
  if (v["schema"] != "substrate-bakeoff") bad(c ": schema is not substrate-bakeoff")
  if (v["tier"] !~ /^(hook|skill-called|library|dev-check)$/) bad(c ": tier is not hook, skill-called, library or dev-check")
  for (f in isrun) {
    if (v[f] == "-" || v[f] == "") bad(c ": run field " f " is empty")
    else if (f ~ /^(runs|timeout_s|fixture_set_count)$/ && v[f] !~ /^[1-9][0-9]*$/) bad(c ": run field " f " is not a whole number of at least one")
    if (rows == 1) first[f] = v[f]
    else if (v[f] != first[f]) bad(c ": run field " f " differs from the first row (one report is one run)")
  }
  if (c in seen) bad(c ": candidate appears twice")
  seen[c] = 1
  for (f in shared) if (v[f] == "-" || v[f] == "") bad(c ": the " v["class"] " class requires " f)
  for (f in numeric) if (v[f] != "-" && !num(v[f])) bad(c ": " f " is not a number: " v[f])
    else if (f in whole && v[f] != "-" && v[f] !~ /^[0-9]+$/) bad(c ": " f " is not a whole number: " v[f])
  if (v["class"] == "full") {
    nfull++
    for (f in prim) if (!(f in base) && (v[f] == "-" || v[f] == "")) bad(c ": the full class requires " f)
    if (v["fixtures_executed"] != v["fixture_set_count"]) bad(c ": the run executed " v["fixtures_executed"] " of the " v["fixture_set_count"] " production differential fixtures")
    nr = split(v["fixture_results"], fr, ",")
    if (v["fixture_results"] == "-") nr = 0
    if (nr != v["fixture_set_count"]) bad(c ": fixture_results records " nr " of the " v["fixture_set_count"] " production differential fixtures")
    split("", frseen); npass = 0
    for (k = 1; k <= nr; k++) {
      if (fr[k] !~ /^[A-Za-z0-9._-]+\/[A-Za-z0-9._-]+:(pass|fail)$/) { bad(c ": fixture_results entry \"" fr[k] "\" is not <primitive>/<case>:pass|fail"); continue }
      fx = fr[k]; sub(/:[a-z]+$/, "", fx)
      if (fx in frseen) bad(c ": fixture_results repeats " fx)
      frseen[fx] = 1
      if (fr[k] ~ /:pass$/) npass++
    }
    if (nr && npass != v["tests_passed"]) bad(c ": fixture_results records " npass " passing fixtures, tests_passed " v["tests_passed"])
    if (v["tests_passed"] + v["tests_failed"] != v["fixture_set_count"]) bad(c ": tests_passed plus tests_failed is not the production fixture count")
    if (v["review_runs"] !~ /^[1-9][0-9]*$/) bad(c ": review_runs is not a whole number of at least one")
    if (v["review_qualification"] != (v["review_runs"] == 1 ? "unqualified" : "qualified")) bad(c ": review_qualification must be unqualified for a single convergence run and qualified otherwise")
    if (v["literal_path"] !~ /^(yes|no)$/ || v["offline_replay"] !~ /^(yes|no)$/) bad(c ": literal_path and offline_replay are yes or no")
    fullrow[c] = NR; brun[c] = v["baseline_run_id"]; bmed[c] = v["baseline_latency_median_ms"]; bspr[c] = v["baseline_latency_spread_ms"]
    if (c == "shell") { hasshell = 1; smed = v["latency_median_ms"]; sspr = v["latency_spread_ms"] }
    if (v["hook_budget"] != "-" && v["hook_budget"] !~ /^(within|over)$/) bad(c ": hook_budget is within or over")
    budget[c] = v["hook_budget"]
    lat[c] = v["latency_median_ms"]
  } else if (v["class"] == "comparison") {
    for (f in prim) if (v[f] != "-") bad(c ": a comparison point carries the primitive field " f)
    for (f in cmp) if (v[f] == "-" || v[f] == "") bad(c ": the comparison class requires " f)
    if (v["trivial_result"] !~ /^(pass|fail)$/) bad(c ": trivial_result is pass or fail")
  } else bad(c ": class is \"" v["class"] "\", not full or comparison")
  for (f in shared) if (f ~ /^(platform_result|delivery_)/ && v[f] !~ /^(pass|fail)$/) bad(c ": " f " is pass or fail")
}
END {
  if (NR == 0) { bad("no header"); exit 1 }
  if (hdrbad) exit 1
  if (rows == 0) bad("no candidate row")
  for (c in fullrow) {
    if ((brun[c] == "-") != (budget[c] == "-") || (brun[c] == "-") != (bmed[c] == "-") || (brun[c] == "-") != (bspr[c] == "-")) bad(c ": hook_budget is set exactly when the shell latency columns are")
    else if (brun[c] != "-" && bmed[c] != "-" && bspr[c] != "-" && budget[c] != ((lat[c] + 0 <= bmed[c] + bspr[c]) ? "within" : "over")) bad(c ": hook_budget does not follow from its median and the shell baseline")
  }
  if (first["tier"] == "hook") {
    if (!hasshell) bad("a hook-tier report needs the shell candidate (id shell) as the latency baseline")
    for (c in fullrow) {
      if (brun[c] == "-" || bmed[c] == "-" || bspr[c] == "-" || budget[c] == "-") bad(c ": a hook-tier report needs the shell latency columns on every full candidate")
      else if (brun[c] != first["run_id"]) bad(c ": the shell latency columns carry run " brun[c] ", the candidate run " first["run_id"] "; both must come from one harness run")
      else if (hasshell && (bmed[c] != smed || bspr[c] != sspr)) bad(c ": the shell latency columns differ from the shell row")
    }
  }
  exit err ? 1 : 0
}' "$1"
}

# --- render -----------------------------------------------------------------

render_report() {
  BK_ME=$me awk -F '\t' '
# Code spans take the value raw: run ids and platforms are charset-checked.
function raw(s) { gsub(/[^A-Za-z0-9._:-]/, "", s); return s }
# A character loop, since awks disagree on backslashes in gsub replacements.
function cell(s,   o, i, ch) {
  gsub(/[^[:print:]]/, "", s)
  o = ""
  for (i = 1; i <= length(s); i++) {
    ch = substr(s, i, 1)
    if (ch == "&") ch = "&amp;"
    else if (ch == "<") ch = "&lt;"
    else if (ch == ">") ch = "&gt;"
    else if (index("\\`*_|[]", ch)) ch = "\\" ch
    o = o ch
  }
  return o
}
NR == 1 { for (i = 1; i <= NF; i++) h[i] = $i; nh = NF; next }
{
  n++
  for (i = 1; i <= nh; i++) { v[n, h[i]] = $i }
  if (v[n, "class"] == "full") full[++nf] = n; else cmpn[++nc] = n
}
END {
  printf "# Bake-off report: %s tier\n\n", cell(v[1, "tier"])
  printf "Run `%s` on `%s`: %s runs per latency measurement, a %s s timeout per execution, %s production differential fixtures.\n", raw(v[1, "run_id"]), raw(v[1, "platform"]), cell(v[1, "runs"]), cell(v[1, "timeout_s"]), cell(v[1, "fixture_set_count"])
  if (nf) {
    print "\n## Full candidates\n"
    print "| Candidate | Platform | Fixtures passed | Latency median ms | Spread ms | Hook budget | Spawns | Dependencies | Source bytes | Porting rate min/KiB | Review findings/KiB | Review runs |"
    print "| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |"
    for (k = 1; k <= nf; k++) { r = full[k]
      printf "| %s | %s | %s of %s | %s | %s | %s | %s | %s | %s | %s | %s | %s %s |\n", cell(v[r, "candidate"]), cell(v[r, "platform_result"]), cell(v[r, "tests_passed"]), cell(v[r, "fixture_set_count"]), cell(v[r, "latency_median_ms"]), cell(v[r, "latency_spread_ms"]), cell(v[r, "hook_budget"]), cell(v[r, "spawns_per_invocation"]), cell(v[r, "dependency_count"]), cell(v[r, "source_bytes"]), cell(v[r, "porting_rate_min_per_kib"]), cell(v[r, "review_findings_per_kib"]), cell(v[r, "review_runs"]), cell(v[r, "review_qualification"])
    }
  }
  if (nc) {
    print "\n## Comparison points\n"
    print "| Candidate | Platform | Trivial program | Cold start median ms | Spread ms | Binary bytes | Dependencies |"
    print "| --- | --- | --- | --- | --- | --- | --- |"
    for (k = 1; k <= nc; k++) { r = cmpn[k]
      printf "| %s | %s | %s | %s | %s | %s | %s |\n", cell(v[r, "candidate"]), cell(v[r, "platform_result"]), cell(v[r, "trivial_result"]), cell(v[r, "cold_start_median_ms"]), cell(v[r, "cold_start_spread_ms"]), cell(v[r, "binary_size_bytes"]), cell(v[r, "dependency_count"])
    }
  }
  print "\n## Every field"
  for (r = 1; r <= n; r++) {
    printf "\n### %s\n\n| Field | Value |\n| --- | --- |\n", cell(v[r, "candidate"])
    for (i = 1; i <= nh; i++) printf "| %s | %s |\n", cell(h[i]), cell(v[r, h[i]])
  }
}' "$1"
}

# --- run helpers ------------------------------------------------------------

# conf_get <file> <key>: print the value; exit 3 absent, 4 malformed or repeated.
conf_get() {
  BK_KEY=$2 awk '
BEGIN { k = ENVIRON["BK_KEY"] }
{ sub(/\r$/, "") }
/^[ \t]*#/ || /^[ \t]*$/ { next }
{
  i = index($0, "=")
  key = substr($0, 1, i - 1)
  if (i < 2 || key !~ /^[a-z][a-z0-9_.-]*$/) { bad = 1; exit }
  if (key in seen) { bad = 1; exit }
  seen[key] = 1
  if (key == k) { val = substr($0, i + 1); found = 1 }
}
END { if (bad) exit 4; if (!found) exit 3; print val }' "$1"
}

conf_keys() {
  awk '/^[ \t]*#/ || /^[ \t]*$/ { next } { i = index($0, "="); if (i > 1) print substr($0, 1, i - 1) }' "$1"
}

# need <file> <key> <what>: set val, or refuse naming what is missing.
need() {
  val=$(conf_get "$1" "$2")
  case $? in
    0) [ -n "$val" ] || refuse "$3: $2 is empty" ;;
    3) refuse "$3: $2 is not set" ;;
    *) fail_closed "$1 is malformed (a line without key=value, or a repeated key)" ;;
  esac
}

is_count() {
  case $1 in '' | *[!0-9]*) return 1 ;; esac
}

# plain_path <value> <what>: refuse anything but a relative path inside the
# candidate directory.
plain_path() {
  case $1 in
    /* | *..* | *[!A-Za-z0-9._/-]*) refuse "$cand: $2 must be a plain relative path inside the candidate directory" ;;
  esac
}

# The timed runner. Env: BK_TIMEOUT, BK_STDIN, BK_STDOUT, BK_WORK, BK_FILES,
# BK_REPEAT, BK_PATH, BK_SPAWN_LOG, BK_OFFLINE, BK_CLEAN_ENV; argv the command.
# Each repetition runs in a fresh directory under BK_WORK holding a copy of
# BK_FILES, with a fresh home (and, with BK_CLEAN_ENV, nothing inherited but
# PATH and the C locale), in its own process group, which is swept after the
# reap so nothing it backgrounded in that group outlives it. Prints `<status><TAB><ms>` per
# repetition, the status being the exit code, 128 plus the signal, or
# `timeout`. The clock spans fork to reap; staging is outside it.
# shellcheck disable=SC2016 # the $-sigils are perl variables
runner_pl='use strict; use warnings; use Time::HiRes qw(time); use File::Temp qw(tempdir);
my %bk = map { $_ => $ENV{$_} } grep { /^BK_/ } keys %ENV;
delete @ENV{ keys %bk };
%ENV = (LC_ALL => "C") if $bk{BK_CLEAN_ENV};
$ENV{PATH} = $bk{BK_PATH};
$ENV{PLANWRIGHT_BAKEOFF_SPAWN_LOG} = $bk{BK_SPAWN_LOG};
if ($bk{BK_OFFLINE}) {
  $ENV{$_} = "http://127.0.0.1:9" for qw(http_proxy https_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY all_proxy);
  $ENV{GOPROXY} = "off"; $ENV{GOFLAGS} = "-mod=vendor"; $ENV{CARGO_NET_OFFLINE} = "true";
}
my $pid = 0;
my %signum = (HUP => 1, INT => 2, TERM => 15);
for my $s (keys %signum) {
  $SIG{$s} = sub { if ($pid) { kill "KILL", -$pid; kill "KILL", $pid; waitpid($pid, 0); } POSIX::_exit(128 + $signum{$s}); };
}
for (1 .. ($bk{BK_REPEAT} || 1)) {
  my $cwd = tempdir("rep.XXXXXX", DIR => $bk{BK_WORK});
  $ENV{HOME} = $ENV{TMPDIR} = tempdir("home.XXXXXX", DIR => $bk{BK_WORK});
  if ($bk{BK_FILES} ne "") { system("cp", "-R", "--", "$bk{BK_FILES}/.", "$cwd/") == 0 or die "could not stage $bk{BK_FILES}\n"; }
  my $t0 = time;
  $pid = fork;
  die "fork: $!\n" unless defined $pid;
  if ($pid == 0) {
    setpgrp(0, 0);
    chdir $cwd or POSIX::_exit(127);
    open(STDIN, "<", $bk{BK_STDIN}) or POSIX::_exit(127);
    open(STDOUT, ">", $bk{BK_STDOUT}) or POSIX::_exit(127);
    open(STDERR, ">", "/dev/null") or POSIX::_exit(127);
    { no warnings "exec"; exec { $ARGV[0] } @ARGV; }
    POSIX::_exit(127);
  }
  my $timed_out = 0;
  my $ok = eval {
    local $SIG{ALRM} = sub { die "alarm\n" };
    alarm $bk{BK_TIMEOUT}; waitpid($pid, 0); alarm 0; 1;
  };
  unless ($ok) { $timed_out = 1; kill "KILL", -$pid; kill "KILL", $pid; waitpid($pid, 0); }
  my $st = $?;
  my $ms = (time - $t0) * 1000;
  kill "KILL", -$pid;
  $pid = 0;
  my $code = $timed_out ? "timeout" : ($st & 127) ? 128 + ($st & 127) : $st >> 8;
  printf "%s\t%.3f\n", $code, $ms;
}'

# run_case <argv-file> <fixture-dir|""> <extra-arg|""> <stdout> <repeat> <path>
# <spawn-log> <offline 0|1> <timings-out> <clean-env 0|1>: run the argv once
# per repetition, each with a fresh home and, when clean-env is 1, no
# inherited environment beyond PATH and the C locale.
run_case() {
  files=""
  [ -n "$2" ] && [ -d "$2/files" ] && files=$2/files
  stdin=/dev/null
  [ -n "$2" ] && [ -f "$2/stdin" ] && stdin=$2/stdin
  : >"$7"
  rc_out=$4 rep=$5 path=$6 slog=$7 offl=$8 timings=$9 clean=${10}
  # One argv word per line, so no word is re-split on blanks.
  old_ifs=$IFS
  IFS='
'
  # shellcheck disable=SC2046 # split on newlines only, globbing off
  set -- $(cat "$1") $([ -n "$2" ] && [ -f "$2/args" ] && cat "$2/args") $([ -n "$3" ] && printf '%s\n' "$3")
  IFS=$old_ifs
  BK_REPEAT=$rep BK_WORK=$work BK_FILES=$files BK_STDIN=$stdin BK_STDOUT=$rc_out BK_TIMEOUT=$timeout_s \
    BK_PATH=$path BK_SPAWN_LOG=$slog BK_OFFLINE=$offl BK_CLEAN_ENV=$clean \
    "$perl_bin" -MPOSIX -e "$runner_pl" "$@" >"$timings" &
  # Waited on rather than run in the foreground, so a signal to this shell
  # reaches its trap at once and the trap can stop the runner.
  runner_pid=$!
  wait "$runner_pid"
  runner_rc=$?
  runner_pid=""
  [ "$runner_rc" -eq 0 ] || fail_closed "the timed runner failed"
}

# The runner kills its execution's process group on TERM before it exits.
stop_runner() {
  [ -z "${runner_pid:-}" ] && return 0
  kill -s TERM "$runner_pid" 2>/dev/null
  wait "$runner_pid"
}

first_status() {
  awk -F '\t' 'NR == 1 { print $1 }' "$1"
}

# stats <timings>: median and interquartile range (nearest rank) of the times.
# mismatches <timings> <expected-status>: repetitions whose status differed.
mismatches() {
  BK_W=$2 awk -F '\t' '$1 != ENVIRON["BK_W"] { n++ } END { print n + 0 }' "$1" || fail_closed "could not read the timings"
}

stats() {
  cut -f2 "$1" >"$work/times" || fail_closed "could not read the timings"
  sort -n "$work/times" >"$work/times.sorted" || fail_closed "sort failed"
  awk '
{ v[++n] = $1 }
function q(p,   r) { r = int(p * n); if (r < p * n) r++; if (r < 1) r = 1; return v[r] }
END {
  if (n == 0) exit 1
  m = (n % 2) ? v[(n + 1) / 2] : (v[n / 2] + v[n / 2 + 1]) / 2
  printf "%.3f\t%.3f\n", m, q(0.75) - q(0.25)
}' "$work/times.sorted"
}

# build_argv <invocation>: write the argv file, words split on blanks, each
# word naming a file under the candidate directory made absolute. literal
# turns no unless the value is one word naming an executable file there.
build_argv() {
  argv_file=$work/argv
  : >"$argv_file"
  # shellcheck disable=SC2086 # the invocation is split into words on purpose
  set -- $1
  [ "$#" -ge 1 ] || refuse "$cand: an invocation is empty"
  [ "$#" -eq 1 ] || literal=no
  [ -f "$cdir/$1" ] && [ -x "$cdir/$1" ] || literal=no
  for w in "$@"; do
    plain_path "$w" "invocation word $w"
    if [ -f "$cdir/$w" ]; then
      printf '%s\n' "$cdir/$w" >>"$argv_file"
    else
      printf '%s\n' "$w" >>"$argv_file"
    fi
  done
}

utc_seconds() {
  # Seconds since the epoch of a YYYY-MM-DDTHH:MM:SSZ stamp; empty when malformed.
  printf '%s\n' "$1" | awk '
/^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z$/ {
  y = substr($0, 1, 4) + 0; m = substr($0, 6, 2) + 0; d = substr($0, 9, 2) + 0
  H = substr($0, 12, 2) + 0; M = substr($0, 15, 2) + 0; S = substr($0, 18, 2) + 0
  split("31 28 31 30 31 30 31 31 30 31 30 31", ml, " ")
  if (y % 4 == 0 && (y % 100 != 0 || y % 400 == 0)) ml[2] = 29
  if (m < 1 || m > 12 || d < 1 || d > ml[m] || H > 23 || M > 59 || S > 59) exit
  yy = (m <= 2) ? y - 1 : y; era = int(yy / 400); yoe = yy - era * 400
  doy = int((153 * (m + (m > 2 ? -3 : 9)) + 2) / 5) + d - 1
  doe = yoe * 365 + int(yoe / 4) - int(yoe / 100) + doy
  printf "%.0f\n", ((era * 146097 + doe - 719468) * 86400) + H * 3600 + M * 60 + S
}'
}

# Every command on PATH gets a logging shim, so a spawn found through PATH
# is counted; toolchains get failing shims for the offline replay.
build_shims() {
  shim_dir=$work/spawn-shims
  block_dir=$work/offline-block
  mkdir -p -- "$shim_dir" "$block_dir" || fail_closed "could not create the shim directories"
  old_ifs=$IFS
  IFS=:
  set +f
  for d in $orig_path; do
    case $d in /*) ;; *) continue ;; esac
    case $d in *"'"*) continue ;; esac
    for e in "$d"/*; do
      n=${e##*/}
      case $n in '' | *[!A-Za-z0-9._+-]*) continue ;; esac
      [ -e "$shim_dir/$n" ] && continue
      [ -f "$e" ] && [ -x "$e" ] || continue
      # shellcheck disable=SC2016 # the shim expands its own variables
      printf '#!/bin/sh\nprintf %%s\\\\n %s >>"$PLANWRIGHT_BAKEOFF_SPAWN_LOG"\nexec '"'"'%s'"'"' "$@"\n' "$n" "$e" >"$shim_dir/$n" \
        || fail_closed "could not write a spawn shim"
    done
  done
  set -f
  IFS=$old_ifs
  for n in cargo rustc rustup go gofmt zig bun node npm npx deno python python3 pip pip3; do
    printf '#!/bin/sh\nexit 127\n' >"$block_dir/$n" || fail_closed "could not write an offline-block shim"
  done
  find "$shim_dir" "$block_dir" -type f -exec chmod 755 {} + || fail_closed "could not mark the shims executable"
}

# deps <conf>: set dep_count and dep_listing.
deps() {
  need "$1" dependencies "$cand"
  dspec=$val
  if [ "$dspec" = spawned ]; then
    dep_count=$distinct
    dep_listing=$(awk '{ s = s (NR > 1 ? ";" : "") $0 ",system,-,-" } END { print (NR ? s : "none") }' "$work/commands") \
      || fail_closed "could not list the spawned commands"
    return
  fi
  plain_path "$dspec" dependencies
  [ -f "$cdir/$dspec" ] && [ -r "$cdir/$dspec" ] || refuse "$cand: the dependency listing $dspec is missing"
  out=$(awk -F '\t' '
/^#/ || /^[ \t]*$/ { next }
NF != 4 { bad = 1; exit }
{ for (i = 1; i <= 4; i++) if ($i == "" || $i ~ /[,;|]/ || $i ~ /[^[:print:]]/) { bad = 1; exit }
  n++; s = s (n > 1 ? ";" : "") $1 "," $2 "," $3 "," $4 }
END { if (bad) exit 1; printf "%d\t%s\n", n, (n ? s : "none") }' "$cdir/$dspec") \
    || refuse "$cand: the dependency listing needs four non-empty tab-separated fields per row (name, licence, last release, standard-library alternative) and no , ; or |"
  dep_count=${out%%"$TAB"*}
  dep_listing=${out#*"$TAB"}
}

# delivery <conf> <mode>: set dres to pass or fail.
delivery() {
  need "$1" "delivery.$2" "$cand"
  plain_path "$val" "delivery.$2"
  [ -f "$cdir/$val" ] || refuse "$cand: delivery.$2 names a missing file"
  printf '%s\n' "$cdir/$val" >"$work/dargv"
  run_case "$work/dargv" "" "" "$work/dout" 1 "$orig_path" "$work/dlog" 0 "$work/dt" 0
  dres=fail
  [ "$(first_status "$work/dt")" = 0 ] && dres=pass
}

# build_step <conf>: run the optional build script; fail when it fails.
build_step() {
  bscript=$(conf_get "$1" build)
  case $? in
    3) return 0 ;;
    0) ;;
    *) fail_closed "$1 is malformed" ;;
  esac
  [ -n "$bscript" ] || refuse "$cand: build is empty"
  plain_path "$bscript" build
  printf '%s\n' "$cdir/$bscript" >"$work/bargv"
  run_case "$work/bargv" "" "" "$work/bout" 1 "$orig_path" "$work/blog" 0 "$work/bt" 0
  [ "$(first_status "$work/bt")" = 0 ]
}

# field <name> <value>: queue one field of the row being assembled.
field() {
  printf '%s\t%s\n' "$1" "$2" >>"$work/fields"
}

emit_row() {
  field schema substrate-bakeoff
  field run_id "$run_id"
  field platform "$platform"
  field tier "$tier"
  field runs "$runs"
  field timeout_s "$timeout_s"
  field fixture_set_count "$fixture_count"
  BK_ALL=$all_fields awk -F '\t' '
{ v[$1] = $2 }
END {
  n = split(ENVIRON["BK_ALL"], all, " ")
  for (i = 1; i <= n; i++) printf "%s%s", (i > 1 ? "\t" : ""), ((all[i] in v) ? v[all[i]] : "-")
  printf "\n"
}' "$work/fields" >>"$work/rows" || fail_closed "could not assemble a row"
  : >"$work/fields"
}

measure_full() {
  conf=$cdir/candidate.conf
  literal=yes
  launch_ok=yes
  build_step "$conf" || launch_ok=no
  for k in $(conf_keys "$conf"); do
    case $k in invoke.*) grep -Fqx -- "${k#invoke.}" "$work/primitives" || refuse "$cand: $k names no primitive of the fixture set" ;; esac
  done
  : >"$work/results"
  : >"$work/commands.raw"
  passed=0 failed=0 executed=0 spawns=""
  while IFS= read -r fx; do
    need "$conf" "invoke.${fx%%/*}" "$cand (a full candidate implements every primitive the fixture set holds, so its run executes every production differential fixture)"
    inv=$val
    build_argv "$inv"
    run_case "$argv_file" "$bakeoff/fixtures/$fx" "" "$work/out" 1 "$shim_dir:$orig_path" "$work/slog" 0 "$work/t" 1
    executed=$((executed + 1))
    st=$(first_status "$work/t")
    want=$(cat "$bakeoff/fixtures/$fx/expected-status")
    case $st in 126 | 127) [ "$want" = "$st" ] || launch_ok=no ;; esac
    if [ "$st" = "$want" ] && cmp -s "$work/out" "$bakeoff/fixtures/$fx/expected-stdout"; then
      passed=$((passed + 1))
      printf '%s:pass\n' "$fx" >>"$work/results"
    else
      failed=$((failed + 1))
      printf '%s:fail\n' "$fx" >>"$work/results"
    fi
    cat "$work/slog" >>"$work/commands.raw" || fail_closed "could not read a spawn log"
    if [ "$fx" = "$call_site" ]; then
      spawns=$(awk 'END { print NR }' "$work/slog")
      cp "$work/out" "$work/call-out" || fail_closed "could not keep the call-site output"
      call_status=$st
      call_inv=$inv
    fi
  done <"$work/fixtures"
  sort -u "$work/commands.raw" >"$work/commands" || fail_closed "sort failed"
  distinct=$(awk 'END { print NR }' "$work/commands")
  results=$(awk '{ s = s (NR > 1 ? "," : "") $0 } END { print s }' "$work/results")

  build_argv "$call_inv"
  run_case "$argv_file" "$bakeoff/fixtures/$call_site" "" "$work/out" "$runs" "$orig_path" "$work/slog" 0 "$work/t" 1
  lat=$(stats "$work/t") || fail_closed "the latency measurement failed"
  lat_mismatch=$(mismatches "$work/t" "$(cat "$bakeoff/fixtures/$call_site/expected-status")")

  run_case "$argv_file" "$bakeoff/fixtures/$call_site" "" "$work/replay" 1 "$block_dir:$orig_path" "$work/slog" 1 "$work/t" 1
  offline=no
  [ "$(first_status "$work/t")" = "$call_status" ] && cmp -s "$work/replay" "$work/call-out" && offline=yes

  need "$conf" sources "$cand"
  src_bytes=0
  # shellcheck disable=SC2086 # sources is a blank-separated list of plain paths
  set -- $val
  for s in "$@"; do
    plain_path "$s" "source $s"
    [ -f "$cdir/$s" ] || refuse "$cand: source $s is missing"
    b=$(wc -c <"$cdir/$s") || fail_closed "could not size $s"
    src_bytes=$((src_bytes + b))
  done
  [ "$src_bytes" -gt 0 ] || refuse "$cand: its sources are empty"

  impl=$(BK_C=$cand awk -F '\t' '$1 == ENVIRON["BK_C"] { n++; d = $2; g = $3 } END { if (n == 1) print d "\t" g; else if (n > 1) print "dup" }' "$bakeoff/implementation-time.tsv")
  [ -n "$impl" ] || refuse "$cand: implementation-time.tsv has no row for it (the log is required per full candidate)"
  [ "$impl" != dup ] || refuse "$cand: implementation-time.tsv has more than one row for it"
  t0=$(utc_seconds "${impl%"$TAB"*}")
  t1=$(utc_seconds "${impl#*"$TAB"}")
  [ -n "$t0" ] && [ -n "$t1" ] || refuse "$cand: implementation-time.tsv stamps are not YYYY-MM-DDTHH:MM:SSZ calendar times"
  [ "$t1" -ge "$t0" ] || refuse "$cand: its first green run precedes its dispatch"

  rev=$(BK_C=$cand BK_N=$review_runs awk -F '\t' '
$1 == ENVIRON["BK_C"] {
  if ($2 !~ /^[1-9][0-9]*$/ || $3 !~ /^[0-9]+$/ || $2 > ENVIRON["BK_N"] + 0 || ($2 in seen)) { bad = 1; exit }
  seen[$2] = 1; n++; t += $3
}
END { if (bad || n != ENVIRON["BK_N"] + 0) exit 1; print t }' "$bakeoff/review-findings.tsv") \
    || refuse "$cand: review-findings.tsv needs exactly one row per convergence run 1 to $review_runs, each with a whole findings count"
  qual=qualified
  [ "$review_runs" -eq 1 ] && qual=unqualified
  derived=$(awk -v s="$t1" -v d="$t0" -v b="$src_bytes" -v f="$rev" -v n="$review_runs" 'BEGIN {
    m = (s - d) / 60; k = b / 1024
    printf "%.1f %.3f %.3f\n", m, f / n / k, m / k }')
  # shellcheck disable=SC2086 # three blank-separated numbers
  set -- $derived

  deps "$conf"
  delivery "$conf" marketplace
  field delivery_marketplace "$dres"
  delivery "$conf" writer
  field delivery_writer "$dres"
  platform_result=pass
  [ "$launch_ok" = yes ] || platform_result=fail

  field candidate "$cand"
  field class full
  field platform_result "$platform_result"
  field dependency_count "$dep_count"
  field dependency_listing "$dep_listing"
  field literal_path "$literal"
  field offline_replay "$offline"
  field tests_passed "$passed"
  field tests_failed "$failed"
  field fixtures_executed "$executed"
  field fixture_results "$results"
  field latency_median_ms "${lat%"$TAB"*}"
  field latency_spread_ms "${lat#*"$TAB"}"
  field spawns_per_invocation "$spawns"
  field distinct_commands "$distinct"
  field source_bytes "$src_bytes"
  field implementation_minutes "$1"
  field review_runs "$review_runs"
  field review_findings "$rev"
  field review_findings_per_kib "$2"
  field review_qualification "$qual"
  field porting_rate_min_per_kib "$3"
  field latency_status_mismatches "$lat_mismatch"
  emit_row
}

measure_comparison() {
  conf=$cdir/candidate.conf
  for k in $(conf_keys "$conf"); do
    case $k in invoke.trivial) ;; invoke.*) refuse "$cand: a comparison point never implements a primitive, yet it declares $k" ;; esac
  done
  launch_ok=yes
  literal=yes
  build_step "$conf" || launch_ok=no
  need "$conf" invoke.trivial "$cand"
  build_argv "$val"
  run_case "$argv_file" "" world "$work/out" 1 "$shim_dir:$orig_path" "$work/slog" 0 "$work/t" 1
  st=$(first_status "$work/t")
  case $st in 126 | 127) launch_ok=no ;; esac
  sort -u "$work/slog" >"$work/commands" || fail_closed "sort failed"
  distinct=$(awk 'END { print NR }' "$work/commands")
  trivial=fail
  printf 'hello world\n' >"$work/trivial-expected"
  [ "$st" = 0 ] && cmp -s "$work/out" "$work/trivial-expected" && trivial=pass
  run_case "$argv_file" "" world "$work/out" "$runs" "$orig_path" "$work/slog" 0 "$work/t" 1
  cold=$(stats "$work/t") || fail_closed "the cold-start measurement failed"
  cold_mismatch=$(mismatches "$work/t" 0)
  need "$conf" artifact "$cand"
  plain_path "$val" artifact
  [ -f "$cdir/$val" ] || refuse "$cand: artifact $val is missing"
  size=$(wc -c <"$cdir/$val") || fail_closed "could not size the artifact"

  deps "$conf"
  delivery "$conf" marketplace
  field delivery_marketplace "$dres"
  delivery "$conf" writer
  field delivery_writer "$dres"
  platform_result=pass
  [ "$launch_ok" = yes ] || platform_result=fail

  field candidate "$cand"
  field class comparison
  field platform_result "$platform_result"
  field dependency_count "$dep_count"
  field dependency_listing "$dep_listing"
  field trivial_result "$trivial"
  field cold_start_median_ms "${cold%"$TAB"*}"
  field cold_start_spread_ms "${cold#*"$TAB"}"
  field cold_start_status_mismatches "$cold_mismatch"
  field binary_size_bytes "$((size + 0))"
  emit_row
}

# Fill the shell baseline columns of every full row from the shell row of
# this same run, and judge each against the hook-tier budget: no regression
# beyond the shell's own spread.
fill_baseline() {
  BK_RUN=$run_id awk -F '\t' -v OFS='\t' '
NR == 1 { for (i = 1; i <= NF; i++) c[$i] = i; print; next }
{ r[++n] = $0 }
$c["candidate"] == "shell" && $c["class"] == "full" { m = $c["latency_median_ms"]; s = $c["latency_spread_ms"]; have = 1 }
END {
  for (k = 1; k <= n; k++) {
    $0 = r[k]
    if (have && $c["class"] == "full") {
      $c["baseline_run_id"] = ENVIRON["BK_RUN"]
      $c["baseline_latency_median_ms"] = m
      $c["baseline_latency_spread_ms"] = s
      $c["hook_budget"] = ($c["latency_median_ms"] + 0 <= m + s) ? "within" : "over"
    }
    print
  }
}' "$1" >"$1.filled" || fail_closed "could not fill the baseline columns"
  mv -- "$1.filled" "$1" || fail_closed "could not fill the baseline columns"
}

cmd_run() {
  bakeoff="" out_dir="" run_id="" platform=""
  while [ "$#" -gt 0 ]; do
    case $1 in
      --bakeoff | --out-dir | --run-id | --platform)
        [ "$#" -ge 2 ] && [ -n "$2" ] || usage
        case $1 in
          --bakeoff) bakeoff=$2 ;;
          --out-dir) out_dir=$2 ;;
          --run-id) run_id=$2 ;;
          --platform) platform=$2 ;;
        esac
        shift 2
        ;;
      *) usage ;;
    esac
  done
  [ -n "$bakeoff" ] && [ -n "$out_dir" ] || usage
  case $run_id in *[!A-Za-z0-9._:-]*) refuse "--run-id carries a character outside [A-Za-z0-9._:-]" ;; esac
  case $platform in *[!A-Za-z0-9._-]*) refuse "--platform carries a character outside [A-Za-z0-9._-]" ;; esac
  perl_bin=$(command -v perl) || fail_closed "perl is not on PATH"
  "$perl_bin" -MTime::HiRes -MPOSIX -e 1 >/dev/null 2>&1 || fail_closed "perl lacks Time::HiRes or POSIX"
  bakeoff=$(cd "$bakeoff" 2>/dev/null && pwd -P) || fail_closed "the bake-off directory is missing"
  [ -d "$out_dir" ] || fail_closed "the output directory $out_dir does not exist"
  bconf=$bakeoff/bakeoff.conf
  [ -f "$bconf" ] && [ -r "$bconf" ] || fail_closed "bakeoff.conf is missing or unreadable"
  for f in implementation-time.tsv review-findings.tsv; do
    [ -f "$bakeoff/$f" ] && [ -r "$bakeoff/$f" ] || fail_closed "the bake-off log $f is missing or unreadable"
  done
  cand=bakeoff.conf
  need "$bconf" tier bakeoff.conf
  tier=$val
  case $tier in hook | skill-called | library | dev-check) ;; *) refuse "bakeoff.conf: tier $tier is not hook, skill-called, library or dev-check" ;; esac
  need "$bconf" runs bakeoff.conf
  runs=$val
  need "$bconf" timeout_s bakeoff.conf
  timeout_s=$val
  need "$bconf" review_runs bakeoff.conf
  review_runs=$val
  need "$bconf" call_site bakeoff.conf
  call_site=$val
  for n in "$runs" "$timeout_s" "$review_runs"; do
    is_count "$n" && [ "$n" -ge 1 ] || refuse "bakeoff.conf: runs, timeout_s and review_runs are whole numbers of at least one"
  done

  work=$(mktemp -d "${TMPDIR:-/tmp}/substrate-bakeoff.XXXXXX") || fail_closed "mktemp -d failed"
  [ -n "$work" ] && [ -d "$work" ] || fail_closed "mktemp -d produced no directory"
  rt="" vt="" runner_pid=""
  trap 'rm -rf "$work"; [ -z "$rt" ] || rm -f -- "$rt" "$vt"' EXIT
  trap 'stop_runner; exit 129' HUP
  trap 'stop_runner; exit 130' INT
  trap 'stop_runner; exit 143' TERM
  : >"$work/fields"

  [ -d "$bakeoff/fixtures" ] || fail_closed "the bake-off has no fixtures directory"
  : >"$work/fixtures"
  set +f
  for d in "$bakeoff"/fixtures/*/*/; do
    set -f
    [ -d "$d" ] || continue
    d=${d%/}
    c=${d##*/}
    p=${d%/*}
    p=${p##*/}
    case $p/$c in *[!A-Za-z0-9._/-]*) fail_closed "fixture $p/$c has a name outside [A-Za-z0-9._-]" ;; esac
    [ -f "$d/expected-stdout" ] && [ -f "$d/expected-status" ] || fail_closed "fixture $p/$c lacks expected-stdout or expected-status"
    if [ -f "$d/args" ] && grep -q '^$' "$d/args"; then
      fail_closed "fixture $p/$c: args has an empty line (one argument per line, and an empty argument cannot be passed)"
    fi
    case $(cat "$d/expected-status") in 0 | [1-9] | [1-9][0-9] | 1[0-9][0-9] | 2[0-4][0-9] | 25[0-5]) ;; *) fail_closed "fixture $p/$c: expected-status is not an exit status (0 to 255, no leading zero)" ;; esac
    printf '%s\n' "$p/$c" >>"$work/fixtures"
    set +f
  done
  set -f
  sort -o "$work/fixtures" "$work/fixtures" || fail_closed "sort failed"
  fixture_count=$(awk 'END { print NR }' "$work/fixtures")
  [ "$fixture_count" -gt 0 ] || fail_closed "the production differential fixture set is empty"
  case $call_site in */*/* | /* | */ | *[!A-Za-z0-9._/-]*) refuse "bakeoff.conf: call_site is not <primitive>/<case>" ;; esac
  grep -Fqx -- "$call_site" "$work/fixtures" || refuse "bakeoff.conf: call_site $call_site names no fixture"
  cut -d/ -f1 "$work/fixtures" | sort -u >"$work/primitives" || fail_closed "could not list the primitives"

  [ -n "$run_id" ] || run_id=$(date -u +%Y%m%dT%H%M%SZ)-$$
  if [ -z "$platform" ]; then
    platform=$(uname -s | tr 'ABCDEFGHIJKLMNOPQRSTUVWXYZ' 'abcdefghijklmnopqrstuvwxyz')
    [ -f /etc/alpine-release ] && platform=alpine
    platform=$platform-$(uname -m)
  fi
  orig_path=$PATH
  build_shims

  printf '%s\n' "$all_fields" | tr ' ' '\t' >"$work/rows"
  set +f
  for cdir in "$bakeoff"/candidates/*/; do
    set -f
    [ -d "$cdir" ] || continue
    cdir=${cdir%/}
    cand=${cdir##*/}
    case $cand in [a-z0-9]*) ;; *) fail_closed "candidate directory $cand does not start with [a-z0-9]" ;; esac
    case $cand in *[!a-z0-9-]*) fail_closed "candidate directory $cand has a name outside [a-z0-9-]" ;; esac
    [ -f "$cdir/candidate.conf" ] || fail_closed "candidate $cand has no candidate.conf"
    for k in $(conf_keys "$cdir/candidate.conf"); do
      case $k in class | invoke.* | sources | artifact | dependencies | delivery.marketplace | delivery.writer | build) ;; *) refuse "$cand: $k is not a candidate.conf key" ;; esac
    done
    need "$cdir/candidate.conf" class "$cand"
    case $val in
      full) measure_full ;;
      comparison) measure_comparison ;;
      *) refuse "$cand: class $val is not full or comparison" ;;
    esac
    set +f
  done
  set -f
  [ "$(awk 'END { print NR }' "$work/rows")" -gt 1 ] || fail_closed "the bake-off has no candidate"
  fill_baseline "$work/rows"
  validate_report "$work/rows" >&2 || exit 1
  render_report "$work/rows" >"$work/view.md" || fail_closed "could not render the view"
  for f in report.tsv view.md; do
    if [ -e "$out_dir/$f" ] || [ -L "$out_dir/$f" ]; then
      [ -f "$out_dir/$f" ] && [ ! -L "$out_dir/$f" ] || fail_closed "$out_dir/$f is not a regular file"
    fi
  done
  # Both files are staged before either lands, so a failure in staging leaves
  # the old pair; only a failed second move can leave a new report beside an
  # old view.
  rt=$(mktemp "$out_dir/.report.XXXXXX") || fail_closed "could not stage the output in $out_dir"
  vt=$(mktemp "$out_dir/.view.XXXXXX") || fail_closed "could not stage the output in $out_dir"
  if ! cp "$work/rows" "$rt" || ! cp "$work/view.md" "$vt" || ! chmod 644 "$rt" "$vt" \
    || ! mv -- "$rt" "$out_dir/report.tsv" || ! mv -- "$vt" "$out_dir/view.md"; then
    fail_closed "could not write the report into $out_dir"
  fi
  printf '%s\n' "$me: run $run_id on $platform: report $out_dir/report.tsv, view $out_dir/view.md"
}

[ "$#" -ge 1 ] || usage
sub=$1
shift
case $sub in
  run) cmd_run "$@" ;;
  validate)
    [ "$#" -eq 1 ] || usage
    validate_report "$1"
    ;;
  render)
    [ "$#" -eq 1 ] || usage
    validate_report "$1" >&2 || exit 1
    render_report "$1"
    ;;
  *) usage ;;
esac
