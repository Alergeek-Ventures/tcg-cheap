defmodule TcgCheap.Catalogue.Validations.SealedProductIdentity do
  @moduledoc "Validates canonical slugs and the sealed product type allowlist."
  use Ash.Resource.Validation

  alias Ash.Changeset

  @types ~w(booster_pack sleeved_booster booster_bundle booster_box elite_trainer_box tin collection_box deck trainer_toolkit other)

  @impl true
  def validate(changeset, _opts, _context) do
    slug = Changeset.get_attribute(changeset, :slug)
    type = Changeset.get_attribute(changeset, :product_type)

    cond do
      not is_binary(slug) or not Regex.match?(~r/^[a-z0-9]+(?:-[a-z0-9]+)*$/, slug) ->
        {:error, field: :slug, message: "must be lowercase kebab-case"}

      type not in @types ->
        {:error, field: :product_type, message: "is not a supported sealed product type"}

      true ->
        :ok
    end
  end
end
