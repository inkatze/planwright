// Prop pal as pure data: pixels in, pixels out. A cell grid (a Raster,
// half-block pixel art, which works inside tmux). Nothing here reads the
// engine; panel.tsx and register.tsx decide what to draw and where.

export type Rgb = number // 0xRRGGBB

export type SpriteState = 'bumpy' | 'circling' | 'landing' | 'cruising' | 'taxiing'

// The approved art, pixel for pixel. Motion is drawn on top of it, never into it.
export const SPRITE_ROWS = [
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

const SPRITE_PALETTE: Record<string, Rgb> = {
  D: 0x2d5aa0,
  N: 0x4a86d8,
  W: 0xf2efe6,
  E: 0x141413,
  Y: 0x3a6bbf,
  P: 0xc7ced8,
  H: 0x9aa3ae,
}

const GROUND = 0x4a5568
const PUFF = [0xc9d1dc, 0x9aa3b2, 0x6b7586]
const DUST = 0x8a93a3
const CAUTION = 0xe5483b

const DEFAULT_COLOR = 0x01000000
const UPPER_HALF = 0x2580

const ART_W = SPRITE_ROWS[0]!.length
const ART_H = SPRITE_ROWS.length
// The canvas leaves room to drop (landing), bank, shake and trail exhaust.
const LEFT = 5
const TOP = 4
export const SPRITE_COLUMNS = ART_W + LEFT + 3
const PIXEL_ROWS = TOP + ART_H + 2
export const SPRITE_CELL_ROWS = Math.ceil(PIXEL_ROWS / 2)
const GROUND_Y = TOP + ART_H

export type Pixel = { x: number; y: number; color: Rgb }
type Point = { x: number; y: number }

const at = <T>(table: T[], frame: number): T => table[frame % table.length]!

// Where an art pixel lands on the canvas at a frame, and the extra pixels a
// state draws around the body.
type Motion = { place: (x: number, y: number) => Point; extras: Pixel[]; blade: 'full' | 'short' }

const rigid = (dx: number, dy: number) => (x: number, y: number) => ({ x: LEFT + dx + x, y: TOP + dy + y })

const BUMPS: [number, number][] = [[0, 0], [1, 0], [0, 1], [-1, 0], [0, -1], [1, 1]]
const BANK = [0, 1, 2, 1, 0, -1, -2, -1]
const ROLL = [0, 0, 1, 1, 2, 2, 1, 1]
const BOB = [0, -1, -1, 0, 0, 1, 1, 0]
const DESCENT = [-4, -3, -2, -1, 0]
const LANDED_AT = 6

// The frame a still mascot (reduced motion) and a redrawn pane start from: a
// landing's is its settled pose, never the middle of the descent.
export const restFrame = (state: SpriteState): number => (state === 'landing' ? LANDED_AT : 0)
// A landing plays once; past its settled pose a further frame draws nothing new.
export const isSettled = (state: SpriteState, frame: number): boolean => state === 'landing' && frame > LANDED_AT

function motion(state: SpriteState, frame: number): Motion {
  const blade = frame % 2 === 0 ? 'full' : 'short'
  switch (state) {
    case 'taxiing': {
      const place = rigid(at(ROLL, frame), 0)
      // The ground slides back under the wheels as the plane rolls forward.
      const extras: Pixel[] = []
      for (let x = 0; x < SPRITE_COLUMNS; x++) if ((x + frame) % 4 < 2) extras.push({ x, y: GROUND_Y, color: GROUND })
      return { place, extras, blade: 'full' }
    }
    case 'cruising': {
      const dy = at(BOB, frame)
      const tail = rigid(0, dy)(0, 5)
      // Three puffs drift back from the tail, fading as they go.
      const extras = [0, 1, 2].map(i => {
        const d = (frame + i * 2) % 6
        return { x: tail.x - 1 - d, y: tail.y + (d % 2), color: PUFF[Math.min(2, Math.floor(d / 2))]! }
      })
      return { place: rigid(0, dy), extras, blade }
    }
    case 'circling': {
      const bank = at(BANK, frame)
      const dx = at(BANK, frame)
      // The wing line tilts: the far end rises as the near end falls.
      const place = (x: number, y: number) => ({
        x: LEFT + dx + x,
        y: TOP + y + Math.round((bank * (x - (ART_W - 1) / 2)) / ((ART_W - 1) / 2)),
      })
      return { place, extras: [], blade }
    }
    case 'landing': {
      const f = Math.min(frame, LANDED_AT)
      const dy = f < DESCENT.length ? DESCENT[f]! : 0
      const extras: Pixel[] = []
      for (let x = 0; x < SPRITE_COLUMNS; x++) extras.push({ x, y: GROUND_Y, color: GROUND })
      // Dust at the touchdown, gone once settled.
      if (f === 4 || f === 5) {
        const spread = f - 3
        for (const x of [LEFT + 2 - spread, LEFT + ART_W - 4 + spread]) extras.push({ x, y: GROUND_Y - 1, color: DUST })
      }
      return { place: rigid(0, dy), extras, blade: 'full' }
    }
    case 'bumpy': {
      const [dx, dy] = at(BUMPS, frame)
      const place = rigid(dx, dy)
      const extras: Pixel[] =
        frame % 2 === 0 ? [15, 16].map(x => ({ ...place(x, 1), color: CAUTION })) : []
      return { place, extras, blade }
    }
  }
}

// Every lit pixel at a frame, the art's own placed by `origin`.
export function spriteGrid(state: SpriteState, frame: number): { pixels: Pixel[]; origin: (x: number, y: number) => Point } {
  const m = motion(state, frame)
  const pixels: Pixel[] = [...m.extras]
  for (let y = 0; y < ART_H; y++) {
    for (let x = 0; x < ART_W; x++) {
      const color = SPRITE_PALETTE[SPRITE_ROWS[y]![x]!]
      if (color === undefined) continue
      // A spinning blade swaps between full and short; the body never changes.
      if (x >= ART_W - 2 && m.blade === 'short' && (y < 4 || y > 7)) continue
      const p = m.place(x, y)
      pixels.push({ ...p, color })
    }
  }
  return { pixels, origin: m.place }
}

export type Cells = { columns: number; rows: number; cells: string }

// The mascot as a Raster: each cell is an upper half block, its foreground the
// upper pixel and its background the lower; a transparent pixel is the
// terminal's own colour.
export function spriteCells(state: SpriteState, frame: number): Cells {
  const columns = SPRITE_COLUMNS
  const rows = SPRITE_CELL_ROWS
  const lit = new Map<number, Rgb>()
  // Extras are listed first so the body is drawn over them.
  for (const p of spriteGrid(state, frame).pixels) {
    if (p.x >= 0 && p.x < columns && p.y >= 0 && p.y < rows * 2) lit.set(p.y * columns + p.x, p.color)
  }
  const words = new Uint32Array(columns * rows * 3)
  for (let r = 0; r < rows; r++) {
    for (let c = 0; c < columns; c++) {
      const i = (r * columns + c) * 3
      words[i] = UPPER_HALF
      words[i + 1] = lit.get(r * 2 * columns + c) ?? DEFAULT_COLOR
      words[i + 2] = lit.get((r * 2 + 1) * columns + c) ?? DEFAULT_COLOR
    }
  }
  return { columns, rows, cells: new Uint8Array(words.buffer).toBase64() }
}
