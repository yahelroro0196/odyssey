defmodule OdysseyElixir.GitHub.AdapterTest do
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

    Process.put(:github_test_pid, self())

    on_exit(fn ->
      Application.delete_env(:odyssey_elixir, :github_client_module)
    end)

    :ok
  end

  describe "create_comment/2" do
    test "posts correct body" do
      Process.put(:github_rest_response, {:ok, %{"id" => 1}})

      assert :ok = Adapter.create_comment("42", "Looks good!")

      assert_received {:github_rest_api, "POST", path, body}
      assert path == "/repos/owner/repo/issues/42/comments"
      assert body == %{"body" => "Looks good!"}
    end

    test "returns error on failure" do
      Process.put(:github_rest_response, {:error, :timeout})

      assert {:error, :timeout} = Adapter.create_comment("42", "fail")
    end
  end

  describe "update_issue_state/2" do
    test "removes old labels and adds new label" do
      calls = :ets.new(:github_calls, [:bag, :public])

      Process.put(:github_rest_response, fn method, path, body ->
        :ets.insert(calls, {method, path, body})

        cond do
          method == "GET" && String.contains?(path, "/labels") ->
            {:ok,
             [
               %{"name" => "todo"},
               %{"name" => "enhancement"}
             ]}

          method == "DELETE" ->
            {:ok, %{}}

          method == "POST" && String.contains?(path, "/labels") ->
            {:ok, [%{"name" => "in progress"}]}

          true ->
            {:error, :unexpected}
        end
      end)

      assert :ok = Adapter.update_issue_state("42", "in progress")

      all_calls = :ets.tab2list(calls)

      assert Enum.any?(all_calls, fn {m, p, _b} ->
               m == "GET" && String.contains?(p, "/issues/42/labels")
             end)

      assert Enum.any?(all_calls, fn {m, p, _b} ->
               m == "DELETE" && String.contains?(p, "/labels/todo")
             end)

      refute Enum.any?(all_calls, fn {m, p, _b} ->
               m == "DELETE" && String.contains?(p, "/labels/enhancement")
             end)

      assert Enum.any?(all_calls, fn {_m, _p, b} ->
               b == %{"labels" => ["in progress"]}
             end)

      :ets.delete(calls)
    end

    test "closes issue for terminal states" do
      calls = :ets.new(:github_calls, [:bag, :public])

      Process.put(:github_rest_response, fn method, path, body ->
        :ets.insert(calls, {method, path, body})

        cond do
          method == "GET" && String.contains?(path, "/labels") ->
            {:ok, [%{"name" => "in progress"}]}

          method == "DELETE" ->
            {:ok, %{}}

          method == "POST" && String.contains?(path, "/labels") ->
            {:ok, [%{"name" => "done"}]}

          method == "PATCH" ->
            {:ok, %{}}

          true ->
            {:error, :unexpected}
        end
      end)

      assert :ok = Adapter.update_issue_state("42", "done")

      all_calls = :ets.tab2list(calls)

      assert Enum.any?(all_calls, fn {m, _p, b} ->
               m == "PATCH" && b == %{"state" => "closed"}
             end)

      :ets.delete(calls)
    end

    test "does not close issue for non-terminal states" do
      calls = :ets.new(:github_calls, [:bag, :public])

      Process.put(:github_rest_response, fn method, path, body ->
        :ets.insert(calls, {method, path, body})

        cond do
          method == "GET" && String.contains?(path, "/labels") ->
            {:ok, []}

          method == "POST" && String.contains?(path, "/labels") ->
            {:ok, [%{"name" => "todo"}]}

          true ->
            {:error, :unexpected}
        end
      end)

      assert :ok = Adapter.update_issue_state("42", "todo")

      all_calls = :ets.tab2list(calls)

      refute Enum.any?(all_calls, fn {m, _p, _b} -> m == "PATCH" end)

      :ets.delete(calls)
    end

    test "propagates error from label fetch" do
      Process.put(:github_rest_response, fn method, path, _body ->
        if method == "GET" && String.contains?(path, "/labels") do
          {:error, :network_error}
        else
          {:ok, %{}}
        end
      end)

      assert {:error, :network_error} = Adapter.update_issue_state("42", "done")
    end
  end
end
