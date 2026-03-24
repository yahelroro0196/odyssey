defmodule OdysseyElixir.TestSupport.FakeJiraClient do
  @moduledoc false

  def fetch_candidate_issues do
    case Process.get(:jira_candidate_issues) do
      nil -> {:ok, []}
      issues -> {:ok, issues}
    end
  end

  def fetch_issues_by_states(_states) do
    case Process.get(:jira_issues_by_states) do
      nil -> {:ok, []}
      issues -> {:ok, issues}
    end
  end

  def fetch_issue_states_by_ids(_ids) do
    case Process.get(:jira_issue_states) do
      nil -> {:ok, []}
      issues -> {:ok, issues}
    end
  end

  def rest_api(method, path, body \\ nil) do
    if pid = Process.get(:jira_test_pid) do
      send(pid, {:jira_rest_api, method, path, body})
    end

    case Process.get(:jira_rest_response) do
      nil -> {:ok, %{}}
      fun when is_function(fun, 3) -> fun.(method, path, body)
      response -> response
    end
  end
end

defmodule OdysseyElixir.TestSupport.FakeGitHubClient do
  @moduledoc false

  def fetch_candidate_issues do
    case Process.get(:github_candidate_issues) do
      nil -> {:ok, []}
      issues -> {:ok, issues}
    end
  end

  def fetch_issues_by_states(_states) do
    case Process.get(:github_issues_by_states) do
      nil -> {:ok, []}
      issues -> {:ok, issues}
    end
  end

  def fetch_issue_states_by_ids(_ids) do
    case Process.get(:github_issue_states) do
      nil -> {:ok, []}
      issues -> {:ok, issues}
    end
  end

  def rest_api(method, path, body \\ nil) do
    if pid = Process.get(:github_test_pid) do
      send(pid, {:github_rest_api, method, path, body})
    end

    case Process.get(:github_rest_response) do
      nil -> {:ok, %{}}
      fun when is_function(fun, 3) -> fun.(method, path, body)
      response -> response
    end
  end
end
