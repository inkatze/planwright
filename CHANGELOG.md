# Changelog

## [0.37.0](https://github.com/inkatze/planwright/compare/v0.36.0...v0.37.0) (2026-09-05)


### Features

* **allocation:** record an observation when a unit needed more than it started with ([#389](https://github.com/inkatze/planwright/issues/389)) ([a1d2f31](https://github.com/inkatze/planwright/commit/a1d2f314e9e50dd18cfc4fe08e1f08dc0e59d293))
* **fleet:** classify every worker into four positive states with its owner ([#400](https://github.com/inkatze/planwright/issues/400)) ([e69806c](https://github.com/inkatze/planwright/commit/e69806c1cfdef49fd9352dfad14853e3ef3d93b9))
* **fleet:** register every dispatch and stamp it with its tower ([#387](https://github.com/inkatze/planwright/issues/387)) ([01c58e4](https://github.com/inkatze/planwright/commit/01c58e4e49a7a899ef0a8267fbc9f74cf7f2f97d))
* **guard:** screen committed coordination artifacts for peer operational detail ([#396](https://github.com/inkatze/planwright/issues/396)) ([d34475f](https://github.com/inkatze/planwright/commit/d34475f13b2718b75940befee23116d95e2806ec))
* **guards:** flag cd substitutions missing unset CDPATH, pin lint:md template scope ([#398](https://github.com/inkatze/planwright/issues/398)) ([abdf9d9](https://github.com/inkatze/planwright/commit/abdf9d9ae5fb83af3a90562efa0e399a1821d2a0))
* **guards:** follow the mise task graph when keeping evals out of CI ([#397](https://github.com/inkatze/planwright/issues/397)) ([8383643](https://github.com/inkatze/planwright/commit/8383643370eaaf6a8c215b18397214bf6c921b4c))
* **release:** skip the release proposal while a publish is pending ([#382](https://github.com/inkatze/planwright/issues/382)) ([c3a8465](https://github.com/inkatze/planwright/commit/c3a846558c57210d96d15a6a6417c7e396ba626e))
* **skills:** cross-check enumerated claims at drafting and sign-off ([#392](https://github.com/inkatze/planwright/issues/392)) ([3acdc8e](https://github.com/inkatze/planwright/commit/3acdc8ea330fa4a144269a1cd49ab6f668acbba9))
* **spec-kickoff:** re-anchor before the push when a fix lands after sign-off ([#395](https://github.com/inkatze/planwright/issues/395)) ([77b6ae1](https://github.com/inkatze/planwright/commit/77b6ae16cb989e3df55ae08922bc94ea28d32e81))
* **spec:** prose-disposition kickoff sign-off ([#410](https://github.com/inkatze/planwright/issues/410)) ([dc0442a](https://github.com/inkatze/planwright/commit/dc0442a9e9aea6240073ed848d80055ec5bab9f8))

## [0.36.0](https://github.com/inkatze/planwright/compare/v0.35.0...v0.36.0) (2026-09-02)


### Features

* **spec:** tower-front-door kickoff sign-off ([#377](https://github.com/inkatze/planwright/issues/377)) ([045861c](https://github.com/inkatze/planwright/commit/045861cca0d5b20aceffdb91a1c1e57fdeaf60e6))

## [0.35.0](https://github.com/inkatze/planwright/compare/v0.34.0...v0.35.0) (2026-08-31)


### Features

* **allocation:** adapt a unit's tier from its own ledger at each launch ([#370](https://github.com/inkatze/planwright/issues/370)) ([0988084](https://github.com/inkatze/planwright/commit/098808442dc583aca891f30a4ef4d7ba95da5217))
* **allocation:** resolve model and effort at every launch point ([#357](https://github.com/inkatze/planwright/issues/357)) ([7af710c](https://github.com/inkatze/planwright/commit/7af710c7f1d99ccec5ebe9f61b15570fa7a92ee6))
* **doctrine:** arbitrate what reaches the operator versus what the record keeps ([#362](https://github.com/inkatze/planwright/issues/362)) ([14763bb](https://github.com/inkatze/planwright/commit/14763bbfdb6ccb982cdcc663967d855b5a353e98))
* **doctrine:** give every worker resource an open, a close, and a stuck-detector ([#358](https://github.com/inkatze/planwright/issues/358)) ([f536eed](https://github.com/inkatze/planwright/commit/f536eed421dbd947232b706aafdb0f3c7214973f))
* **drain:** reconcile the gate evaluator with the six-status lifecycle (task 4) ([#367](https://github.com/inkatze/planwright/issues/367)) ([ff1f67b](https://github.com/inkatze/planwright/commit/ff1f67b86cb363fa724de922c34473a83fbf3eb4))
* **execute-task:** keep the converging branch current with main ([#359](https://github.com/inkatze/planwright/issues/359)) ([3d757f3](https://github.com/inkatze/planwright/commit/3d757f3661606d754c0f3295d0b099a0aa4399dd))
* **fence:** claim a unit on origin so two towers cannot dispatch it ([#369](https://github.com/inkatze/planwright/issues/369)) ([3db8932](https://github.com/inkatze/planwright/commit/3db893273612327cf08da06e1e96c7810fb3e8c1))
* **fleet:** per-tower checkouts with a fast-forward-only main sync ([#360](https://github.com/inkatze/planwright/issues/360)) ([885bccc](https://github.com/inkatze/planwright/commit/885bccc68a487d5bfefe7eac83f79c0b06cdd996))
* **guard:** screen the tree and commits for purged identifiers (guard-coverage task 3) ([#373](https://github.com/inkatze/planwright/issues/373)) ([02b1ddf](https://github.com/inkatze/planwright/commit/02b1ddfa835e8907d5e6dd1b7840f33ef3af5d80))
* **guard:** stand up the anchor-freshness guard and its pre-commit mirror (anchor-integrity task 4) ([#354](https://github.com/inkatze/planwright/issues/354)) ([73dd75f](https://github.com/inkatze/planwright/commit/73dd75fdfef407a73ef9a287ffecafacde840c7b))
* **guard:** tether three doc restatements to the artifacts they restate (guard-coverage task 9) ([#366](https://github.com/inkatze/planwright/issues/366)) ([c33a34b](https://github.com/inkatze/planwright/commit/c33a34b70cc7c044652c5948340f9fbd1007fd6d))
* **hooks:** pin every hook payload and stop registering the one that refuses ([#368](https://github.com/inkatze/planwright/issues/368)) ([c343385](https://github.com/inkatze/planwright/commit/c3433855d5f70768862afc3314ca80538f2beedd))
* **inception:** bundle validator and venture hygiene scaffold (task 2) ([#364](https://github.com/inkatze/planwright/issues/364)) ([93c20d4](https://github.com/inkatze/planwright/commit/93c20d4bfbe1e80e8a9c9b508beeb423a10bf07f))
* **release:** record the bootstrap-sha finding; halt task 10 on contract drift ([#361](https://github.com/inkatze/planwright/issues/361)) ([b98da2b](https://github.com/inkatze/planwright/commit/b98da2b325718037a506f04f24a7393703a04752))
* **skills:** make act-on-findings skills re-anchor the specs they edit ([#365](https://github.com/inkatze/planwright/issues/365)) ([7bf8dce](https://github.com/inkatze/planwright/commit/7bf8dce51f32dbbf32ef3d3fc0bfbc2deebcab6c))
* **spec-parse:** give the line-80 format grammar one home (task 8) ([#355](https://github.com/inkatze/planwright/issues/355)) ([7eaff04](https://github.com/inkatze/planwright/commit/7eaff042e627fc725727861af60badf5ed2de487))
* **spec:** cover the release-please bootstrap race in release-hardening ([#353](https://github.com/inkatze/planwright/issues/353)) ([2e6ada8](https://github.com/inkatze/planwright/commit/2e6ada840583c5d06cb9e04de10c1bb7922e08de))
* **spec:** model-allocation kickoff sign-off ([#356](https://github.com/inkatze/planwright/issues/356)) ([46481ae](https://github.com/inkatze/planwright/commit/46481aeaa3621348d33f4d3c4f30997cf418b820))
* **spec:** operator-dialogue extension kickoff sign-off ([#351](https://github.com/inkatze/planwright/issues/351)) ([08841c0](https://github.com/inkatze/planwright/commit/08841c0f072d7bd406d9a0e04f7684bd796b1359))


### Bug Fixes

* **instructions:** diet the polish start-load back past its restoration target ([#375](https://github.com/inkatze/planwright/issues/375)) ([7407973](https://github.com/inkatze/planwright/commit/7407973e7860018d914e7714796b7ad6e3ff06a3))
* **test:** pin the SIGTERM case by holding the engine in the locked append ([#376](https://github.com/inkatze/planwright/issues/376)) ([18efdf7](https://github.com/inkatze/planwright/commit/18efdf74eb4e700432e139b2ffc46b67b233256e))

## [0.34.0](https://github.com/inkatze/planwright/compare/v0.33.0...v0.34.0) (2026-08-25)


### ⚠ BREAKING CHANGES

* **anchor:** an anchor recorded before this change no longer recomputes. Adopter bundles need the one-time self-re-anchor documented in docs/getting-started.md and doctrine/spec-format.md (Execution validity): classify the anchored-content delta first, then take the machine expression-only entry or, for a meaning-class delta, the re-review ritual the bundle status admits.

### Features

* **anchor:** narrow the content anchor and re-anchor every bundle (anchor-integrity tasks 2+3) ([#344](https://github.com/inkatze/planwright/issues/344)) ([eedad48](https://github.com/inkatze/planwright/commit/eedad48d46ae1999f36cda01e05dbafab6869dd4))
* **guard:** pin the fork-PR posture with a workflow-posture check ([#346](https://github.com/inkatze/planwright/issues/346)) ([731def5](https://github.com/inkatze/planwright/commit/731def53fa2a4525a957c255f0a518ceae4c5112))
* **inception:** domain, lens, evidence, and storage-class doctrine (task 3) ([#345](https://github.com/inkatze/planwright/issues/345)) ([b78ea4e](https://github.com/inkatze/planwright/commit/b78ea4ed9ba138b3b25dd66dce7a030c51cc21d2))
* **spec-parse:** grammar-keyed parser and validator landing (task 6) ([#350](https://github.com/inkatze/planwright/issues/350)) ([1bd20ee](https://github.com/inkatze/planwright/commit/1bd20eeb905bec807c98068ae848faaf488cc23d))
* **spec:** fleet-lifecycle-closure kickoff sign-off ([#347](https://github.com/inkatze/planwright/issues/347)) ([db55986](https://github.com/inkatze/planwright/commit/db5598686d9a1068b59414239d4a662bf4be9ff4))

## [0.33.0](https://github.com/inkatze/planwright/compare/v0.32.1...v0.33.0) (2026-07-30)


### Features

* **ready-guard:** deny-emitting PreToolUse guard on the draft-&gt;ready flip ([#336](https://github.com/inkatze/planwright/issues/336)) ([5f2818d](https://github.com/inkatze/planwright/commit/5f2818de57281555fb66774fe541531a67eec0da))

## [0.32.1](https://github.com/inkatze/planwright/compare/v0.32.0...v0.32.1) (2026-07-28)


### Bug Fixes

* **command-guard:** narrow three over-broad screens that defer read-only pre-flight ([#330](https://github.com/inkatze/planwright/issues/330)) ([260b3dd](https://github.com/inkatze/planwright/commit/260b3dd7ffce72c4d2eb90236d69179b89ddd532))
* **fleet:** admit a verified merged PR as worktree-reclaim evidence ([#328](https://github.com/inkatze/planwright/issues/328)) ([c64ce20](https://github.com/inkatze/planwright/commit/c64ce203e9a6004b69b6ad39e9e84f8720c5310a))

## [0.32.0](https://github.com/inkatze/planwright/compare/v0.31.0...v0.32.0) (2026-07-27)


### Features

* **fleet:** rendered status dashboard (execution-backends task 8) ([#320](https://github.com/inkatze/planwright/issues/320)) ([7a9ae12](https://github.com/inkatze/planwright/commit/7a9ae123e61d791da53dd0356be2819e15efe90e))
* **spec-parse:** parked-map and Format-version parses into the shared lib ([#322](https://github.com/inkatze/planwright/issues/322)) ([7e7628f](https://github.com/inkatze/planwright/commit/7e7628f2bdbc2777379c3f71556287fcc6764519))

## [0.31.0](https://github.com/inkatze/planwright/compare/v0.30.0...v0.31.0) (2026-07-24)


### Features

* **backends:** full-session knob and default flip (execution-backends task 5) ([#316](https://github.com/inkatze/planwright/issues/316)) ([a1bde3c](https://github.com/inkatze/planwright/commit/a1bde3c367cf4b4888ce99411633d902cecb2e56))
* **backends:** headless-oneshot dispatch support (execution-backends task 3) ([#314](https://github.com/inkatze/planwright/issues/314)) ([38a6edc](https://github.com/inkatze/planwright/commit/38a6edcba7d04052cb6b2647229274a4b84b1aca))
* **backends:** stream-json-persistent supervisor backend (execution-backends task 4) ([#312](https://github.com/inkatze/planwright/issues/312)) ([7d8d337](https://github.com/inkatze/planwright/commit/7d8d337e06b8ea3318a9ee67c0461565e73c581d))
* **fleet:** agents-json idle oracle for worker liveness (execution-backends task 1) ([#308](https://github.com/inkatze/planwright/issues/308)) ([70f7d4a](https://github.com/inkatze/planwright/commit/70f7d4a8f988bad74605894fd7c9c4d88ca0b3bf))
* **fleet:** backend-agnostic CLI status view (execution-backends task 7) ([#315](https://github.com/inkatze/planwright/issues/315)) ([afe68ea](https://github.com/inkatze/planwright/commit/afe68eabe09e25f44104e30ff5b460b051b61c9c))
* **offload:** work-placement doctrine and /offload skill (execution-backends task 6) ([#311](https://github.com/inkatze/planwright/issues/311)) ([fc33b6c](https://github.com/inkatze/planwright/commit/fc33b6c521b31b1fa1b5c58bb178f047e5c33794))

## [0.30.0](https://github.com/inkatze/planwright/compare/v0.29.0...v0.30.0) (2026-07-23)


### Features

* **backends:** extend capability contract and registry to the 8-field advertisement ([#307](https://github.com/inkatze/planwright/issues/307)) ([46482da](https://github.com/inkatze/planwright/commit/46482da08193ed818ce144d98dcb62f56b0e07b7))
* **doctrine:** add assume-multiplicity and deterministic-attention fleet coordination floors ([#299](https://github.com/inkatze/planwright/issues/299)) ([9ddc764](https://github.com/inkatze/planwright/commit/9ddc76428045e39ede183a33e7239766d6b48b20))
* **fleet:** cross-tower presence publish, discover, and liveness ([#305](https://github.com/inkatze/planwright/issues/305)) ([9151419](https://github.com/inkatze/planwright/commit/9151419eb19518f32147cd59c37975cbdba744d2))
* **guards:** git hook backstop with wire step and detection check (guard-coverage task 2) ([#302](https://github.com/inkatze/planwright/issues/302)) ([5953cd2](https://github.com/inkatze/planwright/commit/5953cd27befd192dd732660a4fe973e4bdc38830))
* **inception:** inception-format doctrine (task 1) ([#300](https://github.com/inkatze/planwright/issues/300)) ([5f87432](https://github.com/inkatze/planwright/commit/5f874324a19c645345b6e9dd955f7cc17a12404c))
* **spec-parse:** found shared spec-parse lib and re-point extract_tasks ([#301](https://github.com/inkatze/planwright/issues/301)) ([f4db79f](https://github.com/inkatze/planwright/commit/f4db79f4901caf7419404417a41714685297120b))
* **spec:** execution-backends kickoff sign-off ([#304](https://github.com/inkatze/planwright/issues/304)) ([b569b1b](https://github.com/inkatze/planwright/commit/b569b1b652f456267fcc0c16d6e6a51b746b7288))
* **spec:** merge-currency-guard kickoff sign-off ([#276](https://github.com/inkatze/planwright/issues/276)) ([7ed0f28](https://github.com/inkatze/planwright/commit/7ed0f288a323bf17b8d67f48c55beee195eb5ce5))

## [0.29.0](https://github.com/inkatze/planwright/compare/v0.28.0...v0.29.0) (2026-07-22)


### Features

* **operator-dialogue:** kickoff acceptance invariants, persona pilots, rubric audit (task 6) ([#296](https://github.com/inkatze/planwright/issues/296)) ([d4a6604](https://github.com/inkatze/planwright/commit/d4a66042b7199ff697dd03a3beceec5d03cc1bef))
* **spec:** concurrent-orchestrator-coordination kickoff sign-off ([#295](https://github.com/inkatze/planwright/issues/295)) ([5140d2a](https://github.com/inkatze/planwright/commit/5140d2ae04fe7a08c54ca5be181017aaad6760b6))

## [0.28.0](https://github.com/inkatze/planwright/compare/v0.27.0...v0.28.0) (2026-07-21)


### Features

* **fleet:** configurable budget-aware model allocation & degrade ladder (task 10) ([#287](https://github.com/inkatze/planwright/issues/287)) ([641de7d](https://github.com/inkatze/planwright/commit/641de7d09d6a74dddb883c78b5f1808a28463a30))
* **self-review:** render-based no-arg spec resolution (skill-rigor task 3) ([#292](https://github.com/inkatze/planwright/issues/292)) ([8648de0](https://github.com/inkatze/planwright/commit/8648de011a5aa31e8d4eef0d678031f196e8cb70))
* **spec-draft:** inline self-critique lens in review-and-validate (task 2) ([#288](https://github.com/inkatze/planwright/issues/288)) ([1249553](https://github.com/inkatze/planwright/commit/124955380cf1de86fdfc94600e751e87d1714566))
* **spec-kickoff:** adaptive-level calibration in the kickoff dialogue (task 4) ([#294](https://github.com/inkatze/planwright/issues/294)) ([8e32f6e](https://github.com/inkatze/planwright/commit/8e32f6e3eabf2012016a872590560613ec0e344a))
* **spec-kickoff:** instantiate interaction disciplines in-band (task 3) ([#290](https://github.com/inkatze/planwright/issues/290)) ([15c6f06](https://github.com/inkatze/planwright/commit/15c6f0659f0547319fac03c958095512595f349a))

## [0.27.0](https://github.com/inkatze/planwright/compare/v0.26.0...v0.27.0) (2026-07-21)


### Features

* **fleet-autonomy:** credit-continuation recovery (task 11) ([#282](https://github.com/inkatze/planwright/issues/282)) ([4b046da](https://github.com/inkatze/planwright/commit/4b046da674d97e2971166d6f4c4bc2240066cf5d))
* **fleet:** proactive shared-aware /usage budget gate + restriction ladder (task 9) ([#284](https://github.com/inkatze/planwright/issues/284)) ([9e4c724](https://github.com/inkatze/planwright/commit/9e4c7248c303334ab7eee1a491b2bf7ad4bf8c66))
* **operator-dialogue:** behavioral eval harness scaffold (task 5) ([#279](https://github.com/inkatze/planwright/issues/279)) ([3cec425](https://github.com/inkatze/planwright/commit/3cec42598c4636c86009971591e5a273d7604f05))
* **operator-dialogue:** self-contained-confirmation rule and structural check (task 2) ([#281](https://github.com/inkatze/planwright/issues/281)) ([7e74539](https://github.com/inkatze/planwright/commit/7e74539be1b403da56368690e7c9da7bf30d3e9f))
* **operator-dialogue:** widen interaction-style to every attended surface (task 1) ([#277](https://github.com/inkatze/planwright/issues/277)) ([2830cb1](https://github.com/inkatze/planwright/commit/2830cb1ecc8acb02c6cd1a347121cdd86f2df9ef))
* **spec-kickoff:** mid-walk lens + post-lens stale-reference sweep (task 7) ([#286](https://github.com/inkatze/planwright/issues/286)) ([f2ec9d0](https://github.com/inkatze/planwright/commit/f2ec9d07b53a2f640cede0e9c386d20613d373d2))
* **spec-kickoff:** pre-flip lint + recorded-claim re-derivation (task 5) ([#283](https://github.com/inkatze/planwright/issues/283)) ([381d87f](https://github.com/inkatze/planwright/commit/381d87f429729ecc0b89791824f485054fd9a09a))
* **spec-kickoff:** ready-flip CI gate + wait-bound config (task 6) ([#285](https://github.com/inkatze/planwright/issues/285)) ([0b237b6](https://github.com/inkatze/planwright/commit/0b237b6fd81de9624ede811a720e9d3dff410a91))

## [0.26.0](https://github.com/inkatze/planwright/compare/v0.25.0...v0.26.0) (2026-07-21)


### Features

* **fleet-hardening:** deterministic D-36 branch naming in the tmux dispatch primitive (task 10) ([#274](https://github.com/inkatze/planwright/issues/274)) ([e079116](https://github.com/inkatze/planwright/commit/e079116a12451856534c6fd59a3ecb96e9cf818e))
* **fleet-hardening:** fallback pane-state detector, footer-only debounced backstop (task 3) ([#263](https://github.com/inkatze/planwright/issues/263)) ([ae35dd6](https://github.com/inkatze/planwright/commit/ae35dd6eadfa9700bc232be0b61bb4e39d6a6ec2))
* **fleet-hardening:** fetch-before-gate dispatch freshness and merge detection ([#257](https://github.com/inkatze/planwright/issues/257)) ([bd54f7d](https://github.com/inkatze/planwright/commit/bd54f7d6ef130e304eb65750fc2b0dd8acff97d3))
* **fleet-hardening:** fork-park attention via the Notification hook (Task 2) ([#259](https://github.com/inkatze/planwright/issues/259)) ([044dd89](https://github.com/inkatze/planwright/commit/044dd891aad7153190c39698c5b59808b369c88d))
* **fleet-hardening:** ghost-text pin in the dispatch launch primitive (task 5) ([#264](https://github.com/inkatze/planwright/issues/264)) ([c6002aa](https://github.com/inkatze/planwright/commit/c6002aa2ee1f69857895881e008dede7a4d727d1))
* **fleet-hardening:** sanctioned tower-observation-to-main carry path (task 9) ([#271](https://github.com/inkatze/planwright/issues/271)) ([5db7bad](https://github.com/inkatze/planwright/commit/5db7badbf3de037a52991d160adeda4b17612d78))
* **fleet-hardening:** structured worker-to-tower decision channel (task 4) ([#268](https://github.com/inkatze/planwright/issues/268)) ([6274bb5](https://github.com/inkatze/planwright/commit/6274bb5fd1d5cb5b2c38c83beac5c44472855643))
* **instruction-headroom:** closing verification and guidance re-land (task 11) ([#273](https://github.com/inkatze/planwright/issues/273)) ([1dc9550](https://github.com/inkatze/planwright/commit/1dc9550b34dceca7b0c876a5e688d670c63ac8cb))
* **instruction-headroom:** execute-task body diet (task 7) ([#266](https://github.com/inkatze/planwright/issues/266)) ([e42ef44](https://github.com/inkatze/planwright/commit/e42ef44d3739ec74ffc508780cb00d150b842f15))
* **instruction-headroom:** guard reverse use-site check (task 5) ([#262](https://github.com/inkatze/planwright/issues/262)) ([db2ec7c](https://github.com/inkatze/planwright/commit/db2ec7c87278ff654b1ba2bba8a95cde9678922e))


### Bug Fixes

* **fleet-hardening:** fork-park survives turn-end Stop (idle_prompt/Stop async race) ([#265](https://github.com/inkatze/planwright/issues/265)) ([ce1a1b8](https://github.com/inkatze/planwright/commit/ce1a1b851bb90b107cdbe5cb641c7ba5539fde95))

## [0.25.0](https://github.com/inkatze/planwright/compare/v0.24.0...v0.25.0) (2026-07-20)


### Features

* **fleet-hardening:** correct-glob allow-rule discipline & check (Task 6) ([#255](https://github.com/inkatze/planwright/issues/255)) ([96d35f9](https://github.com/inkatze/planwright/commit/96d35f95f6bf6469db4ff4c6c7e0d30bd640cfee))
* **fleet-hardening:** tower command-guard & tower-settings profile (task 7) ([#256](https://github.com/inkatze/planwright/issues/256)) ([5a4abad](https://github.com/inkatze/planwright/commit/5a4abadff3d97f54b1dd5ebbe0036a44a0827634))
* **instruction-hygiene:** pending-diet Task field on audit surface, derived offender expectations (task 4) ([#254](https://github.com/inkatze/planwright/issues/254)) ([b3f1357](https://github.com/inkatze/planwright/commit/b3f13571769ad2598703ce54aae907706436fdd0))

## [0.24.0](https://github.com/inkatze/planwright/compare/v0.23.0...v0.24.0) (2026-07-19)


### Features

* **instruction-hygiene:** capped charge for exempt docs on aggregates (task 3) ([#251](https://github.com/inkatze/planwright/issues/251)) ([c3e471f](https://github.com/inkatze/planwright/commit/c3e471f5566895c3db69c12dccf0090724bb64f9))
* **instruction-hygiene:** guard headroom floors, margins, declared-exception + raise (task 2) ([#246](https://github.com/inkatze/planwright/issues/246)) ([bc81dcb](https://github.com/inkatze/planwright/commit/bc81dcbcd0bb25787ff73b05f8682f5d0b12ada6))
* **instruction-hygiene:** headroom policy (floors, ladder, capped charge) ([#232](https://github.com/inkatze/planwright/issues/232)) ([0a6cd30](https://github.com/inkatze/planwright/commit/0a6cd30c0eaff0a118248eebd6e6be2e60766b64))
* **release-hardening:** canonicalize and contain the version_file path ([#243](https://github.com/inkatze/planwright/issues/243)) ([9416696](https://github.com/inkatze/planwright/commit/9416696da0b240b41f4a4a5987e45c9eee56647c))
* **release:** add mise run release-arm task wrapper ([#242](https://github.com/inkatze/planwright/issues/242)) ([8a7cee8](https://github.com/inkatze/planwright/commit/8a7cee8e3caee7420c06b35bdd874b984eaea15a))
* **release:** add require_ci knob to relax only the NONE publish verdict ([#249](https://github.com/inkatze/planwright/issues/249)) ([fa48a44](https://github.com/inkatze/planwright/commit/fa48a44ee7ab7f467602878dcb46b913c6a4f68f))
* **release:** fail-closed comparator signaling ([#248](https://github.com/inkatze/planwright/issues/248)) ([f30d81b](https://github.com/inkatze/planwright/commit/f30d81b98132a99ae664acc4cc8d3f1ef42f6071))
* **release:** shared rl_ci_state with workflow-scoped window-lock exclusion ([#247](https://github.com/inkatze/planwright/issues/247)) ([e1a6e3b](https://github.com/inkatze/planwright/commit/e1a6e3bdb18c268cf3d7e878078b57f154855db8))
* **spec:** fleet-hardening kickoff sign-off ([#245](https://github.com/inkatze/planwright/issues/245)) ([1112bc4](https://github.com/inkatze/planwright/commit/1112bc4df78903e47721bc11e34773bc29467a9c))

## [0.23.0](https://github.com/inkatze/planwright/compare/v0.22.0...v0.23.0) (2026-07-19)


### Features

* **skills:** resolve plugin scripts by literal path in dispatching skills ([#236](https://github.com/inkatze/planwright/issues/236)) ([e907ade](https://github.com/inkatze/planwright/commit/e907ade4d8136ad96a2240ff22481aa7b062ef3b))
* **spec:** worker-permission-ergonomics kickoff sign-off ([#234](https://github.com/inkatze/planwright/issues/234)) ([82f4ffb](https://github.com/inkatze/planwright/commit/82f4ffbd18c20c95d69aa9f67d1318457b6fd360))
* **worker-permission-ergonomics:** wire auto-approve hook into worker-settings ([#238](https://github.com/inkatze/planwright/issues/238)) ([abfad1b](https://github.com/inkatze/planwright/commit/abfad1baa6b958ffbe1796697058db2aaec459be))
* **worker-permission-ergonomics:** worker command-guard PreToolUse hook ([#237](https://github.com/inkatze/planwright/issues/237)) ([8543bfb](https://github.com/inkatze/planwright/commit/8543bfb623137a1a5a0b3b70413088e2d397d6f9))

## [0.22.0](https://github.com/inkatze/planwright/compare/v0.21.0...v0.22.0) (2026-07-18)


### Features

* **fleet:** fleet-stats rendering and the statusline notification channel (fleet-autonomy task 8) ([#229](https://github.com/inkatze/planwright/issues/229)) ([21c56e9](https://github.com/inkatze/planwright/commit/21c56e90546580fda593c5bfbc10f92a615ddb4a))

## [0.21.0](https://github.com/inkatze/planwright/compare/v0.20.0...v0.21.0) (2026-07-18)


### Features

* **fleet:** peer-pane /context context-budget corroboration (fleet-autonomy task 5) ([#215](https://github.com/inkatze/planwright/issues/215)) ([2226446](https://github.com/inkatze/planwright/commit/22264463ccfe28a9b4179558a452518ebd3ca72a))

## [0.20.0](https://github.com/inkatze/planwright/compare/v0.19.0...v0.20.0) (2026-07-18)


### Features

* **fleet:** cleanup, housekeeping sweep & reconcile backstop (fleet-autonomy task 4) ([#216](https://github.com/inkatze/planwright/issues/216)) ([7aeebdd](https://github.com/inkatze/planwright/commit/7aeebdd02452775293503391f9c0227bbb789c2d))
* **fleet:** push-based worker liveness, classifier, crash-loop backoff (fleet-autonomy task 2) ([#214](https://github.com/inkatze/planwright/issues/214)) ([0cf90b1](https://github.com/inkatze/planwright/commit/0cf90b1ff8306a9dacd8fbde9c8cb2d0d99bd58d))
* **spec:** anchor-integrity kickoff sign-off ([#223](https://github.com/inkatze/planwright/issues/223)) ([15a0217](https://github.com/inkatze/planwright/commit/15a02171502122a18d185f1dd16fa7614b637efa))
* **spec:** guard-coverage kickoff sign-off ([#226](https://github.com/inkatze/planwright/issues/226)) ([72d66ee](https://github.com/inkatze/planwright/commit/72d66ee8a3e9b22ab55eface41a332efdf498e1d))
* **spec:** operator-dialogue kickoff sign-off ([#225](https://github.com/inkatze/planwright/issues/225)) ([938cf85](https://github.com/inkatze/planwright/commit/938cf85b40a217897e6f3bb184478fa611163e0a))
* **spec:** release-hardening kickoff sign-off ([#222](https://github.com/inkatze/planwright/issues/222)) ([c6bd51b](https://github.com/inkatze/planwright/commit/c6bd51b19d7dee0a6b2d1dcf1a6ec81369651bde))

## [0.19.0](https://github.com/inkatze/planwright/compare/v0.18.0...v0.19.0) (2026-07-17)


### Features

* **fleet:** tower-liveness watchdog and crash recovery (fleet-autonomy task 3) ([#217](https://github.com/inkatze/planwright/issues/217)) ([f379061](https://github.com/inkatze/planwright/commit/f379061876f2a4d155f79592914e64c38e8cca5d))

## [0.18.0](https://github.com/inkatze/planwright/compare/v0.17.0...v0.18.0) (2026-07-17)


### Features

* **fleet:** resource governance: model, throttle, and auto-mode guards (task 7) ([#213](https://github.com/inkatze/planwright/issues/213)) ([b44b2d5](https://github.com/inkatze/planwright/commit/b44b2d5674553fee15c79fd75486f189176fe962))

## [0.17.0](https://github.com/inkatze/planwright/compare/v0.16.0...v0.17.0) (2026-07-17)


### Features

* **spec:** format-grammar kickoff sign-off ([#219](https://github.com/inkatze/planwright/issues/219)) ([363c1d5](https://github.com/inkatze/planwright/commit/363c1d56daa0a4fd89c0bb4f46796a29b939817b))
* **spec:** instruction-headroom kickoff sign-off ([#212](https://github.com/inkatze/planwright/issues/212)) ([6e24240](https://github.com/inkatze/planwright/commit/6e24240e51aca074fac9eed4410ee23cc12b683e))
* **spec:** skill-rigor kickoff sign-off ([#211](https://github.com/inkatze/planwright/issues/211)) ([d4b4afa](https://github.com/inkatze/planwright/commit/d4b4afa0c85886a357f752a6929ee10da8017531))

## [0.16.0](https://github.com/inkatze/planwright/compare/v0.15.1...v0.16.0) (2026-07-17)


### Features

* **fleet:** shared floors and daemon infrastructure (fleet-autonomy task 1) ([#207](https://github.com/inkatze/planwright/issues/207)) ([a7f6813](https://github.com/inkatze/planwright/commit/a7f6813f2f0d355b5cebb9b15d47b4cb95006d72))

## [0.15.1](https://github.com/inkatze/planwright/compare/v0.15.0...v0.15.1) (2026-07-17)


### Bug Fixes

* **doctrine:** resolve-rule-doc self-locates core doctrine ([#206](https://github.com/inkatze/planwright/issues/206)) ([835ec92](https://github.com/inkatze/planwright/commit/835ec92e3c66f27861a5e37d97ad1417ce58a1ed))

## [0.15.0](https://github.com/inkatze/planwright/compare/v0.14.1...v0.15.0) (2026-07-17)


### Features

* **fleet:** prevent dispatch ghost-text via CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION ([#205](https://github.com/inkatze/planwright/issues/205)) ([ea77871](https://github.com/inkatze/planwright/commit/ea7787108d718027889a9cfcebf4c681bc707292))

## [0.14.1](https://github.com/inkatze/planwright/compare/v0.14.0...v0.14.1) (2026-07-17)


### Bug Fixes

* **sync:** fail closed on a present-but-unreadable requirements.md ([#203](https://github.com/inkatze/planwright/issues/203)) ([fd901f2](https://github.com/inkatze/planwright/commit/fd901f288ba89247cdf2b3aed80bc445928f6fab))

## [0.14.0](https://github.com/inkatze/planwright/compare/v0.13.0...v0.14.0) (2026-07-16)


### Features

* **migrate:** one-shot v1-to-v2 spec migration and live-bundle cutover ([#199](https://github.com/inkatze/planwright/issues/199)) ([1c7d620](https://github.com/inkatze/planwright/commit/1c7d6201413e05e814ad868d1c55619dfad6aabb))

## [0.13.0](https://github.com/inkatze/planwright/compare/v0.12.0...v0.13.0) (2026-07-16)


### Features

* **docs:** version-2 state-layer docs and completion-annotation supersession (Task 8) ([#197](https://github.com/inkatze/planwright/issues/197)) ([d75bd37](https://github.com/inkatze/planwright/commit/d75bd37be5fd7f239d7ef55a139f21aaa6c1f1d5))
* **select:** selector and gate re-sourcing for format-version 2 (invariant-tasks Task 5) ([#196](https://github.com/inkatze/planwright/issues/196)) ([1b3d551](https://github.com/inkatze/planwright/commit/1b3d5517d420459cf24ed74e2538800da907813e))

## [0.12.0](https://github.com/inkatze/planwright/compare/v0.11.0...v0.12.0) (2026-07-15)


### Features

* **skills:** reconcile state-layer skills for format-version 2 (Task 7) ([#194](https://github.com/inkatze/planwright/issues/194)) ([71f2708](https://github.com/inkatze/planwright/commit/71f270859c44a439e6294bfc4f613b36bd84c67b))
* **state:** version-key the tasks.md writer and ledger guard for format-version 2 ([#193](https://github.com/inkatze/planwright/issues/193)) ([517b2f5](https://github.com/inkatze/planwright/commit/517b2f573ab83e3192be2e77fbbc51bd330d9d09))

## [0.11.0](https://github.com/inkatze/planwright/compare/v0.10.0...v0.11.0) (2026-07-15)


### Features

* **status:** derived status render surface (invariant-tasks Task 3) ([#188](https://github.com/inkatze/planwright/issues/188)) ([a0a69b1](https://github.com/inkatze/planwright/commit/a0a69b18093b1097daac11d02b1e0dbba8e125e9))

## [0.10.0](https://github.com/inkatze/planwright/compare/v0.9.0...v0.10.0) (2026-07-15)


### Features

* **doctrine:** define spec-format format-version 2 (invariant ledger) ([#181](https://github.com/inkatze/planwright/issues/181)) ([ca0faa6](https://github.com/inkatze/planwright/commit/ca0faa6a8430bdb1a2d7d060667aed8c822e5d8f))

## [0.9.0](https://github.com/inkatze/planwright/compare/v0.8.0...v0.9.0) (2026-07-15)


### Features

* **instruction-hygiene:** guard-catalog entry, docs, closeout audit (Task 8) ([#182](https://github.com/inkatze/planwright/issues/182)) ([3e49956](https://github.com/inkatze/planwright/commit/3e4995622b65c79273c000a3b89eb4dd770efbb9))

## [0.8.0](https://github.com/inkatze/planwright/compare/v0.7.0...v0.8.0) (2026-07-15)


### Features

* **instruction-hygiene:** diet residual start-load offenders (Task 7.5) ([#179](https://github.com/inkatze/planwright/issues/179)) ([2862196](https://github.com/inkatze/planwright/commit/28621969c0f631336a7127454e026509bc43f8b6))

## [0.7.0](https://github.com/inkatze/planwright/compare/v0.6.0...v0.7.0) (2026-07-15)


### Features

* **spec:** fleet-autonomy kickoff sign-off ([#177](https://github.com/inkatze/planwright/issues/177)) ([7871f57](https://github.com/inkatze/planwright/commit/7871f57d52a38cb2708ee36aa4e1b7c51ed5e021))

## [0.6.0](https://github.com/inkatze/planwright/compare/v0.5.0...v0.6.0) (2026-07-15)


### Features

* **instruction-hygiene:** diet /spec-kickoff, exempt spec-format (Task 7) ([#166](https://github.com/inkatze/planwright/issues/166)) ([99f3e08](https://github.com/inkatze/planwright/commit/99f3e088b645134a333e65fbaea64a3363fd36c6))

## [0.5.0](https://github.com/inkatze/planwright/compare/v0.4.0...v0.5.0) (2026-07-14)


### Features

* **catalog:** add release-tagging guard + versioning-scheme domain (Task 3) ([#159](https://github.com/inkatze/planwright/issues/159)) ([fe235bb](https://github.com/inkatze/planwright/commit/fe235bbdb354f53467ca3f44d1ffba50e6d4222f))
* **gate-wiring:** canonicalize pending-sign-off marker and add emit-time guard ([#150](https://github.com/inkatze/planwright/issues/150)) ([564aeaf](https://github.com/inkatze/planwright/commit/564aeaf12811c363d6328342a6fd1f60179052c9))
* **gate-wiring:** human-first PR-body assembly contract ([#149](https://github.com/inkatze/planwright/issues/149)) ([8197e2c](https://github.com/inkatze/planwright/commit/8197e2c20b5ca14950144b97aacca94d403edede))
* **instruction-hygiene:** diet /execute-task under size budgets (Task 6) ([#167](https://github.com/inkatze/planwright/issues/167)) ([f2587b3](https://github.com/inkatze/planwright/commit/f2587b3d53ea5975ee06cd2cdb9a88c31e06f7b7))
* **instruction-hygiene:** doctrine manifests in all skills (Task 3) ([#160](https://github.com/inkatze/planwright/issues/160)) ([b0765bc](https://github.com/inkatze/planwright/commit/b0765bc1781278fdd10c59877e4ac82f6e8ade52))
* **instruction-hygiene:** size guard, budget knobs, and audit mode (Task 2) ([#157](https://github.com/inkatze/planwright/issues/157)) ([38b15b3](https://github.com/inkatze/planwright/commit/38b15b3c4e01c3a857d8fbef4f3cfc3452ad58b6))
* **obs-consume:** consumption and archival mechanics (Task 4) ([#147](https://github.com/inkatze/planwright/issues/147)) ([ed800ac](https://github.com/inkatze/planwright/commit/ed800ac5abbeff4e22b2a00893e2b495a8368c87))
* **observations:** fragment-substrate cutover — skill reconciliation + migration (Tasks 5–6) ([#152](https://github.com/inkatze/planwright/issues/152)) ([84145b4](https://github.com/inkatze/planwright/commit/84145b4004b951b01130f1eeaa3734d360cdcf04))
* **observations:** render command and drain fragment surfacing (Task 3) ([#146](https://github.com/inkatze/planwright/issues/146)) ([51c5199](https://github.com/inkatze/planwright/commit/51c5199df737493491599270ad93694539ebf9e9))
* **orchestrate:** diet /orchestrate + eval-harness hardening; pilot deferred (Task 5) ([#169](https://github.com/inkatze/planwright/issues/169)) ([78f31bf](https://github.com/inkatze/planwright/commit/78f31bfb0c53a41e45e1ef40a7b7dc77ddfceeaa))
* **prompt-evals:** kept-eval runner, /orchestrate fixtures, CI-exclusion guard (Task 4) ([#162](https://github.com/inkatze/planwright/issues/162)) ([85942fd](https://github.com/inkatze/planwright/commit/85942fd79be51eabbfa48f2b9c2767d9e2463673))
* **release-window:** lock the untagged window with a required CI check ([#154](https://github.com/inkatze/planwright/issues/154)) ([9f3ea17](https://github.com/inkatze/planwright/commit/9f3ea17ef54dd9c3b87b9ae282405171f0b5276f))
* **release:** armed/watch mode for the signed publish flow (Task 10) ([#161](https://github.com/inkatze/planwright/issues/161)) ([68f2cfa](https://github.com/inkatze/planwright/commit/68f2cfa59fad9533a9bc018932995e05e1afc1d9))
* **release:** bookkeeping surfacing + mise run release wrapper ([#155](https://github.com/inkatze/planwright/issues/155)) ([92bca79](https://github.com/inkatze/planwright/commit/92bca79c9dbeed393195bb1c2003365bc7a64761))
* **release:** require signed release tags on this repo + release docs ([#156](https://github.com/inkatze/planwright/issues/156)) ([b932222](https://github.com/inkatze/planwright/commit/b93222284830870334aec05e4b48b1039a5a7313))
* **spec-format:** derived-content authoring guidance ([#151](https://github.com/inkatze/planwright/issues/151)) ([f42cb50](https://github.com/inkatze/planwright/commit/f42cb506d358b7bf4c8defa6146d2b6b3db23bb1))
* **spec:** inception kickoff sign-off ([#168](https://github.com/inkatze/planwright/issues/168)) ([3fbdbac](https://github.com/inkatze/planwright/commit/3fbdbacb26ee45587c93fb51034202c9db40d91c))


### Bug Fixes

* **release:** exclude window-lock from publish CI gate (unblock untagged-window publish) ([#163](https://github.com/inkatze/planwright/issues/163)) ([6983f2c](https://github.com/inkatze/planwright/commit/6983f2c39ec42434368333c35c1495fd52b631a6))

## [0.4.0](https://github.com/inkatze/planwright/compare/v0.3.0...v0.4.0) (2026-07-10)


### Features

* **doctrine:** add the autopilot-reflex rule doc ([#134](https://github.com/inkatze/planwright/issues/134)) ([db4e3f2](https://github.com/inkatze/planwright/commit/db4e3f2d3f13434feb99a2f7acd29af4a123d411))
* **doctrine:** instruction-hygiene rule doc (prompt-hygiene task 1) ([#133](https://github.com/inkatze/planwright/issues/133)) ([1758dee](https://github.com/inkatze/planwright/commit/1758deeffc1095a117a8906fd5c4fb5057fe7454))
* **doctrine:** release-tagging policy note (Task 2) ([#138](https://github.com/inkatze/planwright/issues/138)) ([a134bb2](https://github.com/inkatze/planwright/commit/a134bb22d1dd14180aca4fcdb37c1745cf01e7ed))
* **observations:** add check:obs fragment store CI guard ([#139](https://github.com/inkatze/planwright/issues/139)) ([5d58d84](https://github.com/inkatze/planwright/commit/5d58d845926d0db1604e5dc465ca3d661e0cfa0e))
* **observations:** obs-record fragment recording substrate (Task 1) ([#135](https://github.com/inkatze/planwright/issues/135)) ([6c80f10](https://github.com/inkatze/planwright/commit/6c80f10b158273f5c939ad80aaa16f8fff39cfc6))
* **output-hygiene:** memory-link neutralization rule and standing guard ([#141](https://github.com/inkatze/planwright/issues/141)) ([8b2d932](https://github.com/inkatze/planwright/commit/8b2d9327ec064ebefcb898850c6851133e282001))
* **output-hygiene:** organic completion-annotation stamping (Task 7) ([#136](https://github.com/inkatze/planwright/issues/136)) ([9b1023f](https://github.com/inkatze/planwright/commit/9b1023f680c86db5ae14a31b3468dfd759123a07))
* **release:** publish + comparator scripts, config knobs, tests (Task 4) ([#140](https://github.com/inkatze/planwright/issues/140)) ([3cb3861](https://github.com/inkatze/planwright/commit/3cb38616fa0c72e32ed2476b08a6b0e964caaa0c))
* **release:** release-please PR-only config + adopter template (Task 5) ([#142](https://github.com/inkatze/planwright/issues/142)) ([cff8a76](https://github.com/inkatze/planwright/commit/cff8a762edb9497661f05e01a14dbbe12cb4dc65))
* **scripts:** reference-integrity lint for doctrine cross-tree links ([#132](https://github.com/inkatze/planwright/issues/132)) ([1954cf9](https://github.com/inkatze/planwright/commit/1954cf9c868b0b642851f17b4e4c1b8481cdfe2d))
* **skills:** wire autopilot-reflex altitude gate into spec-draft + spec-kickoff (Task 8) ([#143](https://github.com/inkatze/planwright/issues/143)) ([58d67dd](https://github.com/inkatze/planwright/commit/58d67dda18a167aaed9a97a8357335c64109bf9e))
* **spec:** observation-recording kickoff sign-off ([#128](https://github.com/inkatze/planwright/issues/128)) ([1af51af](https://github.com/inkatze/planwright/commit/1af51afcad2f1c359239305a735c16515e3a0463))
* **spec:** prompt-hygiene kickoff sign-off ([#130](https://github.com/inkatze/planwright/issues/130)) ([1993673](https://github.com/inkatze/planwright/commit/19936738107ac6bab85c58143b2ceec12ce63bac))
