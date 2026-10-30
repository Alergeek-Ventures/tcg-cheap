defmodule TcgCheap.Sealed.Product do
  @moduledoc "One catalogue product and the rules for recognising its offers."
  @enforce_keys [:slug, :name, :kind, :terms]
  defstruct [
    :slug,
    :name,
    :kind,
    :set_name,
    :release_date,
    :image_url,
    eans: [],
    terms: [],
    exclude: []
  ]

  @type t :: %__MODULE__{
          slug: String.t(),
          name: String.t(),
          kind: atom(),
          set_name: String.t() | nil,
          release_date: Date.t() | nil,
          image_url: String.t() | nil,
          eans: [String.t()],
          terms: [[String.t()]],
          exclude: [String.t()]
        }
end
