# Architecture

Odyssey is a long-running service that polls issue trackers, creates isolated workspaces, and
dispatches coding agents to work on issues autonomously.

## System Overview

```
                          WORKFLOW.md
                              |
                              v
 +----------+    +-------------------------+    +-----------------+
 |  Tracker  |<-->|     Orchestrator        |<-->|  Agent Runner   |
 |  Adapter  |   | (poll, dispatch, retry)  |   | (workspace,     |
 +----------+    +-------------------------+    |  prompt, turns)  |
  Linear/Jira/        |          |              +-----------------+
  GitHub              v          v                     |
              +-----------+ +-----------+              v
              | Approval  | |Persistence|        +-----------+
              |   Store   | |  (SQLite) |        |  Agent    |
              +-----------+ +-----------+        |  Backend  |
                    |                            +-----------+
                    v                             Codex / Claude
              +-----------+
              | Dashboard |
              | (LiveView)|
              +-----------+
```

## Core Components

### Orchestrator (`orchestrator.ex`)

The central GenServer that owns the polling loop and all runtime state:

- **Polling**: Fetches candidate issues from the tracker on a fixed cadence
- **Dispatch**: Spawns agent tasks with bounded concurrency (`max_concurrent_agents`)
- **Retry queue**: Exponential backoff (10s base, capped at `max_retry_backoff_ms`) for failed agents; 1s delay for continuation retries
- **Reconciliation**: Every tick, verifies running issues are still in active states; stops agents for terminal issues
- **Stall detection**: Terminates agents that haven't emitted events within `stall_timeout_ms`
- **Token accounting**: Tracks per-session and global token usage, enforces budgets

### Agent Runner (`agent_runner.ex`)

Executes a single issue's agent session:

1. Creates workspace via `Workspace.create_for_issue/2`
2. Runs lifecycle hooks (`before_run`)
3. Builds prompt via `PromptBuilder`
4. Enters multi-turn loop: `run_turn` -> check issue state -> next turn or exit
5. Runs cleanup hooks (`after_run`)
6. Reports results back to orchestrator via message passing

### Agent Backends

| Backend | Protocol | Module |
|---------|----------|--------|
| **Codex** | JSON-RPC 2.0 over stdio | `codex/app_server.ex` |
| **Claude Code** | CLI with `--output-format stream-json` | `claude_code/cli_client.ex` |

Both implement the `AgentBackend` behaviour: `start_session/2`, `run_turn/4`, `stop_session/1`.

### Tracker Adapters

| Tracker | Module | State Model |
|---------|--------|-------------|
| **Linear** | `linear/adapter.ex` | Native workflow states via GraphQL |
| **Jira** | `jira/adapter.ex` | Status transitions via REST API |
| **GitHub Issues** | `github/adapter.ex` | Labels simulate workflow states |

All implement the `Tracker` behaviour. Selection via `tracker.kind` in WORKFLOW.md.

## Data Flow

```
1. Poll:     Tracker.fetch_candidate_issues()
2. Filter:   Skip claimed, blocked, at-concurrency-limit
3. Gate:     If approval_gates.before_dispatch → pause for approval
4. Dispatch: AgentRunner.run(issue, orchestrator_pid, opts)
5. Session:  Backend.start_session → run_turn (loop) → stop_session
6. Report:   {:agent_worker_update, issue_id, event} messages to orchestrator
7. Complete: Schedule continuation retry or release claim
8. Gate:     If approval_gates.before_merge → pause for approval
```

## Persistence Layer

Optional SQLite-backed persistence (`persistence.mode: sqlite`):

| Table | Purpose |
|-------|---------|
| `sessions` | Session metadata, tokens, status, duration |
| `issue_token_totals` | Aggregated per-issue token usage |
| `daily_token_totals` | Daily token summaries for budget enforcement |
| `retry_snapshots` | Retry queue state for crash recovery |
| `events` | Append-only event log |

On startup, the orchestrator loads retry snapshots and global totals from the database to recover
state. The `Persistence` facade routes to either `Memory` (no-op) or `SQLite` backend based on config.

## Approval Gates

Two configurable gates pause the orchestrator for human approval:

- **before_dispatch**: After an issue is selected but before the agent is spawned
- **before_merge**: After an agent completes normally, before scheduling continuation

The `ApprovalStore` GenServer manages pending approvals with:
- Configurable timeout (auto-approve or auto-reject)
- PubSub broadcast for dashboard updates
- REST API endpoints for external integrations

## Metrics & Observability

- **Telemetry events** emitted at dispatch, completion, failure, turn, and token update points
- **Prometheus** `/metrics` endpoint via `telemetry_metrics_prometheus_core`
- **Slack** webhook notifications for completions, failures, budget warnings, and approval requests
- **LiveView dashboard** with real-time sessions, retry queue, token totals, cost estimation, and approval UI
- **REST API** at `/api/v1/*` for programmatic access (see [API.md](API.md))

## Token Budget Enforcement

Three levels of budget control:

1. **Per-agent**: `codex.max_tokens_per_agent` — hard cap per session, terminates agent on exceed
2. **Warning threshold**: `codex.budget_warning_pct` — soft warning at configurable percentage
3. **Global daily/weekly**: `budget.daily_token_limit` / `budget.weekly_token_limit` — pauses dispatch when exceeded
