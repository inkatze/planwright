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
# heading, the `### Task <id> —` task heading, the definition fields, and the
# Dependencies / Citations token extraction) comes from the shared grammar lib,
# scripts/spec-parse.sh (format-grammar Task 8; REQ-B1.5 · D-4). It used to be
# reimplemented here, which is the divergence legacy line 80 recorded: the
# reader, the validator, and the selector now answer "what is a task heading"
# from one definition.
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
#   2  usage or environment error: no argument, the spec directory itself is
#      absent or unreadable (fail closed — a model over a non-bundle must not
#      silently report an empty model), or the shared grammar lib is missing or
#      unreadable (REQ-B1.6a: a broken install refuses rather than falling back
#      to a private grammar copy). An unreadable individual bundle file is
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

# The shared spec-parse grammar lib (D-3, D-4; REQ-B1.5): sourced, never
# executed. Fail closed when it is missing or unreadable rather than falling
# back to a private grammar copy (REQ-B1.6a) — a reader that silently parsed by
# its own rules is exactly the divergence the lib exists to end.
#
# The parses below prepend the lib's fence lexer, so fenced illustration is
# documentation rather than content. They deliberately do NOT call its
# end-of-file-inside-an-open-fence refusal: this reader degrades rather than
# refuses (REQ-A1.5), so an unbalanced fence leaves the model holding only what
# sat above it, exactly as an unreadable file leaves it holding nothing. The
# malformation itself is reported where reporting belongs — spec-validate.sh
# flags an unbalanced fence per file (REQ-D1.11) — so the truncation is never
# the only signal a reader gets. The parsers that ACT on their parse
# (orchestrate-select.sh, spec-anchor.sh) take the refusal instead.
script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2
spec_parse_sh="$script_dir/spec-parse.sh"
if [ ! -f "$spec_parse_sh" ] || [ ! -r "$spec_parse_sh" ]; then
  echo "spec-model: required helper $spec_parse_sh missing or not readable" >&2
  exit 2
fi
# shellcheck source=scripts/spec-parse.sh
. "$spec_parse_sh" || exit 2

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
  function emit_cites(owner, tag, line,    i, n, t) {
    # One edge per D-id / REQ-id token the shared grammar extracts from a
    # Cites/Citations annotation, the owner id already excluded. A consumer
    # scopes to the bundle by intersecting with the emitted id set; cross-spec
    # carry references are recorded, not silently dropped (losslessness, D-2).
    n = split(spec_parse_cite_ids(line, owner), t, " ")
    for (i = 1; i <= n; i++) printf "%s\t%s\t%s\n", tag, owner, t[i]
  }
'

# Requirements: REQ records (id, group-from-id, live|superseded, plain text)
# plus REQCITE edges. Only bullets under a `## REQ-` group are parsed (the
# spec-validate ingroup discipline). The id token and the `*(Cites: ...)*`
# annotation are kept out of the text column so the plain text stays free of
# internal vocabulary (REQ-C1.1) and the back-pointer is separable (REQ-D1.3).
parse_requirements() {
  awk "$spec_parse_awk_fence$spec_parse_awk_grammar$awk_clean"'
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
      cur = spec_parse_req_bullet_id($0)
      if (cur != "") {
        sup = ($0 ~ /\*\*Superseded-by: REQ-/) ? 1 : 0
        if ($0 ~ /\(Cites:/) emit_cites(cur, "REQCITE", $0)
        # The bolded lead is `- **` <id> `**`, so the text starts past it.
        text = strip_annot(substr($0, length(cur) + 7))
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
  awk "$spec_parse_awk_fence$spec_parse_awk_grammar$awk_clean"'
    function flush_field() {
      if (cur != "" && fld != "") printf "DECFIELD\t%s\t%s\t%s\n", cur, fld, clean(fbuf)
      fld = ""
      fbuf = ""
    }
    function flush_dec() {
      flush_field()
      cur = ""
    }
    spec_parse_dec_attempt($0) {
      flush_dec()
      cur = spec_parse_dec_id($0)
      # A malformed attempt ("### D-four: …") is not a decision; it ends the
      # open one and is otherwise ordinary prose, as an ordinary H3 would be.
      if (cur == "") next
      line = spec_parse_dec_title($0)
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
  awk "$spec_parse_awk_fence$spec_parse_awk_grammar$awk_clean"'
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
    spec_parse_is_task_heading($0) {
      flush_task()
      cur = spec_parse_task_id($0)
      if (cur != "")
        printf "TASK\t%s\t%s\t%s\n", cur, clean(section), clean(spec_parse_task_title($0))
      next
    }
    /^### / { flush_task(); next }
    cur == "" { next }
    # The definition fields, named by the shared grammar. Dependencies and
    # Citations become EDGES rather than fields; the other three carry their
    # payload into a TASKFIELD record. Any other bolded bullet (Status, Last
    # activity, Dispatch, …) ends the open field and is not modelled.
    #
    # The dependency ids are the shared extraction (Task 8; REQ-B1.5): the
    # model graph and the selector graph now come from one tokenizer, so the
    # drawn graph cannot lose (or invent) an edge the critical path crosses
    # (REQ-C1.3, D-6). The model has no malformed-deps channel, so a
    # non-conforming token is simply not emitted as an edge.
    /^- \*\*/ {
      field = spec_parse_task_field($0)
      if (field == "dependencies") {
        flush_field()
        n = split(spec_parse_dep_ids($0), a, " ")
        for (i = 1; i <= n; i++) printf "TASKDEP\t%s\t%s\n", cur, a[i]
        next
      }
      if (field == "citations") {
        flush_field()
        emit_cites(cur, "TASKCITE", $0)
        next
      }
      flush_field()
      if (field != "") { fld = field; fbuf = spec_parse_task_field_value($0) }
      next
    }
    fld != "" { fbuf = fbuf " " $0 }
    END { flush_task() }
  ' "$1"
}

# Test-spec: one TEST record per REQ with a verification path (an H3 entry
# heading naming a REQ-id). Exact-id extraction through the shared grammar
# (the spec-validate coverage discipline).
parse_test_spec() {
  awk "$spec_parse_awk_fence$spec_parse_awk_grammar"'
    /^### / {
      id = spec_parse_req_token($0)
      if (id != "") printf "TEST\t%s\n", id
    }
  ' "$1"
}

readable_file "$spec_dir/requirements.md" && parse_requirements "$spec_dir/requirements.md"
readable_file "$spec_dir/design.md" && parse_design "$spec_dir/design.md"
readable_file "$spec_dir/tasks.md" && parse_tasks "$spec_dir/tasks.md"
readable_file "$spec_dir/test-spec.md" && parse_test_spec "$spec_dir/test-spec.md"

exit 0
