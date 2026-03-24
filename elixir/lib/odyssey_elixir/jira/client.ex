defmodule OdysseyElixir.Jira.Client do
  @moduledoc """
  Jira REST API client for polling and managing issues.
  """

  require Logger
  alias OdysseyElixir.{Config, Tracker.Issue}

  @page_size 50
  @max_error_body_log_bytes 1_000

  @spec fetch_candidate_issues() :: {:ok, [Issue.t()]} | {:error, term()}
  def fetch_candidate_issues do
    tracker = Config.settings!().tracker

    cond do
      not is_binary(tracker.api_key) ->
        {:error, :missing_jira_api_token}

      not is_binary(tracker.base_url) ->
        {:error, :missing_jira_base_url}

      not is_binary(tracker.project_key) ->
        {:error, :missing_jira_project_key}

      true ->
        states_jql = Enum.map_join(tracker.active_states, ", ", &"\"#{&1}\"")

        jql =
          "project = #{tracker.project_key} AND status IN (#{states_jql})"
          |> maybe_append_jql_filter(tracker.jql_filter)

        do_search(jql, 0, [])
    end
  end

  @spec fetch_issues_by_states([String.t()]) :: {:ok, [Issue.t()]} | {:error, term()}
  def fetch_issues_by_states(state_names) when is_list(state_names) do
    if state_names == [] do
      {:ok, []}
    else
      tracker = Config.settings!().tracker
      states_jql = Enum.map_join(state_names, ", ", &"\"#{&1}\"")

      jql =
        "project = #{tracker.project_key} AND status IN (#{states_jql})"
        |> maybe_append_jql_filter(tracker.jql_filter)

      do_search(jql, 0, [])
    end
  end

  @spec fetch_issue_states_by_ids([String.t()]) :: {:ok, [Issue.t()]} | {:error, term()}
  def fetch_issue_states_by_ids(issue_ids) when is_list(issue_ids) do
    ids = Enum.uniq(issue_ids)

    if ids == [] do
      {:ok, []}
    else
      keys_jql = Enum.map_join(ids, ", ", &"\"#{&1}\"")
      jql = "key IN (#{keys_jql})"
      do_search(jql, 0, [])
    end
  end

  @spec rest_api(String.t(), String.t(), map() | nil) :: {:ok, term()} | {:error, term()}
  def rest_api(method, path, body \\ nil) do
    tracker = Config.settings!().tracker
    url = String.trim_trailing(tracker.base_url, "/") <> path

    with {:ok, headers} <- auth_headers(tracker) do
      opts = [headers: headers, connect_options: [timeout: 30_000]]

      opts =
        if body && method in ["POST", "PUT", "PATCH"] do
          Keyword.put(opts, :json, body)
        else
          opts
        end

      result =
        case String.upcase(method) do
          "GET" -> Req.get(url, opts)
          "POST" -> Req.post(url, opts)
          "PUT" -> Req.put(url, opts)
          "DELETE" -> Req.delete(url, opts)
          "PATCH" -> Req.patch(url, opts)
          other -> {:error, {:unsupported_method, other}}
        end

      case result do
        {:ok, %{status: status, body: resp_body}} when status in 200..299 ->
          {:ok, resp_body}

        {:ok, %{status: status, body: resp_body}} ->
          Logger.error("Jira API #{method} #{path} failed status=#{status} body=#{summarize_body(resp_body)}")
          {:error, {:jira_api_status, status}}

        {:error, reason} ->
          Logger.error("Jira API #{method} #{path} failed: #{inspect(reason)}")
          {:error, {:jira_api_request, reason}}
      end
    end
  end

  defp do_search(jql, start_at, acc) do
    body = %{
      "jql" => jql,
      "startAt" => start_at,
      "maxResults" => @page_size,
      "fields" => ["summary", "description", "status", "priority", "labels", "assignee"]
    }

    case rest_api("POST", "/rest/api/3/search", body) do
      {:ok, %{"issues" => issues, "total" => total}} ->
        tracker = Config.settings!().tracker
        normalized = Enum.map(issues, &normalize_issue(&1, tracker))
        updated_acc = acc ++ normalized

        if start_at + length(issues) < total do
          do_search(jql, start_at + length(issues), updated_acc)
        else
          {:ok, updated_acc}
        end

      {:ok, %{"issues" => issues}} ->
        tracker = Config.settings!().tracker
        normalized = Enum.map(issues, &normalize_issue(&1, tracker))
        {:ok, acc ++ normalized}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp normalize_issue(issue, tracker) when is_map(issue) do
    fields = issue["fields"] || %{}
    key = issue["key"]

    %Issue{
      id: key,
      identifier: key,
      title: get_in(fields, ["summary"]),
      description: extract_description(fields["description"]),
      state: get_in(fields, ["status", "name"]),
      priority: get_in(fields, ["priority", "id"]),
      url: String.trim_trailing(tracker.base_url, "/") <> "/browse/#{key}",
      labels: extract_labels(fields["labels"]),
      branch_name: "odyssey/#{key}",
      assignee_id: get_in(fields, ["assignee", "accountId"]),
      assigned_to_worker: true
    }
  end

  defp extract_description(nil), do: nil
  defp extract_description(desc) when is_binary(desc), do: desc

  defp extract_description(%{"content" => content}) when is_list(content) do
    content
    |> Enum.map(&extract_adf_text/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
  end

  defp extract_description(_), do: nil

  defp extract_adf_text(%{"type" => "paragraph", "content" => content}) when is_list(content) do
    Enum.map_join(content, "", fn
      %{"type" => "text", "text" => text} -> text
      _ -> ""
    end)
  end

  defp extract_adf_text(_), do: ""

  defp extract_labels(nil), do: []

  defp extract_labels(labels) when is_list(labels) do
    labels
    |> Enum.map(fn
      %{"name" => name} when is_binary(name) -> String.downcase(name)
      label when is_binary(label) -> String.downcase(label)
      _ -> nil
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp extract_labels(_), do: []

  defp maybe_append_jql_filter(jql, nil), do: jql
  defp maybe_append_jql_filter(jql, ""), do: jql
  defp maybe_append_jql_filter(jql, filter), do: "#{jql} AND (#{filter})"

  defp auth_headers(tracker) do
    cond do
      not is_binary(tracker.api_key) ->
        {:error, :missing_jira_api_token}

      is_binary(tracker.email) ->
        credentials = Base.encode64("#{tracker.email}:#{tracker.api_key}")

        {:ok,
         [
           {"Authorization", "Basic #{credentials}"},
           {"Content-Type", "application/json"}
         ]}

      true ->
        {:ok,
         [
           {"Authorization", "Bearer #{tracker.api_key}"},
           {"Content-Type", "application/json"}
         ]}
    end
  end

  defp summarize_body(body) when is_binary(body) do
    if byte_size(body) > @max_error_body_log_bytes do
      binary_part(body, 0, @max_error_body_log_bytes) <> "...<truncated>"
    else
      body
    end
  end

  defp summarize_body(body), do: inspect(body, limit: 20, printable_limit: @max_error_body_log_bytes)
end
