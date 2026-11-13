import { expect, test } from 'claude-code/testing'

import { boot, digestText, PANE, ran, REVIEWS, world } from './fixture'

const SURFACES = ['terminal', 'desktop', 'vscode', 'mobile'] as const

test('the pane draws my open PRs and the PRs waiting on my review, on every surface', async ($, on) => {
  const w = world(on, { digest: digestText({ extra: REVIEWS }) })
  await boot($, w)
  for (const surface of SURFACES) {
    const ui = await $.ui.mount({ ...PANE, surface })
    const text = async (re: RegExp) => (await ui.find({ type: 'Text', text: re }))?.text
    expect(await text(/^Pull requests/)).toBe('Pull requests (9)')
    expect(await text(/^#7 /)).toBeUndefined()
    expect(await text(/^#8 /)).toBeUndefined()
    expect(await text(/^9 other pull requests need nothing from you/)).toBe('9 other pull requests need nothing from you')
    expect(await text(/^Waiting on my review/)).toBe('Waiting on my review (1)')
    expect(await text(/^#12 /)).toBe('#12 Rework the docs · from dave · 90m')
    await ui.unmount()
  }
})

test('empty lists are said as such', async ($, on) => {
  const w = world(on, { digest: digestText({ extra: ['reviews\tok\t5'] }) })
  await boot($, w)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect(await ui.find({ type: 'Text', text: /^No open pull requests\.$/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /^Nothing waiting on your review\.$/ })).toBeDefined()
  await ui.unmount()
})

test('a long list is capped with the count it leaves out', async ($, on) => {
  const many = Array.from({ length: 7 }, (_, i) => `review-waiting\tacme/widgets\t${20 + i}\tready\tdave\t60\tPR ${i}`)
  const w = world(on, { digest: digestText({ extra: ['reviews\tok\t5', ...many] }) })
  await boot($, w)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect((await ui.find({ type: 'Text', text: /^Waiting on my review/ }))?.text).toBe('Waiting on my review (7)')
  expect(await ui.find({ type: 'Text', text: /^#24 / })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /^#25 / })).toBeUndefined()
  expect(await ui.find({ type: 'Text', text: /^\+2 more$/ })).toBeDefined()
  await ui.unmount()
})

test('PRs across repositories name their repository', async ($, on) => {
  const w = world(on, {
    digest: digestText({
      extra: [
        'reviews\tok\t5',
        'review-mine\tacme/widgets\t7\tready\tgreen\t0\tno\t-\tOne',
        'review-mine\tacme/gears\t4\tready\tgreen\t0\tno\t-\tThree',
        'review-waiting\tacme/gears\t3\tready\terin\t60\tTwo',
      ],
    }),
  })
  await boot($, w)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect(await ui.find({ type: 'Text', text: /^acme\/widgets#7 One/ })).toBeUndefined()
  expect(await ui.find({ type: 'Text', text: /^2 other pull requests need nothing/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /^acme\/gears#3 Two · from erin/ })).toBeDefined()
  await ui.unmount()
})

test('unavailable reviews are said with their reason, never as empty lists', async ($, on) => {
  const w = world(on, { digest: digestText({ extra: ['reviews\tunavailable\tgh is not authenticated'] }) })
  await boot($, w)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect((await ui.find({ type: 'Text', text: /^Pull requests$/ }))?.text).toBe('Pull requests')
  expect((await ui.find({ type: 'Text', text: /^Unavailable:/ }))?.text).toBe('Unavailable: gh is not authenticated')
  expect(await ui.find({ type: 'Text', text: /^Pull requests \(/ })).toBeUndefined()
  expect(await ui.find({ type: 'Text', text: /^No open pull requests/ })).toBeUndefined()
  expect(await ui.find({ type: 'Text', text: /In flight \(2\)/ })).toBeDefined()
  await ui.unmount()
})

test('rows a digest sends while reviews are unavailable are not drawn', async ($, on) => {
  const w = world(on, {
    digest: digestText({ extra: ['reviews\tunavailable\tgh is not installed', 'review-mine\tacme/widgets\t7\tready\tred\t0\tno\t-\tStale'] }),
  })
  await boot($, w)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect(await ui.find({ type: 'Text', text: /Stale/ })).toBeUndefined()
  await ui.unmount()
})

test('a digest with no reviews record draws no reviews section', async ($, on) => {
  const w = world(on)
  await boot($, w)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect(await ui.find({ type: 'Text', text: /^(Pull requests|Waiting on my review)/ })).toBeUndefined()
  expect(await ui.find({ type: 'Text', text: /In flight \(2\)/ })).toBeDefined()
  await ui.unmount()
})

test('the snapshot is checked at bring-up and on its own cadence, read-only, for the program', async ($, on) => {
  const w = world(on)
  await boot($, w)
  const first = ran(w, 'mc-reviews.sh', 'refresh')
  expect(first).toHaveLength(1)
  expect(first[0]?.slice(2)).toEqual(['refresh', '--program', 'alpha'])
  // The default 5m TTL is checked once a minute, not on every 10s redraw.
  await w.clock.advance(50_000)
  expect(ran(w, 'mc-reviews.sh', 'refresh')).toHaveLength(1)
  await w.clock.advance(10_000)
  expect(ran(w, 'mc-reviews.sh', 'refresh')).toHaveLength(2)
  expect(w.runs.filter(r => (r[1] ?? '').endsWith('/mc-reviews.sh') && r[2] !== 'refresh')).toEqual([])
  expect(w.submitted).toEqual([])
})

test('a short TTL is checked every fifth of it, never faster than the redraw', async ($, on) => {
  const w = world(on, { digest: digestText({ reviewsTtl: 60 }) })
  await boot($, w)
  await w.clock.advance(11_000)
  expect(ran(w, 'mc-reviews.sh', 'refresh')).toHaveLength(1)
  await w.clock.advance(1_000)
  expect(ran(w, 'mc-reviews.sh', 'refresh')).toHaveLength(2)
})

test('a TTL shorter than five redraws is checked once per redraw', async ($, on) => {
  const w = world(on, { digest: digestText({ reviewsTtl: 5 }) })
  await boot($, w)
  await w.clock.advance(9_000)
  expect(ran(w, 'mc-reviews.sh', 'refresh')).toHaveLength(1)
  await w.clock.advance(1_000)
  expect(ran(w, 'mc-reviews.sh', 'refresh')).toHaveLength(2)
})

test('a new snapshot is drawn at once; a fresh answer redraws nothing', async ($, on) => {
  const w = world(on, { digest: digestText({ refresh: 11 }) })
  await boot($, w)
  const digests = () => ran(w, 'mc-panel.sh', 'digest').length
  await w.clock.advance(56_000)
  const before = digests()
  await w.clock.advance(4_000)
  expect(ran(w, 'mc-reviews.sh', 'refresh')).toHaveLength(2)
  expect(digests()).toBe(before + 1)
  w.set({ reviewsOut: 'fresh' })
  await w.clock.advance(56_000)
  const again = digests()
  await w.clock.advance(4_000)
  expect(ran(w, 'mc-reviews.sh', 'refresh')).toHaveLength(3)
  expect(digests()).toBe(again)
})

test('a failed refresh stays a fault until a refresh reads the forge again', async ($, on) => {
  const w = world(on, { reviewsExit: 1 })
  await boot($, w)
  const fault = async () => {
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    const text = (await ui.find({ type: 'Text', text: /^Fault:/ }))?.text
    await ui.unmount()
    return text
  }
  await w.clock.advance(10_000)
  expect(await fault()).toBe('Fault: the reviews snapshot could not be refreshed: store unreadable')
  w.set({ reviewsExit: 0, reviewsOut: 'fresh' })
  await w.clock.advance(60_000)
  expect(await fault()).toBe('Fault: the reviews snapshot could not be refreshed: store unreadable')
  w.set({ reviewsOut: 'unavailable\tgh is not installed' })
  await w.clock.advance(60_000)
  expect(await fault()).toBeUndefined()
})
