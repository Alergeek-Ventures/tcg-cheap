defmodule TcgCheap.Catalogue.SearchText do
  @moduledoc "Canonical normalization shared by persisted search text and queries."

  @whitespace ~r/\s+/u
  @apostrophes ~r/[‘’ʼ＇]/u

  def normalize(value) when is_binary(value) do
    value
    |> String.normalize(:nfkc)
    |> String.trim()
    |> String.replace(@whitespace, " ")
    |> String.downcase(:greek)
  end

  def normalize(_value), do: ""

  def normalize_cardmarket_name(value) do
    value
    |> normalize()
    |> String.replace(@apostrophes, "'")
  end
end
