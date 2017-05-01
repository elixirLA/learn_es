# Please see https://tech.zilverline.com/2017/04/07/elixir_event_sourcing


# The event handler has only one function, `handle`, 
# which dispatches an event to multiple handlers. 
# Use pattern matching to process the list of handlers.

defmodule EventHandler do
  @handlers [CounterEventHandler]

  def handle(_, []), do: :ok
  def handle({uuid, event}, [handler | handlers] \\ @handlers) do
    :ok = handler.handle(event)
    handle({uuid, event}, handlers)
  end
end
