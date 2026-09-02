defmodule TcgCheap.Catalogue.SealedProductDraftFromListingTest do
  use TcgCheap.DataCase, async: false

  alias TcgCheap.Accounts
  alias TcgCheap.Catalogue.SealedProduct
  alias TcgCheap.Core
  alias TcgCheap.Repo

  test "admin derives a hidden draft and repeated requests do not overwrite it" do
    admin = admin()
    shop = retailer()
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)
    suffix = System.unique_integer([:positive])

    listing =
      Core.ingest_retailer_listing!(%{
        retailer_id: shop.id,
        source_listing_id: "listing-#{suffix}",
        source_title: "Żółty Elite Trainer Box",
        direct_url: "https://shop.example/products/etb",
        image_url: "https://lootquest.pl/images/etb-#{suffix}.jpg",
        current_price_pln: Decimal.new("199.99"),
        stock_status: "in_stock",
        first_seen_at: now,
        last_seen_at: now,
        last_checked_at: now
      })

    Core.create_pending_listing_mapping!(%{retailer_listing_id: listing.id})

    assert {:ok, first} =
             Core.create_sealed_product_draft_from_listing(listing.id, actor: admin)

    assert first.publication_status == "draft"
    assert first.product_type == "elite_trainer_box"
    assert first.name == "Żółty Elite Trainer Box"
    assert first.slug =~ ~r/-[a-f0-9]{16}$/
    assert first.image_source == shop.name
    assert first.image_source_url == listing.direct_url
    assert first.source == "retailer:#{shop.source_key}"
    assert first.source_id == listing.source_listing_id

    revised =
      Core.revise_sealed_product_draft!(
        first,
        %{name: "Human curation", expected_updated_at: first.updated_at},
        authorize?: false
      )

    assert {:ok, second} =
             Core.create_sealed_product_draft_from_listing(listing.id, actor: admin)

    assert second.id == first.id
    assert second.name == revised.name
    assert second.updated_at == revised.updated_at
  end

  test "draft contains only bounded listing evidence and checked timestamps" do
    admin = admin()
    shop = retailer()
    first = ~U[2026-01-01 10:00:00.000000Z]
    checked = ~U[2026-01-02 11:00:00.000000Z]

    listing =
      listing(shop, "evidence-#{System.unique_integer([:positive])}", %{
        source_title: "Evidence ETB",
        first_seen_at: first,
        last_seen_at: first,
        last_checked_at: checked,
        current_price_pln: Decimal.new("123.45"),
        stock_status: "unknown"
      })

    assert {:ok, product} =
             Core.create_sealed_product_draft_from_listing(listing.id, actor: admin)

    assert {product.series_name, product.set_name, product.release_date, product.msrp_pln,
            product.official_url} == {nil, nil, nil, nil, nil}

    assert {product.description, product.details_source, product.details_source_url} ==
             {nil, nil, nil}

    assert {product.official_price_amount, product.official_price_currency,
            product.official_price_source, product.official_price_source_url} ==
             {nil, nil, nil, nil}

    assert product.officially_distributed == false
    assert product.source_updated_at == checked
    assert DateTime.diff(product.last_synced_at, DateTime.utc_now(), :second) in -2..2

    assert product.source_payload == %{
             "retailer_id" => shop.id,
             "retailer_source_key" => shop.source_key,
             "retailer_name" => shop.name,
             "source_listing_id" => listing.source_listing_id,
             "direct_url" => listing.direct_url,
             "price_pln" => "123.45",
             "stock_status" => "unknown"
           }
  end

  test "infers every supported sealed product type family" do
    admin = admin()
    shop = retailer()

    for {title, expected} <- [
          {"Elite Trainer Box", "elite_trainer_box"},
          {"Booster Bundle", "booster_bundle"},
          {"Display Box", "booster_box"},
          {"Sleeved Booster", "sleeved_booster"},
          {"Ordinary Booster Pack", "booster_pack"},
          {"Puszka", "tin"},
          {"Talia", "deck"},
          {"Trainer Toolkit", "trainer_toolkit"},
          {"Collection Box", "collection_box"},
          {"Mystery Product", "other"}
        ] do
      row = listing(shop, "type-#{System.unique_integer([:positive])}", %{source_title: title})
      assert {:ok, product} = Core.create_sealed_product_draft_from_listing(row.id, actor: admin)
      assert product.product_type == expected
    end
  end

  test "unsafe images are rejected and image provenance is all-or-nothing" do
    admin = admin()
    shop = retailer()

    assert {:error, _} =
             Core.ingest_retailer_listing(%{
               retailer_id: shop.id,
               source_listing_id: "image-unsafe-#{System.unique_integer([:positive])}",
               source_title: "Unsafe image listing",
               direct_url: "https://shop.example/products/unsafe-image",
               image_url: "https://evil.example/image.jpg",
               first_seen_at: DateTime.utc_now(),
               last_seen_at: DateTime.utc_now(),
               last_checked_at: DateTime.utc_now()
             })

    assert Repo.query!("SHOW session_replication_role").rows == [["origin"]]

    image_less = listing(shop, "image-less-#{System.unique_integer([:positive])}")

    assert {:ok, product} =
             Core.create_sealed_product_draft_from_listing(image_less.id, actor: admin)

    assert {product.image_url, product.image_source, product.image_source_url} == {nil, nil, nil}

    suffix = System.unique_integer([:positive])

    valid =
      listing(shop, "image-valid-#{suffix}", %{
        image_url: "https://lootquest.pl/images/product-#{suffix}.jpg"
      })

    assert {:ok, product} = Core.create_sealed_product_draft_from_listing(valid.id, actor: admin)

    assert {product.image_url, product.image_source, product.image_source_url} ==
             {valid.image_url, shop.name, valid.direct_url}
  end

  test "invalid listing identities never create products" do
    admin = admin()
    shop = retailer()
    before = Repo.aggregate(SealedProduct, :count, :id)

    assert {:error, _} =
             Core.create_sealed_product_draft_from_listing(Ecto.UUID.generate(), actor: admin)

    disabled_listing = listing(shop, "disabled-listing-#{System.unique_integer([:positive])}")
    Core.disable_retailer_listing!(disabled_listing)

    assert {:error, _} =
             Core.create_sealed_product_draft_from_listing(disabled_listing.id, actor: admin)

    disabled_shop = retailer()

    disabled_shop_listing =
      listing(disabled_shop, "disabled-shop-#{System.unique_integer([:positive])}")

    Core.disable_retailer!(disabled_shop)

    assert {:error, _} =
             Core.create_sealed_product_draft_from_listing(disabled_shop_listing.id, actor: admin)

    assert {:error, _} =
             Core.ingest_retailer_listing(%{
               retailer_id: shop.id,
               source_listing_id: "malformed-direct-url-#{System.unique_integer([:positive])}",
               source_title: "Malformed direct URL",
               direct_url: "https://:bad",
               first_seen_at: DateTime.utc_now(),
               last_seen_at: DateTime.utc_now(),
               last_checked_at: DateTime.utc_now()
             })

    assert Repo.query!("SHOW session_replication_role").rows == [["origin"]]
    assert Repo.aggregate(SealedProduct, :count, :id) == before
  end

  test "long common titles retain distinct digest slugs within the bound" do
    admin = admin()
    shop = retailer()
    prefix = String.duplicate("Long Product ", 38)

    first =
      listing(shop, "long-a-#{System.unique_integer([:positive])}", %{
        source_title: prefix <> "AAAAAA"
      })

    second =
      listing(shop, "long-b-#{System.unique_integer([:positive])}", %{
        source_title: prefix <> "BBBBBB"
      })

    assert {:ok, one} = Core.create_sealed_product_draft_from_listing(first.id, actor: admin)
    assert {:ok, two} = Core.create_sealed_product_draft_from_listing(second.id, actor: admin)
    assert byte_size(one.slug) <= 120 and byte_size(two.slug) <= 120
    assert one.slug =~ ~r/-[a-f0-9]{16}$/ and two.slug =~ ~r/-[a-f0-9]{16}$/
    refute one.slug == two.slug
  end

  test "repeating after approval preserves curated product state" do
    admin = admin()
    shop = retailer()
    row = listing(shop, "approved-repeat-#{System.unique_integer([:positive])}")
    assert {:ok, draft} = Core.create_sealed_product_draft_from_listing(row.id, actor: admin)

    curated =
      Core.revise_sealed_product_draft!(
        draft,
        %{
          name: "Curated name",
          officially_distributed: true,
          release_date: Date.utc_today(),
          expected_updated_at: draft.updated_at
        },
        authorize?: false
      )

    Repo.query!("UPDATE sealed_products SET market = 'PL', language = 'en' WHERE id = $1", [
      Ecto.UUID.dump!(curated.id)
    ])

    curated = Ash.get!(SealedProduct, curated.id, authorize?: false)

    approved =
      Core.approve_sealed_product!(curated, %{expected_updated_at: curated.updated_at},
        authorize?: false
      )

    assert {:ok, repeated} = Core.create_sealed_product_draft_from_listing(row.id, actor: admin)

    assert {repeated.id, repeated.publication_status, repeated.name, repeated.updated_at} ==
             {approved.id, "approved", "Curated name", approved.updated_at}
  end

  test "action requires an administrator" do
    assert {:error, error} = Core.create_sealed_product_draft_from_listing(Ecto.UUID.generate())
    assert Exception.message(error) =~ "Forbidden Error"
  end

  test "active listing without a mapping cannot create a draft" do
    admin = admin()
    shop = retailer()
    row = listing(shop, "unmapped-#{System.unique_integer([:positive])}", %{mapping?: false})

    assert {:error, error} = Core.create_sealed_product_draft_from_listing(row.id, actor: admin)
    assert Exception.message(error) =~ "pending or review mapping"
  end

  test "active listing with a rejected mapping cannot create a draft" do
    admin = admin()
    shop = retailer()
    row = listing(shop, "rejected-#{System.unique_integer([:positive])}")
    mapping = Core.get_listing_mapping!(row.id)

    Core.reject_listing_mapping!(
      mapping,
      %{reason: "Rejected", expected_updated_at: mapping.updated_at},
      authorize?: false
    )

    assert {:error, error} = Core.create_sealed_product_draft_from_listing(row.id, actor: admin)
    assert Exception.message(error) =~ "no longer reviewable"
  end

  test "retailer listing lookup by id requires an administrator" do
    listing = listing(retailer())
    assert {:error, error} = Core.get_retailer_listing_by_id(listing.id)
    assert Exception.message(error) =~ "Forbidden Error"
  end

  test "draft is not returned by public lookup" do
    admin = admin()
    listing = listing(retailer())

    assert {:ok, product} =
             Core.create_sealed_product_draft_from_listing(listing.id, actor: admin)

    assert Core.get_public_sealed_product_by_id(product.id) == {:ok, nil}
  end

  defp admin do
    Accounts.register_admin!(
      %{
        email: "draft-#{System.unique_integer([:positive])}@example.test",
        password: "correct horse battery staple",
        password_confirmation: "correct horse battery staple"
      },
      authorize?: false
    )
  end

  defp retailer do
    unique = System.unique_integer([:positive])

    Core.register_retailer!(%{
      slug: "draft-shop-#{unique}",
      source_key: "draft-shop-#{unique}",
      name: "Draft Shop",
      category: "lgs",
      homepage_url: "https://shop.example"
    })
  end

  defp listing(
         shop,
         source_listing_id \\ "listing-#{System.unique_integer([:positive])}",
         overrides \\ %{}
       ) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    mapping? = Map.get(overrides, :mapping?, true)
    overrides = Map.delete(overrides, :mapping?)

    listing =
      Core.ingest_retailer_listing!(
        Map.merge(
          %{
            retailer_id: shop.id,
            source_listing_id: source_listing_id,
            source_title: "Booster pack",
            direct_url: "https://shop.example/products/pack",
            first_seen_at: now,
            last_seen_at: now,
            last_checked_at: now
          },
          overrides
        )
      )

    if mapping? do
      Core.create_pending_listing_mapping!(%{retailer_listing_id: listing.id})
    end

    listing
  end
end
