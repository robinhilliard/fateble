defmodule FateWeb.Router do
  use FateWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {FateWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", FateWeb do
    pipe_through :browser

    get "/", PageController, :home
    live "/branches", BranchesLive
    live "/table/:branch_id", TableLive
    live "/actions/:branch_id", ActionsLive
  end

  scope "/api" do
    pipe_through :api

    forward "/mcp", ExMCP.HttpPlug,
      handler: Fate.McpServer,
      server_info: %{name: "fate-rpg", version: "0.1.0"},
      sse_enabled: true,
      cors_enabled: true
  end
end
