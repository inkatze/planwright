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

// REQ-F1.16: retirement removes the record.
test('the end of the session retires its record', async ($, on) => {
  const w = world(on)
  await boot($, w)
  await $.session.end({ reason: 'prompt_input_exit', sessionId: SESSION } as never)
  expect(ran(w, 'mc-panel.sh', 'retire')[0]).toEqual(expect.arrayContaining(['--session', SESSION]))
})
