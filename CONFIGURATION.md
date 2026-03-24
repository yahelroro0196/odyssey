# Configuration Reference

All configuration lives in `WORKFLOW.md` as YAML front matter between `---` delimiters. The
Markdown body after the second `---` is the agent prompt template (Liquid syntax).

Environment variable indirection is supported: use `$VAR_NAME` as a value and Odyssey resolves it
at load time. Path values expand `~` to the home directory.

## Tracker

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `tracker.kind` | string | **required** | `"linear"`, `"jira"`, or `"github"` |
| `tracker.api_key` | string | `$LINEAR_API_KEY` / `$JIRA_API_TOKEN` / `$GITHUB_TOKEN` | API token (resolved per tracker kind) |
| `tracker.active_states` | string[] | `["Todo", "In Progress"]` | Issue states that trigger agent dispatch |
| `tracker.terminal_states` | string[] | `["Closed", "Cancelled", ...]` | Issue states that stop agents and clean up |
| `tracker.assignee` | string | nil | Filter to issues assigned to this user (`"me"` supported for Linear) |

### Linear-specific

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `tracker.endpoint` | string | `https://api.linear.app/graphql` | GraphQL endpoint |
| `tracker.project_slug` | string | **required** | Linear project slug (from project URL) |

### Jira-specific

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `tracker.base_url` | string | **required** / `$JIRA_BASE_URL` | Jira instance URL (e.g. `https://company.atlassian.net`) |
| `tracker.project_key` | string | **required** | Jira project key (e.g. `"PROJ"`) |
| `tracker.email` | string | `$JIRA_EMAIL` | Email for Basic auth (Jira Cloud) |
| `tracker.jql_filter` | string | nil | Additional JQL filter appended to queries |

### GitHub Issues-specific

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `tracker.repo` | string | **required** / `$GITHUB_REPOSITORY` | GitHub repo in `"owner/repo"` format |

Note: GitHub Issues uses labels to simulate workflow states. `active_states` and `terminal_states`
map to label names.

## Polling

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `polling.interval_ms` | integer | `30000` | Milliseconds between tracker polls |

## Workspace

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `workspace.root` | string | system tmp dir | Root directory for per-issue workspaces |
| `workspace.source_repo` | string | nil | Source repo path (for worktree-based workspaces) |

## Worker

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `worker.ssh_hosts` | string[] | `[]` | SSH hosts for remote workspace execution |
| `worker.max_concurrent_agents_per_host` | integer | nil | Per-host concurrency limit |

## Agent

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `agent.max_concurrent_agents` | integer | `10` | Global max concurrent agent sessions |
| `agent.max_turns` | integer | `20` | Max turns per agent invocation |
| `agent.max_retry_backoff_ms` | integer | `300000` | Max retry backoff delay (5 min) |
| `agent.max_concurrent_agents_by_state` | map | `{}` | Per-state concurrency limits (e.g. `{"In Progress": 5}`) |

## Codex (primary agent)

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `codex.provider` | string | `"codex"` | `"codex"` or `"claude_code"` |
| `codex.command` | string | `"codex app-server"` | Shell command to launch the agent |
| `codex.approval_policy` | string/map | reject sandbox+rules+mcp | Codex approval policy |
| `codex.thread_sandbox` | string | `"workspace-write"` | `"read-only"`, `"workspace-write"`, or `"danger-full-access"` |
| `codex.turn_sandbox_policy` | map | nil | Custom turn sandbox policy (passed through to Codex) |
| `codex.turn_timeout_ms` | integer | `3600000` | Turn timeout (1 hour) |
| `codex.read_timeout_ms` | integer | `5000` | Read timeout for agent responses |
| `codex.stall_timeout_ms` | integer | `300000` | Stall detection timeout (5 min) |
| `codex.max_tokens_per_agent` | integer | nil | Hard token cap per agent session |
| `codex.budget_warning_pct` | integer | `80` | Soft warning threshold (% of max_tokens) |
| `codex.claude_code_options` | map | nil | Claude Code-specific options (model, max_turns, etc.) |

## Review Agent

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `review_agent.enabled` | boolean | `false` | Enable the review agent role |
| `review_agent.provider` | string | `"codex"` | Agent provider for review |
| `review_agent.command` | string | `"codex app-server"` | Shell command for review agent |
| `review_agent.prompt` | string | nil | Review-specific prompt template |
| `review_agent.state_name` | string | `"AI Review"` | Issue state that triggers review |
| `review_agent.max_tokens_per_agent` | integer | nil | Token cap for review sessions |
| `review_agent.budget_warning_pct` | integer | `80` | Warning threshold for review |

## Hooks

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `hooks.after_create` | string | nil | Shell script run after workspace creation |
| `hooks.before_run` | string | nil | Shell script run before each agent session |
| `hooks.after_run` | string | nil | Shell script run after each agent session |
| `hooks.before_remove` | string | nil | Shell script run before workspace removal |
| `hooks.timeout_ms` | integer | `60000` | Hook execution timeout (1 min) |

## Persistence

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `persistence.mode` | string | `"memory"` | `"memory"` (no persistence) or `"sqlite"` |
| `persistence.database` | string | `priv/odyssey.db` | SQLite database file path |

## Budget

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `budget.daily_token_limit` | integer | nil | Daily token cap across all agents (nil = unlimited) |
| `budget.weekly_token_limit` | integer | nil | Weekly token cap (nil = unlimited) |
| `budget.cost_per_1k_input_tokens` | float | nil | Input token rate for cost estimation |
| `budget.cost_per_1k_output_tokens` | float | nil | Output token rate for cost estimation |
| `budget.currency` | string | `"USD"` | Currency label for dashboard display |

## Approval Gates

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `approval_gates.before_dispatch` | boolean | `false` | Require approval before agent dispatch |
| `approval_gates.before_merge` | boolean | `false` | Require approval before merge continuation |
| `approval_gates.timeout_ms` | integer | `600000` | Auto-resolve timeout (10 min) |
| `approval_gates.timeout_action` | string | `"approve"` | `"approve"` or `"reject"` on timeout |

## Notifications

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `notifications.webhook_url` | string | nil | Generic webhook URL for event POSTs |
| `notifications.slack_webhook_url` | string | nil | Slack incoming webhook URL |

## Observability

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `observability.dashboard_enabled` | boolean | `true` | Enable terminal status dashboard |
| `observability.refresh_ms` | integer | `1000` | Dashboard refresh interval |
| `observability.render_interval_ms` | integer | `16` | Terminal render interval |
| `observability.prometheus_enabled` | boolean | `false` | Enable `/metrics` Prometheus endpoint |

## Server

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `server.port` | integer | nil | Phoenix server port (nil = disabled) |
| `server.host` | string | `"127.0.0.1"` | Server bind address |

## Full Example

```yaml
---
tracker:
  kind: linear
  project_slug: "my-project"
  active_states: [Todo, In Progress, AI Review, Merging, Rework]
  terminal_states: [Closed, Cancelled, Completed, Done]
polling:
  interval_ms: 5000
workspace:
  root: ~/code/workspaces
  source_repo: ~/code/my-repo
hooks:
  after_create: |
    cd elixir && mix deps.get
agent:
  max_concurrent_agents: 10
  max_turns: 20
codex:
  command: codex app-server
  approval_policy: never
  thread_sandbox: workspace-write
  max_tokens_per_agent: 500000
  budget_warning_pct: 80
review_agent:
  enabled: true
  state_name: AI Review
persistence:
  mode: sqlite
budget:
  daily_token_limit: 5000000
  cost_per_1k_input_tokens: 0.003
  cost_per_1k_output_tokens: 0.015
approval_gates:
  before_dispatch: false
  before_merge: true
  timeout_ms: 600000
notifications:
  slack_webhook_url: "https://hooks.slack.com/services/..."
observability:
  prometheus_enabled: true
server:
  port: 4000
---

You are working on ticket {{ issue.identifier }}...
```
