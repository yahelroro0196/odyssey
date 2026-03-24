defmodule OdysseyElixir.MetricsReporter do
  @moduledoc false

  def child_spec(_opts) do
    TelemetryMetricsPrometheus.Core.child_spec(
      metrics: OdysseyElixir.Telemetry.metrics(),
      name: :odyssey_prometheus,
      start_async: false
    )
  end

  def scrape do
    TelemetryMetricsPrometheus.Core.scrape(:odyssey_prometheus)
  end
end
