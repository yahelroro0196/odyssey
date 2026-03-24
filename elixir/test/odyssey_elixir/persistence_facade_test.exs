defmodule OdysseyElixir.PersistenceFacadeTest do
  use OdysseyElixir.TestSupport

  alias OdysseyElixir.Persistence

  describe "routing based on config mode" do
    test "defaults to memory backend" do
      assert :ok = Persistence.record_session_start(%{id: "s1", issue_id: "i1"})
      assert %{} = Persistence.load_retry_queue()
    end

    test "memory backend returns zero totals" do
      result = Persistence.issue_token_total("i1")
      assert result == %{input_tokens: 0, output_tokens: 0, total_tokens: 0, session_count: 0}
    end

    test "sqlite?/0 returns false for memory mode" do
      refute Persistence.sqlite?()
    end

    test "all facade functions delegate without error" do
      assert :ok = Persistence.record_session_end("s1", %{status: "completed"})
      assert :ok = Persistence.record_token_delta("i1", "s1", %{input: 10})
      assert :ok = Persistence.save_retry_queue(%{})
      assert :ok = Persistence.clear_retry_queue()
      assert %{} = Persistence.daily_token_total(Date.utc_today())
      assert %{} = Persistence.weekly_token_total()
      assert %{} = Persistence.global_totals()
      assert :ok = Persistence.persist_event("i1", %{type: :test})
    end
  end
end
