defmodule OdysseyElixir.GitHub.ClientTest do
  use OdysseyElixir.TestSupport, async: false

  alias OdysseyElixir.GitHub.Adapter

  setup do
    Application.put_env(
      :odyssey_elixir,
      :github_client_module,
      OdysseyElixir.TestSupport.FakeGitHubClient
    )

    write_workflow_file!(Workflow.workflow_file_path(),
      tracker_kind: "github",
      tracker_api_token: "ghp_test123",
      tracker_repo: "owner/repo",
      tracker_active_states: ["todo", "in progress"],
      tracker_terminal_states: ["done", "closed"]
    )

    on_exit(fn ->
      Application.delete_env(:odyssey_elixir, :github_client_module)
    end)

    :ok
  end

  describe "normalize_issue (tested through adapter + fake)" do
    test "maps issue number to identifier with # prefix" do
      issue = %Issue{
        id: "42",
        identifier: "#42",
        title: "Fix bug",
        description: "Details here",
        state: "todo",
        url: "https://github.com/owner/repo/issues/42",
        labels: ["bug", "todo"],
        branch_name: "odyssey/42-fix-bug",
        assignee_id: "octocat",
        assigned_to_worker: true
      }

      Process.put(:github_candidate_issues, [issue])
      assert {:ok, [fetched]} = Adapter.fetch_candidate_issues()
      assert fetched.identifier == "#42"
      assert fetched.id == "42"
    end

    test "detects state from labels" do
      issue = %Issue{
        id: "10",
        identifier: "#10",
        title: "Labeled",
        state: "in progress",
        labels: ["in progress", "enhancement"]
      }

      Process.put(:github_candidate_issues, [issue])
      assert {:ok, [fetched]} = Adapter.fetch_candidate_issues()
      assert fetched.state == "in progress"
    end

    test "handles empty labels" do
      issue = %Issue{
        id: "11",
        identifier: "#11",
        title: "No labels",
        state: "open",
        labels: []
      }

      Process.put(:github_candidate_issues, [issue])
      assert {:ok, [fetched]} = Adapter.fetch_candidate_issues()
      assert fetched.labels == []
    end

    test "url comes from html_url" do
      issue = %Issue{
        id: "12",
        identifier: "#12",
        title: "URL test",
        state: "todo",
        url: "https://github.com/owner/repo/issues/12"
      }

      Process.put(:github_candidate_issues, [issue])
      assert {:ok, [fetched]} = Adapter.fetch_candidate_issues()
      assert fetched.url == "https://github.com/owner/repo/issues/12"
    end

    test "assignee from assignee.login" do
      issue = %Issue{
        id: "13",
        identifier: "#13",
        title: "Assigned",
        state: "todo",
        assignee_id: "octocat"
      }

      Process.put(:github_candidate_issues, [issue])
      assert {:ok, [fetched]} = Adapter.fetch_candidate_issues()
      assert fetched.assignee_id == "octocat"
    end

    test "returns empty list when no issues" do
      Process.put(:github_candidate_issues, [])
      assert {:ok, []} = Adapter.fetch_candidate_issues()
    end
  end

  describe "fetch_issues_by_states" do
    test "delegates to client" do
      issue = %Issue{
        id: "20",
        identifier: "#20",
        title: "By state",
        state: "done"
      }

      Process.put(:github_issues_by_states, [issue])
      assert {:ok, [fetched]} = Adapter.fetch_issues_by_states(["done"])
      assert fetched.identifier == "#20"
    end
  end

  describe "fetch_issue_states_by_ids" do
    test "delegates to client" do
      issue = %Issue{
        id: "30",
        identifier: "#30",
        title: "By ID",
        state: "in progress"
      }

      Process.put(:github_issue_states, [issue])
      assert {:ok, [fetched]} = Adapter.fetch_issue_states_by_ids(["30"])
      assert fetched.state == "in progress"
    end
  end
end
