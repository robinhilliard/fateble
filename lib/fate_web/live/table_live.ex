defmodule FateWeb.TableLive do
  use FateWeb, :live_view

  alias Fate.Engine

  @impl true
  def mount(_params, _session, socket) do
    is_gm = is_localhost?(socket)

    socket =
      socket
      |> assign(:is_gm, is_gm)
      |> assign(:dock_position, :south)
      |> assign(:tent_size, 0.3)
      |> assign(:branch_id, nil)
      |> assign(:state, nil)
      |> assign(:participants, [])
      |> assign(:current_participant, nil)
      |> assign(:selection, [])
      |> assign(:table_modal, nil)

    {:ok, socket}
  end

  @impl true
  def handle_params(%{"branch_id" => branch_id}, _uri, socket) do
    if connected?(socket) do
      Engine.subscribe(branch_id)
      Phoenix.PubSub.subscribe(Fate.PubSub, "selection:#{branch_id}")

      case Engine.derive_state(branch_id) do
        {:ok, state} ->
          participants = load_branch_participants(branch_id)
          {:noreply,
           socket
           |> assign(:branch_id, branch_id)
           |> assign(:state, state)
           |> assign(:participants, participants)}

        {:error, _reason} ->
          {:noreply, put_flash(socket, :error, "Could not load branch")}
      end
    else
      {:noreply, assign(socket, :branch_id, branch_id)}
    end
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_info({:state_updated, state}, socket) do
    {:noreply, assign(socket, :state, state)}
  end

  def handle_info({:selection_updated, selection}, socket) do
    {:noreply, assign(socket, :selection, selection)}
  end

  @impl true
  def handle_event("set_dock", %{"position" => position}, socket) do
    position = String.to_existing_atom(position)
    {:noreply, assign(socket, :dock_position, position)}
  end

  def handle_event("set_tent_size", %{"size" => size}, socket) do
    {size, _} = Float.parse(size)
    {:noreply, assign(socket, :tent_size, size)}
  end

  def handle_event("remove_aspect", %{"aspect-id" => aspect_id, "entity-id" => entity_id}, socket) do
    Fate.Engine.append_event(socket.assigns.branch_id, %{
      type: :aspect_remove,
      target_id: entity_id,
      description: "Remove aspect",
      detail: %{"aspect_id" => aspect_id}
    })

    {:noreply, socket}
  end

  def handle_event("remove_scene_aspect", %{"aspect-id" => aspect_id}, socket) do
    Fate.Engine.append_event(socket.assigns.branch_id, %{
      type: :aspect_remove,
      description: "Remove scene aspect",
      detail: %{"aspect_id" => aspect_id}
    })

    {:noreply, socket}
  end

  def handle_event("remove_from_zone", %{"entity_id" => entity_id}, socket) do
    case Fate.Engine.append_event(socket.assigns.branch_id, %{
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
    case Fate.Engine.append_event(socket.assigns.branch_id, %{
      type: :entity_move,
      actor_id: entity_id,
      description: "Move to zone",
      detail: %{"entity_id" => entity_id, "zone_id" => zone_id}
    }) do
      {:ok, _state, _event} -> {:noreply, socket}
      {:error, reason} -> {:noreply, put_flash(socket, :error, inspect(reason))}
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

    if socket.assigns.branch_id do
      Phoenix.PubSub.broadcast(
        Fate.PubSub,
        "selection:#{socket.assigns.branch_id}",
        {:selection_updated, selection}
      )
    end

    {:noreply, assign(socket, :selection, selection)}
  end

  def handle_event("ring_action", %{"action" => action, "entity-id" => entity_id}, socket) do
    branch_id = socket.assigns.branch_id

    case action do
      "fp_earn" ->
        Fate.Engine.append_event(branch_id, %{
          type: :fate_point_earn,
          target_id: entity_id,
          description: "Earn fate point",
          detail: %{"entity_id" => entity_id, "amount" => 1}
        })

      "fp_spend" ->
        Fate.Engine.append_event(branch_id, %{
          type: :fate_point_spend,
          target_id: entity_id,
          description: "Spend fate point",
          detail: %{"entity_id" => entity_id, "amount" => 1}
        })

      "concede" ->
        Fate.Engine.append_event(branch_id, %{
          type: :concede,
          actor_id: entity_id,
          description: "Concede"
        })

      "reveal" ->
        reveal_entity_aspects(branch_id, entity_id, socket.assigns.state)

      "hide" ->
        hide_entity_aspects(branch_id, entity_id, socket.assigns.state)

      "remove" ->
        Fate.Engine.append_event(branch_id, %{
          type: :entity_remove,
          target_id: entity_id,
          description: "Remove entity"
        })

      _ ->
        :ok
    end

    {:noreply, socket}
  end

  def handle_event("ring_action", %{"action" => "end_scene"}, socket) do
    active = Enum.find(socket.assigns.state.scenes, &(&1.status == :active))

    if active do
      Fate.Engine.append_event(socket.assigns.branch_id, %{
        type: :scene_end,
        description: "End scene: #{active.name}",
        detail: %{"scene_id" => active.id}
      })
    end

    {:noreply, socket}
  end

  def handle_event("ring_action", %{"action" => "new_scene"}, socket) do
    {:noreply, assign(socket, :table_modal, "scene_start")}
  end

  def handle_event("ring_action", %{"action" => "add_zone"}, socket) do
    {:noreply, assign(socket, :table_modal, "zone_create")}
  end

  def handle_event("apply_stress", %{"entity-id" => entity_id, "track-label" => track_label, "box-index" => box_str}, socket) do
    {box_index, _} = Integer.parse(box_str)
    state = socket.assigns.state
    entity = Map.get(state.entities, entity_id)

    already_checked =
      entity &&
        Enum.any?(entity.stress_tracks, fn track ->
          track.label == track_label && box_index in track.checked
        end)

    unless already_checked do
      Fate.Engine.append_event(socket.assigns.branch_id, %{
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

  def handle_event("toggle_zone_visibility", %{"zone-id" => zone_id, "scene-id" => _scene_id}, socket) do
    active = Enum.find(socket.assigns.state.scenes, &(&1.status == :active))
    zone = active && Enum.find(active.zones, &(&1.id == zone_id))

    if zone do
      Fate.Engine.append_event(socket.assigns.branch_id, %{
        type: :zone_modify,
        description: "#{if zone.hidden, do: "Reveal", else: "Hide"} zone: #{zone.name}",
        detail: %{"zone_id" => zone_id, "hidden" => !zone.hidden}
      })
    end

    {:noreply, socket}
  end

  def handle_event("toggle_scene_aspect_visibility", %{"aspect-id" => aspect_id}, socket) do
    aspect = find_scene_aspect(socket.assigns.state, aspect_id)

    if aspect do
      {target_type, target_id} = find_aspect_owner(socket.assigns.state, aspect_id)

      Fate.Engine.append_event(socket.assigns.branch_id, %{
        type: :aspect_remove,
        description: "#{if aspect.hidden, do: "Reveal", else: "Hide"}: #{aspect.description}",
        detail: %{"aspect_id" => aspect_id}
      })

      Fate.Engine.append_event(socket.assigns.branch_id, %{
        type: :aspect_create,
        target_id: target_id,
        description: "#{if aspect.hidden, do: "Reveal", else: "Hide"}: #{aspect.description}",
        detail: %{
          "target_id" => target_id,
          "target_type" => target_type,
          "aspect_id" => aspect_id,
          "description" => aspect.description,
          "role" => to_string(aspect.role),
          "free_invokes" => aspect.free_invokes,
          "hidden" => !aspect.hidden
        }
      })
    end

    {:noreply, socket}
  end

  def handle_event("close_table_modal", _params, socket) do
    {:noreply, assign(socket, :table_modal, nil)}
  end

  def handle_event("submit_table_modal", params, socket) do
    case socket.assigns.table_modal do
      "scene_start" ->
        Fate.Engine.append_event(socket.assigns.branch_id, %{
          type: :scene_start,
          description: "Start scene: #{params["name"]}",
          detail: %{
            "scene_id" => Ash.UUID.generate(),
            "name" => params["name"],
            "description" => params["scene_description"],
            "gm_notes" => params["gm_notes"]
          }
        })

      "zone_create" ->
        active = Enum.find(socket.assigns.state.scenes, &(&1.status == :active))

        if active do
          Fate.Engine.append_event(socket.assigns.branch_id, %{
            type: :zone_create,
            description: "Create zone: #{params["name"]}",
            detail: %{
              "scene_id" => active.id,
              "zone_id" => Ash.UUID.generate(),
              "name" => params["name"],
              "hidden" => true
            }
          })
        end

      _ ->
        :ok
    end

    {:noreply, assign(socket, :table_modal, nil)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id="table-view"
      class="relative w-screen h-screen overflow-hidden"
      style="background: #2d1f0e; background-image: url('/images/felt-texture.png');"
      phx-hook="SpringLayout"
      data-scene-key={@branch_id || "default"}
      data-scene-id={active_scene_id(@state)}
    >
      <%= if @state == nil do %>
        <div class="flex items-center justify-center h-full">
          <div class="text-center">
            <h1 class="text-4xl font-bold text-amber-100 mb-4" style="font-family: 'Permanent Marker', cursive;">
              Fate Table
            </h1>
            <p class="text-amber-200/70 mb-8">No branch loaded. Select a branch to begin.</p>
            <.link navigate={~p"/branches"} class="px-6 py-3 bg-amber-700 text-amber-100 rounded-lg hover:bg-amber-600 transition">
              Browse Branches
            </.link>
          </div>
        </div>
      <% else %>
        <%!-- Window switcher --%>
        <a
          href={~p"/actions/#{@branch_id}"}
          target="fate-actions"
          class="absolute bottom-3 right-3 z-50 px-3 py-1.5 bg-amber-900/70 border border-amber-700/30 rounded-lg text-amber-200 text-sm hover:bg-amber-800/70 transition"
          style="font-family: 'Patrick Hand', cursive;"
        >
          Actions ↗
        </a>

        <%!-- === Participant labels on the border === --%>

        <%!-- GM (you) on the border --%>
        <div
          class="absolute spring-element"
          data-element-id="gm-label"
          data-on-border="true"
          data-anchor="gm-border"
          data-pinned="true"
          data-dock-edge={@dock_position}
          data-participant-id="gm"
        >
          <div class="text-center px-4 py-2">
            <span
              class="text-2xl font-bold participant-name"
              style="font-family: 'Patrick Hand', cursive; color: #ef4444;"
            >
              Robin
            </span>
            <span class="text-sm text-red-300/60 ml-1 participant-name">GM</span>
          </div>
        </div>

        <%!-- === GM Notes Card (always visible for GM) === --%>
        <%= if @is_gm do %>
          <% gm_scene = @state && @state.scenes |> Enum.find(&(&1.status == :active)) %>
          <div
            class="absolute spring-element"
            data-anchor="gm"
            data-element-id="gm-notes-card"
          >
            <div class="relative p-3 rounded-lg shadow-lg w-56" style="background: #1a1510; border: 1px solid rgba(180, 140, 80, 0.3);">
              <div
                class="w-5 h-5 rounded-full bg-amber-700 hover:bg-amber-600 cursor-pointer flex items-center justify-center transition entity-circle ring-trigger"
                style="position: absolute; top: -0.375rem; right: -0.375rem;"
                id="gm-notes-trigger"
                phx-hook=".RingTrigger"
              >
                <.icon name="hero-cog-6-tooth" class="w-3 h-3 text-amber-200" />
                <.gm_notes_ring state={@state} />
              </div>
              <%= if gm_scene do %>
                <div class="text-sm font-bold text-amber-100/90 mb-1" style="font-family: 'Patrick Hand', cursive;">
                  {gm_scene.name}
                </div>
                <%= if gm_scene.description do %>
                  <div class="text-xs text-amber-200/40 mb-2" style="font-family: 'Caveat', cursive;">
                    {gm_scene.description}
                  </div>
                <% end %>
              <% end %>
              <%= if gm_scene && gm_scene.gm_notes do %>
                <div class="text-xs text-amber-200/60 border-t border-amber-700/20 pt-2 mt-1" style="font-family: 'Patrick Hand', cursive;">
                  {gm_scene.gm_notes}
                </div>
              <% end %>
              <%= if is_nil(gm_scene) do %>
                <div class="text-xs text-amber-200/30 italic">No active scene</div>
              <% end %>
              <div class="text-xs text-amber-200/20 mt-2 uppercase tracking-wide">GM Notes</div>
            </div>
          </div>
        <% end %>

        <%!-- Other participants on the border (exclude GM) --%>
        <%= for bp <- Enum.reject(@participants, &(&1.role == :gm)) do %>
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
        <% active_scene = @state.scenes |> Enum.find(&(&1.status == :active)) %>
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
                  class="text-amber-200/50 text-lg mt-1 max-w-lg"
                  style="font-family: 'Caveat', cursive;"
                >
                  {active_scene.description}
                </p>
              <% end %>
            </div>
          </div>
        <% end %>

        <%!-- === Visible uncontrolled entities — anchored to scene === --%>
        <%= for entity <- visible_uncontrolled_entities(@state, @is_gm) do %>
          <div
            class="absolute spring-element"
            data-anchor="centre"
            data-element-id={"entity-#{entity.id}"}
            phx-mounted={JS.transition("entity-warp-in", time: 1000)}
            phx-remove={JS.transition("entity-warp-out", time: 1000)}
          >
            <.entity_card
              entity={entity}
              is_gm={@is_gm}
              selected={%{id: entity.id, type: "entity"} in @selection}
            />
          </div>
        <% end %>

        <%!-- === Hidden entities (GM only) — anchored to GM === --%>
        <%= if @is_gm do %>
          <%= for entity <- hidden_entities(@state) do %>
            <div
              class="absolute spring-element opacity-40 hover:opacity-80 transition-opacity duration-300"
              data-anchor="gm"
              data-element-id={"entity-#{entity.id}"}
            >
              <.entity_card
                entity={entity}
                is_gm={@is_gm}
                selected={%{id: entity.id, type: "entity"} in @selection}
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
              selected={%{id: entity.id, type: "entity"} in @selection}
            />
          </div>
        <% end %>

        <%!-- === Zones — anchored to scene === --%>
        <% active_scene_zones = if active_scene, do: active_scene.zones, else: [] %>
        <% visible_zones = if @is_gm, do: active_scene_zones, else: Enum.reject(active_scene_zones, & &1.hidden) %>
        <%= for zone <- visible_zones do %>
          <div
            class={["absolute spring-element", zone.hidden && "opacity-40 hover:opacity-70 transition-opacity duration-300"]}
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
                    if(zone.hidden, do: "bg-amber-600 hover:bg-amber-500 text-white", else: "bg-gray-600 hover:bg-gray-500 text-white opacity-0 hover:opacity-100")
                  ]}
                  title={if(zone.hidden, do: "Reveal zone", else: "Hide zone")}
                >
                  <.icon name={if(zone.hidden, do: "hero-eye", else: "hero-eye-slash")} class="w-3 h-3" />
                </button>
              <% end %>
              <div
                class="text-xs uppercase text-amber-200/50 font-bold mb-1 tracking-wide"
                style="font-family: 'Patrick Hand', cursive;"
              >
                {zone.name}
              </div>

              <%!-- Zone aspects --%>
              <%= for aspect <- visible_zone_aspects(zone.aspects, @is_gm) do %>
                <div class={["group/za text-xs px-1 py-0.5 rounded mb-1 flex items-center gap-1", aspect_style(aspect), aspect.hidden && "opacity-50"]}>
                  <span class="flex-1 text-gray-900" style="font-family: 'Permanent Marker', cursive; font-size: 0.65rem;">
                    {aspect.description}
                  </span>
                  <%= if @is_gm do %>
                    <button
                      phx-click="toggle_scene_aspect_visibility"
                      phx-value-aspect-id={aspect.id}
                      class="opacity-0 group-hover/za:opacity-100 transition-opacity text-gray-500 hover:text-gray-700"
                      title={if(aspect.hidden, do: "Reveal", else: "Hide")}
                    >
                      <.icon name={if(aspect.hidden, do: "hero-eye", else: "hero-eye-slash")} class="w-3 h-3" />
                    </button>
                  <% end %>
                </div>
              <% end %>

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
                  >
                    {entity.name}
                  </div>
                <% end %>
              </div>
            </div>
          </div>
        <% end %>

        <%!-- === Scene aspects — anchored to scene === --%>
        <%= for aspect <- scene_aspects(@state, @is_gm) do %>
          <div
            class={["absolute spring-element", aspect.hidden && "opacity-40 hover:opacity-70 transition-opacity duration-300"]}
            data-anchor="centre"
            data-element-id={"aspect-#{aspect.id}"}
            phx-mounted={JS.transition("entity-warp-in", time: 1000)}
          >
            <.aspect_card
              aspect={aspect}
              selected={%{id: aspect.id, type: "aspect"} in @selection}
              is_gm={@is_gm}
            />
          </div>
        <% end %>

        <%!-- === Table modal overlay === --%>
        <.table_modal modal={@table_modal} />

      <% end %>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".RingTrigger">
        export default {
          mounted() {
            this.ring = this.el.querySelector('.context-ring')
            if (!this.ring) return

            this._hideTimer = null
            this._positioned = false

            this.el.addEventListener('mouseenter', () => this.show())
            this.el.addEventListener('mouseleave', () => this.scheduleHide())

            const items = this.ring.querySelectorAll('.ring-item')
            items.forEach(item => {
              item.addEventListener('mouseenter', () => this.cancelHide())
              item.addEventListener('mouseleave', () => this.scheduleHide())
            })
          },

          updated() {
            this.ring = this.el.querySelector('.context-ring')
            this._positioned = false
          },

          position() {
            if (!this.ring) return
            const items = this.ring.querySelectorAll('.ring-item')
            const count = items.length
            if (count === 0) return

            const rect = this.el.getBoundingClientRect()
            const cx = rect.left + rect.width / 2
            const cy = rect.top + rect.height / 2
            const vw = window.innerWidth
            const vh = window.innerHeight
            const radius = 38

            let startDeg = 200, sweepDeg = 160
            if (cy < 100) { startDeg = 20; sweepDeg = 140 }
            else if (cy > vh - 100) { startDeg = 200; sweepDeg = 140 }
            else if (cx > vw - 120) { startDeg = 110; sweepDeg = 140 }
            else if (cx < 120) { startDeg = 290; sweepDeg = 140 }

            const step = count > 1 ? sweepDeg / (count - 1) : 0
            items.forEach((item, i) => {
              const angle = (startDeg + i * step) * Math.PI / 180
              const x = Math.cos(angle) * radius
              const y = Math.sin(angle) * radius
              item.style.setProperty('--ring-x', x + 'px')
              item.style.setProperty('--ring-y', y + 'px')
            })
            this._positioned = true
          },

          show() {
            clearTimeout(this._hideTimer)
            if (!this._positioned) this.position()
            this.el.classList.add('ring-open')
            const springEl = this.el.closest('.spring-element')
            if (springEl) springEl.classList.add('ring-active')
          },

          scheduleHide() {
            clearTimeout(this._hideTimer)
            this._hideTimer = setTimeout(() => this.hide(), 120)
          },

          cancelHide() {
            clearTimeout(this._hideTimer)
          },

          hide() {
            this.el.classList.remove('ring-open')
            const springEl = this.el.closest('.spring-element')
            if (springEl) springEl.classList.remove('ring-active')
          },

          destroyed() {
            clearTimeout(this._hideTimer)
          }
        }
      </script>
    </div>
    """
  end

  # --- Components ---

  @gm_color "#ef4444"

  defp entity_card(assigns) do
    assigns = assign_new(assigns, :circle_color, fn ->
      if assigns.entity.controller_id, do: assigns.entity.color || "#6b7280", else: @gm_color
    end)

    ~H"""
    <div
      id={"entity-#{@entity.id}"}
      phx-click="select"
      phx-value-id={@entity.id}
      phx-value-type="entity"
      class={"relative p-3 rounded-lg shadow-lg w-52 cursor-pointer transition-all
        #{if @selected, do: "ring-2 ring-yellow-400 scale-105", else: "hover:scale-102"}"}
      style={"background: #f5f0e8; border-left: 4px solid #{@entity.color || "#6b7280"};"}
    >
      <div class="flex items-center gap-2 mb-2">
        <%= if @entity.avatar do %>
          <div class="w-8 h-8 rounded-full bg-gray-300 flex items-center justify-center text-xs">
            {String.at(@entity.name, 0)}
          </div>
        <% end %>
        <div>
          <div class="font-bold text-gray-900 text-base" style="font-family: 'Patrick Hand', cursive;">
            {@entity.name}
          </div>
          <div class="text-xs text-gray-500 uppercase tracking-wide">{@entity.kind}</div>
        </div>
        <div class="ml-auto relative ring-trigger" id={"ring-trigger-#{@entity.id}"} phx-hook=".RingTrigger">
          <div
            class="w-7 h-7 rounded-full flex items-center justify-center text-xs font-bold text-white entity-circle"
            style={"background: #{@circle_color};"}
            draggable="true"
            phx-hook="DraggableToken"
            id={"token-#{@entity.id}"}
            data-entity-id={@entity.id}
            data-entity-name={@entity.name}
            data-entity-color={@circle_color}
          >
            <%= if @entity.fate_points do %>
              {@entity.fate_points}
            <% end %>
          </div>
          <.entity_ring entity={@entity} is_gm={@is_gm} />
        </div>
      </div>

      <%!-- Aspects --%>
      <%= for aspect <- visible_aspects(@entity.aspects, @is_gm) do %>
        <div class={"group/aspect flex items-start gap-1 text-xs px-2 py-1 rounded mb-1 #{aspect_style(aspect)}"}>
          <span class="flex-1 font-semibold text-gray-900" style="font-family: 'Permanent Marker', cursive; font-size: 0.8rem;">
            {aspect.description}
          </span>
          <%= if aspect.free_invokes > 0 do %>
            <span class="text-green-700">
              {"☐" |> String.duplicate(aspect.free_invokes)}
            </span>
          <% end %>
          <%= if aspect.hidden do %>
            <span class="opacity-50">👁</span>
          <% end %>
          <button
            phx-click="remove_aspect"
            phx-value-aspect-id={aspect.id}
            phx-value-entity-id={@entity.id}
            class="opacity-0 group-hover/aspect:opacity-100 text-red-400 hover:text-red-600 text-xs leading-none transition-opacity"
            title="Remove aspect"
          >
            ✕
          </button>
        </div>
      <% end %>

      <%!-- Consequences (only shown when taken) --%>
      <%= for cons <- @entity.consequences do %>
        <div class={"text-xs px-2 py-1 rounded mb-1 #{if cons.recovering, do: "bg-green-50 border-l-2 border-green-300", else: "bg-red-50 border-l-2 border-red-300"}"}>
          <span class="text-gray-400 uppercase" style="font-size: 0.6rem;">{cons.severity}</span>
          <span class="font-semibold text-gray-900 ml-1" style="font-family: 'Permanent Marker', cursive; font-size: 0.75rem;">
            {cons.aspect_text || "—"}
          </span>
        </div>
      <% end %>

      <%!-- Stress tracks --%>
      <%= if @entity.stress_tracks != [] do %>
        <div class="flex gap-2 mt-1">
          <%= for track <- @entity.stress_tracks do %>
            <div class="flex items-center gap-0.5">
              <span class="text-gray-400 text-xs font-bold uppercase" style="font-size: 0.55rem;">
                {String.first(track.label)}
              </span>
              <%= for i <- 1..track.boxes do %>
                <div
                  phx-click="apply_stress"
                  phx-value-entity-id={@entity.id}
                  phx-value-track-label={track.label}
                  phx-value-box-index={i}
                  class={[
                    "w-4 h-4 border rounded text-center leading-4 cursor-pointer transition-all",
                    if(i in track.checked,
                      do: "bg-red-500 border-red-600 text-white",
                      else: "border-gray-400 text-gray-400 hover:bg-red-100 hover:border-red-300"
                    )
                  ]}
                  style="font-size: 0.55rem;"
                >
                  {i}
                </div>
              <% end %>
            </div>
          <% end %>
        </div>
      <% end %>

      <%!-- Pending shifts --%>
      <%= if @entity.pending_shifts do %>
        <div class="mt-1 px-2 py-1 bg-red-100 border border-red-300 rounded text-xs text-red-700 font-bold animate-pulse">
          {@entity.pending_shifts.remaining_shifts} shifts!
        </div>
      <% end %>
    </div>
    """
  end

  defp aspect_card(assigns) do
    assigns = assign_new(assigns, :is_gm, fn -> false end)

    ~H"""
    <div
      id={"aspect-#{@aspect.id}"}
      phx-click="select"
      phx-value-id={@aspect.id}
      phx-value-type="aspect"
      class={"group/scard relative p-2 rounded shadow-md min-w-32 max-w-48 cursor-pointer transition-all
        #{if @selected, do: "ring-2 ring-yellow-400 scale-105", else: "hover:scale-102"}
        #{if @aspect.role == :boost, do: "opacity-80", else: ""}"}
      style={aspect_card_bg(@aspect)}
    >
      <div class="font-bold text-gray-900 text-sm" style="font-family: 'Permanent Marker', cursive;">
        {@aspect.description}
      </div>
      <%= if @aspect.free_invokes > 0 do %>
        <div class="text-xs text-green-700 mt-1">
          Free: {"☐" |> String.duplicate(@aspect.free_invokes)}
        </div>
      <% end %>
      <div class="absolute -top-2 -right-2 flex gap-0.5">
        <%= if @is_gm do %>
          <button
            phx-click="toggle_scene_aspect_visibility"
            phx-value-aspect-id={@aspect.id}
            class={[
              "w-5 h-5 rounded-full flex items-center justify-center shadow transition-opacity",
              if(@aspect.hidden, do: "bg-amber-600 hover:bg-amber-500 text-white", else: "bg-gray-600 hover:bg-gray-500 text-white opacity-0 group-hover/scard:opacity-100")
            ]}
            title={if(@aspect.hidden, do: "Reveal", else: "Hide")}
          >
            <.icon name={if(@aspect.hidden, do: "hero-eye", else: "hero-eye-slash")} class="w-3 h-3" />
          </button>
        <% end %>
        <button
          phx-click="remove_scene_aspect"
          phx-value-aspect-id={@aspect.id}
          class="w-5 h-5 bg-red-500 hover:bg-red-400 text-white rounded-full flex items-center justify-center text-xs shadow opacity-0 group-hover/scard:opacity-100 transition-opacity"
          title="Remove aspect"
        >
          ✕
        </button>
      </div>
    </div>
    """
  end

  defp your_tent(assigns) do
    entities = controlled_entities(assigns.state, assigns.current_participant)
    assigns = assign(assigns, :entities, entities)

    ~H"""
    <div
      id="your-tent"
      class="z-30"
      style={tent_style(@dock_position, @tent_size)}
    >
      <div class="h-full overflow-y-auto p-4 flex flex-wrap gap-3 content-start">
        <%= if @is_gm do %>
          <%!-- GM tent content --%>
          <div class="w-full mb-2">
            <div
              class="text-lg text-amber-100 font-bold"
              style="font-family: 'Permanent Marker', cursive;"
            >
              GM Workspace
            </div>
            <div class="flex items-center gap-2 mt-1">
              <div class="text-amber-200/70 text-sm">Fate Points:</div>
              <div class="w-8 h-8 rounded-full bg-red-800 flex items-center justify-center text-white font-bold text-sm">
                {@state.gm_fate_points}
              </div>
            </div>
          </div>

          <%!-- All entities the GM might manage --%>
          <%= for entity <- Map.values(@state.entities) |> Enum.filter(&(&1.kind != :pc)) do %>
            <.entity_card
              entity={entity}
              is_gm={@is_gm}
              selected={%{id: entity.id, type: "entity"} in @selection}
            />
          <% end %>
        <% else %>
          <%!-- Player tent content --%>
          <%= for entity <- @entities do %>
            <.entity_card_detailed
              entity={entity}
              is_gm={false}
              selection={@selection}
            />
          <% end %>

          <%= if @entities == [] do %>
            <div class="text-amber-200/50 text-sm">
              No controlled entities. Ask the GM to assign you a character.
            </div>
          <% end %>
        <% end %>
      </div>
    </div>
    """
  end

  defp entity_card_detailed(assigns) do
    ~H"""
    <div
      id={"detail-#{@entity.id}"}
      class="p-4 rounded-lg shadow-lg w-full max-w-md"
      style={"background: #f5f0e8; border-left: 4px solid #{@entity.color || "#6b7280"};"}
    >
      <%!-- Header --%>
      <div class="flex items-center gap-3 mb-3">
        <div>
          <div class="font-bold text-gray-900 text-xl" style="font-family: 'Patrick Hand', cursive;">
            {@entity.name}
          </div>
          <div class="text-sm text-gray-500 uppercase tracking-wide">{@entity.kind}</div>
        </div>
        <%= if @entity.fate_points do %>
          <div class="ml-auto flex items-center gap-2">
            <span class="text-xs text-gray-500">FP</span>
            <div
              class="w-10 h-10 rounded-full flex items-center justify-center text-sm font-bold text-white"
              style={"background: #{@entity.color || "#6b7280"};"}
            >
              {@entity.fate_points}
            </div>
            <%= if @entity.refresh do %>
              <span class="text-xs text-gray-400">/ {@entity.refresh}</span>
            <% end %>
          </div>
        <% end %>
      </div>

      <%!-- Aspects --%>
      <div class="mb-3">
        <%= for aspect <- @entity.aspects do %>
          <div
            phx-click="select"
            phx-value-id={aspect.id}
            phx-value-type="aspect"
            class={"text-sm px-2 py-1 rounded mb-1 cursor-pointer transition-all #{aspect_style(aspect)}
              #{if %{id: aspect.id, type: "aspect"} in @selection, do: "ring-2 ring-yellow-400", else: ""}"}
          >
            <span class="text-xs uppercase text-gray-400 mr-1">{aspect.role}</span>
            <span class="text-gray-900" style="font-family: 'Permanent Marker', cursive;">{aspect.description}</span>
            <%= if aspect.free_invokes > 0 do %>
              <span class="ml-1 text-green-700">{"☐" |> String.duplicate(aspect.free_invokes)}</span>
            <% end %>
          </div>
        <% end %>
      </div>

      <%!-- Skills --%>
      <%= if map_size(@entity.skills) > 0 do %>
        <div class="mb-3">
          <div class="text-xs uppercase text-gray-500 mb-1 font-bold">Skills</div>
          <div class="grid grid-cols-2 gap-1">
            <%= for {skill, rating} <- @entity.skills |> Enum.sort_by(&elem(&1, 1), :desc) do %>
              <div class="flex justify-between text-xs px-2 py-0.5 bg-white/50 rounded">
                <span>{skill}</span>
                <span class="font-bold">{rating_label(rating)}</span>
              </div>
            <% end %>
          </div>
        </div>
      <% end %>

      <%!-- Stunts --%>
      <%= if @entity.stunts != [] do %>
        <div class="mb-3">
          <div class="text-xs uppercase text-gray-500 mb-1 font-bold">Stunts</div>
          <%= for stunt <- @entity.stunts do %>
            <div class="text-xs px-2 py-1 bg-blue-50 rounded mb-1">
              <span class="font-bold">{stunt.name}:</span>
              <span class="text-gray-600">{stunt.effect}</span>
            </div>
          <% end %>
        </div>
      <% end %>

      <%!-- Stress Tracks --%>
      <%= for track <- @entity.stress_tracks do %>
        <div class="mb-2">
          <div class="text-xs uppercase text-gray-500 font-bold">{track.label} Stress</div>
          <div class="flex gap-1 mt-1">
            <%= for i <- 1..track.boxes do %>
              <div
                phx-click="apply_stress"
                phx-value-entity-id={@entity.id}
                phx-value-track-label={track.label}
                phx-value-box-index={i}
                class={[
                  "w-6 h-6 border-2 rounded flex items-center justify-center text-xs font-bold cursor-pointer transition-all",
                  if(i in track.checked,
                    do: "bg-red-500 border-red-700 text-white",
                    else: "border-gray-400 text-gray-400 hover:bg-red-100 hover:border-red-300"
                  )
                ]}
              >
                {i}
              </div>
            <% end %>
          </div>
        </div>
      <% end %>

      <%!-- Consequences --%>
      <div class="mb-2">
        <div class="text-xs uppercase text-gray-500 font-bold mb-1">Consequences</div>
        <%= for cons <- @entity.consequences do %>
          <div class={"text-xs px-2 py-1 rounded mb-1 #{if cons.recovering, do: "bg-green-50 border border-green-200", else: "bg-red-50 border border-red-200"}"}>
            <span class="font-bold uppercase text-gray-500">{cons.severity} ({cons.shifts}):</span>
            <span style="font-family: 'Permanent Marker', cursive;">
              {cons.aspect_text || "—"}
            </span>
          </div>
        <% end %>
        <%= if @entity.consequences == [] do %>
          <div class="text-xs text-gray-400">No consequences</div>
        <% end %>
      </div>

      <%!-- Pending Shifts --%>
      <%= if @entity.pending_shifts do %>
        <div class="p-2 bg-red-100 border border-red-300 rounded text-xs">
          <span class="font-bold text-red-700">
            {@entity.pending_shifts.remaining_shifts} shifts to absorb!
          </span>
        </div>
      <% end %>
    </div>
    """
  end

  defp other_tent(assigns) do
    participant = assigns.branch_participant.participant
    entity = find_controlled_entity(assigns.state, participant.id)
    assigns = assign(assigns, :entity, entity) |> assign(:participant, participant)

    ~H"""
    <div
      id={"tent-#{@participant.id}"}
      class="z-20"
    >
      <div
        class="p-2 rounded-lg shadow-lg max-w-48 overflow-hidden"
        style={"background: #f5f0e8; border-top: 3px solid #{@participant.color};"}
      >
        <div class="font-bold text-gray-800 text-sm" style="font-family: 'Patrick Hand', cursive;">
          {@participant.name}
          <span class="text-xs text-gray-400 ml-1">
            {if @branch_participant.role == :gm, do: "(GM)", else: ""}
          </span>
        </div>

        <%= if @entity do %>
          <div class="text-xs text-gray-600 mt-1">{@entity.name}</div>

          <%!-- Aspects (always visible) --%>
          <%= for aspect <- visible_aspects(@entity.aspects, @is_gm) do %>
            <div class={"text-xs px-1 py-0.5 rounded mt-1 #{aspect_style(aspect)}"}>
              <span style="font-family: 'Permanent Marker', cursive; font-size: 0.65rem;">
                {aspect.description}
              </span>
            </div>
          <% end %>

          <%!-- GM X-ray: skills, full stress, consequences --%>
          <%= if @is_gm do %>
            <%= if map_size(@entity.skills) > 0 do %>
              <div class="mt-2 text-xs">
                <%= for {skill, rating} <- @entity.skills |> Enum.sort_by(&elem(&1, 1), :desc) |> Enum.take(4) do %>
                  <div class="flex justify-between text-gray-600">
                    <span>{skill}</span>
                    <span class="font-bold">{rating_label(rating)}</span>
                  </div>
                <% end %>
              </div>
            <% end %>

            <%= for track <- @entity.stress_tracks do %>
              <div class="flex gap-0.5 mt-1">
                <%= for i <- 1..track.boxes do %>
                  <div class={"w-4 h-4 border rounded text-center text-xs
                    #{if i in track.checked, do: "bg-red-500 border-red-700 text-white", else: "border-gray-300"}"}>
                    {if i in track.checked, do: "×", else: ""}
                  </div>
                <% end %>
              </div>
            <% end %>
          <% else %>
            <%!-- Player view: compact stress summary --%>
            <%= if @entity.stress_tracks != [] do %>
              <div class="text-xs text-gray-400 mt-1">
                Stress: {stress_summary(@entity)}
              </div>
            <% end %>
          <% end %>

          <%!-- Fate points --%>
          <%= if @entity.fate_points do %>
            <div class="mt-1">
              <div
                class="inline-flex w-5 h-5 rounded-full items-center justify-center text-xs font-bold text-white"
                style={"background: #{@entity.color || @participant.color};"}
              >
                {@entity.fate_points}
              </div>
            </div>
          <% end %>
        <% end %>
      </div>
    </div>
    """
  end

  defp entity_ring(assigns) do
    ~H"""
    <div class="context-ring" id={"ring-#{@entity.id}"}>
      <%= if @entity.fate_points do %>
        <button class="ring-item" phx-click="ring_action" phx-value-action="fp_earn" phx-value-entity-id={@entity.id} data-tooltip="FP +1">
          <.icon name="hero-plus-circle" class="w-3.5 h-3.5" />
        </button>
        <button class="ring-item" phx-click="ring_action" phx-value-action="fp_spend" phx-value-entity-id={@entity.id} data-tooltip="FP −1">
          <.icon name="hero-minus-circle" class="w-3.5 h-3.5" />
        </button>
        <button class="ring-item" phx-click="ring_action" phx-value-action="concede" phx-value-entity-id={@entity.id} data-tooltip="Concede">
          <.icon name="hero-flag" class="w-3.5 h-3.5" />
        </button>
      <% end %>
      <%= if @is_gm do %>
        <button
          class="ring-item"
          phx-click="ring_action"
          phx-value-action={if(entity_hidden?(@entity), do: "reveal", else: "hide")}
          phx-value-entity-id={@entity.id}
          data-tooltip={if(entity_hidden?(@entity), do: "Reveal", else: "Hide")}
        >
          <.icon name={if(entity_hidden?(@entity), do: "hero-eye", else: "hero-eye-slash")} class="w-3.5 h-3.5" />
        </button>
        <button
          class="ring-item ring-item-danger"
          phx-click="ring_action"
          phx-value-action="remove"
          phx-value-entity-id={@entity.id}
          data-tooltip="Remove"
          data-confirm="Remove this entity?"
        >
          <.icon name="hero-trash" class="w-3.5 h-3.5" />
        </button>
      <% end %>
    </div>
    """
  end

  defp gm_notes_ring(assigns) do
    active_scene = Enum.find(assigns.state.scenes, &(&1.status == :active))
    assigns = assign(assigns, :active_scene, active_scene)

    ~H"""
    <div class="context-ring" id="ring-gm-notes">
      <button class="ring-item" phx-click="ring_action" phx-value-action="new_scene" data-tooltip="New Scene">
        <.icon name="hero-play" class="w-3.5 h-3.5" />
      </button>
      <%= if @active_scene do %>
        <button class="ring-item ring-item-danger" phx-click="ring_action" phx-value-action="end_scene" data-tooltip="End Scene">
          <.icon name="hero-stop" class="w-3.5 h-3.5" />
        </button>
        <button class="ring-item" phx-click="ring_action" phx-value-action="add_zone" data-tooltip="Add Zone">
          <.icon name="hero-map-pin" class="w-3.5 h-3.5" />
        </button>
      <% end %>
    </div>
    """
  end

  defp table_modal(%{modal: nil} = assigns), do: ~H""

  defp table_modal(%{modal: "scene_start"} = assigns) do
    ~H"""
    <div class="fixed inset-0 z-[300] flex items-center justify-center bg-black/60" phx-click="close_table_modal">
      <div class="bg-amber-950 border border-amber-700/40 rounded-xl p-6 w-96 shadow-2xl" phx-click-away="close_table_modal">
        <h3 class="text-lg font-bold text-amber-100 mb-4" style="font-family: 'Permanent Marker', cursive;">
          Start Scene
        </h3>
        <form phx-submit="submit_table_modal" class="space-y-3">
          <div>
            <label class="block text-sm text-amber-200/70 mb-1">Scene Name</label>
            <input type="text" name="name" placeholder="Dockside Warehouse"
              class="w-full px-3 py-2 bg-amber-900/30 border border-amber-700/30 rounded-lg text-amber-100 text-sm placeholder-amber-200/20" />
          </div>
          <div>
            <label class="block text-sm text-amber-200/70 mb-1">Description</label>
            <input type="text" name="scene_description" placeholder="A brief framing of the scene"
              class="w-full px-3 py-2 bg-amber-900/30 border border-amber-700/30 rounded-lg text-amber-100 text-sm placeholder-amber-200/20" />
          </div>
          <div>
            <label class="block text-sm text-amber-200/70 mb-1">GM Notes</label>
            <textarea name="gm_notes" placeholder="Private prep notes..." rows="3"
              class="w-full px-3 py-2 bg-amber-900/30 border border-amber-700/30 rounded-lg text-amber-100 text-sm placeholder-amber-200/20" />
          </div>
          <div class="flex gap-2 pt-2">
            <button type="submit"
              class="flex-1 py-2 bg-green-800/60 border border-green-600/30 rounded-lg hover:bg-green-700/60 text-green-200 font-bold text-sm">
              Start
            </button>
            <button type="button" phx-click="close_table_modal"
              class="flex-1 py-2 bg-red-900/40 border border-red-700/30 rounded-lg hover:bg-red-800/40 text-red-200 text-sm">
              Cancel
            </button>
          </div>
        </form>
      </div>
    </div>
    """
  end

  defp table_modal(%{modal: "zone_create"} = assigns) do
    ~H"""
    <div class="fixed inset-0 z-[300] flex items-center justify-center bg-black/60" phx-click="close_table_modal">
      <div class="bg-amber-950 border border-amber-700/40 rounded-xl p-6 w-96 shadow-2xl" phx-click-away="close_table_modal">
        <h3 class="text-lg font-bold text-amber-100 mb-4" style="font-family: 'Permanent Marker', cursive;">
          Add Zone
        </h3>
        <form phx-submit="submit_table_modal" class="space-y-3">
          <div>
            <label class="block text-sm text-amber-200/70 mb-1">Zone Name</label>
            <input type="text" name="name" placeholder="Back Alley"
              class="w-full px-3 py-2 bg-amber-900/30 border border-amber-700/30 rounded-lg text-amber-100 text-sm placeholder-amber-200/20" />
          </div>
          <p class="text-xs text-amber-200/40">Zone will start hidden. Reveal it from the table when ready.</p>
          <div class="flex gap-2 pt-2">
            <button type="submit"
              class="flex-1 py-2 bg-green-800/60 border border-green-600/30 rounded-lg hover:bg-green-700/60 text-green-200 font-bold text-sm">
              Create
            </button>
            <button type="button" phx-click="close_table_modal"
              class="flex-1 py-2 bg-red-900/40 border border-red-700/30 rounded-lg hover:bg-red-800/40 text-red-200 text-sm">
              Cancel
            </button>
          </div>
        </form>
      </div>
    </div>
    """
  end

  defp table_modal(assigns), do: ~H""

  # --- Helper functions ---

  defp is_localhost?(socket) do
    case get_connect_info(socket, :peer_data) do
      %{address: {127, 0, 0, 1}} -> true
      %{address: {0, 0, 0, 0, 0, 0, 0, 1}} -> true
      _ -> false
    end
  rescue
    _ -> false
  end

  defp load_branch_participants(branch_id) do
    require Ash.Query

    Fate.Game.BranchParticipant
    |> Ash.Query.filter(branch_id: branch_id)
    |> Ash.Query.load(:participant)
    |> Ash.read!()
  rescue
    e ->
      require Logger
      Logger.error("Failed to load participants: #{inspect(e)}")
      []
  end

  defp active_scene_id(nil), do: "none"

  defp active_scene_id(state) do
    case Enum.find(state.scenes, &(&1.status == :active)) do
      nil -> "none"
      scene -> scene.id
    end
  end

  defp visible_uncontrolled_entities(state, _is_gm) do
    state.entities
    |> Map.values()
    |> Enum.filter(fn e ->
      is_nil(e.controller_id) && !has_all_hidden_aspects?(e)
    end)
  end

  defp hidden_entities(state) do
    state.entities
    |> Map.values()
    |> Enum.filter(fn e ->
      is_nil(e.controller_id) && has_all_hidden_aspects?(e)
    end)
  end

  defp has_all_hidden_aspects?(entity) do
    entity.aspects != [] && Enum.all?(entity.aspects, & &1.hidden)
  end

  defp entity_hidden?(entity) do
    entity.aspects != [] && Enum.all?(entity.aspects, & &1.hidden)
  end

  defp reveal_entity_aspects(branch_id, entity_id, state) do
    entity = Map.get(state.entities, entity_id)

    if entity do
      Enum.each(entity.aspects, fn aspect ->
        if aspect.hidden do
          Fate.Engine.append_event(branch_id, %{
            type: :aspect_remove,
            target_id: entity_id,
            description: "Reveal: #{aspect.description}",
            detail: %{"aspect_id" => aspect.id}
          })

          Fate.Engine.append_event(branch_id, %{
            type: :aspect_create,
            target_id: entity_id,
            description: "Reveal: #{aspect.description}",
            detail: %{
              "target_id" => entity_id,
              "target_type" => "entity",
              "aspect_id" => aspect.id,
              "description" => aspect.description,
              "role" => to_string(aspect.role),
              "hidden" => false
            }
          })
        end
      end)
    end
  end

  defp hide_entity_aspects(branch_id, entity_id, state) do
    entity = Map.get(state.entities, entity_id)

    if entity do
      Enum.each(entity.aspects, fn aspect ->
        unless aspect.hidden do
          Fate.Engine.append_event(branch_id, %{
            type: :aspect_remove,
            target_id: entity_id,
            description: "Hide: #{aspect.description}",
            detail: %{"aspect_id" => aspect.id}
          })

          Fate.Engine.append_event(branch_id, %{
            type: :aspect_create,
            target_id: entity_id,
            description: "Hide: #{aspect.description}",
            detail: %{
              "target_id" => entity_id,
              "target_type" => "entity",
              "aspect_id" => aspect.id,
              "description" => aspect.description,
              "role" => to_string(aspect.role),
              "hidden" => true
            }
          })
        end
      end)
    end
  end

  defp find_scene_aspect(state, aspect_id) do
    state.scenes
    |> Enum.filter(&(&1.status == :active))
    |> Enum.flat_map(fn scene ->
      scene.aspects ++ Enum.flat_map(scene.zones, & &1.aspects)
    end)
    |> Enum.find(&(&1.id == aspect_id))
  end

  defp find_aspect_owner(state, aspect_id) do
    Enum.find_value(state.scenes, fn scene ->
      cond do
        Enum.any?(scene.aspects, &(&1.id == aspect_id)) ->
          {"scene", scene.id}

        zone = Enum.find(scene.zones, fn z -> Enum.any?(z.aspects, &(&1.id == aspect_id)) end) ->
          {"zone", zone.id}

        true ->
          nil
      end
    end) || {"scene", nil}
  end

  defp visible_zone_aspects(aspects, is_gm) do
    if is_gm, do: aspects, else: Enum.reject(aspects, & &1.hidden)
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

  defp controlled_entities(state, nil), do: Map.values(state.entities)

  defp controlled_entities(state, participant) do
    state.entities
    |> Map.values()
    |> Enum.filter(&(&1.controller_id == participant.id))
  end

  defp find_controlled_entity(state, participant_id) do
    state.entities
    |> Map.values()
    |> Enum.find(&(&1.controller_id == participant_id))
  end

  defp other_participants(participants, current) do
    Enum.reject(participants, fn bp ->
      current && bp.participant_id == current.id
    end)
  end

  defp scene_aspects(state, is_gm) do
    state.scenes
    |> Enum.filter(&(&1.status == :active))
    |> Enum.flat_map(fn scene ->
      scene_aspects = scene.aspects
      zone_aspects = Enum.flat_map(scene.zones, & &1.aspects)
      scene_aspects ++ zone_aspects
    end)
    |> Enum.filter(fn aspect ->
      is_gm || !aspect.hidden
    end)
  end

  defp visible_aspects(aspects, is_gm) do
    if is_gm, do: aspects, else: Enum.reject(aspects, & &1.hidden)
  end

  defp aspect_style(aspect) do
    case aspect.role do
      :high_concept -> "bg-amber-100 border-l-2 border-amber-500"
      :trouble -> "bg-red-100 border-l-2 border-red-400"
      :boost -> "bg-yellow-100 border-l-2 border-yellow-400 italic"
      :situation -> "bg-blue-100 border-l-2 border-blue-400"
      :consequence -> "bg-red-50 border-l-2 border-red-300"
      _ -> "bg-gray-100 border-l-2 border-gray-400"
    end
  end

  defp aspect_card_bg(aspect) do
    case aspect.role do
      :boost -> "background: #fef9c3; transform: rotate(-1deg);"
      :situation -> "background: #bfdbfe; transform: rotate(1deg);"
      _ -> "background: #fef3c7;"
    end
  end

  defp rating_label(rating) do
    labels = %{
      8 => "+8 Legendary",
      7 => "+7 Epic",
      6 => "+6 Fantastic",
      5 => "+5 Superb",
      4 => "+4 Great",
      3 => "+3 Good",
      2 => "+2 Fair",
      1 => "+1 Average",
      0 => "+0 Mediocre",
      -1 => "-1 Terrible",
      -2 => "-2 Abysmal"
    }

    Map.get(labels, rating, "+#{rating}")
  end

  defp stress_summary(entity) do
    entity.stress_tracks
    |> Enum.map(fn track ->
      checked = length(track.checked)
      "#{track.label}: #{checked}/#{track.boxes}"
    end)
    |> Enum.join(", ")
  end

  defp tent_style(:south, size) do
    height = trunc(size * 100)
    "bottom: 0; left: 0; right: 0; height: #{height}vh; background: rgba(30, 20, 10, 0.85); border-top: 2px solid rgba(180, 140, 80, 0.3);"
  end

  defp tent_style(:north, size) do
    height = trunc(size * 100)
    "top: 0; left: 0; right: 0; height: #{height}vh; background: rgba(30, 20, 10, 0.85); border-bottom: 2px solid rgba(180, 140, 80, 0.3);"
  end

  defp tent_style(:west, size) do
    width = trunc(size * 100)
    "top: 0; left: 0; bottom: 0; width: #{width}vw; background: rgba(30, 20, 10, 0.85); border-right: 2px solid rgba(180, 140, 80, 0.3);"
  end

  defp tent_style(:east, size) do
    width = trunc(size * 100)
    "top: 0; right: 0; bottom: 0; width: #{width}vw; background: rgba(30, 20, 10, 0.85); border-left: 2px solid rgba(180, 140, 80, 0.3);"
  end

  defp other_tent_style(index, total, dock_position) do
    fraction = (index + 1) / (total + 1)

    case dock_position do
      :south ->
        "top: #{trunc(fraction * 60)}%; left: #{if rem(index, 2) == 0, do: "2%", else: "auto"}; right: #{if rem(index, 2) == 1, do: "2%", else: "auto"};"

      :north ->
        "bottom: #{trunc(fraction * 60)}%; left: #{if rem(index, 2) == 0, do: "2%", else: "auto"}; right: #{if rem(index, 2) == 1, do: "2%", else: "auto"};"

      :west ->
        "top: #{if rem(index, 2) == 0, do: "2%", else: "auto"}; bottom: #{if rem(index, 2) == 1, do: "2%", else: "auto"}; right: #{trunc(fraction * 40)}%;"

      :east ->
        "top: #{if rem(index, 2) == 0, do: "2%", else: "auto"}; bottom: #{if rem(index, 2) == 1, do: "2%", else: "auto"}; left: #{trunc(fraction * 40)}%;"
    end
  end
end
