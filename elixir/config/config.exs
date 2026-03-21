import Config

config :phoenix, :json_library, Jason

config :odyssey_elixir, OdysseyElixirWeb.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  url: [host: "localhost"],
  render_errors: [
    formats: [html: OdysseyElixirWeb.ErrorHTML, json: OdysseyElixirWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: OdysseyElixir.PubSub,
  live_view: [signing_salt: "odyssey-live-view"],
  secret_key_base: String.duplicate("s", 64),
  check_origin: false,
  server: false
