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

        case Ash.create(Fate.Game.Participant, %{name: name, color: color}, action: :create) do
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
    participant = Ash.get!(Fate.Game.Participant, participant_id)

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
      </div>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".LobbyIdentity">
        export default {
          mounted() {
            this.handleEvent("store_identity", ({participant_id, name, role}) => {
              if (participant_id) localStorage.setItem("fate_participant_id", participant_id)
              else localStorage.removeItem("fate_participant_id")
              localStorage.setItem("fate_name", name)
              localStorage.setItem("fate_role", role)
            })
          }
        }
      </script>
    </div>
    """
  end

  defp valid_participant?(participant_id) do
    case Ash.get(Fate.Game.Participant, participant_id, not_found_error?: false) do
      {:ok, p} when p != nil -> true
      _ -> false
    end
  end

  defp load_existing_participants do
    case Ash.read(Fate.Game.Participant) do
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

        Ash.create(
          Fate.Game.BookmarkParticipant,
          %{
            bookmark_id: bookmark_id,
            participant_id: participant_id,
            role: role_atom,
            seat_index: seat_index
          },
          action: :create
        )
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
    alias Fate.Game.{Event, Bookmark}

    with {:ok, root_bmk_event} <-
           Ash.create(
             Event,
             %{
               type: :bookmark_create,
               description: "New Game",
               detail: %{"name" => "New Game"}
             },
             action: :append
           ),
         {:ok, null_scene} <-
           Ash.create(
             Event,
             %{
               parent_id: root_bmk_event.id,
               type: :scene_start,
               description: "Default scene",
               detail: %{
                 "scene_id" => Ash.UUID.generate(),
                 "name" => nil,
                 "description" => nil,
                 "gm_notes" => "NO SCENE"
               }
             },
             action: :append
           ),
         {:ok, root_bookmark} <-
           Ash.create(
             Bookmark,
             %{
               name: "New Game",
               head_event_id: null_scene.id
             },
             action: :create
           ) do
      case Fate.Game.Demo.create_from_root(root_bookmark) do
        {:ok, demo_bookmark} -> demo_bookmark.id
        _ -> root_bookmark.id
      end
    else
      _ -> raise "Failed to bootstrap"
    end
  end

  defp random_color do
    Enum.random(["#2563eb", "#16a34a", "#d946ef", "#f59e0b", "#06b6d4", "#ef4444", "#8b5cf6"])
  end
end
