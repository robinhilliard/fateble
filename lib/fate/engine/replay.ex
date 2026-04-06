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
    ActiveScene,
    ZoneState
  }

  @doc """
  Replays events and returns a MapSet of event IDs whose targets
  are missing from the state at the point they would be applied.
  """
  def validate_chain(events) do
    {_state, invalids} =
      Enum.reduce(events, {%DerivedState{}, %{}}, fn event, {state, invalids} ->
        invalids =
          case invalid_reason(event, state) do
            nil -> invalids
            reason -> Map.put(invalids, event.id, reason)
          end

        {apply_event(event, state), invalids}
      end)

    invalids
  end

  @entity_target_types ~w(entity_modify entity_remove skill_set stunt_add stunt_remove
    stress_apply stress_clear consequence_take consequence_recover
    fate_point_spend fate_point_earn fate_point_refresh mook_eliminate concede taken_out)a

  defp invalid_reason(%{type: type} = event, state) when type in @entity_target_types do
    entity_id = event.target_id || event.actor_id || (event.detail || %{})["entity_id"]

    if entity_id != nil and not Map.has_key?(state.entities, entity_id),
      do: "Target entity is missing at this point in the timeline"
  end

  defp invalid_reason(%{type: type} = event, state)
       when type in ~w(entity_move entity_enter_scene)a do
    entity_id = event.actor_id || (event.detail || %{})["entity_id"]

    if entity_id != nil and not Map.has_key?(state.entities, entity_id),
      do: "Target entity is missing at this point in the timeline"
  end

  defp invalid_reason(%{type: :aspect_create} = event, state) do
    detail = event.detail || %{}

    if target_missing?(
         state,
         detail["target_type"] || "entity",
         event.target_id || detail["target_id"]
       ),
       do: "Target is missing at this point in the timeline"
  end

  defp invalid_reason(%{type: :aspect_compel} = event, state) do
    if event.target_id != nil and not Map.has_key?(state.entities, event.target_id),
      do: "Target entity is missing at this point in the timeline"
  end

  defp invalid_reason(%{type: type} = event, state)
       when type in ~w(scene_end scene_modify zone_create)a do
    scene_id = (event.detail || %{})["scene_id"]

    if scene_id != nil and not Enum.any?(state.scene_templates, &(&1.id == scene_id)),
      do: "Scene template does not exist"
  end

  defp invalid_reason(%{type: :zone_modify} = event, state) do
    zone_id = (event.detail || %{})["zone_id"]

    if zone_id != nil and not zone_exists?(state, zone_id),
      do: "Zone does not exist"
  end

  defp invalid_reason(%{type: :template_scene_create}, _state), do: nil

  defp invalid_reason(%{type: type} = event, state)
       when type in ~w(template_scene_modify template_zone_create template_zone_modify template_aspect_add template_entity_place)a do
    scene_id = (event.detail || %{})["scene_id"]

    if scene_id != nil and not Enum.any?(state.scene_templates, &(&1.id == scene_id)),
      do: "Scene template does not exist"
  end

  defp invalid_reason(%{type: :active_scene_start} = event, state) do
    scene_id = (event.detail || %{})["scene_id"]

    cond do
      state.active_scene != nil ->
        "A scene is already active (#{state.active_scene.name})"

      scene_id != nil and not Enum.any?(state.scene_templates, &(&1.id == scene_id)) ->
        "Scene template does not exist"

      true ->
        nil
    end
  end

  defp invalid_reason(%{type: :active_scene_end}, state) do
    if state.active_scene == nil, do: "No scene is currently active"
  end

  defp invalid_reason(%{type: type}, state)
       when type in ~w(active_scene_update active_zone_add active_zone_modify active_aspect_add active_aspect_modify active_aspect_remove)a do
    if state.active_scene == nil, do: "No scene is currently active"
  end

  defp invalid_reason(%{type: :redirect_hit} = event, state) do
    detail = event.detail || %{}
    from_id = event.actor_id || detail["from_entity_id"]
    to_id = event.target_id || detail["to_entity_id"]

    cond do
      from_id != nil and not Map.has_key?(state.entities, from_id) ->
        "Source entity is missing at this point in the timeline"

      to_id != nil and not Map.has_key?(state.entities, to_id) ->
        "Target entity is missing at this point in the timeline"

      true ->
        nil
    end
  end

  defp invalid_reason(%{type: :shifts_resolved} = event, state) do
    if event.target_id != nil and not Map.has_key?(state.entities, event.target_id),
      do: "Target entity is missing at this point in the timeline"
  end

  defp invalid_reason(_event, _state), do: nil

  defp target_missing?(state, "entity", id),
    do: id != nil and not Map.has_key?(state.entities, id)

  defp target_missing?(state, "scene", id),
    do: id != nil and not scene_or_active_exists?(state, id)

  defp target_missing?(state, "zone", id),
    do: id != nil and not zone_exists?(state, id)

  defp target_missing?(_, _, _), do: false

  defp scene_or_active_exists?(state, scene_id) do
    Enum.any?(state.scene_templates, &(&1.id == scene_id)) or
      (state.active_scene != nil and state.active_scene.template_id == scene_id)
  end

  defp zone_exists?(state, zone_id) do
    template_has =
      Enum.any?(state.scene_templates, fn scene ->
        Enum.any?(scene.zones, &(&1.id == zone_id))
      end)

    active_has =
      state.active_scene != nil and
        Enum.any?(state.active_scene.zones, &(&1.id == zone_id))

    template_has or active_has
  end

  @doc """
  Given a branch ID, head event ID, and an ordered list of events (root first),
  produces the derived game state.
  """
  def derive(bookmark_id, events) do
    head_event_id =
      case List.last(events) do
        nil -> nil
        event -> event.id
      end

    initial = %DerivedState{bookmark_id: bookmark_id, head_event_id: head_event_id}

    Enum.reduce(events, initial, &apply_event/2)
  end

  @doc """
  Aspect id stored on or implied by an `:aspect_create` event (matches `apply_aspect_create/2`).
  """
  def aspect_id_for_create_event(%{id: id, detail: detail}) do
    d = detail || %{}
    d["aspect_id"] || deterministic_id("aspect", "#{id || ""}")
  end

  defp apply_event(event, state) do
    case event.type do
      :create_campaign -> apply_create_campaign(event, state)
      :set_system -> apply_set_system(event, state)
      :entity_create -> apply_entity_create(event, state)
      :entity_restore -> apply_entity_restore(event, state)
      :entity_modify -> apply_entity_modify(event, state)
      :entity_remove -> apply_entity_remove(event, state)
      :aspect_create -> apply_aspect_create(event, state)
      :aspect_modify -> apply_aspect_modify(event, state)
      :aspect_remove -> apply_aspect_remove(event, state)
      :skill_set -> apply_skill_set(event, state)
      :stunt_add -> apply_stunt_add(event, state)
      :stunt_remove -> apply_stunt_remove(event, state)
      # Legacy scene types (backward compat: create+activate in one step)
      :scene_start -> apply_legacy_scene_start(event, state)
      :scene_end -> apply_legacy_scene_end(event, state)
      :scene_modify -> apply_legacy_scene_modify(event, state)
      :zone_create -> apply_legacy_zone_create(event, state)
      :zone_modify -> apply_legacy_zone_modify(event, state)
      # Template scene types (prep)
      :template_scene_create -> apply_template_scene_create(event, state)
      :template_scene_modify -> apply_template_scene_modify(event, state)
      :template_zone_create -> apply_template_zone_create(event, state)
      :template_zone_modify -> apply_template_zone_modify(event, state)
      :template_aspect_add -> apply_template_aspect_add(event, state)
      :template_entity_place -> apply_template_entity_place(event, state)
      # Active scene types (play)
      :active_scene_start -> apply_active_scene_start(event, state)
      :active_scene_end -> apply_active_scene_end(event, state)
      :active_scene_update -> apply_active_scene_update(event, state)
      :active_zone_add -> apply_active_zone_add(event, state)
      :active_zone_modify -> apply_active_zone_modify(event, state)
      :active_aspect_add -> apply_active_aspect_add(event, state)
      :active_aspect_modify -> apply_active_aspect_modify(event, state)
      :active_aspect_remove -> apply_active_aspect_remove(event, state)
      # Other
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
      :redirect_hit -> apply_redirect_hit(event, state)
      :note -> state
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
      consequences: build_consequences(detail["consequences"] || []),
      hidden: detail["hidden"] || false
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
      |> maybe_put(:hidden, detail["hidden"])
    end)
  end

  defp apply_entity_restore(event, state) do
    entity_id = event.target_id || get_in(event.detail, ["entity_id"])

    case Map.pop(state.removed_entities, entity_id) do
      {nil, _} ->
        state

      {entity, remaining} ->
        %{
          state
          | entities: Map.put(state.entities, entity_id, entity),
            removed_entities: remaining
        }
    end
  end

  defp apply_entity_remove(event, state) do
    entity_id = event.target_id || get_in(event.detail, ["entity_id"])

    removed =
      case Map.get(state.entities, entity_id) do
        nil -> state.removed_entities
        entity -> Map.put(state.removed_entities, entity_id, entity)
      end

    %{state | entities: Map.delete(state.entities, entity_id), removed_entities: removed}
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

    add_fn = fn s -> %{s | aspects: s.aspects ++ [aspect]} end

    case target_type do
      "entity" ->
        update_entity(state, target_id, add_fn)

      "scene" ->
        state = update_template(state, target_id, add_fn)

        if state.active_scene && state.active_scene.template_id == target_id do
          update_active_scene(state, add_fn)
        else
          state
        end

      "zone" ->
        state =
          update_template_zone(state, target_id, fn zone ->
            %{zone | aspects: zone.aspects ++ [aspect]}
          end)

        if state.active_scene && Enum.any?(state.active_scene.zones, &(&1.id == target_id)) do
          update_active_zone(state, target_id, fn zone ->
            %{zone | aspects: zone.aspects ++ [aspect]}
          end)
        else
          state
        end

      _ ->
        state
    end
  end

  defp apply_aspect_modify(event, state) do
    detail = event.detail || %{}
    aspect_id = detail["aspect_id"]
    target_type = detail["target_type"]
    target_id = detail["target_id"]

    update_fn = aspect_modify_fn(aspect_id, detail)

    if is_binary(target_type) and is_binary(target_id) do
      map_fn = fn s -> %{s | aspects: Enum.map(s.aspects, update_fn)} end

      case target_type do
        "entity" ->
          update_entity(state, target_id, fn entity ->
            %{entity | aspects: Enum.map(entity.aspects, update_fn)}
          end)

        "scene" ->
          state = update_template(state, target_id, map_fn)

          if state.active_scene && state.active_scene.template_id == target_id do
            update_active_scene(state, map_fn)
          else
            state
          end

        "zone" ->
          zone_map_fn = fn zone -> %{zone | aspects: Enum.map(zone.aspects, update_fn)} end
          state = update_template_zone(state, target_id, zone_map_fn)

          if state.active_scene && Enum.any?(state.active_scene.zones, &(&1.id == target_id)) do
            update_active_zone(state, target_id, zone_map_fn)
          else
            state
          end

        _ ->
          apply_aspect_modify_legacy(state, aspect_id, update_fn)
      end
    else
      apply_aspect_modify_legacy(state, aspect_id, update_fn)
    end
  end

  defp aspect_modify_fn(aspect_id, detail) do
    fn aspect ->
      if aspect.id == aspect_id do
        aspect
        |> maybe_put(:hidden, detail["hidden"])
        |> maybe_put(:description, detail["description"])
        |> maybe_put(:free_invokes, detail["free_invokes"])
      else
        aspect
      end
    end
  end

  defp apply_aspect_modify_legacy(state, _aspect_id, update_fn) do
    state
    |> update_all_entities(fn entity ->
      %{entity | aspects: Enum.map(entity.aspects, update_fn)}
    end)
    |> update_all_templates(fn template ->
      zones =
        Enum.map(template.zones, fn zone ->
          %{zone | aspects: Enum.map(zone.aspects, update_fn)}
        end)

      %{template | aspects: Enum.map(template.aspects, update_fn), zones: zones}
    end)
    |> then(fn s ->
      if s.active_scene do
        update_active_scene(s, fn scene ->
          zones =
            Enum.map(scene.zones, fn zone ->
              %{zone | aspects: Enum.map(zone.aspects, update_fn)}
            end)

          %{scene | aspects: Enum.map(scene.aspects, update_fn), zones: zones}
        end)
      else
        s
      end
    end)
  end

  defp apply_aspect_remove(event, state) do
    detail = event.detail || %{}
    aspect_id = detail["aspect_id"]
    target_type = detail["target_type"]
    target_id = detail["target_id"]

    if is_binary(target_type) and is_binary(target_id) do
      reject_fn = fn s -> %{s | aspects: Enum.reject(s.aspects, &(&1.id == aspect_id))} end

      case target_type do
        "entity" ->
          update_entity(state, target_id, fn entity ->
            %{entity | aspects: Enum.reject(entity.aspects, &(&1.id == aspect_id))}
          end)

        "scene" ->
          state = update_template(state, target_id, reject_fn)

          if state.active_scene && state.active_scene.template_id == target_id do
            update_active_scene(state, reject_fn)
          else
            state
          end

        "zone" ->
          zone_reject_fn = fn zone ->
            %{zone | aspects: Enum.reject(zone.aspects, &(&1.id == aspect_id))}
          end

          state = update_template_zone(state, target_id, zone_reject_fn)

          if state.active_scene && Enum.any?(state.active_scene.zones, &(&1.id == target_id)) do
            update_active_zone(state, target_id, zone_reject_fn)
          else
            state
          end

        _ ->
          apply_aspect_remove_legacy(state, aspect_id)
      end
    else
      apply_aspect_remove_legacy(state, aspect_id)
    end
  end

  defp apply_aspect_remove_legacy(state, aspect_id) do
    state
    |> update_all_entities(fn entity ->
      %{entity | aspects: Enum.reject(entity.aspects, &(&1.id == aspect_id))}
    end)
    |> update_all_templates(fn template ->
      %{template | aspects: Enum.reject(template.aspects, &(&1.id == aspect_id))}
    end)
    |> then(fn s ->
      if s.active_scene do
        update_active_scene(s, fn scene ->
          %{scene | aspects: Enum.reject(scene.aspects, &(&1.id == aspect_id))}
        end)
      else
        s
      end
    end)
  end

  defp apply_skill_set(event, state) do
    detail = event.detail || %{}
    entity_id = event.target_id || detail["entity_id"]
    skill = detail["skill"]
    rating = detail["rating"]

    update_entity(state, entity_id, fn entity ->
      if rating == 0 do
        %{entity | skills: Map.delete(entity.skills, skill)}
      else
        %{entity | skills: Map.put(entity.skills, skill, rating)}
      end
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

  # --- Legacy scene handlers (backward compat: create+activate in one step) ---

  defp apply_legacy_scene_start(event, state) do
    detail = event.detail || %{}
    scene_id = detail["scene_id"] || deterministic_id("scene", event.id || "")

    template = %SceneState{
      id: scene_id,
      name: detail["name"] || "No Scene",
      description: detail["description"],
      gm_notes: detail["gm_notes"],
      zones: build_zones(detail["zones"] || []),
      aspects: build_aspects(detail["aspects"] || [])
    }

    %{state | scene_templates: state.scene_templates ++ [template]}
  end

  defp apply_legacy_scene_end(event, state) do
    detail = event.detail || %{}
    scene_id = detail["scene_id"]

    if state.active_scene != nil and state.active_scene.template_id == scene_id do
      deactivate_scene(state)
    else
      state
    end
  end

  defp apply_legacy_scene_modify(event, state) do
    detail = event.detail || %{}
    scene_id = detail["scene_id"]

    modify_fn = fn s ->
      s
      |> maybe_put(:name, detail["name"])
      |> maybe_put(:description, detail["description"])
      |> maybe_put(:gm_notes, detail["gm_notes"])
    end

    state = update_template(state, scene_id, modify_fn)

    if state.active_scene != nil and state.active_scene.template_id == scene_id do
      update_active_scene(state, modify_fn)
    else
      state
    end
  end

  defp apply_legacy_zone_create(event, state) do
    detail = event.detail || %{}
    scene_id = detail["scene_id"]

    zone = %ZoneState{
      id: detail["zone_id"] || deterministic_id("zone", event.id || ""),
      name: detail["name"] || "Zone",
      sort_order: detail["sort_order"] || 0,
      aspects: build_aspects(detail["aspects"] || []),
      hidden: detail["hidden"] || false
    }

    state =
      update_template(state, scene_id, fn template ->
        %{template | zones: template.zones ++ [zone]}
      end)

    if state.active_scene != nil and state.active_scene.template_id == scene_id do
      update_active_scene(state, fn scene ->
        %{scene | zones: scene.zones ++ [zone]}
      end)
    else
      state
    end
  end

  defp apply_legacy_zone_modify(event, state) do
    detail = event.detail || %{}
    zone_id = detail["zone_id"]

    modify_fn = fn zone ->
      zone
      |> maybe_put(:name, detail["name"])
      |> maybe_put(:hidden, detail["hidden"])
    end

    state = update_template_zone(state, zone_id, modify_fn)

    if state.active_scene != nil and
         Enum.any?(state.active_scene.zones, &(&1.id == zone_id)) do
      update_active_zone(state, zone_id, modify_fn)
    else
      state
    end
  end

  # --- Template scene handlers (prep) ---

  defp apply_template_scene_create(event, state) do
    detail = event.detail || %{}

    template = %SceneState{
      id: detail["scene_id"] || deterministic_id("scene", event.id || ""),
      name: detail["name"] || "Untitled Scene",
      description: detail["description"],
      gm_notes: detail["gm_notes"],
      zones: build_zones(detail["zones"] || []),
      aspects: build_aspects(detail["aspects"] || [])
    }

    %{state | scene_templates: state.scene_templates ++ [template]}
  end

  defp apply_template_scene_modify(event, state) do
    detail = event.detail || %{}
    scene_id = detail["scene_id"]

    update_template(state, scene_id, fn template ->
      template
      |> maybe_put(:name, detail["name"])
      |> maybe_put(:description, detail["description"])
      |> maybe_put(:gm_notes, detail["gm_notes"])
    end)
  end

  defp apply_template_zone_create(event, state) do
    detail = event.detail || %{}
    scene_id = detail["scene_id"]

    zone = %ZoneState{
      id: detail["zone_id"] || deterministic_id("zone", event.id || ""),
      name: detail["name"] || "Zone",
      sort_order: detail["sort_order"] || 0,
      aspects: build_aspects(detail["aspects"] || []),
      hidden: detail["hidden"] || false
    }

    update_template(state, scene_id, fn template ->
      %{template | zones: template.zones ++ [zone]}
    end)
  end

  defp apply_template_zone_modify(event, state) do
    detail = event.detail || %{}
    zone_id = detail["zone_id"]

    update_template_zone(state, zone_id, fn zone ->
      zone
      |> maybe_put(:name, detail["name"])
      |> maybe_put(:hidden, detail["hidden"])
    end)
  end

  defp apply_template_aspect_add(event, state) do
    detail = event.detail || %{}
    target_type = detail["target_type"] || "scene"
    target_id = detail["target_id"]

    aspect = %Aspect{
      id: detail["aspect_id"] || deterministic_id("aspect", event.id || ""),
      description: detail["description"] || "",
      role: parse_atom(detail["role"], :situation),
      created_by_entity_id: event.actor_id,
      free_invokes: detail["free_invokes"] || 0,
      hidden: detail["hidden"] || false
    }

    case target_type do
      "scene" ->
        update_template(state, target_id, fn template ->
          %{template | aspects: template.aspects ++ [aspect]}
        end)

      "zone" ->
        update_template_zone(state, target_id, fn zone ->
          %{zone | aspects: zone.aspects ++ [aspect]}
        end)

      _ ->
        state
    end
  end

  defp apply_template_entity_place(event, state) do
    detail = event.detail || %{}
    scene_id = detail["scene_id"]
    entity_id = detail["entity_id"]
    zone_id = detail["zone_id"]

    update_template(state, scene_id, fn template ->
      placements =
        if zone_id do
          Map.put(template.entity_placements, entity_id, zone_id)
        else
          Map.delete(template.entity_placements, entity_id)
        end

      %{template | entity_placements: placements}
    end)
  end

  # --- Active scene handlers (play) ---

  defp apply_active_scene_start(event, state) do
    detail = event.detail || %{}
    scene_id = detail["scene_id"]

    case Enum.find(state.scene_templates, &(&1.id == scene_id)) do
      nil ->
        template = %SceneState{
          id: scene_id || deterministic_id("scene", event.id || ""),
          name: detail["name"] || "Untitled Scene",
          description: detail["description"],
          gm_notes: detail["gm_notes"]
        }

        state = %{state | scene_templates: state.scene_templates ++ [template]}
        activate_template(state, template)

      template ->
        activate_template(state, template)
    end
  end

  defp apply_active_scene_end(_event, state) do
    if state.active_scene != nil do
      deactivate_scene(state)
    else
      state
    end
  end

  defp apply_active_scene_update(event, state) do
    detail = event.detail || %{}

    update_active_scene(state, fn scene ->
      scene
      |> maybe_put(:name, detail["name"])
      |> maybe_put(:description, detail["description"])
      |> maybe_put(:gm_notes, detail["gm_notes"])
    end)
  end

  defp apply_active_zone_add(event, state) do
    detail = event.detail || %{}

    zone = %ZoneState{
      id: detail["zone_id"] || deterministic_id("zone", event.id || ""),
      name: detail["name"] || "Zone",
      sort_order: detail["sort_order"] || 0,
      aspects: build_aspects(detail["aspects"] || []),
      hidden: detail["hidden"] || false
    }

    update_active_scene(state, fn scene ->
      %{scene | zones: scene.zones ++ [zone]}
    end)
  end

  defp apply_active_zone_modify(event, state) do
    detail = event.detail || %{}
    zone_id = detail["zone_id"]

    update_active_zone(state, zone_id, fn zone ->
      zone
      |> maybe_put(:name, detail["name"])
      |> maybe_put(:hidden, detail["hidden"])
    end)
  end

  defp apply_active_aspect_add(event, state) do
    detail = event.detail || %{}
    target_type = detail["target_type"] || "scene"
    target_id = detail["target_id"]

    aspect = %Aspect{
      id: detail["aspect_id"] || deterministic_id("aspect", event.id || ""),
      description: detail["description"] || "",
      role: parse_atom(detail["role"], :situation),
      created_by_entity_id: event.actor_id,
      free_invokes: detail["free_invokes"] || 0,
      hidden: detail["hidden"] || false
    }

    case target_type do
      "scene" ->
        update_active_scene(state, fn scene ->
          %{scene | aspects: scene.aspects ++ [aspect]}
        end)

      "zone" ->
        update_active_zone(state, target_id, fn zone ->
          %{zone | aspects: zone.aspects ++ [aspect]}
        end)

      _ ->
        state
    end
  end

  defp apply_active_aspect_modify(event, state) do
    detail = event.detail || %{}
    aspect_id = detail["aspect_id"]
    update_fn = aspect_modify_fn(aspect_id, detail)

    case detail["target_type"] do
      "zone" ->
        zone_id = detail["target_id"]

        update_active_zone(state, zone_id, fn zone ->
          %{zone | aspects: Enum.map(zone.aspects, update_fn)}
        end)

      _ ->
        update_active_scene(state, fn scene ->
          %{scene | aspects: Enum.map(scene.aspects, update_fn)}
        end)
    end
  end

  defp apply_active_aspect_remove(event, state) do
    detail = event.detail || %{}
    aspect_id = detail["aspect_id"]

    case detail["target_type"] do
      "zone" ->
        zone_id = detail["target_id"]

        update_active_zone(state, zone_id, fn zone ->
          %{zone | aspects: Enum.reject(zone.aspects, &(&1.id == aspect_id))}
        end)

      _ ->
        update_active_scene(state, fn scene ->
          %{scene | aspects: Enum.reject(scene.aspects, &(&1.id == aspect_id))}
        end)
    end
  end

  # --- Scene activation/deactivation helpers ---

  defp activate_template(state, template) do
    active = %ActiveScene{
      id: Ash.UUID.generate(),
      template_id: template.id,
      name: template.name,
      description: template.description,
      gm_notes: template.gm_notes,
      zones: Enum.map(template.zones, fn z -> %{z | hidden: true} end),
      aspects: Enum.map(template.aspects, fn a -> %{a | hidden: true} end),
      entity_placements: template.entity_placements
    }

    pc_count = state.entities |> Map.values() |> Enum.count(&(&1.kind == :pc))

    state =
      Enum.reduce(template.entity_placements, state, fn {entity_id, zone_id}, acc ->
        update_entity(acc, entity_id, fn entity ->
          %{entity | zone_id: zone_id, hidden: true}
        end)
      end)

    %{state | active_scene: active, gm_fate_points: pc_count}
  end

  defp deactivate_scene(state) do
    zone_ids = Enum.map(state.active_scene.zones, & &1.id)

    state
    |> clear_all_stress()
    |> remove_boosts()
    |> clear_zone_ids(zone_ids)
    |> Map.put(:active_scene, nil)
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

      %{
        entity
        | stress_tracks: stress_tracks,
          pending_shifts: absorb_shifts(entity.pending_shifts, shifts_absorbed)
      }
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
      %{
        entity
        | consequences: entity.consequences ++ [consequence],
          pending_shifts: absorb_shifts(entity.pending_shifts, shifts_absorbed)
      }
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

  defp apply_redirect_hit(event, state) do
    detail = event.detail || %{}
    from_id = event.actor_id || detail["from_entity_id"]
    to_id = event.target_id || detail["to_entity_id"]

    case Map.get(state.entities, from_id) do
      %{pending_shifts: %PendingShifts{} = shifts} ->
        state
        |> update_entity(from_id, fn entity -> %{entity | pending_shifts: nil} end)
        |> update_entity(to_id, fn entity -> %{entity | pending_shifts: shifts} end)

      _ ->
        state
    end
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

  defp update_template(state, nil, _fun), do: state

  defp update_template(state, scene_id, fun) do
    templates =
      Enum.map(state.scene_templates, fn template ->
        if template.id == scene_id, do: fun.(template), else: template
      end)

    %{state | scene_templates: templates}
  end

  defp update_all_templates(state, fun) do
    %{state | scene_templates: Enum.map(state.scene_templates, fun)}
  end

  defp update_active_scene(state, fun) do
    if state.active_scene do
      %{state | active_scene: fun.(state.active_scene)}
    else
      state
    end
  end

  defp update_template_zone(state, zone_id, fun) do
    templates =
      Enum.map(state.scene_templates, fn template ->
        zones =
          Enum.map(template.zones, fn zone ->
            if zone.id == zone_id, do: fun.(zone), else: zone
          end)

        %{template | zones: zones}
      end)

    %{state | scene_templates: templates}
  end

  defp update_active_zone(state, zone_id, fun) do
    update_active_scene(state, fn scene ->
      zones =
        Enum.map(scene.zones, fn zone ->
          if zone.id == zone_id, do: fun.(zone), else: zone
        end)

      %{scene | zones: zones}
    end)
  end

  defp clear_all_stress(state) do
    update_all_entities(state, fn entity ->
      tracks = Enum.map(entity.stress_tracks, fn track -> %{track | checked: []} end)
      %{entity | stress_tracks: tracks}
    end)
  end

  defp remove_boosts(state) do
    state =
      update_all_entities(state, fn entity ->
        %{entity | aspects: Enum.reject(entity.aspects, &(&1.role == :boost))}
      end)

    if state.active_scene do
      update_active_scene(state, fn scene ->
        %{scene | aspects: Enum.reject(scene.aspects, &(&1.role == :boost))}
      end)
    else
      state
    end
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

  defp absorb_shifts(%PendingShifts{remaining_shifts: r} = ps, absorbed) when r > 0 do
    new_remaining = max(0, r - absorbed)
    if new_remaining == 0, do: nil, else: %{ps | remaining_shifts: new_remaining}
  end

  defp absorb_shifts(other, _absorbed), do: other

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

  @doc """
  Finds which container holds an aspect. Returns `{:ok, target_type, target_id}` or `:error`.
  """
  def find_aspect_container(%DerivedState{} = state, aspect_id) when is_binary(aspect_id) do
    entity_hit =
      Enum.find_value(state.entities, fn {eid, entity} ->
        if Enum.any?(entity.aspects, &(&1.id == aspect_id)), do: {:ok, "entity", eid}
      end)

    if entity_hit do
      entity_hit
    else
      active_hit =
        if state.active_scene do
          find_aspect_in_scene(state.active_scene, aspect_id)
        end

      active_hit ||
        Enum.find_value(state.scene_templates, fn template ->
          find_aspect_in_scene(template, aspect_id)
        end) || :error
    end
  end

  def find_aspect_container(_, _), do: :error

  defp find_aspect_in_scene(scene, aspect_id) do
    cond do
      Enum.any?(scene.aspects, &(&1.id == aspect_id)) ->
        {:ok, "scene", Map.get(scene, :template_id, scene.id)}

      true ->
        Enum.find_value(scene.zones, fn zone ->
          if Enum.any?(zone.aspects, &(&1.id == aspect_id)), do: {:ok, "zone", zone.id}
        end)
    end
  end

  @doc """
  Entity ids (strings) referenced by an event, for filtering the event log by selected table entities.
  """
  def event_entity_refs(%{type: type} = event) do
    detail = event.detail || %{}
    aid = event.actor_id
    tid = event.target_id

    case type do
      t when t in [:entity_create, :entity_restore] ->
        MapSet.new() |> ref_put(detail["entity_id"])

      :aspect_create ->
        s = MapSet.new()

        if (detail["target_type"] || "entity") == "entity" do
          ref_put(s, detail["target_id"] || tid)
        else
          s
        end

      :aspect_modify ->
        s = MapSet.new() |> ref_put(tid)
        if detail["target_type"] == "entity", do: ref_put(s, detail["target_id"]), else: s

      :aspect_remove ->
        s = MapSet.new() |> ref_put(tid)
        if detail["target_type"] == "entity", do: ref_put(s, detail["target_id"]), else: s

      :note ->
        s = MapSet.new()
        if detail["target_type"] == "entity", do: ref_put(s, detail["target_id"]), else: s

      :redirect_hit ->
        MapSet.new()
        |> ref_put(aid || detail["from_entity_id"])
        |> ref_put(tid || detail["to_entity_id"])

      t
      when t in ~w(entity_modify entity_remove skill_set stunt_add stunt_remove stress_apply stress_clear consequence_take consequence_recover fate_point_spend fate_point_earn fate_point_refresh mook_eliminate)a ->
        MapSet.new() |> ref_put(tid || aid || detail["entity_id"])

      :entity_move ->
        MapSet.new() |> ref_put(aid || detail["entity_id"])

      :entity_enter_scene ->
        MapSet.new() |> ref_put(detail["entity_id"] || aid)

      :concede ->
        MapSet.new() |> ref_put(aid)

      :taken_out ->
        MapSet.new() |> ref_put(tid || aid)

      t when t in ~w(roll_attack roll_defend roll_overcome roll_create_advantage)a ->
        MapSet.new()
        |> ref_put(aid || detail["entity_id"])
        |> ref_put(tid)

      :invoke ->
        MapSet.new() |> ref_put(aid)

      :shifts_resolved ->
        MapSet.new() |> ref_put(tid)

      :aspect_compel ->
        MapSet.new()
        |> ref_put(tid)
        |> ref_put(aid)
        |> ref_put(detail["target_id"])

      _ ->
        MapSet.new()
    end
  end

  def event_matches_selected_entities?(event, %MapSet{} = selected_ids, entity_names \\ %{}) do
    not MapSet.disjoint?(event_entity_refs(event), selected_ids) ||
      event_text_mentions_selected?(event, selected_ids, entity_names)
  end

  defp event_text_mentions_selected?(_event, _selected_ids, names) when map_size(names) == 0,
    do: false

  defp event_text_mentions_selected?(event, selected_ids, entity_names) do
    detail = event.detail || %{}
    text = (event.description || "") <> " " <> (detail["text"] || "")
    downcased = String.downcase(text)

    Enum.any?(selected_ids, fn id ->
      case Map.get(entity_names, id) do
        nil ->
          false

        name ->
          pattern = "@" <> Regex.escape(name)
          Regex.match?(Regex.compile!("#{pattern}(?![a-zA-Z0-9])"), downcased)
      end
    end)
  end

  @doc """
  Returns a MapSet of event IDs that fall within any active scene
  (between :active_scene_start and :active_scene_end), regardless of template.
  The start and end events themselves are included.
  """
  def events_in_any_active_scene(events) when is_list(events) do
    {result, _} =
      Enum.reduce(events, {MapSet.new(), false}, fn event, {acc, in_scene} ->
        cond do
          event.type == :active_scene_start ->
            {MapSet.put(acc, event.id), true}

          event.type == :active_scene_end and in_scene ->
            {MapSet.put(acc, event.id), false}

          in_scene ->
            {MapSet.put(acc, event.id), in_scene}

          true ->
            {acc, false}
        end
      end)

    result
  end

  @doc """
  Returns a MapSet of event IDs that occurred during active scenes
  based on the given template IDs (including the start/end events themselves).
  """
  def events_during_scenes(events, %MapSet{} = template_ids) when is_list(events) do
    if MapSet.size(template_ids) == 0 do
      MapSet.new()
    else
      {result, _} =
        Enum.reduce(events, {MapSet.new(), nil}, fn event, {acc, active_template} ->
          cond do
            event.type == :active_scene_start ->
              scene_id = get_in(event.detail || %{}, ["scene_id"])

              if MapSet.member?(template_ids, scene_id) do
                {MapSet.put(acc, event.id), scene_id}
              else
                {acc, nil}
              end

            event.type == :active_scene_end && active_template != nil ->
              {MapSet.put(acc, event.id), nil}

            active_template != nil ->
              {MapSet.put(acc, event.id), active_template}

            true ->
              {acc, active_template}
          end
        end)

      result
    end
  end

  defp ref_put(set, val) do
    if is_binary(val) and val != "", do: MapSet.put(set, val), else: set
  end
end
