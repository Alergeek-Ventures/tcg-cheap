defmodule TcgCheap.Sealed.AgentTools.SetExpansionLogo do
  @moduledoc """
  Sets or clears the logo of a Cardmarket expansion that has products in the
  catalogue. Clearing takes no page or day, so a logo given without its
  url is rejected rather than dropped (AshAi already rejects unknown keys).
  The image host is checked by `TcgCheap.Sealed.ExpansionLogo`.
  """

  use Ash.Resource.Actions.Implementation

  alias Ash.Error.Action.InvalidArgument
  alias TcgCheap.Sealed

  @impl true
  def run(input, _opts, _context) do
    id = input.arguments.expansion_id
    logo = Map.take(input.arguments, [:url, :page, :checked_on])

    with {:ok, name} <- expansion_name(id),
         {:ok, logo} <- save(id, logo) do
      {:ok, %{expansion_id: id, expansion: name, logo: logo}}
    end
  end

  defp save(id, %{url: url} = logo) when is_binary(url) do
    with {:ok, logo} <-
           logo |> Map.put(:cardmarket_expansion_id, id) |> Sealed.set_expansion_logo() do
      {:ok, Map.take(logo, [:url, :page, :checked_on])}
    end
  end

  defp save(id, logo) do
    if Enum.all?(Map.values(logo), &is_nil/1),
      do: clear(id),
      else: invalid(:url, "is required with page and checked_on; to clear the logo give neither")
  end

  defp clear(id) do
    with {:ok, logo} <- Sealed.get_expansion_logo(id),
         :ok <- if(logo, do: Sealed.destroy_expansion_logo(logo), else: :ok) do
      {:ok, nil}
    end
  end

  defp expansion_name(id) do
    case Sealed.list_product_facets!("", nil, nil, id) do
      [] ->
        invalid(:expansion_id, "no catalogue product is in this Cardmarket expansion")

      products ->
        {:ok,
         products
         |> Enum.map(& &1.set_name)
         |> Enum.reject(&is_nil/1)
         |> Enum.frequencies()
         |> Enum.max_by(&elem(&1, 1), fn -> {nil, 0} end)
         |> elem(0)}
    end
  end

  defp invalid(field, message),
    do: {:error, InvalidArgument.exception(field: field, message: message)}
end
