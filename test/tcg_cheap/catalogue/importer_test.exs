defmodule TcgCheap.Catalogue.ImporterTest do
  use ExUnit.Case, async: false

  import Ecto.Query

  alias Ecto.Adapters.SQL.Sandbox
  alias TcgCheap.{Catalogue.Importer, Core, Repo}

  defmodule MismatchProvider do
    def fetch_card(_, _),
      do:
        {:ok,
         %{
           "id" => "mismatch-card",
           "name" => "Card",
           "localId" => "1",
           "set" => %{"id" => "expected"}
         }}

    def fetch_set(_, _), do: {:ok, %{"id" => "actual", "name" => "Wrong Set"}}
  end

  defmodule CardMismatchProvider do
    def fetch_card(_, _),
      do:
        {:ok,
         %{
           "id" => "actual-card",
           "name" => "Card",
           "localId" => "1",
           "set" => %{"id" => "card-mismatch-set"}
         }}

    def fetch_set(_, _), do: {:ok, %{"id" => "card-mismatch-set", "name" => "Set"}}
  end

  defmodule MaterialProvider do
    def fetch_card(_, _),
      do:
        {:ok,
         %{
           "id" => "material-card",
           "name" => "Card",
           "localId" => "1",
           "set" => %{"id" => "material-set"},
           "variants_detailed" => [
             %{"type" => "normal", "subtype" => "shadowless"},
             %{"type" => "holo", "subtype" => "oversized"}
           ]
         }}

    def fetch_set(_, _), do: {:ok, %{"id" => "material-set", "name" => "Set"}}
  end

  defmodule SingleShadowlessProvider do
    def fetch_card(_, _),
      do:
        {:ok,
         %{
           "id" => "single-shadowless",
           "name" => "Card",
           "localId" => "1",
           "set" => %{"id" => "single-material-set"},
           "variants_detailed" => [%{"subtype" => "shadowless"}]
         }}

    def fetch_set(_, _), do: {:ok, %{"id" => "single-material-set", "name" => "Set"}}
  end

  defmodule SingleOversizedProvider do
    def fetch_card(_, _),
      do:
        {:ok,
         %{
           "id" => "single-oversized",
           "name" => "Card",
           "localId" => "1",
           "set" => %{"id" => "single-size-set"},
           "variants_detailed" => [%{"size" => "jumbo"}]
         }}

    def fetch_set(_, _), do: {:ok, %{"id" => "single-size-set", "name" => "Set"}}
  end

  defmodule ProductsProvider do
    def fetch_card(_, _),
      do:
        {:ok,
         %{
           "id" => "products-card",
           "name" => "Card",
           "localId" => "1",
           "set" => %{"id" => "products-set"},
           "pricing" => %{"cardmarket" => %{"idProduct" => 1}},
           "variants_detailed" => [%{"pricing" => %{"cardmarket" => %{"idProduct" => 2}}}]
         }}

    def fetch_set(_, _), do: {:ok, %{"id" => "products-set", "name" => "Set"}}
  end

  defmodule TopLevelMaterialProvider do
    def fetch_card(_, _),
      do:
        {:ok,
         %{
           "id" => "top-level-material",
           "name" => "Card",
           "localId" => "1",
           "set" => %{"id" => "top-level-material-set"},
           "variants" => %{"jumbo" => true, "preRelease" => true},
           "pricing" => %{"cardmarket" => %{"idProduct" => 123}}
         }}

    def fetch_set(_, _), do: {:ok, %{"id" => "top-level-material-set", "name" => "Set"}}
  end

  defmodule FoilMaterialProvider do
    def fetch_card(_, _),
      do:
        {:ok,
         %{
           "id" => "foil-material",
           "name" => "Card",
           "localId" => "1",
           "set" => %{"id" => "foil-material-set"},
           "variants_detailed" => [%{"type" => "normal", "foil" => "pokeball"}],
           "pricing" => %{"cardmarket" => %{"idProduct" => 456}}
         }}

    def fetch_set(_, _), do: {:ok, %{"id" => "foil-material-set", "name" => "Set"}}
  end

  defmodule OtherProviderProductProvider do
    def fetch_card(_, _),
      do:
        {:ok,
         %{
           "id" => "other-provider-product",
           "name" => "Card",
           "localId" => "1",
           "set" => %{"id" => "other-provider-product-set"},
           "pricing" => %{"tcgplayer" => %{"idProduct" => 789}}
         }}

    def fetch_set(_, _), do: {:ok, %{"id" => "other-provider-product-set", "name" => "Set"}}
  end

  defmodule FailingProvider do
    def fetch_card(_, _),
      do:
        {:ok,
         %{
           "id" => "failing-card",
           "name" => "Card",
           "localId" => "1",
           "set" => %{"id" => "failing-set"},
           "bad" => self()
         }}

    def fetch_set(_, _), do: {:ok, %{"id" => "failing-set", "name" => "Set"}}
  end

  defmodule NumericLocalIdProvider do
    def fetch_card(_, _),
      do:
        {:ok,
         %{
           "id" => "numeric-local-id",
           "name" => "Numeric Card",
           "localId" => 7,
           "set" => %{"id" => "numeric-set"}
         }}

    def fetch_set(_, _), do: {:ok, %{"id" => "numeric-set", "name" => "Numeric Set"}}
  end

  defmodule NewCatalogueProvider do
    def fetch_card(_, _),
      do:
        {:ok,
         %{
           "id" => "versioned-card",
           "name" => "New Name",
           "localId" => "1",
           "updated" => "2026-02-02T00:00:00Z",
           "set" => %{"id" => "versioned-set"},
           "pricing" => %{
             "cardmarket" => %{"idProduct" => 222, "updated" => "2026-02-02T00:00:00Z"}
           }
         }}

    def fetch_set(_, _), do: {:ok, %{"id" => "versioned-set", "name" => "New Set"}}
  end

  defmodule OldCatalogueProvider do
    def fetch_card(_, _),
      do:
        {:ok,
         %{
           "id" => "versioned-card",
           "name" => "Old Name",
           "localId" => "1",
           "updated" => "2026-01-01T00:00:00Z",
           "set" => %{"id" => "versioned-set"},
           "pricing" => %{
             "cardmarket" => %{"idProduct" => 111, "updated" => "2026-01-01T00:00:00Z"}
           }
         }}

    def fetch_set(_, _), do: {:ok, %{"id" => "versioned-set", "name" => "Old Set"}}
  end

  defmodule MalformedCallbackProvider do
    def fetch_card(_, _), do: :not_a_callback_result
    def fetch_set(_, _), do: {:ok, %{"id" => "set", "name" => "Set"}}
  end

  defmodule RaisedCallbackProvider do
    def fetch_card(_, _), do: raise("provider boom")
    def fetch_set(_, _), do: {:ok, %{"id" => "set", "name" => "Set"}}
  end

  defmodule SequentialBudgetStub do
    def admit("tcgdex_catalogue") do
      Agent.get_and_update(
        Application.fetch_env!(:tcg_cheap, :importer_budget_stub),
        fn
          0 -> {{:ok, %{}}, 1}
          calls -> {{:error, :hourly_limit_reached}, calls + 1}
        end
      )
    end
  end

  @fixture_dir Path.expand("../../fixtures/tcgdex/catalogue", __DIR__)

  setup do
    :ok = Sandbox.checkout(Repo)
    Sandbox.mode(Repo, {:shared, self()})
    :ok
  end

  defp fixture(name), do: @fixture_dir |> Path.join(name) |> File.read!()

  defp stub_catalogue(card_body, set_body, opts \\ []) do
    name = make_ref()
    card_id = Keyword.get(opts, :card_id, "sv-base-1")
    set_id = Keyword.get(opts, :set_id, "sv-base")

    Req.Test.stub(name, fn conn ->
      case conn.request_path do
        "/v2/en/cards/" <> ^card_id -> Req.Test.text(conn, card_body)
        "/v2/en/sets/" <> ^set_id -> Req.Test.text(conn, set_body)
        _ -> Plug.Conn.send_resp(conn, 500, "unexpected path")
      end
    end)

    [provider_options: [request_options: [plug: {Req.Test, name}, retry: false, max_retries: 0]]]
  end

  test "imports a modern normal/reverse card as matched and preserves legal flags" do
    opts = stub_catalogue(fixture("modern_normal.json"), fixture("modern_set.json"))

    assert {:ok, card} =
             Importer.import_card(
               "sv-base-1",
               Keyword.put(opts, :clock, fn -> ~U[2026-01-01 00:00:00Z] end)
             )

    assert card.mapping_status == "matched"
    assert card.cardmarket_product_id == 12_345
    assert card.standard_legal
    assert card.expanded_legal
    assert card.image_url == "https://assets.tcgdex.net/en/tcg/sv/sv-base/001/high.webp"

    assert {:ok, set} = Core.get_card_set_by_tcgdex_id("sv-base")
    assert set.standard_legal
    assert set.expanded_legal
    assert set.logo_url == "https://assets.tcgdex.net/en/sets/sv/sv-base/logo.webp"
    assert set.symbol_url == "https://assets.tcgdex.net/en/sets/sv/sv-base/symbol.webp"
  end

  test "material first edition, shadowless and stamped variants require review" do
    opts =
      stub_catalogue(fixture("charizard_variants.json"), fixture("base_set.json"),
        card_id: "base-4",
        set_id: "base"
      )

    assert {:ok, card} = Importer.import_card("base-4", opts)
    assert card.mapping_status == "review"
    assert card.cardmarket_product_id == nil
    assert card.mapping_review_reason == "firstEdition variant"
  end

  test "missing mapping is unmatched" do
    opts =
      stub_catalogue(fixture("no_mapping.json"), fixture("no_mapping_set.json"),
        card_id: "sv-base-2",
        set_id: "sv-base-2-set"
      )

    assert {:ok, card} = Importer.import_card("sv-base-2", opts)
    assert card.mapping_status == "unmatched"
    assert card.cardmarket_product_id == nil
  end

  test "reimport updates metadata without duplicating rows" do
    opts = stub_catalogue(fixture("modern_normal.json"), fixture("modern_set.json"))
    assert {:ok, first} = Importer.import_card("sv-base-1", opts)

    changed_card = String.replace(fixture("modern_normal.json"), "Pikachu", "Raichu")
    changed_set = String.replace(fixture("modern_set.json"), "Modern Base", "Modern Base Updated")
    opts = stub_catalogue(changed_card, changed_set)
    assert {:ok, second} = Importer.import_card("sv-base-1", opts)
    assert second.id == first.id
    assert second.name == "Raichu"
    assert second.set_name == "Modern Base Updated"
    assert {:ok, stored_set} = Core.get_card_set_by_tcgdex_id("sv-base")
    assert stored_set.name == "Modern Base"
    assert Repo.aggregate(from(c in "card_printings"), :count, :id) == 1
    assert Repo.aggregate(from(c in "card_sets"), :count, :id) == 1
  end

  test "set fetch failure happens before persistence" do
    name = make_ref()

    Req.Test.stub(name, fn conn ->
      case conn.request_path do
        "/v2/en/cards/sv-base-1" -> Req.Test.text(conn, fixture("modern_normal.json"))
        "/v2/en/sets/sv-base" -> Plug.Conn.send_resp(conn, 503, "offline")
      end
    end)

    assert {:error, {:http_error, %{status: 503}}} =
             Importer.import_card("sv-base-1",
               provider_options: [
                 request_options: [plug: {Req.Test, name}, retry: false, max_retries: 0]
               ]
             )

    assert Repo.aggregate(from(c in "card_printings"), :count, :id) == 0
    assert Repo.aggregate(from(c in "card_sets"), :count, :id) == 0
  end

  test "operational imports admit each provider request before HTTP" do
    previous_admitter = Application.get_env(:tcg_cheap, :acquisition_budget_admitter)
    previous_stub = Application.get_env(:tcg_cheap, :importer_budget_stub)
    {:ok, budget_stub} = Agent.start_link(fn -> 0 end)

    Application.put_env(:tcg_cheap, :acquisition_budget_admitter, SequentialBudgetStub)
    Application.put_env(:tcg_cheap, :importer_budget_stub, budget_stub)

    on_exit(fn ->
      restore_env(:acquisition_budget_admitter, previous_admitter)
      restore_env(:importer_budget_stub, previous_stub)
      if Process.alive?(budget_stub), do: Agent.stop(budget_stub)
    end)

    name = make_ref()
    requests = :counters.new(1, [:atomics])

    Req.Test.stub(name, fn conn ->
      :counters.add(requests, 1, 1)

      case conn.request_path do
        "/v2/en/cards/sv-base-1" -> Req.Test.text(conn, fixture("modern_normal.json"))
        _ -> flunk("rejected set request reached HTTP")
      end
    end)

    assert {:error,
            {:acquisition_budget_rejected, :hourly_limit_reached,
             %DateTime{time_zone: "Etc/UTC"} = reset_at}} =
             Importer.import_card("sv-base-1",
               provider_options: [
                 request_options: [plug: {Req.Test, name}, retry: :safe_transient, max_retries: 2]
               ]
             )

    assert DateTime.compare(reset_at, DateTime.utc_now()) == :gt
    assert reset_at.minute == 0
    assert reset_at.second == 0
    assert :counters.get(requests, 1) == 1
    assert Agent.get(budget_stub, & &1) == 2
    assert Repo.aggregate(from(c in "card_printings"), :count, :id) == 0
    assert Repo.aggregate(from(c in "card_sets"), :count, :id) == 0
  end

  test "normalizes malformed and raised provider callbacks" do
    assert {:error,
            {:provider_callback_error, :fetch_card, {:unexpected_return, :not_a_callback_result}}} =
             Importer.import_card("callback-card", provider: MalformedCallbackProvider)

    assert {:error,
            {:provider_callback_error, :fetch_card,
             {:raised, %RuntimeError{message: "provider boom"}}}} =
             Importer.import_card("callback-card", provider: RaisedCallbackProvider)
  end

  test "clock is invoked once after fetches and shared by both records" do
    opts = stub_catalogue(fixture("modern_normal.json"), fixture("modern_set.json"))
    counter = :counters.new(1, [:atomics])

    clock = fn ->
      :counters.add(counter, 1, 1)
      ~U[2026-02-02 00:00:00Z]
    end

    assert {:ok, card} = Importer.import_card("sv-base-1", Keyword.put(opts, :clock, clock))
    assert :counters.get(counter, 1) == 1
    assert {:ok, set} = Core.get_card_set_by_tcgdex_id("sv-base")
    assert card.last_synced_at == set.last_synced_at
  end

  test "accepts numeric localId and persists its canonical decimal string" do
    assert {:ok, card} =
             Importer.import_card("numeric-local-id", provider: NumericLocalIdProvider)

    assert card.collector_number == "7"
  end

  test "older metadata and mapping responses do not overwrite newer records" do
    assert {:ok, newer} = Importer.import_card("versioned-card", provider: NewCatalogueProvider)
    assert {:ok, older} = Importer.import_card("versioned-card", provider: OldCatalogueProvider)

    assert older.id == newer.id
    assert older.name == "New Name"
    assert older.cardmarket_product_id == 222
    assert DateTime.compare(older.source_updated_at, ~U[2026-02-02 00:00:00Z]) == :eq
    assert DateTime.compare(older.mapping_updated_at, ~U[2026-02-02 00:00:00Z]) == :eq
    assert {:ok, set} = Core.get_card_set_by_tcgdex_id("versioned-set")
    assert set.name == "New Set"
    assert Repo.aggregate(from(c in "card_printings"), :count, :id) == 1
    assert Repo.aggregate(from(s in "card_sets"), :count, :id) == 1
  end

  test "set identity mismatch is malformed and writes nothing" do
    assert {:error, {:malformed_response, {:set_id_mismatch, "expected", "actual"}}} =
             Importer.import_card("mismatch-card", provider: MismatchProvider)

    assert Repo.aggregate(from(c in "card_sets"), :count, :id) == 0
    assert Repo.aggregate(from(c in "card_printings"), :count, :id) == 0
  end

  test "card identity mismatch is malformed and writes nothing" do
    assert {:error, {:malformed_response, {:card_id_mismatch, "requested-card", "actual-card"}}} =
             Importer.import_card("requested-card", provider: CardMismatchProvider)

    assert Repo.aggregate(from(c in "card_sets"), :count, :id) == 0
    assert Repo.aggregate(from(c in "card_printings"), :count, :id) == 0
  end

  test "multiple material identities require review" do
    assert {:ok, card} = Importer.import_card("material-card", provider: MaterialProvider)
    assert card.mapping_status == "review"
    assert card.cardmarket_product_id == nil
  end

  test "a single shadowless subtype requires review without guessing a product" do
    assert {:ok, card} =
             Importer.import_card("single-shadowless", provider: SingleShadowlessProvider)

    assert card.mapping_status == "review"
    assert card.cardmarket_product_id == nil
    assert card.mapping_review_reason =~ "material descriptor"
  end

  test "a single oversized size requires review without guessing a product" do
    assert {:ok, card} =
             Importer.import_card("single-oversized", provider: SingleOversizedProvider)

    assert card.mapping_status == "review"
    assert card.cardmarket_product_id == nil
    assert card.mapping_review_reason =~ "material descriptor"
  end

  test "multiple Cardmarket products require review" do
    assert {:ok, card} = Importer.import_card("products-card", provider: ProductsProvider)
    assert card.mapping_status == "review"
    assert card.cardmarket_product_id == nil
  end

  test "top-level jumbo and preRelease flags require review" do
    assert {:ok, card} =
             Importer.import_card("top-level-material", provider: TopLevelMaterialProvider)

    assert card.mapping_status == "review"
    assert card.cardmarket_product_id == nil
  end

  test "a detailed foil descriptor requires review" do
    assert {:ok, card} = Importer.import_card("foil-material", provider: FoilMaterialProvider)
    assert card.mapping_status == "review"
    assert card.cardmarket_product_id == nil
    assert card.mapping_review_reason =~ "material descriptor"
  end

  test "an idProduct from another pricing provider does not match" do
    assert {:ok, card} =
             Importer.import_card("other-provider-product",
               provider: OtherProviderProductProvider
             )

    assert card.mapping_status == "unmatched"
    assert card.cardmarket_product_id == nil
  end

  test "card write failure rolls back the set write" do
    assert {:error, _reason} = Importer.import_card("failing-card", provider: FailingProvider)
    assert Repo.aggregate(from(c in "card_sets"), :count, :id) == 0
    assert Repo.aggregate(from(c in "card_printings"), :count, :id) == 0
  end

  test "database check constraints reject invalid mapping and set count rows" do
    assert_raise Postgrex.Error, fn ->
      Repo.query!("""
      INSERT INTO card_printings
        (tcgdex_id, name, set_name, collector_number, mapping_status, mapping_review_reason)
      VALUES ('raw-invalid-mapping', 'Card', 'Set', '1', 'matched', NULL)
      """)
    end

    assert_raise Postgrex.Error, fn ->
      Repo.query!("""
      INSERT INTO card_sets (tcgdex_id, name, official_count, total_count)
      VALUES ('raw-invalid-counts', 'Set', 5, 4)
      """)
    end
  end

  test "imports an already fetched payload with the same mapping behavior" do
    card_id = "fetched-card-#{System.unique_integer([:positive])}"
    set_id = "fetched-set-#{System.unique_integer([:positive])}"

    card = %{
      "id" => card_id,
      "name" => "Fetched Card",
      "localId" => 3,
      "set" => %{"id" => set_id},
      "pricing" => %{"cardmarket" => %{"idProduct" => 321}}
    }

    set = %{"id" => set_id, "name" => "Fetched Set"}

    assert {:ok, imported} =
             Importer.import_fetched_card(card, set, card_id,
               expected_set_id: set_id,
               synced_at: ~U[2026-03-01 00:00:00.123456Z]
             )

    assert imported.card.mapping_status == "matched"
    assert imported.card.cardmarket_product_id == 321
    assert imported.outcome == :imported
    assert imported.card.last_synced_at == ~U[2026-03-01 00:00:00.123456Z]
  end

  test "accepts punctuation card IDs with a strict set ID" do
    card_id = "exu-%3F"
    set_id = "exu"
    card = %{"id" => card_id, "name" => "Question", "localId" => "2", "set" => %{"id" => set_id}}
    set = %{"id" => set_id, "name" => "Destined Rivals"}

    assert {:ok, %{card: %{tcgdex_id: ^card_id}}} =
             Importer.import_fetched_card(card, set, card_id,
               expected_set_id: set_id,
               synced_at: ~U[2026-03-01 00:00:00Z]
             )

    assert {:error, :invalid_options} =
             Importer.import_fetched_card(%{card | "id" => "exu-%GG"}, set, "exu-%GG",
               expected_set_id: set_id,
               synced_at: ~U[2026-03-01 00:00:00Z]
             )
  end

  test "direct import rejects invalid card IDs before provider callbacks" do
    assert {:error, :invalid_id} = Importer.import_card("exu-%GG", provider: __MODULE__)
    assert {:error, :invalid_options} = Importer.import_card("exu-%3F", "bad")
  end

  test "fetched payload identity mismatches happen before any writes" do
    card_id = "fetched-mismatch-#{System.unique_integer([:positive])}"
    set_id = "fetched-mismatch-set-#{System.unique_integer([:positive])}"

    card = %{
      "id" => "different-card",
      "name" => "Fetched Card",
      "localId" => "1",
      "set" => %{"id" => set_id}
    }

    assert {:error, {:malformed_response, {:card_id_mismatch, ^card_id, "different-card"}}} =
             Importer.import_fetched_card(card, %{"id" => set_id, "name" => "Set"}, card_id,
               expected_set_id: set_id,
               synced_at: ~U[2026-03-01 00:00:00Z]
             )

    assert Repo.aggregate(from(c in "card_printings"), :count, :id) == 0
    assert Repo.aggregate(from(s in "card_sets"), :count, :id) == 0
  end

  test "fetched payload requires one valid shared timestamp and known options" do
    card_id = "fetched-options-#{System.unique_integer([:positive])}"
    set_id = "fetched-options-set-#{System.unique_integer([:positive])}"
    card = %{"id" => card_id, "name" => "Card", "localId" => "1", "set" => %{"id" => set_id}}
    set = %{"id" => set_id, "name" => "Set"}

    assert {:error, :invalid_clock} =
             Importer.import_fetched_card(card, set, card_id, expected_set_id: set_id)

    assert {:error, :invalid_clock} =
             Importer.import_fetched_card(card, set, card_id, synced_at: :bad)

    assert {:error, :invalid_options} =
             Importer.import_fetched_card(card, set, "bad id",
               synced_at: ~U[2026-03-01 00:00:00Z]
             )

    assert {:error, :invalid_id} =
             Importer.import_fetched_card(card, set, card_id,
               expected_set_id: "bad id",
               synced_at: ~U[2026-03-01 00:00:00Z]
             )

    assert {:error, :invalid_options} =
             Importer.import_fetched_card(card, set, card_id,
               synced_at: ~U[2026-03-01 00:00:00Z],
               unknown: true
             )

    assert {:error, :invalid_options} =
             Importer.import_fetched_card(card, set, card_id,
               synced_at: ~U[2026-03-01 00:00:00Z],
               synced_at: ~U[2026-03-01 00:00:00Z]
             )

    assert Repo.aggregate(from(c in "card_printings"), :count, :id) == 0
  end

  test "does not reassign an existing card to a different set" do
    card_id = "cross-set-card-#{System.unique_integer([:positive])}"
    foreign_id = "foreign-set-#{System.unique_integer([:positive])}"
    target_id = "target-set-#{System.unique_integer([:positive])}"
    foreign = Core.import_card_set!(%{tcgdex_id: foreign_id, name: "Foreign"})

    TcgCheap.TestSupport.import_card_printing!(%{
      tcgdex_id: card_id,
      name: "Existing",
      set_name: "Foreign",
      collector_number: "1",
      card_set_id: foreign.id,
      source_payload: %{"existing" => true},
      mapping_status: "matched",
      cardmarket_product_id: 999
    })

    card = %{
      "id" => card_id,
      "name" => "Incoming",
      "localId" => "1",
      "set" => %{"id" => target_id}
    }

    assert {:error, {:card_set_conflict, %{tcgdex_id: ^card_id}}} =
             Importer.import_fetched_card(card, %{"id" => target_id, "name" => "Target"}, card_id,
               expected_set_id: target_id,
               synced_at: ~U[2026-03-01 00:00:00Z]
             )

    assert {:ok, retained} = Core.get_card_printing_by_tcgdex_id(card_id)
    assert retained.name == "Existing"
    assert retained.card_set_id == foreign.id
    assert {:error, _} = Core.get_card_set_by_tcgdex_id(target_id)
  end

  test "legacy card without a set link can be linked by fetched import" do
    card_id = "legacy-card-#{System.unique_integer([:positive])}"
    set_id = "legacy-set-#{System.unique_integer([:positive])}"

    legacy =
      Core.create_card_printing!(%{
        tcgdex_id: card_id,
        name: "Legacy",
        set_name: "Set",
        collector_number: "1"
      })

    card = %{"id" => card_id, "name" => "Enriched", "localId" => "1", "set" => %{"id" => set_id}}

    assert {:ok, %{card: imported, outcome: :imported}} =
             Importer.import_fetched_card(card, %{"id" => set_id, "name" => "Set"}, card_id,
               expected_set_id: set_id,
               synced_at: ~U[2026-03-01 00:00:00Z]
             )

    assert imported.id == legacy.id
    assert imported.card_set_id != nil
  end

  test "stale cross-set payload still conflicts before stale preservation" do
    card_id = "stale-cross-card-#{System.unique_integer([:positive])}"
    foreign_id = "stale-foreign-set-#{System.unique_integer([:positive])}"
    target_id = "stale-target-set-#{System.unique_integer([:positive])}"
    foreign = Core.import_card_set!(%{tcgdex_id: foreign_id, name: "Foreign"})

    TcgCheap.TestSupport.import_card_printing!(%{
      tcgdex_id: card_id,
      name: "Authoritative",
      set_name: "Foreign",
      collector_number: "1",
      card_set_id: foreign.id,
      source_updated_at: ~U[2026-03-01 00:00:00Z],
      source_payload: %{"authoritative" => true},
      mapping_status: "matched",
      cardmarket_product_id: 77
    })

    card = %{
      "id" => card_id,
      "name" => "Stale Incoming",
      "localId" => "1",
      "updated" => "2026-02-01T00:00:00Z",
      "set" => %{"id" => target_id}
    }

    assert {:error, {:card_set_conflict, %{tcgdex_id: ^card_id}}} =
             Importer.import_fetched_card(card, %{"id" => target_id, "name" => "Target"}, card_id,
               expected_set_id: target_id,
               synced_at: ~U[2026-03-02 00:00:00Z]
             )

    assert {:ok, retained} = Core.get_card_printing_by_tcgdex_id(card_id)
    assert retained.name == "Authoritative"
    assert retained.card_set_id == foreign.id
    assert {:error, _} = Core.get_card_set_by_tcgdex_id(target_id)
  end

  defp restore_env(key, nil), do: Application.delete_env(:tcg_cheap, key)
  defp restore_env(key, value), do: Application.put_env(:tcg_cheap, key, value)
end
