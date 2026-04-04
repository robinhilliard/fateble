defmodule FateWeb.ActionHelpers do
  @moduledoc """
  Shared helpers for event editing, form data construction, and event persistence.

  These functions are extracted from ActionsLive so they can be reused
  by any LiveView that hosts the event log and action palette.
  """

  alias Fate.Engine

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

  def build_edit_form_data(%{type: :note} = event) do
    detail = event.detail || %{}

    target_ref =
      case {detail["target_type"], event.target_id} do
        {type, id} when type != nil and id != nil -> "#{type}:#{id}"
        _ -> ""
      end

    edit_base(event, %{
      "text" => detail["text"] || event.description || "",
      "target_ref" => target_ref
    })
  end

  def build_edit_form_data(%{type: :aspect_create} = event) do
    detail = event.detail || %{}

    target_ref =
      case {detail["target_type"], detail["target_id"] || event.target_id} do
        {type, id} when type != nil and id != nil -> "#{type}:#{id}"
        _ -> ""
      end

    edit_base(event, %{
      "target_ref" => target_ref,
      "description" => detail["description"] || "",
      "role" => detail["role"] || "additional",
      "hidden" => if(detail["hidden"] == true, do: "true", else: nil)
    })
  end

  def build_edit_form_data(%{type: :aspect_compel} = event) do
    detail = event.detail || %{}

    edit_base(event, %{
      "actor_id" => event.actor_id || "",
      "target_id" => event.target_id || detail["target_id"] || "",
      "aspect_id" => detail["aspect_id"] || "",
      "description" => detail["description"] || "",
      "accepted" => if(detail["accepted"] != false, do: "true", else: "false")
    })
  end

  def build_edit_form_data(%{type: :entity_move} = event) do
    detail = event.detail || %{}

    edit_base(event, %{
      "entity_id" => detail["entity_id"] || event.actor_id || "",
      "zone_id" => detail["zone_id"] || ""
    })
  end

  def build_edit_form_data(%{type: type} = event) when type in ~w(scene_start scene_modify)a do
    detail = event.detail || %{}

    edit_base(event, %{
      "scene_id" => detail["scene_id"] || "",
      "name" => detail["name"] || "",
      "scene_description" => detail["description"] || "",
      "gm_notes" => detail["gm_notes"] || ""
    })
  end

  def build_edit_form_data(%{type: :entity_create} = event) do
    detail = event.detail || %{}

    aspects_text =
      case detail["aspects"] do
        aspects when is_list(aspects) ->
          Enum.map_join(aspects, "\n", fn a ->
            if a["role"] && a["role"] != "additional",
              do: "#{a["role"]}|#{a["description"]}",
              else: a["description"] || ""
          end)

        _ ->
          ""
      end

    edit_base(event, %{
      "entity_id" => detail["entity_id"] || "",
      "name" => detail["name"] || "",
      "kind" => detail["kind"] || "npc",
      "controller_id" => detail["controller_id"] || "",
      "fate_points" => to_string(detail["fate_points"] || ""),
      "refresh" => to_string(detail["refresh"] || ""),
      "parent_entity_id" => detail["parent_entity_id"] || "",
      "aspects" => aspects_text
    })
  end

  def build_edit_form_data(%{type: :entity_modify} = event) do
    detail = event.detail || %{}

    edit_base(event, %{
      "entity_id" => detail["entity_id"] || event.target_id || "",
      "name" => detail["name"] || "",
      "kind" => detail["kind"] || "",
      "controller_id" => detail["controller_id"] || "",
      "fate_points" => to_string(detail["fate_points"] || ""),
      "refresh" => to_string(detail["refresh"] || "")
    })
  end

  def build_edit_form_data(%{type: :skill_set} = event) do
    detail = event.detail || %{}

    edit_base(event, %{
      "entity_id" => detail["entity_id"] || event.target_id || "",
      "skill" => detail["skill"] || "",
      "rating" => to_string(detail["rating"] || "")
    })
  end

  def build_edit_form_data(%{type: :stunt_add} = event) do
    detail = event.detail || %{}

    edit_base(event, %{
      "entity_id" => detail["entity_id"] || event.target_id || "",
      "stunt_id" => detail["stunt_id"] || "",
      "name" => detail["name"] || "",
      "effect" => detail["effect"] || ""
    })
  end

  def build_edit_form_data(%{type: :stunt_remove} = event) do
    detail = event.detail || %{}

    edit_base(event, %{
      "entity_id" => detail["entity_id"] || event.target_id || "",
      "stunt_id" => detail["stunt_id"] || ""
    })
  end

  def build_edit_form_data(%{type: :set_system} = event) do
    detail = event.detail || %{}
    edit_base(event, %{"system" => detail["system"] || "core"})
  end

  def build_edit_form_data(%{type: type} = event)
      when type in ~w(fate_point_spend fate_point_earn fate_point_refresh)a do
    detail = event.detail || %{}
    edit_base(event, %{"entity_id" => detail["entity_id"] || event.target_id || ""})
  end

  def build_edit_form_data(event), do: %{"event_id" => event.id}

  defp edit_base(event, fields), do: Map.put(fields, "event_id", event.id)

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
