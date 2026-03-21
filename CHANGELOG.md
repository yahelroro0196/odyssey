# Changelog

All notable changes to Odyssey are documented in this file.

## Unreleased

### Added

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
