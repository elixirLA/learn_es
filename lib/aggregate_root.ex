# Please see https://tech.zilverline.com/2017/04/07/elixir_event_sourcing

# The aggregate repository will instantiate aggregates and 
# hand out references to them. 

# This is the first part of our event sourcing implementation that will 
# make use of OTP. Our general strategy with aggregates is to have one 
# process per aggregate. With this approach we can eliminate 
# race conditions and guarantee data consistency. 

# Aggregate.Repository.with_aggregate/3 takes a model, aggregate id, and 
# function as arguments. It calls GenServer.call with the PID and 
# function as arguments. This sends the function to the aggregate 
# process, which then executes it. This approach eliminates race 
# conditions and guarantees that our data will always be consistent.


# In order to ensure that there is always only one process per aggregate, 
# we should also have a single process that is giving out references 
# to aggregates.

# Aggregate.Repository simply loads requested aggregates into memory 
# an maintains an aggregate cache to avoid having to load the aggregate 
# from disk more often than necessary. This may be particularly 
# important for performance where it concerns larger aggregates, 
# and this approach is being taken to avoid implementing another 
# solution like snapshotting.

# Aggregate.Repository is a supervisor, which keeps track of all its 
# children processes. When one of these processes dies, we want 
# Aggregate.Repository to be notified so that it can remove it from 
# its own internal tracking. 
# This is accomplished with `Process.flag(:trap_exit, true)` and 
# the callback `handle_info`.

# Consider setting upper limit to number of processes as we might run out
# of memory.

defmodule Aggregate.Repository do
  use GenServer

  def start_link do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def with_aggregate(model, aggregate_id, function) do
    get(model, aggregate_id)
    |> GenServer.call(function)
  end

  defp get(model, aggregate_id) do
    GenServer.call(__MODULE__, {:get, model, aggregate_id})
  end

  # callbacks

  def init(_) do
    
    Process.flag(:trap_exit, true)
    {:ok, %{}}
  end

  def handle_call({:get, model, aggregate_id}, _, aggregates) do
    case Map.fetch(aggregates, aggregate_id) do
      {:ok, aggregate_pid} ->
        {:reply, aggregate_pid, aggregates}
      :error ->
        new_aggregate_pid = Aggregate.Instance.start_link(model, aggregate_id)
        {:reply, new_aggregate_pid, Map.merge(aggregates, %{aggregate_id => new_aggregate_pid, new_aggregate_pid => aggregate_id})}
    end
  end

  def handle_info({:EXIT, from, reason}, aggregates) do
    require Logger
    Logger.error("Aggregate `#{inspect from}` exited with reason `#{inspect reason}`")
    {:ok, aggregate_id} = aggregates |> Map.fetch(from)
    {:noreply, aggregates |> Map.delete(aggregate_id) |> Map.delete(from)}
  end
end




# The aggregate instance is also a GenServer, capturing the state of 
# the aggregate, and ensuring data consistency by ensuring that 
# all writes for a particular aggregate get executed in a single process. 
# This eliminates race conditions present in typical CRUD applications 
# (which may have multiple “read -> compute new state -> write” processes
#  computing at once).

# In `start_link`, we send an asynchronous message to the aggregate 
#`to tell it to finish its own initialization. The aggregate must read 
# its events from the event store and build up its state before it is 
# ready to do any computation. `start_link` is always run in the 
# `Aggregate.Repository` process, but we want `EventStore.load` to 
# execute in the `Aggregate.Instance` process. 
# This will reduce the amount of computation done in 
# `Aggregate.Repository`, improving its throughput. `Aggregate.Repository` 
# is a bottleneck in the system, since every write request will be 
# using it.

# Appending to lists is an expensive O(N) operation, 
# while prepending to lists is O(1). This is due to immutability and 
# the structure of linked lists. So while it may seem logical to 
# append new events, we will actually prepend them and then reverse 
# the order later with Enum.reverse.

# If the model returns {:error, reason}, then the state reverts to the 
# old state, and nothing is written to the event store. 
# Only when the result of function is a valid new state, do the new 
# events get written to the event store.

# In order to have as many aggregates loaded in memory as possible 
# it makes sense to limit the amount of state that will be tracked to 
# only that which is needed to perform business logic. 
# Data that is not used in invariants should not be tracked in 
# the State struct of an aggregate.



defmodule Aggregate.Instance do
  use GenServer

  def start_link(model, aggregate_id) do
    {:ok, pid} = GenServer.start_link(__MODULE__, {model, aggregate_id})
    GenServer.cast(pid, :finish_init)
    pid
  end

  # callbacks
  #
  def init({model, aggregate_id}) do
    {:ok, {model, %{aggregate_id: aggregate_id}}}
  end

  def handle_cast(:finish_init, {model, state}) do
    events = if state.aggregate_id, do: EventStore.load(state.aggregate_id), else: []

    {:noreply, {model, state_from_events(model, events) || nil}}
  end

  def handle_call(function, _from, {model, state}) do
    case function.({state, []}) do
      {_, {:error, reason}} ->
        {:reply, {:error, reason}, {model, state}}
      {new_state, new_events} ->
        EventStore.commit(new_state.aggregate_id, Enum.reverse(new_events))
        {:reply, :ok, {model, new_state}}
    end
  end

  defp state_from_events(model, events) do
    events
    |> Enum.reduce(nil, fn(event, state) -> model.next_state(event, state) end)
  end
end
