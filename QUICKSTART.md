# Quickstart

## Add Odyssey to your repo

```bash
git submodule add https://github.com/yahelroro0196/odyssey.git odyssey
```

## Create a WORKFLOW.md

Create a `WORKFLOW.md` (or `orchestration/WORKFLOW.md`) in your repo with YAML front matter config and a Liquid prompt template. Minimal example:

```yaml
---
tracker:
  kind: linear
  project_slug: "your-project-slug"
  active_states:
    - Todo
    - In Progress
    - AI Review
    - Merging
    - Rework
  terminal_states:
    - Completed
    - Canceled
    - Duplicate
polling:
  interval_ms: 10000
workspace:
  root: /tmp/my-workspaces
  source_repo: ~/dev/my-repo
agent:
  max_concurrent_agents: 5
  max_turns: 20
codex:
  command: codex app-server
  approval_policy: never
  thread_sandbox: workspace-write
  max_tokens_per_agent: 500000
---

You are working on Linear ticket `{{ issue.identifier }}`

Identifier: {{ issue.identifier }}
Title: {{ issue.title }}
Status: {{ issue.state }}

{% if issue.description %}
{{ issue.description }}
{% endif %}
```

### Tracker Authentication

Set the API key for your tracker:

```bash
# Linear
export LINEAR_API_KEY=lin_api_your_key_here

# Jira
export JIRA_API_TOKEN=your_jira_token
export JIRA_EMAIL=you@company.com
export JIRA_BASE_URL=https://yourcompany.atlassian.net

# GitHub Issues
export GITHUB_TOKEN=ghp_your_token_here
```

### Other Tracker Examples

<details>
<summary>Jira configuration</summary>

```yaml
tracker:
  kind: jira
  base_url: "https://yourcompany.atlassian.net"
  project_key: "PROJ"
  active_states:
    - To Do
    - In Progress
  terminal_states:
    - Done
    - Cancelled
```
</details>

<details>
<summary>GitHub Issues configuration</summary>

```yaml
tracker:
  kind: github
  repo: "owner/repo"
  active_states:
    - todo
    - in-progress
  terminal_states:
    - done
    - closed
```

Note: GitHub Issues uses labels to simulate workflow states.
</details>

## Run

```bash
# Foreground (TUI in terminal)
odyssey/bin/odyssey-start --workflow WORKFLOW.md

# Background daemon
odyssey/bin/odyssey-start --workflow WORKFLOW.md -d

# Check status
odyssey/bin/odyssey-status

# Stop
odyssey/bin/odyssey-stop
```

## Options

| Flag | Default | Description |
|------|---------|-------------|
| `--workflow <path>` | `REPO_ROOT/WORKFLOW.md` | Path to WORKFLOW.md |
| `--port <N>` | `4000` | Dashboard port |
| `-d` / `--background` | foreground | Run as daemon |
| `--logs-root <path>` | `REPO_ROOT/log` | Log directory |

Environment variables `ODYSSEY_PORT` and `ODYSSEY_WORKFLOW` override the defaults.

## Dashboard

When running with a port, open `http://localhost:4000`:

- `/` — Live operations dashboard
- `/tmux` — Split-pane view of all agent streams
- `/issues/:id` — Single agent chat view
- `/api/v1/state` — JSON API

## Optional Features

Add these sections to your `WORKFLOW.md` front matter to enable additional capabilities.

### Persistent State (crash recovery)

```yaml
persistence:
  mode: sqlite
```

### Prometheus Metrics & Slack Notifications

```yaml
observability:
  prometheus_enabled: true
notifications:
  slack_webhook_url: "https://hooks.slack.com/services/..."
```

### Approval Gates

```yaml
approval_gates:
  before_dispatch: true
  before_merge: true
  timeout_ms: 600000
  timeout_action: approve
```

### Token Budgets

```yaml
budget:
  daily_token_limit: 5000000
  cost_per_1k_input_tokens: 0.003
  cost_per_1k_output_tokens: 0.015
codex:
  max_tokens_per_agent: 500000
  budget_warning_pct: 80
```

See [CONFIGURATION.md](CONFIGURATION.md) for the full config reference.

## Update

```bash
cd odyssey && git pull origin main && cd elixir && mix deps.get && mix build
```
