defmodule OdysseyElixir.Persistence.Schemas.RetrySnapshot do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:issue_id, :string, autogenerate: false}

  schema "retry_snapshots" do
    field :attempt, :integer, default: 0
    field :error, :string
    field :worker_host, :string
    field :workspace_path, :string
  end

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:issue_id, :attempt, :error, :worker_host, :workspace_path])
    |> validate_required([:issue_id])
  end
end
