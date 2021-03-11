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
        length(state) == 1 ->
          ([head] = state; {head, []})
        length(state) == 0 ->
          {{"","","",""}, []}
      end
    end)
  end

  def peek_next_in_queue() do
    Agent.get(Spider.QueueAgent, fn state ->
      cond do
        length(state) >= 1 -> hd(state)
        true -> {"","","",""}
      end
    end)
  end

  def add_url_to_queue(urlData) do
    { _, url, _, _ } = urlData
    existing = Agent.get(Spider.QueueAgent, fn state -> state end)
    cond do
      length(Enum.filter(existing, fn oldUrlData ->
        fixedUrlData = List.to_tuple(Enum.map(Tuple.to_list(urlData), fn item -> String.downcase(item) end))
        fixedOldUrlData = List.to_tuple(Enum.map(Tuple.to_list(oldUrlData), fn item -> String.downcase(item) end))
        cond do
          fixedUrlData == fixedOldUrlData -> true
          true -> false
        end
      end)) == 0 -> (IO.puts("Adding URL to queue: " <> url); Agent.update(Spider.QueueAgent, fn state -> state ++ [urlData] end))
      true -> :ok
    end
  end

  def get_currently_queued(project) do
    Agent.get(Spider.QueueAgent, fn state ->
      Enum.filter(state, fn item ->
        { p, _, _, _ } = item
        project == p
      end)
    end)
  end
end
