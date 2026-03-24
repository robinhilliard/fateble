defmodule FateWeb.ActionsLive do
  use FateWeb, :live_view

  alias Fate.Engine

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
    mook_eliminate: "Eliminate Mook"
  }

  @exchange_types ~w(roll_attack roll_defend roll_overcome roll_create_advantage invoke shifts_resolved redirect_hit stress_apply consequence_take concede taken_out)a

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:branch_id, nil)
      |> assign(:events, [])
      |> assign(:state, nil)
      |> assign(:selection, [])
      |> assign(:building, nil)
      |> assign(:build_steps, [])
      |> assign(:modal, nil)
      |> assign(:form_data, %{})
      |> assign(:prefill_entity_id, nil)

    {:ok, socket}
  end

  @impl true
  def handle_params(%{"branch_id" => branch_id}, _uri, socket) do
    if connected?(socket) do
      Engine.subscribe(branch_id)
      Phoenix.PubSub.subscribe(Fate.PubSub, "selection:#{branch_id}")

      case Engine.load_event_chain(get_head_event_id(branch_id)) do
        {:ok, events} ->
          {:ok, state} = Engine.derive_state(branch_id)

          {:noreply,
           socket
           |> assign(:branch_id, branch_id)
           |> assign(:events, events)
           |> assign(:state, state)}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Could not load branch")}
      end
    else
      {:noreply, assign(socket, :branch_id, branch_id)}
    end
  end

  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  @impl true
  def handle_info({:state_updated, state}, socket) do
    case Engine.load_event_chain(get_head_event_id(socket.assigns.branch_id)) do
      {:ok, events} ->
        {:noreply, socket |> assign(:state, state) |> assign(:events, events)}

      _ ->
        {:noreply, assign(socket, :state, state)}
    end
  end

  def handle_info({:selection_updated, selection}, socket) do
    {:noreply, assign(socket, :selection, selection)}
  end

  @impl true
  def handle_event("start_exchange", %{"type" => type} = params, socket) do
    type = String.to_existing_atom(type)

    {:noreply,
     socket
     |> assign(:building, type)
     |> assign(:build_steps, [])
     |> assign(:prefill_entity_id, params["entity_id"])}
  end

  def handle_event("cancel_build", _params, socket) do
    {:noreply, socket |> assign(:building, nil) |> assign(:build_steps, [])}
  end

  def handle_event("add_step", %{"step_type" => step_type} = params, socket) do
    step = %{
      type: String.to_existing_atom(step_type),
      actor_id: params["actor_id"],
      target_id: params["target_id"],
      detail: params["detail"] || %{},
      description: params["description"] || ""
    }

    {:noreply, assign(socket, :build_steps, socket.assigns.build_steps ++ [step])}
  end

  def handle_event("remove_step", %{"index" => index}, socket) do
    {index, _} = Integer.parse(index)
    steps = List.delete_at(socket.assigns.build_steps, index)
    {:noreply, assign(socket, :build_steps, steps)}
  end

  def handle_event("commit_exchange", _params, socket) do
    branch_id = socket.assigns.branch_id
    exchange_id = Ash.UUID.generate()

    Enum.reduce_while(socket.assigns.build_steps, {:ok, nil}, fn step, _acc ->
      attrs = %{
        type: step.type,
        actor_id: step.actor_id,
        target_id: step.target_id,
        exchange_id: exchange_id,
        description: step.description,
        detail: step.detail
      }

      case Engine.append_event(branch_id, attrs) do
        {:ok, _state, _event} -> {:cont, {:ok, nil}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)

    {:noreply, socket |> assign(:building, nil) |> assign(:build_steps, [])}
  end

  def handle_event("open_modal", %{"type" => type} = params, socket) do
    {:noreply,
     socket
     |> assign(:modal, type)
     |> assign(:form_data, %{})
     |> assign(:prefill_entity_id, params["entity_id"])}
  end

  def handle_event("entity_dropped", %{"entity_id" => entity_id, "action_type" => action_type, "action_category" => category}, socket) do
    case category do
      "exchange" ->
        type = String.to_existing_atom(action_type)

        {:noreply,
         socket
         |> assign(:building, type)
         |> assign(:build_steps, [])
         |> assign(:prefill_entity_id, entity_id)}

      "quick" ->
        {:noreply,
         socket
         |> assign(:modal, action_type)
         |> assign(:form_data, %{})
         |> assign(:prefill_entity_id, entity_id)}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("close_modal", _params, socket) do
    {:noreply, socket |> assign(:modal, nil) |> assign(:form_data, %{})}
  end

  def handle_event("submit_modal", params, socket) do
    result =
      case socket.assigns.modal do
        "aspect_create" ->
          {target_type, target_id} =
            case String.split(params["target_ref"] || "entity:", ":", parts: 2) do
              ["scene", id] -> {"scene", id}
              ["zone", id] -> {"zone", id}
              ["entity", id] -> {"entity", id}
              _ -> {"entity", params["target_id"]}
            end

          Engine.append_event(socket.assigns.branch_id, %{
            type: :aspect_create,
            target_id: target_id,
            description: "Add aspect: #{params["description"]}",
            detail: %{
              "target_id" => target_id,
              "target_type" => target_type,
              "description" => params["description"],
              "role" => params["role"] || "additional",
              "hidden" => params["hidden"] == "true"
            }
          })

        "aspect_compel" ->
          Engine.append_event(socket.assigns.branch_id, %{
            type: :aspect_compel,
            actor_id: params["actor_id"],
            target_id: params["target_id"],
            description: "Compel: #{params["description"]}",
            detail: %{
              "aspect_id" => params["aspect_id"],
              "accepted" => params["accepted"] != "false"
            }
          })

        "entity_move" ->
          Engine.append_event(socket.assigns.branch_id, %{
            type: :entity_move,
            actor_id: params["entity_id"],
            description: "Move to #{params["zone_name"] || "zone"}",
            detail: %{"entity_id" => params["entity_id"], "zone_id" => params["zone_id"]}
          })

        "scene_start" ->
          Engine.append_event(socket.assigns.branch_id, %{
            type: :scene_start,
            description: "Start scene: #{params["name"]}",
            detail: %{
              "scene_id" => Ash.UUID.generate(),
              "name" => params["name"],
              "description" => params["scene_description"]
            }
          })

        "scene_end" ->
          active = socket.assigns.state.scenes |> Enum.find(&(&1.status == :active))
          if active do
            Engine.append_event(socket.assigns.branch_id, %{
              type: :scene_end,
              description: "End scene: #{active.name}",
              detail: %{"scene_id" => active.id}
            })
          else
            {:error, "No active scene"}
          end

        "fate_point_spend" ->
          Engine.append_event(socket.assigns.branch_id, %{
            type: :fate_point_spend,
            target_id: params["entity_id"],
            description: "Spend fate point",
            detail: %{"entity_id" => params["entity_id"], "amount" => 1}
          })

        "fate_point_earn" ->
          Engine.append_event(socket.assigns.branch_id, %{
            type: :fate_point_earn,
            target_id: params["entity_id"],
            description: "Earn fate point",
            detail: %{"entity_id" => params["entity_id"], "amount" => 1}
          })

        "fate_point_refresh" ->
          Engine.append_event(socket.assigns.branch_id, %{
            type: :fate_point_refresh,
            target_id: params["entity_id"],
            description: "Refresh fate points",
            detail: %{"entity_id" => params["entity_id"]}
          })

        "entity_create" ->
          Engine.append_event(socket.assigns.branch_id, %{
            type: :entity_create,
            description: "Create #{params["name"]}",
            detail: %{
              "entity_id" => Ash.UUID.generate(),
              "name" => params["name"],
              "kind" => params["kind"] || "npc",
              "color" => params["color"] || "#6b7280",
              "fate_points" => parse_int(params["fate_points"]),
              "refresh" => parse_int(params["refresh"])
            }
          })

        _ ->
          {:error, "Unknown modal type"}
      end

    case result do
      {:ok, _state, _event} ->
        {:noreply, socket |> assign(:modal, nil) |> assign(:form_data, %{})}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, inspect(reason))}
    end
  end

  def handle_event("delete_event", %{"id" => event_id}, socket) do
    case Ash.get(Fate.Game.Event, event_id) do
      {:ok, event} ->
        Ash.destroy!(event, action: :delete)

        case Engine.load_event_chain(get_head_event_id(socket.assigns.branch_id)) do
          {:ok, events} ->
            {:ok, state} = Engine.derive_state(socket.assigns.branch_id)
            {:noreply, socket |> assign(:events, events) |> assign(:state, state)}

          _ ->
            {:noreply, socket}
        end

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex h-screen relative" style="background: #1a1410; color: #e8dcc8;">
      <%!-- Window switcher --%>
      <a
        href={~p"/table/#{@branch_id || ""}"}
        target="fate-table"
        class="absolute bottom-3 right-3 z-50 px-3 py-1.5 bg-amber-900/70 border border-amber-700/30 rounded-lg text-amber-200 text-sm hover:bg-amber-800/70 transition"
        style="font-family: 'Patrick Hand', cursive;"
      >
        Table ↗
      </a>

      <%!-- Modal overlay --%>
      <.action_modal modal={@modal} state={@state} prefill_entity_id={@prefill_entity_id} />
      <%!-- Event Log (left panel) --%>
      <div class="w-1/2 border-r border-amber-900/30 flex flex-col">
        <div class="p-4 border-b border-amber-900/30">
          <h2 class="text-xl font-bold" style="font-family: 'Permanent Marker', cursive;">
            Event Log
          </h2>
          <p class="text-amber-200/40 text-sm mt-1">
            {length(@events)} events on this branch
          </p>
        </div>

        <div class="flex-1 overflow-y-auto p-3 space-y-1" id="event-log">
          <%= if @events == [] do %>
            <div class="text-amber-200/30 text-center py-8">No events yet</div>
          <% else %>
            <%= for {event, index} <- @events |> Enum.reverse() |> Enum.with_index() do %>
              <.event_row event={event} index={length(@events) - 1 - index} state={@state} />
            <% end %>
          <% end %>
        </div>
      </div>

      <%!-- Action Palette (right panel) --%>
      <div class="w-1/2 flex flex-col">
        <div class="p-4 border-b border-amber-900/30">
          <h2 class="text-xl font-bold" style="font-family: 'Permanent Marker', cursive;">
            Action Palette
          </h2>

          <%!-- Cross-window selection pills --%>
          <%= if @selection != [] do %>
            <div class="flex flex-wrap gap-1 mt-2">
              <span class="text-xs text-amber-200/50">Selected:</span>
              <%= for item <- @selection do %>
                <span class="px-2 py-0.5 bg-yellow-900/50 text-yellow-200 text-xs rounded-full border border-yellow-600/30">
                  {item.type}: {short_id(item.id)}
                </span>
              <% end %>
            </div>
          <% end %>
        </div>

        <div class="flex-1 overflow-y-auto p-4">
          <%= if @building do %>
            <%!-- Exchange builder --%>
            <.exchange_builder
              building={@building}
              build_steps={@build_steps}
              state={@state}
              selection={@selection}
            />
          <% else %>
            <%!-- Quick actions + exchange starters --%>
            <.action_menu state={@state} />
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  # --- Components ---

  defp event_row(assigns) do
    color = entity_color(assigns.state, assigns.event.actor_id)
    summary = compact_event_summary(assigns.event)

    assigns =
      assigns
      |> assign(:color, color)
      |> assign(:summary, summary)

    ~H"""
    <div
      id={"event-#{@index}"}
      class={"group flex items-center gap-2 px-2 py-1 rounded hover:bg-amber-900/20 transition text-sm
        #{if @event.exchange_id, do: "ml-4 border-l-2 border-amber-700/20", else: ""}"}
    >
      <div
        class="w-2 h-2 rounded-full shrink-0"
        style={"background: #{@color};"}
      />
      <span class="text-amber-200/40 text-xs shrink-0">{@index + 1}</span>
      <span class="flex-1 text-amber-100/80 truncate" style="font-family: 'Patrick Hand', cursive;">
        {@summary}
      </span>
      <button
        phx-click="delete_event"
        phx-value-id={@event.id}
        class="opacity-0 group-hover:opacity-100 text-red-400/50 hover:text-red-400 text-xs transition shrink-0"
        data-confirm="Delete this event?"
      >
        ✕
      </button>
    </div>
    """
  end

  defp compact_event_summary(event) do
    detail = event.detail || %{}

    case event.type do
      :create_campaign -> "Campaign: #{detail["campaign_name"] || event.description}"
      :set_system -> "System: #{detail["system"] || "core"}"
      :entity_create -> "New #{detail["kind"] || "entity"}: #{detail["name"]}"
      :entity_modify -> "Edit #{detail["name"] || event.target_id}"
      :entity_remove -> "Remove #{event.target_id}"
      :aspect_create -> "+ #{detail["description"]}"
      :aspect_remove -> "- #{event.description || "aspect"}"
      :aspect_compel -> "Compel: #{detail["aspect_id"]}"
      :skill_set -> "#{detail["skill"]} → +#{detail["rating"]}"
      :stunt_add -> "Stunt: #{detail["name"]}"
      :stunt_remove -> "Remove stunt"
      :scene_start -> "Scene: #{detail["name"]}"
      :scene_end -> "End scene"
      :zone_create -> "Zone: #{detail["name"]}"
      :entity_enter_scene -> "Enter scene"
      :entity_move -> "Move to zone"
      :roll_attack -> "Attack #{detail["skill"] || ""} #{format_dice(detail["fudge_dice"] || [])} = #{detail["raw_total"] || "?"}"
      :roll_defend -> "Defend #{detail["skill"] || ""} #{format_dice(detail["fudge_dice"] || [])} = #{detail["raw_total"] || "?"}"
      :roll_overcome -> "Overcome #{detail["skill"] || ""} #{format_dice(detail["fudge_dice"] || [])}"
      :roll_create_advantage -> "Advantage #{detail["skill"] || ""} #{format_dice(detail["fudge_dice"] || [])}"
      :invoke -> "Invoke: #{detail["description"] || detail["aspect_id"]}"
      :shifts_resolved -> "#{detail["shifts"] || 0} shifts — #{detail["outcome"]}"
      :redirect_hit -> "Redirect hit"
      :stress_apply -> "Stress ×#{detail["box_index"]}"
      :stress_clear -> "Clear stress"
      :consequence_take -> "#{detail["severity"]}: #{detail["aspect_text"]}"
      :consequence_recover -> "Recover consequence"
      :fate_point_spend -> "Spend FP"
      :fate_point_earn -> "Earn FP"
      :fate_point_refresh -> "Refresh FP"
      :concede -> "Concede"
      :taken_out -> "Taken out!"
      :mook_eliminate -> "Mook eliminated"
      _ -> event.description || to_string(event.type)
    end
  end

  defp exchange_builder(assigns) do
    ~H"""
    <div>
      <div class="flex items-center justify-between mb-4">
        <h3 class="text-lg font-bold" style="font-family: 'Patrick Hand', cursive;">
          Building: {exchange_label(@building)}
        </h3>
        <button
          phx-click="cancel_build"
          class="text-sm text-red-400 hover:text-red-300"
        >
          Cancel
        </button>
      </div>

      <%!-- Available step tiles --%>
      <div class="mb-4">
        <div class="text-xs uppercase text-amber-200/40 mb-2 font-bold">Available Steps</div>
        <div class="flex flex-wrap gap-2">
          <%= for step_type <- available_steps(@building) do %>
            <button
              phx-click="add_step"
              phx-value-step_type={step_type}
              class="px-3 py-2 bg-amber-900/40 border border-amber-700/30 rounded-lg
                hover:bg-amber-800/40 hover:border-amber-600/40 transition text-sm"
              style="font-family: 'Patrick Hand', cursive;"
            >
              {Map.get(@event_type_labels, step_type, to_string(step_type))}
            </button>
          <% end %>
        </div>
      </div>

      <%!-- Build lane --%>
      <div class="mb-4">
        <div class="text-xs uppercase text-amber-200/40 mb-2 font-bold">Build Lane</div>
        <%= if @build_steps == [] do %>
          <div class="text-amber-200/20 text-sm py-4 text-center border border-dashed border-amber-700/20 rounded-lg">
            Click steps above to add them here
          </div>
        <% else %>
          <div class="space-y-2">
            <%= for {step, index} <- Enum.with_index(@build_steps) do %>
              <div class="flex items-center gap-2 px-3 py-2 bg-amber-900/30 rounded-lg border border-amber-700/20">
                <span class="text-xs text-amber-300/50 font-bold">{index + 1}.</span>
                <span class="text-sm" style="font-family: 'Patrick Hand', cursive;">
                  {Map.get(@event_type_labels, step.type, to_string(step.type))}
                </span>
                <%= if step.description != "" do %>
                  <span class="text-xs text-amber-200/40">— {step.description}</span>
                <% end %>
                <button
                  phx-click="remove_step"
                  phx-value-index={index}
                  class="ml-auto text-red-400/50 hover:text-red-400 text-xs"
                >
                  ✕
                </button>
              </div>
            <% end %>
          </div>
        <% end %>
      </div>

      <%!-- Commit button --%>
      <%= if @build_steps != [] do %>
        <button
          phx-click="commit_exchange"
          class="w-full py-3 bg-green-800/60 border border-green-600/30 rounded-lg
            hover:bg-green-700/60 transition text-green-200 font-bold"
        >
          Commit {length(@build_steps)} steps to log
        </button>
      <% end %>
    </div>
    """
  end

  defp action_menu(assigns) do
    ~H"""
    <div>
      <%!-- Exchange starters --%>
      <div class="mb-6">
        <div class="text-xs uppercase text-amber-200/40 mb-2 font-bold">Start Exchange</div>
        <div class="grid grid-cols-2 gap-2">
          <%= for {type, label, desc, bg} <- [
            {"attack", "Attack", "Roll, defend, invoke, resolve, absorb", "bg-red-900/30 border-red-700/30 hover:bg-red-800/30"},
            {"overcome", "Overcome", "Roll vs fixed difficulty", "bg-blue-900/30 border-blue-700/30 hover:bg-blue-800/30"},
            {"create_advantage", "Create Advantage", "Roll to create or discover an aspect", "bg-green-900/30 border-green-700/30 hover:bg-green-800/30"},
            {"defend", "Defend", "Oppose an attack or overcome", "bg-amber-900/30 border-amber-700/30 hover:bg-amber-800/30"}
          ] do %>
            <button
              phx-click="start_exchange"
              phx-value-type={type}
              phx-hook="DropTarget"
              id={"exchange-#{type}"}
              data-action-type={type}
              data-action-category="exchange"
              class={"px-4 py-3 border rounded-lg transition text-left cursor-pointer drop-target #{bg}"}
            >
              <div class="font-bold text-sm" style="font-family: 'Permanent Marker', cursive;">{label}</div>
              <div class="text-xs text-amber-200/30">{desc}</div>
            </button>
          <% end %>
        </div>
      </div>

      <%!-- Quick actions --%>
      <div class="mb-6">
        <div class="text-xs uppercase text-amber-200/40 mb-2 font-bold">Quick Actions</div>
        <div class="grid grid-cols-3 gap-2">
          <%= for {type, label} <- quick_action_types() do %>
            <button
              phx-click="open_modal"
              phx-value-type={type}
              phx-hook="DropTarget"
              id={"quick-#{type}"}
              data-action-type={type}
              data-action-category="quick"
              class="px-3 py-2 bg-amber-900/20 border border-amber-700/20 rounded-lg
                hover:bg-amber-800/30 transition text-sm cursor-pointer drop-target"
              style="font-family: 'Patrick Hand', cursive;"
            >
              {label}
            </button>
          <% end %>
        </div>
      </div>

      <%!-- Entities reference --%>
      <%= if @state do %>
        <div>
          <div class="text-xs uppercase text-amber-200/40 mb-2 font-bold">Entities</div>
          <div class="space-y-0.5">
            <%= for {section, entities} <- grouped_entities(@state) do %>
              <div class="text-xs uppercase text-amber-200/25 mt-2 mb-1 tracking-wider">{section}</div>
              <%= for {entity, depth} <- entities do %>
                <div
                  class="flex items-center gap-2 px-2 py-1 rounded hover:bg-amber-900/20 cursor-grab active:cursor-grabbing"
                  style={"margin-left: #{depth * 16}px;"}
                  draggable="true"
                  phx-hook="DraggableEntity"
                  id={"entity-drag-#{entity.id}"}
                  data-entity-id={entity.id}
                  data-entity-name={entity.name}
                >
                  <div class="w-3 h-3 rounded-full shrink-0" style={"background: #{entity.color};"} />
                  <span class="text-sm" style="font-family: 'Patrick Hand', cursive;">{entity.name}</span>
                  <span class="text-xs text-amber-200/30">{entity.kind}</span>
                  <%= if entity.fate_points do %>
                    <span class="ml-auto text-xs text-amber-200/50">FP: {entity.fate_points}</span>
                  <% end %>
                </div>
              <% end %>
            <% end %>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  # --- Helpers ---

  defp grouped_entities(state) do
    all = Map.values(state.entities)
    top_level = Enum.filter(all, &is_nil(&1.parent_id))
    children_by_parent = Enum.group_by(all, & &1.parent_id)

    pcs = top_level |> Enum.filter(&(&1.kind == :pc)) |> Enum.sort_by(& &1.name)
    npcs = top_level |> Enum.filter(&(&1.kind == :npc)) |> Enum.sort_by(& &1.name)
    others = top_level |> Enum.reject(&(&1.kind in [:pc, :npc])) |> Enum.sort_by(& &1.name)

    sections =
      [
        {"Player Characters", flatten_with_children(pcs, children_by_parent, 0)},
        {"NPCs", flatten_with_children(npcs, children_by_parent, 0)},
        {"Other", flatten_with_children(others, children_by_parent, 0)}
      ]
      |> Enum.reject(fn {_, list} -> list == [] end)

    sections
  end

  defp flatten_with_children(entities, children_by_parent, depth) do
    Enum.flat_map(entities, fn entity ->
      kids = Map.get(children_by_parent, entity.id, []) |> Enum.sort_by(& &1.name)
      [{entity, depth} | flatten_with_children(kids, children_by_parent, depth + 1)]
    end)
  end

  defp get_head_event_id(branch_id) do
    case Ash.get(Fate.Game.Branch, branch_id) do
      {:ok, branch} -> branch.head_event_id
      _ -> nil
    end
  end

  defp entity_color(nil, _), do: "#6b7280"
  defp entity_color(_state, nil), do: "#6b7280"

  defp entity_color(state, entity_id) do
    case Map.get(state.entities, entity_id) do
      nil -> "#6b7280"
      entity -> entity.color || "#6b7280"
    end
  end

  defp short_id(nil), do: "—"
  defp short_id(id) when is_binary(id), do: String.slice(id, 0..7)

  defp format_dice([]), do: "—"

  defp format_dice(dice) do
    dice
    |> Enum.map(fn
      1 -> "+"
      -1 -> "−"
      0 -> "○"
      _ -> "?"
    end)
    |> Enum.join("")
  end

  defp exchange_label(:attack), do: "Attack Exchange"
  defp exchange_label(:overcome), do: "Overcome"
  defp exchange_label(:create_advantage), do: "Create Advantage"
  defp exchange_label(:defend), do: "Defend"
  defp exchange_label(other), do: to_string(other)

  defp available_steps(:attack) do
    [:roll_attack, :roll_defend, :invoke, :shifts_resolved, :stress_apply, :consequence_take, :redirect_hit, :concede, :taken_out]
  end

  defp available_steps(:overcome) do
    [:roll_overcome, :invoke, :shifts_resolved]
  end

  defp available_steps(:create_advantage) do
    [:roll_create_advantage, :invoke, :shifts_resolved, :aspect_create]
  end

  defp available_steps(:defend) do
    [:roll_defend, :invoke]
  end

  defp available_steps(_), do: []

  defp quick_action_types do
    [
      {"aspect_create", "Create Aspect"},
      {"aspect_compel", "Compel"},
      {"entity_move", "Move Entity"},
      {"scene_start", "Start Scene"},
      {"scene_end", "End Scene"},
      {"fate_point_spend", "Spend FP"},
      {"fate_point_earn", "Earn FP"},
      {"fate_point_refresh", "Refresh FP"},
      {"entity_create", "Create Entity"}
    ]
  end

  defp decode_detail(nil), do: %{}
  defp decode_detail(detail) when is_map(detail), do: detail

  defp decode_detail(detail) when is_binary(detail) do
    case Jason.decode(detail) do
      {:ok, map} -> map
      _ -> %{}
    end
  end

  defp parse_int(nil), do: nil
  defp parse_int(""), do: nil
  defp parse_int(v) when is_integer(v), do: v

  defp parse_int(v) when is_binary(v) do
    case Integer.parse(v) do
      {n, _} -> n
      :error -> nil
    end
  end

  defp action_modal(%{modal: nil} = assigns), do: ~H""

  defp action_modal(assigns) do
    entities = if assigns.state, do: Map.values(assigns.state.entities), else: []
    assigns = assign(assigns, :entities, entities)

    ~H"""
    <div class="fixed inset-0 z-50 flex items-center justify-center bg-black/60">
      <div class="bg-amber-950 border border-amber-700/40 rounded-xl p-6 w-96 shadow-2xl">
        <h3 class="text-lg font-bold mb-4" style="font-family: 'Permanent Marker', cursive;">
          {modal_title(@modal)}
        </h3>

        <form phx-submit="submit_modal" class="space-y-3">
          <.modal_fields modal={@modal} entities={@entities} state={@state} prefill_entity_id={@prefill_entity_id} />

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

  defp modal_title("aspect_create"), do: "Create Aspect"
  defp modal_title("aspect_compel"), do: "Compel Aspect"
  defp modal_title("entity_move"), do: "Move Entity"
  defp modal_title("scene_start"), do: "Start Scene"
  defp modal_title("scene_end"), do: "End Scene"
  defp modal_title("fate_point_spend"), do: "Spend Fate Point"
  defp modal_title("fate_point_earn"), do: "Earn Fate Point"
  defp modal_title("fate_point_refresh"), do: "Refresh Fate Points"
  defp modal_title("entity_create"), do: "Create Entity"
  defp modal_title(other), do: other

  defp modal_fields(%{modal: "aspect_create"} = assigns) do
    active_scene = assigns.state && assigns.state.scenes |> Enum.find(&(&1.status == :active))
    zones = if active_scene, do: active_scene.zones, else: []

    scene_and_zone_options =
      if active_scene do
        [{"scene:#{active_scene.id}", "Scene: #{active_scene.name}"}] ++
          Enum.map(zones, fn z -> {"zone:#{z.id}", "Zone: #{z.name}"} end)
      else
        []
      end

    entity_options = Enum.map(assigns.entities, fn e -> {"entity:#{e.id}", "#{e.name} (#{e.kind})"} end)
    all_options = scene_and_zone_options ++ entity_options

    prefill =
      if assigns.prefill_entity_id, do: "entity:#{assigns.prefill_entity_id}", else: nil

    assigns = assigns
      |> assign(:all_options, all_options)
      |> assign(:prefill, prefill)

    ~H"""
    <div>
      <label class="block text-sm text-amber-200/70 mb-1">On</label>
      <select name="target_ref" class="w-full px-3 py-2 bg-amber-900/30 border border-amber-700/30 rounded-lg text-amber-100 text-sm">
        <%= for {value, label} <- @all_options do %>
          <option value={value} selected={value == @prefill}>{label}</option>
        <% end %>
      </select>
    </div>
    <.text_input name="description" label="Aspect Text" placeholder="e.g. On Fire! or Flanking Position" />
    <.select_input name="role" label="Role" options={[
      {"situation", "Situation"}, {"boost", "Boost"}, {"additional", "Additional"},
      {"high_concept", "High Concept"}, {"trouble", "Trouble"}
    ]} />
    <label class="flex items-center gap-2 text-sm text-amber-200/70">
      <input type="checkbox" name="hidden" value="true" class="rounded" />
      Hidden from players
    </label>
    """
  end

  defp modal_fields(%{modal: "entity_create"} = assigns) do
    ~H"""
    <.text_input name="name" label="Name" placeholder="Character name" />
    <.select_input name="kind" label="Kind" options={[
      {"pc", "PC"}, {"npc", "NPC"}, {"mook_group", "Mook Group"},
      {"organization", "Organization"}, {"vehicle", "Vehicle"},
      {"item", "Item"}, {"hazard", "Hazard"}, {"custom", "Custom"}
    ]} />
    <.text_input name="color" label="Color" placeholder="#dc2626" />
    <.text_input name="fate_points" label="Fate Points" placeholder="3" />
    <.text_input name="refresh" label="Refresh" placeholder="3" />
    """
  end

  defp modal_fields(%{modal: "scene_start"} = assigns) do
    ~H"""
    <.text_input name="name" label="Scene Name" placeholder="Dockside Warehouse" />
    <.text_input name="scene_description" label="Description" placeholder="A brief framing of the scene" />
    """
  end

  defp modal_fields(%{modal: "scene_end"} = assigns) do
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

  defp modal_fields(%{modal: modal} = assigns) when modal in ~w(fate_point_spend fate_point_earn fate_point_refresh) do
    ~H"""
    <.entity_select name="entity_id" label="Entity" entities={@entities} selected={@prefill_entity_id} />
    """
  end

  defp modal_fields(%{modal: "entity_move"} = assigns) do
    zones =
      if assigns.state do
        assigns.state.scenes
        |> Enum.filter(&(&1.status == :active))
        |> Enum.flat_map(& &1.zones)
      else
        []
      end

    assigns = assign(assigns, :zones, zones)

    ~H"""
    <.entity_select name="entity_id" label="Entity" entities={@entities} selected={@prefill_entity_id} />
    <div>
      <label class="block text-sm text-amber-200/70 mb-1">To Zone</label>
      <select name="zone_id" class="w-full px-3 py-2 bg-amber-900/30 border border-amber-700/30 rounded-lg text-amber-100 text-sm">
        <%= for zone <- @zones do %>
          <option value={zone.id}>{zone.name}</option>
        <% end %>
      </select>
    </div>
    """
  end

  defp modal_fields(%{modal: "aspect_compel"} = assigns) do
    ~H"""
    <.entity_select name="target_id" label="Target Entity" entities={@entities} selected={@prefill_entity_id} />
    <.text_input name="description" label="Compel Description" placeholder="What complication does this cause?" />
    """
  end

  defp modal_fields(assigns) do
    ~H"""
    <p class="text-sm text-amber-200/50">No fields configured for this action type.</p>
    """
  end

  defp entity_select(assigns) do
    assigns = assign_new(assigns, :selected, fn -> nil end)

    ~H"""
    <div>
      <label class="block text-sm text-amber-200/70 mb-1">{@label}</label>
      <select name={@name} class="w-full px-3 py-2 bg-amber-900/30 border border-amber-700/30 rounded-lg text-amber-100 text-sm">
        <%= for entity <- @entities do %>
          <option value={entity.id} selected={entity.id == @selected}>{entity.name} ({entity.kind})</option>
        <% end %>
      </select>
    </div>
    """
  end

  defp text_input(assigns) do
    assigns = assign_new(assigns, :placeholder, fn -> "" end)

    ~H"""
    <div>
      <label class="block text-sm text-amber-200/70 mb-1">{@label}</label>
      <input
        type="text"
        name={@name}
        placeholder={@placeholder}
        class="w-full px-3 py-2 bg-amber-900/30 border border-amber-700/30 rounded-lg text-amber-100 text-sm placeholder-amber-200/20"
      />
    </div>
    """
  end

  defp select_input(assigns) do
    ~H"""
    <div>
      <label class="block text-sm text-amber-200/70 mb-1">{@label}</label>
      <select name={@name} class="w-full px-3 py-2 bg-amber-900/30 border border-amber-700/30 rounded-lg text-amber-100 text-sm">
        <%= for {value, label} <- @options do %>
          <option value={value}>{label}</option>
        <% end %>
      </select>
    </div>
    """
  end
end
