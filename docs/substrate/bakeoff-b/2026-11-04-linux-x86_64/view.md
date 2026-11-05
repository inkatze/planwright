# Bake-off report: hook tier

Run `20261104T183837Z-3305146` on `linux-x86_64`:
50 runs per latency measurement,
a 300 s timeout per execution,
114 production differential fixtures.

## Full candidates

| Candidate | Platform | Fixtures passed | Latency median ms | Spread ms | Hook budget | Spawns | Dependencies | Source bytes | Porting rate min/KiB | Review findings/KiB | Review runs |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| go | pass | 114 of 114 | 7.995 | 0.703 | within | 0 | 1 | 24195 | 0.205 | 0.169 | 2 qualified |
| rust | pass | 114 of 114 | 0.841 | 0.088 | within | 0 | 2 | 39273 | 0.077 | 0.130 | 2 qualified |
| shell | pass | 114 of 114 | 9.544 | 0.258 | within | 2 | 5 | 8875 | 0.998 | 0.288 | 2 qualified |

## Every field

### go

| Field | Value |
| --- | --- |
| schema | substrate-bakeoff |
| run\_id | 20261104T183837Z-3305146 |
| platform | linux-x86\_64 |
| tier | hook |
| runs | 50 |
| timeout\_s | 300 |
| fixture\_set\_count | 114 |
| candidate | go |
| class | full |
| platform\_result | pass |
| delivery\_marketplace | pass |
| delivery\_writer | pass |
| dependency\_count | 1 |
| dependency\_listing | go-runtime-and-stdlib,BSD-3-Clause,2026-10-19,none (the standard library is the alternative to every third-party package) |
| literal\_path | yes |
| offline\_replay | yes |
| tests\_passed | 114 |
| tests\_failed | 0 |
| fixtures\_executed | 114 |
| fixture\_results | ready/defer-already-ready:pass,ready/defer-behind-conflict-only:pass,ready/defer-current:pass,ready/defer-no-selector:pass,ready/defer-repo-case:pass,ready/defer-sha256-oid:pass,ready/defer-unknown-then-mergeable:pass,ready/defer-unknown-then-ready:pass,ready/deny-bad-base:pass,ready/deny-bad-oid:pass,ready/deny-base-dotdot:pass,ready/deny-base-object:pass,ready/deny-behind:pass,ready/deny-compare-error:pass,ready/deny-compare-garbage:pass,ready/deny-compare-missing:pass,ready/deny-compare-timeout:pass,ready/deny-conflicting:pass,ready/deny-conflicting-control-base:pass,ready/deny-conflicting-hangul-base:pass,ready/deny-conflicting-non-ascii-base:pass,ready/deny-conflicting-quoted-base:pass,ready/deny-conflicting-truncated-base:pass,ready/deny-draft-missing:pass,ready/deny-draft-null:pass,ready/deny-draft-string:pass,ready/deny-duplicate-key:pass,ready/deny-escaped-key:pass,ready/deny-incomplete:pass,ready/deny-mergeable-number:pass,ready/deny-mergeable-other:pass,ready/deny-not-json:pass,ready/deny-not-object:pass,ready/deny-pr-mismatch:pass,ready/deny-repo-mismatch:pass,ready/deny-requery-error:pass,ready/deny-short-oid:pass,ready/deny-unicode-escape-sign:pass,ready/deny-unknown-twice:pass,ready/deny-url-bad-number:pass,ready/deny-url-bad-owner:pass,ready/deny-url-bad-repo:pass,ready/deny-url-no-pull:pass,ready/deny-view-empty:pass,ready/deny-view-error:pass,ready/deny-view-killed:pass,ready/deny-view-rc-malformed:pass,ready/deny-view-timeout:pass,ready/usage-bad-policy:pass,ready/usage-bad-pr:pass,ready/usage-bad-repo:pass,ready/usage-none:pass,tokenize/at-cap:pass,tokenize/blanks-only:pass,tokenize/empty:pass,tokenize/ops-case-terminator:pass,tokenize/ops-control:pass,tokenize/ops-group:pass,tokenize/ops-newline:pass,tokenize/redir-append-both:pass,tokenize/redir-fd-dup:pass,tokenize/redir-heredocs:pass,tokenize/redir-input-dup:pass,tokenize/redir-quoted-digit:pass,tokenize/refuse-ansi-c:pass,tokenize/refuse-arith-bracket:pass,tokenize/refuse-arith-subst:pass,tokenize/refuse-backtick:pass,tokenize/refuse-brace-modifier:pass,tokenize/refuse-brace-subscript:pass,tokenize/refuse-comment:pass,tokenize/refuse-escaped-operator:pass,tokenize/refuse-line-continuation:pass,tokenize/refuse-name-subscript:pass,tokenize/refuse-named-fd:pass,tokenize/refuse-named-fd-both:pass,tokenize/refuse-nested-subst:pass,tokenize/refuse-non-ascii-name:pass,tokenize/refuse-nul:pass,tokenize/refuse-over-cap:pass,tokenize/refuse-process-subst-in:pass,tokenize/refuse-process-subst-out:pass,tokenize/refuse-special-subscript:pass,tokenize/refuse-trailing-backslash:pass,tokenize/refuse-unbalanced-double:pass,tokenize/refuse-zsh-glob-param:pass,tokenize/usage-extra:pass,tokenize/vec-case-folded-key:pass,tokenize/vec-dup-redirect-file:pass,tokenize/vec-env-prefix:pass,tokenize/vec-fail-closed-emission:pass,tokenize/vec-fish-paren:pass,tokenize/vec-git-alias-injection:pass,tokenize/vec-git-config-injection:pass,tokenize/vec-path-escape:pass,tokenize/vec-path-prefixed-verb:pass,tokenize/vec-unknown-flag-writer:pass,tokenize/word-assignment-quoted:pass,tokenize/word-awk-quoted-redirect:pass,tokenize/word-brace-name:pass,tokenize/word-dollar-dq:pass,tokenize/word-dollar-locale-quote:pass,tokenize/word-escaped-letter:pass,tokenize/word-escaped-quote-dq:pass,tokenize/word-glob-brace:pass,tokenize/word-literal-dollar:pass,tokenize/word-mixed-quoting:pass,tokenize/word-newline-in-quotes:pass,tokenize/word-quoted-substitution:pass,tokenize/word-subst-bare:pass,tokenize/word-tab-separated:pass,tokenize/word-zsh-dollar-prefix:pass,tokenize/word-zsh-marks:pass,tokenize/worker-compound:pass |
| latency\_median\_ms | 7.995 |
| latency\_spread\_ms | 0.703 |
| spawns\_per\_invocation | 0 |
| distinct\_commands | 0 |
| source\_bytes | 24195 |
| implementation\_minutes | 4.8 |
| review\_runs | 2 |
| review\_findings | 8 |
| review\_findings\_per\_kib | 0.169 |
| review\_qualification | qualified |
| porting\_rate\_min\_per\_kib | 0.205 |
| baseline\_run\_id | 20261104T183837Z-3305146 |
| baseline\_latency\_median\_ms | 9.544 |
| baseline\_latency\_spread\_ms | 0.258 |
| hook\_budget | within |
| latency\_status\_mismatches | 0 |
| trivial\_result | - |
| cold\_start\_median\_ms | - |
| cold\_start\_spread\_ms | - |
| binary\_size\_bytes | - |
| cold\_start\_status\_mismatches | - |

### rust

| Field | Value |
| --- | --- |
| schema | substrate-bakeoff |
| run\_id | 20261104T183837Z-3305146 |
| platform | linux-x86\_64 |
| tier | hook |
| runs | 50 |
| timeout\_s | 300 |
| fixture\_set\_count | 114 |
| candidate | rust |
| class | full |
| platform\_result | pass |
| delivery\_marketplace | pass |
| delivery\_writer | pass |
| dependency\_count | 2 |
| dependency\_listing | rust-std,MIT OR Apache-2.0,2026-07-16,none (the standard library is the alternative to every crate);glibc,LGPL-2.1-or-later,2026-09-03,musl (MIT) by building for the musl target (glibc is linked in on glibc Linux only) |
| literal\_path | yes |
| offline\_replay | yes |
| tests\_passed | 114 |
| tests\_failed | 0 |
| fixtures\_executed | 114 |
| fixture\_results | ready/defer-already-ready:pass,ready/defer-behind-conflict-only:pass,ready/defer-current:pass,ready/defer-no-selector:pass,ready/defer-repo-case:pass,ready/defer-sha256-oid:pass,ready/defer-unknown-then-mergeable:pass,ready/defer-unknown-then-ready:pass,ready/deny-bad-base:pass,ready/deny-bad-oid:pass,ready/deny-base-dotdot:pass,ready/deny-base-object:pass,ready/deny-behind:pass,ready/deny-compare-error:pass,ready/deny-compare-garbage:pass,ready/deny-compare-missing:pass,ready/deny-compare-timeout:pass,ready/deny-conflicting:pass,ready/deny-conflicting-control-base:pass,ready/deny-conflicting-hangul-base:pass,ready/deny-conflicting-non-ascii-base:pass,ready/deny-conflicting-quoted-base:pass,ready/deny-conflicting-truncated-base:pass,ready/deny-draft-missing:pass,ready/deny-draft-null:pass,ready/deny-draft-string:pass,ready/deny-duplicate-key:pass,ready/deny-escaped-key:pass,ready/deny-incomplete:pass,ready/deny-mergeable-number:pass,ready/deny-mergeable-other:pass,ready/deny-not-json:pass,ready/deny-not-object:pass,ready/deny-pr-mismatch:pass,ready/deny-repo-mismatch:pass,ready/deny-requery-error:pass,ready/deny-short-oid:pass,ready/deny-unicode-escape-sign:pass,ready/deny-unknown-twice:pass,ready/deny-url-bad-number:pass,ready/deny-url-bad-owner:pass,ready/deny-url-bad-repo:pass,ready/deny-url-no-pull:pass,ready/deny-view-empty:pass,ready/deny-view-error:pass,ready/deny-view-killed:pass,ready/deny-view-rc-malformed:pass,ready/deny-view-timeout:pass,ready/usage-bad-policy:pass,ready/usage-bad-pr:pass,ready/usage-bad-repo:pass,ready/usage-none:pass,tokenize/at-cap:pass,tokenize/blanks-only:pass,tokenize/empty:pass,tokenize/ops-case-terminator:pass,tokenize/ops-control:pass,tokenize/ops-group:pass,tokenize/ops-newline:pass,tokenize/redir-append-both:pass,tokenize/redir-fd-dup:pass,tokenize/redir-heredocs:pass,tokenize/redir-input-dup:pass,tokenize/redir-quoted-digit:pass,tokenize/refuse-ansi-c:pass,tokenize/refuse-arith-bracket:pass,tokenize/refuse-arith-subst:pass,tokenize/refuse-backtick:pass,tokenize/refuse-brace-modifier:pass,tokenize/refuse-brace-subscript:pass,tokenize/refuse-comment:pass,tokenize/refuse-escaped-operator:pass,tokenize/refuse-line-continuation:pass,tokenize/refuse-name-subscript:pass,tokenize/refuse-named-fd:pass,tokenize/refuse-named-fd-both:pass,tokenize/refuse-nested-subst:pass,tokenize/refuse-non-ascii-name:pass,tokenize/refuse-nul:pass,tokenize/refuse-over-cap:pass,tokenize/refuse-process-subst-in:pass,tokenize/refuse-process-subst-out:pass,tokenize/refuse-special-subscript:pass,tokenize/refuse-trailing-backslash:pass,tokenize/refuse-unbalanced-double:pass,tokenize/refuse-zsh-glob-param:pass,tokenize/usage-extra:pass,tokenize/vec-case-folded-key:pass,tokenize/vec-dup-redirect-file:pass,tokenize/vec-env-prefix:pass,tokenize/vec-fail-closed-emission:pass,tokenize/vec-fish-paren:pass,tokenize/vec-git-alias-injection:pass,tokenize/vec-git-config-injection:pass,tokenize/vec-path-escape:pass,tokenize/vec-path-prefixed-verb:pass,tokenize/vec-unknown-flag-writer:pass,tokenize/word-assignment-quoted:pass,tokenize/word-awk-quoted-redirect:pass,tokenize/word-brace-name:pass,tokenize/word-dollar-dq:pass,tokenize/word-dollar-locale-quote:pass,tokenize/word-escaped-letter:pass,tokenize/word-escaped-quote-dq:pass,tokenize/word-glob-brace:pass,tokenize/word-literal-dollar:pass,tokenize/word-mixed-quoting:pass,tokenize/word-newline-in-quotes:pass,tokenize/word-quoted-substitution:pass,tokenize/word-subst-bare:pass,tokenize/word-tab-separated:pass,tokenize/word-zsh-dollar-prefix:pass,tokenize/word-zsh-marks:pass,tokenize/worker-compound:pass |
| latency\_median\_ms | 0.841 |
| latency\_spread\_ms | 0.088 |
| spawns\_per\_invocation | 0 |
| distinct\_commands | 0 |
| source\_bytes | 39273 |
| implementation\_minutes | 3.0 |
| review\_runs | 2 |
| review\_findings | 10 |
| review\_findings\_per\_kib | 0.130 |
| review\_qualification | qualified |
| porting\_rate\_min\_per\_kib | 0.077 |
| baseline\_run\_id | 20261104T183837Z-3305146 |
| baseline\_latency\_median\_ms | 9.544 |
| baseline\_latency\_spread\_ms | 0.258 |
| hook\_budget | within |
| latency\_status\_mismatches | 0 |
| trivial\_result | - |
| cold\_start\_median\_ms | - |
| cold\_start\_spread\_ms | - |
| binary\_size\_bytes | - |
| cold\_start\_status\_mismatches | - |

### shell

| Field | Value |
| --- | --- |
| schema | substrate-bakeoff |
| run\_id | 20261104T183837Z-3305146 |
| platform | linux-x86\_64 |
| tier | hook |
| runs | 50 |
| timeout\_s | 300 |
| fixture\_set\_count | 114 |
| candidate | shell |
| class | full |
| platform\_result | pass |
| delivery\_marketplace | pass |
| delivery\_writer | pass |
| dependency\_count | 5 |
| dependency\_listing | awk,system,-,-;bash,system,-,-;jq,system,-,-;sleep,system,-,-;tr,system,-,- |
| literal\_path | yes |
| offline\_replay | yes |
| tests\_passed | 114 |
| tests\_failed | 0 |
| fixtures\_executed | 114 |
| fixture\_results | ready/defer-already-ready:pass,ready/defer-behind-conflict-only:pass,ready/defer-current:pass,ready/defer-no-selector:pass,ready/defer-repo-case:pass,ready/defer-sha256-oid:pass,ready/defer-unknown-then-mergeable:pass,ready/defer-unknown-then-ready:pass,ready/deny-bad-base:pass,ready/deny-bad-oid:pass,ready/deny-base-dotdot:pass,ready/deny-base-object:pass,ready/deny-behind:pass,ready/deny-compare-error:pass,ready/deny-compare-garbage:pass,ready/deny-compare-missing:pass,ready/deny-compare-timeout:pass,ready/deny-conflicting:pass,ready/deny-conflicting-control-base:pass,ready/deny-conflicting-hangul-base:pass,ready/deny-conflicting-non-ascii-base:pass,ready/deny-conflicting-quoted-base:pass,ready/deny-conflicting-truncated-base:pass,ready/deny-draft-missing:pass,ready/deny-draft-null:pass,ready/deny-draft-string:pass,ready/deny-duplicate-key:pass,ready/deny-escaped-key:pass,ready/deny-incomplete:pass,ready/deny-mergeable-number:pass,ready/deny-mergeable-other:pass,ready/deny-not-json:pass,ready/deny-not-object:pass,ready/deny-pr-mismatch:pass,ready/deny-repo-mismatch:pass,ready/deny-requery-error:pass,ready/deny-short-oid:pass,ready/deny-unicode-escape-sign:pass,ready/deny-unknown-twice:pass,ready/deny-url-bad-number:pass,ready/deny-url-bad-owner:pass,ready/deny-url-bad-repo:pass,ready/deny-url-no-pull:pass,ready/deny-view-empty:pass,ready/deny-view-error:pass,ready/deny-view-killed:pass,ready/deny-view-rc-malformed:pass,ready/deny-view-timeout:pass,ready/usage-bad-policy:pass,ready/usage-bad-pr:pass,ready/usage-bad-repo:pass,ready/usage-none:pass,tokenize/at-cap:pass,tokenize/blanks-only:pass,tokenize/empty:pass,tokenize/ops-case-terminator:pass,tokenize/ops-control:pass,tokenize/ops-group:pass,tokenize/ops-newline:pass,tokenize/redir-append-both:pass,tokenize/redir-fd-dup:pass,tokenize/redir-heredocs:pass,tokenize/redir-input-dup:pass,tokenize/redir-quoted-digit:pass,tokenize/refuse-ansi-c:pass,tokenize/refuse-arith-bracket:pass,tokenize/refuse-arith-subst:pass,tokenize/refuse-backtick:pass,tokenize/refuse-brace-modifier:pass,tokenize/refuse-brace-subscript:pass,tokenize/refuse-comment:pass,tokenize/refuse-escaped-operator:pass,tokenize/refuse-line-continuation:pass,tokenize/refuse-name-subscript:pass,tokenize/refuse-named-fd:pass,tokenize/refuse-named-fd-both:pass,tokenize/refuse-nested-subst:pass,tokenize/refuse-non-ascii-name:pass,tokenize/refuse-nul:pass,tokenize/refuse-over-cap:pass,tokenize/refuse-process-subst-in:pass,tokenize/refuse-process-subst-out:pass,tokenize/refuse-special-subscript:pass,tokenize/refuse-trailing-backslash:pass,tokenize/refuse-unbalanced-double:pass,tokenize/refuse-zsh-glob-param:pass,tokenize/usage-extra:pass,tokenize/vec-case-folded-key:pass,tokenize/vec-dup-redirect-file:pass,tokenize/vec-env-prefix:pass,tokenize/vec-fail-closed-emission:pass,tokenize/vec-fish-paren:pass,tokenize/vec-git-alias-injection:pass,tokenize/vec-git-config-injection:pass,tokenize/vec-path-escape:pass,tokenize/vec-path-prefixed-verb:pass,tokenize/vec-unknown-flag-writer:pass,tokenize/word-assignment-quoted:pass,tokenize/word-awk-quoted-redirect:pass,tokenize/word-brace-name:pass,tokenize/word-dollar-dq:pass,tokenize/word-dollar-locale-quote:pass,tokenize/word-escaped-letter:pass,tokenize/word-escaped-quote-dq:pass,tokenize/word-glob-brace:pass,tokenize/word-literal-dollar:pass,tokenize/word-mixed-quoting:pass,tokenize/word-newline-in-quotes:pass,tokenize/word-quoted-substitution:pass,tokenize/word-subst-bare:pass,tokenize/word-tab-separated:pass,tokenize/word-zsh-dollar-prefix:pass,tokenize/word-zsh-marks:pass,tokenize/worker-compound:pass |
| latency\_median\_ms | 9.544 |
| latency\_spread\_ms | 0.258 |
| spawns\_per\_invocation | 2 |
| distinct\_commands | 5 |
| source\_bytes | 8875 |
| implementation\_minutes | 8.7 |
| review\_runs | 2 |
| review\_findings | 5 |
| review\_findings\_per\_kib | 0.288 |
| review\_qualification | qualified |
| porting\_rate\_min\_per\_kib | 0.998 |
| baseline\_run\_id | 20261104T183837Z-3305146 |
| baseline\_latency\_median\_ms | 9.544 |
| baseline\_latency\_spread\_ms | 0.258 |
| hook\_budget | within |
| latency\_status\_mismatches | 0 |
| trivial\_result | - |
| cold\_start\_median\_ms | - |
| cold\_start\_spread\_ms | - |
| binary\_size\_bytes | - |
| cold\_start\_status\_mismatches | - |
