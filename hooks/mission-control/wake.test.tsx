import { expect, test } from 'claude-code/testing'

import { digestText, ran, start, WAKE, world } from './fixture'

// Minutes of mock clock at the redraw cadence: the default 5 s budget is
// real time, which a loaded runner can spend.
const SLOW = { timeoutMs: 30_000 }
const busy = { text: 'working', turnId: 't1' } as const
const done = { text: '', turnId: 't1', answer: '', durationMs: 5, isAborted: false, reason: 'answer' } as const

// REQ-E1.3, REQ-M1.2: a pending event wakes an idle session within one redraw.
test('a fixture event submits the wake within one redraw while idle', async ($, on) => {
  const w = world(on)
  await $.session.start(start)
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
  await $.session.start(start)
  await $.turn.start(busy)
  w.set({ digest: digestText({ pending: 1 }), wake: WAKE })
  await w.clock.advance(30_000)
  expect(w.submitted).toEqual([])
  expect(ran(w, 'mc-event.sh', 'mark')).toEqual([])
  await $.turn.complete(done)
  expect(w.submitted).toHaveLength(1)
})

test('a held wake animates the radar on the band', async ($, on) => {
  const w = world(on)
  await $.session.start(start)
  await $.turn.start(busy)
  w.set({ digest: digestText({ pending: 1 }), wake: WAKE })
  await w.clock.advance(10_000)
  const ui = await $.ui.mount({
    plugin: 'planwright',
    component: 'AbovePrompt',
    requestId: 'band',
    surface: 'terminal',
    props: { hasSurvey: false, isWorking: true, maxRows: 3, bodyColumns: 120, scroll: { offset: 0, bodyRows: 3 }, view: {} },
  })
  const first = (await ui.find({ type: 'Text', text: /^[◜◝◞◟]/ }))?.text
  await w.clock.advance(500)
  const second = (await ui.find({ type: 'Text', text: /^[◜◝◞◟]/ }))?.text
  expect(first).toBeDefined()
  expect(second).not.toBe(first)
  expect(await ui.find({ type: 'Text', text: /1 inbound/ })).toBeDefined()
  await ui.unmount()
})

// REQ-E1.4: the tick fires at its cadence and starts no turn with nothing due.
test('the tick fires at its cadence without a turn when nothing is due', SLOW, async ($, on) => {
  const w = world(on)
  await $.session.start(start)
  await w.clock.advance(299_000)
  expect(ran(w, 'mc-wake.sh', 'compose')).toEqual([])
  await w.clock.advance(1_000)
  expect(ran(w, 'mc-wake.sh', 'compose')).toHaveLength(1)
  await w.clock.advance(300_000)
  expect(ran(w, 'mc-wake.sh', 'compose')).toHaveLength(2)
  expect(w.submitted).toEqual([])
  const ui = await $.ui.mount({
    plugin: 'planwright',
    component: 'Pane',
    requestId: 'mission-control',
    surface: 'desktop',
    props: { title: 'Mission control', isFocused: false, bodyColumns: 60, placement: 'dock', scroll: { offset: 0, bodyRows: 40 }, view: {} },
  })
  expect((await ui.find({ type: 'Text', text: /failsafe tick/ }))?.text).toBe('failsafe tick fired 2×')
  await ui.unmount()
})

// REQ-E1.4: the push missed an event (its read failed); the tick finds it.
test('the tick submits its prompt when due and idle', SLOW, async ($, on) => {
  const w = world(on)
  await $.session.start(start)
  w.set({ digest: digestText({ extra: ['unreadable\tevents'] }), wake: WAKE })
  await w.clock.advance(290_000)
  expect(w.submitted).toEqual([])
  await w.clock.advance(10_000)
  expect(w.submitted).toEqual(['Failsafe tick. mission control (alpha): 1 event(s) pending.\n- pr-ready pr-7'])
})

test('the tick holds its prompt while the session is busy', SLOW, async ($, on) => {
  const w = world(on, { wake: WAKE })
  await $.session.start(start)
  await $.turn.start(busy)
  await w.clock.advance(300_000)
  expect(w.submitted).toEqual([])
})

// REQ-F1.4's input (tower-comms D-23): prompt events feed the presence marker.
test('an operator prompt records presence; the mod own prompt does not', async ($, on) => {
  const w = world(on)
  await $.session.start(start)
  const before = ran(w, 'mc-panel.sh', 'presence').length
  await $.prompt.submit({ text: 'status?', origin: { kind: 'composer' }, wait: false })
  const after = ran(w, 'mc-panel.sh', 'presence')
  expect(after).toHaveLength(before + 1)
  expect(after.at(-1)).toContain('--prompt')
  w.set({ digest: digestText({ pending: 1 }), wake: WAKE })
  await w.clock.advance(10_000)
  expect(ran(w, 'mc-panel.sh', 'presence').filter(r => r.includes('--prompt'))).toHaveLength(1)
})

test('the session end hands the target back to the relay', async ($, on) => {
  const w = world(on)
  await $.session.start(start)
  await $.session.end({ reason: 'other', sessionId: 's1', resume: { id: 's1' } })
  const last = ran(w, 'mc-wake.sh', 'target').at(-1)
  expect(last).toEqual(expect.arrayContaining(['add', 'alpha']))
  expect(last).not.toContain('--mod')
})
