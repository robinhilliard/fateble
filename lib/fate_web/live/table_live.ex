defmodule FateWeb.TableLive do
  use FateWeb, :live_view

  alias Fate.Engine
  alias Fate.Engine.Replay
  alias Fate.Game.Bookmarks
  alias FateWeb.ModalSubmit

  import FateWeb.TableComponents

  @impl true
  def mount(_params, _session, socket) do
    identity = FateWeb.Helpers.identify(socket)

    if connected?(socket) && is_nil(identity.role) do
      {:ok, push_navigate(socket, to: ~p"/")}
    else
      socket =
        socket
        |> assign(:is_gm, identity.is_gm)
        |> assign(:is_observer, identity.is_observer)
        |> assign(:current_participant_id, identity.participant_id)
        |> assign(:current_participant_name, identity.name)
        |> assign(:dock_position, :south)
        |> assign(:tent_size, 0.3)
        |> assign(:bookmark_id, nil)
        |> assign(:state, nil)
        |> assign(:participants, [])
        |> assign(:selection, [])
        |> assign(:expanded_entities, MapSet.new())
        |> assign(:current_template_id, nil)
        |> assign(:table_modal, nil)
        |> assign(:splash_visible, true)
        |> assign(:gm_panel_open, false)
        |> assign(:player_panel_open, false)
        |> assign(:mention_catalog_json, Engine.mention_catalog_json(nil))

      {:ok, socket}
    end
  end

  @impl true
  def handle_params(%{"bookmark_id" => bookmark_id} = params, _uri, socket) do
    if connected?(socket) do
      Engine.subscribe(bookmark_id)

      Phoenix.PubSub.subscribe(
        Fate.PubSub,
        "selection:#{bookmark_id}:#{socket.assigns.current_participant_id}"
      )

      Phoenix.PubSub.subscribe(Fate.PubSub, "dock:#{bookmark_id}")

      case Engine.derive_state(bookmark_id) do
        {:ok, state} ->
          participants = Bookmarks.load_participants(bookmark_id)

          socket =
            socket
            |> assign(:bookmark_id, bookmark_id)
            |> assign(:state, state)
            |> assign(:participants, participants)
            |> assign(:current_template_id, nil)
            |> assign(:mention_catalog_json, Engine.mention_catalog_json(bookmark_id))
            |> maybe_open_panel(params["panel"])
            |> push_event("splash_dismiss", %{})

          {:noreply, socket}

        {:error, _reason} ->
          {:noreply, put_flash(socket, :error, "Could not load bookmark")}
      end
    else
      {:noreply, assign(socket, :bookmark_id, bookmark_id)}
    end
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_info({:state_updated, state}, socket) do
    {:noreply,
     socket
     |> assign(:state, state)
     |> assign(:mention_catalog_json, Engine.mention_catalog_json(socket.assigns.bookmark_id))}
  end

  def handle_info({:selection_updated, selection}, socket) do
    {:noreply, assign(socket, :selection, selection)}
  end

  def handle_info({:dock_panel, panel, from_pid}, socket) do
    send(from_pid, :dock_ack)
    {:noreply, assign(socket, panel_assign(panel), true)}
  end

  @impl true
  def handle_event("splash_done", _params, socket) do
    {:noreply, assign(socket, :splash_visible, false)}
  end

  def handle_event("toggle_panel", %{"panel" => panel}, socket) do
    key = panel_assign(panel)
    {:noreply, assign(socket, key, !socket.assigns[key])}
  end

  def handle_event("detach_panel", %{"panel" => panel}, socket) do
    {:noreply, assign(socket, panel_assign(panel), false)}
  end

  def handle_event("restore_panel_state", params, socket) do
    socket =
      socket
      |> then(fn s -> if params["gm_panel_open"], do: assign(s, :gm_panel_open, true), else: s end)
      |> then(fn s ->
        if params["player_panel_open"], do: assign(s, :player_panel_open, true), else: s
      end)

    {:noreply, socket}
  end

  def handle_event("set_dock", %{"position" => position}, socket) do
    position = String.to_existing_atom(position)
    {:noreply, assign(socket, :dock_position, position)}
  end

  def handle_event("set_tent_size", %{"size" => size}, socket) do
    {size, _} = Float.parse(size)
    {:noreply, assign(socket, :tent_size, size)}
  end

  def handle_event("remove_aspect", %{"aspect-id" => aspect_id, "entity-id" => entity_id}, socket) do
    entity = Map.get(socket.assigns.state.entities, entity_id)
    aspect = entity && Enum.find(entity.aspects, &(&1.id == aspect_id))
    desc = if aspect, do: aspect.description, else: "aspect"

    Fate.Engine.append_event(socket.assigns.bookmark_id, %{
      type: :aspect_remove,
      target_id: entity_id,
      description: "Remove aspect: #{desc}",
      detail: %{
        "aspect_id" => aspect_id,
        "description" => desc,
        "target_type" => "entity",
        "target_id" => entity_id
      }
    })

    {:noreply, socket}
  end

  def handle_event("remove_scene_aspect", %{"aspect-id" => aspect_id}, socket) do
    aspect = find_scene_aspect(socket.assigns.state, aspect_id)
    desc = if aspect, do: aspect.description, else: "aspect"

    detail =
      case Replay.find_aspect_container(socket.assigns.state, aspect_id) do
        {:ok, tt, tid} ->
          %{
            "aspect_id" => aspect_id,
            "description" => desc,
            "target_type" => tt,
            "target_id" => tid
          }

        :error ->
          %{"aspect_id" => aspect_id, "description" => desc}
      end

    type = if socket.assigns.state.active_scene, do: :active_aspect_remove, else: :aspect_remove

    Fate.Engine.append_event(socket.assigns.bookmark_id, %{
      type: type,
      description: "Remove aspect: #{desc}",
      detail: detail
    })

    {:noreply, socket}
  end

  def handle_event("remove_from_zone", %{"entity_id" => entity_id}, socket) do
    case Fate.Engine.append_event(socket.assigns.bookmark_id, %{
           type: :entity_move,
           actor_id: entity_id,
           description: "Leave zone",
           detail: %{"entity_id" => entity_id, "zone_id" => nil}
         }) do
      {:ok, _state, _event} -> {:noreply, socket}
      {:error, reason} -> {:noreply, put_flash(socket, :error, inspect(reason))}
    end
  end

  def handle_event("move_to_zone", %{"entity_id" => entity_id, "zone_id" => zone_id}, socket) do
    case Fate.Engine.append_event(socket.assigns.bookmark_id, %{
           type: :entity_move,
           actor_id: entity_id,
           description: "Move to zone",
           detail: %{"entity_id" => entity_id, "zone_id" => zone_id}
         }) do
      {:ok, _state, _event} -> {:noreply, socket}
      {:error, reason} -> {:noreply, put_flash(socket, :error, inspect(reason))}
    end
  end

  def handle_event(
        "invoke_aspect",
        %{
          "aspect-id" => _aspect_id,
          "entity-id" => entity_id,
          "description" => description,
          "free" => free
        },
        socket
      ) do
    is_free = free == "true"
    branch_id = socket.assigns.bookmark_id

    for attrs <- ModalSubmit.ring_invoke_aspect_events(entity_id, description, is_free) do
      Fate.Engine.append_event(branch_id, attrs)
    end

    {:noreply, socket}
  end

  def handle_event(
        "compel_aspect",
        %{"entity-id" => entity_id, "aspect-id" => aspect_id, "description" => description},
        socket
      ) do
    branch_id = socket.assigns.bookmark_id

    for attrs <- ModalSubmit.ring_compel_accepted_events(entity_id, aspect_id, description) do
      Fate.Engine.append_event(branch_id, attrs)
    end

    {:noreply, socket}
  end

  def handle_event(
        "begin_recovery",
        %{
          "consequence-id" => consequence_id,
          "entity-id" => entity_id,
          "aspect-text" => aspect_text
        },
        socket
      ) do
    Fate.Engine.append_event(socket.assigns.bookmark_id, %{
      type: :consequence_recover,
      target_id: entity_id,
      description: "Begin recovery: #{aspect_text}",
      detail: %{"entity_id" => entity_id, "consequence_id" => consequence_id, "clear" => false}
    })

    {:noreply, socket}
  end

  def handle_event(
        "clear_consequence",
        %{"consequence-id" => consequence_id, "entity-id" => entity_id},
        socket
      ) do
    Fate.Engine.append_event(socket.assigns.bookmark_id, %{
      type: :consequence_recover,
      target_id: entity_id,
      description: "Clear consequence",
      detail: %{"entity_id" => entity_id, "consequence_id" => consequence_id, "clear" => true}
    })

    {:noreply, socket}
  end

  def handle_event("toggle_expand", %{"entity-id" => entity_id}, socket) do
    expanded = socket.assigns.expanded_entities

    expanded =
      if MapSet.member?(expanded, entity_id),
        do: MapSet.delete(expanded, entity_id),
        else: MapSet.put(expanded, entity_id)

    socket =
      socket
      |> assign(:expanded_entities, expanded)
      |> push_event("expanded_entities_changed", %{expanded: MapSet.to_list(expanded)})

    {:noreply, socket}
  end

  def handle_event("restore_expanded_entities", %{"expanded" => ids}, socket) when is_list(ids) do
    {:noreply, assign(socket, :expanded_entities, MapSet.new(ids))}
  end

  def handle_event(
        "adjust_skill",
        %{"entity-id" => entity_id, "skill" => skill, "delta" => delta},
        socket
      ) do
    {delta, _} = Integer.parse(delta)
    state = socket.assigns.state
    entity = Map.get(state.entities, entity_id)
    current = (entity && Map.get(entity.skills, skill, 0)) || 0
    new_rating = current + delta

    if new_rating <= 0 do
      Fate.Engine.append_event(socket.assigns.bookmark_id, %{
        type: :skill_set,
        target_id: entity_id,
        description: "Remove #{skill}",
        detail: %{"entity_id" => entity_id, "skill" => skill, "rating" => 0}
      })
    else
      Fate.Engine.append_event(socket.assigns.bookmark_id, %{
        type: :skill_set,
        target_id: entity_id,
        description: "#{skill} → +#{new_rating}",
        detail: %{"entity_id" => entity_id, "skill" => skill, "rating" => new_rating}
      })
    end

    {:noreply, socket}
  end

  def handle_event("remove_stunt", %{"entity-id" => entity_id, "stunt-id" => stunt_id}, socket) do
    Fate.Engine.append_event(socket.assigns.bookmark_id, %{
      type: :stunt_remove,
      target_id: entity_id,
      description: "Remove stunt",
      detail: %{"entity_id" => entity_id, "stunt_id" => stunt_id}
    })

    {:noreply, socket}
  end

  def handle_event("add_skill", %{"entity-id" => entity_id, "skill" => skill}, socket) do
    Fate.Engine.append_event(socket.assigns.bookmark_id, %{
      type: :skill_set,
      target_id: entity_id,
      description: "#{skill} → +1",
      detail: %{"entity_id" => entity_id, "skill" => skill, "rating" => 1}
    })

    {:noreply, socket}
  end

  def handle_event("open_add_stunt", %{"entity-id" => entity_id}, socket) do
    {:noreply, assign(socket, :table_modal, {"stunt_add", entity_id})}
  end

  def handle_event(
        "submit_table_modal",
        %{"stunt_name" => _, "stunt_effect" => _} = params,
        socket
      ) do
    case socket.assigns.table_modal do
      {"stunt_add", entity_id} ->
        attrs = FateWeb.ModalSubmit.stunt_add_attrs(params, entity_id)
        Fate.Engine.append_event(socket.assigns.bookmark_id, attrs)

        {:noreply, assign(socket, :table_modal, nil)}

      _ ->
        handle_event("submit_table_modal", params, socket)
    end
  end

  def handle_event("select", %{"id" => id, "type" => type}, socket) do
    item = %{id: id, type: type}

    selection =
      if item in socket.assigns.selection do
        List.delete(socket.assigns.selection, item)
      else
        socket.assigns.selection ++ [item]
      end

    FateWeb.Helpers.broadcast_selection(socket, selection)

    {:noreply, assign(socket, :selection, selection)}
  end

  def handle_event("clear_selection", _params, socket) do
    FateWeb.Helpers.broadcast_selection(socket, [])
    {:noreply, assign(socket, :selection, [])}
  end

  def handle_event(
        "ring_action",
        %{"action" => "add_entity_aspect", "entity-id" => entity_id},
        socket
      ) do
    {:noreply, assign(socket, :table_modal, {"entity_aspect_add", entity_id})}
  end

  def handle_event(
        "ring_action",
        %{"action" => "add_entity_note", "entity-id" => entity_id},
        socket
      ) do
    {:noreply, assign(socket, :table_modal, {"note_create_for", entity_id})}
  end

  def handle_event(
        "ring_action",
        %{"action" => "edit_entity", "entity-id" => entity_id},
        socket
      ) do
    if can_edit_entity?(socket, entity_id) do
      {:noreply, assign(socket, :table_modal, {"entity_edit", entity_id})}
    else
      {:noreply, socket}
    end
  end

  def handle_event("ring_action", %{"action" => action, "entity-id" => entity_id}, socket) do
    branch_id = socket.assigns.bookmark_id

    case action do
      "fp_earn" ->
        Fate.Engine.append_event(
          branch_id,
          ModalSubmit.fate_point_earn_attrs(%{"entity_id" => entity_id})
        )

      "fp_spend" ->
        Fate.Engine.append_event(
          branch_id,
          ModalSubmit.fate_point_spend_attrs(%{"entity_id" => entity_id})
        )

      "concede" ->
        Fate.Engine.append_event(branch_id, ModalSubmit.concede_attrs(entity_id))

      "reveal" ->
        reveal_entity(branch_id, entity_id, socket.assigns.state)

      "hide" ->
        hide_entity(branch_id, entity_id, socket.assigns.state)

      "remove" ->
        entity = Map.get(socket.assigns.state.entities, entity_id)

        Fate.Engine.append_event(
          branch_id,
          ModalSubmit.entity_remove_attrs(entity_id, entity && entity.name, entity && entity.kind)
        )

      "mook_eliminate" ->
        Fate.Engine.append_event(branch_id, ModalSubmit.mook_eliminate_attrs(entity_id))

      "taken_out" ->
        Fate.Engine.append_event(branch_id, ModalSubmit.taken_out_attrs(entity_id))

      "clear_stress" ->
        Fate.Engine.append_event(branch_id, ModalSubmit.stress_clear_attrs(entity_id))

      _ ->
        :ok
    end

    {:noreply, socket}
  end

  def handle_event("ring_action", %{"action" => "end_scene"}, socket) do
    active_scene = socket.assigns.state.active_scene

    if active_scene do
      Fate.Engine.append_event(
        socket.assigns.bookmark_id,
        ModalSubmit.active_scene_end_attrs(active_scene)
      )
    end

    {:noreply, socket}
  end

  def handle_event(
        "ring_action",
        %{"action" => "switch_scene", "template-id" => template_id},
        socket
      ) do
    {:noreply, socket |> assign(:current_template_id, template_id) |> assign(:table_modal, nil)}
  end

  def handle_event("ring_action", %{"action" => "start_scene"}, socket) do
    template_id = socket.assigns.current_template_id

    if template_id && socket.assigns.state.active_scene == nil do
      Fate.Engine.append_event(
        socket.assigns.bookmark_id,
        ModalSubmit.active_scene_start_attrs(template_id)
      )
    end

    {:noreply, socket}
  end

  def handle_event("ring_action", %{"action" => "new_scene"}, socket) do
    {:noreply, assign(socket, :table_modal, "scene_start")}
  end

  def handle_event("ring_action", %{"action" => "switch_scene_list"}, socket) do
    {:noreply, assign(socket, :table_modal, "switch_scene")}
  end

  def handle_event("ring_action", %{"action" => "add_zone"}, socket) do
    {:noreply, assign(socket, :table_modal, "zone_create")}
  end

  def handle_event("open_note", _params, socket) do
    {:noreply, assign(socket, :table_modal, "note_create")}
  end

  def handle_event("open_cheat_sheet", _params, socket) do
    {:noreply, assign(socket, :table_modal, "cheat_sheet")}
  end

  def handle_event("ring_action", %{"action" => "add_scene_aspect"}, socket) do
    {:noreply, assign(socket, :table_modal, "scene_aspect_create")}
  end

  def handle_event(
        "apply_stress",
        %{"entity-id" => entity_id, "track-label" => track_label, "box-index" => box_str},
        socket
      ) do
    {box_index, _} = Integer.parse(box_str)
    state = socket.assigns.state
    entity = Map.get(state.entities, entity_id)

    already_checked =
      entity &&
        Enum.any?(entity.stress_tracks, fn track ->
          track.label == track_label && box_index in track.checked
        end)

    unless already_checked do
      Fate.Engine.append_event(socket.assigns.bookmark_id, %{
        type: :stress_apply,
        target_id: entity_id,
        description: "Apply stress: #{track_label} box #{box_index}",
        detail: %{
          "entity_id" => entity_id,
          "track_label" => track_label,
          "box_index" => box_index,
          "shifts_absorbed" => box_index
        }
      })
    end

    {:noreply, socket}
  end

  def handle_event(
        "toggle_zone_visibility",
        %{"zone-id" => zone_id, "scene-id" => _scene_id},
        socket
      ) do
    current = displayed_scene(socket.assigns.state, socket.assigns.current_template_id)
    zone = current && Enum.find(current.zones, &(&1.id == zone_id))

    if zone do
      type =
        if socket.assigns.state.active_scene, do: :active_zone_modify, else: :template_zone_modify

      Fate.Engine.append_event(socket.assigns.bookmark_id, %{
        type: type,
        description: "#{if zone.hidden, do: "Reveal", else: "Hide"} zone: #{zone.name}",
        detail: %{"zone_id" => zone_id, "hidden" => !zone.hidden}
      })
    end

    {:noreply, socket}
  end

  def handle_event("toggle_scene_aspect_visibility", %{"aspect-id" => aspect_id}, socket) do
    aspect = find_scene_aspect(socket.assigns.state, aspect_id)

    if aspect do
      scene = displayed_scene(socket.assigns.state, socket.assigns.current_template_id)

      parent_name = if scene, do: scene.name, else: "scene"
      action = if aspect.hidden, do: "Reveal", else: "Hide"

      detail =
        case Replay.find_aspect_container(socket.assigns.state, aspect_id) do
          {:ok, tt, tid} ->
            %{
              "aspect_id" => aspect_id,
              "hidden" => !aspect.hidden,
              "target_type" => tt,
              "target_id" => tid
            }

          :error ->
            %{"aspect_id" => aspect_id, "hidden" => !aspect.hidden}
        end

      type = if socket.assigns.state.active_scene, do: :active_aspect_modify, else: :aspect_modify

      Fate.Engine.append_event(socket.assigns.bookmark_id, %{
        type: type,
        description: "#{action} #{parent_name}: #{aspect.description}",
        detail: detail
      })
    end

    {:noreply, socket}
  end

  def handle_event(
        "toggle_entity_aspect_visibility",
        %{"aspect-id" => aspect_id, "entity-id" => entity_id},
        socket
      ) do
    entity = Map.get(socket.assigns.state.entities, entity_id)
    aspect = entity && Enum.find(entity.aspects, &(&1.id == aspect_id))

    if aspect do
      action = if aspect.hidden, do: "Reveal", else: "Hide"

      Fate.Engine.append_event(socket.assigns.bookmark_id, %{
        type: :aspect_modify,
        target_id: entity_id,
        description: "#{action} #{entity.name}: #{aspect.description}",
        detail: %{
          "aspect_id" => aspect_id,
          "hidden" => !aspect.hidden,
          "target_type" => "entity",
          "target_id" => entity_id
        }
      })
    end

    {:noreply, socket}
  end

  def handle_event("close_table_modal", _params, socket) do
    {:noreply, assign(socket, :table_modal, nil)}
  end

  def handle_event("submit_table_modal", params, socket) do
    new_scene_id =
      case socket.assigns.table_modal do
        "scene_start" ->
          scene_id = Ash.UUID.generate()

          Fate.Engine.append_event(
            socket.assigns.bookmark_id,
            FateWeb.ModalSubmit.template_scene_create_attrs(params, scene_id)
          )

          scene_id

        "zone_create" ->
          state = socket.assigns.state

          if state.active_scene do
            Fate.Engine.append_event(
              socket.assigns.bookmark_id,
              FateWeb.ModalSubmit.active_zone_add_attrs(params)
            )
          else
            scene =
              Enum.find(state.scene_templates, &(&1.id == socket.assigns.current_template_id))

            if scene do
              Fate.Engine.append_event(
                socket.assigns.bookmark_id,
                FateWeb.ModalSubmit.template_zone_create_attrs(scene.id, params)
              )
            end
          end

          nil

        "scene_aspect_create" ->
          active_scene? = socket.assigns.state.active_scene != nil

          case FateWeb.ModalSubmit.aspect_create_attrs(params, {:table_scene, active_scene?}) do
            {:ok, attrs} ->
              Fate.Engine.append_event(socket.assigns.bookmark_id, attrs)

            :error ->
              nil
          end

          nil

        {"note_create_for", _entity_id} ->
          case FateWeb.ModalSubmit.note_attrs(params) do
            {:ok, attrs} -> Fate.Engine.append_event(socket.assigns.bookmark_id, attrs)
            :error -> nil
          end

          nil

        "note_create" ->
          case FateWeb.ModalSubmit.note_attrs(params) do
            {:ok, attrs} -> Fate.Engine.append_event(socket.assigns.bookmark_id, attrs)
            :error -> nil
          end

          nil

        {"entity_aspect_add", entity_id} ->
          case FateWeb.ModalSubmit.aspect_create_attrs(params, {:table_entity, entity_id}) do
            {:ok, attrs} ->
              Fate.Engine.append_event(socket.assigns.bookmark_id, attrs)

            :error ->
              nil
          end

          nil

        {"entity_edit", modal_entity_id} ->
          if params["entity_id"] == modal_entity_id &&
               can_edit_entity?(socket, modal_entity_id) do
            entity = Map.get(socket.assigns.state.entities, modal_entity_id)

            if entity do
              label =
                String.trim(params["name"] || "")
                |> then(&if(&1 != "", do: &1, else: entity.name))

              Fate.Engine.append_event(
                socket.assigns.bookmark_id,
                FateWeb.ModalSubmit.entity_modify_attrs(
                  params,
                  socket.assigns.participants,
                  label
                )
              )
            end
          end

          nil

        _ ->
          nil
      end

    socket =
      socket
      |> assign(:table_modal, nil)
      |> then(fn s ->
        if new_scene_id, do: assign(s, :current_template_id, new_scene_id), else: s
      end)

    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id="ide-shell"
      class="flex h-screen w-screen"
      phx-hook=".PanelState"
      data-gm-panel-open={to_string(@gm_panel_open)}
      data-player-panel-open={to_string(@player_panel_open)}
      phx-window-keydown={if @table_modal, do: "close_table_modal"}
      phx-key={if @table_modal, do: "Escape"}
    >
      <%!-- GM panel (embedded) --%>
      <%= if @is_gm do %>
        <div class={[
          "shrink-0 overflow-hidden transition-[width] duration-150 ease-in-out",
          if(@gm_panel_open, do: "w-80 border-r border-amber-900/30", else: "w-0")
        ]}>
          <div class="w-80 h-full">
            {live_render(@socket, FateWeb.GmPanelLive,
              id: "gm-panel",
              session: %{"bookmark_id" => @bookmark_id, "embedded" => true}
            )}
          </div>
        </div>
      <% end %>

      <%!-- Table surface --%>
      <div
        id="table-view"
        class="relative flex-1 h-full overflow-hidden"
        style="background: #1a3a1a url('/images/felt.png') repeat; background-size: 512px 512px;"
        phx-hook="SpringLayout"
        data-scene-key={@bookmark_id || "default"}
        data-scene-id={
          (@state && @state.active_scene && @state.active_scene.template_id) || @current_template_id ||
            "none"
        }
        data-participant-key={@current_participant_id || "gm"}
      >
        <div
          id="table-felt-clear-selection"
          class="absolute inset-0 z-0"
          phx-click="clear_selection"
          title="Click to clear selection"
        />
        <%= if @splash_visible do %>
          <div
            id="splash"
            class="absolute inset-0 z-[100] flex items-center justify-center"
            style="background: #1a3a1a url('/images/felt.png') repeat; background-size: 512px 512px;"
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

        <%!-- Activity bar icons (overlaid on table surface) --%>
        <%= if @is_gm do %>
          <div class="absolute top-3 left-3 z-50 flex flex-col gap-1">
            <button
              phx-click="toggle_panel"
              phx-value-panel="gm"
              class="p-1.5 transition-all activity-icon"
              title={
                if @gm_panel_open, do: "Hide the GM Tools sidebar", else: "Show the GM Tools sidebar"
              }
            >
              <.icon
                name={if @gm_panel_open, do: "hero-bookmark-slash", else: "hero-bookmark"}
                class="w-5 h-5"
              />
            </button>
            <button
              id="detach-gm"
              phx-click="detach_panel"
              phx-value-panel="gm"
              phx-hook=".DetachPanel"
              data-panel-url={~p"/panel/gm/#{@bookmark_id || ""}"}
              data-window-name="fate-gm-panel"
              class="p-1.5 transition-all activity-icon"
              title={
                if @gm_panel_open,
                  do: "Undock the GM Tools sidebar",
                  else: "Open GM Tools in a separate browser window"
              }
            >
              <.icon name="hero-arrow-up-right" class="w-5 h-5" />
            </button>
          </div>
        <% end %>

        <div class="absolute top-3 right-3 z-50 flex flex-col gap-1">
          <button
            phx-click="toggle_panel"
            phx-value-panel="player"
            class="p-1.5 transition-all activity-icon"
            title={
              if @player_panel_open, do: "Hide the Events sidebar", else: "Show the Events sidebar"
            }
          >
            <.icon
              name={if @player_panel_open, do: "hero-bolt-slash", else: "hero-bolt"}
              class="w-5 h-5"
            />
          </button>
          <button
            id="detach-player"
            phx-click="detach_panel"
            phx-value-panel="player"
            phx-hook=".DetachPanel"
            data-panel-url={~p"/panel/player/#{@bookmark_id || ""}"}
            data-window-name="fate-player-panel"
            class="p-1.5 transition-all activity-icon"
            title={
              if @player_panel_open,
                do: "Undock the Events sidebar",
                else: "Open Events in a separate browser window"
            }
          >
            <.icon name="hero-arrow-up-right" class="w-5 h-5" />
          </button>
          <%= unless @is_observer do %>
            <button
              phx-click="open_note"
              class="p-1.5 transition-all activity-icon mt-1"
              title="Make a note"
            >
              <.icon name="hero-pencil-square" class="w-5 h-5" />
            </button>
          <% end %>
          <button
            phx-click="open_cheat_sheet"
            class="p-1.5 transition-all activity-icon"
            title="Cheat sheet"
          >
            <.icon name="hero-book-open" class="w-5 h-5" />
          </button>
          <button
            id="fullscreen-toggle"
            phx-hook=".Fullscreen"
            phx-update="ignore"
            class="p-1.5 transition-all activity-icon"
            title="Toggle fullscreen"
          >
            <.icon name="hero-arrows-pointing-out" class="w-5 h-5" />
          </button>
        </div>

        <%= if @state do %>
          <script :type={Phoenix.LiveView.ColocatedHook} name=".Fullscreen">
            export default {
              mounted() {
                this.el.addEventListener("click", () => {
                  if (!document.fullscreenElement) {
                    document.documentElement.requestFullscreen();
                  } else {
                    document.exitFullscreen();
                  }
                });
                document.addEventListener("fullscreenchange", () => {
                  const icon = this.el.querySelector("span");
                  if (document.fullscreenElement) {
                    icon.className = icon.className.replace("hero-arrows-pointing-out", "hero-arrows-pointing-in");
                  } else {
                    icon.className = icon.className.replace("hero-arrows-pointing-in", "hero-arrows-pointing-out");
                  }
                });
              }
            }
          </script>

          <%!-- === Participant labels on the border === --%>

          <%!-- Current user on the border (unless observer) --%>
          <%= unless @is_observer do %>
            <% current_bp =
              Enum.find(@participants, fn bp -> bp.participant_id == @current_participant_id end) %>
            <% current_color = if(current_bp, do: current_bp.participant.color, else: "#ef4444") %>
            <div
              class="absolute spring-element"
              data-element-id="gm-label"
              data-on-border="true"
              data-anchor="gm-border"
              data-pinned="true"
              data-dock-edge={@dock_position}
              data-participant-id={@current_participant_id || "self"}
            >
              <div class="text-center px-4 py-2 group/self">
                <span
                  class="text-2xl font-bold participant-name"
                  style={"font-family: 'Patrick Hand', cursive; color: #{current_color};"}
                >
                  {@current_participant_name || "You"}
                </span>
                <%= if @is_gm do %>
                  <span class="text-sm text-red-300/60 ml-1 participant-name">GM</span>
                <% end %>
                <button
                  id="logout-btn"
                  phx-hook=".Logout"
                  class="ml-2 opacity-0 group-hover/self:opacity-100 transition-opacity text-amber-200/40 hover:text-amber-200/80 touch-reveal"
                  title="Leave table"
                >
                  <.icon name="hero-arrow-right-start-on-rectangle" class="w-4 h-4" />
                </button>
              </div>
            </div>
          <% end %>

          <%!-- === GM Notes Card (always visible for GM) === --%>
          <%= if @is_gm do %>
            <% gm_scene = @state && displayed_scene(@state, @current_template_id) %>
            <div
              class="absolute spring-element"
              data-anchor="gm"
              data-element-id="gm-notes-card"
            >
              <div
                class={[
                  "p-3 rounded-lg shadow-lg gm-notes-inner",
                  @state.active_scene && "ring-2 ring-red-500/30"
                ]}
                style="background: #1a1510; border: 1px solid rgba(180, 140, 80, 0.3); width: 280px;"
              >
                <div
                  class="ring-trigger"
                  style="position: absolute; top: -0.375rem; right: -0.375rem; z-index: 10;"
                  id="gm-notes-trigger"
                  phx-hook="FateWeb.TableComponents.RingTrigger"
                >
                  <div class="w-5 h-5 rounded-full bg-amber-700 hover:bg-amber-600 cursor-pointer flex items-center justify-center transition">
                    <.icon name="hero-cog-6-tooth" class="w-3 h-3 text-amber-200" />
                  </div>
                  <.gm_notes_ring state={@state} active_scene={@state.active_scene} />
                </div>
                <%!-- LIVE/PREP indicator — always visible on the card --%>
                <div
                  class="absolute flex items-center gap-1"
                  style="top: -0.375rem; left: -0.375rem; z-index: 10;"
                >
                  <%= if @state.active_scene do %>
                    <span class="flex items-center gap-1 px-1.5 py-0.5 rounded-full bg-red-900/80 border border-red-500/50">
                      <span class="w-1.5 h-1.5 rounded-full bg-red-500 animate-pulse"></span>
                      <span class="text-red-400 text-[0.55rem] font-bold uppercase tracking-wider leading-none">
                        Live
                      </span>
                    </span>
                  <% else %>
                    <span class="px-1.5 py-0.5 rounded-full bg-amber-900/50 border border-amber-700/30">
                      <span class="text-amber-200/40 text-[0.55rem] font-bold uppercase tracking-wider leading-none">
                        Prep
                      </span>
                    </span>
                  <% end %>
                </div>
                <%= if gm_scene do %>
                  <div
                    class="text-sm font-bold text-amber-100/90 mb-1"
                    style="font-family: 'Patrick Hand', cursive;"
                  >
                    {gm_scene.name}
                  </div>
                  <%= if gm_scene.description do %>
                    <div
                      class="text-lg text-amber-200/50 mb-2 leading-snug"
                      style="font-family: 'Caveat', cursive;"
                    >
                      {gm_scene.description}
                    </div>
                  <% end %>
                <% end %>
                <%= if gm_scene && gm_scene.gm_notes do %>
                  <div
                    class="text-sm text-amber-200/60 border-t border-amber-700/20 pt-2 mt-1 leading-snug"
                    style="font-family: 'Patrick Hand', cursive;"
                  >
                    {gm_scene.gm_notes}
                  </div>
                <% end %>
                <%= if is_nil(gm_scene) do %>
                  <div class="text-xs text-amber-200/30 italic">No active scene</div>
                <% end %>
                <div class="text-xs text-amber-200/20 mt-2 uppercase tracking-wide">GM Notes</div>
                <div class="gm-resize-handle" id="gm-notes-resize" phx-hook=".GmNotesResize"></div>
              </div>
            </div>
          <% end %>

          <%!-- Other participants on the border (exclude current user) --%>
          <%= for bp <- Enum.reject(@participants, &(&1.participant_id == @current_participant_id)) do %>
            <div
              class="absolute spring-element"
              data-element-id={"player-#{bp.participant_id}"}
              data-on-border="true"
              data-anchor="player-border"
              data-dock-edge={@dock_position}
              data-participant-id={bp.participant_id}
            >
              <div class="text-center px-4 py-2">
                <span
                  class="text-2xl font-bold participant-name"
                  style={"font-family: 'Patrick Hand', cursive; color: #{bp.participant.color};"}
                >
                  {bp.participant.name}
                </span>
              </div>
            </div>
          <% end %>

          <%!-- === Scene title — anchored at 2/3 offset from GM === --%>
          <% active_scene = displayed_scene(@state, @current_template_id) %>
          <%= if active_scene do %>
            <div
              class="absolute spring-element"
              data-anchor="scene"
              data-element-id="scene-title"
              data-pinned="true"
            >
              <div class="text-center px-4 py-2">
                <h2
                  class="text-3xl text-amber-100/80"
                  style="font-family: 'Caveat', cursive; font-weight: 700;"
                >
                  {active_scene.name}
                </h2>
                <%= if active_scene.description do %>
                  <p
                    class="text-amber-200/50 text-xl mt-1 max-w-lg"
                    style="font-family: 'Caveat', cursive;"
                  >
                    {active_scene.description}
                  </p>
                <% end %>
              </div>
            </div>
          <% end %>

          <%!-- === Visible uncontrolled entities — anchored to scene (or parent) === --%>
          <%= for entity <- visible_uncontrolled_entities(@state, @is_gm) do %>
            <div
              class="absolute spring-element"
              data-anchor={if(entity.parent_id, do: "entity-#{entity.parent_id}", else: "centre")}
              data-anchor-fallback="centre"
              data-element-id={"entity-#{entity.id}"}
              phx-mounted={JS.transition("entity-warp-in", time: 1000)}
              phx-remove={JS.transition("entity-warp-out", time: 1000)}
            >
              <.entity_card
                entity={entity}
                is_gm={@is_gm}
                is_observer={@is_observer}
                current_participant_id={@current_participant_id}
                selected={%{id: entity.id, type: "entity"} in @selection}
                expanded={MapSet.member?(@expanded_entities, entity.id)}
                can_expand={@is_gm || entity.kind == :pc}
              />
            </div>
          <% end %>

          <%!-- === Hidden entities (GM only) — anchored to GM (or parent) === --%>
          <%= if @is_gm do %>
            <%= for entity <- hidden_entities(@state) do %>
              <div
                class="absolute spring-element opacity-40 hover:opacity-80 transition-opacity duration-300"
                data-anchor={if(entity.parent_id, do: "entity-#{entity.parent_id}", else: "gm")}
                data-anchor-fallback="gm"
                data-element-id={"entity-#{entity.id}"}
              >
                <.entity_card
                  entity={entity}
                  is_gm={@is_gm}
                  is_observer={@is_observer}
                  current_participant_id={@current_participant_id}
                  selected={%{id: entity.id, type: "entity"} in @selection}
                  expanded={MapSet.member?(@expanded_entities, entity.id)}
                  can_expand={true}
                />
              </div>
            <% end %>
          <% end %>

          <%!-- === Controlled entities — anchored to their controller on the border === --%>
          <%= for entity <- controlled_entities_all(@state) do %>
            <div
              class="absolute spring-element"
              data-anchor={"controller-#{entity.controller_id}"}
              data-controller-id={entity.controller_id}
              data-element-id={"entity-#{entity.id}"}
            >
              <.entity_card
                entity={entity}
                is_gm={@is_gm}
                is_observer={@is_observer}
                current_participant_id={@current_participant_id}
                selected={%{id: entity.id, type: "entity"} in @selection}
                expanded={MapSet.member?(@expanded_entities, entity.id)}
                can_expand={@is_gm || entity.kind == :pc}
              />
            </div>
          <% end %>

          <%!-- === Zones — anchored to scene === --%>
          <% active_scene_zones = if active_scene, do: active_scene.zones, else: [] %>
          <% visible_zones =
            if @is_gm, do: active_scene_zones, else: Enum.reject(active_scene_zones, & &1.hidden) %>
          <%= for zone <- visible_zones do %>
            <div
              class={[
                "absolute spring-element",
                zone.hidden && "opacity-40 hover:opacity-70 transition-opacity duration-300"
              ]}
              data-anchor="centre"
              data-element-id={"zone-#{zone.id}"}
              data-zone-only-repulsion="true"
              phx-mounted={JS.transition("entity-warp-in", time: 1000)}
            >
              <div
                class="zone-box relative"
                phx-hook="ZoneDropTarget"
                id={"zone-drop-#{zone.id}"}
                data-zone-id={zone.id}
              >
                <%= if @is_gm do %>
                  <button
                    phx-click="toggle_zone_visibility"
                    phx-value-zone-id={zone.id}
                    phx-value-scene-id={active_scene && active_scene.id}
                    class={[
                      "absolute -top-2 -right-2 w-5 h-5 rounded-full flex items-center justify-center text-xs shadow-lg transition z-10",
                      if(zone.hidden,
                        do: "bg-amber-600 hover:bg-amber-500 text-white opacity-100",
                        else:
                          "bg-gray-600 hover:bg-gray-500 text-white opacity-0 hover:opacity-100 touch-reveal"
                      )
                    ]}
                    data-tooltip={if(zone.hidden, do: "Reveal zone", else: "Hide zone")}
                  >
                    <.icon
                      name={if(zone.hidden, do: "hero-eye", else: "hero-eye-slash")}
                      class="w-3 h-3"
                    />
                  </button>
                <% end %>
                <div
                  class="text-xs uppercase text-amber-200/50 font-bold mb-1 tracking-wide"
                  style="font-family: 'Patrick Hand', cursive;"
                >
                  {zone.name}
                </div>

                <%!-- Entity tokens in this zone --%>
                <div class="flex flex-col gap-1 mt-1">
                  <%= for entity <- entities_in_zone(@state, zone.id) do %>
                    <div
                      class="zone-token"
                      style={"background: #{entity.color || "#6b7280"};"}
                      draggable="true"
                      phx-hook="DraggableToken"
                      id={"zone-token-#{entity.id}"}
                      data-entity-id={entity.id}
                      data-entity-name={entity.name}
                      data-entity-color={entity.color || "#6b7280"}
                      data-source="zone"
                    >
                      {entity.name}
                    </div>
                  <% end %>
                </div>
              </div>
            </div>
          <% end %>

          <%!-- === Scene aspects — anchored to scene or zone === --%>
          <%= for {aspect, zone_id} <- scene_aspects(@state, @is_gm, @current_template_id) do %>
            <div
              class={[
                "absolute spring-element",
                aspect.hidden && "opacity-40 hover:opacity-70 transition-opacity duration-300"
              ]}
              data-anchor={if(zone_id, do: "zone-#{zone_id}", else: "centre")}
              data-anchor-fallback="centre"
              data-element-id={"aspect-#{aspect.id}"}
              phx-mounted={JS.transition("entity-warp-in", time: 1000)}
            >
              <.aspect_card
                aspect={aspect}
                selected={%{id: aspect.id, type: "aspect"} in @selection}
                is_gm={@is_gm}
                is_observer={@is_observer}
              />
            </div>
          <% end %>
        <% end %>

        <script :type={Phoenix.LiveView.ColocatedHook} name=".GmNotesResize">
          export default {
            mounted() {
              const startResize = (clientX, clientY) => {
                const inner = this.el.closest(".gm-notes-inner")
                if (!inner) return null
                return {
                  inner,
                  startX: clientX,
                  startY: clientY,
                  startW: inner.offsetWidth,
                  startH: inner.offsetHeight,
                }
              }

              const applyResize = (ctx, clientX, clientY) => {
                const w = Math.min(500, Math.max(200, ctx.startW + clientX - ctx.startX))
                const h = Math.min(500, Math.max(80, ctx.startH + clientY - ctx.startY))
                ctx.inner.style.width = w + "px"
                ctx.inner.style.height = h + "px"
              }

              this.el.addEventListener("mousedown", (e) => {
                e.stopPropagation()
                e.preventDefault()
                const ctx = startResize(e.clientX, e.clientY)
                if (!ctx) return

                const onMove = (ev) => applyResize(ctx, ev.clientX, ev.clientY)
                const onUp = () => {
                  document.removeEventListener("mousemove", onMove)
                  document.removeEventListener("mouseup", onUp)
                }
                document.addEventListener("mousemove", onMove)
                document.addEventListener("mouseup", onUp)
              })

              let touchCtx = null
              this.el.addEventListener("touchstart", (e) => {
                if (e.touches.length !== 1) return
                e.stopPropagation()
                const touch = e.touches[0]
                touchCtx = startResize(touch.clientX, touch.clientY)
              }, { passive: true })

              this._onTouchMove = (e) => {
                if (!touchCtx) return
                e.preventDefault()
                const touch = e.touches[0]
                applyResize(touchCtx, touch.clientX, touch.clientY)
              }
              this._onTouchEnd = () => { touchCtx = null }

              document.addEventListener("touchmove", this._onTouchMove, { passive: false })
              document.addEventListener("touchend", this._onTouchEnd)
              document.addEventListener("touchcancel", this._onTouchEnd)
            },

            destroyed() {
              document.removeEventListener("touchmove", this._onTouchMove)
              document.removeEventListener("touchend", this._onTouchEnd)
              document.removeEventListener("touchcancel", this._onTouchEnd)
            }
          }
        </script>

        <%!-- .RingTrigger hook is defined in TableComponents.entity_card --%>

        <script :type={Phoenix.LiveView.ColocatedHook} name=".Logout">
          export default {
            mounted() {
              this.el.addEventListener("click", () => {
                localStorage.removeItem("fate_participant_id")
                localStorage.removeItem("fate_name")
                localStorage.removeItem("fate_role")
                window.location.href = "/"
              })
            }
          }
        </script>

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
      </div>

      <%!-- === Table modal overlay (outside table-view to avoid stacking context) === --%>
      <%= if @state do %>
        <.table_modal
          modal={@table_modal}
          state={@state}
          current_template_id={@current_template_id}
          current_participant_id={@current_participant_id}
          is_gm={@is_gm}
          participants={@participants}
          mention_catalog_json={@mention_catalog_json}
        />
      <% end %>

      <%!-- Player panel (embedded) --%>
      <div class={[
        "shrink-0 overflow-hidden transition-[width] duration-150 ease-in-out",
        if(@player_panel_open, do: "w-96 border-l border-amber-900/30", else: "w-0")
      ]}>
        <div class="w-96 h-full">
          {live_render(@socket, FateWeb.PlayerPanelLive,
            id: "player-panel",
            session: %{"bookmark_id" => @bookmark_id, "embedded" => true}
          )}
        </div>
      </div>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".PanelState">
        export default {
          mounted() {
            try {
              const saved = JSON.parse(localStorage.getItem("fate-panel-state") || "{}")
              if (saved.gm_panel_open || saved.player_panel_open) {
                this.pushEvent("restore_panel_state", saved)
              }
            } catch(_) {}
          },
          updated() {
            const state = {
              gm_panel_open: this.el.dataset.gmPanelOpen === "true",
              player_panel_open: this.el.dataset.playerPanelOpen === "true"
            }
            localStorage.setItem("fate-panel-state", JSON.stringify(state))
          }
        }
      </script>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".DetachPanel">
        export default {
          mounted() {
            this.el.addEventListener("click", () => {
              const url = this.el.dataset.panelUrl
              const name = this.el.dataset.windowName
              if (url) {
                const w = Math.round(window.screen.width * 0.3)
                const h = window.screen.height
                const left = name === "fate-gm-panel" ? 0 : window.screen.width - w
                window.open(url, name, `width=${w},height=${h},top=0,left=${left}`)
              }
            })
          }
        }
      </script>
    </div>
    """
  end

  # --- Helper functions ---

  defp displayed_scene(state, current_template_id) do
    state.active_scene ||
      Enum.find(state.scene_templates, &(&1.id == current_template_id))
  end

  defp visible_uncontrolled_entities(state, _is_gm) do
    state.entities
    |> Map.values()
    |> Enum.filter(fn e -> is_nil(e.controller_id) && !e.hidden end)
  end

  defp hidden_entities(state) do
    state.entities
    |> Map.values()
    |> Enum.filter(fn e -> is_nil(e.controller_id) && e.hidden end)
  end

  defp reveal_entity(branch_id, entity_id, state) do
    entity = Map.get(state.entities, entity_id)

    if entity do
      Fate.Engine.append_event(branch_id, %{
        type: :entity_modify,
        target_id: entity_id,
        description: "Reveal #{entity.name}",
        detail: %{"entity_id" => entity_id, "hidden" => false}
      })
    end
  end

  defp hide_entity(branch_id, entity_id, state) do
    entity = Map.get(state.entities, entity_id)

    if entity do
      Fate.Engine.append_event(branch_id, %{
        type: :entity_modify,
        target_id: entity_id,
        description: "Hide #{entity.name}",
        detail: %{"entity_id" => entity_id, "hidden" => true}
      })

      Enum.each(entity.aspects, fn aspect ->
        unless aspect.hidden do
          Fate.Engine.append_event(branch_id, %{
            type: :aspect_modify,
            target_id: entity_id,
            description: "Hide #{entity.name} #{aspect.description}",
            detail: %{
              "aspect_id" => aspect.id,
              "hidden" => true,
              "target_type" => "entity",
              "target_id" => entity_id
            }
          })
        end
      end)
    end
  end

  defp find_scene_aspect(state, aspect_id) do
    scenes =
      if state.active_scene,
        do: [state.active_scene],
        else: state.scene_templates

    scenes
    |> Enum.flat_map(fn scene ->
      scene.aspects ++ Enum.flat_map(scene.zones, & &1.aspects)
    end)
    |> Enum.find(&(&1.id == aspect_id))
  end

  defp entities_in_zone(state, zone_id) do
    state.entities
    |> Map.values()
    |> Enum.filter(&(&1.zone_id == zone_id))
  end

  defp controlled_entities_all(state) do
    state.entities
    |> Map.values()
    |> Enum.filter(&(!is_nil(&1.controller_id)))
  end

  defp scene_aspects(state, is_gm, current_template_id) do
    scene = displayed_scene(state, current_template_id)

    if scene do
      scene_level = Enum.map(scene.aspects, &{&1, nil})

      zone_level =
        Enum.flat_map(scene.zones, fn zone ->
          if zone.hidden and not is_gm, do: [], else: Enum.map(zone.aspects, &{&1, zone.id})
        end)

      (scene_level ++ zone_level)
      |> Enum.filter(fn {aspect, _zone_id} -> is_gm || !aspect.hidden end)
    else
      []
    end
  end

  defp can_edit_entity?(socket, entity_id) do
    entity = Map.get(socket.assigns.state.entities, entity_id)

    entity &&
      (socket.assigns.is_gm ||
         entity.controller_id == socket.assigns.current_participant_id)
  end

  defp panel_assign("gm"), do: :gm_panel_open
  defp panel_assign("player"), do: :player_panel_open
  defp panel_assign(:gm), do: :gm_panel_open
  defp panel_assign(:player), do: :player_panel_open

  defp maybe_open_panel(socket, "gm"), do: assign(socket, :gm_panel_open, true)
  defp maybe_open_panel(socket, "player"), do: assign(socket, :player_panel_open, true)
  defp maybe_open_panel(socket, _), do: socket
end
