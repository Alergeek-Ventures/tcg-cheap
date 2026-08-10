defmodule TcgCheap.ReleaseTest do
  use TcgCheap.DataCase, async: false

  import ExUnit.CaptureIO

  test "provision_admin reports missing environment names without values" do
    preserve_admin_environment()

    System.delete_env("ADMIN_EMAIL")
    System.put_env("ADMIN_PASSWORD", "never-print-this")

    error = assert_raise ArgumentError, fn -> TcgCheap.Release.provision_admin() end

    assert Exception.message(error) == "ADMIN_EMAIL is required"
    refute Exception.message(error) =~ "never-print-this"
  end

  test "provision_admin does not expose a rejected password" do
    preserve_admin_environment()

    System.put_env("ADMIN_EMAIL", "release-#{System.unique_integer([:positive])}@example.test")
    System.put_env("ADMIN_PASSWORD", "secret-marker")

    output =
      capture_io(fn ->
        error = assert_raise RuntimeError, fn -> TcgCheap.Release.provision_admin() end
        assert Exception.message(error) == "Administrator provisioning failed"
      end)

    refute output =~ "secret-marker"
  end

  defp preserve_admin_environment do
    original_email = System.get_env("ADMIN_EMAIL")
    original_password = System.get_env("ADMIN_PASSWORD")

    on_exit(fn -> restore_env("ADMIN_EMAIL", original_email) end)
    on_exit(fn -> restore_env("ADMIN_PASSWORD", original_password) end)
  end

  defp restore_env(name, nil), do: System.delete_env(name)
  defp restore_env(name, value), do: System.put_env(name, value)
end
