import { expect, test } from 'claude-code/testing'

import { boot, done, PANE, ran, recordFor, SESSION, turn, world } from './fixture'

const OTHER = '99999999-2222-3333-4444-555555555555'

// REQ-F1.16: the skill's record verb, with no environment, activates the panel.
test('with no environment, the record activates the panel within one timer interval', async ($, on) => {
  const w = world(on, { env: {} })
  await boot($, w)
  expect(ran(w, 'mc-panel.sh', 'digest')).toEqual([])
  w.set({ records: { [SESSION]: recordFor('alpha', 'mc-main') } })
  await w.clock.advance(10_000)
  expect(ran(w, 'mc-panel.sh', 'lookup')[0]).toEqual(expect.arrayContaining(['--session', SESSION]))
  expect(ran(w, 'mc-panel.sh', 'digest')[0]).toEqual(expect.arrayContaining(['--program', 'alpha', '--target', 'mc-main']))
  expect(ran(w, 'mc-panel.sh', 'ack')[0]).toEqual(expect.arrayContaining(['--session', SESSION]))
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect((await ui.find({ type: 'Text', text: /Mission control · alpha/ }))?.text).toMatch(/alpha/)
  await ui.unmount()
})

// REQ-F1.16: a session mission control launches carries another id.
test('a record naming another session never activates this one', async ($, on) => {
  const w = world(on, { env: {}, records: { [OTHER]: recordFor('alpha') } })
  await boot($, w)
  await w.clock.advance(60_000)
  expect(ran(w, 'mc-panel.sh', 'lookup')).toEqual([])
  expect(ran(w, 'mc-panel.sh', 'digest')).toEqual([])
  expect(ran(w, 'mc-panel.sh', 'ack')).toEqual([])
})

// REQ-F1.16: a record the lookup refuses (an unknown format) does not activate.
test('a record the lookup refuses does not activate', async ($, on) => {
  const w = world(on, { env: {}, records: { [SESSION]: recordFor('alpha') }, lookupExit: 1 })
  await boot($, w)
  await w.clock.advance(30_000)
  expect(ran(w, 'mc-panel.sh', 'lookup').length).toBeGreaterThan(0)
  expect(ran(w, 'mc-panel.sh', 'digest')).toEqual([])
  expect(ran(w, 'mc-panel.sh', 'ack')).toEqual([])
})

test('the end of a turn checks for the record at once', async ($, on) => {
  const w = world(on, { env: {} })
  await boot($, w)
  w.set({ records: { [SESSION]: recordFor('alpha') } })
  await $.turn.start(turn('t1'))
  await $.turn.complete(done('t1'))
  await w.clock.settle()
  expect(ran(w, 'mc-panel.sh', 'ack')).toHaveLength(1)
})

// REQ-F1.16: the environment variable stays a fast path.
test('the variable activates without a record, and records the activation', async ($, on) => {
  const w = world(on)
  await boot($, w)
  expect(ran(w, 'mc-panel.sh', 'lookup')).toEqual([])
  expect(ran(w, 'mc-panel.sh', 'activate')[0]).toEqual(
    expect.arrayContaining(['--program', 'alpha', '--target', 'alpha', '--session', SESSION]),
  )
  expect(ran(w, 'mc-panel.sh', 'ack')[0]).toEqual(expect.arrayContaining(['--session', SESSION]))
  expect(ran(w, 'mc-panel.sh', 'digest').length).toBeGreaterThan(0)
})

test('an acknowledgment that cannot be written stays on the pane', async ($, on) => {
  const w = world(on, { ackExit: 1 })
  await boot($, w)
  await w.clock.advance(10_000)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect((await ui.find({ type: 'Text', text: /^Fault:/ }))?.text).toContain('could not be acknowledged')
  await ui.unmount()
})

// An ack beside a record this session could not write would answer for
// whatever record stood there before, naming another program.
test('an activation that cannot be recorded is never acknowledged', async ($, on) => {
  const w = world(on, { activateExit: 1, records: { [SESSION]: recordFor('beta') } })
  await boot($, w)
  await w.clock.advance(10_000)
  await w.clock.settle()
  expect(ran(w, 'mc-panel.sh', 'activate').length).toBeGreaterThan(1)
  expect(ran(w, 'mc-panel.sh', 'ack')).toEqual([])
  expect(ran(w, 'mc-panel.sh', 'digest').at(-1)).toEqual(expect.arrayContaining(['--program', 'alpha']))
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect((await ui.find({ type: 'Text', text: /^Fault:/ }))?.text).toContain('could not be recorded')
  await ui.unmount()
})

// The skill's bring-up rewrites the record after the variable activated the
// panel; the live mod must answer it, or the skill falls back to text.
test('a rewritten record with no acknowledgment is acknowledged again', async ($, on) => {
  const w = world(on)
  await boot($, w)
  const acks = ran(w, 'mc-panel.sh', 'ack').length
  w.set({ records: { [SESSION]: recordFor('alpha') } })
  await w.clock.advance(10_000)
  expect(ran(w, 'mc-panel.sh', 'ack')).toHaveLength(acks + 1)
  expect(ran(w, 'mc-panel.sh', 'digest').at(-1)).toEqual(expect.arrayContaining(['--program', 'alpha']))
})

test('an empty acknowledgment is written again', async ($, on) => {
  const w = world(on)
  await boot($, w)
  const acks = ran(w, 'mc-panel.sh', 'ack').length
  w.set({ records: { [SESSION]: recordFor('alpha'), [`${SESSION}.ack`]: '' } })
  await w.clock.advance(10_000)
  expect(ran(w, 'mc-panel.sh', 'ack')).toHaveLength(acks + 1)
})

test('a record naming another program switches the panel to it', async ($, on) => {
  const w = world(on)
  await boot($, w)
  w.set({ records: { [SESSION]: recordFor('beta') } })
  await w.clock.advance(10_000)
  await w.clock.settle()
  expect(ran(w, 'mc-panel.sh', 'digest').at(-1)).toEqual(expect.arrayContaining(['--program', 'beta']))
  expect(ran(w, 'mc-wake.sh', 'target').at(-1)).toEqual(expect.arrayContaining(['beta', '--mod']))
  const released = ran(w, 'mc-wake.sh', 'target').filter(r => r.includes('alpha') && !r.includes('--mod'))
  expect(released.length).toBeGreaterThan(0)
})

test('a failed acknowledgment never stands the panel down', async ($, on) => {
  const w = world(on, { ackExit: 1 })
  await boot($, w)
  w.set({ records: {} })
  await w.clock.advance(30_000)
  expect(ran(w, 'mc-wake.sh', 'target').at(-1)).toContain('--mod')
})

test('an acknowledgment under an id the session no longer carries is recorded again', async ($, on) => {
  const w = world(on)
  await boot($, w)
  w.set({ sessionId: OTHER })
  await w.clock.advance(10_000)
  await w.clock.settle()
  expect(ran(w, 'mc-panel.sh', 'retire').at(-1)).toEqual(expect.arrayContaining(['--session', SESSION]))
  expect(ran(w, 'mc-panel.sh', 'activate').at(-1)).toEqual(expect.arrayContaining(['--session', OTHER]))
  expect(ran(w, 'mc-panel.sh', 'ack').at(-1)).toEqual(expect.arrayContaining(['--session', OTHER]))
})

// REQ-F1.16: a retired record (a handover released this session) stands the
// panel down, so two sessions never claim one wake target.
test('a retired record stands the panel down', async ($, on) => {
  const w = world(on)
  await boot($, w)
  w.set({ records: {} })
  await w.clock.advance(10_000)
  await w.clock.settle()
  expect(ran(w, 'mc-wake.sh', 'target').at(-1)).not.toContain('--mod')
  const digests = ran(w, 'mc-panel.sh', 'digest').length
  await w.clock.advance(60_000)
  expect(ran(w, 'mc-panel.sh', 'digest')).toHaveLength(digests)
})

test('a retired record with no exit marker stands down without ending the session', async ($, on) => {
  const w = world(on)
  await boot($, w)
  w.set({ records: {} })
  await w.clock.advance(10_000)
  await w.clock.settle()
  expect(ran(w, 'mc-wake.sh', 'target').at(-1)).not.toContain('--mod')
  expect(ran(w, 'mc-panel.sh', 'retire')).toEqual([])
  expect(w.commandRuns).toEqual([])
})

// A released predecessor ends itself once its turn is over: its own mod runs
// /exit, so the operator's own session needs no other session to close it.
test('a record retired for exit stands the panel down and ends the session', async ($, on) => {
  const w = world(on)
  await boot($, w)
  w.set({ records: { [`${SESSION}.exit`]: 'exit' } })
  await w.clock.advance(10_000)
  await w.clock.settle()
  expect(ran(w, 'mc-wake.sh', 'target').at(-1)).not.toContain('--mod')
  expect(ran(w, 'mc-panel.sh', 'retire').at(-1)).toEqual(expect.arrayContaining(['--session', SESSION]))
  expect(w.commandRuns).toEqual(['exit'])
  await w.clock.advance(60_000)
  expect(w.commandRuns).toEqual(['exit'])
})

test('an exit that cannot run is said, telling the operator to type /exit', async ($, on) => {
  const w = world(on, { isExitRefused: true })
  await boot($, w)
  w.set({ records: { [`${SESSION}.exit`]: 'exit' } })
  await w.clock.advance(10_000)
  await w.clock.settle()
  expect(ran(w, 'mc-panel.sh', 'retire').at(-1)).toEqual(expect.arrayContaining(['--session', SESSION]))
  expect(w.commandRuns).toEqual([])
  expect(w.toasts.at(-1)).toMatch(/released the alpha program name.*type \/exit/)
})

test('a release while an activation is being retried ends the session instead', async ($, on) => {
  const w = world(on, { activateExit: 1 })
  await boot($, w)
  const tries = ran(w, 'mc-panel.sh', 'activate').length
  w.set({ records: { [`${SESSION}.exit`]: 'exit' } })
  await w.clock.advance(10_000)
  await w.clock.settle()
  expect(ran(w, 'mc-panel.sh', 'activate')).toHaveLength(tries)
  expect(w.commandRuns).toEqual(['exit'])
})

test('a release under the id a /clear left behind still ends the session', async ($, on) => {
  const w = world(on)
  await boot($, w)
  w.set({ records: { [`${SESSION}.exit`]: 'exit' }, sessionId: OTHER })
  await w.clock.advance(10_000)
  await w.clock.settle()
  expect(ran(w, 'mc-panel.sh', 'activate').filter(r => r.includes(OTHER))).toEqual([])
  expect(w.commandRuns).toEqual(['exit'])
})

test('a /clear right after a release ends the session rather than moving the record', async ($, on) => {
  const w = world(on)
  await boot($, w)
  w.set({ records: { [`${SESSION}.exit`]: 'exit' }, sessionId: OTHER })
  await $.session.end({ reason: 'clear', sessionId: SESSION } as never)
  await w.clock.settle()
  expect(ran(w, 'mc-panel.sh', 'activate').filter(r => r.includes(OTHER))).toEqual([])
  expect(ran(w, 'mc-panel.sh', 'retire').at(-1)).toEqual(expect.arrayContaining(['--session', SESSION]))
  expect(w.commandRuns).toEqual(['exit'])
})

test('a wake target that cannot be handed back is tried once more, then said', async ($, on) => {
  const w = world(on)
  await boot($, w)
  w.set({ records: {}, releaseExit: 1 })
  await w.clock.advance(10_000)
  await w.clock.settle()
  const released = ran(w, 'mc-wake.sh', 'target').filter(r => r.includes('alpha') && !r.includes('--mod'))
  expect(released).toHaveLength(2)
  expect(w.toasts.at(-1)).toMatch(/alpha wake target could not be handed back/)
})

test('a failed read of the record directory is tried again', async ($, on) => {
  const w = world(on, { env: {}, whereExit: 1 })
  await boot($, w)
  w.set({ whereExit: 0, records: { [SESSION]: recordFor('alpha') } })
  await w.clock.advance(10_000)
  await w.clock.settle()
  expect(ran(w, 'mc-panel.sh', 'ack')).toHaveLength(1)
})

test('a /clear moves the record to the id the session goes on under', async ($, on) => {
  const w = world(on)
  await boot($, w)
  w.set({ sessionId: OTHER })
  await $.session.end({ reason: 'clear', sessionId: SESSION } as never)
  await w.clock.settle()
  expect(ran(w, 'mc-panel.sh', 'retire').at(-1)).toEqual(expect.arrayContaining(['--session', SESSION]))
  expect(ran(w, 'mc-panel.sh', 'activate').at(-1)).toEqual(expect.arrayContaining(['--session', OTHER]))
  expect(ran(w, 'mc-panel.sh', 'ack').at(-1)).toEqual(expect.arrayContaining(['--session', OTHER]))
  await w.clock.advance(10_000)
  expect(ran(w, 'mc-panel.sh', 'digest').length).toBeGreaterThan(0)
  expect(ran(w, 'mc-wake.sh', 'target').at(-1)).toContain('--mod')
})

// REQ-F1.16: retirement removes the record.
test('the end of the session retires its record', async ($, on) => {
  const w = world(on)
  await boot($, w)
  await $.session.end({ reason: 'prompt_input_exit', sessionId: SESSION } as never)
  expect(ran(w, 'mc-panel.sh', 'retire')[0]).toEqual(expect.arrayContaining(['--session', SESSION]))
})

test('the end of a session retires the record it was acknowledged under, too', async ($, on) => {
  const w = world(on)
  await boot($, w)
  w.set({ sessionId: OTHER })
  await $.session.end({ reason: 'prompt_input_exit', sessionId: OTHER } as never)
  const retired = ran(w, 'mc-panel.sh', 'retire').map(r => r[r.indexOf('--session') + 1])
  expect(retired).toEqual(expect.arrayContaining([OTHER, SESSION]))
})
