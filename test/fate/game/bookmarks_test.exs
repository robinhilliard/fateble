defmodule Fate.Game.BookmarksTest do
  use Fate.DataCase, async: true

  alias Fate.Game
  alias Fate.Game.Bookmarks

  defp create_bookmark(name \\ "Test") do
    {:ok, root} =
      Game.append_event(%{
        type: :bookmark_create,
        description: name,
        detail: %{"name" => name}
      })

    {:ok, scene} =
      Game.append_event(%{
        parent_id: root.id,
        type: :scene_start,
        description: "Default scene",
        detail: %{"scene_id" => Ash.UUID.generate(), "name" => "No Scene"}
      })

    {:ok, bookmark} =
      Game.create_bookmark(%{
        name: name,
        head_event_id: scene.id
      })

    bookmark
  end

  describe "fork/2" do
    test "creates child bookmark with correct parent reference" do
      parent = create_bookmark("Parent")
      assert {:ok, child} = Bookmarks.fork(parent.id, "Child")

      assert child.name == "Child"
      assert child.parent_bookmark_id == parent.id
      assert child.head_event_id != nil
    end

    test "returns error when bookmark not found" do
      result = Bookmarks.fork(Ash.UUID.generate(), "Orphan")
      assert result == {:error, :not_found} or result == {:error, :no_head_event}
    end
  end

  describe "archive/1" do
    test "sets status to archived" do
      bookmark = create_bookmark("Archivable")
      assert {:ok, archived} = Bookmarks.archive(bookmark.id)
      assert archived.status == :archived
    end
  end

  describe "leaf_bookmark?/1" do
    test "returns true when bookmark has no children" do
      bookmark = create_bookmark("Leaf")
      assert Bookmarks.leaf_bookmark?(bookmark) == true
    end

    test "returns false when bookmark has active children" do
      parent = create_bookmark("Parent")
      {:ok, _child} = Bookmarks.fork(parent.id, "Child")

      {:ok, refreshed} = Game.get_bookmark(parent.id)
      assert Bookmarks.leaf_bookmark?(refreshed) == false
    end
  end

  describe "find_latest_leaf/0" do
    test "returns the newest leaf bookmark" do
      _first = create_bookmark("First")
      second = create_bookmark("Second")

      assert {:ok, found} = Bookmarks.find_latest_leaf()
      assert found.id == second.id
    end

    test "returns :none when no bookmarks exist" do
      assert :none = Bookmarks.find_latest_leaf()
    end
  end
end
