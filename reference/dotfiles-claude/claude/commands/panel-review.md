Do a comprehensive code review of the current feature branch using configurable non-Anthropic model backends, so the variance does not come exclusively from this Claude session.

Same Discovery + Validation rigor as `/self-review`. The backends provide the discovery angle (different training distributions catch what Claude would miss); validation is grounded locally in this session.

## When to use

You want a `/self-review` shape but with one or more external models contributing findings. Common cases:

- ChatGPT Enterprise users on a work repo (Codex CLI as a fast frontier-OpenAI backend).
- Personal repos (local Ollama models from different lineages: Alibaba's Qwen2.5-Coder, OpenAI's gpt-oss).
- Any time you want a non-Anthropic angle without paying GitHub Copilot's per-request quota.

For autonomous looping (review, apply, push, re-review until convergence), use `/panel-pairing` instead. For the standard Claude-only review, use `/self-review`.

## Pre-flight (once per run)

1. **Identify base branch and capture the diff** (same as `/self-review` step 1).
2. **(Optional) Jira ticket** (same as `/self-review` step 2).
3. **Detect repo profile.** Work or personal, driven by an untracked, machine-local
   signal so no employer identifiers live in this tracked, public file. Set
   `PANEL_REVIEW_PROFILE=work` on work machines (e.g. a fish universal variable or
   shell rc); anything else (unset or any other value) resolves to `personal`:

   ```bash
   case "${PANEL_REVIEW_PROFILE:-personal}" in
     work) echo work ;;
     *)    echo personal ;;
   esac
   ```

4. **Resolve the backend set.** If `$ARGUMENTS` contains `--backends a,b,c`, use those (comma-separated). Otherwise resolve the default from the merged pair-flow config: run `~/.claude/scripts/pair-flow-config.sh show` (the canonical merger of `~/.claude/pair-flow.yml` and `~/.claude/pair-flow.local.yml`, per D-6 / D-19) and read its `panel-backends` key; fall back to the profile table only if the config is missing:

   | Profile | Default backends |
   |---|---|
   | work | `codex` |
   | personal / alt | `gemini` |

   Supported backends: `codex`, `gemini`, `qwen-coder`, `gpt-oss`, `copilot`. `copilot` is **opt-in only** via `--backends`; do not auto-include it (the GitHub quota is the original constraint and including it implicitly defeats the point). `deepseek-r1` was retired: it is a reasoning model that emits `<think>` chain-of-thought blocks the panel prompt cannot reliably suppress, and ~2x wall-clock vs `qwen-coder`. `gpt-oss:20b` replaces it as a different-lineage second slot (OpenAI training, instruction-tuned, no reasoning trace). The Ollama models remain available via `--backends` for variance panels when wanted.

5. **Verify each backend.** Stop with a specific install / auth message if any fails; do not silently drop a backend (the user expects the variance the backend provides).

   - `codex`: `command -v codex` must succeed; `codex auth status` (or equivalent: query the codex CLI's own readiness probe) must report an authenticated session. If not authed, stop with `Codex CLI needs auth; run 'codex login'`. If not installed, stop with `Codex CLI not installed; mise run osx will install via Brewfile cask 'codex'`.
   - `gemini`: `command -v gemini` must succeed. The `GEMINI_API_KEY` env var must be set (the dotfiles fish conf.d/gemini.fish exports it from `~/.gemini/.api-key`, which is written by `scripts/claude-gemini-auth-sync.sh` from the 1Password item declared in that script). If `gemini` is missing, stop with `Gemini CLI not installed; mise run osx will install via Brewfile 'gemini-cli'`. If `GEMINI_API_KEY` is unset, stop with `Gemini CLI needs auth; run 'mise run osx' to sync from 1Password (requires the 1Password item UUID to be set in scripts/claude-gemini-auth-sync.sh) or set GEMINI_API_KEY manually`.
   - `qwen-coder` / `gpt-oss`: `curl -sf "${OLLAMA_BASE_URL:-http://localhost:11434}/api/tags"` must return a body containing the model name (`qwen2.5-coder:32b` or `gpt-oss:20b`). If the API does not respond, stop with `Ollama service not running; brew services start ollama` (on the work host; on personal/alt the dotfiles fish conf.d/ollama.fish points OLLAMA_BASE_URL at the work host's LAN IP, see dotfiles `CLAUDE.md` "Cross-host Ollama topology"). If the model is missing, stop with `Model not pulled; ollama pull <name>` (the dotfiles Ansible task pulls both on the work host by default; missing means an opt-out or the cross-host route is not configured).
   - `copilot`: `gh copilot --help` must succeed and the account must have quota. Stop if `gh` is not authenticated or `gh copilot` returns a quota-exhausted error.

## Steps

### 1. Run project tooling once

Linters, formatters, type checkers, static analyzers, complexity / duplication meters, dead-code detectors, security scanners. Discover via `lefthook.yml`, CI workflows, `mise.toml` tasks, language config files, and the SessionStart `tool-discovery` summary if present in this session's context. Capture the output; it becomes shared input for every backend so all of them ground their findings the same way (this is what makes "tool-grounded" survive backend variance).

### 2. Backend discovery pass

For each backend in the resolved set, invoke it **once** with the full diff, the tooling output from step 1, and a lens-walk prompt covering all 9 canonical lenses from CLAUDE.md `Discovery Rigor (Issue Identification)`. Each invocation is independent; run them in parallel (separate `Bash` tool calls in the same response) when possible.

**Prompt structure to send each backend** (adapt the literal wording per backend's preferences; the substance is what matters):

```
Review this diff. Walk every lens below and report findings for each. Severity-pruning is forbidden: a small doc nit and a critical bug must both be reported in the same pass. If a lens has no findings, return `none` with a one-line reason.

Lenses:
1. Correctness, logic, edge cases (null, empty, max size, concurrency, off-by-one, error paths)
2. Security (injection, auth, data exposure, secret handling, untrusted input)
3. Error handling and failure modes
4. Performance (allocation, IO, complexity, hot paths)
5. Concurrency / state (races, idempotency, ordering, retries)
6. Naming, readability, structure (only flag when this PR worsens it)
7. Documentation (docstrings, READMEs, ADRs, config docs)
8. Tests / verification (coverage of new behavior, missing failing-case tests)
9. Cross-file consistency (broken invariants, sibling-pattern drift)

Output format: ONLY a Markdown table with columns Lens, File:Line, Finding, Rule cited (if any), Severity. No preamble (including `<think>` blocks, "Thinking..." traces, or any reasoning model intermediate output). No commentary, observations, or summaries after the table. The table is the entire response. One row per finding; if a lens has zero findings, emit a row like `| Documentation | n/a | none (one-line reason) | | n/a |` so the empty lens stays visible.

Project tooling output (shared with all backends):
<tooling output from step 1>

Diff:
<full diff or relevant slice>
```

**Per-backend invocation patterns** (verify exact flags on first use; this is illustrative):

- **codex**: `codex exec "<prompt>"` (or the equivalent flag set; the CLI may require `--model` or similar). Codex returns text on stdout; capture and parse the table.
- **gemini**: `gemini -p "<prompt>" -o text` (the `-p` / `--prompt` flag drops the CLI into headless mode; `-o text` keeps stdout free of JSON envelope so the table parser sees the raw markdown). Add `-m <model>` to pin a specific Gemini model (defaults to whatever the CLI considers current). `--approval-mode plan` forces read-only operation. Stdout carries the model response; capture and parse the table.
- **qwen-coder** and **gpt-oss** (Ollama): **prefer the HTTP API** for programmatic invocation. The base URL is read from `OLLAMA_BASE_URL` (set in fish conf.d/ollama.fish on personal/alt hosts to the work host's LAN IP) and falls back to `http://localhost:11434` on the work host itself:
  ```bash
  curl -s "${OLLAMA_BASE_URL:-http://localhost:11434}/api/generate" \
    -d "$(jq -nR --arg model 'qwen2.5-coder:32b' --rawfile prompt /tmp/panel-review-prompt.txt \
      '{model: $model, prompt: $prompt, stream: false}')" \
    | jq -r '.response'
  ```
  The API returns clean JSON with the response under `.response`. `ollama run <model> "<prompt>"` works as a fallback but emits ANSI escape codes (cursor moves, line clears) intended for an interactive TTY; even when piped, those leak into the output and require post-processing (`sed -E 's/\x1b\[[0-9;]*[a-zA-Z]//g' | tr -d '\r'`). The HTTP API path avoids that entirely.
- **Wall-clock estimates on M1 Max 32GB** (one model loaded at a time; Ollama swaps when the second is invoked): `qwen-coder:32b` ~5 min, `gpt-oss:20b` ~3 min (smaller, instruction-tuned, no reasoning chain). qwen-coder at ~19 GB and gpt-oss at ~13 GB can't co-reside in unified memory comfortably, so the panel still serializes in practice; gpt-oss swaps in faster than the retired deepseek-r1:32b did.
- **copilot**: route through `gh copilot` or the chosen Copilot CLI; specifics depend on which CLI variant is current.

If a backend invocation **does not recover** (a final non-zero exit, empty or unparseable output, or auth lost with no successful retry), do **not** silently drop it: stop the run and surface the failure. Judge by the final outcome, not intermediate stderr: do **not** stop on transient quota / rate-limit / retry messages the backend CLI emits while it retries internally if it ultimately returns a valid result. The user invoked this skill specifically for the variance that backend provides; partial runs hide the fact that one source of variance went missing.

### 3. Merge backend findings

Build one normalized list:

- Dedupe by `(file, line, root issue)`. A finding flagged by multiple backends becomes one row with all backend labels tagged in the row.
- Tag every row with which backend(s) surfaced it. This is what lets you see, over time, which backends earn their keep on your code.
- A finding hitting two lenses (one backend assigned `Correctness`, another assigned `Error handling`) gets one row with both lens labels.

Apply the **review-mode refactor instinct** filter (CLAUDE.md `Refactor Instinct`): drop refactor flags not anchored in tool output that do not represent this-PR-makes-it-worse.

### 4. Self-critique pass (mandatory)

Re-scan the merged list with the assumption that it is incomplete. Add what feels under-represented. This is the same anti-silent-pruning guard the canonical Discovery Rigor specifies; backends can self-prune within their own context windows the same way a single coordinator agent can, so the critique pass is load-bearing even with multiple backends.

### 5. Validate every finding with the three-pass rigor

Apply CLAUDE.md `Validation Rigor (Issue Identification)` in full, locally in this Claude session, on every backend-surfaced finding:

- **Pass 1: direct reproduction.** Reproduce runtime claims (failing test, repro script, concrete-input trace).
- **Pass 2: orthogonal angle.** Callers, related paths, project conventions, sibling implementations, existing test coverage.
- **Pass 3: outside-in angle.** `git log` / `git blame`, repo-wide search, official docs, library source / tests, deepwiki MCP, GitHub issues, RFCs, web search for text or research-based claims.

Drop or downgrade items where the three passes do not converge. Backends produce findings; validation grounds them. A finding that survives three passes with high confidence routes to Auto-applicable or Needs sign-off per `Finding Categorization`; lower confidence or genuinely ambiguous resolutions route to Needs human judgment.

### 6. Present results

Lens-coverage table from CLAUDE.md `Discovery Rigor (Issue Identification)` first (one row per lens, counts merged across backends, with `none` / `n/a` rows where applicable). Then the **four findings tables in fixed order** per `Finding Categorization`: Auto-applicable, Agent-resolvable, Needs sign-off, Needs human judgment. Each table always appears; empty buckets get a single `none` row.

Findings tables include a `Backend(s)` column so you can see which model surfaced what. Suggested columns: `# | Lens | File:Line | Finding | Rule cited | Backend(s) | Validation passes | Confidence | Recommendation`. Drop columns that are uniformly empty.

### 7. Follow the standard review workflow

Per CLAUDE.md `Code & PR Reviews`: ask which mode (a/b/c/d) and apply progress tracking. Option sets are derived from the bucket per `Finding Categorization`:

- **Auto-applicable**: no question, apply with solution validation.
- **Needs sign-off**: standard `Apply / Skip / Modify` option set across batched and clustered modes.
- **Needs human judgment**: bespoke options per finding (skill authors the actual decision branches; generic timing options are forbidden, see `Finding Categorization` forcing function).

When implementing fixes, apply CLAUDE.md `Validation Rigor (Solutions)`: targeted failing test → fix → confirm pass; wider check (project tests, linters, type checkers); edge / integration / manual when relevant. For non-testable changes, substitute review angles and note why no test was added.

### 8. Documentation check

Before committing, verify documentation affected by the changes is up to date: docstrings, READMEs, requirements / design docs, task / planning files, configuration docs, any prose referencing changed code. Search the repo for references to changed function names, feature names, or concepts. Include doc issues in the review findings alongside code issues.

### 9. Commit, push, PR

After all items are addressed, commit. Then if the review found nothing substantive (or after everything is addressed), offer to push and handle the PR, gracefully reusing an existing one if present (same as `/self-review` step 9, including the push-hook failure handling that forbids `--no-verify`).

## Maintenance

After completing the workflow, check if any part of these instructions seems outdated or misaligned with current tooling: backend CLI command syntax changes (Codex flags, Ollama API), new backend options worth adding, changes to model names / sizes, or drift from `/self-review`'s discovery shape (which this skill mirrors). If something looks off, flag it and offer a ready-to-use prompt to paste into a new dotfiles session to update this command.

$ARGUMENTS
