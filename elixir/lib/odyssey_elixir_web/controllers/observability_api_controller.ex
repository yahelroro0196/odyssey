defmodule OdysseyElixirWeb.ObservabilityApiController do
  @moduledoc """
  JSON API for Odyssey observability data.
  """

  use Phoenix.Controller, formats: [:json]

  alias OdysseyElixirWeb.{Endpoint, Presenter}
  alias Plug.Conn

  @spec metrics(Conn.t(), map()) :: Conn.t()
  def metrics(conn, _params) do
    if prometheus_enabled?() do
      conn
      |> put_resp_content_type("text/plain")
      |> send_resp(200, OdysseyElixir.MetricsReporter.scrape())
    else
      error_response(conn, 404, "not_found", "Prometheus metrics not enabled")
    end
  end

  @spec state(Conn.t(), map()) :: Conn.t()
  def state(conn, _params) do
    json(conn, Presenter.state_payload(orchestrator(), snapshot_timeout_ms()))
  end

  @spec issue(Conn.t(), map()) :: Conn.t()
  def issue(conn, %{"issue_identifier" => issue_identifier}) do
    case Presenter.issue_payload(issue_identifier, orchestrator(), snapshot_timeout_ms()) do
      {:ok, payload} ->
        json(conn, payload)

      {:error, :issue_not_found} ->
        error_response(conn, 404, "issue_not_found", "Issue not found")
    end
  end

  @spec refresh(Conn.t(), map()) :: Conn.t()
  def refresh(conn, _params) do
    case Presenter.refresh_payload(orchestrator()) do
      {:ok, payload} ->
        conn
        |> put_status(202)
        |> json(payload)

      {:error, :unavailable} ->
        error_response(conn, 503, "orchestrator_unavailable", "Orchestrator is unavailable")
    end
  end

  @spec cancel(Conn.t(), map()) :: Conn.t()
  def cancel(conn, %{"issue_identifier" => issue_identifier}) do
    case OdysseyElixir.Orchestrator.cancel_issue(orchestrator(), issue_identifier) do
      :ok ->
        json(conn, %{status: "cancelled", issue_identifier: issue_identifier})

      {:error, :not_found} ->
        error_response(conn, 404, "issue_not_found", "Issue not found or not running")
    end
  end

  @spec reload(Conn.t(), map()) :: Conn.t()
  def reload(conn, _params) do
    {result, modules} = do_reload()
    json(conn, %{status: result, modules_reloaded: length(modules)})
  end

  defp do_reload do
    case IEx.Helpers.recompile() do
      {:recompiled, modules} -> {"reloaded", modules}
      _ -> {"no_changes", []}
    end
  rescue
    _ ->
      case Code.compile_file("mix.exs") do
        _ -> {"reloaded", []}
      end
  end

  @spec list_approvals(Conn.t(), map()) :: Conn.t()
  def list_approvals(conn, _params) do
    pending = OdysseyElixir.ApprovalStore.list_pending()

    approvals =
      Enum.map(pending, fn a ->
        %{
          id: a.id,
          gate: a.gate,
          issue_identifier: a.issue_identifier,
          issue_title: a.issue_title,
          requested_at: DateTime.to_iso8601(a.requested_at),
          timeout_ms: a.timeout_ms
        }
      end)

    json(conn, %{approvals: approvals})
  end

  @spec approve_gate(Conn.t(), map()) :: Conn.t()
  def approve_gate(conn, %{"approval_id" => approval_id}) do
    case OdysseyElixir.ApprovalStore.approve(String.to_integer(approval_id)) do
      :ok -> json(conn, %{status: "approved", approval_id: String.to_integer(approval_id)})
      {:error, :not_found} -> error_response(conn, 404, "not_found", "Approval not found")
    end
  end

  @spec reject_gate(Conn.t(), map()) :: Conn.t()
  def reject_gate(conn, %{"approval_id" => approval_id}) do
    case OdysseyElixir.ApprovalStore.reject(String.to_integer(approval_id)) do
      :ok -> json(conn, %{status: "rejected", approval_id: String.to_integer(approval_id)})
      {:error, :not_found} -> error_response(conn, 404, "not_found", "Approval not found")
    end
  end

  @spec method_not_allowed(Conn.t(), map()) :: Conn.t()
  def method_not_allowed(conn, _params) do
    error_response(conn, 405, "method_not_allowed", "Method not allowed")
  end

  @spec not_found(Conn.t(), map()) :: Conn.t()
  def not_found(conn, _params) do
    error_response(conn, 404, "not_found", "Route not found")
  end

  defp error_response(conn, status, code, message) do
    conn
    |> put_status(status)
    |> json(%{error: %{code: code, message: message}})
  end

  defp orchestrator do
    Endpoint.config(:orchestrator) || OdysseyElixir.Orchestrator
  end

  defp snapshot_timeout_ms do
    Endpoint.config(:snapshot_timeout_ms) || 15_000
  end

  defp prometheus_enabled? do
    case OdysseyElixir.Config.settings!() do
      %{observability: %{prometheus_enabled: true}} -> true
      _ -> false
    end
  rescue
    _ -> false
  end
end
