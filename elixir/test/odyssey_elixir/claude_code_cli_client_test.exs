defmodule OdysseyElixir.ClaudeCodeCliClientTest do
  use OdysseyElixir.TestSupport

  alias OdysseyElixir.ClaudeCode.CliClient
  alias OdysseyElixir.Codex.AppServer

  test "start_session returns session map with workspace and role" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "odyssey-claude-start-session-#{System.unique_integer([:positive])}"
      )

    try do
      workspace_root = Path.join(test_root, "workspaces")
      workspace = Path.join(workspace_root, "MT-100")
      File.mkdir_p!(workspace)

      write_workflow_file!(Workflow.workflow_file_path(),
        workspace_root: workspace_root,
        codex_command: "claude"
      )

      assert {:ok, session} = CliClient.start_session(workspace, role: :coder)
      assert String.ends_with?(session.workspace, "workspaces/MT-100")
      assert session.role == :coder
      assert is_nil(session.resume_session_id)
    after
      File.rm_rf(test_root)
    end
  end

  test "start_session rejects workspace outside root" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "odyssey-claude-workspace-guard-#{System.unique_integer([:positive])}"
      )

    try do
      workspace_root = Path.join(test_root, "workspaces")
      outside_workspace = Path.join(test_root, "outside")
      File.mkdir_p!(workspace_root)
      File.mkdir_p!(outside_workspace)

      write_workflow_file!(Workflow.workflow_file_path(),
        workspace_root: workspace_root,
        codex_command: "claude"
      )

      assert {:error, {:invalid_workspace_cwd, :outside_workspace_root, _, _}} =
               CliClient.start_session(outside_workspace)
    after
      File.rm_rf(test_root)
    end
  end

  test "run_turn parses stream-json and emits events" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "odyssey-claude-run-turn-#{System.unique_integer([:positive])}"
      )

    try do
      workspace_root = Path.join(test_root, "workspaces")
      workspace = Path.join(workspace_root, "MT-200")
      fake_claude = Path.join(test_root, "fake-claude")
      File.mkdir_p!(workspace)

      File.write!(fake_claude, """
      #!/bin/sh
      echo '{"type":"system","subtype":"init","session_id":"sess-abc"}'
      echo '{"type":"assistant","message":{"content":[{"type":"text","text":"Working on it"}]}}'
      echo '{"type":"tool_use","tool":"Bash","input":{"command":"echo hello"}}'
      echo '{"type":"tool_result","output":"hello"}'
      echo '{"type":"result","session_id":"sess-abc","usage":{"input_tokens":100,"output_tokens":50},"cost_usd":0.001}'
      """)

      File.chmod!(fake_claude, 0o755)

      write_workflow_file!(Workflow.workflow_file_path(),
        workspace_root: workspace_root,
        codex_command: fake_claude
      )

      issue = %Issue{
        id: "issue-claude-200",
        identifier: "MT-200",
        title: "Test Claude Code turn",
        description: "Verify stream-json parsing",
        state: "In Progress",
        url: "https://example.org/issues/MT-200",
        labels: []
      }

      test_pid = self()

      on_message = fn message ->
        send(test_pid, {:test_event, message.event})
      end

      session = %{
        workspace: workspace,
        worker_host: nil,
        role: :coder,
        resume_session_id: nil,
        config: Config.agent_codex_config(:coder)
      }

      assert {:ok, result} = CliClient.run_turn(session, "test prompt", issue, on_message: on_message)
      assert result.session_id == "sess-abc"
      assert result.usage["input_tokens"] == 100

      assert_received {:test_event, :session_started}
      assert_received {:test_event, :notification}
      assert_received {:test_event, :turn_completed}
    after
      File.rm_rf(test_root)
    end
  end

  test "run_turn handles port exit with non-zero status" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "odyssey-claude-error-#{System.unique_integer([:positive])}"
      )

    try do
      workspace_root = Path.join(test_root, "workspaces")
      workspace = Path.join(workspace_root, "MT-300")
      fake_claude = Path.join(test_root, "fake-claude-error")
      File.mkdir_p!(workspace)

      File.write!(fake_claude, """
      #!/bin/sh
      echo '{"type":"system","subtype":"init","session_id":"sess-err"}'
      exit 1
      """)

      File.chmod!(fake_claude, 0o755)

      write_workflow_file!(Workflow.workflow_file_path(),
        workspace_root: workspace_root,
        codex_command: fake_claude
      )

      issue = %Issue{
        id: "issue-claude-300",
        identifier: "MT-300",
        title: "Test error handling",
        description: "Verify port exit error",
        state: "In Progress",
        url: "https://example.org/issues/MT-300",
        labels: []
      }

      session = %{
        workspace: workspace,
        worker_host: nil,
        role: :coder,
        resume_session_id: nil,
        config: Config.agent_codex_config(:coder)
      }

      assert {:error, {:port_exit, 1}} = CliClient.run_turn(session, "test prompt", issue)
    after
      File.rm_rf(test_root)
    end
  end

  test "stop_session is a no-op" do
    assert :ok = CliClient.stop_session(%{workspace: "/tmp/test"})
  end

  test "validate_workspace_cwd is shared with AppServer" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "odyssey-claude-shared-validation-#{System.unique_integer([:positive])}"
      )

    try do
      workspace_root = Path.join(test_root, "workspaces")
      workspace = Path.join(workspace_root, "MT-400")
      File.mkdir_p!(workspace)

      write_workflow_file!(Workflow.workflow_file_path(), workspace_root: workspace_root)

      assert {:ok, _} = AppServer.validate_workspace_cwd(workspace, nil)

      assert {:error, {:invalid_workspace_cwd, :workspace_root, _}} =
               AppServer.validate_workspace_cwd(workspace_root, nil)
    after
      File.rm_rf(test_root)
    end
  end

  test "config defaults provider to codex" do
    assert Config.agent_codex_config(:coder).provider == "codex"
    assert Config.agent_backend(:coder) == OdysseyElixir.Codex.AppServer
  end

  test "config routes claude_code provider to CliClient" do
    write_workflow_file!(Workflow.workflow_file_path(),
      codex_provider: "claude_code",
      codex_command: "claude"
    )

    assert Config.agent_codex_config(:coder).provider == "claude_code"
    assert Config.agent_backend(:coder) == OdysseyElixir.ClaudeCode.CliClient
  end
end
