defmodule OdysseyElixir.Persistence.SQLite do
  import Ecto.Query

  alias OdysseyElixir.Repo
  alias OdysseyElixir.Persistence.Schemas.{Session, IssueTokenTotal, DailyTokenTotal, RetrySnapshot, Event}

  def record_session_start(attrs) when is_map(attrs) do
    %Session{}
    |> Session.changeset(Map.put(attrs, :status, "running"))
    |> Repo.insert(on_conflict: :nothing)

    :ok
  end

  def record_session_end(session_id, attrs) when is_binary(session_id) and is_map(attrs) do
    case Repo.get(Session, session_id) do
      nil -> :ok
      session ->
        session
        |> Session.changeset(Map.merge(attrs, %{finished_at: DateTime.utc_now()}))
        |> Repo.update()

        upsert_issue_token_total(session.issue_id, session)
        upsert_daily_token_total(session)
        :ok
    end
  end

  def record_token_delta(issue_id, session_id, delta)
      when is_binary(issue_id) and is_map(delta) do
    case Repo.get(Session, session_id || "") do
      nil -> :ok
      session ->
        session
        |> Session.changeset(%{
          input_tokens: session.input_tokens + Map.get(delta, :input_tokens, 0),
          output_tokens: session.output_tokens + Map.get(delta, :output_tokens, 0),
          total_tokens: session.total_tokens + Map.get(delta, :total_tokens, 0)
        })
        |> Repo.update()

        :ok
    end
  end

  def save_retry_queue(retry_attempts) when is_map(retry_attempts) do
    Repo.delete_all(RetrySnapshot)

    Enum.each(retry_attempts, fn {issue_id, entry} ->
      %RetrySnapshot{}
      |> RetrySnapshot.changeset(%{
        issue_id: issue_id,
        attempt: Map.get(entry, :attempt, 0),
        error: Map.get(entry, :error),
        worker_host: Map.get(entry, :worker_host),
        workspace_path: Map.get(entry, :workspace_path)
      })
      |> Repo.insert(on_conflict: :replace_all, conflict_target: :issue_id)
    end)

    :ok
  end

  def load_retry_queue do
    RetrySnapshot
    |> Repo.all()
    |> Enum.reduce(%{}, fn snapshot, acc ->
      Map.put(acc, snapshot.issue_id, %{
        attempt: snapshot.attempt,
        error: snapshot.error,
        worker_host: snapshot.worker_host,
        workspace_path: snapshot.workspace_path
      })
    end)
  end

  def clear_retry_queue do
    Repo.delete_all(RetrySnapshot)
    :ok
  end

  def issue_token_total(issue_id) when is_binary(issue_id) do
    case Repo.get(IssueTokenTotal, issue_id) do
      nil -> %{input_tokens: 0, output_tokens: 0, total_tokens: 0, session_count: 0}
      row -> %{input_tokens: row.input_tokens, output_tokens: row.output_tokens, total_tokens: row.total_tokens, session_count: row.session_count}
    end
  end

  def daily_token_total(date) do
    case Repo.get(DailyTokenTotal, date) do
      nil -> %{input_tokens: 0, output_tokens: 0, total_tokens: 0, session_count: 0}
      row -> %{input_tokens: row.input_tokens, output_tokens: row.output_tokens, total_tokens: row.total_tokens, session_count: row.session_count}
    end
  end

  def weekly_token_total do
    week_ago = Date.add(Date.utc_today(), -7)

    result =
      from(d in DailyTokenTotal,
        where: d.date >= ^week_ago,
        select: %{
          input_tokens: coalesce(sum(d.input_tokens), 0),
          output_tokens: coalesce(sum(d.output_tokens), 0),
          total_tokens: coalesce(sum(d.total_tokens), 0),
          session_count: coalesce(sum(d.session_count), 0)
        }
      )
      |> Repo.one()

    result || %{input_tokens: 0, output_tokens: 0, total_tokens: 0, session_count: 0}
  end

  def global_totals do
    result =
      from(s in Session,
        select: %{
          input_tokens: coalesce(sum(s.input_tokens), 0),
          output_tokens: coalesce(sum(s.output_tokens), 0),
          total_tokens: coalesce(sum(s.total_tokens), 0),
          session_count: count(s.id)
        }
      )
      |> Repo.one()

    result || %{input_tokens: 0, output_tokens: 0, total_tokens: 0, session_count: 0}
  end

  def persist_event(issue_id, event) when is_binary(issue_id) do
    event_type =
      case event do
        %{event: type} -> to_string(type)
        _ -> "unknown"
      end

    payload =
      case Jason.encode(event) do
        {:ok, _} -> event
        _ -> %{raw: inspect(event)}
      end

    %Event{}
    |> Event.changeset(%{
      issue_id: issue_id,
      event_type: event_type,
      payload: payload,
      inserted_at: DateTime.utc_now()
    })
    |> Repo.insert()

    :ok
  end

  defp upsert_issue_token_total(issue_id, session) do
    case Repo.get(IssueTokenTotal, issue_id) do
      nil ->
        %IssueTokenTotal{}
        |> IssueTokenTotal.changeset(%{
          issue_id: issue_id,
          input_tokens: session.input_tokens,
          output_tokens: session.output_tokens,
          total_tokens: session.total_tokens,
          session_count: 1
        })
        |> Repo.insert(on_conflict: :nothing)

      existing ->
        existing
        |> IssueTokenTotal.changeset(%{
          input_tokens: existing.input_tokens + session.input_tokens,
          output_tokens: existing.output_tokens + session.output_tokens,
          total_tokens: existing.total_tokens + session.total_tokens,
          session_count: existing.session_count + 1
        })
        |> Repo.update()
    end
  end

  defp upsert_daily_token_total(session) do
    today = Date.utc_today()

    case Repo.get(DailyTokenTotal, today) do
      nil ->
        %DailyTokenTotal{}
        |> DailyTokenTotal.changeset(%{
          date: today,
          input_tokens: session.input_tokens,
          output_tokens: session.output_tokens,
          total_tokens: session.total_tokens,
          session_count: 1
        })
        |> Repo.insert(on_conflict: :nothing)

      existing ->
        existing
        |> DailyTokenTotal.changeset(%{
          input_tokens: existing.input_tokens + session.input_tokens,
          output_tokens: existing.output_tokens + session.output_tokens,
          total_tokens: existing.total_tokens + session.total_tokens,
          session_count: existing.session_count + 1
        })
        |> Repo.update()
    end
  end
end
