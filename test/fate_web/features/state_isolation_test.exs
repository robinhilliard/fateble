defmodule FateWeb.Features.StateIsolationTest do
  use FateWeb.FeatureCase
  @moduletag area: :isolation

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

  defp js_eval(session, js, args) do
    {:ok, result} = Wallaby.WebdriverClient.execute_script(session, js, args)
    result
  end

  defp entity_selected?(session, entity_id) do
    js_eval(
      session,
      """
        const el = document.querySelector('#entity-' + arguments[0]);
        return el && (el.classList.contains('ring-2') || el.classList.contains('scale-105'));
      """,
      [entity_id]
    )
  end

  defp click_entity(session, entity_id) do
    Wallaby.Browser.execute_script(
      session,
      """
        const el = document.querySelector('#entity-' + arguments[0]);
        if (el) el.click();
      """,
      [entity_id]
    )

    :timer.sleep(1_000)
    session
  end

  @sessions 2
  feature "selection is private per user — GM selection not visible to player",
          %{sessions: [gm, player]} do
    gm =
      gm
      |> join_as_gm("Test GM")
      |> fork_bookmark_from("New Game", "Selection Isolation")
      |> create_entity("Shared Entity")
      |> open_table()

    :timer.sleep(2_000)
    bookmark_id = get_bookmark_id(gm)

    player = join_player_to_bookmark(player, "Test Player", bookmark_id)
    :timer.sleep(2_000)

    entity_id = find_entity_id_by_name(gm, "Shared Entity")
    assert entity_id != nil

    gm = click_entity(gm, entity_id)

    assert entity_selected?(gm, entity_id), "GM should see entity selected"

    :timer.sleep(1_000)
    refute entity_selected?(player, entity_id), "Player should NOT see GM's selection"
  end

  @sessions 2
  feature "player selection is not visible to GM", %{sessions: [gm, player]} do
    gm =
      gm
      |> join_as_gm("Test GM")
      |> fork_bookmark_from("New Game", "Reverse Isolation")
      |> create_entity("Another Entity")
      |> open_table()

    :timer.sleep(2_000)
    bookmark_id = get_bookmark_id(gm)

    player = join_player_to_bookmark(player, "Test Player", bookmark_id)
    :timer.sleep(2_000)

    entity_id = find_entity_id_by_name(player, "Another Entity")
    assert entity_id != nil

    player = click_entity(player, entity_id)

    assert entity_selected?(player, entity_id), "Player should see entity selected"

    :timer.sleep(1_000)
    refute entity_selected?(gm, entity_id), "GM should NOT see player's selection"
  end

  @sessions 2
  feature "modal form state is private per user", %{sessions: [gm, player]} do
    gm =
      gm
      |> join_as_gm("Test GM")
      |> fork_bookmark_from("New Game", "Modal Isolation")
      |> open_actions()
      |> assert_has(Query.text("Action Palette"))

    bookmark_id = get_bookmark_id(gm)

    player =
      player
      |> join_as_player("Test Player")
      |> visit("/panel/player/#{bookmark_id}")
      |> wait_for_splash_dismiss()

    :timer.sleep(1_000)

    gm = click(gm, Query.css("#quick-entity_create"))
    :timer.sleep(500)
    assert_has(gm, Query.css("form[phx-submit='submit_modal']"))

    refute Wallaby.Browser.has?(player, Query.css("form[phx-submit='submit_modal']")),
           "Player should NOT see GM's modal"
  end

  @sessions 2
  feature "exchange builder is shared between users", %{sessions: [gm, player]} do
    gm =
      gm
      |> join_as_gm("Test GM")
      |> fork_bookmark_from("New Game", "Exchange Sharing")

    bookmark_id = get_bookmark_id(gm)

    player =
      player
      |> join_as_player("Test Player")
      |> visit("/panel/player/#{bookmark_id}")
      |> wait_for_splash_dismiss()

    :timer.sleep(1_000)

    _gm =
      gm
      |> open_actions()
      |> click(Query.css("#exchange-attack", count: :any, at: 0))

    :timer.sleep(2_000)

    assert Wallaby.Browser.has?(player, Query.css("#exchange-builder")),
           "Player should see exchange builder started by GM"
  end

  @sessions 2
  feature "saved state is shared — entity created by GM visible to player",
          %{sessions: [gm, player]} do
    gm =
      gm
      |> join_as_gm("Test GM")
      |> fork_bookmark_from("New Game", "Saved State Sharing")

    bookmark_id = get_bookmark_id(gm)

    player = join_player_to_bookmark(player, "Test Player", bookmark_id)
    :timer.sleep(1_000)

    _gm = create_entity(gm, "Visible To All")
    :timer.sleep(3_000)

    player = visit(player, "/table/#{bookmark_id}")
    :timer.sleep(3_000)

    assert_has(player, Query.text("Visible To All"))
  end
end
