export type PanelFlight = { worker: string; scope: string; backend: string }
export type PanelDecision = { time: string; subject: string; act: string }
export type PanelHeadroom = { dimension: string; used: number; limit: number; percent: number }
export type PanelWatcher = { duty: string; script: string; state: string; next: number | null }
export type PanelSource = { cls: string; source: string; mode: string; age: number | null }
export type PanelMeasure = { name: string; value: string; age: number | null }

export type PanelDigest = {
  taken: number
  knobs: Record<string, number>
  flights: PanelFlight[]
  waiting: number | null
  pending: number | null
  decisions: PanelDecision[]
  rung: { name: string; reason: string }
  headroom: PanelHeadroom[]
  watchers: PanelWatcher[]
  sources: PanelSource[]
  kbAge: number | null
  measures: PanelMeasure[]
  isHandoverInstalled: boolean
  unreadable: string[]
  line: string
}

export type PanelRateLimit = { kind: string; percentUsed: number }

export type PanelView = {
  program: string
  digest: PanelDigest | null
  contextPercent: number | null
  rateLimits: PanelRateLimit[]
  compactions: number
  wakes: number
  ticks: number
  lastTickAt: number | null
  lastWakeAt: number | null
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
