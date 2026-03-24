defmodule OdysseyElixir.Persistence.SQLiteTest do
  use ExUnit.Case, async: false

  alias OdysseyElixir.Persistence.SQLite
  alias OdysseyElixir.TestSupport.PersistenceHelper

  setup do
    {pid, db_path, original_config} = PersistenceHelper.setup_test_db()

    on_exit(fn ->
      try do
        PersistenceHelper.cleanup_test_db({pid, db_path, original_config})
      catch
        :exit, _ -> :ok
      end
    end)

    :ok
  end

  defp unique_session_id, do: "sess-#{System.unique_integer([:positive])}"
  defp unique_issue_id, do: "ISSUE-#{System.unique_integer([:positive])}"

  defp session_attrs(session_id, issue_id, opts \\ []) do
    %{
      id: session_id,
      issue_id: issue_id,
      started_at: DateTime.utc_now(),
      input_tokens: Keyword.get(opts, :input_tokens, 0),
      output_tokens: Keyword.get(opts, :output_tokens, 0),
      total_tokens: Keyword.get(opts, :total_tokens, 0)
    }
  end

  describe "record_session_start/1" do
    test "inserts a session row" do
      sid = unique_session_id()
      iid = unique_issue_id()

      assert :ok = SQLite.record_session_start(session_attrs(sid, iid))

      session = OdysseyElixir.Repo.get(OdysseyElixir.Persistence.Schemas.Session, sid)
      assert session.issue_id == iid
      assert session.status == "running"
    end
  end

  describe "record_session_end/2" do
    test "updates session with final tokens and status" do
      sid = unique_session_id()
      iid = unique_issue_id()
      SQLite.record_session_start(session_attrs(sid, iid))

      :ok = SQLite.record_session_end(sid, %{status: "completed", input_tokens: 100, output_tokens: 50, total_tokens: 150})

      session = OdysseyElixir.Repo.get(OdysseyElixir.Persistence.Schemas.Session, sid)
      assert session.status == "completed"
      assert session.input_tokens == 100
      assert session.total_tokens == 150
      assert session.finished_at != nil
    end

    test "upserts issue_token_totals from pre-update session values" do
      sid = unique_session_id()
      iid = unique_issue_id()
      # Start with tokens already set so upsert picks them up
      SQLite.record_session_start(session_attrs(sid, iid, input_tokens: 100, output_tokens: 50, total_tokens: 150))
      SQLite.record_session_end(sid, %{status: "completed", input_tokens: 100, output_tokens: 50, total_tokens: 150})

      totals = SQLite.issue_token_total(iid)
      assert totals.input_tokens == 100
      assert totals.output_tokens == 50
      assert totals.total_tokens == 150
      assert totals.session_count == 1
    end

    test "upserts daily_token_totals" do
      sid = unique_session_id()
      iid = unique_issue_id()
      SQLite.record_session_start(session_attrs(sid, iid, input_tokens: 200, output_tokens: 100, total_tokens: 300))
      SQLite.record_session_end(sid, %{status: "completed", input_tokens: 200, output_tokens: 100, total_tokens: 300})

      today = Date.utc_today()
      totals = SQLite.daily_token_total(today)
      assert totals.input_tokens >= 200
      assert totals.total_tokens >= 300
      assert totals.session_count >= 1
    end

    test "returns :ok for unknown session_id" do
      assert :ok = SQLite.record_session_end("nonexistent", %{status: "completed"})
    end
  end

  describe "record_token_delta/3" do
    test "updates running session tokens" do
      sid = unique_session_id()
      iid = unique_issue_id()
      SQLite.record_session_start(session_attrs(sid, iid))

      :ok = SQLite.record_token_delta(iid, sid, %{input_tokens: 10, output_tokens: 5, total_tokens: 15})

      session = OdysseyElixir.Repo.get(OdysseyElixir.Persistence.Schemas.Session, sid)
      assert session.input_tokens == 10
      assert session.output_tokens == 5
      assert session.total_tokens == 15
    end

    test "accumulates multiple deltas" do
      sid = unique_session_id()
      iid = unique_issue_id()
      SQLite.record_session_start(session_attrs(sid, iid))

      SQLite.record_token_delta(iid, sid, %{input_tokens: 10, output_tokens: 5, total_tokens: 15})
      SQLite.record_token_delta(iid, sid, %{input_tokens: 20, output_tokens: 10, total_tokens: 30})

      session = OdysseyElixir.Repo.get(OdysseyElixir.Persistence.Schemas.Session, sid)
      assert session.input_tokens == 30
      assert session.output_tokens == 15
      assert session.total_tokens == 45
    end
  end

  describe "retry queue" do
    test "save_retry_queue/1 persists entries" do
      queue = %{
        "ISSUE-1" => %{attempt: 2, error: "timeout", worker_host: "host1", workspace_path: "/tmp/ws1"},
        "ISSUE-2" => %{attempt: 1, error: nil, worker_host: "host2", workspace_path: "/tmp/ws2"}
      }

      assert :ok = SQLite.save_retry_queue(queue)
    end

    test "load_retry_queue/0 returns saved entries" do
      queue = %{
        "ISSUE-1" => %{attempt: 2, error: "timeout", worker_host: "host1", workspace_path: "/tmp/ws1"}
      }

      SQLite.save_retry_queue(queue)
      loaded = SQLite.load_retry_queue()

      assert Map.has_key?(loaded, "ISSUE-1")
      assert loaded["ISSUE-1"].attempt == 2
      assert loaded["ISSUE-1"].error == "timeout"
    end

    test "clear_retry_queue/0 removes all entries" do
      SQLite.save_retry_queue(%{"ISSUE-1" => %{attempt: 1, error: nil, worker_host: nil, workspace_path: nil}})
      assert :ok = SQLite.clear_retry_queue()
      assert %{} = SQLite.load_retry_queue()
    end

    test "save_retry_queue/1 replaces previous entries" do
      SQLite.save_retry_queue(%{"ISSUE-1" => %{attempt: 1, error: nil, worker_host: nil, workspace_path: nil}})
      SQLite.save_retry_queue(%{"ISSUE-2" => %{attempt: 3, error: "fail", worker_host: nil, workspace_path: nil}})

      loaded = SQLite.load_retry_queue()
      refute Map.has_key?(loaded, "ISSUE-1")
      assert Map.has_key?(loaded, "ISSUE-2")
    end
  end

  describe "issue_token_total/1" do
    test "returns zeroes for unknown issue" do
      totals = SQLite.issue_token_total("nonexistent-#{System.unique_integer([:positive])}")
      assert totals == %{input_tokens: 0, output_tokens: 0, total_tokens: 0, session_count: 0}
    end
  end

  describe "daily_token_total/1" do
    test "returns zeroes for date with no sessions" do
      totals = SQLite.daily_token_total(~D[2020-01-01])
      assert totals == %{input_tokens: 0, output_tokens: 0, total_tokens: 0, session_count: 0}
    end
  end

  describe "weekly_token_total/0" do
    test "sums last 7 days" do
      sid = unique_session_id()
      iid = unique_issue_id()
      SQLite.record_session_start(session_attrs(sid, iid, input_tokens: 50, output_tokens: 25, total_tokens: 75))
      SQLite.record_session_end(sid, %{status: "completed"})

      totals = SQLite.weekly_token_total()
      assert totals.input_tokens >= 50
      assert totals.total_tokens >= 75
    end
  end

  describe "global_totals/0" do
    test "returns all-time totals" do
      sid = unique_session_id()
      iid = unique_issue_id()
      SQLite.record_session_start(session_attrs(sid, iid, input_tokens: 100, output_tokens: 50, total_tokens: 150))

      totals = SQLite.global_totals()
      assert totals.session_count >= 1
      assert totals.input_tokens >= 100
    end
  end

  describe "persist_event/2" do
    test "inserts event" do
      iid = unique_issue_id()
      event = %{event: :session_started, data: "test"}

      assert :ok = SQLite.persist_event(iid, event)

      events = OdysseyElixir.Repo.all(OdysseyElixir.Persistence.Schemas.Event)
      assert Enum.any?(events, &(&1.issue_id == iid))
    end
  end

  describe "multiple sessions accumulate into totals" do
    test "issue totals accumulate across sessions" do
      iid = unique_issue_id()

      sid1 = unique_session_id()
      SQLite.record_session_start(session_attrs(sid1, iid, input_tokens: 100, output_tokens: 50, total_tokens: 150))
      SQLite.record_session_end(sid1, %{status: "completed"})

      sid2 = unique_session_id()
      SQLite.record_session_start(session_attrs(sid2, iid, input_tokens: 200, output_tokens: 100, total_tokens: 300))
      SQLite.record_session_end(sid2, %{status: "completed"})

      totals = SQLite.issue_token_total(iid)
      assert totals.input_tokens == 300
      assert totals.output_tokens == 150
      assert totals.total_tokens == 450
      assert totals.session_count == 2
    end
  end
end
