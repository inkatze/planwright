# Security Posture

planwright's security doctrine has three parts: when written code gets a
focused security pass, what committed framework artifacts may contain, and
how planwright's own scripts behave. The hard-disqualifier zones in
[finding-categorization.md](finding-categorization.md) are the gate-side
expression of the same posture: security-sensitive findings never apply
autonomously.

Citations: REQ-D1.6.

## Write-time security triggers

A diff touching any of the following gets a focused security pass before the
PR is opened, distinct from the general Discovery Rigor security lens: the
pass examines the specific risk class the trigger names, with Research Rigor
consulted for current guidance when the pattern is unfamiliar.

- **Untrusted input** (parsing, decoding, or acting on data from outside the
  trust boundary)
- **Subprocess or shell construction** (command lines built from variables,
  interpolation into scripts)
- **Path handling** (paths derived from input, traversal, symlink
  resolution, containment checks)
- **Authorization** (permission checks, role logic, trust decisions)
- **Crypto** (key handling, algorithm choice, randomness)
- **Serialization** (formats that can encode object graphs or code)

## Artifact data-hygiene

Committed framework artifacts (spec bundles, kickoff briefs, risk registers,
observation logs, PR bodies) carry no secrets, credentials, or sensitive
operational detail. The risk register is the artifact most at risk: it
exists to record context, and context invites detail. Record the shape of a
risk and the decision taken; do not record tokens, internal hostnames,
customer data, or identifying details of private repositories. Secret
scanning in CI catches token-shaped leaks; prose-shaped leaks are caught
only by this rule being applied at write time.

## Framework-script security

planwright ships hooks and scripts that run on adopter machines, and a
`~/.claude/` writer that touches user configuration. They are held to a
stricter bar than the code they help review:

- **Never execute untrusted input.** Data parsed from branch names, gate
  conditions, spec files, or accumulator entries is data, never code: no
  `eval`, no subshell expansion of it, no use as a pattern, format string,
  or unquoted argument. Identifiers are validated against their declared
  grammar before any use.
- **Guard path access.** Paths derived from parsed input are validated and
  containment-checked after canonicalization before any read or write.
  Hostile input is a clean refusal, never a path.
- **Stay auditable.** Scripts are plain portable shell, lint-checked and
  secret-scanned in planwright's own CI, small enough to read before
  trusting.
