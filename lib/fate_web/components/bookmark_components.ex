defmodule FateWeb.BookmarkComponents do
  @moduledoc """
  Function components for rendering the bookmark tree.
  """

  use Phoenix.Component
  import FateWeb.CoreComponents

  use Phoenix.VerifiedRoutes,
    endpoint: FateWeb.Endpoint,
    router: FateWeb.Router,
    statics: FateWeb.static_paths()

  attr :bookmark_id, :string, required: true
  attr :bookmarks, :list, required: true

  def bookmark_tree(assigns) do
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

  attr :bookmark, :map, required: true
  attr :children_map, :map, required: true
  attr :current_id, :string, required: true
  attr :depth, :integer, required: true

  def bookmark_node(assigns) do
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
end
