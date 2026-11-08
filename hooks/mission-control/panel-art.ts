// The panel's pictures, as pure data: pixels in, pixels out. Prop pal is a
// cell grid (a Raster, half-block pixel art, which works inside tmux); the
// instruments and bars are RGBA images (an Image, drawn by kitty and its kin).
// Nothing here reads the engine; panel.tsx decides what to draw and where.

export type Rgb = number // 0xRRGGBB

export const COLOR = {
  panel: 0x141821,
  track: 0x262c3a,
  edge: 0x3a4152,
  ink: 0xe6e8ec,
  blue: 0x56b4e9,
  yellow: 0xf0e442,
  red: 0xd55e00,
  dark: 0x0b0d11,
} as const

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
export const SPRITE_CELL_ROWS = Math.ceil(SPRITE_ROWS.length / 2)

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
  if (x !== SPRITE_WIDTH - 1) return spritePixel(x, y)
  return (frame % 2 === 0 ? y < 5 : y >= 4) ? SPRITE_PALETTE.P! : null
}

export type Cells = { columns: number; rows: number; cells: string }

// The mascot as a Raster: each cell is an upper half block, its foreground the
// upper pixel and its background the lower; a transparent pixel is the
// terminal's own colour. `pad` leaves room for the sprite to move.
export function spriteCells(state: SpriteState, frame: number, pad = 5): Cells {
  const columns = SPRITE_WIDTH + pad
  const rows = SPRITE_CELL_ROWS + 1
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

// ---- Image: a small RGBA canvas -------------------------------------------

export type Canvas = { width: number; height: number; px: Uint8Array }

export function canvas(width: number, height: number, fill: Rgb = COLOR.panel): Canvas {
  const px = new Uint8Array(width * height * 4)
  const c = { width, height, px }
  fillRect(c, 0, 0, width, height, fill)
  return c
}

function put(c: Canvas, x: number, y: number, rgb: Rgb) {
  if (x < 0 || y < 0 || x >= c.width || y >= c.height) return
  const i = (y * c.width + x) * 4
  c.px[i] = (rgb >> 16) & 0xff
  c.px[i + 1] = (rgb >> 8) & 0xff
  c.px[i + 2] = rgb & 0xff
  c.px[i + 3] = 0xff
}

export function fillRect(c: Canvas, x: number, y: number, w: number, h: number, rgb: Rgb) {
  for (let j = Math.round(y); j < Math.round(y + h); j++) for (let i = Math.round(x); i < Math.round(x + w); i++) put(c, i, j, rgb)
}

// A ring (or a disc when `inner` is 0) of the given radii.
function ring(c: Canvas, cx: number, cy: number, outer: number, inner: number, rgb: Rgb) {
  for (let j = Math.floor(cy - outer); j <= Math.ceil(cy + outer); j++) {
    for (let i = Math.floor(cx - outer); i <= Math.ceil(cx + outer); i++) {
      const d = Math.hypot(i + 0.5 - cx, j + 0.5 - cy)
      if (d <= outer && d >= inner) put(c, i, j, rgb)
    }
  }
}

// Degrees clockwise from twelve o'clock.
function polar(cx: number, cy: number, r: number, deg: number): [number, number] {
  const a = (deg * Math.PI) / 180
  return [cx + r * Math.sin(a), cy - r * Math.cos(a)]
}

function arc(c: Canvas, cx: number, cy: number, r: number, from: number, to: number, thick: number, rgb: Rgb) {
  for (let deg = from; deg <= to; deg += 1) {
    const [x, y] = polar(cx, cy, r, deg)
    ring(c, x, y, thick / 2, 0, rgb)
  }
}

function needle(c: Canvas, cx: number, cy: number, r: number, deg: number, rgb: Rgb) {
  for (let t = 0; t <= r; t += 0.5) {
    const [x, y] = polar(cx, cy, t, deg)
    ring(c, x, y, 1.5, 0, rgb)
  }
}

export function toRgba(c: Canvas): { rgba: string; width: number; height: number } {
  return { rgba: c.px.toBase64(), width: c.width, height: c.height }
}

// ---- Bars -------------------------------------------------------------------

export type Mark = { at: number; color: Rgb }

export const BAR_PX_WIDTH = 560
export const BAR_PX_HEIGHT = 20

// A horizontal bar a row tall: the fill, then thin full-height marks. Marks
// are 3 px wide so they read apart from the fill without colour.
export function barPicture(percent: number, fill: Rgb, marks: Mark[] = []) {
  const c = canvas(BAR_PX_WIDTH, BAR_PX_HEIGHT, COLOR.panel)
  const top = 4
  const h = BAR_PX_HEIGHT - 8
  fillRect(c, 0, top, BAR_PX_WIDTH, h, COLOR.track)
  const clamped = Math.max(0, Math.min(100, percent))
  fillRect(c, 0, top, (clamped / 100) * BAR_PX_WIDTH, h, fill)
  for (const m of marks) {
    const x = Math.min(BAR_PX_WIDTH - 3, Math.max(0, Math.round((m.at / 100) * BAR_PX_WIDTH) - 1))
    fillRect(c, x, 0, 3, BAR_PX_HEIGHT, m.color)
  }
  return toRgba(c)
}

// ---- The instrument row ----------------------------------------------------

export type Instruments = {
  usageLeft: number | null
  load: { ratio: number } | null
  memory: number | null
  context: { percent: number; handoverAt?: number; windowAt: number } | null
  caution: 'clear' | 'lit' | 'unknown'
}

export const GAUGES_WIDTH = 550
export const GAUGES_HEIGHT = 100
const SLOT = GAUGES_WIDTH / 5

function column(c: Canvas, slot: number, percent: number | null, fill: Rgb, redAt?: number) {
  const x = slot * SLOT + (SLOT - 22) / 2
  fillRect(c, x - 2, 6, 26, 88, COLOR.edge)
  fillRect(c, x, 8, 22, 84, COLOR.dark)
  if (percent !== null) {
    const h = (Math.max(0, Math.min(100, percent)) / 100) * 80
    fillRect(c, x + 2, 90 - h, 18, h, fill)
    fillRect(c, x + 2, 90 - h - 2, 18, 3, COLOR.ink)
  }
  if (redAt !== undefined) fillRect(c, x - 8, 90 - (redAt / 100) * 80, 6, 3, COLOR.red)
}

function dialFace(c: Canvas, slot: number) {
  const cx = slot * SLOT + SLOT / 2
  ring(c, cx, 50, 38, 0, COLOR.edge)
  ring(c, cx, 50, 35, 0, COLOR.dark)
  return cx
}

// The gauge row: usage left (a column), host load (a dial with its redline
// arc), memory (a column), context (a dial with the handover tick and the
// window arc) and the caution lamp (a square). Each is a picture of a number
// the pane also says in words.
export function gaugesPicture(i: Instruments) {
  const c = canvas(GAUGES_WIDTH, GAUGES_HEIGHT)

  column(c, 0, i.usageLeft, COLOR.blue, 10)

  const lx = dialFace(c, 1)
  arc(c, lx, 50, 31, 54, 135, 5, COLOR.red)
  if (i.load) needle(c, lx, 50, 28, Math.min(1, i.load.ratio) * 270 - 135, i.load.ratio >= 0.7 ? COLOR.yellow : COLOR.ink)
  ring(c, lx, 50, 4, 0, COLOR.ink)

  column(c, 2, i.memory, COLOR.blue, undefined)
  if (i.memory !== null && i.memory < 10) fillRect(c, 2 * SLOT + SLOT / 2 + 16, 76, 10, 14, COLOR.red)

  const cx = dialFace(c, 3)
  if (i.context) {
    const sweep = (p: number) => (Math.max(0, Math.min(100, p)) / 100) * 360
    arc(c, cx, 50, 31, 0, sweep(i.context.percent), 5, COLOR.blue)
    const [ax, ay] = polar(cx, 50, 31, sweep(i.context.windowAt))
    ring(c, ax, ay, 4, 0, COLOR.red)
    if (i.context.handoverAt !== undefined) {
      for (let t = 24; t <= 36; t += 0.5) {
        const [x, y] = polar(cx, 50, t, sweep(i.context.handoverAt))
        ring(c, x, y, 1.5, 0, COLOR.yellow)
      }
    }
    needle(c, cx, 50, 26, sweep(i.context.percent), COLOR.ink)
  }
  ring(c, cx, 50, 4, 0, COLOR.ink)

  const lamp = 4 * SLOT + (SLOT - 44) / 2
  const lit = i.caution === 'lit'
  fillRect(c, lamp - 2, 28, 48, 44, COLOR.edge)
  fillRect(c, lamp, 30, 44, 40, lit ? COLOR.yellow : i.caution === 'clear' ? COLOR.track : COLOR.dark)
  // The lamp carries a glyph, so lit and clear differ by shape as well as colour:
  // a bar for lit, a ring for clear, a dot for unknown.
  if (lit) fillRect(c, lamp + 19, 36, 6, 20, COLOR.dark), fillRect(c, lamp + 19, 60, 6, 6, COLOR.dark)
  else if (i.caution === 'clear') ring(c, lamp + 22, 50, 10, 6, COLOR.ink)
  else ring(c, lamp + 22, 50, 4, 0, COLOR.ink)

  return toRgba(c)
}
