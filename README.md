# claude-handoff

A `/handoff` skill for [Claude Code](https://code.claude.com) that writes the state compaction throws away: decisions and their why, options ruled out, what was tried and failed, where things stand, and the one executable next action. A SessionStart hook loads it back. A PreCompact hook writes a safety snapshot when you forget.

## Why

Context compaction keeps a summary, a handful of recently edited files, `CLAUDE.md`, auto-memory and the plan. It drops the reasoning. After a compaction the model knows *what* was decided and has lost *why*, which options were rejected, and what already failed. Auto-memory does not help: it excludes in-progress reasoning by design.

Practitioners report the same fix independently: end the session with a written note and start fresh. Amp retired compaction outright in favour of handoff threads. This repo makes the note a first-class artefact with a load path.

## What you get

| Piece | Path | Role |
|---|---|---|
| Skill | `skills/handoff/SKILL.md` | `/handoff` write, `/handoff resume`, `/handoff done` |
| Template | `skills/handoff/templates/handoff.md` | The document shape |
| Loader | `hooks/handoff-load.py` | SessionStart on `startup`, `resume`, `clear`, `compact`. Prints the newest handoff for the current branch into context. |
| Safety net | `hooks/handoff-precompact.py` | PreCompact. Writes a deterministic snapshot from the transcript and git when no fresh handoff exists. |
| Helpers | `hooks/handoff_common.py` | Git, frontmatter, timestamps, secret redaction. Stdlib only. |

## Install

```bash
git clone https://github.com/kam/claude-handoff.git
cd claude-handoff
./install.sh          # symlinks into ~/.claude and merges two hook entries into settings.json
# ./install.sh --copy     copy instead of symlink
# ./install.sh --uninstall
```

Requires `python3` and `git` on `PATH`. Restart Claude Code afterwards. Windows users: the hook commands in `settings.json` use `$HOME`; replace with `%USERPROFILE%` or an absolute path.

## Use

Run `/handoff` at a task boundary, or whenever the context is heavy and you are about to `/compact` or `/clear`. The skill reads the repo (branch, status, log, task file), writes or updates `.claude/handoffs/<date>-<branch>-<title>.md`, and tells you the next action. Then compact or clear freely. The next session, or the post-compaction context, starts with the handoff loaded.

`/handoff resume` reads the handoff, validates it against the repo, and proposes the next action. `/handoff done` closes it when the work ships.

### The document

```
---
status: active            # active | done | auto-snapshot
branch: feature/login
project: my-app
created: 2026-09-02T09:10
updated: 2026-09-02T14:32
next_action: Implement T-3 session store; run bin/rails test test/models/session_test.rb
tasks_file: docs/prd/login.tasks.md
---
# Handoff: Session-based login

## Goal and why
## Current state
## Decisions (with why, and options rejected)
## Tried and failed — do not repeat
## Blockers and open questions
## Next steps
## Artifacts (paths and URLs only)
## Resume and validate
## Audit log
```

Rules the skill enforces: decisions carry their why and the rejected alternatives; tried-and-failed is a do-not list with evidence; artefacts are paths, never contents; one executable next action first; the body is current state and revision history lives in the audit log.

## Trust model

Handoff files sit in the repo at `.claude/handoffs/` and are **git-excluded, never tracked**. The hooks add the exclude line to `<git-common-dir>/info/exclude` (so worktrees and submodules work) and never touch your `.gitignore`.

The loader treats the repo as untrusted:

- Files git tracks are refused with a notice. A cloned repo cannot ship a handoff into your context.
- Files without a `branch:` field are ignored. Only the current branch's files are candidates.
- `updated:` stamps in the future are ignored for ordering.
- Every loaded body is wrapped in a banner stating it is file content, not instructions, and the skill requires confirming `next_action` with the user before acting.

The snapshot hook redacts API keys (OpenAI, Anthropic, AWS, Google, GitHub, GitLab, Slack, Stripe), JWTs, PEM blocks, `user:pass@` URLs, `key=value` secrets and long high-entropy blobs from every field, including commit messages and paths. It writes nothing unless the exclude line is confirmed, never writes into `$HOME`, and keeps the last five snapshots per branch. Set `HANDOFF_SNAPSHOT_PROMPTS=0` to stop it recording user prompts at all.

Both hooks fail open: any internal error exits 0 and neither session start nor compaction is ever blocked.

## Configuration

| Variable | Default | Effect |
|---|---|---|
| `HANDOFF_LOAD_CAP` | `12000` | Characters the loader prints before truncating |
| `HANDOFF_FRESH_MINUTES` | `30` | Skip the snapshot when a manual handoff is newer than this |
| `HANDOFF_KEEP_SNAPSHOTS` | `5` | Snapshots kept per branch |
| `HANDOFF_SNAPSHOT_PROMPTS` | `1` | `0` disables verbatim prompt capture |

## Tests

```bash
tests/test_hooks.sh
```

Thirty-one scenarios in throwaway repos: redaction shapes, tracked-file refusal, branch filtering, ordering, BOM and quoting, detached HEAD, worktrees, `$HOME` guard, bad environment values, pruning.

## Design notes

- Manual `/handoff` is the primary path. The model writes the best document while it still holds the reasoning. The PreCompact snapshot is a fallback and says so in its own header.
- PreCompact stdout never reaches the model, so the snapshot only writes to disk; the SessionStart hook with source `compact` re-injects it.
- A handoff points at the project's task file for the queue. It never restates task status.
- Global skill, not a plugin: the workflow is the same in every repo, and a plugin command with the same name would shadow the skill.

## Licence

MIT.
