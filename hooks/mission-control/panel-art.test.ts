import { expect, test } from 'claude-code/testing'

import {
  spriteCells,
  spriteOffset,
  SPRITE_CELL_ROWS,
  SPRITE_WIDTH,
} from './panel-art'
import type { SpriteState } from './panel-art'

const STATES: SpriteState[] = ['bumpy', 'circling', 'landing', 'cruising', 'taxiing']

const words = (b64: string) => new Uint32Array(Uint8Array.fromBase64(b64).buffer)
test('Prop pal is a cell grid of the declared size, one triplet per cell, in every state', () => {
  for (const s of STATES) {
    const g = spriteCells(s, 0)
    expect(g.columns).toBe(SPRITE_WIDTH + 5)
    expect(g.rows).toBe(SPRITE_CELL_ROWS)
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

test('the landing frame that drops lowest still holds the whole sprite', () => {
  const g = spriteCells('landing', 0)
  const w = words(g.cells)
  const belly = 0x2d5aa0
  const dropped = spriteOffset('landing', 0)
  const pixelRow = 9 + dropped.dy
  const cellRow = Math.floor(pixelRow / 2)
  const i = (cellRow * g.columns + 6 + dropped.dx) * 3
  expect(w[i + (pixelRow % 2 === 0 ? 1 : 2)]).toBe(belly)
})

test('the propeller stays inside the sprite and flips between frames', () => {
  const colOf = (frame: number) => {
    const g = spriteCells('taxiing', frame)
    const w = words(g.cells)
    const x = SPRITE_WIDTH - 1 + spriteOffset('taxiing', frame).dx
    let lit = 0
    for (let r = 0; r < g.rows; r++) for (const k of [1, 2]) if (w[(r * g.columns + x) * 3 + k] !== 0x01000000) lit++
    return lit
  }
  expect(colOf(1)).toBeLessThanOrEqual(10)
  expect(spriteCells('taxiing', 1).cells).not.toBe(spriteCells('taxiing', 2).cells)
})
