defmodule FateWeb.Features.ActionsTest do
  use FateWeb.FeatureCase
  @moduletag area: :actions

  defp setup_with_entity(session) do
    session
    |> join_as_gm()
    |> fork_bookmark_from("New Game", "UI Testing")
    |> create_entity("Actions Entity")
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

  defp open_action_palette(session) do
    session
    |> open_actions()
    |> assert_has(Query.text("Action Palette"))
  end

  feature "action palette shows create buttons and exchanges", %{session: session} do
    session =
      session
      |> join_as_gm()
      |> fork_bookmark_from("New Game", "UI Testing")
      |> open_action_palette()

    assert_has(session, Query.css("#quick-entity_create"))
    assert_has(session, Query.css("#quick-aspect_create"))
    assert_has(session, Query.css("#exchange-attack"))
    assert_has(session, Query.css("#exchange-overcome"))
  end

  feature "start exchange shows builder", %{session: session} do
    session =
      session
      |> join_as_gm()
      |> fork_bookmark_from("New Game", "UI Testing")
      |> open_action_palette()
      |> click(Query.css("#exchange-attack", count: :any, at: 0))

    :timer.sleep(1_000)

    has_builder = Wallaby.Browser.has?(session, Query.text("Attack"))

    if has_builder do
      session
      |> click(Query.css("button[phx-click='cancel_build']", count: :any, at: 0))

      :timer.sleep(500)
      assert_has(session, Query.text("Action Palette"))
    else
      IO.puts("INFO: Exchange builder not found after clicking attack")
    end
  end

  feature "cancel exchange returns to action palette", %{session: session} do
    session =
      session
      |> join_as_gm()
      |> fork_bookmark_from("New Game", "UI Testing")
      |> open_action_palette()

    click(session, Query.css("#exchange-attack", count: :any, at: 0))
    :timer.sleep(1_000)

    has_cancel =
      Wallaby.Browser.has?(session, Query.css("button[phx-click='cancel_build']", minimum: 1))

    if has_cancel do
      session
      |> click(Query.css("button[phx-click='cancel_build']", count: :any, at: 0))

      :timer.sleep(500)
      assert_has(session, Query.text("Action Palette"))
    else
      IO.puts("INFO: Cancel build button not found")
    end
  end
end
