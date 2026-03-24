defmodule OdysseyElixir.Repo do
  use Ecto.Repo,
    otp_app: :odyssey_elixir,
    adapter: Ecto.Adapters.SQLite3
end
