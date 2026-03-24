defmodule Fate.Engine do
  @moduledoc """
  Central coordination module for game state.
  Loads events from the database, replays them into derived state,
  and broadcasts changes via PubSub.
  """

  alias Fate.Game.{Event, Branch}
  alias Fate.Engine.Replay

  @pubsub Fate.PubSub

  @doc """
  Loads the event chain for a branch and computes derived state.
  Uses a recursive CTE to walk from the branch head to root.
  """
  def derive_state(branch_id) do
    with {:ok, branch} <- Ash.get(Branch, branch_id),
         {:ok, events} <- load_event_chain(branch.head_event_id) do
      {:ok, Replay.derive(branch_id, events)}
    end
  end

  @doc """
  Appends a new event to a branch and returns the updated derived state.
  """
  def append_event(branch_id, attrs) do
    with {:ok, branch} <- Ash.get(Branch, branch_id),
         attrs <- Map.put(attrs, :parent_id, branch.head_event_id),
         {:ok, event} <- Ash.create(Event, attrs, action: :append),
         {:ok, _branch} <- Ash.update(branch, %{head_event_id: event.id}, action: :advance_head),
         {:ok, state} <- derive_state(branch_id) do
      broadcast(branch_id, state)
      {:ok, state, event}
    end
  end

  @doc """
  Loads the ordered event chain from root to the given event_id.
  """
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

    {:ok, binary_id} = Ecto.UUID.dump(event_id)

    case Fate.Repo.query(query, [binary_id]) do
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

  defp broadcast(branch_id, state) do
    Phoenix.PubSub.broadcast(@pubsub, "branch:#{branch_id}", {:state_updated, state})
  end

  def subscribe(branch_id) do
    Phoenix.PubSub.subscribe(@pubsub, "branch:#{branch_id}")
  end
end
