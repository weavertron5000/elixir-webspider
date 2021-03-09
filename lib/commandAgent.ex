defmodule Spider.CommandAgent do
  use Agent

  def start_link(_opts) do
    Agent.start_link(fn -> [] end, name: Spider.CommandAgent)
  end

  def set_data(project, data) do
    Agent.update(Spider.CommandAgent, fn state -> state ++ [{project, data}] end)
  end

  def get_all_items(project) do
    Agent.get(Spider.CommandAgent, fn state ->
      Enum.filter(state, fn item ->
        { p, _ } = item
        project == p
      end)
    end)
  end
end
