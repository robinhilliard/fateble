defmodule Fate.Game.EventsTest do
  use Fate.DataCase, async: true

  alias Fate.Game
  alias Fate.Game.Events
  alias Fate.Engine

  defp create_chain do
    {:ok, e1} =
      Game.append_event(%{
        type: :bookmark_create,
        description: "Root",
        detail: %{"name" => "Root"}
      })

    {:ok, e2} =
      Game.append_event(%{
        parent_id: e1.id,
        type: :scene_start,
        description: "Scene",
        detail: %{"scene_id" => Ash.UUID.generate(), "name" => "Scene"}
      })

    {:ok, e3} =
      Game.append_event(%{
        parent_id: e2.id,
        type: :entity_create,
        description: "Entity",
        detail: %{"entity_id" => Ash.UUID.generate(), "name" => "NPC", "kind" => "npc"}
      })

    {:ok, bookmark} =
      Game.create_bookmark(%{
        name: "Test",
        head_event_id: e3.id
      })

    {bookmark, [e1, e2, e3]}
  end

  describe "reorder/3" do
    test "moves event to new position in chain" do
      {bookmark, [e1, e2, e3]} = create_chain()

      assert :ok = Events.reorder(e3.id, e1.id, bookmark.id)

      {:ok, chain} = Engine.load_event_chain(bookmark.head_event_id)
      ids = Enum.map(chain, & &1.id)
      e3_pos = Enum.find_index(ids, &(&1 == e3.id))
      e1_pos = Enum.find_index(ids, &(&1 == e1.id))
      assert e3_pos > e1_pos
    end

    test "noop when event is already in position" do
      {bookmark, [_e1, e2, e3]} = create_chain()
      assert :ok = Events.reorder(e3.id, e2.id, bookmark.id)
    end
  end

  describe "delete/2" do
    test "removes event and reparents children" do
      {bookmark, [e1, e2, e3]} = create_chain()

      assert :ok = Events.delete(e2.id, bookmark.id)

      {:ok, refreshed_e3} = Game.get_event(e3.id)
      assert refreshed_e3.parent_id == e1.id
    end

    test "updates bookmark head when deleting the head event" do
      {bookmark, [_e1, e2, e3]} = create_chain()

      assert :ok = Events.delete(e3.id, bookmark.id)

      {:ok, refreshed} = Game.get_bookmark(bookmark.id)
      assert refreshed.head_event_id == e2.id
    end
  end
end
