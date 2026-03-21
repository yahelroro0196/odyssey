defmodule SymphonyElixirWeb.ChatLive do
  @moduledoc """
  Full-screen LiveView for viewing a running agent's event stream.
  """

  use Phoenix.LiveView, layout: {SymphonyElixirWeb.Layouts, :app}

  alias SymphonyElixir.{EventStore, StatusDashboard}
  alias SymphonyElixirWeb.{Endpoint, ObservabilityPubSub, Presenter}

  @runtime_tick_ms 1_000

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

        events = EventStore.events(issue_id)

        socket =
          socket
          |> assign(:issue_id, issue_id)
          |> assign(:agent_info, agent_info)
          |> assign(:events, events)

        {:ok, socket}

      {:error, :not_found} ->
        socket =
          socket
          |> assign(:issue_id, nil)
          |> assign(:agent_info, nil)
          |> assign(:events, [])

        {:ok, socket}
    end
  end

  @impl true
  def handle_info({:agent_event, issue_id, event}, socket) do
    if socket.assigns.issue_id == issue_id do
      {:noreply, assign(socket, :events, socket.assigns.events ++ [event])}
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
          <%= if @events == [] do %>
            <p class="chat-empty-events">No events yet.</p>
          <% else %>
            <div :for={{event, idx} <- Enum.with_index(@events)} class="chat-event" id={"event-#{idx}"}>
              <div class="chat-event-header">
                <span class={event_badge_class(event[:event])}>
                  <%= event[:event] || "unknown" %>
                </span>
                <span class="chat-event-time mono numeric"><%= format_event_time(event[:timestamp]) %></span>
              </div>
              <div class="chat-event-body"><%= humanize_event(event) %></div>
              <%= if event[:raw] || event[:payload] do %>
                <button
                  type="button"
                  class="chat-event-toggle"
                  onclick="var el=this.nextElementSibling;el.classList.toggle('chat-event-raw--open');this.textContent=el.classList.contains('chat-event-raw--open')?'Hide JSON':'Show JSON'"
                >
                  Show JSON
                </button>
                <pre class="chat-event-raw"><%= format_raw(event) %></pre>
              <% end %>
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

      // Re-create liveSocket with hooks if needed
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

  defp humanize_event(event) do
    StatusDashboard.humanize_codex_message(event)
  end

  defp format_event_time(%DateTime{} = dt) do
    dt
    |> DateTime.truncate(:second)
    |> Calendar.strftime("%H:%M:%S")
  end

  defp format_event_time(_), do: ""

  defp format_raw(event) do
    raw = event[:raw] || event[:payload]

    case raw do
      s when is_binary(s) ->
        case Jason.decode(s) do
          {:ok, decoded} -> Jason.encode!(decoded, pretty: true)
          _ -> s
        end

      m when is_map(m) ->
        Jason.encode!(m, pretty: true)

      other ->
        inspect(other, pretty: true, limit: :infinity)
    end
  end

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

  defp runtime_seconds(%DateTime{} = started_at, %DateTime{} = now) do
    max(DateTime.diff(now, started_at, :second), 0)
  end

  defp runtime_seconds(started_at, %DateTime{} = now) when is_binary(started_at) do
    case DateTime.from_iso8601(started_at) do
      {:ok, parsed, _offset} -> runtime_seconds(parsed, now)
      _ -> 0
    end
  end

  defp runtime_seconds(_started_at, _now), do: 0

  defp format_int(value) when is_integer(value) do
    value
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/.{3}(?=.)/, "\\0,")
    |> String.reverse()
  end

  defp format_int(_value), do: "n/a"

  defp orchestrator do
    Endpoint.config(:orchestrator) || SymphonyElixir.Orchestrator
  end

  defp snapshot_timeout_ms do
    Endpoint.config(:snapshot_timeout_ms) || 15_000
  end

  defp schedule_runtime_tick do
    Process.send_after(self(), :runtime_tick, @runtime_tick_ms)
  end
end
