# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when
working with code in this repository.

**Standards reference**: <https://github.com/vergil-project/vergil-tooling>
— active standards documentation lives in the vergil-tooling repository under `docs/`.
Repository profile: `vergil.toml`.

## Memory management

Memory is allowed with human approval. The authoritative policy is in
the user's global `~/.claude/CLAUDE.md` — agents must propose memory
writes and suggest a destination (repo memory, global CLAUDE.md, or
plugin/skill issue) before writing. See that file for the full
workflow.

Available skills:
- `/vergil:memory-init` — set up or update the policy header
  in a project's `MEMORY.md`.
- `/vergil:memory-audit` — structured collaborative review
  of memory files.

## Parallel AI agent development

This repository supports running multiple Claude Code agents in parallel via
git worktrees. The convention keeps parallel agents' working trees isolated
while preserving shared project memory (which Claude Code derives from the
session's starting CWD).

**Canonical spec:**
[`vergil-tooling/docs/specs/worktree-convention.md`](https://github.com/vergil-project/vergil-tooling/blob/develop/docs/specs/worktree-convention.md)
— full rationale, trust model, failure modes, and memory-path implications.
The canonical text lives in `vergil-tooling`; this section is the local
on-ramp.

### Structure

```text
~/dev/github/mq-rest-admin-dev-environment/  ← sessions ALWAYS start here
  .git/
  CLAUDE.md, docker/, scripts/, …            ← main worktree (usually `develop`)
  .worktrees/                                ← container for parallel worktrees
    issue-96-adopt-worktree-convention/      ← worktree on feature/96-...
    …
```

### Rules

1. **Sessions always start at the project root.**
   `cd ~/dev/github/mq-rest-admin-dev-environment && claude` — never from inside
   `.worktrees/<name>/`. This keeps the memory-path slug stable and shared.
2. **Each parallel agent is assigned exactly one worktree.** The session
   prompt names the worktree (see Agent prompt contract below).
   - For Read / Edit / Write tools: use the worktree's absolute path.
   - For Bash commands that touch files: `cd` into the worktree first,
     or use absolute paths.
3. **The main worktree is read-only.** All edits flow through a worktree
   on a feature branch — the logical endpoint of the standing
   "no direct commits to `develop`" policy.
4. **One worktree per issue.** Don't stack in-flight issues. When a
   branch lands, remove the worktree before starting the next.
5. **Naming: `issue-<N>-<short-slug>`.** `<N>` is the GitHub issue
   number; `<short-slug>` is 2–4 kebab-case tokens.

### Agent prompt contract

When launching a parallel-agent session, use this template (fill in the
placeholders):

```text
You are working on issue #<N>: <issue title>.

Your worktree is: /Users/pmoore/dev/github/mq-rest-admin-dev-environment/.worktrees/issue-<N>-<slug>/
Your branch is:   feature/<N>-<slug>

Rules for this session:
- Do all git operations from inside your worktree:
    cd <absolute-worktree-path> && git <command>
- For Read / Edit / Write tools, use the absolute worktree path.
- For Bash commands that touch files, cd into the worktree first
  or use absolute paths.
- Do not edit files at the project root. The main worktree is
  read-only — all changes flow through your worktree on your
  feature branch.
```

All fields are required.

## Project Overview

Shared dockerized IBM MQ test environment for use across multiple
repositories. Provides container lifecycle scripts, seed data, and
a reusable GitHub Actions workflow for integration testing against
a real MQ queue manager.

**Project name**: mq-rest-admin-dev-environment

**Status**: Pre-alpha (initial setup)

**Consuming repositories**:

- `pymqrest` — Python wrapper for the MQ administrative REST API
- `mq-rest-admin` — Java port of pymqrest
- `pymqpcf` — Python wrapper for the MQ PCF API (planned)

## Development Commands

### Standard Tooling

```bash
cd ../vergil-tooling && uv sync                                                  # Install vergil-tooling
export PATH="../vergil-tooling/.venv/bin:../vergil-tooling/scripts/bin:$PATH"     # Put tools on PATH
git config core.hooksPath ../vergil-tooling/scripts/lib/git-hooks                 # Enable git hooks
```

### Environment Setup

- **Docker**: Docker Desktop or equivalent with Docker Compose v2
- **curl**: For REST API health checks (typically pre-installed on
  macOS/Linux)

### Container Lifecycle

```bash
scripts/mq_start.sh         # Start QM1 + QM2, wait for REST API readiness
scripts/mq_seed.sh           # Run MQSC seed commands on both queue managers
scripts/mq_verify.sh         # Verify seed objects exist via REST API
scripts/mq_reset.sh          # Stop + start + re-seed (full reset)
scripts/mq_stop.sh           # Stop and remove containers
```

### Validation

```bash
scripts/mq_verify.sh         # Verify MQ environment is correctly seeded
markdownlint . --ignore node_modules            # Lint documentation
```

## Architecture

### Environment Contract

Consuming repositories depend on these stable details:

| Property | Value |
| --- | --- |
| Queue manager 1 | QM1 |
| Queue manager 2 | QM2 |
| QM1 REST API | `https://localhost:9443/ibmmq/rest/v2` |
| QM2 REST API | `https://localhost:9444/ibmmq/rest/v2` |
| QM1 MQ listener | `localhost:1414` |
| QM2 MQ listener | `localhost:1415` |
| Admin user | `mqadmin` / `mqadmin` |
| Reader user | `mqreader` / `mqreader` |
| Docker image | `icr.io/ibm-messaging/mq:latest` (IBM MQ for Developers) |
| Docker network | `mq-dev-net` |

### Seed Data Strategy

- **Shared base**: This repository owns all common seed objects
  (queues, channels, topics, namelists, etc.) used across consuming
  repos
- **Repo-specific overlays**: Consuming repos may provide additional
  MQSC files when they need specialized objects beyond the shared
  base (deferred until needed)

### Consumption Model

- **Local development**: Consuming repos reference this repo as a
  sibling directory (`../mq-rest-admin-dev-environment`) — same pattern as
  `../vergil-tooling`
- **CI**: Reusable GitHub Actions workflow (or composite action) that
  starts the MQ containers, seeds them, and makes them available to
  the calling workflow's test jobs

### Repository Structure

```text
scripts/
    mq_start.sh          # Start containers + wait for readiness
    mq_seed.sh           # Run MQSC seed scripts
    mq_verify.sh         # Verify seed objects via REST API
    mq_reset.sh          # Full reset (stop + start + seed)
    mq_stop.sh           # Stop and remove containers
config/
    docker-compose.yml   # Container definitions (QM1, QM2)
    mqwebuser.xml        # REST API user/role configuration
seed/
    base-qm1.mqsc        # Shared seed objects for QM1
    base-qm2.mqsc        # Shared seed objects for QM2
docs/
    plans/               # Decision documents
    repository-standards.md
    vergil-tooling.md
```

## Key References

**Consuming repositories**:

- `../pymqrest` (Python MQ REST wrapper)
- `../mq-rest-admin` (Java MQ REST wrapper)

**External Documentation**:

- IBM MQ 9.4 administrative REST API
- IBM MQ for Developers container image documentation
