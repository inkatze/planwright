# Security Policy

## Reporting a vulnerability

Please report suspected vulnerabilities privately through
[GitHub's private vulnerability reporting](https://github.com/inkatze/planwright/security/advisories/new)
rather than a public issue. You will get an acknowledgement, and a fix or an
assessment of the report, as quickly as the maintainer can manage; planwright
is a solo-maintained project, so there is no guaranteed response window.

## Supported versions

Only the latest release receives fixes.

## Security posture

planwright's own rules for handling security-sensitive work (write-time
triggers, artifact data hygiene, framework-script security) are public
doctrine: see
[doctrine/security-posture.md](../doctrine/security-posture.md). CI runs a
secret scan over the full git history on every pull request.
