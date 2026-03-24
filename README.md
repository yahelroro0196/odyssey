# Odyssey

Odyssey orchestrates coding agents to autonomously execute project work — polling issue trackers,
spinning up isolated workspaces, and running agent sessions end-to-end so teams manage work, not
agents.

[![Odyssey demo video preview](.github/media/odyssey-demo-poster.jpg)](.github/media/odyssey-demo.mp4)

_In this [demo video](.github/media/odyssey-demo.mp4), Odyssey monitors a Linear board for work and spawns agents to handle the tasks. The agents complete the tasks and provide proof of work: CI status, PR review feedback, complexity analysis, and walkthrough videos. When accepted, the agents land the PR safely. Engineers manage work at a higher level instead of supervising individual agent turns._

> [!WARNING]
> Odyssey is a low-key engineering preview for testing in trusted environments.

## Features

- **Multi-tracker support** — Poll issues from Linear, Jira, or GitHub Issues via a pluggable adapter layer
- **Multiple agent runtimes** — Run Codex (JSON-RPC) or Claude Code (CLI) as the coding agent backend
- **Persistent state & crash recovery** — Optional SQLite-backed persistence for retry queues, session history, and token accounting
- **Human-in-the-loop approval gates** — Configurable checkpoints before dispatch or merge, with dashboard UI and REST API
- **Prometheus metrics & Slack alerts** — Export telemetry to `/metrics` and send event notifications to Slack
- **Token budget enforcement** — Per-agent and global daily/weekly token caps with soft warnings and cost estimation

## Documentation

| Document | Description |
|----------|-------------|
| [QUICKSTART.md](QUICKSTART.md) | Get running in minutes |
| [SPEC.md](SPEC.md) | Language-agnostic service specification |
| [ARCHITECTURE.md](ARCHITECTURE.md) | System design and component overview |
| [CONFIGURATION.md](CONFIGURATION.md) | Full WORKFLOW.md config reference |
| [API.md](API.md) | REST API endpoint reference |
| [CHANGELOG.md](CHANGELOG.md) | Version history |
| [elixir/README.md](elixir/README.md) | Elixir reference implementation setup |

## Supported Agent Runtimes

Odyssey supports multiple coding agent backends, configurable per role (coder / reviewer) in
`WORKFLOW.md`:

| Provider | Mode | Configuration |
|----------|------|---------------|
| **Codex** (default) | JSON-RPC 2.0 app-server over stdio | `provider: codex` |
| **Claude Code** | CLI with `--output-format stream-json` | `provider: claude_code` |

Set the `provider` field under `codex:` or `review_agent:` in your `WORKFLOW.md` to choose the
backend. Both providers support multi-turn sessions, auto-approval for unattended operation, and
streaming event observability through the dashboard.

## Running Odyssey

### Requirements

Odyssey works best in codebases that have adopted
[harness engineering](https://openai.com/index/harness-engineering/). Odyssey is the next step --
moving from managing coding agents to managing work that needs to get done.

### Option 1. Make your own

Tell your favorite coding agent to build Odyssey in a programming language of your choice:

> Implement Odyssey according to the following spec:
> https://github.com/openai/odyssey/blob/main/SPEC.md

### Option 2. Use our experimental reference implementation

Check out [elixir/README.md](elixir/README.md) for instructions on how to set up your environment
and run the Elixir-based Odyssey implementation. You can also ask your favorite coding agent to
help with the setup:

> Set up Odyssey for my repository based on
> https://github.com/openai/odyssey/blob/main/elixir/README.md

---

## License

This project is licensed under the [Apache License 2.0](LICENSE).
