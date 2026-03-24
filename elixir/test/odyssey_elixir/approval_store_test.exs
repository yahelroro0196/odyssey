defmodule OdysseyElixir.ApprovalStoreTest do
  use OdysseyElixir.TestSupport, async: false

  alias OdysseyElixir.ApprovalStore

  @pubsub OdysseyElixir.PubSub
  @topic "approvals:updates"

  defp fake_issue(id \\ "ISSUE-#{System.unique_integer([:positive])}") do
    %{id: id, identifier: id, title: "Test issue #{id}"}
  end

  defp stop_existing_approval_store do
    case Process.whereis(ApprovalStore) do
      nil -> :ok
      _pid -> Supervisor.terminate_child(OdysseyElixir.Supervisor, ApprovalStore)
    end
  end

  defp restart_app_approval_store do
    Supervisor.restart_child(OdysseyElixir.Supervisor, ApprovalStore)
    :ok
  end

  defp start_approval_store(_ctx) do
    stop_existing_approval_store()
    pid = start_supervised!(ApprovalStore)
    Phoenix.PubSub.subscribe(@pubsub, @topic)

    on_exit(fn ->
      restart_app_approval_store()
    end)

    %{store_pid: pid}
  end

  defp write_workflow_with_approval_gates(timeout_ms, timeout_action) do
    root = Path.join(System.tmp_dir!(), "odyssey-approval-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    file = Path.join(root, "WORKFLOW.md")
    write_workflow_file!(file)

    # Append approval_gates YAML section before the closing ---
    content = File.read!(file)

    patched =
      String.replace(
        content,
        ~r/^approval_gates:.*$\n/m,
        ""
      )

    # Insert approval_gates section before the last ---
    parts = String.split(patched, "\n---\n", parts: 2)

    new_content =
      case parts do
        [yaml, prompt] ->
          yaml <>
            "\napproval_gates:\n  timeout_ms: #{timeout_ms}\n  timeout_action: \"#{timeout_action}\"\n---\n" <>
            prompt

        _ ->
          patched
      end

    File.write!(file, new_content)
    OdysseyElixir.Workflow.set_workflow_file_path(file)
    if Process.whereis(OdysseyElixir.WorkflowStore), do: OdysseyElixir.WorkflowStore.force_reload()
    root
  end

  describe "request_approval/3" do
    setup :start_approval_store

    test "creates pending entry and returns {:ok, id}" do
      issue = fake_issue()
      assert {:ok, 1} = ApprovalStore.request_approval(:before_dispatch, issue, %{orchestrator_pid: self()})
    end

    test "increments ids for successive requests" do
      issue = fake_issue()
      assert {:ok, 1} = ApprovalStore.request_approval(:before_dispatch, issue, %{orchestrator_pid: self()})
      assert {:ok, 2} = ApprovalStore.request_approval(:before_merge, issue, %{orchestrator_pid: self()})
    end

    test "broadcasts PubSub update on request" do
      issue = fake_issue()
      {:ok, _id} = ApprovalStore.request_approval(:before_dispatch, issue, %{orchestrator_pid: self()})
      assert_receive {:approvals_updated}
    end
  end

  describe "list_pending/0" do
    setup :start_approval_store

    test "returns all pending approvals" do
      issue1 = fake_issue()
      issue2 = fake_issue()
      {:ok, id1} = ApprovalStore.request_approval(:before_dispatch, issue1, %{orchestrator_pid: self()})
      {:ok, id2} = ApprovalStore.request_approval(:before_merge, issue2, %{orchestrator_pid: self()})

      pending = ApprovalStore.list_pending()
      assert length(pending) == 2
      assert Enum.map(pending, & &1.id) == [id1, id2]
    end

    test "returns empty list when no approvals pending" do
      assert [] = ApprovalStore.list_pending()
    end
  end

  describe "approve/1" do
    setup :start_approval_store

    test "removes from pending and sends :approved to orchestrator_pid" do
      issue = fake_issue()
      metadata = %{orchestrator_pid: self(), extra: "data"}
      {:ok, id} = ApprovalStore.request_approval(:before_dispatch, issue, metadata)

      assert :ok = ApprovalStore.approve(id)
      assert_receive {:approval_resolved, ^id, :approved, ^metadata}
      assert [] = ApprovalStore.list_pending()
    end

    test "returns {:error, :not_found} for unknown id" do
      assert {:error, :not_found} = ApprovalStore.approve(999)
    end

    test "broadcasts PubSub update on resolve" do
      issue = fake_issue()
      {:ok, id} = ApprovalStore.request_approval(:before_dispatch, issue, %{orchestrator_pid: self()})
      assert_receive {:approvals_updated}

      ApprovalStore.approve(id)
      assert_receive {:approvals_updated}
    end
  end

  describe "reject/1" do
    setup :start_approval_store

    test "removes from pending and sends :rejected to orchestrator_pid" do
      issue = fake_issue()
      metadata = %{orchestrator_pid: self(), extra: "data"}
      {:ok, id} = ApprovalStore.request_approval(:before_merge, issue, metadata)

      assert :ok = ApprovalStore.reject(id)
      assert_receive {:approval_resolved, ^id, :rejected, ^metadata}
      assert [] = ApprovalStore.list_pending()
    end

    test "returns {:error, :not_found} for unknown id" do
      assert {:error, :not_found} = ApprovalStore.reject(999)
    end
  end

  describe "timeout" do
    test "auto-approves when timeout_action is 'approve'" do
      root = write_workflow_with_approval_gates(50, "approve")
      stop_existing_approval_store()
      start_supervised!(ApprovalStore)
      Phoenix.PubSub.subscribe(@pubsub, @topic)

      issue = fake_issue()
      {:ok, id} = ApprovalStore.request_approval(:before_dispatch, issue, %{orchestrator_pid: self()})

      assert_receive {:approval_resolved, ^id, :approved, _metadata}, 500
      assert [] = ApprovalStore.list_pending()

      on_exit(fn ->
        restart_app_approval_store()
        File.rm_rf(root)
      end)
    end

    test "auto-rejects when timeout_action is 'reject'" do
      root = write_workflow_with_approval_gates(50, "reject")
      stop_existing_approval_store()
      start_supervised!(ApprovalStore)
      Phoenix.PubSub.subscribe(@pubsub, @topic)

      issue = fake_issue()
      {:ok, id} = ApprovalStore.request_approval(:before_dispatch, issue, %{orchestrator_pid: self()})

      assert_receive {:approval_resolved, ^id, :rejected, _metadata}, 500
      assert [] = ApprovalStore.list_pending()

      on_exit(fn ->
        restart_app_approval_store()
        File.rm_rf(root)
      end)
    end
  end

  describe "timer cancellation" do
    setup :start_approval_store

    test "no timeout message after manual approve" do
      issue = fake_issue()
      {:ok, id} = ApprovalStore.request_approval(:before_dispatch, issue, %{orchestrator_pid: self()})

      :ok = ApprovalStore.approve(id)
      assert_receive {:approval_resolved, ^id, :approved, _metadata}

      refute_receive {:approval_resolved, ^id, _, _}, 200
    end
  end

  describe "multiple pending approvals" do
    setup :start_approval_store

    test "tracked independently" do
      issue1 = fake_issue()
      issue2 = fake_issue()
      meta1 = %{orchestrator_pid: self(), tag: :first}
      meta2 = %{orchestrator_pid: self(), tag: :second}

      {:ok, id1} = ApprovalStore.request_approval(:before_dispatch, issue1, meta1)
      {:ok, id2} = ApprovalStore.request_approval(:before_merge, issue2, meta2)

      :ok = ApprovalStore.approve(id1)
      assert_receive {:approval_resolved, ^id1, :approved, ^meta1}

      pending = ApprovalStore.list_pending()
      assert length(pending) == 1
      assert hd(pending).id == id2

      :ok = ApprovalStore.reject(id2)
      assert_receive {:approval_resolved, ^id2, :rejected, ^meta2}
      assert [] = ApprovalStore.list_pending()
    end
  end
end
