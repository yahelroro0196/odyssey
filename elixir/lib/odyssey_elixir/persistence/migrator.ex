defmodule OdysseyElixir.Persistence.Migrator do
  require Logger

  @migrations [
    {1, OdysseyElixir.Persistence.Migrations.V1}
  ]

  def migrate do
    Ecto.Migrator.run(OdysseyElixir.Repo, @migrations, :up, all: true, log: :info)
  end
end
