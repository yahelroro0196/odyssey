defmodule OdysseyElixir do
  @moduledoc """
  Entry point for the Odyssey orchestrator.
  """

  @doc """
  Start the orchestrator in the current BEAM node.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    OdysseyElixir.Orchestrator.start_link(opts)
  end
end

defmodule OdysseyElixir.Application do
  @moduledoc """
  OTP application entrypoint that starts core supervisors and workers.
  """

  use Application

  @impl true
  def start(_type, _args) do
    :ok = OdysseyElixir.LogFile.configure()

    children = [
      {Phoenix.PubSub, name: OdysseyElixir.PubSub},
      {Task.Supervisor, name: OdysseyElixir.TaskSupervisor},
      OdysseyElixir.WorkflowStore,
      OdysseyElixir.EventStore,
      OdysseyElixir.Orchestrator,
      OdysseyElixir.HttpServer,
      OdysseyElixir.StatusDashboard
    ]

    Supervisor.start_link(
      children,
      strategy: :one_for_one,
      name: OdysseyElixir.Supervisor
    )
  end

  @impl true
  def stop(_state) do
    OdysseyElixir.StatusDashboard.render_offline_status()
    :ok
  end
end
