defmodule Fate.Engine.ReplayTest do
  use ExUnit.Case, async: true

  alias Fate.Engine.Replay
  alias Fate.Engine.State.DerivedState
  import Fate.EventFactory

  describe "derive/2" do
    test "empty events returns default state" do
      state = Replay.derive("bm-1", [])

      assert %DerivedState{} = state
      assert state.bookmark_id == "bm-1"
      assert state.head_event_id == nil
      assert state.entities == %{}
      assert state.scene_templates == []
      assert state.system == "core"
    end

    test "create_campaign sets campaign_name" do
      events = [
        build_event(:create_campaign, %{"campaign_name" => "The Iron Carnival"})
      ]

      state = Replay.derive("bm-1", events)
      assert state.campaign_name == "The Iron Carnival"
    end

    test "set_system sets system and populates skill_list" do
      events = [
        build_event(:set_system, %{"system" => "accelerated"})
      ]

      state = Replay.derive("bm-1", events)
      assert state.system == "accelerated"
      assert "Careful" in state.skill_list
      assert "Sneaky" in state.skill_list
      refute "Athletics" in state.skill_list
    end

    test "set_system with core uses default core skills" do
      events = [build_event(:set_system, %{"system" => "core"})]

      state = Replay.derive("bm-1", events)
      assert state.system == "core"
      assert "Athletics" in state.skill_list
      assert "Will" in state.skill_list
    end

    test "entity_create adds entity with correct fields" do
      {entity_id, event} =
        entity_create("Hero",
          kind: "pc",
          fate_points: 3,
          refresh: 3,
          aspects: [%{"description" => "Strong", "role" => "high_concept"}],
          skills: %{"Fight" => 4, "Athletics" => 3},
          stunts: [%{"name" => "Riposte", "effect" => "+2 to Fight"}],
          stress_tracks: [%{"label" => "physical", "boxes" => 3}]
        )

      state = Replay.derive("bm-1", [event])

      assert Map.has_key?(state.entities, entity_id)
      entity = state.entities[entity_id]
      assert entity.name == "Hero"
      assert entity.kind == :pc
      assert entity.fate_points == 3
      assert entity.refresh == 3
      assert length(entity.aspects) == 1
      assert hd(entity.aspects).description == "Strong"
      assert entity.skills["Fight"] == 4
      assert entity.skills["Athletics"] == 3
      assert length(entity.stunts) == 1
      assert hd(entity.stunts).name == "Riposte"
      assert length(entity.stress_tracks) == 1
      assert hd(entity.stress_tracks).boxes == 3
    end

    test "entity_modify updates existing entity fields" do
      {entity_id, create} = entity_create("Original", kind: "npc")

      modify =
        build_event(
          :entity_modify,
          %{
            "entity_id" => entity_id,
            "name" => "Renamed"
          },
          target_id: entity_id
        )

      state = Replay.derive("bm-1", [create, modify])
      assert state.entities[entity_id].name == "Renamed"
    end

    test "entity_remove deletes entity from state" do
      {entity_id, create} = entity_create("Doomed")
      remove = build_event(:entity_remove, %{"entity_id" => entity_id}, target_id: entity_id)

      state = Replay.derive("bm-1", [create, remove])
      refute Map.has_key?(state.entities, entity_id)
    end

    test "aspect_create on entity adds aspect" do
      {entity_id, create} = entity_create("Target")
      {aspect_id, add_aspect} = aspect_create(entity_id, "Quick Reflexes", target_type: "entity")

      state = Replay.derive("bm-1", [create, add_aspect])
      entity = state.entities[entity_id]
      assert length(entity.aspects) == 1
      assert hd(entity.aspects).id == aspect_id
      assert hd(entity.aspects).description == "Quick Reflexes"
    end

    test "aspect_create on scene adds aspect to scene" do
      {scene_id, scene} = scene_start("Battle")

      {_aspect_id, add_aspect} =
        aspect_create(scene_id, "Flickering Torchlight", target_type: "scene")

      state = Replay.derive("bm-1", List.flatten([scene, add_aspect]))
      assert length(state.active_scene.aspects) == 1
      assert hd(state.active_scene.aspects).description == "Flickering Torchlight"
    end

    test "aspect_create on zone adds aspect to zone" do
      {scene_id, scene} = scene_start("Battle")
      {zone_id, zone} = zone_create(scene_id, "Alley")
      {_aspect_id, add_aspect} = aspect_create(zone_id, "Dark Shadows", target_type: "zone")

      state = Replay.derive("bm-1", List.flatten([scene, zone, add_aspect]))
      zone_state = hd(state.active_scene.zones)
      assert length(zone_state.aspects) == 1
      assert hd(zone_state.aspects).description == "Dark Shadows"
    end

    test "aspect_modify toggles hidden flag" do
      {entity_id, create} = entity_create("Target")
      {aspect_id, add_aspect} = aspect_create(entity_id, "Hidden Trait")
      modify = build_event(:aspect_modify, %{"aspect_id" => aspect_id, "hidden" => true})

      state = Replay.derive("bm-1", [create, add_aspect, modify])
      aspect = hd(state.entities[entity_id].aspects)
      assert aspect.hidden == true
    end

    test "aspect_modify with target_type only touches that container" do
      {entity_id, create} = entity_create("Hero")
      {scene_id, scene} = scene_start("Fight")
      {asp_entity, add_ent} = aspect_create(entity_id, "Tough", target_type: "entity")
      {_asp_scene, add_scene} = aspect_create(scene_id, "Dark", target_type: "scene")

      modify_entity =
        build_event(:aspect_modify, %{
          "aspect_id" => asp_entity,
          "hidden" => true,
          "target_type" => "entity",
          "target_id" => entity_id
        })

      state =
        Replay.derive("bm-1", List.flatten([create, scene, add_ent, add_scene, modify_entity]))

      assert hd(state.entities[entity_id].aspects).hidden == true
      refute hd(state.active_scene.aspects).hidden
    end

    test "aspect_remove with target_type only touches that container" do
      {entity_id, create} = entity_create("Hero")
      {asp_entity, add_ent} = aspect_create(entity_id, "Tmp", target_type: "entity")

      remove =
        build_event(:aspect_remove, %{
          "aspect_id" => asp_entity,
          "target_type" => "entity",
          "target_id" => entity_id
        })

      state = Replay.derive("bm-1", [create, add_ent, remove])
      assert state.entities[entity_id].aspects == []
    end

    test "aspect_remove removes aspect from entity" do
      {entity_id, create} = entity_create("Target")
      {aspect_id, add_aspect} = aspect_create(entity_id, "Temporary")
      remove = build_event(:aspect_remove, %{"aspect_id" => aspect_id})

      state = Replay.derive("bm-1", [create, add_aspect, remove])
      assert state.entities[entity_id].aspects == []
    end

    test "skill_set with positive rating sets skill, zero removes it" do
      {entity_id, create} = entity_create("Skilled")
      set_fight = skill_set(entity_id, "Fight", 4)
      set_zero = skill_set(entity_id, "Fight", 0)

      state = Replay.derive("bm-1", [create, set_fight])
      assert state.entities[entity_id].skills["Fight"] == 4

      state = Replay.derive("bm-1", [create, set_fight, set_zero])
      refute Map.has_key?(state.entities[entity_id].skills, "Fight")
    end

    test "stunt_add and stunt_remove" do
      {entity_id, create} = entity_create("Stunt User")
      {stunt_id, add} = stunt_add(entity_id, "Riposte", "+2 to Fight")

      remove =
        build_event(:stunt_remove, %{"entity_id" => entity_id, "stunt_id" => stunt_id},
          target_id: entity_id
        )

      state_with = Replay.derive("bm-1", [create, add])
      assert length(state_with.entities[entity_id].stunts) == 1
      assert hd(state_with.entities[entity_id].stunts).name == "Riposte"

      state_without = Replay.derive("bm-1", [create, add, remove])
      assert state_without.entities[entity_id].stunts == []
    end

    test "scene_start appends scene and sets gm_fate_points to PC count" do
      {_id1, pc1} = entity_create("PC One", kind: "pc")
      {_id2, pc2} = entity_create("PC Two", kind: "pc")
      {_id3, npc} = entity_create("NPC", kind: "npc")
      {scene_id, scene} = scene_start("Battle")

      state = Replay.derive("bm-1", List.flatten([pc1, pc2, npc, scene]))
      assert length(state.scene_templates) == 1
      assert hd(state.scene_templates).id == scene_id
      assert hd(state.scene_templates).name == "Battle"
      assert state.active_scene != nil
      assert state.active_scene.template_id == scene_id
      assert state.gm_fate_points == 2
    end

    test "scene_end clears stress and removes boosts" do
      {entity_id, create} =
        entity_create("Fighter",
          stress_tracks: [%{"label" => "physical", "boxes" => 2}]
        )

      {scene_id, scene} = scene_start("Fight")

      stress =
        build_event(
          :stress_apply,
          %{
            "entity_id" => entity_id,
            "track_label" => "physical",
            "box_index" => 0
          },
          target_id: entity_id
        )

      {_boost_id, boost} = aspect_create(entity_id, "Quick Boost", role: "boost")

      end_scene = build_event(:scene_end, %{"scene_id" => scene_id})

      state = Replay.derive("bm-1", List.flatten([create, scene, stress, boost, end_scene]))
      entity = state.entities[entity_id]

      assert hd(entity.stress_tracks).checked == []
      refute Enum.any?(entity.aspects, &(&1.role == :boost))
      assert state.active_scene == nil
      assert length(state.scene_templates) == 1
    end

    test "zone_create adds zone to active scene" do
      {scene_id, scene} = scene_start("Room")
      {zone_id, zone} = zone_create(scene_id, "Corner")

      state = Replay.derive("bm-1", List.flatten([scene, zone]))
      assert length(state.active_scene.zones) == 1
      assert hd(state.active_scene.zones).id == zone_id
      assert hd(state.active_scene.zones).name == "Corner"
    end

    test "entity_move sets zone_id on entity" do
      {entity_id, create} = entity_create("Mover")
      {scene_id, scene} = scene_start("Room")
      {zone_id, zone} = zone_create(scene_id, "Corner")

      move =
        build_event(
          :entity_move,
          %{
            "entity_id" => entity_id,
            "zone_id" => zone_id
          },
          actor_id: entity_id
        )

      state = Replay.derive("bm-1", List.flatten([create, scene, zone, move]))
      assert state.entities[entity_id].zone_id == zone_id
    end

    test "fate_point_spend and earn adjust entity FP" do
      {entity_id, create} = entity_create("Hero", fate_points: 3)
      spend = fate_point_spend(entity_id)
      earn = fate_point_earn(entity_id, 2)

      state = Replay.derive("bm-1", [create, spend])
      assert state.entities[entity_id].fate_points == 2

      state = Replay.derive("bm-1", [create, spend, earn])
      assert state.entities[entity_id].fate_points == 4
    end
  end

  describe "event_entity_refs/1 and event_matches_selected_entities?/2" do
    test "entity_modify refs target entity" do
      ev =
        build_event(:entity_modify, %{"entity_id" => "e1", "name" => "X"}, target_id: "e1")

      assert MapSet.equal?(Replay.event_entity_refs(ev), MapSet.new(["e1"]))
      assert Replay.event_matches_selected_entities?(ev, MapSet.new(["e1"]))
      refute Replay.event_matches_selected_entities?(ev, MapSet.new(["other"]))
    end

    test "aspect_create on entity refs that entity" do
      ev =
        build_event(:aspect_create, %{
          "target_type" => "entity",
          "target_id" => "ent-a",
          "aspect_id" => Ash.UUID.generate(),
          "description" => "Hi"
        })

      assert Replay.event_matches_selected_entities?(ev, MapSet.new(["ent-a"]))
      refute Replay.event_matches_selected_entities?(ev, MapSet.new(["ent-b"]))
    end

    test "aspect_modify with entity target refs entity" do
      ev =
        build_event(:aspect_modify, %{
          "aspect_id" => "asp",
          "hidden" => true,
          "target_type" => "entity",
          "target_id" => "e2"
        })

      assert Replay.event_matches_selected_entities?(ev, MapSet.new(["e2"]))
    end

    test "scene_start has no entity refs" do
      {_, [create_ev, start_ev]} = scene_start("X")
      assert Replay.event_entity_refs(create_ev) == MapSet.new()
      assert Replay.event_entity_refs(start_ev) == MapSet.new()
      refute Replay.event_matches_selected_entities?(create_ev, MapSet.new(["any"]))
    end

    test "note targeting entity refs that entity" do
      ev =
        build_event(:note, %{"target_type" => "entity", "target_id" => "n1", "text" => "Hi"})

      assert Replay.event_matches_selected_entities?(ev, MapSet.new(["n1"]))
    end
  end

  describe "find_aspect_container/2" do
    test "returns entity when aspect is on an entity" do
      {eid, create} = entity_create("X")
      {aid, add} = aspect_create(eid, "A", target_type: "entity")
      state = Replay.derive("bm-1", [create, add])
      assert {:ok, "entity", ^eid} = Replay.find_aspect_container(state, aid)
    end

    test "returns zone when aspect is on a zone" do
      {sid, scene} = scene_start("S")
      {zid, zone} = zone_create(sid, "Z")
      {aid, add} = aspect_create(zid, "Zasp", target_type: "zone")
      state = Replay.derive("bm-1", List.flatten([scene, zone, add]))
      assert {:ok, "zone", ^zid} = Replay.find_aspect_container(state, aid)
    end
  end

  describe "validate_chain/1" do
    test "returns empty map for valid chain" do
      {_id, create} = entity_create("Valid")
      invalids = Replay.validate_chain([create])
      assert invalids == %{}
    end

    test "marks events targeting missing entities as invalid with reason" do
      modify =
        build_event(
          :entity_modify,
          %{
            "entity_id" => "nonexistent"
          },
          target_id: "nonexistent",
          id: "bad-event"
        )

      invalids = Replay.validate_chain([modify])
      assert is_binary(invalids["bad-event"])
    end

    test "does not mark events targeting existing entities" do
      {entity_id, create} = entity_create("Real")

      modify =
        build_event(
          :entity_modify,
          %{
            "entity_id" => entity_id,
            "name" => "Updated"
          },
          target_id: entity_id,
          id: "good-event"
        )

      invalids = Replay.validate_chain([create, modify])
      refute Map.has_key?(invalids, "good-event")
    end
  end
end
