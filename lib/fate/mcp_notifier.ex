defmodule Fate.McpNotifier do
  @moduledoc """
  Bridges game state changes to MCP SSE clients.

  Subscribes to PubSub for state changes and sends
  `notifications/resources/updated` through active SSE handlers
  so MCP clients know to refetch stale resources.
  """

  use GenServer
  require Logger

  alias ExMCP.HttpPlug.SSEHandler

  @pubsub Fate.PubSub
  @ets_table :http_plug_sessions

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    Phoenix.PubSub.subscribe(@pubsub, "mcp:state_changed")
    {:ok, %{}}
  end

  @impl true
  def handle_info({:state_updated, _bookmark_id}, state) do
    notify_sse_clients("fate://game/state")
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  defp notify_sse_clients(uri) do
    notification = %{
      "jsonrpc" => "2.0",
      "method" => "notifications/resources/updated",
      "params" => %{"uri" => uri}
    }

    for {_session_id, handler_pid} <- list_sse_handlers(),
        Process.alive?(handler_pid) do
      SSEHandler.send_event(handler_pid, "message", notification)
    end

    :ok
  rescue
    ArgumentError -> :ok
  end

  defp list_sse_handlers do
    :ets.tab2list(@ets_table)
  rescue
    ArgumentError -> []
  end
end
