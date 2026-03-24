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

    repo_children = maybe_repo_children()

    children =
      [
        {Phoenix.PubSub, name: OdysseyElixir.PubSub},
        {Task.Supervisor, name: OdysseyElixir.TaskSupervisor},
        OdysseyElixir.WorkflowStore
      ] ++
        repo_children ++
        [
          OdysseyElixir.EventStore,
          OdysseyElixir.ApprovalStore,
          OdysseyElixir.MetricsReporter,
          OdysseyElixir.Orchestrator,
          OdysseyElixir.HttpServer,
          OdysseyElixir.StatusDashboard
        ]

    result =
      Supervisor.start_link(
        children,
        strategy: :one_for_one,
        name: OdysseyElixir.Supervisor
      )

    if persistence_mode() == "sqlite" do
      OdysseyElixir.Persistence.Migrator.migrate()
    end

    result
  end

  defp maybe_repo_children do
    case persistence_mode() do
      "sqlite" -> [OdysseyElixir.Repo]
      _ -> []
    end
  end

  defp persistence_mode do
    case OdysseyElixir.Config.settings() do
      {:ok, settings} -> settings.persistence.mode
      _ -> "memory"
    end
  end

  @impl true
  def stop(_state) do
    OdysseyElixir.StatusDashboard.render_offline_status()
    :ok
  end
end
