#!/bin/sh
# One-shot landing proof for the anchor-integrity re-anchor sweep
# (anchor-integrity REQ-A1.4, D-3; test-spec.md REQ-A1.4).
#
# The hash-scope change (REQ-A1.1, Task 2) moves every shipped bundle's
# anchor, so it lands together with the sweep that re-anchors them. This test
# is that sweep's proof: it walks the whole in-repo corpus and asserts the
# property the sweep claims to have established.
#
# Properties verified:
#   1. Corpus proof — for every non-Draft, non-terminal bundle under specs/
#      with a kickoff brief, the brief's most recent anchor entry parses, uses
#      a sanctioned command form, and recomputes equal against this tree.
#   2. Known-parked carve-out — a bundle whose tasks.md `## Awaiting input`
#      carries a live `anchor re-review pending` bullet (the REQ-A1.4 park for
#      a meaning-class delta routed to its re-review ritual) reports as a
#      notice, not an error, so one routed bundle cannot red the proof.
#   3. Teeth — the same walk over a synthesized fixture corpus goes red on a
#      stale anchor with no park marker, and green when the park marker is
#      present. Without this, a walk that silently matched nothing would pass
#      property 1 vacuously.
#
# Scope: this is the one-shot proof Task 3 owes, not the permanent guard.
# scripts/check-anchor-freshness.sh (Task 4) has since taken over the standing
# enforcement and widened it (changelog pairing against a baseline ref, the
# brief-less-bundle error, the lefthook mirror). This file keeps the narrower
# scope it landed with — in-scope means "briefed", and a brief-less bundle is a
# notice rather than an error — because it is the sweep's evidence as it stood,
# not a second copy of the guard.
#
# Runs standalone: ./tests/test-anchor-landing-proof.sh
set -eu

# Pin the C locale: the hex-range case globs below are collation-dependent
# under UTF-8 locales.
LC_ALL=C
export LC_ALL

# A CDPATH-resolved cd echoes the destination into the command substitution
# below, corrupting the derived script path (house pattern, see sibling tests).
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/.." && pwd)
anchor="$repo/scripts/spec-anchor.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -x "$anchor" ] || fail "scripts/spec-anchor.sh missing or not executable"

# The header-block Status parse is normative (doctrine/spec-format.md,
# *Header-block extent*) and the lib is its one implementation: it bounds the
# read to the leading header block and fails closed on a duplicate declaration.
# A second grammar here would be a second thing to keep in step.
# shellcheck source=scripts/spec-parse.sh
. "$repo/scripts/spec-parse.sh"

# --- the walk -----------------------------------------------------------
#
# proof_walk <specs-root>
#
# Prints one tab-separated record per bundle — `<verdict><TAB><bundle><TAB>
# <detail>` where verdict is ok / notice / error — and returns 1 if any
# record is an error. Every bundle is always visited: one failure never
# hides another, and the printed table IS the landing-proof artifact.
proof_walk() {
  pw_root=$1
  pw_rc=0
  pw_seen=0

  for pw_dir in "$pw_root"/*/; do
    pw_name=${pw_dir%/}
    pw_name=${pw_name##*/}
    # Underscore-prefixed directories are accumulators (_observations,
    # _pending), not spec bundles.
    case $pw_name in
      _*) continue ;;
    esac
    [ -f "$pw_dir/requirements.md" ] || continue

    # A status that will not parse (unreadable file, duplicate declaration) is
    # a fact about the bundle, not a reason to abandon the walk: record it and
    # keep going, so one broken bundle never hides the rest of the table.
    pw_status=$(spec_parse_header_value "$pw_dir/requirements.md" Status 2>/dev/null) || pw_status=""
    if [ -z "$pw_status" ]; then
      printf 'error\t%s\tno parseable header-block Status declaration\n' "$pw_name"
      pw_rc=1
      continue
    fi
    case $pw_status in
      Draft)
        printf 'notice\t%s\tDraft — skipped\n' "$pw_name"
        continue
        ;;
      Retired | Superseded)
        printf 'notice\t%s\tterminal (%s) — skipped\n' "$pw_name" "$pw_status"
        continue
        ;;
    esac

    pw_brief="$pw_dir/kickoff-brief.md"
    if [ ! -f "$pw_brief" ]; then
      printf 'notice\t%s\tno kickoff brief — out of the proof scope\n' "$pw_name"
      continue
    fi

    pw_seen=$((pw_seen + 1))
    pw_parked=no
    parked_marker "$pw_dir/tasks.md" && pw_parked=yes

    pw_entry=$(latest_anchor_entry "$pw_brief") || pw_entry=""
    if [ -z "$pw_entry" ]; then
      report "$pw_name" "$pw_parked" "no parseable anchor entry"
      pw_rc=$((pw_rc | report_rc))
      continue
    fi
    pw_recorded=${pw_entry%%	*}
    pw_cmd=${pw_entry#*	}

    pw_got=$(recompute "$pw_cmd" "$pw_dir" 2>/dev/null) || pw_got=""
    if [ -z "$pw_got" ]; then
      report "$pw_name" "$pw_parked" "recompute failed or non-sanctioned form: $pw_cmd"
      pw_rc=$((pw_rc | report_rc))
      continue
    fi

    if [ "$pw_recorded" = "$pw_got" ]; then
      printf 'ok\t%s\t%s\n' "$pw_name" "$pw_got"
    else
      report "$pw_name" "$pw_parked" "recorded $pw_recorded, recomputed $pw_got"
      pw_rc=$((pw_rc | report_rc))
    fi
  done

  # A walk that visited no bundle would satisfy every assertion vacuously.
  if [ "$pw_seen" -eq 0 ]; then
    printf 'error\t(corpus)\tno in-scope bundle found under %s\n' "$pw_root"
    pw_rc=1
  fi
  return "$pw_rc"
}

# report <bundle> <parked> <detail> — prints the record on stdout (the table is
# the artifact) and sets report_rc to the contribution this record makes to the
# walk's exit status. A parked bundle's failing gate is the REQ-A1.4 design (it
# stays failed closed until its re-review signs off), so it never reds the
# proof. The rc travels in a variable rather than the exit status because the
# caller is inside a command substitution that owns stdout.
report_rc=0
report() {
  if [ "$2" = yes ]; then
    printf 'notice\t%s\tknown-parked (anchor re-review pending): %s\n' "$1" "$3"
    report_rc=0
  else
    printf 'error\t%s\t%s\n' "$1" "$3"
    report_rc=1
  fi
}

# parked_marker <tasks.md> — succeeds when a live `anchor re-review pending`
# bullet sits in the `## Awaiting input` section.
parked_marker() {
  [ -f "$1" ] || return 1
  awk '
    /^## / { in_sec = ($0 ~ /^## Awaiting input/) ; next }
    in_sec && /^- / && /anchor re-review pending/ { found = 1 }
    END { exit(found ? 0 : 1) }
  ' "$1"
}

# latest_anchor_entry <brief> — prints `<hash><TAB><command>` for the brief's
# most recent (last-appended) anchor entry. Both recorded layouts are read:
# the canonical two-line form, and the single-line parenthesized variant.
latest_anchor_entry() {
  awk '
    /^Anchor:/ {
      line = $0
      nextline = ""
      if ((getline nl) > 0) { nextline = nl }
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
      # Reading the same line only inside parentheses keeps the two apart.
      cmd = ""
      if (match(line, /\(`[^`]+`\)/)) {
        cmd = substr(line, RSTART + 2, RLENGTH - 4)
      } else if (match(nextline, /^`[^`]+`$/)) {
        cmd = substr(nextline, 2, length(nextline) - 2)
      }
      if (hash != "" && cmd != "") { best_hash = hash; best_cmd = cmd }
    }
    END {
      if (best_hash == "") { exit 1 }
      printf "%s\t%s\n", best_hash, best_cmd
    }
  ' "$1"
}

# recompute <recorded-command> <spec-dir> — recompute with the form on record,
# never a substituted one (doctrine/spec-format.md, *Resolving the recorded
# command*). The recorded string is data: it is matched against the sanctioned
# grammar and the tool is then invoked with the parsed directory argument,
# never evaluated (REQ-D1.5).
recompute() {
  rc_cmd=$1
  rc_dir=$2
  rc_arg=${rc_cmd##* }
  case $rc_cmd in
    "scripts/spec-anchor.sh $rc_arg" | "spec-anchor.sh $rc_arg") ;;
    *) return 1 ;;
  esac
  # The argument must be a plain `specs/<identifier>` (REQ-A1.8) before it is
  # read any further. It reaches a case pattern below, where an unvalidated
  # glob byte would widen the containment check instead of being compared by it.
  case $rc_arg in
    specs/*) rc_name=${rc_arg#specs/} ;;
    *) return 1 ;;
  esac
  case $rc_name in
    '' | */* | *[!a-z0-9-]* | [!a-z0-9]*) return 1 ;;
  esac
  # The recorded argument must name the bundle being checked; a mismatch means
  # the entry was copied from another bundle, which is not a recompute at all.
  case $rc_dir in
    *"/$rc_name/") ;;
    *) return 1 ;;
  esac
  "$anchor" "$rc_dir"
}

# --- property 3: teeth, on a synthesized corpus -------------------------

tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT

# make_bundle <specs-root> <name> <status> <body-marker>
make_bundle() {
  mb_dir="$1/$2"
  mkdir -p "$mb_dir"
  printf '%s\n' "# $2 — Requirements" '' "**Status:** $3" '' '## Goal' '' "$4" >"$mb_dir/requirements.md"
  printf '%s\n' "# $2 — Design" '' "**Status:** $3" '' '### D-1: A decision' '' 'A design body.' >"$mb_dir/design.md"
  printf '%s\n' "# $2 — Test Spec" '' "**Status:** $3" '' '## REQ-X' '' 'A test-spec body.' >"$mb_dir/test-spec.md"
  cat >"$mb_dir/tasks.md" <<EOF
# $2 — Tasks

**Status:** $3

## Tasks

### Task 1 — A task

- **Deliverables:** A thing.
- **Done when:** The thing exists.
- **Dependencies:** none
- **Citations:** REQ-X1.1
- **Estimated effort:** half day

## Awaiting input

(none yet)
EOF
}

# write_entry <specs-root> <name> <hash>
write_entry() {
  cat >"$1/$2/kickoff-brief.md" <<EOF
# $2 — Kickoff Brief

## Amendment log

Class: expression-only
Anchor: \`$3\` — computed as
\`scripts/spec-anchor.sh specs/$2\`
EOF
}

# park <specs-root> <name>
park() {
  # Replace the placeholder so the section carries a live marker bullet.
  awk '
    /^## Awaiting input/ { print; print ""; print "- **anchor re-review pending** — routed to its re-review ritual."; skip = 1; next }
    skip && /^\(none yet\)$/ { skip = 0; next }
    { print }
  ' "$1/$2/tasks.md" >"$1/$2/tasks.md.new"
  mv "$1/$2/tasks.md.new" "$1/$2/tasks.md"
}

fixture="$tmp/specs"
mkdir -p "$fixture"

make_bundle "$fixture" fresh Ready 'A requirement body.'
write_entry "$fixture" fresh "$("$anchor" "$fixture/fresh")"

make_bundle "$fixture" draft-skipped Draft 'A requirement body.'
# Deliberately no brief and a nonsense anchor would both be invisible here:
# a Draft bundle is skipped before either is read.

out=$(proof_walk "$fixture") || fail "green fixture corpus should pass: $out"
case $out in
  *"ok	fresh"*) ;;
  *) fail "green fixture: expected an ok record for 'fresh', got: $out" ;;
esac
case $out in
  *"notice	draft-skipped	Draft"*) ;;
  *) fail "green fixture: expected a Draft skip notice, got: $out" ;;
esac

# A stale anchor with no park marker must red the proof.
make_bundle "$fixture" stale Ready 'A requirement body.'
write_entry "$fixture" stale 0000000000000000000000000000000000000000

if out=$(proof_walk "$fixture"); then
  fail "stale-anchor fixture should have failed the walk: $out"
fi
case $out in
  *"error	stale	recorded 0000000000"*) ;;
  *) fail "stale fixture: expected an error record for 'stale', got: $out" ;;
esac

# The same stale bundle, parked: a notice, and the walk goes green again.
park "$fixture" stale
out=$(proof_walk "$fixture") || fail "parked fixture should pass the walk: $out"
case $out in
  *"notice	stale	known-parked (anchor re-review pending)"*) ;;
  *) fail "parked fixture: expected a known-parked notice, got: $out" ;;
esac

# The park is scoped to `## Awaiting input`. The same words anywhere else in
# tasks.md are prose, not a park, and must leave the bundle failing.
make_bundle "$fixture" mislabelled Ready 'Prose mentioning anchor re-review pending.'
write_entry "$fixture" mislabelled 1111111111111111111111111111111111111111
printf '\n## Deferred\n\n- anchor re-review pending (a note, in the wrong section)\n' \
  >>"$fixture/mislabelled/tasks.md"
if out=$(proof_walk "$fixture"); then
  fail "a park marker outside '## Awaiting input' must not exempt a bundle: $out"
fi
case $out in
  *"error	mislabelled	recorded 1111111111"*) ;;
  *) fail "mislabelled fixture: expected an error record, got: $out" ;;
esac
rm -rf "$fixture/mislabelled"

# An entry recorded with a non-sanctioned command form is an error, not a
# silent pass: the gate never reads an unresolved command as a match.
make_bundle "$fixture" forged Ready 'A requirement body.'
cat >"$fixture/forged/kickoff-brief.md" <<EOF
# forged — Kickoff Brief

Class: expression-only
Anchor: \`$("$anchor" "$fixture/forged")\` — computed as
\`sha1sum specs/forged/*\`
EOF
if out=$(proof_walk "$fixture"); then
  fail "non-sanctioned command form should have failed the walk: $out"
fi
case $out in
  *"error	forged	recompute failed or non-sanctioned form"*) ;;
  *) fail "forged fixture: expected a non-sanctioned-form error, got: $out" ;;
esac

# --- properties 1 and 2: the real corpus --------------------------------

if ! corpus=$(proof_walk "$repo/specs"); then
  printf '%s\n' "$corpus" >&2
  fail "landing proof: the in-repo corpus has an unparked stale anchor (see the table above)"
fi

printf '%s\n' "$corpus"
echo "ok: anchor landing proof — $(printf '%s\n' "$corpus" | grep -c '^ok	') recompute equal, $(printf '%s\n' "$corpus" | grep -c '^notice	') notice(s)"
