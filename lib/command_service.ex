# Please see https://tech.zilverline.com/2017/04/07/elixir_event_sourcing

# EventHandler dispatches each event to every individual event handler, 
# the first command handler that claims to handle a command processes
# the command to guarantee it is executed once 
# This module enables to stop at the first command handler 
# that claims to handle a command. 

# Raise an error if we reach the end of the list of without 
# finding one handler that will handle a command



defmodule CommandService do
  @command_handlers [CounterCommandHandler]

  def execute(command, []), do: raise "No command handler registered that can process this command"

  def execute(command, [command_handler | command_handlers] \\ @command_handlers) do
    case command_handler.execute(command) do
      :not_handled -> execute(command, command_handlers)
      x -> x
    end
  end
end
