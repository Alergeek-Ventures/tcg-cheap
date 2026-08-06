defmodule TcgCheap.CoreTest do
  use ExUnit.Case, async: true

  test "Core is configured as an Ash domain" do
    assert TcgCheap.Core in Application.get_env(:tcg_cheap, :ash_domains, [])
  end
end
