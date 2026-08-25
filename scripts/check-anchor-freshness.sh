#!/bin/sh
# check-anchor-freshness.sh — the standing anchor-freshness guard
# (anchor-integrity Task 4; REQ-D1.1, REQ-D1.2, REQ-D1.3, REQ-D1.4, REQ-D1.5;
# D-6). One script, two wirings: the normative whole-corpus form inside
# `mise run check` (the merge gate), and a best-effort lefthook pre-commit
# mirror scoped to commits that stage `specs/**` (lefthook.yml).
#
# It asserts two properties over every non-Draft, non-terminal bundle:
#
#   1. Recompute (REQ-D1.1). The bundle's kickoff brief carries a most-recent
#      anchor entry that parses, uses a sanctioned command form
#      (doctrine/spec-format.md, *Sanctioned command forms*), and recomputes
#      equal against the checked tree.
#   2. Changelog pairing (REQ-D1.2). An edit to ANCHORED content since the
#      baseline ref carries a dated `## Changelog` entry somewhere in the same
#      bundle — the out-of-flow edit class, where a signed bundle was edited
#      without the ritual that records why. Edits are detected through the
#      canonical extraction, so a change confined to excluded content (a header
#      `**Status:**` flip, a tasks.md state annotation, a block move between
#      sections) never flags.
#
# Skip and error semantics (REQ-D1.4):
#   * Draft bundles and terminal ones (Retired, Superseded) are skipped with a
#     notice — frozen or unsigned history whose briefs never grow machine
#     entries.
#   * A non-Draft, non-terminal bundle with NO kickoff brief is an error naming
#     the repair remedy, never a silent skip: deleting a brief must not disable
#     the check.
#   * A bundle carrying the live `anchor re-review pending` marker in its
#     tasks.md `## Awaiting input` section (the REQ-A1.4 park for a
#     meaning-class delta routed to its re-review ritual) reports its recompute
#     failure as a known-parked NOTICE, so one routed bundle cannot red the
#     merge gate repo-wide. The park covers the recompute arm only: an
#     unpaired out-of-flow edit is still an error there, since the park says
#     "this anchor awaits a re-review", not "edits to this bundle need no
#     record".
#
# Execution safety (REQ-D1.5). A recorded command is DATA. It is matched
# against the sanctioned grammar and the tool is then invoked with a parsed,
# containment-checked `<spec-dir>` argument — never evaluated, so an injected
# suffix, a substitution, or an out-of-tree argument is refused with no
# execution side effect. Diagnostics echo parsed content only through the
# grammar lib's canonical sanitizer, and a `--baseline` value is screened
# against the ref grammar and rev-parse-validated before any use.
#
# Usage: check-anchor-freshness.sh [--baseline <ref>] [<specs-root>]
#   <specs-root>   defaults to the repo's specs/ directory (the CI entry point).
#   --baseline     the pairing check's comparison ref; defaults to origin/main
#                  (the sibling checks' convention), compared at its merge base
#                  with HEAD so a baseline branch that moved ahead never reads
#                  as an unpaired local edit. An unresolvable DEFAULT degrades
#                  the pairing check to a skip with a notice; an explicit
#                  --baseline that cannot be used is fatal.
#
# Exit codes: 0 clean (ok and notice records only), 1 one or more errors,
# 2 usage error, an unusable explicit baseline, or a broken install (a missing
# or unreadable scripts/spec-parse.sh, the shared grammar lib).
#
# Every bundle is always visited: one failure never hides another, and the
# printed table is the artifact.
#
# Portable POSIX sh + awk + git; bash 3.2 / BSD tooling floor, no eval.
set -u

# Pin the C locale: the byte ranges and bracket expressions below are
# collation-dependent under UTF-8 locales.
LC_ALL=C
export LC_ALL

# A CDPATH-resolved cd would echo the destination into the command
# substitutions below and corrupt every derived path.
unset CDPATH 2>/dev/null || true

script_dir=$(cd "$(dirname "$0")" && pwd -P) || exit 2
repo_root=$(cd "$script_dir/.." && pwd -P) || exit 2

# The shared spec-parse grammar lib: the header-block Status parse and the
# stderr sanitizer come from it, so this guard's notion of "the header block"
# cannot diverge from spec-anchor.sh's. Sourced, never executed; fail closed
# when it is missing or unreadable.
spec_parse_sh="$script_dir/spec-parse.sh"
if [ ! -f "$spec_parse_sh" ] || [ ! -r "$spec_parse_sh" ]; then
  lib_disp=$(printf '%s' "$spec_parse_sh" | tr -d '\000-\037\177\200-\237')
  [ -n "$lib_disp" ] || lib_disp='(unprintable path)'
  printf '%s\n' "check-anchor-freshness: spec-parse.sh missing or unreadable: $lib_disp" >&2
  exit 2
fi
# shellcheck source=scripts/spec-parse.sh
. "$spec_parse_sh" || exit 2

usage() {
  echo "usage: check-anchor-freshness.sh [--baseline <ref>] [<specs-root>]" >&2
  exit 2
}

baseline=origin/main
explicit_baseline=0
specs_root=
while [ $# -gt 0 ]; do
  case $1 in
    --baseline)
      [ $# -ge 2 ] || usage
      baseline=$2
      explicit_baseline=1
      shift 2
      ;;
    -*) usage ;;
    *)
      [ -z "$specs_root" ] || usage
      specs_root=$1
      shift
      ;;
  esac
done
[ -n "$specs_root" ] || specs_root="$repo_root/specs"
# Keep the value as the caller gave it for diagnostics. The strip below empties
# a path that is nothing but slashes, and the sanitizer renders an empty string
# as "(unprintable path)" — which would report a perfectly printable `/` as
# unprintable and name nothing the caller typed.
specs_root_given=$specs_root
while [ "$specs_root" != "${specs_root%/}" ]; do specs_root=${specs_root%/}; done
if [ ! -d "$specs_root" ]; then
  printf '%s\n' "check-anchor-freshness: not a directory: $(spec_parse_printable "$specs_root_given")" >&2
  exit 2
fi
specs_root=$(cd "$specs_root" && pwd -P) || exit 2

# The checked tree is what the corpus sits in: its own scripts/spec-anchor.sh
# wins over any ambient root (doctrine/spec-format.md, *Resolving the recorded
# command*), and its git view is what the pairing check diffs against.
tree_root=$(cd "$specs_root/.." && pwd -P) || exit 2

# `--baseline` screen (REQ-D1.5). A ref reaches `git` as a single argument and
# is never interpolated, but a value that begins with `-` would still be read
# as an option, and one carrying whitespace or control bytes is not a ref at
# all. Screen the byte set FIRST, so nothing outside it ever reaches git.
if [ "$explicit_baseline" -eq 1 ]; then
  case $baseline in
    '' | -*)
      echo "check-anchor-freshness: --baseline value is empty or begins with '-'" >&2
      exit 2
      ;;
    *[!A-Za-z0-9._/^~@{}-]*)
      # Never echo the candidate back: a hostile value must not reach any
      # output a caller might interpolate.
      echo "check-anchor-freshness: --baseline value is not a plain ref (allowed: A-Z a-z 0-9 . _ / ^ ~ @ { } -)" >&2
      exit 2
      ;;
  esac
  [ "${#baseline}" -le 256 ] || {
    echo "check-anchor-freshness: --baseline value is too long" >&2
    exit 2
  }
fi

wtmp=$(mktemp -d) || exit 2
trap 'rm -rf "$wtmp"' EXIT

# --- the anchor tool ----------------------------------------------------
#
# resolve_anchor_tool — print the reference implementation's path, preferring
# the checked tree's own script and falling back to the core root chain only
# where it is absent (doctrine/spec-format.md, *Sanctioned command forms* arm
# list and *Resolving the recorded command*). An arm whose root is unset or
# empty is SKIPPED, never expanded into a bare `/scripts/...` path. Resolution
# finds the same tool for both script-based forms; it never rewrites the
# recorded form.
resolve_anchor_tool() {
  rat_claude_dir=${CLAUDE_DIR:-}
  if [ -z "$rat_claude_dir" ] && [ -n "${HOME:-}" ]; then
    rat_claude_dir="$HOME/.claude"
  fi
  for rat_cand in \
    "$tree_root/scripts" \
    "${PLANWRIGHT_ROOT:-}${PLANWRIGHT_ROOT:+/scripts}" \
    "${CLAUDE_PLUGIN_ROOT:-}${CLAUDE_PLUGIN_ROOT:+/scripts}" \
    "${rat_claude_dir:-}${rat_claude_dir:+/planwright/scripts}" \
    "$script_dir"; do
    [ -n "$rat_cand" ] || continue
    if [ -f "$rat_cand/spec-anchor.sh" ] && [ -x "$rat_cand/spec-anchor.sh" ]; then
      printf '%s\n' "$rat_cand/spec-anchor.sh"
      return 0
    fi
  done
  return 1
}
anchor_tool=$(resolve_anchor_tool) || anchor_tool=

# --- recompute ----------------------------------------------------------
#
# recompute <recorded-command> <spec-dir> <bundle-name> — recompute the anchor
# with the form ON RECORD (a consumer never substitutes a different form),
# printing the hash on success. On failure it prints nothing and returns:
#   1  the recorded string is outside the sanctioned grammar, names another
#      bundle, or carries an injected suffix / substitution / out-of-tree path;
#   3  a sanctioned script form whose tool resolves to nothing — the
#      fail-closed absent-anchor class, never read as a match;
#   4  the tool ran and failed (a malformed header block, an unreadable file).
recompute() {
  rc_cmd=$1
  rc_dir=$2
  rc_name=$3

  # The interim whole-file form is a fixed literal that invokes git directly
  # and needs no resolution. Matching the literal IS the validation; the
  # pipeline below is this script's own, not the recorded string run.
  if [ "$rc_cmd" = "git hash-object requirements.md design.md tasks.md test-spec.md | git hash-object --stdin" ]; then
    (
      cd "$rc_dir" || exit 4
      git hash-object requirements.md design.md tasks.md test-spec.md \
        | git hash-object --stdin
    ) || return 4
    return 0
  fi

  # The two script forms. Everything after the last space is the candidate
  # argument; re-composing the command from it and comparing against the
  # original is what rejects a suffix (`...; touch x`) — the recomposed string
  # differs the moment anything follows the argument.
  rc_arg=${rc_cmd##* }
  case $rc_cmd in
    "scripts/spec-anchor.sh $rc_arg" | "spec-anchor.sh $rc_arg") ;;
    *) return 1 ;;
  esac
  # The argument must be a plain `specs/<identifier>` (REQ-A1.8) before it is
  # read any further: it reaches a case pattern below, where an unvalidated
  # glob byte would widen the containment check instead of being compared by
  # it. This is also what refuses a substitution and an out-of-tree path.
  case $rc_arg in
    specs/*) rc_id=${rc_arg#specs/} ;;
    *) return 1 ;;
  esac
  case $rc_id in
    '' | */* | *[!a-z0-9-]* | [!a-z0-9]*) return 1 ;;
  esac
  # Containment: the recorded argument must name the bundle being checked. An
  # entry copied from another bundle is not a recompute of this one.
  [ "$rc_id" = "$rc_name" ] || return 1

  [ -n "$anchor_tool" ] || return 3
  "$anchor_tool" "$rc_dir" 2>/dev/null || return 4
}

# --- the park marker ----------------------------------------------------
#
# parked_marker <tasks.md> — succeeds when a live `anchor re-review pending`
# bullet sits in the `## Awaiting input` section. Section-scoped on purpose:
# the same words in prose, or in another section, are a note, not a park.
parked_marker() {
  [ -f "$1" ] || return 1
  awk '
    /^## / { in_sec = ($0 ~ /^## Awaiting input/) ; next }
    in_sec && /^- / && /anchor re-review pending/ { found = 1 }
    END { exit(found ? 0 : 1) }
  ' "$1"
}

# --- the brief's most recent anchor entry -------------------------------
#
# latest_anchor_entry <brief> — print `<hash><TAB><command>` for the brief's
# most recent (last-appended) anchor entry. Both recorded layouts are read: the
# canonical two-line form, and the single-line parenthesized variant.
#
# An `Anchor:` line is held PENDING and resolved when the following record
# arrives, rather than pulled in with `getline`. The distinction matters where
# the two layouts meet: a `getline` consumes the next line unconditionally, so
# a single-line entry immediately followed by another `Anchor:` line swallows
# that neighbour and the walk reads every other entry — silently anchoring on
# an older hash. Holding the line instead lets an adjacent `Anchor:` both close
# the pending entry and open its own.
latest_anchor_entry() {
  awk '
    # resolve <line> <nextline> — record the entry if both halves parsed. The
    # trailing parameters are awk local scratch, not arguments.
    function resolve(line, nextline,   hash, scratch, n, tok, i, cmd) {
      # Blank out every non-hex byte and take the one 40-char run: an interval
      # expression would say this in one pattern, but old BSD awks do not read
      # them, and a bare /[0-9a-f]+/ matches the "c" in "Anchor" first.
      hash = ""
      scratch = line
      gsub(/[^0-9a-f]/, " ", scratch)
      n = split(scratch, tok, " ")
      for (i = 1; i <= n; i++) {
        if (length(tok[i]) == 40) { hash = tok[i]; break }
      }
      # The canonical layout backticks the hash on this line and carries the
      # command alone on the next; the parenthesized variant carries it here.
      cmd = ""
      if (match(line, /\(`[^`]+`\)/)) {
        cmd = substr(line, RSTART + 2, RLENGTH - 4)
      } else if (match(nextline, /^`[^`]+`$/)) {
        cmd = substr(nextline, 2, length(nextline) - 2)
      }
      if (hash != "" && cmd != "") { best_hash = hash; best_cmd = cmd }
    }
    # Order is load-bearing: a pending entry closes against this record BEFORE
    # the record is itself considered as a new entry, so an adjacent pair does
    # both in one pass.
    pending != "" { resolve(pending, $0); pending = "" }
    /^Anchor:/ { pending = $0 }
    END {
      # A brief ending on its anchor line has no following record; the
      # parenthesized layout still carries the command, the canonical one does
      # not and stays unparsed.
      if (pending != "") { resolve(pending, "") }
      if (best_hash == "") { exit 1 }
      printf "%s\t%s\n", best_hash, best_cmd
    }
  ' "$1"
}

# --- dated changelog entries --------------------------------------------
#
# changelog_entries <dir> <out-file> — collect the bundle's dated `## Changelog`
# bullets, one `<file>|<line>` record apiece, sorted. The file prefix keeps two
# bundles' identically-worded entries apart across the four files. Section
# scoped: a dated bullet elsewhere in a spec file is not a changelog entry.
changelog_entries() {
  ce_dir=$1
  : >"$2"
  for ce_f in requirements.md design.md tasks.md test-spec.md; do
    [ -f "$ce_dir/$ce_f" ] || continue
    awk -v file="$ce_f" '
      /^## / { in_ch = ($0 ~ /^## Changelog[ \t]*$/) ; next }
      in_ch && /^- [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/ {
        printf "%s|%s\n", file, $0
      }
    ' "$ce_dir/$ce_f"
  done | sort -u >"$2"
}

# --- the baseline view --------------------------------------------------
#
# The pairing check needs the bundle as it stood at the baseline ref. Resolve
# the git view once: an unusable DEFAULT baseline degrades the whole pairing
# check to a skip with a notice (the sibling validator's convention), while an
# explicit one that cannot be used is fatal.
git_top=
pairing=on
pairing_note=
if ! git_top=$(git -C "$tree_root" rev-parse --show-toplevel 2>/dev/null); then
  if [ "$explicit_baseline" -eq 1 ]; then
    echo "check-anchor-freshness: --baseline given but the checked tree is not in a git work tree" >&2
    exit 2
  fi
  pairing=off
  pairing_note="not a git work tree"
elif ! git -C "$tree_root" rev-parse --verify --quiet "$baseline^{commit}" >/dev/null 2>&1; then
  if [ "$explicit_baseline" -eq 1 ]; then
    printf '%s\n' "check-anchor-freshness: baseline ref does not resolve: $(spec_parse_printable "$baseline")" >&2
    exit 2
  fi
  pairing=off
  pairing_note="baseline ref $baseline does not resolve"
fi
base_commit=$baseline
if [ "$pairing" = on ]; then
  git_top=$(cd "$git_top" && pwd -P) || exit 2
  # Compare against the MERGE BASE, not the ref tip. The question this check
  # asks is "what did this branch edit without recording it", and a bare tip
  # comparison answers a different one: every bundle the baseline branch
  # changed since the fork point reads as an unpaired local edit, so the guard
  # would go red on work this tree never touched the moment `main` moved ahead.
  # The kickoff brief pins the convention as effectively merge-base with main.
  # An unrelated or missing HEAD leaves the ref itself as the baseline.
  if mb=$(git -C "$git_top" merge-base "$baseline" HEAD 2>/dev/null) && [ -n "$mb" ]; then
    base_commit=$mb
  fi
  if [ -z "$anchor_tool" ]; then
    # The pairing check detects edits through the CANONICAL extraction, so it
    # needs the reference implementation even when an entry recorded another
    # sanctioned form.
    pairing=off
    pairing_note="the anchor tool did not resolve"
  fi
fi

ok=0
notice=0
error=0
seen=0

record() {
  # $1 verdict, $2 bundle, $3 detail. Bundle names and parsed content are
  # sanitized: both are untrusted input headed for a terminal (REQ-D1.5).
  printf 'check-anchor-freshness: %-6s %s — %s\n' \
    "$1" "$(spec_parse_printable "$2")" "$3"
}
say_ok() {
  ok=$((ok + 1))
  record ok "$1" "$2"
}
say_notice() {
  notice=$((notice + 1))
  record notice "$1" "$2"
}
say_error() {
  error=$((error + 1))
  record ERROR "$1" "$2"
}

# report_recompute <bundle> <parked> <detail> — a recompute failure is a
# known-parked notice on a parked bundle (its gate stays failed closed until
# the re-review signs off; REQ-D1.1) and an error otherwise.
report_recompute() {
  if [ "$2" = yes ]; then
    say_notice "$1" "known-parked (anchor re-review pending): $3"
  else
    say_error "$1" "$3"
  fi
}

for dir in "$specs_root"/*/; do
  name=${dir%/}
  name=${name##*/}
  # Underscore-prefixed directories are accumulators (_observations,
  # _pending), not spec bundles.
  case $name in
    _*) continue ;;
  esac
  [ -f "$dir/requirements.md" ] || continue
  seen=$((seen + 1))

  # Screen the bundle name against the spec-identifier grammar (REQ-A1.8)
  # before it reaches a recorded command's containment check or a `<ref>:<path>`
  # argument. Fail closed and name the real cause: without this, an off-grammar
  # directory would fail the containment check instead and report as a
  # non-sanctioned command form, blaming the brief for the directory's fault.
  case $name in
    '' | *[!a-z0-9-]* | [!a-z0-9]*)
      say_error "$name" \
        "not a valid spec identifier (^[a-z0-9][a-z0-9-]*\$); the bundle cannot be checked — remedy: rename it per the validator's rule"
      continue
      ;;
  esac
  [ "${#name}" -le 64 ] || {
    say_error "$name" "spec identifier longer than 64 characters; the bundle cannot be checked"
    continue
  }

  # An unparseable status (unreadable file, duplicate declaration) is a fact
  # about the bundle, not a reason to abandon the walk.
  status=$(spec_parse_header_value "$dir/requirements.md" Status 2>/dev/null) || status=""
  if [ -z "$status" ]; then
    say_error "$name" "no parseable header-block Status declaration in requirements.md"
    continue
  fi
  # The lib returns declaration values RAW (its own header says so), and the
  # in-scope arm below echoes the status back — an arbitrary parsed string, not
  # one of the matched literals. Sanitize once here so every diagnostic that
  # quotes it is covered (REQ-D1.5 echo discipline).
  # (The lib's own no-printable-bytes fallback reads "(unprintable path)". Odd
  # wording for a status, but a status of nothing but control bytes is
  # pathological, and copying the byte range here to reword it is the
  # duplication the exported sanitizer exists to prevent.)
  status_disp=$(spec_parse_printable "$status")
  case $status in
    Draft)
      say_notice "$name" "Draft — skipped (unsigned; briefs grow no machine entries yet)"
      continue
      ;;
    Retired | Superseded)
      say_notice "$name" "terminal ($status_disp) — skipped (frozen history)"
      continue
      ;;
  esac

  brief="$dir/kickoff-brief.md"
  if [ ! -f "$brief" ]; then
    say_error "$name" \
      "non-Draft, non-terminal ($status_disp) with no kickoff-brief.md — remedy: complete or repair the sign-off record via /spec-kickoff (a removed brief must not disable this check)"
    continue
  fi

  # Every sanctioned form recomputes over the same four files, so a bundle
  # missing one cannot be recomputed by any of them. Name that cause here, once
  # for all forms: the script forms already fail closed, but the interim
  # whole-file form is a pipeline whose status comes from its last stage, so it
  # would hash the survivors and report a confident mismatch — blaming the
  # anchor for a missing file, the misdiagnosis the identifier screen above
  # exists to prevent.
  missing_file=
  for f in requirements.md design.md tasks.md test-spec.md; do
    [ -f "$dir/$f" ] || {
      missing_file=$f
      break
    }
  done
  if [ -n "$missing_file" ]; then
    say_error "$name" \
      "the bundle is missing $missing_file, so no recorded command can recompute its anchor — remedy: restore the file"
    continue
  fi

  parked=no
  parked_marker "$dir/tasks.md" && parked=yes

  entry=$(latest_anchor_entry "$brief" 2>/dev/null) || entry=""
  if [ -z "$entry" ]; then
    report_recompute "$name" "$parked" \
      "no parseable anchor entry in the brief — remedy: repair the sign-off record per the meta-spec's execution-validity rules"
  else
    recorded=${entry%%	*}
    cmd=${entry#*	}
    got=$(recompute "$cmd" "$dir" "$name")
    case $? in
      0)
        if [ "$recorded" = "$got" ]; then
          say_ok "$name" "anchor $recorded"
        else
          report_recompute "$name" "$parked" \
            "anchor mismatch: recorded $recorded, recomputed $got"
        fi
        ;;
      3)
        report_recompute "$name" "$parked" \
          "absent-anchor class: the recorded command's tool resolves to nothing here — remedy: supply the checked tree's scripts/spec-anchor.sh or set a root the chain reads"
        ;;
      4)
        report_recompute "$name" "$parked" \
          "the recorded command's tool failed to compute an anchor for this bundle"
        ;;
      *)
        report_recompute "$name" "$parked" \
          "non-sanctioned command form: $(spec_parse_printable "$cmd")"
        ;;
    esac
  fi

  # --- changelog pairing (REQ-D1.2) ---
  [ "$pairing" = on ] || continue
  case $dir in
    "$git_top"/*) rel=${dir#"$git_top"/} ;;
    *) continue ;;
  esac
  rel=${rel%/}

  # Fast path: if not a byte of the bundle differs from the baseline (working
  # tree included), no anchored content can have changed either, so skip the
  # two anchor computations the exact check would cost. Measured on this repo's
  # corpus, one cheap plumbing call per untouched bundle is what keeps the
  # whole-corpus run inside the per-commit cost D-6 accepted for the mirror
  # (without it the run took about three times as long). Exact, not
  # approximate: this arm only ever skips a bundle with no diff at all.
  if git -C "$git_top" diff --quiet "$base_commit" -- "$rel" 2>/dev/null; then
    continue
  fi

  base_dir="$wtmp/base"
  rm -rf "$base_dir"
  mkdir -p "$base_dir" || continue
  missing=0
  for f in requirements.md design.md tasks.md test-spec.md; do
    git -C "$git_top" show "$base_commit:$rel/$f" >"$base_dir/$f" 2>/dev/null || missing=1
  done
  if [ "$missing" -eq 1 ]; then
    say_notice "$name" "not a complete bundle at the baseline ref — pairing check skipped"
    continue
  fi

  base_anchor=$("$anchor_tool" "$base_dir" 2>/dev/null) || base_anchor=
  live_anchor=$("$anchor_tool" "$dir" 2>/dev/null) || live_anchor=
  if [ -z "$base_anchor" ] || [ -z "$live_anchor" ]; then
    say_notice "$name" "anchored content could not be extracted on both sides — pairing check skipped"
    continue
  fi
  [ "$base_anchor" != "$live_anchor" ] || continue

  changelog_entries "$base_dir" "$wtmp/base-log"
  changelog_entries "$dir" "$wtmp/live-log"
  if [ -n "$(comm -13 "$wtmp/base-log" "$wtmp/live-log")" ]; then
    continue
  fi
  say_error "$name" \
    "anchored content changed since $baseline with no new dated Changelog entry in the bundle — remedy: record the edit as a dated \`## Changelog\` entry (an expression-only edit also carries the marked self-re-anchor citing it)"
done

if [ "$seen" -eq 0 ]; then
  printf '%s\n' "check-anchor-freshness: no spec bundle found under $(spec_parse_printable "$specs_root")" >&2
  exit 2
fi

if [ "$pairing" = off ]; then
  printf '%s\n' "check-anchor-freshness: note: $pairing_note — pairing check skipped for every bundle."
fi
printf 'check-anchor-freshness: %d ok, %d notice(s), %d error(s)\n' "$ok" "$notice" "$error"
[ "$error" -eq 0 ] || exit 1
exit 0
