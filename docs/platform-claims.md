# Platform claims

planwright relies on a few facts about hosts it does not control: how a cloud session marks
itself, what Cowork keeps between sessions, what an outside API accepts. These rot faster than
the code that depends on them, and nothing in the test suite notices when one stops being true.
This register is where each one is written down with its source, so it can be checked again.

## How the register is kept

Each claim is an `### PC-<n> — <title>` entry with five fields: the **Claim** in one or two
sentences, the file it is **Relied on by** (a repository path in backticks), the **Source** it was
verified against (an https URL in angle brackets, official documentation first), the date it was
**Verified**, and the date it must be verified again by (**Re-verify-by**). Fast-moving surfaces
get a short window.
IDs are never reused; a claim that stops mattering is deleted with the code that relied on it.

`scripts/check-platform-claims.sh` guards the register:

- **In the gate** (`mise run check:platform-claims`), a malformed entry fails, and a claim past its
  re-verify date is listed as `due` without failing, so the suite never turns red on a date
  alone.
- **Before a release** (`scripts/check-platform-claims.sh --strict`, a step in the
  [release checklist](release-checklist.md)), a due claim fails as well. Re-verify it against its
  source; if it still holds, advance both dates; if it changed, change the code that relies on it
  in the same pull request.

## Claims

### PC-1 — Claude Code marks a cloud session

- **Claim:** Claude Code sets `CLAUDE_CODE_REMOTE=true` in a cloud session, and documents it as the
  way a hook or script detects one. The venture helper reads it to treat the host as ephemeral.
- **Relied on by:** `scripts/inception-venture.sh`
- **Source:** <https://code.claude.com/docs/en/env-vars>
- **Verified:** 2026-10-25
- **Re-verify-by:** 2027-01-25

### PC-2 — Cowork sets no variable a session can read

- **Claim:** Neither Claude Code's environment-variable reference nor Cowork's architecture
  overview documents a variable that marks a Cowork session, so the venture helper detects Cowork
  only through the operator's `PLANWRIGHT_INCEPTION_HOST=cowork`. A documented signal appearing
  is the cue to read it instead.
- **Relied on by:** `scripts/inception-venture.sh`
- **Source:** <https://support.claude.com/en/articles/14479288>
- **Verified:** 2026-10-25
- **Re-verify-by:** 2026-12-25

### PC-3 — Cowork cloud sessions discard their sandbox

- **Claim:** Cowork runs sessions in the cloud by default, in a sandbox created when the session
  starts and destroyed when it ends; a local session instead runs in a Linux VM on the device,
  over folders the member connects. The venture helper therefore treats a Cowork host as
  ephemeral unless the operator overrides it for a connected folder.
- **Relied on by:** `scripts/inception-venture.sh`
- **Source:** <https://support.claude.com/en/articles/14479288>
- **Verified:** 2026-10-25
- **Re-verify-by:** 2026-12-25

### PC-4 — Cowork egress is allowlisted

- **Claim:** A Cowork cloud session's outbound traffic goes through a proxy that reaches only
  allowlisted destinations, and Enterprise organizations default to no network access, so
  `git pull` and `git push` can fail inside a session. The sync protocol's blocked-network
  section and the helper's Cowork caveat rest on this.
- **Relied on by:** `scripts/inception-scaffold.sh`
- **Source:** <https://support.claude.com/en/articles/14479288>
- **Verified:** 2026-10-25
- **Re-verify-by:** 2026-12-25

### PC-5 — CLAUDE.md imports a file by relative path

- **Claim:** A `CLAUDE.md` line `@path` imports that file into the session's context, with a
  relative path resolved against the importing file, and Claude Code's memory documentation names
  Cowork sessions among those that load these files. A venture's `CLAUDE.md` carries the sync
  protocol this way. Whether Cowork reads any other instructions file in a folder is
  undocumented; the [Cowork validation record](inception-cowork-validation.md) is where a real run
  settles it.
- **Relied on by:** `scripts/inception-scaffold.sh`
- **Source:** <https://code.claude.com/docs/en/memory>
- **Verified:** 2026-10-25
- **Re-verify-by:** 2026-12-25

### PC-6 — Cloud sessions keep work only by pushing it

- **Claim:** A Claude Code cloud session runs in a VM that is reclaimed after inactivity;
  reopening it restores the conversation but not the VM, so work survives only once it is pushed
  to a branch. This is why the cloud host's local arm is session-only and the private-remote home
  is the one to choose there.
- **Relied on by:** `scripts/inception-venture.sh`
- **Source:** <https://code.claude.com/docs/en/claude-code-on-the-web>
- **Verified:** 2026-10-25
- **Re-verify-by:** 2027-01-25

### PC-7 — Notion accepts and returns page content as Markdown

- **Claim:** The Notion API creates a page from a `markdown` body parameter on `POST /v1/pages`,
  and reads and edits page content as Markdown through `/v1/pages/:page_id/markdown`, under the
  `2026-03-11` API version. The Notion export adapter's case for a lossless-enough export rests on
  it.
- **Relied on by:** `specs/inception/design.md`
- **Source:** <https://developers.notion.com/guides/data-apis/working-with-markdown-content>
- **Verified:** 2026-10-25
- **Re-verify-by:** 2027-01-25
