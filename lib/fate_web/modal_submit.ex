defmodule FateWeb.ModalSubmit do
  @moduledoc """
  Pure builders for modal submit payloads shared by `TableLive` and `PlayerPanelLive`.
  """

  import FateWeb.ActionHelpers, only: [maybe_put_int: 3, parse_int: 1, put_non_empty: 3]

  def aspect_create_attrs(params, :panel) do
    desc = String.trim(params["description"] || "")

    if desc == "" do
      :error
    else
      {target_type, target_id} =
        case FateWeb.Helpers.parse_target_ref(params["target_ref"] || "") do
          {nil, nil} -> {"entity", params["target_id"]}
          pair -> pair
        end

      if target_id in [nil, ""] do
        :error
      else
        {:ok,
         %{
           type: :aspect_create,
           target_id: target_id,
           description: "Add aspect: #{desc}",
           detail: %{
             "target_id" => target_id,
             "target_type" => target_type,
             "description" => desc,
             "role" => params["role"] || "additional",
             "hidden" => params["hidden"] == "true"
           }
         }}
      end
    end
  end

  def aspect_create_attrs(params, :table_scene) do
    {target_type, target_id} = FateWeb.Helpers.parse_target_ref(params["target_ref"] || "")
    desc = String.trim(params["description"] || "")

    cond do
      target_id in [nil, ""] -> :error
      desc == "" -> :error
      true ->
        {:ok,
         %{
           type: :aspect_create,
           target_id: target_id,
           description: "Add aspect: #{desc}",
           detail: %{
             "target_id" => target_id,
             "target_type" => target_type,
             "description" => desc,
             "role" => "situation"
           }
         }}
    end
  end

  def aspect_create_attrs(params, {:table_entity, entity_id}) do
    desc = String.trim(params["description"] || "")
    role = params["role"] || "situation"

    if desc == "" do
      :error
    else
      {:ok,
       %{
         type: :aspect_create,
         target_id: entity_id,
         description: "Add aspect: #{desc}",
         detail: %{
           "target_id" => entity_id,
           "target_type" => "entity",
           "description" => desc,
           "role" => role
         }
       }}
    end
  end

  @doc "Caller supplies `scene_id` (new UUID on table, or `params[\"scene_id\"]` / generated on panel)."
  def scene_start_attrs(params, scene_id) when is_binary(scene_id) do
    %{
      type: :scene_start,
      description: "Start scene: #{params["name"]}",
      detail: %{
        "scene_id" => scene_id,
        "name" => params["name"],
        "description" => params["scene_description"],
        "gm_notes" => params["gm_notes"]
      }
    }
  end

  def note_attrs(params) do
    text = String.trim(params["text"] || "")

    if text == "" do
      :error
    else
      {target_type, target_id} = FateWeb.Helpers.parse_target_ref(params["target_ref"] || "")

      detail =
        %{"text" => text}
        |> then(fn d ->
          if target_id,
            do: Map.merge(d, %{"target_id" => target_id, "target_type" => target_type}),
            else: d
        end)

      {:ok,
       %{
         type: :note,
         target_id: target_id,
         description: text,
         detail: detail
       }}
    end
  end

  def entity_modify_attrs(params, participants, description_label) do
    entity_id = params["entity_id"]
    edit_controller_id = if params["controller_id"] not in [nil, ""], do: params["controller_id"]
    edit_color = controller_color(participants, edit_controller_id)

    detail =
      %{"entity_id" => entity_id}
      |> put_non_empty("name", params["name"])
      |> put_non_empty("kind", params["kind"])
      |> put_non_empty("controller_id", edit_controller_id)
      |> put_non_empty("color", edit_color)
      |> maybe_put_int("fate_points", params["fate_points"])
      |> maybe_put_int("refresh", params["refresh"])

    %{
      type: :entity_modify,
      target_id: entity_id,
      description: "Edit #{description_label}",
      detail: detail
    }
  end

  @doc "Panel uses `name` / `effect`; table ring modal uses `stunt_name` / `stunt_effect`. Pass `entity_id` when it is not in params (table)."
  def stunt_add_attrs(params, entity_id \\ nil) do
    eid = entity_id || params["entity_id"]
    name = params["name"] || params["stunt_name"] || ""
    effect = params["effect"] || params["stunt_effect"] || ""
    stunt_id = params["stunt_id"] || Ash.UUID.generate()

    %{
      type: :stunt_add,
      target_id: eid,
      description: "Stunt: #{name}",
      detail: %{
        "entity_id" => eid,
        "stunt_id" => stunt_id,
        "name" => name,
        "effect" => effect
      }
    }
  end

  def stunt_remove_attrs(params) do
    %{
      type: :stunt_remove,
      target_id: params["entity_id"],
      description: "Remove stunt",
      detail: %{
        "entity_id" => params["entity_id"],
        "stunt_id" => params["stunt_id"]
      }
    }
  end

  def scene_modify_attrs(params) do
    detail =
      %{"scene_id" => params["scene_id"]}
      |> put_non_empty("name", params["name"])
      |> put_non_empty("description", params["scene_description"])
      |> put_non_empty("gm_notes", params["gm_notes"])

    %{type: :scene_modify, description: "Edit scene", detail: detail}
  end

  def aspect_compel_attrs(params, target_display_name) when is_binary(target_display_name) do
    compel_actor_id = if params["actor_id"] not in [nil, ""], do: params["actor_id"]

    %{
      type: :aspect_compel,
      actor_id: compel_actor_id,
      target_id: params["target_id"],
      description: "Compel #{target_display_name}: #{params["description"]}",
      detail: %{
        "aspect_id" => params["aspect_id"],
        "description" => params["description"],
        "accepted" => params["accepted"] != "false"
      }
    }
  end

  def entity_move_attrs(params, zone_display_name) when is_binary(zone_display_name) do
    %{
      type: :entity_move,
      actor_id: params["entity_id"],
      description: "Move to #{zone_display_name}",
      detail: %{"entity_id" => params["entity_id"], "zone_id" => params["zone_id"]}
    }
  end

  def fate_point_spend_attrs(params) do
    %{
      type: :fate_point_spend,
      target_id: params["entity_id"],
      description: "Spend fate point",
      detail: %{"entity_id" => params["entity_id"], "amount" => 1}
    }
  end

  def fate_point_earn_attrs(params) do
    %{
      type: :fate_point_earn,
      target_id: params["entity_id"],
      description: "Earn fate point",
      detail: %{"entity_id" => params["entity_id"], "amount" => 1}
    }
  end

  def fate_point_refresh_attrs(params) do
    %{
      type: :fate_point_refresh,
      target_id: params["entity_id"],
      description: "Refresh fate points",
      detail: %{"entity_id" => params["entity_id"]}
    }
  end

  def skill_set_attrs(params) do
    %{
      type: :skill_set,
      target_id: params["entity_id"],
      description: "#{params["skill"]} → +#{params["rating"]}",
      detail: %{
        "entity_id" => params["entity_id"],
        "skill" => params["skill"],
        "rating" => parse_int(params["rating"]) || 0
      }
    }
  end

  def set_system_attrs(params) do
    %{
      type: :set_system,
      description: "Set system: #{params["system"]}",
      detail: %{"system" => params["system"]}
    }
  end

  @doc "Pass the active scene struct/map (with `id` and `name`), or `nil` if none."
  def scene_end_attrs(nil), do: :error

  def scene_end_attrs(scene) do
    {:ok,
     %{
       type: :scene_end,
       description: "End scene: #{scene.name}",
       detail: %{"scene_id" => scene.id}
     }}
  end

  def zone_create_attrs(active_scene_id, params) when is_binary(active_scene_id) do
    %{
      type: :zone_create,
      description: "Create zone: #{params["name"]}",
      detail: %{
        "scene_id" => active_scene_id,
        "zone_id" => Ash.UUID.generate(),
        "name" => params["name"],
        "hidden" => true
      }
    }
  end

  def entity_create_attrs(params, participants) do
    controller_id = if params["controller_id"] not in [nil, ""], do: params["controller_id"]
    color = entity_create_controller_color(controller_id, participants)

    detail = %{
      "entity_id" => params["entity_id"] || Ash.UUID.generate(),
      "name" => params["name"],
      "kind" => params["kind"] || "npc",
      "color" => color,
      "controller_id" => controller_id,
      "fate_points" => parse_int(params["fate_points"]),
      "refresh" => parse_int(params["refresh"]),
      "parent_entity_id" => params["parent_entity_id"]
    }

    detail =
      case FateWeb.ActionHelpers.entity_create_aspects_from_form_params(params) do
        [] -> detail
        aspects -> Map.put(detail, "aspects", aspects)
      end

    %{
      type: :entity_create,
      description: "Create #{params["name"]}",
      detail: detail
    }
  end

  defp entity_create_controller_color(nil, _), do: "#6b7280"
  defp entity_create_controller_color("", _), do: "#6b7280"

  defp entity_create_controller_color(controller_id, participants) when is_binary(controller_id) do
    case Enum.find(participants || [], &(&1.participant_id == controller_id)) do
      nil -> "#6b7280"
      bp -> bp.participant.color || "#6b7280"
    end
  end

  defp controller_color(_participants, nil), do: nil
  defp controller_color(_participants, ""), do: nil

  defp controller_color(participants, controller_id) when is_binary(controller_id) do
    case Enum.find(participants || [], &(&1.participant_id == controller_id)) do
      nil -> nil
      bp -> bp.participant.color
    end
  end
end
