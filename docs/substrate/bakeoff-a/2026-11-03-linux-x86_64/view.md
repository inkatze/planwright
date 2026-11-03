# Bake-off report: library tier

Run `20261103T025308Z-2230262` on `linux-x86_64`:
50 runs per latency measurement,
a 300 s timeout per execution,
51 production differential fixtures.

## Full candidates

| Candidate | Platform | Fixtures passed | Latency median ms | Spread ms | Hook budget | Spawns | Dependencies | Source bytes | Porting rate min/KiB | Review findings/KiB | Review runs |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| go | pass | 51 of 51 | 8.195 | 0.588 | within | 0 | 1 | 12992 | 0.151 | 0.394 | 1 unqualified |
| rust | pass | 51 of 51 | 3.918 | 0.206 | within | 0 | 2 | 17534 | 0.178 | 0.409 | 1 unqualified |
| shell | pass | 51 of 51 | 11.669 | 0.421 | within | 4 | 8 | 5561 | 1.071 | 0.921 | 1 unqualified |

## Comparison points

| Candidate | Platform | Trivial program | Cold start median ms | Spread ms | Binary bytes | Dependencies |
| --- | --- | --- | --- | --- | --- | --- |
| bun | pass | pass | 13.119 | 0.558 | 109123760 | 2 |
| zig | pass | pass | 4.812 | 0.465 | 149336 | 1 |

## Every field

### bun

| Field | Value |
| --- | --- |
| schema | substrate-bakeoff |
| run\_id | 20261103T025308Z-2230262 |
| platform | linux-x86\_64 |
| tier | library |
| runs | 50 |
| timeout\_s | 300 |
| fixture\_set\_count | 51 |
| candidate | bun |
| class | comparison |
| platform\_result | pass |
| delivery\_marketplace | pass |
| delivery\_writer | pass |
| dependency\_count | 2 |
| dependency\_listing | bun-runtime,MIT,2026-10-22,none (embedded in every compiled executable);javascriptcore,LGPL-2.1-or-later,2026-10-22,none (Bun's engine and statically embedded) |
| literal\_path | - |
| offline\_replay | - |
| tests\_passed | - |
| tests\_failed | - |
| fixtures\_executed | - |
| fixture\_results | - |
| latency\_median\_ms | - |
| latency\_spread\_ms | - |
| spawns\_per\_invocation | - |
| distinct\_commands | - |
| source\_bytes | - |
| implementation\_minutes | - |
| review\_runs | - |
| review\_findings | - |
| review\_findings\_per\_kib | - |
| review\_qualification | - |
| porting\_rate\_min\_per\_kib | - |
| baseline\_run\_id | - |
| baseline\_latency\_median\_ms | - |
| baseline\_latency\_spread\_ms | - |
| hook\_budget | - |
| latency\_status\_mismatches | - |
| trivial\_result | pass |
| cold\_start\_median\_ms | 13.119 |
| cold\_start\_spread\_ms | 0.558 |
| binary\_size\_bytes | 109123760 |
| cold\_start\_status\_mismatches | 0 |

### go

| Field | Value |
| --- | --- |
| schema | substrate-bakeoff |
| run\_id | 20261103T025308Z-2230262 |
| platform | linux-x86\_64 |
| tier | library |
| runs | 50 |
| timeout\_s | 300 |
| fixture\_set\_count | 51 |
| candidate | go |
| class | full |
| platform\_result | pass |
| delivery\_marketplace | pass |
| delivery\_writer | pass |
| dependency\_count | 1 |
| dependency\_listing | go-runtime-and-stdlib,BSD-3-Clause,2026-10-19,none (the standard library is the alternative to every third-party package) |
| literal\_path | yes |
| offline\_replay | yes |
| tests\_passed | 51 |
| tests\_failed | 0 |
| fixtures\_executed | 51 |
| fixture\_results | deps/basic:pass,deps/carry-clause:pass,deps/continuation:pass,deps/crlf:pass,deps/directory:pass,deps/duplicates:pass,deps/empty-file:pass,deps/fenced:pass,deps/greedy-lead:pass,deps/latin1-bytes:pass,deps/malformed-heading:pass,deps/missing-file:pass,deps/no-trailing-newline:pass,deps/real-bundle:pass,deps/scope-reset:pass,deps/separators:pass,deps/tabs:pass,deps/unclosed-fence:pass,deps/usage-extra:pass,deps/usage-none:pass,lock/alive-dead:pass,lock/alive-detached:pass,lock/alive-foreign:pass,lock/alive-live:pass,lock/alive-pid-zero:pass,lock/alive-wide-pid:pass,lock/owner-free:pass,lock/owner-held:pass,lock/release-free:pass,lock/release-other:pass,lock/release-own:pass,lock/try-foreign-token:pass,lock/try-free:pass,lock/try-held-dead:pass,lock/try-held-detached:pass,lock/try-held-live:pass,lock/try-missing-dir:pass,lock/try-path-dash:pass,lock/try-path-hash:pass,lock/try-path-slash:pass,lock/try-pid-leading-zero:pass,lock/try-pid-text:pass,lock/try-pid-wide:pass,lock/try-pid-zero:pass,lock/try-squatted-dir:pass,lock/try-squatted-file:pass,lock/try-stale-claim:pass,lock/try-subdir:pass,lock/usage-missing-arg:pass,lock/usage-none:pass,lock/usage-verb:pass |
| latency\_median\_ms | 8.195 |
| latency\_spread\_ms | 0.588 |
| spawns\_per\_invocation | 0 |
| distinct\_commands | 0 |
| source\_bytes | 12992 |
| implementation\_minutes | 1.9 |
| review\_runs | 1 |
| review\_findings | 5 |
| review\_findings\_per\_kib | 0.394 |
| review\_qualification | unqualified |
| porting\_rate\_min\_per\_kib | 0.151 |
| baseline\_run\_id | 20261103T025308Z-2230262 |
| baseline\_latency\_median\_ms | 11.669 |
| baseline\_latency\_spread\_ms | 0.421 |
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
| run\_id | 20261103T025308Z-2230262 |
| platform | linux-x86\_64 |
| tier | library |
| runs | 50 |
| timeout\_s | 300 |
| fixture\_set\_count | 51 |
| candidate | rust |
| class | full |
| platform\_result | pass |
| delivery\_marketplace | pass |
| delivery\_writer | pass |
| dependency\_count | 2 |
| dependency\_listing | rust-std,MIT OR Apache-2.0,2026-07-16,none (the standard library is the alternative to every crate);glibc,LGPL-2.1-or-later,2026-09-03,musl (MIT) by building for the musl target (glibc is linked in on glibc Linux only) |
| literal\_path | yes |
| offline\_replay | yes |
| tests\_passed | 51 |
| tests\_failed | 0 |
| fixtures\_executed | 51 |
| fixture\_results | deps/basic:pass,deps/carry-clause:pass,deps/continuation:pass,deps/crlf:pass,deps/directory:pass,deps/duplicates:pass,deps/empty-file:pass,deps/fenced:pass,deps/greedy-lead:pass,deps/latin1-bytes:pass,deps/malformed-heading:pass,deps/missing-file:pass,deps/no-trailing-newline:pass,deps/real-bundle:pass,deps/scope-reset:pass,deps/separators:pass,deps/tabs:pass,deps/unclosed-fence:pass,deps/usage-extra:pass,deps/usage-none:pass,lock/alive-dead:pass,lock/alive-detached:pass,lock/alive-foreign:pass,lock/alive-live:pass,lock/alive-pid-zero:pass,lock/alive-wide-pid:pass,lock/owner-free:pass,lock/owner-held:pass,lock/release-free:pass,lock/release-other:pass,lock/release-own:pass,lock/try-foreign-token:pass,lock/try-free:pass,lock/try-held-dead:pass,lock/try-held-detached:pass,lock/try-held-live:pass,lock/try-missing-dir:pass,lock/try-path-dash:pass,lock/try-path-hash:pass,lock/try-path-slash:pass,lock/try-pid-leading-zero:pass,lock/try-pid-text:pass,lock/try-pid-wide:pass,lock/try-pid-zero:pass,lock/try-squatted-dir:pass,lock/try-squatted-file:pass,lock/try-stale-claim:pass,lock/try-subdir:pass,lock/usage-missing-arg:pass,lock/usage-none:pass,lock/usage-verb:pass |
| latency\_median\_ms | 3.918 |
| latency\_spread\_ms | 0.206 |
| spawns\_per\_invocation | 0 |
| distinct\_commands | 0 |
| source\_bytes | 17534 |
| implementation\_minutes | 3.0 |
| review\_runs | 1 |
| review\_findings | 7 |
| review\_findings\_per\_kib | 0.409 |
| review\_qualification | unqualified |
| porting\_rate\_min\_per\_kib | 0.178 |
| baseline\_run\_id | 20261103T025308Z-2230262 |
| baseline\_latency\_median\_ms | 11.669 |
| baseline\_latency\_spread\_ms | 0.421 |
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
| run\_id | 20261103T025308Z-2230262 |
| platform | linux-x86\_64 |
| tier | library |
| runs | 50 |
| timeout\_s | 300 |
| fixture\_set\_count | 51 |
| candidate | shell |
| class | full |
| platform\_result | pass |
| delivery\_marketplace | pass |
| delivery\_writer | pass |
| dependency\_count | 8 |
| dependency\_listing | awk,system,-,-;date,system,-,-;ln,system,-,-;mv,system,-,-;ps,system,-,-;readlink,system,-,-;rm,system,-,-;tr,system,-,- |
| literal\_path | yes |
| offline\_replay | yes |
| tests\_passed | 51 |
| tests\_failed | 0 |
| fixtures\_executed | 51 |
| fixture\_results | deps/basic:pass,deps/carry-clause:pass,deps/continuation:pass,deps/crlf:pass,deps/directory:pass,deps/duplicates:pass,deps/empty-file:pass,deps/fenced:pass,deps/greedy-lead:pass,deps/latin1-bytes:pass,deps/malformed-heading:pass,deps/missing-file:pass,deps/no-trailing-newline:pass,deps/real-bundle:pass,deps/scope-reset:pass,deps/separators:pass,deps/tabs:pass,deps/unclosed-fence:pass,deps/usage-extra:pass,deps/usage-none:pass,lock/alive-dead:pass,lock/alive-detached:pass,lock/alive-foreign:pass,lock/alive-live:pass,lock/alive-pid-zero:pass,lock/alive-wide-pid:pass,lock/owner-free:pass,lock/owner-held:pass,lock/release-free:pass,lock/release-other:pass,lock/release-own:pass,lock/try-foreign-token:pass,lock/try-free:pass,lock/try-held-dead:pass,lock/try-held-detached:pass,lock/try-held-live:pass,lock/try-missing-dir:pass,lock/try-path-dash:pass,lock/try-path-hash:pass,lock/try-path-slash:pass,lock/try-pid-leading-zero:pass,lock/try-pid-text:pass,lock/try-pid-wide:pass,lock/try-pid-zero:pass,lock/try-squatted-dir:pass,lock/try-squatted-file:pass,lock/try-stale-claim:pass,lock/try-subdir:pass,lock/usage-missing-arg:pass,lock/usage-none:pass,lock/usage-verb:pass |
| latency\_median\_ms | 11.669 |
| latency\_spread\_ms | 0.421 |
| spawns\_per\_invocation | 4 |
| distinct\_commands | 8 |
| source\_bytes | 5561 |
| implementation\_minutes | 5.8 |
| review\_runs | 1 |
| review\_findings | 5 |
| review\_findings\_per\_kib | 0.921 |
| review\_qualification | unqualified |
| porting\_rate\_min\_per\_kib | 1.071 |
| baseline\_run\_id | 20261103T025308Z-2230262 |
| baseline\_latency\_median\_ms | 11.669 |
| baseline\_latency\_spread\_ms | 0.421 |
| hook\_budget | within |
| latency\_status\_mismatches | 0 |
| trivial\_result | - |
| cold\_start\_median\_ms | - |
| cold\_start\_spread\_ms | - |
| binary\_size\_bytes | - |
| cold\_start\_status\_mismatches | - |

### zig

| Field | Value |
| --- | --- |
| schema | substrate-bakeoff |
| run\_id | 20261103T025308Z-2230262 |
| platform | linux-x86\_64 |
| tier | library |
| runs | 50 |
| timeout\_s | 300 |
| fixture\_set\_count | 51 |
| candidate | zig |
| class | comparison |
| platform\_result | pass |
| delivery\_marketplace | pass |
| delivery\_writer | pass |
| dependency\_count | 1 |
| dependency\_listing | zig-std,MIT,2026-10-01,none (the standard library) |
| literal\_path | - |
| offline\_replay | - |
| tests\_passed | - |
| tests\_failed | - |
| fixtures\_executed | - |
| fixture\_results | - |
| latency\_median\_ms | - |
| latency\_spread\_ms | - |
| spawns\_per\_invocation | - |
| distinct\_commands | - |
| source\_bytes | - |
| implementation\_minutes | - |
| review\_runs | - |
| review\_findings | - |
| review\_findings\_per\_kib | - |
| review\_qualification | - |
| porting\_rate\_min\_per\_kib | - |
| baseline\_run\_id | - |
| baseline\_latency\_median\_ms | - |
| baseline\_latency\_spread\_ms | - |
| hook\_budget | - |
| latency\_status\_mismatches | - |
| trivial\_result | pass |
| cold\_start\_median\_ms | 4.812 |
| cold\_start\_spread\_ms | 0.465 |
| binary\_size\_bytes | 149336 |
| cold\_start\_status\_mismatches | 0 |
