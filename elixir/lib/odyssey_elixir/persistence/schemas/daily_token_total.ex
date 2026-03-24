defmodule OdysseyElixir.Persistence.Schemas.DailyTokenTotal do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:date, :date, autogenerate: false}

  schema "daily_token_totals" do
    field :input_tokens, :integer, default: 0
    field :output_tokens, :integer, default: 0
    field :total_tokens, :integer, default: 0
    field :session_count, :integer, default: 0
  end

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:date, :input_tokens, :output_tokens, :total_tokens, :session_count])
    |> validate_required([:date])
  end
end
