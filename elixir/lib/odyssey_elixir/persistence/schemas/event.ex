defmodule OdysseyElixir.Persistence.Schemas.Event do
  use Ecto.Schema
  import Ecto.Changeset

  schema "events" do
    field :issue_id, :string
    field :event_type, :string
    field :payload, :map
    field :inserted_at, :utc_datetime_usec
  end

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:issue_id, :event_type, :payload, :inserted_at])
    |> validate_required([:issue_id, :inserted_at])
  end
end
