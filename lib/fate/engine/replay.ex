defmodule Fate.Engine.Replay do
  @moduledoc """
  Replays an ordered list of events from root to head to produce a DerivedState.
  Each event type has a pure apply function that transforms the state.
  """

  alias Fate.Engine.State.{
    DerivedState,
    Entity,
    Aspect,
    Stunt,
    StressTrack,
    Consequence,
    PendingShifts,
    SceneState,
    ZoneState
  }

  @doc """
  Given a branch ID, head event ID, and an ordered list of events (root first),
  produces the derived game state.
  """
  def derive(branch_id, events) do
    head_event_id =
      case List.last(events) do
        nil -> nil
        event -> event.id
      end

    initial = %DerivedState{branch_id: branch_id, head_event_id: head_event_id}

    Enum.reduce(events, initial, &apply_event/2)
  end

  defp apply_event(event, state) do
    case event.type do
      :create_campaign -> apply_create_campaign(event, state)
      :set_system -> apply_set_system(event, state)
      :entity_create -> apply_entity_create(event, state)
      :entity_modify -> apply_entity_modify(event, state)
      :entity_remove -> apply_entity_remove(event, state)
      :aspect_create -> apply_aspect_create(event, state)
      :aspect_remove -> apply_aspect_remove(event, state)
      :skill_set -> apply_skill_set(event, state)
      :stunt_add -> apply_stunt_add(event, state)
      :stunt_remove -> apply_stunt_remove(event, state)
      :scene_start -> apply_scene_start(event, state)
      :scene_end -> apply_scene_end(event, state)
      :zone_create -> apply_zone_create(event, state)
      :zone_modify -> apply_zone_modify(event, state)
      :entity_enter_scene -> apply_entity_enter_scene(event, state)
      :entity_move -> apply_entity_move(event, state)
      :stress_apply -> apply_stress_apply(event, state)
      :stress_clear -> apply_stress_clear(event, state)
      :consequence_take -> apply_consequence_take(event, state)
      :consequence_recover -> apply_consequence_recover(event, state)
      :fate_point_spend -> apply_fate_point_change(event, state, :spend)
      :fate_point_earn -> apply_fate_point_change(event, state, :earn)
      :fate_point_refresh -> apply_fate_point_refresh(event, state)
      :shifts_resolved -> apply_shifts_resolved(event, state)
      :concede -> apply_concede(event, state)
      :taken_out -> apply_taken_out(event, state)
      :mook_eliminate -> apply_mook_eliminate(event, state)
      _ -> state
    end
  end

  defp apply_create_campaign(event, state) do
    name = get_in(event.detail, ["campaign_name"]) || event.description
    %{state | campaign_name: name}
  end

  defp apply_set_system(event, state) do
    detail = event.detail || %{}
    system = detail["system"] || "core"
    skill_list = detail["skill_list"] || default_skill_list(system)

    %{state | system: system, skill_list: skill_list}
  end

  defp default_skill_list("accelerated"),
    do: ~w(Careful Clever Flashy Forceful Quick Sneaky)

  defp default_skill_list(_),
    do:
      ~w(Athletics Burglary Contacts Crafts Deceive Drive Empathy Fight Investigate Lore Notice Physique Provoke Rapport Resources Shoot Stealth Will)

  defp apply_entity_create(event, state) do
    detail = event.detail || %{}

    entity = %Entity{
      id: detail["entity_id"] || deterministic_id("entity", event.id || ""),
      name: detail["name"] || "Unnamed",
      kind: parse_atom(detail["kind"], :custom),
      fate_points: detail["fate_points"],
      refresh: detail["refresh"],
      mook_count: detail["mook_count"],
      color: detail["color"] || "#6b7280",
      avatar: detail["avatar"],
      controller_id: detail["controller_id"],
      parent_id: detail["parent_entity_id"],
      table_x: detail["table_x"],
      table_y: detail["table_y"],
      aspects: build_aspects(detail["aspects"] || []),
      skills: build_skills(detail["skills"] || %{}),
      stunts: build_stunts(detail["stunts"] || []),
      stress_tracks: build_stress_tracks(detail["stress_tracks"] || []),
      consequences: build_consequences(detail["consequences"] || [])
    }

    put_in(state.entities[entity.id], entity)
  end

  defp apply_entity_modify(event, state) do
    detail = event.detail || %{}
    entity_id = event.target_id || detail["entity_id"]

    update_entity(state, entity_id, fn entity ->
      entity
      |> maybe_put(:name, detail["name"])
      |> maybe_put(:kind, parse_atom(detail["kind"], nil))
      |> maybe_put(:color, detail["color"])
      |> maybe_put(:avatar, detail["avatar"])
      |> maybe_put(:fate_points, detail["fate_points"])
      |> maybe_put(:refresh, detail["refresh"])
      |> maybe_put(:controller_id, detail["controller_id"])
      |> maybe_put(:table_x, detail["table_x"])
      |> maybe_put(:table_y, detail["table_y"])
    end)
  end

  defp apply_entity_remove(event, state) do
    entity_id = event.target_id || get_in(event.detail, ["entity_id"])
    %{state | entities: Map.delete(state.entities, entity_id)}
  end

  defp apply_aspect_create(event, state) do
    detail = event.detail || %{}
    target_id = event.target_id || detail["target_id"]
    target_type = detail["target_type"] || "entity"

    aspect = %Aspect{
      id: detail["aspect_id"] || deterministic_id("aspect", event.id || ""),
      description: detail["description"] || "",
      role: parse_atom(detail["role"], :additional),
      created_by_entity_id: event.actor_id,
      free_invokes: detail["free_invokes"] || 0,
      hidden: detail["hidden"] || false
    }

    case target_type do
      "entity" ->
        update_entity(state, target_id, fn entity ->
          %{entity | aspects: entity.aspects ++ [aspect]}
        end)

      "scene" ->
        update_scene(state, target_id, fn scene ->
          %{scene | aspects: scene.aspects ++ [aspect]}
        end)

      "zone" ->
        update_zone(state, target_id, fn zone ->
          %{zone | aspects: zone.aspects ++ [aspect]}
        end)

      _ ->
        state
    end
  end

  defp apply_aspect_remove(event, state) do
    detail = event.detail || %{}
    aspect_id = detail["aspect_id"]

    state
    |> update_all_entities(fn entity ->
      %{entity | aspects: Enum.reject(entity.aspects, &(&1.id == aspect_id))}
    end)
    |> update_all_scenes(fn scene ->
      %{scene | aspects: Enum.reject(scene.aspects, &(&1.id == aspect_id))}
    end)
  end

  defp apply_skill_set(event, state) do
    detail = event.detail || %{}
    entity_id = event.target_id || detail["entity_id"]
    skill = detail["skill"]
    rating = detail["rating"]

    update_entity(state, entity_id, fn entity ->
      %{entity | skills: Map.put(entity.skills, skill, rating)}
    end)
  end

  defp apply_stunt_add(event, state) do
    detail = event.detail || %{}
    entity_id = event.target_id || detail["entity_id"]

    stunt = %Stunt{
      id: detail["stunt_id"] || deterministic_id("stunt", event.id || ""),
      name: detail["name"],
      effect: detail["effect"]
    }

    update_entity(state, entity_id, fn entity ->
      %{entity | stunts: entity.stunts ++ [stunt]}
    end)
  end

  defp apply_stunt_remove(event, state) do
    detail = event.detail || %{}
    entity_id = event.target_id || detail["entity_id"]
    stunt_id = detail["stunt_id"]

    update_entity(state, entity_id, fn entity ->
      %{entity | stunts: Enum.reject(entity.stunts, &(&1.id == stunt_id))}
    end)
  end

  defp apply_scene_start(event, state) do
    detail = event.detail || %{}

    scene = %SceneState{
      id: detail["scene_id"] || deterministic_id("scene", event.id || ""),
      name: detail["name"] || "Untitled Scene",
      description: detail["description"],
      gm_notes: detail["gm_notes"],
      status: :active,
      zones: build_zones(detail["zones"] || []),
      aspects: build_aspects(detail["aspects"] || [])
    }

    pc_count = state.entities |> Map.values() |> Enum.count(&(&1.kind == :pc))

    %{state | scenes: state.scenes ++ [scene], gm_fate_points: pc_count}
  end

  defp apply_scene_end(event, state) do
    detail = event.detail || %{}
    scene_id = detail["scene_id"]

    scene = Enum.find(state.scenes, &(&1.id == scene_id))
    zone_ids = if scene, do: Enum.map(scene.zones, & &1.id), else: []

    state
    |> update_scene(scene_id, fn scene -> %{scene | status: :resolved} end)
    |> clear_all_stress()
    |> remove_boosts()
    |> clear_zone_ids(zone_ids)
  end

  defp clear_zone_ids(state, zone_ids) do
    update_all_entities(state, fn entity ->
      if entity.zone_id in zone_ids do
        %{entity | zone_id: nil}
      else
        entity
      end
    end)
  end

  defp apply_zone_create(event, state) do
    detail = event.detail || %{}
    scene_id = detail["scene_id"]

    zone = %ZoneState{
      id: detail["zone_id"] || deterministic_id("zone", event.id || ""),
      name: detail["name"] || "Zone",
      sort_order: detail["sort_order"] || 0,
      aspects: build_aspects(detail["aspects"] || [])
    }

    update_scene(state, scene_id, fn scene ->
      %{scene | zones: scene.zones ++ [zone]}
    end)
  end

  defp apply_zone_modify(event, state) do
    detail = event.detail || %{}
    zone_id = detail["zone_id"]

    update_zone(state, zone_id, fn zone ->
      zone
      |> maybe_put(:name, detail["name"])
      |> maybe_put(:hidden, detail["hidden"])
    end)
  end

  defp apply_entity_enter_scene(event, state) do
    detail = event.detail || %{}
    entity_id = event.actor_id || detail["entity_id"]
    zone_id = detail["zone_id"]

    update_entity(state, entity_id, fn entity ->
      %{entity | zone_id: zone_id}
    end)
  end

  defp apply_entity_move(event, state) do
    apply_entity_enter_scene(event, state)
  end

  defp apply_stress_apply(event, state) do
    detail = event.detail || %{}
    entity_id = event.target_id || detail["entity_id"]
    track_label = detail["track_label"]
    box_index = detail["box_index"]
    shifts_absorbed = detail["shifts_absorbed"] || 1

    state
    |> update_entity(entity_id, fn entity ->
      stress_tracks =
        Enum.map(entity.stress_tracks, fn track ->
          if track.label == track_label do
            %{track | checked: [box_index | track.checked] |> Enum.uniq()}
          else
            track
          end
        end)

      pending =
        case entity.pending_shifts do
          %PendingShifts{remaining_shifts: r} = ps when r > 0 ->
            new_remaining = max(0, r - shifts_absorbed)
            if new_remaining == 0, do: nil, else: %{ps | remaining_shifts: new_remaining}

          other ->
            other
        end

      %{entity | stress_tracks: stress_tracks, pending_shifts: pending}
    end)
  end

  defp apply_stress_clear(_event, state) do
    clear_all_stress(state)
  end

  defp apply_consequence_take(event, state) do
    detail = event.detail || %{}
    entity_id = event.target_id || detail["entity_id"]
    shifts_absorbed = detail["shifts_absorbed"] || severity_to_shifts(detail["severity"])

    consequence = %Consequence{
      id: detail["consequence_id"] || deterministic_id("consequence", event.id || ""),
      severity: parse_atom(detail["severity"], :mild),
      shifts: shifts_absorbed,
      aspect_text: detail["aspect_text"],
      recovering: false
    }

    update_entity(state, entity_id, fn entity ->
      pending =
        case entity.pending_shifts do
          %PendingShifts{remaining_shifts: r} = ps when r > 0 ->
            new_remaining = max(0, r - shifts_absorbed)
            if new_remaining == 0, do: nil, else: %{ps | remaining_shifts: new_remaining}

          other ->
            other
        end

      %{entity | consequences: entity.consequences ++ [consequence], pending_shifts: pending}
    end)
  end

  defp apply_consequence_recover(event, state) do
    detail = event.detail || %{}
    entity_id = event.target_id || detail["entity_id"]
    consequence_id = detail["consequence_id"]
    new_text = detail["new_aspect_text"]
    clear = detail["clear"] || false

    update_entity(state, entity_id, fn entity ->
      consequences =
        if clear do
          Enum.reject(entity.consequences, &(&1.id == consequence_id))
        else
          Enum.map(entity.consequences, fn c ->
            if c.id == consequence_id do
              %{c | recovering: true, aspect_text: new_text || c.aspect_text}
            else
              c
            end
          end)
        end

      %{entity | consequences: consequences}
    end)
  end

  defp apply_fate_point_change(event, state, direction) do
    detail = event.detail || %{}
    entity_id = event.target_id || event.actor_id || detail["entity_id"]
    amount = detail["amount"] || 1

    update_entity(state, entity_id, fn entity ->
      delta = if direction == :earn, do: amount, else: -amount
      %{entity | fate_points: (entity.fate_points || 0) + delta}
    end)
  end

  defp apply_fate_point_refresh(event, state) do
    detail = event.detail || %{}
    entity_id = event.target_id || detail["entity_id"]

    update_entity(state, entity_id, fn entity ->
      %{entity | fate_points: max(entity.fate_points || 0, entity.refresh || 0)}
    end)
  end

  defp apply_shifts_resolved(event, state) do
    detail = event.detail || %{}
    target_id = event.target_id
    shifts = detail["shifts"] || 0

    if shifts > 0 and target_id do
      update_entity(state, target_id, fn entity ->
        %{
          entity
          | pending_shifts: %PendingShifts{
              exchange_id: event.exchange_id,
              attacker_id: event.actor_id,
              total_shifts: shifts,
              remaining_shifts: shifts
            }
        }
      end)
    else
      state
    end
  end

  defp apply_concede(event, state) do
    entity_id = event.actor_id

    update_entity(state, entity_id, fn entity ->
      %{entity | pending_shifts: nil}
    end)
  end

  defp apply_taken_out(event, state) do
    entity_id = event.target_id || event.actor_id

    update_entity(state, entity_id, fn entity ->
      %{entity | pending_shifts: nil}
    end)
  end

  defp apply_mook_eliminate(event, state) do
    detail = event.detail || %{}
    entity_id = event.target_id || detail["entity_id"]
    count = detail["count"] || 1

    update_entity(state, entity_id, fn entity ->
      %{entity | mook_count: max(0, (entity.mook_count || 0) - count)}
    end)
  end

  # --- Helpers ---

  defp update_entity(state, nil, _fun), do: state

  defp update_entity(state, entity_id, fun) do
    case Map.get(state.entities, entity_id) do
      nil -> state
      entity -> %{state | entities: Map.put(state.entities, entity_id, fun.(entity))}
    end
  end

  defp update_all_entities(state, fun) do
    entities = Map.new(state.entities, fn {id, entity} -> {id, fun.(entity)} end)
    %{state | entities: entities}
  end

  defp update_scene(state, nil, _fun), do: state

  defp update_scene(state, scene_id, fun) do
    scenes =
      Enum.map(state.scenes, fn scene ->
        if scene.id == scene_id, do: fun.(scene), else: scene
      end)

    %{state | scenes: scenes}
  end

  defp update_all_scenes(state, fun) do
    %{state | scenes: Enum.map(state.scenes, fun)}
  end

  defp update_zone(state, zone_id, fun) do
    scenes =
      Enum.map(state.scenes, fn scene ->
        zones =
          Enum.map(scene.zones, fn zone ->
            if zone.id == zone_id, do: fun.(zone), else: zone
          end)

        %{scene | zones: zones}
      end)

    %{state | scenes: scenes}
  end

  defp clear_all_stress(state) do
    update_all_entities(state, fn entity ->
      tracks = Enum.map(entity.stress_tracks, fn track -> %{track | checked: []} end)
      %{entity | stress_tracks: tracks}
    end)
  end

  defp remove_boosts(state) do
    update_all_entities(state, fn entity ->
      %{entity | aspects: Enum.reject(entity.aspects, &(&1.role == :boost))}
    end)
    |> update_all_scenes(fn scene ->
      %{scene | aspects: Enum.reject(scene.aspects, &(&1.role == :boost))}
    end)
  end

  defp build_aspects(aspect_list) do
    Enum.with_index(aspect_list)
    |> Enum.map(fn {a, i} ->
      %Aspect{
        id: a["id"] || deterministic_id("aspect", a["description"] || "#{i}"),
        description: a["description"] || "",
        role: parse_atom(a["role"], :additional),
        created_by_entity_id: a["created_by_entity_id"],
        free_invokes: a["free_invokes"] || 0,
        hidden: a["hidden"] || false
      }
    end)
  end

  defp deterministic_id(namespace, content) do
    :crypto.hash(:sha256, "#{namespace}:#{content}")
    |> Base.encode16(case: :lower)
    |> String.slice(0..31)
    |> then(fn hex ->
      "#{String.slice(hex, 0..7)}-#{String.slice(hex, 8..11)}-#{String.slice(hex, 12..15)}-#{String.slice(hex, 16..19)}-#{String.slice(hex, 20..31)}"
    end)
  end

  defp build_skills(skills_map) do
    Map.new(skills_map, fn {k, v} -> {to_string(k), v} end)
  end

  defp build_stunts(stunt_list) do
    Enum.with_index(stunt_list)
    |> Enum.map(fn {s, i} ->
      %Stunt{
        id: s["id"] || deterministic_id("stunt", s["name"] || "#{i}"),
        name: s["name"],
        effect: s["effect"]
      }
    end)
  end

  defp build_stress_tracks(track_list) do
    Enum.map(track_list, fn t ->
      %StressTrack{
        label: t["label"] || "physical",
        boxes: t["boxes"] || 2,
        checked: t["checked"] || []
      }
    end)
  end

  defp build_consequences(consequence_list) do
    Enum.with_index(consequence_list)
    |> Enum.map(fn {c, i} ->
      %Consequence{
        id: c["id"] || deterministic_id("consequence", c["severity"] || "#{i}"),
        severity: parse_atom(c["severity"], :mild),
        shifts: c["shifts"] || severity_to_shifts(c["severity"]),
        aspect_text: c["aspect_text"],
        recovering: c["recovering"] || false
      }
    end)
  end

  defp build_zones(zone_list) do
    Enum.with_index(zone_list)
    |> Enum.map(fn {z, i} ->
      %ZoneState{
        id: z["id"] || deterministic_id("zone", z["name"] || "#{i}"),
        name: z["name"] || "Zone",
        sort_order: z["sort_order"] || 0,
        aspects: build_aspects(z["aspects"] || []),
        hidden: z["hidden"] || false
      }
    end)
  end

  defp maybe_put(struct, _key, nil), do: struct
  defp maybe_put(struct, key, value), do: Map.put(struct, key, value)

  defp parse_atom(nil, default), do: default
  defp parse_atom(value, _default) when is_atom(value), do: value

  defp parse_atom(value, default) when is_binary(value) do
    try do
      String.to_existing_atom(value)
    rescue
      ArgumentError -> default
    end
  end

  defp severity_to_shifts("mild"), do: 2
  defp severity_to_shifts("moderate"), do: 4
  defp severity_to_shifts("severe"), do: 6
  defp severity_to_shifts("extreme"), do: 8
  defp severity_to_shifts(_), do: 2
end
