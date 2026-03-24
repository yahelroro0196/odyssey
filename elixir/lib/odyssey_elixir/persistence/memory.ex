defmodule OdysseyElixir.Persistence.Memory do
  def record_session_start(_attrs), do: :ok
  def record_session_end(_id, _attrs), do: :ok
  def record_token_delta(_issue_id, _session_id, _delta), do: :ok
  def save_retry_queue(_retry_attempts), do: :ok
  def load_retry_queue, do: %{}
  def clear_retry_queue, do: :ok
  def issue_token_total(_issue_id), do: %{input_tokens: 0, output_tokens: 0, total_tokens: 0, session_count: 0}
  def daily_token_total(_date), do: %{input_tokens: 0, output_tokens: 0, total_tokens: 0, session_count: 0}
  def weekly_token_total, do: %{input_tokens: 0, output_tokens: 0, total_tokens: 0, session_count: 0}
  def global_totals, do: %{input_tokens: 0, output_tokens: 0, total_tokens: 0, session_count: 0}
  def persist_event(_issue_id, _event), do: :ok
end
