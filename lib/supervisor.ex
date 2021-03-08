defmodule Spider.Supervisor do
  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(Spider.Supervisor, :ok, opts)
  end

  @impl true
  def init(:ok) do
    children = [
      {Spider.QueueAgent, name: Spider.QueueAgent, strategy: :one_for_one},
      {Spider.OutgoingAgent, name: Spider.OutgoingAgent, strategy: :one_for_one},
      {Spider.CommandAgent, name: Spider.CommandAgent, strategy: :one_for_one},
      {Spider.QueryServer, name: Spider.QueryServer, strategy: :one_for_one},
      {Spider.StorageServer, name: Spider.StorageServer, strategy: :one_for_one}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
