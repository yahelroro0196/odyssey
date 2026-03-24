defmodule OdysseyElixir.Persistence.SchemasTest do
  use ExUnit.Case, async: true

  alias OdysseyElixir.Persistence.Schemas.{Session, Event, RetrySnapshot, IssueTokenTotal, DailyTokenTotal}

  describe "Session changeset" do
    test "valid with all required fields" do
      cs = Session.changeset(%Session{}, %{id: "s1", issue_id: "i1", status: "running"})
      assert cs.valid?
    end

    test "invalid without id" do
      cs = Session.changeset(%Session{}, %{issue_id: "i1"})
      refute cs.valid?
      assert {:id, _} = List.keyfind(cs.errors, :id, 0)
    end

    test "invalid without issue_id" do
      cs = Session.changeset(%Session{}, %{id: "s1"})
      refute cs.valid?
      assert {:issue_id, _} = List.keyfind(cs.errors, :issue_id, 0)
    end

    test "defaults status to running" do
      cs = Session.changeset(%Session{}, %{id: "s1", issue_id: "i1"})
      assert cs.valid?
      assert Ecto.Changeset.get_field(cs, :status) == "running"
    end

    test "defaults token counts to zero" do
      cs = Session.changeset(%Session{}, %{id: "s1", issue_id: "i1"})
      assert Ecto.Changeset.get_field(cs, :input_tokens) == 0
      assert Ecto.Changeset.get_field(cs, :output_tokens) == 0
      assert Ecto.Changeset.get_field(cs, :total_tokens) == 0
      assert Ecto.Changeset.get_field(cs, :turn_count) == 0
    end
  end

  describe "Event changeset" do
    test "valid with all required fields" do
      now = DateTime.utc_now()
      cs = Event.changeset(%Event{}, %{issue_id: "i1", event_type: "completed", inserted_at: now})
      assert cs.valid?
    end

    test "invalid without issue_id" do
      cs = Event.changeset(%Event{}, %{event_type: "completed", inserted_at: DateTime.utc_now()})
      refute cs.valid?
      assert {:issue_id, _} = List.keyfind(cs.errors, :issue_id, 0)
    end

    test "invalid without inserted_at" do
      cs = Event.changeset(%Event{}, %{issue_id: "i1", event_type: "completed"})
      refute cs.valid?
      assert {:inserted_at, _} = List.keyfind(cs.errors, :inserted_at, 0)
    end
  end

  describe "RetrySnapshot changeset" do
    test "valid with required fields" do
      cs = RetrySnapshot.changeset(%RetrySnapshot{}, %{issue_id: "i1", attempt: 2})
      assert cs.valid?
    end

    test "invalid without issue_id" do
      cs = RetrySnapshot.changeset(%RetrySnapshot{}, %{attempt: 1})
      refute cs.valid?
      assert {:issue_id, _} = List.keyfind(cs.errors, :issue_id, 0)
    end

    test "defaults attempt to zero" do
      cs = RetrySnapshot.changeset(%RetrySnapshot{}, %{issue_id: "i1"})
      assert cs.valid?
      assert Ecto.Changeset.get_field(cs, :attempt) == 0
    end
  end

  describe "IssueTokenTotal changeset" do
    test "valid with required fields" do
      cs = IssueTokenTotal.changeset(%IssueTokenTotal{}, %{issue_id: "i1", total_tokens: 100})
      assert cs.valid?
    end

    test "invalid without issue_id" do
      cs = IssueTokenTotal.changeset(%IssueTokenTotal{}, %{total_tokens: 100})
      refute cs.valid?
      assert {:issue_id, _} = List.keyfind(cs.errors, :issue_id, 0)
    end

    test "defaults all counters to zero" do
      cs = IssueTokenTotal.changeset(%IssueTokenTotal{}, %{issue_id: "i1"})
      assert cs.valid?
      assert Ecto.Changeset.get_field(cs, :input_tokens) == 0
      assert Ecto.Changeset.get_field(cs, :output_tokens) == 0
      assert Ecto.Changeset.get_field(cs, :total_tokens) == 0
      assert Ecto.Changeset.get_field(cs, :session_count) == 0
    end
  end

  describe "DailyTokenTotal changeset" do
    test "valid with required fields" do
      cs = DailyTokenTotal.changeset(%DailyTokenTotal{}, %{date: ~D[2026-03-24]})
      assert cs.valid?
    end

    test "invalid without date" do
      cs = DailyTokenTotal.changeset(%DailyTokenTotal{}, %{total_tokens: 50})
      refute cs.valid?
      assert {:date, _} = List.keyfind(cs.errors, :date, 0)
    end

    test "defaults all counters to zero" do
      cs = DailyTokenTotal.changeset(%DailyTokenTotal{}, %{date: ~D[2026-03-24]})
      assert cs.valid?
      assert Ecto.Changeset.get_field(cs, :input_tokens) == 0
      assert Ecto.Changeset.get_field(cs, :output_tokens) == 0
      assert Ecto.Changeset.get_field(cs, :total_tokens) == 0
      assert Ecto.Changeset.get_field(cs, :session_count) == 0
    end
  end
end
