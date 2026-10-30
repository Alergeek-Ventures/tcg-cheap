defmodule TcgCheap.Sealed.Shop do
  @moduledoc "A configured shop and the facts needed to read its product feed."
  @enforce_keys [:key, :name, :host, :category, :sealed_categories, :product_path, :max_pages]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          key: String.t(),
          name: String.t(),
          host: String.t(),
          category: String.t(),
          sealed_categories: [String.t()],
          product_path: Regex.t(),
          max_pages: pos_integer()
        }
end
