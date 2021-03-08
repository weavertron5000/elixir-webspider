defmodule Spider do
  @impl true
  def start(_type, _args) do
    # Although we don't use the supervisor name below directly,
    # it can be useful when debugging or introspecting the system.
    Spider.Supervisor.start_link(name: Spider.Supervisor)
  end
end
