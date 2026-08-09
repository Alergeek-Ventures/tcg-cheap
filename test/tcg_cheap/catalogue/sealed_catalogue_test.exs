defmodule TcgCheap.Catalogue.SealedCatalogueTest do
  use TcgCheap.DataCase, async: true

  alias TcgCheap.Catalogue.SealedIdentifier
  alias TcgCheap.Core

  defp attrs(overrides \\ %{}) do
    Map.merge(
      %{
        slug: "sealed-#{System.unique_integer([:positive])}",
        name: "Example Product",
        product_type: "booster_box"
      },
      overrides
    )
  end

  defp approved_product(overrides \\ %{}) do
    attrs =
      attrs(Map.merge(%{officially_distributed: true, release_date: Date.utc_today()}, overrides))

    draft = Core.create_sealed_product_draft!(attrs)

    Core.approve_sealed_product!(draft, %{expected_updated_at: draft.updated_at},
      authorize?: false
    )
  end

  test "drafts are permissive and normalized but unpublished" do
    product = Core.create_sealed_product_draft!(attrs(%{name: "  Example   Product "}))
    assert {product.publication_status, product.market, product.language} == {"draft", "PL", "en"}
    assert product.search_name == "example product"

    assert Core.list_sealed_product_draft_review_queue!(authorize?: false)
           |> Enum.any?(&(&1.id == product.id))
  end

  test "product type and canonical slug are constrained" do
    for invalid <- [
          %{product_type: "case"},
          %{slug: "Not-Kebab"},
          %{slug: "bad_slug"},
          %{slug: "bad--slug"},
          %{slug: "bad slug"}
        ] do
      assert_raise Ash.Error.Invalid, fn -> Core.create_sealed_product_draft!(attrs(invalid)) end
    end
  end

  test "MSRP requires a finite positive amount and matching source" do
    for invalid <- [
          %{msrp_pln: Decimal.new("0"), msrp_source: "x"},
          %{msrp_pln: Decimal.new("-1"), msrp_source: "x"},
          %{msrp_pln: "NaN", msrp_source: "x"},
          %{msrp_pln: "Infinity", msrp_source: "x"},
          %{msrp_pln: Decimal.new("1")},
          %{msrp_source: "x"}
        ] do
      assert_raise Ash.Error.Invalid, fn -> Core.create_sealed_product_draft!(attrs(invalid)) end
    end

    assert Core.create_sealed_product_draft!(
             attrs(%{msrp_pln: Decimal.new("1"), msrp_source: "official"})
           ).msrp_currency == "PLN"
  end

  test "approval enforces draft, official PL/en, release, and MSRP requirements" do
    draft = Core.create_sealed_product_draft!(attrs())

    assert_raise Ash.Error.Invalid, fn ->
      Core.approve_sealed_product!(draft, %{expected_updated_at: draft.updated_at},
        authorize?: false
      )
    end

    future =
      Core.revise_sealed_product_draft!(
        draft,
        %{
          officially_distributed: true,
          release_date: Date.add(Date.utc_today(), 1),
          expected_updated_at: draft.updated_at
        },
        authorize?: false
      )

    assert_raise Ash.Error.Invalid, fn ->
      Core.approve_sealed_product!(future, %{expected_updated_at: future.updated_at},
        authorize?: false
      )
    end

    ready =
      Core.revise_sealed_product_draft!(
        future,
        %{
          officially_distributed: true,
          release_date: Date.utc_today(),
          expected_updated_at: future.updated_at
        },
        authorize?: false
      )

    assert Core.approve_sealed_product!(
             ready,
             %{expected_updated_at: ready.updated_at},
             authorize?: false
           ).publication_status == "approved"
  end

  test "revise and approve are draft-only transitions" do
    approved = approved_product()

    assert_raise Ash.Error.Invalid, fn ->
      Core.revise_sealed_product_draft!(
        approved,
        %{name: "Changed", expected_updated_at: approved.updated_at},
        authorize?: false
      )
    end

    assert_raise Ash.Error.Invalid, fn ->
      Core.approve_sealed_product!(approved, %{expected_updated_at: approved.updated_at},
        authorize?: false
      )
    end

    archived =
      Core.archive_sealed_product!(
        approved,
        %{expected_updated_at: approved.updated_at},
        authorize?: false
      )

    assert_raise Ash.Error.Invalid, fn ->
      Core.revise_sealed_product_draft!(
        archived,
        %{name: "Changed", expected_updated_at: archived.updated_at},
        authorize?: false
      )
    end

    assert_raise Ash.Error.Invalid, fn ->
      Core.approve_sealed_product!(archived, %{expected_updated_at: archived.updated_at},
        authorize?: false
      )
    end
  end

  test "stale review versions cannot revise or archive a draft" do
    draft = Core.create_sealed_product_draft!(attrs())
    original_updated_at = draft.updated_at

    revised =
      Core.revise_sealed_product_draft!(
        draft,
        %{name: "First revision", expected_updated_at: original_updated_at},
        authorize?: false
      )

    assert revised.name == "First revision"

    assert_raise Ash.Error.Invalid, fn ->
      Core.revise_sealed_product_draft!(
        revised,
        %{name: "Stale revision", expected_updated_at: original_updated_at},
        authorize?: false
      )
    end

    assert_raise Ash.Error.Invalid, fn ->
      Core.archive_sealed_product!(
        revised,
        %{expected_updated_at: original_updated_at},
        authorize?: false
      )
    end
  end

  test "product import refreshes drafts and protects approved and archived rows" do
    source = attrs(%{name: "Initial", source: "provider", source_id: "stable-1"})
    draft = Core.import_sealed_product_draft!(source)

    corrected_source = Map.put(source, :slug, "corrected-slug")

    assert Core.import_sealed_product_draft!(corrected_source).id == draft.id
    assert Core.get_sealed_product_by_slug!("corrected-slug").id == draft.id

    assert Core.import_sealed_product_draft!(Map.put(corrected_source, :name, "Refreshed")).name ==
             "Refreshed"

    current_draft = Core.get_sealed_product_by_slug!("corrected-slug")

    revised =
      Core.revise_sealed_product_draft!(
        current_draft,
        %{
          officially_distributed: true,
          release_date: Date.utc_today(),
          expected_updated_at: current_draft.updated_at
        },
        authorize?: false
      )

    Core.approve_sealed_product!(
      revised,
      %{expected_updated_at: revised.updated_at},
      authorize?: false
    )

    approved = Core.get_sealed_product_by_slug!("corrected-slug")

    assert Core.import_sealed_product_draft!(Map.put(corrected_source, :name, "Protected")).name ==
             approved.name

    archived =
      Core.archive_sealed_product!(
        approved,
        %{expected_updated_at: approved.updated_at},
        authorize?: false
      )

    assert Core.import_sealed_product_draft!(Map.put(corrected_source, :name, "Still Protected")).name ==
             archived.name
  end

  test "public reads include released current/discontinued products, not drafts or archived" do
    current = approved_product(%{name: "Zulu Product"})

    discontinued =
      approved_product(%{name: "Alpha Product"})
      |> Core.mark_sealed_product_discontinued!(authorize?: false)

    hidden = approved_product(%{name: "Hidden Product"})

    archived =
      Core.archive_sealed_product!(
        hidden,
        %{expected_updated_at: hidden.updated_at},
        authorize?: false
      )

    draft = Core.create_sealed_product_draft!(attrs(%{name: "Draft Product"}))

    public =
      Core.list_public_sealed_products!() |> Enum.filter(&String.starts_with?(&1.slug, "sealed-"))

    assert Enum.map(public, & &1.name) == Enum.sort([current.name, discontinued.name])
    assert Core.get_public_sealed_product_by_slug!(current.slug).id == current.id
    assert {:ok, public_discontinued} = Core.get_public_sealed_product_by_slug(discontinued.slug)
    assert public_discontinued.id == discontinued.id
    assert {:ok, nil} = Core.get_public_sealed_product_by_slug(archived.slug)
    assert {:ok, nil} = Core.get_public_sealed_product_by_slug(draft.slug)
  end

  test "aliases normalize names, validate GTINs, and remain pending" do
    product = Core.create_sealed_product_draft!(attrs())

    alias_record =
      Core.create_sealed_product_alias!(%{
        sealed_product_id: product.id,
        kind: "name",
        original_value: "  Ｅxample   Product "
      })

    assert alias_record.normalized_value == "example product"
    assert alias_record.review_status == "pending"

    for {value, normalized} <- [
          {"9638-5074", "96385074"},
          {"036000291452", "036000291452"},
          {"4006381333931", "4006381333931"},
          {"10614141000019", "10614141000019"}
        ] do
      gtin =
        Core.create_sealed_product_alias!(%{
          sealed_product_id: product.id,
          kind: "ean",
          original_value: value
        })

      assert gtin.normalized_value == normalized
    end
  end

  test "invalid GTINs are rejected through the Core action" do
    product = Core.create_sealed_product_draft!(attrs())

    for value <- ["40063813339A1", "123456789", "4006381333932"] do
      assert_raise Ash.Error.Invalid, fn ->
        Core.create_sealed_product_alias!(%{
          sealed_product_id: product.id,
          kind: "ean",
          original_value: value
        })
      end
    end

    refute SealedIdentifier.valid_ean?("4006381333932")
  end

  test "alias imports are pending-only idempotent upserts" do
    product = Core.create_sealed_product_draft!(attrs())
    source = %{sealed_product_id: product.id, kind: "name", original_value: "First", source: "a"}
    first = Core.import_sealed_product_alias!(source)

    refreshed =
      Core.import_sealed_product_alias!(
        Map.merge(source, %{original_value: " First ", source: "b"})
      )

    assert refreshed.id == first.id and refreshed.original_value == "First"

    approved =
      Core.approve_sealed_product_alias!(
        refreshed,
        %{expected_updated_at: refreshed.updated_at},
        authorize?: false
      )

    protected =
      Core.import_sealed_product_alias!(
        Map.merge(source, %{original_value: " First ", source: "c"})
      )

    assert protected.id == approved.id and protected.original_value == "First" and
             protected.review_status == "approved"

    rejected_alias =
      Core.create_sealed_product_alias!(%{
        sealed_product_id: product.id,
        kind: "name",
        original_value: "Rejected"
      })

    rejected =
      Core.reject_sealed_product_alias!(
        rejected_alias,
        %{expected_updated_at: rejected_alias.updated_at},
        authorize?: false
      )

    assert Core.import_sealed_product_alias!(%{
             sealed_product_id: product.id,
             kind: "name",
             original_value: "Rejected",
             source: "d"
           }).original_value == "Rejected"

    assert_raise Ash.Error.Invalid, fn ->
      Core.approve_sealed_product_alias!(
        rejected,
        %{expected_updated_at: rejected.updated_at},
        authorize?: false
      )
    end

    assert_raise Ash.Error.Invalid, fn ->
      Core.reject_sealed_product_alias!(
        approved,
        %{expected_updated_at: approved.updated_at},
        authorize?: false
      )
    end
  end

  test "alias queues, duplicate identity, and foreign keys are enforced" do
    product = Core.create_sealed_product_draft!(attrs())

    alias_record =
      Core.create_sealed_product_alias!(%{
        sealed_product_id: product.id,
        kind: "name",
        original_value: "Alias"
      })

    queued =
      Enum.find(
        Core.list_sealed_product_alias_pending_queue!(authorize?: false),
        &(&1.id == alias_record.id)
      )

    assert queued.sealed_product.id == product.id

    assert_raise Ash.Error.Invalid, fn ->
      Core.create_sealed_product_alias!(%{
        sealed_product_id: product.id,
        kind: "name",
        original_value: " alias "
      })
    end

    assert_raise Ash.Error.Invalid, fn ->
      Core.create_sealed_product_alias!(%{
        sealed_product_id: Ecto.UUID.generate(),
        kind: "name",
        original_value: "Other"
      })
    end

    approved =
      Core.approve_sealed_product_alias!(
        alias_record,
        %{expected_updated_at: alias_record.updated_at},
        authorize?: false
      )

    assert Enum.map(Core.list_approved_sealed_product_aliases!(product.id), & &1.id) == [
             approved.id
           ]

    assert Core.reject_sealed_product_alias(
             approved,
             %{expected_updated_at: approved.updated_at},
             authorize?: false
           )
           |> elem(0) == :error

    rejected_alias =
      Core.create_sealed_product_alias!(%{
        sealed_product_id: product.id,
        kind: "name",
        original_value: "Queue Rejected"
      })

    rejected =
      Core.reject_sealed_product_alias!(
        rejected_alias,
        %{expected_updated_at: rejected_alias.updated_at},
        authorize?: false
      )

    assert Enum.any?(
             Core.list_sealed_product_alias_rejected_queue!(authorize?: false),
             &(&1.id == rejected.id)
           )
  end

  test "source provenance is optional for curation but paired and required for imports" do
    assert_raise Ash.Error.Invalid, fn ->
      Core.create_sealed_product_draft!(attrs(%{source: "provider"}))
    end

    assert_raise Ash.Error.Invalid, fn ->
      Core.create_sealed_product_draft!(attrs(%{source_id: "id"}))
    end

    assert_raise Ash.Error.Invalid, fn ->
      Core.import_sealed_product_draft!(attrs(%{source: "provider"}))
    end

    assert_raise Ash.Error.Invalid, fn ->
      Core.import_sealed_product_draft!(
        attrs(%{source: "provider", source_id: "id"})
        |> Map.delete(:slug)
      )
    end
  end

  test "direct SQL rejects a NULL source with a non-NULL source_id" do
    product = Core.create_sealed_product_draft!(attrs())

    assert_raise Postgrex.Error, fn ->
      Repo.query!("UPDATE sealed_products SET source = NULL, source_id = 'id' WHERE id = $1", [
        Ecto.UUID.dump!(product.id)
      ])
    end
  end

  test "direct SQL rejects MSRP NaN with a valid source pair" do
    product = Core.create_sealed_product_draft!(attrs())

    assert_raise Postgrex.Error, fn ->
      Repo.query!(
        "UPDATE sealed_products SET msrp_pln = 'NaN'::numeric, msrp_source = 'official' WHERE id = $1",
        [Ecto.UUID.dump!(product.id)]
      )
    end
  end

  test "direct SQL rejects positive MSRP Infinity with a valid source pair" do
    product = Core.create_sealed_product_draft!(attrs())

    assert_raise Postgrex.Error, fn ->
      Repo.query!(
        "UPDATE sealed_products SET msrp_pln = 'Infinity'::numeric, msrp_source = 'official' WHERE id = $1",
        [Ecto.UUID.dump!(product.id)]
      )
    end
  end

  test "direct SQL rejects negative MSRP Infinity with a valid source pair" do
    product = Core.create_sealed_product_draft!(attrs())

    assert_raise Postgrex.Error, fn ->
      Repo.query!(
        "UPDATE sealed_products SET msrp_pln = '-Infinity'::numeric, msrp_source = 'official' WHERE id = $1",
        [Ecto.UUID.dump!(product.id)]
      )
    end
  end

  test "direct SQL rejects approved products without official release completeness" do
    product = Core.create_sealed_product_draft!(attrs())

    assert_raise Postgrex.Error, fn ->
      Repo.query!(
        "UPDATE sealed_products SET publication_status = 'approved', approved_at = now(), release_date = NULL, officially_distributed = FALSE WHERE id = $1",
        [Ecto.UUID.dump!(product.id)]
      )
    end
  end

  test "direct SQL rejects invalid GTIN checksum" do
    product = Core.create_sealed_product_draft!(attrs())

    assert_raise Postgrex.Error, fn ->
      Repo.query!(
        "INSERT INTO sealed_product_aliases (id, kind, original_value, normalized_value, review_status, sealed_product_id, inserted_at, updated_at) VALUES (gen_random_uuid(), 'ean', '4006381333932', '4006381333932', 'pending', $1, now(), now())",
        [Ecto.UUID.dump!(product.id)]
      )
    end
  end

  test "a GTIN cannot belong to two canonical products" do
    first = Core.create_sealed_product_draft!(attrs())
    second = Core.create_sealed_product_draft!(attrs())
    value = "4006381333931"

    Core.create_sealed_product_alias!(%{
      sealed_product_id: first.id,
      kind: "ean",
      original_value: value
    })

    assert_raise Ash.Error.Invalid, fn ->
      Core.create_sealed_product_alias!(%{
        sealed_product_id: second.id,
        kind: "ean",
        original_value: value
      })
    end
  end
end

defmodule TcgCheap.Catalogue.SealedCatalogueConcurrencyTest do
  use TcgCheap.DataCase, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias TcgCheap.Core
  alias TcgCheap.Repo

  test "concurrent approvals serialize and only one valid transition wins" do
    product =
      Sandbox.unboxed_run(Repo, fn ->
        Core.create_sealed_product_draft!(%{
          slug: "concurrent-#{System.unique_integer([:positive])}",
          name: "Concurrent Product",
          product_type: "tin",
          officially_distributed: true,
          release_date: Date.utc_today()
        })
      end)

    on_exit(fn ->
      Sandbox.unboxed_run(Repo, fn ->
        Repo.query!("DELETE FROM sealed_products WHERE id = $1", [Ecto.UUID.dump!(product.id)])
      end)
    end)

    parent = self()

    tasks =
      for _ <- 1..2 do
        Task.async(fn ->
          send(parent, {:ready, self()})

          receive do
            :go ->
              Sandbox.unboxed_run(Repo, fn ->
                Core.approve_sealed_product(
                  product,
                  %{expected_updated_at: product.updated_at},
                  authorize?: false
                )
              end)
          end
        end)
      end

    assert_receive {:ready, first}, 5_000
    assert_receive {:ready, second}, 5_000
    send(first, :go)
    send(second, :go)
    results = Enum.map(tasks, &Task.await(&1, 10_000))
    assert Enum.count(results, &match?({:ok, _}, &1)) == 1
    assert Enum.count(results, &match?({:error, %Ash.Error.Invalid{}}, &1)) == 1

    assert Sandbox.unboxed_run(Repo, fn ->
             Core.get_sealed_product_by_slug!(product.slug).publication_status
           end) == "approved"

    approved = Sandbox.unboxed_run(Repo, fn -> Core.get_sealed_product_by_slug!(product.slug) end)

    Sandbox.unboxed_run(Repo, fn ->
      Core.archive_sealed_product!(
        approved,
        %{expected_updated_at: approved.updated_at},
        authorize?: false
      )
    end)
  end
end
