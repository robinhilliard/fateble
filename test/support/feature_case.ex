defmodule FateWeb.FeatureCase do
  @moduledoc """
  Test case for browser-based feature tests using Wallaby.

  Provides helpers for joining as GM/player, navigating between
  table and actions views, forking bookmarks, and interacting
  with the spring layout system.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      use Wallaby.Feature

      import FateWeb.FeatureCase.Helpers

      @endpoint FateWeb.Endpoint
    end
  end

  setup tags do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(Fate.Repo, shared: not tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)

    metadata = Phoenix.Ecto.SQL.Sandbox.metadata_for(Fate.Repo, pid)
    {:ok, sandbox: metadata}
  end

  defmodule Helpers do
    @moduledoc false

    use Wallaby.DSL

    defp run_script(session, js, args \\ []) do
      Wallaby.Browser.execute_script(session, js, args)
      session
    end

    defp eval_script(session, js, args) do
      {:ok, result} = Wallaby.WebdriverClient.execute_script(session, js, args)
      result
    end

    # ── Join helpers ──

    def join_as_gm(session, name \\ "Test GM") do
      join_as(session, name, "gm")
    end

    def join_as_player(session, name \\ "Test Player") do
      join_as(session, name, "player")
    end

    defp join_as(session, name, role) do
      label_text = %{"gm" => "GM", "player" => "Player", "observer" => "Observer"}[role]

      session
      |> visit("/")
      |> find(Query.css("#lobby"), fn s -> s end)
      |> fill_in(Query.css("input[name='name']"), with: name)
      |> click(Query.text(label_text, count: :any, at: 0))
      |> click(Query.button("Join Game"))
      |> find(Query.css("#table-view"), fn s -> s end)
      |> wait_for_splash_dismiss()
    end

    def join_player_to_bookmark(session, name \\ "Test Player", bookmark_id) do
      session
      |> join_as_player(name)
      |> visit("/table/#{bookmark_id}")
      |> find(Query.css("#table-view"), fn s -> s end)
      |> wait_for_splash_dismiss()
    end

    # ── Navigation helpers ──

    def open_actions(session) do
      bookmark_id = get_bookmark_id(session)

      session
      |> visit("/actions/#{bookmark_id}")
      |> wait_for_splash_dismiss()
      |> assert_has(Query.css("button[phx-click='set_log_tab']", minimum: 1))
    end

    def open_table(session) do
      bookmark_id = get_bookmark_id(session)

      session
      |> visit("/table/#{bookmark_id}")
      |> find(Query.css("#table-view"), fn s -> s end)
      |> wait_for_splash_dismiss()
    end

    def navigate_to_bookmark(session, bookmark_id) do
      session
      |> visit("/table/#{bookmark_id}")
      |> find(Query.css("#table-view"), fn s -> s end)
      |> wait_for_splash_dismiss()
    end

    def get_bookmark_id(session) do
      url = current_url(session)

      cond do
        url =~ ~r{/table/([a-f0-9-]+)} ->
          [_, id] = Regex.run(~r{/table/([a-f0-9-]+)}, url)
          id

        url =~ ~r{/actions/([a-f0-9-]+)} ->
          [_, id] = Regex.run(~r{/actions/([a-f0-9-]+)}, url)
          id

        true ->
          raise "Cannot extract bookmark_id from URL: #{url}"
      end
    end

    # ── Splash helpers ──

    def wait_for_splash_dismiss(session) do
      :timer.sleep(1_500)

      run_script(session, """
        const splash = document.querySelector('#splash');
        if (splash) {
          splash.style.display = 'none';
          splash.style.opacity = '0';
          splash.style.pointerEvents = 'none';
        }
      """)

      :timer.sleep(500)
      session
    end

    # ── Bookmark helpers ──

    def fork_bookmark(session, name) do
      bookmark_id = get_bookmark_id(session)

      session
      |> open_actions()
      |> click(Query.css("button[phx-click='set_log_tab'][phx-value-tab='bookmarks']"))
      |> find(Query.css("#bookmark-tree"), fn s -> s end)
      |> click(Query.css("button[phx-click='fork_bookmark'][phx-value-bookmark-id='#{bookmark_id}']"))
      |> assert_has(Query.css("form[phx-submit='submit_modal']"))
      |> fill_in(Query.css("input[name='name']"), with: name)
      |> click(Query.button("Confirm"))
      |> find(Query.css("#table-view"), fn s -> s end)
      |> wait_for_splash_dismiss()
    end

    # ── Drag-and-drop helper ──

    def drag_and_drop(session, source_selector, target_selector) do
      run_script(session, """
        (function() {
          const src = document.querySelector(arguments[0]);
          const tgt = document.querySelector(arguments[1]);
          if (!src || !tgt) return;
          const dt = new DataTransfer();
          const srcRect = src.getBoundingClientRect();
          const tgtRect = tgt.getBoundingClientRect();

          for (const [key, val] of Object.entries(src.dataset)) {
            if (key.endsWith('Id') || key === 'entityId') {
              const kebab = key.replace(/([A-Z])/g, '-$1').toLowerCase();
              dt.setData(kebab, val);
            }
          }

          src.dispatchEvent(new DragEvent('dragstart', {
            dataTransfer: dt, bubbles: true,
            clientX: srcRect.x + srcRect.width/2, clientY: srcRect.y + srcRect.height/2
          }));
          tgt.dispatchEvent(new DragEvent('dragover', {
            dataTransfer: dt, bubbles: true,
            clientX: tgtRect.x + tgtRect.width/2, clientY: tgtRect.y + tgtRect.height/2
          }));
          tgt.dispatchEvent(new DragEvent('drop', {
            dataTransfer: dt, bubbles: true,
            clientX: tgtRect.x + tgtRect.width/2, clientY: tgtRect.y + tgtRect.height/2
          }));
          src.dispatchEvent(new DragEvent('dragend', {
            dataTransfer: dt, bubbles: true
          }));
        })()
      """, [source_selector, target_selector])

      :timer.sleep(500)
      session
    end

    # ── Spring layout helpers ──

    def wait_for_spring_settle(session) do
      run_script(session, """
        return new Promise((resolve) => {
          let attempts = 0;
          const check = () => {
            attempts++;
            const el = document.querySelector('#table-view');
            const hook = el && el._phxHookObject;
            if ((hook && hook.settled) || attempts > 200) {
              resolve(true);
            } else {
              requestAnimationFrame(check);
            }
          };
          check();
        });
      """)

      session
    end

    def get_element_position(session, selector) do
      eval_script(session, """
        const el = document.querySelector(arguments[0]);
        if (!el) return null;
        const rect = el.getBoundingClientRect();
        return {x: rect.x, y: rect.y, width: rect.width, height: rect.height};
      """, [selector])
    end

    def drag_element_to(session, selector, target_x, target_y) do
      run_script(session, """
        (function() {
          const el = document.querySelector(arguments[0]);
          if (!el) return;
          const rect = el.getBoundingClientRect();
          const startX = rect.x + rect.width / 2;
          const startY = rect.y + rect.height / 2;

          el.dispatchEvent(new MouseEvent('mousedown', {
            bubbles: true, clientX: startX, clientY: startY
          }));

          const steps = 10;
          for (let i = 1; i <= steps; i++) {
            const x = startX + (arguments[1] - startX) * (i / steps);
            const y = startY + (arguments[2] - startY) * (i / steps);
            window.dispatchEvent(new MouseEvent('mousemove', {
              bubbles: true, clientX: x, clientY: y
            }));
          }

          window.dispatchEvent(new MouseEvent('mouseup', {
            bubbles: true, clientX: arguments[1], clientY: arguments[2]
          }));
        })()
      """, [selector, target_x, target_y])

      :timer.sleep(300)
      session
    end

    def double_click_element(session, selector) do
      run_script(session, """
        const el = document.querySelector(arguments[0]);
        if (el) el.dispatchEvent(new MouseEvent('dblclick', {bubbles: true}));
      """, [selector])

      :timer.sleep(200)
      session
    end

    # ── GM notes ring helpers ──

    @doc """
    Opens the GM notes ring. NOTE: The GM ring hook name is currently
    `FateWeb.TableComponents.RingTrigger` but should be `.RingTrigger`.
    Until fixed, ring_action events must be pushed via JS workaround.
    """
    def open_gm_ring(session) do
      session
    end

    def click_gm_ring_action(session, action) do
      run_script(session, """
        (function() {
          const trigger = document.querySelector('#gm-notes-trigger');
          if (!trigger) return;
          trigger.classList.add('ring-open');
          const ring = trigger.querySelector('.context-ring');
          if (!ring) return;
          const btn = ring.querySelector('button[phx-value-action="' + arguments[0] + '"]');
          if (btn) {
            btn.style.pointerEvents = 'auto';
            btn.style.opacity = '1';
            btn.dispatchEvent(new MouseEvent('click', {bubbles: true}));
          }
        })()
      """, [action])

      :timer.sleep(1_000)
      session
    end

    def push_table_event(session, event, params \\ %{}) do
      run_script(session, """
        const el = document.querySelector('[data-phx-session]');
        if (el && window.liveSocket) {
          const view = window.liveSocket.getViewByEl(el);
          if (view) {
            view.pushEvent('click', el, arguments[0], arguments[1]);
          }
        }
      """, [event, params])

      :timer.sleep(1_000)
      session
    end

    # ── Ring menu helpers ──

    def open_ring_menu(session, entity_id) do
      run_script(session, """
        const trigger = document.querySelector('#ring-trigger-' + arguments[0]);
        if (trigger) {
          trigger.dispatchEvent(new MouseEvent('mouseenter', {bubbles: true}));
        }
      """, [entity_id])

      :timer.sleep(600)
      session
    end

    def click_ring_action(session, entity_id, action) do
      run_script(session, """
        const ring = document.querySelector('#ring-' + arguments[0]);
        if (ring) {
          const btn = ring.querySelector('button[phx-value-action="' + arguments[1] + '"]');
          if (btn) btn.click();
        }
      """, [entity_id, action])

      :timer.sleep(500)
      session
    end

    def find_entity_id_by_name(session, name) do
      eval_script(session, """
        const cards = document.querySelectorAll('[id^="entity-"]');
        for (const card of cards) {
          if (card.textContent.includes(arguments[0])) {
            return card.id.replace('entity-', '');
          }
        }
        return null;
      """, [name])
    end
  end
end
