defmodule OdysseyElixir.TrackerTest do
  use OdysseyElixir.TestSupport

  alias OdysseyElixir.Tracker

  describe "adapter/0" do
    test "returns Jira.Adapter for jira" do
      write_workflow_file!(
        Application.get_env(:odyssey_elixir, :workflow_file_path),
        tracker_kind: "jira",
        tracker_base_url: "https://jira.example.com",
        tracker_project_key: "PROJ",
        tracker_email: "bot@example.com"
      )

      assert Tracker.adapter() == OdysseyElixir.Jira.Adapter
    end

    test "returns GitHub.Adapter for github" do
      write_workflow_file!(
        Application.get_env(:odyssey_elixir, :workflow_file_path),
        tracker_kind: "github",
        tracker_repo: "org/repo"
      )

      assert Tracker.adapter() == OdysseyElixir.GitHub.Adapter
    end

    test "returns Tracker.Memory for memory" do
      write_workflow_file!(
        Application.get_env(:odyssey_elixir, :workflow_file_path),
        tracker_kind: "memory"
      )

      assert Tracker.adapter() == OdysseyElixir.Tracker.Memory
    end

    test "returns Linear.Adapter for linear" do
      write_workflow_file!(
        Application.get_env(:odyssey_elixir, :workflow_file_path),
        tracker_kind: "linear"
      )

      assert Tracker.adapter() == OdysseyElixir.Linear.Adapter
    end

    test "returns Linear.Adapter as default for unknown kind" do
      write_workflow_file!(
        Application.get_env(:odyssey_elixir, :workflow_file_path),
        tracker_kind: "unknown_tracker"
      )

      assert Tracker.adapter() == OdysseyElixir.Linear.Adapter
    end
  end
end
