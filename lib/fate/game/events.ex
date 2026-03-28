defmodule Fate.Game.Events do
  @moduledoc """
  Context functions for event lifecycle operations.
  """

  alias Fate.Game
  alias Fate.Game.Event

  require Ash.Query

  @doc """
  Move `event_id` to be immediately after `after_event_id` in the chain.
  Pass `nil` for `after_event_id` to move the event to the very beginning (root position).
  """
  def reorder(event_id, after_event_id, bookmark_id) do
    if event_id == after_event_id, do: throw(:noop)

    with {:ok, event} when event != nil <- Game.get_event(event_id),
         {:ok, bookmark} when bookmark != nil <- Game.get_bookmark(bookmark_id) do
      if event.parent_id == after_event_id, do: throw(:noop)

      {:ok, displaced} =
        if after_event_id do
          Ash.read(Event |> Ash.Query.filter(parent_id: after_event_id))
        else
          {:ok, []}
        end

      displaced = Enum.reject(displaced, &(&1.id == event_id))

      {:ok, children} = Ash.read(Event |> Ash.Query.filter(parent_id: event_id))

      Enum.each(children, fn child ->
        Game.edit_event!(child, %{parent_id: event.parent_id})
      end)

      if bookmark.head_event_id == event_id do
        Game.advance_head!(bookmark, %{head_event_id: event.parent_id})
      end

      Game.edit_event!(event, %{parent_id: after_event_id})

      Enum.each(displaced, fn next ->
        Game.edit_event!(next, %{parent_id: event_id})
      end)

      after_ts =
        if after_event_id do
          case Game.get_event(after_event_id) do
            {:ok, a} when a != nil -> a.timestamp
            _ -> ~U[2000-01-01 00:00:00.000000Z]
          end
        else
          ~U[2000-01-01 00:00:00.000000Z]
        end

      next_ts =
        case displaced do
          [d | _] -> d.timestamp
          [] -> DateTime.add(after_ts, 1, :second)
        end

      diff_us = DateTime.diff(next_ts, after_ts, :microsecond)
      mid_ts = DateTime.add(after_ts, div(diff_us, 2), :microsecond)
      Game.edit_event!(event, %{timestamp: mid_ts})

      {:ok, bookmark} = Game.get_bookmark(bookmark_id)

      {:ok, event_children} = Ash.read(Event |> Ash.Query.filter(parent_id: event_id))

      if event_children == [] do
        Game.advance_head!(bookmark, %{head_event_id: event_id})
      end

      :ok
    else
      _ -> {:error, :not_found}
    end
  catch
    :noop -> :ok
  end

  def delete(event_id, bookmark_id) do
    with {:ok, event} when event != nil <- Game.get_event(event_id) do
      {:ok, bookmark} = Game.get_bookmark(bookmark_id)

      if bookmark && bookmark.head_event_id == event_id do
        Game.advance_head!(bookmark, %{head_event_id: event.parent_id})
      end

      case Ash.read(Event |> Ash.Query.filter(parent_id: event_id)) do
        {:ok, children} ->
          Enum.each(children, fn child ->
            Game.edit_event!(child, %{parent_id: event.parent_id})
          end)

        _ ->
          :ok
      end

      Game.delete_event(event)
    else
      _ -> {:error, :not_found}
    end
  end
end
