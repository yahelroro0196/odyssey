defmodule OdysseyElixir.Persistence.MemoryTest do
  use ExUnit.Case, async: true

  alias OdysseyElixir.Persistence.Memory

  describe "record_session_start/1" do
    test "returns :ok" do
      assert :ok = Memory.record_session_start(%{id: "s1", issue_id: "i1"})
    end
  end

  describe "record_session_end/2" do
    test "returns :ok" do
      assert :ok = Memory.record_session_end("s1", %{status: "completed"})
    end
  end

  describe "record_token_delta/3" do
    test "returns :ok" do
      assert :ok = Memory.record_token_delta("i1", "s1", %{input: 10, output: 20})
    end
  end

  describe "save_retry_queue/1" do
    test "returns :ok" do
      assert :ok = Memory.save_retry_queue(%{"i1" => %{attempt: 1}})
    end
  end

  describe "load_retry_queue/0" do
    test "returns empty map" do
      assert %{} = Memory.load_retry_queue()
    end
  end

  describe "clear_retry_queue/0" do
    test "returns :ok" do
      assert :ok = Memory.clear_retry_queue()
    end
  end

  describe "issue_token_total/1" do
    test "returns zero totals" do
      result = Memory.issue_token_total("i1")
      assert result == %{input_tokens: 0, output_tokens: 0, total_tokens: 0, session_count: 0}
    end
  end

  describe "daily_token_total/1" do
    test "returns zero totals" do
      result = Memory.daily_token_total(Date.utc_today())
      assert result == %{input_tokens: 0, output_tokens: 0, total_tokens: 0, session_count: 0}
    end
  end

  describe "weekly_token_total/0" do
    test "returns zero totals" do
      result = Memory.weekly_token_total()
      assert result == %{input_tokens: 0, output_tokens: 0, total_tokens: 0, session_count: 0}
    end
  end

  describe "global_totals/0" do
    test "returns zero totals" do
      result = Memory.global_totals()
      assert result == %{input_tokens: 0, output_tokens: 0, total_tokens: 0, session_count: 0}
    end
  end

  describe "persist_event/2" do
    test "returns :ok" do
      assert :ok = Memory.persist_event("i1", %{type: :completed})
    end
  end
end
