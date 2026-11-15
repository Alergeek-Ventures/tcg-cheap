defmodule TcgCheap.Countries do
  @moduledoc """
  The countries the guide names (`TcgCheap.Country`), one file each in
  `lib/tcg_cheap/countries/` (`TcgCheap.ModuleDir`), and the regions some of
  them define: Poland's first, the original region every old URL and
  unknown visitor goes to, then the others by code.
  """

  alias TcgCheap.ModuleDir

  @dir Path.expand("countries", __DIR__)
  @files ModuleDir.files(@dir)
  for file <- @files, do: @external_resource(Path.join(@dir, file))
  @modules Enum.map(@files, &ModuleDir.module(__MODULE__, &1))

  @by_code Map.new(@modules, &{&1.code(), &1})

  @regions (for module <- @modules, region <- [module.region()], region != nil do
              Map.merge(region, %{country: module.code(), module: module})
            end)
           |> Enum.sort_by(&{&1.code != "pl", &1.code})

  # A region's language menu lists its own language, English and its
  # popular ones first, at most four (TcgCheapWeb.Region).
  for region <- @regions do
    case region do
      %{popular_languages: popular} when length(popular) <= 2 ->
        :ok

      %{code: code} ->
        raise ArgumentError, "region #{code} needs popular_languages, at most two"
    end
  end

  @doc false
  def __mix_recompile__?, do: ModuleDir.files(@dir) != @files

  @doc "A country's module by its ISO code."
  @spec fetch(String.t()) :: {:ok, module()} | :error
  def fetch(code), do: Map.fetch(@by_code, code)

  @spec fetch!(String.t()) :: module()
  def fetch!(code), do: Map.fetch!(@by_code, code)

  @doc """
  Every region (`c:TcgCheap.Country.region/0`), Poland's first, each with
  its country's ISO code (`country`) and module (`module`).
  """
  @spec regions() :: [map()]
  def regions, do: @regions
end
