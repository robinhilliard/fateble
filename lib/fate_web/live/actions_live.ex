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
    scene_modify: "Edit Scene"
  }

  @roll_types ~w(roll_attack roll_defend roll_overcome roll_create_advantage)a

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:bookmark_id, nil)
      |> assign(:events, [])
      |> assign(:state, nil)
      |> assign(:is_gm, FateWeb.Helpers.localhost?(socket))
      |> assign(:log_tab, :bookmarks)
      |> assign(:selection, [])
      |> assign(:building, nil)
      |> assign(:build_steps, [])
      |> assign(:editing_step, nil)
      |> assign(:modal, nil)
      |> assign(:form_data, %{})
      |> assign(:prefill_entity_id, nil)

    {:ok, socket}
  end

  @impl true
  def handle_params(%{"bookmark_id" => bookmark_id}, _uri, socket) do
    if connected?(socket) do
      Engine.subscribe(bookmark_id)
      Phoenix.PubSub.subscribe(Fate.PubSub, "selection:#{bookmark_id}")
      Phoenix.PubSub.subscribe(Fate.PubSub, "exchange:#{bookmark_id}")

      with {:ok, state} <- Engine.derive_state(bookmark_id) do
        events = load_events_for_role(bookmark_id, socket.assigns.is_gm)

        {:noreply,
         socket
         |> assign(:bookmark_id, bookmark_id)
         |> assign(:events, events)
         |> assign(:state, state)}
      else
        _ ->
          {:noreply,
           socket
           |> assign(:bookmark_id, bookmark_id)
           |> put_flash(:error, "Could not load bookmark")}
      end
    else
      {:noreply, assign(socket, :bookmark_id, bookmark_id)}
    end
  end

  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  @impl true
  def handle_info({:state_updated, state}, socket) do
    events = load_events_for_role(socket.assigns.bookmark_id, socket.assigns.is_gm)

    {:noreply,
     socket
     |> assign(:state, state)
     |> assign(:events, events)}
  end

  def handle_info({:selection_updated, selection}, socket) do
    {:noreply, assign(socket, :selection, selection)}
  end

  def handle_info({:exchange_updated, %{building: building, build_steps: build_steps}}, socket) do
    {:noreply,
     socket
     |> assign(:building, building)
     |> assign(:build_steps, build_steps)}
  end

  def handle_event("fork_bookmark", %{"bookmark-id" => bookmark_id}, socket) do
    {:noreply,
     socket
     |> assign(:modal, "fork_bookmark")
     |> assign(:fork_bookmark_id, bookmark_id)}
  end

  def handle_event("set_log_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :log_tab, String.to_existing_atom(tab))}
  end

  @impl true
  def handle_event("start_exchange", %{"type" => type} = params, socket) do
    type = String.to_existing_atom(type)

    socket =
      socket
      |> assign(:building, type)
      |> assign(:build_steps, [])
      |> assign(:prefill_entity_id, params["entity_id"])

    broadcast_exchange(socket)
    {:noreply, socket}
  end

  def handle_event("cancel_build", _params, socket) do
    socket =
      socket |> assign(:building, nil) |> assign(:build_steps, []) |> assign(:editing_step, nil)

    broadcast_exchange(socket)
    {:noreply, socket}
  end

  def handle_event("add_step", %{"step_type" => step_type} = _params, socket) do
    type = String.to_existing_atom(step_type)
    prefill_actor = socket.assigns.prefill_entity_id

    step = %{
      type: type,
      actor_id: prefill_actor,
      target_id: nil,
      detail: default_step_detail(type),
      description: ""
    }

    new_index = length(socket.assigns.build_steps)

    socket =
      socket
      |> assign(:build_steps, socket.assigns.build_steps ++ [step])
      |> assign(:editing_step, new_index)

    broadcast_exchange(socket)
    {:noreply, socket}
  end

  def handle_event("edit_step", %{"index" => index}, socket) do
    {index, _} = Integer.parse(index)
    {:noreply, assign(socket, :editing_step, index)}
  end

  def handle_event("close_step_form", _params, socket) do
    {:noreply, assign(socket, :editing_step, nil)}
  end

  def handle_event("remove_step", %{"index" => index}, socket) do
    {index, _} = Integer.parse(index)
    steps = List.delete_at(socket.assigns.build_steps, index)
    editing = socket.assigns.editing_step

    editing =
      cond do
        editing == nil -> nil
        editing == index -> nil
        editing > index -> editing - 1
        true -> editing
      end

    socket = socket |> assign(:build_steps, steps) |> assign(:editing_step, editing)
    broadcast_exchange(socket)
    {:noreply, socket}
  end

  def handle_event("update_step_field", %{"index" => index_str} = params, socket) do
    {index, _} = Integer.parse(index_str)
    steps = socket.assigns.build_steps

    case Enum.at(steps, index) do
      nil ->
        {:noreply, socket}

      step ->
        step =
          step
          |> maybe_update_field(params, "actor_id", :actor_id)
          |> maybe_update_field(params, "target_id", :target_id)

        detail_fields =
          ~w(skill skill_rating difficulty severity aspect_text shifts outcome track_label box_index description)

        step =
          Enum.reduce(detail_fields, step, fn field, acc ->
            case params[field] do
              nil -> acc
              val -> put_in(acc.detail[field], parse_step_value(field, val))
            end
          end)

        step =
          if params["skill"] && socket.assigns.state do
            actor = step.actor_id && Map.get(socket.assigns.state.entities, step.actor_id)
            rating = (actor && Map.get(actor.skills, params["skill"], 0)) || 0
            put_in(step.detail["skill_rating"], rating)
          else
            step
          end

        steps = List.replace_at(steps, index, step)
        socket = assign(socket, :build_steps, steps)
        broadcast_exchange(socket)
        {:noreply, socket}
    end
  end

  def handle_event("auto_roll_dice", %{"index" => index_str}, socket) do
    {index, _} = Integer.parse(index_str)
    steps = socket.assigns.build_steps

    case Enum.at(steps, index) do
      nil ->
        {:noreply, socket}

      step ->
        dice = for _ <- 1..4, do: Enum.random([-1, 0, 1])
        step = put_in(step.detail["fudge_dice"], dice)

        dice_sum = Enum.sum(dice)
        skill_rating = step.detail["skill_rating"] || 0
        step = put_in(step.detail["raw_total"], dice_sum + skill_rating)

        steps = List.replace_at(steps, index, step)
        socket = assign(socket, :build_steps, steps)
        broadcast_exchange(socket)
        {:noreply, socket}
    end
  end

  def handle_event("toggle_die", %{"index" => index_str, "die" => die_str}, socket) do
    {step_index, _} = Integer.parse(index_str)
    {die_index, _} = Integer.parse(die_str)
    steps = socket.assigns.build_steps

    case Enum.at(steps, step_index) do
      nil ->
        {:noreply, socket}

      step ->
        dice = step.detail["fudge_dice"] || [0, 0, 0, 0]
        current = Enum.at(dice, die_index, 0)

        next_val =
          case current do
            0 -> 1
            1 -> -1
            -1 -> 0
          end

        dice = List.replace_at(dice, die_index, next_val)
        step = put_in(step.detail["fudge_dice"], dice)

        dice_sum = Enum.sum(dice)
        skill_rating = step.detail["skill_rating"] || 0
        step = put_in(step.detail["raw_total"], dice_sum + skill_rating)

        steps = List.replace_at(steps, step_index, step)
        socket = assign(socket, :build_steps, steps)
        broadcast_exchange(socket)
        {:noreply, socket}
    end
  end

  def handle_event("commit_exchange", _params, socket) do
    branch_id = socket.assigns.bookmark_id
    exchange_id = Ash.UUID.generate()

    Enum.reduce_while(socket.assigns.build_steps, {:ok, nil}, fn step, _acc ->
      attrs = %{
        type: step.type,
        actor_id: step.actor_id,
        target_id: step.target_id,
        exchange_id: exchange_id,
        description: build_step_description(step, socket.assigns.state),
        detail: step.detail
      }

      case Engine.append_event(branch_id, attrs) do
        {:ok, _state, _event} -> {:cont, {:ok, nil}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)

    socket =
      socket |> assign(:building, nil) |> assign(:build_steps, []) |> assign(:editing_step, nil)

    broadcast_exchange(socket)
    {:noreply, socket}
  end

  def handle_event("open_modal", %{"type" => type} = params, socket) do
    {:noreply,
     socket
     |> assign(:modal, type)
     |> assign(:form_data, %{})
     |> assign(:prefill_entity_id, params["entity_id"])}
  end

  def handle_event(
        "entity_dropped",
        %{"entity_id" => entity_id, "action_type" => action_type, "action_category" => category},
        socket
      ) do
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

          Engine.append_event(socket.assigns.bookmark_id, %{
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
          Engine.append_event(socket.assigns.bookmark_id, %{
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
          Engine.append_event(socket.assigns.bookmark_id, %{
            type: :entity_move,
            actor_id: params["entity_id"],
            description: "Move to #{params["zone_name"] || "zone"}",
            detail: %{"entity_id" => params["entity_id"], "zone_id" => params["zone_id"]}
          })

        "scene_start" ->
          Engine.append_event(socket.assigns.bookmark_id, %{
            type: :scene_start,
            description: "Start scene: #{params["name"]}",
            detail: %{
              "scene_id" => Ash.UUID.generate(),
              "name" => params["name"],
              "description" => params["scene_description"],
              "gm_notes" => params["gm_notes"]
            }
          })

        "scene_end" ->
          active = socket.assigns.state.scenes |> Enum.find(&(&1.status == :active))

          if active do
            Engine.append_event(socket.assigns.bookmark_id, %{
              type: :scene_end,
              description: "End scene: #{active.name}",
              detail: %{"scene_id" => active.id}
            })
          else
            {:error, "No active scene"}
          end

        "fate_point_spend" ->
          Engine.append_event(socket.assigns.bookmark_id, %{
            type: :fate_point_spend,
            target_id: params["entity_id"],
            description: "Spend fate point",
            detail: %{"entity_id" => params["entity_id"], "amount" => 1}
          })

        "fate_point_earn" ->
          Engine.append_event(socket.assigns.bookmark_id, %{
            type: :fate_point_earn,
            target_id: params["entity_id"],
            description: "Earn fate point",
            detail: %{"entity_id" => params["entity_id"], "amount" => 1}
          })

        "fate_point_refresh" ->
          Engine.append_event(socket.assigns.bookmark_id, %{
            type: :fate_point_refresh,
            target_id: params["entity_id"],
            description: "Refresh fate points",
            detail: %{"entity_id" => params["entity_id"]}
          })

        "entity_create" ->
          detail = %{
            "entity_id" => Ash.UUID.generate(),
            "name" => params["name"],
            "kind" => params["kind"] || "npc",
            "color" => params["color"] || "#6b7280",
            "fate_points" => parse_int(params["fate_points"]),
            "refresh" => parse_int(params["refresh"]),
            "parent_entity_id" => params["parent_entity_id"]
          }

          detail =
            if params["aspects"] && params["aspects"] != "" do
              aspects =
                params["aspects"]
                |> String.split("\n", trim: true)
                |> Enum.map(fn line ->
                  case String.split(line, "|", parts: 2) do
                    [role, desc] ->
                      %{"role" => String.trim(role), "description" => String.trim(desc)}

                    [desc] ->
                      %{"role" => "additional", "description" => String.trim(desc)}
                  end
                end)

              Map.put(detail, "aspects", aspects)
            else
              detail
            end

          Engine.append_event(socket.assigns.bookmark_id, %{
            type: :entity_create,
            description: "Create #{params["name"]}",
            detail: detail
          })

        "entity_edit" ->
          detail =
            %{"entity_id" => params["entity_id"]}
            |> put_non_empty("name", params["name"])
            |> put_non_empty("kind", params["kind"])
            |> put_non_empty("color", params["color"])
            |> maybe_put_int("fate_points", params["fate_points"])
            |> maybe_put_int("refresh", params["refresh"])

          Engine.append_event(socket.assigns.bookmark_id, %{
            type: :entity_modify,
            target_id: params["entity_id"],
            description: "Edit #{params["name"] || "entity"}",
            detail: detail
          })

        "skill_set" ->
          Engine.append_event(socket.assigns.bookmark_id, %{
            type: :skill_set,
            target_id: params["entity_id"],
            description: "#{params["skill"]} → +#{params["rating"]}",
            detail: %{
              "entity_id" => params["entity_id"],
              "skill" => params["skill"],
              "rating" => parse_int(params["rating"]) || 0
            }
          })

        "stunt_add" ->
          Engine.append_event(socket.assigns.bookmark_id, %{
            type: :stunt_add,
            target_id: params["entity_id"],
            description: "Stunt: #{params["name"]}",
            detail: %{
              "entity_id" => params["entity_id"],
              "stunt_id" => Ash.UUID.generate(),
              "name" => params["name"],
              "effect" => params["effect"]
            }
          })

        "stunt_remove" ->
          Engine.append_event(socket.assigns.bookmark_id, %{
            type: :stunt_remove,
            target_id: params["entity_id"],
            description: "Remove stunt",
            detail: %{
              "entity_id" => params["entity_id"],
              "stunt_id" => params["stunt_id"]
            }
          })

        "set_system" ->
          detail = %{"system" => params["system"]}

          Engine.append_event(socket.assigns.bookmark_id, %{
            type: :set_system,
            description: "Set system: #{params["system"]}",
            detail: detail
          })

        "scene_modify" ->
          detail =
            %{"scene_id" => params["scene_id"]}
            |> put_non_empty("name", params["name"])
            |> put_non_empty("description", params["scene_description"])
            |> put_non_empty("gm_notes", params["gm_notes"])

          Engine.append_event(socket.assigns.bookmark_id, %{
            type: :scene_modify,
            description: "Edit scene",
            detail: detail
          })

        "fork_bookmark" ->
          bookmark_id = socket.assigns[:fork_bookmark_id]

          case Ash.get(Fate.Game.Bookmark, bookmark_id, not_found_error?: false) do
            {:ok, %{head_event_id: head_id} = parent} when head_id != nil ->
              with {:ok, bmk_event} <-
                     Ash.create(
                       Fate.Game.Event,
                       %{
                         parent_id: head_id,
                         type: :bookmark_create,
                         description: params["name"],
                         detail: %{"name" => params["name"]}
                       },
                       action: :append
                     ),
                   {:ok, new_bm} <-
                     Ash.create(
                       Fate.Game.Bookmark,
                       %{
                         name: params["name"],
                         head_event_id: bmk_event.id,
                         parent_bookmark_id: parent.id
                       },
                       action: :create
                     ) do
                {:ok, nil, new_bm}
              end

            _ ->
              {:error, "Bookmark not found"}
          end

        _ ->
          {:error, "Unknown modal type"}
      end

    case result do
      {:ok, nil, %Fate.Game.Bookmark{id: new_bm_id}} ->
        {:noreply, push_navigate(socket, to: ~p"/table/#{new_bm_id}")}

      {:ok, _state, _event} ->
        {:noreply, socket |> assign(:modal, nil) |> assign(:form_data, %{})}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, inspect(reason))}
    end
  end

  def handle_event("delete_event", %{"id" => event_id}, socket) do
    bookmark_id = socket.assigns.bookmark_id

    case Fate.Game.Events.delete(event_id, bookmark_id) do
      :ok ->
        events = load_events_for_role(bookmark_id, socket.assigns.is_gm)

        case Engine.derive_state(bookmark_id) do
          {:ok, state} ->
            Phoenix.PubSub.broadcast(
              Fate.PubSub,
              "bookmark:#{bookmark_id}",
              {:state_updated, state}
            )

            {:noreply, socket |> assign(:events, events) |> assign(:state, state)}

          _ ->
            {:noreply, assign(socket, :events, events)}
        end

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Cannot delete: other events depend on this one")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex h-screen relative" style="background: #1a1410; color: #e8dcc8;">
      <%!-- Window switcher --%>
      <a
        href={~p"/table/#{@bookmark_id || ""}"}
        target="fate-table"
        class="absolute bottom-3 right-3 z-50 px-3 py-1.5 bg-amber-900/70 border border-amber-700/30 rounded-lg text-amber-200 text-sm hover:bg-amber-800/70 transition"
        style="font-family: 'Patrick Hand', cursive;"
      >
        Table ↗
      </a>

      <%!-- Modal overlay --%>
      <.action_modal modal={@modal} state={@state} prefill_entity_id={@prefill_entity_id} />
      <%!-- Left panel: Event Log / Bookmarks tabs --%>
      <div class="w-1/2 border-r border-amber-900/30 flex flex-col">
        <div class="p-4 border-b border-amber-900/30">
          <div class="flex gap-4 mb-2">
            <button
              phx-click="set_log_tab"
              phx-value-tab="bookmarks"
              class={[
                "text-lg font-bold transition",
                if(@log_tab == :bookmarks,
                  do: "text-amber-100",
                  else: "text-amber-200/30 hover:text-amber-200/60"
                )
              ]}
              style="font-family: 'Permanent Marker', cursive;"
            >
              Bookmarks
            </button>
            <button
              phx-click="set_log_tab"
              phx-value-tab="events"
              class={[
                "text-lg font-bold transition",
                if(@log_tab == :events,
                  do: "text-amber-100",
                  else: "text-amber-200/30 hover:text-amber-200/60"
                )
              ]}
              style="font-family: 'Permanent Marker', cursive;"
            >
              Events
            </button>
          </div>
          <%= if @log_tab == :events do %>
            <p class="text-amber-200/40 text-sm">{length(@events)} events</p>
          <% end %>
        </div>

        <%= if @log_tab == :events do %>
          <% boundary = bookmark_boundary_index(@events) %>
          <div class="flex-1 overflow-y-auto p-3 space-y-1" id="event-log">
            <%= if @events == [] do %>
              <div class="text-amber-200/30 text-center py-8">No events yet</div>
            <% else %>
              <%= for {event, index} <- @events |> Enum.reverse() |> Enum.with_index() do %>
                <% real_index = length(@events) - 1 - index %>
                <.event_row
                  event={event}
                  index={real_index}
                  state={@state}
                  immutable={real_index <= boundary}
                />
              <% end %>
            <% end %>
          </div>
        <% else %>
          <div class="flex-1 overflow-y-auto p-3" id="bookmark-tree">
            <.bookmark_tree bookmark_id={@bookmark_id} />
          </div>
        <% end %>
      </div>

      <%!-- Right panel --%>
      <div class="w-1/2 flex flex-col">
        <%= if @log_tab == :bookmarks do %>
          <div class="flex-1 overflow-y-auto p-6">
            <h2
              class="text-xl font-bold text-amber-100 mb-4"
              style="font-family: 'Permanent Marker', cursive;"
            >
              Managing Bookmarks
            </h2>
            <div
              class="space-y-3 text-sm text-amber-200/60"
              style="font-family: 'Patrick Hand', cursive; font-size: 1.1rem; line-height: 1.6;"
            >
              <p>
                Bookmarks organize your games as a tree. Each bookmark is a snapshot of game state that can branch into new timelines.
              </p>
              <p>
                <span class="text-amber-100">Create Bookmark</span>
                —
                Click the <.icon name="hero-plus-circle" class="w-4 h-4 inline text-green-400/60" />
                button on any bookmark to create a child. The child inherits all entities, scenes, and aspects from the parent.
              </p>
              <p>
                <span class="text-amber-100">Navigate</span> —
                Click a bookmark name to open it on the table. Only leaf bookmarks (those without children) can be opened.
              </p>
              <p>
                <span class="text-amber-100">Locked bookmarks</span>
                —
                Once a bookmark has children, it becomes locked (<.icon
                  name="hero-lock-closed"
                  class="w-3.5 h-3.5 inline text-amber-400/30"
                />). Its events are immutable — they form the shared foundation for all child timelines.
              </p>
              <p>
                <span class="text-amber-100">Typical workflow</span> —
                Create entities and scenes under a prep bookmark. When ready to play, create a child bookmark for your game session. If you want to replay the same setup with different players, create another child from the same prep bookmark.
              </p>
            </div>
          </div>
        <% else %>
          <div class="p-4 border-b border-amber-900/30">
            <h2 class="text-xl font-bold" style="font-family: 'Permanent Marker', cursive;">
              Action Palette
            </h2>
          </div>

          <div class="flex-1 overflow-y-auto p-4">
            <%= if @building do %>
              <%!-- Exchange builder --%>
              <.exchange_builder
                building={@building}
                build_steps={@build_steps}
                editing_step={@editing_step}
                state={@state}
                selection={@selection}
              />
            <% else %>
              <%!-- Quick actions + exchange starters --%>
              <.action_menu state={@state} />
            <% end %>
          </div>
        <% end %>
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
      |> assign_new(:immutable, fn -> false end)

    ~H"""
    <div
      id={"event-#{@index}"}
      class={[
        "group flex items-center gap-2 px-2 py-1 rounded transition text-sm",
        if(@event.exchange_id, do: "ml-4 border-l-2 border-amber-700/20", else: ""),
        if(@immutable, do: "opacity-30", else: "hover:bg-amber-900/20")
      ]}
    >
      <div
        class="w-2 h-2 rounded-full shrink-0"
        style={"background: #{@color};"}
      />
      <span class="text-amber-200/40 text-xs shrink-0">{@index + 1}</span>
      <span class="flex-1 text-amber-100/80 truncate" style="font-family: 'Patrick Hand', cursive;">
        {@summary}
      </span>
      <%= unless @immutable do %>
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

  defp compact_event_summary(event) do
    detail = event.detail || %{}

    case event.type do
      :create_campaign ->
        "Campaign: #{detail["campaign_name"] || event.description}"

      :set_system ->
        "System: #{detail["system"] || "core"}"

      :entity_create ->
        "New #{detail["kind"] || "entity"}: #{detail["name"]}"

      :entity_modify ->
        event.description || "Edit #{detail["name"] || "entity"}"

      :entity_remove ->
        "Remove #{event.target_id}"

      :aspect_create ->
        "+ #{detail["description"]}"

      :aspect_remove ->
        desc =
          (event.description || "aspect")
          |> String.replace(~r/^(Hide|Reveal|Remove aspect): /i, "")

        "- #{desc}"

      :aspect_modify ->
        event.description || "Edit aspect"

      :aspect_compel ->
        "Compel: #{detail["aspect_id"]}"

      :skill_set ->
        "#{detail["skill"]} → +#{detail["rating"]}"

      :stunt_add ->
        "Stunt: #{detail["name"]}"

      :stunt_remove ->
        "Remove stunt"

      :scene_start ->
        "Scene: #{detail["name"]}"

      :scene_end ->
        "End scene"

      :zone_create ->
        "Zone: #{detail["name"]}"

      :zone_modify ->
        "#{if detail["hidden"] == false, do: "Reveal", else: "Hide"} zone"

      :entity_enter_scene ->
        "Enter scene"

      :entity_move ->
        "Move to zone"

      :roll_attack ->
        "Attack #{detail["skill"] || ""} #{format_dice(detail["fudge_dice"] || [])} = #{detail["raw_total"] || "?"}"

      :roll_defend ->
        "Defend #{detail["skill"] || ""} #{format_dice(detail["fudge_dice"] || [])} = #{detail["raw_total"] || "?"}"

      :roll_overcome ->
        "Overcome #{detail["skill"] || ""} #{format_dice(detail["fudge_dice"] || [])}"

      :roll_create_advantage ->
        "Advantage #{detail["skill"] || ""} #{format_dice(detail["fudge_dice"] || [])}"

      :invoke ->
        "Invoke: #{detail["description"] || detail["aspect_id"]}"

      :shifts_resolved ->
        "#{detail["shifts"] || 0} shifts — #{detail["outcome"]}"

      :redirect_hit ->
        "Redirect hit"

      :stress_apply ->
        "Stress ×#{detail["box_index"]}"

      :stress_clear ->
        "Clear stress"

      :consequence_take ->
        "#{detail["severity"]}: #{detail["aspect_text"]}"

      :consequence_recover ->
        "Recover consequence"

      :fate_point_spend ->
        "Spend FP"

      :fate_point_earn ->
        "Earn FP"

      :fate_point_refresh ->
        "Refresh FP"

      :concede ->
        "Concede"

      :taken_out ->
        "Taken out!"

      :mook_eliminate ->
        "Mook eliminated"

      _ ->
        event.description || to_string(event.type)
    end
  end

  defp exchange_builder(assigns) do
    ~H"""
    <div>
      <div class="flex items-center justify-between mb-4">
        <h3 class="text-lg font-bold" style="font-family: 'Patrick Hand', cursive;">
          Building: {exchange_label(@building)}
        </h3>
        <button phx-click="cancel_build" class="text-sm text-red-400 hover:text-red-300">
          Cancel
        </button>
      </div>

      <%!-- Available step tiles --%>
      <div class="mb-4">
        <div class="text-xs uppercase text-amber-200/40 mb-2 font-bold">Add Step</div>
        <div class="flex flex-wrap gap-2">
          <%= for step_type <- available_steps(@building) do %>
            <button
              phx-click="add_step"
              phx-value-step_type={step_type}
              class="px-3 py-2 bg-amber-900/40 border border-amber-700/30 rounded-lg
                hover:bg-amber-800/40 hover:border-amber-600/40 transition text-sm"
              style="font-family: 'Patrick Hand', cursive;"
            >
              {step_type_label(step_type)}
            </button>
          <% end %>
        </div>
      </div>

      <%!-- Build lane --%>
      <div class="mb-4">
        <div class="text-xs uppercase text-amber-200/40 mb-2 font-bold">Build Lane</div>
        <%= if @build_steps == [] do %>
          <div class="text-amber-200/20 text-sm py-4 text-center border border-dashed border-amber-700/20 rounded-lg">
            Click a step above to begin
          </div>
        <% else %>
          <div class="space-y-2">
            <%= for {step, index} <- Enum.with_index(@build_steps) do %>
              <%= if @editing_step == index do %>
                <.step_form step={step} index={index} state={@state} />
              <% else %>
                <.step_summary step={step} index={index} state={@state} />
              <% end %>
            <% end %>
          </div>
        <% end %>
      </div>

      <%!-- Commit button --%>
      <%= if @build_steps != [] && @editing_step == nil do %>
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

  defp step_summary(assigns) do
    desc = build_step_description(assigns.step, assigns.state)
    assigns = assign(assigns, :desc, desc)

    ~H"""
    <div
      class="flex items-center gap-2 px-3 py-2 bg-amber-900/30 rounded-lg border border-amber-700/20 cursor-pointer hover:bg-amber-900/40 transition"
      phx-click="edit_step"
      phx-value-index={@index}
    >
      <span class="text-xs text-amber-300/50 font-bold">{@index + 1}.</span>
      <span class="text-sm flex-1" style="font-family: 'Patrick Hand', cursive;">
        {step_type_label(@step.type)}
      </span>
      <span class="text-xs text-amber-200/40 flex-1 truncate">{@desc}</span>
      <%!-- Dice preview for rolls --%>
      <%= if roll_step?(@step.type) do %>
        <div class="flex gap-0.5">
          <%= for val <- @step.detail["fudge_dice"] || [0,0,0,0] do %>
            <span class={"w-4 h-4 rounded text-center text-xs font-bold leading-4 #{die_class(val)}"}>
              {die_display(val)}
            </span>
          <% end %>
          <span class="text-xs text-amber-200/60 ml-1 font-bold">
            {format_rating(@step.detail["raw_total"] || 0)}
          </span>
        </div>
      <% end %>
      <button
        phx-click="remove_step"
        phx-value-index={@index}
        class="text-red-400/50 hover:text-red-400 text-xs shrink-0"
      >
        ✕
      </button>
    </div>
    """
  end

  defp step_form(%{step: %{type: type}} = assigns) when type in @roll_types do
    entities = if assigns.state, do: Map.values(assigns.state.entities), else: []
    skills = actor_skills(assigns.state, assigns.step.actor_id)
    needs_target = type == :roll_attack
    needs_difficulty = type == :roll_overcome

    assigns =
      assigns
      |> assign(:entities, entities)
      |> assign(:skills, skills)
      |> assign(:needs_target, needs_target)
      |> assign(:needs_difficulty, needs_difficulty)

    ~H"""
    <div class="p-3 bg-amber-900/20 rounded-lg border border-amber-600/30 space-y-3">
      <div class="flex items-center justify-between">
        <span class="text-sm font-bold" style="font-family: 'Patrick Hand', cursive;">
          {step_type_label(@step.type)}
        </span>
        <div class="flex gap-1">
          <button
            phx-click="close_step_form"
            class="text-xs text-amber-200/50 hover:text-amber-200 px-2 py-1 bg-amber-900/40 rounded"
          >
            Done
          </button>
          <button
            phx-click="remove_step"
            phx-value-index={@index}
            class="text-xs text-red-400/50 hover:text-red-400 px-2 py-1"
          >
            ✕
          </button>
        </div>
      </div>

      <%!-- Actor --%>
      <div>
        <label class="block text-xs text-amber-200/50 mb-1">Actor</label>
        <select
          phx-change="update_step_field"
          phx-value-index={@index}
          name="actor_id"
          class="w-full px-2 py-1.5 bg-amber-900/30 border border-amber-700/30 rounded text-amber-100 text-sm"
        >
          <option value="">Select...</option>
          <%= for e <- @entities do %>
            <option value={e.id} selected={e.id == @step.actor_id}>{e.name} ({e.kind})</option>
          <% end %>
        </select>
      </div>

      <%!-- Skill --%>
      <div>
        <label class="block text-xs text-amber-200/50 mb-1">Skill</label>
        <select
          phx-change="update_step_field"
          phx-value-index={@index}
          name="skill"
          class="w-full px-2 py-1.5 bg-amber-900/30 border border-amber-700/30 rounded text-amber-100 text-sm"
        >
          <option value="">Select...</option>
          <%= for {skill, rating} <- @skills do %>
            <option value={skill} selected={skill == @step.detail["skill"]}>
              {skill} ({format_rating(rating)})
            </option>
          <% end %>
        </select>
      </div>

      <%!-- Fudge Dice --%>
      <div>
        <label class="block text-xs text-amber-200/50 mb-1">Dice</label>
        <div class="flex items-center gap-3">
          <div class="flex gap-1.5">
            <%= for {val, die_idx} <- Enum.with_index(@step.detail["fudge_dice"] || [0,0,0,0]) do %>
              <button
                phx-click="toggle_die"
                phx-value-index={@index}
                phx-value-die={die_idx}
                class={"w-8 h-8 rounded-lg border-2 font-bold text-base flex items-center justify-center transition-all cursor-pointer hover:scale-110 #{die_class(val)}"}
              >
                {die_display(val)}
              </button>
            <% end %>
          </div>
          <button
            phx-click="auto_roll_dice"
            phx-value-index={@index}
            class="px-3 py-1.5 bg-amber-700/60 hover:bg-amber-600/60 border border-amber-600/40 rounded-lg text-amber-100 text-sm font-bold transition"
          >
            <.icon name="hero-cube-transparent" class="w-4 h-4 inline -mt-0.5" /> Roll
          </button>
          <div class="text-right">
            <div
              class="text-lg font-bold text-amber-100"
              style="font-family: 'Permanent Marker', cursive;"
            >
              {format_rating(@step.detail["raw_total"] || 0)}
            </div>
            <div class="text-xs text-amber-200/30">
              dice {format_rating(Enum.sum(@step.detail["fudge_dice"] || [0, 0, 0, 0]))} + skill {format_rating(
                @step.detail["skill_rating"] || 0
              )}
            </div>
          </div>
        </div>
      </div>

      <%!-- Target (attack only) --%>
      <%= if @needs_target do %>
        <div>
          <label class="block text-xs text-amber-200/50 mb-1">Target</label>
          <select
            phx-change="update_step_field"
            phx-value-index={@index}
            name="target_id"
            class="w-full px-2 py-1.5 bg-amber-900/30 border border-amber-700/30 rounded text-amber-100 text-sm"
          >
            <option value="">Select...</option>
            <%= for e <- @entities do %>
              <option value={e.id} selected={e.id == @step.target_id}>{e.name}</option>
            <% end %>
          </select>
        </div>
      <% end %>

      <%!-- Difficulty (overcome only) --%>
      <%= if @needs_difficulty do %>
        <div>
          <label class="block text-xs text-amber-200/50 mb-1">Difficulty</label>
          <input
            type="number"
            phx-change="update_step_field"
            phx-value-index={@index}
            name="difficulty"
            value={@step.detail["difficulty"]}
            placeholder="0"
            class="w-20 px-2 py-1.5 bg-amber-900/30 border border-amber-700/30 rounded text-amber-100 text-sm"
          />
        </div>
      <% end %>
    </div>
    """
  end

  defp step_form(%{step: %{type: :invoke}} = assigns) do
    state = assigns.state

    aspects =
      if state do
        entity_aspects =
          state.entities
          |> Map.values()
          |> Enum.flat_map(fn e ->
            Enum.map(
              e.aspects,
              &%{id: &1.id, label: "#{e.name}: #{&1.description}", free_invokes: &1.free_invokes}
            )
          end)

        scene_aspects =
          state.scenes
          |> Enum.filter(&(&1.status == :active))
          |> Enum.flat_map(fn s ->
            Enum.map(
              s.aspects,
              &%{id: &1.id, label: "Scene: #{&1.description}", free_invokes: &1.free_invokes}
            ) ++
              Enum.flat_map(s.zones, fn z ->
                Enum.map(
                  z.aspects,
                  &%{
                    id: &1.id,
                    label: "#{z.name}: #{&1.description}",
                    free_invokes: &1.free_invokes
                  }
                )
              end)
          end)

        entity_aspects ++ scene_aspects
      else
        []
      end

    assigns = assign(assigns, :aspects, aspects)

    ~H"""
    <div class="p-3 bg-amber-900/20 rounded-lg border border-amber-600/30 space-y-3">
      <div class="flex items-center justify-between">
        <span class="text-sm font-bold" style="font-family: 'Patrick Hand', cursive;">
          Invoke Aspect
        </span>
        <div class="flex gap-1">
          <button
            phx-click="close_step_form"
            class="text-xs text-amber-200/50 hover:text-amber-200 px-2 py-1 bg-amber-900/40 rounded"
          >
            Done
          </button>
          <button
            phx-click="remove_step"
            phx-value-index={@index}
            class="text-xs text-red-400/50 hover:text-red-400 px-2 py-1"
          >
            ✕
          </button>
        </div>
      </div>
      <div>
        <label class="block text-xs text-amber-200/50 mb-1">Aspect</label>
        <select
          phx-change="update_step_field"
          phx-value-index={@index}
          name="description"
          class="w-full px-2 py-1.5 bg-amber-900/30 border border-amber-700/30 rounded text-amber-100 text-sm"
        >
          <option value="">Select...</option>
          <%= for a <- @aspects do %>
            <option value={a.label} selected={a.label == @step.detail["description"]}>
              {a.label} {if a.free_invokes > 0, do: "(#{a.free_invokes} free)", else: ""}
            </option>
          <% end %>
        </select>
      </div>
    </div>
    """
  end

  defp step_form(%{step: %{type: :shifts_resolved}} = assigns) do
    entities = if assigns.state, do: Map.values(assigns.state.entities), else: []
    assigns = assign(assigns, :entities, entities)

    ~H"""
    <div class="p-3 bg-amber-900/20 rounded-lg border border-amber-600/30 space-y-3">
      <div class="flex items-center justify-between">
        <span class="text-sm font-bold" style="font-family: 'Patrick Hand', cursive;">
          Resolve Shifts
        </span>
        <div class="flex gap-1">
          <button
            phx-click="close_step_form"
            class="text-xs text-amber-200/50 hover:text-amber-200 px-2 py-1 bg-amber-900/40 rounded"
          >
            Done
          </button>
          <button
            phx-click="remove_step"
            phx-value-index={@index}
            class="text-xs text-red-400/50 hover:text-red-400 px-2 py-1"
          >
            ✕
          </button>
        </div>
      </div>
      <div class="flex gap-3">
        <div>
          <label class="block text-xs text-amber-200/50 mb-1">Shifts</label>
          <input
            type="number"
            phx-change="update_step_field"
            phx-value-index={@index}
            name="shifts"
            value={@step.detail["shifts"]}
            placeholder="0"
            class="w-20 px-2 py-1.5 bg-amber-900/30 border border-amber-700/30 rounded text-amber-100 text-sm"
          />
        </div>
        <div class="flex-1">
          <label class="block text-xs text-amber-200/50 mb-1">Target</label>
          <select
            phx-change="update_step_field"
            phx-value-index={@index}
            name="target_id"
            class="w-full px-2 py-1.5 bg-amber-900/30 border border-amber-700/30 rounded text-amber-100 text-sm"
          >
            <option value="">None</option>
            <%= for e <- @entities do %>
              <option value={e.id} selected={e.id == @step.target_id}>{e.name}</option>
            <% end %>
          </select>
        </div>
      </div>
    </div>
    """
  end

  defp step_form(%{step: %{type: :consequence_take}} = assigns) do
    entities = if assigns.state, do: Map.values(assigns.state.entities), else: []
    assigns = assign(assigns, :entities, entities)

    ~H"""
    <div class="p-3 bg-amber-900/20 rounded-lg border border-amber-600/30 space-y-3">
      <div class="flex items-center justify-between">
        <span class="text-sm font-bold" style="font-family: 'Patrick Hand', cursive;">
          Take Consequence
        </span>
        <div class="flex gap-1">
          <button
            phx-click="close_step_form"
            class="text-xs text-amber-200/50 hover:text-amber-200 px-2 py-1 bg-amber-900/40 rounded"
          >
            Done
          </button>
          <button
            phx-click="remove_step"
            phx-value-index={@index}
            class="text-xs text-red-400/50 hover:text-red-400 px-2 py-1"
          >
            ✕
          </button>
        </div>
      </div>
      <div>
        <label class="block text-xs text-amber-200/50 mb-1">Entity</label>
        <select
          phx-change="update_step_field"
          phx-value-index={@index}
          name="target_id"
          class="w-full px-2 py-1.5 bg-amber-900/30 border border-amber-700/30 rounded text-amber-100 text-sm"
        >
          <option value="">Select...</option>
          <%= for e <- @entities do %>
            <option value={e.id} selected={e.id == @step.target_id}>{e.name}</option>
          <% end %>
        </select>
      </div>
      <div class="flex gap-3">
        <div>
          <label class="block text-xs text-amber-200/50 mb-1">Severity</label>
          <select
            phx-change="update_step_field"
            phx-value-index={@index}
            name="severity"
            class="px-2 py-1.5 bg-amber-900/30 border border-amber-700/30 rounded text-amber-100 text-sm"
          >
            <option value="mild" selected={@step.detail["severity"] == "mild"}>Mild (2)</option>
            <option value="moderate" selected={@step.detail["severity"] == "moderate"}>
              Moderate (4)
            </option>
            <option value="severe" selected={@step.detail["severity"] == "severe"}>Severe (6)</option>
            <option value="extreme" selected={@step.detail["severity"] == "extreme"}>
              Extreme (8)
            </option>
          </select>
        </div>
        <div class="flex-1">
          <label class="block text-xs text-amber-200/50 mb-1">Aspect Text</label>
          <input
            type="text"
            phx-change="update_step_field"
            phx-value-index={@index}
            name="aspect_text"
            value={@step.detail["aspect_text"]}
            placeholder="Broken Arm"
            class="w-full px-2 py-1.5 bg-amber-900/30 border border-amber-700/30 rounded text-amber-100 text-sm placeholder-amber-200/20"
          />
        </div>
      </div>
    </div>
    """
  end

  defp step_form(%{step: %{type: :stress_apply}} = assigns) do
    entities = if assigns.state, do: Map.values(assigns.state.entities), else: []

    target =
      assigns.step.target_id && assigns.state &&
        Map.get(assigns.state.entities, assigns.step.target_id)

    tracks = if target, do: target.stress_tracks, else: []

    assigns =
      assigns
      |> assign(:entities, entities)
      |> assign(:tracks, tracks)

    ~H"""
    <div class="p-3 bg-amber-900/20 rounded-lg border border-amber-600/30 space-y-3">
      <div class="flex items-center justify-between">
        <span class="text-sm font-bold" style="font-family: 'Patrick Hand', cursive;">
          Apply Stress
        </span>
        <div class="flex gap-1">
          <button
            phx-click="close_step_form"
            class="text-xs text-amber-200/50 hover:text-amber-200 px-2 py-1 bg-amber-900/40 rounded"
          >
            Done
          </button>
          <button
            phx-click="remove_step"
            phx-value-index={@index}
            class="text-xs text-red-400/50 hover:text-red-400 px-2 py-1"
          >
            ✕
          </button>
        </div>
      </div>
      <div>
        <label class="block text-xs text-amber-200/50 mb-1">Entity</label>
        <select
          phx-change="update_step_field"
          phx-value-index={@index}
          name="target_id"
          class="w-full px-2 py-1.5 bg-amber-900/30 border border-amber-700/30 rounded text-amber-100 text-sm"
        >
          <option value="">Select...</option>
          <%= for e <- @entities do %>
            <option value={e.id} selected={e.id == @step.target_id}>{e.name}</option>
          <% end %>
        </select>
      </div>
      <%= if @tracks != [] do %>
        <div class="flex gap-3">
          <div>
            <label class="block text-xs text-amber-200/50 mb-1">Track</label>
            <select
              phx-change="update_step_field"
              phx-value-index={@index}
              name="track_label"
              class="px-2 py-1.5 bg-amber-900/30 border border-amber-700/30 rounded text-amber-100 text-sm"
            >
              <%= for t <- @tracks do %>
                <option value={t.label} selected={t.label == @step.detail["track_label"]}>
                  {t.label}
                </option>
              <% end %>
            </select>
          </div>
          <div>
            <label class="block text-xs text-amber-200/50 mb-1">Box</label>
            <input
              type="number"
              phx-change="update_step_field"
              phx-value-index={@index}
              name="box_index"
              value={@step.detail["box_index"]}
              placeholder="1"
              min="1"
              class="w-16 px-2 py-1.5 bg-amber-900/30 border border-amber-700/30 rounded text-amber-100 text-sm"
            />
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  defp step_form(assigns) do
    ~H"""
    <div class="flex items-center gap-2 px-3 py-2 bg-amber-900/30 rounded-lg border border-amber-600/30">
      <span class="text-xs text-amber-300/50 font-bold">{@index + 1}.</span>
      <span class="text-sm flex-1" style="font-family: 'Patrick Hand', cursive;">
        {step_type_label(@step.type)}
      </span>
      <button
        phx-click="close_step_form"
        class="text-xs text-amber-200/50 hover:text-amber-200 px-2 py-1 bg-amber-900/40 rounded"
      >
        Done
      </button>
      <button
        phx-click="remove_step"
        phx-value-index={@index}
        class="text-xs text-red-400/50 hover:text-red-400 px-2 py-1"
      >
        ✕
      </button>
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
              <div class="font-bold text-sm" style="font-family: 'Permanent Marker', cursive;">
                {label}
              </div>
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
              <div class="text-xs uppercase text-amber-200/25 mt-2 mb-1 tracking-wider">
                {section}
              </div>
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
                  <span class="text-sm" style="font-family: 'Patrick Hand', cursive;">
                    {entity.name}
                  </span>
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
    all = Map.values(state.entities) |> Enum.reject(&entity_hidden?/1)
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

  defp load_events_for_role(bookmark_id, true = _is_gm) do
    case Ash.get(Fate.Game.Bookmark, bookmark_id, not_found_error?: false) do
      {:ok, %{head_event_id: head_id}} when head_id != nil ->
        case Engine.load_event_chain(head_id) do
          {:ok, events} -> events
          _ -> []
        end

      _ ->
        []
    end
  end

  defp load_events_for_role(bookmark_id, false = _is_gm) do
    case Engine.load_player_events(bookmark_id) do
      {:ok, events} -> events
      _ -> []
    end
  end

  defp bookmark_tree(assigns) do
    require Ash.Query

    bookmarks =
      case Ash.read(
             Fate.Game.Bookmark
             |> Ash.Query.filter(status: :active)
             |> Ash.Query.sort(created_at: :asc)
           ) do
        {:ok, bms} -> bms
        _ -> []
      end

    top_level = Enum.filter(bookmarks, &is_nil(&1.parent_bookmark_id))
    children_map = Enum.group_by(bookmarks, & &1.parent_bookmark_id)

    assigns = assigns |> assign(:top_level, top_level) |> assign(:children_map, children_map)

    ~H"""
    <%= if @top_level == [] do %>
      <div class="text-amber-200/30 text-center py-8">No bookmarks yet</div>
    <% else %>
      <div class="space-y-1">
        <%= for bm <- @top_level do %>
          <.bookmark_node
            bookmark={bm}
            children_map={@children_map}
            current_id={@bookmark_id}
            depth={0}
          />
        <% end %>
      </div>
    <% end %>
    """
  end

  defp bookmark_node(assigns) do
    children = Map.get(assigns.children_map, assigns.bookmark.id, [])
    has_children = children != []
    assigns = assigns |> assign(:children, children) |> assign(:has_children, has_children)

    ~H"""
    <div style={"margin-left: #{@depth * 16}px;"}>
      <div class={[
        "flex items-center gap-2 px-2 py-1.5 rounded transition text-sm",
        if(@bookmark.id == @current_id,
          do: "bg-amber-800/40 border border-amber-600/30",
          else: "hover:bg-amber-900/20"
        )
      ]}>
        <%= if @has_children do %>
          <.icon name="hero-lock-closed" class="w-3.5 h-3.5 text-amber-400/30 shrink-0" />
          <span
            class="flex-1 text-amber-200/40 truncate"
            style="font-family: 'Patrick Hand', cursive;"
          >
            {@bookmark.name}
          </span>
        <% else %>
          <.icon name="hero-bookmark" class="w-3.5 h-3.5 text-amber-400/60 shrink-0" />
          <.link
            navigate={~p"/table/#{@bookmark.id}"}
            class="flex-1 text-amber-100 truncate hover:text-amber-200"
            style="font-family: 'Patrick Hand', cursive;"
          >
            {@bookmark.name}
          </.link>
        <% end %>
        <button
          phx-click="fork_bookmark"
          phx-value-bookmark-id={@bookmark.id}
          class="text-xs text-green-400/40 hover:text-green-300 transition shrink-0"
          data-tooltip="Create Bookmark"
        >
          <.icon name="hero-plus-circle" class="w-3.5 h-3.5" />
        </button>
        <span class="text-xs text-amber-200/25 shrink-0">
          {Calendar.strftime(@bookmark.created_at, "%b %d")}
        </span>
      </div>
      <%= for child <- @children do %>
        <.bookmark_node
          bookmark={child}
          children_map={@children_map}
          current_id={@current_id}
          depth={@depth + 1}
        />
      <% end %>
    </div>
    """
  end

  defp bookmark_boundary_index(events) do
    events
    |> Enum.with_index()
    |> Enum.reduce(-1, fn {event, index}, acc ->
      if event.type == :bookmark_create, do: index, else: acc
    end)
  end

  defp entity_color(nil, _), do: "#6b7280"
  defp entity_color(_state, nil), do: "#6b7280"

  defp entity_color(state, entity_id) do
    case Map.get(state.entities, entity_id) do
      nil -> "#6b7280"
      entity -> entity.color || "#6b7280"
    end
  end

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
    [
      :roll_attack,
      :roll_defend,
      :invoke,
      :shifts_resolved,
      :stress_apply,
      :consequence_take,
      :redirect_hit,
      :concede,
      :taken_out
    ]
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
      {"entity_create", "Create Entity"},
      {"entity_edit", "Edit Entity"},
      {"skill_set", "Set Skill"},
      {"stunt_add", "Add Stunt"},
      {"stunt_remove", "Remove Stunt"},
      {"set_system", "Set System"},
      {"scene_modify", "Edit Scene"}
    ]
  end

  defp broadcast_exchange(socket) do
    if socket.assigns.bookmark_id do
      Phoenix.PubSub.broadcast(
        Fate.PubSub,
        "exchange:#{socket.assigns.bookmark_id}",
        {:exchange_updated,
         %{building: socket.assigns.building, build_steps: socket.assigns.build_steps}}
      )
    end
  end

  defp put_non_empty(map, _key, nil), do: map
  defp put_non_empty(map, _key, ""), do: map
  defp put_non_empty(map, key, val), do: Map.put(map, key, val)

  defp maybe_put_int(map, _key, nil), do: map
  defp maybe_put_int(map, _key, ""), do: map
  defp maybe_put_int(map, key, val), do: Map.put(map, key, parse_int(val))

  defp entity_hidden?(entity), do: entity.hidden

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
          <.modal_fields
            modal={@modal}
            entities={@entities}
            state={@state}
            prefill_entity_id={@prefill_entity_id}
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

  defp modal_title("aspect_create"), do: "Create Aspect"
  defp modal_title("aspect_compel"), do: "Compel Aspect"
  defp modal_title("entity_move"), do: "Move Entity"
  defp modal_title("scene_start"), do: "Start Scene"
  defp modal_title("scene_end"), do: "End Scene"
  defp modal_title("fate_point_spend"), do: "Spend Fate Point"
  defp modal_title("fate_point_earn"), do: "Earn Fate Point"
  defp modal_title("fate_point_refresh"), do: "Refresh Fate Points"
  defp modal_title("entity_create"), do: "Create Entity"
  defp modal_title("entity_edit"), do: "Edit Entity"
  defp modal_title("skill_set"), do: "Set Skill"
  defp modal_title("stunt_add"), do: "Add Stunt"
  defp modal_title("stunt_remove"), do: "Remove Stunt"
  defp modal_title("set_system"), do: "Set System"
  defp modal_title("scene_modify"), do: "Edit Scene"
  defp modal_title("fork_bookmark"), do: "Create Bookmark"
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

    entity_options =
      Enum.map(assigns.entities, fn e -> {"entity:#{e.id}", "#{e.name} (#{e.kind})"} end)

    all_options = scene_and_zone_options ++ entity_options

    prefill =
      if assigns.prefill_entity_id, do: "entity:#{assigns.prefill_entity_id}", else: nil

    assigns =
      assigns
      |> assign(:all_options, all_options)
      |> assign(:prefill, prefill)

    ~H"""
    <div>
      <label class="block text-sm text-amber-200/70 mb-1">On</label>
      <select
        name="target_ref"
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
    />
    <.select_input
      name="role"
      label="Role"
      options={[
        {"situation", "Situation"},
        {"boost", "Boost"},
        {"additional", "Additional"},
        {"high_concept", "High Concept"},
        {"trouble", "Trouble"}
      ]}
    />
    <label class="flex items-center gap-2 text-sm text-amber-200/70">
      <input type="checkbox" name="hidden" value="true" class="rounded" /> Hidden from players
    </label>
    """
  end

  defp modal_fields(%{modal: "entity_create"} = assigns) do
    parent_options =
      if assigns.state do
        assigns.state.entities
        |> Map.values()
        |> Enum.sort_by(& &1.name)
        |> Enum.map(fn e -> {e.id, "#{e.name} (#{e.kind})"} end)
      else
        []
      end

    assigns = assign(assigns, :parent_options, parent_options)

    ~H"""
    <.text_input name="name" label="Name" placeholder="Character name" />
    <.select_input
      name="kind"
      label="Kind"
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
    <.text_input name="color" label="Color" placeholder="#dc2626" />
    <.text_input name="fate_points" label="Fate Points" placeholder="3" />
    <.text_input name="refresh" label="Refresh" placeholder="3" />
    <div>
      <label class="block text-sm text-amber-200/70 mb-1">Parent Entity (optional)</label>
      <select
        name="parent_entity_id"
        class="w-full px-3 py-2 bg-amber-900/30 border border-amber-700/30 rounded-lg text-amber-100 text-sm"
      >
        <option value="">None</option>
        <%= for {id, label} <- @parent_options do %>
          <option value={id}>{label}</option>
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
      />
    </div>
    """
  end

  defp modal_fields(%{modal: "scene_start"} = assigns) do
    ~H"""
    <.text_input name="name" label="Scene Name" placeholder="Dockside Warehouse" />
    <.text_input
      name="scene_description"
      label="Description"
      placeholder="A brief framing of the scene"
    />
    <div>
      <label class="block text-sm text-amber-200/70 mb-1">GM Notes</label>
      <textarea
        name="gm_notes"
        placeholder="Private prep notes..."
        class="w-full px-3 py-2 bg-amber-900/30 border border-amber-700/30 rounded-lg text-amber-100 text-sm placeholder-amber-200/20"
        rows="3"
      />
    </div>
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

  defp modal_fields(%{modal: modal} = assigns)
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
    <.entity_select
      name="entity_id"
      label="Entity"
      entities={@entities}
      selected={@prefill_entity_id}
    />
    <div>
      <label class="block text-sm text-amber-200/70 mb-1">To Zone</label>
      <select
        name="zone_id"
        class="w-full px-3 py-2 bg-amber-900/30 border border-amber-700/30 rounded-lg text-amber-100 text-sm"
      >
        <%= for zone <- @zones do %>
          <option value={zone.id}>{zone.name}</option>
        <% end %>
      </select>
    </div>
    """
  end

  defp modal_fields(%{modal: "aspect_compel"} = assigns) do
    ~H"""
    <.entity_select
      name="target_id"
      label="Target Entity"
      entities={@entities}
      selected={@prefill_entity_id}
    />
    <.text_input
      name="description"
      label="Compel Description"
      placeholder="What complication does this cause?"
    />
    """
  end

  defp modal_fields(%{modal: "entity_edit"} = assigns) do
    ~H"""
    <.entity_select
      name="entity_id"
      label="Entity"
      entities={@entities}
      selected={@prefill_entity_id}
    />
    <.text_input name="name" label="Name" placeholder="New name" />
    <.select_input
      name="kind"
      label="Kind"
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
    <.text_input name="color" label="Color" placeholder="#dc2626" />
    <.text_input name="fate_points" label="Fate Points" placeholder="" />
    <.text_input name="refresh" label="Refresh" placeholder="" />
    """
  end

  defp modal_fields(%{modal: "skill_set"} = assigns) do
    skill_list = if assigns.state, do: assigns.state.skill_list, else: []

    assigns = assign(assigns, :skill_list, skill_list)

    ~H"""
    <.entity_select
      name="entity_id"
      label="Entity"
      entities={@entities}
      selected={@prefill_entity_id}
    />
    <div>
      <label class="block text-sm text-amber-200/70 mb-1">Skill</label>
      <select
        name="skill"
        class="w-full px-3 py-2 bg-amber-900/30 border border-amber-700/30 rounded-lg text-amber-100 text-sm"
      >
        <%= for skill <- @skill_list do %>
          <option value={skill}>{skill}</option>
        <% end %>
      </select>
    </div>
    <.text_input name="rating" label="Rating" placeholder="2" />
    """
  end

  defp modal_fields(%{modal: "stunt_add"} = assigns) do
    ~H"""
    <.entity_select
      name="entity_id"
      label="Entity"
      entities={@entities}
      selected={@prefill_entity_id}
    />
    <.text_input name="name" label="Stunt Name" placeholder="Master Swordswoman" />
    <.text_input name="effect" label="Effect" placeholder="+2 to Fight when dueling one-on-one" />
    """
  end

  defp modal_fields(%{modal: "stunt_remove"} = assigns) do
    stunts =
      if assigns.state do
        assigns.state.entities
        |> Map.values()
        |> Enum.flat_map(fn e ->
          Enum.map(e.stunts, fn s -> {s.id, "#{e.name}: #{s.name}"} end)
        end)
      else
        []
      end

    assigns = assign(assigns, :stunts, stunts)

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
        <%= for {id, label} <- @stunts do %>
          <option value={id}>{label}</option>
        <% end %>
      </select>
    </div>
    """
  end

  defp modal_fields(%{modal: "set_system"} = assigns) do
    ~H"""
    <.select_input
      name="system"
      label="System"
      options={[
        {"core", "Fate Core"},
        {"accelerated", "Fate Accelerated (FAE)"}
      ]}
    />
    """
  end

  defp modal_fields(%{modal: "scene_modify"} = assigns) do
    scenes =
      if assigns.state,
        do: Enum.filter(assigns.state.scenes, &(&1.status == :active)),
        else: []

    assigns = assign(assigns, :scenes, scenes)

    ~H"""
    <div>
      <label class="block text-sm text-amber-200/70 mb-1">Scene</label>
      <select
        name="scene_id"
        class="w-full px-3 py-2 bg-amber-900/30 border border-amber-700/30 rounded-lg text-amber-100 text-sm"
      >
        <%= for scene <- @scenes do %>
          <option value={scene.id}>{scene.name}</option>
        <% end %>
      </select>
    </div>
    <.text_input name="name" label="Name" placeholder="Scene name" />
    <.text_input
      name="scene_description"
      label="Description"
      placeholder="Scene description"
    />
    <div>
      <label class="block text-sm text-amber-200/70 mb-1">GM Notes</label>
      <textarea
        name="gm_notes"
        placeholder="Private prep notes..."
        class="w-full px-3 py-2 bg-amber-900/30 border border-amber-700/30 rounded-lg text-amber-100 text-sm placeholder-amber-200/20"
        rows="3"
      />
    </div>
    """
  end

  defp modal_fields(%{modal: "fork_bookmark"} = assigns) do
    ~H"""
    <.text_input name="name" label="Bookmark Name" placeholder="My Fork" />
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
      <select
        name={@name}
        class="w-full px-3 py-2 bg-amber-900/30 border border-amber-700/30 rounded-lg text-amber-100 text-sm"
      >
        <%= for entity <- @entities do %>
          <option value={entity.id} selected={entity.id == @selected}>
            {entity.name} ({entity.kind})
          </option>
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
      <select
        name={@name}
        class="w-full px-3 py-2 bg-amber-900/30 border border-amber-700/30 rounded-lg text-amber-100 text-sm"
      >
        <%= for {value, label} <- @options do %>
          <option value={value}>{label}</option>
        <% end %>
      </select>
    </div>
    """
  end

  # --- Step form helpers ---

  defp step_type_label(type), do: Map.get(@event_type_labels, type, to_string(type))

  defp default_step_detail(type) when type in @roll_types do
    %{
      "skill" => nil,
      "skill_rating" => 0,
      "fudge_dice" => [0, 0, 0, 0],
      "raw_total" => 0,
      "difficulty" => nil
    }
  end

  defp default_step_detail(:invoke),
    do: %{"aspect_id" => nil, "description" => nil, "free" => true}

  defp default_step_detail(:shifts_resolved), do: %{"shifts" => 0, "outcome" => nil}
  defp default_step_detail(:stress_apply), do: %{"track_label" => nil, "box_index" => nil}
  defp default_step_detail(:consequence_take), do: %{"severity" => "mild", "aspect_text" => nil}
  defp default_step_detail(_), do: %{}

  defp maybe_update_field(step, params, param_key, struct_key) do
    case params[param_key] do
      nil -> step
      "" -> Map.put(step, struct_key, nil)
      val -> Map.put(step, struct_key, val)
    end
  end

  defp parse_step_value("skill_rating", val), do: parse_int_or(val, 0)
  defp parse_step_value("difficulty", val), do: parse_int_or(val, nil)
  defp parse_step_value("shifts", val), do: parse_int_or(val, 0)
  defp parse_step_value("box_index", val), do: parse_int_or(val, nil)
  defp parse_step_value(_, val), do: val

  defp parse_int_or(nil, default), do: default
  defp parse_int_or("", default), do: default

  defp parse_int_or(val, default) when is_binary(val) do
    case Integer.parse(val) do
      {n, _} -> n
      :error -> default
    end
  end

  defp parse_int_or(val, _default) when is_integer(val), do: val

  defp roll_step?(type), do: type in @roll_types

  defp actor_skills(state, actor_id) do
    case state && actor_id && Map.get(state.entities, actor_id) do
      nil -> []
      entity -> entity.skills |> Enum.sort_by(&elem(&1, 1), :desc)
    end
  end

  defp format_rating(n) when is_integer(n) and n >= 0, do: "+#{n}"
  defp format_rating(n) when is_integer(n), do: "#{n}"
  defp format_rating(_), do: "+0"

  defp die_display(1), do: "+"
  defp die_display(-1), do: "−"
  defp die_display(_), do: " "

  defp die_class(1), do: "bg-green-700 text-green-100 border-green-600"
  defp die_class(-1), do: "bg-red-700 text-red-100 border-red-600"
  defp die_class(_), do: "bg-gray-600 text-gray-300 border-gray-500"

  defp build_step_description(step, _state) do
    case step.type do
      type when type in @roll_types ->
        action = type |> to_string() |> String.replace("roll_", "")
        skill = step.detail["skill"] || "?"
        dice = step.detail["fudge_dice"] || []
        total = step.detail["raw_total"] || 0
        dice_str = dice |> Enum.map(&die_display/1) |> Enum.join("")
        "#{String.capitalize(action)} #{skill} [#{dice_str}] = #{format_rating(total)}"

      :invoke ->
        desc = step.detail["description"] || "aspect"
        if step.detail["free"], do: "Invoke: #{desc} (free)", else: "Invoke: #{desc} (FP)"

      :shifts_resolved ->
        shifts = step.detail["shifts"] || 0
        outcome = step.detail["outcome"] || ""
        "#{shifts} shifts — #{outcome}"

      :stress_apply ->
        track = step.detail["track_label"] || "?"
        box = step.detail["box_index"] || "?"
        "Stress #{track} box #{box}"

      :consequence_take ->
        sev = step.detail["severity"] || "mild"
        text = step.detail["aspect_text"] || "?"
        "#{sev}: #{text}"

      _ ->
        to_string(step.type)
    end
  end
end
