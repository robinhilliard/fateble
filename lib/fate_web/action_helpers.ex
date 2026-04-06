defmodule FateWeb.ActionHelpers do
  @moduledoc """
  Shared helpers for event editing, form data construction, and event persistence.

  Shared helpers for event editing, form data construction, and event persistence,
  used by PlayerPanelLive and any LiveView that hosts the event log.
  """

  alias Fate.Engine
  alias Fate.Engine.Replay

  @entity_modify_form_keys MapSet.new(~w(name kind controller_id fate_points refresh))

  def bookmark_boundary_index(events) do
    events
    |> Enum.with_index()
    |> Enum.reduce(-1, fn {event, index}, acc ->
      if event.type == :bookmark_create, do: index, else: acc
    end)
  end

  def put_non_empty(map, _key, nil), do: map
  def put_non_empty(map, _key, ""), do: map
  def put_non_empty(map, key, val), do: Map.put(map, key, val)

  def maybe_put_int(map, _key, nil), do: map
  def maybe_put_int(map, _key, ""), do: map
  def maybe_put_int(map, key, val), do: Map.put(map, key, parse_int(val))

  def parse_int(nil), do: nil
  def parse_int(""), do: nil
  def parse_int(v) when is_integer(v), do: v

  def parse_int(v) when is_binary(v) do
    case Integer.parse(v) do
      {n, _} -> n
      :error -> nil
    end
  end

  @doc """
  Builds the `aspects` list for `entity_create` from the create-entity form:
  optional High Concept and Trouble, then one aspect per non-empty line in
  `additional_aspects` (optional `role|text`, otherwise `additional`).
  """
  def entity_create_aspects_from_form_params(params) when is_map(params) do
    p = entity_create_normalize_form_params(params)
    hc = String.trim(p["high_concept"] || "")
    tr = String.trim(p["trouble"] || "")

    additional =
      (p["additional_aspects"] || "")
      |> String.split("\n", trim: true)
      |> Enum.map(&parse_entity_create_aspect_line/1)

    []
    |> then(fn acc ->
      if hc != "", do: acc ++ [%{"role" => "high_concept", "description" => hc}], else: acc
    end)
    |> then(fn acc ->
      if tr != "", do: acc ++ [%{"role" => "trouble", "description" => tr}], else: acc
    end)
    |> Kernel.++(additional)
  end

  defp entity_create_normalize_form_params(params) do
    has_new? =
      Map.has_key?(params, "high_concept") || Map.has_key?(params, "trouble") ||
        Map.has_key?(params, "additional_aspects")

    if has_new? do
      params
    else
      %{
        "high_concept" => "",
        "trouble" => "",
        "additional_aspects" => params["aspects"] || ""
      }
    end
  end

  defp parse_entity_create_aspect_line(line) do
    case String.split(line, "|", parts: 2) do
      [role, desc] ->
        %{"role" => String.trim(role), "description" => String.trim(desc)}

      [desc] ->
        %{"role" => "additional", "description" => String.trim(desc)}
    end
  end

  defp entity_create_aspect_form_empty do
    %{"high_concept" => "", "trouble" => "", "additional_aspects" => ""}
  end

  defp split_aspects_list_to_form_fields(aspects) when is_list(aspects) do
    pairs =
      Enum.map(aspects, fn a ->
        r = to_string(a["role"] || a[:role] || "additional")
        d = a["description"] || a[:description] || ""
        {r, d}
      end)

    {hc, rem} = take_first_role_pair(pairs, "high_concept")
    {tr, rem} = take_first_role_pair(rem, "trouble")

    additional =
      Enum.map_join(rem, "\n", fn {r, d} ->
        if r == "additional", do: d, else: "#{r}|#{d}"
      end)

    %{
      "high_concept" => hc || "",
      "trouble" => tr || "",
      "additional_aspects" => additional
    }
  end

  defp take_first_role_pair(pairs, wanted) do
    case Enum.find_index(pairs, fn {r, _} -> r == wanted end) do
      nil ->
        {nil, pairs}

      i ->
        {_r, desc} = Enum.at(pairs, i)
        {desc, List.delete_at(pairs, i)}
    end
  end

  @doc """
  Builds form field map for editing an event. Pass `state_after_event: state` to fill
  patch-shaped `detail` fields from replayed snapshot (post-event derived state).
  """
  def build_edit_form_data(event, opts \\ [])

  def build_edit_form_data(%{type: :note} = event, opts) do
    detail = event.detail || %{}
    state = Keyword.get(opts, :state_after_event)

    target_ref =
      case {detail["target_type"], event.target_id} do
        {type, id} when type != nil and id != nil -> "#{type}:#{id}"
        _ -> ""
      end

    text =
      if Map.has_key?(detail, "text") do
        detail["text"] || ""
      else
        event.description || ""
      end

    target_ref =
      if target_ref != "" or state == nil do
        target_ref
      else
        note_target_ref_from_state(state, event.target_id, detail["target_type"])
      end

    edit_base(event, %{
      "text" => text,
      "target_ref" => target_ref
    })
  end

  def build_edit_form_data(%{type: :aspect_create} = event, opts) do
    detail = event.detail || %{}
    state = Keyword.get(opts, :state_after_event)

    target_ref =
      case {detail["target_type"], detail["target_id"] || event.target_id} do
        {type, id} when type != nil and id != nil -> "#{type}:#{id}"
        _ -> ""
      end

    aspect_row = aspect_create_row_from_state(state, event, detail)

    edit_base(event, %{
      "target_ref" => target_ref,
      "description" => aspect_field(aspect_row, detail, "description"),
      "role" =>
        aspect_field(aspect_row, detail, "role") ||
          (detail["role"] && to_string(detail["role"])) || "additional",
      "hidden" => if(aspect_hidden?(aspect_row, detail), do: "true", else: nil)
    })
  end

  def build_edit_form_data(%{type: :aspect_compel} = event, _opts) do
    detail = event.detail || %{}

    edit_base(event, %{
      "actor_id" => event.actor_id || detail["actor_id"] || "",
      "target_id" => event.target_id || detail["target_id"] || "",
      "aspect_id" => detail["aspect_id"] || "",
      "description" => detail["description"] || "",
      "accepted" => if(detail["accepted"] != false, do: "true", else: "false")
    })
  end

  def build_edit_form_data(%{type: :entity_move} = event, opts) do
    detail = event.detail || %{}
    state = Keyword.get(opts, :state_after_event)

    entity_id = detail["entity_id"] || event.actor_id || ""

    zone_id =
      if Map.has_key?(detail, "zone_id") do
        detail["zone_id"] || ""
      else
        if state && entity_id do
          entity = Map.get(state.entities, entity_id)
          if entity, do: entity.zone_id || "", else: ""
        else
          ""
        end
      end

    edit_base(event, %{
      "entity_id" => entity_id,
      "zone_id" => zone_id
    })
  end

  def build_edit_form_data(%{type: type} = event, opts)
      when type in ~w(scene_start scene_modify)a do
    detail = event.detail || %{}
    state = Keyword.get(opts, :state_after_event)
    scene_id = detail["scene_id"] || ""

    scene =
      if state && scene_id != "" do
        find_scene(state, scene_id)
      end

    name =
      if Map.has_key?(detail, "name"), do: detail["name"] || "", else: (scene && scene.name) || ""

    desc =
      if Map.has_key?(detail, "description"),
        do: detail["description"] || "",
        else: (scene && scene.description) || ""

    gm =
      if Map.has_key?(detail, "gm_notes"),
        do: detail["gm_notes"] || "",
        else: (scene && scene.gm_notes) || ""

    edit_base(event, %{
      "scene_id" => scene_id,
      "name" => name,
      "scene_description" => desc,
      "gm_notes" => gm
    })
  end

  def build_edit_form_data(%{type: :entity_create} = event, opts) do
    detail = event.detail || %{}
    state = Keyword.get(opts, :state_after_event)
    entity_id = detail["entity_id"] || ""
    entity = state && entity_id != "" && Map.get(state.entities, entity_id)

    aspect_form =
      cond do
        Map.has_key?(detail, "aspects") ->
          case detail["aspects"] do
            aspects when is_list(aspects) -> split_aspects_list_to_form_fields(aspects)
            _ -> entity_create_aspect_form_empty()
          end

        entity && entity.aspects != [] ->
          aspects =
            Enum.map(entity.aspects, fn a ->
              %{
                "role" => to_string(a.role || :additional),
                "description" => a.description || ""
              }
            end)

          split_aspects_list_to_form_fields(aspects)

        true ->
          entity_create_aspect_form_empty()
      end

    edit_base(event, %{
      "entity_id" => entity_id,
      "name" => field_from_detail_or_entity(detail, entity, "name", :name, & &1),
      "kind" =>
        field_from_detail_or_entity(detail, entity, "kind", :kind, fn
          nil -> "npc"
          k when is_atom(k) -> Atom.to_string(k)
          k -> to_string(k)
        end),
      "controller_id" =>
        field_from_detail_or_entity(detail, entity, "controller_id", :controller_id, & &1),
      "fate_points" =>
        field_from_detail_or_entity(detail, entity, "fate_points", :fate_points, &int_to_form/1),
      "refresh" =>
        field_from_detail_or_entity(detail, entity, "refresh", :refresh, &int_to_form/1),
      "parent_entity_id" =>
        field_from_detail_or_entity(detail, entity, "parent_entity_id", :parent_id, & &1)
    })
    |> Map.merge(aspect_form)
  end

  def build_edit_form_data(%{type: :entity_modify} = event, opts) do
    detail = event.detail || %{}
    state = Keyword.get(opts, :state_after_event)
    entity_id = detail["entity_id"] || event.target_id || ""
    entity = state && entity_id != "" && Map.get(state.entities, entity_id)

    changed =
      detail |> Map.keys() |> MapSet.new() |> MapSet.intersection(@entity_modify_form_keys)

    edit_base(event, %{
      "entity_id" => entity_id,
      "changed_fields" => changed,
      "name" => field_from_detail_or_entity(detail, entity, "name", :name, & &1),
      "kind" =>
        field_from_detail_or_entity(detail, entity, "kind", :kind, fn
          nil -> ""
          k when is_atom(k) -> Atom.to_string(k)
          k -> to_string(k)
        end),
      "controller_id" =>
        field_from_detail_or_entity(detail, entity, "controller_id", :controller_id, & &1),
      "fate_points" =>
        field_from_detail_or_entity(detail, entity, "fate_points", :fate_points, &int_to_form/1),
      "refresh" =>
        field_from_detail_or_entity(detail, entity, "refresh", :refresh, &int_to_form/1)
    })
  end

  def build_edit_form_data(%{type: :skill_set} = event, opts) do
    detail = event.detail || %{}
    state = Keyword.get(opts, :state_after_event)
    entity_id = detail["entity_id"] || event.target_id || ""
    entity = state && entity_id != "" && Map.get(state.entities, entity_id)

    skill =
      if Map.has_key?(detail, "skill") do
        detail["skill"] || ""
      else
        ""
      end

    rating_str =
      if Map.has_key?(detail, "rating") do
        to_string(detail["rating"] || "")
      else
        if entity && skill != "" do
          to_string(Map.get(entity.skills, skill, 0))
        else
          ""
        end
      end

    edit_base(event, %{
      "entity_id" => entity_id,
      "skill" => skill,
      "rating" => rating_str
    })
  end

  def build_edit_form_data(%{type: :stunt_add} = event, opts) do
    detail = event.detail || %{}
    state = Keyword.get(opts, :state_after_event)
    entity_id = detail["entity_id"] || event.target_id || ""
    stunt_id = detail["stunt_id"] || ""
    entity = state && entity_id != "" && Map.get(state.entities, entity_id)

    stunt =
      if entity && stunt_id != "" do
        Enum.find(entity.stunts, &(&1.id == stunt_id))
      end

    edit_base(event, %{
      "entity_id" => entity_id,
      "stunt_id" => stunt_id,
      "name" => field_from_detail_or_stunt(detail, stunt, "name", :name, & &1),
      "effect" => field_from_detail_or_stunt(detail, stunt, "effect", :effect, & &1)
    })
  end

  def build_edit_form_data(%{type: :stunt_remove} = event, _opts) do
    detail = event.detail || %{}

    edit_base(event, %{
      "entity_id" => detail["entity_id"] || event.target_id || "",
      "stunt_id" => detail["stunt_id"] || ""
    })
  end

  def build_edit_form_data(%{type: :set_system} = event, _opts) do
    detail = event.detail || %{}
    edit_base(event, %{"system" => detail["system"] || "core"})
  end

  def build_edit_form_data(%{type: type} = event, _opts)
      when type in ~w(fate_point_spend fate_point_earn fate_point_refresh)a do
    detail = event.detail || %{}
    edit_base(event, %{"entity_id" => detail["entity_id"] || event.target_id || ""})
  end

  def build_edit_form_data(event, _opts), do: %{"event_id" => event.id}

  defp edit_base(event, fields), do: Map.put(fields, "event_id", event.id)

  defp int_to_form(nil), do: ""
  defp int_to_form(v), do: to_string(v)

  defp field_from_detail_or_entity(detail, entity, detail_key, entity_key, from_entity) do
    if is_map(detail) && Map.has_key?(detail, detail_key) do
      v = Map.get(detail, detail_key)
      if detail_key in ~w(fate_points refresh), do: int_to_form(v), else: v || ""
    else
      case entity do
        nil -> ""
        e -> from_entity.(Map.get(e, entity_key)) || ""
      end
    end
  end

  defp field_from_detail_or_stunt(detail, stunt, detail_key, stunt_key, from_stunt) do
    if is_map(detail) && Map.has_key?(detail, detail_key) do
      Map.get(detail, detail_key) || ""
    else
      case stunt do
        nil -> ""
        s -> from_stunt.(Map.get(s, stunt_key)) || ""
      end
    end
  end

  defp aspect_field(aspect_row, detail, "description") do
    if aspect_row, do: aspect_row.description || "", else: detail["description"] || ""
  end

  defp aspect_field(aspect_row, detail, "role") do
    if aspect_row do
      to_string(aspect_row.role || :additional)
    else
      detail["role"] || "additional"
    end
  end

  defp aspect_hidden?(aspect_row, detail) do
    if aspect_row do
      aspect_row.hidden == true
    else
      detail["hidden"] == true
    end
  end

  defp aspect_create_row_from_state(nil, _event, _detail), do: nil

  defp aspect_create_row_from_state(state, event, detail) do
    target_type = detail["target_type"] || "entity"
    target_id = detail["target_id"] || event.target_id
    aid = Replay.aspect_id_for_create_event(event)

    case target_type do
      "entity" ->
        state.entities
        |> Map.get(target_id || "")
        |> case do
          nil -> nil
          e -> Enum.find(e.aspects, &(&1.id == aid))
        end

      "scene" ->
        find_scene(state, target_id)
        |> case do
          nil -> nil
          s -> Enum.find(s.aspects, &(&1.id == aid))
        end

      "zone" ->
        all_zones(state)
        |> Enum.find(&(&1.id == target_id))
        |> case do
          nil -> nil
          z -> Enum.find(z.aspects, &(&1.id == aid))
        end

      _ ->
        nil
    end
  end

  defp note_target_ref_from_state(_state, nil, _), do: ""

  defp note_target_ref_from_state(_state, target_id, target_type) when is_binary(target_id) do
    tt = target_type || "entity"
    "#{tt}:#{target_id}"
  end

  @doc """
  Merges `detail` for an event edit: starts from `original_detail`, updates only keys
  whose normalized submitted values differ from `baseline` (form values at open).
  """
  def merge_edit_detail(modal, original_detail, baseline, params, participants \\ [])

  def merge_edit_detail(modal, original, baseline, params, participants) do
    original = if is_map(original), do: original, else: %{}
    baseline = baseline || %{}

    case modal do
      "aspect_create" ->
        merge_aspect_create_detail(original, baseline, params)

      "aspect_compel" ->
        merge_aspect_compel_detail(original, baseline, params)

      "entity_move" ->
        merge_entity_move_detail(original, baseline, params)

      "scene_start" ->
        merge_scene_detail(original, baseline, params)

      "scene_modify" ->
        merge_scene_detail(original, baseline, params)

      "entity_create" ->
        merge_entity_create_detail(original, baseline, params, participants)

      "entity_edit" ->
        merge_entity_modify_detail(original, baseline, params, participants)

      "skill_set" ->
        merge_skill_set_detail(original, baseline, params)

      "stunt_add" ->
        merge_stunt_add_detail(original, baseline, params)

      "stunt_remove" ->
        merge_stunt_remove_detail(original, baseline, params)

      "set_system" ->
        merge_set_system_detail(original, baseline, params)

      m when m in ~w(fate_point_spend fate_point_earn fate_point_refresh) ->
        merge_fate_point_detail(original, baseline, params)

      m when m in ~w(note edit_note) ->
        merge_note_detail(original, baseline, params)

      _ ->
        original
    end
  end

  defp str(v), do: v |> to_string() |> String.trim()

  defp merge_aspect_create_detail(o, b, params) do
    br = str(b["target_ref"] || "")
    pr = str(params["target_ref"] || "")

    o
    |> put_if_str_changed(
      "description",
      str(params["description"] || ""),
      str(b["description"] || "")
    )
    |> put_if_str_changed(
      "role",
      params["role"] || "additional",
      b["role"] || "additional",
      &str/1
    )
    |> put_if_bool_changed("hidden", params["hidden"] == "true", b["hidden"] == "true")
    |> then(fn acc ->
      if pr != br do
        {tt, tid} = FateWeb.Helpers.parse_target_ref(params["target_ref"] || "")
        tt = tt || "entity"
        acc |> Map.put("target_type", tt) |> Map.put("target_id", tid)
      else
        acc
      end
    end)
  end

  defp merge_aspect_compel_detail(o, b, params) do
    accepted_new = params["accepted"] != "false"
    accepted_base = b["accepted"] != "false"

    o
    |> put_if_str_changed("actor_id", str(params["actor_id"] || ""), str(b["actor_id"] || ""))
    |> put_if_str_changed("target_id", str(params["target_id"] || ""), str(b["target_id"] || ""))
    |> put_if_str_changed("aspect_id", str(params["aspect_id"] || ""), str(b["aspect_id"] || ""))
    |> put_if_str_changed(
      "description",
      str(params["description"] || ""),
      str(b["description"] || "")
    )
    |> put_if_bool_changed("accepted", accepted_new, accepted_base)
  end

  defp merge_entity_move_detail(o, b, params) do
    o
    |> put_if_str_changed("entity_id", str(params["entity_id"] || ""), str(b["entity_id"] || ""))
    |> put_if_str_changed("zone_id", str(params["zone_id"] || ""), str(b["zone_id"] || ""))
  end

  defp merge_scene_detail(o, b, params) do
    acc =
      o
      |> put_if_str_changed("name", str(params["name"] || ""), str(b["name"] || ""))
      |> put_if_str_changed(
        "description",
        str(params["scene_description"] || ""),
        str(b["scene_description"] || "")
      )
      |> put_if_str_changed("gm_notes", str(params["gm_notes"] || ""), str(b["gm_notes"] || ""))

    sid = str(params["scene_id"] || "")
    sb = str(b["scene_id"] || "")

    if sid != sb, do: Map.put(acc, "scene_id", sid), else: acc
  end

  defp merge_entity_create_detail(o, b, params, participants) do
    new_controller =
      if params["controller_id"] not in [nil, ""], do: params["controller_id"], else: ""

    base_controller = str(b["controller_id"] || "")

    color =
      if new_controller != "" && new_controller != base_controller do
        bp = Enum.find(participants || [], &(&1.participant_id == new_controller))
        if(bp, do: bp.participant.color, else: "#6b7280")
      else
        nil
      end

    aspects_changed? =
      entity_create_aspects_from_form_params(params) !=
        entity_create_aspects_from_form_params(b)

    acc =
      o
      |> put_if_str_changed(
        "entity_id",
        str(params["entity_id"] || ""),
        str(b["entity_id"] || "")
      )
      |> put_if_str_changed("name", str(params["name"] || ""), str(b["name"] || ""))
      |> put_if_str_changed("kind", str(params["kind"] || "npc"), str(b["kind"] || "npc"))
      |> put_if_int_string_changed("fate_points", params["fate_points"], b["fate_points"])
      |> put_if_int_string_changed("refresh", params["refresh"], b["refresh"])
      |> put_if_str_changed(
        "parent_entity_id",
        str(params["parent_entity_id"] || ""),
        str(b["parent_entity_id"] || "")
      )

    acc =
      cond do
        new_controller != "" && new_controller != base_controller ->
          acc |> Map.put("controller_id", new_controller) |> Map.put("color", color)

        new_controller == "" && base_controller != "" ->
          Map.put(acc, "controller_id", nil)

        true ->
          acc
      end

    if aspects_changed? do
      Map.put(acc, "aspects", entity_create_aspects_from_form_params(params))
    else
      acc
    end
  end

  defp merge_entity_modify_detail(o, b, params, participants) do
    new_controller =
      if params["controller_id"] not in [nil, ""], do: params["controller_id"], else: ""

    base_controller = str(b["controller_id"] || "")

    acc =
      o
      |> put_if_str_changed(
        "entity_id",
        str(params["entity_id"] || ""),
        str(b["entity_id"] || "")
      )
      |> put_if_str_changed("name", str(params["name"] || ""), str(b["name"] || ""))
      |> put_if_kind_changed(params["kind"], b["kind"])
      |> put_if_int_string_changed("fate_points", params["fate_points"], b["fate_points"])
      |> put_if_int_string_changed("refresh", params["refresh"], b["refresh"])

    acc =
      cond do
        new_controller != "" && new_controller != base_controller ->
          color =
            case Enum.find(participants || [], &(&1.participant_id == new_controller)) do
              nil -> nil
              bp -> bp.participant.color
            end

          acc
          |> Map.put("controller_id", new_controller)
          |> then(fn a -> if color, do: Map.put(a, "color", color), else: a end)

        new_controller == "" && base_controller != "" ->
          Map.put(acc, "controller_id", nil)

        true ->
          acc
      end

    acc
  end

  defp merge_skill_set_detail(o, b, params) do
    o
    |> put_if_str_changed("entity_id", str(params["entity_id"] || ""), str(b["entity_id"] || ""))
    |> put_if_str_changed("skill", str(params["skill"] || ""), str(b["skill"] || ""))
    |> put_if_int_changed("rating", parse_int(params["rating"]), parse_int(b["rating"]))
  end

  defp merge_stunt_add_detail(o, b, params) do
    o
    |> put_if_str_changed("entity_id", str(params["entity_id"] || ""), str(b["entity_id"] || ""))
    |> put_if_str_changed("stunt_id", str(params["stunt_id"] || ""), str(b["stunt_id"] || ""))
    |> put_if_str_changed("name", str(params["name"] || ""), str(b["name"] || ""))
    |> put_if_str_changed("effect", str(params["effect"] || ""), str(b["effect"] || ""))
  end

  defp merge_stunt_remove_detail(o, b, params) do
    o
    |> put_if_str_changed("entity_id", str(params["entity_id"] || ""), str(b["entity_id"] || ""))
    |> put_if_str_changed("stunt_id", str(params["stunt_id"] || ""), str(b["stunt_id"] || ""))
  end

  defp merge_set_system_detail(o, b, params) do
    put_if_str_changed(o, "system", str(params["system"] || "core"), str(b["system"] || "core"))
  end

  defp merge_fate_point_detail(o, b, params) do
    put_if_str_changed(o, "entity_id", str(params["entity_id"] || ""), str(b["entity_id"] || ""))
  end

  defp merge_note_detail(o, b, params) do
    br = str(b["target_ref"] || "")
    pr = str(params["target_ref"] || "")

    o
    |> put_if_str_changed("text", str(params["text"] || ""), str(b["text"] || ""))
    |> then(fn acc ->
      if pr != br do
        {tt, tid} = FateWeb.Helpers.parse_target_ref(params["target_ref"] || "")

        acc
        |> maybe_put_target(tt, tid)
      else
        acc
      end
    end)
  end

  defp maybe_put_target(acc, nil, nil), do: acc

  defp maybe_put_target(acc, tt, tid) when is_binary(tid) and tid != "" do
    acc
    |> Map.put("target_type", tt || "entity")
    |> Map.put("target_id", tid)
  end

  defp maybe_put_target(acc, _, _), do: Map.delete(acc, "target_id") |> Map.delete("target_type")

  defp put_if_str_changed(map, key, new_val, base_val, norm \\ &str/1) do
    if norm.(new_val) != norm.(base_val), do: Map.put(map, key, new_val), else: map
  end

  defp put_if_bool_changed(map, key, new_val, base_val) do
    if new_val != base_val, do: Map.put(map, key, new_val), else: map
  end

  defp put_if_int_string_changed(map, key, param_val, base_str) do
    pn = parse_int(param_val)
    bn = parse_int(base_str)

    if pn != bn do
      if pn == nil, do: map, else: Map.put(map, key, pn)
    else
      map
    end
  end

  defp put_if_int_changed(map, key, new_int, base_int) do
    n = new_int || 0
    b = base_int || 0
    if n != b, do: Map.put(map, key, n), else: map
  end

  defp all_scenes(state) do
    active = if state.active_scene, do: [state.active_scene], else: []
    (state.scene_templates || []) ++ active
  end

  defp all_zones(state) do
    all_scenes(state) |> Enum.flat_map(& &1.zones)
  end

  defp find_scene(state, id) do
    a = state.active_scene

    if a && (a.id == id || Map.get(a, :template_id) == id) do
      a
    else
      Enum.find(state.scene_templates, &(&1.id == id))
    end
  end

  defp put_if_kind_changed(map, param_kind, base_kind) do
    p = str(param_kind || "")
    b = str(base_kind || "")

    cond do
      p == "" ->
        map

      p != b ->
        Map.put(map, "kind", p)

      true ->
        map
    end
  end

  def update_event_and_broadcast(event, attrs, bookmark_id) do
    Fate.Game.edit_event!(event, attrs)

    case Engine.derive_state(bookmark_id) do
      {:ok, state} ->
        Phoenix.PubSub.broadcast(
          Fate.PubSub,
          "bookmark:#{bookmark_id}",
          {:state_updated, state}
        )

        {:ok, state, event}

      _ ->
        {:ok, nil, nil}
    end
  end

  def create_or_update_event(params, attrs, bookmark_id) do
    case params["event_id"] do
      nil ->
        Engine.append_event(bookmark_id, attrs)

      event_id ->
        case Fate.Game.get_event(event_id) do
          {:ok, event} when event != nil ->
            update_attrs = Map.take(attrs, [:description, :detail, :target_id, :actor_id])
            update_event_and_broadcast(event, update_attrs, bookmark_id)

          _ ->
            {:error, "Event not found"}
        end
    end
  end
end
