defmodule Spider.CommandAgent do
  use Agent

  def start_link(_opts) do
    Agent.start_link(fn -> [] end, name: Spider.CommandAgent)
  end

  def set_data(data) do
    Agent.update(Spider.CommandAgent, fn state -> data end)
  end

  def get_all_items() do
    Agent.get(Spider.CommandAgent, fn state -> state end)
  end
end
