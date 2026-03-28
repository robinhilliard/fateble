defmodule FateWeb.ActionComponents do
  use FateWeb, :html

  @event_type_labels %{
    create_campaign: "Create Campaign",
    set_system: "Set System",
    scene_start: "Scene Start",
    scene_end: "Scene End",
    zone_create: "Create Zone",
    entity_enter_scene: "Enter Scene",
    entity_move: "Move",
    entity_create: "Create Entity",
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

  # --- Event log ---

  def event_row(assigns) do
    color = entity_color(assigns.state, assigns.event.actor_id)
    summary = compact_event_summary(assigns.event, assigns.state)
    draggable = assigns[:is_gm] && !assigns[:immutable] && !assigns[:is_observer]

    assigns =
      assigns
      |> assign(:color, color)
      |> assign(:summary, summary)
      |> assign(:draggable, draggable)
      |> assign_new(:immutable, fn -> false end)
      |> assign_new(:is_observer, fn -> false end)
      |> assign_new(:is_gm, fn -> false end)
      |> assign_new(:invalid, fn -> false end)

    ~H"""
    <div
      id={"event-#{@index}"}
      class={[
        "group flex items-center gap-2 px-2 py-1 rounded transition text-sm event-row",
        if(@event.exchange_id, do: "ml-4 border-l-2 border-amber-700/20", else: ""),
        if(@immutable, do: "opacity-30", else: "hover:bg-amber-900/20"),
        @draggable && "cursor-grab"
      ]}
      draggable={if(@draggable, do: "true", else: "false")}
      data-event-id={@event.id}
      data-event-index={@index}
    >
      <%= if @invalid do %>
        <span
          class="text-amber-500 shrink-0"
          data-tooltip="This event had no effect — its target is missing at this point in the timeline"
        >
          <.icon name="hero-exclamation-triangle" class="w-3.5 h-3.5" />
        </span>
      <% else %>
        <div
          class="w-2 h-2 rounded-full shrink-0"
          style={"background: #{@color};"}
        />
      <% end %>
      <span class="text-amber-200/40 text-xs shrink-0">{@index + 1}</span>
      <span class="flex-1 text-amber-100/80 truncate" style="font-family: 'Patrick Hand', cursive;">
        {@summary}
      </span>
      <%= if editable_type?(@event.type) && !@immutable && !@is_observer do %>
        <button
          phx-click="edit_event"
          phx-value-id={@event.id}
          class="opacity-0 group-hover:opacity-100 text-amber-400/50 hover:text-amber-300 text-xs transition shrink-0"
        >
          <.icon name="hero-pencil-square" class="w-3.5 h-3.5" />
        </button>
      <% end %>
      <%= if !@immutable && !@is_observer do %>
        <button
          phx-click="delete_event"
          phx-value-id={@event.id}
          class="opacity-0 group-hover:opacity-100 text-red-400/50 hover:text-red-400 text-xs transition shrink-0"
          data-confirm="Delete this event?"
        >
          ✕
        </button>
      <% end %>
    </div>
    """
  end

  def compact_event_summary(%{type: :create_campaign} = event, _state) do
    detail = event.detail || %{}
    "Campaign: #{detail["campaign_name"] || event.description}"
  end

  def compact_event_summary(%{type: :set_system} = event, _state) do
    detail = event.detail || %{}
    "System: #{detail["system"] || "core"}"
  end

  def compact_event_summary(%{type: :entity_create} = event, _state) do
    detail = event.detail || %{}
    "New #{detail["kind"] || "entity"}: #{detail["name"]}"
  end

  def compact_event_summary(%{type: :entity_modify} = event, state) do
    detail = event.detail || %{}
    target = entity_name(state, event.target_id)
    "Edit #{target || detail["name"] || "entity"}"
  end

  def compact_event_summary(%{type: :entity_remove} = event, state) do
    "Remove #{entity_name(state, event.target_id)}"
  end

  def compact_event_summary(%{type: :aspect_create} = event, state) do
    detail = event.detail || %{}
    target = entity_name(state, event.target_id)
    resolved = target || target_name(state, event.target_id, detail["target_type"])
    "Add aspect \"#{detail["description"]}\"#{if resolved, do: " on #{resolved}"}"
  end

  def compact_event_summary(%{type: :aspect_remove} = event, state) do
    detail = event.detail || %{}
    target = entity_name(state, event.target_id)
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
    target = entity_name(state, event.target_id)
    "Compel #{target || "?"}: #{detail["description"] || ""}"
  end

  def compact_event_summary(%{type: :skill_set} = event, state) do
    detail = event.detail || %{}
    target = entity_name(state, event.target_id)
    rating = detail["rating"]

    skill_text =
      if rating == 0, do: "Remove #{detail["skill"]}", else: "#{detail["skill"]} → +#{rating}"

    "#{skill_text} — #{target}"
  end

  def compact_event_summary(%{type: :stunt_add} = event, state) do
    detail = event.detail || %{}
    "Stunt: #{detail["name"]} — #{entity_name(state, event.target_id)}"
  end

  def compact_event_summary(%{type: :stunt_remove} = event, state) do
    "Remove stunt — #{entity_name(state, event.target_id)}"
  end

  def compact_event_summary(%{type: :scene_start} = event, _state) do
    detail = event.detail || %{}
    "Scene: #{detail["name"]}"
  end

  def compact_event_summary(%{type: :scene_end} = event, _state) do
    event.description || "End scene"
  end

  def compact_event_summary(%{type: :scene_modify}, _state), do: "Edit scene"

  def compact_event_summary(%{type: :zone_create} = event, _state) do
    detail = event.detail || %{}
    "Zone: #{detail["name"]}"
  end

  def compact_event_summary(%{type: :zone_modify} = event, state) do
    detail = event.detail || %{}
    zone = zone_name(state, detail["zone_id"])
    "#{if detail["hidden"] == false, do: "Reveal", else: "Hide"} zone#{if zone, do: " #{zone}"}"
  end

  def compact_event_summary(%{type: :entity_enter_scene} = event, state) do
    detail = event.detail || %{}
    actor = entity_name(state, event.actor_id)
    zone = zone_name(state, detail["zone_id"])
    "#{actor} enters#{if zone, do: " #{zone}"}"
  end

  def compact_event_summary(%{type: :entity_move} = event, state) do
    detail = event.detail || %{}
    actor = entity_name(state, event.actor_id)
    zone = zone_name(state, detail["zone_id"])
    if zone, do: "#{actor} moves to #{zone}", else: "#{actor} leaves all zones"
  end

  def compact_event_summary(%{type: :roll_attack} = event, state) do
    detail = event.detail || %{}
    actor = entity_name(state, event.actor_id)

    "#{actor} attacks #{detail["skill"] || ""} #{format_dice(detail["fudge_dice"] || [])} = #{detail["raw_total"] || "?"}"
  end

  def compact_event_summary(%{type: :roll_defend} = event, state) do
    detail = event.detail || %{}
    actor = entity_name(state, event.actor_id)

    "#{actor} defends #{detail["skill"] || ""} #{format_dice(detail["fudge_dice"] || [])} = #{detail["raw_total"] || "?"}"
  end

  def compact_event_summary(%{type: :roll_overcome} = event, state) do
    detail = event.detail || %{}
    actor = entity_name(state, event.actor_id)
    "#{actor} overcomes #{detail["skill"] || ""} #{format_dice(detail["fudge_dice"] || [])}"
  end

  def compact_event_summary(%{type: :roll_create_advantage} = event, state) do
    detail = event.detail || %{}
    actor = entity_name(state, event.actor_id)

    "#{actor} creates advantage #{detail["skill"] || ""} #{format_dice(detail["fudge_dice"] || [])}"
  end

  def compact_event_summary(%{type: :invoke} = event, state) do
    detail = event.detail || %{}
    actor = entity_name(state, event.actor_id)
    "#{actor} invokes: #{detail["description"] || "aspect"}"
  end

  def compact_event_summary(%{type: :shifts_resolved} = event, state) do
    detail = event.detail || %{}
    target = entity_name(state, event.target_id)
    "#{detail["shifts"] || 0} shifts#{if target, do: " on #{target}"}"
  end

  def compact_event_summary(%{type: :redirect_hit} = event, state) do
    target = entity_name(state, event.target_id)
    "Redirect hit#{if target, do: " to #{target}"}"
  end

  def compact_event_summary(%{type: :stress_apply} = event, state) do
    detail = event.detail || %{}
    "#{entity_name(state, event.target_id)} stress ×#{detail["box_index"]}"
  end

  def compact_event_summary(%{type: :stress_clear} = event, state) do
    "#{entity_name(state, event.target_id)} clears stress"
  end

  def compact_event_summary(%{type: :consequence_take} = event, state) do
    detail = event.detail || %{}
    "#{entity_name(state, event.target_id)} takes #{detail["severity"]}: #{detail["aspect_text"]}"
  end

  def compact_event_summary(%{type: :consequence_recover} = event, state) do
    "#{entity_name(state, event.target_id)} recovers consequence"
  end

  def compact_event_summary(%{type: :fate_point_spend} = event, state) do
    "#{entity_name(state, event.target_id)} spends FP"
  end

  def compact_event_summary(%{type: :fate_point_earn} = event, state) do
    "#{entity_name(state, event.target_id)} earns FP"
  end

  def compact_event_summary(%{type: :fate_point_refresh} = event, state) do
    "#{entity_name(state, event.target_id)} refreshes FP"
  end

  def compact_event_summary(%{type: :concede} = event, state) do
    "#{entity_name(state, event.actor_id)} concedes"
  end

  def compact_event_summary(%{type: :taken_out} = event, state) do
    "#{entity_name(state, event.target_id) || entity_name(state, event.actor_id)} taken out!"
  end

  def compact_event_summary(%{type: :mook_eliminate} = event, state) do
    "#{entity_name(state, event.target_id)} mook eliminated"
  end

  def compact_event_summary(%{type: :note} = event, state) do
    detail = event.detail || %{}
    text = detail["text"] || event.description || ""
    target = entity_name(state, event.target_id)
    resolved = target || target_name(state, event.target_id, detail["target_type"])
    truncated = if String.length(text) > 60, do: String.slice(text, 0..57) <> "...", else: text
    if resolved, do: "#{truncated} (#{resolved})", else: truncated
  end

  def compact_event_summary(event, _state) do
    event.description || to_string(event.type)
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

  def zone_name(nil, _), do: nil
  def zone_name(_, nil), do: nil

  def zone_name(state, zone_id) do
    state.scenes
    |> Enum.flat_map(& &1.zones)
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
        case Enum.find(state.scenes, &(&1.id == id)) do
          nil -> "scene"
          scene -> "scene #{scene.name}"
        end

      "zone" ->
        state.scenes
        |> Enum.flat_map(& &1.zones)
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
    entities = if assigns.state, do: Map.values(assigns.state.entities), else: []
    editing? = assigns.form_data["event_id"] != nil

    assigns =
      assigns
      |> assign(:entities, entities)
      |> assign(:editing?, editing?)

    ~H"""
    <div class="fixed inset-0 z-50 flex items-center justify-center bg-black/60">
      <div class="bg-amber-950 border border-amber-700/40 rounded-xl p-6 w-96 shadow-2xl">
        <h3 class="text-lg font-bold mb-4" style="font-family: 'Permanent Marker', cursive;">
          {if(@editing?, do: edit_modal_title(@modal), else: modal_title(@modal))}
        </h3>

        <form phx-submit="submit_modal" phx-change="modal_form_changed" class="space-y-3">
          <input :if={@editing?} type="hidden" name="event_id" value={@form_data["event_id"]} />
          <.modal_fields
            modal={@modal}
            entities={@entities}
            state={@state}
            prefill_entity_id={@prefill_entity_id}
            form_data={@form_data}
            participants={@participants}
          />

          <div class="flex gap-2 pt-2">
            <button
              type="submit"
              class="flex-1 py-2 bg-green-800/60 border border-green-600/30 rounded-lg hover:bg-green-700/60 text-green-200 font-bold text-sm"
            >
              Confirm
            </button>
            <button
              type="button"
              phx-click="close_modal"
              class="flex-1 py-2 bg-red-900/40 border border-red-700/30 rounded-lg hover:bg-red-800/40 text-red-200 text-sm"
            >
              Cancel
            </button>
          </div>
        </form>
      </div>
    </div>
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
    all_scenes = if assigns.state, do: assigns.state.scenes, else: []

    scene_and_zone_options =
      Enum.flat_map(all_scenes, fn scene ->
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

    ~H"""
    <div>
      <label class="block text-sm text-amber-200/70 mb-1">On</label>
      <select
        name="target_ref"
        size={min(length(@all_options), 8)}
        class="w-full px-3 py-2 bg-amber-900/30 border border-amber-700/30 rounded-lg text-amber-100 text-sm"
      >
        <%= for {value, label} <- @all_options do %>
          <option value={value} selected={value == @prefill}>{label}</option>
        <% end %>
      </select>
    </div>
    <.text_input
      name="description"
      label="Aspect Text"
      placeholder="e.g. On Fire! or Flanking Position"
      required={true}
      value={@fd["description"]}
    />
    <.select_input
      name="role"
      label="Role"
      selected={@fd["role"]}
      options={[
        {"situation", "Situation"},
        {"boost", "Boost"},
        {"additional", "Additional"},
        {"high_concept", "High Concept"},
        {"trouble", "Trouble"}
      ]}
    />
    <label class="flex items-center gap-2 text-sm text-amber-200/70">
      <input
        type="checkbox"
        name="hidden"
        value="true"
        checked={@fd["hidden"] == "true"}
        class="rounded"
      /> Hidden from players
    </label>
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
    <div>
      <label class="block text-sm text-amber-200/70 mb-1">
        Aspects (one per line, optional role|text)
      </label>
      <textarea
        name="aspects"
        placeholder="high_concept|Infamous Girl with Sword\ntrouble|Tempted by Shiny Things\nRivals in the Underworld"
        class="w-full px-3 py-2 bg-amber-900/30 border border-amber-700/30 rounded-lg text-amber-100 text-sm placeholder-amber-200/20"
        rows="4"
      >{@fd["aspects"]}</textarea>
    </div>
    """
  end

  def modal_fields(%{modal: "scene_start"} = assigns) do
    fd = assigns[:form_data] || %{}
    assigns = assign(assigns, :fd, fd)

    ~H"""
    <input :if={@fd["scene_id"]} type="hidden" name="scene_id" value={@fd["scene_id"]} />
    <.text_input
      name="name"
      label="Scene Name"
      placeholder="Dockside Warehouse"
      required={true}
      value={@fd["name"]}
    />
    <.text_input
      name="scene_description"
      label="Description"
      placeholder="A brief framing of the scene"
      value={@fd["scene_description"]}
    />
    <div>
      <label class="block text-sm text-amber-200/70 mb-1">GM Notes</label>
      <textarea
        name="gm_notes"
        placeholder="Private prep notes..."
        class="w-full px-3 py-2 bg-amber-900/30 border border-amber-700/30 rounded-lg text-amber-100 text-sm placeholder-amber-200/20"
        rows="3"
      >{@fd["gm_notes"]}</textarea>
    </div>
    """
  end

  def modal_fields(%{modal: "scene_end"} = assigns) do
    active = assigns.state && assigns.state.scenes |> Enum.find(&(&1.status == :active))
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
      if assigns.state do
        assigns.state.scenes
        |> Enum.filter(&(&1.status == :active))
        |> Enum.flat_map(& &1.zones)
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

    ~H"""
    <.entity_select
      name="entity_id"
      label="Entity"
      entities={@entities}
      selected={@prefill_entity_id}
    />
    <.text_input name="name" label="Name" value={@e_name} placeholder="Name" />
    <.select_input
      name="kind"
      label="Kind"
      selected={@e_kind}
      options={[
        {"", "— no change —"},
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
      <label class="block text-sm text-amber-200/70 mb-1">Controller</label>
      <select
        name="controller_id"
        class="w-full px-3 py-2 bg-amber-900/30 border border-amber-700/30 rounded-lg text-amber-100 text-sm"
      >
        <option value="">None (GM-controlled)</option>
        <%= for {id, label} <- @controller_options do %>
          <option value={id} selected={id == @e_controller}>{label}</option>
        <% end %>
      </select>
    </div>
    <.text_input name="fate_points" label="Fate Points" value={@e_fp} placeholder="" />
    <.text_input name="refresh" label="Refresh" value={@e_refresh} placeholder="" />
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
    <.text_input name="name" label="Stunt Name" placeholder="Master Swordswoman" value={@fd["name"]} />
    <.text_input
      name="effect"
      label="Effect"
      placeholder="+2 to Fight when dueling one-on-one"
      value={@fd["effect"]}
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
      if assigns.state,
        do: Enum.filter(assigns.state.scenes, &(&1.status == :active)),
        else: []

    first_scene = List.first(scenes)

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
    <.text_input
      name="scene_description"
      label="Description"
      value={@s_desc}
      placeholder="Scene description"
    />
    <div>
      <label class="block text-sm text-amber-200/70 mb-1">GM Notes</label>
      <textarea
        name="gm_notes"
        placeholder="Private prep notes..."
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

    prefill_ref =
      fd["target_ref"] ||
        if(assigns.prefill_entity_id, do: "entity:#{assigns.prefill_entity_id}", else: "")

    assigns =
      assigns
      |> assign(:all_options, all_options)
      |> assign(:note_text, fd["text"] || "")
      |> assign(:note_target_ref, prefill_ref)

    ~H"""
    <.note_form_fields all_options={@all_options} text={@note_text} target_ref={@note_target_ref} />
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
    active_scene = Enum.find(state.scenes, &(&1.status == :active))

    scene_opts =
      if active_scene do
        [{"scene:#{active_scene.id}", "Scene: #{active_scene.name}"}] ++
          Enum.map(active_scene.zones, fn z -> {"zone:#{z.id}", "Zone: #{z.name}"} end)
      else
        []
      end

    entity_opts =
      state.entities
      |> Map.values()
      |> Enum.map(fn e -> {"entity:#{e.id}", "#{e.name} (#{e.kind})"} end)

    scene_opts ++ entity_opts
  end

  defp note_form_fields(assigns) do
    ~H"""
    <div>
      <label class="block text-sm text-amber-200/70 mb-1">Note</label>
      <textarea
        name="text"
        rows="4"
        required
        placeholder="What happened..."
        class="w-full px-3 py-2 bg-amber-900/30 border border-amber-700/30 rounded-lg text-amber-100 text-sm placeholder-amber-200/20"
      >{@text}</textarea>
    </div>
    <div>
      <label class="block text-sm text-amber-200/70 mb-1">About (optional)</label>
      <select
        name="target_ref"
        class="w-full px-3 py-2 bg-amber-900/30 border border-amber-700/30 rounded-lg text-amber-100 text-sm"
      >
        <option value="">General note</option>
        <%= for {value, label} <- @all_options do %>
          <option value={value} selected={value == @target_ref}>{label}</option>
        <% end %>
      </select>
    </div>
    """
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
