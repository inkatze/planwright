import { expect, test } from 'claude-code/testing'

import { BAND, boot, digestText, PANE, ran, world } from './fixture'

const SURFACES = ['terminal', 'desktop', 'vscode', 'mobile'] as const

// REQ-F1.1, REQ-L1.4, REQ-H1.4, REQ-M1.8
test('the pane draws every store from the fixture digest, on every surface', async ($, on) => {
  const w = world(on)
  await boot($, w)
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
  await boot($, w)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect(await ui.find({ type: 'Text', text: /In flight \(2\)/ })).toBeDefined()
  w.set({ digest: digestText().replace(/^flight\tw-two.*\n/m, '') })
  await w.clock.advance(10_000)
  expect((await ui.find({ type: 'Text', text: /In flight/ }))?.text).toBe('In flight (1)')
  expect(w.submitted).toEqual([])
  await ui.unmount()
})

test('the knobs set the redraw and tick cadences', async ($, on) => {
  const w = world(on, { digest: digestText({ refresh: 3, tick: 60 }) })
  await boot($, w)
  const digests = () => ran(w, 'mc-panel.sh', 'digest').length
  const first = digests()
  await w.clock.advance(3_000)
  expect(digests()).toBe(first + 1)
  expect(ran(w, 'mc-wake.sh', 'compose')).toEqual([])
  await w.clock.advance(57_000)
  expect(ran(w, 'mc-wake.sh', 'compose')).toHaveLength(1)
  expect(ran(w, 'mc-panel.sh', 'digest')[0]).toContain('--knobs')
  expect(ran(w, 'mc-panel.sh', 'digest').at(-1)).not.toContain('--knobs')
})

test('the band draws the summary line above the prompt', async ($, on) => {
  const w = world(on)
  await boot($, w)
  for (const surface of SURFACES) {
    const ui = await $.ui.mount({ ...BAND, surface })
    const band = await ui.find({ type: 'Text', text: /✈ alpha/ })
    expect(band?.text).toBe('✈ alpha · 2 in flight · 2 holding · rung throttle · ctx 42% · five_hour 31%')
    await ui.unmount()
  }
})

test('the band leaves a survey alone', async ($, on) => {
  const w = world(on)
  on('ui.render', ($, e) => {
    const { Text } = $.ui.resolve(e)
    return <Text>engine</Text>
  })
  await boot($, w)
  const ui = await $.ui.mount({ ...BAND, surface: 'terminal', props: { ...BAND.props, hasSurvey: true } })
  expect((await ui.find({ type: 'Text' }))?.text).toBe('engine')
  await ui.unmount()
})

test('a store the digest could not read is said, its count unknown', async ($, on) => {
  const w = world(on, {
    digest: digestText({ extra: ['unreadable\toperator queue', 'unreadable\tfleet registry', 'unreadable\tknowledge base'] }),
  })
  await boot($, w)
  const ui = await $.ui.mount({ ...PANE, surface: 'desktop' })
  expect((await ui.find({ type: 'Text', text: /Unreadable/ }))?.text).toBe(
    'Unreadable: operator queue, fleet registry, knowledge base',
  )
  expect(await ui.find({ type: 'Text', text: /In flight \(\?\)/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /knowledge base unreadable/ })).toBeDefined()
  await ui.unmount()
})

test('measures not yet written are said as such', async ($, on) => {
  const w = world(on, {
    digest: digestText().replace(/^measure.*\n/gm, '').replace('handover\tabsent', 'measure\t-\tnone\t-\nhandover\tabsent'),
  })
  await boot($, w)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect(await ui.find({ type: 'Text', text: /^measures none$/ })).toBeDefined()
  await ui.unmount()
})

test('a failed digest keeps the last reading and names the fault', async ($, on) => {
  const w = world(on)
  await boot($, w)
  w.set({ digestExit: 1 })
  await w.clock.advance(10_000)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect((await ui.find({ type: 'Text', text: /^Fault:/ }))?.text).toBe(
    'Fault: store unreadable',
  )
  expect(await ui.find({ type: 'Text', text: /In flight \(2\)/ })).toBeDefined()
  await ui.unmount()
})

// REQ-F1.2: where no surface places the pane, the text line carries it.
test('the fallback line shows where nothing draws the pane', async ($, on) => {
  const w = world(on, { isPlaced: false })
  await boot($, w)
  const line = w.statuses.filter((s): s is string => typeof s === 'string').at(-1)
  expect(line).toBe('mission control alpha: 2 in flight, 2 waiting, 0 pending, rung throttle, context 42%')
  await w.clock.advance(10_000)
  expect(w.statuses.at(-1)).toBe(line)
})

test('a placed pane clears the fallback line', async ($, on) => {
  const w = world(on)
  await boot($, w)
  expect(w.statuses).toEqual([undefined])
})

test('the slash command reopens the pane', async ($, on) => {
  const w = world(on)
  await boot($, w)
  const before = w.opened
  const out = await $.command.run({ command: 'mission-control', args: '', origin: { kind: 'composer' } } as never)
  expect(w.opened).toBe(before + 1)
  expect(JSON.stringify(out)).toContain('Mission control panel opened.')
})

test('the mod stays inert in a session that is not mission control', async ($, on) => {
  const w = world(on, { env: {} })
  // Stands for the engine's own band.
  on('ui.render', ($, e) => {
    const { Text } = $.ui.resolve(e)
    return <Text>engine</Text>
  })
  await boot($, w)
  await w.clock.advance(60_000)
  expect(w.runs).toEqual([])
  const ui = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect((await ui.find({ type: 'Text' }))?.text).toBe('engine')
  await ui.unmount()
})

// A session this one starts must not inherit the activation and take its wakes.
test('the activation variables are read once and cleared', async ($, on) => {
  const w = world(on, { env: { PLANWRIGHT_MC_PROGRAM: 'alpha', PLANWRIGHT_MC_TARGET: 'mc-main' } })
  await boot($, w)
  expect(w.envWrites).toEqual([
    ['PLANWRIGHT_MC_PROGRAM', undefined],
    ['PLANWRIGHT_MC_TARGET', undefined],
  ])
  expect(ran(w, 'mc-wake.sh', 'target')[0]).toEqual(expect.arrayContaining(['alpha', 'mc-main', '--mod']))
  expect(ran(w, 'mc-panel.sh', 'digest')[0]).toEqual(expect.arrayContaining(['--target', 'mc-main']))
})

test('a target outside the handle grammar falls back to the program', async ($, on) => {
  const w = world(on, { env: { PLANWRIGHT_MC_PROGRAM: 'alpha', PLANWRIGHT_MC_TARGET: 'bad;target' } })
  await boot($, w)
  expect(ran(w, 'mc-wake.sh', 'target')[0]).toEqual(expect.arrayContaining(['alpha', '--mod']))
  expect(ran(w, 'mc-wake.sh', 'target')[0]).not.toContain('bad;target')
})

test('a refused clear of the activation stays on the pane', async ($, on) => {
  const w = world(on, { isEnvDenied: true })
  await boot($, w)
  await w.clock.advance(10_000)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect((await ui.find({ type: 'Text', text: /^Fault:/ }))?.text).toBe(
    'Fault: the activation could not be cleared: sessions started from here inherit it',
  )
  await ui.unmount()
})

test('knobs that arrive after a failed first reading set the cadences then', async ($, on) => {
  const w = world(on, { digestExit: 1, digest: digestText({ refresh: 3, tick: 60 }) })
  await boot($, w)
  await w.clock.advance(10_000)
  w.set({ digestExit: 0 })
  await w.clock.advance(10_000)
  const after = ran(w, 'mc-panel.sh', 'digest').length
  await w.clock.advance(3_000)
  expect(ran(w, 'mc-panel.sh', 'digest').length).toBe(after + 1)
  expect(ran(w, 'mc-panel.sh', 'digest').at(-1)).not.toContain('--knobs')
})

test('a lasting fault clearing leaves a failing reading on the pane', async ($, on) => {
  const w = world(on, { claimExit: 1 })
  await boot($, w)
  w.set({ digestExit: 1, claimExit: 0 })
  await w.clock.advance(10_000)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect((await ui.find({ type: 'Text', text: /^Fault:/ }))?.text).toBe('Fault: store unreadable')
  await ui.unmount()
})

test('a knob unread at bring-up is read again until every knob arrives', async ($, on) => {
  const partial = digestText().replace(/^knob\thandover-context.*$/m, 'unreadable\tknob mission_control_handover_context')
  const w = world(on, { digest: partial })
  await boot($, w)
  await w.clock.advance(10_000)
  expect(ran(w, 'mc-panel.sh', 'digest').at(-1)).toContain('--knobs')
  w.set({ digest: digestText(), contextPercent: 75 })
  await w.clock.advance(10_000)
  expect(ran(w, 'mc-event.sh', 'emit').at(-1)?.slice(-3)).toEqual(['handover-due', 'alpha', 'context at 75%'])
  await w.clock.advance(10_000)
  expect(ran(w, 'mc-panel.sh', 'digest').at(-1)).not.toContain('--knobs')
})
