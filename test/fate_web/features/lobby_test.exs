defmodule FateWeb.Features.LobbyTest do
  use FateWeb.FeatureCase

  feature "joining as GM redirects to table", %{session: session} do
    session
    |> visit("/")
    |> assert_has(Query.text("Join the Table"))
    |> fill_in(Query.css("input[name='name']"), with: "Test GM")
    |> click(Query.text("GM", count: :any, at: 0))
    |> click(Query.button("Join Game"))
    |> assert_has(Query.css("#table-view"))
  end

  feature "joining as player redirects to table", %{session: session} do
    session
    |> visit("/")
    |> assert_has(Query.text("Join the Table"))
    |> fill_in(Query.css("input[name='name']"), with: "Test Player")
    |> click(Query.text("Player", count: :any, at: 0))
    |> click(Query.button("Join Game"))
    |> assert_has(Query.css("#table-view"))
  end

  feature "table renders with scene content after joining", %{session: session} do
    session
    |> join_as_gm("Scene Check GM")
    |> assert_has(Query.css("#table-view"))
    |> assert_has(Query.css(".spring-element", minimum: 1))
  end
end
