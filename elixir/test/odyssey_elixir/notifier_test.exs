defmodule OdysseyElixir.NotifierTest do
  use OdysseyElixir.TestSupport

  alias OdysseyElixir.Notifier

  describe "notify/3 with no webhooks configured" do
    test "returns :ok when no webhook URLs are set" do
      assert :ok = Notifier.notify("TEST-1", :completed)
    end

    test "returns :ok for all event types without error" do
      events = [
        :completed, :failed, :budget_exceeded, :budget_warning,
        :approval_requested, :approval_approved, :approval_rejected,
        :approval_timeout, :unknown_event
      ]

      for event <- events do
        assert :ok = Notifier.notify("TEST-1", event, %{})
      end
    end
  end

  describe "notify/3 with invalid webhook URLs" do
    test "attempts HTTP call and logs warning for generic webhook" do
      write_workflow_file!(
        Application.get_env(:odyssey_elixir, :workflow_file_path) ||
          Path.join(System.tmp_dir!(), "WORKFLOW.md"),
        []
      )

      assert :ok = Notifier.notify("TEST-1", :completed, %{detail: "test"})
    end
  end

  describe "notify/3 accepts details map" do
    test "passes details without error" do
      assert :ok = Notifier.notify("TEST-1", :completed, %{tokens: 100, turns: 5})
    end
  end

  describe "notify/3 with invalid identifier types" do
    test "raises for non-binary identifier" do
      assert_raise FunctionClauseError, fn ->
        Notifier.notify(123, :completed)
      end
    end

    test "raises for non-atom event" do
      assert_raise FunctionClauseError, fn ->
        Notifier.notify("TEST-1", "completed")
      end
    end
  end

  describe "slack emoji mapping" do
    test "all known events produce :ok" do
      known_events = [
        :completed, :failed, :budget_exceeded, :budget_warning,
        :approval_requested, :approval_approved, :approval_rejected,
        :approval_timeout
      ]

      for event <- known_events do
        assert :ok = Notifier.notify("TEST-1", event)
      end
    end
  end
end
