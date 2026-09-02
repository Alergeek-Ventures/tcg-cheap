defmodule TcgCheap.Catalogue.SealedProductConstraintTest do
  use TcgCheap.DataCase, async: true

  alias TcgCheap.Core
  alias TcgCheap.Repo

  test "rejects an official price without a source" do
    product = create_product()

    assert {:error, %Postgrex.Error{postgres: %{code: :check_violation}}} =
             Repo.query(
               "UPDATE sealed_products SET official_price_amount = 10, official_price_currency = 'USD', official_price_source_url = 'https://example.com/price' WHERE id = $1",
               [Ecto.UUID.dump!(product.id)]
             )
  end

  test "rejects an image without a source" do
    product = create_product()

    assert {:error, %Postgrex.Error{postgres: %{code: :check_violation}}} =
             Repo.query(
               "UPDATE sealed_products SET image_url = 'https://example.com/image.jpg', image_source_url = 'https://example.com/source' WHERE id = $1",
               [Ecto.UUID.dump!(product.id)]
             )
  end

  test "rejects populated details without a source" do
    product = create_product()

    assert {:error, %Postgrex.Error{postgres: %{code: :check_violation}}} =
             Repo.query(
               "UPDATE sealed_products SET description = 'Details' WHERE id = $1",
               [Ecto.UUID.dump!(product.id)]
             )
  end

  test "rejects whitespace and control characters in provenance source URLs" do
    for {sql, value} <- [
          {"UPDATE sealed_products SET official_price_amount = 10, official_price_currency = 'USD', official_price_source = 'Price source', official_price_source_url = $1 WHERE id = $2",
           "https://example.com/price with-space"},
          {"UPDATE sealed_products SET image_url = 'https://assets.pokemon.com/image.jpg', image_source = 'Image source', image_source_url = $1 WHERE id = $2",
           "https://example.com/source\u0001"},
          {"UPDATE sealed_products SET description = 'Details', details_source = 'Details source', details_source_url = $1 WHERE id = $2",
           "https://example.com/source\n"}
        ] do
      product = create_product()

      assert {:error, %Postgrex.Error{postgres: %{code: :check_violation}}} =
               Repo.query(
                 sql,
                 [value, Ecto.UUID.dump!(product.id)]
               )
    end
  end

  test "rejects an alphabetic MSRP source port independently" do
    product = create_product()

    assert {:error, %Postgrex.Error{postgres: %{code: :check_violation}}} =
             Repo.query(
               "UPDATE sealed_products SET msrp_pln = 10, msrp_source = 'Price source', msrp_source_url = 'https://example.com:bad/path' WHERE id = $1",
               [Ecto.UUID.dump!(product.id)]
             )
  end

  test "rejects an alphabetic official URL port independently" do
    product = create_product()

    assert {:error, %Postgrex.Error{postgres: %{code: :check_violation}}} =
             Repo.query(
               "UPDATE sealed_products SET description = 'Details', details_source = 'Details source', details_source_url = 'https://example.com/details', official_url = 'https://example.com:bad/path' WHERE id = $1",
               [Ecto.UUID.dump!(product.id)]
             )
  end

  defp create_product do
    assert {:ok, product} =
             Core.create_sealed_product_draft(%{
               slug: "constraint-#{System.unique_integer([:positive])}",
               name: "Constraint test product",
               product_type: "booster_box"
             })

    product
  end
end
