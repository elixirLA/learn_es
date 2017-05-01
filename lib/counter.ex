# Please see https://tech.zilverline.com/2017/04/07/elixir_event_sourcing


defmodule CounterEventHandler do
  alias Model.Counter


  def handle(%Counter.Created{aggregate_id: aggregate_id}) do
    %Eslixir.Counter{aggregate_id: aggregate_id, count: 0}
    |> Eslixir.Repo.insert

    :ok
  end

  def handle(%Counter.Incremented{aggregate_id: aggregate_id, count: count}) do
    import Ecto.Query, only: [from: 2, update: 2, where: 2]

    from(c in Eslixir.Counter, where: c.aggregate_id == ^aggregate_id)
    |> Eslixir.Repo.update_all(set: [count: count])

    :ok
  end

# This is necessary to prevent Elixir from complaining that a particular 
# event handler doesn’t have a function definition for a particular event. 
# So we simply return :ok for all events not otherwise handled 
# by a particular event handler.

  def handle(_), do: :ok
end



# This model is defining a simple counter. 
# Every model has a State struct, that’s what’s going to be held in 
# memory in the `Aggregate.Instance` process. 

# `Model.Counter.create/2` applies `Created`, but only if the counter 
# has not already been created.

# `Model.Counter.increment/2` applied Incremented, and 
# increases the count by 1.

# `Model.Counter.next_state` is used to translate events to state. 
# This is used both when the aggregate is being loaded from 
# the event store, and when a new event is applied to the aggregate. 
# This way the state is always kept up to date.

# `Model.Counter.apply_event/3` simply coordinates setting the new state 
# and prepending the new event.

defmodule Model.Counter do
  defmodule State, do: defstruct [:aggregate_id, :count]

  defmodule Create, do: defstruct [:aggregate_id]
  defmodule Increment, do: defstruct [:aggregate_id]

  defmodule Created, do: defstruct [:aggregate_id]
  defmodule Incremented, do: defstruct [:aggregate_id, :count]

  def create({state, new_events}, aggregate_id) do
    if(state) do
      {state, {:error, "Already created"}}
    else
      {state, new_events} |> apply_event(%Created{aggregate_id: aggregate_id})
    end
  end

  def increment({state, new_events}) do
    {state, new_events} |> apply_event(%Incremented{aggregate_id: state.aggregate_id, count: state.count + 1})
  end

  def next_state(%Created{aggregate_id: aggregate_id}, _), do: %State{aggregate_id: aggregate_id, count: 0}
  def next_state(%Incremented{aggregate_id: aggregate_id, count: count}, state), do: %State{state | count: count}

  defp apply_event({state, {:error, reason}}, _), do: {state, {:error, reason}}
  defp apply_event({state, new_events}, event) do
    { next_state(event, state), [event | new_events] }
  end
end




# A command handler described here fetches the aggregate 
# from the repository, and translate the command into 
# instructions to increment. This can be used to execute TTL events
# or push instructions using "pusherex" etcc.

defmodule CounterCommandHandler do
  alias Model.Counter

  def execute(%Counter.Create{aggregate_id: aggregate_id}) do
    Aggregate.Repository.with_aggregate(Counter, aggregate_id, fn(state) ->
      state |> Counter.create(aggregate_id)
    end)
  end

  def execute(%Counter.Increment{aggregate_id: aggregate_id}) do
    Aggregate.Repository.with_aggregate(Counter, aggregate_id, fn(state) ->
      state |> Counter.increment
    end)
  end

#   def execute(%Counter.Increment2{}) do
#   Aggregate.Repository.with_aggregate(Counter, aggregate_id, fn(state) ->
#     state
#     |> Counter.increment
#     |> Counter.increment
#   end)
# end



  def execute(_), do: :not_handled
end




