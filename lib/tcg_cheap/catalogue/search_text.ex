defmodule TcgCheap.Catalogue.SearchText do
  @moduledoc "Canonical normalization shared by persisted search text and queries."

  def normalize(value) when is_binary(value) do
    value
    |> String.normalize(:nfkc)
    |> String.trim()
    |> String.replace(~r/\s+/u, " ")
    |> String.downcase(:greek)
  end

  def normalize(_value), do: ""
end
