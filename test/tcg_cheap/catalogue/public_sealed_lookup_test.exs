defmodule TcgCheap.Catalogue.PublicSealedLookupTest do
  use TcgCheap.DataCase, async: true

  alias TcgCheap.Catalogue.PublicSealedProductProjection
  alias TcgCheap.Core
  alias TcgCheap.Repo

  defp product(name) do
    draft =
      Core.create_sealed_product_draft!(%{
        slug: "lookup-#{System.unique_integer([:positive])}",
        name: name,
        product_type: "booster_box",
        description: "A complete sealed product for lookup tests.",
        contents: ["36 booster packs"],
        pack_count: 36,
        cards_per_pack: 10,
        official_url: "https://example.com/products/lookup",
        details_source: "Official product page",
        details_source_url: "https://example.com/products/lookup/details",
        image_url: "https://assets.tcgdex.net/en/sealed/lookup.jpg",
        image_source: "Official product page",
        image_source_url: "https://example.com/products/lookup/image",
        officially_distributed: true,
        release_date: Date.utc_today()
      })

    Core.approve_sealed_product!(draft, %{expected_updated_at: draft.updated_at},
      authorize?: false
    )
  end

  test "public search normalizes, bounds, and includes approved names only" do
    product = product("Public Search Canonical")

    alias_row =
      Core.create_sealed_product_alias!(%{
        sealed_product_id: product.id,
        kind: "name",
        original_value: "Friendly Search Name"
      })

    approved_alias =
      Core.approve_sealed_product_alias!(alias_row, %{expected_updated_at: alias_row.updated_at},
        authorize?: false
      )

    assert {:error, _} = Core.search_public_sealed_products("x")

    assert {:ok, results} = Core.search_public_sealed_products("  FRIENDLY   SEARCH ")
    assert Enum.map(results, & &1.id) == [product.id]

    pending = product("Pending Alias Hidden")

    Core.create_sealed_product_alias!(%{
      sealed_product_id: pending.id,
      kind: "name",
      original_value: "Invisible Lookup"
    })

    assert {:ok, []} = Core.search_public_sealed_products("invisible lookup")

    assert approved_alias.review_status == "approved"
  end

  test "projection chooses current and sold-out evidence deterministically per retailer" do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)
    retailer = fn id, name -> %{id: id, name: name, slug: name} end

    listing = fn id, shop, status, price, checked ->
      %{
        id: id,
        retailer: shop,
        source_listing_id: id,
        stock_status: status,
        current_price_pln: price,
        last_checked_at: checked
      }
    end

    first = retailer.("r1", "Alpha")
    second = retailer.("r2", "Beta")

    mappings = [
      %{id: "m1", retailer_listing: listing.("a", first, "in_stock", Decimal.new("12"), now)},
      %{id: "m2", retailer_listing: listing.("b", first, "in_stock", Decimal.new("9"), now)},
      %{
        id: "m6",
        retailer_listing:
          listing.("f", first, "sold_out", Decimal.new("2"), DateTime.add(now, -10, :second))
      },
      %{
        id: "m3",
        retailer_listing:
          listing.("c", second, "sold_out", Decimal.new("2"), DateTime.add(now, -10, :second))
      },
      %{id: "m4", retailer_listing: listing.("d", second, "sold_out", Decimal.new("2"), now)},
      %{id: "m5", retailer_listing: listing.("e", second, "unknown", nil, now)}
    ]

    result = PublicSealedProductProjection.project(mappings)
    assert Enum.map(result.current, & &1.mapping.id) == ["m2"]
    assert Enum.map(result.sold_out, & &1.mapping.id) == ["m4", "m6"]
  end

  test "projection breaks current and sold-out ties by listing id" do
    checked = DateTime.utc_now() |> DateTime.truncate(:microsecond)
    retailer = %{id: "r1", name: "Alpha", slug: "alpha"}

    listing = fn id, status ->
      %{
        id: id,
        retailer: retailer,
        source_listing_id: id,
        stock_status: status,
        current_price_pln: Decimal.new("9"),
        last_checked_at: checked
      }
    end

    mappings = [
      %{id: "sold-lower", retailer_listing: listing.("a", "sold_out")},
      %{id: "sold-higher", retailer_listing: listing.("z", "sold_out")},
      %{id: "current-higher", retailer_listing: listing.("z-current", "in_stock")},
      %{id: "current-lower", retailer_listing: listing.("a-current", "in_stock")}
    ]

    result = PublicSealedProductProjection.project(mappings)
    assert Enum.map(result.current, & &1.mapping.id) == ["current-lower"]
    assert Enum.map(result.sold_out, & &1.mapping.id) == ["sold-higher"]
  end

  test "projection sorts sold-out offers chronologically across month and year boundaries" do
    as_of = ~U[2026-01-02 12:00:00.000000Z]
    retailer = fn id, name -> %{id: id, name: name, slug: String.downcase(name)} end
    alpha = retailer.("r1", "Alpha")
    beta = retailer.("r2", "Beta")

    listing = fn id, shop, checked_at ->
      %{
        id: id,
        retailer: shop,
        source_listing_id: id,
        stock_status: "sold_out",
        current_price_pln: Decimal.new("9"),
        last_checked_at: checked_at
      }
    end

    mappings = [
      %{
        id: "december",
        retailer_listing: listing.("december", alpha, ~U[2025-12-31 23:59:00.000000Z])
      },
      %{
        id: "january",
        retailer_listing: listing.("january", beta, ~U[2026-01-01 00:01:00.000000Z])
      }
    ]

    result = PublicSealedProductProjection.project(mappings, as_of)
    assert Enum.map(result.sold_out, & &1.mapping.id) == ["january", "december"]
  end

  test "projection includes sold-out checks through 30 days and excludes older or future checks" do
    as_of = ~U[2026-08-09 12:00:00.000000Z]

    offer = fn id, checked_at ->
      %{
        id: "mapping-#{id}",
        retailer_listing: %{
          id: "listing-#{id}",
          retailer: %{id: "retailer-#{id}", name: id, slug: id},
          source_listing_id: id,
          stock_status: "sold_out",
          current_price_pln: nil,
          last_checked_at: checked_at
        }
      }
    end

    boundary = offer.("boundary", DateTime.add(as_of, -30, :day))
    too_old = offer.("too-old", DateTime.add(as_of, -30, :day) |> DateTime.add(-1, :second))
    future = offer.("future", DateTime.add(as_of, 1, :second))

    result = PublicSealedProductProjection.project([boundary, too_old, future], as_of)

    assert Enum.map(result.sold_out, & &1.mapping.id) == ["mapping-boundary"]
  end

  test "public search applies explicit limit and deterministic name order" do
    token = "sealed-limit-#{System.unique_integer([:positive])}"
    product("#{token} Bravo")
    product("#{token} Alpha")
    product("#{token} Charlie")

    assert {:ok, results} = Core.search_public_sealed_products(token, 2)
    assert Enum.map(results, & &1.name) == ["#{token} Alpha", "#{token} Bravo"]
  end

  test "public search ranks an exact approved alias above a canonical substring" do
    query = "Alias Ranking #{System.unique_integer([:positive])}"
    canonical_substring = product("Prefix #{query} Suffix")
    alias_match = product("Different Canonical Product")

    alias_row =
      Core.create_sealed_product_alias!(%{
        sealed_product_id: alias_match.id,
        kind: "name",
        original_value: query
      })

    Core.approve_sealed_product_alias!(alias_row, %{expected_updated_at: alias_row.updated_at},
      authorize?: false
    )

    assert {:ok, [first, second]} = Core.search_public_sealed_products(query)
    assert [first.id, second.id] == [alias_match.id, canonical_substring.id]
  end

  test "public search ranks an approved alias prefix above a canonical substring" do
    query = "Prefix Alias Ranking #{System.unique_integer([:positive])}"
    canonical_substring = product("Before #{query} After")
    alias_match = product("Unrelated Prefix Canonical")

    alias_row =
      Core.create_sealed_product_alias!(%{
        sealed_product_id: alias_match.id,
        kind: "name",
        original_value: "#{query} Extended"
      })

    Core.approve_sealed_product_alias!(alias_row, %{expected_updated_at: alias_row.updated_at},
      authorize?: false
    )

    assert {:ok, [first, second]} = Core.search_public_sealed_products(query)
    assert [first.id, second.id] == [alias_match.id, canonical_substring.id]
  end

  test "public search treats percent, underscore, and backslash as literals" do
    token = "sealed-wildcards-#{System.unique_integer([:positive])}"
    percent = product("#{token} literal-%x")
    underscore = product("#{token} literal-_u")
    backslash = product("#{token} literal-\\s")

    product("#{token} literal-AX")
    product("#{token} literal-Au")
    product("#{token} literal-s")

    assert {:ok, [result]} = Core.search_public_sealed_products("literal-%x")
    assert result.id == percent.id

    assert {:ok, [result]} = Core.search_public_sealed_products("literal-_u")
    assert result.id == underscore.id

    assert {:ok, [result]} = Core.search_public_sealed_products("literal-\\s")
    assert result.id == backslash.id
  end

  test "public search keeps publication, distribution, and alias review boundaries" do
    token = "sealed-eligibility-#{System.unique_integer([:positive])}"
    discontinued = product("#{token} Discontinued")
    Core.mark_sealed_product_discontinued!(discontinued, authorize?: false)

    archived = product("#{token} Archived")

    Core.archive_sealed_product!(
      archived,
      %{expected_updated_at: archived.updated_at},
      authorize?: false
    )

    Core.create_sealed_product_draft!(%{
      slug: "future-#{System.unique_integer([:positive])}",
      name: "#{token} Future",
      product_type: "tin",
      officially_distributed: true,
      release_date: Date.add(Date.utc_today(), 1)
    })

    Core.create_sealed_product_draft!(%{
      slug: "unofficial-#{System.unique_integer([:positive])}",
      name: "#{token} Unofficial",
      product_type: "tin",
      officially_distributed: false,
      release_date: Date.utc_today()
    })

    alias_product = product("Canonical without the eligibility token")

    rejected =
      Core.create_sealed_product_alias!(%{
        sealed_product_id: alias_product.id,
        kind: "name",
        original_value: "#{token} Rejected Alias"
      })

    Core.reject_sealed_product_alias!(rejected, %{expected_updated_at: rejected.updated_at},
      authorize?: false
    )

    ean =
      Core.create_sealed_product_alias!(%{
        sealed_product_id: alias_product.id,
        kind: "ean",
        original_value: "4006381333931"
      })

    Core.approve_sealed_product_alias!(ean, %{expected_updated_at: ean.updated_at},
      authorize?: false
    )

    assert {:ok, results} = Core.search_public_sealed_products(token)
    assert Enum.map(results, & &1.id) == [discontinued.id]
    assert {:ok, []} = Core.search_public_sealed_products("4006381333931")
  end

  test "public mapping read filters and loads active evidence" do
    shop =
      Core.register_retailer!(%{
        slug: "public-shop-#{System.unique_integer([:positive])}",
        source_key: "public-shop-#{System.unique_integer([:positive])}",
        name: "Public Shop",
        category: "regular_retailer"
      })

    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    listing =
      Core.ingest_retailer_listing!(%{
        retailer_id: shop.id,
        source_listing_id: "public-listing-#{System.unique_integer([:positive])}",
        source_title: "Public Box",
        direct_url: "https://shop.example/public",
        stock_status: "in_stock",
        current_price_pln: Decimal.new("10"),
        first_seen_at: now,
        last_seen_at: now,
        last_checked_at: now
      })

    target = product("Mapped Public Product")

    review =
      Core.create_review_listing_mapping!(%{
        retailer_listing_id: listing.id,
        candidate_product_id: target.id,
        confidence: Decimal.new("0.9"),
        evidence: %{source: "test"},
        reason: "test review"
      })

    mapping =
      Core.approve_listing_mapping!(
        review,
        %{
          confirmed_product_id: target.id,
          confidence: Decimal.new("1"),
          evidence: %{source: "test"},
          expected_updated_at: review.updated_at
        },
        authorize?: false
      )

    assert [public] = Core.list_public_listing_mappings_for_product!(target.id)
    assert public.id == mapping.id
    assert public.retailer_listing.retailer.id == shop.id

    disabled_listing =
      Core.ingest_retailer_listing!(%{
        retailer_id: shop.id,
        source_listing_id: "disabled-listing-#{System.unique_integer([:positive])}",
        source_title: "Disabled Box",
        direct_url: "https://shop.example/disabled",
        stock_status: "in_stock",
        current_price_pln: Decimal.new("11"),
        first_seen_at: now,
        last_seen_at: now,
        last_checked_at: now
      })

    disabled_review =
      Core.create_review_listing_mapping!(%{
        retailer_listing_id: disabled_listing.id,
        candidate_product_id: target.id,
        confidence: Decimal.new("0.9"),
        evidence: %{source: "test"},
        reason: "test review"
      })

    Core.approve_listing_mapping!(
      disabled_review,
      %{
        confirmed_product_id: target.id,
        confidence: Decimal.new("1"),
        evidence: %{source: "test"},
        expected_updated_at: disabled_review.updated_at
      },
      authorize?: false
    )

    Core.disable_retailer_listing!(disabled_listing)

    assert Enum.map(Core.list_public_listing_mappings_for_product!(target.id), & &1.id) == [
             mapping.id
           ]

    disabled_shop =
      Core.register_retailer!(%{
        slug: "disabled-public-shop-#{System.unique_integer([:positive])}",
        source_key: "disabled-public-shop-#{System.unique_integer([:positive])}",
        name: "Disabled Public Shop",
        category: "regular_retailer"
      })

    disabled_shop_listing =
      Core.ingest_retailer_listing!(%{
        retailer_id: disabled_shop.id,
        source_listing_id: "disabled-shop-listing-#{System.unique_integer([:positive])}",
        source_title: "Disabled Shop Box",
        direct_url: "https://disabled-shop.example/public",
        stock_status: "in_stock",
        current_price_pln: Decimal.new("12"),
        first_seen_at: now,
        last_seen_at: now,
        last_checked_at: now
      })

    disabled_shop_review =
      Core.create_review_listing_mapping!(%{
        retailer_listing_id: disabled_shop_listing.id,
        candidate_product_id: target.id,
        confidence: Decimal.new("0.9"),
        evidence: %{source: "test"},
        reason: "test review"
      })

    Core.approve_listing_mapping!(
      disabled_shop_review,
      %{
        confirmed_product_id: target.id,
        confidence: Decimal.new("1"),
        evidence: %{source: "test"},
        expected_updated_at: disabled_shop_review.updated_at
      },
      authorize?: false
    )

    Core.disable_retailer!(disabled_shop)

    assert Enum.map(Core.list_public_listing_mappings_for_product!(target.id), & &1.id) == [
             mapping.id
           ]

    Repo.query!(
      "UPDATE sealed_products SET image_url = NULL, image_source = NULL, image_source_url = NULL WHERE id = $1",
      [Ecto.UUID.dump!(target.id)]
    )

    for image_url <- [
          "https://boosterland.pl/images/fallback.jpg",
          "https://cdn.colligere.pl/images/fallback.jpg"
        ] do
      Repo.query!(
        "UPDATE retailer_listings SET image_url = $1 WHERE id = $2",
        [image_url, Ecto.UUID.dump!(mapping.retailer_listing_id)]
      )

      assert [fallback] = Core.list_public_listing_mappings_for_product!(target.id)
      assert fallback.id == mapping.id
    end

    assert {:ok, public_target} = Core.get_public_sealed_product_by_id(target.id)
    assert public_target.id == target.id
    [public_mapping] = public_target.public_image_mappings
    assert match?(%Ash.NotLoaded{}, public_mapping.evidence)
    assert match?(%Ash.NotLoaded{}, public_mapping.reason)
    assert match?(%Ash.NotLoaded{}, public_mapping.retailer_listing.source_payload)
    assert match?(%Ash.NotLoaded{}, public_mapping.retailer_listing.retailer)

    Core.disable_retailer_listing!(listing)
    assert Core.list_public_listing_mappings_for_product!(target.id) == []
  end
end
