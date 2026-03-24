defmodule OdysseyElixir.Telemetry do
  @moduledoc false

  import Telemetry.Metrics

  def metrics do
    [
      counter("odyssey.issues.dispatched.total", tags: [:state, :role]),
      counter("odyssey.issues.completed.total", tags: [:state]),
      counter("odyssey.issues.failed.total"),
      counter("odyssey.agent.turns.total", tags: [:role]),
      sum("odyssey.tokens.total", tags: [:type]),
      last_value("odyssey.retry_queue.size"),
      last_value("odyssey.concurrent_agents.count"),
      distribution("odyssey.agent.duration.seconds",
        reporter_options: [buckets: [30, 60, 120, 300, 600, 1800, 3600]]
      )
    ]
  end
end
