defmodule Fate.Engine do
  @moduledoc """
  Central coordination module for game state.
  Loads events from the database, replays them into derived state,
  and broadcasts changes via PubSub.
  """

  alias Fate.Game
  alias Fate.Engine.Replay

  @pubsub Fate.PubSub

  def derive_state(bookmark_id) do
    with {:ok, bookmark} when bookmark != nil <- Game.get_bookmark(bookmark_id),
         {:ok, events} <- load_event_chain(bookmark.head_event_id) do
      {:ok, Replay.derive(bookmark_id, events)}
    else
      {:ok, nil} -> {:error, :not_found}
      error -> error
    end
  end

  def append_event(bookmark_id, attrs) do
    with {:ok, bookmark} when bookmark != nil <- Game.get_bookmark(bookmark_id) do
      attrs = Map.put(attrs, :parent_id, bookmark.head_event_id)

      with {:ok, event} <- Game.append_event(attrs),
           {:ok, _bookmark} <- Game.advance_head(bookmark, %{head_event_id: event.id}),
           {:ok, state} <- derive_state(bookmark_id) do
        broadcast(bookmark_id, state)
        {:ok, state, event}
      end
    end
  end

  def load_event_chain(nil), do: {:ok, []}

  def load_event_chain(event_id) do
    query = """
    WITH RECURSIVE chain AS (
      SELECT * FROM events WHERE id = $1
      UNION ALL
      SELECT e.* FROM events e
      JOIN chain c ON e.id = c.parent_id
    )
    SELECT * FROM chain ORDER BY timestamp ASC
    """

    run_event_query(query, event_id)
  end

  @doc """
  Loads events from bookmark head back to (but not including) the nearest
  bookmark_create event. Used for player-visible event log.
  """
  def load_player_events(bookmark_id) do
    with {:ok, bookmark} when bookmark != nil <- Game.get_bookmark(bookmark_id) do
      query = """
      WITH RECURSIVE chain AS (
        SELECT * FROM events WHERE id = $1
        UNION ALL
        SELECT e.* FROM events e
        JOIN chain c ON e.id = c.parent_id
        WHERE c.type != 'bookmark_create'
      )
      SELECT * FROM chain ORDER BY timestamp ASC
      """

      run_event_query(query, bookmark.head_event_id)
    else
      _ -> {:ok, []}
    end
  end

  defp run_event_query(sql, event_id) do
    {:ok, binary_id} = Ecto.UUID.dump(event_id)

    case Fate.Repo.query(sql, [binary_id]) do
      {:ok, %{rows: rows, columns: columns}} ->
        events =
          Enum.map(rows, fn row ->
            columns
            |> Enum.zip(row)
            |> Map.new()
            |> row_to_event()
          end)

        {:ok, events}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp row_to_event(row) do
    %{
      id: load_uuid(row["id"]),
      parent_id: load_uuid(row["parent_id"]),
      timestamp: row["timestamp"],
      type: parse_type(row["type"]),
      actor_id: row["actor_id"],
      target_id: row["target_id"],
      exchange_id: load_uuid(row["exchange_id"]),
      description: row["description"],
      detail: row["detail"]
    }
  end

  defp load_uuid(nil), do: nil

  defp load_uuid(<<_::128>> = binary) do
    {:ok, uuid} = Ecto.UUID.load(binary)
    uuid
  end

  defp load_uuid(string) when is_binary(string), do: string

  defp parse_type(type) when is_binary(type) do
    String.to_existing_atom(type)
  rescue
    ArgumentError -> :unknown
  end

  defp parse_type(type) when is_atom(type), do: type

  defp broadcast(bookmark_id, state) do
    Phoenix.PubSub.broadcast(@pubsub, "bookmark:#{bookmark_id}", {:state_updated, state})
    Phoenix.PubSub.broadcast(@pubsub, "mcp:state_changed", {:state_updated, bookmark_id})
  end

  def subscribe(bookmark_id) do
    Phoenix.PubSub.subscribe(@pubsub, "bookmark:#{bookmark_id}")
  end
end
