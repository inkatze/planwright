import { expect, test } from 'claude-code/testing'

import { spriteCells, spriteGrid, SPRITE_CELL_ROWS, SPRITE_COLUMNS, SPRITE_ROWS } from './panel-art'
import type { SpriteState } from './panel-art'

const STATES: SpriteState[] = ['bumpy', 'circling', 'landing', 'cruising', 'taxiing']

const words = (b64: string) => new Uint32Array(Uint8Array.from(atob(b64), ch => ch.charCodeAt(0)).buffer)

// The approved Prop pal (Mascot board): rows and palette, pixel for pixel.
const APPROVED = [
  '..........................',
  'DD........................',
  'DDD..........NNNNNN......P',
  'DDDD.......NNWWWWWWNN....P',
  'DDDDNNNNNNNWEWWWWEWNNN..PP',
  '.NNNNNNNNNNWEWWWWEWNNNNHPP',
  '.NNNNNNNNNNNWWWWWWNNNNNHNP',
  '..NNNNYYYYYYYYYYYYNNNNNH.P',
  '...NNNNNYYYYYYYYNNNNNN..PP',
  '.....DDDDDDDDDDDDDDDD....P',
]
const PALETTE: Record<string, number> = {
  D: 0x2d5aa0,
  N: 0x4a86d8,
  W: 0xf2efe6,
  E: 0x141413,
  Y: 0x3a6bbf,
  P: 0xc7ced8,
  H: 0x9aa3ae,
}

test('the sprite rows are the approved art, exactly', () => {
  expect(SPRITE_ROWS).toEqual(APPROVED)
})

test('Prop pal is a cell grid of the declared size, one triplet per cell, in every state and frame', () => {
  for (const s of STATES) {
    for (let f = 0; f < 12; f++) {
      const g = spriteCells(s, f)
      expect(g.columns).toBe(SPRITE_COLUMNS)
      expect(g.rows).toBe(SPRITE_CELL_ROWS)
      expect(words(g.cells).length).toBe(g.columns * g.rows * 3)
    }
  }
})

test('the body is the approved art in every frame, whatever the motion', () => {
  // The body is every colored art pixel except the two propeller columns, which spin. Motion only moves it.
  for (const s of STATES) {
    for (let f = 0; f < 12; f++) {
      const { pixels, origin } = spriteGrid(s, f)
      let seen = 0
      for (let y = 0; y < APPROVED.length; y++) {
        for (let x = 0; x < APPROVED[0]!.length; x++) {
          const ch = APPROVED[y]![x]!
          if (ch === '.' || x >= APPROVED[0]!.length - 2) continue
          const found = pixels.some(p => p.color === PALETTE[ch] && p.x === origin(x, y).x && p.y === origin(x, y).y)
          if (found) seen++
        }
      }
      const body = APPROVED.join('')
        .split('')
        .filter((ch, i) => ch !== '.' && i % APPROVED[0]!.length < APPROVED[0]!.length - 2).length
      expect(seen).toBe(body)
    }
  }
})

test('each state moves its own way, and the five are told apart by shape', () => {
  const at = (s: SpriteState, f: number) => spriteCells(s, f).cells
  for (const s of ['bumpy', 'circling', 'cruising', 'taxiing'] as const) {
    expect(at(s, 0)).not.toBe(at(s, 1))
  }
  expect(new Set(STATES.map(s => at(s, 1))).size).toBe(STATES.length)
})

test('taxiing rolls along the ground: the plane keeps its height and the ground moves', () => {
  const heights = new Set<number>()
  for (let f = 0; f < 12; f++) heights.add(spriteGrid('taxiing', f).origin(0, 0).y)
  expect(heights.size).toBe(1)
  expect(spriteCells('taxiing', 0).cells).not.toBe(spriteCells('taxiing', 3).cells)
})

test('flying bobs, its propeller spins and exhaust puffs trail behind the tail', () => {
  const ys = new Set<number>()
  for (let f = 0; f < 8; f++) ys.add(spriteGrid('cruising', f).origin(0, 0).y)
  expect(ys.size).toBeGreaterThan(1)
  const { pixels, origin } = spriteGrid('cruising', 0)
  const tail = origin(0, 1)
  expect(pixels.some(p => p.x < tail.x && p.y >= tail.y && p.y <= tail.y + 6)).toBe(true)
  const blade = (f: number) => spriteGrid('cruising', f).pixels.filter(p => p.color === 0xc7ced8).length
  expect(new Set([blade(0), blade(1)]).size).toBe(2)
})

test('circling banks: the nose and tail sit at different heights, back and forth', () => {
  const slope = (f: number) => {
    const g = spriteGrid('circling', f)
    return g.origin(25, 5).y - g.origin(0, 5).y
  }
  const slopes = new Set<number>()
  for (let f = 0; f < 8; f++) slopes.add(slope(f))
  expect(slopes.size).toBeGreaterThan(2)
  expect([...slopes].some(v => v > 0) && [...slopes].some(v => v < 0)).toBe(true)
})

test('landing plays once: it descends, touches down, then holds still', () => {
  const y = (f: number) => spriteGrid('landing', f).origin(0, 9).y
  expect(y(0)).toBeLessThan(y(4))
  expect(spriteCells('landing', 6).cells).toBe(spriteCells('landing', 40).cells)
})

test('a bumpy ride shakes and the caution light turns red', () => {
  const red = (f: number) => spriteGrid('bumpy', f).pixels.some(p => p.color === 0xe5483b)
  expect(red(0) || red(1)).toBe(true)
  const shakes = new Set<string>()
  for (let f = 0; f < 6; f++) {
    const o = spriteGrid('bumpy', f).origin(0, 0)
    shakes.add(`${o.x},${o.y}`)
  }
  expect(shakes.size).toBeGreaterThan(2)
})
