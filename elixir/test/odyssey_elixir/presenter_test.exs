defmodule OdysseyElixir.PresenterTest do
  use OdysseyElixir.TestSupport

  @tag :integration

  alias OdysseyElixirWeb.Presenter

  defmodule StaticOrchestrator do
    use GenServer

    def start_link(opts) do
      name = Keyword.fetch!(opts, :name)
      GenServer.start_link(__MODULE__, opts, name: name)
    end

    def init(opts), do: {:ok, opts}

    def handle_call(:snapshot, _from, state) do
      {:reply, Keyword.fetch!(state, :snapshot), state}
    end

    def handle_call(:request_refresh, _from, state) do
      {:reply, Keyword.get(state, :refresh, :unavailable), state}
    end
  end

  defp make_running_entry(overrides \\ %{}) do
    Map.merge(
      %{
        issue_id: "issue-1",
        identifier: "PRES-1",
        state: "In Progress",
        session_id: "session-1",
        turn_count: 5,
        last_agent_event: :notification,
        last_agent_message: "working on it",
        last_agent_timestamp: nil,
        agent_input_tokens: 100,
        agent_output_tokens: 200,
        agent_total_tokens: 300,
        started_at: DateTime.utc_now()
      },
      overrides
    )
  end

  defp make_retry_entry(overrides \\ %{}) do
    Map.merge(
      %{
        issue_id: "issue-2",
        identifier: "PRES-2",
        attempt: 3,
        due_in_ms: 5_000,
        error: "timeout"
      },
      overrides
    )
  end

  defp make_snapshot(overrides \\ %{}) do
    Map.merge(
      %{
        running: [make_running_entry()],
        retrying: [make_retry_entry()],
        agent_totals: %{input_tokens: 100, output_tokens: 200, total_tokens: 300, seconds_running: 10.0},
        rate_limits: %{"primary" => %{"remaining" => 5}}
      },
      overrides
    )
  end

  defp start_orchestrator(snapshot, opts \\ []) do
    name = Module.concat(__MODULE__, :"Orch#{System.unique_integer([:positive])}")

    start_supervised!(
      {StaticOrchestrator,
       [name: name, snapshot: snapshot] ++ opts}
    )

    name
  end

  test "state_payload with valid snapshot returns full structured response" do
    snapshot =
      make_snapshot(%{
        budget_status: %{paused: false},
        pending_approvals: [%{id: 1, gate: :before_dispatch}]
      })

    orch = start_orchestrator(snapshot)
    payload = Presenter.state_payload(orch, 5_000)

    assert payload.generated_at
    assert payload.counts == %{running: 1, retrying: 1}
    assert length(payload.running) == 1
    assert length(payload.retrying) == 1
    assert payload.agent_totals == snapshot.agent_totals
    assert payload.rate_limits == snapshot.rate_limits
    assert payload.budget_status == %{paused: false}
    assert payload.pending_approvals == [%{id: 1, gate: :before_dispatch}]
  end

  test "state_payload with :timeout snapshot returns timeout error" do
    orch = start_orchestrator(:timeout)
    payload = Presenter.state_payload(orch, 5_000)

    assert payload.error == %{code: "snapshot_timeout", message: "Snapshot timed out"}
    assert payload.generated_at
    refute Map.has_key?(payload, :counts)
  end

  test "state_payload with :unavailable snapshot returns unavailable error" do
    orch = start_orchestrator(:unavailable)
    payload = Presenter.state_payload(orch, 5_000)

    assert payload.error == %{code: "snapshot_unavailable", message: "Snapshot unavailable"}
    assert payload.generated_at
    refute Map.has_key?(payload, :counts)
  end

  test "issue_payload finds running issue by identifier" do
    orch = start_orchestrator(make_snapshot())
    assert {:ok, payload} = Presenter.issue_payload("PRES-1", orch, 5_000)
    assert payload.issue_identifier == "PRES-1"
    assert payload.issue_id == "issue-1"
    assert payload.status == "running"
    assert payload.running != nil
    assert payload.retry == nil
  end

  test "issue_payload finds retrying issue by identifier" do
    orch = start_orchestrator(make_snapshot())
    assert {:ok, payload} = Presenter.issue_payload("PRES-2", orch, 5_000)
    assert payload.issue_identifier == "PRES-2"
    assert payload.status == "retrying"
    assert payload.retry != nil
    assert payload.retry.attempt == 3
  end

  test "issue_payload returns error for unknown identifier" do
    orch = start_orchestrator(make_snapshot())
    assert {:error, :issue_not_found} = Presenter.issue_payload("PRES-MISSING", orch, 5_000)
  end

  test "cost computation with nil rates returns nil estimated" do
    write_workflow_file!(Workflow.workflow_file_path())
    snapshot = make_snapshot()
    orch = start_orchestrator(snapshot)
    payload = Presenter.state_payload(orch, 5_000)

    assert payload.cost.estimated == nil
    assert payload.cost.currency == "USD"
  end

  test "cost struct always includes currency field" do
    snapshot = make_snapshot()
    orch = start_orchestrator(snapshot)
    payload = Presenter.state_payload(orch, 5_000)

    assert Map.has_key?(payload.cost, :currency)
    assert Map.has_key?(payload.cost, :estimated)
  end

  test "budget fields present in running entry payload" do
    orch = start_orchestrator(make_snapshot())
    payload = Presenter.state_payload(orch, 5_000)

    [entry] = payload.running
    assert Map.has_key?(entry, :budget)
    assert Map.has_key?(entry.budget, :max_tokens)
    assert Map.has_key?(entry.budget, :remaining)
    assert Map.has_key?(entry.budget, :pct_used)
    assert Map.has_key?(entry.budget, :warning)
  end

  test "pending approvals passed through in state payload" do
    approvals = [
      %{id: 1, gate: :before_dispatch},
      %{id: 2, gate: :before_merge}
    ]

    snapshot = make_snapshot(%{pending_approvals: approvals})
    orch = start_orchestrator(snapshot)
    payload = Presenter.state_payload(orch, 5_000)

    assert payload.pending_approvals == approvals
  end

  test "state_payload defaults budget_status and pending_approvals when absent" do
    snapshot = make_snapshot() |> Map.drop([:budget_status, :pending_approvals])
    orch = start_orchestrator(snapshot)
    payload = Presenter.state_payload(orch, 5_000)

    assert payload.budget_status == %{}
    assert payload.pending_approvals == []
  end

  test "running entry includes expected fields" do
    entry =
      make_running_entry(%{
        worker_host: "host-1",
        workspace_path: "/tmp/ws",
        pr_url: "https://github.com/org/repo/pull/1",
        role: :review
      })

    snapshot = make_snapshot(%{running: [entry]})
    orch = start_orchestrator(snapshot)
    payload = Presenter.state_payload(orch, 5_000)

    [running] = payload.running
    assert running.issue_id == "issue-1"
    assert running.issue_identifier == "PRES-1"
    assert running.worker_host == "host-1"
    assert running.workspace_path == "/tmp/ws"
    assert running.session_id == "session-1"
    assert running.turn_count == 5
    assert running.pr_url == "https://github.com/org/repo/pull/1"
    assert running.role == :review
    assert running.tokens == %{input_tokens: 100, output_tokens: 200, total_tokens: 300}
  end

  test "retry entry includes expected fields" do
    entry = make_retry_entry(%{worker_host: "host-2", workspace_path: "/tmp/retry"})
    snapshot = make_snapshot(%{retrying: [entry]})
    orch = start_orchestrator(snapshot)
    payload = Presenter.state_payload(orch, 5_000)

    [retrying] = payload.retrying
    assert retrying.issue_id == "issue-2"
    assert retrying.issue_identifier == "PRES-2"
    assert retrying.attempt == 3
    assert retrying.error == "timeout"
    assert retrying.worker_host == "host-2"
    assert retrying.workspace_path == "/tmp/retry"
    assert retrying.due_at
  end

  test "issue_payload for snapshot timeout returns not found" do
    orch = start_orchestrator(:timeout)
    assert {:error, :issue_not_found} = Presenter.issue_payload("PRES-1", orch, 5_000)
  end
end
