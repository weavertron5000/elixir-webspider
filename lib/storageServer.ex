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

    {:ok, projects} = Redix.command(redis, ["SMEMBERS", "projects"])

    Enum.each(projects, fn project ->
      queued = Spider.QueueAgent.get_currently_queued(project)

      queuedAsLists = Enum.map(queued, &Tuple.to_list(&1))

      {:ok, _} = Redix.command(redis, ["SET", project <> ":queued", Jason.encode!(queuedAsLists)])

      {:ok, commands} = Redix.command(redis, ["SMEMBERS", project <> ":commands"])

      case commands do
        nil -> Spider.CommandAgent.set_data(project, [])
        _ -> Spider.CommandAgent.set_data(project, commands)
      end

      {:ok, sites} = Redix.command(redis, ["SMEMBERS", project <> ":sites"])

      currentTime = DateTime.now("Etc/UTC") |> elem(1) |> DateTime.to_iso8601()

      case sites do
        nil -> :ok
        _ -> Enum.each(sites, fn x -> Spider.QueueAgent.add_url_to_queue({ project, x, "0", currentTime }) end)
      end

      {:ok, _} = Redix.command(redis, ["DEL", project <> ":sites"])

      Enum.each(Spider.OutgoingAgent.get_all_items_in_queue(project), fn tuple ->
        { _, x } = tuple

        %{ "url" => url, "data" => _ } = x

        {:ok, _} = Redix.command(redis, ["SADD", project <> ":" <> url, Jason.encode!(x)])

        {:ok, _} = Redix.command(redis, ["SADD", project <> ":crawled", url])
      end)

      Spider.OutgoingAgent.clear(project)
    end)

    schedule_next()

    {:noreply, {redis}}
  end

  defp schedule_next do
    Process.send_after(self(), :tick, 1000)
  end
end
