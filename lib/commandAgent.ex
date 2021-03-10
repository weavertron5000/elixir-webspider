defmodule Spider.CommandAgent do
  use Agent

  def start_link(_opts) do
    Agent.start_link(fn -> [] end, name: Spider.CommandAgent)
  end

  def set_data(project, data) do
    existing = Agent.get(Spider.CommandAgent, fn state -> state end)
    cond do
      length(Enum.filter(existing, fn command ->
        cond do
          command == {project, data} -> true
          true -> false
        end
      end)) == 0 -> Agent.update(Spider.CommandAgent, fn state -> state ++ [{project, data}] end)
      true -> :ok
    end
  end

  def get_all_items(project) do
    Agent.get(Spider.CommandAgent, fn state ->
      filtered = Enum.filter(state, fn item ->
        { p, _ } = item
        project == p
      end)
      [{ _, items}] = filtered
      items
    end)
  end
end
