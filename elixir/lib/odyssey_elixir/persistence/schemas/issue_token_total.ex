defmodule OdysseyElixir.Persistence.Schemas.IssueTokenTotal do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:issue_id, :string, autogenerate: false}

  schema "issue_token_totals" do
    field :input_tokens, :integer, default: 0
    field :output_tokens, :integer, default: 0
    field :total_tokens, :integer, default: 0
    field :session_count, :integer, default: 0
  end

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:issue_id, :input_tokens, :output_tokens, :total_tokens, :session_count])
    |> validate_required([:issue_id])
  end
end
