defmodule FateWeb.Helpers do
  @moduledoc """
  Shared helper functions for LiveViews.
  """

  @doc """
  Reads identity from LiveSocket connect params (backed by localStorage).
  Returns a map with :participant_id, :name, :role (as atom), :is_gm, :is_observer.
  """
  def identify(socket) do
    params = Phoenix.LiveView.get_connect_params(socket) || %{}
    role = params["participant_role"]

    %{
      participant_id: params["participant_id"],
      name: params["participant_name"],
      role: role,
      is_gm: role == "gm",
      is_observer: role == "observer"
    }
  rescue
    _ -> %{participant_id: nil, name: nil, role: nil, is_gm: false, is_observer: false}
  end

  @doc """
  Parses a "type:id" target reference string into a `{type, id}` tuple.
  Returns `{nil, nil}` when the ref is nil, empty, or unrecognized.
  """
  def parse_target_ref(nil), do: {nil, nil}
  def parse_target_ref(""), do: {nil, nil}

  def parse_target_ref(target_ref) do
    case String.split(target_ref, ":", parts: 2) do
      ["entity", id] -> {"entity", id}
      ["scene", id] -> {"scene", id}
      ["zone", id] -> {"zone", id}
      _ -> {nil, nil}
    end
  end

  @doc """
  Broadcasts exchange builder state to all clients viewing the same bookmark.
  Uses `broadcast_from` so the sender's own LiveView doesn't re-handle the message.
  """
  def broadcast_exchange(socket) do
    if socket.assigns.bookmark_id do
      Phoenix.PubSub.broadcast_from(
        Fate.PubSub,
        self(),
        "exchange:#{socket.assigns.bookmark_id}",
        {:exchange_updated,
         %{building: socket.assigns.building, build_steps: socket.assigns.build_steps}}
      )
    end
  end

  @doc """
  PubSub topic for table ↔ panel selection sync (`{:selection_updated, list}`).
  """
  def selection_topic(bookmark_id, participant_id)
      when is_binary(bookmark_id) and is_binary(participant_id) do
    "selection:#{bookmark_id}:#{participant_id}"
  end

  @doc """
  Broadcasts selection to all subscribers (including other LiveViews for the same participant).
  """
  def broadcast_selection(socket, selection) do
    bid = socket.assigns.bookmark_id
    pid = socket.assigns.current_participant_id

    if bid && pid do
      Phoenix.PubSub.broadcast(
        Fate.PubSub,
        selection_topic(bid, pid),
        {:selection_updated, selection}
      )
    end
  end

  @doc """
  PubSub topic for GM search-result selection sync.
  Scoped per-participant so multiple GMs don't interfere.
  """
  def search_selection_topic(bookmark_id, participant_id)
      when is_binary(bookmark_id) and is_binary(participant_id) do
    "search_selection:#{bookmark_id}:#{participant_id}"
  end

  @doc """
  Broadcasts search selection (entity IDs and scene template IDs) to subscribers.
  """
  def broadcast_search_selection(socket, %{} = selection) do
    bid = socket.assigns.bookmark_id
    pid = socket.assigns.current_participant_id

    if bid && pid do
      Phoenix.PubSub.broadcast(
        Fate.PubSub,
        search_selection_topic(bid, pid),
        {:search_selection_updated, selection}
      )
    end
  end
end
