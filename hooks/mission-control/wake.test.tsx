import { expect, test } from 'claude-code/testing'

import { BAND, boot, digestText, done, PANE, ran, turn, WAKE, world } from './fixture'

// Minutes of mock clock at the redraw cadence: the default 5 s budget is
// real time, which a loaded runner can spend.
const SLOW = { timeoutMs: 30_000 }

const sweepOf = async (ui: { find: (q: { type: string; text: RegExp }) => Promise<{ text?: string } | undefined> }) =>
  (await ui.find({ type: 'Text', text: /^[◜◝◞◟]/ }))?.text

// REQ-E1.3, REQ-M1.2: a pending event wakes an idle session within one redraw.
test('a fixture event submits the wake within one redraw while idle', async ($, on) => {
  const w = world(on)
  await boot($, w)
  expect(ran(w, 'mc-wake.sh', 'target')[0]).toContain('--mod')
  w.set({ digest: digestText({ pending: 1 }), wake: WAKE })
  await w.clock.advance(10_000)
  expect(w.submitted).toEqual(['mission control (alpha): 1 event(s) pending.\n- pr-ready pr-7'])
  const marks = ran(w, 'mc-event.sh', 'mark')
  expect(marks).toHaveLength(1)
  expect(marks[0]?.slice(3)).toEqual(['--program', 'alpha', '--target', 'alpha', 'submitted', 'e1000.ab12'])
})

test('a busy session holds the wake, then gets it when the turn ends', async ($, on) => {
  const w = world(on)
  await boot($, w)
  await $.turn.start(turn('t1'))
  w.set({ digest: digestText({ pending: 1 }), wake: WAKE })
  await w.clock.advance(30_000)
  expect(w.submitted).toEqual([])
  expect(ran(w, 'mc-event.sh', 'mark')).toEqual([])
  await $.turn.complete(done('t1'))
  await w.clock.settle()
  expect(w.submitted).toHaveLength(1)
})

test('a subagent turn does not hold the wake', async ($, on) => {
  const w = world(on)
  await boot($, w)
  await $.turn.start(turn('s1', 'agent-1'))
  w.set({ digest: digestText({ pending: 1 }), wake: WAKE })
  await w.clock.advance(10_000)
  expect(w.submitted).toHaveLength(1)
})

test('a held wake sweeps the radar, which stops once the wake is in', async ($, on) => {
  const w = world(on)
  await boot($, w)
  await $.turn.start(turn('t1'))
  w.set({ digest: digestText({ pending: 1 }), wake: WAKE })
  await w.clock.advance(10_000)
  const ui = await $.ui.mount({ ...BAND, surface: 'terminal', props: { ...BAND.props, isWorking: true } })
  const first = await sweepOf(ui)
  await w.clock.advance(500)
  const second = await sweepOf(ui)
  expect(first).toBeDefined()
  expect(second).not.toBe(first)
  expect(await ui.find({ type: 'Text', text: /1 inbound/ })).toBeDefined()
  await $.turn.complete(done('t1'))
  await w.clock.settle()
  expect(await sweepOf(ui)).toBeUndefined()
  await ui.unmount()
})

// REQ-E1.4: the tick fires at its cadence and starts no turn with nothing due.
test('the tick fires at its cadence without a turn when nothing is due', SLOW, async ($, on) => {
  const w = world(on)
  await boot($, w)
  await w.clock.advance(299_000)
  expect(ran(w, 'mc-wake.sh', 'compose')).toEqual([])
  await w.clock.advance(1_000)
  expect(ran(w, 'mc-wake.sh', 'compose')).toHaveLength(1)
  await w.clock.advance(300_000)
  expect(ran(w, 'mc-wake.sh', 'compose')).toHaveLength(2)
  expect(w.submitted).toEqual([])
  const ui = await $.ui.mount({ ...PANE, surface: 'desktop' })
  expect((await ui.find({ type: 'Text', text: /failsafe tick/ }))?.text).toBe('failsafe tick fired 2×')
  await ui.unmount()
})

// REQ-E1.4: the push missed an event (its read failed); the tick finds it.
test('the tick submits its prompt when due and idle', SLOW, async ($, on) => {
  const w = world(on)
  await boot($, w)
  w.set({ digest: digestText({ extra: ['unreadable\tevents'] }), wake: WAKE })
  await w.clock.advance(290_000)
  expect(w.submitted).toEqual([])
  await w.clock.advance(10_000)
  expect(w.submitted).toEqual(['Failsafe tick. mission control (alpha): 1 event(s) pending.\n- pr-ready pr-7'])
})

test('the tick holds its prompt while the session is busy', SLOW, async ($, on) => {
  const w = world(on, { wake: WAKE })
  await boot($, w)
  await $.turn.start(turn('t1'))
  await w.clock.advance(300_000)
  expect(w.submitted).toEqual([])
})

test('the daemon pause holds the mod too', SLOW, async ($, on) => {
  const paused = digestText({ pending: 1 }).replace(/^rung\t.*$/m, 'rung\tpaused\tthe fleet daemon pause')
  const w = world(on, { wake: WAKE, digest: paused })
  await boot($, w)
  await w.clock.advance(300_000)
  expect(w.submitted).toEqual([])
})

test('a dropped wake is not marked, and is tried again', async ($, on) => {
  const w = world(on, { isDropped: true })
  await boot($, w)
  w.set({ digest: digestText({ pending: 1 }), wake: WAKE })
  await w.clock.advance(10_000)
  expect(ran(w, 'mc-event.sh', 'mark')).toEqual([])
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect((await ui.find({ type: 'Text', text: /dropped/ }))?.text).toBe(
    'Fault: the wake was dropped: a guard refused it',
  )
  await ui.unmount()
  w.set({ isDropped: false })
  await w.clock.advance(10_000)
  expect(w.submitted).toHaveLength(1)
  expect(ran(w, 'mc-event.sh', 'mark')).toHaveLength(1)
})

test('a wake whose events cannot be marked is held for one tick period', SLOW, async ($, on) => {
  const w = world(on, { markExit: 1 })
  await boot($, w)
  w.set({ digest: digestText({ pending: 1 }), wake: WAKE })
  await w.clock.advance(10_000)
  expect(w.submitted).toHaveLength(1)
  expect(w.toasts.at(-1)).toMatch(/could not be marked/)
  await w.clock.advance(280_000)
  expect(w.submitted).toHaveLength(1)
  w.set({ markExit: 0 })
  await w.clock.advance(20_000)
  expect(w.submitted).toHaveLength(2)
})

test('a failed compose is named on the pane', async ($, on) => {
  const w = world(on, { composeExit: 1 })
  await boot($, w)
  w.set({ digest: digestText({ pending: 1 }) })
  await w.clock.advance(10_000)
  expect(w.submitted).toEqual([])
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect(await ui.find({ type: 'Text', text: /the wake could not be composed/ })).toBeDefined()
  await ui.unmount()
})

// The operator queue's presence input (routed tower-comms delta).
test('an operator prompt records presence; another plugin prompt does not', async ($, on) => {
  const w = world(on)
  await boot($, w)
  const prompts = () => ran(w, 'mc-panel.sh', 'presence').filter(r => r.includes('--prompt'))
  await $.prompt.submit({ text: 'status?', origin: { kind: 'composer' }, wait: false })
  await w.clock.settle()
  expect(prompts()).toHaveLength(1)
  await $.prompt.submit({ text: 'hi', origin: { kind: 'plugin', name: 'other' }, wait: false } as never)
  await w.clock.settle()
  expect(prompts()).toHaveLength(1)
})

test('the presence marker is restamped every minute', SLOW, async ($, on) => {
  const w = world(on)
  await boot($, w)
  const refreshes = () => ran(w, 'mc-panel.sh', 'presence').filter(r => r.includes('--refresh')).length
  const first = refreshes()
  await w.clock.advance(60_000)
  expect(refreshes()).toBe(first + 1)
  // The relay reads the target's own lease, which the restamp carries.
  expect(ran(w, 'mc-panel.sh', 'presence').at(-1)).toEqual(expect.arrayContaining(['--target', 'alpha']))
})

test('the session end hands the target back to the relay', async ($, on) => {
  const w = world(on)
  await boot($, w)
  await $.session.end({ reason: 'other', sessionId: 's1', resume: { id: 's1' } })
  const last = ran(w, 'mc-wake.sh', 'target').at(-1)
  expect(last).toEqual(expect.arrayContaining(['add', 'alpha']))
  expect(last).not.toContain('--mod')
})

test('a /clear keeps the target and starts the counts over', async ($, on) => {
  const w = world(on)
  await boot($, w)
  await $.turn.start(turn('t1'))
  await $.turn.complete(done('t1'))
  const claims = ran(w, 'mc-wake.sh', 'target').length
  await $.session.end({ reason: 'clear', sessionId: 's1', resume: { id: 's1' } })
  expect(ran(w, 'mc-wake.sh', 'target')).toHaveLength(claims)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect(await ui.find({ type: 'Text', text: /compactions since start 0 · wakes 0/ })).toBeDefined()
  await ui.unmount()
})

test('a pruned event (mark exit 3) still counts as marked', async ($, on) => {
  const w = world(on, { markExit: 3 })
  await boot($, w)
  w.set({ digest: digestText({ pending: 1 }), wake: WAKE })
  await w.clock.advance(10_000)
  expect(w.toasts).toEqual([])
  w.set({ wake: 'idle' })
  await w.clock.advance(10_000)
  expect(w.submitted).toHaveLength(1)
})

test('a failed claim stays on the pane and is retried until it lands', async ($, on) => {
  const w = world(on, { claimExit: 1 })
  await boot($, w)
  await w.clock.advance(10_000)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect(await ui.find({ type: 'Text', text: /the wake target could not be claimed/ })).toBeDefined()
  const tries = ran(w, 'mc-wake.sh', 'target').length
  expect(tries).toBeGreaterThan(1)
  w.set({ claimExit: 0 })
  await w.clock.advance(10_000)
  await w.clock.advance(10_000)
  expect(ran(w, 'mc-wake.sh', 'target')).toHaveLength(tries + 1)
  expect(await ui.find({ type: 'Text', text: /could not be claimed/ })).toBeUndefined()
  await ui.unmount()
})

test('the presence marker keeps its lease under a slow redraw cadence', SLOW, async ($, on) => {
  const w = world(on, { digest: digestText({ refresh: 600 }) })
  await boot($, w)
  const refreshes = () => ran(w, 'mc-panel.sh', 'presence').filter(r => r.includes('--refresh')).length
  const first = refreshes()
  await w.clock.advance(240_000)
  expect(refreshes()).toBe(first + 4)
})

test('a reload finds the program and target in the view once the variables are cleared', async ($, on) => {
  const w = world(on, { env: { PLANWRIGHT_MC_PROGRAM: 'alpha', PLANWRIGHT_MC_TARGET: 'mc-main' } })
  await boot($, w)
  const before = ran(w, 'mc-wake.sh', 'target').length
  await boot($, w)
  const claims = ran(w, 'mc-wake.sh', 'target')
  expect(claims).toHaveLength(before + 1)
  expect(claims.at(-1)).toEqual(expect.arrayContaining(['alpha', 'mc-main', '--mod']))
})
