defmodule TcgCheap.Catalogue.SinglesCatalogueBootstrapWorkerTest do
  use TcgCheap.DataCase, async: false

  import Oban.Testing

  alias TcgCheap.Catalogue.{
    CardDetailEnrichmentWorker,
    SinglesCatalogueBootstrapWorker,
    SinglesEnrichmentBootstrapWorker
  }

  alias TcgCheap.Core

  setup do
    previous = Application.get_env(:tcg_cheap, :catalogue_sync)

    Application.put_env(:tcg_cheap, :catalogue_sync,
      provider: TcgCheap.Catalogue.SinglesCatalogueBootstrapWorkerTest.Provider,
      provider_options: [],
      batch_size: 1,
      batch_delay_seconds: 900,
      budget_backoff_seconds: 3600
    )

    on_exit(fn -> restore(:catalogue_sync, previous) end)
    :ok
  end

  test "weekly perform enqueues exact catalogue and detail bootstrap jobs" do
    assert :ok = SinglesCatalogueBootstrapWorker.perform(job(%{"policy_version" => 1}))

    assert_enqueued(
      repo: TcgCheap.Repo,
      worker: TcgCheap.Catalogue.CatalogueSyncWorker,
      args: %{"scope" => "all_sets"}
    )

    assert_enqueued(
      repo: TcgCheap.Repo,
      worker: SinglesEnrichmentBootstrapWorker,
      args: %{"policy_version" => 1}
    )
  end

  test "detail bootstrap performs the lexical first candidate with continuation and priority five" do
    set = Core.import_card_set!(%{tcgdex_id: "bootstrap-set", name: "Set", series_id: "sv"})
    first = import_card(set, "a-bootstrap")
    _later = import_card(set, "z-bootstrap")

    assert :ok = SinglesEnrichmentBootstrapWorker.perform(job(%{"policy_version" => 1}))

    assert_enqueued(
      repo: TcgCheap.Repo,
      worker: CardDetailEnrichmentWorker,
      args: %{"local_card_id" => first.id, "tcgdex_id" => first.tcgdex_id, "continue" => true},
      priority: 5
    )
  end

  test "malformed detail bootstrap arguments cancel" do
    assert {:cancel, :malformed_job_args} = SinglesEnrichmentBootstrapWorker.perform(job(%{}))

    assert {:cancel, :malformed_job_args} =
             SinglesCatalogueBootstrapWorker.perform(job(%{"policy_version" => 2}))
  end

  test "completed weekly bootstrap uniqueness includes completed jobs for seven days" do
    unique =
      Ecto.Changeset.get_field(
        SinglesCatalogueBootstrapWorker.new(%{"policy_version" => 1}),
        :unique
      )

    assert unique.period == 7 * 24 * 60 * 60
    assert :completed in unique.states
  end

  defmodule Provider do
    def fetch_card(_, _), do: {:error, :unused}
    def fetch_set(_, _), do: {:error, :unused}
    def list_sets(_), do: {:ok, []}
  end

  defp import_card(set, id),
    do:
      TcgCheap.TestSupport.import_card_printing!(
        %{
          tcgdex_id: id,
          name: "Brief",
          set_name: set.name,
          collector_number: "1",
          card_set_id: set.id
        },
        scoped?: false
      )

  defp job(args),
    do: %Oban.Job{
      id: System.unique_integer([:positive]),
      attempt: 1,
      max_attempts: 5,
      worker: "TcgCheap.Catalogue.SinglesCatalogueBootstrapWorker",
      queue: "catalogue_sync",
      args: args
    }

  defp restore(key, nil), do: Application.delete_env(:tcg_cheap, key)
  defp restore(key, value), do: Application.put_env(:tcg_cheap, key, value)
end
