defmodule TcgCheap.Catalogue.Provider do
  @moduledoc """
  Boundary for catalogue providers used by background imports.

  Operational callers pass a zero-arity `:request_admitter` in provider options.
  Adapters must invoke it immediately before every outbound request and return its
  error without performing that request. Fixture-only callers may omit it.
  """

  @callback fetch_card(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  @callback fetch_set(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  @callback list_sets(keyword()) :: {:ok, [map()]} | {:error, term()}
end
