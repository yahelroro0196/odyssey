defmodule OdysseyElixir.ApprovalStore do
  @moduledoc false

  use GenServer
  require Logger

  alias OdysseyElixir.{Config, Notifier}

  @pubsub OdysseyElixir.PubSub
  @topic "approvals:updates"

  defstruct pending: %{}, next_id: 1

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def request_approval(gate, issue, metadata) when gate in [:before_dispatch, :before_merge] do
    GenServer.call(__MODULE__, {:request, gate, issue, metadata})
  end

  def approve(approval_id) when is_integer(approval_id) do
    GenServer.call(__MODULE__, {:resolve, approval_id, :approved})
  end

  def reject(approval_id) when is_integer(approval_id) do
    GenServer.call(__MODULE__, {:resolve, approval_id, :rejected})
  end

  def list_pending do
    GenServer.call(__MODULE__, :list_pending)
  end

  @impl true
  def init(_opts) do
    {:ok, %__MODULE__{}}
  end

  @impl true
  def handle_call({:request, gate, issue, metadata}, _from, state) do
    id = state.next_id
    settings = Config.settings!()
    ag = Map.get(settings, :approval_gates) || %{}
    timeout_ms = Map.get(ag, :timeout_ms) || 600_000
    timeout_action = Map.get(ag, :timeout_action) || "approve"

    timer_ref = Process.send_after(self(), {:approval_timeout, id}, timeout_ms)

    approval = %{
      id: id,
      gate: gate,
      issue_id: issue.id,
      issue_identifier: issue.identifier,
      issue_title: issue.title,
      requested_at: DateTime.utc_now(),
      timeout_ms: timeout_ms,
      timeout_action: timeout_action,
      timeout_timer_ref: timer_ref,
      orchestrator_pid: Map.get(metadata, :orchestrator_pid),
      metadata: metadata
    }

    pending = Map.put(state.pending, id, approval)
    state = %{state | pending: pending, next_id: id + 1}

    broadcast_update()

    Notifier.notify(issue.identifier, :approval_requested, %{
      gate: gate,
      approval_id: id
    })

    {:reply, {:ok, id}, state}
  end

  @impl true
  def handle_call({:resolve, approval_id, decision}, _from, state) do
    case Map.pop(state.pending, approval_id) do
      {nil, _pending} ->
        {:reply, {:error, :not_found}, state}

      {approval, pending} ->
        Process.cancel_timer(approval.timeout_timer_ref)
        state = %{state | pending: pending}

        if is_pid(approval.orchestrator_pid) do
          send(approval.orchestrator_pid, {:approval_resolved, approval_id, decision, approval.metadata})
        end

        event =
          case decision do
            :approved -> :approval_approved
            :rejected -> :approval_rejected
          end

        Notifier.notify(approval.issue_identifier, event, %{
          gate: approval.gate,
          approval_id: approval_id
        })

        broadcast_update()
        {:reply, :ok, state}
    end
  end

  @impl true
  def handle_call(:list_pending, _from, state) do
    pending =
      state.pending
      |> Map.values()
      |> Enum.sort_by(& &1.requested_at, DateTime)

    {:reply, pending, state}
  end

  @impl true
  def handle_info({:approval_timeout, id}, state) do
    case Map.pop(state.pending, id) do
      {nil, _pending} ->
        {:noreply, state}

      {approval, pending} ->
        state = %{state | pending: pending}
        decision = if approval.timeout_action == "reject", do: :rejected, else: :approved

        Logger.info(
          "Approval timeout for id=#{id} gate=#{approval.gate} issue=#{approval.issue_identifier} action=#{decision}"
        )

        if is_pid(approval.orchestrator_pid) do
          send(approval.orchestrator_pid, {:approval_resolved, id, decision, approval.metadata})
        end

        Notifier.notify(approval.issue_identifier, :approval_timeout, %{
          gate: approval.gate,
          approval_id: id,
          decision: decision
        })

        broadcast_update()
        {:noreply, state}
    end
  end

  defp broadcast_update do
    case Process.whereis(@pubsub) do
      pid when is_pid(pid) ->
        Phoenix.PubSub.broadcast(@pubsub, @topic, {:approvals_updated})

      _ ->
        :ok
    end
  end
end
