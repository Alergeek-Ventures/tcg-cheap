defmodule TcgCheap.Storage.Calculations.VariantPlaceholder do
  @moduledoc """
  Reads the inline placeholder stored by `TcgCheap.Storage.Variants.Webp` on an
  attachment's variant blob. Returns `nil` until the variant exists.
  """

  use Ash.Resource.Calculation

  @impl true
  def strict_loads?, do: false

  @impl true
  def load(_query, opts, _context), do: [{opts[:attachment], blob: :variants}]

  @impl true
  def calculate(records, opts, _context) do
    variant_name = to_string(opts[:variant])

    Enum.map(records, fn record ->
      with %{blob: %{variants: variants}} <- Map.get(record, opts[:attachment]),
           %{metadata: %{"placeholder" => placeholder}} <-
             Enum.find(variants, &(&1.variant_name == variant_name)) do
        placeholder
      else
        _missing -> nil
      end
    end)
  end
end
