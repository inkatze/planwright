import { expect, test } from 'claude-code/testing'

import { BAND, boot, digestText, done, PANE, ran, turn, world } from './fixture'

const compact = (trigger: 'auto' | 'manual' | 'precompute', agentId?: string) => ({
  trigger,
  messages: [{ role: 'user' as const, text: 'summary of the session', toolUses: [] }],
  ...(agentId ? { agentId } : {}),
})

// D-5, D-29: the active rules come back in the compacted conversation.
test('the compaction hook re-injects the active rules', async ($, on) => {
  const w = world(on)
  await boot($, w)
  const out = await $.session.compact(compact('auto'))
  expect(ran(w, 'mc-rules.sh', 'load')[0]?.slice(3)).toEqual(['alpha'])
  if (out.skip !== undefined) throw new Error(`skipped: ${out.skip}`)
  expect(out.messages).toHaveLength(2)
  expect(out.messages[1]?.role).toBe('user')
  expect(out.messages[1]?.text).toMatch(/^Mission control: the active rules, re-injected after a compaction\./)
  expect(out.messages[1]?.text).toContain('- R1 never merge')
})

test('a second compaction replaces the re-injected rules, never doubles them', async ($, on) => {
  const w = world(on)
  await boot($, w)
  const first = await $.session.compact(compact('manual'))
  if (first.skip !== undefined) throw new Error('skipped')
  const again = await $.session.compact({ trigger: 'manual', messages: [...first.messages] })
  if (again.skip !== undefined) throw new Error('skipped')
  expect(again.messages.filter(m => m.text.startsWith('Mission control: the active rules'))).toHaveLength(1)
})

test('a failed re-injection raises an item and keeps the compaction', async ($, on) => {
  const w = world(on, { rulesExit: 1 })
  await boot($, w)
  const out = await $.session.compact(compact('auto'))
  if (out.skip !== undefined) throw new Error(`skipped: ${out.skip}`)
  expect(out.messages).toHaveLength(1)
  const emitted = ran(w, 'mc-event.sh', 'emit')
  expect(emitted.at(-1)).toEqual(expect.arrayContaining(['rules-reinjection-failed', 'alpha']))
  expect(w.toasts.at(-1)).toMatch(/could not be re-injected/)
})

test('a precompute or a subagent compaction is left alone', async ($, on) => {
  const w = world(on)
  await boot($, w)
  const pre = await $.session.compact(compact('precompute'))
  const sub = await $.session.compact(compact('auto', 'agent-1'))
  expect(pre.messages).toHaveLength(1)
  expect(sub.messages).toHaveLength(1)
  expect(ran(w, 'mc-rules.sh', 'load')).toEqual([])
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect(await ui.find({ type: 'Text', text: /compactions since start 0 / })).toBeDefined()
  await ui.unmount()
})

test('compactions since start count on the pane', async ($, on) => {
  const w = world(on)
  await boot($, w)
  await $.session.compact(compact('manual'))
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect(await ui.find({ type: 'Text', text: /compactions since start 1 / })).toBeDefined()
  await ui.unmount()
})

// REQ-L1.5: each trigger source fires from its fixture.
test('measured context at the threshold raises the handover, on every surface it shows', async ($, on) => {
  const w = world(on, { contextPercent: 69 })
  await boot($, w)
  expect(ran(w, 'mc-event.sh', 'emit')).toEqual([])
  w.set({ contextPercent: 70 })
  await w.clock.advance(10_000)
  const raised = ran(w, 'mc-event.sh', 'emit')
  expect(raised).toHaveLength(1)
  expect(raised[0]?.slice(-3)).toEqual(['handover-due', 'alpha', 'context at 70%'])
  expect(w.toasts.at(-1)).toBe('Mission control: handover due (context at 70%)')
  const pane = await $.ui.mount({ ...PANE, surface: 'desktop' })
  expect(await pane.find({ type: 'Text', text: /^Handover due: context at 70%$/ })).toBeDefined()
  await pane.unmount()
  const band = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect((await band.find({ type: 'Text', text: /✈/ }))?.text).toMatch(/handover due$/)
  await band.unmount()
  await w.clock.advance(10_000)
  expect(ran(w, 'mc-event.sh', 'emit')).toHaveLength(1)
})

test('a failed handover emit is tried again', async ($, on) => {
  const w = world(on, { contextPercent: 80, emitExit: 1 })
  await boot($, w)
  expect(ran(w, 'mc-event.sh', 'emit')).toHaveLength(1)
  w.set({ emitExit: 0 })
  await w.clock.advance(10_000)
  expect(ran(w, 'mc-event.sh', 'emit')).toHaveLength(2)
  await w.clock.advance(10_000)
  expect(ran(w, 'mc-event.sh', 'emit')).toHaveLength(2)
})

test('without a context reading the completed-wake count raises it', async ($, on) => {
  const w = world(on, { contextPercent: undefined })
  await boot($, w)
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
  await boot($, w)
  for (const id of ['a', 'b', 'c', 'd']) {
    await $.turn.start(turn(id))
    await $.turn.complete(done(id))
  }
  expect(ran(w, 'mc-event.sh', 'emit')).toEqual([])
})

test('the compaction ceiling raises it whatever the context reads', async ($, on) => {
  const w = world(on, { contextPercent: 5 })
  await boot($, w)
  await $.session.compact(compact('auto'))
  expect(ran(w, 'mc-event.sh', 'emit')).toEqual([])
  await $.session.compact(compact('auto'))
  expect(ran(w, 'mc-event.sh', 'emit')[0]?.slice(-3)).toEqual(['handover-due', 'alpha', '2 compactions'])
})

// D-29: an automatic compaction waits while a handover can run instead.
test('a due handover defers an automatic compaction where the verb is installed', async ($, on) => {
  const w = world(on, { contextPercent: 80, digest: digestText({ extra: ['handover\tavailable'] }) })
  await boot($, w)
  const auto = await $.session.compact(compact('auto'))
  expect(auto.skip).toMatch(/deferred while the handover is due/)
  const manual = await $.session.compact(compact('manual'))
  expect(manual.skip).toBeUndefined()
  // Read live: the ceiling applies the moment the window reaches it.
  w.set({ contextPercent: 95 })
  const late = await $.session.compact(compact('auto'))
  expect(late.skip).toBeUndefined()
  w.set({ contextPercent: undefined })
  const unmeasured = await $.session.compact(compact('auto'))
  expect(unmeasured.skip).toBeUndefined()
})

test('without the handover verb the compaction runs and re-injects', async ($, on) => {
  const w = world(on, { contextPercent: 80 })
  await boot($, w)
  const out = await $.session.compact(compact('auto'))
  if (out.skip !== undefined) throw new Error(`skipped: ${out.skip}`)
  expect(out.messages.at(-1)?.text).toContain('- R1 never merge')
})
