defmodule OdysseyElixir.Persistence do
  alias OdysseyElixir.Persistence.{Memory, SQLite}

  defp backend do
    case OdysseyElixir.Config.settings!().persistence.mode do
      "sqlite" -> SQLite
      _ -> Memory
    end
  end

  def record_session_start(attrs), do: backend().record_session_start(attrs)
  def record_session_end(id, attrs), do: backend().record_session_end(id, attrs)
  def record_token_delta(issue_id, session_id, delta), do: backend().record_token_delta(issue_id, session_id, delta)
  def save_retry_queue(retry_attempts), do: backend().save_retry_queue(retry_attempts)
  def load_retry_queue, do: backend().load_retry_queue()
  def clear_retry_queue, do: backend().clear_retry_queue()
  def issue_token_total(issue_id), do: backend().issue_token_total(issue_id)
  def daily_token_total(date), do: backend().daily_token_total(date)
  def weekly_token_total, do: backend().weekly_token_total()
  def global_totals, do: backend().global_totals()
  def persist_event(issue_id, event), do: backend().persist_event(issue_id, event)

  def sqlite?, do: OdysseyElixir.Config.settings!().persistence.mode == "sqlite"
end
