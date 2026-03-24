# Changelog

All notable changes to Odyssey are documented in this file.

## Unreleased

### Added

- **Multi-tracker support** -- Pluggable tracker adapters for Linear, Jira (REST API), and GitHub Issues (label-based state). Configure via `tracker.kind` in WORKFLOW.md.
- **Persistent state & crash recovery** -- Optional SQLite-backed persistence (`persistence.mode: sqlite`) for retry queues, session history, token accounting, and event logs. Automatic recovery on restart.
- **Human-in-the-loop approval gates** -- Configurable `before_dispatch` and `before_merge` gates with dashboard approve/reject UI, REST API endpoints, timeout policies, and Slack notifications.
- **Prometheus metrics export** -- `/metrics` endpoint exposing counters, gauges, and histograms for issues dispatched/completed, token usage, agent duration, retry queue size, and concurrent agents.
- **Slack notifications** -- Webhook-based alerts for agent completions, failures, budget warnings, and approval requests.
- **Token budget enforcement** -- Per-agent `max_tokens_per_agent` now enforced with soft warnings at configurable threshold (`budget_warning_pct`). Global daily/weekly token caps via `budget.daily_token_limit`.
- **Cost estimation dashboard** -- Dashboard cards showing estimated USD cost based on configurable token rates.
- **Tiered test framework** -- 161 new tests across 20 files with tag-based execution tiers (unit, component, integration, e2e).
- **Config reload feedback** -- WorkflowStore now logs successful reloads with changed sections, broadcasts `{:config_reloaded, metadata}` via PubSub, and exposes `reload_status/0` and `subscribe_config/0` APIs.
- **Config reload dashboard indicator** -- Operations dashboard shows a "Config reloaded" badge when WORKFLOW.md changes are detected, with tooltip showing changed sections and timestamp.
- **Config reload in API** -- `GET /api/v1/state` includes a `config` key with `last_reloaded_at`, `last_changed_sections`, and `reload_count`.
- **Agent chat view** -- Full-screen event stream view at `/issues/:issue_identifier` showing real-time Codex agent events with color-coded badges, humanized messages, and expandable raw JSON. Accessible by clicking issue identifiers in the dashboard.
- **EventStore** -- ETS-backed GenServer accumulating per-agent events in a bounded ring buffer (max 500), with PubSub streaming for live updates.

### Fixed

- SSH retries kept in orchestrator (#54).
- Malformed JSON event from Codex message (#50).

### Changed

- SSH worker support added to Odyssey Elixir.
- Stabilized orchestration and policy handling.
- Aligned workflow config spec with schema behavior.
- Refactored config access around an Ecto schema.
- Moved observability dashboard to Phoenix (#29).
