# Please see https://tech.zilverline.com/2017/04/07/elixir_event_sourcing

# The EventStore stores events in the event store, 
# and notifies listeners via `EventHandler`. 
# It has only two functions. 
# `commit` will add events to a particular aggregate, 
# identified by its uuid. 
# `load` simply loads events from a particular aggregate.

defmodule EventStore do
  @event_store RedisEventStore

  def commit(uuid, events) when is_list(events) do
    @event_store.commit(uuid, (events |> Enum.map(&EventSerializer.serialize/1)))

    notify(uuid, events)
  end
  def commit(uuid, event), do: commit(uuid, [event])

  def load(uuid), do: @event_store.load(uuid) |> Enum.map(&EventSerializer.deserialize/1)

  defp notify(_uuid, []), do: :ok
  defp notify(uuid, [event | events]) do
    EventHandler.handle({uuid, event})
    notify(uuid, events)
  end
end


 #  serializer to convert our events from structs to strings and 
 #  back again.

defmodule EventSerializer do
  def serialize(event) do
    event |> Map.from_struct |> Map.merge(%{__struct__: to_string(event.__struct__)}) |> Poison.encode!
  end

  def deserialize(serialized_event) do
    serialized_event |> Poison.decode!(keys: :atoms) |> decode()
  end

  def decode(event_map) do
    new_event = event_map |> Enum.reduce(%{}, fn ({key, val}, acc) -> Map.put(acc, key, val) end)
    [Map.fetch!(new_event, :__struct__)] |> Module.concat() |> struct(new_event)
  end
end

# Read and write from Redis

defmodule RedisEventStore do
  def commit(_uuid, []), do: nil
  def commit(uuid, [event|events]) do
    {:ok, _} = Redix.command(:redix, ["RPUSH", uuid, event])
    commit(uuid, events)
  end

  def load(uuid) do
    {:ok, result} = Redix.command(:redix, ~w(LRANGE #{uuid} 0 -1))
    result
  end
end
