defmodule OdysseyElixir.Persistence.Schemas.Session do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :string, autogenerate: false}

  schema "sessions" do
    field :issue_id, :string
    field :status, :string, default: "running"
    field :input_tokens, :integer, default: 0
    field :output_tokens, :integer, default: 0
    field :total_tokens, :integer, default: 0
    field :turn_count, :integer, default: 0
    field :started_at, :utc_datetime_usec
    field :finished_at, :utc_datetime_usec
    field :error, :string
  end

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:id, :issue_id, :status, :input_tokens, :output_tokens, :total_tokens, :turn_count, :started_at, :finished_at, :error])
    |> validate_required([:id, :issue_id])
  end
end
