defmodule OdysseyElixir.GitHub.Adapter do
  @moduledoc """
  GitHub Issues-backed tracker adapter.
  """

  @behaviour OdysseyElixir.Tracker

  alias OdysseyElixir.{Config, GitHub.Client}

  @spec fetch_candidate_issues() :: {:ok, [term()]} | {:error, term()}
  def fetch_candidate_issues, do: Client.fetch_candidate_issues()

  @spec fetch_issues_by_states([String.t()]) :: {:ok, [term()]} | {:error, term()}
  def fetch_issues_by_states(states), do: Client.fetch_issues_by_states(states)

  @spec fetch_issue_states_by_ids([String.t()]) :: {:ok, [term()]} | {:error, term()}
  def fetch_issue_states_by_ids(issue_ids), do: Client.fetch_issue_states_by_ids(issue_ids)

  @spec create_comment(String.t(), String.t()) :: :ok | {:error, term()}
  def create_comment(issue_id, body) when is_binary(issue_id) and is_binary(body) do
    tracker = Config.settings!().tracker

    case Client.rest_api("POST", "/repos/#{tracker.repo}/issues/#{issue_id}/comments", %{
           "body" => body
         }) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @spec update_issue_state(String.t(), String.t()) :: :ok | {:error, term()}
  def update_issue_state(issue_id, state_name)
      when is_binary(issue_id) and is_binary(state_name) do
    tracker = Config.settings!().tracker
    terminal_set = MapSet.new(Enum.map(tracker.terminal_states, &String.downcase/1))
    active_set = MapSet.new(Enum.map(tracker.active_states, &String.downcase/1))
    known_states = MapSet.union(active_set, terminal_set)

    with :ok <- remove_state_labels(tracker, issue_id, known_states),
         :ok <- add_state_label(tracker, issue_id, state_name) do
      if MapSet.member?(terminal_set, String.downcase(state_name)) do
        case Client.rest_api("PATCH", "/repos/#{tracker.repo}/issues/#{issue_id}", %{
               "state" => "closed"
             }) do
          {:ok, _} -> :ok
          {:error, reason} -> {:error, reason}
        end
      else
        :ok
      end
    end
  end

  defp remove_state_labels(tracker, issue_id, known_states) do
    case Client.rest_api("GET", "/repos/#{tracker.repo}/issues/#{issue_id}/labels") do
      {:ok, labels} when is_list(labels) ->
        labels
        |> Enum.filter(fn
          %{"name" => name} -> MapSet.member?(known_states, String.downcase(name))
          _ -> false
        end)
        |> Enum.reduce_while(:ok, fn %{"name" => name}, :ok ->
          case Client.rest_api(
                 "DELETE",
                 "/repos/#{tracker.repo}/issues/#{issue_id}/labels/#{URI.encode(name)}"
               ) do
            {:ok, _} -> {:cont, :ok}
            {:error, reason} -> {:halt, {:error, reason}}
          end
        end)

      {:ok, _} ->
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp add_state_label(tracker, issue_id, state_name) do
    case Client.rest_api("POST", "/repos/#{tracker.repo}/issues/#{issue_id}/labels", %{
           "labels" => [state_name]
         }) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
