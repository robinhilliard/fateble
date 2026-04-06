defmodule Fate.EventFactory do
  @moduledoc """
  Helpers for building event maps used in replay tests.
  Events are plain maps matching the shape produced by Engine.load_event_chain/1.
  """

  def build_event(type, detail \\ %{}, opts \\ []) do
    %{
      id: opts[:id] || Ash.UUID.generate(),
      parent_id: opts[:parent_id],
      timestamp: opts[:timestamp] || DateTime.utc_now(),
      type: type,
      actor_id: opts[:actor_id],
      target_id: opts[:target_id],
      exchange_id: opts[:exchange_id],
      description: opts[:description],
      detail: detail
    }
  end

  def entity_create(name, opts \\ []) do
    entity_id = opts[:entity_id] || Ash.UUID.generate()

    detail =
      %{
        "entity_id" => entity_id,
        "name" => name,
        "kind" => opts[:kind] || "npc"
      }
      |> put_if(:fate_points, opts[:fate_points])
      |> put_if(:refresh, opts[:refresh])
      |> put_if(:mook_count, opts[:mook_count])
      |> put_if(:color, opts[:color])
      |> put_if(:controller_id, opts[:controller_id])
      |> put_if(:aspects, opts[:aspects])
      |> put_if(:skills, opts[:skills])
      |> put_if(:stunts, opts[:stunts])
      |> put_if(:stress_tracks, opts[:stress_tracks])
      |> put_if(:hidden, opts[:hidden])

    {entity_id, build_event(:entity_create, detail)}
  end

  @doc "Legacy scene_start (creates + activates in one step for backward compat tests)"
  def scene_start(name, opts \\ []) do
    scene_id = opts[:scene_id] || Ash.UUID.generate()

    detail =
      %{
        "scene_id" => scene_id,
        "name" => name,
        "description" => opts[:description],
        "gm_notes" => opts[:gm_notes]
      }
      |> put_if(:zones, opts[:zones])
      |> put_if(:aspects, opts[:aspects])

    create = build_event(:scene_start, detail)
    activate = build_event(:active_scene_start, %{"scene_id" => scene_id})
    {scene_id, [create, activate]}
  end

  def template_scene_create(name, opts \\ []) do
    scene_id = opts[:scene_id] || Ash.UUID.generate()

    detail =
      %{
        "scene_id" => scene_id,
        "name" => name,
        "description" => opts[:description],
        "gm_notes" => opts[:gm_notes]
      }
      |> put_if(:zones, opts[:zones])
      |> put_if(:aspects, opts[:aspects])

    {scene_id, build_event(:template_scene_create, detail)}
  end

  def active_scene_start(scene_id) do
    build_event(:active_scene_start, %{"scene_id" => scene_id})
  end

  def active_scene_end(scene_id) do
    build_event(:active_scene_end, %{"scene_id" => scene_id})
  end

  @doc "Legacy zone_create"
  def zone_create(scene_id, name, opts \\ []) do
    zone_id = opts[:zone_id] || Ash.UUID.generate()

    detail = %{
      "scene_id" => scene_id,
      "zone_id" => zone_id,
      "name" => name,
      "hidden" => opts[:hidden] || false
    }

    {zone_id, build_event(:zone_create, detail)}
  end

  def template_zone_create(scene_id, name, opts \\ []) do
    zone_id = opts[:zone_id] || Ash.UUID.generate()

    detail = %{
      "scene_id" => scene_id,
      "zone_id" => zone_id,
      "name" => name,
      "hidden" => opts[:hidden] || false
    }

    {zone_id, build_event(:template_zone_create, detail)}
  end

  def aspect_create(target_id, description, opts \\ []) do
    aspect_id = opts[:aspect_id] || Ash.UUID.generate()

    detail = %{
      "target_id" => target_id,
      "target_type" => opts[:target_type] || "entity",
      "aspect_id" => aspect_id,
      "description" => description,
      "role" => opts[:role] || "additional",
      "hidden" => opts[:hidden] || false,
      "free_invokes" => opts[:free_invokes] || 0
    }

    {aspect_id, build_event(:aspect_create, detail, target_id: target_id)}
  end

  def skill_set(entity_id, skill, rating) do
    build_event(
      :skill_set,
      %{
        "entity_id" => entity_id,
        "skill" => skill,
        "rating" => rating
      },
      target_id: entity_id
    )
  end

  def stunt_add(entity_id, name, effect, opts \\ []) do
    stunt_id = opts[:stunt_id] || Ash.UUID.generate()

    detail = %{
      "entity_id" => entity_id,
      "stunt_id" => stunt_id,
      "name" => name,
      "effect" => effect
    }

    {stunt_id, build_event(:stunt_add, detail, target_id: entity_id)}
  end

  def fate_point_spend(entity_id, amount \\ 1) do
    build_event(
      :fate_point_spend,
      %{
        "entity_id" => entity_id,
        "amount" => amount
      },
      target_id: entity_id
    )
  end

  def fate_point_earn(entity_id, amount \\ 1) do
    build_event(
      :fate_point_earn,
      %{
        "entity_id" => entity_id,
        "amount" => amount
      },
      target_id: entity_id
    )
  end

  defp put_if(map, _key, nil), do: map
  defp put_if(map, key, value), do: Map.put(map, to_string(key), value)
end
