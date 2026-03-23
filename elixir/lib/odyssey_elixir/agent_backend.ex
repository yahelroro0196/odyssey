defmodule OdysseyElixir.AgentBackend do
  @moduledoc """
  Behaviour for agent runtime backends (Codex, Claude Code, etc.).
  """

  @type session :: map()

  @callback start_session(Path.t(), keyword()) :: {:ok, session()} | {:error, term()}
  @callback run_turn(session(), String.t(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  @callback stop_session(session()) :: :ok
end
