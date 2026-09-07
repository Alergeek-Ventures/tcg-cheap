defmodule TcgCheap.Pricing.Singles.ValuationPolicyCacheTestLoader do
  use GenServer

  def start_link(result), do: GenServer.start(__MODULE__, result, name: __MODULE__)
  def load_system, do: GenServer.call(__MODULE__, :load, 5_000)
  def count, do: GenServer.call(__MODULE__, :count)

  @impl true
  def init(result), do: {:ok, %{result: result, count: 0}}

  @impl true
  def handle_call(:count, _from, state), do: {:reply, state.count, state}

  def handle_call({:replace, result}, _from, state),
    do: {:reply, :ok, %{state | result: result}}

  def handle_call(:load, _from, %{result: result, count: count} = state) do
    reply =
      case result do
        {:ok, _} = value ->
          value

        {:error, _} = value ->
          value

        {:slow, delay, value} ->
          Process.sleep(delay)
          value

        :raise ->
          raise "boom"

        :throw ->
          throw(:boom)

        :exit ->
          exit(:boom)
      end

    {:reply, reply, %{state | count: count + 1}}
  end
end

defmodule TcgCheap.Pricing.Singles.ValuationPolicyCacheTest do
  use ExUnit.Case, async: false

  alias TcgCheap.Pricing.Singles.{ValuationPolicy, ValuationPolicyCache}
  alias TcgCheap.Pricing.Singles.ValuationPolicyCacheTestLoader

  @bulk ValuationPolicy.bulk_policy()
  @tcgdex ValuationPolicy.tcgdex_policy()

  setup do
    {:ok, loader} =
      ValuationPolicyCacheTestLoader.start_link({:ok, %{cutover: %{ready?: true}}})

    name = {:global, {:valuation_policy_cache_test, make_ref()}}

    {:ok, cache} =
      ValuationPolicyCache.start_link(name: name, loader: loader_module(), ttl_seconds: 1)

    on_exit(fn ->
      if Process.alive?(cache), do: GenServer.stop(cache)
      if Process.alive?(loader), do: GenServer.stop(loader)
    end)

    {:ok, name: name}
  end

  test "serializes concurrent misses and caches within the TTL", %{name: name} do
    assert Enum.all?(
             Task.await_many(
               for _ <- 1..20, do: Task.async(fn -> ValuationPolicyCache.selection(name) end)
             ),
             &(&1 == @bulk)
           )

    assert ValuationPolicyCacheTestLoader.count() == 1
    assert ValuationPolicyCache.selection(name) == @bulk
    assert ValuationPolicyCacheTestLoader.count() == 1
  end

  test "invalidation forces a reload", %{name: name} do
    assert ValuationPolicyCache.selection(name) == @bulk
    assert :ok = ValuationPolicyCache.invalidate(name)
    assert ValuationPolicyCache.selection(name) == @bulk
    assert ValuationPolicyCacheTestLoader.count() == 2
  end

  test "refreshes an expired policy and broadcasts only when it changes", %{name: name} do
    assert :ok = ValuationPolicyCache.subscribe()
    assert ValuationPolicyCache.selection(name) == @bulk
    assert_receive :valuation_policy_invalidated, 1_000

    :ok =
      GenServer.call(
        ValuationPolicyCacheTestLoader,
        {:replace, {:ok, %{cutover: %{ready?: false}}}}
      )

    assert_receive :valuation_policy_invalidated, 1_500
    assert ValuationPolicyCache.selection(name) == @tcgdex
    assert ValuationPolicyCacheTestLoader.count() == 2
  end

  for {label, result} <- [
        not_ready: {:ok, %{cutover: %{ready?: false}}},
        error: {:error, :unavailable},
        malformed: {:ok, %{cutover: :bad}},
        raised: :raise,
        thrown: :throw,
        exited: :exit
      ] do
    test "#{label} loader result fails closed", %{name: name} do
      loader = ValuationPolicyCacheTestLoader
      :ok = GenServer.call(loader, {:replace, unquote(Macro.escape(result))})
      assert ValuationPolicyCache.selection(name) == @tcgdex
    end
  end

  test "missing process fails closed" do
    assert ValuationPolicyCache.selection(:missing_valuation_policy_cache) == @tcgdex
    assert ValuationPolicyCache.invalidate(:missing_valuation_policy_cache) == :ok
  end

  test "reconciles a timed-out on-demand load when it later completes", %{name: name} do
    :ok = ValuationPolicyCache.subscribe()

    :ok =
      GenServer.call(
        ValuationPolicyCacheTestLoader,
        {:replace, {:slow, 2_200, {:ok, %{cutover: %{ready?: true}}}}}
      )

    assert ValuationPolicyCache.selection(name) == @tcgdex
    assert_receive :valuation_policy_invalidated, 2_000
    assert ValuationPolicyCache.selection(name) == @bulk
  end

  test "requested TCGdex policy does not touch the cache" do
    previous = Application.get_env(:tcg_cheap, :public_singles_valuation_policy)
    Application.put_env(:tcg_cheap, :public_singles_valuation_policy, @tcgdex)

    on_exit(fn -> Application.put_env(:tcg_cheap, :public_singles_valuation_policy, previous) end)
    assert ValuationPolicy.selection() == @tcgdex
  end

  defp loader_module, do: TcgCheap.Pricing.Singles.ValuationPolicyCacheTestLoader
end
