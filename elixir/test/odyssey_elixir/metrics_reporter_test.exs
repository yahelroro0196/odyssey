defmodule OdysseyElixir.MetricsReporterTest do
  use ExUnit.Case, async: true

  alias OdysseyElixir.MetricsReporter

  describe "child_spec/1" do
    test "returns a valid child spec map" do
      spec = MetricsReporter.child_spec([])
      assert is_map(spec)
      assert Map.has_key?(spec, :id)
      assert Map.has_key?(spec, :start)
    end
  end

  describe "scrape/0" do
    test "returns binary data from the running prometheus core" do
      result = MetricsReporter.scrape()
      assert is_binary(result)
    end
  end
end
