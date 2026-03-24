defmodule OdysseyElixir.Tracker.MemoryTest do
  use ExUnit.Case

  alias OdysseyElixir.Tracker.{Memory, Issue}

  setup do
    Application.put_env(:odyssey_elixir, :memory_tracker_issues, [
      %Issue{id: "1", identifier: "TEST-1", title: "First", state: "Todo"},
      %Issue{id: "2", identifier: "TEST-2", title: "Second", state: "In Progress"},
      %Issue{id: "3", identifier: "TEST-3", title: "Third", state: "todo"}
    ])

    Application.put_env(:odyssey_elixir, :memory_tracker_recipient, self())

    on_exit(fn ->
      Application.delete_env(:odyssey_elixir, :memory_tracker_issues)
      Application.delete_env(:odyssey_elixir, :memory_tracker_recipient)
    end)

    :ok
  end

  describe "fetch_candidate_issues/0" do
    test "returns configured issues" do
      {:ok, issues} = Memory.fetch_candidate_issues()
      assert length(issues) == 3
      assert Enum.all?(issues, &match?(%Issue{}, &1))
    end

    test "returns empty list when none configured" do
      Application.put_env(:odyssey_elixir, :memory_tracker_issues, [])
      {:ok, issues} = Memory.fetch_candidate_issues()
      assert issues == []
    end
  end

  describe "fetch_issues_by_states/1" do
    test "filters by matching state (case insensitive)" do
      {:ok, issues} = Memory.fetch_issues_by_states(["Todo"])
      ids = Enum.map(issues, & &1.id)
      assert "1" in ids
      assert "3" in ids
      refute "2" in ids
    end

    test "returns empty list for non-matching state" do
      {:ok, issues} = Memory.fetch_issues_by_states(["Done"])
      assert issues == []
    end
  end

  describe "fetch_issue_states_by_ids/1" do
    test "filters by matching ids" do
      {:ok, issues} = Memory.fetch_issue_states_by_ids(["1", "3"])
      ids = Enum.map(issues, & &1.id)
      assert ids == ["1", "3"]
    end

    test "returns empty list for unknown ids" do
      {:ok, issues} = Memory.fetch_issue_states_by_ids(["999"])
      assert issues == []
    end
  end

  describe "create_comment/2" do
    test "sends message to recipient pid" do
      assert :ok = Memory.create_comment("1", "hello")
      assert_receive {:memory_tracker_comment, "1", "hello"}
    end
  end

  describe "update_issue_state/2" do
    test "sends message to recipient pid" do
      assert :ok = Memory.update_issue_state("1", "Done")
      assert_receive {:memory_tracker_state_update, "1", "Done"}
    end
  end
end
