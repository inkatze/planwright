import { expect, test } from 'claude-code/testing'

import { digestText, start, world } from './fixture'

const SURFACES = ['terminal', 'desktop', 'vscode', 'mobile'] as const

const PANE = {
  plugin: 'planwright',
  component: 'Pane',
  requestId: 'mission-control',
  props: {
    title: 'Mission control',
    isFocused: false,
    bodyColumns: 60,
    placement: 'dock',
    scroll: { offset: 0, bodyRows: 40 },
    view: {},
  },
} as const

const BAND = {
  plugin: 'planwright',
  component: 'AbovePrompt',
  requestId: 'band',
  props: {
    hasSurvey: false,
    isWorking: false,
    maxRows: 3,
    bodyColumns: 120,
    scroll: { offset: 0, bodyRows: 3 },
    view: {},
  },
} as const

// REQ-F1.1, REQ-L1.4, REQ-H1.4, REQ-M1.8
test('the pane draws every store from the fixture digest, on every surface', async ($, on) => {
  world(on)
  await $.session.start(start)
  for (const surface of SURFACES) {
    const ui = await $.ui.mount({ ...PANE, surface })
    const has = async (text: RegExp) => expect((await ui.find({ type: 'Text', text }))?.text).toMatch(text)
    await has(/Mission control · alpha/)
    await has(/In flight \(2\)/)
    await has(/w-one {2}mission-control:alpha {2}stream-json/)
    await has(/2 waiting on you/)
    await has(/relaunch w-one: relaunch/)
    await has(/Fuel · rung throttle/)
    await has(/tightest: polls_per_hour 72%/)
    await has(/inbox\/inbox-watch\.sh stopped, next 40s overdue/)
    await has(/code-state: forge snapshot, 90s old/)
    await has(/designs: none cited/)
    await has(/context 42% · five_hour 31%/)
    await has(/compactions since start 0/)
    await has(/knowledge base 10m old/)
    await has(/interruptions per hour 2\.5/)
    await has(/settled share 80/)
    await ui.unmount()
  }
})

// REQ-F1.1: the stores change and the timer redraws with no turn.
test('the pane redraws from the stores on the timer, without a turn', async ($, on) => {
  const w = world(on)
  await $.session.start(start)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect(await ui.find({ type: 'Text', text: /In flight \(2\)/ })).toBeDefined()
  w.set({ digest: digestText().replace(/^flight\tw-two.*\n/m, '') })
  await w.clock.advance(10_000)
  expect((await ui.find({ type: 'Text', text: /In flight/ }))?.text).toBe('In flight (1)')
  expect(w.submitted).toEqual([])
  await ui.unmount()
})

test('the band draws the summary line above the prompt', async ($, on) => {
  world(on)
  await $.session.start(start)
  for (const surface of SURFACES) {
    const ui = await $.ui.mount({ ...BAND, surface })
    const band = await ui.find({ type: 'Text', text: /✈ alpha/ })
    expect(band?.text).toBe('✈ alpha · 2 in flight · 2 holding · rung throttle · ctx 42% · five_hour 31%')
    await ui.unmount()
  }
})

test('a store the digest could not read is said on the pane', async ($, on) => {
  world(on, { digest: digestText({ extra: ['unreadable\toperator queue'] }) })
  await $.session.start(start)
  const ui = await $.ui.mount({ ...PANE, surface: 'desktop' })
  expect((await ui.find({ type: 'Text', text: /Unreadable/ }))?.text).toBe('Unreadable: operator queue')
  await ui.unmount()
})

test('a failed digest keeps the last reading and names the fault', async ($, on) => {
  const w = world(on)
  await $.session.start(start)
  w.set({ digestExit: 1 })
  await w.clock.advance(10_000)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect((await ui.find({ type: 'Text', text: /Last reading failed/ }))?.text).toBe(
    'Last reading failed: store unreadable',
  )
  expect(await ui.find({ type: 'Text', text: /In flight \(2\)/ })).toBeDefined()
  await ui.unmount()
})

// REQ-F1.2: where no surface places the pane, the text line carries it.
test('the fallback line shows where nothing draws the pane', async ($, on) => {
  const w = world(on, { isPlaced: false })
  await $.session.start(start)
  const line = w.statuses.filter((s): s is string => typeof s === 'string').at(-1)
  expect(line).toBe('mission control alpha: 2 in flight, 2 waiting, 0 pending, rung throttle, context 42%')
  await w.clock.advance(10_000)
  expect(w.statuses.at(-1)).toBe(line)
})

test('a placed pane clears the fallback line', async ($, on) => {
  const w = world(on)
  await $.session.start(start)
  expect(w.statuses).toEqual([undefined])
})

test('the mod stays inert in a session that is not mission control', async ($, on) => {
  const w = world(on, { program: undefined })
  // Stands for the engine's own band.
  on('ui.render', ($, e) => {
    const { Text } = $.ui.resolve(e)
    return <Text>engine</Text>
  })
  await $.session.start(start)
  await w.clock.advance(60_000)
  expect(w.runs).toEqual([])
  const ui = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect((await ui.find({ type: 'Text' }))?.text).toBe('engine')
  await ui.unmount()
})
