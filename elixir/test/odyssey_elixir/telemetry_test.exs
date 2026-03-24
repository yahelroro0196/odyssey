defmodule OdysseyElixir.TelemetryTest do
  use ExUnit.Case, async: true

  alias OdysseyElixir.Telemetry

  describe "metrics/0" do
    test "returns a non-empty list of metric definitions" do
      metrics = Telemetry.metrics()
      assert is_list(metrics)
      assert length(metrics) > 0
    end

    test "contains expected metric names" do
      metrics = Telemetry.metrics()
      names = Enum.map(metrics, & &1.name)

      assert [:odyssey, :issues, :dispatched, :total] in names
      assert [:odyssey, :issues, :completed, :total] in names
      assert [:odyssey, :issues, :failed, :total] in names
      assert [:odyssey, :tokens, :total] in names
      assert [:odyssey, :retry_queue, :size] in names
    end

    test "all metrics are Telemetry.Metrics structs" do
      metrics = Telemetry.metrics()

      for metric <- metrics do
        assert is_struct(metric)
        assert Map.has_key?(metric, :name)
        assert Map.has_key?(metric, :event_name)
      end
    end

    test "includes distribution metric for agent duration" do
      metrics = Telemetry.metrics()
      duration = Enum.find(metrics, &(&1.name == [:odyssey, :agent, :duration, :seconds]))
      assert duration != nil
    end
  end
end
