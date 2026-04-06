defmodule FateWeb.ActionComponents do
  use FateWeb, :html

  alias Fate.Engine

  import FateWeb.ModalComponents
  import FateWeb.ModalForms

  defp mention_catalog_json(assigns) do
    Map.get(assigns, :mention_catalog_json) || Engine.mention_catalog_json(nil)
  end

  @event_type_labels %{
    create_campaign: "Create Campaign",
    set_system: "Set System",
    scene_start: "Scene Start",
    scene_end: "Scene End",
    zone_create: "Create Zone",
    entity_enter_scene: "Enter Scene",
    entity_move: "Move",
    entity_create: "Create Entity",
    entity_restore: "Restore Entity",
    entity_modify: "Modify Entity",
    entity_remove: "Remove Entity",
    aspect_create: "Create Aspect",
    aspect_remove: "Remove Aspect",
    aspect_modify: "Modify Aspect",
    aspect_compel: "Compel",
    skill_set: "Set Skill",
    stunt_add: "Add Stunt",
    stunt_remove: "Remove Stunt",
    roll_attack: "Roll Attack",
    roll_defend: "Roll Defend",
    roll_overcome: "Roll Overcome",
    roll_create_advantage: "Roll Create Advantage",
    invoke: "Invoke Aspect",
    shifts_resolved: "Shifts Resolved",
    redirect_hit: "Redirect Hit",
    stress_apply: "Apply Stress",
    stress_clear: "Clear Stress",
    consequence_take: "Take Consequence",
    consequence_recover: "Recover Consequence",
    fate_point_spend: "Spend Fate Point",
    fate_point_earn: "Earn Fate Point",
    fate_point_refresh: "Refresh Fate Points",
    concede: "Concede",
    taken_out: "Taken Out",
    mook_eliminate: "Eliminate Mook",
    zone_modify: "Modify Zone",
    scene_modify: "Edit Scene",
    note: "Note"
  }

  @editable_types ~w(aspect_create aspect_compel entity_move scene_start scene_modify
    entity_create entity_modify skill_set stunt_add stunt_remove set_system
    fate_point_spend fate_point_earn fate_point_refresh note)a

  def event_type_labels, do: @event_type_labels

  def editable_type?(type), do: type in @editable_types

  @entity_modify_form_keys MapSet.new(~w(name kind controller_id fate_points refresh))

  def editable_event?(%{type: :entity_modify, detail: detail}) when is_map(detail) do
    detail |> Map.keys() |> Enum.any?(&MapSet.member?(@entity_modify_form_keys, &1))
  end

  def editable_event?(%{type: type}), do: editable_type?(type)

  # --- Event log ---

  def event_row(assigns) do
    color = entity_color(assigns.state, assigns.event.actor_id)
    summary = compact_event_summary(assigns.event, assigns.state)
    draggable = assigns[:is_gm] && !assigns[:immutable] && !assigns[:is_observer]

    my_ids = assigns[:my_entity_ids] || MapSet.new()
    event = assigns.event
    detail = event.detail || %{}

    involves_me =
      MapSet.size(my_ids) > 0 &&
        (MapSet.member?(my_ids, event.target_id) ||
           MapSet.member?(my_ids, event.actor_id) ||
           MapSet.member?(my_ids, detail["entity_id"]) ||
           MapSet.member?(my_ids, detail["target_id"]))

    index_tooltip_extra = event_log_index_tooltip(event, assigns.state)
    full_summary = full_event_summary(event, assigns.state)

    type_label =
      Map.get(event_type_labels(), event.type) ||
        event.type |> to_string() |> String.replace("_", " ")

    index_tooltip =
      index_tooltip_extra || "#{assigns.index} · #{type_label}"

    assigns =
      assigns
      |> assign(:color, color)
      |> assign(:summary, summary)
      |> assign(:full_summary, full_summary)
      |> assign(:draggable, draggable)
      |> assign(:involves_me, involves_me)
      |> assign(:index_tooltip, index_tooltip)
      |> assign_new(:immutable, fn -> false end)
      |> assign_new(:is_observer, fn -> false end)
      |> assign_new(:is_gm, fn -> false end)
      |> assign_new(:invalid, fn -> nil end)
      |> assign_new(:tip_of_timeline, fn -> false end)
      |> then(&assign(&1, :warn_history_action_tooltip, !&1.tip_of_timeline))

    ~H"""
    <div
      id={"event-#{@index}"}
      class={[
        "group relative z-0 hover:z-30 flex items-center gap-2 px-2 py-1 rounded transition text-sm event-row",
        if(@event.exchange_id, do: "ml-4 border-l-2 border-amber-700/20", else: ""),
        if(@immutable, do: "opacity-30", else: "hover:bg-amber-900/20"),
        @draggable && "cursor-grab",
        @involves_me && !@immutable && "bg-amber-800/15"
      ]}
      draggable={if(@draggable, do: "true", else: "false")}
      data-event-id={@event.id}
      data-event-index={@index}
    >
      <%= if @invalid do %>
        <span
          class="text-amber-500 shrink-0 relative event-log-index-tooltip"
          data-tooltip={"This event had no effect — #{@invalid}"}
        >
          <.icon name="hero-exclamation-triangle" class="w-3.5 h-3.5" />
        </span>
      <% else %>
        <div
          class="w-2 h-2 rounded-full shrink-0"
          style={"background: #{@color};"}
        />
      <% end %>
      <span
        class="text-amber-200/40 text-xs shrink-0 relative event-log-index-tooltip"
        data-tooltip={@index_tooltip}
      >
        {@index}
      </span>
      <span
        class="flex-1 text-amber-100/80 truncate"
        style="font-family: 'Patrick Hand', cursive;"
        data-summary-tooltip={@full_summary}
      >
        {@summary}
      </span>
      <%= if editable_event?(@event) && !@immutable && !@is_observer do %>
        <button
          phx-click="edit_event"
          phx-value-id={@event.id}
          class={[
            "opacity-0 group-hover:opacity-100 text-amber-400/50 hover:text-amber-300 text-xs transition shrink-0 relative touch-reveal",
            @warn_history_action_tooltip && "event-log-action-tooltip"
          ]}
          data-tooltip={
            if(@warn_history_action_tooltip,
              do: "Change a historical event - BE CAREFUL",
              else: nil
            )
          }
        >
          <.icon name="hero-pencil-square" class="w-3.5 h-3.5" />
        </button>
      <% end %>
      <%= if !@immutable && !@is_observer do %>
        <button
          phx-click="delete_event"
          phx-value-id={@event.id}
          class={[
            "opacity-0 group-hover:opacity-100 text-red-400/50 hover:text-red-400 text-xs transition shrink-0 relative touch-reveal",
            @warn_history_action_tooltip && "event-log-action-tooltip"
          ]}
          data-tooltip={
            if(@warn_history_action_tooltip,
              do: "Permanently delete this event from history - BE CAREFUL",
              else: nil
            )
          }
          data-confirm={if(@tip_of_timeline, do: nil, else: "Delete this event?")}
        >
          ✕
        </button>
      <% end %>
    </div>
    """
  end

  def compact_event_summary(%{type: :create_campaign} = event, _state) do
    detail = event.detail || %{}
    "Create campaign #{detail["campaign_name"] || event.description}"
  end

  def compact_event_summary(%{type: :set_system} = event, _state) do
    detail = event.detail || %{}
    "Set system to #{detail["system"] || "core"}"
  end

  def compact_event_summary(%{type: :entity_create} = event, _state) do
    detail = event.detail || %{}
    "Create #{detail["kind"] || "entity"} #{detail["name"]}"
  end

  def compact_event_summary(%{type: :entity_restore} = event, state) do
    label = entity_label(state, event.target_id)

    if label do
      "Restore #{label}"
    else
      detail = event.detail || %{}
      "Restore #{detail["kind"] || "entity"} #{detail["name"]}"
    end
  end

  def compact_event_summary(%{type: :entity_modify} = event, state) do
    detail = event.detail || %{}
    label = entity_label(state, event.target_id) || detail["name"] || "entity"

    cond do
      not editable_event?(event) && detail["hidden"] == true -> "Hide #{label}"
      not editable_event?(event) && detail["hidden"] == false -> "Reveal #{label}"
      true -> "Edit #{label}"
    end
  end

  def compact_event_summary(%{type: :entity_remove} = event, state) do
    detail = event.detail || %{}

    label =
      entity_label(state, event.target_id) ||
        detail_label(detail["kind"], detail["name"]) ||
        "entity"

    "Remove #{label}"
  end

  def compact_event_summary(%{type: :aspect_create} = event, state) do
    detail = event.detail || %{}
    target = entity_label(state, event.target_id)
    resolved = target || target_name(state, event.target_id, detail["target_type"])
    "Add aspect \"#{detail["description"]}\"#{if resolved, do: " on #{resolved}"}"
  end

  def compact_event_summary(%{type: :aspect_remove} = event, state) do
    detail = event.detail || %{}
    target = entity_label(state, event.target_id)
    desc = detail["description"] || detail["aspect_description"]
    resolved = target || target_name(state, event.target_id, detail["target_type"])

    if desc do
      "Remove aspect \"#{desc}\"#{if resolved, do: " from #{resolved}"}"
    else
      "Remove aspect#{if resolved, do: " from #{resolved}"}"
    end
  end

  def compact_event_summary(%{type: :aspect_modify} = event, _state) do
    event.description || "Modify aspect"
  end

  def compact_event_summary(%{type: :aspect_compel} = event, state) do
    detail = event.detail || %{}
    target = entity_label(state, event.target_id) || "?"
    "Compel #{target} with #{detail["description"] || "aspect"}"
  end

  def compact_event_summary(%{type: :skill_set} = event, state) do
    detail = event.detail || %{}
    target = entity_label(state, event.target_id) || "entity"
    rating = detail["rating"]

    if rating == 0 do
      "Remove #{detail["skill"]} from #{target}"
    else
      "Set #{detail["skill"]} to +#{rating} on #{target}"
    end
  end

  def compact_event_summary(%{type: :stunt_add} = event, state) do
    detail = event.detail || %{}
    target = entity_label(state, event.target_id) || "entity"
    "Add stunt #{detail["name"]} to #{target}"
  end

  def compact_event_summary(%{type: :stunt_remove} = event, state) do
    target = entity_label(state, event.target_id) || "entity"
    "Remove stunt from #{target}"
  end

  def compact_event_summary(%{type: type} = event, _state)
      when type in [:scene_start, :template_scene_create] do
    detail = event.detail || %{}
    "Create scene #{detail["name"]}"
  end

  def compact_event_summary(%{type: :active_scene_start} = event, state) do
    detail = event.detail || %{}
    scene_id = detail["scene_id"]

    name =
      case Enum.find(state.scene_templates, &(&1.id == scene_id)) do
        nil -> detail["name"]
        template -> template.name
      end

    "Start scene #{name || "Untitled"}"
  end

  def compact_event_summary(%{type: type} = event, _state)
      when type in [:scene_end, :active_scene_end] do
    event.description || "End scene"
  end

  def compact_event_summary(%{type: type}, _state)
      when type in [:scene_modify, :template_scene_modify],
      do: "Edit scene"

  def compact_event_summary(%{type: :active_scene_update}, _state), do: "Update scene"

  def compact_event_summary(%{type: type} = event, _state)
      when type in [:zone_create, :template_zone_create, :active_zone_add] do
    detail = event.detail || %{}
    "Add zone #{detail["name"]}"
  end

  def compact_event_summary(%{type: type} = event, state)
      when type in [:zone_modify, :template_zone_modify, :active_zone_modify] do
    detail = event.detail || %{}
    zone = zone_name(state, detail["zone_id"])
    "#{if detail["hidden"] == false, do: "Reveal", else: "Hide"} zone#{if zone, do: " #{zone}"}"
  end

  def compact_event_summary(%{type: :template_aspect_add} = event, _state) do
    detail = event.detail || %{}
    "Add aspect \"#{detail["description"]}\""
  end

  def compact_event_summary(%{type: :active_aspect_add} = event, _state) do
    detail = event.detail || %{}
    "Add aspect \"#{detail["description"]}\""
  end

  def compact_event_summary(%{type: :active_aspect_modify}, _state), do: "Modify scene aspect"
  def compact_event_summary(%{type: :active_aspect_remove}, _state), do: "Remove scene aspect"

  def compact_event_summary(%{type: :template_entity_place} = event, state) do
    detail = event.detail || %{}
    label = entity_label(state, detail["entity_id"]) || "entity"
    "Place #{label} in scene"
  end

  def compact_event_summary(%{type: :entity_enter_scene} = event, state) do
    detail = event.detail || %{}
    actor = entity_label(state, event.actor_id) || "entity"
    zone = zone_name(state, detail["zone_id"])
    if zone, do: "#{actor} enters #{zone}", else: "#{actor} enters scene"
  end

  def compact_event_summary(%{type: :entity_move} = event, state) do
    detail = event.detail || %{}
    actor = entity_label(state, event.actor_id) || "entity"
    zone = zone_name(state, detail["zone_id"])
    if zone, do: "Move #{actor} to #{zone}", else: "#{actor} leaves zone"
  end

  def compact_event_summary(%{type: :roll_attack} = event, state) do
    detail = event.detail || %{}
    actor = entity_label(state, event.actor_id) || "entity"
    "#{actor} attacks with #{detail["skill"] || "?"} #{format_dice(detail["fudge_dice"] || [])} = #{detail["raw_total"] || "?"}"
  end

  def compact_event_summary(%{type: :roll_defend} = event, state) do
    detail = event.detail || %{}
    actor = entity_label(state, event.actor_id) || "entity"
    "#{actor} defends with #{detail["skill"] || "?"} #{format_dice(detail["fudge_dice"] || [])} = #{detail["raw_total"] || "?"}"
  end

  def compact_event_summary(%{type: :roll_overcome} = event, state) do
    detail = event.detail || %{}
    actor = entity_label(state, event.actor_id) || "entity"
    "#{actor} overcomes with #{detail["skill"] || "?"} #{format_dice(detail["fudge_dice"] || [])}"
  end

  def compact_event_summary(%{type: :roll_create_advantage} = event, state) do
    detail = event.detail || %{}
    actor = entity_label(state, event.actor_id) || "entity"
    "#{actor} creates advantage with #{detail["skill"] || "?"} #{format_dice(detail["fudge_dice"] || [])}"
  end

  def compact_event_summary(%{type: :invoke} = event, state) do
    detail = event.detail || %{}
    actor = entity_label(state, event.actor_id) || "entity"
    "#{actor} invokes #{detail["description"] || "aspect"}"
  end

  def compact_event_summary(%{type: :shifts_resolved} = event, state) do
    detail = event.detail || %{}
    target = entity_label(state, event.target_id)
    "Resolve #{detail["shifts"] || 0} shifts#{if target, do: " on #{target}"}"
  end

  def compact_event_summary(%{type: :redirect_hit} = event, state) do
    target = entity_label(state, event.target_id)
    "Redirect hit#{if target, do: " to #{target}"}"
  end

  def compact_event_summary(%{type: :stress_apply} = event, state) do
    detail = event.detail || %{}
    target = entity_label(state, event.target_id) || "entity"
    "Apply stress box #{detail["box_index"]} to #{target}"
  end

  def compact_event_summary(%{type: :stress_clear} = event, state) do
    target = entity_label(state, event.target_id) || "entity"
    "Clear all stress on #{target}"
  end

  def compact_event_summary(%{type: :consequence_take} = event, state) do
    detail = event.detail || %{}
    target = entity_label(state, event.target_id) || "entity"
    "#{target} takes #{detail["severity"]} consequence #{detail["aspect_text"]}"
  end

  def compact_event_summary(%{type: :consequence_recover} = event, state) do
    target = entity_label(state, event.target_id) || "entity"
    "#{target} recovers consequence"
  end

  def compact_event_summary(%{type: :fate_point_spend} = event, state) do
    target = entity_label(state, event.target_id) || "entity"
    "#{target} spends fate point"
  end

  def compact_event_summary(%{type: :fate_point_earn} = event, state) do
    target = entity_label(state, event.target_id) || "entity"
    "#{target} earns fate point"
  end

  def compact_event_summary(%{type: :fate_point_refresh} = event, state) do
    target = entity_label(state, event.target_id) || "entity"
    "Refresh fate points on #{target}"
  end

  def compact_event_summary(%{type: :concede} = event, state) do
    actor = entity_label(state, event.actor_id) || "entity"
    "#{actor} concedes"
  end

  def compact_event_summary(%{type: :taken_out} = event, state) do
    target = entity_label(state, event.target_id) || entity_label(state, event.actor_id) || "entity"
    "#{target} is taken out"
  end

  def compact_event_summary(%{type: :mook_eliminate} = event, state) do
    target = entity_label(state, event.target_id) || "mook"
    "Eliminate #{target}"
  end

  def compact_event_summary(%{type: :note} = event, state) do
    detail = event.detail || %{}
    text = detail["text"] || event.description || ""
    target = entity_label(state, event.target_id)
    resolved = target || target_name(state, event.target_id, detail["target_type"])
    truncated = if String.length(text) > 60, do: String.slice(text, 0..57) <> "...", else: text
    if resolved, do: "#{truncated} (#{resolved})", else: truncated
  end

  def compact_event_summary(event, _state) do
    event.description || to_string(event.type)
  end

  @doc """
  Full untruncated event summary for the title tooltip on the event row.
  Falls back to `compact_event_summary` when there is no additional detail.
  """
  def full_event_summary(%{type: :aspect_create} = event, state) do
    detail = event.detail || %{}
    target = entity_label(state, event.target_id)
    resolved = target || target_name(state, event.target_id, detail["target_type"])
    desc = detail["description"] || ""
    role = detail["role"]
    role_str = if role && role not in ["additional", "situation"], do: " (#{role})", else: ""
    "Add aspect#{role_str}: #{desc}#{if resolved, do: " — #{resolved}"}"
  end

  def full_event_summary(%{type: :note} = event, state) do
    detail = event.detail || %{}
    text = detail["text"] || event.description || ""
    target = entity_label(state, event.target_id)
    resolved = target || target_name(state, event.target_id, detail["target_type"])
    if resolved, do: "#{text} (#{resolved})", else: text
  end

  def full_event_summary(event, state) do
    compact_event_summary(event, state)
  end

  @doc """
  Extra detail for the event log index tooltip when the compact one-line label hides information.
  Returns `nil` when there is nothing useful to add.
  """
  def event_log_index_tooltip(%{type: :note} = event, _state) do
    detail = event.detail || %{}
    text = detail["text"] || event.description || ""

    if text != "" and String.length(text) > 60 do
      text
    else
      nil
    end
  end

  def event_log_index_tooltip(%{type: :entity_modify} = event, _state) do
    detail = event.detail || %{}

    lines =
      ~w(name kind color avatar fate_points refresh controller_id hidden)
      |> Enum.flat_map(fn key ->
        if Map.has_key?(detail, key) do
          case entity_modify_tooltip_line(key, detail[key]) do
            nil -> []
            line -> [line]
          end
        else
          []
        end
      end)

    lines =
      lines ++ entity_modify_table_position_lines(detail)

    case lines do
      [] -> nil
      _ -> Enum.join(lines, "\n")
    end
  end

  def event_log_index_tooltip(%{type: type} = event, _state)
      when type in [:scene_modify, :template_scene_modify, :active_scene_update] do
    detail = event.detail || %{}

    lines =
      [
        scene_modify_tooltip_line(detail, "name", "Name"),
        scene_modify_tooltip_line(detail, "description", "Description"),
        scene_modify_tooltip_line(detail, "gm_notes", "GM notes")
      ]
      |> Enum.reject(&is_nil/1)

    case lines do
      [] -> nil
      _ -> Enum.join(lines, "\n")
    end
  end

  def event_log_index_tooltip(%{type: :stunt_add} = event, _state) do
    detail = event.detail || %{}
    effect = detail["effect"]

    if is_binary(effect) and String.trim(effect) != "" do
      "Effect: #{effect}"
    else
      nil
    end
  end

  def event_log_index_tooltip(%{type: :entity_create} = event, _state) do
    entity_detail_tooltip(event.detail || %{})
  end

  def event_log_index_tooltip(%{type: :entity_restore} = event, state) do
    entity_id = event.target_id || (event.detail || %{})["entity_id"]
    entity = Map.get(state.removed_entities, entity_id) || Map.get(state.entities, entity_id)

    if entity do
      entity_state_tooltip(entity)
    else
      entity_detail_tooltip(event.detail || %{})
    end
  end

  def event_log_index_tooltip(%{type: :entity_remove} = event, state) do
    detail = event.detail || %{}
    name = entity_label(state, event.target_id) || detail_label(detail["kind"], detail["name"])
    if name, do: name, else: nil
  end

  def event_log_index_tooltip(%{type: :aspect_create} = event, _state) do
    detail = event.detail || %{}
    desc = detail["description"]
    role = detail["role"]

    lines =
      (if(desc, do: ["Description: #{desc}"], else: []) ++
         if(role && role != "additional", do: ["Role: #{role}"], else: []))

    case lines do
      [] -> nil
      _ -> Enum.join(lines, "\n")
    end
  end

  def event_log_index_tooltip(_event, _state), do: nil

  defp entity_detail_tooltip(detail) do
    lines =
      if(detail["name"], do: ["Name: #{detail["name"]}"], else: []) ++
        if(detail["kind"], do: ["Kind: #{detail["kind"]}"], else: []) ++
        if(detail["controller_id"], do: ["Controller: #{detail["controller_id"]}"], else: []) ++
        if(detail["fate_points"], do: ["Fate points: #{detail["fate_points"]}"], else: []) ++
        if(detail["refresh"], do: ["Refresh: #{detail["refresh"]}"], else: [])

    aspects = detail["aspects"] || []

    aspect_lines =
      Enum.map(aspects, fn a ->
        role = if a["role"] && a["role"] != "additional", do: "(#{a["role"]}) ", else: ""
        "  #{role}#{a["description"]}"
      end)

    lines = if aspect_lines != [], do: lines ++ ["Aspects:"] ++ aspect_lines, else: lines

    case lines do
      [] -> nil
      _ -> Enum.join(lines, "\n")
    end
  end

  defp entity_state_tooltip(entity) do
    lines =
      if(entity.name, do: ["Name: #{entity.name}"], else: []) ++
        if(entity.kind, do: ["Kind: #{entity.kind}"], else: []) ++
        if(entity.controller_id, do: ["Controller: #{entity.controller_id}"], else: []) ++
        if(entity.fate_points, do: ["Fate points: #{entity.fate_points}"], else: []) ++
        if(entity.refresh, do: ["Refresh: #{entity.refresh}"], else: [])

    aspect_lines =
      Enum.map(entity.aspects, fn a ->
        role = if a.role not in [:additional, nil], do: "(#{a.role}) ", else: ""
        "  #{role}#{a.description}"
      end)

    lines = if aspect_lines != [], do: lines ++ ["Aspects:"] ++ aspect_lines, else: lines

    case lines do
      [] -> nil
      _ -> Enum.join(lines, "\n")
    end
  end

  defp entity_modify_tooltip_line("name", v) when is_binary(v), do: "Name: #{v}"

  defp entity_modify_tooltip_line("kind", v) when not is_nil(v),
    do: "Kind: #{format_kind_for_tooltip(v)}"

  defp entity_modify_tooltip_line("color", v) when is_binary(v) and v != "", do: "Color: #{v}"

  defp entity_modify_tooltip_line("avatar", v) when is_binary(v) and v != "",
    do: "Avatar: #{avatar_tooltip_snippet(v)}"

  defp entity_modify_tooltip_line("fate_points", v) when not is_nil(v), do: "Fate points: #{v}"
  defp entity_modify_tooltip_line("refresh", v) when not is_nil(v), do: "Refresh: #{v}"

  defp entity_modify_tooltip_line("controller_id", v) when is_binary(v) and v != "",
    do: "Controller: #{v}"

  defp entity_modify_tooltip_line("hidden", v) when v in [true, false], do: "Hidden: #{v}"
  defp entity_modify_tooltip_line(_, _), do: nil

  defp entity_modify_table_position_lines(detail) do
    if Map.has_key?(detail, "table_x") || Map.has_key?(detail, "table_y") do
      x = Map.get(detail, "table_x")
      y = Map.get(detail, "table_y")
      ["Table position: (#{x || "?"}, #{y || "?"})"]
    else
      []
    end
  end

  defp format_kind_for_tooltip(k) when is_atom(k), do: Atom.to_string(k)
  defp format_kind_for_tooltip(k), do: to_string(k)

  defp avatar_tooltip_snippet(url) do
    if String.length(url) > 80, do: String.slice(url, 0, 77) <> "...", else: url
  end

  defp scene_modify_tooltip_line(detail, key, label) do
    if Map.has_key?(detail, key) do
      case detail[key] do
        v when is_binary(v) ->
          if String.trim(v) != "", do: "#{label}: #{v}", else: nil

        _ ->
          nil
      end
    else
      nil
    end
  end

  # --- Name resolution ---

  def entity_name(nil, _), do: nil
  def entity_name(_, nil), do: nil

  def entity_name(state, id) do
    case Map.get(state.entities, id) do
      nil -> nil
      entity -> entity.name
    end
  end

  defp entity_label(state, id) do
    case Map.get(state.entities, id) do
      nil ->
        case Map.get(state.removed_entities, id) do
          nil -> nil
          %{name: name, kind: kind} -> "#{kind_word(kind)} #{name}"
        end

      entity ->
        "#{kind_word(entity.kind)} #{entity.name}"
    end
  end

  defp kind_word(:pc), do: "PC"
  defp kind_word(:npc), do: "NPC"
  defp kind_word(:vehicle), do: "vehicle"
  defp kind_word(:mook), do: "mook"
  defp kind_word(other) when is_atom(other), do: to_string(other)
  defp kind_word(_), do: "entity"

  defp detail_label(nil, nil), do: nil
  defp detail_label(nil, name), do: name
  defp detail_label(kind, nil), do: kind
  defp detail_label(kind, name), do: "#{kind} #{name}"

  def zone_name(nil, _), do: nil
  def zone_name(_, nil), do: nil

  def zone_name(state, zone_id) do
    all_zones(state)
    |> Enum.find(&(&1.id == zone_id))
    |> case do
      nil -> nil
      zone -> zone.name
    end
  end

  def target_name(nil, _, _), do: nil
  def target_name(_, nil, _), do: nil

  def target_name(state, id, target_type) do
    case target_type do
      "scene" ->
        case find_scene(state, id) do
          nil -> "scene"
          scene -> "scene #{scene.name}"
        end

      "zone" ->
        all_zones(state)
        |> Enum.find(&(&1.id == id))
        |> case do
          nil -> "zone"
          zone -> "zone #{zone.name}"
        end

      _ ->
        entity_name(state, id)
    end
  end

  # --- Formatting ---

  def entity_color(nil, _), do: "#6b7280"
  def entity_color(_state, nil), do: "#6b7280"

  def entity_color(state, entity_id) do
    case Map.get(state.entities, entity_id) do
      nil -> "#6b7280"
      entity -> entity.color || "#6b7280"
    end
  end

  def format_dice([]), do: "—"

  def format_dice(dice) do
    dice
    |> Enum.map(fn
      1 -> "+"
      -1 -> "−"
      0 -> "○"
      _ -> "?"
    end)
    |> Enum.join("")
  end

  # --- Modal system ---

  def action_modal(%{modal: nil} = assigns), do: ~H""

  def action_modal(assigns) do
    assigns = assign_new(assigns, :modal_context_state, fn -> nil end)
    editing? = assigns.form_data["event_id"] != nil

    modal_state =
      if editing? do
        assigns[:modal_context_state] || assigns.state
      else
        assigns.state
      end

    entities = if modal_state, do: Map.values(modal_state.entities), else: []

    assigns =
      assigns
      |> assign(:entities, entities)
      |> assign(:editing?, editing?)
      |> assign(:modal_state, modal_state)
      |> assign_new(:mention_catalog_json, fn -> Engine.mention_catalog_json(nil) end)

    ~H"""
    <.modal_frame variant={:panel}>
      <:title>
        {if(@editing?, do: edit_modal_title(@modal), else: modal_title(@modal))}
      </:title>
      <form phx-submit="submit_modal" phx-change="modal_form_changed" class="space-y-3">
        <input :if={@editing?} type="hidden" name="event_id" value={@form_data["event_id"]} />
        <.modal_fields
          modal={@modal}
          entities={@entities}
          state={@modal_state}
          prefill_entity_id={@prefill_entity_id}
          form_data={@form_data}
          participants={@participants}
          mention_catalog_json={@mention_catalog_json}
        />
        <.modal_frame_actions primary_label="Confirm" close_event="close_modal" />
      </form>
    </.modal_frame>
    """
  end

  def modal_title("aspect_create"), do: "Create Aspect"
  def modal_title("aspect_compel"), do: "Compel Aspect"
  def modal_title("entity_move"), do: "Move Entity"
  def modal_title("scene_start"), do: "Start Scene"
  def modal_title("scene_end"), do: "End Scene"
  def modal_title("fate_point_spend"), do: "Spend Fate Point"
  def modal_title("fate_point_earn"), do: "Earn Fate Point"
  def modal_title("fate_point_refresh"), do: "Refresh Fate Points"
  def modal_title("entity_create"), do: "Create Entity"
  def modal_title("entity_edit"), do: "Edit Entity"
  def modal_title("skill_set"), do: "Set Skill"
  def modal_title("stunt_add"), do: "Add Stunt"
  def modal_title("stunt_remove"), do: "Remove Stunt"
  def modal_title("set_system"), do: "Set System"
  def modal_title("scene_modify"), do: "Edit Scene"
  def modal_title("fork_bookmark"), do: "Create Bookmark"
  def modal_title("note"), do: "Make a Note"
  def modal_title("edit_note"), do: "Edit Note"
  def modal_title(other), do: other

  def edit_modal_title("aspect_create"), do: "Edit Aspect"
  def edit_modal_title("entity_create"), do: "Edit Entity Creation"
  def edit_modal_title("scene_start"), do: "Edit Scene Start"
  def edit_modal_title("stunt_add"), do: "Edit Stunt"
  def edit_modal_title("stunt_remove"), do: "Edit Stunt Removal"
  def edit_modal_title("skill_set"), do: "Edit Skill"
  def edit_modal_title("note"), do: "Edit Note"
  def edit_modal_title("fate_point_spend"), do: "Edit Fate Point Spend"
  def edit_modal_title("fate_point_earn"), do: "Edit Fate Point Earn"
  def edit_modal_title("fate_point_refresh"), do: "Edit Fate Point Refresh"
  def edit_modal_title(modal), do: modal_title(modal)

  # --- Modal fields ---

  def modal_fields(%{modal: "aspect_create"} = assigns) do
    fd = assigns[:form_data] || %{}
    scenes = if assigns.state, do: all_scenes(assigns.state), else: []

    scene_and_zone_options =
      Enum.flat_map(scenes, fn scene ->
        [{"scene:#{scene.id}", "Scene: #{scene.name}"}] ++
          Enum.map(scene.zones, fn z -> {"zone:#{z.id}", "Zone: #{z.name}"} end)
      end)

    entity_options =
      Enum.map(assigns.entities, fn e -> {"entity:#{e.id}", "#{e.name} (#{e.kind})"} end)

    all_options = scene_and_zone_options ++ entity_options

    prefill =
      fd["target_ref"] ||
        if(assigns.prefill_entity_id, do: "entity:#{assigns.prefill_entity_id}", else: nil)

    assigns =
      assigns
      |> assign(:all_options, all_options)
      |> assign(:prefill, prefill)
      |> assign(:fd, fd)
      |> assign(:target_select_size, min(length(all_options), 8))

    ~H"""
    <.aspect_form_fields
      target_options={@all_options}
      selected_target_ref={@prefill || ""}
      target_select_size={@target_select_size}
      description_value={@fd["description"] || ""}
      description_label="Aspect Text"
      description_placeholder="e.g. On Fire! or Flanking Position"
      description_required={true}
      role_selected={@fd["role"] || "situation"}
      show_hidden_checkbox={true}
      hidden_checked={@fd["hidden"] == "true"}
    />
    """
  end

  def modal_fields(%{modal: "entity_create"} = assigns) do
    fd = assigns[:form_data] || %{}

    parent_options =
      if assigns.state do
        assigns.state.entities
        |> Map.values()
        |> Enum.sort_by(& &1.name)
        |> Enum.map(fn e -> {e.id, "#{e.name} (#{e.kind})"} end)
      else
        []
      end

    controller_options =
      assigns[:participants]
      |> Enum.map(fn bp -> {bp.participant_id, "#{bp.participant.name} (#{bp.role})"} end)

    assigns =
      assigns
      |> assign(:parent_options, parent_options)
      |> assign(:controller_options, controller_options)
      |> assign(:fd, fd)

    ~H"""
    <input :if={@fd["entity_id"]} type="hidden" name="entity_id" value={@fd["entity_id"]} />
    <.text_input
      name="name"
      label="Name"
      placeholder="Character name"
      required={true}
      value={@fd["name"]}
    />
    <.select_input
      name="kind"
      label="Kind"
      selected={@fd["kind"]}
      options={[
        {"pc", "PC"},
        {"npc", "NPC"},
        {"mook_group", "Mook Group"},
        {"organization", "Organization"},
        {"vehicle", "Vehicle"},
        {"item", "Item"},
        {"hazard", "Hazard"},
        {"custom", "Custom"}
      ]}
    />
    <div>
      <label class="block text-sm text-amber-200/70 mb-1">Controller (optional)</label>
      <select
        name="controller_id"
        class="w-full px-3 py-2 bg-amber-900/30 border border-amber-700/30 rounded-lg text-amber-100 text-sm"
      >
        <option value="">None (GM-controlled)</option>
        <%= for {id, label} <- @controller_options do %>
          <option value={id} selected={id == @fd["controller_id"]}>{label}</option>
        <% end %>
      </select>
    </div>
    <.text_input name="fate_points" label="Fate Points" placeholder="3" value={@fd["fate_points"]} />
    <.text_input name="refresh" label="Refresh" placeholder="3" value={@fd["refresh"]} />
    <div>
      <label class="block text-sm text-amber-200/70 mb-1">Parent Entity (optional)</label>
      <select
        name="parent_entity_id"
        class="w-full px-3 py-2 bg-amber-900/30 border border-amber-700/30 rounded-lg text-amber-100 text-sm"
      >
        <option value="">None</option>
        <%= for {id, label} <- @parent_options do %>
          <option value={id} selected={id == (@fd["parent_entity_id"] || @prefill_entity_id)}>
            {label}
          </option>
        <% end %>
      </select>
    </div>
    <.text_input
      name="high_concept"
      label="High Concept"
      placeholder="Infamous Girl with a Sword"
      value={@fd["high_concept"]}
    />
    <.text_input
      name="trouble"
      label="Trouble"
      placeholder="Tempted by Shiny Things"
      value={@fd["trouble"]}
    />
    <div>
      <label class="block text-sm text-amber-200/70 mb-1">Additional aspects</label>
      <textarea
        name="additional_aspects"
        placeholder="One per line — plain text becomes an extra aspect\nOptional: role|description (e.g. additional|Rivals in the Underworld)"
        class="w-full px-3 py-2 bg-amber-900/30 border border-amber-700/30 rounded-lg text-amber-100 text-sm placeholder-amber-200/20"
        rows="4"
      >{@fd["additional_aspects"]}</textarea>
      <p class="text-xs text-amber-200/40 mt-1">
        Lines without a role default to “additional”. Use known roles (e.g. situation, consequence) only if you mean them.
      </p>
    </div>
    """
  end

  def modal_fields(%{modal: "scene_start"} = assigns) do
    fd = assigns[:form_data] || %{}
    mcj = mention_catalog_json(assigns)

    assigns =
      assigns
      |> assign(:fd, fd)
      |> assign(:mcj, mcj)

    ~H"""
    <.scene_start_fields
      scene_id={@fd["scene_id"]}
      name_value={@fd["name"] || ""}
      scene_description_value={@fd["scene_description"] || ""}
      gm_notes_value={@fd["gm_notes"] || ""}
      name_required={true}
      mention_catalog_json={@mcj}
    />
    """
  end

  def modal_fields(%{modal: "scene_end"} = assigns) do
    active = assigns.state && assigns.state.active_scene
    assigns = assign(assigns, :active, active)

    ~H"""
    <%= if @active do %>
      <p class="text-sm text-amber-200/70">
        End the current scene: <strong class="text-amber-100">{@active.name}</strong>
      </p>
      <p class="text-xs text-amber-200/40">This will clear all stress and remove boosts.</p>
    <% else %>
      <p class="text-sm text-red-300">No active scene to end.</p>
    <% end %>
    """
  end

  def modal_fields(%{modal: modal} = assigns)
      when modal in ~w(fate_point_spend fate_point_earn fate_point_refresh) do
    ~H"""
    <.entity_select
      name="entity_id"
      label="Entity"
      entities={@entities}
      selected={@prefill_entity_id}
    />
    """
  end

  def modal_fields(%{modal: "entity_move"} = assigns) do
    fd = assigns[:form_data] || %{}

    zones =
      if assigns.state && assigns.state.active_scene do
        assigns.state.active_scene.zones
      else
        []
      end

    assigns =
      assigns
      |> assign(:zones, zones)
      |> assign(:fd, fd)

    ~H"""
    <.entity_select
      name="entity_id"
      label="Entity"
      entities={@entities}
      selected={@prefill_entity_id}
    />
    <div>
      <label class="block text-sm text-amber-200/70 mb-1">To Zone</label>
      <%= if @zones == [] do %>
        <p class="text-sm text-amber-200/40 italic">
          No zones available — create a scene with zones first
        </p>
      <% else %>
        <select
          name="zone_id"
          class="w-full px-3 py-2 bg-amber-900/30 border border-amber-700/30 rounded-lg text-amber-100 text-sm"
        >
          <%= for zone <- @zones do %>
            <option value={zone.id} selected={zone.id == @fd["zone_id"]}>{zone.name}</option>
          <% end %>
        </select>
      <% end %>
    </div>
    """
  end

  def modal_fields(%{modal: "aspect_compel"} = assigns) do
    fd = assigns[:form_data] || %{}

    aspects =
      if assigns.state do
        assigns.state.entities
        |> Map.values()
        |> Enum.flat_map(fn e ->
          Enum.map(e.aspects, fn a ->
            {a.id, "#{e.name}: #{a.description}"}
          end)
        end)
      else
        []
      end

    assigns =
      assigns
      |> assign(:aspects, aspects)
      |> assign(:fd, fd)

    ~H"""
    <div>
      <label class="block text-sm text-amber-200/70 mb-1">Compelling Entity (GM/NPC)</label>
      <select
        name="actor_id"
        class="w-full px-3 py-2 bg-amber-900/30 border border-amber-700/30 rounded-lg text-amber-100 text-sm"
      >
        <option value="" selected={@fd["actor_id"] in [nil, ""]}>GM</option>
        <%= for entity <- @entities do %>
          <option value={entity.id} selected={entity.id == @fd["actor_id"]}>
            {entity.name} ({entity.kind})
          </option>
        <% end %>
      </select>
    </div>
    <.entity_select
      name="target_id"
      label="Target Entity"
      entities={@entities}
      selected={@fd["target_id"] || @prefill_entity_id}
    />
    <div>
      <label class="block text-sm text-amber-200/70 mb-1">Aspect</label>
      <select
        name="aspect_id"
        required
        class="w-full px-3 py-2 bg-amber-900/30 border border-amber-700/30 rounded-lg text-amber-100 text-sm"
      >
        <option value="">Select aspect...</option>
        <%= for {id, label} <- @aspects do %>
          <option value={id} selected={id == @fd["aspect_id"]}>{label}</option>
        <% end %>
      </select>
    </div>
    <.text_input
      name="description"
      label="Compel Description"
      placeholder="What complication does this cause?"
      value={@fd["description"]}
    />
    <div class="flex items-center gap-2">
      <input type="hidden" name="accepted" value="false" />
      <input
        type="checkbox"
        name="accepted"
        value="true"
        checked={@fd["accepted"] != "false"}
        class="rounded bg-amber-900/30 border-amber-700/30 text-amber-600"
      />
      <label class="text-sm text-amber-200/70">Accepted</label>
    </div>
    """
  end

  def modal_fields(%{modal: "entity_edit"} = assigns) do
    fd = assigns[:form_data] || %{}
    editing? = fd["event_id"] != nil

    entity =
      if assigns.prefill_entity_id && assigns.state do
        Map.get(assigns.state.entities, assigns.prefill_entity_id)
      end

    controller_options =
      assigns[:participants]
      |> Enum.map(fn bp -> {bp.participant_id, "#{bp.participant.name} (#{bp.role})"} end)

    assigns =
      assigns
      |> assign(:entity, entity)
      |> assign(:e_name, if(editing?, do: fd["name"], else: if(entity, do: entity.name)))
      |> assign(
        :e_kind,
        if(editing?, do: fd["kind"], else: if(entity, do: to_string(entity.kind)))
      )
      |> assign(
        :e_controller,
        if(editing?, do: fd["controller_id"], else: if(entity, do: entity.controller_id))
      )
      |> assign(
        :e_fp,
        if(editing?,
          do: fd["fate_points"],
          else: if(entity && entity.fate_points, do: to_string(entity.fate_points))
        )
      )
      |> assign(
        :e_refresh,
        if(editing?,
          do: fd["refresh"],
          else: if(entity && entity.refresh, do: to_string(entity.refresh))
        )
      )
      |> assign(:controller_options, controller_options)
      |> assign(:changed_fields, if(editing?, do: fd["changed_fields"]))

    ~H"""
    <.entity_select
      name="entity_id"
      label="Entity"
      entities={@entities}
      selected={@prefill_entity_id}
    />
    <.entity_edit_fields
      e_name={@e_name || ""}
      e_kind={@e_kind || ""}
      e_controller={@e_controller}
      e_fp={@e_fp || ""}
      e_refresh={@e_refresh || ""}
      controller_options={@controller_options}
      changed_fields={@changed_fields}
    />
    """
  end

  def modal_fields(%{modal: "skill_set"} = assigns) do
    fd = assigns[:form_data] || %{}
    skill_list = if assigns.state, do: assigns.state.skill_list, else: []

    assigns =
      assigns
      |> assign(:skill_list, skill_list)
      |> assign(:fd, fd)

    ~H"""
    <.entity_select
      name="entity_id"
      label="Entity"
      entities={@entities}
      selected={@prefill_entity_id}
    />
    <div>
      <label class="block text-sm text-amber-200/70 mb-1">Skill</label>
      <%= if @skill_list == [] do %>
        <p class="text-sm text-amber-200/40 italic">No skills defined — set a system first</p>
      <% else %>
        <select
          name="skill"
          class="w-full px-3 py-2 bg-amber-900/30 border border-amber-700/30 rounded-lg text-amber-100 text-sm"
        >
          <%= for skill <- @skill_list do %>
            <option value={skill} selected={skill == @fd["skill"]}>{skill}</option>
          <% end %>
        </select>
      <% end %>
    </div>
    <.text_input name="rating" label="Rating" placeholder="2" value={@fd["rating"]} />
    """
  end

  def modal_fields(%{modal: "stunt_add"} = assigns) do
    fd = assigns[:form_data] || %{}
    assigns = assign(assigns, :fd, fd)

    ~H"""
    <input :if={@fd["stunt_id"]} type="hidden" name="stunt_id" value={@fd["stunt_id"]} />
    <.entity_select
      name="entity_id"
      label="Entity"
      entities={@entities}
      selected={@prefill_entity_id}
    />
    <.stunt_add_fields
      name_field="name"
      effect_field="effect"
      name_value={@fd["name"]}
      effect_value={@fd["effect"]}
    />
    """
  end

  def modal_fields(%{modal: "stunt_remove"} = assigns) do
    fd = assigns[:form_data] || %{}

    entity =
      if assigns.prefill_entity_id && assigns.state,
        do: Map.get(assigns.state.entities, assigns.prefill_entity_id),
        else: nil

    stunts =
      if entity do
        Enum.map(entity.stunts, fn s -> {s.id, s.name} end)
      else
        if assigns.state do
          assigns.state.entities
          |> Map.values()
          |> Enum.flat_map(fn e ->
            Enum.map(e.stunts, fn s -> {s.id, "#{e.name}: #{s.name}"} end)
          end)
        else
          []
        end
      end

    assigns =
      assigns
      |> assign(:stunts, stunts)
      |> assign(:fd, fd)

    ~H"""
    <.entity_select
      name="entity_id"
      label="Entity"
      entities={@entities}
      selected={@prefill_entity_id}
    />
    <div>
      <label class="block text-sm text-amber-200/70 mb-1">Stunt</label>
      <select
        name="stunt_id"
        class="w-full px-3 py-2 bg-amber-900/30 border border-amber-700/30 rounded-lg text-amber-100 text-sm"
      >
        <option value="">Select stunt...</option>
        <%= for {id, label} <- @stunts do %>
          <option value={id} selected={id == @fd["stunt_id"]}>{label}</option>
        <% end %>
      </select>
    </div>
    """
  end

  def modal_fields(%{modal: "set_system"} = assigns) do
    fd = assigns[:form_data] || %{}
    assigns = assign(assigns, :fd, fd)

    ~H"""
    <.select_input
      name="system"
      label="System"
      selected={@fd["system"]}
      options={[
        {"core", "Fate Core"},
        {"accelerated", "Fate Accelerated (FAE)"}
      ]}
    />
    """
  end

  def modal_fields(%{modal: "scene_modify"} = assigns) do
    fd = assigns[:form_data] || %{}
    editing? = fd["event_id"] != nil

    scenes =
      cond do
        editing? && assigns.state ->
          all_scenes(assigns.state)

        assigns.state && assigns.state.active_scene ->
          [assigns.state.active_scene]

        true ->
          []
      end

    first_scene = List.first(scenes)

    mcj = mention_catalog_json(assigns)

    assigns =
      assigns
      |> assign(:scenes, scenes)
      |> assign(
        :s_name,
        if(editing?, do: fd["name"], else: if(first_scene, do: first_scene.name))
      )
      |> assign(
        :s_desc,
        if(editing?,
          do: fd["scene_description"],
          else: if(first_scene, do: first_scene.description)
        )
      )
      |> assign(
        :s_notes,
        if(editing?, do: fd["gm_notes"], else: if(first_scene, do: first_scene.gm_notes))
      )
      |> assign(:fd, fd)
      |> assign(:mcj, mcj)

    ~H"""
    <div>
      <label class="block text-sm text-amber-200/70 mb-1">Scene</label>
      <select
        name="scene_id"
        class="w-full px-3 py-2 bg-amber-900/30 border border-amber-700/30 rounded-lg text-amber-100 text-sm"
      >
        <%= for scene <- @scenes do %>
          <option value={scene.id} selected={scene.id == @fd["scene_id"]}>{scene.name}</option>
        <% end %>
      </select>
    </div>
    <.text_input name="name" label="Name" value={@s_name} placeholder="Scene name" />
    <div>
      <label class="block text-sm text-amber-200/70 mb-1">Description</label>
      <textarea
        id="panel-scene-description-edit"
        name="scene_description"
        placeholder="Scene description"
        phx-hook="MentionTypeahead"
        data-mention-catalog={@mcj}
        class="w-full px-3 py-2 bg-amber-900/30 border border-amber-700/30 rounded-lg text-amber-100 text-sm placeholder-amber-200/20"
        rows="3"
      >{@s_desc}</textarea>
    </div>
    <div>
      <label class="block text-sm text-amber-200/70 mb-1">GM Notes</label>
      <textarea
        id="panel-gm-notes-edit"
        name="gm_notes"
        placeholder="Private prep notes..."
        phx-hook="MentionTypeahead"
        data-mention-catalog={@mcj}
        class="w-full px-3 py-2 bg-amber-900/30 border border-amber-700/30 rounded-lg text-amber-100 text-sm placeholder-amber-200/20"
        rows="3"
      >{@s_notes}</textarea>
    </div>
    """
  end

  def modal_fields(%{modal: "fork_bookmark"} = assigns) do
    ~H"""
    <.text_input name="name" label="Bookmark Name" placeholder="My Fork" />
    """
  end

  def modal_fields(%{modal: modal} = assigns) when modal in ~w(note edit_note) do
    fd = assigns[:form_data] || %{}
    all_options = note_target_options(assigns.state)
    mcj = mention_catalog_json(assigns)

    prefill_ref =
      fd["target_ref"] ||
        if(assigns.prefill_entity_id, do: "entity:#{assigns.prefill_entity_id}", else: "")

    assigns =
      assigns
      |> assign(:all_options, all_options)
      |> assign(:note_text, fd["text"] || "")
      |> assign(:note_target_ref, prefill_ref)
      |> assign(:mcj, mcj)

    ~H"""
    <.note_form_fields
      all_options={@all_options}
      text={@note_text}
      target_ref={@note_target_ref}
      mention_catalog_json={@mcj}
    />
    """
  end

  def modal_fields(assigns) do
    ~H"""
    <p class="text-sm text-amber-200/50">No fields configured for this action type.</p>
    """
  end

  # --- Note helpers ---

  defp note_target_options(nil), do: []

  defp note_target_options(state) do
    scene_opts =
      Enum.flat_map(all_scenes(state), fn scene ->
        [{"scene:#{scene.id}", "Scene: #{scene.name}"}] ++
          Enum.map(scene.zones, fn z -> {"zone:#{z.id}", "Zone: #{z.name}"} end)
      end)

    entity_opts =
      state.entities
      |> Map.values()
      |> Enum.map(fn e -> {"entity:#{e.id}", "#{e.name} (#{e.kind})"} end)

    scene_opts ++ entity_opts
  end

  # --- Scene helpers ---

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

  # --- Form input components ---

  def entity_select(assigns) do
    assigns = assign_new(assigns, :selected, fn -> nil end)

    ~H"""
    <div>
      <label class="block text-sm text-amber-200/70 mb-1">{@label}</label>
      <%= if @entities == [] do %>
        <p class="text-sm text-amber-200/40 italic">No entities available</p>
      <% else %>
        <select
          name={@name}
          class="w-full px-3 py-2 bg-amber-900/30 border border-amber-700/30 rounded-lg text-amber-100 text-sm"
        >
          <option value="">Select...</option>
          <%= for entity <- @entities do %>
            <option value={entity.id} selected={entity.id == @selected}>
              {entity.name} ({entity.kind})
            </option>
          <% end %>
        </select>
      <% end %>
    </div>
    """
  end

  def text_input(assigns) do
    assigns =
      assigns
      |> assign_new(:placeholder, fn -> "" end)
      |> assign_new(:value, fn -> nil end)
      |> assign_new(:required, fn -> false end)

    ~H"""
    <div>
      <label class="block text-sm text-amber-200/70 mb-1">{@label}</label>
      <input
        type="text"
        name={@name}
        value={@value}
        placeholder={@placeholder}
        required={@required}
        class="w-full px-3 py-2 bg-amber-900/30 border border-amber-700/30 rounded-lg text-amber-100 text-sm placeholder-amber-200/20"
      />
    </div>
    """
  end

  def select_input(assigns) do
    assigns = assign_new(assigns, :selected, fn -> nil end)

    ~H"""
    <div>
      <label class="block text-sm text-amber-200/70 mb-1">{@label}</label>
      <select
        name={@name}
        class="w-full px-3 py-2 bg-amber-900/30 border border-amber-700/30 rounded-lg text-amber-100 text-sm"
      >
        <%= for {value, label} <- @options do %>
          <option value={value} selected={value == @selected}>{label}</option>
        <% end %>
      </select>
    </div>
    """
  end
end
