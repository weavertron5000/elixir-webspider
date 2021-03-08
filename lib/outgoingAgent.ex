defmodule Spider.OutgoingAgent do
  use Agent

  def start_link(_opts) do
    Agent.start_link(fn -> [] end, name: Spider.OutgoingAgent)
  end

  def add_data_to_queue(data) do
    Agent.update(Spider.OutgoingAgent, fn state -> state ++ [data] end)
  end

  def get_all_items_in_queue() do
    Agent.get(Spider.OutgoingAgent, fn state -> state end)
  end

  def clear() do
    Agent.update(Spider.OutgoingAgent, fn state -> [] end)
  end
end
