defmodule SymphonyElixir.WorkflowStoreReloadTest do
  use SymphonyElixir.TestSupport

  alias SymphonyElixir.WorkflowStore

  describe "reload_status/0" do
    test "returns status with expected structure" do
      status = WorkflowStore.reload_status()
      assert is_integer(status.reload_count)
      assert is_list(status.last_changed_sections)
    end

    test "increments reload_count after config change" do
      before_count = WorkflowStore.reload_status().reload_count

      workflow_path = SymphonyElixir.Workflow.workflow_file_path()
      write_workflow_file!(workflow_path, poll_interval_ms: 5_000)

      assert :ok = WorkflowStore.force_reload()

      status = WorkflowStore.reload_status()
      assert status.reload_count == before_count + 1
      assert %DateTime{} = status.last_reloaded_at
      assert "polling" in status.last_changed_sections
    end
  end

  describe "subscribe_config/0 and PubSub broadcast" do
    test "receives config_reloaded event on reload" do
      :ok = WorkflowStore.subscribe_config()

      workflow_path = SymphonyElixir.Workflow.workflow_file_path()
      write_workflow_file!(workflow_path, max_concurrent_agents: 99)

      assert :ok = WorkflowStore.force_reload()

      assert_receive {:config_reloaded, metadata}
      assert %DateTime{} = metadata.reloaded_at
      assert "agent" in metadata.changed_sections
    end

    test "does not broadcast when config is unchanged" do
      :ok = WorkflowStore.subscribe_config()

      assert :ok = WorkflowStore.force_reload()

      refute_receive {:config_reloaded, _}, 100
    end
  end

  describe "changed_sections detection" do
    test "identifies multiple changed sections" do
      :ok = WorkflowStore.subscribe_config()

      workflow_path = SymphonyElixir.Workflow.workflow_file_path()
      write_workflow_file!(workflow_path, poll_interval_ms: 7_000, max_concurrent_agents: 3)

      assert :ok = WorkflowStore.force_reload()

      assert_receive {:config_reloaded, metadata}
      assert "polling" in metadata.changed_sections
      assert "agent" in metadata.changed_sections
    end
  end

  describe "failed reload" do
    test "does not increment reload_count on failure" do
      workflow_path = SymphonyElixir.Workflow.workflow_file_path()

      WorkflowStore.force_reload()
      WorkflowStore.force_reload()
      before_count = WorkflowStore.reload_status().reload_count

      # Write YAML front matter with invalid YAML syntax to trigger a parse error
      File.write!(workflow_path, "---\n: [invalid yaml {{\n---\nprompt\n")
      {:error, _} = WorkflowStore.force_reload()

      assert WorkflowStore.reload_status().reload_count <= before_count
    end
  end
end
