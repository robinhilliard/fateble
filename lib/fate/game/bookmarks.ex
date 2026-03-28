defmodule Fate.Game.Bookmarks do
  @moduledoc """
  Context functions for bookmark lifecycle operations:
  listing, forking, archiving, loading participants, and bootstrapping.
  """

  alias Fate.Game
  alias Fate.Game.{Bookmark, BookmarkParticipant}

  require Ash.Query

  def list_active do
    case Ash.read(
           Bookmark
           |> Ash.Query.filter(status: :active)
           |> Ash.Query.sort(created_at: :asc)
         ) do
      {:ok, bookmarks} -> bookmarks
      _ -> []
    end
  end

  def fork(bookmark_id, name \\ nil) do
    case Game.get_bookmark(bookmark_id) do
      {:ok, %{head_event_id: head_id, name: bm_name} = parent} when head_id != nil ->
        fork_name = name || "Fork: #{bm_name}"

        with {:ok, bmk_event} <-
               Game.append_event(%{
                 parent_id: head_id,
                 type: :bookmark_create,
                 description: fork_name,
                 detail: %{"name" => fork_name}
               }),
             {:ok, new_bm} <-
               Game.create_bookmark(%{
                 name: fork_name,
                 head_event_id: bmk_event.id,
                 parent_bookmark_id: parent.id
               }) do
          {:ok, new_bm}
        end

      {:ok, _} ->
        {:error, :no_head_event}

      _ ->
        {:error, :not_found}
    end
  end

  def archive(bookmark_id) do
    case Game.get_bookmark(bookmark_id) do
      {:ok, bookmark} when bookmark != nil ->
        Game.set_status(bookmark, %{status: :archived})

      _ ->
        {:error, :not_found}
    end
  end

  def load_participants(bookmark_id) do
    BookmarkParticipant
    |> Ash.Query.filter(bookmark_id: bookmark_id)
    |> Ash.Query.load(:participant)
    |> Ash.read!()
  rescue
    e ->
      require Logger
      Logger.error("Failed to load participants: #{inspect(e)}")
      []
  end

  def leaf_bookmark?(bookmark) do
    case Ash.read(
           Bookmark
           |> Ash.Query.filter(parent_bookmark_id: bookmark.id, status: :active)
         ) do
      {:ok, []} -> true
      _ -> false
    end
  end

  def find_latest_leaf do
    case Ash.read(
           Bookmark
           |> Ash.Query.filter(status: :active)
           |> Ash.Query.load(:head_event)
           |> Ash.Query.sort(created_at: :desc)
         ) do
      {:ok, [_ | _] = bookmarks} ->
        bookmarks
        |> Enum.filter(&leaf_bookmark?/1)
        |> Enum.max_by(fn b -> b.head_event && b.head_event.timestamp end, DateTime, fn -> nil end)
        |> case do
          nil -> {:ok, List.first(bookmarks)}
          b -> {:ok, b}
        end

      _ ->
        :none
    end
  end
end
