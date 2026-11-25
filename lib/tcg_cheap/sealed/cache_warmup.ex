defmodule TcgCheap.Sealed.CacheWarmup do
  @moduledoc """
  Reads the shared entries that the home pages and every page's footer show
  (`TcgCheap.Sealed.Cache`) once the application starts, so the first visitors
  after a deploy do not wait for them. Each entry then refreshes in the
  background as its readers find it expired.

  The list follows `TcgCheapWeb.HomeLive.mount/3`, its articles and
  `TcgCheapWeb.SiteFooter`: an entry left out is read by its first reader, as
  before.
  """

  use Task, restart: :temporary

  alias TcgCheap.Cards
  alias TcgCheap.Sealed.{BoosterGuide, Deals, Expansions, Market, Shops}

  require Logger

  def start_link(_arg), do: Task.start_link(&run/0)

  @doc "Reads every entry; one that fails is logged and left to its first reader."
  @spec run() :: :ok
  def run do
    {us, _} = :timer.tc(fn -> Enum.each(reads(), &read/1) end)
    Logger.info("Cache warm-up finished in #{div(us, 1000)} ms")
  end

  defp reads do
    shared = [
      fn -> Expansions.newest(1) end,
      fn -> Expansions.latest(1) end,
      &Deals.current/0,
      &Deals.market/0,
      &BoosterGuide.guide/0,
      &Cards.Expensive.overview/0,
      &Cards.Value.guide/0
    ]

    banners =
      for market <- Market.all(),
          Shops.singles?(market),
          do: fn -> Cards.SinglesBanner.market(market) end

    shared ++ banners
  end

  defp read(fun) do
    fun.()
  rescue
    error ->
      Logger.warning(
        "Cache warm-up read failed: " <> Exception.format(:error, error, __STACKTRACE__)
      )
  end
end
