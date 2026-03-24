# REST API Reference

The Odyssey API is available when the server is started with `server.port` configured or `--port`
flag. Base URL: `http://<host>:<port>`.

## Dashboard Routes

| Route | Description |
|-------|-------------|
| `GET /` | LiveView operations dashboard |
| `GET /tmux` | Split-pane view of all agent streams |
| `GET /issues/:issue_identifier` | Single agent chat/event stream |
| `GET /metrics` | Prometheus metrics (requires `observability.prometheus_enabled: true`) |

## API Endpoints

All API endpoints are under `/api/v1`.

### GET /api/v1/state

Returns the full system state snapshot.

**Response** `200 OK`:

```json
{
  "generated_at": "2025-01-15T10:30:00Z",
  "counts": { "running": 3, "retrying": 1 },
  "running": [
    {
      "issue_id": "...",
      "issue_identifier": "MT-42",
      "state": "In Progress",
      "role": "coder",
      "session_id": "thread-abc",
      "turn_count": 5,
      "tokens": { "input_tokens": 1200, "output_tokens": 800, "total_tokens": 2000 },
      "budget": { "max_tokens": 500000, "remaining": 498000, "pct_used": 0, "warning": false },
      "started_at": "2025-01-15T10:25:00Z",
      "last_event": "notification",
      "last_message": "...",
      "last_event_at": "2025-01-15T10:29:55Z",
      "pr_url": null,
      "worker_host": null,
      "workspace_path": "/tmp/workspaces/MT-42"
    }
  ],
  "retrying": [
    {
      "issue_id": "...",
      "issue_identifier": "MT-43",
      "attempt": 2,
      "due_at": "2025-01-15T10:31:00Z",
      "error": "agent exit: timeout",
      "worker_host": null,
      "workspace_path": "/tmp/workspaces/MT-43"
    }
  ],
  "agent_totals": {
    "input_tokens": 50000,
    "output_tokens": 30000,
    "total_tokens": 80000,
    "seconds_running": 3600.5
  },
  "rate_limits": {},
  "cost": { "estimated": 0.42, "currency": "USD" },
  "budget_status": { "daily_used": 80000, "daily_limit": 5000000, "paused": false },
  "pending_approvals": [],
  "config": {
    "last_reloaded_at": "2025-01-15T10:00:00Z",
    "last_changed_sections": ["agent", "codex"],
    "reload_count": 3
  }
}
```

### GET /api/v1/:issue_identifier

Returns details for a specific issue by identifier (e.g. `MT-42`, `PROJ-123`, `#7`).

**Response** `200 OK`:

```json
{
  "issue_identifier": "MT-42",
  "issue_id": "...",
  "status": "running",
  "workspace": { "path": "/tmp/workspaces/MT-42", "host": null },
  "attempts": { "restart_count": 0, "current_retry_attempt": 0 },
  "running": { "session_id": "thread-abc", "turn_count": 5, "..." : "..." },
  "events": []
}
```

**Response** `404 Not Found`:

```json
{ "error": { "code": "issue_not_found", "message": "Issue not found" } }
```

### POST /api/v1/refresh

Triggers an immediate poll cycle.

**Response** `202 Accepted`:

```json
{ "queued": true, "requested_at": "2025-01-15T10:30:00Z" }
```

### POST /api/v1/reload

Hot-reloads Elixir application code (development use).

**Response** `200 OK`:

```json
{ "status": "reloaded", "modules_reloaded": 5 }
```

### POST /api/v1/:issue_identifier/cancel

Cancels a running agent session for the given issue.

**Response** `200 OK`:

```json
{ "status": "cancelled" }
```

### GET /api/v1/approvals

Lists all pending approval requests.

**Response** `200 OK`:

```json
{
  "approvals": [
    {
      "id": 1,
      "gate": "before_dispatch",
      "issue_id": "...",
      "issue_identifier": "MT-42",
      "issue_title": "Fix login bug",
      "requested_at": "2025-01-15T10:30:00Z",
      "timeout_ms": 600000,
      "timeout_action": "approve"
    }
  ]
}
```

### POST /api/v1/approvals/:approval_id/approve

Approves a pending gate request.

**Response** `200 OK`:

```json
{ "status": "approved", "approval_id": "1" }
```

**Response** `404 Not Found`:

```json
{ "error": { "code": "approval_not_found", "message": "Approval not found" } }
```

### POST /api/v1/approvals/:approval_id/reject

Rejects a pending gate request.

**Response** `200 OK`:

```json
{ "status": "rejected", "approval_id": "1" }
```

### GET /metrics

Returns Prometheus-format metrics. Requires `observability.prometheus_enabled: true` in WORKFLOW.md.

**Response** `200 OK` (`text/plain`):

```
# TYPE odyssey_issues_dispatched_total counter
odyssey_issues_dispatched_total{state="Todo",role="coder"} 42
# TYPE odyssey_issues_completed_total counter
odyssey_issues_completed_total{state="In Progress"} 38
# TYPE odyssey_tokens_total counter
odyssey_tokens_total{type="input"} 500000
odyssey_tokens_total{type="output"} 300000
# TYPE odyssey_concurrent_agents_count gauge
odyssey_concurrent_agents_count 3
# TYPE odyssey_retry_queue_size gauge
odyssey_retry_queue_size 1
# TYPE odyssey_agent_duration_seconds histogram
odyssey_agent_duration_seconds_bucket{le="60"} 10
...
```

**Response** `404 Not Found` (when disabled):

```json
{ "error": { "code": "metrics_disabled", "message": "Prometheus metrics not enabled" } }
```

## Error Format

All error responses use a consistent format:

```json
{
  "error": {
    "code": "error_code",
    "message": "Human-readable error description"
  }
}
```

| Code | HTTP Status | Description |
|------|-------------|-------------|
| `issue_not_found` | 404 | Issue identifier not found in running or retrying state |
| `approval_not_found` | 404 | Approval ID not found in pending approvals |
| `metrics_disabled` | 404 | Prometheus metrics not enabled in config |
| `snapshot_timeout` | 500 | Orchestrator did not respond in time |
| `snapshot_unavailable` | 503 | Orchestrator not available |
| `method_not_allowed` | 405 | HTTP method not supported for this endpoint |
