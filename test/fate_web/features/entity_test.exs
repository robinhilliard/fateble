defmodule FateWeb.Features.EntityTest do
  use FateWeb.FeatureCase

  defp create_entity_via_modal(session, name, kind \\ "npc") do
    session
    |> open_actions()
    |> click(Query.css("button[phx-click='set_log_tab'][phx-value-tab='events']"))
    |> assert_has(Query.text("Action Palette"))
    |> click(Query.css("#quick-entity_create"))
    |> assert_has(Query.css("form[phx-submit='submit_modal']"))
    |> fill_in(Query.css("input[name='name']"), with: name)
    |> execute_script("""
      document.querySelector('select[name="kind"]').value = '#{kind}';
      document.querySelector('select[name="kind"]').dispatchEvent(new Event('change', {bubbles: true}));
    """)
    |> click(Query.button("Confirm"))
  end

  feature "create entity appears on table", %{session: session} do
    session =
      session
      |> join_as_gm()
      |> fork_bookmark_from("New Game", "UI Testing")
      |> create_entity_via_modal("Test Hero", "pc")
      |> open_table()

    assert_has(session, Query.text("Test Hero"))
  end

  feature "create entity event appears in event log", %{session: session} do
    session
    |> join_as_gm()
    |> fork_bookmark_from("New Game", "UI Testing")
    |> create_entity_via_modal("Event Log Entity")
    |> click(Query.css("button[phx-click='set_log_tab'][phx-value-tab='events']"))
    |> assert_has(Query.text("Event Log Entity"))
  end

  feature "hide and reveal entity via ring menu", %{session: session} do
    session =
      session
      |> join_as_gm()
      |> fork_bookmark_from("New Game", "UI Testing")
      |> create_entity_via_modal("Hideable NPC")
      |> open_table()

    :timer.sleep(2_000)
    entity_id = find_entity_id_by_name(session, "Hideable NPC")
    assert entity_id != nil

    session =
      session
      |> open_ring_menu(entity_id)
      |> click_ring_action(entity_id, "hide")

    :timer.sleep(1_000)
    assert_has(session, Query.text("Hideable NPC"))

    session =
      session
      |> open_ring_menu(entity_id)
      |> click_ring_action(entity_id, "reveal")

    :timer.sleep(1_000)
    assert_has(session, Query.text("Hideable NPC"))
  end

  feature "remove entity via ring menu", %{session: session} do
    session =
      session
      |> join_as_gm()
      |> fork_bookmark_from("New Game", "UI Testing")
      |> create_entity_via_modal("Removable NPC")
      |> open_table()

    :timer.sleep(2_000)
    entity_id = find_entity_id_by_name(session, "Removable NPC")
    assert entity_id != nil

    Wallaby.Browser.execute_script(
      session,
      "window.__origConfirm = window.confirm; window.confirm = () => true;"
    )

    session
    |> open_ring_menu(entity_id)
    |> click_ring_action(entity_id, "remove")

    :timer.sleep(2_000)

    Wallaby.Browser.execute_script(
      session,
      "if (window.__origConfirm) window.confirm = window.__origConfirm;"
    )

    refute_has(session, Query.text("Removable NPC"))
  end

  @sessions 2
  feature "hidden entity not visible to player", %{sessions: [gm, player]} do
    gm =
      gm
      |> join_as_gm("Test GM")
      |> fork_bookmark_from("New Game", "UI Testing")
      |> create_entity_via_modal("Secret NPC")
      |> open_table()

    :timer.sleep(2_000)
    bookmark_id = get_bookmark_id(gm)

    player = join_player_to_bookmark(player, "Test Player", bookmark_id)
    :timer.sleep(1_000)
    assert_has(player, Query.text("Secret NPC"))

    entity_id = find_entity_id_by_name(gm, "Secret NPC")

    _gm =
      gm
      |> open_ring_menu(entity_id)
      |> click_ring_action(entity_id, "hide")

    :timer.sleep(3_000)
    player = visit(player, "/table/#{bookmark_id}")
    :timer.sleep(5_000)

    refute_has(player, Query.text("Secret NPC"))
  end

  @sessions 2
  feature "revealed entity becomes visible to player", %{sessions: [gm, player]} do
    gm =
      gm
      |> join_as_gm("Test GM")
      |> fork_bookmark_from("New Game", "UI Testing")
      |> create_entity_via_modal("Hidden Then Revealed")
      |> open_table()

    :timer.sleep(2_000)
    bookmark_id = get_bookmark_id(gm)
    entity_id = find_entity_id_by_name(gm, "Hidden Then Revealed")

    gm =
      gm
      |> open_ring_menu(entity_id)
      |> click_ring_action(entity_id, "hide")

    :timer.sleep(1_000)

    player = join_player_to_bookmark(player, "Test Player", bookmark_id)
    :timer.sleep(1_000)
    refute_has(player, Query.text("Hidden Then Revealed"))

    _gm =
      gm
      |> open_ring_menu(entity_id)
      |> click_ring_action(entity_id, "reveal")

    :timer.sleep(3_000)
    player = visit(player, "/table/#{bookmark_id}")
    :timer.sleep(5_000)

    assert_has(player, Query.text("Hidden Then Revealed"))
  end
end
