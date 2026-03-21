defmodule OdysseyElixirWeb.TmuxLive do
  @moduledoc """
  Split-pane view showing all running agents' chat streams simultaneously.
  """

  use Phoenix.LiveView, layout: {OdysseyElixirWeb.Layouts, :app}

  alias OdysseyElixir.{EventStore, StatusDashboard}
  alias OdysseyElixirWeb.{Endpoint, ObservabilityPubSub, Presenter}

  @runtime_tick_ms 1_000

  @hidden_methods MapSet.new([
                    "thread/tokenUsage/updated",
                    "account/rateLimits/updated",
                    "account/updated",
                    "account/chatgptAuthTokens/refresh"
                  ])

  @delta_methods MapSet.new([
                   "item/agentMessage/delta",
                   "item/reasoning/textDelta",
                   "item/reasoning/summaryTextDelta",
                   "item/reasoning/summaryPartAdded",
                   "item/commandExecution/outputDelta",
                   "item/fileChange/outputDelta",
                   "item/plan/delta"
                 ])

  @impl true
  def mount(_params, _session, socket) do
    payload = load_payload()
    agents = agents_from_payload(payload)

    socket =
      socket
      |> assign(:payload, payload)
      |> assign(:agents, agents)
      |> assign(:panes, build_panes(agents))
      |> assign(:now, DateTime.utc_now())

    if connected?(socket) do
      :ok = ObservabilityPubSub.subscribe()
      Enum.each(agents, fn a -> EventStore.subscribe(a.issue_id) end)
      schedule_runtime_tick()
    end

    {:ok, socket}
  end

  @impl true
  def handle_info(:observability_updated, socket) do
    payload = load_payload()
    new_agents = agents_from_payload(payload)
    old_ids = MapSet.new(socket.assigns.agents, & &1.issue_id)
    new_ids = MapSet.new(new_agents, & &1.issue_id)

    if connected?(socket) do
      new_ids |> MapSet.difference(old_ids) |> Enum.each(&EventStore.subscribe/1)
    end

    panes = sync_panes(socket.assigns.panes, new_agents)

    {:noreply,
     socket
     |> assign(:payload, payload)
     |> assign(:agents, new_agents)
     |> assign(:panes, panes)
     |> assign(:now, DateTime.utc_now())}
  end

  def handle_info({:agent_event, issue_id, event}, socket) do
    panes = update_pane(socket.assigns.panes, issue_id, event)
    {:noreply, assign(socket, :panes, panes)}
  end

  def handle_info(:runtime_tick, socket) do
    schedule_runtime_tick()
    {:noreply, assign(socket, :now, DateTime.utc_now())}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <div class="tmux-shell">
      <header class="tmux-topbar">
        <a href="/" class="chat-back">&larr; Dashboard</a>
        <span class="tmux-title">Agent Streams</span>
        <span class="chat-meta numeric"><%= length(@agents) %> active</span>
      </header>

      <%= if @agents == [] do %>
        <div class="chat-empty">
          <p>No running agents.</p>
          <a href="/" class="chat-back-link">&larr; Back to dashboard</a>
        </div>
      <% else %>
        <div class={"tmux-grid tmux-grid-#{grid_cols(length(@agents))}"}>
          <div :for={pane <- @panes} class="tmux-pane" id={"pane-#{pane.issue_id}"}>
            <div class="tmux-pane-header">
              <a href={"/issues/#{pane.identifier}"} class="tmux-pane-id"><%= pane.identifier %></a>
              <span class={pane_state_class(pane.state)}><%= pane.state %></span>
              <span class="tmux-pane-meta numeric"><%= format_tokens(pane.tokens) %> tok</span>
            </div>
            <div class="tmux-pane-stream" id={"pane-stream-#{pane.issue_id}"} phx-hook="TmuxScroll">
              <div :for={{item, idx} <- Enum.with_index(pane.items)} class={pane_item_class(item)} id={"pane-#{pane.issue_id}-#{idx}"}>
                <%= render_pane_item(item) %>
              </div>
              <%= if pane.items == [] do %>
                <span class="tmux-pane-waiting">Waiting...</span>
              <% end %>
            </div>
          </div>
        </div>
      <% end %>
    </div>

    <script>
      if (!window.Hooks) window.Hooks = {};
      window.Hooks.TmuxScroll = {
        mounted() { this.scrollToBottom(); },
        updated() { this.scrollToBottom(); },
        scrollToBottom() { this.el.scrollTop = this.el.scrollHeight; }
      };
      (function() {
        if (window.__tmuxHooksInstalled) return;
        window.__tmuxHooksInstalled = true;
        window.addEventListener("DOMContentLoaded", function() {
          if (!window.Phoenix || !window.LiveView) return;
          if (window.liveSocket) { window.liveSocket.disconnect(); }
          var csrfToken = document.querySelector("meta[name='csrf-token']")?.getAttribute("content");
          var liveSocket = new window.LiveView.LiveSocket("/live", window.Phoenix.Socket, {
            hooks: window.Hooks,
            params: {_csrf_token: csrfToken}
          });
          liveSocket.connect();
          window.liveSocket = liveSocket;
        });
      })();
    </script>
    """
  end

  defp render_pane_item(%{type: :message} = item) do
    assigns = %{item: item}

    ~H"""
    <div class="tmux-item-text"><%= @item.text %></div>
    """
  end

  defp render_pane_item(%{type: :reasoning} = item) do
    assigns = %{item: item}

    ~H"""
    <div class="tmux-item-reasoning"><%= truncate_text(@item.text, 200) %></div>
    """
  end

  defp render_pane_item(%{type: :command} = item) do
    assigns = %{item: item}

    ~H"""
    <pre class="tmux-item-command"><%= truncate_text(@item.text, 150) %></pre>
    """
  end

  defp render_pane_item(%{type: :system} = item) do
    assigns = %{item: item}

    ~H"""
    <div class="tmux-item-system"><%= @item.text %></div>
    """
  end

  defp render_pane_item(item) do
    assigns = %{item: item}

    ~H"""
    <div class="tmux-item-event"><%= @item.text %></div>
    """
  end

  # ── Pane management ──

  defp agents_from_payload(payload) do
    case payload do
      %{running: running} when is_list(running) ->
        Enum.map(running, fn entry ->
          %{
            issue_id: entry.issue_id,
            identifier: entry.issue_identifier,
            state: entry.state,
            tokens: entry.tokens.total_tokens
          }
        end)

      _ ->
        []
    end
  end

  defp build_panes(agents) do
    Enum.map(agents, fn agent ->
      events = EventStore.events(agent.issue_id)

      %{
        issue_id: agent.issue_id,
        identifier: agent.identifier,
        state: agent.state,
        tokens: agent.tokens,
        items: build_items(events)
      }
    end)
  end

  defp sync_panes(old_panes, new_agents) do
    old_map = Map.new(old_panes, &{&1.issue_id, &1})

    Enum.map(new_agents, fn agent ->
      case Map.get(old_map, agent.issue_id) do
        nil ->
          events = EventStore.events(agent.issue_id)
          %{issue_id: agent.issue_id, identifier: agent.identifier, state: agent.state, tokens: agent.tokens, items: build_items(events)}

        existing ->
          %{existing | state: agent.state, tokens: agent.tokens}
      end
    end)
  end

  defp update_pane(panes, issue_id, event) do
    Enum.map(panes, fn pane ->
      if pane.issue_id == issue_id do
        %{pane | items: append_event(pane.items, event)}
      else
        pane
      end
    end)
  end

  # ── Event processing (same logic as ChatLive) ──

  defp build_items(events) do
    Enum.reduce(events, [], fn event, items -> append_event(items, event) end)
  end

  defp append_event(items, event) do
    method = extract_method(event)

    cond do
      MapSet.member?(@hidden_methods, method) -> items
      MapSet.member?(@delta_methods, method) -> merge_delta(items, event, method)
      true -> items ++ [classify_event(event, method)]
    end
  end

  defp merge_delta(items, event, method) do
    delta_text = extract_delta_text(event)

    if delta_text == "" do
      items
    else
      type = delta_type(method)

      case List.last(items) do
        %{type: ^type, open: true} = last ->
          List.replace_at(items, -1, %{last | text: last.text <> delta_text})

        _ ->
          items ++ [%{type: type, text: delta_text, time: event_time(event), open: true}]
      end
    end
  end

  defp classify_event(event, "item/started"), do: classify_item_started(event)
  defp classify_event(event, "item/completed"), do: classify_item_completed(event)
  defp classify_event(event, "item/commandExecution/requestApproval"), do: %{type: :command, text: extract_command_text(event) || "command", time: event_time(event)}
  defp classify_event(event, "item/fileChange/requestApproval"), do: %{type: :system, text: "file change", time: event_time(event)}
  defp classify_event(event, "item/tool/call"), do: %{type: :system, text: "tool: #{extract_tool_name(event)}", time: event_time(event)}
  defp classify_event(event, "turn/completed"), do: %{type: :system, text: "Turn completed", time: event_time(event)}
  defp classify_event(event, "turn/failed"), do: %{type: :system, text: "Turn failed", time: event_time(event)}
  defp classify_event(event, "turn/started"), do: %{type: :system, text: "Turn started", time: event_time(event)}

  defp classify_event(event, _method) do
    text = StatusDashboard.humanize_codex_message(event)
    %{type: :event, text: text, time: event_time(event)}
  end

  defp classify_item_started(event) do
    case extract_item_type(event) do
      "reasoning" -> %{type: :reasoning, text: "", time: event_time(event), open: true}
      "message" -> %{type: :message, text: "", time: event_time(event), open: true}
      other -> %{type: :system, text: "#{other || "item"} started", time: event_time(event)}
    end
  end

  defp classify_item_completed(event) do
    item_type = extract_item_type(event)
    status = extract_item_status(event)
    suffix = if status, do: " (#{status})", else: ""
    %{type: :system, text: "#{item_type || "item"} completed#{suffix}", time: event_time(event)}
  end

  # ── Payload extraction ──

  defp extract_method(event) do
    payload = event[:payload]

    cond do
      is_map(payload) -> Map.get(payload, "method") || Map.get(payload, :method)
      is_binary(event[:raw]) -> extract_method_from_raw(event[:raw])
      true -> nil
    end
  end

  defp extract_method_from_raw(raw) do
    case Jason.decode(raw) do
      {:ok, %{"method" => method}} -> method
      _ -> nil
    end
  end

  defp extract_delta_text(event) do
    payload = event[:payload] || decode_raw(event[:raw])
    params = map_get_any(payload, ["params", :params]) || %{}

    map_get_any(params, ["delta", :delta]) ||
      map_get_any(params, ["textDelta", :textDelta]) ||
      map_get_any(params, ["summaryTextDelta", :summaryTextDelta]) ||
      map_get_any(params, ["outputDelta", :outputDelta]) ||
      ""
  end

  defp extract_item_type(event) do
    payload = event[:payload] || decode_raw(event[:raw])
    params = map_get_any(payload, ["params", :params]) || %{}
    item = map_get_any(params, ["item", :item]) || map_get_any(params, ["msg", :msg]) || %{}
    map_get_any(item, ["type", :type])
  end

  defp extract_item_status(event) do
    payload = event[:payload] || decode_raw(event[:raw])
    params = map_get_any(payload, ["params", :params]) || %{}
    item = map_get_any(params, ["item", :item]) || %{}
    map_get_any(item, ["status", :status])
  end

  defp extract_command_text(event) do
    payload = event[:payload] || decode_raw(event[:raw])
    params = map_get_any(payload, ["params", :params]) || %{}
    map_get_any(params, ["command", :command])
  end

  defp extract_tool_name(event) do
    payload = event[:payload] || decode_raw(event[:raw])
    params = map_get_any(payload, ["params", :params]) || %{}
    map_get_any(params, ["tool", :tool]) || map_get_any(params, ["name", :name])
  end

  defp decode_raw(nil), do: %{}

  defp decode_raw(raw) when is_binary(raw) do
    case Jason.decode(raw) do
      {:ok, m} -> m
      _ -> %{}
    end
  end

  defp decode_raw(m) when is_map(m), do: m

  defp map_get_any(nil, _keys), do: nil
  defp map_get_any(map, keys) when is_map(map), do: Enum.find_value(keys, fn k -> Map.get(map, k) end)
  defp map_get_any(_map, _keys), do: nil

  defp delta_type("item/agentMessage/delta"), do: :message
  defp delta_type("item/reasoning/textDelta"), do: :reasoning
  defp delta_type("item/reasoning/summaryTextDelta"), do: :reasoning
  defp delta_type("item/reasoning/summaryPartAdded"), do: :reasoning
  defp delta_type("item/commandExecution/outputDelta"), do: :command
  defp delta_type("item/fileChange/outputDelta"), do: :system
  defp delta_type("item/plan/delta"), do: :message
  defp delta_type(_), do: :message

  defp event_time(event), do: format_event_time(event[:timestamp])

  # ── Display helpers ──

  defp grid_cols(n) when n <= 1, do: "1"
  defp grid_cols(n) when n <= 2, do: "2"
  defp grid_cols(n) when n <= 4, do: "2"
  defp grid_cols(n) when n <= 6, do: "3"
  defp grid_cols(_n), do: "4"

  defp pane_state_class(state) do
    normalized = state |> to_string() |> String.downcase()

    cond do
      String.contains?(normalized, ["progress", "running", "active"]) -> "tmux-state tmux-state-active"
      String.contains?(normalized, ["blocked", "error", "failed"]) -> "tmux-state tmux-state-danger"
      true -> "tmux-state"
    end
  end

  defp pane_item_class(%{type: :message}), do: "tmux-item tmux-msg"
  defp pane_item_class(%{type: :reasoning}), do: "tmux-item tmux-reason"
  defp pane_item_class(%{type: :command}), do: "tmux-item tmux-cmd"
  defp pane_item_class(%{type: :system}), do: "tmux-item tmux-sys"
  defp pane_item_class(_), do: "tmux-item"

  defp format_tokens(n) when is_integer(n) and n >= 1_000_000, do: "#{Float.round(n / 1_000_000, 1)}M"
  defp format_tokens(n) when is_integer(n) and n >= 1_000, do: "#{div(n, 1_000)}k"
  defp format_tokens(n) when is_integer(n), do: "#{n}"
  defp format_tokens(_), do: "0"

  defp truncate_text(text, max) when is_binary(text) and byte_size(text) > max, do: String.slice(text, 0, max) <> "..."
  defp truncate_text(text, _max), do: text

  defp format_event_time(%DateTime{} = dt), do: dt |> DateTime.truncate(:second) |> Calendar.strftime("%H:%M:%S")
  defp format_event_time(_), do: ""

  defp load_payload, do: Presenter.state_payload(orchestrator(), snapshot_timeout_ms())
  defp orchestrator, do: Endpoint.config(:orchestrator) || OdysseyElixir.Orchestrator
  defp snapshot_timeout_ms, do: Endpoint.config(:snapshot_timeout_ms) || 15_000
  defp schedule_runtime_tick, do: Process.send_after(self(), :runtime_tick, @runtime_tick_ms)
end
