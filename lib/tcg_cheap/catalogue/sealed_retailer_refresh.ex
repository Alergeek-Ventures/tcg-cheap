defmodule TcgCheap.Catalogue.SealedRetailerRefresh do
  @moduledoc "Fetches, validates, and atomically ingests one retailer's listing batch."

  alias TcgCheap.Catalogue.{ListingProductMappingImporter, Retailer, SealedRetailerAdapter}
  alias TcgCheap.Core
  alias TcgCheap.Repo

  defmodule Result do
    @moduledoc "A completed retailer refresh summary."
    @enforce_keys [:retailer_id, :source_key, :fetched, :persisted, :checked_at]
    defstruct [:retailer_id, :source_key, :fetched, :persisted, :checked_at]

    @type t :: %__MODULE__{
            retailer_id: String.t(),
            source_key: String.t(),
            fetched: non_neg_integer(),
            persisted: non_neg_integer(),
            checked_at: DateTime.t() | nil
          }
  end

  @max_batch 1_000

  @spec refresh(String.t(), String.t(), module(), keyword()) ::
          {:ok, Result.t()} | {:error, term()}
  def refresh(retailer_id, source_key, adapter, options) do
    with {:ok, retailer} <- canonical_retailer(retailer_id, source_key),
         {:ok, fetched} <- safely_fetch(adapter, retailer, options),
         {:ok, listings} <- validate_batch(fetched),
         {:ok, persisted} <- persist(retailer.id, source_key, listings) do
      {:ok,
       %Result{
         retailer_id: retailer.id,
         source_key: source_key,
         fetched: length(listings),
         persisted: persisted,
         checked_at: latest_check(listings)
       }}
    end
  end

  def canonical_retailer(retailer_id, source_key) do
    with {:ok, retailer} <- Core.get_retailer_by_source_key(source_key),
         true <- retailer.id == retailer_id,
         true <- retailer.status == "active",
         true <- canonical_source?(retailer, source_key) do
      {:ok, retailer}
    else
      {:error, error} -> classify_retailer_lookup(error)
      _ -> {:error, :retailer_not_active_or_mismatched}
    end
  end

  defp canonical_source?(%Retailer{source_key: source_key}, source_key), do: true
  defp canonical_source?(_, _), do: false

  defp classify_retailer_lookup(%Ash.Error.Invalid{errors: errors}) when errors != [] do
    if Enum.all?(errors, &match?(%Ash.Error.Query.NotFound{}, &1)),
      do: {:error, :retailer_not_found},
      else: {:error, :retailer_lookup_failed}
  end

  defp classify_retailer_lookup(_error), do: {:error, :retailer_lookup_failed}

  defp safely_fetch(adapter, retailer, options) do
    with :ok <- validate_adapter(adapter, retailer) do
      call_adapter(adapter, retailer, options)
    end
  end

  defp validate_adapter(adapter, retailer) when is_atom(adapter) do
    if Code.ensure_loaded?(adapter) and function_exported?(adapter, :fetch_listings, 2) and
         function_exported?(adapter, :source_key, 0) and
         safe_source_key(adapter) == retailer.source_key,
       do: :ok,
       else: {:error, :invalid_provider_configuration}
  end

  defp validate_adapter(_adapter, _retailer), do: {:error, :invalid_provider_configuration}

  defp call_adapter(adapter, retailer, options) do
    case adapter.fetch_listings(retailer, options) do
      {:ok, value} -> {:ok, value}
      {:error, reason} -> {:error, reason}
      _ -> {:error, :malformed_provider_result}
    end
  rescue
    _ -> {:error, :adapter_exception}
  catch
    :throw, _ -> {:error, :adapter_throw}
    :exit, _ -> {:error, :adapter_exit}
  end

  defp safe_source_key(adapter) do
    adapter.source_key()
  rescue
    _ -> nil
  catch
    _, _ -> nil
  end

  defp validate_batch(listings) when is_list(listings) and length(listings) <= @max_batch do
    with {:ok, validated} <- Enum.reduce_while(listings, {:ok, []}, &validate_listing/2),
         true <- unique_ids?(validated) do
      {:ok, Enum.reverse(validated)}
    else
      false -> {:error, :duplicate_source_listing_id}
      error -> error
    end
  end

  defp validate_batch(_), do: {:error, :malformed_batch}

  defp validate_listing(%SealedRetailerAdapter.Listing{} = listing, {:ok, acc}) do
    case SealedRetailerAdapter.new(Map.from_struct(listing)) do
      {:ok, value} -> {:cont, {:ok, [value | acc]}}
      {:error, _} -> {:halt, {:error, :malformed_listing}}
    end
  end

  defp validate_listing(_, _), do: {:halt, {:error, :malformed_listing}}

  defp unique_ids?(listings),
    do:
      length(Enum.map(listings, & &1.source_listing_id)) ==
        length(Enum.uniq_by(listings, & &1.source_listing_id))

  defp persist(retailer_id, source_key, listings) do
    case Repo.transaction(fn -> persist_all(retailer_id, source_key, listings) end) do
      {:ok, {persisted, notifications}} ->
        Ash.Notifier.notify(notifications)
        {:ok, persisted}

      {:error, {:invalid, _error}} ->
        {:error, :persistence_invalid}

      {:error, :retailer_not_active_or_mismatched} ->
        {:error, :retailer_not_active_or_mismatched}

      {:error, {:persistence_db_failure, _reason}} ->
        {:error, :persistence_failed}

      {:error, %Ash.Changeset{}} ->
        {:error, :persistence_invalid}

      {:error, %Ash.Error.Invalid{}} ->
        {:error, :persistence_invalid}

      {:error, _reason} ->
        {:error, :persistence_failed}
    end
  rescue
    _ -> {:error, :persistence_failed}
  catch
    _, _ -> {:error, :persistence_failed}
  end

  defp persist_all(retailer_id, source_key, listings) do
    with :ok <- lock_active_retailer(retailer_id, source_key) do
      persist_listings(retailer_id, listings)
    end
  end

  defp lock_active_retailer(retailer_id, source_key) do
    case Repo.query(
           "SELECT id FROM retailers WHERE id = $1::uuid AND source_key = $2 AND status = 'active' FOR UPDATE",
           [Ecto.UUID.dump!(retailer_id), source_key]
         ) do
      {:ok, %{num_rows: 1}} -> :ok
      {:ok, %{num_rows: 0}} -> Repo.rollback(:retailer_not_active_or_mismatched)
      {:error, reason} -> Repo.rollback({:persistence_db_failure, reason})
    end
  end

  defp persist_listings(retailer_id, listings) do
    Enum.reduce(listings, {0, []}, fn listing, {count, notifications} ->
      {persisted, action_notifications, mapping_notifications} =
        persist_listing(retailer_id, listing)

      {count + persisted, [action_notifications, mapping_notifications | notifications]}
    end)
    |> then(fn {count, notifications} -> {count, Enum.flat_map(notifications, & &1)} end)
  end

  defp persist_listing(retailer_id, listing) do
    attrs =
      listing
      |> Map.from_struct()
      |> Map.put(:retailer_id, retailer_id)
      |> Map.delete(:normalized_title)

    with {:ok, stored_listing, action_notifications} <-
           Core.ingest_retailer_listing(attrs, return_notifications?: true),
         {:ok, _mapping, mapping_notifications} <-
           ListingProductMappingImporter.ensure(stored_listing) do
      {1, action_notifications, mapping_notifications}
    else
      {:error, %Ash.Error.Invalid{} = error} ->
        Repo.rollback({:invalid, error})

      {:error, %Ash.Changeset{} = changeset} ->
        Repo.rollback({:invalid, changeset})

      {:error, error} ->
        Repo.rollback(error)
    end
  end

  defp latest_check([]), do: nil
  defp latest_check(listings), do: Enum.max_by(listings, & &1.last_checked_at).last_checked_at
end
