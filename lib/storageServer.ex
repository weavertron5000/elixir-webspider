defmodule Spider.StorageServer do
  use GenServer

  def start_link(opts) do
    GenServer.start_link(Spider.StorageServer, {}, opts)
  end

  @impl true
  def init(_state) do
    {:ok, redis} = Redix.start_link("redis://localhost:6379/0", name: :redix)

    schedule_next()

    {:ok, { redis }}
  end

  @impl true
  def handle_info(:tick, state) do
    { redis } = state

    queued = Spider.QueueAgent.get_currently_queued()

    {:ok, _} = Redix.command(redis, ["SET", "queued", Jason.encode!(queued)])

    {:ok, commands} = Redix.command(redis, ["SMEMBERS", "commands"])

    case commands do
      nil -> Spider.CommandAgent.set_data([])
      _ -> Spider.CommandAgent.set_data(commands)
    end

    {:ok, sites} = Redix.command(redis, ["SMEMBERS", "sites"])

    case sites do
      nil -> :ok
      _ -> Enum.each(sites, fn x -> Spider.QueueAgent.add_url_to_queue(x) end)
    end

    {:ok, _} = Redix.command(redis, ["DEL", "sites"])

    Enum.each(Spider.OutgoingAgent.get_all_items_in_queue(), fn x ->
      %{ "url" => url, "data" => _ } = x

      {:ok, _} = Redix.command(redis, ["SADD", url, Jason.encode!(x)])

      {:ok, _} = Redix.command(redis, ["SADD", "crawled", url])
    end)

    Spider.OutgoingAgent.clear()

    schedule_next()

    {:noreply, {redis}}
  end

  defp schedule_next do
    Process.send_after(self(), :tick, 1000)
  end
end
