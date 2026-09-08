defmodule TcgCheap.Pricing.CardmarketBulk.Sync do
  @moduledoc "Fetches Cardmarket bulk data and promotes it under an advisory lock."

  alias TcgCheap.Pricing.CardmarketBulk.{Adapter, Batch, Price, Product, RawResponse}
  alias TcgCheap.Repo

  @policy "cardmarket_bulk_v1"
  @parser "cardmarket_bulk_adapter_v1"
  @products_url "https://downloads.s3.cardmarket.com/productCatalog/productList/products_singles_6.json"
  @prices_url "https://downloads.s3.cardmarket.com/productCatalog/priceGuide/price_guide_6.json"
  @batch_size 500
  @transaction_timeout 900_000
  @cleanup_margin 30_000
  @lock_key 3_784_291
  @allowed_options [
    :adapter,
    :adapter_options,
    :request_admitter,
    :clock,
    :completion_clock,
    :after_stage,
    :deadline,
    :monotonic_clock
  ]

  def policy_version, do: @policy

  def run(opts \\ [])

  def run(opts) when is_list(opts) do
    adapter = Keyword.get(opts, :adapter, Adapter)

    with :ok <- validate_options(opts, adapter),
         :ok <- validate_adapter_option(adapter),
         {:ok, products} <-
           deadline_fetch(
             opts,
             fn -> adapter.fetch_products(adapter_call_options(opts)) end,
             :fetch_products
           ),
         {:ok, prices} <-
           deadline_fetch(
             opts,
             fn -> adapter.fetch_prices(adapter_call_options(opts)) end,
             :fetch_prices
           ),
         :ok <- valid_result(products),
         :ok <- valid_result(prices),
         :ok <- valid_clock_order(products, prices),
         :ok <- exact_ids(products.rows, prices.rows),
         :ok <- plausibility_check(products, prices),
         :ok <- before_deadline(opts) do
      prepare_and_promote(products, prices, opts) |> normalize_result()
    end
  rescue
    error -> {:error, {:persistence, error}}
  end

  def run(_), do: {:error, :invalid_options}

  defp normalize_result({:error, %Ash.Error.Unknown.UnknownError{value: [error: reason]}}),
    do: {:error, reason}

  defp normalize_result(result), do: result

  defp validate_options(opts, adapter) do
    with :ok <- validate_plausibility_config(),
         :ok <- validate_option_keys(opts),
         :ok <- validate_adapter(adapter),
         :ok <- validate_function_options(opts),
         :ok <- validate_after_stage(opts),
         :ok <- validate_anomaly_config() do
      validate_deadline_option(opts)
    end
  end

  defp validate_plausibility_config do
    if valid_plausibility_config?(), do: :ok, else: {:error, :invalid_configuration}
  end

  defp valid_plausibility_config? do
    value = Application.get_env(:tcg_cheap, :cardmarket_bulk_plausibility)

    Keyword.keyword?(value) and valid_plausibility_keys?(Keyword.keys(value)) and
      Enum.all?(value, &valid_plausibility_floor?/1)
  end

  defp valid_plausibility_keys?(keys) do
    expected = [
      :minimum_product_rows,
      :minimum_singles_price_rows,
      :minimum_priceable_singles_rows
    ]

    length(keys) == length(expected) and
      length(Enum.uniq(keys)) == length(expected) and
      Enum.sort(keys) == Enum.sort(expected)
  end

  defp valid_plausibility_floor?({_key, floor}), do: is_integer(floor) and floor >= 1

  defp validate_option_keys(opts) do
    adapter_options = Keyword.get(opts, :adapter_options, [])

    if valid_keyword?(opts, @allowed_options) and
         valid_keyword?(adapter_options, [:request_options]) do
      :ok
    else
      {:error, :invalid_options}
    end
  end

  defp validate_adapter_option(adapter) when is_atom(adapter), do: validate_adapter(adapter)

  defp validate_adapter_option(_adapter), do: {:error, :invalid_options}

  defp validate_function_options(opts) do
    if valid_function_options?(opts), do: :ok, else: {:error, :invalid_options}
  end

  defp validate_after_stage(opts) do
    callback = Keyword.get(opts, :after_stage)

    if is_nil(callback) or is_function(callback, 1), do: :ok, else: {:error, :invalid_options}
  end

  defp validate_anomaly_config do
    if valid_anomaly_config?(), do: :ok, else: {:error, :invalid_options}
  end

  defp validate_deadline_option(opts) do
    if valid_deadline_options?(opts), do: :ok, else: {:error, :invalid_options}
  end

  defp valid_deadline_options?(opts) do
    deadline = Keyword.get(opts, :deadline)
    clock = Keyword.get(opts, :monotonic_clock, &:erlang.monotonic_time/1)

    (is_nil(deadline) or is_integer(deadline)) and
      (is_nil(deadline) or is_function(clock, 0) or is_function(clock, 1))
  end

  defp valid_anomaly_config? do
    bound =
      Application.get_env(:tcg_cheap, :cardmarket_bulk, [])
      |> Keyword.get(:row_count_anomaly_bound, 0.10)

    is_number(bound) and bound >= 0 and bound <= 1
  end

  defp valid_keyword?(value, allowed),
    do:
      Keyword.keyword?(value) and Keyword.keys(value) == Enum.uniq(Keyword.keys(value)) and
        Enum.all?(Keyword.keys(value), &(&1 in allowed))

  defp valid_function_options?(opts),
    do:
      is_function(Keyword.get(opts, :request_admitter, fn -> :ok end), 0) and
        is_function(Keyword.get(opts, :clock, &DateTime.utc_now/0), 0) and
        is_function(Keyword.get(opts, :completion_clock, &DateTime.utc_now/0), 0)

  defp validate_adapter(adapter),
    do:
      if(
        function_exported?(adapter, :fetch_products, 1) and
          function_exported?(adapter, :fetch_prices, 1),
        do: :ok,
        else: {:error, :invalid_configuration}
      )

  defp safe_fetch(request, function) do
    case request.() do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, reason}
      _ -> {:error, {:provider_callback_error, function, :invalid_result}}
    end
  rescue
    _ -> {:error, {:provider_callback_error, function, :adapter_exception}}
  catch
    _, _ -> {:error, {:provider_callback_error, function, :adapter_exception}}
  end

  defp deadline_fetch(opts, request, function) do
    case before_deadline(opts) do
      :ok -> safe_fetch(request, function)
      {:error, _} = error -> error
    end
  end

  defp valid_result(%Adapter{
         raw_body: body,
         sha256: sha,
         fetched_at: fetched,
         created_at: created,
         rows: rows
       })
       when is_binary(body) and is_binary(sha) and is_struct(fetched, DateTime) and
              is_struct(created, DateTime) and is_list(rows),
       do: :ok

  defp valid_result(_), do: {:error, {:malformed, :provider_response}}

  defp adapter_call_options(opts),
    do:
      opts
      |> Keyword.get(:adapter_options, [])
      |> Keyword.put(:request_admitter, Keyword.get(opts, :request_admitter, fn -> :ok end))
      |> Keyword.put(:clock, Keyword.get(opts, :clock, &DateTime.utc_now/0))

  defp prepare_and_promote(products, prices, opts) do
    transaction(opts, [Batch, RawResponse], fn ->
      lock!()

      with :ok <- source_not_stale(products, prices),
           :ok <- anomaly_check(products, prices),
           {:ok, batch} <- get_or_stage(products, prices, opts) do
        batch
      else
        {:error, reason} -> Ash.DataLayer.rollback([Batch, RawResponse], {:error, reason})
      end
    end)
    |> case do
      {:ok, batch, notifications} ->
        Ash.Notifier.notify(notifications)
        promote(batch, products, prices, opts)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp transaction(opts, resources, fun) do
    case transaction_timeout(opts) do
      {:error, reason} ->
        {:error, reason}

      {:ok, timeout} ->
        Ash.transact(
          resources,
          fun,
          timeout: timeout,
          return_notifications?: true
        )
    end
  end

  defp promote(batch, products, prices, opts) do
    result =
      transaction(opts, [Batch, RawResponse, Product, Price], fn ->
        lock!()
        batch = read_identity!(products, prices)

        with :ok <- source_not_stale(products, prices),
             :ok <- anomaly_check(products, prices) do
          promote_batch_or_rollback(batch, products, prices, opts)
        else
          {:error, reason} ->
            Ash.DataLayer.rollback([Batch, RawResponse, Product, Price], {:error, reason})
        end
      end)

    case result do
      {:ok, {:noop, batch}, notifications} ->
        Ash.Notifier.notify(notifications)
        {:ok, %{batch: batch, persisted?: false}}

      {:ok, {:done, batch}, notifications} ->
        Ash.Notifier.notify(notifications)
        {:ok, %{batch: batch, persisted?: true}}

      {:error, reason} ->
        _ = mark_failed(batch, reason, opts)
        {:error, reason}
    end
  end

  defp promote_batch_or_rollback(batch, products, prices, opts) do
    case promote_batch(batch, products, prices, opts) do
      {:error, reason} ->
        Ash.DataLayer.rollback([Batch, RawResponse, Product, Price], {:error, reason})

      result ->
        result
    end
  end

  defp promote_batch(%Batch{status: "succeeded"} = batch, _products, _prices, _opts),
    do: {:noop, batch}

  defp promote_batch(batch, products, prices, opts) do
    with {:ok, _} <- stage(Product, product_inputs(products.rows, batch)),
         {:ok, _} <- stage(Price, price_inputs(prices.rows, batch)),
         :ok <- invoke_after_stage(opts, batch),
         {:ok, completed_at} <- completion_time(opts),
         {:ok, succeeded} <- succeed(batch, completed_at) do
      {:done, succeeded}
    end
  end

  defp succeed(batch, completed_at) do
    Ash.update(batch, %{completed_at: completed_at}, action: :succeed, authorize?: false)
  end

  defp get_or_stage(products, prices, _opts) do
    identity = [
      policy_version: @policy,
      product_created_at: products.created_at,
      price_created_at: prices.created_at,
      product_sha256: products.sha256,
      price_sha256: prices.sha256
    ]

    case Ash.read_one(Ash.Query.for_read(Batch, :by_identity, identity), authorize?: false) do
      {:ok, %Batch{} = batch} ->
        {:ok, batch}

      {:ok, nil} ->
        attrs =
          Map.merge(Map.new(identity), %{
            parser_version: @parser,
            fetched_at: later(products.fetched_at, prices.fetched_at),
            product_byte_size: products.byte_size,
            price_byte_size: prices.byte_size,
            product_row_count: products.total_rows,
            price_row_count: prices.total_rows,
            singles_price_row_count: length(prices.rows),
            priceable_singles_count: prices.priceable_count
          })

        with {:ok, batch} <-
               Ash.create(Ash.Changeset.for_create(Batch, :stage, attrs),
                 authorize?: false
               ),
             {:ok, _} <- store_raw_if_new(batch, products, "products", @products_url),
             {:ok, _} <- store_raw(batch, prices, "prices", @prices_url) do
          {:ok, batch}
        else
          {:error, reason} -> Ash.DataLayer.rollback([Batch, RawResponse], {:error, reason})
        end

      {:error, reason} ->
        Ash.DataLayer.rollback([Batch, RawResponse], {:error, reason})
    end
  end

  defp store_raw_if_new(batch, result, kind, url) do
    case kind do
      kind when kind in ["products", "prices"] -> store_raw_lookup(batch, result, kind, url)
      _ -> {:error, :invalid_endpoint_kind}
    end
  end

  defp store_raw_lookup(batch, result, kind, url) do
    query =
      Ash.Query.for_read(RawResponse, :by_sha256, %{
        endpoint_kind: kind,
        sha256: result.sha256
      })

    case Ash.read_one(query, authorize?: false) do
      {:ok, %RawResponse{endpoint_kind: "products"}} when kind == "products" -> {:ok, []}
      {:ok, nil} -> store_raw(batch, result, kind, url)
      {:ok, %RawResponse{}} -> store_raw(batch, result, kind, url)
      {:error, reason} -> {:error, {:raw_lookup_failed, reason}}
      _ -> {:error, :raw_lookup_failed}
    end
  end

  defp store_raw(batch, result, kind, url) do
    body = :zlib.gzip(result.raw_body)

    case Ash.create(
           Ash.Changeset.for_create(RawResponse, :store, %{
             batch_id: batch.id,
             endpoint_kind: kind,
             source_url: url,
             source_byte_size: byte_size(result.raw_body),
             compressed_byte_size: byte_size(body),
             sha256: result.sha256,
             body: body,
             fetched_at: result.fetched_at,
             upstream_created_at: result.created_at
           }),
           authorize?: false
         ) do
      {:ok, record} -> {:ok, record}
      error -> error
    end
  end

  defp source_not_stale(products, prices) do
    case Ash.read_one(Ash.Query.for_read(Batch, :latest_successful), authorize?: false) do
      {:ok, nil} ->
        :ok

      {:ok, b} ->
        stale_source_error(products, prices, b)

      {:error, r} ->
        {:error, {:persistence, r}}
    end
  end

  defp stale_source_error(products, prices, batch) do
    cond do
      DateTime.compare(products.created_at, batch.product_created_at) == :lt ->
        {:error, {:stale_source_batch, :products}}

      DateTime.compare(prices.created_at, batch.price_created_at) == :lt ->
        {:error, {:stale_source_batch, :prices}}

      true ->
        :ok
    end
  end

  defp anomaly_check(products, prices) do
    case Ash.read_one(Ash.Query.for_read(Batch, :latest_successful), authorize?: false) do
      {:ok, nil} ->
        :ok

      {:ok, b} ->
        Enum.find_value(
          [
            {products.total_rows, b.product_row_count, :product_row_count},
            {prices.total_rows, b.price_row_count, :price_row_count},
            {length(prices.rows), b.singles_price_row_count, :singles_price_row_count},
            {prices.priceable_count, b.priceable_singles_count, :priceable_singles_count}
          ],
          :ok,
          &anomaly_for/1
        )

      _ ->
        {:error, {:malformed, :provider_response}}
    end
  end

  defp anomaly_for({new, old, key}) when old > 0 do
    if abs(new - old) / old > anomaly_bound(),
      do: {:error, {:malformed, {:row_count_anomaly, key}}}
  end

  defp anomaly_for(_), do: nil

  defp anomaly_bound,
    do:
      Application.get_env(:tcg_cheap, :cardmarket_bulk, [])
      |> Keyword.get(:row_count_anomaly_bound, 0.10)

  defp lock!, do: Repo.query!("SELECT pg_advisory_xact_lock($1)", [@lock_key])

  defp plausibility_check(products, prices) do
    floors = Application.fetch_env!(:tcg_cheap, :cardmarket_bulk_plausibility)

    counts = [
      {products.source_rows, :minimum_product_rows},
      {length(prices.rows), :minimum_singles_price_rows},
      {prices.priceable_count, :minimum_priceable_singles_rows}
    ]

    case Enum.find(counts, fn {count, key} -> count < Keyword.fetch!(floors, key) end) do
      nil ->
        :ok

      {count, key} ->
        {:error, {:malformed, {:row_count_below_floor, key, count, Keyword.fetch!(floors, key)}}}
    end
  end

  defp before_deadline(opts) do
    case remaining_work_ms(opts) do
      nil -> :ok
      remaining when remaining > 0 -> :ok
      _ -> {:error, :deadline_exceeded}
    end
  end

  defp transaction_timeout(opts) do
    case remaining_work_ms(opts) do
      nil -> {:ok, @transaction_timeout}
      remaining when remaining > 0 -> {:ok, min(remaining, @transaction_timeout)}
      _ -> {:error, :deadline_exceeded}
    end
  end

  defp remaining_work_ms(opts) do
    case Keyword.get(opts, :deadline) do
      nil -> nil
      deadline -> deadline - monotonic_ms(opts) - @cleanup_margin
    end
  end

  defp monotonic_ms(opts),
    do: monotonic_ms(Keyword.get(opts, :monotonic_clock, &:erlang.monotonic_time/1), opts)

  defp monotonic_ms(clock, _opts) when is_function(clock, 0), do: clock.()
  defp monotonic_ms(clock, _opts) when is_function(clock, 1), do: clock.(:millisecond)

  defp read_identity!(%Batch{} = batch, %Batch{}) do
    Ash.read_one!(
      Ash.Query.for_read(Batch, :by_identity,
        policy_version: batch.policy_version,
        product_created_at: batch.product_created_at,
        price_created_at: batch.price_created_at,
        product_sha256: batch.product_sha256,
        price_sha256: batch.price_sha256
      ),
      authorize?: false
    )
  end

  defp read_identity!(p, q),
    do:
      Ash.read_one!(
        Ash.Query.for_read(Batch, :by_identity,
          policy_version: @policy,
          product_created_at: p.created_at,
          price_created_at: q.created_at,
          product_sha256: p.sha256,
          price_sha256: q.sha256
        ),
        authorize?: false
      )

  defp invoke_after_stage(opts, batch) do
    case Keyword.get(opts, :after_stage) do
      nil ->
        :ok

      callback ->
        case callback.(batch) do
          :ok -> :ok
          {:ok, _} -> :ok
          {:error, reason} -> {:error, reason}
          _ -> {:error, :after_stage_failed}
        end
    end
  rescue
    _ -> {:error, :after_stage_failed}
  end

  defp mark_failed(batch, reason, opts) do
    case Ash.transact(
           Batch,
           fn ->
             lock!()
             batch |> read_identity!() |> mark_current_failed(reason)
           end,
           timeout: failure_timeout(opts),
           return_notifications?: true
         ) do
      {:ok, result, notifications} ->
        Ash.Notifier.notify(notifications)
        {:ok, result}

      error ->
        error
    end
  end

  defp failure_timeout(opts) do
    case Keyword.get(opts, :deadline) do
      nil -> @transaction_timeout
      deadline -> max(1, min(@cleanup_margin, deadline - monotonic_ms(opts)))
    end
  end

  defp read_identity!(%Batch{} = batch), do: read_identity!(batch, batch)

  defp mark_current_failed(%Batch{status: "succeeded"}, _reason), do: :ok

  defp mark_current_failed(current, reason) do
    attrs = %{
      completed_at: failure_time(current.fetched_at),
      failure_summary: failure_summary(reason)
    }

    case Ash.update(current, attrs, action: :fail, authorize?: false) do
      {:ok, _} -> :ok
      {:error, _} -> :failed
    end
  end

  defp failure_time(fetched_at) do
    now = DateTime.utc_now()
    if DateTime.compare(now, fetched_at) == :lt, do: fetched_at, else: now
  end

  defp failure_summary(_), do: "cardmarket bulk pipeline failed"

  defp completion_time(opts) do
    case Keyword.get(opts, :completion_clock, &DateTime.utc_now/0).() do
      %DateTime{time_zone: "Etc/UTC"} = value -> {:ok, value}
      _ -> {:error, {:malformed, :invalid_completion_clock}}
    end
  rescue
    _ -> {:error, {:malformed, :invalid_completion_clock}}
  end

  defp later(a, b), do: if(DateTime.compare(a, b) == :lt, do: b, else: a)

  defp valid_clock_order(a, b),
    do:
      if(
        DateTime.compare(a.created_at, a.fetched_at) != :gt and
          DateTime.compare(b.created_at, b.fetched_at) != :gt,
        do: :ok,
        else: {:error, {:malformed, :future_source_timestamp}}
      )

  defp exact_ids(a, b),
    do:
      if(MapSet.equal?(MapSet.new(a, & &1.id_product), MapSet.new(b, & &1.id_product)),
        do: :ok,
        else: {:error, {:identity_mismatch, length(a), length(b), %{}}}
      )

  defp product_inputs(rows, batch),
    do:
      Stream.map(rows, fn r ->
        %{
          cardmarket_product_id: r.id_product,
          name: r.name,
          category_id: r.category_id,
          category_name: r.category,
          expansion_id: r.id_expansion,
          metacard_id: r.id_metacard,
          source_date_added: r.date_added,
          last_batch_id: batch.id,
          source_updated_at: batch.product_created_at
        }
      end)

  defp price_inputs(rows, batch),
    do:
      Stream.map(rows, fn r ->
        %{
          cardmarket_product_id: r.id_product,
          category_id: r.category_id,
          avg: r.avg,
          low: r.low,
          trend: r.trend,
          avg1: r.avg1,
          avg7: r.avg7,
          avg30: r.avg30,
          avg_holo: r.avg_holo,
          low_holo: r.low_holo,
          trend_holo: r.trend_holo,
          avg1_holo: r.avg1_holo,
          avg7_holo: r.avg7_holo,
          avg30_holo: r.avg30_holo,
          selected_metric: metric_name(r.selected_metric),
          selected_value_eur: r.selected_value,
          last_batch_id: batch.id,
          source_updated_at: batch.price_created_at
        }
      end)

  defp metric_name(nil), do: nil
  defp metric_name(m) when is_atom(m), do: Atom.to_string(m)
  defp metric_name(m) when is_binary(m), do: m
  defp metric_name(_), do: nil

  defp stage(resource, inputs),
    do:
      inputs
      |> Stream.chunk_every(@batch_size)
      |> Enum.reduce_while({:ok, 0}, fn chunk, {:ok, n} ->
        case Ash.bulk_create(chunk, resource, :upsert,
               domain: TcgCheap.Core,
               authorize?: false,
               notify?: false,
               return_records?: false,
               transaction: false,
               batch_size: @batch_size,
               upsert?: true,
               upsert_identity: :unique_cardmarket_product_id,
               upsert_fields: resource_upsert_fields(resource)
             ) do
          %Ash.BulkResult{status: :success, errors: e} when e in [nil, []] ->
            {:cont, {:ok, n + length(chunk)}}

          _other ->
            {:halt, {:error, {:bulk_persistence, :unexpected_result}}}
        end
      end)

  defp resource_upsert_fields(Product),
    do: [
      :name,
      :category_id,
      :category_name,
      :expansion_id,
      :metacard_id,
      :source_date_added,
      :last_batch_id,
      :source_updated_at
    ]

  defp resource_upsert_fields(Price),
    do: [
      :category_id,
      :avg,
      :low,
      :trend,
      :avg1,
      :avg7,
      :avg30,
      :avg_holo,
      :low_holo,
      :trend_holo,
      :avg1_holo,
      :avg7_holo,
      :avg30_holo,
      :selected_metric,
      :selected_value_eur,
      :last_batch_id,
      :source_updated_at
    ]
end
