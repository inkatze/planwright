export type PanelFlight = { worker: string; scope: string; backend: string; state: 'working' | 'waiting' | 'stuck' }
export type PanelDecision = { time: string; subject: string; act: string }
export type PanelHeadroom = { dimension: string; used: number; limit: number; percent: number }
export type PanelWatcher = { duty: string; script: string; state: string; next: number | null }
export type PanelSource = { cls: string; source: string; mode: string; age: number | null }
export type PanelMeasure = { name: string; value: string; age: number | null }
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
  decisions: PanelDecision[]
  rung: { name: string; reason: string }
  headroom: PanelHeadroom[]
  watchers: PanelWatcher[]
  sources: PanelSource[]
  kbAge: number | null
  measures: PanelMeasure[]
  // Null where the digest carried no reviews record.
  reviews: PanelReviews | null
  isHandoverInstalled: boolean
  // The holder record's kind: only a registry holder (a session mission
  // control launched) hands over; null with no record or an unreadable one.
  holder: 'registry' | 'attended' | null
  unreadable: string[]
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
