defmodule FateWeb.Features.AspectTest do
  use FateWeb.FeatureCase

  defp setup_with_entity(session) do
    session
    |> join_as_gm()
    |> fork_bookmark("UI Testing")
    |> create_entity("Aspect Target")
  end

  defp create_entity(session, name) do
    session
    |> open_actions()
    |> click(Query.css("button[phx-click='set_log_tab'][phx-value-tab='events']"))
    |> assert_has(Query.text("Action Palette"))
    |> click(Query.css("#quick-entity_create"))
    |> assert_has(Query.css("form[phx-submit='submit_modal']"))
    |> fill_in(Query.css("input[name='name']"), with: name)
    |> click(Query.button("Confirm"))
    |> then(fn s -> :timer.sleep(1_000); s end)
  end

  defp create_aspect_on_entity(session, entity_name, aspect_text) do
    session
    |> open_actions()
    |> click(Query.css("button[phx-click='set_log_tab'][phx-value-tab='events']"))
    |> assert_has(Query.text("Action Palette"))
    |> click(Query.css("#quick-aspect_create"))
    |> assert_has(Query.css("form[phx-submit='submit_modal']"))
    |> then(fn s ->
      entity_id = find_entity_id_by_name(s, entity_name)
      if entity_id do
        Wallaby.Browser.execute_script(s, """
          const sel = document.querySelector('select[name="target_ref"]');
          if (sel) {
            for (const opt of sel.options) {
              if (opt.value.startsWith('entity:')) { sel.value = opt.value; sel.dispatchEvent(new Event('change', {bubbles: true})); break; }
            }
          }
        """)
      end
      s
    end)
    |> fill_in(Query.css("input[name='description'], textarea[name='description']", count: :any, at: 0), with: aspect_text)
    |> click(Query.button("Confirm"))
    |> then(fn s -> :timer.sleep(1_000); s end)
  end

  feature "create entity aspect via actions modal", %{session: session} do
    session =
      session
      |> setup_with_entity()
      |> create_aspect_on_entity("Aspect Target", "Test Aspect")
      |> open_table()

    :timer.sleep(1_000)
    assert_has(session, Query.text("Test Aspect"))
  end

  feature "aspect create event appears in log", %{session: session} do
    session =
      session
      |> setup_with_entity()
      |> create_aspect_on_entity("Aspect Target", "Logged Aspect")
      |> click(Query.css("button[phx-click='set_log_tab'][phx-value-tab='events']"))

    assert_has(session, Query.text("Logged Aspect"))
  end

  feature "remove entity aspect on table", %{session: session} do
    session =
      session
      |> setup_with_entity()
      |> create_aspect_on_entity("Aspect Target", "Removable Aspect")
      |> open_table()

    :timer.sleep(2_000)
    assert_has(session, Query.text("Removable Aspect"))

    # Click the remove button on the aspect (visible on hover, use JS)
    run_script(session, """
      const aspects = document.querySelectorAll('[id^="entity-aspect-"]');
      for (const a of aspects) {
        if (a.textContent.includes('Removable Aspect')) {
          const btn = a.querySelector('button[phx-click="remove_aspect"]');
          if (btn) btn.click();
          break;
        }
      }
    """)

    :timer.sleep(2_000)
    refute_has(session, Query.text("Removable Aspect"))
  end

  @sessions 2
  feature "hidden entity aspect not visible to player", %{sessions: [gm, player]} do
    gm =
      gm
      |> join_as_gm("Test GM")
      |> fork_bookmark("UI Testing")
      |> create_entity("Vis Entity")
      |> open_actions()
      |> click(Query.css("button[phx-click='set_log_tab'][phx-value-tab='events']"))
      |> assert_has(Query.text("Action Palette"))
      |> click(Query.css("#quick-aspect_create"))
      |> assert_has(Query.css("form[phx-submit='submit_modal']"))

    # Select entity target and set hidden
    Wallaby.Browser.execute_script(gm, """
      const sel = document.querySelector('select[name="target_ref"]');
      if (sel) {
        for (const opt of sel.options) {
          if (opt.value.startsWith('entity:')) { sel.value = opt.value; sel.dispatchEvent(new Event('change', {bubbles: true})); break; }
        }
      }
      const hidden = document.querySelector('input[name="hidden"]');
      if (hidden) { hidden.checked = true; hidden.dispatchEvent(new Event('change', {bubbles: true})); }
    """)

    gm =
      gm
      |> fill_in(Query.css("input[name='description'], textarea[name='description']", count: :any, at: 0), with: "Secret Aspect")
      |> click(Query.button("Confirm"))

    :timer.sleep(1_000)
    gm = open_table(gm)
    :timer.sleep(1_000)
    bookmark_id = get_bookmark_id(gm)

    assert_has(gm, Query.text("Secret Aspect"))

    player = join_player_to_bookmark(player, "Test Player", bookmark_id)
    :timer.sleep(2_000)

    refute_has(player, Query.text("Secret Aspect"))
  end

  defp run_script(session, js, args \\ []) do
    Wallaby.Browser.execute_script(session, js, args)
    session
  end
end
