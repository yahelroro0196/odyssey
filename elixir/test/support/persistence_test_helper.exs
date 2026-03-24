defmodule OdysseyElixir.TestSupport.PersistenceHelper do
  @moduledoc false

  def setup_test_db do
    db_path = Path.join(System.tmp_dir!(), "odyssey_test_#{System.unique_integer([:positive])}.db")

    original_config = Application.get_env(:odyssey_elixir, OdysseyElixir.Repo)

    Application.put_env(:odyssey_elixir, OdysseyElixir.Repo,
      database: db_path,
      journal_mode: :wal,
      pool_size: 1
    )

    case OdysseyElixir.Repo.start_link([]) do
      {:ok, pid} ->
        OdysseyElixir.Persistence.Migrator.migrate()
        {pid, db_path, original_config}

      {:error, {:already_started, pid}} ->
        OdysseyElixir.Persistence.Migrator.migrate()
        {pid, db_path, original_config}
    end
  end

  def cleanup_test_db({pid, db_path, original_config}) do
    if Process.alive?(pid), do: GenServer.stop(pid)

    if original_config do
      Application.put_env(:odyssey_elixir, OdysseyElixir.Repo, original_config)
    else
      Application.delete_env(:odyssey_elixir, OdysseyElixir.Repo)
    end

    File.rm(db_path)
    File.rm(db_path <> "-wal")
    File.rm(db_path <> "-shm")
  end
end
