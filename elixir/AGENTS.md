# Odyssey Elixir

This directory contains the Elixir agent orchestration service that polls issue trackers (Linear, Jira, GitHub Issues), creates per-issue workspaces, and runs coding agents (Codex, Claude Code).

## Environment

- Elixir: `1.19.x` (OTP 28) via `mise`.
- Install deps: `mix setup`.
- Main quality gate: `make all` (format check, lint, coverage, dialyzer).


## Codebase-Specific Conventions

- Runtime config is loaded from `WORKFLOW.md` front matter via `OdysseyElixir.Workflow` and `OdysseyElixir.Config`.
- Keep the implementation aligned with [`../SPEC.md`](../SPEC.md) where practical.
  - The implementation may be a superset of the spec.
  - The implementation must not conflict with the spec.
  - If implementation changes meaningfully alter the intended behavior, update the spec in the same
    change where practical so the spec stays current.
- Prefer adding config access through `OdysseyElixir.Config` instead of ad-hoc env reads.
- Workspace safety is critical:
  - Never run Codex turn cwd in source repo.
  - Workspaces must stay under configured workspace root.
- Orchestrator behavior is stateful and concurrency-sensitive; preserve retry, reconciliation, and cleanup semantics.
- Follow `docs/LOGGING.md` for logging conventions and required issue/session context fields.
- New tracker adapters must implement `OdysseyElixir.Tracker` behaviour and use `client_module/0` DI pattern (see `linear/adapter.ex:76`).
- Persistence code goes under `lib/odyssey_elixir/persistence/`; new tables need an Ecto migration and schema.
- New Ecto schemas live in `lib/odyssey_elixir/persistence/schemas/`.

## Tests and Validation

Tests use a tiered tag system:

```bash
mix test                           # Unit + component (default)
mix test --include integration     # + integration tests
mix test --include e2e             # + end-to-end tests
```

Tag new tests with `@tag :integration` or `@tag :e2e` as appropriate. Use `FakeJiraClient`/`FakeGitHubClient` from `test/support/fake_tracker_clients.exs` for tracker adapter tests.

Run targeted tests while iterating, then run full gates before handoff.

```bash
make all
```

## Required Rules

- Public functions (`def`) in `lib/` must have an adjacent `@spec`.
- `defp` specs are optional.
- `@impl` callback implementations are exempt from local `@spec` requirement.
- Keep changes narrowly scoped; avoid unrelated refactors.
- Follow existing module/style patterns in `lib/odyssey_elixir/*`.

Validation command:

```bash
mix specs.check
```

## PR Requirements

- PR body must follow `../.github/pull_request_template.md` exactly.
- Validate PR body locally when needed:

```bash
mix pr_body.check --file /path/to/pr_body.md
```

## Docs Update Policy

If behavior/config changes, update docs in the same PR:

- `../README.md` for project concept and goals.
- `README.md` for Elixir implementation and run instructions.
- `WORKFLOW.md` for workflow/config contract changes.
