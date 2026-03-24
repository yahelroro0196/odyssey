defmodule OdysseyElixir.ObservabilityApiIntegrationTest do
  use OdysseyElixir.TestSupport

  import Phoenix.ConnTest

  @endpoint OdysseyElixirWeb.Endpoint
  @tag :integration

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

    def handle_call({:cancel_issue, identifier}, _from, state) do
      cancelable = Keyword.get(state, :cancelable, [])

      if identifier in cancelable do
        {:reply, :ok, state}
      else
        {:reply, {:error, :not_found}, state}
      end
    end
  end

  defp static_snapshot do
    %{
      running: [
        %{
          issue_id: "issue-api",
          identifier: "API-1",
          state: "In Progress",
          session_id: "thread-api",
          turn_count: 3,
          last_agent_event: :notification,
          last_agent_message: "processing",
          last_agent_timestamp: nil,
          agent_input_tokens: 10,
          agent_output_tokens: 20,
          agent_total_tokens: 30,
          started_at: DateTime.utc_now()
        }
      ],
      retrying: [
        %{
          issue_id: "issue-retry",
          identifier: "API-RETRY",
          attempt: 2,
          due_in_ms: 3_000,
          error: "crash"
        }
      ],
      agent_totals: %{input_tokens: 10, output_tokens: 20, total_tokens: 30, seconds_running: 5.0},
      rate_limits: %{"primary" => %{"remaining" => 8}}
    }
  end

  defp start_test_endpoint(overrides) do
    endpoint_config =
      :odyssey_elixir
      |> Application.get_env(OdysseyElixirWeb.Endpoint, [])
      |> Keyword.merge(server: false, secret_key_base: String.duplicate("s", 64))
      |> Keyword.merge(overrides)

    Application.put_env(:odyssey_elixir, OdysseyElixirWeb.Endpoint, endpoint_config)
    start_supervised!({OdysseyElixirWeb.Endpoint, []})
  end

  setup do
    endpoint_config = Application.get_env(:odyssey_elixir, OdysseyElixirWeb.Endpoint, [])

    on_exit(fn ->
      Application.put_env(:odyssey_elixir, OdysseyElixirWeb.Endpoint, endpoint_config)
    end)

    orchestrator_name = Module.concat(__MODULE__, :"Orch#{System.unique_integer([:positive])}")

    start_supervised!(
      {StaticOrchestrator,
       name: orchestrator_name,
       snapshot: static_snapshot(),
       refresh: %{
         queued: true,
         coalesced: false,
         requested_at: DateTime.utc_now(),
         operations: ["poll", "reconcile"]
       },
       cancelable: ["API-1"]}
    )

    start_test_endpoint(orchestrator: orchestrator_name, snapshot_timeout_ms: 50)

    unless Process.whereis(OdysseyElixir.ApprovalStore) do
      start_supervised!(OdysseyElixir.ApprovalStore)
    end

    %{orchestrator: orchestrator_name}
  end

  test "GET /api/v1/state returns 200 with expected structure" do
    conn = get(build_conn(), "/api/v1/state")
    body = json_response(conn, 200)

    assert body["generated_at"]
    assert body["counts"] == %{"running" => 1, "retrying" => 1}
    assert length(body["running"]) == 1
    assert length(body["retrying"]) == 1
    assert body["agent_totals"]["total_tokens"] == 30
  end

  test "GET /api/v1/:issue_identifier returns issue details for running issue" do
    conn = get(build_conn(), "/api/v1/API-1")
    body = json_response(conn, 200)

    assert body["issue_identifier"] == "API-1"
    assert body["issue_id"] == "issue-api"
    assert body["status"] == "running"
  end

  test "GET /api/v1/:issue_identifier returns 404 for unknown issue" do
    conn = get(build_conn(), "/api/v1/MISSING-999")
    body = json_response(conn, 404)

    assert body["error"]["code"] == "issue_not_found"
  end

  test "POST /api/v1/refresh returns 202" do
    conn = post(build_conn(), "/api/v1/refresh", %{})
    body = json_response(conn, 202)

    assert body["queued"] == true
    assert body["coalesced"] == false
    assert body["operations"] == ["poll", "reconcile"]
  end

  test "POST /api/v1/:issue_identifier/cancel returns cancelled status" do
    conn = post(build_conn(), "/api/v1/API-1/cancel", %{})
    body = json_response(conn, 200)

    assert body["status"] == "cancelled"
    assert body["issue_identifier"] == "API-1"
  end

  test "GET /api/v1/approvals returns empty list initially" do
    conn = get(build_conn(), "/api/v1/approvals")
    body = json_response(conn, 200)

    assert body["approvals"] == []
  end

  test "POST /api/v1/approvals/:id/approve with invalid id returns 404" do
    conn = post(build_conn(), "/api/v1/approvals/999/approve", %{})
    body = json_response(conn, 404)

    assert body["error"]["code"] == "not_found"
  end

  test "POST /api/v1/approvals/:id/reject with invalid id returns 404" do
    conn = post(build_conn(), "/api/v1/approvals/999/reject", %{})
    body = json_response(conn, 404)

    assert body["error"]["code"] == "not_found"
  end

  test "GET /metrics returns 404 when prometheus not enabled" do
    conn = get(build_conn(), "/metrics")
    body = json_response(conn, 404)

    assert body["error"]["code"] == "not_found"
    assert body["error"]["message"] == "Prometheus metrics not enabled"
  end
end
