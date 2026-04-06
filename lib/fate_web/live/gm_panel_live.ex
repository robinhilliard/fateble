defmodule FateWeb.GmPanelLive do
  use FateWeb, :live_view

  alias Fate.Engine
  alias Fate.Engine.Search

  import FateWeb.ActionComponents
  import FateWeb.BookmarkComponents

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
        |> assign(:bookmarks, [])
        |> assign(:state, nil)
        |> assign(:is_gm, identity.is_gm)
        |> assign(:is_observer, identity.is_observer)
        |> assign(:current_participant_id, identity.participant_id)
        |> assign(:modal, nil)
        |> assign(:form_data, %{})
        |> assign(:prefill_entity_id, nil)
        |> assign(:fork_bookmark_id, nil)
        |> assign(:participants, [])
        |> assign(:embedded, embedded)
        |> assign(:splash_visible, !embedded)
        |> assign(:search_query, "")
        |> assign(:search_results, [])
        |> assign(:search_selected_entity_ids, MapSet.new())
        |> assign(:search_selected_scene_ids, MapSet.new())
        |> assign(:recent_searches, [])
        |> assign(:show_recent, false)
        |> assign(:search_open, true)
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
    socket =
      socket
      |> assign(:state, state)
      |> assign(:bookmarks, load_active_bookmarks())
      |> assign(:mention_catalog_json, Engine.mention_catalog_json(socket.assigns.bookmark_id))
      |> refresh_search_results()

    {:noreply, socket}
  rescue
    DBConnection.ConnectionError -> {:noreply, socket}
  end

  def handle_info({:search_selection_updated, %{entity_ids: eids, scene_ids: sids}}, socket) do
    {:noreply,
     socket
     |> assign(:search_selected_entity_ids, eids)
     |> assign(:search_selected_scene_ids, sids)}
  end

  def handle_info(:dock_ack, socket) do
    {:noreply, push_event(socket, "close_window", %{})}
  end

  def handle_info({:dock_timeout, panel}, socket) do
    {:noreply, push_navigate(socket, to: ~p"/table/#{socket.assigns.bookmark_id}?panel=#{panel}")}
  end

  @impl true
  def handle_event("splash_done", _params, socket) do
    {:noreply, assign(socket, :splash_visible, false)}
  end

  def handle_event("fork_bookmark", %{"bookmark-id" => bookmark_id}, socket) do
    {:noreply,
     socket
     |> assign(:modal, "fork_bookmark")
     |> assign(:fork_bookmark_id, bookmark_id)}
  end

  def handle_event("close_modal", _params, socket) do
    {:noreply,
     socket |> assign(:modal, nil) |> assign(:form_data, %{}) |> assign(:prefill_entity_id, nil)}
  end

  def handle_event("modal_form_changed", _params, socket) do
    {:noreply, socket}
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

  def handle_event("search_changed", %{"search_query" => query}, socket) do
    trimmed = String.trim(query)

    socket =
      socket
      |> assign(:search_query, trimmed)
      |> assign(:show_recent, trimmed == "" && socket.assigns.recent_searches != [])
      |> run_search(trimmed)

    {:noreply, socket}
  end

  def handle_event("search_submit", %{"search_query" => query}, socket) do
    query = String.trim(query)

    socket =
      if query != "" do
        recent =
          [query | Enum.reject(socket.assigns.recent_searches, &(&1 == query))]
          |> Enum.take(10)

        socket
        |> assign(:recent_searches, recent)
        |> assign(:show_recent, false)
        |> push_event("save_recent_searches", %{searches: recent})
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_event("pick_recent", %{"query" => query}, socket) do
    query = String.trim(query)

    socket =
      socket
      |> assign(:search_query, query)
      |> assign(:show_recent, false)
      |> run_search(query)
      |> push_event("set_search_query", %{query: query})

    {:noreply, socket}
  end

  def handle_event("clear_search", _params, socket) do
    socket =
      socket
      |> assign(:search_query, "")
      |> assign(:search_results, [])
      |> assign(:search_selected_entity_ids, MapSet.new())
      |> assign(:search_selected_scene_ids, MapSet.new())
      |> assign(:show_recent, socket.assigns.recent_searches != [])
      |> push_event("set_search_query", %{query: ""})

    broadcast_current_search_selection(socket)
    {:noreply, socket}
  end

  def handle_event("toggle_search_select", %{"result-id" => id, "result-type" => type}, socket) do
    socket =
      case type do
        "entity" ->
          ids = toggle_set(socket.assigns.search_selected_entity_ids, id)
          assign(socket, :search_selected_entity_ids, ids)

        "scene" ->
          ids = toggle_set(socket.assigns.search_selected_scene_ids, id)
          assign(socket, :search_selected_scene_ids, ids)

        _ ->
          socket
      end

    broadcast_current_search_selection(socket)
    {:noreply, socket}
  end

  def handle_event("toggle_search_panel", _params, socket) do
    opening = !socket.assigns.search_open

    socket =
      socket
      |> assign(:search_open, opening)
      |> assign(
        :show_recent,
        opening && socket.assigns.search_query == "" && socket.assigns.recent_searches != []
      )

    {:noreply, socket}
  end

  def handle_event("focus_search", _params, socket) do
    show = socket.assigns.search_query == "" && socket.assigns.recent_searches != []
    {:noreply, assign(socket, :show_recent, show)}
  end

  def handle_event("blur_search", _params, socket) do
    {:noreply, assign(socket, :show_recent, false)}
  end

  def handle_event("init_recent_searches", %{"searches" => searches}, socket)
      when is_list(searches) do
    cleaned =
      searches
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.uniq()
      |> Enum.take(10)

    socket =
      socket
      |> assign(:recent_searches, cleaned)
      |> push_event("save_recent_searches", %{searches: cleaned})

    {:noreply, socket}
  end

  def handle_event("restore_entity", %{"entity-id" => entity_id}, socket) do
    state = socket.assigns.state

    case Map.get(state.removed_entities, entity_id) do
      nil ->
        {:noreply, socket}

      entity ->
        tree_ids = Search.ownership_tree(state, entity_id)

        parents_first =
          tree_ids
          |> Enum.filter(&Map.has_key?(state.removed_entities, &1))
          |> sort_parents_first(state.removed_entities)

        Enum.each(parents_first, fn id ->
          case Map.get(state.removed_entities, id) do
            nil ->
              :ok

            e ->
              Engine.append_event(socket.assigns.bookmark_id, %{
                type: :entity_restore,
                target_id: id,
                description: "Restore #{e.name || "entity"}",
                detail: %{"entity_id" => id}
              })
          end
        end)

        if parents_first == [] do
          Engine.append_event(socket.assigns.bookmark_id, %{
            type: :entity_restore,
            target_id: entity_id,
            description: "Restore #{entity.name || "entity"}",
            detail: %{"entity_id" => entity_id}
          })
        end

        {:noreply, socket}
    end
  end

  def handle_event("submit_modal", params, socket) do
    case socket.assigns.modal do
      "fork_bookmark" ->
        bookmark_id = socket.assigns[:fork_bookmark_id]

        case Fate.Game.get_bookmark(bookmark_id) do
          {:ok, %{head_event_id: head_id} = parent} when head_id != nil ->
            with {:ok, bmk_event} <-
                   Fate.Game.append_event(%{
                     parent_id: head_id,
                     type: :bookmark_create,
                     description: params["name"],
                     detail: %{"name" => params["name"]}
                   }),
                 {:ok, new_bm} <-
                   Fate.Game.create_bookmark(%{
                     name: params["name"],
                     head_event_id: bmk_event.id,
                     parent_bookmark_id: parent.id
                   }) do
              {:noreply, push_navigate(socket, to: ~p"/table/#{new_bm.id}")}
            else
              _ -> {:noreply, put_flash(socket, :error, "Could not create bookmark")}
            end

          _ ->
            {:noreply, put_flash(socket, :error, "Bookmark not found")}
        end

      _ ->
        {:noreply, socket}
    end
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
          id="splash-gm"
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

      <div class="p-4 border-b border-amber-900/30 flex items-center justify-between">
        <h2
          class="text-lg font-bold text-amber-100"
          style="font-family: 'Permanent Marker', cursive;"
        >
          Bookmarks
        </h2>
        <%= unless @embedded do %>
          <button
            id="dock-gm"
            phx-hook=".DockPanel"
            data-panel="gm"
            data-bookmark-id={@bookmark_id}
            class="p-1.5 rounded-lg text-amber-200/40 hover:text-amber-200/70 hover:bg-amber-900/30 transition"
            title="Dock into table view"
          >
            <.icon name="hero-arrow-down-on-square" class="w-4 h-4" />
          </button>
        <% end %>
      </div>

      <div class="shrink-0 overflow-y-auto p-3" style="max-height: 30vh" id="bookmark-tree">
        <.bookmark_tree bookmark_id={@bookmark_id} bookmarks={@bookmarks} />
      </div>

      <div
        class="flex-1 flex flex-col min-h-0 border-t border-amber-900/30"
        id="search-panel"
        phx-hook=".SearchPanel"
      >
        <button
          class="p-3 flex items-center justify-between w-full text-left hover:bg-amber-900/10 transition"
          phx-click="toggle_search_panel"
        >
          <h2
            class="text-lg font-bold text-amber-100"
            style="font-family: 'Permanent Marker', cursive;"
          >
            Search
          </h2>
          <.icon
            name={if @search_open, do: "hero-chevron-down", else: "hero-chevron-right"}
            class="w-3.5 h-3.5 text-amber-200/40"
          />
        </button>

        <%= if @search_open do %>
          <div class="px-3 pb-2">
            <div class="relative">
              <form phx-change="search_changed" phx-submit="search_submit" id="search-form">
                <div class="relative">
                  <.icon
                    name="hero-magnifying-glass"
                    class="w-3.5 h-3.5 absolute left-2.5 top-1/2 -translate-y-1/2 text-amber-200/30 pointer-events-none"
                  />
                  <input
                    type="text"
                    name="search_query"
                    id="search-input"
                    value={@search_query}
                    placeholder="Search entities & scenes..."
                    phx-debounce="300"
                    phx-focus="focus_search"
                    phx-blur="blur_search"
                    phx-hook="MentionTypeahead"
                    data-mention-catalog={@mention_catalog_json}
                    autocomplete="off"
                    class="w-full pl-8 pr-8 py-1.5 rounded-lg text-xs bg-amber-950/40 border border-amber-900/30 text-amber-100 placeholder-amber-200/20 focus:outline-none focus:border-amber-700/50 focus:ring-1 focus:ring-amber-700/30"
                  />
                  <%= if @search_query != "" do %>
                    <button
                      type="button"
                      phx-click="clear_search"
                      class="absolute right-2 top-1/2 -translate-y-1/2 text-amber-200/30 hover:text-amber-200/60"
                    >
                      <.icon name="hero-x-mark" class="w-3.5 h-3.5" />
                    </button>
                  <% end %>
                </div>
              </form>

              <%= if @show_recent && @recent_searches != [] do %>
                <div class="absolute z-20 left-0 right-0 top-full mt-1 rounded-lg border border-amber-900/30 bg-[#1a1410] shadow-xl overflow-hidden">
                  <div class="px-2.5 py-1.5 text-[10px] uppercase tracking-wider text-amber-200/30 font-semibold">
                    Recent
                  </div>
                  <%= for {q, idx} <- Enum.with_index(@recent_searches) do %>
                    <button
                      type="button"
                      phx-click="pick_recent"
                      phx-value-query={q}
                      onmousedown="event.preventDefault()"
                      data-recent-index={idx}
                      class="recent-item w-full text-left px-2.5 py-1.5 text-xs text-amber-100/70 hover:bg-amber-900/20 hover:text-amber-100 transition truncate"
                    >
                      {q}
                    </button>
                  <% end %>
                </div>
              <% end %>
            </div>
          </div>

          <div class="flex-1 overflow-y-auto px-3 pb-3">
            <%= if @search_query != "" && @search_results == [] do %>
              <div class="text-amber-200/20 text-xs text-center italic py-4">
                No results
              </div>
            <% end %>

            <% grouped = group_with_ownership(@search_results, @state) %>
            <%= for group <- grouped do %>
              <div class="mb-1.5">
                <%= for {result, depth} <- group do %>
                  <% selected =
                    if result.type == :entity,
                      do: MapSet.member?(@search_selected_entity_ids, result.id),
                      else: MapSet.member?(@search_selected_scene_ids, result.id) %>
                  <.search_result_row
                    result={result}
                    depth={depth}
                    selected={selected}
                    on_table={result.status == :on_table}
                  />
                <% end %>
              </div>
            <% end %>
          </div>
        <% end %>
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
      <script :type={Phoenix.LiveView.ColocatedHook} name=".SearchPanel">
        export default {
          mounted() {
            try {
              const raw = localStorage.getItem("fate_recent_searches")
              if (raw) {
                const searches = JSON.parse(raw)
                if (Array.isArray(searches)) {
                  this.pushEvent("init_recent_searches", { searches: searches.slice(0, 10) })
                }
              }
            } catch (_) {}

            this.handleEvent("save_recent_searches", ({ searches }) => {
              try {
                localStorage.setItem("fate_recent_searches", JSON.stringify(searches))
              } catch (_) {}
            })

            this.handleEvent("set_search_query", ({ query }) => {
              const input = this.el.querySelector("#search-input")
              if (input) {
                input.value = query
                if (query === "") input.focus()
              }
            })

            this._recentIndex = -1

            this.el.addEventListener("keydown", (e) => {
              const input = this.el.querySelector("#search-input")
              const items = this.el.querySelectorAll(".recent-item")

              if (e.key === "Escape") {
                if (input && input.value !== "") {
                  input.value = ""
                  this._recentIndex = -1
                  this.pushEvent("clear_search", {})
                } else if (input) {
                  input.blur()
                }
                return
              }

              if (items.length === 0) return

              if (e.key === "ArrowDown") {
                e.preventDefault()
                this._recentIndex = Math.min(this._recentIndex + 1, items.length - 1)
                this._highlightRecent(items)
              } else if (e.key === "ArrowUp") {
                e.preventDefault()
                this._recentIndex = Math.max(this._recentIndex - 1, -1)
                this._highlightRecent(items)
              } else if (e.key === "Enter" && this._recentIndex >= 0 && this._recentIndex < items.length) {
                e.preventDefault()
                const query = items[this._recentIndex].getAttribute("phx-value-query")
                this._recentIndex = -1
                this.pushEvent("pick_recent", { query })
              }
            })
          },
          updated() {
            this._recentIndex = -1
          },
          _highlightRecent(items) {
            items.forEach((el, i) => {
              if (i === this._recentIndex) {
                el.classList.add("bg-amber-900/30", "text-amber-100")
              } else {
                el.classList.remove("bg-amber-900/30", "text-amber-100")
              }
            })
          }
        }
      </script>
    </div>
    """
  end

  defp search_result_row(assigns) do
    ~H"""
    <div
      class={[
        "flex items-center gap-1.5 px-2 py-1 rounded-md text-xs cursor-pointer transition group",
        if(@selected, do: "bg-amber-800/30 ring-1 ring-amber-600/40", else: "hover:bg-amber-900/20")
      ]}
      style={if @depth > 0, do: "margin-left: #{@depth * 16}px"}
    >
      <button
        type="button"
        phx-click="toggle_search_select"
        phx-value-result-id={@result.id}
        phx-value-result-type={@result.type}
        class="flex-1 flex items-center gap-1.5 min-w-0 text-left"
      >
        <span class={[
          "shrink-0 w-1.5 h-1.5 rounded-full",
          status_dot_class(@result.status)
        ]} />
        <span class="truncate text-amber-100/90">{@result.name}</span>
        <span class="shrink-0 text-[10px] text-amber-200/30">
          {result_kind_label(@result)}
        </span>
        <span class={["shrink-0 text-[10px] px-1 rounded", status_badge_class(@result.status)]}>
          {status_label(@result.status)}
        </span>
      </button>

      <%= if @result.type == :entity && @result.status == :removed do %>
        <button
          type="button"
          phx-click="restore_entity"
          phx-value-entity-id={@result.id}
          class="shrink-0 px-1.5 py-0.5 rounded text-[10px] font-medium border border-amber-700/40 text-amber-200/60 hover:text-amber-100 hover:border-amber-600/60 hover:bg-amber-800/30 transition opacity-0 group-hover:opacity-100"
          title="Restore to table"
        >
          <.icon name="hero-arrow-uturn-left" class="w-3 h-3" />
        </button>
      <% end %>
    </div>
    """
  end

  defp status_dot_class(:on_table), do: "bg-emerald-400"
  defp status_dot_class(:removed), do: "bg-red-400/60"
  defp status_dot_class(:template), do: "bg-amber-400/60"
  defp status_dot_class(:active), do: "bg-emerald-300"
  defp status_dot_class(_), do: "bg-gray-400/40"

  defp status_badge_class(:on_table), do: "bg-emerald-900/30 text-emerald-300/70"
  defp status_badge_class(:removed), do: "bg-red-900/20 text-red-300/50"
  defp status_badge_class(:template), do: "bg-amber-900/20 text-amber-300/50"
  defp status_badge_class(:active), do: "bg-emerald-900/30 text-emerald-300/70"
  defp status_badge_class(_), do: "bg-gray-900/20 text-gray-300/40"

  defp status_label(:on_table), do: "table"
  defp status_label(:removed), do: "removed"
  defp status_label(:template), do: "template"
  defp status_label(:active), do: "active"
  defp status_label(_), do: ""

  defp result_kind_label(%{type: :scene}), do: "scene"

  defp result_kind_label(%{type: :entity, kind: kind}) when kind != nil do
    kind |> to_string() |> String.downcase()
  end

  defp result_kind_label(_), do: ""

  defp group_with_ownership(results, state) when is_nil(state), do: Enum.map(results, &[{&1, 0}])

  defp group_with_ownership(results, state) do
    result_map = Map.new(results, &{&1.id, &1})
    all_entities = Map.merge(state.entities, state.removed_entities)

    {entity_results, scene_results} = Enum.split_with(results, &(&1.type == :entity))

    trees =
      entity_results
      |> Enum.reduce({[], MapSet.new()}, fn result, {groups, seen} ->
        if MapSet.member?(seen, result.id) do
          {groups, seen}
        else
          tree_ids = Search.ownership_tree(state, result.id)

          tree =
            build_tree_rows(tree_ids, all_entities, result_map, state)

          new_seen = Enum.reduce(tree_ids, seen, &MapSet.put(&2, &1))
          {groups ++ [tree], new_seen}
        end
      end)
      |> elem(0)

    scene_groups = Enum.map(scene_results, &[{&1, 0}])

    trees ++ scene_groups
  end

  defp build_tree_rows(ids, all_entities, result_map, state) do
    ids
    |> Enum.map(fn id ->
      entity = Map.get(all_entities, id)

      if entity do
        depth = compute_depth(all_entities, id, 0)

        result =
          Map.get_lazy(result_map, id, fn ->
            status = if Map.has_key?(state.entities, id), do: :on_table, else: :removed

            %{
              type: :entity,
              id: id,
              name: entity.name || "Unnamed",
              status: status,
              kind: entity.kind,
              data: entity
            }
          end)

        {result, depth}
      else
        nil
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.sort_by(fn {_result, depth} -> depth end)
  end

  defp compute_depth(_all, _id, depth) when depth > 10, do: depth

  defp compute_depth(all, id, depth) do
    case Map.get(all, id) do
      %{parent_id: parent_id} when is_binary(parent_id) and parent_id != "" ->
        if Map.has_key?(all, parent_id), do: compute_depth(all, parent_id, depth + 1), else: depth

      _ ->
        depth
    end
  end

  defp run_search(socket, query) do
    query = String.trim(query)

    if String.length(query) < 2 || is_nil(socket.assigns.state) do
      socket
      |> assign(:search_results, [])
      |> prune_search_selection([])
    else
      results = Search.search(socket.assigns.state, query)

      socket
      |> assign(:search_results, results)
      |> prune_search_selection(results)
    end
  end

  defp refresh_search_results(socket) do
    if socket.assigns.search_query != "" && socket.assigns.state != nil do
      run_search(socket, socket.assigns.search_query)
    else
      socket
    end
  end

  defp prune_search_selection(socket, results) do
    state = socket.assigns.state

    result_entity_ids =
      results
      |> Enum.filter(&(&1.type == :entity))
      |> Enum.flat_map(fn r ->
        if state, do: Search.ownership_tree(state, r.id), else: [r.id]
      end)
      |> MapSet.new()

    result_scene_ids =
      results |> Enum.filter(&(&1.type == :scene)) |> MapSet.new(& &1.id)

    pruned_entities =
      MapSet.intersection(socket.assigns.search_selected_entity_ids, result_entity_ids)

    pruned_scenes =
      MapSet.intersection(socket.assigns.search_selected_scene_ids, result_scene_ids)

    changed =
      pruned_entities != socket.assigns.search_selected_entity_ids ||
        pruned_scenes != socket.assigns.search_selected_scene_ids

    if changed do
      socket =
        socket
        |> assign(:search_selected_entity_ids, pruned_entities)
        |> assign(:search_selected_scene_ids, pruned_scenes)

      broadcast_current_search_selection(socket)
      socket
    else
      socket
    end
  end

  defp toggle_set(%MapSet{} = set, id) do
    if MapSet.member?(set, id), do: MapSet.delete(set, id), else: MapSet.put(set, id)
  end

  defp broadcast_current_search_selection(socket) do
    FateWeb.Helpers.broadcast_search_selection(socket, %{
      entity_ids: socket.assigns.search_selected_entity_ids,
      scene_ids: socket.assigns.search_selected_scene_ids
    })
  end

  defp sort_parents_first(ids, removed_entities) do
    Enum.sort_by(ids, fn id ->
      case Map.get(removed_entities, id) do
        %{parent_id: nil} -> 0
        %{parent_id: ""} -> 0
        %{parent_id: _} -> 1
        _ -> 0
      end
    end)
  end

  defp init_state(socket, bookmark_id) do
    Engine.subscribe(bookmark_id)

    pid = socket.assigns.current_participant_id

    if pid do
      Phoenix.PubSub.subscribe(
        Fate.PubSub,
        FateWeb.Helpers.search_selection_topic(bookmark_id, pid)
      )
    end

    case Engine.derive_state(bookmark_id) do
      {:ok, state} ->
        socket
        |> assign(:state, state)
        |> assign(:bookmarks, load_active_bookmarks())

      _ ->
        socket
    end
  end

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
end
