defmodule OdysseyElixirWeb.ChatLive do
  @moduledoc """
  Full-screen LiveView for viewing a running agent's event stream as a conversation.
  """

  use Phoenix.LiveView, layout: {OdysseyElixirWeb.Layouts, :app}

  alias OdysseyElixir.EventStore
  alias OdysseyElixirWeb.{Endpoint, ObservabilityPubSub, Presenter}

  @runtime_tick_ms 1_000

  # Methods that are noise — never shown
  @hidden_methods MapSet.new([
                    "thread/tokenUsage/updated",
                    "account/rateLimits/updated",
                    "account/updated",
                    "account/chatgptAuthTokens/refresh"
                  ])

  # Streaming delta methods — aggregated into the parent item
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
  def mount(%{"issue_identifier" => issue_identifier}, _session, socket) do
    socket =
      socket
      |> assign(:issue_identifier, issue_identifier)
      |> assign(:now, DateTime.utc_now())
      |> assign(:ended, false)

    case Presenter.find_running_by_identifier(issue_identifier, orchestrator(), snapshot_timeout_ms()) do
      {:ok, agent_info} ->
        issue_id = agent_info.issue_id

        if connected?(socket) do
          :ok = EventStore.subscribe(issue_id)
          :ok = ObservabilityPubSub.subscribe()
          schedule_runtime_tick()
        end

        raw_events = EventStore.events(issue_id)

        socket =
          socket
          |> assign(:issue_id, issue_id)
          |> assign(:agent_info, agent_info)
          |> assign(:items, build_items(raw_events))

        {:ok, socket}

      {:error, :not_found} ->
        socket =
          socket
          |> assign(:issue_id, nil)
          |> assign(:agent_info, nil)
          |> assign(:items, [])

        {:ok, socket}
    end
  end

  @impl true
  def handle_info({:agent_event, issue_id, event}, socket) do
    if socket.assigns.issue_id == issue_id do
      {:noreply, assign(socket, :items, append_event(socket.assigns.items, event))}
    else
      {:noreply, socket}
    end
  end

  def handle_info(:observability_updated, socket) do
    case socket.assigns.issue_id do
      nil ->
        {:noreply, socket}

      _issue_id ->
        case Presenter.find_running_by_identifier(
               socket.assigns.issue_identifier,
               orchestrator(),
               snapshot_timeout_ms()
             ) do
          {:ok, agent_info} ->
            {:noreply, assign(socket, :agent_info, agent_info)}

          {:error, :not_found} ->
            {:noreply, assign(socket, :ended, true)}
        end
    end
  end

  def handle_info(:runtime_tick, socket) do
    schedule_runtime_tick()
    {:noreply, assign(socket, :now, DateTime.utc_now())}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <div class="chat-shell">
      <header class="chat-header">
        <a href="/" class="chat-back">&larr; Dashboard</a>
        <div class="chat-header-info">
          <span class="chat-issue-id"><%= @issue_identifier %></span>
          <%= if @agent_info do %>
            <span class={state_badge_class(@agent_info.state)}>
              <%= @agent_info.state %>
            </span>
            <span class="chat-meta numeric">
              <%= format_runtime(@agent_info.started_at, @now) %>
            </span>
            <span class="chat-meta numeric">
              Tokens: <%= format_int(@agent_info.tokens.total_tokens) %>
            </span>
          <% end %>
          <%= if @ended do %>
            <span class="state-badge state-badge-danger">Ended</span>
          <% end %>
        </div>
      </header>

      <%= if is_nil(@agent_info) and not @ended do %>
        <div class="chat-empty">
          <p>No active session for <strong><%= @issue_identifier %></strong>.</p>
          <a href="/" class="chat-back-link">&larr; Back to dashboard</a>
        </div>
      <% else %>
        <%= if @ended do %>
          <div class="chat-ended-banner">Session has ended. Showing last known events.</div>
        <% end %>

        <div class="chat-stream" id="chat-stream" phx-hook="ChatScroll">
          <%= if @items == [] do %>
            <p class="chat-empty-events">Waiting for agent activity...</p>
          <% else %>
            <div :for={{item, idx} <- Enum.with_index(@items)} class={item_class(item)} id={"item-#{idx}"}>
              <%= render_item(item, assigns) %>
            </div>
          <% end %>
        </div>
      <% end %>
    </div>

    <script>
      if (!window.Hooks) window.Hooks = {};
      window.Hooks.ChatScroll = {
        mounted() { this.scrollToBottom(); },
        updated() { this.scrollToBottom(); },
        scrollToBottom() { this.el.scrollTop = this.el.scrollHeight; }
      };
      (function() {
        if (window.__chatHooksInstalled) return;
        window.__chatHooksInstalled = true;
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

  defp render_item(%{type: :message} = item, _assigns) do
    assigns = %{item: item}

    ~H"""
    <div class="chat-item-header">
      <span class="chat-item-role">Agent</span>
      <span class="chat-event-time mono numeric"><%= @item.time %></span>
    </div>
    <div class="chat-item-text"><%= @item.text %></div>
    """
  end

  defp render_item(%{type: :reasoning} = item, _assigns) do
    assigns = %{item: item}

    ~H"""
    <details class="chat-reasoning-details">
      <summary class="chat-reasoning-summary">
        <span class="chat-item-role-muted">Thinking</span>
        <span class="chat-event-time mono numeric"><%= @item.time %></span>
      </summary>
      <div class="chat-item-text chat-reasoning-text"><%= @item.text %></div>
    </details>
    """
  end

  defp render_item(%{type: :command} = item, _assigns) do
    assigns = %{item: item}

    ~H"""
    <div class="chat-item-header">
      <span class="chat-item-role-tool">Command</span>
      <span class="chat-event-time mono numeric"><%= @item.time %></span>
    </div>
    <pre class="chat-command-text"><%= @item.text %></pre>
    """
  end

  defp render_item(%{type: :tool_call} = item, _assigns) do
    assigns = %{item: item}

    ~H"""
    <div class="chat-item-header">
      <span class="chat-item-role-tool">Tool</span>
      <span class="chat-event-time mono numeric"><%= @item.time %></span>
    </div>
    <div class="chat-item-text"><%= @item.text %></div>
    """
  end

  defp render_item(%{type: :file_change} = item, _assigns) do
    assigns = %{item: item}

    ~H"""
    <div class="chat-item-header">
      <span class="chat-item-role-tool">File Change</span>
      <span class="chat-event-time mono numeric"><%= @item.time %></span>
    </div>
    <div class="chat-item-text"><%= @item.text %></div>
    """
  end

  defp render_item(%{type: :system} = item, _assigns) do
    assigns = %{item: item}

    ~H"""
    <div class="chat-item-system">
      <span class="chat-event-time mono numeric"><%= @item.time %></span>
      <span><%= @item.text %></span>
    </div>
    """
  end

  defp render_item(%{type: :event} = item, _assigns) do
    assigns = %{item: item}

    ~H"""
    <div class="chat-item-header">
      <span class={event_badge_class(@item.event_type)}>
        <%= @item.event_type || "event" %>
      </span>
      <span class="chat-event-time mono numeric"><%= @item.time %></span>
    </div>
    <div class="chat-item-text"><%= @item.text %></div>
    """
  end

  # ── Event processing: convert raw events into conversation items ──

  defp build_items(events) do
    events
    |> Enum.reduce([], fn event, items -> append_event(items, event) end)
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
          items ++ [%{type: type, text: delta_text, time: format_event_time(event[:timestamp]), open: true}]
      end
    end
  end

  defp classify_event(event, "item/started"), do: classify_item_started(event)
  defp classify_event(event, "item/completed"), do: classify_item_completed(event)
  defp classify_event(event, "item/commandExecution/requestApproval"), do: %{type: :command, text: extract_command_text(event) || "command execution", time: event_time(event)}
  defp classify_event(event, "item/fileChange/requestApproval"), do: %{type: :file_change, text: describe_file_change(event), time: event_time(event)}
  defp classify_event(event, "item/tool/call"), do: %{type: :tool_call, text: extract_tool_name(event) || "tool call", time: event_time(event)}
  defp classify_event(event, "turn/completed"), do: %{type: :system, text: "Turn completed", time: event_time(event)}
  defp classify_event(event, "turn/failed"), do: %{type: :system, text: "Turn failed", time: event_time(event)}
  defp classify_event(event, "turn/started"), do: %{type: :system, text: "Turn started", time: event_time(event)}
  defp classify_event(event, "turn/diff/updated"), do: %{type: :system, text: "Diff updated", time: event_time(event)}

  defp classify_event(event, _method) do
    text = OdysseyElixir.StatusDashboard.humanize_codex_message(event)
    %{type: :event, text: text, time: event_time(event), event_type: event[:event]}
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

  defp event_time(event), do: format_event_time(event[:timestamp])

  # ── Payload extraction helpers ──

  defp extract_method(event) do
    (is_binary(event[:raw]) && extract_method_from_raw(event[:raw])) ||
      extract_method_from_payload(event[:payload])
  end

  defp extract_method_from_raw(raw) do
    case Jason.decode(raw) do
      {:ok, %{"method" => method}} -> method
      _ -> nil
    end
  end

  defp extract_method_from_payload(payload) when is_map(payload) do
    Map.get(payload, "method") || Map.get(payload, :method)
  end

  defp extract_method_from_payload(_), do: nil

  defp parsed_event(event) do
    decode_raw(event[:raw]) || event[:payload] || %{}
  end

  defp extract_delta_text(event) do
    params = map_get_any(parsed_event(event), ["params", :params]) || %{}

    map_get_any(params, ["delta", :delta]) ||
      map_get_any(params, ["textDelta", :textDelta]) ||
      map_get_any(params, ["summaryTextDelta", :summaryTextDelta]) ||
      map_get_any(params, ["outputDelta", :outputDelta]) ||
      ""
  end

  defp extract_item_type(event) do
    params = map_get_any(parsed_event(event), ["params", :params]) || %{}
    item = map_get_any(params, ["item", :item]) || map_get_any(params, ["msg", :msg]) || %{}
    map_get_any(item, ["type", :type])
  end

  defp extract_item_status(event) do
    params = map_get_any(parsed_event(event), ["params", :params]) || %{}
    item = map_get_any(params, ["item", :item]) || %{}
    map_get_any(item, ["status", :status])
  end

  defp extract_command_text(event) do
    params = map_get_any(parsed_event(event), ["params", :params]) || %{}
    map_get_any(params, ["command", :command])
  end

  defp extract_tool_name(event) do
    params = map_get_any(parsed_event(event), ["params", :params]) || %{}
    map_get_any(params, ["tool", :tool]) || map_get_any(params, ["name", :name])
  end

  defp describe_file_change(event) do
    params = map_get_any(parsed_event(event), ["params", :params]) || %{}
    count = map_get_any(params, ["fileChangeCount", :fileChangeCount]) || map_get_any(params, ["changeCount", :changeCount])
    if is_integer(count), do: "#{count} file change(s)", else: "file change"
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
  defp delta_type("item/fileChange/outputDelta"), do: :file_change
  defp delta_type("item/plan/delta"), do: :message
  defp delta_type(_), do: :message

  defp item_class(%{type: :message}), do: "chat-item chat-item-message"
  defp item_class(%{type: :reasoning}), do: "chat-item chat-item-reasoning"
  defp item_class(%{type: :command}), do: "chat-item chat-item-command"
  defp item_class(%{type: :tool_call}), do: "chat-item chat-item-tool"
  defp item_class(%{type: :file_change}), do: "chat-item chat-item-tool"
  defp item_class(%{type: :system}), do: "chat-item chat-item-system"
  defp item_class(%{type: :event}), do: "chat-item chat-item-event"
  defp item_class(_), do: "chat-item"

  @event_badge_modifiers %{
    session_started: "chat-badge-info",
    turn_completed: "chat-badge-success",
    turn_failed: "chat-badge-danger",
    turn_cancelled: "chat-badge-danger",
    approval_auto_approved: "chat-badge-warning",
    approval_required: "chat-badge-warning",
    tool_call_completed: "chat-badge-tool",
    tool_call_failed: "chat-badge-danger",
    unsupported_tool_call: "chat-badge-danger",
    tool_input_auto_answered: "chat-badge-warning",
    turn_input_required: "chat-badge-warning",
    notification: "chat-badge-muted"
  }

  defp event_badge_class(event) do
    modifier = Map.get(@event_badge_modifiers, event, "chat-badge-muted")
    "chat-event-badge #{modifier}"
  end

  defp state_badge_class(state) do
    base = "state-badge"
    normalized = state |> to_string() |> String.downcase()

    cond do
      String.contains?(normalized, ["progress", "running", "active"]) -> "#{base} state-badge-active"
      String.contains?(normalized, ["blocked", "error", "failed"]) -> "#{base} state-badge-danger"
      String.contains?(normalized, ["todo", "queued", "pending", "retry"]) -> "#{base} state-badge-warning"
      true -> base
    end
  end

  defp format_runtime(started_at, now) do
    seconds = runtime_seconds(started_at, now)
    mins = div(seconds, 60)
    secs = rem(seconds, 60)
    "#{mins}m #{secs}s"
  end

  defp runtime_seconds(%DateTime{} = started_at, %DateTime{} = now), do: max(DateTime.diff(now, started_at, :second), 0)

  defp runtime_seconds(started_at, %DateTime{} = now) when is_binary(started_at) do
    case DateTime.from_iso8601(started_at) do
      {:ok, parsed, _offset} -> runtime_seconds(parsed, now)
      _ -> 0
    end
  end

  defp runtime_seconds(_started_at, _now), do: 0

  defp format_event_time(%DateTime{} = dt), do: dt |> DateTime.truncate(:second) |> Calendar.strftime("%H:%M:%S")
  defp format_event_time(_), do: ""

  defp format_int(value) when is_integer(value) do
    value |> Integer.to_string() |> String.reverse() |> String.replace(~r/.{3}(?=.)/, "\\0,") |> String.reverse()
  end

  defp format_int(_value), do: "n/a"

  defp orchestrator, do: Endpoint.config(:orchestrator) || OdysseyElixir.Orchestrator
  defp snapshot_timeout_ms, do: Endpoint.config(:snapshot_timeout_ms) || 15_000
  defp schedule_runtime_tick, do: Process.send_after(self(), :runtime_tick, @runtime_tick_ms)
end
