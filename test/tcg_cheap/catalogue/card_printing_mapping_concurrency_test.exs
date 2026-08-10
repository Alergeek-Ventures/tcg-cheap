defmodule TcgCheap.Catalogue.CardPrintingMappingConcurrencyTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias TcgCheap.Accounts.Admin
  alias TcgCheap.Catalogue.Importer
  alias TcgCheap.Core
  alias TcgCheap.Repo

  setup do
    {card, admin} =
      Sandbox.unboxed_run(Repo, fn ->
        suffix = System.unique_integer([:positive])
        email = "card-mapping-race-#{suffix}@example.test"

        {:ok, %{rows: [[admin_id]]}} =
          Repo.query(
            "INSERT INTO admins (id, email, hashed_password) VALUES (gen_random_uuid(), $1, 'test') RETURNING id",
            [email]
          )

        card =
          TcgCheap.TestSupport.import_card_printing!(%{
            tcgdex_id: "card-mapping-race-#{suffix}",
            name: "Race card",
            set_name: "Race set",
            collector_number: "1",
            mapping_status: "matched",
            cardmarket_product_id: 123
          })

        {card, %Admin{id: admin_id, email: email}}
      end)

    on_exit(fn -> cleanup(card, admin.id) end)
    {:ok, card: card, admin: admin}
  end

  test "a correction racing an old-mapping valuation cannot leave it current", %{
    card: card,
    admin: admin
  } do
    record_valuation(card, 123, "10.00")

    results =
      concurrently([
        fn ->
          Core.correct_cardmarket_mapping(
            card,
            %{
              expected_updated_at: card.updated_at,
              cardmarket_product_id: 456,
              reason: "Concurrent correction"
            },
            actor: admin
          )
        end,
        fn -> Core.record_single_valuation(valuation_attrs(card, 123, "11.00")) end
      ])

    assert Enum.any?(results, &match?({:ok, %{cardmarket_product_id: 456}}, &1))

    Sandbox.unboxed_run(Repo, fn ->
      updated = Core.get_card_printing_by_tcgdex_id!(card.tcgdex_id)
      assert {updated.mapping_authority, updated.cardmarket_product_id} == {"administrator", 456}
      assert {:ok, nil} = Core.get_current_single_valuation(card.id, "tcgdex_cardmarket_v1")

      assert {:ok, [%{event: "corrected", cardmarket_product_id: 456}]} =
               Core.list_card_printing_mapping_decision_history(card.id, authorize?: false)

      assert Core.list_single_valuation_history!(card.id, "tcgdex_cardmarket_v1")
             |> Enum.all?(&(not &1.current? and &1.cardmarket_product_id == 123))
    end)
  end

  test "a reopen racing a valuation cannot leave the resolved mapping priced", %{
    card: card,
    admin: admin
  } do
    corrected =
      Sandbox.unboxed_run(Repo, fn ->
        Core.correct_cardmarket_mapping!(
          card,
          %{
            expected_updated_at: card.updated_at,
            cardmarket_product_id: 123,
            reason: "Establish administrator mapping"
          },
          actor: admin
        )
      end)

    record_valuation(corrected, 123, "10.00")

    results =
      concurrently([
        fn ->
          Core.reopen_cardmarket_mapping(
            corrected,
            %{expected_updated_at: corrected.updated_at, reason: "Concurrent review"},
            actor: admin
          )
        end,
        fn -> Core.record_single_valuation(valuation_attrs(corrected, 123, "11.00")) end
      ])

    assert Enum.any?(results, &match?({:ok, %{mapping_status: "review"}}, &1))

    Sandbox.unboxed_run(Repo, fn ->
      updated = Core.get_card_printing_by_tcgdex_id!(card.tcgdex_id)
      assert {updated.mapping_status, updated.cardmarket_product_id} == {"review", nil}
      assert {:ok, nil} = Core.get_current_single_valuation(card.id, "tcgdex_cardmarket_v1")

      assert {:ok, decisions} =
               Core.list_card_printing_mapping_decision_history(card.id, authorize?: false)

      assert Enum.map(decisions, & &1.event) == ["corrected", "reopened"]

      assert Core.list_single_valuation_history!(card.id, "tcgdex_cardmarket_v1")
             |> Enum.all?(&(not &1.current? and &1.cardmarket_product_id == 123))
    end)
  end

  test "an administrator correction racing a provider import converges on one mapping history", %{
    card: card,
    admin: admin
  } do
    record_valuation(card, 123, "10.00")

    [correction_result, import_result] =
      concurrently([
        fn ->
          Core.correct_cardmarket_mapping(
            card,
            %{
              expected_updated_at: card.updated_at,
              cardmarket_product_id: 456,
              reason: "Concurrent administrator evidence"
            },
            actor: admin
          )
        end,
        fn -> provider_import(card, 999) end
      ])

    assert match?({:ok, _}, import_result)

    Sandbox.unboxed_run(Repo, fn ->
      updated = Core.get_card_printing_by_tcgdex_id!(card.tcgdex_id)
      assert {:ok, nil} = Core.get_current_single_valuation(card.id, "tcgdex_cardmarket_v1")

      assert {:ok, decisions} =
               Core.list_card_printing_mapping_decision_history(card.id, authorize?: false)

      case correction_result do
        {:ok, _corrected} ->
          assert {updated.mapping_authority, updated.cardmarket_product_id} ==
                   {"administrator", 456}

          assert Enum.map(decisions, & &1.event) == ["corrected"]

        {:error, _stale} ->
          assert {updated.mapping_authority, updated.cardmarket_product_id} == {"provider", 999}
          assert Enum.map(decisions, & &1.event) == ["provider_updated"]
      end
    end)
  end

  defp concurrently(functions) do
    parent = self()

    tasks =
      Enum.map(functions, fn function ->
        Task.async(fn ->
          send(parent, {:ready, self()})

          receive do
            :go -> Sandbox.unboxed_run(Repo, function)
          end
        end)
      end)

    for _task <- tasks, do: assert_receive({:ready, _pid}, 5_000)
    Enum.each(tasks, &send(&1.pid, :go))
    Enum.map(tasks, &Task.await(&1, 10_000))
  end

  defp record_valuation(card, product_id, value) do
    Sandbox.unboxed_run(Repo, fn ->
      Core.record_single_valuation!(valuation_attrs(card, product_id, value))
    end)
  end

  defp valuation_attrs(card, product_id, value) do
    %{
      card_printing_id: card.id,
      value_eur: Decimal.new(value),
      policy_version: "tcgdex_cardmarket_v1",
      source: "test",
      source_metric: "avg7",
      fetched_at: DateTime.utc_now(),
      cardmarket_product_id: product_id
    }
  end

  defp provider_import(card, product_id) do
    set_id = card.tcgdex_id <> "-set"

    payload = %{
      "id" => card.tcgdex_id,
      "name" => card.name,
      "localId" => card.collector_number,
      "set" => %{"id" => set_id, "name" => card.set_name},
      "updated" => "2026-08-10T10:00:00Z",
      "pricing" => %{"cardmarket" => %{"idProduct" => product_id}}
    }

    Importer.import_fetched_card(
      payload,
      %{"id" => set_id, "name" => card.set_name},
      card.tcgdex_id,
      synced_at: DateTime.utc_now()
    )
  end

  defp cleanup(card, admin_id) do
    Sandbox.unboxed_run(Repo, fn ->
      dumped_card_id = Ecto.UUID.dump!(card.id)

      Repo.query!("DELETE FROM card_printing_mapping_decisions WHERE card_printing_id = $1", [
        dumped_card_id
      ])

      Repo.query!("DELETE FROM single_valuation_snapshots WHERE card_printing_id = $1", [
        dumped_card_id
      ])

      Repo.query!("DELETE FROM card_printings WHERE id = $1", [dumped_card_id])
      Repo.query!("DELETE FROM card_sets WHERE tcgdex_id = $1", [card.tcgdex_id <> "-set"])
      Repo.query!("DELETE FROM admins WHERE id = $1", [dump_uuid!(admin_id)])
    end)
  end

  defp dump_uuid!(<<_::binary-size(16)>> = id), do: id
  defp dump_uuid!(id), do: Ecto.UUID.dump!(id)
end
