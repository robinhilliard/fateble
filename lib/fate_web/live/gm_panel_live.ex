defmodule FateWeb.GmPanelLive do
  use FateWeb, :live_view

  alias Fate.Engine

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
        |> assign(:modal, nil)
        |> assign(:form_data, %{})
        |> assign(:prefill_entity_id, nil)
        |> assign(:fork_bookmark_id, nil)
        |> assign(:participants, [])
        |> assign(:embedded, embedded)
        |> assign(:splash_visible, !embedded)

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
    {:noreply,
     socket
     |> assign(:state, state)
     |> assign(:bookmarks, load_active_bookmarks())}
  end

  def handle_info(:dock_ack, socket) do
    {:noreply, push_event(socket, "close_window", %{})}
  end

  def handle_info({:dock_timeout, panel}, socket) do
    {:noreply,
     push_navigate(socket, to: ~p"/table/#{socket.assigns.bookmark_id}?panel=#{panel}")}
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
    <div class={["flex flex-col relative", if(@embedded, do: "h-full", else: "h-screen")]} style="background: #1a1410; color: #e8dcc8;">
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

      <div class="flex-1 overflow-y-auto p-3" id="bookmark-tree">
        <.bookmark_tree bookmark_id={@bookmark_id} bookmarks={@bookmarks} />
      </div>

      <div class="p-4 border-t border-amber-900/30">
        <div class="text-amber-200/20 text-xs text-center italic">
          More GM tools coming soon
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

  defp init_state(socket, bookmark_id) do
    Engine.subscribe(bookmark_id)

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
