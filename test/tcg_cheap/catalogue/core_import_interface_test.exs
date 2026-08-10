defmodule TcgCheap.Catalogue.CoreImportInterfaceTest do
  use ExUnit.Case, async: true

  alias TcgCheap.Core

  test "does not expose the importer-only card printing action" do
    refute Enum.any?(Core.__info__(:functions), fn {name, _arity} ->
             name in [:import_card_printing, :import_card_printing!]
           end)
  end
end
