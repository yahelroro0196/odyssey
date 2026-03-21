defmodule OdysseyElixir.Notifier do
  @moduledoc """
  Sends webhook notifications for agent lifecycle events.
  """

  require Logger

  alias OdysseyElixir.Config

  @spec notify(String.t(), atom(), map()) :: :ok
  def notify(issue_identifier, event, details \\ %{}) when is_binary(issue_identifier) and is_atom(event) do
    case webhook_url() do
      nil -> :ok
      url -> send_async(url, issue_identifier, event, details)
    end
  end

  defp send_async(url, issue_identifier, event, details) do
    payload = %{
      event: event,
      issue_identifier: issue_identifier,
      details: details,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    Task.start(fn ->
      case Req.post(url, json: payload, receive_timeout: 10_000) do
        {:ok, %{status: status}} when status in 200..299 ->
          :ok

        {:ok, %{status: status}} ->
          Logger.warning("Webhook returned status=#{status} url=#{url} event=#{event}")

        {:error, reason} ->
          Logger.warning("Webhook failed url=#{url} event=#{event} reason=#{inspect(reason)}")
      end
    end)

    :ok
  end

  defp webhook_url do
    case Config.settings!() do
      %{notifications: %{webhook_url: url}} when is_binary(url) and url != "" -> url
      _ -> nil
    end
  rescue
    _ -> nil
  end
end
