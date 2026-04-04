defmodule FateWeb.PlayerPanelLive do
  use FateWeb, :live_view

  alias Fate.Engine
  alias Fate.Engine.Replay

  import FateWeb.ActionComponents
  import FateWeb.ActionHelpers
  import FateWeb.ExchangeComponents

  defp modal_for_event_type(:entity_modify), do: "entity_edit"
  defp modal_for_event_type(:note), do: "edit_note"
  defp modal_for_event_type(type), do: Atom.to_string(type)

  @impl true
  def mount(_params, session, socket) do
    identity = FateWeb.Helpers.identify(socket)

    if connected?(socket) && is_nil(identity.role) do
      {:ok, push_navigate(socket, to: ~p"/")}
    else
      socket =
        socket
        |> assign(:bookmark_id, session["bookmark_id"])
        |> assign(:events, [])
        |> assign(:invalid_event_ids, MapSet.new())
        |> assign(:state, nil)
        |> assign(:participants, [])
        |> assign(:is_gm, identity.is_gm)
        |> assign(:is_observer, identity.is_observer)
        |> assign(:current_participant_id, identity.participant_id)
        |> assign(:selection, [])
        |> assign(:building, nil)
        |> assign(:build_steps, [])
        |> assign(:editing_step, nil)
        |> assign(:modal, nil)
        |> assign(:form_data, %{})
        |> assign(:prefill_entity_id, nil)
        |> assign(:splash_visible, !session["embedded"])

      {:ok, socket}
    end
  end

  @impl true
  def handle_params(%{"bookmark_id" => bookmark_id}, _uri, socket) do
    if connected?(socket) do
      subscribe_all(bookmark_id, socket.assigns.current_participant_id)

      with {:ok, state} <- Engine.derive_state(bookmark_id) do
        events = load_events_for_role(bookmark_id, socket.assigns.is_gm)
        participants = Fate.Game.Bookmarks.load_participants(bookmark_id)

        {:noreply,
         socket
         |> assign(:bookmark_id, bookmark_id)
         |> assign(:events, events)
         |> assign(:invalid_event_ids, Replay.validate_chain(events))
         |> assign(:participants, participants)
         |> assign(:state, state)
         |> push_event("splash_dismiss", %{})}
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

  def handle_params(_params, _uri, socket) do
    bookmark_id = socket.assigns.bookmark_id

    if connected?(socket) && bookmark_id do
      subscribe_all(bookmark_id, socket.assigns.current_participant_id)

      with {:ok, state} <- Engine.derive_state(bookmark_id) do
        events = load_events_for_role(bookmark_id, socket.assigns.is_gm)
        participants = Fate.Game.Bookmarks.load_participants(bookmark_id)

        {:noreply,
         socket
         |> assign(:events, events)
         |> assign(:invalid_event_ids, Replay.validate_chain(events))
         |> assign(:participants, participants)
         |> assign(:state, state)}
      else
        _ -> {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:state_updated, state}, socket) do
    events = load_events_for_role(socket.assigns.bookmark_id, socket.assigns.is_gm)

    {:noreply,
     socket
     |> assign(:state, state)
     |> assign(:events, events)
     |> assign(:invalid_event_ids, Replay.validate_chain(events))}
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

  # --- Events ---

  @impl true
  def handle_event("splash_done", _params, socket) do
    {:noreply, assign(socket, :splash_visible, false)}
  end

  def handle_event("start_exchange", %{"type" => type} = params, socket) do
    type = String.to_existing_atom(type)

    socket =
      socket
      |> assign(:building, type)
      |> assign(:build_steps, [])
      |> assign(:prefill_entity_id, params["entity_id"])

    FateWeb.Helpers.broadcast_exchange(socket)
    {:noreply, socket}
  end

  def handle_event("cancel_build", _params, socket) do
    socket =
      socket |> assign(:building, nil) |> assign(:build_steps, []) |> assign(:editing_step, nil)

    FateWeb.Helpers.broadcast_exchange(socket)
    {:noreply, socket}
  end

  def handle_event("add_step", %{"step_type" => step_type} = params, socket) do
    type = String.to_existing_atom(step_type)
    prefill_actor = socket.assigns.prefill_entity_id

    step = %{
      type: type,
      actor_id: prefill_actor,
      target_id: nil,
      detail: default_step_detail(type),
      description: ""
    }

    {steps, new_index} =
      case params["position"] do
        pos when is_binary(pos) ->
          {idx, _} = Integer.parse(pos)
          idx = min(idx, length(socket.assigns.build_steps))
          {List.insert_at(socket.assigns.build_steps, idx, step), idx}

        _ ->
          idx = length(socket.assigns.build_steps)
          {socket.assigns.build_steps ++ [step], idx}
      end

    socket =
      socket
      |> assign(:build_steps, steps)
      |> assign(:editing_step, new_index)

    FateWeb.Helpers.broadcast_exchange(socket)
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
    FateWeb.Helpers.broadcast_exchange(socket)
    {:noreply, socket}
  end

  def handle_event("reorder_step", %{"from" => from_str, "to" => to_str}, socket) do
    {from, _} = Integer.parse(from_str)
    {to, _} = Integer.parse(to_str)
    steps = socket.assigns.build_steps

    if from == to or from < 0 or from >= length(steps) do
      {:noreply, socket}
    else
      step = Enum.at(steps, from)
      steps = List.delete_at(steps, from)
      to = min(to, length(steps))
      steps = List.insert_at(steps, to, step)

      editing = socket.assigns.editing_step

      editing =
        cond do
          editing == nil -> nil
          editing == from -> to
          from < editing and editing <= to -> editing - 1
          to <= editing and editing < from -> editing + 1
          true -> editing
        end

      socket = socket |> assign(:build_steps, steps) |> assign(:editing_step, editing)
      FateWeb.Helpers.broadcast_exchange(socket)
      {:noreply, socket}
    end
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
              "" -> acc
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
        FateWeb.Helpers.broadcast_exchange(socket)
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
        FateWeb.Helpers.broadcast_exchange(socket)
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
        FateWeb.Helpers.broadcast_exchange(socket)
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

    FateWeb.Helpers.broadcast_exchange(socket)
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

  def handle_event("edit_event", %{"id" => event_id}, socket) do
    event = Enum.find(socket.assigns.events, &(&1.id == event_id))

    if event && editable_type?(event.type) do
      form_data = build_edit_form_data(event)
      modal = modal_for_event_type(event.type)

      prefill_entity_id =
        case event.type do
          t when t in ~w(entity_modify skill_set stunt_add stunt_remove
            fate_point_spend fate_point_earn fate_point_refresh entity_move)a ->
            form_data["entity_id"]

          :aspect_create ->
            detail = event.detail || %{}
            if detail["target_type"] == "entity", do: detail["target_id"] || event.target_id

          _ ->
            socket.assigns.prefill_entity_id
        end

      {:noreply,
       socket
       |> assign(:modal, modal)
       |> assign(:form_data, form_data)
       |> assign(:prefill_entity_id, prefill_entity_id)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("close_modal", _params, socket) do
    {:noreply,
     socket |> assign(:modal, nil) |> assign(:form_data, %{}) |> assign(:prefill_entity_id, nil)}
  end

  def handle_event("modal_form_changed", params, socket) do
    socket =
      case socket.assigns.modal do
        modal
        when modal in ~w(entity_edit skill_set stunt_add stunt_remove entity_move
          fate_point_spend fate_point_earn fate_point_refresh) ->
          if params["entity_id"] && params["entity_id"] != "" do
            assign(socket, :prefill_entity_id, params["entity_id"])
          else
            socket
          end

        _ ->
          socket
      end

    {:noreply, socket}
  end

  def handle_event("submit_modal", params, socket) do
    result =
      case socket.assigns.modal do
        "aspect_create" ->
          {target_type, target_id} =
            case FateWeb.Helpers.parse_target_ref(params["target_ref"]) do
              {nil, nil} -> {"entity", params["target_id"]}
              result -> result
            end

          create_or_update_event(
            params,
            %{
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
            },
            socket.assigns.bookmark_id
          )

        "aspect_compel" ->
          target_entity =
            if socket.assigns.state && params["target_id"],
              do: Map.get(socket.assigns.state.entities, params["target_id"]),
              else: nil

          target_name = if target_entity, do: target_entity.name, else: "entity"
          compel_actor_id = if params["actor_id"] != "", do: params["actor_id"]

          create_or_update_event(
            params,
            %{
              type: :aspect_compel,
              actor_id: compel_actor_id,
              target_id: params["target_id"],
              description: "Compel #{target_name}: #{params["description"]}",
              detail: %{
                "aspect_id" => params["aspect_id"],
                "description" => params["description"],
                "accepted" => params["accepted"] != "false"
              }
            },
            socket.assigns.bookmark_id
          )

        "entity_move" ->
          zone_name =
            if socket.assigns.state do
              socket.assigns.state.scenes
              |> Enum.flat_map(& &1.zones)
              |> Enum.find(&(&1.id == params["zone_id"]))
              |> case do
                nil -> "zone"
                z -> z.name
              end
            else
              "zone"
            end

          create_or_update_event(
            params,
            %{
              type: :entity_move,
              actor_id: params["entity_id"],
              description: "Move to #{zone_name}",
              detail: %{"entity_id" => params["entity_id"], "zone_id" => params["zone_id"]}
            },
            socket.assigns.bookmark_id
          )

        "scene_start" ->
          create_or_update_event(
            params,
            %{
              type: :scene_start,
              description: "Start scene: #{params["name"]}",
              detail: %{
                "scene_id" => params["scene_id"] || Ash.UUID.generate(),
                "name" => params["name"],
                "description" => params["scene_description"],
                "gm_notes" => params["gm_notes"]
              }
            },
            socket.assigns.bookmark_id
          )

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
          create_or_update_event(
            params,
            %{
              type: :fate_point_spend,
              target_id: params["entity_id"],
              description: "Spend fate point",
              detail: %{"entity_id" => params["entity_id"], "amount" => 1}
            },
            socket.assigns.bookmark_id
          )

        "fate_point_earn" ->
          create_or_update_event(
            params,
            %{
              type: :fate_point_earn,
              target_id: params["entity_id"],
              description: "Earn fate point",
              detail: %{"entity_id" => params["entity_id"], "amount" => 1}
            },
            socket.assigns.bookmark_id
          )

        "fate_point_refresh" ->
          create_or_update_event(
            params,
            %{
              type: :fate_point_refresh,
              target_id: params["entity_id"],
              description: "Refresh fate points",
              detail: %{"entity_id" => params["entity_id"]}
            },
            socket.assigns.bookmark_id
          )

        "entity_create" ->
          controller_id = if params["controller_id"] != "", do: params["controller_id"]

          color =
            if controller_id do
              bp = Enum.find(socket.assigns.participants, &(&1.participant_id == controller_id))
              if bp, do: bp.participant.color, else: "#6b7280"
            else
              "#6b7280"
            end

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

          create_or_update_event(
            params,
            %{
              type: :entity_create,
              description: "Create #{params["name"]}",
              detail: detail
            },
            socket.assigns.bookmark_id
          )

        "entity_edit" ->
          edit_controller_id = if params["controller_id"] != "", do: params["controller_id"]

          edit_color =
            if edit_controller_id do
              bp =
                Enum.find(socket.assigns.participants, &(&1.participant_id == edit_controller_id))

              if bp, do: bp.participant.color, else: nil
            end

          detail =
            %{"entity_id" => params["entity_id"]}
            |> put_non_empty("name", params["name"])
            |> put_non_empty("kind", params["kind"])
            |> put_non_empty("color", edit_color)
            |> put_non_empty("controller_id", edit_controller_id)
            |> maybe_put_int("fate_points", params["fate_points"])
            |> maybe_put_int("refresh", params["refresh"])

          create_or_update_event(
            params,
            %{
              type: :entity_modify,
              target_id: params["entity_id"],
              description: "Edit #{params["name"] || "entity"}",
              detail: detail
            },
            socket.assigns.bookmark_id
          )

        "skill_set" ->
          create_or_update_event(
            params,
            %{
              type: :skill_set,
              target_id: params["entity_id"],
              description: "#{params["skill"]} → +#{params["rating"]}",
              detail: %{
                "entity_id" => params["entity_id"],
                "skill" => params["skill"],
                "rating" => parse_int(params["rating"]) || 0
              }
            },
            socket.assigns.bookmark_id
          )

        "stunt_add" ->
          create_or_update_event(
            params,
            %{
              type: :stunt_add,
              target_id: params["entity_id"],
              description: "Stunt: #{params["name"]}",
              detail: %{
                "entity_id" => params["entity_id"],
                "stunt_id" => params["stunt_id"] || Ash.UUID.generate(),
                "name" => params["name"],
                "effect" => params["effect"]
              }
            },
            socket.assigns.bookmark_id
          )

        "stunt_remove" ->
          create_or_update_event(
            params,
            %{
              type: :stunt_remove,
              target_id: params["entity_id"],
              description: "Remove stunt",
              detail: %{
                "entity_id" => params["entity_id"],
                "stunt_id" => params["stunt_id"]
              }
            },
            socket.assigns.bookmark_id
          )

        "set_system" ->
          create_or_update_event(
            params,
            %{
              type: :set_system,
              description: "Set system: #{params["system"]}",
              detail: %{"system" => params["system"]}
            },
            socket.assigns.bookmark_id
          )

        "scene_modify" ->
          detail =
            %{"scene_id" => params["scene_id"]}
            |> put_non_empty("name", params["name"])
            |> put_non_empty("description", params["scene_description"])
            |> put_non_empty("gm_notes", params["gm_notes"])

          create_or_update_event(
            params,
            %{
              type: :scene_modify,
              description: "Edit scene",
              detail: detail
            },
            socket.assigns.bookmark_id
          )

        modal when modal in ~w(note edit_note) ->
          text = String.trim(params["text"] || "")

          if text != "" do
            {target_type, target_id} = FateWeb.Helpers.parse_target_ref(params["target_ref"])

            detail =
              %{"text" => text}
              |> then(fn d ->
                if target_id,
                  do: Map.merge(d, %{"target_id" => target_id, "target_type" => target_type}),
                  else: d
              end)

            create_or_update_event(
              params,
              %{
                type: :note,
                target_id: target_id,
                description: text,
                detail: detail
              },
              socket.assigns.bookmark_id
            )
          else
            {:error, "Note text is required"}
          end

        _ ->
          {:error, "Unknown modal type"}
      end

    case result do
      {:ok, _state, _event} ->
        {:noreply,
         socket
         |> assign(:modal, nil)
         |> assign(:form_data, %{})
         |> assign(:prefill_entity_id, nil)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, inspect(reason))}
    end
  end

  def handle_event(
        "reorder_event",
        %{"event_id" => event_id, "after_event_id" => after_event_id},
        socket
      ) do
    bookmark_id = socket.assigns.bookmark_id
    after_id = if after_event_id == "", do: nil, else: after_event_id

    case Fate.Game.Events.reorder(event_id, after_id, bookmark_id) do
      :ok -> {:noreply, refresh_events_and_state(socket)}
      {:error, _reason} -> {:noreply, put_flash(socket, :error, "Could not reorder event")}
    end
  end

  def handle_event("delete_event", %{"id" => event_id}, socket) do
    bookmark_id = socket.assigns.bookmark_id

    case Fate.Game.Events.delete(event_id, bookmark_id) do
      :ok ->
        {:noreply, refresh_events_and_state(socket)}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Cannot delete: other events depend on this one")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col h-screen relative" style="background: #1a1410; color: #e8dcc8;">
      <%= if @splash_visible do %>
        <div
          id="splash-player"
          class="absolute inset-0 z-[100] flex items-center justify-center"
          style="background: #1a1410;"
          phx-hook=".Splash"
          phx-update="ignore"
        >
          <img
            src={~p"/images/fateble_logo.png"}
            alt="Fateble"
            class="w-48 h-48 object-contain drop-shadow-2xl"
          />
        </div>
      <% end %>

      <%= unless @is_observer do %>
        <.action_modal
          modal={@modal}
          state={@state}
          prefill_entity_id={@prefill_entity_id}
          form_data={@form_data}
          participants={@participants}
        />
      <% end %>

      <%!-- Event log header --%>
      <div class="p-4 border-b border-amber-900/30 flex items-center justify-between">
        <h2
          class="text-lg font-bold text-amber-100"
          style="font-family: 'Permanent Marker', cursive;"
        >
          Events
        </h2>
        <span class="text-amber-200/40 text-sm">{length(@events)} events</span>
      </div>

      <%!-- Event log (chat order: oldest at top, newest at bottom) --%>
      <% boundary = bookmark_boundary_index(@events) %>
      <% my_entity_ids = my_controlled_entity_ids(@state, @current_participant_id) %>
      <div
        class="flex-1 min-h-0 overflow-y-auto p-3 space-y-1"
        id="event-log"
        phx-hook=".EventAutoScroll"
      >
        <%= if @events == [] do %>
          <div class="text-amber-200/30 text-center py-8">No events yet</div>
        <% else %>
          <div
            id="event-log-items"
            phx-hook={if(@is_gm && !@is_observer, do: "EventReorder")}
          >
            <%= for {event, index} <- Enum.with_index(@events) do %>
              <.event_row
                event={event}
                index={index}
                state={@state}
                immutable={index <= boundary}
                is_observer={@is_observer}
                is_gm={@is_gm}
                invalid={MapSet.member?(@invalid_event_ids, event.id)}
                my_entity_ids={my_entity_ids}
              />
            <% end %>
          </div>
        <% end %>
      </div>

      <%!-- Action palette / Exchange builder --%>
      <div class="shrink-0 border-t border-amber-900/30">
        <div class="p-4 border-b border-amber-900/30">
          <h2
            class="text-lg font-bold text-amber-100"
            style="font-family: 'Permanent Marker', cursive;"
          >
            Action Palette
          </h2>
        </div>

        <div class="p-4">
          <%= if @building do %>
            <.exchange_builder
              building={@building}
              build_steps={@build_steps}
              editing_step={@editing_step}
              state={@state}
              selection={@selection}
              is_observer={@is_observer}
            />
          <% else %>
            <%= if @is_observer do %>
              <div class="text-amber-200/30 text-center py-4">
                Observing — actions are disabled
              </div>
            <% else %>
              <.action_menu state={@state} />
            <% end %>
          <% end %>
        </div>
      </div>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".Splash">
        export default {
          mounted() {
            this._mountedAt = Date.now()
            this.handleEvent("splash_dismiss", () => {
              const elapsed = Date.now() - this._mountedAt
              const wait = Math.max(0, 1000 - elapsed)
              setTimeout(() => {
                this.el.style.transition = "opacity 1s ease-out"
                this.el.style.opacity = "0"
                this.el.addEventListener("transitionend", () => {
                  this.pushEvent("splash_done", {})
                }, {once: true})
              }, wait)
            })
          }
        }
      </script>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".EventAutoScroll">
        export default {
          mounted() {
            this._userScrolledUp = false
            this.el.addEventListener("scroll", () => {
              const { scrollTop, scrollHeight, clientHeight } = this.el
              this._userScrolledUp = scrollHeight - scrollTop - clientHeight > 40
            })
            this.el.scrollTop = this.el.scrollHeight
          },
          updated() {
            if (!this._userScrolledUp) {
              this.el.scrollTop = this.el.scrollHeight
            }
          }
        }
      </script>
    </div>
    """
  end

  # --- Helpers ---

  defp subscribe_all(bookmark_id, participant_id) do
    Engine.subscribe(bookmark_id)

    Phoenix.PubSub.subscribe(
      Fate.PubSub,
      "selection:#{bookmark_id}:#{participant_id}"
    )

    Phoenix.PubSub.subscribe(Fate.PubSub, "exchange:#{bookmark_id}")
  end

  defp my_controlled_entity_ids(nil, _), do: MapSet.new()
  defp my_controlled_entity_ids(_, nil), do: MapSet.new()

  defp my_controlled_entity_ids(state, participant_id) do
    state.entities
    |> Map.values()
    |> Enum.filter(&(&1.controller_id == participant_id))
    |> Enum.map(& &1.id)
    |> MapSet.new()
  end

  defp load_events_for_role(bookmark_id, true = _is_gm) do
    case Fate.Game.get_bookmark(bookmark_id) do
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

  defp refresh_events_and_state(socket) do
    bookmark_id = socket.assigns.bookmark_id
    events = load_events_for_role(bookmark_id, socket.assigns.is_gm)

    socket =
      socket
      |> assign(:events, events)
      |> assign(:invalid_event_ids, Replay.validate_chain(events))

    case Engine.derive_state(bookmark_id) do
      {:ok, state} ->
        Phoenix.PubSub.broadcast(
          Fate.PubSub,
          "bookmark:#{bookmark_id}",
          {:state_updated, state}
        )

        assign(socket, :state, state)

      _ ->
        socket
    end
  end
end
