import { mock } from 'claude-code/testing'
import type { Engine, MockClock } from 'claude-code/testing'
import type { On } from 'claude-code'

// The world beneath the mod in the plugin tests: every call it makes on `$`
// answered from fixture stores, every script run recorded.

export const START = 1_000_000_000

const tab = (...f: (string | number)[]) => f.join('\t')

export function digestText(o: { pending?: number; extra?: string[]; refresh?: number; tick?: number } = {}): string {
  return [
    tab('format', 1),
    tab('program', 'alpha'),
    tab('taken', 1000),
    tab('knob', 'refresh', o.refresh ?? 10),
    tab('knob', 'tick', o.tick ?? 300),
    tab('knob', 'handover-context', 70),
    tab('knob', 'handover-wakes', 3),
    tab('knob', 'handover-compactions', 2),
    tab('flight', 'w-one', 'mission-control:alpha', 'stream-json'),
    tab('flight', 'w-two', 'flight:docs', 'tmux'),
    tab('waiting', 2),
    tab('pending', o.pending ?? 0),
    tab('decision', '2026-10-26T10:15:00Z', 'relaunch w-one', 'relaunch'),
    tab('rung', 'throttle', 'polls_per_hour at 72%'),
    tab('headroom', 'sessions', 2, 4, 50),
    tab('headroom', 'polls_per_hour', 72, 100, 72),
    tab('watcher', 'inbox', 'inbox-watch.sh', 'stopped', -40),
    tab('source', 'work-items', 'specs', 'record', '-'),
    tab('source', 'code-state', 'forge', 'snapshot', 90),
    tab('source', 'designs', '-', 'cited', '-'),
    tab('kb', 600),
    tab('measure', 'interruptions_per_hour', '2.5', 130),
    tab('measure', 'settled_share', '80', 130),
    tab('handover', 'absent'),
    ...(o.extra ?? []),
    tab('line', 'mission control alpha: 2 in flight, 2 waiting, 0 pending, rung throttle'),
  ].join('\n')
}

export const WAKE = ['wake\t1\te1000.ab12', 'mission control (alpha): 1 event(s) pending.', '- pr-ready pr-7'].join(
  '\n',
)

export const PANE = {
  plugin: 'planwright',
  component: 'Pane',
  requestId: 'mission-control',
  props: {
    title: 'Mission control',
    isFocused: false,
    bodyColumns: 60,
    placement: 'dock',
    scroll: { offset: 0, bodyRows: 40 },
    view: {},
  },
} as const

export const BAND = {
  plugin: 'planwright',
  component: 'AbovePrompt',
  requestId: 'band',
  props: {
    hasSurvey: false,
    isWorking: false,
    maxRows: 3,
    bodyColumns: 120,
    scroll: { offset: 0, bodyRows: 3 },
    view: {},
  },
} as const

export const turn = (id: string, agentId?: string) => ({ text: '', turnId: id, ...(agentId ? { agentId } : {}) })
export const done = (id: string, agentId?: string) =>
  ({
    text: '',
    turnId: id,
    answer: '',
    durationMs: 5,
    isAborted: false,
    reason: 'answer',
    ...(agentId ? { agentId } : {}),
  }) as const

export type World = {
  clock: MockClock
  runs: string[][]
  submitted: string[]
  statuses: (string | undefined)[]
  toasts: string[]
  opened: number
  envWrites: [string, string | undefined][]
  set: (o: Partial<Fixture>) => void
}

export type Fixture = {
  digest: string
  digestExit: number
  wake: string
  composeExit: number
  markExit: number
  emitExit: number
  rules: string
  rulesExit: number
  isPlaced: boolean
  isDropped: boolean
  contextPercent: number | undefined
  env: Record<string, string>
}

export function world(on: On, given: Partial<Fixture> = {}): World {
  const fx: Fixture = {
    digest: digestText(),
    digestExit: 0,
    wake: 'idle',
    composeExit: 0,
    markExit: 0,
    emitExit: 0,
    rules: '<!-- rules begin -->\n- R1 never merge\n<!-- rules end -->',
    rulesExit: 0,
    isPlaced: true,
    isDropped: false,
    contextPercent: 42,
    env: { PLANWRIGHT_MC_PROGRAM: 'alpha' },
    ...given,
  }
  const w: World = {
    clock: mock.clock(on, { now: START }),
    runs: [],
    submitted: [],
    statuses: [],
    toasts: [],
    opened: 0,
    envWrites: [],
    set: o => Object.assign(fx, o),
  }
  mock.env(on, fx.env)
  on('env.set', (_, e) => {
    w.envWrites.push([e.name, e.value])
    return { value: {} }
  })
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('session.end', (_, e) => ({ sessionId: e.sessionId }))
  on('command.register', () => ({ value: { command: 'mission-control' } }))
  on('ui.open', () => {
    w.opened += 1
    return { value: fx.isPlaced ? { isPlaced: true } : { isPlaced: false, reason: 'no-surface' } }
  })
  on('ui.status', (_, e) => {
    w.statuses.push(e.text)
    return { value: undefined }
  })
  on('ui.toast', (_, e) => {
    w.toasts.push(e.text)
    return { value: undefined }
  })
  on('session.usage', () => ({
    value: {
      startedAt: START,
      context: { window: 200_000, percent: fx.contextPercent },
      rateLimits: [{ kind: 'five_hour', percentUsed: 31 }],
    },
  }))
  on('prompt.submit', (_, e) => {
    if (fx.isDropped) return { drop: 'a guard refused it' }
    w.submitted.push(e.text)
    return { text: e.text }
  })
  on('turn.start', (_, e) => ({ turnId: e.turnId }))
  on('turn.complete', () => ({ text: '' }))
  on('session.compact', (_, e) => ({ messages: e.messages }))
  on('process.run', (_, e) => {
    const argv = [...e.argv]
    w.runs.push(argv)
    const script = (argv[1] ?? '').split('/').pop()
    const verb = argv[2]
    const answer = (stdout: string, exitCode = 0) => ({
      value: {
        exitCode,
        stdout,
        stderr: exitCode === 0 ? '' : 'store unreadable',
        isStdoutTruncated: false,
        isStderrTruncated: false,
      },
    })
    if (script === 'mc-panel.sh' && verb === 'digest') return answer(fx.digest, fx.digestExit)
    if (script === 'mc-wake.sh' && verb === 'compose') return answer(fx.wake, fx.composeExit)
    if (script === 'mc-event.sh' && verb === 'mark') return answer('', fx.markExit)
    if (script === 'mc-event.sh' && verb === 'emit') return answer('e1.ff', fx.emitExit)
    if (script === 'mc-rules.sh') return answer(fx.rulesExit === 0 ? fx.rules : '', fx.rulesExit)
    return answer('')
  })
  return w
}

export const ran = (w: World, script: string, verb: string): string[][] =>
  w.runs.filter(r => (r[1] ?? '').endsWith(`/scripts/${script}`) && r[2] === verb)

// Starts the session and lets the bring-up the start hook schedules run.
export async function boot($: Engine, w: World) {
  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })
  await w.clock.settle()
}
