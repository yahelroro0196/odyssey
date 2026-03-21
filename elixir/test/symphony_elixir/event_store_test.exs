defmodule SymphonyElixir.EventStoreTest do
  use SymphonyElixir.TestSupport

  alias SymphonyElixir.EventStore

  describe "push/2 and events/1" do
    test "stores events retrievable by issue_id" do
      issue_id = "evt-#{System.unique_integer([:positive])}"
      event = %{event: :notification, timestamp: DateTime.utc_now(), payload: %{"data" => "test"}}

      assert :ok = EventStore.push(issue_id, event)
      assert [^event] = EventStore.events(issue_id)
    end

    test "events are ordered by insertion order" do
      issue_id = "evt-#{System.unique_integer([:positive])}"
      e1 = %{event: :session_started, timestamp: ~U[2026-01-01 10:00:00Z]}
      e2 = %{event: :notification, timestamp: ~U[2026-01-01 10:00:01Z]}
      e3 = %{event: :turn_completed, timestamp: ~U[2026-01-01 10:00:02Z]}

      :ok = EventStore.push(issue_id, e1)
      :ok = EventStore.push(issue_id, e2)
      :ok = EventStore.push(issue_id, e3)

      assert [^e1, ^e2, ^e3] = EventStore.events(issue_id)
    end

    test "events for different issue_ids are isolated" do
      id_a = "evt-#{System.unique_integer([:positive])}"
      id_b = "evt-#{System.unique_integer([:positive])}"

      event_a = %{event: :notification, timestamp: DateTime.utc_now(), data: "a"}
      event_b = %{event: :notification, timestamp: DateTime.utc_now(), data: "b"}

      :ok = EventStore.push(id_a, event_a)
      :ok = EventStore.push(id_b, event_b)

      assert [^event_a] = EventStore.events(id_a)
      assert [^event_b] = EventStore.events(id_b)
    end
  end

  describe "ring buffer eviction" do
    test "evicts oldest events when exceeding max" do
      issue_id = "evt-#{System.unique_integer([:positive])}"

      events =
        for i <- 1..510 do
          event = %{event: :notification, timestamp: DateTime.utc_now(), index: i}
          :ok = EventStore.push(issue_id, event)
          event
        end

      stored = EventStore.events(issue_id)
      assert length(stored) == 500
      assert hd(stored).index == 11
      assert List.last(stored).index == 510
      assert stored == Enum.drop(events, 10)
    end
  end

  describe "clear/1" do
    test "removes all events for an issue" do
      issue_id = "evt-#{System.unique_integer([:positive])}"
      :ok = EventStore.push(issue_id, %{event: :notification, timestamp: DateTime.utc_now()})
      assert [_] = EventStore.events(issue_id)

      assert :ok = EventStore.clear(issue_id)
      assert [] = EventStore.events(issue_id)
    end

    test "does not affect other issue_ids" do
      id_a = "evt-#{System.unique_integer([:positive])}"
      id_b = "evt-#{System.unique_integer([:positive])}"

      event_b = %{event: :notification, timestamp: DateTime.utc_now()}
      :ok = EventStore.push(id_a, %{event: :notification, timestamp: DateTime.utc_now()})
      :ok = EventStore.push(id_b, event_b)

      :ok = EventStore.clear(id_a)
      assert [] = EventStore.events(id_a)
      assert [^event_b] = EventStore.events(id_b)
    end
  end

  describe "subscribe/1 and PubSub broadcast" do
    test "broadcasts events to subscribers" do
      issue_id = "evt-#{System.unique_integer([:positive])}"
      :ok = EventStore.subscribe(issue_id)

      event = %{event: :turn_completed, timestamp: DateTime.utc_now()}
      :ok = EventStore.push(issue_id, event)

      assert_receive {:agent_event, ^issue_id, ^event}
    end

    test "does not receive events for other issue_ids" do
      id_a = "evt-#{System.unique_integer([:positive])}"
      id_b = "evt-#{System.unique_integer([:positive])}"
      :ok = EventStore.subscribe(id_a)

      :ok = EventStore.push(id_b, %{event: :notification, timestamp: DateTime.utc_now()})

      refute_receive {:agent_event, ^id_a, _}
    end
  end

  describe "events/1 on empty store" do
    test "returns empty list for unknown issue_id" do
      assert [] = EventStore.events("nonexistent-#{System.unique_integer([:positive])}")
    end
  end
end
