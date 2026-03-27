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
end
