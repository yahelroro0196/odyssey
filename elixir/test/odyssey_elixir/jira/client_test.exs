defmodule OdysseyElixir.Jira.ClientTest do
  use OdysseyElixir.TestSupport, async: false

  alias OdysseyElixir.Jira.Adapter

  setup do
    Application.put_env(
      :odyssey_elixir,
      :jira_client_module,
      OdysseyElixir.TestSupport.FakeJiraClient
    )

    write_workflow_file!(Workflow.workflow_file_path(),
      tracker_kind: "jira",
      tracker_api_token: "test-token",
      tracker_base_url: "https://jira.example.com",
      tracker_project_key: "PROJ",
      tracker_email: "user@example.com"
    )

    on_exit(fn ->
      Application.delete_env(:odyssey_elixir, :jira_client_module)
    end)

    :ok
  end

  describe "normalize_issue (tested through adapter + fake)" do
    test "maps Jira JSON fields correctly via fetch_candidate_issues" do
      issue = %Issue{
        id: "PROJ-42",
        identifier: "PROJ-42",
        title: "Fix login",
        description: "Login is broken",
        state: "In Progress",
        priority: "3",
        url: "https://jira.example.com/browse/PROJ-42",
        labels: ["bug"],
        branch_name: "odyssey/PROJ-42",
        assignee_id: "abc123",
        assigned_to_worker: true
      }

      Process.put(:jira_candidate_issues, [issue])
      assert {:ok, [fetched]} = Adapter.fetch_candidate_issues()
      assert fetched.identifier == "PROJ-42"
      assert fetched.title == "Fix login"
      assert fetched.state == "In Progress"
      assert fetched.url == "https://jira.example.com/browse/PROJ-42"
      assert fetched.labels == ["bug"]
      assert fetched.branch_name == "odyssey/PROJ-42"
      assert fetched.assignee_id == "abc123"
    end

    test "handles nil description" do
      issue = %Issue{
        id: "PROJ-1",
        identifier: "PROJ-1",
        title: "No desc",
        description: nil,
        state: "Todo"
      }

      Process.put(:jira_candidate_issues, [issue])
      assert {:ok, [fetched]} = Adapter.fetch_candidate_issues()
      assert fetched.description == nil
    end

    test "handles empty labels" do
      issue = %Issue{
        id: "PROJ-2",
        identifier: "PROJ-2",
        title: "No labels",
        state: "Todo",
        labels: []
      }

      Process.put(:jira_candidate_issues, [issue])
      assert {:ok, [fetched]} = Adapter.fetch_candidate_issues()
      assert fetched.labels == []
    end

    test "returns empty list when no issues" do
      Process.put(:jira_candidate_issues, [])
      assert {:ok, []} = Adapter.fetch_candidate_issues()
    end
  end

  describe "fetch_issues_by_states" do
    test "delegates to client" do
      issue = %Issue{
        id: "PROJ-10",
        identifier: "PROJ-10",
        title: "Stateful",
        state: "Done"
      }

      Process.put(:jira_issues_by_states, [issue])
      assert {:ok, [fetched]} = Adapter.fetch_issues_by_states(["Done"])
      assert fetched.identifier == "PROJ-10"
    end
  end

  describe "fetch_issue_states_by_ids" do
    test "delegates to client" do
      issue = %Issue{
        id: "PROJ-20",
        identifier: "PROJ-20",
        title: "By ID",
        state: "In Progress"
      }

      Process.put(:jira_issue_states, [issue])
      assert {:ok, [fetched]} = Adapter.fetch_issue_states_by_ids(["PROJ-20"])
      assert fetched.state == "In Progress"
    end
  end
end
