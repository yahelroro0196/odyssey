defmodule OdysseyElixir.EventStore do
  @moduledoc """
  Accumulates per-agent Codex events in an ETS-backed ring buffer.

  Each running agent (keyed by `issue_id`) gets a bounded event list.
  LiveView consumers subscribe to per-agent PubSub topics for real-time streaming.
  """

  use GenServer

  @pubsub OdysseyElixir.PubSub
  @table :odyssey_event_store
  @max_events_per_agent 500

  @type event :: map()

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @spec push(String.t(), event()) :: :ok
  def push(issue_id, event) when is_binary(issue_id) do
    GenServer.call(__MODULE__, {:push, issue_id, event})
  end

  @spec events(String.t()) :: [event()]
  def events(issue_id) when is_binary(issue_id) do
    @table
    |> :ets.select([{{{issue_id, :_}, :_}, [], [:"$_"]}])
    |> Enum.sort_by(fn {{_id, counter}, _event} -> counter end)
    |> Enum.map(fn {_key, event} -> event end)
  end

  @spec clear(String.t()) :: :ok
  def clear(issue_id) when is_binary(issue_id) do
    GenServer.call(__MODULE__, {:clear, issue_id})
  end

  @spec subscribe(String.t()) :: :ok | {:error, term()}
  def subscribe(issue_id) when is_binary(issue_id) do
    Phoenix.PubSub.subscribe(@pubsub, topic(issue_id))
  end

  # --- GenServer callbacks ---

  @impl true
  def init(_opts) do
    :ets.new(@table, [:named_table, :ordered_set, :public, read_concurrency: true])
    {:ok, %{counters: %{}}}
  end

  @impl true
  def handle_call({:push, issue_id, event}, _from, state) do
    counter = Map.get(state.counters, issue_id, 0)
    :ets.insert(@table, {{issue_id, counter}, event})

    state = %{state | counters: Map.put(state.counters, issue_id, counter + 1)}
    state = maybe_evict(state, issue_id)

    broadcast_event(issue_id, event)
    Task.start(fn -> OdysseyElixir.Persistence.persist_event(issue_id, event) end)
    {:reply, :ok, state}
  end

  def handle_call({:clear, issue_id}, _from, state) do
    :ets.select_delete(@table, [{{{issue_id, :_}, :_}, [], [true]}])
    {:reply, :ok, %{state | counters: Map.delete(state.counters, issue_id)}}
  end

  # --- Private ---

  defp maybe_evict(state, issue_id) do
    events = :ets.select(@table, [{{{issue_id, :_}, :_}, [], [:"$_"]}])

    if length(events) > @max_events_per_agent do
      sorted = Enum.sort_by(events, fn {{_id, counter}, _} -> counter end)
      to_delete = Enum.take(sorted, length(events) - @max_events_per_agent)
      Enum.each(to_delete, fn {key, _} -> :ets.delete(@table, key) end)
    end

    state
  end

  defp broadcast_event(issue_id, event) do
    case Process.whereis(@pubsub) do
      pid when is_pid(pid) ->
        Phoenix.PubSub.broadcast(@pubsub, topic(issue_id), {:agent_event, issue_id, event})

      _ ->
        :ok
    end
  end

  defp topic(issue_id), do: "agent_events:#{issue_id}"
end
