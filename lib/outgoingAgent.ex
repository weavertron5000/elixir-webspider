defmodule Spider.OutgoingAgent do
  use Agent

  def start_link(_opts) do
    Agent.start_link(fn -> [] end, name: Spider.OutgoingAgent)
  end

  def add_data_to_queue(project, data) do
    Agent.update(Spider.OutgoingAgent, fn state -> state ++ [{ project, data }] end)
  end

  def get_all_items_in_queue(project) do
    Agent.get(Spider.OutgoingAgent, fn state ->
      Enum.filter(state, fn item ->
        { p, _ } = item
        project == p
      end)
    end)
  end

  def clear(project) do
    Agent.update(Spider.OutgoingAgent, fn state ->
      Enum.filter(state, fn item ->
        { p, _ } = item
        project != p
      end)
    end)
  end
end
