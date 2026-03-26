defmodule Fate.Game.Events do
  @moduledoc """
  Context functions for event lifecycle operations.
  """

  alias Fate.Game.{Event, Bookmark}

  require Ash.Query

  def delete(event_id, bookmark_id) do
    with {:ok, event} when event != nil <-
           Ash.get(Event, event_id, not_found_error?: false) do
      {:ok, bookmark} = Ash.get(Bookmark, bookmark_id, not_found_error?: false)

      if bookmark && bookmark.head_event_id == event_id do
        Ash.update!(bookmark, %{head_event_id: event.parent_id}, action: :advance_head)
      end

      case Ash.read(Event |> Ash.Query.filter(parent_id: event_id)) do
        {:ok, children} ->
          Enum.each(children, fn child ->
            Ash.update!(child, %{parent_id: event.parent_id}, action: :edit)
          end)

        _ ->
          :ok
      end

      Ash.destroy(event, action: :delete)
    else
      _ -> {:error, :not_found}
    end
  end
end
