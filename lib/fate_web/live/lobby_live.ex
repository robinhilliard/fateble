defmodule FateWeb.LobbyLive do
  use FateWeb, :live_view

  alias Fate.Game.Bookmarks

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      params = get_connect_params(socket)
      participant_id = params["participant_id"]
      role = params["participant_role"]

      cond do
        role == "observer" ->
          bookmark_id = find_or_create_bookmark()
          {:ok, push_navigate(socket, to: ~p"/table/#{bookmark_id}")}

        participant_id && valid_participant?(participant_id) ->
          bookmark_id = find_or_create_bookmark()
          {:ok, push_navigate(socket, to: ~p"/table/#{bookmark_id}")}

        true ->
          existing = load_existing_participants()
          stored_name = params["participant_name"]
          stored_role = params["participant_role"]

          {:ok,
           socket
           |> assign(:existing_participants, existing)
           |> assign(:stored_name, stored_name)
           |> assign(:stored_role, stored_role)
           |> assign(:mcp_url, nil)
           |> assign(:show_mcp_setup, false)
           |> assign(:mode, :prompt)}
      end
    else
      {:ok, assign(socket, :mode, :loading)}
    end
  end

  @impl true
  def handle_event("join", params, socket) do
    role = params["role"]
    bookmark_id = find_or_create_bookmark()

    case role do
      "observer" ->
        socket =
          socket
          |> push_event("store_identity", %{
            participant_id: nil,
            name: "Observer",
            role: "observer"
          })
          |> push_navigate(to: ~p"/table/#{bookmark_id}")

        {:noreply, socket}

      _ ->
        name = params["name"] || "Player"
        color = params["color"] || random_color()

        case Fate.Game.create_participant(%{name: name, color: color}) do
          {:ok, participant} ->
            ensure_bookmark_participant(bookmark_id, participant.id, role)

            socket =
              socket
              |> push_event("store_identity", %{
                participant_id: participant.id,
                name: name,
                role: role
              })
              |> push_navigate(to: ~p"/table/#{bookmark_id}")

            {:noreply, socket}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Failed to create participant")}
        end
    end
  end

  def handle_event(
        "select_existing",
        %{"participant-id" => participant_id, "role" => role},
        socket
      ) do
    bookmark_id = find_or_create_bookmark()
    {:ok, participant} = Fate.Game.get_participant(participant_id)

    ensure_bookmark_participant(bookmark_id, participant_id, role)

    socket =
      socket
      |> push_event("store_identity", %{
        participant_id: participant_id,
        name: participant.name,
        role: role
      })
      |> push_navigate(to: ~p"/table/#{bookmark_id}")

    {:noreply, socket}
  end

  def handle_event("set_mcp_url", %{"url" => url}, socket) do
    {:noreply, assign(socket, :mcp_url, url)}
  end

  def handle_event("toggle_mcp_setup", _params, socket) do
    {:noreply, assign(socket, :show_mcp_setup, !socket.assigns.show_mcp_setup)}
  end

  defp mcp_config_details(assigns) do
    ~H"""
    <details class="group">
      <summary class="text-xs text-amber-200/50 cursor-pointer hover:text-amber-200/70 transition">
        {@label} <span class="text-amber-200/30">({@hint})</span>
      </summary>
      <div class="mt-1 relative">
        <pre class="px-2 py-1.5 bg-amber-900/30 border border-amber-700/20 rounded text-xs text-amber-100 font-mono overflow-x-auto"><code>{@config}</code></pre>
        <button
          id={"copy-#{@id}-config"}
          phx-hook=".CopyToClipboard"
          data-copy={@config}
          class="absolute top-1 right-1 p-1 bg-amber-900/50 rounded hover:bg-amber-800/50 transition"
          title="Copy config"
        >
          <.icon name="hero-clipboard-document" class="w-3 h-3 text-amber-200/40" />
        </button>
      </div>
    </details>
    """
  end

  @impl true
  def render(%{mode: :loading} = assigns) do
    ~H"""
    <div
      class="flex items-center justify-center h-screen"
      style="background: #1a3a1a url('/images/felt.png') repeat; background-size: 512px 512px;"
    >
      <div class="text-center">
        <h1
          class="text-4xl font-bold text-amber-100 mb-4"
          style="font-family: 'Permanent Marker', cursive;"
        >
          Fateble
        </h1>
        <p class="text-amber-200/50">Loading...</p>
      </div>
    </div>
    """
  end

  def render(%{mode: :prompt} = assigns) do
    ~H"""
    <div
      id="lobby"
      class="flex items-center justify-center h-screen"
      style="background: #1a3a1a url('/images/felt.png') repeat; background-size: 512px 512px;"
      phx-hook=".LobbyIdentity"
    >
      <div
        class="w-96 p-8 rounded-xl shadow-2xl"
        style="background: #1a1510; border: 1px solid rgba(180, 140, 80, 0.3);"
      >
        <h1
          class="text-3xl font-bold text-amber-100 mb-6 text-center"
          style="font-family: 'Permanent Marker', cursive;"
        >
          Join the Table
        </h1>

        <%!-- New participant form --%>
        <form phx-submit="join" class="space-y-4 mb-6">
          <div>
            <label class="block text-sm text-amber-200/70 mb-1">Your Name</label>
            <input
              type="text"
              name="name"
              value={@stored_name}
              placeholder="Enter your name"
              required
              class="w-full px-3 py-2 bg-amber-900/30 border border-amber-700/30 rounded-lg text-amber-100 text-sm placeholder-amber-200/20"
            />
          </div>

          <div>
            <label class="block text-sm text-amber-200/70 mb-2">Role</label>
            <div class="grid grid-cols-3 gap-2">
              <label class="role-option flex flex-col items-center gap-1 p-3 rounded-lg border border-amber-700/30 bg-amber-900/20 hover:bg-amber-900/30 cursor-pointer transition has-[:checked]:border-amber-500 has-[:checked]:bg-amber-900/40">
                <input
                  type="radio"
                  name="role"
                  value="gm"
                  checked={@stored_role == "gm"}
                  class="sr-only"
                />
                <.icon name="hero-eye" class="w-5 h-5 text-amber-300" />
                <span class="text-xs text-amber-200 font-bold">GM</span>
              </label>
              <label class="role-option flex flex-col items-center gap-1 p-3 rounded-lg border border-amber-700/30 bg-amber-900/20 hover:bg-amber-900/30 cursor-pointer transition has-[:checked]:border-amber-500 has-[:checked]:bg-amber-900/40">
                <input
                  type="radio"
                  name="role"
                  value="player"
                  checked={@stored_role != "gm" && @stored_role != "observer"}
                  class="sr-only"
                />
                <.icon name="hero-user" class="w-5 h-5 text-blue-300" />
                <span class="text-xs text-amber-200 font-bold">Player</span>
              </label>
              <label class="role-option flex flex-col items-center gap-1 p-3 rounded-lg border border-amber-700/30 bg-amber-900/20 hover:bg-amber-900/30 cursor-pointer transition has-[:checked]:border-amber-500 has-[:checked]:bg-amber-900/40">
                <input
                  type="radio"
                  name="role"
                  value="observer"
                  checked={@stored_role == "observer"}
                  class="sr-only"
                />
                <.icon name="hero-eye-slash" class="w-5 h-5 text-gray-400" />
                <span class="text-xs text-amber-200 font-bold">Observer</span>
              </label>
            </div>
          </div>

          <div>
            <label class="block text-sm text-amber-200/70 mb-1">Color</label>
            <input
              type="color"
              name="color"
              value={random_color()}
              class="w-full h-8 rounded cursor-pointer bg-transparent border border-amber-700/30"
            />
          </div>

          <button
            type="submit"
            class="w-full py-2.5 bg-green-800/60 border border-green-600/30 rounded-lg hover:bg-green-700/60 text-green-200 font-bold text-sm transition"
          >
            Join Game
          </button>
        </form>

        <%!-- Existing participants --%>
        <%= if @existing_participants != [] do %>
          <div class="border-t border-amber-700/20 pt-4">
            <p class="text-xs text-amber-200/40 mb-2 uppercase tracking-wide">Or rejoin as:</p>
            <div class="space-y-1">
              <%= for {p, role} <- Enum.map(@existing_participants, fn p -> {p, participant_role(p)} end) do %>
                <div class="flex items-center gap-2 px-3 py-2 rounded-lg hover:bg-amber-900/20 transition">
                  <div class="w-3 h-3 rounded-full shrink-0" style={"background: #{p.color};"} />
                  <span
                    class="flex-1 text-sm text-amber-100"
                    style="font-family: 'Patrick Hand', cursive;"
                  >
                    {p.name}
                  </span>
                  <span class="text-xs text-amber-200/40 uppercase">{role}</span>
                  <button
                    phx-click="select_existing"
                    phx-value-participant-id={p.id}
                    phx-value-role={role}
                    class="px-2 py-1 text-xs bg-amber-900/40 hover:bg-amber-800/40 rounded text-amber-200/70 transition"
                  >
                    Rejoin
                  </button>
                </div>
              <% end %>
            </div>
          </div>
        <% end %>

        <%!-- MCP setup --%>
        <div class="border-t border-amber-700/20 pt-4 mt-2">
          <button
            phx-click="toggle_mcp_setup"
            class="flex items-center gap-2 w-full text-left text-xs text-amber-200/40 uppercase tracking-wide hover:text-amber-200/60 transition"
          >
            <.icon
              name={if @show_mcp_setup, do: "hero-chevron-down", else: "hero-chevron-right"}
              class="w-3 h-3"
            /> Connect an AI Assistant
          </button>

          <div class={[
            "overflow-hidden transition-all duration-200",
            if(@show_mcp_setup, do: "max-h-[600px] opacity-100 mt-3", else: "max-h-0 opacity-0")
          ]}>
            <p class="text-xs text-amber-200/50 mb-3">
              Fateble includes an MCP server that lets AI assistants prep and run
              Fate RPG games alongside the GM.
            </p>

            <%= if @mcp_url do %>
              <div class="mb-3">
                <label class="block text-xs text-amber-200/40 uppercase tracking-wide mb-1">
                  MCP Endpoint
                </label>
                <div class="flex items-center gap-1">
                  <code
                    class="flex-1 px-2 py-1.5 bg-amber-900/30 border border-amber-700/20 rounded text-xs text-amber-100 font-mono truncate"
                    id="mcp-url-display"
                  >
                    {@mcp_url}
                  </code>
                  <button
                    id="copy-mcp-url"
                    phx-hook=".CopyToClipboard"
                    data-copy={@mcp_url}
                    class="px-2 py-1.5 bg-amber-900/30 border border-amber-700/20 rounded hover:bg-amber-800/30 transition"
                    title="Copy URL"
                  >
                    <.icon name="hero-clipboard-document" class="w-3.5 h-3.5 text-amber-200/50" />
                  </button>
                </div>
              </div>

              <label class="block text-xs text-amber-200/40 uppercase tracking-wide mb-1">
                Configuration
              </label>
              <p class="text-xs text-amber-200/40 mb-2">
                Add this to your AI client's MCP config:
              </p>

              <div class="space-y-2">
                <.mcp_config_details
                  id="cursor"
                  label="Cursor"
                  hint=".cursor/mcp.json"
                  config={mcp_config_json(@mcp_url)}
                />
                <.mcp_config_details
                  id="claude"
                  label="Claude Desktop"
                  hint="claude_desktop_config.json"
                  config={mcp_config_json(@mcp_url)}
                />
                <.mcp_config_details
                  id="windsurf"
                  label="Windsurf"
                  hint="~/.codeium/windsurf/mcp_config.json"
                  config={mcp_config_json(@mcp_url)}
                />
                <.mcp_config_details
                  id="chatgpt"
                  label="ChatGPT Desktop"
                  hint="Settings → Developer → Edit Config"
                  config={mcp_config_json(@mcp_url)}
                />
                <.mcp_config_details
                  id="vscode"
                  label="VS Code / Copilot"
                  hint=".vscode/mcp.json"
                  config={vscode_config_json(@mcp_url)}
                />
              </div>
            <% else %>
              <p class="text-xs text-amber-200/30 italic">Detecting endpoint URL…</p>
            <% end %>
          </div>
        </div>
      </div>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".LobbyIdentity">
        export default {
          mounted() {
            this.pushEvent("set_mcp_url", { url: window.location.origin + "/api/mcp" })
            this.handleEvent("store_identity", ({participant_id, name, role}) => {
              if (participant_id) localStorage.setItem("fate_participant_id", participant_id)
              else localStorage.removeItem("fate_participant_id")
              localStorage.setItem("fate_name", name)
              localStorage.setItem("fate_role", role)
            })
          }
        }
      </script>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".CopyToClipboard">
        export default {
          mounted() {
            this.el.addEventListener("click", () => {
              const text = this.el.dataset.copy
              navigator.clipboard.writeText(text).then(() => {
                const icon = this.el.querySelector("span[data-icon]") || this.el.querySelector("span")
                if (!icon) return
                const original = icon.className
                icon.className = icon.className.replace("hero-clipboard-document", "hero-check")
                setTimeout(() => { icon.className = original }, 1500)
              })
            })
          }
        }
      </script>
    </div>
    """
  end

  defp valid_participant?(participant_id) do
    case Fate.Game.get_participant(participant_id) do
      {:ok, p} when p != nil -> true
      _ -> false
    end
  end

  defp load_existing_participants do
    case Fate.Game.list_participants() do
      {:ok, participants} -> participants
      _ -> []
    end
  end

  defp participant_role(participant) do
    require Ash.Query

    case Ash.read(
           Fate.Game.BookmarkParticipant
           |> Ash.Query.filter(participant_id: participant.id)
           |> Ash.Query.limit(1)
         ) do
      {:ok, [bp | _]} -> to_string(bp.role)
      _ -> "player"
    end
  end

  defp ensure_bookmark_participant(bookmark_id, participant_id, role) do
    require Ash.Query

    existing =
      Ash.read(
        Fate.Game.BookmarkParticipant
        |> Ash.Query.filter(bookmark_id: bookmark_id, participant_id: participant_id)
      )

    case existing do
      {:ok, [_ | _]} ->
        :ok

      _ ->
        seat_index = next_seat_index(bookmark_id)
        role_atom = if role == "gm", do: :gm, else: :player

        Fate.Game.create_bookmark_participant(%{
          bookmark_id: bookmark_id,
          participant_id: participant_id,
          role: role_atom,
          seat_index: seat_index
        })
    end
  end

  defp next_seat_index(bookmark_id) do
    require Ash.Query

    case Ash.read(
           Fate.Game.BookmarkParticipant
           |> Ash.Query.filter(bookmark_id: bookmark_id)
         ) do
      {:ok, bps} -> length(bps)
      _ -> 0
    end
  end

  defp find_or_create_bookmark do
    case Bookmarks.find_latest_leaf() do
      {:ok, bookmark} -> bookmark.id
      :none -> bootstrap()
    end
  end

  defp bootstrap do
    with {:ok, root_bmk_event} <-
           Fate.Game.append_event(%{
             type: :bookmark_create,
             description: "New Game",
             detail: %{"name" => "New Game"}
           }),
         {:ok, root_bookmark} <-
           Fate.Game.create_bookmark(%{
             name: "New Game",
             head_event_id: root_bmk_event.id
           }) do
      case Fate.Game.Demo.create_from_root(root_bookmark) do
        {:ok, demo_bookmark} -> demo_bookmark.id
        _ -> root_bookmark.id
      end
    else
      _ -> raise "Failed to bootstrap"
    end
  end

  defp mcp_config_json(mcp_url) do
    Jason.encode!(
      %{"mcpServers" => %{"fateble" => %{"url" => mcp_url}}},
      pretty: true
    )
  end

  defp vscode_config_json(mcp_url) do
    Jason.encode!(
      %{"servers" => %{"fateble" => %{"type" => "sse", "url" => mcp_url}}},
      pretty: true
    )
  end

  defp random_color do
    Enum.random(["#2563eb", "#16a34a", "#d946ef", "#f59e0b", "#06b6d4", "#ef4444", "#8b5cf6"])
  end
end
