defmodule Fate.EngineTest do
  use Fate.DataCase, async: true

  alias Fate.Engine
  alias Fate.Game

  defp create_bookmark do
    {:ok, root_event} =
      Game.append_event(%{
        type: :bookmark_create,
        description: "Test",
        detail: %{"name" => "Test"}
      })

    {:ok, scene_event} =
      Game.append_event(%{
        parent_id: root_event.id,
        type: :scene_start,
        description: "Default scene",
        detail: %{
          "scene_id" => Ash.UUID.generate(),
          "name" => "No Scene"
        }
      })

    {:ok, bookmark} =
      Game.create_bookmark(%{
        name: "Test Bookmark",
        head_event_id: scene_event.id
      })

    {bookmark, [root_event, scene_event]}
  end

  describe "derive_state/1" do
    test "returns derived state for valid bookmark" do
      {bookmark, _events} = create_bookmark()
      assert {:ok, state} = Engine.derive_state(bookmark.id)
      assert state.bookmark_id == bookmark.id
      assert length(state.scenes) == 1
    end

    test "returns error for nonexistent bookmark" do
      assert {:error, :not_found} = Engine.derive_state(Ash.UUID.generate())
    end
  end

  describe "append_event/2" do
    test "creates event, advances head, and returns updated state" do
      {bookmark, _} = create_bookmark()

      assert {:ok, state, event} =
               Engine.append_event(bookmark.id, %{
                 type: :entity_create,
                 description: "Create hero",
                 detail: %{
                   "entity_id" => Ash.UUID.generate(),
                   "name" => "Hero",
                   "kind" => "pc"
                 }
               })

      assert Map.has_key?(state.entities, event.detail["entity_id"])

      {:ok, refreshed} = Game.get_bookmark(bookmark.id)
      assert refreshed.head_event_id == event.id
    end
  end

  describe "load_event_chain/1" do
    test "returns events in timestamp order" do
      {_bookmark, [root, scene]} = create_bookmark()
      {:ok, chain} = Engine.load_event_chain(scene.id)

      assert length(chain) == 2
      [first, second] = chain
      assert first.type == :bookmark_create
      assert second.type == :scene_start
    end

    test "returns empty list for nil" do
      assert {:ok, []} = Engine.load_event_chain(nil)
    end
  end

  describe "load_player_events/1" do
    test "stops at bookmark_create boundary for forked bookmarks" do
      {parent, _} = create_bookmark()

      {:ok, child} = Fate.Game.Bookmarks.fork(parent.id, "Child")

      Engine.append_event(child.id, %{
        type: :entity_create,
        description: "Create NPC",
        detail: %{"entity_id" => Ash.UUID.generate(), "name" => "NPC", "kind" => "npc"}
      })

      {:ok, events} = Engine.load_player_events(child.id)
      types = Enum.map(events, & &1.type)
      assert :entity_create in types
      assert :bookmark_create in types
      refute :scene_start in types
    end
  end
end
