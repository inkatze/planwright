import { expect, test } from 'claude-code/testing'

import {
  BAR_PX_HEIGHT,
  BAR_PX_WIDTH,
  barPicture,
  COLOR,
  GAUGES_HEIGHT,
  GAUGES_WIDTH,
  gaugesPicture,
  spriteCells,
  spriteOffset,
  SPRITE_CELL_ROWS,
  SPRITE_WIDTH,
} from './panel-art'
import type { SpriteState } from './panel-art'

const STATES: SpriteState[] = ['bumpy', 'circling', 'landing', 'cruising', 'taxiing']

const words = (b64: string) => new Uint32Array(Uint8Array.fromBase64(b64).buffer)
const pixel = (rgba: string, w: number, x: number, y: number) => {
  const b = Uint8Array.fromBase64(rgba)
  const i = (y * w + x) * 4
  return (b[i]! << 16) | (b[i + 1]! << 8) | b[i + 2]!
}

test('Prop pal is a cell grid of the declared size, one triplet per cell, in every state', () => {
  for (const s of STATES) {
    const g = spriteCells(s, 0)
    expect(g.columns).toBe(SPRITE_WIDTH + 5)
    expect(g.rows).toBe(SPRITE_CELL_ROWS + 1)
    expect(words(g.cells).length).toBe(g.columns * g.rows * 3)
  }
})

test('Prop pal moves: frames of a moving state differ, a landed state settles', () => {
  for (const s of ['bumpy', 'circling', 'cruising'] as const) {
    expect(spriteCells(s, 0).cells).not.toBe(spriteCells(s, 1).cells)
  }
  expect(spriteOffset('landing', 3)).toEqual({ dx: 0, dy: 0 })
  expect(spriteOffset('landing', 0).dy).toBeGreaterThan(0)
})

test('Prop pal states are told apart by shape, not only by colour', () => {
  const frames = STATES.map(s => spriteCells(s, 1).cells)
  expect(new Set(frames).size).toBe(STATES.length)
})

test('a bar fills to the percent and draws its marks over the fill', () => {
  const b = barPicture(40, COLOR.blue, [{ at: 80, color: COLOR.red }])
  expect([b.width, b.height]).toEqual([BAR_PX_WIDTH, BAR_PX_HEIGHT])
  const mid = BAR_PX_HEIGHT / 2
  expect(pixel(b.rgba, b.width, 10, mid)).toBe(COLOR.blue)
  expect(pixel(b.rgba, b.width, Math.round(BAR_PX_WIDTH * 0.7), mid)).toBe(COLOR.track)
  expect(pixel(b.rgba, b.width, Math.round(BAR_PX_WIDTH * 0.8) - 1, mid)).toBe(COLOR.red)
  expect(pixel(b.rgba, b.width, Math.round(BAR_PX_WIDTH * 0.8) - 1, 0)).toBe(COLOR.red)
})

test('a bar clamps an out-of-range percent', () => {
  expect(pixel(barPicture(250, COLOR.blue).rgba, BAR_PX_WIDTH, BAR_PX_WIDTH - 4, 10)).toBe(COLOR.blue)
  expect(pixel(barPicture(-5, COLOR.blue).rgba, BAR_PX_WIDTH, 2, 10)).toBe(COLOR.track)
})

test('the gauge row is one picture of the declared size and differs by reading', () => {
  const base = {
    usageLeft: 22,
    load: { ratio: 0.26 },
    memory: 54,
    context: { percent: 31, handoverAt: 40, windowAt: 80 },
    caution: 'lit' as const,
  }
  const a = gaugesPicture(base)
  expect([a.width, a.height]).toEqual([GAUGES_WIDTH, GAUGES_HEIGHT])
  expect(Uint8Array.fromBase64(a.rgba).length).toBe(GAUGES_WIDTH * GAUGES_HEIGHT * 4)
  expect(gaugesPicture({ ...base, load: { ratio: 1 } }).rgba).not.toBe(a.rgba)
  expect(gaugesPicture({ ...base, caution: 'clear' }).rgba).not.toBe(a.rgba)
  expect(gaugesPicture({ ...base, context: null, load: null, usageLeft: null, memory: null, caution: 'unknown' }).rgba).not.toBe(a.rgba)
})
