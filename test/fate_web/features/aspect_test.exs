defmodule FateWeb.Features.AspectTest do
  use FateWeb.FeatureCase
  @moduletag area: :aspects

  defp setup_with_entity(session) do
    session
    |> join_as_gm()
    |> fork_bookmark_from("New Game", "UI Testing")
    |> create_entity("Aspect Target")
  end

  defp create_entity(session, name) do
    session
    |> open_actions()
    |> assert_has(Query.text("Action Palette"))
    |> click(Query.css("#quick-entity_create"))
    |> assert_has(Query.css("form[phx-submit='submit_modal']"))
    |> fill_in(Query.css("input[name='name']"), with: name)
    |> click(Query.button("Confirm"))
    |> then(fn s ->
      :timer.sleep(1_000)
      s
    end)
  end

  defp create_aspect_on_entity(session, _entity_name, aspect_text) do
    session
    |> open_actions()
    |> assert_has(Query.text("Action Palette"))
    |> click(Query.css("#quick-aspect_create"))
    |> assert_has(Query.css("form[phx-submit='submit_modal']"))
    |> select_option_by_value_prefix("target_ref", "entity:")
    |> fill_in(Query.css("input[name='description']"), with: aspect_text)
    |> click(Query.button("Confirm"))
    |> then(fn s ->
      :timer.sleep(1_000)
      s
    end)
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

    Wallaby.Browser.execute_script(session, """
      const aspects = document.querySelectorAll('[id^="entity-aspect-"]');
      for (const a of aspects) {
        if (a.textContent.includes('Removable Aspect')) {
          const btn = a.querySelector('button[phx-click="remove_aspect"]');
          if (btn) { btn.style.opacity = '1'; btn.click(); }
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
      |> fork_bookmark_from("New Game", "UI Testing")
      |> create_entity("Vis Entity")
      |> open_actions()
      |> assert_has(Query.text("Action Palette"))
      |> click(Query.css("#quick-aspect_create"))
      |> assert_has(Query.css("form[phx-submit='submit_modal']"))
      |> select_option_by_value_prefix("target_ref", "entity:")

    Wallaby.Browser.execute_script(gm, """
      const hidden = document.querySelector('input[name="hidden"]');
      if (hidden) { hidden.checked = true; hidden.dispatchEvent(new Event('input', {bubbles: true})); }
    """)

    gm =
      gm
      |> fill_in(Query.css("input[name='description']"), with: "Secret Aspect")
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
end
