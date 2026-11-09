// Prop pal as pure data: pixels in, pixels out. A cell grid (a Raster,
// half-block pixel art, which works inside tmux). Nothing here reads the
// engine; panel.tsx and register.tsx decide what to draw and where.

export type Rgb = number // 0xRRGGBB

// ---- Raster: the mascot ----------------------------------------------------

export type SpriteState = 'bumpy' | 'circling' | 'landing' | 'cruising' | 'taxiing'

const SPRITE_ROWS = [
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

const DEFAULT_COLOR = 0x01000000
const UPPER_HALF = 0x2580

export const SPRITE_WIDTH = SPRITE_ROWS[0]!.length
// Two pixel rows per cell row.
// The deepest drop any state applies, so the grid always holds the whole sprite.
const MAX_DROP = 3
export const SPRITE_CELL_ROWS = Math.ceil((SPRITE_ROWS.length + MAX_DROP) / 2)

// The pixel at a column and row, after the state's offset; transparent is null.
function spritePixel(x: number, y: number): Rgb | null {
  const ch = SPRITE_ROWS[y]?.[x]
  return ch === undefined ? null : (SPRITE_PALETTE[ch] ?? null)
}

// How far the sprite is displaced at a frame: columns right, pixel rows down.
export function spriteOffset(state: SpriteState, frame: number): { dx: number; dy: number } {
  switch (state) {
    case 'bumpy':
      return { dx: frame % 2 === 0 ? 0 : 1, dy: frame % 2 === 0 ? 0 : 1 }
    case 'circling':
      return { dx: [0, 2, 4, 2][frame % 4]!, dy: [0, 1, 0, 1][frame % 4]! }
    case 'landing':
      return { dx: 0, dy: Math.max(0, 3 - Math.min(frame, 3)) }
    case 'cruising':
      return { dx: 0, dy: frame % 2 === 0 ? 0 : 1 }
    case 'taxiing':
      return { dx: frame % 4 === 0 ? 1 : 0, dy: 0 }
  }
}

// The propeller blades flip between two heights each frame, so a spin reads.
function propPixel(x: number, y: number, frame: number): Rgb | null {
  const px = spritePixel(x, y)
  if (x !== SPRITE_WIDTH - 1 || px === null) return px
  return (frame % 2 === 0 ? y < 6 : y >= 4) ? px : null
}

export type Cells = { columns: number; rows: number; cells: string }

// The mascot as a Raster: each cell is an upper half block, its foreground the
// upper pixel and its background the lower; a transparent pixel is the
// terminal's own colour. `pad` leaves room for the sprite to move.
export function spriteCells(state: SpriteState, frame: number, pad = 5): Cells {
  const columns = SPRITE_WIDTH + pad
  const rows = SPRITE_CELL_ROWS
  const { dx, dy } = spriteOffset(state, frame)
  const words = new Uint32Array(columns * rows * 3)
  for (let r = 0; r < rows; r++) {
    for (let c = 0; c < columns; c++) {
      const top = propPixel(c - dx, r * 2 - dy, frame)
      const bottom = propPixel(c - dx, r * 2 + 1 - dy, frame)
      const i = (r * columns + c) * 3
      words[i] = UPPER_HALF
      words[i + 1] = top ?? DEFAULT_COLOR
      words[i + 2] = bottom ?? DEFAULT_COLOR
    }
  }
  return { columns, rows, cells: new Uint8Array(words.buffer).toBase64() }
}
