defmodule Mix.Tasks.Odyssey.Run do
  @shortdoc "Start Odyssey with hot code reloading support"
  @moduledoc """
  Starts Odyssey using the Mix project (not escript), enabling hot code reloading.

  Usage: mix odyssey.run [--port <N>] [--logs-root <path>] [path-to-WORKFLOW.md]

  The `--i-understand-that-this-will-be-running-without-the-usual-guardrails`
  flag is automatically set when running via this task.
  """

  use Mix.Task

  @impl true
  def run(args) do
    full_args = ["--i-understand-that-this-will-be-running-without-the-usual-guardrails" | args]

    case OdysseyElixir.CLI.evaluate(full_args) do
      :ok ->
        Mix.shell().info("Odyssey started (hot-reloadable mode)")
        Process.sleep(:infinity)

      {:error, message} ->
        Mix.shell().error(message)
        exit({:shutdown, 1})
    end
  end
end
