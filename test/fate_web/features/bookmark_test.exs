defmodule FateWeb.Features.BookmarkTest do
  use FateWeb.FeatureCase
  @moduletag area: :bookmarks

  feature "fork bookmark creates child and navigates to table", %{session: session} do
    session =
      session
      |> join_as_gm()
      |> fork_bookmark("UI Testing")

    assert current_url(session) =~ ~r{/table/[a-f0-9-]+}
    assert_has(session, Query.css("#table-view"))
  end

  feature "fork from New Game creates clean bookmark without demo data", %{session: session} do
    session =
      session
      |> join_as_gm()
      |> fork_bookmark_from("New Game", "Clean Fork")
      |> open_table()

    :timer.sleep(1_000)
    assert_has(session, Query.css("#table-view"))
    refute_has(session, Query.text("Behind the Big Top"))
    assert_has(session, Query.text("No active scene", minimum: 1))
  end

  feature "forked bookmark appears in bookmark tree", %{session: session} do
    session =
      session
      |> join_as_gm()
      |> fork_bookmark_from("New Game", "UI Testing")
      |> open_gm_panel()

    assert_has(session, Query.text("UI Testing"))
  end

  feature "parent bookmark shows lock icon after fork", %{session: session} do
    session =
      session
      |> join_as_gm()
      |> fork_bookmark_from("New Game", "UI Testing")
      |> open_gm_panel()

    assert_has(session, Query.css("span[class*='hero-lock-closed']", minimum: 1))
  end

  feature "nested fork creates deeper tree", %{session: session} do
    session =
      session
      |> join_as_gm()
      |> fork_bookmark_from("New Game", "UI Testing")
      |> fork_bookmark("Nested Fork")
      |> open_gm_panel()

    assert_has(session, Query.text("UI Testing"))
    assert_has(session, Query.text("Nested Fork"))
  end
end
