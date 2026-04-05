defmodule FateWeb.TableComponents do
  @moduledoc """
  Function components for the table view: entity cards, aspect cards,
  context rings, and table modals.
  """

  use FateWeb, :html

  import FateWeb.ModalComponents
  import FateWeb.ModalForms

  @gm_color "#ef4444"

  def entity_card(assigns) do
    assigns =
      assigns
      |> assign_new(:circle_color, fn ->
        if assigns.entity.controller_id, do: assigns.entity.color || "#6b7280", else: @gm_color
      end)
      |> assign_new(:is_observer, fn -> false end)
      |> assign_new(:current_participant_id, fn -> nil end)
      |> assign_new(:expanded, fn -> false end)
      |> assign_new(:can_expand, fn -> false end)

    sorted_skills =
      if assigns.expanded do
        assigns.entity.skills
        |> Enum.sort_by(fn {_k, v} -> -v end)
      else
        []
      end

    assigns = assign(assigns, :sorted_skills, sorted_skills)

    ~H"""
    <div
      id={"entity-#{@entity.id}"}
      phx-click={unless(@is_observer, do: "select")}
      phx-value-id={@entity.id}
      phx-value-type="entity"
      class={[
        "group/card relative p-3 rounded-lg shadow-lg cursor-pointer transition-all",
        if(@expanded, do: "w-[420px]", else: "w-52"),
        @selected && "ring-2 ring-yellow-400 scale-105"
      ]}
      style={"background: url('/images/paper.jpg') center/cover; border-left: 4px solid #{@entity.color || "#6b7280"}; backface-visibility: hidden;"}
    >
      <%= if @can_expand do %>
        <button
          phx-click="toggle_expand"
          phx-value-entity-id={@entity.id}
          class="absolute top-1/2 -right-3 -translate-y-1/2 w-6 h-10 bg-gray-200/80 hover:bg-gray-300 rounded-r-md flex items-center justify-center transition-all opacity-0 group-hover/card:opacity-100 touch-reveal"
        >
          <.icon
            name={if(@expanded, do: "hero-chevron-left-mini", else: "hero-chevron-right-mini")}
            class="w-4 h-4 text-gray-500"
          />
        </button>
      <% end %>
      <div class="flex items-center gap-2 mb-2">
        <%= if @entity.avatar do %>
          <div class="w-8 h-8 rounded-full bg-gray-300 flex items-center justify-center text-xs">
            {String.at(@entity.name, 0)}
          </div>
        <% end %>
        <div>
          <div
            class="font-bold text-gray-900 text-base"
            style="font-family: 'Patrick Hand', cursive;"
          >
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
            <.entity_ring
              entity={@entity}
              is_gm={@is_gm}
              current_participant_id={@current_participant_id}
            />
          </div>
        <% end %>
      </div>

      <div class={["flex gap-3", @expanded && "flex-row"]}>
        <div class={[
          if(@expanded, do: "flex-1 min-w-0", else: "w-full"),
          @expanded && "flex flex-col"
        ]}>
          <%!-- Aspects --%>
          <%= for aspect <- visible_aspects(@entity.aspects, @is_gm) do %>
            <div
              id={"entity-aspect-#{aspect.id}"}
              class={[
                "entity-aspect group/aspect relative flex w-full min-w-0 items-start gap-1 text-xs px-2 py-1 rounded mb-1",
                aspect_style(aspect),
                if(!@is_observer, do: "entity-aspect-row--actions")
              ]}
              phx-mounted={JS.transition("entity-warp-in", time: 1000)}
            >
              <span
                class="min-w-0 flex-1 font-semibold text-gray-900 break-words"
                style="font-family: 'Permanent Marker', cursive; font-size: 0.8rem;"
              >
                {aspect.description}
              </span>
              <%= if aspect.free_invokes > 0 do %>
                <span class="shrink-0 text-green-700">
                  {"☐" |> String.duplicate(aspect.free_invokes)}
                </span>
              <% end %>
              <div
                :if={!@is_observer}
                class={[
                  "entity-aspect-actions",
                  @is_gm && "entity-aspect-actions--quad"
                ]}
              >
                <button
                  phx-click="invoke_aspect"
                  phx-value-aspect-id={aspect.id}
                  phx-value-entity-id={@entity.id}
                  phx-value-description={aspect.description}
                  phx-value-free={if(aspect.free_invokes > 0, do: "true", else: "false")}
                  class="px-1.5 py-0.5 bg-green-600/80 hover:bg-green-500 text-white rounded text-xs leading-none transition"
                  data-tooltip={
                    if(aspect.free_invokes > 0, do: "Free invoke", else: "Invoke (spend FP)")
                  }
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
                  <button
                    phx-click="toggle_entity_aspect_visibility"
                    phx-value-aspect-id={aspect.id}
                    phx-value-entity-id={@entity.id}
                    class="px-1 py-0.5 bg-gray-600/80 hover:bg-gray-500 text-white rounded text-xs leading-none transition"
                    data-tooltip={
                      if(aspect.hidden, do: "Reveal to players", else: "Hide from players")
                    }
                  >
                    <.icon
                      name={if(aspect.hidden, do: "hero-eye", else: "hero-eye-slash")}
                      class="w-3 h-3"
                    />
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
            <div class={[
              "group/cons relative flex w-full min-w-0 items-center gap-1 text-xs px-2 py-1 rounded mb-1",
              if(cons.recovering,
                do: "bg-green-300/40 border-l-2 border-green-400",
                else: "bg-red-200/50 border-l-2 border-red-300"
              ),
              if(!@is_observer, do: "pr-10")
            ]}>
              <span class="text-gray-400 uppercase shrink-0" style="font-size: 0.6rem;">
                {cons.severity}
              </span>
              <span
                class="min-w-0 flex-1 font-semibold text-gray-900 break-words"
                style="font-family: 'Permanent Marker', cursive; font-size: 0.75rem;"
              >
                {cons.aspect_text || "—"}
              </span>
              <div
                :if={!@is_observer}
                class="absolute right-1 top-1/2 z-10 -translate-y-1/2 opacity-0 group-hover/cons:opacity-100 transition-opacity flex gap-0.5 touch-reveal"
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

          <div class={if(@expanded, do: "mt-auto", else: "")}>
            <%!-- Stress tracks --%>
            <%= if @entity.stress_tracks != [] do %>
              <div class="flex gap-2 mt-1">
                <%= for track <- @entity.stress_tracks do %>
                  <div class="flex items-center gap-0.5">
                    <span
                      class="text-gray-400 text-xs font-bold uppercase"
                      style="font-size: 0.55rem;"
                    >
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
                            else:
                              "border-gray-400 text-gray-400 hover:bg-red-100 hover:border-red-300"
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
        </div>

        <%!-- Right column: skills, stunts, details (expanded only) --%>
        <%= if @expanded do %>
          <div class="w-40 border-l border-gray-300 pl-3 shrink-0">
            <%!-- Skills --%>
            <div class="flex items-center gap-1 mb-1">
              <div class="text-xs text-gray-400 uppercase tracking-wide font-bold flex-1">Skills</div>
              <%= unless @is_observer do %>
                <div class="relative">
                  <button
                    phx-click={JS.toggle(to: "#skill-picker-#{@entity.id}")}
                    class="text-gray-400 hover:text-green-600 transition"
                  >
                    <.icon name="hero-plus" class="w-3 h-3" />
                  </button>
                  <div
                    id={"skill-picker-#{@entity.id}"}
                    class="hidden absolute right-0 top-4 z-20 bg-white border border-gray-200 rounded-lg shadow-lg p-1 w-32 max-h-48 overflow-y-auto"
                    phx-click-away={JS.hide(to: "#skill-picker-#{@entity.id}")}
                  >
                    <% existing = Map.keys(@entity.skills) %>
                    <%= for skill <- available_skills() -- existing do %>
                      <button
                        phx-click="add_skill"
                        phx-value-entity-id={@entity.id}
                        phx-value-skill={skill}
                        class="block w-full text-left px-2 py-1 text-xs text-gray-700 hover:bg-gray-100 rounded"
                        style="font-family: 'Patrick Hand', cursive;"
                      >
                        {skill}
                      </button>
                    <% end %>
                  </div>
                </div>
              <% end %>
            </div>
            <%= if @sorted_skills != [] do %>
              <div class="space-y-0.5 mb-2">
                <%= for {skill, rating} <- @sorted_skills do %>
                  <div class="group/skill flex items-center gap-1 text-xs">
                    <span
                      class="text-gray-600 flex-1 truncate"
                      style="font-family: 'Patrick Hand', cursive;"
                    >
                      {skill}
                    </span>
                    <%= unless @is_observer do %>
                      <button
                        phx-click="adjust_skill"
                        phx-value-entity-id={@entity.id}
                        phx-value-skill={skill}
                        phx-value-delta="-1"
                        class="opacity-0 group-hover/skill:opacity-100 text-gray-400 hover:text-red-500 transition-opacity leading-none touch-reveal"
                        data-tooltip={if(rating <= 1, do: "Remove skill")}
                      >
                        <.icon name="hero-minus" class="w-3 h-3" />
                      </button>
                    <% end %>
                    <span class="font-bold text-gray-900 tabular-nums w-6 text-center">
                      {if(rating >= 0, do: "+#{rating}", else: "#{rating}")}
                    </span>
                    <%= unless @is_observer do %>
                      <button
                        phx-click="adjust_skill"
                        phx-value-entity-id={@entity.id}
                        phx-value-skill={skill}
                        phx-value-delta="1"
                        class="opacity-0 group-hover/skill:opacity-100 text-gray-400 hover:text-green-500 transition-opacity leading-none touch-reveal"
                      >
                        <.icon name="hero-plus" class="w-3 h-3" />
                      </button>
                    <% end %>
                  </div>
                <% end %>
              </div>
            <% end %>

            <%!-- Stunts --%>
            <div class="flex items-center gap-1 mb-1">
              <div class="text-xs text-gray-400 uppercase tracking-wide font-bold flex-1">Stunts</div>
              <%= unless @is_observer do %>
                <button
                  phx-click="open_add_stunt"
                  phx-value-entity-id={@entity.id}
                  class="text-gray-400 hover:text-green-600 transition"
                >
                  <.icon name="hero-plus" class="w-3 h-3" />
                </button>
              <% end %>
            </div>
            <%= if @entity.stunts != [] do %>
              <div class="space-y-1 mb-2">
                <%= for stunt <- @entity.stunts do %>
                  <div class="group/stunt text-xs">
                    <div class="flex items-center gap-1">
                      <span
                        class="font-bold text-gray-800 flex-1"
                        style="font-family: 'Patrick Hand', cursive;"
                      >
                        {stunt.name}
                      </span>
                      <%= unless @is_observer do %>
                        <button
                          phx-click="remove_stunt"
                          phx-value-entity-id={@entity.id}
                          phx-value-stunt-id={stunt.id}
                          data-confirm={"Remove stunt \"#{stunt.name}\"?"}
                          class="opacity-0 group-hover/stunt:opacity-100 text-red-400 hover:text-red-600 transition-opacity leading-none shrink-0 touch-reveal"
                        >
                          <.icon name="hero-x-mark" class="w-3 h-3" />
                        </button>
                      <% end %>
                    </div>
                    <div class="text-gray-500 leading-tight">{stunt.effect}</div>
                  </div>
                <% end %>
              </div>
            <% end %>

            <%!-- Refresh --%>
            <%= if @entity.refresh do %>
              <div class="flex items-center gap-1 text-xs mt-1 pt-1 border-t border-gray-200">
                <span class="text-gray-400 uppercase tracking-wide font-bold">Refresh</span>
                <span class="ml-auto font-bold text-gray-900">{@entity.refresh}</span>
              </div>
            <% end %>
          </div>
        <% end %>
      </div>

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

            this._onTouchTrigger = (e) => {
              e.stopPropagation()
              if (this._open) { this.hide() } else { this.show() }
            }
            this.el.addEventListener('touchend', this._onTouchTrigger)

            this._onDocTouch = (e) => {
              if (!this._open) return
              if (this.el.contains(e.target)) return
              this.hide()
            }
            document.addEventListener('touchstart', this._onDocTouch, { passive: true })
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
            document.removeEventListener('touchstart', this._onDocTouch)
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
                  "bg-gray-600 hover:bg-gray-500 text-white opacity-0 group-hover/scard:opacity-100 touch-reveal"
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
          class="w-5 h-5 bg-red-500 hover:bg-red-400 text-white rounded-full flex items-center justify-center text-xs shadow opacity-0 group-hover/scard:opacity-100 transition-opacity touch-reveal"
          data-tooltip="Remove"
        >
          ✕
        </button>
      </div>
    </div>
    """
  end

  def entity_ring(assigns) do
    assigns = assign_new(assigns, :current_participant_id, fn -> nil end)

    can_edit =
      assigns.is_gm || assigns.entity.controller_id == assigns.current_participant_id

    assigns = assign(assigns, :can_edit_entity, can_edit)

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
      <button
        class="ring-item"
        phx-click="ring_action"
        phx-value-action="add_entity_aspect"
        phx-value-entity-id={@entity.id}
        data-tooltip="Add Aspect"
      >
        <.icon name="hero-tag" class="w-3.5 h-3.5" />
      </button>
      <button
        class="ring-item"
        phx-click="ring_action"
        phx-value-action="add_entity_note"
        phx-value-entity-id={@entity.id}
        data-tooltip="Add Note"
      >
        <.icon name="hero-pencil-square" class="w-3.5 h-3.5" />
      </button>
      <%= if @can_edit_entity do %>
        <button
          class="ring-item"
          phx-click="ring_action"
          phx-value-action="edit_entity"
          phx-value-entity-id={@entity.id}
          data-tooltip="Edit entity"
        >
          <.icon name="hero-pencil" class="w-3.5 h-3.5" />
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
        >
          <.icon name="hero-trash" class="w-3.5 h-3.5" />
        </button>
      <% end %>
    </div>
    """
  end

  def gm_notes_ring(assigns) do
    active_scene = assigns.state.active_scene
    scene_templates = assigns.state.scene_templates

    assigns =
      assigns |> assign(:active_scene, active_scene) |> assign(:scene_templates, scene_templates)

    ~H"""
    <div class="context-ring" id="ring-gm-notes">
      <%!-- Always available: create new template --%>
      <button
        class="ring-item"
        phx-click="ring_action"
        phx-value-action="new_scene"
        data-tooltip="New Scene"
      >
        <.icon name="hero-document-plus" class="w-3.5 h-3.5" />
      </button>

      <%!-- Prep mode only --%>
      <%= unless @active_scene do %>
        <%= if length(@scene_templates) > 1 do %>
          <button
            class="ring-item"
            phx-click="ring_action"
            phx-value-action="switch_scene_list"
            data-tooltip="Switch Scene"
          >
            <.icon name="hero-arrows-right-left" class="w-3.5 h-3.5" />
          </button>
        <% end %>
        <button
          class="ring-item"
          phx-click="ring_action"
          phx-value-action="start_scene"
          data-tooltip="Start Scene"
        >
          <.icon name="hero-play" class="w-3.5 h-3.5" />
        </button>
      <% end %>

      <%!-- Live mode only --%>
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
        <button
          class="ring-item"
          phx-click="ring_action"
          phx-value-action="add_scene_aspect"
          data-tooltip="Add Aspect"
        >
          <.icon name="hero-tag" class="w-3.5 h-3.5" />
        </button>
      <% end %>
    </div>
    """
  end

  def table_modal(%{modal: nil} = assigns), do: ~H""

  def table_modal(%{modal: "scene_start"} = assigns) do
    assigns =
      assign_new(assigns, :mention_catalog_json, fn ->
        Fate.Engine.mention_catalog_json(nil)
      end)

    ~H"""
    <.modal_frame variant={:table} inner_click_away={true}>
      <:title>New Scene</:title>
      <form phx-submit="submit_table_modal" class="space-y-3">
        <.scene_start_fields mention_catalog_json={@mention_catalog_json} />
        <.modal_frame_actions primary_label="Create" close_event="close_table_modal" />
      </form>
    </.modal_frame>
    """
  end

  def table_modal(%{modal: "zone_create"} = assigns) do
    ~H"""
    <.modal_frame variant={:table} inner_click_away={true}>
      <:title>Add Zone</:title>
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
        <.modal_frame_actions primary_label="Create" close_event="close_table_modal" />
      </form>
    </.modal_frame>
    """
  end

  def table_modal(%{modal: "switch_scene"} = assigns) do
    scene_templates =
      if assigns[:state], do: assigns.state.scene_templates, else: []

    assigns = assign(assigns, :scene_templates, scene_templates)

    ~H"""
    <.modal_frame variant={:table} inner_click_away={true}>
      <:title>Switch Scene</:title>
      <div class="space-y-2">
        <button
          phx-click="ring_action"
          phx-value-action="new_scene"
          class="w-full text-left px-3 py-2 bg-green-900/30 border border-green-700/20 rounded-lg hover:bg-green-800/40 transition flex items-center gap-2"
        >
          <.icon name="hero-plus" class="w-4 h-4 text-green-400" />
          <span class="text-sm text-green-200 font-bold">New Scene</span>
        </button>
        <%= for template <- @scene_templates do %>
          <button
            phx-click="ring_action"
            phx-value-action="switch_scene"
            phx-value-template-id={template.id}
            class={[
              "w-full text-left px-3 py-2 border rounded-lg hover:bg-amber-800/40 transition",
              if(template.id == @current_template_id,
                do: "bg-amber-800/50 border-amber-600/40",
                else: "bg-amber-900/30 border-amber-700/20"
              )
            ]}
          >
            <div
              class="text-sm text-amber-100 font-bold"
              style="font-family: 'Patrick Hand', cursive;"
            >
              {template.name || "(untitled)"}
            </div>
            <%= if template.description do %>
              <div class="text-xs text-amber-200/40">{template.description}</div>
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
    </.modal_frame>
    """
  end

  def table_modal(%{modal: {"stunt_add", _entity_id}} = assigns) do
    ~H"""
    <.modal_frame variant={:table} inner_click_away={true}>
      <:title>Add Stunt</:title>
      <form phx-submit="submit_table_modal" class="space-y-3">
        <.stunt_add_fields
          name_field="stunt_name"
          effect_field="stunt_effect"
          required={true}
        />
        <.modal_frame_actions primary_label="Add" close_event="close_table_modal" />
      </form>
    </.modal_frame>
    """
  end

  def table_modal(%{modal: "scene_aspect_create"} = assigns) do
    active_scene = if assigns[:state], do: assigns.state.active_scene, else: nil

    scene =
      if active_scene do
        active_scene
      else
        if assigns[:state] && assigns[:current_template_id],
          do: Enum.find(assigns.state.scene_templates, &(&1.id == assigns.current_template_id)),
          else: nil
      end

    target_options =
      if scene do
        [{"scene:#{scene.id}", "Scene: #{scene.name}"}] ++
          Enum.map(scene.zones, fn z -> {"zone:#{z.id}", "Zone: #{z.name}"} end)
      else
        []
      end

    assigns = assign(assigns, :target_options, target_options)

    ~H"""
    <.modal_frame variant={:table} escape_close={true}>
      <:title>Add Situation Aspect</:title>
      <form phx-submit="submit_table_modal" class="space-y-3">
        <.aspect_form_fields
          target_options={@target_options}
          selected_target_ref=""
          role_mode={:hidden}
          fixed_role="situation"
          description_label="Aspect"
          description_placeholder="Raging Inferno"
          description_required={true}
          description_autofocus={true}
        />
        <.modal_frame_actions primary_label="Add" close_event="close_table_modal" />
      </form>
    </.modal_frame>
    """
  end

  def table_modal(%{modal: {modal_type, preselect_entity_id}} = assigns)
      when modal_type in ["note_create", "note_create_for"] do
    assigns = assign(assigns, :modal, "note_create")
    table_modal_note(assigns, preselect_entity_id)
  end

  def table_modal(%{modal: "note_create"} = assigns) do
    participant_id = assigns[:current_participant_id]
    state = assigns[:state]

    default_entity_id =
      if participant_id && state do
        state.entities
        |> Map.values()
        |> Enum.find_value(fn e ->
          if e.controller_id == participant_id, do: e.id
        end)
      end

    table_modal_note(assigns, default_entity_id)
  end

  def table_modal(%{modal: {"entity_aspect_add", entity_id}} = assigns) do
    entity =
      if assigns[:state],
        do: Map.get(assigns.state.entities, entity_id),
        else: nil

    entity_name = if entity, do: entity.name, else: "entity"
    assigns = assign(assigns, :entity_name, entity_name)

    ~H"""
    <.modal_frame variant={:table} escape_close={true}>
      <:title>Add Aspect to {@entity_name}</:title>
      <form phx-submit="submit_table_modal" class="space-y-3">
        <.aspect_form_fields
          show_target_select={false}
          role_label="Type"
          description_placeholder="On Fire!"
          description_required={true}
          description_autofocus={true}
        />
        <.modal_frame_actions primary_label="Add" close_event="close_table_modal" />
      </form>
    </.modal_frame>
    """
  end

  def table_modal(%{modal: {"entity_edit", entity_id}} = assigns) do
    assigns =
      assigns
      |> assign_new(:participants, fn -> [] end)

    entity =
      if assigns[:state],
        do: Map.get(assigns.state.entities, entity_id),
        else: nil

    controller_options =
      Enum.map(assigns.participants, fn bp ->
        {bp.participant_id, "#{bp.participant.name} (#{bp.role})"}
      end)

    e_name = if entity, do: entity.name, else: ""
    e_kind = if entity, do: to_string(entity.kind), else: ""
    e_controller = if entity, do: entity.controller_id, else: nil

    e_fp =
      if entity && entity.fate_points != nil,
        do: to_string(entity.fate_points),
        else: ""

    e_refresh =
      if entity && entity.refresh != nil,
        do: to_string(entity.refresh),
        else: ""

    assigns =
      assigns
      |> assign(:edit_entity_id, entity_id)
      |> assign(:edit_entity, entity)
      |> assign(:e_name, e_name)
      |> assign(:e_kind, e_kind)
      |> assign(:e_controller, e_controller)
      |> assign(:e_fp, e_fp)
      |> assign(:e_refresh, e_refresh)
      |> assign(:controller_options, controller_options)

    ~H"""
    <.modal_frame
      variant={:table}
      escape_close={true}
      inner_extra_class="max-h-[85vh] overflow-y-auto"
    >
      <:title>
        <%= if @edit_entity do %>
          Edit {@edit_entity.name}
        <% else %>
          Edit entity
        <% end %>
      </:title>
      <%= if @edit_entity do %>
        <form phx-submit="submit_table_modal" id="table-modal-entity-edit-form" class="space-y-3">
          <input type="hidden" name="entity_id" value={@edit_entity_id} />
          <.entity_edit_fields
            e_name={@e_name}
            e_kind={@e_kind}
            e_controller={@e_controller}
            e_fp={@e_fp}
            e_refresh={@e_refresh}
            controller_options={@controller_options}
            input_ids={
              %{
                name: "table-entity-edit-name",
                kind: "table-entity-edit-kind",
                controller: "table-entity-edit-controller",
                fate_points: "table-entity-edit-fp",
                refresh: "table-entity-edit-refresh"
              }
            }
          />
          <.modal_frame_actions primary_label="Save" close_event="close_table_modal" />
        </form>
      <% else %>
        <p class="text-sm text-amber-200/60 mb-4">This entity is no longer on the table.</p>
        <button
          type="button"
          phx-click="close_table_modal"
          class="w-full py-2 bg-red-900/40 border border-red-700/30 rounded-lg hover:bg-red-800/40 text-red-200 text-sm"
        >
          Close
        </button>
      <% end %>
    </.modal_frame>
    """
  end

  def table_modal(%{modal: "cheat_sheet"} = assigns) do
    ~H"""
    <div
      class="fixed inset-0 z-[300] flex items-center justify-center bg-black/70"
      phx-window-keydown="close_table_modal"
      phx-key="escape"
    >
      <div
        class="w-[90vw] h-[90vh] bg-stone-900 border border-amber-700/40 rounded-2xl shadow-2xl flex flex-col overflow-hidden"
        phx-click-away="close_table_modal"
        style="font-family: 'Patrick Hand', cursive;"
      >
        <%!-- Header --%>
        <div class="flex items-center justify-between px-6 py-4 border-b border-amber-700/30 shrink-0">
          <h2
            class="text-2xl text-amber-100 tracking-wide"
            style="font-family: 'Permanent Marker', cursive;"
          >
            Fate Core — Quick Reference
          </h2>
          <button
            phx-click="close_table_modal"
            class="text-amber-200/60 hover:text-amber-100 transition text-2xl leading-none"
          >
            <.icon name="hero-x-mark" class="w-6 h-6" />
          </button>
        </div>

        <%!-- Scrollable content --%>
        <div class="flex-1 overflow-y-auto p-6 space-y-8 text-amber-100/90">
          <%!-- The Ladder --%>
          <section>
            <h3 class="text-xl text-amber-200 mb-3" style="font-family: 'Permanent Marker', cursive;">
              The Ladder
            </h3>
            <div class="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-5 gap-2 text-center text-sm">
              <.ladder_rung
                value="+8"
                label="Legendary"
                color="bg-violet-500/30 border-violet-400/50"
              />
              <.ladder_rung value="+7" label="Epic" color="bg-fuchsia-500/30 border-fuchsia-400/50" />
              <.ladder_rung value="+6" label="Fantastic" color="bg-rose-500/30 border-rose-400/50" />
              <.ladder_rung value="+5" label="Superb" color="bg-orange-500/30 border-orange-400/50" />
              <.ladder_rung value="+4" label="Great" color="bg-amber-500/30 border-amber-400/50" />
              <.ladder_rung value="+3" label="Good" color="bg-yellow-500/30 border-yellow-400/50" />
              <.ladder_rung value="+2" label="Fair" color="bg-lime-500/30 border-lime-400/50" />
              <.ladder_rung value="+1" label="Average" color="bg-green-500/30 border-green-400/50" />
              <.ladder_rung value="+0" label="Mediocre" color="bg-stone-500/30 border-stone-400/50" />
              <.ladder_rung value="−1" label="Poor" color="bg-stone-600/30 border-stone-500/50" />
            </div>
          </section>

          <%!-- Four Actions × Four Outcomes --%>
          <section>
            <h3
              class="text-xl text-amber-200 mb-3"
              style="font-family: 'Permanent Marker', cursive;"
            >
              Actions &amp; Outcomes
            </h3>
            <div class="overflow-x-auto -mx-2">
              <table class="w-full text-sm border-collapse min-w-[600px]">
                <thead>
                  <tr class="text-amber-300 text-left">
                    <th class="p-2 w-24"></th>
                    <th class="p-2">Overcome</th>
                    <th class="p-2">Create Advantage</th>
                    <th class="p-2">Attack</th>
                    <th class="p-2">Defend</th>
                  </tr>
                </thead>
                <tbody>
                  <tr class="bg-red-900/20 border-t border-amber-700/20">
                    <td class="p-2 font-bold text-red-300">Fail</td>
                    <td class="p-2">Fail, or succeed at a major cost</td>
                    <td class="p-2">No aspect, or free invoke goes to someone else</td>
                    <td class="p-2">No harm caused</td>
                    <td class="p-2">You don't prevent harm or advantage</td>
                  </tr>
                  <tr class="bg-yellow-900/20 border-t border-amber-700/20">
                    <td class="p-2 font-bold text-yellow-300">Tie</td>
                    <td class="p-2">Succeed at minor cost</td>
                    <td class="p-2">Boost instead of aspect, or free invoke on existing aspect</td>
                    <td class="p-2">Gain a boost</td>
                    <td class="p-2">Grant opponent a boost</td>
                  </tr>
                  <tr class="bg-green-900/20 border-t border-amber-700/20">
                    <td class="p-2 font-bold text-green-300">Succeed</td>
                    <td colspan="4" class="p-2 text-center italic text-amber-200/80">
                      You achieve your goal without any additional benefit or cost
                    </td>
                  </tr>
                  <tr class="bg-emerald-900/20 border-t border-amber-700/20">
                    <td class="p-2 font-bold text-emerald-300 leading-tight">
                      Succeed w/ Style
                      <span class="block text-xs text-emerald-400/70">(3+ shifts)</span>
                    </td>
                    <td class="p-2">Succeed and also gain a boost</td>
                    <td class="p-2">Aspect with two free invokes</td>
                    <td class="p-2">Reduce shifts by 1 to gain a boost</td>
                    <td class="p-2">Gain a boost</td>
                  </tr>
                </tbody>
              </table>
            </div>
          </section>

          <%!-- Two-column layout --%>
          <div class="grid grid-cols-1 lg:grid-cols-2 gap-8">
            <%!-- Left column --%>
            <div class="space-y-8">
              <%!-- Stress & Consequences --%>
              <section>
                <h3
                  class="text-xl text-amber-200 mb-3"
                  style="font-family: 'Permanent Marker', cursive;"
                >
                  Stress &amp; Consequences
                </h3>
                <div class="space-y-2 text-sm">
                  <div class="flex items-center gap-3 bg-stone-800/50 rounded-lg px-3 py-2 border border-stone-700/40">
                    <span class="font-bold text-amber-300 w-16 shrink-0">Stress</span>
                    <span>
                      Boxes 1–4 (3 &amp; 4 unlocked by Physique/Will). Absorbs that many shifts. Clears at end of scene.
                    </span>
                  </div>
                  <div class="flex items-center gap-3 bg-red-950/30 rounded-lg px-3 py-2 border border-red-900/40">
                    <span class="font-bold text-red-300 w-16 shrink-0">Mild</span>
                    <span>Absorbs 2 shifts — clears after one full scene of recovery</span>
                  </div>
                  <div class="flex items-center gap-3 bg-red-950/40 rounded-lg px-3 py-2 border border-red-900/40">
                    <span class="font-bold text-red-400 w-16 shrink-0">Moderate</span>
                    <span>Absorbs 4 shifts — clears after one full session of recovery</span>
                  </div>
                  <div class="flex items-center gap-3 bg-red-950/50 rounded-lg px-3 py-2 border border-red-900/40">
                    <span class="font-bold text-red-500 w-16 shrink-0">Severe</span>
                    <span>
                      Absorbs 6 shifts — requires at least one full scenario to begin recovery
                    </span>
                  </div>
                  <div class="flex items-center gap-3 bg-red-950/60 rounded-lg px-3 py-2 border border-red-900/40">
                    <span class="font-bold text-red-600 w-16 shrink-0">Extreme</span>
                    <span>Absorbs 8 shifts — permanently replaces one of your aspects</span>
                  </div>
                </div>
              </section>

              <%!-- Challenges, Contests & Conflicts --%>
              <section>
                <h3
                  class="text-xl text-amber-200 mb-3"
                  style="font-family: 'Permanent Marker', cursive;"
                >
                  Challenges, Contests &amp; Conflicts
                </h3>
                <div class="space-y-3 text-sm">
                  <div class="bg-stone-800/40 rounded-lg px-4 py-3 border border-stone-700/40">
                    <div class="font-bold text-amber-300 mb-1">Challenge</div>
                    <span class="text-amber-100/80">
                      Series of Overcome rolls against fixed opposition. One roll per obstacle.
                    </span>
                  </div>
                  <div class="bg-stone-800/40 rounded-lg px-4 py-3 border border-stone-700/40">
                    <div class="font-bold text-amber-300 mb-1">Contest</div>
                    <span class="text-amber-100/80">
                      Back-and-forth exchanges. Each side rolls; victories accumulate. First to three wins.
                    </span>
                  </div>
                  <div class="bg-stone-800/40 rounded-lg px-4 py-3 border border-stone-700/40">
                    <div class="font-bold text-amber-300 mb-1">Conflict</div>
                    <span class="text-amber-100/80">
                      Full tactical scene with zones, turn order, and all four actions. Ends via concession or being taken out.
                    </span>
                  </div>
                </div>
              </section>

              <%!-- Stunt Formula --%>
              <section>
                <h3
                  class="text-xl text-amber-200 mb-3"
                  style="font-family: 'Permanent Marker', cursive;"
                >
                  Stunt Formula
                </h3>
                <div class="bg-stone-800/40 rounded-lg px-4 py-3 border border-stone-700/40 text-sm italic text-amber-200/80">
                  "Because I <span class="text-amber-300 not-italic">[describe how you're amazing]</span>, I get +2 when I use
                  <span class="text-amber-300 not-italic">[skill]</span>
                  to <span class="text-amber-300 not-italic">[action]</span>
                  when <span class="text-amber-300 not-italic">[circumstance]</span>."
                </div>
              </section>
            </div>

            <%!-- Right column --%>
            <div class="flex flex-col gap-8">
              <%!-- Invoke vs Compel --%>
              <section>
                <h3
                  class="text-xl text-amber-200 mb-3"
                  style="font-family: 'Permanent Marker', cursive;"
                >
                  Invoke vs Compel
                </h3>
                <div class="space-y-3 text-sm">
                  <div class="bg-blue-950/30 rounded-lg px-4 py-3 border border-blue-800/30">
                    <div class="font-bold text-blue-300 mb-1">Invoke (spend a fate point)</div>
                    <ul class="space-y-1 text-amber-100/80 list-disc list-inside">
                      <li>+2 bonus to your roll, <em>or</em> reroll all dice</li>
                      <li>Must use a relevant aspect you know about</li>
                      <li>Free invokes (from Create Advantage) don't cost a point</li>
                    </ul>
                  </div>
                  <div class="bg-purple-950/30 rounded-lg px-4 py-3 border border-purple-800/30">
                    <div class="font-bold text-purple-300 mb-1">Compel (receive a fate point)</div>
                    <ul class="space-y-1 text-amber-100/80 list-disc list-inside">
                      <li>GM offers a complication based on one of your aspects</li>
                      <li>Accept: take the fate point, the complication happens</li>
                      <li>Refuse: pay a fate point to avoid it</li>
                    </ul>
                  </div>
                </div>
              </section>

              <%!-- Aspect Types --%>
              <section>
                <h3
                  class="text-xl text-amber-200 mb-3"
                  style="font-family: 'Permanent Marker', cursive;"
                >
                  Aspect Types
                </h3>
                <div class="space-y-2 text-sm">
                  <div class="flex gap-2 items-start">
                    <span class="inline-block w-2.5 h-2.5 rounded-full bg-amber-400 mt-1.5 shrink-0">
                    </span>
                    <span>
                      <strong class="text-amber-300">High Concept</strong>
                      — who your character fundamentally is
                    </span>
                  </div>
                  <div class="flex gap-2 items-start">
                    <span class="inline-block w-2.5 h-2.5 rounded-full bg-red-400 mt-1.5 shrink-0">
                    </span>
                    <span>
                      <strong class="text-red-300">Trouble</strong>
                      — a recurring complication or weakness
                    </span>
                  </div>
                  <div class="flex gap-2 items-start">
                    <span class="inline-block w-2.5 h-2.5 rounded-full bg-blue-400 mt-1.5 shrink-0">
                    </span>
                    <span>
                      <strong class="text-blue-300">Situation</strong>
                      — created in play, attached to a scene or zone
                    </span>
                  </div>
                  <div class="flex gap-2 items-start">
                    <span class="inline-block w-2.5 h-2.5 rounded-full bg-yellow-400 mt-1.5 shrink-0">
                    </span>
                    <span>
                      <strong class="text-yellow-300">Boost</strong>
                      — fragile, one free invoke then gone
                    </span>
                  </div>
                  <div class="flex gap-2 items-start">
                    <span class="inline-block w-2.5 h-2.5 rounded-full bg-orange-400 mt-1.5 shrink-0">
                    </span>
                    <span>
                      <strong class="text-orange-300">Consequence</strong>
                      — taken to absorb stress, lasts beyond the scene
                    </span>
                  </div>
                  <div class="flex gap-2 items-start">
                    <span class="inline-block w-2.5 h-2.5 rounded-full bg-stone-400 mt-1.5 shrink-0">
                    </span>
                    <span>
                      <strong class="text-stone-300">Game/Campaign</strong>
                      — truths about the setting everyone knows
                    </span>
                  </div>
                </div>
              </section>

              <%!-- SRD Attribution --%>
              <section class="mt-auto">
                <div class="text-sm text-amber-200/40 leading-relaxed border-t border-amber-700/20 pt-4">
                  This work is based on Fate Core System and Fate Accelerated Edition
                  (<a
                    href="https://fate-srd.com/"
                    target="_blank"
                    class="underline hover:text-amber-200/60"
                  >fate-srd.com</a>),
                  products of Evil Hat Productions, LLC, developed, authored, and edited by
                  Leonard Balsera, Brian Engard, Jeremy Keller, Ryan Macklin, Mike Olson,
                  Clark Valentine, Amanda Valentine, Fred Hicks, and Rob Donoghue, and
                  licensed for our use under the
                  <a
                    href="http://creativecommons.org/licenses/by/3.0/"
                    target="_blank"
                    class="underline hover:text-amber-200/60"
                  >
                    Creative Commons Attribution 3.0 Unported
                  </a>
                  license.
                </div>
              </section>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  def table_modal(assigns), do: ~H""

  defp ladder_rung(assigns) do
    ~H"""
    <div class={["rounded-lg border px-2 py-1.5", @color]}>
      <div class="text-base font-bold text-amber-100">{@value}</div>
      <div class="text-xs text-amber-200/70">{@label}</div>
    </div>
    """
  end

  defp table_modal_note(assigns, preselect_entity_id) do
    state = assigns[:state]
    active_scene = if state, do: state.active_scene, else: nil

    scene =
      if active_scene do
        active_scene
      else
        current_template_id = assigns[:current_template_id]

        if state && current_template_id,
          do: Enum.find(state.scene_templates, &(&1.id == current_template_id)),
          else: nil
      end

    target_options =
      if state do
        scene_opts =
          if scene,
            do:
              [{"scene:#{scene.id}", "Scene: #{scene.name}"}] ++
                Enum.map(scene.zones, fn z -> {"zone:#{z.id}", "Zone: #{z.name}"} end),
            else: []

        entity_opts =
          state.entities
          |> Map.values()
          |> Enum.map(fn e -> {"entity:#{e.id}", "#{e.name} (#{e.kind})"} end)

        scene_opts ++ entity_opts
      else
        []
      end

    preselect_ref = if preselect_entity_id, do: "entity:#{preselect_entity_id}"

    assigns =
      assigns
      |> assign(:target_options, target_options)
      |> assign(:preselect_ref, preselect_ref)
      |> assign_new(:mention_catalog_json, fn -> Fate.Engine.mention_catalog_json(nil) end)

    ~H"""
    <.modal_frame variant={:table} escape_close={true}>
      <:title>Make a Note</:title>
      <form phx-submit="submit_table_modal" class="space-y-3">
        <.note_form_fields
          all_options={@target_options}
          text=""
          target_ref={@preselect_ref || ""}
          note_text_id="note-text-input"
          autofocus_note={true}
          mention_catalog_json={@mention_catalog_json}
        />
        <.modal_frame_actions
          primary_label="OK"
          cancel_label="Cancel"
          close_event="close_table_modal"
        />
      </form>
    </.modal_frame>
    """
  end

  def visible_aspects(aspects, is_gm) do
    if is_gm, do: aspects, else: Enum.reject(aspects, & &1.hidden)
  end

  def aspect_style(aspect) do
    case aspect.role do
      :high_concept -> "bg-amber-300/50 border-l-2 border-amber-500"
      :trouble -> "bg-red-300/50 border-l-2 border-red-400"
      :boost -> "bg-yellow-300/50 border-l-2 border-yellow-400 italic"
      :situation -> "bg-blue-300/50 border-l-2 border-blue-400"
      :consequence -> "bg-red-200/50 border-l-2 border-red-300"
      _ -> "bg-gray-200/50 border-l-2 border-gray-400"
    end
  end

  def available_skills do
    ~w(Athletics Burglary Contacts Crafts Deceive Drive Empathy Fight Investigate Lore Notice Physique Provoke Rapport Resources Shoot Stealth Will)
  end

  def aspect_card_bg(aspect) do
    paper = "url('/images/paper.jpg') center/cover"

    case aspect.role do
      :boost ->
        "background: linear-gradient(rgba(253, 224, 71, 0.45), rgba(253, 224, 71, 0.45)), #{paper}; transform: rotate(-1deg);"

      :situation ->
        "background: linear-gradient(rgba(96, 165, 250, 0.4), rgba(96, 165, 250, 0.4)), #{paper}; transform: rotate(1deg);"

      _ ->
        "background: linear-gradient(rgba(252, 211, 77, 0.35), rgba(252, 211, 77, 0.35)), #{paper};"
    end
  end
end
