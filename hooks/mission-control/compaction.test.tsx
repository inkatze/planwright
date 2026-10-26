import { expect, test } from 'claude-code/testing'

import { digestText, ran, start, world } from './fixture'

const compact = (trigger: 'auto' | 'manual') => ({
  trigger,
  messages: [{ role: 'user' as const, text: 'summary of the session', toolUses: [] }],
})
const turn = (id: string) => ({ text: '', turnId: id })
const done = (id: string) =>
  ({ text: '', turnId: id, answer: '', durationMs: 5, isAborted: false, reason: 'answer' }) as const

// D-5, D-29: the active rules come back in the compacted conversation.
test('the compaction hook re-injects the active rules', async ($, on) => {
  const w = world(on)
  await $.session.start(start)
  const out = await $.session.compact(compact('auto'))
  expect(ran(w, 'mc-rules.sh', 'load')[0]?.slice(3)).toEqual(['alpha'])
  if (out.skip !== undefined) throw new Error(`skipped: ${out.skip}`)
  expect(out.messages).toHaveLength(2)
  expect(out.messages[1]?.role).toBe('user')
  expect(out.messages[1]?.text).toMatch(/^Mission control: the active rules, re-injected after a compaction\./)
  expect(out.messages[1]?.text).toContain('- R1 never merge')
})

test('a failed re-injection raises an item and keeps the compaction', async ($, on) => {
  const w = world(on, { rulesExit: 1 })
  await $.session.start(start)
  const out = await $.session.compact(compact('auto'))
  if (out.skip !== undefined) throw new Error(`skipped: ${out.skip}`)
  expect(out.messages).toHaveLength(1)
  const emitted = ran(w, 'mc-event.sh', 'emit')
  expect(emitted.at(-1)).toEqual(expect.arrayContaining(['rules-reinjection-failed', 'alpha']))
  expect(w.toasts.at(-1)).toMatch(/could not be re-injected/)
})

test('compactions since start count on the pane', async ($, on) => {
  world(on)
  await $.session.start(start)
  await $.session.compact(compact('manual'))
  const ui = await $.ui.mount({
    plugin: 'planwright',
    component: 'Pane',
    requestId: 'mission-control',
    surface: 'terminal',
    props: { title: 'Mission control', isFocused: false, bodyColumns: 60, placement: 'dock', scroll: { offset: 0, bodyRows: 40 }, view: {} },
  })
  expect(await ui.find({ type: 'Text', text: /compactions since start 1 / })).toBeDefined()
  await ui.unmount()
})

// REQ-L1.5: each trigger source fires from its fixture.
test('measured context at the threshold raises the handover', async ($, on) => {
  const w = world(on, { contextPercent: 69 })
  await $.session.start(start)
  expect(ran(w, 'mc-event.sh', 'emit')).toEqual([])
  w.set({ contextPercent: 70 })
  await w.clock.advance(10_000)
  const raised = ran(w, 'mc-event.sh', 'emit')
  expect(raised).toHaveLength(1)
  expect(raised[0]?.slice(-3)).toEqual(['handover-due', 'alpha', 'context at 70%'])
  await w.clock.advance(10_000)
  expect(ran(w, 'mc-event.sh', 'emit')).toHaveLength(1)
})

test('without a context reading the completed-wake count raises it', async ($, on) => {
  const w = world(on, { contextPercent: undefined })
  await $.session.start(start)
  for (const id of ['a', 'b']) {
    await $.turn.start(turn(id))
    await $.turn.complete(done(id))
  }
  expect(ran(w, 'mc-event.sh', 'emit')).toEqual([])
  await $.turn.start(turn('c'))
  await $.turn.complete(done('c'))
  expect(ran(w, 'mc-event.sh', 'emit')[0]?.slice(-3)).toEqual(['handover-due', 'alpha', '3 wakes'])
})

test('with context measured, the wake count raises nothing', async ($, on) => {
  const w = world(on, { contextPercent: 10 })
  await $.session.start(start)
  for (const id of ['a', 'b', 'c', 'd']) {
    await $.turn.start(turn(id))
    await $.turn.complete(done(id))
  }
  expect(ran(w, 'mc-event.sh', 'emit')).toEqual([])
})

test('the compaction ceiling raises it whatever the context reads', async ($, on) => {
  const w = world(on, { contextPercent: 5 })
  await $.session.start(start)
  await $.session.compact(compact('auto'))
  expect(ran(w, 'mc-event.sh', 'emit')).toEqual([])
  await $.session.compact(compact('auto'))
  expect(ran(w, 'mc-event.sh', 'emit')[0]?.slice(-3)).toEqual(['handover-due', 'alpha', '2 compactions'])
})

// D-29: an automatic compaction waits while a handover can run instead.
test('a due handover defers an automatic compaction where the verb is installed', async ($, on) => {
  const w = world(on, { contextPercent: 80, digest: digestText({ extra: ['handover\tavailable'] }) })
  await $.session.start(start)
  const auto = await $.session.compact(compact('auto'))
  expect(auto.skip).toMatch(/deferred while the handover is due/)
  const manual = await $.session.compact(compact('manual'))
  expect(manual.skip).toBeUndefined()
  w.set({ contextPercent: 96 })
  await w.clock.advance(10_000)
  const late = await $.session.compact(compact('auto'))
  expect(late.skip).toBeUndefined()
})

test('without the handover verb the compaction runs and re-injects', async ($, on) => {
  world(on, { contextPercent: 80 })
  await $.session.start(start)
  const out = await $.session.compact(compact('auto'))
  expect(out.skip).toBeUndefined()
})
