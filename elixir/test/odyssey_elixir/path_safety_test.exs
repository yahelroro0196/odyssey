defmodule OdysseyElixir.PathSafetyTest do
  use ExUnit.Case, async: true

  alias OdysseyElixir.PathSafety

  describe "canonicalize/1" do
    test "resolves a simple absolute path" do
      {:ok, result} = PathSafety.canonicalize("/tmp")
      assert is_binary(result)
      assert String.starts_with?(result, "/")
    end

    test "resolves .. segments" do
      {:ok, result} = PathSafety.canonicalize("/tmp/foo/../bar")
      refute String.contains?(result, "..")
      assert String.ends_with?(result, "/bar")
    end

    test "resolves symlinks" do
      tmp = Path.join(System.tmp_dir!(), "path_safety_test_#{System.unique_integer([:positive])}")
      File.mkdir_p!(tmp)
      real = Path.join(tmp, "real")
      File.mkdir_p!(real)
      link = Path.join(tmp, "link")
      File.ln_s!(real, link)

      {:ok, canonical} = PathSafety.canonicalize(link)
      {:ok, canonical_real} = PathSafety.canonicalize(real)
      assert canonical == canonical_real

      File.rm_rf!(tmp)
    end

    test "handles non-existent trailing segments" do
      {:ok, result} = PathSafety.canonicalize("/tmp/does_not_exist_abc123")
      assert result == "/tmp/does_not_exist_abc123" || String.ends_with?(result, "does_not_exist_abc123")
    end

    test "returns absolute path for relative input" do
      {:ok, result} = PathSafety.canonicalize("relative/path")
      assert String.starts_with?(result, "/")
    end
  end
end
