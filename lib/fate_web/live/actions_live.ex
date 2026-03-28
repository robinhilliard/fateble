defmodule FateWeb.ActionsLive do
  use FateWeb, :live_view

  alias Fate.Engine
  alias Fate.Engine.Replay

  import FateWeb.ActionComponents
  import FateWeb.ExchangeComponents

  defp modal_for_event_type(:entity_modify), do: "entity_edit"
  defp modal_for_event_type(:note), do: "edit_note"
  defp modal_for_event_type(type), do: Atom.to_string(type)

  @impl true
  def mount(_params, _session, socket) do
    identity = FateWeb.Helpers.identify(socket)

    if connected?(socket) && is_nil(identity.role) do
      {:ok, push_navigate(socket, to: ~p"/")}
    else
      socket =
        socket
        |> assign(:bookmark_id, nil)
        |> assign(:events, [])
        |> assign(:invalid_event_ids, MapSet.new())
        |> assign(:state, nil)
        |> assign(:participants, [])
        |> assign(:is_gm, identity.is_gm)
        |> assign(:is_observer, identity.is_observer)
        |> assign(:current_participant_id, identity.participant_id)
        |> assign(:log_tab, :bookmarks)
        |> assign(:selection, [])
        |> assign(:building, nil)
        |> assign(:build_steps, [])
        |> assign(:editing_step, nil)
        |> assign(:modal, nil)
        |> assign(:form_data, %{})
        |> assign(:prefill_entity_id, nil)
        |> assign(:bookmarks, [])

      {:ok, socket}
    end
  end

  @impl true
  def handle_params(%{"bookmark_id" => bookmark_id}, _uri, socket) do
    if connected?(socket) do
      Engine.subscribe(bookmark_id)
      Phoenix.PubSub.subscribe(Fate.PubSub, "selection:#{bookmark_id}")
      Phoenix.PubSub.subscribe(Fate.PubSub, "exchange:#{bookmark_id}")

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
         |> assign(:bookmarks, load_active_bookmarks())}
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
      broadcast_exchange(socket)
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
    {:noreply, socket |> assign(:modal, nil) |> assign(:form_data, %{})}
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
            socket
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
            socket
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
            socket
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
            socket
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
            socket
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
            socket
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
            socket
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
            socket
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
            socket
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
            socket
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
            socket
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
            socket
          )

        "set_system" ->
          create_or_update_event(
            params,
            %{
              type: :set_system,
              description: "Set system: #{params["system"]}",
              detail: %{"system" => params["system"]}
            },
            socket
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
            socket
          )

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
              socket
            )
          else
            {:error, "Note text is required"}
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

      <%!-- Modal overlay (not for observers) --%>
      <%= unless @is_observer do %>
        <.action_modal
          modal={@modal}
          state={@state}
          prefill_entity_id={@prefill_entity_id}
          form_data={@form_data}
          participants={@participants}
        />
      <% end %>
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
          <div
            class="flex-1 overflow-y-auto p-3 space-y-1"
            id="event-log"
            phx-hook={if(@is_gm && !@is_observer, do: "EventReorder")}
          >
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
                  is_observer={@is_observer}
                  is_gm={@is_gm}
                  invalid={MapSet.member?(@invalid_event_ids, event.id)}
                />
              <% end %>
            <% end %>
          </div>
        <% else %>
          <div class="flex-1 overflow-y-auto p-3" id="bookmark-tree">
            <.bookmark_tree bookmark_id={@bookmark_id} bookmarks={@bookmarks} />
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
              <%!-- Exchange builder (visible to all, read-only for observers) --%>
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
                <div class="text-amber-200/30 text-center py-8">
                  Observing — actions are disabled
                </div>
              <% else %>
                <%!-- Quick actions + exchange starters --%>
                <.action_menu state={@state} />
              <% end %>
            <% end %>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  # --- Helpers ---

  defp load_active_bookmarks do
    require Ash.Query

    case Ash.read(
           Fate.Game.Bookmark
           |> Ash.Query.filter(status: :active)
           |> Ash.Query.sort(created_at: :asc)
         ) do
      {:ok, bms} -> bms
      _ -> []
    end
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

  defp bookmark_tree(assigns) do
    bookmarks = assigns.bookmarks
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

  defp broadcast_exchange(socket) do
    if socket.assigns.bookmark_id do
      Phoenix.PubSub.broadcast_from(
        Fate.PubSub,
        self(),
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

  defp parse_int(nil), do: nil
  defp parse_int(""), do: nil
  defp parse_int(v) when is_integer(v), do: v

  defp parse_int(v) when is_binary(v) do
    case Integer.parse(v) do
      {n, _} -> n
      :error -> nil
    end
  end

  defp build_edit_form_data(%{type: :note} = event) do
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

  defp build_edit_form_data(%{type: :aspect_create} = event) do
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

  defp build_edit_form_data(%{type: :aspect_compel} = event) do
    detail = event.detail || %{}

    edit_base(event, %{
      "actor_id" => event.actor_id || "",
      "target_id" => event.target_id || detail["target_id"] || "",
      "aspect_id" => detail["aspect_id"] || "",
      "description" => detail["description"] || "",
      "accepted" => if(detail["accepted"] != false, do: "true", else: "false")
    })
  end

  defp build_edit_form_data(%{type: :entity_move} = event) do
    detail = event.detail || %{}

    edit_base(event, %{
      "entity_id" => detail["entity_id"] || event.actor_id || "",
      "zone_id" => detail["zone_id"] || ""
    })
  end

  defp build_edit_form_data(%{type: type} = event) when type in ~w(scene_start scene_modify)a do
    detail = event.detail || %{}

    edit_base(event, %{
      "scene_id" => detail["scene_id"] || "",
      "name" => detail["name"] || "",
      "scene_description" => detail["description"] || "",
      "gm_notes" => detail["gm_notes"] || ""
    })
  end

  defp build_edit_form_data(%{type: :entity_create} = event) do
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

  defp build_edit_form_data(%{type: :entity_modify} = event) do
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

  defp build_edit_form_data(%{type: :skill_set} = event) do
    detail = event.detail || %{}

    edit_base(event, %{
      "entity_id" => detail["entity_id"] || event.target_id || "",
      "skill" => detail["skill"] || "",
      "rating" => to_string(detail["rating"] || "")
    })
  end

  defp build_edit_form_data(%{type: :stunt_add} = event) do
    detail = event.detail || %{}

    edit_base(event, %{
      "entity_id" => detail["entity_id"] || event.target_id || "",
      "stunt_id" => detail["stunt_id"] || "",
      "name" => detail["name"] || "",
      "effect" => detail["effect"] || ""
    })
  end

  defp build_edit_form_data(%{type: :stunt_remove} = event) do
    detail = event.detail || %{}

    edit_base(event, %{
      "entity_id" => detail["entity_id"] || event.target_id || "",
      "stunt_id" => detail["stunt_id"] || ""
    })
  end

  defp build_edit_form_data(%{type: :set_system} = event) do
    detail = event.detail || %{}
    edit_base(event, %{"system" => detail["system"] || "core"})
  end

  defp build_edit_form_data(%{type: type} = event)
       when type in ~w(fate_point_spend fate_point_earn fate_point_refresh)a do
    detail = event.detail || %{}
    edit_base(event, %{"entity_id" => detail["entity_id"] || event.target_id || ""})
  end

  defp build_edit_form_data(event), do: %{"event_id" => event.id}

  defp edit_base(event, fields), do: Map.put(fields, "event_id", event.id)

  defp update_event_and_broadcast(event, attrs, socket) do
    Ash.update!(event, attrs, action: :edit)

    case Engine.derive_state(socket.assigns.bookmark_id) do
      {:ok, state} ->
        Phoenix.PubSub.broadcast(
          Fate.PubSub,
          "bookmark:#{socket.assigns.bookmark_id}",
          {:state_updated, state}
        )

        {:ok, state, event}

      _ ->
        {:ok, nil, nil}
    end
  end

  defp create_or_update_event(params, attrs, socket) do
    case params["event_id"] do
      nil ->
        Engine.append_event(socket.assigns.bookmark_id, attrs)

      event_id ->
        case Ash.get(Fate.Game.Event, event_id, not_found_error?: false) do
          {:ok, event} when event != nil ->
            update_attrs = Map.take(attrs, [:description, :detail, :target_id, :actor_id])
            update_event_and_broadcast(event, update_attrs, socket)

          _ ->
            {:error, "Event not found"}
        end
    end
  end
end
