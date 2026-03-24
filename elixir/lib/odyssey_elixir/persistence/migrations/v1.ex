defmodule OdysseyElixir.Persistence.Migrations.V1 do
  use Ecto.Migration

  def change do
    create table(:sessions, primary_key: false) do
      add :id, :string, primary_key: true
      add :issue_id, :string, null: false
      add :status, :string, null: false, default: "running"
      add :input_tokens, :integer, default: 0
      add :output_tokens, :integer, default: 0
      add :total_tokens, :integer, default: 0
      add :turn_count, :integer, default: 0
      add :started_at, :utc_datetime_usec
      add :finished_at, :utc_datetime_usec
      add :error, :string
    end

    create index(:sessions, [:issue_id])

    create table(:issue_token_totals, primary_key: false) do
      add :issue_id, :string, primary_key: true
      add :input_tokens, :integer, default: 0
      add :output_tokens, :integer, default: 0
      add :total_tokens, :integer, default: 0
      add :session_count, :integer, default: 0
    end

    create table(:daily_token_totals, primary_key: false) do
      add :date, :date, primary_key: true
      add :input_tokens, :integer, default: 0
      add :output_tokens, :integer, default: 0
      add :total_tokens, :integer, default: 0
      add :session_count, :integer, default: 0
    end

    create table(:retry_snapshots, primary_key: false) do
      add :issue_id, :string, primary_key: true
      add :attempt, :integer, default: 0
      add :error, :string
      add :worker_host, :string
      add :workspace_path, :string
    end

    create table(:events) do
      add :issue_id, :string, null: false
      add :event_type, :string
      add :payload, :map
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create index(:events, [:issue_id])
  end
end
