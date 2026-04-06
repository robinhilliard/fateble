defmodule Fate.Engine.Search do
  @moduledoc """
  In-memory search over DerivedState for entities and scenes.
  Supports plain text, @mention, and #hashtag query modes.
  """

  alias Fate.Engine.State.{DerivedState, Entity, SceneState, ActiveScene}
  alias Fate.Text.CompactTag
  alias Fate.Game.EntityKindTags

  @type result :: %{
          type: :entity | :scene,
          id: String.t(),
          name: String.t(),
          status: :on_table | :removed | :template | :active,
          kind: atom() | nil,
          data: Entity.t() | SceneState.t() | ActiveScene.t()
        }

  @doc """
  Searches entities and scenes in `state` matching `query`.

  Query modes:
  - `@term` — match entity/scene names
  - `#term` — match kind tags, compact tags, and hashtags in text fields
  - plain text — match anywhere across all searchable text
  """
  @spec search(DerivedState.t(), String.t()) :: [result()]
  def search(%DerivedState{} = state, query) when is_binary(query) do
    query = String.trim(query)
    if String.length(query) < 2, do: [], else: do_search(state, query)
  end

  def search(_, _), do: []

  defp do_search(state, "@" <> term) do
    term = String.downcase(term)

    search_entities_by(state, &name_matches?(&1, term)) ++
      search_scenes_by(state, &name_matches?(&1, term))
  end

  defp do_search(state, "#" <> term) do
    term = String.downcase(term)

    search_entities_by(state, &hashtag_matches?(&1, term)) ++
      search_scenes_by(state, &scene_hashtag_matches?(&1, term))
  end

  defp do_search(state, query) do
    term = String.downcase(query)

    search_entities_by(state, &entity_text_matches?(&1, term)) ++
      search_scenes_by(state, &scene_text_matches?(&1, term))
  end

  defp search_entities_by(state, matcher) do
    on_table =
      state.entities
      |> Map.values()
      |> Enum.filter(matcher)
      |> Enum.map(&entity_result(&1, :on_table))

    removed =
      state.removed_entities
      |> Map.values()
      |> Enum.filter(matcher)
      |> Enum.map(&entity_result(&1, :removed))

    Enum.sort_by(on_table ++ removed, &String.downcase(&1.name))
  end

  defp search_scenes_by(state, matcher) do
    templates =
      state.scene_templates
      |> Enum.filter(matcher)
      |> Enum.map(&scene_result(&1, :template))

    active =
      case state.active_scene do
        nil -> []
        scene -> if matcher.(scene), do: [scene_result(scene, :active)], else: []
      end

    Enum.sort_by(templates ++ active, &String.downcase(&1.name))
  end

  defp entity_result(%Entity{} = e, status) do
    %{type: :entity, id: e.id, name: e.name || "Unnamed", status: status, kind: e.kind, data: e}
  end

  defp scene_result(scene, status) do
    %{
      type: :scene,
      id: scene.id,
      name: scene.name || "Scene",
      status: status,
      kind: nil,
      data: scene
    }
  end

  # --- Name matching ---

  defp name_matches?(%{name: name}, term) when is_binary(name) do
    String.contains?(String.downcase(name), term)
  end

  defp name_matches?(_, _), do: false

  # --- Hashtag matching for entities ---

  defp hashtag_matches?(%Entity{} = e, term) do
    compact = CompactTag.from_title(e.name || "")
    kind_tag = EntityKindTags.hashtag_suffix(e.kind)

    String.starts_with?(compact, term) ||
      (kind_tag != nil && String.starts_with?(kind_tag, term)) ||
      text_contains_hashtag?(entity_searchable_text(e), term)
  end

  defp hashtag_matches?(_, _), do: false

  # --- Hashtag matching for scenes ---

  defp scene_hashtag_matches?(scene, term) do
    compact = CompactTag.from_title(scene.name || "")

    String.starts_with?(compact, term) ||
      text_contains_hashtag?(scene_searchable_text(scene), term)
  end

  defp text_contains_hashtag?(text, term) do
    case Regex.scan(~r/#([a-zA-Z][a-zA-Z0-9_]*)/u, text) do
      [] ->
        false

      matches ->
        Enum.any?(matches, fn [_, tag] -> String.starts_with?(String.downcase(tag), term) end)
    end
  end

  # --- Full text matching ---

  defp entity_text_matches?(%Entity{} = e, term) do
    String.contains?(String.downcase(entity_searchable_text(e)), term)
  end

  defp entity_text_matches?(_, _), do: false

  defp scene_text_matches?(scene, term) do
    String.contains?(String.downcase(scene_searchable_text(scene)), term)
  end

  defp entity_searchable_text(%Entity{} = e) do
    parts = [
      e.name || "",
      to_string(e.kind),
      Enum.map_join(e.aspects, " ", & &1.description),
      Enum.map_join(Map.keys(e.skills), " ", & &1),
      Enum.map_join(e.stunts, " ", &"#{&1.name} #{&1.effect}"),
      Enum.map_join(e.consequences, " ", &(&1.aspect_text || ""))
    ]

    Enum.join(parts, " ")
  end

  defp scene_searchable_text(scene) do
    zones_text =
      (Map.get(scene, :zones) || [])
      |> Enum.map_join(" ", fn z ->
        zone_aspects = Enum.map_join(z.aspects, " ", & &1.description)
        "#{z.name} #{zone_aspects}"
      end)

    aspects_text = Enum.map_join(scene.aspects, " ", & &1.description)

    Enum.join(
      [
        scene.name || "",
        scene.description || "",
        Map.get(scene, :gm_notes) || "",
        zones_text,
        aspects_text
      ],
      " "
    )
  end

  # --- Ownership tree ---

  @doc """
  Returns all entity IDs in the ownership tree containing `entity_id`.
  Walks up to the root via `parent_id`, then collects all descendants.
  Searches both active and removed entities.
  """
  @spec ownership_tree(DerivedState.t(), String.t()) :: [String.t()]
  def ownership_tree(%DerivedState{} = state, entity_id) when is_binary(entity_id) do
    all = Map.merge(state.entities, state.removed_entities)
    root_id = find_root(all, entity_id)
    collect_descendants(all, root_id)
  end

  defp find_root(all, id) do
    case Map.get(all, id) do
      %{parent_id: parent_id} when is_binary(parent_id) and parent_id != "" ->
        if Map.has_key?(all, parent_id), do: find_root(all, parent_id), else: id

      _ ->
        id
    end
  end

  defp collect_descendants(all, root_id) do
    children =
      all
      |> Enum.filter(fn {_id, e} -> e.parent_id == root_id end)
      |> Enum.flat_map(fn {id, _e} -> collect_descendants(all, id) end)

    [root_id | children]
  end

  # --- Restore detail ---
end
