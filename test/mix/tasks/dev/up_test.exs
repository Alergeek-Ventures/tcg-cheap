defmodule Mix.Tasks.Dev.UpTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.Dev.Up

  test "extracts container IDs while ignoring compose provider banners" do
    output = """
    >>> Executing external compose provider \"podman-compose\". <<<

    0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
    """

    assert Up.compose_container_ids(output) == [
             "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
           ]
  end

  test "extracts IDs prefixed by the provider's ANSI reset sequence" do
    output = """
    \e[4m>>>> Executing external compose provider \"podman-compose\". Please see podman-compose(1) for how to disable this message. <<<<\e[0m

    \e[0me3fae74342b8
    """

    assert Up.compose_container_ids(output) == ["e3fae74342b8"]
  end

  test "rejects non-hexadecimal or incorrectly sized lines" do
    output = "provider banner\n12345678901\nxyzxyzxyzxyz\n"

    assert Up.compose_container_ids(output) == []
  end
end
