defmodule Fate.Engine.MentionCatalog do
  @moduledoc """
  Builds @ / # type-ahead data by folding the bookmark event chain (including stowed entities
  and ended scenes).
  """

  alias Fate.Game.EntityKindTags
  alias Fate.Text.CompactTag

  @type entity_row :: %{String.t() => String.t()}
  @type t :: %{
          entities: [entity_row()],
          hashtags: [String.t()]
        }

  @doc """
  Pure reducer over events in chronological order (oldest first).
  """
  @spec build([map()]) :: t()
  def build(events) when is_list(events) do
    acc = %{
      entities: %{},
      scenes: %{},
      literal_tags: MapSet.new()
    }

    events = drop_before_bookmark(events)
    acc = Enum.reduce(events, acc, &reduce_event/2)

    %{entities: ent_map, scenes: sc_map, literal_tags: literals} = acc

    entity_rows =
      ent_map
      |> Map.values()
      |> Enum.sort_by(&String.downcase(&1["name"] || ""))

    scene_compact_tags =
      sc_map
      |> Map.values()
      |> Enum.map(& &1["compact_tag"])
      |> Enum.reject(&(&1 in [nil, ""]))
      |> Enum.uniq()

    kinds = ent_map |> Map.values() |> Enum.map(& &1["kind"]) |> Enum.uniq()

    implicit =
      kinds
      |> EntityKindTags.implicit_suffixes_for_kinds()
      |> Enum.map(& &1)

    hashtags =
      literals
      |> MapSet.union(MapSet.new(scene_compact_tags))
      |> MapSet.union(MapSet.new(implicit))
      |> Enum.sort()

    %{entities: entity_rows, hashtags: hashtags}
  end

  defp drop_before_bookmark(events) do
    bookmark_indices =
      events
      |> Enum.with_index()
      |> Enum.filter(fn {ev, _} -> ev.type == :bookmark_create end)
      |> Enum.map(fn {_, idx} -> idx end)

    case bookmark_indices do
      [_, second | _] -> Enum.drop(events, second + 1)
      [first] -> Enum.drop(events, first + 1)
      [] -> events
    end
  end

  defp reduce_event(%{type: type} = ev, acc) when type in [:entity_create, :entity_restore] do
    detail = ev.detail || %{}
    id = detail["entity_id"] || ev.target_id
    if id in [nil, ""], do: acc, else: put_entity(acc, id, detail)
  end

  defp reduce_event(%{type: :entity_modify} = ev, acc) do
    detail = ev.detail || %{}
    id = ev.target_id || detail["entity_id"]
    if id in [nil, ""], do: acc, else: put_entity(acc, id, detail)
  end

  defp reduce_event(%{type: :entity_remove}, acc) do
    # Keep entity in catalog for type-ahead (stowed).
    acc
  end

  defp reduce_event(%{type: type} = ev, acc)
       when type in [:scene_start, :template_scene_create, :active_scene_start] do
    detail = ev.detail || %{}
    id = detail["scene_id"]
    if id in [nil, ""], do: acc, else: put_scene_start(acc, id, detail)
  end

  defp reduce_event(%{type: type} = ev, acc)
       when type in [:scene_modify, :template_scene_modify, :active_scene_update] do
    detail = ev.detail || %{}
    id = detail["scene_id"]
    if id in [nil, ""], do: acc, else: put_scene_modify(acc, id, detail)
  end

  defp reduce_event(%{type: type} = ev, acc)
       when type in [:scene_end, :active_scene_end] do
    detail = ev.detail || %{}
    id = detail["scene_id"]
    if id in [nil, ""], do: acc, else: mark_scene_ended(acc, id)
  end

  defp reduce_event(%{type: :note} = ev, acc) do
    detail = ev.detail || %{}
    text = detail["text"] || ev.description || ""
    acc |> extract_hashtags(text)
  end

  defp reduce_event(_ev, acc), do: acc

  defp put_entity(acc, id, detail) do
    existing = Map.get(acc.entities, id, %{})

    name =
      if is_binary(detail["name"]) and detail["name"] != "" do
        detail["name"]
      else
        existing["name"] || "Unnamed"
      end

    kind_str =
      if is_binary(detail["kind"]) and detail["kind"] != "" do
        detail["kind"]
      else
        existing["kind"] || "custom"
      end

    row = %{
      "id" => id,
      "name" => name,
      "kind" => kind_str,
      "compact_tag" => CompactTag.from_title(name)
    }

    %{acc | entities: Map.put(acc.entities, id, row)}
  end

  defp put_scene_start(acc, id, detail) do
    name = detail["name"] || "Scene"
    desc = detail["description"]
    notes = detail["gm_notes"]

    scene = %{
      "id" => id,
      "name" => name,
      "compact_tag" => CompactTag.from_title(name),
      "description" => desc,
      "gm_notes" => notes,
      "ended" => false
    }

    acc
    |> put_in([:scenes, id], scene)
    |> extract_hashtags("#{desc || ""} #{notes || ""}")
  end

  defp put_scene_modify(acc, id, detail) do
    prev = Map.get(acc.scenes, id, %{})

    name =
      if is_binary(detail["name"]) and detail["name"] != "",
        do: detail["name"],
        else: prev["name"] || "Scene"

    desc =
      if Map.has_key?(detail, "description"),
        do: detail["description"],
        else: prev["description"]

    notes =
      if Map.has_key?(detail, "gm_notes"),
        do: detail["gm_notes"],
        else: prev["gm_notes"]

    scene = %{
      "id" => id,
      "name" => name,
      "compact_tag" => CompactTag.from_title(name),
      "description" => desc,
      "gm_notes" => notes,
      "ended" => prev["ended"] || false
    }

    acc
    |> put_in([:scenes, id], scene)
    |> extract_hashtags("#{desc || ""} #{notes || ""}")
  end

  defp mark_scene_ended(acc, id) do
    if Map.has_key?(acc.scenes, id) do
      put_in(acc, [:scenes, id, "ended"], true)
    else
      acc
    end
  end

  defp extract_hashtags(acc, text) when is_binary(text) do
    tags =
      ~r/#([a-zA-Z][a-zA-Z0-9_]*)/u
      |> Regex.scan(text)
      |> Enum.map(fn [_, t] -> String.downcase(t) end)

    %{acc | literal_tags: Enum.reduce(tags, acc.literal_tags, &MapSet.put(&2, &1))}
  end

  defp extract_hashtags(acc, _), do: acc
end
