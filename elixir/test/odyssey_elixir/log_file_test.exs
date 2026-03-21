defmodule OdysseyElixir.LogFileTest do
  use ExUnit.Case, async: true

  alias OdysseyElixir.LogFile

  test "default_log_file/0 uses the current working directory" do
    assert LogFile.default_log_file() == Path.join(File.cwd!(), "log/odyssey.log")
  end

  test "default_log_file/1 builds the log path under a custom root" do
    assert LogFile.default_log_file("/tmp/odyssey-logs") == "/tmp/odyssey-logs/log/odyssey.log"
  end
end
