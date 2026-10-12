#!/bin/sh
# step-record.sh — write, list, look up, and render custom-steps records,
# fingerprint declared paths, and regenerate the pending-sign-off checklist
# (custom-steps Tasks 4 and 13; REQ-D1.5, REQ-D1.10, REQ-D1.12, REQ-E1.2,
# REQ-E1.6, REQ-H1.3, REQ-I1.5, REQ-I1.7–I1.10, REQ-J1.1, REQ-J1.2; D-12, D-16,
# D-25–D-27, D-31, D-32).
# doctrine/custom-steps.md (*Records*) is the normative home of what a record
# holds and where it folds; doctrine/gate-wiring.md owns the checklist format.
# This header pins what those docs delegate here: the verbs, the storage
# layout, the excerpt bound, the screen action, and the rendered shapes.
#
# Usage:
#   step-record.sh [--worktree <dir>] new-run
#   step-record.sh [--worktree <dir>] write --run <id> --point <point>
#       --step <id> --kind <kind> --target <target> --hosting <hosting>
#       --backend <name> [--head <sha>] [--end-head <sha>] --start <ts>
#       [--end <ts>] --outcome <outcome> [--session <id>]
#       [--excerpt-file <file>] [--output <path>] [--skip-code <code>]
#       [--skip-reason <text>] [--stands-on <run>:<point>:<seq>]
#       [--pool <pool> --wait <seconds> [--holder <text>]... [--unpooled]]
#       [--fingerprint <fp> --args-digest <digest>] [--refire-of <point>]
#   step-record.sh [--worktree <dir>] write --completion --run <id>
#       --point <point> [--head <sha>] [--warning <text>]...
#   step-record.sh [--worktree <dir>] write --full-suite --run <id>
#       --pool <pool> --wait <seconds> --wait-outcome <outcome>
#       [--holder <text>]... --start <ts> [--end <ts>]
#   step-record.sh [--worktree <dir>] list [--run <id>] [--point <point>]
#   step-record.sh [--worktree <dir>] render [--run <id>] [--point <point>]...
#   step-record.sh [--worktree <dir>] regenerate --base <rev> --head <rev>
#       [--run <id>] [--checklist-only]
#   step-record.sh [--worktree <dir>] status --point <flip-point>
#       [--head <sha>] --repo <owner>/<name>
#   step-record.sh [--worktree <dir>] fingerprint --paths <words>
#   step-record.sh [--worktree <dir>] lookup reuse --step <id>
#       --target <target> --args-digest <digest> --fingerprint <fp>
#   step-record.sh [--worktree <dir>] lookup resume --run <id>
#       --point <point> [--head <sha>]
#   step-record.sh args-digest <args>
#   step-record.sh excerpt <file>
#
#   --worktree    the unit's worktree; default the enclosing git top level.
#                 The cache is <worktree>/.claude/steps/, created mode 0700;
#                 a cache, run directory, or record that is a symlink is
#                 refused, as is one that cannot be read, and a cache git
#                 tracks.
#   new-run       issue the next run id (six digits, zero-padded, one past
#                 the highest in the cache) and print it; a run whose id
#                 cannot be printed is removed again. A run is one unit
#                 run or flip attempt; run ids order attempts, the latest
#                 run being the highest id whether or not it holds a record.
#   write         validate every field, then write one record and print its
#                 absolute path (the value a later step's
#                 PLANWRIGHT_STEP_PREV_RECORD carries). --completion writes
#                 the point-completion record instead; --warning repeats.
#                 --full-suite writes a full-suite record instead: one full
#                 local suite attempt's pool wait, tied to no point (it
#                 neither needs nor claims a completion). A re-fire record
#                 (--refire-of) is a post-pr step record, so it lands before
#                 post-pr's completion. A point fires once per run: its
#                 completion is claimed atomically, and a step or completion
#                 record for a point the run already completed is refused. A repeated write is a
#                 second record; retrying is the caller's call. A write that
#                 fails before its record exists leaves nothing claimed,
#                 short of an uncatchable kill, which leaves the cache lock
#                 for the next writer to break once the killed process is
#                 gone; an exit 1 after the record exists (a failed print)
#                 leaves the record in place. A reader running while writers
#                 are in flight may miss a record that lands during its read.
#                 --excerpt-file resolves against the caller's directory.
#   list          print every record of the run (every run when --run is
#                 absent), oldest first, optionally one point's only: a
#                 `record<TAB><worktree-relative path>` line, the record's
#                 stored lines with C0 control bytes and DEL dropped, then a
#                 blank line.
#   render        print one markdown table per point of the run (default the
#                 latest run), in the order the points first recorded, or
#                 the named points in the order given, each once; a named
#                 point with no record renders nothing. Given no point, the
#                 run's full-suite records follow as one full-suite table.
#   regenerate    print the pending-sign-off checklist rebuilt from the
#                 marked commits of <base>..<head>, then, unless
#                 --checklist-only, when the run (default the latest run)
#                 renders anything, a blank line and that render. <base> is
#                 the PR base branch's current tip, so commits a merge from
#                 the base brought in are reachable from it and never enter
#                 the range.
#   status        post a flip point's commit status on --head (default the
#                 worktree's HEAD, as under the field grammar) in --repo, the
#                 base repository the PR targets, and print
#                 `posted<TAB><context><TAB><state><TAB><head>`. The point is
#                 pre-ready-flip or pre-spec-ready-flip, the context
#                 `planwright/<point>`. The latest attempt is the highest run
#                 holding a well-formed completion record of that point
#                 naming --head; a
#                 head with none is refused (exit 1) with no post. The state
#                 is `failure` when any of that run's step records at the
#                 point is halted, failed, or limited, whatever head it
#                 started on, or when an unretired limited record ends on
#                 --head: a limited step record, of any run and point, whose
#                 end head is --head, retired once a higher run holds a
#                 passed, applied, or `resume`-skipped record of the same
#                 step id ending there. Records are read as lookup reads
#                 them, a run's order taken from its directory: a malformed
#                 record retires nothing and, recording limited (or, in the
#                 attempt, anything; or any outcome but passed, applied,
#                 skipped, or limited), counts against the flip, as does a
#                 malformed completion of the point in a run above the
#                 attempt (`a later completion record is malformed`). Otherwise
#                 `success` (an empty list included). The description is
#                 `<point>: no step halted or failed (run <id>)`, or in its
#                 place `a step halted or
#                 failed`, or else `a step stayed limited`; the status
#                 carries no target URL, excerpt, or path. The post is
#                 `gh api --method POST repos/<repo>/statuses/<head>`; a
#                 later post on the same head and context replaces the
#                 earlier one. A failed post exits 1 naming the repository
#                 and the permission the login needs; an exit 1 after the
#                 post (a failed print) leaves the status in place.
#   fingerprint   print the fingerprint of the declared path words (one
#                 argument, words split on spaces, in the --paths grammar
#                 below) at the worktree's HEAD, or `none` when a tracked file
#                 under a word differs from HEAD (staged or not), an
#                 untracked file git does not ignore lies under one, a file
#                 under one is marked skip-worktree or assume-unchanged, a
#                 submodule under one has changes (whatever its ignore
#                 setting), a word reaches through a symbolic link, or a
#                 word absent at HEAD names a path present here that is not
#                 ignored, or any present path on a case-insensitive checkout
#                 (a spelling the file system may fold). The fingerprint is
#                 git's object id (`git hash-object`) of one
#                 `<word><TAB><object id>` line per word in the order given,
#                 the object id the word's blob or tree at HEAD (read with
#                 empty and `.` segments dropped, `.` alone the root tree) or
#                 `-` for a path absent there; nothing is written to the
#                 object store. Git runs with the variables that would point
#                 it elsewhere cleared and literal pathspecs. A worktree with
#                 no commit, or a git read that fails, exits 1.
#   lookup        print the records a step would stand on, one line each,
#                 `record<TAB><run>:<point>:<seq><TAB><step><TAB><head>
#                 <TAB><end head><TAB><hosting><TAB><session><TAB><path>`
#                 (the second field the --stands-on value, the path
#                 worktree-relative), or exit 3 when none qualifies. A record
#                 is read as untrusted: its run, sequence, point, and kind come
#                 from its path, and it qualifies only when its stored run,
#                 seq, point, and type agree, no single-valued key repeats, and its step
#                 id, both heads, hosting, and session meet the write grammar,
#                 so a record with no end head (one written before end
#                 heads) or a withheld value never qualifies. `reuse` prints
#                 the newest step record of any run and point, re-fires
#                 included, that is passed and carries the same step id,
#                 target (as write stores it, so one the screen withheld
#                 matches nothing), args digest, and fingerprint;
#                 --fingerprint none matches nothing. `resume`
#                 reads the named run's step records at --point (one of the
#                 in-run points pre-implementation, pre-ci, convergence,
#                 pre-pr, post-pr) in write order and prints the leading
#                 prefix that are passed or applied with their end head on
#                 --head (default the worktree's HEAD); a `resume` skip there
#                 ending on --head stands for the record it names, which is
#                 printed in its place when it is a passed or applied record
#                 of the same step id ending on --head, so chained resumes
#                 print the same records. The first record that does not
#                 qualify ends the prefix. --run and --point are validated
#                 before any record is read. A record that cannot be read
#                 exits 1; a resume skip naming a record that does not exist
#                 ends the prefix, as any record that does not qualify does.
#   args-digest   print the SHA-256 of <args> exactly as given (no newline
#                 added), the --args-digest value; no worktree is read; a
#                 failed print exits 1.
#   excerpt       print <file> as write would store it as a record excerpt
#                 (cleaned, screened, and bounded, or its placeholder line),
#                 with no record cache or work tree involved; the excerpt a
#                 caller outside the runner (scripts/classify-limit.sh)
#                 carries. A missing or unreadable file exits 2.
#
# Field grammar (write refuses a violation with exit 2, naming the field and
# never echoing its value; no value is ever interpolated before it passes):
#   --run          an issued run id: six digits naming an existing run dir
#   --point        a name from doctrine/custom-steps.md's vocabulary; a point
#                  the run already completed is refused, also with exit 2
#   --step         ^[a-z][a-z0-9-]*$, at most 64 bytes, never `implementation`
#   --kind         skill | command | prompt
#   --hosting      isolated | continue | in-session
#   --backend      ^[a-z0-9][a-z0-9-]*$, at most 64 bytes (the backend
#                  identifier charset)
#   --session      [A-Za-z0-9._:-], 1 to 128 bytes; optional
#   --head         a full commit id: 40 or 64 lowercase hex digits; omitted
#                  (write and status), the worktree's HEAD commit when the
#                  verb runs, refused when it has none. Given, even empty, it
#                  is never defaulted. A step record holds the head its step
#                  started on, so a step that may commit passes that head;
#                  the default fits a completion, status, and a step that
#                  leaves HEAD where it found it.
#   --end-head     a full commit id, the head at the step's end; omitted, the
#                  worktree's HEAD commit when the record is written, given
#                  (even empty) never defaulted, as --head. A step record
#                  only; a completion's --head is already its end.
#   --start/--end  YYYY-MM-DDTHH:MM:SSZ; an omitted write --end is the UTC
#                  time the record is written; --end is refused if earlier
#                  than --start
#   --outcome      passed | applied | halted | failed | skipped | limited
#   --skip-code    missing | reuse | resume | answered; a skipped record
#                  carries exactly one, and only a skipped record carries one
#   --skip-reason  free-text detail of a skip; optional, skipped only
#   --stands-on    <run>:<point>:<seq>, naming a step record of the cache
#                  that the skip can stand on (the same step id, passed for
#                  `reuse`, passed or applied and ending on this record's end
#                  head for `resume`, read as lookup reads records): required
#                  for a `reuse` or `resume` skip, refused on every other
#                  record
#   --pool         a pool name, ^[a-z][a-z0-9-]*$, at most 64 bytes; with it
#                  --wait (whole seconds, at most nine digits) is required,
#                  and --wait, --holder (repeats), and --unpooled (a flag)
#                  are refused without it
#   --fingerprint  `none` or the fingerprint verb's output (40 or 64
#                  lowercase hex digits, the id of an object git does not
#                  store); it and --args-digest (64 lowercase hex digits)
#                  come together or not at all
#   --refire-of    pre-ci | pre-pr; a post-pr record only, carrying
#                  --fingerprint, since a re-fired step declares paths
#                  An empty value of --skip-code, --stands-on, --pool, --wait,
#                  --fingerprint, --args-digest, --refire-of, or
#                  --wait-outcome is refused, never read as absent.
#   --wait-outcome taken | expired | unpooled | nested (--full-suite only; the
#                  stored unpooled flag reads yes exactly for unpooled)
#   --target, --skip-reason, --warning, --holder
#                  single-line text, no C0 control byte or DEL, at most 1024
#                  bytes, non-empty before and after the text cleaning below
#   --paths        (fingerprint) space-separated words of letters, digits,
#                  `.`, `_`, `-`, and `/`, none opening with `/` or `-` or
#                  holding a `..` segment, `.` the whole tree; at least one
#   --output       an existing regular file under the cache, absolute or
#                  relative to the worktree, a path of the text grammar above
#                  that the text cleaning leaves unchanged; stored
#                  worktree-relative
#   --excerpt-file a readable regular file
#
# Storage: <cache>/<run>/<seq>-step-<point>.rec,
# <cache>/<run>/<seq>-suite.rec (a full-suite record), and
# <cache>/<run>/<seq>-done-<point>.rec (a name never carries a step id, which
# the screen may withhold), <seq> three digits unique within the run and
# increasing in write order, at most 999 records a run. Issuing a run id and
# writing a record each happen under <cache>/.lock, taken through
# scripts/lock-lib.sh, so a record's own file is its sequence claim and its
# point's completion. A cache from before that lock also holds `.seq-<seq>`
# and `.done-<point>` directories; they still count as a claimed number and a
# completed point. A record is `<key><TAB><value>` lines: type, run, seq, then
# the fields above under their flag names (`excerpt` for --excerpt-file), an
# empty optional field stored empty; `excerpt`, `warning`, and `holder` lines
# repeat; `unpooled` stores yes, no, or (with no pool) empty. A record from
# before end heads lacks the `end-head` line and the extension's other
# fields; its skip reason renders as written.
# Records are mode 0600. Its form is unstable to anything but this helper.
#
# Text cleaning, applied to every stored text value, the excerpt, and the
# commit text regenerate reads: tabs become spaces; carriage returns and
# every other C0 control byte and DEL are stripped; invalid UTF-8 is dropped;
# C1 controls and the invisible and bidi-control code points are stripped
# (the list scripts/flight-text.sh's INVIS_SED names).
#
# The excerpt (--excerpt-file): the whole cleaned output is screened through
# scripts/inception-secret-screen.sh (the repository's secret screen,
# honoring PLANWRIGHT_SECRET_SCREEN_TOOL), then its last 20 lines, cut to the
# last 2000 bytes (a character the cut splits dropped), are kept. Screen
# action: on a hit the excerpt is withheld and stored as one placeholder
# line; a screen that cannot run withholds it the same way, never passing it
# unscreened. The step, target, backend, session, output, and skip-reason
# values, and each warning and holder, pass the same screen, a hit storing a
# placeholder in the value's place. The full captured output stays where
# --output names, unscreened.
#
# Rendered table (render, regenerate): per point,
#   ## Steps at `<point>` (run `<id>`)
# then a table with the columns
#   # | Step | Kind | Target | Hosting | Backend | Session | Head | Start |
#   End | Outcome | Excerpt | Output
# one row per step record (Outcome reads `skipped: <code>`, then ` on
# <run>:<point>:<seq>` for a record it stands on and ` (<detail>)` for its
# free-text detail, a record without a code `skipped: <detail>`; the
# excerpt's lines join with ` / `; Head shows 12 characters, `<start> to
# <end>` when the step moved the head), or a single `none` row when the point
# has only its completion record; then, after a blank line, one
# `- Row <n>: <details>` line per row carrying pool, paths, or re-fire
# fields, the details joined with `; ` (pool `<pool>`; waited <n> s;
# holders: <holder / holder>; ran unpooled; fingerprint `<12>` or none; args
# digest `<12>`; re-fire of `<point>`); then an "Ended on" line naming the
# head's first 12 characters when a completion record exists, and one
# `- Warning: <text>` line per warning. With no point named, a run's
# full-suite records follow as
#   ## Full-suite runs (run `<id>`)
# then a table with the columns
#   # | Pool | Wait outcome | Waited (s) | Holders | Unpooled | Start | End
#
# Neutralizing, applied to every rendered cell, warning, and checklist text:
# C0 control bytes, DEL, and C1 controls are dropped again (a record is read
# as untrusted); `&`, `<`, and `>` become entities; a zero-width space
# (`&#8203;`) follows every `@` and `#`, splits `://`, `www.`, and `GH-`, so
# no mention, issue reference, closing keyword, or autolink survives; `\`,
# `|`, backtick, `*`, `_`, `[`, `]`, `~`, `(`, `)`, `!`, `$`, and `+` are
# backslash-escaped, as are a leading `-` and the `.` or `)` of a leading
# number, so no markup, link, image, math, or list survives either.
#
# Checklist (regenerate), per doctrine/gate-wiring.md: a commit in the range
# is marked by `Planwright-Sign-Off:` trailers (read, unfolded, through git's
# trailer parser; each value split on blanks and commas, every `PS-<n>` with
# no leading zero an entry, other values ignored) or, legacy and only with no
# such ID, a `[pending-sign-off]` subject suffix (rendered with the ID
# `legacy`; the suffix is dropped from every rendered subject). Commits are
# read parents first (`--topo-order`). A marked commit drops out when a live
# commit in the range carries git's revert line for it (`This reverts commit
# <sha>` followed by `.`, `,`, ` (`, or the line's end, the sha full or, as
# `--reference` writes it, abbreviated to at least 7 hex digits that prefix
# exactly one earlier commit in the range), a commit being live unless a
# live revert undoes it, and a revert whose rejected trailer names one of its
# target's IDs being partial, undoing none of it; or when a live commit's
# `Planwright-Sign-Off-Rejected:` trailer names its PS ID (a legacy entry has
# no ID a trailer can name).
# A non-empty checklist opens with the approval statement (the act that lets
# the PR merge signs off every item, never the ready flip; an item is rejected
# before it by its recipe), so no checkbox stands in for the approval.
# Entries order by ID number, legacy entries last in commit order; an ID
# marked twice keeps its oldest live commit. An entry is
#   - **<id>** <subject> · commit `<sha7>` (<sha7>: the abbreviated sha,
#   at least 7 characters)
#     - Route reason: <the body's first `Route reason:` line, or `not
#       recorded in the commit`>
#     - Shared commit: also carries <the commit's other IDs still listed>,
#       or `its other findings were rejected` when none is (only when the
#       commit carries more than one distinct ID)
#     - <each manifest line: a body line `- <file> — before: …`, joined with
#       the indented lines that continue it>
#     - Reject with: `git revert <sha7>` (plus the hand-edit note when a
#       manifest is present); for a shared commit, a commit undoing its part
#       carrying `Planwright-Sign-Off-Rejected: <id>`; for a merge commit, a
#       later commit's `Planwright-Sign-Off-Rejected: <id>` trailer
#       (`git revert -m 1 <sha7>` for a legacy one, which no trailer can name);
#       for a merge whose body carries `Base-merge resolution: <paths>` (the
#       sync's `resolve` commit), a flag line naming the paths, then the
#       policy set to `halt` and a hand resolution carrying that trailer
# An empty checklist renders `- none`. A <base> or <head> that does not
# resolve, or a range git cannot read, fails by name.
#
# status's --repo is <owner>/<name>: the owner [A-Za-z0-9-], at most 39 bytes,
# not opening with `-`; the name [A-Za-z0-9._-], at most 100 bytes, neither
# `.` nor `..` nor opening with `-`. Its --point and --head follow the grammar
# above, the point one of the two flip points.
#
# Exit: 0 success · 1 a runtime failure (an unresolvable or unreadable range,
# a cache that cannot be read or written, an exhausted counter, a cache lock
# another writer held past the wait, a status with no attempt to post or a
# post that failed, no SHA-256 tool for args-digest) · 2 a usage or
# field-validation error · 3 lookup found no record to stand on.
#
# Portable POSIX sh + awk + iconv; bash 3.2 / BSD tooling floor.
set -u
LC_ALL=C
export LC_ALL
unset CDPATH
umask 077

script_dir=$(cd "$(dirname "$0")" && pwd) || exit 1
if [ ! -f "$script_dir/echo-safety.sh" ] || [ ! -r "$script_dir/echo-safety.sh" ]; then
  printf '%s\n' "step-record.sh: echo-safety.sh is missing or unreadable (broken install)" >&2
  exit 1
fi
# shellcheck source=scripts/echo-safety.sh
. "$script_dir/echo-safety.sh"
# shellcheck source=scripts/lock-lib.sh
. "$script_dir/lock-lib.sh"

prog='step-record.sh'
TAB=$(printf '\t')
LF='
'
EXCERPT_LINES=20
EXCERPT_BYTES=2000
TEXT_MAX=1024

# The byte sequences of the C1 controls, then the invisible and bidi-control
# code points, deleted bytewise; the second list is flight-text.sh's.
INVIS_SED=$(printf 's/\302[\200-\237]//g;s/\302[\205\255]//g;s/\330\234//g;s/\341\205[\237\240]//g;s/\341\236[\264\265]//g;s/\341\240\216//g;s/\342\200[\213-\217\250-\256]//g;s/\342\201[\240-\244\246-\257]//g;s/\343\205\244//g;s/\357\270[\200-\217]//g;s/\357\273\277//g;s/\357\276\240//g;s/\357\277[\271-\273]//g;s/\363\240[\200\201][\200-\277]//g;s/\363\240[\204-\206][\200-\277]//g;s/\363\240\207[\200-\257]//g')

# Word splitting only on newlines, and no globbing: record paths live under a
# worktree path that may carry blanks.
IFS=$LF
set -f

work=''
pending=''
cleanup() {
  pw_lock_release_all
  [ -z "$pending" ] || rm -f "$pending"
  [ -z "$work" ] || rm -rf "$work"
}
trap cleanup EXIT
trap 'cleanup; exit 1' HUP INT TERM

die() {
  printf '%s: %s\n' "$prog" "$2" >&2
  exit "$1"
}
usage() {
  sed -n '/^# Usage:/,/^# Field grammar/p' "$0" | sed -e '$d' -e 's/^# \{0,1\}//' >&2
  exit 2
}
# bad <flag> <reason>: a refused field, named, its value never echoed.
bad() { die 2 "$1: $2"; }

# scratch: the one temporary directory, made in the main shell so its
# cleanup trap runs.
scratch() {
  [ -n "$work" ] && return 0
  work=$(mktemp -d "${TMPDIR:-/tmp}/step-record.XXXXXX") || die 1 "cannot create a temporary directory"
  # Absolute, because a claim reads it after lock_cache has changed directory.
  case $work in /*) ;; *) work="$(pwd -P)/$work" ;; esac
}

# has_ctl <value>: true when the value carries a C0 control byte or DEL.
has_ctl() {
  case $1 in *[[:cntrl:]]*) return 0 ;; esac
  return 1
}

is_text() {
  [ -n "$1" ] && ! has_ctl "$1" && [ "${#1}" -le "$TEXT_MAX" ]
}

# The vocabulary resolve-steps.sh's WIRED_POINTS and UNWIRED_POINTS hold; the
# lists change together, is_in_run_point's being WIRED_POINTS minus the two
# flip points.
is_in_run_point() {
  case $1 in pre-implementation | pre-ci | convergence | pre-pr | post-pr) return 0 ;; esac
  return 1
}

is_point() {
  case $1 in
    pre-implementation | pre-ci | convergence | pre-pr | post-pr | pre-ready-flip | \
      pre-spec-ready-flip | spec-drafted | kickoff-signed-off | unit-selected | \
      pre-dispatch | post-dispatch | unit-halted | post-merge | orchestrator-idle) return 0 ;;
  esac
  return 1
}

is_step_id() {
  case $1 in '' | [!a-z]* | *[!a-z0-9-]*) return 1 ;; esac
  [ "${#1}" -le 64 ]
}

is_backend() {
  case $1 in '' | [!a-z0-9]* | *[!a-z0-9-]*) return 1 ;; esac
  [ "${#1}" -le 64 ]
}

is_session() {
  case $1 in '' | *[!A-Za-z0-9._:-]*) return 1 ;; esac
  [ "${#1}" -le 128 ]
}

is_head() { is_oid "$1"; }

# is_oid: the shape of a full git object id, 40 or 64 lowercase hex digits.
is_oid() {
  case $1 in *[!0-9a-f]*) return 1 ;; esac
  [ "${#1}" -eq 40 ] || [ "${#1}" -eq 64 ]
}

is_ts() {
  case $1 in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z) return 0 ;;
  esac
  return 1
}

# set_head_from_worktree: assigns head the worktree's own HEAD commit.
set_head_from_worktree() {
  worktree_head --head
  head=$WT_HEAD
}

# git_wt <args>: git in the worktree with every inherited variable that would
# point it at another repository, index, object store, or pathspec reading
# cleared; pathspecs are literal unless GW_LITERAL is 0 (check-ignore refuses
# literal pathspecs; the --paths grammar admits no pathspec magic anyway).
git_wt() {
  (
    unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
      GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_COMMON_DIR GIT_NAMESPACE \
      GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT GIT_GLOB_PATHSPECS \
      GIT_NOGLOB_PATHSPECS GIT_ICASE_PATHSPECS
    if [ "${GW_LITERAL:-1}" = 1 ]; then
      GIT_LITERAL_PATHSPECS=1
      export GIT_LITERAL_PATHSPECS
    else
      unset GIT_LITERAL_PATHSPECS
    fi
    git -C "$worktree" "$@"
  )
}

# read_worktree_head: sets WT_HEAD to the worktree's own HEAD commit; returns
# 1 when the worktree is not the top of a git work tree, 2 when it has no
# commit, 3 when git cannot read HEAD. A --worktree that is a plain directory inside another repository
# would resolve that repository, so it is refused rather than reading a commit
# from elsewhere.
read_worktree_head() {
  command -v git >/dev/null 2>&1 || die 1 "git is not on PATH"
  _top=$(git_wt rev-parse --show-toplevel 2>/dev/null) \
    && _top=$(cd -P -- "$_top" 2>/dev/null && pwd -P) && [ "$_top" = "$worktree" ] || return 1
  WT_HEAD=$(git_wt rev-parse --verify --quiet 'HEAD^{commit}' 2>/dev/null) && return 0
  # Unborn: HEAD names a branch that does not exist yet. Anything else is a
  # git failure.
  _ref=$(git_wt symbolic-ref -q HEAD 2>/dev/null) && ! git_wt rev-parse --verify --quiet "$_ref" >/dev/null 2>&1 \
    && return 2
  return 3
}

# worktree_head <flag>: read_worktree_head, a failure refusing <flag>.
worktree_head() {
  read_worktree_head
  case $? in
    0) ;;
    1) bad "$1" "not given and the worktree is not the top of a git work tree to default from" ;;
    2) bad "$1" "not given and the worktree has no commit to default to" ;;
    *) die 1 "git cannot read the worktree's HEAD" ;;
  esac
}

# A pool name shares the step-id grammar.
is_pool() { is_step_id "$1"; }

is_sha256() {
  case $1 in *[!0-9a-f]*) return 1 ;; esac
  [ "${#1}" -eq 64 ]
}

is_seconds() {
  case $1 in '' | *[!0-9]*) return 1 ;; esac
  [ "${#1}" -le 9 ]
}

# is_ref <run>:<point>:<seq>: the --stands-on grammar; sets REF_RUN,
# REF_POINT, REF_SEQ, and REF_PATH, the step record it names.
is_ref() {
  case $1 in *:*:*:*) return 1 ;; *:*:*) ;; *) return 1 ;; esac
  REF_RUN=${1%%:*} REF_SEQ=${1##*:}
  REF_POINT=${1#*:}
  REF_POINT=${REF_POINT%:*}
  is_run_id "$REF_RUN" && is_point "$REF_POINT" || return 1
  case $REF_SEQ in [0-9][0-9][0-9]) ;; *) return 1 ;; esac
  REF_PATH="$cache/$REF_RUN/$REF_SEQ-step-$REF_POINT.rec"
}

# sha256 <file>: print the file's SHA-256 in hex.
sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    _d=$(sha256sum <"$1")
  elif command -v shasum >/dev/null 2>&1; then
    _d=$(shasum -a 256 <"$1")
  elif command -v openssl >/dev/null 2>&1; then
    _d=$(openssl dgst -sha256 -r <"$1")
  else
    die 1 "no SHA-256 tool (sha256sum, shasum, or openssl) is on PATH"
  fi
  _d=${_d%%[!0-9a-f]*}
  is_sha256 "$_d" || die 1 "the SHA-256 tool printed no digest"
  printf '%s\n' "$_d" || die 1 "cannot print the digest"
}

is_run_id() {
  case $1 in [0-9][0-9][0-9][0-9][0-9][0-9]) return 0 ;; esac
  return 1
}

# clean <in> <out>: the text cleaning the header pins. The invisible strip
# repeats until stable, since one deletion can join its neighbours into
# another code point.
clean() {
  tr '\t' ' ' <"$1" >"$2.0" || die 1 "cannot clean text"
  tr -d '\000-\010\013-\037\177' <"$2.0" >"$2.t" || die 1 "cannot clean text"
  # iconv's status differs across platforms when it drops input, so it is
  # not read; its presence is checked once, at startup.
  iconv -c -f UTF-8 -t UTF-8 <"$2.t" >"$2.1" 2>/dev/null
  rm -f "$2.0" "$2.t"
  while :; do
    sed "$INVIS_SED" <"$2.1" >"$2.2" || die 1 "cannot clean text"
    cmp -s "$2.1" "$2.2" && break
    mv "$2.2" "$2.1" || die 1 "cannot clean text"
  done
  mv "$2.1" "$2" || die 1 "cannot clean text"
  rm -f "$2.2"
}

# clean_value <value>: sets CLEANED to the cleaned value.
clean_value() {
  scratch
  printf '%s\n' "$1" >"$work/value" || die 1 "cannot write a temporary file"
  clean "$work/value" "$work/value.clean"
  CLEANED=$(cat "$work/value.clean")
}

# screen <file>: sets SCREEN_RC to the secret screen's verdict on the file
# (0 clean, 1 flagged, 2 could not screen).
screen() {
  SCREEN_RC=0
  if [ -r "$script_dir/inception-secret-screen.sh" ]; then
    /bin/sh "$script_dir/inception-secret-screen.sh" -- "$1" >/dev/null 2>&1 || SCREEN_RC=$?
  else
    SCREEN_RC=2
  fi
  [ "$SCREEN_RC" -le 1 ] || SCREEN_RC=2
}

withheld() {
  if [ "$SCREEN_RC" -eq 1 ]; then
    printf '[withheld: the secret screen flagged this %s]' "$1"
  else
    printf '[withheld: the %s could not be screened]' "$1"
  fi
}

# screen_values <label> <value>...: write the values to $work/screened, one
# line each (an empty value an empty line), each replaced by its placeholder
# when the screen does not pass it. One screen call covers the batch; only a
# batch that does not pass is screened value by value, to name which values
# to withhold.
screen_values() {
  scratch
  sv_label=$1
  shift
  if [ $# -eq 0 ]; then
    : >"$work/screened" || die 1 "cannot write a temporary file"
    return 0
  fi
  : >"$work/batch" || die 1 "cannot write a temporary file"
  for v in "$@"; do printf '%s\n' "$v" >>"$work/batch"; done
  screen "$work/batch"
  sv_all=$SCREEN_RC
  : >"$work/screened"
  for v in "$@"; do
    if [ "$sv_all" -ne 0 ] && [ -n "$v" ]; then
      printf '%s\n' "$v" >"$work/one"
      screen "$work/one"
      [ "$SCREEN_RC" -eq 0 ] || v=$(withheld "$sv_label")
    fi
    printf '%s\n' "$v" >>"$work/screened" || die 1 "cannot write a temporary file"
  done
}

# build_excerpt <in> <out>: the excerpt the header pins, cleaned, screened,
# and bounded, or its one-line placeholder.
build_excerpt() {
  scratch
  clean "$1" "$work/excerpt.full"
  screen "$work/excerpt.full"
  if [ "$SCREEN_RC" -eq 0 ]; then
    tail -n "$EXCERPT_LINES" "$work/excerpt.full" | tail -c "$EXCERPT_BYTES" \
      | iconv -c -f UTF-8 -t UTF-8 >"$2" 2>/dev/null
  else
    withheld excerpt >"$2"
    printf '\n' >>"$2"
  fi
}

# --- global option and verb ---------------------------------------------------
worktree=''
while [ $# -gt 0 ]; do
  case $1 in
    --worktree)
      [ $# -ge 2 ] || usage
      worktree=$2
      shift 2
      ;;
    -h | --help) usage ;;
    *) break ;;
  esac
done
[ $# -ge 1 ] || usage
verb=$1
shift

# excerpt reads no record cache, so it runs before the worktree is resolved.
if [ "$verb" = excerpt ]; then
  [ $# -eq 1 ] && [ -z "$worktree" ] || usage
  [ -f "$1" ] && [ -r "$1" ] || bad excerpt "not a readable file"
  command -v iconv >/dev/null 2>&1 || die 1 "iconv is not on PATH"
  scratch
  build_excerpt "$1" "$work/excerpt"
  cat "$work/excerpt" || die 1 "cannot print the excerpt"
  exit 0
fi
if [ "$verb" = args-digest ]; then
  [ $# -eq 1 ] && [ -z "$worktree" ] || usage
  scratch
  printf '%s' "$1" >"$work/args" || die 1 "cannot write a temporary file"
  sha256 "$work/args"
  exit 0
fi

if [ -z "$worktree" ]; then
  command -v git >/dev/null 2>&1 || die 1 "git is not on PATH"
  worktree=$(git rev-parse --show-toplevel 2>/dev/null) || die 2 "--worktree: not given and not inside a git work tree"
fi
case $worktree in /*) ;; *) worktree="./$worktree" ;; esac
[ -d "$worktree" ] || bad --worktree "not a directory"
worktree=$(cd -P -- "$worktree" && pwd -P) || bad --worktree "not readable"
cache="$worktree/.claude/steps"

# check_dir <dir>: refuse a symlinked or unreadable cache directory.
check_dir() {
  [ ! -L "$1" ] || die 1 "the record cache holds a symlink; refusing it"
  [ ! -e "$1" ] || { [ -d "$1" ] && [ -r "$1" ] && [ -x "$1" ]; } || die 1 "the record cache cannot be read"
}

# glob_names <dir> <pattern>: the names in <dir> matching <pattern>, sorted,
# one per line (globbing is off everywhere else).
glob_names() {
  set +f
  for _g in "$1"/$2; do
    if [ -e "$_g" ] || [ -L "$_g" ]; then printf '%s\n' "${_g##*/}"; fi
  done
  set -f
}

run_ids() {
  [ -d "$cache" ] || return 0
  glob_names "$cache" '[0-9][0-9][0-9][0-9][0-9][0-9]'
}

# check_run <run>: refuse a run directory, or a record in it, that is a
# symlink or cannot be read. Runs in the main shell, before any listing
# below reads the run inside a command substitution, where a refusal could
# not end the script.
check_run() {
  check_dir "$cache/$1"
  for _f in $(glob_names "$cache/$1" '[0-9][0-9][0-9]-*.rec'); do
    _p="$cache/$1/$_f"
    { [ ! -L "$_p" ] && [ -f "$_p" ] && [ -r "$_p" ]; } || die 1 "a record cannot be read"
  done
}

# record_files <run>: the run's record paths in seq order (check_run first).
record_files() {
  for _f in $(glob_names "$cache/$1" '[0-9][0-9][0-9]-*.rec'); do
    printf '%s\n' "$cache/$1/$_f"
  done
}

valid_run() {
  is_run_id "$1" || bad --run "not a run id"
  [ -d "$cache/$1" ] || bad --run "no such run in the cache"
  check_run "$1"
}

# lock_cache / unlock_cache: hold <cache>/.lock around a claim. The lock is
# named from inside the cache because lock-lib refuses a path carrying `#`,
# which a worktree path may; every path a claim reads is absolute by then.
lock_cache() {
  cd "$cache" || die 1 "cannot enter the record cache"
  pw_lock_acquire .lock
  case $? in
    0) ;;
    1) die 1 "the record cache stayed locked by another writer" ;;
    *) die 1 "cannot lock the record cache" ;;
  esac
}
# A release that fails stays recorded, and the exit handler retries it.
unlock_cache() { pw_lock_release .lock || :; }

# point_done <run> <point>: true once the run completed the point, by its
# record or by a directory-shaped marker an older writer left.
point_done() {
  [ -d "$cache/$1/.done-$2" ] \
    || [ -n "$(glob_names "$cache/$1" "[0-9][0-9][0-9]-done-$2.rec")" ]
}

# latest_run: sets LATEST to the highest run id, if any.
latest_run() {
  LATEST=$(run_ids | tail -n 1)
  [ -z "$LATEST" ] || check_run "$LATEST"
}

# --- new-run -------------------------------------------------------------------
cmd_new_run() {
  [ $# -eq 0 ] || usage
  mkdir -p "$cache" || die 1 "cannot create the record cache"
  lock_cache
  last=$(run_ids | tail -n 1)
  next=$((1${last:-000000} - 1000000 + 1))
  [ "$next" -le 999999 ] || die 1 "the run-id counter is exhausted"
  id=$(printf '%06d' "$next")
  { [ ! -e "$cache/$id" ] && [ ! -L "$cache/$id" ]; } || die 1 "cannot create a run directory"
  mkdir -p "$cache/$id" || die 1 "cannot create a run directory"
  unlock_cache
  printf '%s\n' "$id" || {
    rmdir "$cache/$id"
    die 1 "cannot print the run id"
  }
}

# --- write ------------------------------------------------------------------------
# put <key> <value>: one record line. Each write is checked on its own, since
# a group's status is only its last command's.
put() {
  printf '%s\t%s\n' "$1" "$2" || die 1 "cannot write a temporary file"
}

# claim <run> <stem> <type> <body-file> [<point>]: under the cache lock, refuse
# once the point is completed, then write the record under the run's next
# sequence number and print its absolute path.
claim() {
  dir="$cache/$1"
  lock_cache
  [ -z "${5:-}" ] || ! point_done "$1" "$5" || bad --point "already completed in this run"
  last=$({
    glob_names "$dir" '.seq-[0-9][0-9][0-9]' | sed 's/^\.seq-//'
    glob_names "$dir" '[0-9][0-9][0-9]-*.rec' | cut -c1-3
  } | sort | tail -n 1)
  next=$((1${last:-000} - 1000 + 1))
  [ "$next" -le 999 ] || die 1 "the run's record counter is exhausted"
  seq=$(printf '%03d' "$next")
  pending=$(mktemp "$dir/.rec-XXXXXX") || die 1 "cannot write to the record cache"
  { printf 'type\t%s\nrun\t%s\nseq\t%s\n' "$3" "$1" "$seq" && cat "$4"; } >"$pending" \
    || die 1 "cannot write to the record cache"
  path="$dir/$seq-$2.rec"
  ln "$pending" "$path" || die 1 "cannot write to the record cache"
  rm -f "$pending"
  pending=''
  unlock_cache
  printf '%s\n' "$path" || die 1 "cannot print the record path"
}

# --- write helpers: they read the flag state cmd_write parsed ------------------
# check_end: an omitted --end is the clock now; either way --end is a stamp
# no earlier than --start.
check_end() {
  if [ "$end_given" -eq 0 ]; then
    end=$(date -u +%Y-%m-%dT%H:%M:%SZ) || die 1 "cannot read the clock"
    is_ts "$end" || die 1 "the clock printed no UTC stamp"
  fi
  is_ts "$end" || bad --end "not YYYY-MM-DDTHH:MM:SSZ"
  # Same-width UTC stamps: the digits compare as numbers.
  [ "$(printf '%s' "$end" | tr -d -- '-:TZ')" -ge "$(printf '%s' "$start" | tr -d -- '-:TZ')" ] \
    && return 0
  [ "$end_given" -eq 1 ] || bad --end "not given, and the clock now reads earlier than --start"
  bad --end "earlier than --start"
}

# check_pool_fields: --pool with its --wait, and the other pool fields only
# beside a pool.
check_pool_fields() {
  if [ "$pool_given" -eq 1 ]; then
    is_pool "$pool" || bad --pool "not a pool name"
    [ "$wait_given" -eq 1 ] || bad --wait "required with --pool"
    is_seconds "$wait" || bad --wait "not whole seconds"
  elif [ "$wait_given" -eq 1 ] || [ -n "$holders" ] || [ "$unpooled" -eq 1 ]; then
    bad --pool "required with --wait, --holder, or --unpooled"
  fi
}

# clean_holders: sets HOLDERS_CLEAN to the cleaned holders, one a line.
clean_holders() {
  HOLDERS_CLEAN=''
  for h in $holders; do
    clean_value "$h"
    [ -n "$CLEANED" ] || bad --holder "empty once cleaned"
    HOLDERS_CLEAN="$HOLDERS_CLEAN$CLEANED$LF"
  done
}

# check_stands_on: the record REF_PATH names must be one this skip can stand
# on: a well-formed step record of the same step id, passed for a reuse,
# passed or applied and ending on this record's end head for a resume.
check_stands_on() {
  _on=$(printf '%s\n' "$REF_PATH" | awk -v TAB="$TAB" "$AWK_RECORD"'
    { if (load($0) && ok_step()) print F["step"] TAB F["outcome"] TAB F["end-head"] }
    END { if (err) exit 2 }') || die 1 "a record cannot be read"
  case $skip_code:$_on in
    "reuse:$step${TAB}passed$TAB"*) ;;
    "resume:$step${TAB}passed$TAB$end_head" | "resume:$step${TAB}applied$TAB$end_head") ;;
    *) bad --stands-on "names no $skip_code-qualifying record of this step" ;;
  esac
}

cmd_write() {
  completion=0 full_suite=0 run='' point='' step='' kind='' target='' hosting=''
  backend='' session='' head='' end_head='' start='' end='' outcome='' excerpt_file=''
  output='' skip_reason='' skip_code='' skip_codes=0 stands_on='' pool='' wait=''
  holders='' unpooled=0 fingerprint='' args_digest='' refire_of='' wait_outcome=''
  warnings='' head_given=0 end_head_given=0 end_given=0 pool_given=0 wait_given=0
  while [ $# -gt 0 ]; do
    case $1 in
      --completion | --full-suite | --unpooled)
        case $1 in
          --completion) completion=1 ;;
          --full-suite) full_suite=1 ;;
          --unpooled) unpooled=1 ;;
        esac
        shift
        continue
        ;;
      --run | --point | --step | --kind | --target | --hosting | --backend | \
        --session | --head | --end-head | --start | --end | --outcome | \
        --excerpt-file | --output | --skip-reason | --skip-code | --stands-on | \
        --pool | --wait | --holder | --fingerprint | --args-digest | --refire-of | \
        --wait-outcome | --warning)
        [ $# -ge 2 ] || usage
        ;;
      *) usage ;;
    esac
    # An empty value for a field the extension added is a failed substitution
    # more likely than an absent field, so it is refused, never read as absent.
    case $1 in
      --skip-code | --stands-on | --pool | --wait | --fingerprint | --args-digest | \
        --refire-of | --wait-outcome) [ -n "$2" ] || bad "$1" "given empty" ;;
    esac
    case $1 in
      --run) run=$2 ;;
      --point) point=$2 ;;
      --step) step=$2 ;;
      --kind) kind=$2 ;;
      --target) target=$2 ;;
      --hosting) hosting=$2 ;;
      --backend) backend=$2 ;;
      --session) session=$2 ;;
      --head)
        head=$2
        head_given=1
        ;;
      --end-head)
        end_head=$2
        end_head_given=1
        ;;
      --start) start=$2 ;;
      --end)
        end=$2
        end_given=1
        ;;
      --outcome) outcome=$2 ;;
      --excerpt-file) excerpt_file=$2 ;;
      --output) output=$2 ;;
      --skip-reason) skip_reason=$2 ;;
      --skip-code)
        skip_code=$2
        skip_codes=$((skip_codes + 1))
        ;;
      --stands-on) stands_on=$2 ;;
      --pool)
        pool=$2
        pool_given=1
        ;;
      --wait)
        wait=$2
        wait_given=1
        ;;
      --holder)
        is_text "$2" || bad --holder "must be non-empty single-line text of at most $TEXT_MAX bytes"
        holders="$holders$2$LF"
        ;;
      --fingerprint) fingerprint=$2 ;;
      --args-digest) args_digest=$2 ;;
      --refire-of) refire_of=$2 ;;
      --wait-outcome) wait_outcome=$2 ;;
      --warning)
        is_text "$2" || bad --warning "must be non-empty single-line text of at most $TEXT_MAX bytes"
        warnings="$warnings$2$LF"
        ;;
    esac
    shift 2
  done

  [ -n "$run" ] || bad --run "required"
  valid_run "$run"
  if [ "$full_suite" -eq 1 ]; then
    write_full_suite
    return
  fi
  [ -z "$wait_outcome" ] || bad --wait-outcome "belongs to write --full-suite"
  is_point "$point" || bad --point "not a point of the vocabulary"
  # An explicit --head, even an empty one, is never defaulted: an empty value
  # is more likely a failed substitution than a request for HEAD.
  [ "$head_given" -eq 1 ] || set_head_from_worktree
  is_head "$head" || bad --head "not a full commit id"
  ! point_done "$run" "$point" || bad --point "already completed in this run"

  if [ "$completion" -eq 1 ]; then
    for f in "$step" "$kind" "$target" "$hosting" "$backend" "$session" \
      "$start" "$end" "$outcome" "$excerpt_file" "$output" "$skip_reason" \
      "$skip_code" "$stands_on" "$pool" "$wait" "$holders" "$fingerprint" \
      "$args_digest" "$refire_of"; do
      [ -z "$f" ] || bad --completion "takes only --run, --point, --head, and --warning"
    done
    [ "$end_head_given" -eq 0 ] && [ "$unpooled" -eq 0 ] && [ "$pool_given" -eq 0 ] \
      && [ "$wait_given" -eq 0 ] || bad --completion "takes only --run, --point, --head, and --warning"
    scratch
    cleaned=''
    for w in $warnings; do
      clean_value "$w"
      [ -n "$CLEANED" ] || bad --warning "empty once cleaned"
      cleaned="$cleaned$CLEANED$LF"
    done
    # shellcheck disable=SC2086 # split on newlines by design (IFS)
    screen_values warning $cleaned
    {
      put point "$point"
      put head "$head"
      [ -z "$cleaned" ] || while IFS= read -r w; do
        put warning "$w"
      done <"$work/screened"
    } >"$work/body" || die 1 "cannot write a temporary file"
    claim "$run" "done-$point" completion "$work/body" "$point"
    return
  fi
  [ -z "$warnings" ] || bad --warning "belongs to write --completion"

  is_step_id "$step" || bad --step "not a step id"
  [ "$step" != implementation ] || bad --step "reserved for the implementation phase"
  case $kind in skill | command | prompt) ;; *) bad --kind "not skill, command, or prompt" ;; esac
  is_text "$target" || bad --target "must be non-empty single-line text of at most $TEXT_MAX bytes"
  case $hosting in isolated | continue | in-session) ;; *) bad --hosting "not isolated, continue, or in-session" ;; esac
  is_backend "$backend" || bad --backend "not a backend name"
  [ -z "$session" ] || is_session "$session" || bad --session "not a session id"
  if [ "$end_head_given" -eq 1 ]; then
    :
  elif [ "$head_given" -eq 0 ]; then
    end_head=$head
  else
    worktree_head --end-head
    end_head=$WT_HEAD
  fi
  is_head "$end_head" || bad --end-head "not a full commit id"
  is_ts "$start" || bad --start "not YYYY-MM-DDTHH:MM:SSZ"
  check_end
  case $outcome in
    passed | applied | halted | failed | skipped | limited) ;;
    *) bad --outcome "not passed, applied, halted, failed, skipped, or limited" ;;
  esac
  if [ "$outcome" = skipped ]; then
    [ "$skip_codes" -eq 1 ] || bad --skip-code "a skipped step carries exactly one"
    case $skip_code in missing | reuse | resume | answered) ;; *) bad --skip-code "not missing, reuse, resume, or answered" ;; esac
    [ -z "$skip_reason" ] || is_text "$skip_reason" \
      || bad --skip-reason "must be single-line text of at most $TEXT_MAX bytes"
  else
    [ "$skip_codes" -eq 0 ] || bad --skip-code "only a skipped step carries one"
    [ -z "$skip_reason" ] || bad --skip-reason "only a skipped step carries one"
  fi
  case $skip_code in
    reuse | resume)
      [ -n "$stands_on" ] || bad --stands-on "required for a $skip_code skip"
      is_ref "$stands_on" || bad --stands-on "not <run>:<point>:<seq>"
      [ -d "$cache/$REF_RUN" ] && [ ! -L "$cache/$REF_RUN" ] && [ -f "$REF_PATH" ] && [ ! -L "$REF_PATH" ] \
        || bad --stands-on "names no step record in the cache"
      check_stands_on
      ;;
    *) [ -z "$stands_on" ] || bad --stands-on "only a reuse or resume skip stands on a record" ;;
  esac
  check_pool_fields
  if [ -n "$fingerprint" ] || [ -n "$args_digest" ]; then
    [ -n "$args_digest" ] || bad --args-digest "required with --fingerprint"
    [ -n "$fingerprint" ] || bad --fingerprint "required with --args-digest"
    [ "$fingerprint" = none ] || is_oid "$fingerprint" || bad --fingerprint "not none or a fingerprint"
    is_sha256 "$args_digest" || bad --args-digest "not a SHA-256 digest"
  fi
  if [ -n "$refire_of" ]; then
    case $refire_of in pre-ci | pre-pr) ;; *) bad --refire-of "not pre-ci or pre-pr" ;; esac
    [ "$point" = post-pr ] || bad --refire-of "only a post-pr record carries one"
    [ -n "$fingerprint" ] || bad --fingerprint "required with --refire-of, whose step declares paths"
  fi
  rel_output=''
  if [ -n "$output" ]; then
    is_text "$output" || bad --output "not a single-line path"
    case $output in /*) ;; *) output="$worktree/$output" ;; esac
    [ -f "$output" ] && [ ! -L "$output" ] || bad --output "not an existing regular file"
    _od=$(cd "$(dirname "$output")" 2>/dev/null && pwd -P) || bad --output "not an existing regular file"
    output="$_od/${output##*/}"
    case $output in
      "$cache"/*) rel_output=${output#"$worktree"/} ;;
      *) bad --output "outside the record cache" ;;
    esac
  fi
  if [ -n "$excerpt_file" ]; then
    [ -f "$excerpt_file" ] && [ -r "$excerpt_file" ] || bad --excerpt-file "not a readable file"
  fi

  scratch
  clean_value "$target"
  target=$CLEANED
  [ -n "$target" ] || bad --target "empty once cleaned"
  if [ -n "$skip_reason" ]; then
    clean_value "$skip_reason"
    skip_reason=$CLEANED
    [ -n "$skip_reason" ] || bad --skip-reason "empty once cleaned"
  fi
  if [ -n "$rel_output" ]; then
    clean_value "$rel_output"
    [ "$CLEANED" = "$rel_output" ] || bad --output "carries control or invisible characters"
  fi
  clean_holders
  # The unpacking below reads these back by position, the holders after the
  # six fixed values; the two lists change together.
  # shellcheck disable=SC2086 # the holders split on newlines by design (IFS)
  screen_values value "$step" "$target" "$backend" "$session" "$rel_output" "$skip_reason" $HOLDERS_CLEAN
  : >"$work/holders" || die 1 "cannot write a temporary file"
  i=0
  while IFS= read -r l; do
    i=$((i + 1))
    case $i in
      1) s_step=$l ;;
      2) s_target=$l ;;
      3) s_backend=$l ;;
      4) s_session=$l ;;
      5) s_output=$l ;;
      6) s_skip=$l ;;
      *) printf '%s\n' "$l" >>"$work/holders" || die 1 "cannot write a temporary file" ;;
    esac
  done <"$work/screened"

  : >"$work/excerpt"
  [ -z "$excerpt_file" ] || build_excerpt "$excerpt_file" "$work/excerpt"

  s_unpooled=''
  if [ -n "$pool" ]; then
    s_unpooled=no
    [ "$unpooled" -eq 0 ] || s_unpooled=yes
  fi
  {
    put point "$point"
    put step "$s_step"
    put kind "$kind"
    put target "$s_target"
    put hosting "$hosting"
    put backend "$s_backend"
    put session "$s_session"
    put head "$head"
    put end-head "$end_head"
    put start "$start"
    put end "$end"
    put outcome "$outcome"
    put output "$s_output"
    put skip-code "$skip_code"
    put skip-reason "$s_skip"
    put stands-on "$stands_on"
    put pool "$pool"
    put wait "$wait"
    put unpooled "$s_unpooled"
    while IFS= read -r h; do
      put holder "$h"
    done <"$work/holders"
    put fingerprint "$fingerprint"
    put args-digest "$args_digest"
    put refire-of "$refire_of"
    while IFS= read -r line || [ -n "$line" ]; do
      put excerpt "$line"
    done <"$work/excerpt"
  } >"$work/body" || die 1 "cannot write a temporary file"
  claim "$run" "step-$point" step "$work/body" "$point"
}

# write_full_suite: the full-suite record, its flags checked against the
# ones it takes.
write_full_suite() {
  for f in "$point" "$step" "$kind" "$target" "$hosting" "$backend" "$session" \
    "$outcome" "$excerpt_file" "$output" "$skip_reason" "$skip_code" "$stands_on" \
    "$fingerprint" "$args_digest" "$refire_of" "$warnings"; do
    [ -z "$f" ] || bad --full-suite "takes only --run, --pool, --wait, --wait-outcome, --holder, --start, and --end"
  done
  [ "$completion" -eq 0 ] && [ "$head_given" -eq 0 ] && [ "$end_head_given" -eq 0 ] \
    && [ "$unpooled" -eq 0 ] \
    || bad --full-suite "takes only --run, --pool, --wait, --wait-outcome, --holder, --start, and --end"
  [ "$pool_given" -eq 1 ] || bad --pool "required"
  check_pool_fields
  case $wait_outcome in
    taken | expired | unpooled | nested) ;;
    *) bad --wait-outcome "not taken, expired, unpooled, or nested" ;;
  esac
  is_ts "$start" || bad --start "not YYYY-MM-DDTHH:MM:SSZ"
  check_end
  clean_holders
  # shellcheck disable=SC2086 # split on newlines by design (IFS)
  screen_values value $HOLDERS_CLEAN
  mv "$work/screened" "$work/holders" || die 1 "cannot write a temporary file"
  s_unpooled=no
  [ "$wait_outcome" != unpooled ] || s_unpooled=yes
  {
    put pool "$pool"
    put wait "$wait"
    put wait-outcome "$wait_outcome"
    put unpooled "$s_unpooled"
    while IFS= read -r h; do
      put holder "$h"
    done <"$work/holders"
    put start "$start"
    put end "$end"
  } >"$work/body" || die 1 "cannot write a temporary file"
  claim "$run" suite full-suite "$work/body"
}

# --- list -----------------------------------------------------------------------
cmd_list() {
  run='' point=''
  while [ $# -gt 0 ]; do
    case $1 in
      --run | --point) [ $# -ge 2 ] || usage ;;
      *) usage ;;
    esac
    case $1 in
      --run) run=$2 ;;
      --point) point=$2 ;;
    esac
    shift 2
  done
  [ -z "$run" ] || valid_run "$run"
  [ -z "$point" ] || is_point "$point" || bad --point "not a point of the vocabulary"
  if [ -n "$run" ]; then runs=$run; else runs=$(run_ids); fi
  for r in $runs; do
    check_run "$r"
    for f in $(record_files "$r"); do
      if [ -n "$point" ]; then
        grep -Fxq "point$TAB$point" "$f" || continue
      fi
      printf 'record\t%s\n' "${f#"$worktree"/}"
      tr -d '\000-\010\013-\037\177' <"$f" || die 1 "a record cannot be read"
      printf '\n'
    done
  done
}

# --- render ----------------------------------------------------------------------
# safe(s): the neutralizing the header pins, shared by both renderers.
AWK_SAFE='
function safe(s,    out, i, n, c, z, lead) {
  out = ""; n = length(s); z = "&#8203;"; lead = 0
  if (match(s, /^[0-9]+[.)]/)) lead = RLENGTH
  for (i = 1; i <= n; i++) {
    c = substr(s, i, 1)
    if (c < " " || c == "\177") continue
    if (c == "\302" && substr(s, i + 1, 1) >= "\200" && substr(s, i + 1, 1) <= "\237") { i++; continue }
    if (i == lead || (i == 1 && c == "-")) c = "\\" c
    else if (c == "&") c = "&amp;"
    else if (c == "<") c = "&lt;"
    else if (c == ">") c = "&gt;"
    else if (c == "@" || c == "#") c = c z
    else if (c == ":" && substr(s, i + 1, 2) == "//") { c = ":/" z "/"; i += 2 }
    else if (tolower(substr(s, i, 4)) == "www.") { c = substr(s, i, 3) z "."; i += 3 }
    else if (c == "-" && i > 2 && tolower(substr(s, i - 2, 2)) == "gh") c = z "-"
    else if (index("\\|`*_[]~()!$+", c)) c = "\\" c
    out = out c
  }
  return out
}
'

# AWK_RECORD: the readers' record loader. load(path) reads one record into F,
# its run, sequence, kind (step, done, suite), and point taken from the path,
# never from its contents (R_RUN, R_SEQ, R_KIND, R_POINT), and returns 0 for a
# path that names no record. It sets bad when a single-valued key repeats, a
# line carries no tab, or the stored run, seq, or point disagrees with the
# path, or its stored type disagrees with the path's kind. A read error sets
# err and exits 2, unless the record was optional (a resume skip's chained
# target, which then just does not qualify), which returns 0. ok_step() holds when F is a
# step record whose step id, heads, hosting, and session meet the write
# grammar, so a withheld placeholder or a record written before end heads
# never qualifies. ref() is the lookup line for the loaded record.
AWK_RECORD='
function load(p, optional,    line, r, t, k, n, parts, b) {
  split("", F); bad = 0
  n = split(p, parts, "/"); b = parts[n]; R_RUN = parts[n - 1]
  if (R_RUN !~ /^[0-9][0-9][0-9][0-9][0-9][0-9]$/) return 0
  if (b ~ /^[0-9][0-9][0-9]-suite\.rec$/) { R_KIND = "suite"; R_POINT = "" }
  else if (b ~ /^[0-9][0-9][0-9]-(step|done)-[a-z][a-z-]*\.rec$/) {
    R_KIND = substr(b, 5, 4); R_POINT = substr(b, 10, length(b) - 13)
  } else return 0
  R_SEQ = substr(b, 1, 3)
  while ((r = (getline line < p)) > 0) {
    t = index(line, TAB)
    if (!t) { bad = 1; continue }
    k = substr(line, 1, t - 1)
    if ((k in F) && k != "excerpt" && k != "warning" && k != "holder") bad = 1
    F[k] = substr(line, t + 1)
  }
  close(p)
  if (r < 0) { if (optional) return 0; err = 1; exit 2 }
  if (F["run"] != R_RUN || F["seq"] != R_SEQ || F["point"] != R_POINT \
    || F["type"] != (R_KIND == "done" ? "completion" : R_KIND == "suite" ? "full-suite" : "step")) bad = 1
  return 1
}
function hex(h) { return h ~ /^[0-9a-f]+$/ && (length(h) == 40 || length(h) == 64) }
function ok_step() {
  return !bad && R_KIND == "step" && F["type"] == "step" && F["step"] ~ /^[a-z][a-z0-9-]*$/ \
    && length(F["step"]) <= 64 && hex(F["head"]) && hex(F["end-head"]) \
    && F["hosting"] ~ /^(isolated|continue|in-session)$/ \
    && (F["session"] == "" || (F["session"] ~ /^[A-Za-z0-9._:-]+$/ && length(F["session"]) <= 128))
}
function ref() {
  return "record" TAB R_RUN ":" R_POINT ":" R_SEQ TAB F["step"] TAB F["head"] TAB F["end-head"] \
    TAB F["hosting"] TAB F["session"] TAB ".claude/steps/" R_RUN "/" R_SEQ "-step-" R_POINT ".rec"
}
'

# all_records: every run's record paths, oldest first, one a line in
# $work/records, each run checked in the main shell so a refusal ends the
# script. Readers take the list as a file, never as arguments or stdin, so
# neither the argument limit nor an empty cache changes what they read.
all_records() {
  scratch
  : >"$work/records" || die 1 "cannot write a temporary file"
  for r in $(run_ids); do
    check_run "$r"
    record_files "$r" >>"$work/records" || die 1 "cannot list the record cache"
  done
}

# render_run <run> [<point>...]: the tables, points in the order given or,
# given none, the order they first recorded.
render_run() {
  r=$1
  shift
  files=$(record_files "$r")
  [ -n "$files" ] || return 0
  want=''
  for _w in "$@"; do want="$want $_w"; done
  # shellcheck disable=SC2086 # split on newlines by design (IFS)
  awk -v run="$r" -v want="$want" -v TAB="$TAB" "$AWK_SAFE"'
    function short(h) { return substr(h, 1, 12) }
    # details(i): the pool, paths, and re-fire fields of record i, joined.
    function details(i,    d, j, hs) {
      d = ""
      if (F[i, "pool"] != "") {
        d = "pool `" safe(F[i, "pool"]) "`; waited " safe(F[i, "wait"]) " s"
        if (nh[i]) {
          hs = ""
          for (j = 1; j <= nh[i]; j++) hs = hs (j > 1 ? " / " : "") safe(H[i, j])
          d = d "; holders: " hs
        }
        if (F[i, "unpooled"] == "yes") d = d "; ran unpooled"
      }
      if (F[i, "fingerprint"] != "") {
        d = d (d == "" ? "" : "; ") "fingerprint " (F[i, "fingerprint"] == "none" ? "none" : "`" safe(short(F[i, "fingerprint"])) "`")
        d = d "; args digest `" safe(short(F[i, "args-digest"])) "`"
      }
      if (F[i, "refire-of"] != "") d = d (d == "" ? "" : "; ") "re-fire of `" safe(F[i, "refire-of"]) "`"
      return d
    }
    FNR == 1 { k++ }
    {
      t = index($0, TAB); key = substr($0, 1, t - 1); val = substr($0, t + 1)
      if (key == "excerpt") ex[k] = ex[k] (nx[k]++ ? " / " : "") safe(val)
      else if (key == "warning") { nw[k]++; W[k, nw[k]] = val }
      else if (key == "holder") { nh[k]++; H[k, nh[k]] = val }
      else F[k, key] = val
    }
    END {
      m = split(want, Q, " "); np = 0
      for (i = 1; i <= m; i++) if (!(Q[i] in named)) { named[Q[i]] = 1; P[++np] = Q[i] }
      if (np == 0) {
        for (i = 1; i <= k; i++) {
          if (F[i, "type"] == "full-suite" || (F[i, "point"] in seen)) continue
          seen[F[i, "point"]] = 1; P[++np] = F[i, "point"]
        }
      }
      first = 1
      for (p = 1; p <= np; p++) {
        pt = P[p]; any = 0
        for (i = 1; i <= k; i++) if (F[i, "type"] != "full-suite" && F[i, "point"] == pt) any = 1
        if (!any) continue
        if (!first) print ""
        first = 0
        printf "## Steps at `%s` (run `%s`)\n\n", safe(pt), safe(run)
        print "| # | Step | Kind | Target | Hosting | Backend | Session | Head | Start | End | Outcome | Excerpt | Output |"
        print "| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |"
        rows = 0; done = 0; nd = 0
        for (i = 1; i <= k; i++) {
          if (F[i, "type"] == "full-suite" || F[i, "point"] != pt) continue
          if (F[i, "type"] == "completion") { done = i; continue }
          rows++
          outc = F[i, "outcome"]
          if (outc == "skipped" && F[i, "skip-code"] != "") {
            outc = outc ": " F[i, "skip-code"]
            if (F[i, "stands-on"] != "") outc = outc " on " F[i, "stands-on"]
            if (F[i, "skip-reason"] != "") outc = outc " (" F[i, "skip-reason"] ")"
          } else if (outc == "skipped") outc = outc ": " F[i, "skip-reason"]
          hd = short(F[i, "head"])
          if (F[i, "end-head"] != "" && F[i, "end-head"] != F[i, "head"]) hd = hd " to " short(F[i, "end-head"])
          printf "| %d | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s |\n", rows,
            safe(F[i, "step"]), safe(F[i, "kind"]), safe(F[i, "target"]),
            safe(F[i, "hosting"]), safe(F[i, "backend"]), safe(F[i, "session"]),
            safe(hd), safe(F[i, "start"]), safe(F[i, "end"]),
            safe(outc), ex[i], safe(F[i, "output"])
          d = details(i)
          if (d != "") D[++nd] = "- Row " rows ": " d
        }
        if (rows == 0) print "| none | | | | | | | | | | | | |"
        if (nd) print ""
        for (j = 1; j <= nd; j++) print D[j]
        if (done) {
          printf "\nEnded on `%s`.\n", safe(short(F[done, "head"]))
          if (nw[done]) print ""
          for (j = 1; j <= nw[done]; j++) printf "- Warning: %s\n", safe(W[done, j])
        }
      }
      if (m) exit
      rows = 0
      for (i = 1; i <= k; i++) {
        if (F[i, "type"] != "full-suite") continue
        if (!rows++) {
          if (!first) print ""
          printf "## Full-suite runs (run `%s`)\n\n", safe(run)
          print "| # | Pool | Wait outcome | Waited (s) | Holders | Unpooled | Start | End |"
          print "| --- | --- | --- | --- | --- | --- | --- | --- |"
        }
        hs = ""
        for (j = 1; j <= nh[i]; j++) hs = hs (j > 1 ? " / " : "") safe(H[i, j])
        printf "| %d | %s | %s | %s | %s | %s | %s | %s |\n", rows, safe(F[i, "pool"]),
          safe(F[i, "wait-outcome"]), safe(F[i, "wait"]), hs, safe(F[i, "unpooled"]),
          safe(F[i, "start"]), safe(F[i, "end"])
      }
    }' $files || die 1 "cannot render the records"
}

cmd_render() {
  run='' points=''
  while [ $# -gt 0 ]; do
    case $1 in
      --run | --point) [ $# -ge 2 ] || usage ;;
      *) usage ;;
    esac
    case $1 in
      --run) run=$2 ;;
      --point)
        is_point "$2" || bad --point "not a point of the vocabulary"
        points="$points$2$LF"
        ;;
    esac
    shift 2
  done
  if [ -n "$run" ]; then
    valid_run "$run"
  else
    latest_run
    run=$LATEST
    [ -n "$run" ] || return 0
  fi
  # shellcheck disable=SC2086 # points are validated vocabulary words
  render_run "$run" $points
}

# --- regenerate ---------------------------------------------------------------------
cmd_regenerate() {
  base='' rhead='' run='' checklist_only=0
  while [ $# -gt 0 ]; do
    case $1 in
      --checklist-only)
        checklist_only=1
        shift
        continue
        ;;
      --base | --head | --run) [ $# -ge 2 ] || usage ;;
      *) usage ;;
    esac
    case $1 in
      --base) base=$2 ;;
      --head) rhead=$2 ;;
      --run) run=$2 ;;
    esac
    shift 2
  done
  [ -n "$base" ] || bad --base "required"
  [ -n "$rhead" ] || bad --head "required"
  case $base in -*) bad --base "a revision may not begin with a dash" ;; esac
  case $rhead in -*) bad --head "a revision may not begin with a dash" ;; esac
  if [ -n "$run" ]; then
    valid_run "$run"
  elif [ "$checklist_only" -eq 0 ]; then
    latest_run
    run=$LATEST
  fi
  command -v git >/dev/null 2>&1 || die 1 "git is not on PATH"
  git -C "$worktree" rev-parse --verify --quiet "$base^{commit}" >/dev/null \
    || die 1 "--base: cannot resolve $(sanitize_printable "$base" '(unprintable)') to a commit"
  git -C "$worktree" rev-parse --verify --quiet "$rhead^{commit}" >/dev/null \
    || die 1 "--head: cannot resolve $(sanitize_printable "$rhead" '(unprintable)') to a commit"

  # One git read for the whole range. Each commit opens with a marker line
  # carrying a per-run nonce no commit text can predict, then its sha, short
  # sha, parents, subject, sign-off ids, and rejected ids, one per line, then
  # its body.
  scratch
  nonce=$(od -An -N12 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n')
  [ -n "$nonce" ] || nonce="$$-$(date +%s)"
  marker="@@planwright-commit-$nonce@@"
  git -C "$worktree" -c core.abbrev=7 log --topo-order --reverse \
    --format="$marker%n%H%n%h%n%P%n%s%n%(trailers:key=Planwright-Sign-Off,valueonly,unfold,separator=%x20)%n%(trailers:key=Planwright-Sign-Off-Rejected,valueonly,unfold,separator=%x20)%n%b" \
    "$base..$rhead" -- >"$work/log" 2>/dev/null \
    || die 1 "--base/--head: git cannot read the range"
  clean "$work/log" "$work/log.clean"

  awk -v MARK="$marker" "$AWK_SAFE"'
    function after(x, y) { return late[x] > late[y] || (late[x] == late[y] && key[x] > key[y]) }
    $0 == MARK { n++; ln = 0; man[n] = 0; inman = 0; next }
    n == 0 { next }
    {
      ln++
      if (ln == 1) sha[n] = $0
      else if (ln == 2) short[n] = $0
      else if (ln == 3) merge[n] = (split($0, pp, " ") > 1)
      else if (ln == 4) subj[n] = $0
      else if (ln == 5) ids[n] = $0
      else if (ln == 6) rej[n] = $0
      else {
        if ($0 ~ /^This reverts commit [0-9a-f]+([.,]| \(|$)/) {
          s = substr($0, 21); match(s, /^[0-9a-f]+/); s = substr(s, 1, RLENGTH)
          if (length(s) >= 7) { nr[n]++; R[n, nr[n]] = s }
        }
        if (!(n in route) && substr($0, 1, 14) == "Route reason: ") route[n] = substr($0, 15)
        if (!(n in res) && substr($0, 1, 23) == "Base-merge resolution: ") res[n] = substr($0, 24)
        if ($0 ~ /^- / && index($0, "before:")) { man[n]++; M[n, man[n]] = substr($0, 3); inman = 1 }
        else if (inman && $0 ~ /^[ \t]+[^ \t]/ && man[n]) { s = $0; sub(/^[ \t]+/, "", s); M[n, man[n]] = M[n, man[n]] " " s }
        else inman = 0
      }
    }
    END {
      # A revert undoes its target only while it is itself live; walking
      # newest first settles a reverted revert before the commit it names.
      # An abbreviated sha names the one earlier commit it prefixes.
      # A revert whose rejected trailer names an id its target carries is a
      # partial revert: the trailer drops that one item, not the whole target.
      for (i = n; i >= 1; i--) {
        live[i] = !(i in undone)
        if (!live[i]) continue
        for (j = 1; j <= nr[i]; j++) {
          hit = 0; L = length(R[i, j])
          for (c = 1; c < i; c++) if (substr(sha[c], 1, L) == R[i, j]) { hit = hit ? -1 : c }
          if (hit <= 0) continue
          partial = 0; own = " " ids[hit] " "; gsub(/,/, " ", own)
          m = split(rej[i], r, /[ ,]+/)
          for (k = 1; k <= m; k++) if (r[k] ~ /^PS-[1-9][0-9]*$/ && index(own, " " r[k] " ")) partial = 1
          if (!partial) undone[hit] = 1
        }
      }
      for (i = 1; i <= n; i++) if (live[i]) {
        m = split(rej[i], r, /[ ,]+/)
        for (j = 1; j <= m; j++) rejected[r[j]] = 1
      }
      print "## Pending sign-off"
      print ""
      count = 0
      for (i = 1; i <= n; i++) {
        if (!live[i]) continue
        m = split(ids[i], r, /[ ,]+/); nid = 0
        for (j = 1; j <= m; j++) if (r[j] ~ /^PS-[1-9][0-9]*$/) cid[++nid] = r[j]
        s = subj[i]
        legacy = sub(/ ?\[pending-sign-off\]$/, "", s)
        if (nid == 0) {
          if (!legacy) continue
          nid = 1; cid[1] = "legacy"
        }
        shared[i] = ""; nd = 0
        for (j = 1; j <= nid; j++) if (!index(shared[i] " ", " " cid[j] " ")) { shared[i] = shared[i] " " cid[j]; nd++ }
        if (nd < 2) shared[i] = ""
        for (j = 1; j <= nid; j++) {
          id = cid[j]
          if (id != "legacy" && ((id in taken) || (id in rejected))) continue
          taken[id] = 1; rend[i, id] = 1
          count++
          late[count] = (id == "legacy"); key[count] = late[count] ? i : substr(id, 4) + 0
          entry[count] = i; eid[count] = id; esubj[count] = s; ord[count] = count
        }
      }
      # Insertion sort of the entry indices: numbered IDs by number, then
      # legacy entries in commit order.
      for (a = 2; a <= count; a++)
        for (b = a; b > 1 && after(ord[b - 1], ord[b]); b--) { t = ord[b]; ord[b] = ord[b - 1]; ord[b - 1] = t }
      if (count == 0) print "- none"
      else print "The approval act that lets the PR merge signs off every pending-sign-off item, never the ready flip; reject one before it by its printed recipe.\n"
      for (o = 1; o <= count; o++) {
        a = ord[o]; i = entry[a]
        printf "- **%s** %s · commit `%s`\n", eid[a], safe(esubj[a]), short[i]
        printf "  - Route reason: %s\n", ((i in route) ? safe(route[i]) : "not recorded in the commit")
        if (shared[i] != "") {
          # Only siblings still listed from this commit: a rejected one, or
          # one an older commit owns, no longer sits beside this entry.
          m = split(shared[i], r, " "); s = ""
          for (j = 1; j <= m; j++) if (r[j] != eid[a] && ((i, r[j]) in rend)) s = s (s == "" ? "" : ", ") r[j]
          if (s == "") print "  - Shared commit: its other findings were rejected"
          else printf "  - Shared commit: also carries %s\n", s
        }
        for (j = 1; j <= man[i]; j++) printf "  - %s\n", safe(M[i, j])
        # A base-merge resolution the sync committed under `resolve`: the
        # resolution, not the merged base, is what awaits sign-off, and a
        # revert would restore the conflict.
        if (merge[i] && (i in res) && eid[a] != "legacy") {
          printf "  - Base-merge resolution: %s; the agent resolved these conflicts, so review the resolution\n", safe(res[i])
          printf "  - Reject with: set `worker_merge_conflict_policy: halt`, so a re-run of `scripts/converge-sync-main.sh` parks instead of resolving, and land your own resolution of those paths in a commit carrying `Planwright-Sign-Off-Rejected: %s`, never a revert\n", eid[a]
        }
        else if (shared[i] != "" && !merge[i]) printf "  - Reject with: a commit undoing its part, carrying `Planwright-Sign-Off-Rejected: %s`\n", eid[a]
        else if (merge[i] && eid[a] != "legacy") printf "  - Reject with: a later commit carrying `Planwright-Sign-Off-Rejected: %s`\n", eid[a]
        else if (merge[i]) printf "  - Reject with: `git revert -m 1 %s`\n", short[i]
        else if (man[i]) printf "  - Reject with: `git revert %s`; rejecting one sub-item is a hand edit the manifest guides\n", short[i]
        else printf "  - Reject with: `git revert %s`\n", short[i]
      }
    }' "$work/log.clean" || die 1 "cannot render the checklist"

  if [ "$checklist_only" -eq 0 ] && [ -n "$run" ]; then
    render_run "$run" >"$work/render" || exit 1
    if [ -s "$work/render" ]; then
      printf '\n'
      cat "$work/render"
    fi
  fi
}

# --- status --------------------------------------------------------------------------
is_repo() {
  case $1 in */*/* | -* | */-* | */ | /*) return 1 ;; */*) ;; *) return 1 ;; esac
  _owner=${1%%/*} _name=${1#*/}
  case $_owner in *[!A-Za-z0-9-]*) return 1 ;; esac
  case $_name in . | .. | *[!A-Za-z0-9._-]*) return 1 ;; esac
  [ "${#_owner}" -le 39 ] && [ "${#_name}" -le 100 ]
}

cmd_status() {
  point='' head='' repo='' head_given=0
  while [ $# -gt 0 ]; do
    case $1 in
      --point | --head | --repo) [ $# -ge 2 ] || usage ;;
      *) usage ;;
    esac
    case $1 in
      --point) point=$2 ;;
      --head)
        head=$2
        head_given=1
        ;;
      --repo) repo=$2 ;;
    esac
    shift 2
  done
  case $point in pre-ready-flip | pre-spec-ready-flip) ;; *) bad --point "not a flip point" ;; esac
  [ "$head_given" -eq 1 ] || set_head_from_worktree
  is_head "$head" || bad --head "not a full commit id"
  is_repo "$repo" || bad --repo "not an <owner>/<name> repository"

  # One pass over every run's records: the latest attempt (the highest run
  # holding a well-formed completion of the point naming the head), each run's
  # outcomes at the point, and any unretired limited record ending on the
  # head, whatever run or point holds it.
  all_records
  result=$(awk -v TAB="$TAB" -v H="$head" -v P="$point" "$AWK_RECORD"'
    {
      if (!load($0)) next
      if (R_KIND == "done") {
        if (R_POINT != P) next
        if (!bad && F["head"] == H && R_RUN + 0 > A + 0) A = R_RUN
        # A malformed completion names no head it can be trusted on.
        if ((bad || !hex(F["head"])) && R_RUN + 0 > B + 0) B = R_RUN
        next
      }
      if (R_KIND != "step") next
      if (R_POINT == P) {
        if (F["outcome"] == "limited" && !bad) LIM[R_RUN] = 1
        else if (bad || F["outcome"] !~ /^(passed|applied|skipped)$/) HF[R_RUN] = 1
      }
      if (F["end-head"] != H) next
      if (F["outcome"] == "limited") {
        n++; LR[n] = R_RUN + 0; LS[n] = ok_step() ? F["step"] : ""
      } else if (ok_step() && (F["outcome"] == "passed" || F["outcome"] == "applied" \
        || (F["outcome"] == "skipped" && F["skip-code"] == "resume"))) {
        if (!(F["step"] in last) || R_RUN + 0 > last[F["step"]]) last[F["step"]] = R_RUN + 0
      }
    }
    END {
      if (err) exit 2
      if (A == "") { print "none"; exit }
      if (B + 0 > A + 0) { print "malformed " B; exit }
      c = 0
      for (i = 1; i <= n; i++) if (LS[i] == "" || !(LS[i] in last) || last[LS[i]] <= LR[i]) c++
      print ((A in HF) ? "halted-or-failed" : ((A in LIM) || c) ? "limited" : "clean") " " A
    }' "$work/records") || die 1 "cannot read the record cache"
  verdict=${result% *} attempt=${result##* }
  [ "$verdict" != none ] || die 1 "no completion record of $point names $head; refusing to post a status"
  context="planwright/$point"
  case $verdict in
    halted-or-failed)
      state=failure
      description="$point: a step halted or failed (run $attempt)"
      ;;
    limited)
      state=failure
      description="$point: a step stayed limited (run $attempt)"
      ;;
    malformed)
      state=failure
      description="$point: a later completion record is malformed (run $attempt)"
      ;;
    clean)
      state=success
      description="$point: no step halted or failed (run $attempt)"
      ;;
    *) die 1 "cannot read the record cache" ;;
  esac

  command -v gh >/dev/null 2>&1 || die 1 "gh is not on PATH; cannot post the $context status"
  scratch
  if ! gh api --method POST "repos/$repo/statuses/$head" -f "state=$state" \
    -f "context=$context" -f "description=$description" >/dev/null 2>"$work/gh.err"; then
    why=$(head -n 1 "$work/gh.err")
    why=$(sanitize_printable "$why" 'no error text')
    die 1 "cannot post the $context status on $head in $repo ($why); if the cause is a missing permission, the login needs commit-status write access: repo:status on a classic token, or Commit statuses write on a fine-grained token or app"
  fi
  printf 'posted\t%s\t%s\t%s\n' "$context" "$state" "$head" || die 1 "cannot print the posted status"
}

# --- fingerprint ------------------------------------------------------------------
cmd_fingerprint() {
  [ $# -eq 2 ] && [ "$1" = --paths ] || usage
  words=$2
  set --
  IFS=' '
  for w in $words; do set -- "$@" "$w"; done
  IFS=$LF
  [ $# -ge 1 ] || bad --paths "names no path word"
  for w in "$@"; do
    case $w in /* | -* | *[!A-Za-z0-9._/-]*) bad --paths "a word outside the path grammar" ;; esac
    case /$w/ in */../*) bad --paths "a word holding a .. segment" ;; esac
  done
  read_worktree_head
  case $? in
    0) ;;
    1) die 1 "the worktree is not the top of a git work tree; cannot fingerprint" ;;
    2) die 1 "the worktree has no commit to fingerprint at" ;;
    *) die 1 "git cannot read the worktree's HEAD" ;;
  esac
  scratch
  # No fingerprint when anything under a word differs from HEAD, including a
  # file git is told to stop looking at (skip-worktree, or assume-unchanged,
  # whose ls-files tag is lowercase), which status would not report.
  git_wt status --porcelain --untracked-files=all --ignore-submodules=none -- "$@" >"$work/status" 2>/dev/null \
    || die 1 "git cannot read the work tree's status"
  git_wt ls-files -v -- "$@" >"$work/tags" 2>/dev/null || die 1 "git cannot read the index"
  if [ -s "$work/status" ] || grep -q '^[a-zS]' "$work/tags"; then
    printf 'none\n' || die 1 "cannot print the fingerprint"
    return 0
  fi
  : >"$work/fp" || die 1 "cannot write a temporary file"
  for w in "$@"; do
    # The word's path with empty and `.` segments dropped, as git reads it;
    # a word reaching through a symbolic link names content git does not
    # hold at that path, so it leaves no fingerprint.
    norm=''
    IFS=/
    for c in $w; do
      case $c in '' | .) ;; *) norm="$norm${norm:+/}$c" ;; esac
    done
    IFS=$LF
    p=$norm
    while :; do
      case $p in */*) ;; *) break ;; esac
      p=${p%/*}
      if [ -L "$worktree/$p" ]; then
        printf 'none\n' || die 1 "cannot print the fingerprint"
        return 0
      fi
    done
    if [ -z "$norm" ]; then
      oid=$(git_wt rev-parse --verify --quiet "$WT_HEAD^{tree}" 2>/dev/null) \
        || die 1 "git cannot read the tree at HEAD"
    else
      git_wt ls-tree "$WT_HEAD" -- "$norm" >"$work/entry" 2>/dev/null \
        || die 1 "git cannot read a declared path at HEAD"
      oid=$(awk -v n="$norm" -v TAB="$TAB" '
        { t = index($0, TAB); if (substr($0, t + 1) == n) { split(substr($0, 1, t - 1), m, " "); print m[3] } }' \
        "$work/entry") || die 1 "cannot read a declared path's entry"
      if [ -z "$oid" ]; then
        # Absent at HEAD yet present here and not ignored, or on a
        # case-insensitive checkout at all: a spelling the file system may
        # fold onto another path, whose content the absent marker would not
        # track.
        if [ -e "$worktree/$norm" ] || [ -L "$worktree/$norm" ]; then
          if [ "$(git_wt config --bool core.ignorecase 2>/dev/null)" = true ]; then
            _ign=1
          else
            GW_LITERAL=0 git_wt check-ignore -q -- "$norm" 2>/dev/null
            _ign=$?
          fi
          case $_ign in
            0) ;;
            1)
              printf 'none\n' || die 1 "cannot print the fingerprint"
              return 0
              ;;
            *) die 1 "git cannot read the ignore rules" ;;
          esac
        fi
        oid=-
      fi
    fi
    printf '%s\t%s\n' "$w" "$oid" >>"$work/fp" || die 1 "cannot write a temporary file"
  done
  git_wt hash-object --stdin <"$work/fp" || die 1 "git cannot hash the fingerprint"
}

# --- lookup -------------------------------------------------------------------------
cmd_lookup() {
  [ $# -ge 1 ] || usage
  mode=$1
  shift
  case $mode in
    reuse) lookup_reuse "$@" ;;
    resume) lookup_resume "$@" ;;
    *) usage ;;
  esac
}

# lookup_print <awk-status> <line>: the lookup's ending, by the reader's
# status: 0 prints the line, 3 is no match, anything else a read failure.
lookup_print() {
  case $1 in
    0) printf '%s\n' "$2" || die 1 "cannot print the lookup" ;;
    3) exit 3 ;;
    *) die 1 "cannot read the record cache" ;;
  esac
}

lookup_reuse() {
  step='' target='' args_digest='' fingerprint=''
  while [ $# -gt 0 ]; do
    case $1 in
      --step | --target | --args-digest | --fingerprint) [ $# -ge 2 ] || usage ;;
      *) usage ;;
    esac
    case $1 in
      --step) step=$2 ;;
      --target) target=$2 ;;
      --args-digest) args_digest=$2 ;;
      --fingerprint) fingerprint=$2 ;;
    esac
    shift 2
  done
  is_step_id "$step" || bad --step "not a step id"
  is_text "$target" || bad --target "must be non-empty single-line text of at most $TEXT_MAX bytes"
  is_sha256 "$args_digest" || bad --args-digest "not a SHA-256 digest"
  [ "$fingerprint" = none ] || is_oid "$fingerprint" || bad --fingerprint "not none or a fingerprint"
  [ "$fingerprint" != none ] || exit 3
  # The target as write stores it; one the screen withheld was stored as its
  # placeholder, and a record holding a placeholder matches nothing.
  clean_value "$target"
  all_records
  hit=$(LOOKUP_TARGET=$CLEANED awk -v TAB="$TAB" -v S="$step" -v D="$args_digest" \
    -v FP="$fingerprint" "$AWK_RECORD"'
    {
      if (!load($0) || !ok_step() || index(F["target"], "[withheld: ") == 1) next
      if (F["outcome"] == "passed" && F["step"] == S && F["target"] == ENVIRON["LOOKUP_TARGET"] \
        && F["args-digest"] == D && F["fingerprint"] == FP) hit = ref()
    }
    END { if (err) exit 2; if (hit == "") exit 3; print hit }' "$work/records")
  lookup_print $? "$hit"
}

lookup_resume() {
  run='' point='' head='' head_given=0
  while [ $# -gt 0 ]; do
    case $1 in
      --run | --point | --head) [ $# -ge 2 ] || usage ;;
      *) usage ;;
    esac
    case $1 in
      --run) run=$2 ;;
      --point) point=$2 ;;
      --head)
        head=$2
        head_given=1
        ;;
    esac
    shift 2
  done
  is_in_run_point "$point" || bad --point "not an in-run point"
  valid_run "$run"
  [ "$head_given" -eq 1 ] || set_head_from_worktree
  is_head "$head" || bad --head "not a full commit id"
  # Every run is checked, since a resume skip's record may sit in any.
  all_records
  record_files "$run" >"$work/run-records" || die 1 "cannot list the record cache"
  out=$(CACHE_DIR=$cache awk -v TAB="$TAB" -v P="$point" -v H="$head" "$AWK_RECORD"'
    {
      if (stop || !load($0) || R_KIND != "step" || R_POINT != P) next
      if (!ok_step() || F["end-head"] != H) { stop = 1; next }
      if (F["outcome"] == "skipped" && F["skip-code"] == "resume" \
        && F["stands-on"] ~ /^[0-9][0-9][0-9][0-9][0-9][0-9]:[a-z][a-z-]*:[0-9][0-9][0-9]$/) {
        # A resume skip stands for the record it names, which must itself
        # qualify, as the same step on the same head.
        s = F["step"]; split(F["stands-on"], q, ":")
        if (!load(ENVIRON["CACHE_DIR"] "/" q[1] "/" q[3] "-step-" q[2] ".rec", 1) || !ok_step() \
          || F["step"] != s || F["end-head"] != H) { stop = 1; next }
      }
      if (F["outcome"] != "passed" && F["outcome"] != "applied") { stop = 1; next }
      print ref(); found = 1
    }
    END { if (err) exit 2; if (!found) exit 3 }' "$work/run-records")
  lookup_print $? "$out"
}

command -v iconv >/dev/null 2>&1 || die 1 "iconv is not on PATH"
check_dir "$worktree/.claude"
check_dir "$cache"
if command -v git >/dev/null 2>&1 && [ -d "$cache" ]; then
  tracked=$(git -C "$worktree" ls-files -- .claude/steps 2>/dev/null) || tracked=''
  [ -z "$tracked" ] || die 1 "git tracks the record cache; refusing it"
fi

case $verb in
  status) cmd_status "$@" ;;
  new-run) cmd_new_run "$@" ;;
  write) cmd_write "$@" ;;
  list) cmd_list "$@" ;;
  render) cmd_render "$@" ;;
  regenerate) cmd_regenerate "$@" ;;
  fingerprint) cmd_fingerprint "$@" ;;
  lookup) cmd_lookup "$@" ;;
  *) usage ;;
esac
