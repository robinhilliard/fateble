import Config

# Wallaby requires a running server
config :fate, FateWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "BnMleAS9Hj7qonVH7GElTd0nsHN0t+DGcx3a+8nICIjx4AXJbwgZlk+9ogbd/m51",
  server: true

config :fate, :sandbox, Ecto.Adapters.SQL.Sandbox

config :fate, Fate.Repo,
  database: "fate_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

chromedriver_path = Path.expand("../priv/chromedriver", __DIR__)

chromedriver_opts =
  if System.get_env("CI") do
    [headless: true, path: chromedriver_path]
  else
    [
      headless: System.get_env("SHOW_BROWSER") != "1",
      path: chromedriver_path
    ]
  end

config :wallaby,
  otp_app: :fate,
  driver: Wallaby.Chrome,
  chromedriver: chromedriver_opts,
  screenshot_on_failure: true,
  screenshot_dir: "test/screenshots",
  max_wait_time: 15_000

config :logger, level: :warning

config :phoenix, :plug_init_mode, :runtime

config :phoenix_live_view,
  enable_expensive_runtime_checks: true

config :phoenix,
  sort_verified_routes_query_params: true
