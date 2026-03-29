defmodule FateWeb.Features.BookmarkTest do
  use FateWeb.FeatureCase

  feature "fork bookmark creates child and navigates to table", %{session: session} do
    session =
      session
      |> join_as_gm()
      |> fork_bookmark("UI Testing")

    assert current_url(session) =~ ~r{/table/[a-f0-9-]+}
    assert_has(session, Query.css("#table-view"))
  end

  feature "forked bookmark appears in bookmark tree", %{session: session} do
    session =
      session
      |> join_as_gm()
      |> fork_bookmark("UI Testing")
      |> open_actions()
      |> click(Query.css("button[phx-click='set_log_tab'][phx-value-tab='bookmarks']"))
      |> find(Query.css("#bookmark-tree"), fn s -> s end)

    assert_has(session, Query.text("UI Testing"))
  end

  feature "parent bookmark shows lock icon after fork", %{session: session} do
    session =
      session
      |> join_as_gm()
      |> fork_bookmark("UI Testing")
      |> open_actions()
      |> click(Query.css("button[phx-click='set_log_tab'][phx-value-tab='bookmarks']"))
      |> find(Query.css("#bookmark-tree"), fn s -> s end)

    assert_has(session, Query.css("span[class*='hero-lock-closed']", minimum: 1))
  end

  feature "nested fork creates deeper tree", %{session: session} do
    session =
      session
      |> join_as_gm()
      |> fork_bookmark("UI Testing")
      |> fork_bookmark("Nested Fork")
      |> open_actions()
      |> click(Query.css("button[phx-click='set_log_tab'][phx-value-tab='bookmarks']"))
      |> find(Query.css("#bookmark-tree"), fn s -> s end)

    assert_has(session, Query.text("UI Testing"))
    assert_has(session, Query.text("Nested Fork"))
  end
end
