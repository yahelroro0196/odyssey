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

    case slack_webhook_url() do
      nil -> :ok
      url -> send_slack(url, issue_identifier, event)
    end

    :ok
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

  defp send_slack(url, issue_identifier, event) do
    emoji = slack_emoji(event)
    payload = %{text: "#{emoji} [#{issue_identifier}] #{event}"}

    Task.start(fn ->
      case Req.post(url, json: payload, receive_timeout: 10_000) do
        {:ok, %{status: status}} when status in 200..299 ->
          :ok

        {:ok, %{status: status}} ->
          Logger.warning("Slack webhook returned status=#{status} event=#{event}")

        {:error, reason} ->
          Logger.warning("Slack webhook failed event=#{event} reason=#{inspect(reason)}")
      end
    end)

    :ok
  end

  defp slack_emoji(:completed), do: ":white_check_mark:"
  defp slack_emoji(:failed), do: ":x:"
  defp slack_emoji(:budget_exceeded), do: ":warning:"
  defp slack_emoji(:budget_warning), do: ":warning:"
  defp slack_emoji(:approval_requested), do: ":hourglass_flowing_sand:"
  defp slack_emoji(:approval_approved), do: ":white_check_mark:"
  defp slack_emoji(:approval_rejected), do: ":no_entry_sign:"
  defp slack_emoji(:approval_timeout), do: ":alarm_clock:"
  defp slack_emoji(_event), do: ":information_source:"

  defp webhook_url do
    case Config.settings!() do
      %{notifications: %{webhook_url: url}} when is_binary(url) and url != "" -> url
      _ -> nil
    end
  rescue
    _ -> nil
  end

  defp slack_webhook_url do
    case Config.settings!() do
      %{notifications: %{slack_webhook_url: url}} when is_binary(url) and url != "" -> url
      _ -> nil
    end
  rescue
    _ -> nil
  end
end
