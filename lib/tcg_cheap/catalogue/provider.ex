defmodule TcgCheap.Catalogue.Provider do
  @moduledoc "Boundary for catalogue providers used by background imports."

  @callback fetch_card(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  @callback fetch_set(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
end
