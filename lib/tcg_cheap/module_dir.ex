defmodule TcgCheap.ModuleDir do
  @moduledoc """
  Modules kept one per file in a directory, `<namespace>.<CamelizedFileName>`,
  as the countries (`TcgCheap.Countries`), their shops
  (`TcgCheap.Sealed.Shops`) and the languages (`TcgCheapWeb.Languages`) are:
  adding one is adding a file, and no shared list names them.

  A module that reads them at compile time names their files as
  `@external_resource`s, so an edited file recompiles it, and compares
  `files/1` in `__mix_recompile__?/0`, so an added or removed file does too.
  """

  @doc "The Elixir files of a directory, sorted by name."
  @spec files(Path.t()) :: [String.t()]
  def files(dir),
    do: dir |> File.ls!() |> Enum.filter(&(Path.extname(&1) == ".ex")) |> Enum.sort()

  @doc ~S(The module a file defines: "united_kingdom.ex" under `Shops` is `Shops.UnitedKingdom`.)
  @spec module(module(), String.t()) :: module()
  def module(namespace, file), do: Module.concat(namespace, Macro.camelize(Path.rootname(file)))
end
