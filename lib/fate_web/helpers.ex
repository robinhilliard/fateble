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
end
