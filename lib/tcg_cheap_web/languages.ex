defmodule TcgCheapWeb.Languages do
  @moduledoc """
  The languages the guide renders in (`TcgCheapWeb.Language`), one file each
  in `lib/tcg_cheap_web/languages/` (`TcgCheap.ModuleDir`): Polish first, the
  guide's default, then the others by code.
  """

  alias TcgCheap.ModuleDir

  @dir Path.expand("languages", __DIR__)
  @files ModuleDir.files(@dir)
  for file <- @files, do: @external_resource(Path.join(@dir, file))

  @by_code @files
           |> Enum.map(&ModuleDir.module(__MODULE__, &1))
           |> Map.new(&{&1.code(), &1})

  @default Application.compile_env!(:tcg_cheap, [TcgCheapWeb.Gettext, :default_locale])
  @codes @by_code |> Map.keys() |> Enum.sort_by(&{&1 != @default, &1})

  @doc false
  def __mix_recompile__?, do: ModuleDir.files(@dir) != @files

  @doc "Every language's code, the default first."
  @spec codes() :: [String.t()]
  def codes, do: @codes

  @doc "A language's module; the default's for any other code."
  @spec get(String.t() | nil) :: module()
  def get(code), do: Map.get(@by_code, code) || Map.fetch!(@by_code, @default)
end
