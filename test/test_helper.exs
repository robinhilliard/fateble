if !System.get_env("GITHUB_ACTIONS") || System.get_env("BROWSER_TESTS") do
  {:ok, _} = Application.ensure_all_started(:wallaby)
  Application.put_env(:wallaby, :base_url, FateWeb.Endpoint.url())
end

ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Fate.Repo, :manual)
