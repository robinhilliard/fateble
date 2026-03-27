defmodule FateWeb.TableComponents do
  @moduledoc """
  Function components for the table view: entity cards, aspect cards,
  context rings, and table modals.
  """

  use FateWeb, :html

  @gm_color "#ef4444"

  def entity_card(assigns) do
    assigns =
      assigns
      |> assign_new(:circle_color, fn ->
        if assigns.entity.controller_id, do: assigns.entity.color || "#6b7280", else: @gm_color
      end)
      |> assign_new(:is_observer, fn -> false end)

    ~H"""
    <div
      id={"entity-#{@entity.id}"}
      phx-click={unless(@is_observer, do: "select")}
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
          <div class="text-xs text-gray-500 uppercase tracking-wide">
            {@entity.kind}
            <%= if @entity.mook_count do %>
              <span class="ml-1 text-red-600 font-bold">×{@entity.mook_count}</span>
            <% end %>
          </div>
        </div>
        <%= if @is_observer do %>
          <div class="ml-auto">
            <div
              class="w-7 h-7 rounded-full flex items-center justify-center text-xs font-bold text-white"
              style={"background: #{@circle_color};"}
            >
              <%= if @entity.fate_points do %>
                {@entity.fate_points}
              <% end %>
            </div>
          </div>
        <% else %>
          <div
            class="ml-auto relative z-10 ring-trigger"
            id={"ring-trigger-#{@entity.id}"}
            phx-hook=".RingTrigger"
          >
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
        <% end %>
      </div>

      <%!-- Aspects --%>
      <%= for aspect <- visible_aspects(@entity.aspects, @is_gm) do %>
        <div class={"group/aspect relative flex items-start gap-1 text-xs px-2 py-1 rounded mb-1 #{aspect_style(aspect)}"}>
          <span
            class="flex-1 font-semibold text-gray-900"
            style="font-family: 'Permanent Marker', cursive; font-size: 0.8rem;"
          >
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
          <div
            :if={!@is_observer}
            class="aspect-inline-menu opacity-0 group-hover/aspect:opacity-100 transition-opacity flex gap-0.5 shrink-0"
          >
            <button
              phx-click="invoke_aspect"
              phx-value-aspect-id={aspect.id}
              phx-value-entity-id={@entity.id}
              phx-value-description={aspect.description}
              phx-value-free={if(aspect.free_invokes > 0, do: "true", else: "false")}
              class="px-1.5 py-0.5 bg-green-600/80 hover:bg-green-500 text-white rounded text-xs leading-none transition"
              data-tooltip={if(aspect.free_invokes > 0, do: "Free invoke", else: "Invoke (spend FP)")}
            >
              {if aspect.free_invokes > 0, do: "Free", else: "FP"}
            </button>
            <%= if @is_gm do %>
              <button
                phx-click="compel_aspect"
                phx-value-aspect-id={aspect.id}
                phx-value-entity-id={@entity.id}
                phx-value-description={aspect.description}
                class="px-1.5 py-0.5 bg-amber-600/80 hover:bg-amber-500 text-white rounded text-xs leading-none transition"
                data-tooltip="Compel"
              >
                C
              </button>
            <% end %>
            <button
              phx-click="remove_aspect"
              phx-value-aspect-id={aspect.id}
              phx-value-entity-id={@entity.id}
              class="text-red-400 hover:text-red-600 text-xs leading-none transition px-0.5"
              data-tooltip="Remove"
            >
              ✕
            </button>
          </div>
        </div>
      <% end %>

      <%!-- Consequences --%>
      <%= for cons <- @entity.consequences do %>
        <div class={"group/cons flex items-center gap-1 text-xs px-2 py-1 rounded mb-1 #{if cons.recovering, do: "bg-green-50 border-l-2 border-green-300", else: "bg-red-50 border-l-2 border-red-300"}"}>
          <span class="text-gray-400 uppercase shrink-0" style="font-size: 0.6rem;">
            {cons.severity}
          </span>
          <span
            class="flex-1 font-semibold text-gray-900"
            style="font-family: 'Permanent Marker', cursive; font-size: 0.75rem;"
          >
            {cons.aspect_text || "—"}
          </span>
          <div
            :if={!@is_observer}
            class="opacity-0 group-hover/cons:opacity-100 transition-opacity flex gap-0.5 shrink-0"
          >
            <%= if cons.recovering do %>
              <button
                phx-click="clear_consequence"
                phx-value-consequence-id={cons.id}
                phx-value-entity-id={@entity.id}
                class="px-1.5 py-0.5 bg-green-600/80 hover:bg-green-500 text-white rounded text-xs leading-none transition"
                data-tooltip="Clear"
              >
                <.icon name="hero-check" class="w-3 h-3" />
              </button>
            <% else %>
              <button
                phx-click="begin_recovery"
                phx-value-consequence-id={cons.id}
                phx-value-entity-id={@entity.id}
                phx-value-aspect-text={cons.aspect_text}
                class="px-1.5 py-0.5 bg-blue-600/80 hover:bg-blue-500 text-white rounded text-xs leading-none transition"
                data-tooltip="Begin recovery"
              >
                <.icon name="hero-arrow-path" class="w-3 h-3" />
              </button>
            <% end %>
          </div>
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
                  phx-click={unless(@is_observer, do: "apply_stress")}
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

      <script :type={Phoenix.LiveView.ColocatedHook} name=".RingTrigger">
        export default {
          mounted() {
            this.ring = this.el.querySelector('.context-ring')
            if (!this.ring) return

            this._open = false
            this._positioned = false
            this._radius = 52
            this._closeRadius = 80

            this.el.addEventListener('mouseenter', () => this.show())

            this._onDocMouseMove = (e) => {
              if (!this._open) return
              const rect = this.el.getBoundingClientRect()
              const cx = rect.left + rect.width / 2
              const cy = rect.top + rect.height / 2
              const dist = Math.hypot(e.clientX - cx, e.clientY - cy)
              if (dist > this._closeRadius) this.hide()
            }
            document.addEventListener('mousemove', this._onDocMouseMove)
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

            let startDeg = 180, sweepDeg = 200
            if (cy < 80) { startDeg = 20; sweepDeg = 180 }
            else if (cy > vh - 80) { startDeg = 200; sweepDeg = 180 }
            else if (cx > vw - 80) { startDeg = 100; sweepDeg = 180 }
            else if (cx < 80) { startDeg = 280; sweepDeg = 180 }

            const step = count > 1 ? sweepDeg / (count - 1) : 0
            const tipOffset = 22
            items.forEach((item, i) => {
              const angle = (startDeg + i * step) * Math.PI / 180
              const x = Math.cos(angle) * this._radius
              const y = Math.sin(angle) * this._radius
              item.style.setProperty('--ring-x', x + 'px')
              item.style.setProperty('--ring-y', y + 'px')
              item.style.setProperty('--tip-x', Math.cos(angle) * tipOffset + 'px')
              item.style.setProperty('--tip-y', Math.sin(angle) * tipOffset + 'px')
            })
            this._positioned = true
          },

          show() {
            if (!this._positioned) this.position()
            this._open = true
            this.el.classList.add('ring-open')
            const springEl = this.el.closest('.spring-element')
            if (springEl) springEl.classList.add('ring-active')
          },

          hide() {
            this._open = false
            this.el.classList.remove('ring-open')
            const springEl = this.el.closest('.spring-element')
            if (springEl) springEl.classList.remove('ring-active')
          },

          destroyed() {
            document.removeEventListener('mousemove', this._onDocMouseMove)
          }
        }
      </script>
    </div>
    """
  end

  def aspect_card(assigns) do
    assigns =
      assigns
      |> assign_new(:is_gm, fn -> false end)
      |> assign_new(:is_observer, fn -> false end)

    ~H"""
    <div
      id={"aspect-#{@aspect.id}"}
      phx-click={unless(@is_observer, do: "select")}
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
      <div :if={!@is_observer} class="absolute -top-2 -right-2 flex gap-0.5">
        <%= if @is_gm do %>
          <button
            phx-click="toggle_scene_aspect_visibility"
            phx-value-aspect-id={@aspect.id}
            class={[
              "w-5 h-5 rounded-full flex items-center justify-center shadow transition-opacity",
              if(@aspect.hidden,
                do: "bg-amber-600 hover:bg-amber-500 text-white opacity-100",
                else:
                  "bg-gray-600 hover:bg-gray-500 text-white opacity-0 group-hover/scard:opacity-100"
              )
            ]}
            data-tooltip={if(@aspect.hidden, do: "Reveal", else: "Hide")}
          >
            <.icon name={if(@aspect.hidden, do: "hero-eye", else: "hero-eye-slash")} class="w-3 h-3" />
          </button>
        <% end %>
        <button
          phx-click="remove_scene_aspect"
          phx-value-aspect-id={@aspect.id}
          class="w-5 h-5 bg-red-500 hover:bg-red-400 text-white rounded-full flex items-center justify-center text-xs shadow opacity-0 group-hover/scard:opacity-100 transition-opacity"
          data-tooltip="Remove"
        >
          ✕
        </button>
      </div>
    </div>
    """
  end

  def entity_ring(assigns) do
    ~H"""
    <div class="context-ring" id={"ring-#{@entity.id}"}>
      <%= if @entity.fate_points do %>
        <button
          class="ring-item"
          phx-click="ring_action"
          phx-value-action="fp_earn"
          phx-value-entity-id={@entity.id}
          data-tooltip="FP +1"
        >
          <.icon name="hero-plus-circle" class="w-3.5 h-3.5" />
        </button>
        <button
          class="ring-item"
          phx-click="ring_action"
          phx-value-action="fp_spend"
          phx-value-entity-id={@entity.id}
          data-tooltip="FP −1"
        >
          <.icon name="hero-minus-circle" class="w-3.5 h-3.5" />
        </button>
        <button
          class="ring-item"
          phx-click="ring_action"
          phx-value-action="concede"
          phx-value-entity-id={@entity.id}
          data-tooltip="Concede"
        >
          <.icon name="hero-flag" class="w-3.5 h-3.5" />
        </button>
        <button
          class="ring-item ring-item-danger"
          phx-click="ring_action"
          phx-value-action="taken_out"
          phx-value-entity-id={@entity.id}
          data-tooltip="Taken Out"
          data-confirm="Mark as taken out?"
        >
          <.icon name="hero-x-mark" class="w-3.5 h-3.5" />
        </button>
      <% end %>
      <%= if @entity.stress_tracks != [] do %>
        <button
          class="ring-item"
          phx-click="ring_action"
          phx-value-action="clear_stress"
          phx-value-entity-id={@entity.id}
          data-tooltip="Clear Stress"
        >
          <.icon name="hero-arrow-path" class="w-3.5 h-3.5" />
        </button>
      <% end %>
      <%= if @entity.mook_count do %>
        <button
          class="ring-item ring-item-danger"
          phx-click="ring_action"
          phx-value-action="mook_eliminate"
          phx-value-entity-id={@entity.id}
          data-tooltip="Eliminate mook"
        >
          <.icon name="hero-x-circle" class="w-3.5 h-3.5" />
        </button>
      <% end %>
      <%= if @is_gm do %>
        <button
          class="ring-item"
          phx-click="ring_action"
          phx-value-action={if(@entity.hidden, do: "reveal", else: "hide")}
          phx-value-entity-id={@entity.id}
          data-tooltip={if(@entity.hidden, do: "Reveal", else: "Hide")}
        >
          <.icon
            name={if(@entity.hidden, do: "hero-eye", else: "hero-eye-slash")}
            class="w-3.5 h-3.5"
          />
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

  def gm_notes_ring(assigns) do
    active_scene = Enum.find(assigns.state.scenes, &(&1.id == assigns.current_scene_id))
    active_scenes = Enum.filter(assigns.state.scenes, &(&1.status == :active))

    assigns =
      assigns |> assign(:active_scene, active_scene) |> assign(:active_scenes, active_scenes)

    ~H"""
    <div class="context-ring" id="ring-gm-notes">
      <%!-- Prep: add / delete scenes --%>
      <button
        class="ring-item"
        phx-click="ring_action"
        phx-value-action="new_scene"
        data-tooltip="Add Scene"
      >
        <.icon name="hero-document-plus" class="w-3.5 h-3.5" />
      </button>
      <%= if @active_scene do %>
        <button
          class="ring-item ring-item-danger"
          phx-click="ring_action"
          phx-value-action="delete_scene"
          data-tooltip="Delete Scene"
          data-confirm="Delete this scene?"
        >
          <.icon name="hero-trash" class="w-3.5 h-3.5" />
        </button>
      <% end %>

      <%!-- Play: start / stop scenes --%>
      <%= if length(@active_scenes) > 1 do %>
        <button
          class="ring-item"
          phx-click="ring_action"
          phx-value-action="switch_scene_list"
          data-tooltip="Start Scene"
        >
          <.icon name="hero-play" class="w-3.5 h-3.5" />
        </button>
      <% end %>
      <%= if @active_scene do %>
        <button
          class="ring-item ring-item-danger"
          phx-click="ring_action"
          phx-value-action="end_scene"
          data-tooltip="End Scene"
          data-confirm="End this scene? This clears stress and removes boosts."
        >
          <.icon name="hero-stop" class="w-3.5 h-3.5" />
        </button>
        <button
          class="ring-item"
          phx-click="ring_action"
          phx-value-action="add_zone"
          data-tooltip="Add Zone"
        >
          <.icon name="hero-map-pin" class="w-3.5 h-3.5" />
        </button>
      <% end %>
    </div>
    """
  end

  def table_modal(%{modal: nil} = assigns), do: ~H""

  def table_modal(%{modal: "scene_start"} = assigns) do
    ~H"""
    <div
      class="fixed inset-0 z-[300] flex items-center justify-center bg-black/60"
      phx-click="close_table_modal"
    >
      <div
        class="bg-amber-950 border border-amber-700/40 rounded-xl p-6 w-96 shadow-2xl"
        phx-click-away="close_table_modal"
      >
        <h3
          class="text-lg font-bold text-amber-100 mb-4"
          style="font-family: 'Permanent Marker', cursive;"
        >
          Start Scene
        </h3>
        <form phx-submit="submit_table_modal" class="space-y-3">
          <div>
            <label class="block text-sm text-amber-200/70 mb-1">Scene Name</label>
            <input
              type="text"
              name="name"
              placeholder="Dockside Warehouse"
              class="w-full px-3 py-2 bg-amber-900/30 border border-amber-700/30 rounded-lg text-amber-100 text-sm placeholder-amber-200/20"
            />
          </div>
          <div>
            <label class="block text-sm text-amber-200/70 mb-1">Description</label>
            <input
              type="text"
              name="scene_description"
              placeholder="A brief framing of the scene"
              class="w-full px-3 py-2 bg-amber-900/30 border border-amber-700/30 rounded-lg text-amber-100 text-sm placeholder-amber-200/20"
            />
          </div>
          <div>
            <label class="block text-sm text-amber-200/70 mb-1">GM Notes</label>
            <textarea
              name="gm_notes"
              placeholder="Private prep notes..."
              rows="3"
              class="w-full px-3 py-2 bg-amber-900/30 border border-amber-700/30 rounded-lg text-amber-100 text-sm placeholder-amber-200/20"
            />
          </div>
          <div class="flex gap-2 pt-2">
            <button
              type="submit"
              class="flex-1 py-2 bg-green-800/60 border border-green-600/30 rounded-lg hover:bg-green-700/60 text-green-200 font-bold text-sm"
            >
              Start
            </button>
            <button
              type="button"
              phx-click="close_table_modal"
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

  def table_modal(%{modal: "zone_create"} = assigns) do
    ~H"""
    <div
      class="fixed inset-0 z-[300] flex items-center justify-center bg-black/60"
      phx-click="close_table_modal"
    >
      <div
        class="bg-amber-950 border border-amber-700/40 rounded-xl p-6 w-96 shadow-2xl"
        phx-click-away="close_table_modal"
      >
        <h3
          class="text-lg font-bold text-amber-100 mb-4"
          style="font-family: 'Permanent Marker', cursive;"
        >
          Add Zone
        </h3>
        <form phx-submit="submit_table_modal" class="space-y-3">
          <div>
            <label class="block text-sm text-amber-200/70 mb-1">Zone Name</label>
            <input
              type="text"
              name="name"
              placeholder="Back Alley"
              class="w-full px-3 py-2 bg-amber-900/30 border border-amber-700/30 rounded-lg text-amber-100 text-sm placeholder-amber-200/20"
            />
          </div>
          <p class="text-xs text-amber-200/40">
            Zone will start hidden. Reveal it from the table when ready.
          </p>
          <div class="flex gap-2 pt-2">
            <button
              type="submit"
              class="flex-1 py-2 bg-green-800/60 border border-green-600/30 rounded-lg hover:bg-green-700/60 text-green-200 font-bold text-sm"
            >
              Create
            </button>
            <button
              type="button"
              phx-click="close_table_modal"
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

  def table_modal(%{modal: "switch_scene"} = assigns) do
    active_scenes =
      if assigns[:state], do: Enum.filter(assigns.state.scenes, &(&1.status == :active)), else: []

    assigns = assign(assigns, :active_scenes, active_scenes)

    ~H"""
    <div
      class="fixed inset-0 z-[300] flex items-center justify-center bg-black/60"
      phx-click="close_table_modal"
    >
      <div
        class="bg-amber-950 border border-amber-700/40 rounded-xl p-6 w-96 shadow-2xl"
        phx-click-away="close_table_modal"
      >
        <h3
          class="text-lg font-bold text-amber-100 mb-4"
          style="font-family: 'Permanent Marker', cursive;"
        >
          Switch Scene
        </h3>
        <div class="space-y-2">
          <%= for scene <- @active_scenes do %>
            <button
              phx-click="ring_action"
              phx-value-action="switch_scene"
              phx-value-scene-id={scene.id}
              class="w-full text-left px-3 py-2 bg-amber-900/30 border border-amber-700/20 rounded-lg hover:bg-amber-800/40 transition"
            >
              <div
                class="text-sm text-amber-100 font-bold"
                style="font-family: 'Patrick Hand', cursive;"
              >
                {scene.name || "(null scene)"}
              </div>
              <%= if scene.description do %>
                <div class="text-xs text-amber-200/40">{scene.description}</div>
              <% end %>
            </button>
          <% end %>
        </div>
        <button
          type="button"
          phx-click="close_table_modal"
          class="w-full mt-3 py-2 bg-red-900/40 border border-red-700/30 rounded-lg hover:bg-red-800/40 text-red-200 text-sm"
        >
          Cancel
        </button>
      </div>
    </div>
    """
  end

  def table_modal(assigns), do: ~H""

  def visible_aspects(aspects, is_gm) do
    if is_gm, do: aspects, else: Enum.reject(aspects, & &1.hidden)
  end

  def visible_zone_aspects(aspects, is_gm) do
    if is_gm, do: aspects, else: Enum.reject(aspects, & &1.hidden)
  end

  def aspect_style(aspect) do
    case aspect.role do
      :high_concept -> "bg-amber-100 border-l-2 border-amber-500"
      :trouble -> "bg-red-100 border-l-2 border-red-400"
      :boost -> "bg-yellow-100 border-l-2 border-yellow-400 italic"
      :situation -> "bg-blue-100 border-l-2 border-blue-400"
      :consequence -> "bg-red-50 border-l-2 border-red-300"
      _ -> "bg-gray-100 border-l-2 border-gray-400"
    end
  end

  def aspect_card_bg(aspect) do
    case aspect.role do
      :boost -> "background: #fef9c3; transform: rotate(-1deg);"
      :situation -> "background: #bfdbfe; transform: rotate(1deg);"
      _ -> "background: #fef3c7;"
    end
  end
end
