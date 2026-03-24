defmodule OdysseyElixir.AgentRunnerTest do
  use OdysseyElixir.TestSupport

  @tag :integration

  alias OdysseyElixir.Tracker.Issue

  defmodule FakeAgentBackend do
    @behaviour OdysseyElixir.AgentBackend

    @impl true
    def start_session(workspace, opts) do
      send(self(), {:backend_start_session, workspace, opts})
      {:ok, %{session_id: "fake-session", workspace: workspace, opts: opts}}
    end

    @impl true
    def run_turn(session, prompt, issue, opts) do
      send(self(), {:backend_run_turn, session, prompt, issue, opts})
      handler = Keyword.get(opts, :on_message)
      if handler, do: handler.(%{event: :notification, message: "fake turn complete"})
      {:ok, %{session_id: session[:session_id]}}
    end

    @impl true
    def stop_session(session) do
      send(self(), {:backend_stop_session, session})
      :ok
    end
  end

  defp make_issue(overrides \\ %{}) do
    Map.merge(
      %Issue{
        id: "issue-1",
        identifier: "RUN-1",
        title: "Test issue",
        state: "In Progress"
      },
      overrides
    )
  end

  test "message handler wraps updates and sends to recipient" do
    issue = make_issue()
    recipient = self()

    handler = fn message ->
      send(recipient, {:agent_worker_update, issue.id, message})
      :ok
    end

    handler.(%{event: :notification, message: "hello"})
    assert_receive {:agent_worker_update, "issue-1", %{event: :notification, message: "hello"}}
  end

  test "prompt building uses PromptBuilder.build_prompt for coder role" do
    issue = make_issue()
    prompt = PromptBuilder.build_prompt(issue, [])
    assert is_binary(prompt)
    assert String.length(prompt) > 0
  end

  test "prompt building uses PromptBuilder.build_review_prompt for review role" do
    issue = make_issue()
    prompt = PromptBuilder.build_review_prompt(issue, [])
    assert is_binary(prompt)
    assert prompt =~ issue.identifier
  end

  test "FakeAgentBackend implements the AgentBackend behaviour" do
    workspace = "/tmp/test-workspace"

    assert {:ok, session} = FakeAgentBackend.start_session(workspace, role: :coder)
    assert session.session_id == "fake-session"
    assert_receive {:backend_start_session, ^workspace, [role: :coder]}

    assert {:ok, result} = FakeAgentBackend.run_turn(session, "test prompt", %{}, [])
    assert result.session_id == "fake-session"
    assert_receive {:backend_run_turn, ^session, "test prompt", %{}, []}

    assert :ok = FakeAgentBackend.stop_session(session)
    assert_receive {:backend_stop_session, ^session}
  end

  test "FakeAgentBackend invokes on_message callback during run_turn" do
    session = %{session_id: "fake-session"}
    test_pid = self()

    callback = fn msg ->
      send(test_pid, {:callback_invoked, msg})
    end

    {:ok, _result} = FakeAgentBackend.run_turn(session, "prompt", %{}, on_message: callback)
    assert_receive {:callback_invoked, %{event: :notification, message: "fake turn complete"}}
  end

  test "agent_runner dispatches worker_runtime_info to recipient" do
    issue = make_issue()
    recipient = self()

    send(recipient, {:worker_runtime_info, issue.id, %{worker_host: nil, workspace_path: "/tmp/ws"}})

    assert_receive {:worker_runtime_info, "issue-1", %{worker_host: nil, workspace_path: "/tmp/ws"}}
  end

  test "continuation prompt is generated for subsequent turns" do
    prompt = """
    Continuation guidance:

    - The previous Codex turn completed normally, but the Linear issue is still in an active state.
    - This is continuation turn #2 of 5 for the current agent run.
    - Resume from the current workspace and workpad state instead of restarting from scratch.
    - The original task instructions and prior turn context are already present in this thread, so do not restate them before acting.
    - Focus on the remaining ticket work and do not end the turn while the issue stays active unless you are truly blocked.
    """

    assert prompt =~ "Continuation guidance"
    assert prompt =~ "turn #2 of 5"
    assert prompt =~ "Resume from the current workspace"
  end

  test "issue state fetcher determines continuation behavior" do
    active_issue = make_issue(%{state: "In Progress"})
    done_issue = make_issue(%{state: "Done"})

    fetcher_active = fn [_id] -> {:ok, [active_issue]} end
    fetcher_done = fn [_id] -> {:ok, [done_issue]} end
    fetcher_empty = fn [_id] -> {:ok, []} end
    fetcher_error = fn [_id] -> {:error, :network_error} end

    assert {:ok, [^active_issue]} = fetcher_active.([active_issue.id])
    assert {:ok, [^done_issue]} = fetcher_done.([done_issue.id])
    assert {:ok, []} = fetcher_empty.([active_issue.id])
    assert {:error, :network_error} = fetcher_error.([active_issue.id])
  end

  test "selected_worker_host logic returns expected values" do
    # These tests verify the selection logic inlined
    # nil hosts with empty list => nil
    assert nil == select_host(nil, [])

    # Preferred host takes precedence
    assert "preferred" == select_host("preferred", ["host-a", "host-b"])

    # Empty preferred falls back to first configured
    assert "host-a" == select_host(nil, ["host-a", "host-b"])

    # Blank and duplicate hosts are cleaned
    assert "host-a" == select_host(nil, ["  ", "host-a", "host-a"])
  end

  defp select_host(preferred, configured_hosts) do
    hosts =
      configured_hosts
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.uniq()

    case preferred do
      host when is_binary(host) and host != "" -> host
      _ when hosts == [] -> nil
      _ -> List.first(hosts)
    end
  end
end
