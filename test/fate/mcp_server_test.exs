defmodule Fate.McpServerTest do
  use Fate.DataCase, async: true

  alias Fate.McpServer
  alias Fate.Game
  alias Fate.Engine

  defp setup_bookmark do
    {:ok, root} =
      Game.append_event(%{
        type: :bookmark_create,
        description: "Test",
        detail: %{"name" => "Test"}
      })

    {:ok, scene} =
      Game.append_event(%{
        parent_id: root.id,
        type: :scene_start,
        description: "Default",
        detail: %{"scene_id" => Ash.UUID.generate(), "name" => "Test Scene"}
      })

    {:ok, bookmark} =
      Game.create_bookmark(%{
        name: "Test Bookmark",
        head_event_id: scene.id
      })

    %{bookmark_id: bookmark.id}
  end

  defp create_entity(state, name, kind \\ "npc") do
    {:ok, result_state, event} =
      Engine.append_event(state.bookmark_id, %{
        type: :entity_create,
        description: "Create #{name}",
        detail: %{
          "entity_id" => Ash.UUID.generate(),
          "name" => name,
          "kind" => kind,
          "fate_points" => 3,
          "refresh" => 3
        }
      })

    entity_id = event.detail["entity_id"]
    {entity_id, state}
  end

  describe "get_game" do
    test "returns campaign overview" do
      state = setup_bookmark()

      assert {:ok, [%{type: "text", text: json}], _} =
               McpServer.handle_call_tool("get_game", %{}, state)

      data = Jason.decode!(json)
      assert Map.has_key?(data, "system")
      assert Map.has_key?(data, "entity_count")
    end
  end

  describe "create_entity" do
    test "creates entity and returns ID" do
      state = setup_bookmark()

      assert {:ok, [%{type: "text", text: text}], _} =
               McpServer.handle_call_tool(
                 "create_entity",
                 %{
                   "name" => "Test Hero",
                   "kind" => "pc"
                 },
                 state
               )

      assert text =~ "Test Hero"
      assert text =~ "pc"
    end
  end

  describe "list_entities" do
    test "with invalid kind filter returns all entities" do
      state = setup_bookmark()
      {_id, state} = create_entity(state, "NPC One")
      {_id, state} = create_entity(state, "NPC Two")

      assert {:ok, [%{type: "text", text: json}], _} =
               McpServer.handle_call_tool("list_entities", %{"kind" => "invalid_kind"}, state)

      entities = Jason.decode!(json)
      assert length(entities) >= 2
    end
  end

  describe "get_entity" do
    test "with nonexistent ID returns ok with not-found text" do
      state = setup_bookmark()
      fake_id = Ash.UUID.generate()

      assert {:ok, [%{type: "text", text: text}], _} =
               McpServer.handle_call_tool("get_entity", %{"entity_id" => fake_id}, state)

      assert text =~ "Entity not found"
    end
  end

  describe "set_skill" do
    test "sets multiple skills in one call" do
      state = setup_bookmark()
      {entity_id, state} = create_entity(state, "Skilled")

      assert {:ok, [%{type: "text", text: text}], _} =
               McpServer.handle_call_tool(
                 "set_skill",
                 %{
                   "entity_id" => entity_id,
                   "skills" => %{"Fight" => 4, "Athletics" => 3}
                 },
                 state
               )

      assert text =~ "Fight"
      assert text =~ "Athletics"
    end
  end

  describe "switch_bookmark" do
    test "updates server state bookmark_id" do
      state = setup_bookmark()

      {:ok, root2} =
        Game.append_event(%{
          type: :bookmark_create,
          description: "Second",
          detail: %{"name" => "Second"}
        })

      {:ok, scene2} =
        Game.append_event(%{
          parent_id: root2.id,
          type: :scene_start,
          description: "Scene",
          detail: %{"scene_id" => Ash.UUID.generate(), "name" => "Scene"}
        })

      {:ok, bookmark2} =
        Game.create_bookmark(%{
          name: "Second Bookmark",
          head_event_id: scene2.id
        })

      assert {:ok, [%{type: "text", text: text}], new_state} =
               McpServer.handle_call_tool(
                 "switch_bookmark",
                 %{
                   "bookmark_id" => bookmark2.id
                 },
                 state
               )

      assert new_state.bookmark_id == bookmark2.id
      assert text =~ "Second Bookmark"
    end
  end

  describe "roll_dice" do
    test "returns dice array and total" do
      state = setup_bookmark()
      {entity_id, state} = create_entity(state, "Roller")

      Engine.append_event(state.bookmark_id, %{
        type: :skill_set,
        target_id: entity_id,
        description: "Set Fight",
        detail: %{"entity_id" => entity_id, "skill" => "Fight", "rating" => 3}
      })

      assert {:ok, [%{type: "text", text: json}], _} =
               McpServer.handle_call_tool(
                 "roll_dice",
                 %{
                   "entity_id" => entity_id,
                   "skill" => "Fight",
                   "action" => "attack"
                 },
                 state
               )

      result = Jason.decode!(json)
      assert length(result["dice"]) == 4
      assert is_integer(result["total"])
      assert result["action"] == "attack"
    end
  end

  describe "unknown tool" do
    test "returns -32601 error" do
      state = setup_bookmark()

      assert {:error, %{code: -32601, message: msg}, _} =
               McpServer.handle_call_tool("nonexistent_tool", %{}, state)

      assert msg =~ "Unknown tool"
    end
  end
end
