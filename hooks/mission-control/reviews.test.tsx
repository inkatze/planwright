import { expect, test } from 'claude-code/testing'

import { boot, digestText, PANE, ran, REVIEWS, world } from './fixture'

const SURFACES = ['terminal', 'desktop', 'vscode', 'mobile'] as const

test('the pane draws my open PRs and the PRs waiting on my review, on every surface', async ($, on) => {
  const w = world(on, { digest: digestText({ extra: REVIEWS }) })
  await boot($, w)
  for (const surface of SURFACES) {
    const ui = await $.ui.mount({ ...PANE, surface })
    const text = async (re: RegExp) => (await ui.find({ type: 'Text', text: re }))?.text
    expect(await text(/^My open PRs/)).toBe('My open PRs (9) · read 2m ago')
    expect(await text(/^#7 /)).toBe(
      '#7 ready · CI red · 2 unresolved · head reviewed · asks carol, core-team · Add the widget',
    )
    expect(await text(/^#8 /)).toBe('#8 draft · no CI · 0 unresolved · head not reviewed · no reviewer requested · Fix the gadget')
    expect(await text(/^\+7 more$/)).toBe('+7 more')
    expect(await text(/^Waiting on my review/)).toBe('Waiting on my review (1)')
    expect(await text(/^#12 /)).toBe('#12 draft · from dave · 90m · Rework the docs')
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
        'review-waiting\tacme/gears\t3\tready\terin\t60\tTwo',
      ],
    }),
  })
  await boot($, w)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect(await ui.find({ type: 'Text', text: /^acme\/widgets#7 ready · CI green/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /^acme\/gears#3 ready · from erin/ })).toBeDefined()
  await ui.unmount()
})

test('unavailable reviews are said with their reason, never as empty lists', async ($, on) => {
  const w = world(on, { digest: digestText({ extra: ['reviews\tunavailable\tgh is not authenticated'] }) })
  await boot($, w)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect((await ui.find({ type: 'Text', text: /^Reviews$/ }))?.text).toBe('Reviews')
  expect((await ui.find({ type: 'Text', text: /^Unavailable:/ }))?.text).toBe('Unavailable: gh is not authenticated')
  expect(await ui.find({ type: 'Text', text: /^My open PRs/ })).toBeUndefined()
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
  expect(await ui.find({ type: 'Text', text: /^(Reviews|My open PRs|Waiting on my review)/ })).toBeUndefined()
  expect(await ui.find({ type: 'Text', text: /In flight \(2\)/ })).toBeDefined()
  await ui.unmount()
})

test('each redraw asks the snapshot script to refresh, read-only, for the program', async ($, on) => {
  const w = world(on)
  await boot($, w)
  const first = ran(w, 'mc-reviews.sh', 'refresh')
  expect(first).toHaveLength(1)
  expect(first[0]?.slice(2)).toEqual(['refresh', '--program', 'alpha'])
  await w.clock.advance(10_000)
  expect(ran(w, 'mc-reviews.sh', 'refresh')).toHaveLength(2)
  expect(w.runs.filter(r => (r[1] ?? '').endsWith('/mc-reviews.sh') && r[2] !== 'refresh')).toEqual([])
  expect(w.submitted).toEqual([])
})

test('a refresh that fails is a fault on the pane, cleared once one succeeds', async ($, on) => {
  const w = world(on, { reviewsExit: 1 })
  await boot($, w)
  await w.clock.advance(10_000)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect((await ui.find({ type: 'Text', text: /^Fault:/ }))?.text).toBe(
    'Fault: the reviews snapshot could not be refreshed: store unreadable',
  )
  await ui.unmount()
  w.set({ reviewsExit: 0 })
  await w.clock.advance(10_000)
  await w.clock.advance(10_000)
  const again = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect(await again.find({ type: 'Text', text: /^Fault:/ })).toBeUndefined()
  expect(await again.find({ type: 'Text', text: /In flight \(2\)/ })).toBeDefined()
  await again.unmount()
})
