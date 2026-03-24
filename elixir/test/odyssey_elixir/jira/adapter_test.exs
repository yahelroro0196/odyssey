defmodule OdysseyElixir.Jira.AdapterTest do
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

    Process.put(:jira_test_pid, self())

    on_exit(fn ->
      Application.delete_env(:odyssey_elixir, :jira_client_module)
    end)

    :ok
  end

  describe "create_comment/2" do
    test "sends ADF-formatted body" do
      Process.put(:jira_rest_response, {:ok, %{"id" => "123"}})

      assert :ok = Adapter.create_comment("PROJ-1", "Hello world")

      assert_received {:jira_rest_api, "POST", "/rest/api/3/issue/PROJ-1/comment", body}
      assert body["body"]["type"] == "doc"
      assert body["body"]["version"] == 1
      [paragraph] = body["body"]["content"]
      assert paragraph["type"] == "paragraph"
      [text_node] = paragraph["content"]
      assert text_node["type"] == "text"
      assert text_node["text"] == "Hello world"
    end

    test "returns error on failure" do
      Process.put(:jira_rest_response, {:error, :connection_failed})

      assert {:error, :connection_failed} = Adapter.create_comment("PROJ-1", "fail")
    end
  end

  describe "update_issue_state/2" do
    test "looks up transition and applies it" do
      transitions_response = %{
        "transitions" => [
          %{"id" => "31", "name" => "Done", "to" => %{"name" => "Done"}},
          %{"id" => "21", "name" => "In Progress", "to" => %{"name" => "In Progress"}}
        ]
      }

      Process.put(:jira_rest_response, fn method, path, _body ->
        cond do
          method == "GET" && String.contains?(path, "/transitions") ->
            {:ok, transitions_response}

          method == "POST" && String.contains?(path, "/transitions") ->
            {:ok, %{}}

          true ->
            {:error, :unexpected_call}
        end
      end)

      assert :ok = Adapter.update_issue_state("PROJ-1", "Done")

      assert_received {:jira_rest_api, "GET", "/rest/api/3/issue/PROJ-1/transitions", nil}

      assert_received {:jira_rest_api, "POST", "/rest/api/3/issue/PROJ-1/transitions", body}
      assert body["transition"]["id"] == "31"
    end

    test "returns error when transition not found" do
      Process.put(:jira_rest_response, fn method, path, _body ->
        if method == "GET" && String.contains?(path, "/transitions") do
          {:ok, %{"transitions" => [%{"id" => "31", "name" => "Done", "to" => %{"name" => "Done"}}]}}
        else
          {:error, :unexpected_call}
        end
      end)

      assert {:error, {:transition_not_found, "Nonexistent"}} =
               Adapter.update_issue_state("PROJ-1", "Nonexistent")
    end

    test "matches transition case-insensitively" do
      Process.put(:jira_rest_response, fn method, path, _body ->
        cond do
          method == "GET" && String.contains?(path, "/transitions") ->
            {:ok,
             %{
               "transitions" => [
                 %{"id" => "31", "name" => "In Progress", "to" => %{"name" => "In Progress"}}
               ]
             }}

          method == "POST" && String.contains?(path, "/transitions") ->
            {:ok, %{}}

          true ->
            {:error, :unexpected_call}
        end
      end)

      assert :ok = Adapter.update_issue_state("PROJ-1", "in progress")
    end
  end
end
