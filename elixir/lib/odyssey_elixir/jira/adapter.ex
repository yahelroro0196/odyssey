defmodule OdysseyElixir.Jira.Adapter do
  @moduledoc """
  Jira-backed tracker adapter.
  """

  @behaviour OdysseyElixir.Tracker

  alias OdysseyElixir.Jira.Client

  @spec fetch_candidate_issues() :: {:ok, [term()]} | {:error, term()}
  def fetch_candidate_issues, do: Client.fetch_candidate_issues()

  @spec fetch_issues_by_states([String.t()]) :: {:ok, [term()]} | {:error, term()}
  def fetch_issues_by_states(states), do: Client.fetch_issues_by_states(states)

  @spec fetch_issue_states_by_ids([String.t()]) :: {:ok, [term()]} | {:error, term()}
  def fetch_issue_states_by_ids(issue_ids), do: Client.fetch_issue_states_by_ids(issue_ids)

  @spec create_comment(String.t(), String.t()) :: :ok | {:error, term()}
  def create_comment(issue_id, body) when is_binary(issue_id) and is_binary(body) do
    adf_body = %{
      "body" => %{
        "type" => "doc",
        "version" => 1,
        "content" => [
          %{
            "type" => "paragraph",
            "content" => [%{"type" => "text", "text" => body}]
          }
        ]
      }
    }

    case Client.rest_api("POST", "/rest/api/3/issue/#{issue_id}/comment", adf_body) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @spec update_issue_state(String.t(), String.t()) :: :ok | {:error, term()}
  def update_issue_state(issue_id, state_name)
      when is_binary(issue_id) and is_binary(state_name) do
    with {:ok, transition_id} <- find_transition(issue_id, state_name) do
      case Client.rest_api("POST", "/rest/api/3/issue/#{issue_id}/transitions", %{
             "transition" => %{"id" => transition_id}
           }) do
        {:ok, _} -> :ok
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp find_transition(issue_id, state_name) do
    case Client.rest_api("GET", "/rest/api/3/issue/#{issue_id}/transitions") do
      {:ok, %{"transitions" => transitions}} ->
        target = String.downcase(state_name)

        case Enum.find(transitions, fn t ->
               String.downcase(t["name"] || "") == target ||
                 String.downcase(get_in(t, ["to", "name"]) || "") == target
             end) do
          nil -> {:error, {:transition_not_found, state_name}}
          transition -> {:ok, transition["id"]}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end
end
