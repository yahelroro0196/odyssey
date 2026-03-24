defmodule OdysseyElixir.GitHub.Client do
  @moduledoc """
  GitHub Issues REST API client.
  """

  require Logger
  alias OdysseyElixir.{Config, Tracker.Issue}

  @api_base "https://api.github.com"
  @per_page 50
  @max_error_body_log_bytes 1_000

  @spec fetch_candidate_issues() :: {:ok, [Issue.t()]} | {:error, term()}
  def fetch_candidate_issues do
    tracker = Config.settings!().tracker

    cond do
      not is_binary(tracker.api_key) ->
        {:error, :missing_github_token}

      not is_binary(tracker.repo) ->
        {:error, :missing_github_repo}

      true ->
        active_set = MapSet.new(Enum.map(tracker.active_states, &String.downcase/1))

        case do_fetch_open_issues(tracker.repo, 1, []) do
          {:ok, issues} ->
            {:ok, Enum.filter(issues, &issue_matches_states?(&1, active_set))}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  @spec fetch_issues_by_states([String.t()]) :: {:ok, [Issue.t()]} | {:error, term()}
  def fetch_issues_by_states(state_names) when is_list(state_names) do
    if state_names == [] do
      {:ok, []}
    else
      tracker = Config.settings!().tracker
      state_set = MapSet.new(Enum.map(state_names, &String.downcase/1))

      case do_fetch_open_issues(tracker.repo, 1, []) do
        {:ok, issues} ->
          {:ok, Enum.filter(issues, &issue_matches_states?(&1, state_set))}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @spec fetch_issue_states_by_ids([String.t()]) :: {:ok, [Issue.t()]} | {:error, term()}
  def fetch_issue_states_by_ids(issue_ids) when is_list(issue_ids) do
    ids = Enum.uniq(issue_ids)

    if ids == [] do
      {:ok, []}
    else
      tracker = Config.settings!().tracker

      results =
        Enum.reduce_while(ids, {:ok, []}, fn id, {:ok, acc} ->
          case rest_api("GET", "/repos/#{tracker.repo}/issues/#{id}") do
            {:ok, issue_data} ->
              {:cont, {:ok, [normalize_issue(issue_data, tracker) | acc]}}

            {:error, reason} ->
              {:halt, {:error, reason}}
          end
        end)

      case results do
        {:ok, issues} -> {:ok, Enum.reverse(issues)}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @spec rest_api(String.t(), String.t(), map() | nil) :: {:ok, term()} | {:error, term()}
  def rest_api(method, path, body \\ nil) do
    tracker = Config.settings!().tracker
    url = @api_base <> path

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
          Logger.error("GitHub API #{method} #{path} failed status=#{status} body=#{summarize_body(resp_body)}")
          {:error, {:github_api_status, status}}

        {:error, reason} ->
          Logger.error("GitHub API #{method} #{path} failed: #{inspect(reason)}")
          {:error, {:github_api_request, reason}}
      end
    end
  end

  defp do_fetch_open_issues(repo, page, acc) do
    path = "/repos/#{repo}/issues?state=open&per_page=#{@per_page}&page=#{page}"

    case rest_api("GET", path) do
      {:ok, issues} when is_list(issues) ->
        tracker = Config.settings!().tracker

        normalized =
          issues
          |> Enum.reject(&Map.has_key?(&1, "pull_request"))
          |> Enum.map(&normalize_issue(&1, tracker))

        updated_acc = acc ++ normalized

        if length(issues) >= @per_page do
          do_fetch_open_issues(repo, page + 1, updated_acc)
        else
          {:ok, updated_acc}
        end

      {:ok, _} ->
        {:ok, acc}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp normalize_issue(issue, tracker) when is_map(issue) do
    number = issue["number"]
    title = issue["title"] || ""
    all_labels = extract_labels(issue["labels"])
    active_set = MapSet.new(Enum.map(tracker.active_states, &String.downcase/1))
    terminal_set = MapSet.new(Enum.map(tracker.terminal_states, &String.downcase/1))

    state =
      Enum.find(all_labels, fn label ->
        MapSet.member?(active_set, label) || MapSet.member?(terminal_set, label)
      end)

    state =
      cond do
        state -> state
        issue["state"] == "closed" -> "closed"
        true -> "open"
      end

    %Issue{
      id: to_string(number),
      identifier: "##{number}",
      title: title,
      description: issue["body"],
      state: state,
      url: issue["html_url"],
      labels: all_labels,
      branch_name: "odyssey/#{number}-#{slugify(title)}",
      assignee_id: get_in(issue, ["assignee", "login"]),
      assigned_to_worker: true
    }
  end

  defp issue_matches_states?(%Issue{state: state}, state_set) when is_binary(state) do
    MapSet.member?(state_set, String.downcase(state))
  end

  defp issue_matches_states?(_, _), do: false

  defp extract_labels(nil), do: []

  defp extract_labels(labels) when is_list(labels) do
    labels
    |> Enum.map(fn
      %{"name" => name} when is_binary(name) -> String.downcase(name)
      _ -> nil
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp extract_labels(_), do: []

  defp slugify(title) when is_binary(title) do
    title
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
    |> String.slice(0, 50)
  end

  defp slugify(_), do: ""

  defp auth_headers(tracker) do
    if is_binary(tracker.api_key) do
      {:ok,
       [
         {"Authorization", "Bearer #{tracker.api_key}"},
         {"Accept", "application/vnd.github+json"},
         {"X-GitHub-Api-Version", "2022-11-28"}
       ]}
    else
      {:error, :missing_github_token}
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
