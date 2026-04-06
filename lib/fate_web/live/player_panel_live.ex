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
  def mount(params, session, socket) do
    identity = FateWeb.Helpers.identify(socket)

    if connected?(socket) && is_nil(identity.role) do
      {:ok, push_navigate(socket, to: ~p"/")}
    else
      embedded = !!session["embedded"]
      url_bookmark_id = if is_map(params), do: params["bookmark_id"]
      bookmark_id = url_bookmark_id || session["bookmark_id"]

      socket =
        socket
        |> assign(:bookmark_id, bookmark_id)
        |> assign(:events, [])
        |> assign(:event_index_map, %{})
        |> assign(:invalid_event_ids, %{})
        |> assign(:state, nil)
        |> assign(:participants, [])
        |> assign(:is_gm, identity.is_gm)
        |> assign(:is_observer, identity.is_observer)
        |> assign(:current_participant_id, identity.participant_id)
        |> assign(:selection, [])
        |> assign(:search_selected_entity_ids, MapSet.new())
        |> assign(:search_selected_scene_ids, MapSet.new())
        |> assign(:building, nil)
        |> assign(:build_steps, [])
        |> assign(:editing_step, nil)
        |> assign(:modal, nil)
        |> assign(:form_data, %{})
        |> assign(:prefill_entity_id, nil)
        |> assign(:modal_context_state, nil)
        |> assign(:modal_edit_baseline, nil)
        |> assign(:modal_original_detail, nil)
        |> assign(:embedded, embedded)
        |> assign(:splash_visible, !embedded)
        |> assign(:mention_catalog_json, Engine.mention_catalog_json(bookmark_id))

      socket =
        if connected?(socket) && bookmark_id do
          socket = init_state(socket, bookmark_id)
          if(!embedded, do: push_event(socket, "splash_dismiss", %{}), else: socket)
        else
          socket
        end

      {:ok, socket}
    end
  end

  @impl true
  def handle_info({:state_updated, state}, socket) do
    bookmark_id = socket.assigns.bookmark_id
    events = load_events_for_role(bookmark_id, socket.assigns.is_gm)

    {:noreply,
     socket
     |> assign(:state, state)
     |> assign(:events, events)
     |> assign(:event_index_map, build_event_index_map(bookmark_id))
     |> assign(:invalid_event_ids, Replay.validate_chain(events))
     |> assign(
       :mention_catalog_json,
       Engine.mention_catalog_json(bookmark_id)
     )}
  end

  def handle_info({:selection_updated, selection}, socket) do
    {:noreply, assign(socket, :selection, selection)}
  end

  def handle_info({:search_selection_updated, %{entity_ids: eids, scene_ids: sids}}, socket) do
    {:noreply,
     socket
     |> assign(:search_selected_entity_ids, eids)
     |> assign(:search_selected_scene_ids, sids)}
  end

  def handle_info({:exchange_updated, %{building: building, build_steps: build_steps}}, socket) do
    {:noreply,
     socket
     |> assign(:building, building)
     |> assign(:build_steps, build_steps)}
  end

  def handle_info(:dock_ack, socket) do
    {:noreply, push_event(socket, "close_window", %{})}
  end

  def handle_info({:dock_timeout, panel}, socket) do
    {:noreply,
     push_navigate(socket, to: ~p"/table/#{socket.assigns.bookmark_id}?panel=#{panel}")}
  end

  # --- Events ---

  @impl true
  def handle_event("splash_done", _params, socket) do
    {:noreply, assign(socket, :splash_visible, false)}
  end

  def handle_event("clear_selection", _params, socket) do
    FateWeb.Helpers.broadcast_selection(socket, [])

    FateWeb.Helpers.broadcast_search_selection(socket, %{
      entity_ids: MapSet.new(),
      scene_ids: MapSet.new()
    })

    {:noreply,
     socket
     |> assign(:selection, [])
     |> assign(:search_selected_entity_ids, MapSet.new())
     |> assign(:search_selected_scene_ids, MapSet.new())}
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
     |> assign(:prefill_entity_id, params["entity_id"])
     |> assign(:modal_context_state, nil)
     |> assign(:modal_edit_baseline, nil)
     |> assign(:modal_original_detail, nil)}
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
         |> assign(:prefill_entity_id, entity_id)
         |> assign(:modal_context_state, nil)
         |> assign(:modal_edit_baseline, nil)
         |> assign(:modal_original_detail, nil)}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("edit_event", %{"id" => event_id}, socket) do
    event = Enum.find(socket.assigns.events, &(&1.id == event_id))

    if event && editable_event?(event) do
      bookmark_id = socket.assigns.bookmark_id

      {ctx_state, form_data} =
        case Engine.state_through_event(bookmark_id, event.id) do
          {:ok, st} ->
            {st, build_edit_form_data(event, state_after_event: st)}

          _ ->
            {nil, build_edit_form_data(event)}
        end

      baseline = Map.new(form_data)
      original_detail = Map.merge(%{}, event.detail || %{})
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
       |> assign(:prefill_entity_id, prefill_entity_id)
       |> assign(:modal_context_state, ctx_state)
       |> assign(:modal_edit_baseline, baseline)
       |> assign(:modal_original_detail, original_detail)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("close_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:modal, nil)
     |> assign(:form_data, %{})
     |> assign(:prefill_entity_id, nil)
     |> assign(:modal_context_state, nil)
     |> assign(:modal_edit_baseline, nil)
     |> assign(:modal_original_detail, nil)}
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
    submit_state =
      if params["event_id"] not in [nil, ""] do
        socket.assigns.modal_context_state || socket.assigns.state
      else
        socket.assigns.state
      end

    result =
      case socket.assigns.modal do
        "aspect_create" ->
          case FateWeb.ModalSubmit.aspect_create_attrs(params, :panel) do
            {:ok, attrs} ->
              create_or_update_event(
                params,
                finalize_modal_submit(socket, params, attrs),
                socket.assigns.bookmark_id
              )

            :error ->
              {:error, "Choose where the aspect goes and enter aspect text"}
          end

        "aspect_compel" ->
          target_entity =
            if submit_state && params["target_id"],
              do: Map.get(submit_state.entities, params["target_id"]),
              else: nil

          target_name = if target_entity, do: target_entity.name, else: "entity"

          attrs = FateWeb.ModalSubmit.aspect_compel_attrs(params, target_name)

          create_or_update_event(
            params,
            finalize_modal_submit(socket, params, attrs),
            socket.assigns.bookmark_id
          )

        "entity_move" ->
          zone_name =
            if submit_state do
              all_zones =
                (if submit_state.active_scene, do: submit_state.active_scene.zones, else: []) ++
                  Enum.flat_map(submit_state.scene_templates, & &1.zones)

              case Enum.find(all_zones, &(&1.id == params["zone_id"])) do
                nil -> "zone"
                z -> z.name
              end
            else
              "zone"
            end

          attrs = FateWeb.ModalSubmit.entity_move_attrs(params, zone_name)

          create_or_update_event(
            params,
            finalize_modal_submit(socket, params, attrs),
            socket.assigns.bookmark_id
          )

        "scene_start" ->
          attrs =
            FateWeb.ModalSubmit.template_scene_create_attrs(
              params,
              params["scene_id"] || Ash.UUID.generate()
            )

          create_or_update_event(
            params,
            finalize_modal_submit(socket, params, attrs),
            socket.assigns.bookmark_id
          )

        "scene_end" ->
          active = socket.assigns.state.active_scene

          case FateWeb.ModalSubmit.scene_end_attrs(active) do
            {:ok, attrs} ->
              Engine.append_event(socket.assigns.bookmark_id, attrs)

            :error ->
              {:error, "No active scene"}
          end

        "fate_point_spend" ->
          attrs = FateWeb.ModalSubmit.fate_point_spend_attrs(params)

          create_or_update_event(
            params,
            finalize_modal_submit(socket, params, attrs),
            socket.assigns.bookmark_id
          )

        "fate_point_earn" ->
          attrs = FateWeb.ModalSubmit.fate_point_earn_attrs(params)

          create_or_update_event(
            params,
            finalize_modal_submit(socket, params, attrs),
            socket.assigns.bookmark_id
          )

        "fate_point_refresh" ->
          attrs = FateWeb.ModalSubmit.fate_point_refresh_attrs(params)

          create_or_update_event(
            params,
            finalize_modal_submit(socket, params, attrs),
            socket.assigns.bookmark_id
          )

        "entity_create" ->
          attrs =
            FateWeb.ModalSubmit.entity_create_attrs(params, socket.assigns.participants)

          create_or_update_event(
            params,
            finalize_modal_submit(socket, params, attrs),
            socket.assigns.bookmark_id
          )

        "entity_edit" ->
          attrs =
            FateWeb.ModalSubmit.entity_modify_attrs(
              params,
              socket.assigns.participants,
              params["name"] || "entity"
            )

          create_or_update_event(
            params,
            finalize_modal_submit(socket, params, attrs),
            socket.assigns.bookmark_id
          )

        "skill_set" ->
          attrs = FateWeb.ModalSubmit.skill_set_attrs(params)

          create_or_update_event(
            params,
            finalize_modal_submit(socket, params, attrs),
            socket.assigns.bookmark_id
          )

        "stunt_add" ->
          attrs = FateWeb.ModalSubmit.stunt_add_attrs(params)

          create_or_update_event(
            params,
            finalize_modal_submit(socket, params, attrs),
            socket.assigns.bookmark_id
          )

        "stunt_remove" ->
          attrs = FateWeb.ModalSubmit.stunt_remove_attrs(params)

          create_or_update_event(
            params,
            finalize_modal_submit(socket, params, attrs),
            socket.assigns.bookmark_id
          )

        "set_system" ->
          attrs = FateWeb.ModalSubmit.set_system_attrs(params)

          create_or_update_event(
            params,
            finalize_modal_submit(socket, params, attrs),
            socket.assigns.bookmark_id
          )

        "scene_modify" ->
          attrs = FateWeb.ModalSubmit.template_scene_modify_attrs(params)

          create_or_update_event(
            params,
            finalize_modal_submit(socket, params, attrs),
            socket.assigns.bookmark_id
          )

        modal when modal in ~w(note edit_note) ->
          case FateWeb.ModalSubmit.note_attrs(params) do
            {:ok, attrs} ->
              create_or_update_event(
                params,
                finalize_modal_submit(socket, params, attrs),
                socket.assigns.bookmark_id
              )

            :error ->
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
         |> assign(:prefill_entity_id, nil)
         |> assign(:modal_context_state, nil)
         |> assign(:modal_edit_baseline, nil)
         |> assign(:modal_original_detail, nil)}

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

  def handle_event("dock", %{"panel" => panel}, socket) do
    Phoenix.PubSub.broadcast(
      Fate.PubSub,
      "dock:#{socket.assigns.bookmark_id}",
      {:dock_panel, String.to_existing_atom(panel), self()}
    )

    Process.send_after(self(), {:dock_timeout, panel}, 200)
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div
      class={["flex flex-col relative", if(@embedded, do: "h-full", else: "h-screen")]}
      style="background: #1a1410; color: #e8dcc8;"
      phx-window-keydown={if @modal, do: "close_modal"}
      phx-key={if @modal, do: "Escape"}
    >
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
          modal_context_state={@modal_context_state}
          prefill_entity_id={@prefill_entity_id}
          form_data={@form_data}
          participants={@participants}
          mention_catalog_json={@mention_catalog_json}
        />
      <% end %>

      <%!-- Event log header --%>
      <% selected_entity_ids =
           @selection
           |> Enum.filter(&(&1.type == "entity"))
           |> Enum.map(& &1.id)
           |> MapSet.new()
           |> MapSet.union(@search_selected_entity_ids) %>
      <% scene_event_ids = Replay.events_during_scenes(@events, @search_selected_scene_ids) %>
      <% entity_filter? = MapSet.size(selected_entity_ids) > 0 %>
      <% scene_filter? = MapSet.size(scene_event_ids) > 0 %>
      <% filter_active? = entity_filter? || scene_filter? %>
      <% event_items =
           @events
           |> Enum.map(fn ev -> {ev, Map.get(@event_index_map, ev.id, 0)} end)
           |> then(fn pairs ->
             if filter_active? do
               Enum.filter(pairs, fn {ev, _} ->
                 entity_ok = !entity_filter? || Replay.event_matches_selected_entities?(ev, selected_entity_ids)
                 scene_ok = !scene_filter? || MapSet.member?(scene_event_ids, ev.id)
                 entity_ok && scene_ok
               end)
             else
               pairs
             end
           end) %>
      <% filtered_count = length(event_items) %>
      <% total_count = length(@events) %>
      <% latest_event_id =
           case List.last(@events) do
             nil -> nil
             ev -> ev.id
           end %>
      <div class="p-4 border-b border-amber-900/30 flex flex-col gap-2">
        <div class="flex items-baseline justify-between gap-3 min-w-0">
          <div class="flex flex-wrap items-baseline gap-x-3 gap-y-1 min-w-0 flex-1">
            <h2
              class="text-lg font-bold text-amber-100 shrink-0"
              style="font-family: 'Permanent Marker', cursive;"
            >
              Events
            </h2>
            <%= if !filter_active? do %>
              <span class="text-sm text-amber-200/50 leading-snug">
                No entity filter
                <span class="text-amber-200/40"> {total_count} events</span>
              </span>
            <% end %>
          </div>
          <div class="flex items-center gap-2 shrink-0 self-start">
            <%= unless @embedded do %>
              <button
                id="dock-player"
                phx-hook=".DockPanel"
                data-panel="player"
                data-bookmark-id={@bookmark_id}
                class="p-1.5 rounded-lg text-amber-200/40 hover:text-amber-200/70 hover:bg-amber-900/30 transition"
                title="Dock into table view"
              >
                <.icon name="hero-arrow-down-on-square" class="w-4 h-4" />
              </button>
            <% end %>
          </div>
        </div>
        <%= if filter_active? do %>
          <div class="w-full min-w-0 text-sm">
            <div class="text-amber-200/70 break-words [overflow-wrap:anywhere] leading-snug whitespace-normal">
              Showing events for: {format_entity_filter_names(@state, selected_entity_ids)}
            </div>
            <div class="mt-1 flex flex-wrap items-center gap-x-2 gap-y-1">
              <span class="text-amber-200/40">
                {filtered_count} of {total_count} events
              </span>
              <button
                type="button"
                id="event-log-clear-selection"
                phx-click="clear_selection"
                class="text-amber-300/90 hover:text-amber-200 underline underline-offset-2 transition"
              >
                Clear selection
              </button>
            </div>
          </div>
        <% end %>
      </div>

      <%!-- Event log (chat order: oldest at top, newest at bottom) --%>
      <% boundary_idx = bookmark_boundary_index(@events) %>
      <% immutable_ids = @events |> Enum.take(boundary_idx + 1) |> MapSet.new(& &1.id) %>
      <% my_entity_ids = my_controlled_entity_ids(@state, @current_participant_id) %>
      <div
        class="flex-1 min-h-0 overflow-y-auto p-3 space-y-1"
        id="event-log"
        phx-hook=".EventAutoScroll"
      >
        <%= if @events == [] do %>
          <div class="text-amber-200/30 text-center py-8">No events yet</div>
        <% else %>
          <%= if filter_active? && filtered_count == 0 do %>
            <div class="text-amber-200/40 text-center py-8">
              No events match the selected entities.
            </div>
          <% else %>
            <div
              id="event-log-items"
              phx-hook={if(@is_gm && !@is_observer && !filter_active?, do: "EventReorder")}
            >
              <%= for {event, index} <- event_items do %>
                <.event_row
                  event={event}
                  index={index}
                  state={@state}
                  immutable={MapSet.member?(immutable_ids, event.id)}
                  is_observer={@is_observer}
                  is_gm={@is_gm}
                  invalid={Map.get(@invalid_event_ids, event.id)}
                  my_entity_ids={my_entity_ids}
                  tip_of_timeline={latest_event_id != nil and event.id == latest_event_id}
                />
              <% end %>
            </div>
          <% end %>
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
            this._ignoreScroll = false
            this._layoutMute = false
            this._restoreScheduled = false
            this._wasAtBottom = true
            this._savedScrollTop = 0
            this._prevScrollTop = null
            this._lastCH = null
            this._mutationThisFrame = false
            this._restoreIntent = null
            this._scrollTopAtIntent = 0

            /*
             * Opening the modal shrinks this flex child: the browser can clamp scrollTop to 0 in
             * the same frame the viewport height changes. LV often does not run beforeUpdate/updated
             * on #event-log when only the modal sibling changes, so we also watch resize + mutations.
             * We repair (1) tail + viewport height change, or (2) tail + DOM mutation + jump to top,
             * so Home/end-key jumps are not confused with layout when height did not change.
             *
             * Edit/delete run phx-click after layout starts; intermediate scroll events can flip
             * _wasAtBottom before ResizeObserver fires. Capture intent on pointerdown (capture phase)
             * before any of that.
             */
            this._onPointerDown = (e) => {
              const btn = e.target.closest(
                'button[phx-click="edit_event"], button[phx-click="delete_event"]'
              )
              if (!btn || !this.el.contains(btn)) return
              const { scrollTop, scrollHeight, clientHeight } = this.el
              const fromBottom = scrollHeight - scrollTop - clientHeight
              if (fromBottom <= 80) {
                this._restoreIntent = "tail"
              } else {
                this._restoreIntent = "preserve"
                this._scrollTopAtIntent = scrollTop
              }
            }
            this.el.addEventListener("pointerdown", this._onPointerDown, true)

            this._captureScrollIntent = () => {
              if (this._ignoreScroll || this._layoutMute) return
              const { scrollTop, scrollHeight, clientHeight } = this.el
              const maxS = Math.max(0, scrollHeight - clientHeight)
              const prev = this._prevScrollTop
              const chChanged = this._lastCH != null && this._lastCH !== clientHeight
              const jumpedToTop =
                scrollTop < 8 &&
                prev != null &&
                prev > 80 &&
                maxS > 100 &&
                this._wasAtBottom

              if (jumpedToTop && (chChanged || this._mutationThisFrame)) {
                this._ignoreScroll = true
                this.el.scrollTop = scrollHeight
                this._ignoreScroll = false
                this._prevScrollTop = this.el.scrollTop
                this._wasAtBottom = true
                this._savedScrollTop = this.el.scrollTop
                this._lastCH = clientHeight
                return
              }

              this._prevScrollTop = scrollTop
              this._lastCH = clientHeight
              const fromBottom = scrollHeight - scrollTop - clientHeight
              this._wasAtBottom = fromBottom <= 40
              this._savedScrollTop = scrollTop
            }
            this.el.addEventListener("scroll", this._captureScrollIntent, { passive: true })

            this._restoreNow = () => {
              if (!this.el?.isConnected) return
              const intent = this._restoreIntent
              const wantTail =
                intent === "tail" ||
                (intent == null && this._wasAtBottom)
              const savedTop =
                intent === "preserve" ? this._scrollTopAtIntent : this._savedScrollTop

              const { scrollHeight, clientHeight } = this.el
              if (scrollHeight <= clientHeight) return

              this._restoreIntent = null
              this._layoutMute = true
              this._ignoreScroll = true

              if (wantTail) {
                this.el.scrollTop = scrollHeight
              } else {
                const maxScroll = Math.max(0, scrollHeight - clientHeight)
                this.el.scrollTop = Math.min(savedTop, maxScroll)
              }

              this._prevScrollTop = this.el.scrollTop
              this._lastCH = clientHeight

              requestAnimationFrame(() => {
                if (wantTail && this.el.isConnected) {
                  this.el.scrollTop = this.el.scrollHeight
                }
                requestAnimationFrame(() => {
                  if (wantTail && this.el.isConnected) {
                    this.el.scrollTop = this.el.scrollHeight
                  }
                  if (this.el.isConnected) {
                    const sh = this.el.scrollHeight
                    const ch = this.el.clientHeight
                    const st = this.el.scrollTop
                    this._wasAtBottom = sh - st - ch <= 40
                    this._savedScrollTop = st
                  }
                  this._ignoreScroll = false
                  this._layoutMute = false
                })
              })
            }

            // Double rAF: flex + LV may need an extra frame before scrollHeight is stable.
            this._scheduleRestore = () => {
              if (this._restoreScheduled) return
              this._restoreScheduled = true
              requestAnimationFrame(() => {
                requestAnimationFrame(() => {
                  this._restoreScheduled = false
                  this._restoreNow()
                })
              })
            }

            this._mo = new MutationObserver(() => {
              this._mutationThisFrame = true
              requestAnimationFrame(() => {
                this._mutationThisFrame = false
              })
              this._scheduleRestore()
            })
            this._mo.observe(this.el, { childList: true, subtree: true })

            this._ro = new ResizeObserver(() => this._scheduleRestore())
            this._ro.observe(this.el)

            this._scheduleRestore()
            this._initTooltip()
          },
          beforeUpdate() {
            this._captureScrollIntent()
          },
          updated() {
            this._scheduleRestore()
          },
          destroyed() {
            this.el.removeEventListener("scroll", this._captureScrollIntent)
            this.el.removeEventListener("pointerdown", this._onPointerDown, true)
            this.el.removeEventListener("mouseover", this._tipShow)
            this.el.removeEventListener("mouseout", this._tipHide)
            this._mo?.disconnect()
            this._ro?.disconnect()
            if (this._tip) { this._tip.remove(); this._tip = null }
          },
          _initTooltip() {
            this._tip = null

            this._tipShow = (e) => {
              const el = e.target.closest("[data-summary-tooltip]")
              if (!el || !this.el.contains(el)) return
              const text = el.getAttribute("data-summary-tooltip")
              if (!text) return

              if (!this._tip) {
                this._tip = document.createElement("div")
                this._tip.style.cssText =
                  "position:fixed;z-index:99999;pointer-events:none;" +
                  "white-space:pre-wrap;font-size:11px;line-height:1.35;" +
                  "padding:4px 8px;border-radius:4px;" +
                  "background:rgba(20,14,6,0.95);color:#e8dcc8;" +
                  "border:1px solid rgba(180,140,80,0.3);" +
                  "max-width:min(28rem,calc(100vw - 1rem));box-sizing:border-box;"
                document.body.appendChild(this._tip)
              }

              this._tip.textContent = text
              this._tip.style.display = "block"

              const rect = el.getBoundingClientRect()
              const tipH = this._tip.offsetHeight
              const tipW = this._tip.offsetWidth
              let top = rect.bottom + 4
              let left = rect.left

              if (top + tipH > window.innerHeight - 8) top = rect.top - tipH - 4
              if (left + tipW > window.innerWidth - 8) left = window.innerWidth - tipW - 8
              if (left < 4) left = 4

              this._tip.style.top = top + "px"
              this._tip.style.left = left + "px"
            }

            this._tipHide = (e) => {
              const to = e.relatedTarget
              if (to && to.closest && to.closest("[data-summary-tooltip]")) return
              if (this._tip) this._tip.style.display = "none"
            }

            this.el.addEventListener("mouseover", this._tipShow)
            this.el.addEventListener("mouseout", this._tipHide)
          }
        }
      </script>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".DockPanel">
        export default {
          mounted() {
            this.handleEvent("close_window", () => { window.close() })
            this.el.addEventListener("click", () => {
              this.pushEvent("dock", {
                panel: this.el.dataset.panel
              })
            })
          }
        }
      </script>
    </div>
    """
  end

  # --- Helpers ---

  defp finalize_modal_submit(socket, params, attrs) do
    if params["event_id"] not in [nil, ""] && socket.assigns.modal_edit_baseline do
      merged =
        merge_edit_detail(
          socket.assigns.modal,
          socket.assigns.modal_original_detail || %{},
          socket.assigns.modal_edit_baseline,
          params,
          socket.assigns.participants
        )

      Map.put(attrs, :detail, merged)
    else
      attrs
    end
  end

  defp init_state(socket, bookmark_id) do
    subscribe_all(bookmark_id, socket.assigns.current_participant_id)

    case Engine.derive_state(bookmark_id) do
      {:ok, state} ->
        events = load_events_for_role(bookmark_id, socket.assigns.is_gm)
        participants = Fate.Game.Bookmarks.load_participants(bookmark_id)

        socket
        |> assign(:events, events)
        |> assign(:event_index_map, build_event_index_map(bookmark_id))
        |> assign(:invalid_event_ids, Replay.validate_chain(events))
        |> assign(:participants, participants)
        |> assign(:state, state)
        |> assign(:mention_catalog_json, Engine.mention_catalog_json(bookmark_id))

      _ ->
        socket
    end
  end

  defp subscribe_all(bookmark_id, participant_id) do
    Engine.subscribe(bookmark_id)

    Phoenix.PubSub.subscribe(
      Fate.PubSub,
      "selection:#{bookmark_id}:#{participant_id}"
    )

    Phoenix.PubSub.subscribe(Fate.PubSub, "exchange:#{bookmark_id}")

    Phoenix.PubSub.subscribe(
      Fate.PubSub,
      FateWeb.Helpers.search_selection_topic(bookmark_id, participant_id)
    )
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

  defp format_entity_filter_names(nil, _), do: "(unknown)"

  defp format_entity_filter_names(state, selected_ids) do
    all = Map.merge(state.entities, state.removed_entities)

    selected_ids
    |> MapSet.to_list()
    |> Enum.map(fn id ->
      label =
        case Map.get(all, id) do
          %{name: n} when is_binary(n) and n != "" -> n
          _ -> String.slice(id, 0, 8) <> "…"
        end

      {label, id}
    end)
    |> Enum.sort_by(fn {label, id} -> {String.downcase(label), id} end)
    |> Enum.map_join(", ", fn {label, _} -> label end)
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

  defp build_event_index_map(bookmark_id) do
    case Fate.Game.get_bookmark(bookmark_id) do
      {:ok, %{head_event_id: head_id}} when head_id != nil ->
        case Engine.load_event_chain(head_id) do
          {:ok, events} ->
            events
            |> Enum.with_index(1)
            |> Map.new(fn {e, i} -> {e.id, i} end)

          _ ->
            %{}
        end

      _ ->
        %{}
    end
  end

  defp refresh_events_and_state(socket) do
    bookmark_id = socket.assigns.bookmark_id
    events = load_events_for_role(bookmark_id, socket.assigns.is_gm)

    socket =
      socket
      |> assign(:events, events)
      |> assign(:event_index_map, build_event_index_map(bookmark_id))
      |> assign(:invalid_event_ids, Replay.validate_chain(events))

    case Engine.derive_state(bookmark_id) do
      {:ok, state} ->
        Phoenix.PubSub.broadcast(
          Fate.PubSub,
          "bookmark:#{bookmark_id}",
          {:state_updated, state}
        )

        socket
        |> assign(:state, state)
        |> assign(:mention_catalog_json, Engine.mention_catalog_json(bookmark_id))

      _ ->
        socket
    end
  end
end
