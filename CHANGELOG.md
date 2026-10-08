# Changelog

## [0.55.0](https://github.com/inkatze/planwright/compare/v0.54.0...v0.55.0) (2026-10-08)


### Features

* **custom-steps:** add the step pool helper and its config knobs ([#610](https://github.com/inkatze/planwright/issues/610)) ([307c9e0](https://github.com/inkatze/planwright/commit/307c9e05c79d1dddececdc71e2d9d2124f90f7ce))
* **guards:** print echoed expansions with printf and guard the sanitizer source ([#606](https://github.com/inkatze/planwright/issues/606)) ([5f732e8](https://github.com/inkatze/planwright/commit/5f732e87bfa26ead87f9c3573358a574c06aa936))
* **orchestrate:** run the meta-tower's dispatch step in its own session ([#604](https://github.com/inkatze/planwright/issues/604)) ([7cf02aa](https://github.com/inkatze/planwright/commit/7cf02aa6b4ececc795d64886a0b90f677dff4603))
* **spec-location:** name a spec by its bare identifier on every identity seam ([#598](https://github.com/inkatze/planwright/issues/598)) ([49d79cb](https://github.com/inkatze/planwright/commit/49d79cb566c7fba55f6dcd5d58a1c76ba7397fa0))


### Bug Fixes

* **echo-discipline:** restore main's red echo-discipline check by guarding step-pool's helper source ([#612](https://github.com/inkatze/planwright/issues/612)) ([c4ccd98](https://github.com/inkatze/planwright/commit/c4ccd981e9aa03bacace8e93baa49110aaac7af5))
* **guards:** the guards now defer commands containing a shell comment ([#609](https://github.com/inkatze/planwright/issues/609)) ([5b7933b](https://github.com/inkatze/planwright/commit/5b7933b6939cd09efd941e131843d43867b69776))
* **lock-lib:** read a dead lock owner as dead whatever the caller path contains ([#597](https://github.com/inkatze/planwright/issues/597)) ([f0d17a0](https://github.com/inkatze/planwright/commit/f0d17a05052529ae49ab06fa6fb09dea6b7e7e77))
* **streamjson:** report a pending request over an earlier turn's result ([#602](https://github.com/inkatze/planwright/issues/602)) ([2bd4a88](https://github.com/inkatze/planwright/commit/2bd4a882f73a9ce6ac85390801dd386a35e147cb))
* **tests:** keep fleet test suites out of the operator's real fleet registry ([#608](https://github.com/inkatze/planwright/issues/608)) ([9ea089a](https://github.com/inkatze/planwright/commit/9ea089a8abac363e8b34229c97343c63e5620e94))

## [0.54.0](https://github.com/inkatze/planwright/compare/v0.53.0...v0.54.0) (2026-10-06)


### Features

* **check:** describe the detached tmux launch and guard against the old shape ([#589](https://github.com/inkatze/planwright/issues/589)) ([2120b87](https://github.com/inkatze/planwright/commit/2120b87d941034dd825a8bfa85d4532ca81091e7))
* **dispatch:** confirm a tmux worker's startup from its SessionStart hook ([#590](https://github.com/inkatze/planwright/issues/590)) ([5afd9ab](https://github.com/inkatze/planwright/commit/5afd9ab800388404f3ee9afc8c01c55ca5d71530))
* **spec:** quota-handling kickoff sign-off ([#587](https://github.com/inkatze/planwright/issues/587)) ([4001194](https://github.com/inkatze/planwright/commit/40011943fececb61b20a62dd25c4345157fee4de))


### Bug Fixes

* **guard:** defer unexpanded operands and -v forms in both command guards ([#592](https://github.com/inkatze/planwright/issues/592)) ([13b5de0](https://github.com/inkatze/planwright/commit/13b5de0a33acade0a1a452ec84ec3b957036116e))
* **resolve-root:** name core.bare and its repair when a working tree is marked bare ([#586](https://github.com/inkatze/planwright/issues/586)) ([441cdb7](https://github.com/inkatze/planwright/commit/441cdb711c0da1a7efbe7e50e951c10334091fd6))

## [0.53.0](https://github.com/inkatze/planwright/compare/v0.52.0...v0.53.0) (2026-10-05)


### Features

* **tower:** flight lifecycle pushes and the crash policy for flight workers ([#579](https://github.com/inkatze/planwright/issues/579)) ([36e1daa](https://github.com/inkatze/planwright/commit/36e1daa320032b93898c94a45568dc18a310ff0f))

## [0.52.0](https://github.com/inkatze/planwright/compare/v0.51.0...v0.52.0) (2026-10-05)


### Features

* **dispatch:** launch the tmux worker detached, with its safety arms ([#581](https://github.com/inkatze/planwright/issues/581)) ([7fd70ee](https://github.com/inkatze/planwright/commit/7fd70ee448783d3f8a95a4e5fab222fdca123960))
* **spec:** worker-permission-ergonomics extension kickoff sign-off ([#582](https://github.com/inkatze/planwright/issues/582)) ([81fe6eb](https://github.com/inkatze/planwright/commit/81fe6eb423eb4ea43a5ecf9f093845b4b2e09b80))


### Bug Fixes

* **orchestrate:** count dispatch markers across worktrees of a repository ([#576](https://github.com/inkatze/planwright/issues/576)) ([db3fff7](https://github.com/inkatze/planwright/commit/db3fff78e4ca701bdb170b5aa6b1454ef150a752))
* **relay:** stage the tmux relay paste unterminated so one Enter submits it ([#571](https://github.com/inkatze/planwright/issues/571)) ([e933587](https://github.com/inkatze/planwright/commit/e9335871f2c4596538264e6b9b7e771282c3604a))
* **scripts:** restore the executable bit on ready-flip.sh and guard script modes ([#577](https://github.com/inkatze/planwright/issues/577)) ([2a3c028](https://github.com/inkatze/planwright/commit/2a3c028032b2f5175db1b2b8613edbccc4f68c46))

## [0.51.0](https://github.com/inkatze/planwright/compare/v0.50.0...v0.51.0) (2026-10-04)


### Features

* **human-gates:** add the ready-flip helper and its wiring ([#557](https://github.com/inkatze/planwright/issues/557)) ([732a63a](https://github.com/inkatze/planwright/commit/732a63a7cfa122337440db2d5b49fd7bc109a19b))


### Bug Fixes

* **custom-steps:** resolve every point in one pass so the guard fits its deadline ([#561](https://github.com/inkatze/planwright/issues/561)) ([783c2ac](https://github.com/inkatze/planwright/commit/783c2ac6b24448ea53d40d970bd23a4562e59ae8))
* **orchestrate-state:** hold a task whose remote branch carries unmerged work ([#569](https://github.com/inkatze/planwright/issues/569)) ([a29b4f1](https://github.com/inkatze/planwright/commit/a29b4f1ca710392dcb91f68edd26aa65b3502929))
* **ready-flip:** address the cubic findings on the ready-flip helper ([#565](https://github.com/inkatze/planwright/issues/565)) ([c49d28d](https://github.com/inkatze/planwright/commit/c49d28d6a1403414e888bd7615c186191369e552))
* **skills:** issue one plain command per Bash call in dispatched runs ([#568](https://github.com/inkatze/planwright/issues/568)) ([df191ae](https://github.com/inkatze/planwright/commit/df191ae839cf7d6da7fedd80006910a161b7d55b))
* **step-record:** take run ids and records under lock-lib ([#563](https://github.com/inkatze/planwright/issues/563)) ([52326ef](https://github.com/inkatze/planwright/commit/52326ef14de49dd39205478664109c98bdf4c32a))
* **tests:** make the permission-matcher test parse under bash 3.2 ([#567](https://github.com/inkatze/planwright/issues/567)) ([8b38f4a](https://github.com/inkatze/planwright/commit/8b38f4a7e6e2b00b5681cc381c534699f9804562))

## [0.50.0](https://github.com/inkatze/planwright/compare/v0.49.0...v0.50.0) (2026-10-02)


### Features

* **fleet:** deliberate-wedge lifecycle rehearsal ([#553](https://github.com/inkatze/planwright/issues/553)) ([6edf026](https://github.com/inkatze/planwright/commit/6edf0260bb749377d10f291d1ddaaa41feeeffc9))
* **fleet:** dispatch-record reconcile and multi-tower adversarial suite ([#550](https://github.com/inkatze/planwright/issues/550)) ([a885467](https://github.com/inkatze/planwright/commit/a88546746a2279d8fa1328d74dfcbc789d72a341))
* **guards:** add the policy guard and the profile floor ([#549](https://github.com/inkatze/planwright/issues/549)) ([af2690c](https://github.com/inkatze/planwright/commit/af2690c9044dd271c3e814d3deb8a78c68aac5d6))
* **skills:** sign-off prose in the gate-wired skills ([#552](https://github.com/inkatze/planwright/issues/552)) ([fffadbe](https://github.com/inkatze/planwright/commit/fffadbe15627ce0be526474e6a85c198f0a8e66f))
* **spec-location:** migrate the script callers onto the resolved spec root ([#548](https://github.com/inkatze/planwright/issues/548)) ([dee2dea](https://github.com/inkatze/planwright/commit/dee2dea6add7603d1436323c4e40553efec5bba1))
* **tower:** shared flight sweep and its derived index (tower-front-door task 7) ([#539](https://github.com/inkatze/planwright/issues/539)) ([cb58e33](https://github.com/inkatze/planwright/commit/cb58e3392d49284ed3bdcc6d09aa6ff6fc8c3e3c))
* **worker-guard:** approve declared command step lines ([#551](https://github.com/inkatze/planwright/issues/551)) ([be85b5e](https://github.com/inkatze/planwright/commit/be85b5e281300cf4695e1f2463af1d530385da9e))


### Bug Fixes

* **scripts:** make check-no-ci-evals and tower-queue parse under bash 3.2 ([#556](https://github.com/inkatze/planwright/issues/556)) ([90e3b4b](https://github.com/inkatze/planwright/commit/90e3b4bed821e1456d5d1c41bcbdbbf4c203d0f9))

## [0.49.0](https://github.com/inkatze/planwright/compare/v0.48.0...v0.49.0) (2026-09-30)


### ⚠ BREAKING CHANGES

* **config:** ready_flip_policy ships as unit-owner, so task PRs will be marked ready by the executing skill instead of waiting for a person once the ready-flip helper lands; set ready_flip_policy: human to keep the old behaviour.
* **custom-steps:** the review_sequence config key is removed; rename it to steps_convergence in every layer that sets it.

### Features

* **config:** declare the human-gate policy knobs ([#525](https://github.com/inkatze/planwright/issues/525)) ([a5d5a96](https://github.com/inkatze/planwright/commit/a5d5a965636d51da77e425b6c5ecf1a2e40c68c4))
* **custom-steps:** add step records and the PR-body fold ([#531](https://github.com/inkatze/planwright/issues/531)) ([f9808e5](https://github.com/inkatze/planwright/commit/f9808e527ce1d6bf29a0b3116080253cc94b109b))
* **execute-task:** wire the unit points into /execute-task ([#535](https://github.com/inkatze/planwright/issues/535)) ([ad501ac](https://github.com/inkatze/planwright/commit/ad501ac733ed965a89f76b84e46394312f5bec53))
* **fleet-streamjson:** add a read-only pending verb so a tower can see what a worker is asking ([#538](https://github.com/inkatze/planwright/issues/538)) ([72d10d8](https://github.com/inkatze/planwright/commit/72d10d8fb50311f9e164e34e6f8137ee4a63e7c3))
* **fleet:** check every frame before it reaches a worker's stdin ([#516](https://github.com/inkatze/planwright/issues/516)) ([0700751](https://github.com/inkatze/planwright/commit/07007515d7d170be00a33fce888c8194abbcaa83))
* **fleet:** reap a leaked worker process with fleet-cleanup.sh process ([#523](https://github.com/inkatze/planwright/issues/523)) ([c9c3787](https://github.com/inkatze/planwright/commit/c9c37871e6888ed80f1116f3459e5b03aeb66fb7))
* **fleet:** run the periodic sweep on a schedule with an observing reap ([#536](https://github.com/inkatze/planwright/issues/536)) ([56a353e](https://github.com/inkatze/planwright/commit/56a353ed69bebbb2419b8d362c4572bda3e860ea))
* **resolve-root:** add the spec kind with a configurable spec root ([#521](https://github.com/inkatze/planwright/issues/521)) ([821fb2f](https://github.com/inkatze/planwright/commit/821fb2f8d063646e5b26d123da91fb576918b954))
* **sign-off:** record sign-offs in trailers and rebuild the checklist from them ([#530](https://github.com/inkatze/planwright/issues/530)) ([dca8ae4](https://github.com/inkatze/planwright/commit/dca8ae44f3a84d1131a6f0ff7fdcfc0c930fbda0))
* **spec-location:** converge the root chain and overlay layers on the resolver ([#533](https://github.com/inkatze/planwright/issues/533)) ([47667c9](https://github.com/inkatze/planwright/commit/47667c946a071965e27b61087620be1ee75548e5))
* **spec-location:** golden fixture and literal-path guard ([#528](https://github.com/inkatze/planwright/issues/528)) ([a2c0046](https://github.com/inkatze/planwright/commit/a2c004616657f064a734af9be0335f22f578918d))
* **spec:** test-throughput kickoff sign-off ([#522](https://github.com/inkatze/planwright/issues/522)) ([a9b1be5](https://github.com/inkatze/planwright/commit/a9b1be577c6a1a3bae9eb51556b2b2459f091203))
* **test-runner:** share one machine-wide ticket pool across test runs ([#537](https://github.com/inkatze/planwright/issues/537)) ([75c941a](https://github.com/inkatze/planwright/commit/75c941a03a3a4046bdd43bca0acc99bf7c983714))
* **tower:** render and land the visual-flight audit record ([#527](https://github.com/inkatze/planwright/issues/527)) ([2d71e5b](https://github.com/inkatze/planwright/commit/2d71e5b7f62fc457516b2dae2147f26e3a0d0df1))
* **tower:** routing behavioral eval fixtures and the eval-only seam ([#534](https://github.com/inkatze/planwright/issues/534)) ([4e07441](https://github.com/inkatze/planwright/commit/4e07441d83c0615850f12453e8b14d340636002e))


### Bug Fixes

* **guard-wiring:** ignore comment mentions and resolve every mise edge form ([#514](https://github.com/inkatze/planwright/issues/514)) ([12bcc88](https://github.com/inkatze/planwright/commit/12bcc8825d717f1c92a50d20df165fe41658c469))
* **secrets:** allowlist the fleet-cleanup strand-key test fixture ([#526](https://github.com/inkatze/planwright/issues/526)) ([b9a217f](https://github.com/inkatze/planwright/commit/b9a217fb643247f1b975e7edeb59f7858c450a51))
* **spec-location:** rebase the golden fixture on the retired review-sequence knob ([#532](https://github.com/inkatze/planwright/issues/532)) ([4745163](https://github.com/inkatze/planwright/commit/47451636e3e65f4c19efdeb44296ff782263affb))


### Code Refactoring

* **custom-steps:** retire the review-sequence knob; flights run skill steps only ([#524](https://github.com/inkatze/planwright/issues/524)) ([c4a9a83](https://github.com/inkatze/planwright/commit/c4a9a839ac2f6d9e97fb9fa811b3e6b18b0528c5))

## [0.48.0](https://github.com/inkatze/planwright/compare/v0.47.0...v0.48.0) (2026-09-28)


### Features

* **resolve-root:** add an install and repo root resolver ([#510](https://github.com/inkatze/planwright/issues/510)) ([5b83fd4](https://github.com/inkatze/planwright/commit/5b83fd43781f6918c8f8eb6c3cd6948ea359fea6))
* **tower:** dispatch visual flights through /offload to their own worktree ([#511](https://github.com/inkatze/planwright/issues/511)) ([ac21250](https://github.com/inkatze/planwright/commit/ac21250cabb809f77ab70fec6ad288ea8cf79c2b))

## [0.47.0](https://github.com/inkatze/planwright/compare/v0.46.0...v0.47.0) (2026-09-28)


### Features

* **custom-steps:** the steps catalog, the point keys, and the resolver ([#509](https://github.com/inkatze/planwright/issues/509)) ([c63a548](https://github.com/inkatze/planwright/commit/c63a548a4dd2c551de265e4f0c9553a22651e239))


### Bug Fixes

* **scripts:** pass multi-line awk values through ENVIRON ([#508](https://github.com/inkatze/planwright/issues/508)) ([8e4197c](https://github.com/inkatze/planwright/commit/8e4197c8271161c0de13b0ea680fc1868da98cdd))
* **tower:** close the core's security-zone findings ([#512](https://github.com/inkatze/planwright/issues/512)) ([94163a7](https://github.com/inkatze/planwright/commit/94163a76324bcd3843995fac7074423691c1942b))

## [0.46.0](https://github.com/inkatze/planwright/compare/v0.45.0...v0.46.0) (2026-09-25)


### Features

* **guard-coverage:** guard-catalog entries and the registration sweep ([#499](https://github.com/inkatze/planwright/issues/499)) ([db08364](https://github.com/inkatze/planwright/commit/db083647d57eab965ac60fb9fa9c7c2486d2f93a))
* **spec-format:** flight branch and worktree grammar ([#503](https://github.com/inkatze/planwright/issues/503)) ([840bb1c](https://github.com/inkatze/planwright/commit/840bb1ceb1a14a028472dfedf789662e1560595b))
* **spec:** review-effectiveness kickoff sign-off ([#507](https://github.com/inkatze/planwright/issues/507)) ([9fa766f](https://github.com/inkatze/planwright/commit/9fa766fba2e20faa02872c815289e3cfa83af7f9))
* **tower:** the /tower skill core ([#502](https://github.com/inkatze/planwright/issues/502)) ([4a93f21](https://github.com/inkatze/planwright/commit/4a93f21bf62e694ef7cf9464e95a0d1d5ea095af))


### Bug Fixes

* **execute-task:** keep the repo's core.sshCommand in the convergence sync fetch ([#498](https://github.com/inkatze/planwright/issues/498)) ([1016c13](https://github.com/inkatze/planwright/commit/1016c135cab23bc664ba624ae237a1f0ea514ce3))
* **guard-wiring:** stop counting wait_for as a reachability edge ([#504](https://github.com/inkatze/planwright/issues/504)) ([7d031c0](https://github.com/inkatze/planwright/commit/7d031c0185d33a2822c3a97c0dfa8a92b81d26ca))

## [0.45.0](https://github.com/inkatze/planwright/compare/v0.44.0...v0.45.0) (2026-09-24)


### Features

* **operator-dialogue:** instantiate the disciplines at /orchestrate, /resume and /drain ([#492](https://github.com/inkatze/planwright/issues/492)) ([59c8ee4](https://github.com/inkatze/planwright/commit/59c8ee4422a4bbbbf8330f9f0640c86a34b58696))
* **operator-dialogue:** turn-shape eval invariants and sidedness check ([#489](https://github.com/inkatze/planwright/issues/489)) ([297cdc4](https://github.com/inkatze/planwright/commit/297cdc4640cf77cca9c8b7521afa1990eb3dfd99))

## [0.44.0](https://github.com/inkatze/planwright/compare/v0.43.0...v0.44.0) (2026-09-23)


### Features

* **spec:** custom-spec-location kickoff sign-off ([#487](https://github.com/inkatze/planwright/issues/487)) ([3242426](https://github.com/inkatze/planwright/commit/32424263307c518ebb03e878c4027b29348f09f1))
* **spec:** custom-steps kickoff sign-off ([#488](https://github.com/inkatze/planwright/issues/488)) ([8c2c90a](https://github.com/inkatze/planwright/commit/8c2c90a33c42fa4a3e8c4e0b1a0597861292cdf5))
* **spec:** human-gates kickoff sign-off ([#490](https://github.com/inkatze/planwright/issues/490)) ([d1fba9f](https://github.com/inkatze/planwright/commit/d1fba9f4cdc6b7f8e3b616f7d3938ed4bb3f56a3))
* **tower-comms:** route the tower loop's turns through the operator queue ([#486](https://github.com/inkatze/planwright/issues/486)) ([ada82fd](https://github.com/inkatze/planwright/commit/ada82fd20dee2bb7e6a5717643bd92b4a1b2352a))


### Bug Fixes

* **tower-reply-hook:** verify the fleet home, and claim only what the marker stamp guarantees ([#477](https://github.com/inkatze/planwright/issues/477)) ([f41dc06](https://github.com/inkatze/planwright/commit/f41dc0625f2e941cdd93841b851802b1ac7a0002))

## [0.43.0](https://github.com/inkatze/planwright/compare/v0.42.1...v0.43.0) (2026-09-19)


### Features

* **tower-comms:** capture the operator's asks and answer prompts from their written rules ([#475](https://github.com/inkatze/planwright/issues/475)) ([5b78e33](https://github.com/inkatze/planwright/commit/5b78e333a40678606cffd022f84ace2274675a88))
* **tower-comms:** log replies, ticks and delivered turns from the tower (task 2) ([#468](https://github.com/inkatze/planwright/issues/468)) ([687163d](https://github.com/inkatze/planwright/commit/687163db78aa48d15b01f9e0c0ab5bc6b2223c0e))
* **tower-queue:** add the queue store and its verbs ([#467](https://github.com/inkatze/planwright/issues/467)) ([a8011b2](https://github.com/inkatze/planwright/commit/a8011b253ce3d32e0a30cf2370a2da75b6dc5cc5))
* **tower-queue:** deliver the knock, detect away, and push once per departure ([#474](https://github.com/inkatze/planwright/issues/474)) ([e362c0c](https://github.com/inkatze/planwright/commit/e362c0cf512adfdc991d6c3d413ccbca49c06aeb))
* **tower-queue:** settle items on evidence, merge duplicates, catch up ([#471](https://github.com/inkatze/planwright/issues/471)) ([cdcc802](https://github.com/inkatze/planwright/commit/cdcc802b23e613bd800b4afc1b275ca32dc19702))


### Bug Fixes

* **tower-queue:** stop the field guard refusing multi-byte text ([#472](https://github.com/inkatze/planwright/issues/472)) ([f9af67c](https://github.com/inkatze/planwright/commit/f9af67c308a64e4e92f4bb17c97457f246a15344))

## [0.42.1](https://github.com/inkatze/planwright/compare/v0.42.0...v0.42.1) (2026-09-15)


### Bug Fixes

* **guard:** stop deferring read-only commands that stall dispatched workers ([#463](https://github.com/inkatze/planwright/issues/463)) ([5770004](https://github.com/inkatze/planwright/commit/577000493b5ba0e46cc46ca4248341e63f2eb541))

## [0.42.0](https://github.com/inkatze/planwright/compare/v0.41.1...v0.42.0) (2026-09-14)


### Features

* **locks:** one atomic-create advisory lock for the script layer ([#458](https://github.com/inkatze/planwright/issues/458)) ([69c8371](https://github.com/inkatze/planwright/commit/69c8371abb3e92dd0b03c85b46b53b326e1991b3))


### Bug Fixes

* **locks:** stop clearing a working path that a sibling has already moved onto ([#462](https://github.com/inkatze/planwright/issues/462)) ([1e873e5](https://github.com/inkatze/planwright/commit/1e873e592137e9d91922dc85bafbcf7c25dd0a8f))

## [0.41.1](https://github.com/inkatze/planwright/compare/v0.41.0...v0.41.1) (2026-09-13)


### Bug Fixes

* **observations:** sign the carry commit, and stop tracking relay scratch ([#455](https://github.com/inkatze/planwright/issues/455)) ([a0d312b](https://github.com/inkatze/planwright/commit/a0d312b7fa114c51541e1ea29a077eb27b044008))

## [0.41.0](https://github.com/inkatze/planwright/compare/v0.40.0...v0.41.0) (2026-09-13)


### Features

* **doctrine:** add the tower conversation rule doc and its budget raise ([#445](https://github.com/inkatze/planwright/issues/445)) ([4c37bdc](https://github.com/inkatze/planwright/commit/4c37bdc85246c80bacb1bbc618f58085d0dd3ce2))
* **tower-comms:** ship the event log and the scorecard (task 1) ([#451](https://github.com/inkatze/planwright/issues/451)) ([e8b1bbf](https://github.com/inkatze/planwright/commit/e8b1bbf7b610ee19edc7601798cdc21546cc4411))


### Bug Fixes

* **fleet:** approve a worker's opening plugin-script call, and say when it cannot ([#443](https://github.com/inkatze/planwright/issues/443)) ([59dc820](https://github.com/inkatze/planwright/commit/59dc8208c04b922e24506c1c565dab64c0569ee3))
* **fleet:** report the stall class honestly at the dispatch and relay layers ([#444](https://github.com/inkatze/planwright/issues/444)) ([cfe3065](https://github.com/inkatze/planwright/commit/cfe30650a36d1d593f0da519ed326df0062e7af5))
* **guards:** stop one branch's fixture from reddening every sibling's gate ([#453](https://github.com/inkatze/planwright/issues/453)) ([fc36d67](https://github.com/inkatze/planwright/commit/fc36d67b489253e4187c516fab5eb6db0eb45824))

## [0.40.0](https://github.com/inkatze/planwright/compare/v0.39.0...v0.40.0) (2026-09-12)


### Features

* **guards:** hold a budget exception to the margin it was granted at ([#439](https://github.com/inkatze/planwright/issues/439)) ([e7501d7](https://github.com/inkatze/planwright/commit/e7501d7d129e21e5df15490777b04f6f9993ba43))
* **guards:** say why a budget exception went inert, not just that it did ([#432](https://github.com/inkatze/planwright/issues/432)) ([7845727](https://github.com/inkatze/planwright/commit/784572778a1e8d15083458564fd3727ad098fdbc))
* **spec:** tower-comms kickoff sign-off ([#437](https://github.com/inkatze/planwright/issues/437)) ([d10eb82](https://github.com/inkatze/planwright/commit/d10eb82232317d0fa92a086d01d68af5d5a23122))
* **spec:** universal-binary kickoff sign-off ([#436](https://github.com/inkatze/planwright/issues/436)) ([bd0ab0c](https://github.com/inkatze/planwright/commit/bd0ab0c777a4258d30457cf62b1217cab4032098))


### Bug Fixes

* **dispatch:** let a dispatched worker actually do routine work ([#441](https://github.com/inkatze/planwright/issues/441)) ([17d919b](https://github.com/inkatze/planwright/commit/17d919be6557e3d2dd5d81ae69d61dd3f3e78168))
* **fleet:** write the queue row under the lock that guards what it reflects ([#438](https://github.com/inkatze/planwright/issues/438)) ([85af215](https://github.com/inkatze/planwright/commit/85af215d1de000fa124ce424cf0282afff3a14da))

## [0.39.0](https://github.com/inkatze/planwright/compare/v0.38.0...v0.39.0) (2026-09-08)


### Features

* **guards:** gate the test suite's wall-clock against committed budgets ([#403](https://github.com/inkatze/planwright/issues/403)) ([c75f006](https://github.com/inkatze/planwright/commit/c75f006de418a22b7509a8828277ac6ee22854a0))
* **validator:** doctrine-grounded hardening rules (format-grammar task 3) ([#401](https://github.com/inkatze/planwright/issues/401)) ([d866e67](https://github.com/inkatze/planwright/commit/d866e6799c8ea898815923ca839fa00345273b40))


### Bug Fixes

* **fleet:** give the fleet lock a primitive that actually excludes ([#409](https://github.com/inkatze/planwright/issues/409)) ([2dc5363](https://github.com/inkatze/planwright/commit/2dc53636a536a244a212502180c8974cf0c264dd))

## [0.38.0](https://github.com/inkatze/planwright/compare/v0.37.0...v0.38.0) (2026-09-08)


### Features

* **allocation:** state the model roster once and keep the top escalation-only ([#422](https://github.com/inkatze/planwright/issues/422)) ([d50aef0](https://github.com/inkatze/planwright/commit/d50aef0cecb3cab9d5fd0362b5a7a8835bfd565a))
* **fleet:** give the stream-json rung a close verb and a single-initiator launch ([#399](https://github.com/inkatze/planwright/issues/399)) ([f6f3e2b](https://github.com/inkatze/planwright/commit/f6f3e2b6e12b1cc9ab2c8196f1c46b8997a1773e))
* **guards:** fail the gate on a guard the gate never runs ([#424](https://github.com/inkatze/planwright/issues/424)) ([dec28f1](https://github.com/inkatze/planwright/commit/dec28f1b2ac79c9de344cc41f4b1b517a18d9b75))
* **spec:** fleet-messaging kickoff sign-off ([#426](https://github.com/inkatze/planwright/issues/426)) ([ccdebb7](https://github.com/inkatze/planwright/commit/ccdebb78d31fa9f65b2670cbe2e6fd6399dde571))


### Bug Fixes

* **allocation:** run the escalation feedback loop at a unit's terminal states ([#413](https://github.com/inkatze/planwright/issues/413)) ([3877751](https://github.com/inkatze/planwright/commit/3877751a02f11b4b8052aab99db3dea7c0412894))
* **ci:** lint the PR title on a trigger that can re-check a correction ([#420](https://github.com/inkatze/planwright/issues/420)) ([6f38a80](https://github.com/inkatze/planwright/commit/6f38a80a79abf133057ccb0a4f9306b0ad76e1e2))
* **ci:** stop a frozen commit subject reddening a pull request forever ([#425](https://github.com/inkatze/planwright/issues/425)) ([a1b80d3](https://github.com/inkatze/planwright/commit/a1b80d32908f3398adde78fc80b1ac2fdc4094fa))
* **fleet:** fail closed when the supervisor cannot record or probe its worker ([#427](https://github.com/inkatze/planwright/issues/427)) ([8fec7ea](https://github.com/inkatze/planwright/commit/8fec7ea7a358e65be6de50e5fe2ceb0327599598))
* **test:** close the supervisor the registration fixture leaked every run ([#423](https://github.com/inkatze/planwright/issues/423)) ([a527b86](https://github.com/inkatze/planwright/commit/a527b86e24ea98fd20a9b57e9cbba38490da6df8))

## [0.37.0](https://github.com/inkatze/planwright/compare/v0.36.0...v0.37.0) (2026-09-07)


### Features

* **allocation:** let a worker ask for a different model tier ([#407](https://github.com/inkatze/planwright/issues/407)) ([08953c9](https://github.com/inkatze/planwright/commit/08953c9429b2b38ec95da15bb42aa376e155a2f9))
* **allocation:** per-step selection keys, applied one-directionally ([#411](https://github.com/inkatze/planwright/issues/411)) ([038b8e0](https://github.com/inkatze/planwright/commit/038b8e0d471f7d14819e858d86414298e48fe3b7))
* **allocation:** record an observation when a unit needed more than it started with ([#389](https://github.com/inkatze/planwright/issues/389)) ([a1d2f31](https://github.com/inkatze/planwright/commit/a1d2f314e9e50dd18cfc4fe08e1f08dc0e59d293))
* **allocation:** resolve a launch tier at every launch point, not just the fleet ([#412](https://github.com/inkatze/planwright/issues/412)) ([743ef80](https://github.com/inkatze/planwright/commit/743ef80232e1908cda3d08b281880adeab1871f3))
* **fleet:** classify every worker into four positive states with its owner ([#400](https://github.com/inkatze/planwright/issues/400)) ([e69806c](https://github.com/inkatze/planwright/commit/e69806c1cfdef49fd9352dfad14853e3ef3d93b9))
* **fleet:** register every dispatch and stamp it with its tower ([#387](https://github.com/inkatze/planwright/issues/387)) ([01c58e4](https://github.com/inkatze/planwright/commit/01c58e4e49a7a899ef0a8267fbc9f74cf7f2f97d))
* **guard:** screen committed coordination artifacts for peer operational detail ([#396](https://github.com/inkatze/planwright/issues/396)) ([d34475f](https://github.com/inkatze/planwright/commit/d34475f13b2718b75940befee23116d95e2806ec))
* **guards:** flag cd substitutions missing unset CDPATH, pin lint:md template scope ([#398](https://github.com/inkatze/planwright/issues/398)) ([abdf9d9](https://github.com/inkatze/planwright/commit/abdf9d9ae5fb83af3a90562efa0e399a1821d2a0))
* **guards:** follow the mise task graph when keeping evals out of CI ([#397](https://github.com/inkatze/planwright/issues/397)) ([8383643](https://github.com/inkatze/planwright/commit/8383643370eaaf6a8c215b18397214bf6c921b4c))
* **release:** skip the release proposal while a publish is pending ([#382](https://github.com/inkatze/planwright/issues/382)) ([c3a8465](https://github.com/inkatze/planwright/commit/c3a846558c57210d96d15a6a6417c7e396ba626e))
* **skills:** cross-check enumerated claims at drafting and sign-off ([#392](https://github.com/inkatze/planwright/issues/392)) ([3acdc8e](https://github.com/inkatze/planwright/commit/3acdc8ea330fa4a144269a1cd49ab6f668acbba9))
* **spec-kickoff:** re-anchor before the push when a fix lands after sign-off ([#395](https://github.com/inkatze/planwright/issues/395)) ([77b6ae1](https://github.com/inkatze/planwright/commit/77b6ae16cb989e3df55ae08922bc94ea28d32e81))
* **spec:** prose-disposition kickoff sign-off ([#410](https://github.com/inkatze/planwright/issues/410)) ([dc0442a](https://github.com/inkatze/planwright/commit/dc0442a9e9aea6240073ed848d80055ec5bab9f8))


### Bug Fixes

* **allocation:** hold the ledger health check to the grammar append enforces ([#404](https://github.com/inkatze/planwright/issues/404)) ([76f1ff9](https://github.com/inkatze/planwright/commit/76f1ff9133dc9c4de14ff41e0692655585a7781b))
* **fleet:** stop reading a killed worker's result frame as a completion ([#408](https://github.com/inkatze/planwright/issues/408)) ([d094274](https://github.com/inkatze/planwright/commit/d094274e7d04904027e664384b3f6f6b528a91df))

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
