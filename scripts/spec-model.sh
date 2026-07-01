#!/bin/sh
# spec-model.sh — the bundle reader model for /spec-walkthrough.
#
# Task 2 of specs/spec-comprehension (D-2; REQ-C1.1, REQ-C1.7, REQ-D1.3,
# REQ-B1.2): the normalized in-memory substrate every downstream view renders
# from. It reads the four bundle files and emits a deterministic, tagged,
# tab-separated record stream — the model — on stdout. Every record carries
# its source identifier as a back-pointer in its own column (D-2), separable
# from the plain text so the default render can stay audience-neutral
# (REQ-C1.1) and the reveal toggle (REQ-D1.3) can surface the identifiers on
# demand. The citation and dependency edges make a decision's blast radius and
# the task graph computable by a consumer (REQ-B1.2). The plain text is carried
# verbatim — normative tokens are preserved (REQ-C1.7); softening and
# token-marking are the translation layer's job, not the model's.
#
# This is a substrate producer, not the command surface: it takes a spec
# directory directly (like scripts/spec-anchor.sh and
# scripts/orchestrate-select.sh), trusting the identifier-charset and
# path-containment gate the command scaffold (scripts/spec-walkthrough.sh,
# REQ-A1.6) runs before any read. It is strictly read-only (REQ-A1.3): it
# writes nothing.
#
# The format grammar (the REQ-ID bullet shape, the `### D-<n>:` decision
# heading, the `### Task <id> —` task heading, the Dependencies token
# extraction) mirrors the canonical parsers in scripts/spec-validate.sh and
# scripts/orchestrate-select.sh, reimplemented here rather than shared via a
# library so this task does not restructure those load-bearing scripts; the
# duplication is recorded as a drain-loop observation.
#
# Record vocabulary (tag in column 1, tab-separated, emitted in source order):
#   BUNDLE     <spec>  <status>
#   FILE       <name>  present|absent          (name: requirements|design|tasks|test-spec)
#   REQ        <id>    <group>  live|superseded  <text>
#   REQCITE    <req-id>  <cited-id>             (a D-id or REQ-id from the Cites annotation)
#   DEC        <id>    <origin>  <title>
#   DECFIELD   <id>    decision|alternatives|chosen  <text>
#   TASK       <id>    <section>  <title>       (section: the H2 state label)
#   TASKFIELD  <id>    deliverables|donewhen|effort  <text>
#   TASKDEP    <id>    <dep-id>                 (a task-graph dependency edge)
#   TASKCITE   <id>    <cited-id>               (a D-id or REQ-id from the Citations line)
#   TEST       <req-id>                         (a REQ with a verification path in test-spec)
#
# Usage: spec-model.sh <spec-dir>
#
# Exit codes:
#   0  the model was emitted (a partial bundle still emits what is present;
#      an absent — or present-but-unreadable — file is marked FILE ... absent
#      and its records are skipped, degrading the same as absence rather than
#      halting opaquely — graceful degradation, REQ-A1.5).
#   2  usage or environment error: no argument, or the spec directory itself is
#      absent or unreadable (fail closed — a model over a non-bundle must not
#      silently report an empty model). An unreadable individual bundle file is
#      not an error: it degrades like absence (exit 0) per the line above.
#
# Portable: /bin/sh + awk as shipped on macOS (bash 3.2, BSD userland) and
# Linux (the REQ-K1.5 envelope). No gawk-only constructs (3-arg match,
# gensub), no eval; input treated as data only.
set -eu

# Pin the C locale: range patterns and the [[:cntrl:]] class are
# collation-dependent under UTF-8 locales; the byte-wise control-stripping
# below relies on C-locale classification (only 0x00-0x1f and 0x7f are
# cntrl, so multibyte UTF-8 in the body text is preserved).
LC_ALL=C
export LC_ALL
unset CDPATH

spec_dir="${1:-}"
if [ -z "$spec_dir" ]; then
  echo "spec-model: usage: spec-model.sh <spec-dir>" >&2
  exit 2
fi
while [ "$spec_dir" != "${spec_dir%/}" ]; do spec_dir=${spec_dir%/}; done
if [ ! -d "$spec_dir" ] || [ ! -r "$spec_dir" ]; then
  echo "spec-model: spec directory absent or unreadable: $spec_dir" >&2
  exit 2
fi

spec=$(basename "$spec_dir")

# readable_file <path> — true iff a readable regular file. The present/parse
# gate: an exists-but-unreadable file degrades the same as absence (REQ-A1.5;
# the kickoff degrade-vs-refuse boundary — a valid path with broken content
# degrades, naming what is missing, rather than halting opaquely). Without
# this, a present-but-unreadable file is marked "present" yet crashes the awk
# parse under set -e. Mirrors the read gate in scripts/spec-anchor.sh and
# scripts/orchestrate-select.sh, and the directory-level -r check above.
readable_file() {
  [ -f "$1" ] && [ -r "$1" ]
}

# first_header <file> <key> — first "**<key>:** value" header line's value,
# non-printables stripped (header values are ASCII; the echo discipline keeps
# hostile file content from reaching the terminal raw, matching spec-validate).
first_header() {
  awk -v key="$2" '
    index($0, "**" key ":**") == 1 {
      sub(/^\*\*[^*]*:\*\*[ \t]*/, "")
      gsub(/[^[:print:]]/, "")
      print
      exit
    }
  ' "$1"
}

# Status (auto-detected, never a refusal): requirements.md is authoritative;
# only when it is absent does the first sibling mirror that declares one stand
# in. An empty value is reported as undeclared rather than masked.
status=
if readable_file "$spec_dir/requirements.md"; then
  status=$(first_header "$spec_dir/requirements.md" Status)
else
  for f in design.md tasks.md test-spec.md; do
    readable_file "$spec_dir/$f" || continue
    status=$(first_header "$spec_dir/$f" Status)
    [ -n "$status" ] && break
  done
fi
[ -n "$status" ] || status="(undeclared)"

printf 'BUNDLE\t%s\t%s\n' "$spec" "$status"
for f in requirements design tasks test-spec; do
  if readable_file "$spec_dir/$f.md"; then
    printf 'FILE\t%s\tpresent\n' "$f"
  else
    printf 'FILE\t%s\tabsent\n' "$f"
  fi
done

# The shared awk preamble: clean() normalizes a field for the tab-separated,
# line-oriented stream — control characters (including a literal tab, the
# field delimiter, and any continuation newline already joined in) collapse to
# spaces, runs of whitespace fold to one, and the result is trimmed. Bytes at
# or above 0x80 are not [[:cntrl:]] under the C locale, so multibyte UTF-8
# (e.g. a ≤ threshold) survives verbatim (REQ-C1.7).
awk_clean='
  function clean(s) {
    gsub(/[[:cntrl:]]/, " ", s)
    gsub(/  +/, " ", s)
    sub(/^ +/, "", s)
    sub(/ +$/, "", s)
    return s
  }
  function emit_cites(owner, tag, line,    i, n, t, tok) {
    # Extract every D-id and REQ-id token from a Cites/Citations annotation and
    # emit one edge per token. A consumer scopes to the bundle by intersecting
    # with the emitted id set; cross-spec carry references are recorded, not
    # silently dropped (losslessness, D-2). The owners own id is skipped: a
    # requirement bullet carries its id on the same line as an inline citation,
    # and an element never cites itself.
    gsub(/[^A-Za-z0-9.-]+/, " ", line)
    n = split(line, t, " ")
    for (i = 1; i <= n; i++) {
      tok = t[i]
      sub(/\.$/, "", tok)
      if (tok == owner) continue
      if (tok ~ /^D-[0-9]+$/ || tok ~ /^REQ-[A-Z][0-9]+\.[0-9]+$/)
        printf "%s\t%s\t%s\n", tag, owner, tok
    }
  }
'

# Requirements: REQ records (id, group-from-id, live|superseded, plain text)
# plus REQCITE edges. Only bullets under a `## REQ-` group are parsed (the
# spec-validate ingroup discipline). The id token and the `*(Cites: ...)*`
# annotation are kept out of the text column so the plain text stays free of
# internal vocabulary (REQ-C1.1) and the back-pointer is separable (REQ-D1.3).
parse_requirements() {
  awk "$awk_clean"'
    # Drop the trailing `*(Cites: ...)*` annotation (always the final element of
    # a requirement, by convention) and any `**Superseded-by: ...**` marker from
    # the plain text: the citation tokens and the superseded state are carried as
    # separate columns/edges, so the text column stays free of internal
    # vocabulary (REQ-C1.1) whether the annotation rides its own line or the
    # bullet line.
    function strip_annot(s) {
      sub(/\*\(Cites:.*/, "", s)
      gsub(/\*\*Superseded-by:[^*]*\*\*/, "", s)
      return s
    }
    function flush(   g) {
      if (cur == "") return
      if (match(cur, /^REQ-[A-Z]/)) g = substr(cur, 5, RLENGTH - 4)
      else g = ""
      printf "REQ\t%s\t%s\t%s\t%s\n", cur, g, (sup ? "superseded" : "live"), clean(text)
      cur = ""
    }
    /^## / { flush(); ingroup = ($0 ~ /^## REQ-/); next }
    !ingroup { next }
    /^- / {
      flush()
      if (match($0, /^- \*\*REQ-[A-Z][0-9]+\.[0-9]+\*\*/)) {
        cur = substr($0, 5, RLENGTH - 6)
        sup = ($0 ~ /\*\*Superseded-by: REQ-/) ? 1 : 0
        if ($0 ~ /\(Cites:/) emit_cites(cur, "REQCITE", $0)
        text = strip_annot(substr($0, RLENGTH + 1))
        next
      }
      # A non-REQ bullet inside a REQ group ends any open record; its prose is
      # not part of a requirement.
      next
    }
    cur != "" {
      if ($0 ~ /\*\*Superseded-by: REQ-/) sup = 1
      if ($0 ~ /\(Cites:/) emit_cites(cur, "REQCITE", $0)
      r = strip_annot($0)
      if (r != "") text = text " " r
    }
    END { flush() }
  ' "$1"
}

# Design: DEC records (id, origin tag, title) plus DECFIELD records for the
# Decision / Alternatives considered / Chosen because fields — the four-beat
# substrate (D-2). Each field spans from its marker to the next field marker or
# heading. Only the conforming `### D-<n>:` heading is a decision (the
# spec-validate / spec-walkthrough discipline: the colon is required).
parse_design() {
  awk "$awk_clean"'
    function flush_field() {
      if (cur != "" && fld != "") printf "DECFIELD\t%s\t%s\t%s\n", cur, fld, clean(fbuf)
      fld = ""
      fbuf = ""
    }
    function flush_dec() {
      flush_field()
      cur = ""
    }
    /^### D-[0-9]+:/ {
      flush_dec()
      match($0, /^### D-[0-9]+/)
      cur = substr($0, 5, RLENGTH - 4)
      line = substr($0, RLENGTH + 1)
      sub(/^:[ \t]*/, "", line)
      sub(/[ \t]+$/, "", line)
      origin = ""
      if (match(line, /\([^()]*\)$/)) {
        origin = substr(line, RSTART + 1, RLENGTH - 2)
        title = substr(line, 1, RSTART - 1)
      } else {
        title = line
      }
      printf "DEC\t%s\t%s\t%s\n", cur, clean(origin), clean(title)
      next
    }
    /^### / || /^## / { flush_dec(); next }
    cur == "" { next }
    /^\*\*Decision:\*\*/ {
      flush_field(); fld = "decision"; fbuf = substr($0, length("**Decision:**") + 1); next
    }
    /^\*\*Alternatives considered:\*\*/ {
      flush_field(); fld = "alternatives"; fbuf = substr($0, length("**Alternatives considered:**") + 1); next
    }
    /^\*\*Chosen because:\*\*/ {
      flush_field(); fld = "chosen"; fbuf = substr($0, length("**Chosen because:**") + 1); next
    }
    fld != "" { fbuf = fbuf " " $0 }
    END { flush_dec() }
  ' "$1"
}

# Tasks: TASK records (id, H2 section, title), TASKFIELD records for
# Deliverables / Done when / Estimated effort, TASKDEP dependency edges, and
# TASKCITE citation edges. Section membership is the canonical state label
# (the orchestrate-select discipline). Dependency and citation lines are edges,
# not fields, so they are not emitted as TASKFIELD.
parse_tasks() {
  awk "$awk_clean"'
    function flush_field() {
      if (cur != "" && fld != "") printf "TASKFIELD\t%s\t%s\t%s\n", cur, fld, clean(fbuf)
      fld = ""
      fbuf = ""
    }
    function flush_task() {
      flush_field()
      cur = ""
    }
    /^## / {
      flush_task()
      section = substr($0, 4)
      sub(/[[:space:]]+$/, "", section)
      next
    }
    /^### Task / {
      flush_task()
      id = $3
      if (id ~ /^[0-9]+(\.[0-9]+)?$/) {
        cur = id
        title = $0
        sub(/^### Task [0-9]+(\.[0-9]+)?[[:space:]]*/, "", title)
        sub(/^—[[:space:]]*/, "", title)
        printf "TASK\t%s\t%s\t%s\n", cur, clean(section), clean(title)
      } else {
        cur = ""
      }
      next
    }
    /^### / { flush_task(); next }
    cur == "" { next }
    /^- \*\*Deliverables:\*\*/ {
      flush_field(); fld = "deliverables"; fbuf = substr($0, length("- **Deliverables:**") + 1); next
    }
    /^- \*\*Done when:\*\*/ {
      flush_field(); fld = "donewhen"; fbuf = substr($0, length("- **Done when:**") + 1); next
    }
    /^- \*\*Estimated effort:\*\*/ {
      flush_field(); fld = "effort"; fbuf = substr($0, length("- **Estimated effort:**") + 1); next
    }
    /^- \*\*Dependencies:\*\*/ {
      flush_field()
      s = $0
      sub(/.*\*\*Dependencies:\*\*/, "", s)
      # Whitespace-tokenize then grammar-validate, matching the derivation
      # engine (scripts/orchestrate-state.sh). Splitting on commas and
      # whitespace keeps a non-id token whole ("REQ-A1.8", "Task") so it fails
      # the id grammar and is dropped, rather than being digit-scraped into a
      # phantom edge from a parenthetical carry clause ("(REQ-A1.8 / D-9 …)").
      # A trailing run of sentence periods is stripped per token so a prose
      # entry ("Task 1.", "1.", "2.1.") still yields its edge — a task id
      # always ends in a digit, so this only ever removes punctuation. The
      # model has no malformed-deps channel, so a non-conforming token is
      # silently not emitted as an edge (opportunities.md 2026-06-28 /
      # 2026-07-01; parity with PR #103 / #104).
      gsub(/,/, " ", s)
      n = split(s, a, " ")
      for (i = 1; i <= n; i++) {
        tok = a[i]
        sub(/\.+$/, "", tok)
        if (tok ~ /^[0-9]+(\.[0-9]+)?$/) printf "TASKDEP\t%s\t%s\n", cur, tok
      }
      next
    }
    /^- \*\*Citations:\*\*/ {
      flush_field()
      emit_cites(cur, "TASKCITE", $0)
      next
    }
    # Any other bullet field (Status, Last activity, Dispatch, …) ends the open
    # field and is not modelled.
    /^- \*\*/ { flush_field(); next }
    fld != "" { fbuf = fbuf " " $0 }
    END { flush_task() }
  ' "$1"
}

# Test-spec: one TEST record per REQ with a verification path (an H3 entry
# heading naming a REQ-id). Exact-id extraction (the spec-validate coverage
# discipline).
parse_test_spec() {
  awk '
    /^### / {
      if (match($0, /REQ-[A-Z][0-9]+\.[0-9]+/))
        printf "TEST\t%s\n", substr($0, RSTART, RLENGTH)
    }
  ' "$1"
}

readable_file "$spec_dir/requirements.md" && parse_requirements "$spec_dir/requirements.md"
readable_file "$spec_dir/design.md" && parse_design "$spec_dir/design.md"
readable_file "$spec_dir/tasks.md" && parse_tasks "$spec_dir/tasks.md"
readable_file "$spec_dir/test-spec.md" && parse_test_spec "$spec_dir/test-spec.md"

exit 0
