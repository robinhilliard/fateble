defmodule FateWeb.PageController do
  use FateWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
