defmodule Spider.QueueAgent do
  use Agent

  def start_link(_opts) do
    Agent.start_link(fn -> [] end, name: Spider.QueueAgent)
  end

  def get_next_in_queue() do
    Agent.get_and_update(Spider.QueueAgent, fn state ->
      cond do
        length(state) > 1 ->
          ([head | tail] = state; {head, tail})
          {head, tail}
        length(state) == 1 ->
          ([head] = state; {head, []})
        length(state) == 0 ->
          {"", []}
      end
    end)
  end

  def add_url_to_queue(url) do
    existing = Agent.get(Spider.QueueAgent, fn state -> state end)
    cond do
      length(Enum.filter(existing, fn oldUrl ->
        cond do
          String.trim(String.downcase(url)) == String.trim(String.downcase(oldUrl)) -> true
          true -> false
        end
      end)) == 0 -> (IO.puts("Adding URL to queue: " <> url); Agent.update(Spider.QueueAgent, fn state -> state ++ [url] end))
      true -> :ok
    end
  end

  def get_currently_queued() do
    Agent.get(Spider.QueueAgent, fn state -> state end)
  end
end