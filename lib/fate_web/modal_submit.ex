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

  def aspect_create_attrs(params, {:table_scene, active_scene?}) do
    {target_type, target_id} = FateWeb.Helpers.parse_target_ref(params["target_ref"] || "")
    desc = String.trim(params["description"] || "")

    cond do
      target_id in [nil, ""] ->
        :error

      desc == "" ->
        :error

      true ->
        type = if active_scene?, do: :active_aspect_add, else: :template_aspect_add

        {:ok,
         %{
           type: type,
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

  @doc "Create a scene template (prep). Caller supplies scene_id."
  def template_scene_create_attrs(params, scene_id) when is_binary(scene_id) do
    %{
      type: :template_scene_create,
      description: "Create scene: #{params["name"]}",
      detail: %{
        "scene_id" => scene_id,
        "name" => params["name"],
        "description" => params["scene_description"],
        "gm_notes" => params["gm_notes"]
      }
    }
  end

  @doc "Activate a scene template as the active scene (play)."
  def active_scene_start_attrs(scene_id) when is_binary(scene_id) do
    %{
      type: :active_scene_start,
      description: "Start scene",
      detail: %{"scene_id" => scene_id}
    }
  end

  @doc "Start a blank scene (ad-hoc): creates ephemeral template + activates."
  def active_scene_start_blank_attrs(params) do
    scene_id = Ash.UUID.generate()

    %{
      type: :active_scene_start,
      description: "Start scene: #{params["name"] || "Untitled"}",
      detail: %{
        "scene_id" => scene_id,
        "name" => params["name"]
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

  def template_scene_modify_attrs(params) do
    detail =
      %{"scene_id" => params["scene_id"]}
      |> put_non_empty("name", params["name"])
      |> put_non_empty("description", params["scene_description"])
      |> put_non_empty("gm_notes", params["gm_notes"])

    %{type: :template_scene_modify, description: "Edit scene template", detail: detail}
  end

  def active_scene_update_attrs(params) do
    detail =
      %{}
      |> put_non_empty("name", params["name"])
      |> put_non_empty("description", params["scene_description"])
      |> put_non_empty("gm_notes", params["gm_notes"])

    %{type: :active_scene_update, description: "Update scene", detail: detail}
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

  def fate_point_spend_attrs(params, opts \\ []) when is_list(opts) do
    entity_id = params["entity_id"]
    description = Keyword.get(opts, :description, "Spend fate point")

    %{
      type: :fate_point_spend,
      target_id: entity_id,
      description: description,
      detail: %{"entity_id" => entity_id, "amount" => 1}
    }
  end

  def fate_point_earn_attrs(params, opts \\ []) when is_list(opts) do
    entity_id = params["entity_id"]
    description = Keyword.get(opts, :description, "Earn fate point")

    %{
      type: :fate_point_earn,
      target_id: entity_id,
      description: description,
      detail: %{"entity_id" => entity_id, "amount" => 1}
    }
  end

  @doc """
  Table ring / quick actions: FP spend (if not free) then invoke. Caller appends each map in order.
  """
  def ring_invoke_aspect_events(entity_id, description, is_free) when is_boolean(is_free) do
    spend =
      if is_free do
        []
      else
        [
          fate_point_spend_attrs(%{"entity_id" => entity_id},
            description: "Spend FP to invoke: #{description}"
          )
        ]
      end

    invoke = %{
      type: :invoke,
      actor_id: entity_id,
      description: "Invoke: #{description}#{if is_free, do: " (free)", else: " (FP)"}",
      detail: %{"description" => description, "free" => is_free}
    }

    spend ++ [invoke]
  end

  @doc "Table ring compel (accepted) plus matching FP earn. Caller appends each map in order."
  def ring_compel_accepted_events(entity_id, aspect_id, description) do
    compel = %{
      type: :aspect_compel,
      target_id: entity_id,
      description: "Compel: #{description}",
      detail: %{
        "aspect_id" => aspect_id,
        "description" => description,
        "accepted" => true
      }
    }

    earn =
      fate_point_earn_attrs(%{"entity_id" => entity_id},
        description: "Earn FP from compel: #{description}"
      )

    [compel, earn]
  end

  @doc "End the active scene from the table ring."
  def active_scene_end_attrs(scene) do
    %{
      type: :active_scene_end,
      description: "End scene #{scene.name}",
      detail: %{"scene_id" => Map.get(scene, :template_id, scene.id)}
    }
  end

  def concede_attrs(entity_id) do
    %{type: :concede, actor_id: entity_id, description: "Concede"}
  end

  def entity_remove_attrs(entity_id, name_or_nil \\ nil, kind_or_nil \\ nil) do
    kind_str = if kind_or_nil, do: to_string(kind_or_nil), else: nil

    %{
      type: :entity_remove,
      target_id: entity_id,
      description: "Remove #{kind_str || "entity"}#{if name_or_nil, do: " #{name_or_nil}"}",
      detail: %{"entity_id" => entity_id, "name" => name_or_nil, "kind" => kind_str}
    }
  end

  def mook_eliminate_attrs(entity_id) do
    %{
      type: :mook_eliminate,
      target_id: entity_id,
      description: "Mook eliminated",
      detail: %{"entity_id" => entity_id, "count" => 1}
    }
  end

  def taken_out_attrs(entity_id) do
    %{type: :taken_out, target_id: entity_id, description: "Taken out"}
  end

  def stress_clear_attrs(entity_id) do
    %{
      type: :stress_clear,
      target_id: entity_id,
      description: "Clear all stress"
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

  @doc "Pass the active scene struct, or `nil` if none."
  def scene_end_attrs(nil), do: :error

  def scene_end_attrs(scene) do
    {:ok, active_scene_end_attrs(scene)}
  end

  def template_zone_create_attrs(scene_id, params) when is_binary(scene_id) do
    %{
      type: :template_zone_create,
      description: "Create zone: #{params["name"]}",
      detail: %{
        "scene_id" => scene_id,
        "zone_id" => Ash.UUID.generate(),
        "name" => params["name"],
        "hidden" => true
      }
    }
  end

  def active_zone_add_attrs(params) do
    %{
      type: :active_zone_add,
      description: "Add zone: #{params["name"]}",
      detail: %{
        "zone_id" => Ash.UUID.generate(),
        "name" => params["name"],
        "hidden" => Map.get(params, "hidden", true)
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

  defp entity_create_controller_color(controller_id, participants)
       when is_binary(controller_id) do
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
