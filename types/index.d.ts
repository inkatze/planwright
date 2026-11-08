export type PanelFlight = { worker: string; scope: string; backend: string; state: 'working' | 'waiting' | 'stuck' }
export type PanelDecision = { time: string; subject: string; act: string }
export type PanelHeadroom = { dimension: string; used: number; limit: number; percent: number }
export type PanelWatcher = { duty: string; script: string; state: string; next: number | null }
export type PanelSource = { cls: string; source: string; mode: string; age: number | null }
export type PanelMeasure = { name: string; value: string; age: number | null }
// A health check out of its bound; a null count is a store that cannot be read.
export type PanelHealth = { check: string; count: number | null; worst: string; text: string }
export type PanelMyPr = {
  repo: string
  number: number
  isDraft: boolean
  ci: string
  unresolved: number
  isHeadReviewed: boolean
  reviewers: string[]
  title: string
}
export type PanelWaitingPr = { repo: string; number: number; isDraft: boolean; requester: string; age: number; title: string }
export type PanelReviews = {
  isAvailable: boolean
  reason: string
  age: number | null
  // Every match of each search; the lists hold at most the first page.
  mineTotal: number | null
  waitingTotal: number | null
  mine: PanelMyPr[]
  waiting: PanelWaitingPr[]
}

export type PanelDigest = {
  taken: number
  knobs: Record<string, number>
  flights: PanelFlight[]
  // Registry sessions not retired and not seen live.
  finished: number | null
  waiting: number | null
  mergeReady: number | null
  // Some pull requests could not be judged, so mergeReady is a floor.
  isMergeReadyPartial: boolean
  pending: number | null
  // Worker permission prompts mission control answers, never the operator's.
  approvals: number | null
  decisions: PanelDecision[]
  rung: { name: string; reason: string }
  headroom: PanelHeadroom[]
  watchers: PanelWatcher[]
  sources: PanelSource[]
  kbAge: number | null
  measures: PanelMeasure[]
  // Null where the digest carried no reviews record.
  reviews: PanelReviews | null
  // Load (hundredths of one-minute load average), cores and memory still
  // available as a percent; null for what the host could not read.
  host: { load: number | null; cores: number | null; memFreePercent: number | null }
  isHandoverInstalled: boolean
  // The holder record's kind: only a registry holder (a session mission
  // control launched) hands over; null with no record or an unreadable one.
  holder: 'registry' | 'attended' | null
  unreadable: string[]
  // Empty when every health check is within its bound; absent from a
  // digest a reload carried over from before the checks were read.
  health?: PanelHealth[]
  line: string
}

export type PanelRateLimit = { kind: string; percentUsed: number }

export type PanelView = {
  program: string
  target: string
  digest: PanelDigest | null
  contextPercent: number | null
  rateLimits: PanelRateLimit[]
  compactions: number
  wakes: number
  ticks: number
  lastTickAt: number | null
  handover: string | null
  isFallback: boolean
  fault: string | null
  frame: number
}

declare module 'claude-code' {
  interface PluginState {
    planwright: { panel: Shaped<PanelView | null>; isBusy: boolean }
  }
}
