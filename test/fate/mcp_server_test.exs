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
    {:ok, _result_state, event} =
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

  defp create_entity_with_stress(state, name) do
    {:ok, _result_state, event} =
      Engine.append_event(state.bookmark_id, %{
        type: :entity_create,
        description: "Create #{name}",
        detail: %{
          "entity_id" => Ash.UUID.generate(),
          "name" => name,
          "kind" => "pc",
          "fate_points" => 3,
          "refresh" => 3,
          "stress_tracks" => [
            %{"label" => "Physical", "boxes" => 4},
            %{"label" => "Mental", "boxes" => 4}
          ]
        }
      })

    {event.detail["entity_id"], state}
  end

  defp create_mook_group(state, name, count) do
    {:ok, _result_state, event} =
      Engine.append_event(state.bookmark_id, %{
        type: :entity_create,
        description: "Create #{name}",
        detail: %{
          "entity_id" => Ash.UUID.generate(),
          "name" => name,
          "kind" => "mook_group",
          "mook_count" => count
        }
      })

    {event.detail["entity_id"], state}
  end

  defp add_aspect(state, target_id, description, opts \\ []) do
    aspect_id = Ash.UUID.generate()

    {:ok, _, _} =
      Engine.append_event(state.bookmark_id, %{
        type: :aspect_create,
        target_id: target_id,
        description: "Add aspect: #{description}",
        detail: %{
          "aspect_id" => aspect_id,
          "target_id" => target_id,
          "target_type" => Keyword.get(opts, :target_type, "entity"),
          "description" => description,
          "role" => Keyword.get(opts, :role, "situation"),
          "hidden" => Keyword.get(opts, :hidden, false),
          "free_invokes" => Keyword.get(opts, :free_invokes, 0)
        }
      })

    {aspect_id, state}
  end

  defp add_stunt(state, entity_id, name, effect) do
    stunt_id = Ash.UUID.generate()

    {:ok, _, _} =
      Engine.append_event(state.bookmark_id, %{
        type: :stunt_add,
        target_id: entity_id,
        description: "Add stunt: #{name}",
        detail: %{
          "stunt_id" => stunt_id,
          "entity_id" => entity_id,
          "name" => name,
          "effect" => effect
        }
      })

    {stunt_id, state}
  end

  defp get_scene_id(state) do
    {:ok, derived} = Engine.derive_state(state.bookmark_id)
    scene = Enum.find(derived.scenes, &(&1.status == :active))
    scene.id
  end

  defp add_zone(state, scene_id, name) do
    zone_id = Ash.UUID.generate()

    {:ok, _, _} =
      Engine.append_event(state.bookmark_id, %{
        type: :zone_create,
        description: "Create zone: #{name}",
        detail: %{
          "scene_id" => scene_id,
          "zone_id" => zone_id,
          "name" => name,
          "hidden" => false
        }
      })

    {zone_id, state}
  end

  defp take_consequence(state, entity_id, severity, text) do
    {:ok, derived, _} =
      Engine.append_event(state.bookmark_id, %{
        type: :consequence_take,
        target_id: entity_id,
        description: "#{severity}: #{text}",
        detail: %{
          "entity_id" => entity_id,
          "severity" => severity,
          "aspect_text" => text
        }
      })

    entity = Map.get(derived.entities, entity_id)
    consequence = List.last(entity.consequences)
    {consequence.id, state}
  end

  # ── Game overview ──────────────────────────────────────────────────

  describe "get_game" do
    test "returns campaign overview" do
      state = setup_bookmark()

      assert {:ok, [%{type: "text", text: json}], _} =
               McpServer.handle_call_tool("get_game", %{}, state)

      data = Jason.decode!(json)
      assert Map.has_key?(data, "system")
      assert Map.has_key?(data, "entity_count")
      assert Map.has_key?(data, "skill_list")
    end
  end

  # ── Entity CRUD ────────────────────────────────────────────────────

  describe "create_entity" do
    test "creates entity and returns ID" do
      state = setup_bookmark()

      assert {:ok, [%{type: "text", text: text}], _} =
               McpServer.handle_call_tool(
                 "create_entity",
                 %{"name" => "Test Hero", "kind" => "pc"},
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

    test "filters by valid kind" do
      state = setup_bookmark()
      {_id, state} = create_entity(state, "Fighter", "pc")
      {_id, state} = create_entity(state, "Thug", "npc")

      assert {:ok, [%{type: "text", text: json}], _} =
               McpServer.handle_call_tool("list_entities", %{"kind" => "pc"}, state)

      entities = Jason.decode!(json)
      assert length(entities) == 1
      assert hd(entities)["name"] == "Fighter"
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

    test "with valid ID returns entity detail" do
      state = setup_bookmark()
      {entity_id, state} = create_entity(state, "Detailed NPC")

      assert {:ok, [%{type: "text", text: json}], _} =
               McpServer.handle_call_tool("get_entity", %{"entity_id" => entity_id}, state)

      data = Jason.decode!(json)
      assert data["name"] == "Detailed NPC"
      assert data["kind"] == "npc"
    end
  end

  describe "update_entity" do
    test "modifies entity attributes" do
      state = setup_bookmark()
      {entity_id, state} = create_entity(state, "Old Name")

      assert {:ok, [%{type: "text", text: text}], _} =
               McpServer.handle_call_tool(
                 "update_entity",
                 %{"entity_id" => entity_id, "name" => "New Name", "color" => "#ff0000"},
                 state
               )

      assert text =~ "Updated entity"
    end
  end

  describe "remove_entity" do
    test "removes an entity" do
      state = setup_bookmark()
      {entity_id, state} = create_entity(state, "Doomed")

      assert {:ok, [%{type: "text", text: text}], _} =
               McpServer.handle_call_tool("remove_entity", %{"entity_id" => entity_id}, state)

      assert text =~ "removed"
    end
  end

  # ── Aspects ────────────────────────────────────────────────────────

  describe "add_aspect" do
    test "adds aspect to an entity" do
      state = setup_bookmark()
      {entity_id, state} = create_entity(state, "Aspected")

      assert {:ok, [%{type: "text", text: text}], _} =
               McpServer.handle_call_tool(
                 "add_aspect",
                 %{
                   "target_id" => entity_id,
                   "description" => "On Fire!",
                   "role" => "situation"
                 },
                 state
               )

      assert text =~ "On Fire!"
    end

    test "adds aspect to a scene" do
      state = setup_bookmark()
      scene_id = get_scene_id(state)

      assert {:ok, [%{type: "text", text: text}], _} =
               McpServer.handle_call_tool(
                 "add_aspect",
                 %{
                   "target_id" => scene_id,
                   "target_type" => "scene",
                   "description" => "Pitch Black"
                 },
                 state
               )

      assert text =~ "Pitch Black"
    end
  end

  describe "modify_aspect" do
    test "updates aspect description and hidden flag" do
      state = setup_bookmark()
      {entity_id, state} = create_entity(state, "Target")
      {aspect_id, state} = add_aspect(state, entity_id, "Old Aspect")

      assert {:ok, [%{type: "text", text: text}], _} =
               McpServer.handle_call_tool(
                 "modify_aspect",
                 %{"aspect_id" => aspect_id, "description" => "New Aspect", "hidden" => true},
                 state
               )

      assert text =~ "updated"
    end
  end

  describe "remove_aspect" do
    test "removes an aspect" do
      state = setup_bookmark()
      {entity_id, state} = create_entity(state, "Target")
      {aspect_id, _state} = add_aspect(state, entity_id, "Temporary")

      assert {:ok, [%{type: "text", text: text}], _} =
               McpServer.handle_call_tool("remove_aspect", %{"aspect_id" => aspect_id}, state)

      assert text =~ "removed"
    end
  end

  # ── Skills ─────────────────────────────────────────────────────────

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

  # ── Stunts ─────────────────────────────────────────────────────────

  describe "add_stunt" do
    test "adds a stunt to an entity" do
      state = setup_bookmark()
      {entity_id, state} = create_entity(state, "Stunty")

      assert {:ok, [%{type: "text", text: text}], _} =
               McpServer.handle_call_tool(
                 "add_stunt",
                 %{
                   "entity_id" => entity_id,
                   "name" => "Riposte",
                   "effect" => "+2 to Fight when defending in melee"
                 },
                 state
               )

      assert text =~ "Riposte"
    end
  end

  describe "remove_stunt" do
    test "removes a stunt from an entity" do
      state = setup_bookmark()
      {entity_id, state} = create_entity(state, "Stunty")
      {stunt_id, _state} = add_stunt(state, entity_id, "Old Trick", "does a thing")

      assert {:ok, [%{type: "text", text: text}], _} =
               McpServer.handle_call_tool(
                 "remove_stunt",
                 %{"entity_id" => entity_id, "stunt_id" => stunt_id},
                 state
               )

      assert text =~ "removed"
    end
  end

  # ── Scenes and Zones ───────────────────────────────────────────────

  describe "create_scene" do
    test "creates a new scene" do
      state = setup_bookmark()

      assert {:ok, [%{type: "text", text: text}], _} =
               McpServer.handle_call_tool(
                 "create_scene",
                 %{"name" => "Dark Alley", "description" => "A narrow passage"},
                 state
               )

      assert text =~ "Dark Alley"
    end
  end

  describe "list_scenes" do
    test "returns scene data" do
      state = setup_bookmark()

      assert {:ok, [%{type: "text", text: json}], _} =
               McpServer.handle_call_tool("list_scenes", %{}, state)

      scenes = Jason.decode!(json)
      assert length(scenes) >= 1
      assert hd(scenes)["name"] == "Test Scene"
    end
  end

  describe "scene_modify" do
    test "updates scene name and description" do
      state = setup_bookmark()
      scene_id = get_scene_id(state)

      assert {:ok, [%{type: "text", text: text}], _} =
               McpServer.handle_call_tool(
                 "scene_modify",
                 %{"scene_id" => scene_id, "name" => "Renamed Scene"},
                 state
               )

      assert text =~ "updated"
    end
  end

  describe "end_scene" do
    test "ends an active scene" do
      state = setup_bookmark()
      scene_id = get_scene_id(state)

      assert {:ok, [%{type: "text", text: text}], _} =
               McpServer.handle_call_tool("end_scene", %{"scene_id" => scene_id}, state)

      assert text =~ "ended"
    end
  end

  describe "add_zone" do
    test "creates a zone in a scene" do
      state = setup_bookmark()
      scene_id = get_scene_id(state)

      assert {:ok, [%{type: "text", text: text}], _} =
               McpServer.handle_call_tool(
                 "add_zone",
                 %{"scene_id" => scene_id, "name" => "Rooftops"},
                 state
               )

      assert text =~ "Rooftops"
    end
  end

  describe "modify_zone" do
    test "updates zone attributes" do
      state = setup_bookmark()
      scene_id = get_scene_id(state)
      {zone_id, _state} = add_zone(state, scene_id, "Old Zone")

      assert {:ok, [%{type: "text", text: text}], _} =
               McpServer.handle_call_tool(
                 "modify_zone",
                 %{"zone_id" => zone_id, "name" => "Renamed Zone"},
                 state
               )

      assert text =~ "updated"
    end
  end

  # ── Stress and Consequences ────────────────────────────────────────

  describe "stress_apply" do
    test "applies stress to a track box" do
      state = setup_bookmark()
      {entity_id, state} = create_entity_with_stress(state, "Tough")

      assert {:ok, [%{type: "text", text: text}], _} =
               McpServer.handle_call_tool(
                 "stress_apply",
                 %{
                   "entity_id" => entity_id,
                   "track_label" => "Physical",
                   "box_index" => 1
                 },
                 state
               )

      assert text =~ "Physical"
      assert text =~ "1"
    end
  end

  describe "clear_stress" do
    test "clears all stress on an entity" do
      state = setup_bookmark()
      {entity_id, state} = create_entity_with_stress(state, "Battered")

      McpServer.handle_call_tool(
        "stress_apply",
        %{"entity_id" => entity_id, "track_label" => "Physical", "box_index" => 1},
        state
      )

      assert {:ok, [%{type: "text", text: text}], _} =
               McpServer.handle_call_tool("clear_stress", %{"entity_id" => entity_id}, state)

      assert text =~ "cleared"
    end
  end

  describe "consequence_take" do
    test "applies a consequence to an entity" do
      state = setup_bookmark()
      {entity_id, state} = create_entity_with_stress(state, "Wounded")

      assert {:ok, [%{type: "text", text: text}], _} =
               McpServer.handle_call_tool(
                 "consequence_take",
                 %{
                   "entity_id" => entity_id,
                   "severity" => "mild",
                   "aspect_text" => "Sprained Ankle"
                 },
                 state
               )

      assert text =~ "mild"
      assert text =~ "Sprained Ankle"
    end
  end

  describe "consequence_recover" do
    test "begins recovery on a consequence" do
      state = setup_bookmark()
      {entity_id, state} = create_entity_with_stress(state, "Healing")
      {consequence_id, state} = take_consequence(state, entity_id, "mild", "Bruised Ribs")

      assert {:ok, [%{type: "text", text: text}], _} =
               McpServer.handle_call_tool(
                 "consequence_recover",
                 %{
                   "entity_id" => entity_id,
                   "consequence_id" => consequence_id,
                   "new_aspect_text" => "Healing Ribs"
                 },
                 state
               )

      assert text =~ "Recovery started"
    end

    test "clears a consequence entirely" do
      state = setup_bookmark()
      {entity_id, state} = create_entity_with_stress(state, "Recovered")
      {consequence_id, state} = take_consequence(state, entity_id, "mild", "Scratch")

      assert {:ok, [%{type: "text", text: text}], _} =
               McpServer.handle_call_tool(
                 "consequence_recover",
                 %{
                   "entity_id" => entity_id,
                   "consequence_id" => consequence_id,
                   "clear" => true
                 },
                 state
               )

      assert text =~ "cleared"
    end
  end

  # ── Fate Points ────────────────────────────────────────────────────

  describe "fate_point_spend" do
    test "spends fate points" do
      state = setup_bookmark()
      {entity_id, state} = create_entity(state, "Spender", "pc")

      assert {:ok, [%{type: "text", text: text}], _} =
               McpServer.handle_call_tool(
                 "fate_point_spend",
                 %{"entity_id" => entity_id},
                 state
               )

      assert text =~ "Spent 1 FP"
    end
  end

  describe "fate_point_earn" do
    test "earns fate points" do
      state = setup_bookmark()
      {entity_id, state} = create_entity(state, "Earner", "pc")

      assert {:ok, [%{type: "text", text: text}], _} =
               McpServer.handle_call_tool(
                 "fate_point_earn",
                 %{"entity_id" => entity_id},
                 state
               )

      assert text =~ "Earned 1 FP"
    end
  end

  describe "fate_point_refresh" do
    test "refreshes fate points" do
      state = setup_bookmark()
      {entity_id, state} = create_entity(state, "Refresher", "pc")

      assert {:ok, [%{type: "text", text: text}], _} =
               McpServer.handle_call_tool(
                 "fate_point_refresh",
                 %{"entity_id" => entity_id},
                 state
               )

      assert text =~ "refreshed"
    end
  end

  # ── Aspect Actions ────────────────────────────────────────────────

  describe "invoke_aspect" do
    test "invokes an aspect with free invoke" do
      state = setup_bookmark()
      {entity_id, state} = create_entity(state, "Invoker", "pc")

      assert {:ok, [%{type: "text", text: text}], _} =
               McpServer.handle_call_tool(
                 "invoke_aspect",
                 %{
                   "entity_id" => entity_id,
                   "description" => "On Fire!",
                   "free" => true
                 },
                 state
               )

      assert text =~ "Invoked"
      assert text =~ "On Fire!"
    end

    test "invokes an aspect spending a fate point" do
      state = setup_bookmark()
      {entity_id, state} = create_entity(state, "Spender", "pc")

      assert {:ok, [%{type: "text", text: text}], _} =
               McpServer.handle_call_tool(
                 "invoke_aspect",
                 %{
                   "entity_id" => entity_id,
                   "description" => "Sharp Instincts"
                 },
                 state
               )

      assert text =~ "Invoked"
    end
  end

  describe "compel_aspect" do
    test "compels an aspect and earns a fate point" do
      state = setup_bookmark()
      {entity_id, state} = create_entity(state, "Compelled", "pc")

      assert {:ok, [%{type: "text", text: text}], _} =
               McpServer.handle_call_tool(
                 "compel_aspect",
                 %{
                   "entity_id" => entity_id,
                   "description" => "Can't Resist a Challenge"
                 },
                 state
               )

      assert text =~ "Compelled"
      assert text =~ "earned 1 FP"
    end
  end

  # ── Combat Actions ────────────────────────────────────────────────

  describe "concede" do
    test "marks an entity as conceding" do
      state = setup_bookmark()
      {entity_id, state} = create_entity(state, "Yielder", "pc")

      assert {:ok, [%{type: "text", text: text}], _} =
               McpServer.handle_call_tool("concede", %{"entity_id" => entity_id}, state)

      assert text =~ "conceded"
    end
  end

  describe "taken_out" do
    test "marks an entity as taken out" do
      state = setup_bookmark()
      {entity_id, state} = create_entity(state, "Defeated", "npc")

      assert {:ok, [%{type: "text", text: text}], _} =
               McpServer.handle_call_tool("taken_out", %{"entity_id" => entity_id}, state)

      assert text =~ "taken out"
    end
  end

  describe "mook_eliminate" do
    test "eliminates mooks from a group" do
      state = setup_bookmark()
      {entity_id, state} = create_mook_group(state, "Thugs", 5)

      assert {:ok, [%{type: "text", text: text}], _} =
               McpServer.handle_call_tool(
                 "mook_eliminate",
                 %{"entity_id" => entity_id, "count" => 2},
                 state
               )

      assert text =~ "2 mook(s) eliminated"
    end
  end

  describe "redirect_hit" do
    test "redirects a hit between entities" do
      state = setup_bookmark()
      {from_id, state} = create_entity(state, "Protector")
      {to_id, _state} = create_entity(state, "Protected")

      assert {:ok, [%{type: "text", text: text}], _} =
               McpServer.handle_call_tool(
                 "redirect_hit",
                 %{"from_entity_id" => from_id, "to_entity_id" => to_id},
                 state
               )

      assert text =~ "redirected"
    end
  end

  describe "entity_move" do
    test "moves entity to a zone" do
      state = setup_bookmark()
      {entity_id, state} = create_entity(state, "Runner")
      scene_id = get_scene_id(state)
      {zone_id, _state} = add_zone(state, scene_id, "Back Alley")

      assert {:ok, [%{type: "text", text: text}], _} =
               McpServer.handle_call_tool(
                 "entity_move",
                 %{"entity_id" => entity_id, "zone_id" => zone_id},
                 state
               )

      assert text =~ "Moved to zone"
    end

    test "removes entity from zone" do
      state = setup_bookmark()
      {entity_id, state} = create_entity(state, "Leaver")

      assert {:ok, [%{type: "text", text: text}], _} =
               McpServer.handle_call_tool(
                 "entity_move",
                 %{"entity_id" => entity_id},
                 state
               )

      assert text =~ "Left zone"
    end
  end

  # ── Dice ───────────────────────────────────────────────────────────

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

    test "with difficulty returns outcome and shifts" do
      state = setup_bookmark()
      {entity_id, state} = create_entity(state, "Tested")

      Engine.append_event(state.bookmark_id, %{
        type: :skill_set,
        target_id: entity_id,
        description: "Set Notice",
        detail: %{"entity_id" => entity_id, "skill" => "Notice", "rating" => 2}
      })

      assert {:ok, [%{type: "text", text: json}], _} =
               McpServer.handle_call_tool(
                 "roll_dice",
                 %{
                   "entity_id" => entity_id,
                   "skill" => "Notice",
                   "action" => "overcome",
                   "difficulty" => 2
                 },
                 state
               )

      result = Jason.decode!(json)
      assert Map.has_key?(result, "outcome")
      assert Map.has_key?(result, "shifts")
      assert result["outcome"] in ["fail", "tie", "succeed", "succeed_with_style"]
    end
  end

  # ── Bookmarks ──────────────────────────────────────────────────────

  describe "create_bookmark" do
    test "creates a named bookmark" do
      state = setup_bookmark()

      assert {:ok, [%{type: "text", text: text}], _} =
               McpServer.handle_call_tool(
                 "create_bookmark",
                 %{"name" => "Milestone One", "description" => "Before the fight"},
                 state
               )

      assert text =~ "Milestone One"
    end
  end

  describe "list_bookmarks" do
    test "includes current bookmark flag" do
      state = setup_bookmark()

      assert {:ok, [%{type: "text", text: json}], _} =
               McpServer.handle_call_tool("list_bookmarks", %{}, state)

      bookmarks = Jason.decode!(json)
      current = Enum.find(bookmarks, & &1["current"])
      assert current != nil
      assert current["name"] == "Test Bookmark"
    end
  end

  describe "fork_from_bookmark" do
    test "creates a forked bookmark" do
      state = setup_bookmark()

      assert {:ok, [%{type: "text", text: text}], _} =
               McpServer.handle_call_tool(
                 "fork_from_bookmark",
                 %{"bookmark_name" => "Test Bookmark", "new_name" => "What If?"},
                 state
               )

      assert text =~ "What If?"
      assert text =~ "forked from"
    end

    test "returns error for nonexistent bookmark" do
      state = setup_bookmark()

      assert {:error, %{message: msg}, _} =
               McpServer.handle_call_tool(
                 "fork_from_bookmark",
                 %{"bookmark_name" => "Nonexistent", "new_name" => "Nope"},
                 state
               )

      assert msg =~ "not found"
    end
  end

  describe "switch_bookmark" do
    test "switches by bookmark ID" do
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
                 %{"bookmark_id" => bookmark2.id},
                 state
               )

      assert new_state.bookmark_id == bookmark2.id
      assert text =~ "Second Bookmark"
    end

    test "switches by bookmark name" do
      state = setup_bookmark()

      assert {:ok, [%{type: "text", text: text}], new_state} =
               McpServer.handle_call_tool(
                 "switch_bookmark",
                 %{"bookmark_name" => "Test Bookmark"},
                 state
               )

      assert new_state.bookmark_id == state.bookmark_id
      assert text =~ "Test Bookmark"
    end

    test "returns error for nonexistent bookmark" do
      state = setup_bookmark()

      assert {:error, %{message: msg}, _} =
               McpServer.handle_call_tool(
                 "switch_bookmark",
                 %{"bookmark_name" => "No Such Bookmark"},
                 state
               )

      assert msg =~ "not found"
    end
  end

  describe "delete_bookmark" do
    test "archives a bookmark by name" do
      state = setup_bookmark()

      McpServer.handle_call_tool(
        "create_bookmark",
        %{"name" => "Disposable"},
        state
      )

      assert {:ok, [%{type: "text", text: text}], _} =
               McpServer.handle_call_tool(
                 "delete_bookmark",
                 %{"bookmark_name" => "Disposable"},
                 state
               )

      assert text =~ "Archived"
      assert text =~ "Disposable"
    end

    test "returns error for nonexistent bookmark" do
      state = setup_bookmark()

      assert {:error, %{message: msg}, _} =
               McpServer.handle_call_tool(
                 "delete_bookmark",
                 %{"bookmark_name" => "Ghost"},
                 state
               )

      assert msg =~ "not found"
    end
  end

  # ── Notes and Timeline ────────────────────────────────────────────

  describe "add_note" do
    test "adds a general note" do
      state = setup_bookmark()

      assert {:ok, [%{type: "text", text: text}], _} =
               McpServer.handle_call_tool(
                 "add_note",
                 %{"text" => "The party decided to go left"},
                 state
               )

      assert text =~ "Note added"
      assert text =~ "party decided"
    end

    test "adds a note about an entity" do
      state = setup_bookmark()
      {entity_id, state} = create_entity(state, "Notable")

      assert {:ok, [%{type: "text", text: text}], _} =
               McpServer.handle_call_tool(
                 "add_note",
                 %{
                   "text" => "Seemed suspicious",
                   "target_id" => entity_id,
                   "target_type" => "entity"
                 },
                 state
               )

      assert text =~ "Note added"
    end
  end

  describe "search_notes" do
    test "finds notes matching a query" do
      state = setup_bookmark()

      McpServer.handle_call_tool("add_note", %{"text" => "The dragon appeared"}, state)
      McpServer.handle_call_tool("add_note", %{"text" => "The tavern was empty"}, state)

      assert {:ok, [%{type: "text", text: text}], _} =
               McpServer.handle_call_tool("search_notes", %{"query" => "dragon"}, state)

      assert text =~ "Found 1 notes"
      assert text =~ "dragon"
    end

    test "returns all notes when no query given" do
      state = setup_bookmark()

      McpServer.handle_call_tool("add_note", %{"text" => "Note one"}, state)
      McpServer.handle_call_tool("add_note", %{"text" => "Note two"}, state)

      assert {:ok, [%{type: "text", text: text}], _} =
               McpServer.handle_call_tool("search_notes", %{}, state)

      assert text =~ "Found 2 notes"
    end
  end

  describe "get_action_log" do
    test "returns recent events" do
      state = setup_bookmark()
      {_id, state} = create_entity(state, "Logged")

      assert {:ok, [%{type: "text", text: json}], _} =
               McpServer.handle_call_tool("get_action_log", %{"limit" => 5}, state)

      events = Jason.decode!(json)
      assert is_list(events)
      assert length(events) >= 1
    end
  end

  describe "summarise_timeline" do
    test "returns structured timeline payload" do
      state = setup_bookmark()
      {_id, state} = create_entity(state, "Hero")

      assert {:ok, [%{type: "text", text: json}], _} =
               McpServer.handle_call_tool(
                 "summarise_timeline",
                 %{"style" => "narrative"},
                 state
               )

      payload = Jason.decode!(json)
      assert Map.has_key?(payload, "events")
      assert Map.has_key?(payload, "entities")
      assert Map.has_key?(payload, "scenes")
      assert payload["style"] == "narrative"
    end
  end

  # ── System ─────────────────────────────────────────────────────────

  describe "set_system" do
    test "changes the game system" do
      state = setup_bookmark()

      assert {:ok, [%{type: "text", text: text}], _} =
               McpServer.handle_call_tool(
                 "set_system",
                 %{
                   "system" => "accelerated",
                   "skill_list" => ~w(Careful Clever Flashy Forceful Quick Sneaky)
                 },
                 state
               )

      assert text =~ "accelerated"
    end
  end

  describe "delete_event" do
    test "deletes an event from the chain" do
      state = setup_bookmark()

      {:ok, _, event} =
        Engine.append_event(state.bookmark_id, %{
          type: :note,
          description: "Deletable note",
          detail: %{"text" => "Delete me"}
        })

      assert {:ok, [%{type: "text", text: text}], _} =
               McpServer.handle_call_tool("delete_event", %{"event_id" => event.id}, state)

      assert text =~ "deleted"
    end
  end

  # ── Unknown Tool ───────────────────────────────────────────────────

  describe "unknown tool" do
    test "returns -32601 error" do
      state = setup_bookmark()

      assert {:error, %{code: -32601, message: msg}, _} =
               McpServer.handle_call_tool("nonexistent_tool", %{}, state)

      assert msg =~ "Unknown tool"
    end
  end
end
