defmodule TcgCheap.Sealed.Guide do
  @moduledoc "Read models for the public buying-guide pages."

  alias TcgCheap.Sealed
  alias TcgCheap.Sealed.{Catalogue, PriceGuide, Product}

  @history_days 90

  @type summary :: %{
          product: Product.t(),
          verdict: PriceGuide.t(),
          image_url: String.t() | nil
        }

  def history_days, do: @history_days

  @doc "One summary per product, in the given order."
  @spec summaries([Product.t()], DateTime.t()) :: [summary()]
  def summaries(products, %DateTime{} = now) do
    today = DateTime.to_date(now)
    offers = now |> Sealed.current_offers() |> Enum.group_by(& &1.product_slug)

    history =
      today
      |> Date.add(-(PriceGuide.window_days() - 1))
      |> Sealed.list_daily_prices_since!()
      |> Enum.group_by(& &1.product_slug)

    Enum.map(products, fn product ->
      product_offers = Map.get(offers, product.slug, [])
      summary(product, product_offers, Map.get(history, product.slug, []), today)
    end)
  end

  @doc "Everything the product page shows: verdict, offers and 90 days of history."
  @spec product(String.t(), DateTime.t()) ::
          {:ok, summary() | map()} | :error
  def product(slug, %DateTime{} = now) do
    with {:ok, product} <- Catalogue.get(slug) do
      today = DateTime.to_date(now)

      offers =
        now
        |> Sealed.current_offers()
        |> Enum.filter(&(&1.product_slug == slug))
        |> Enum.sort_by(&{not &1.in_stock, Decimal.to_float(&1.price), &1.shop})

      history = Sealed.list_price_history!(slug, Date.add(today, -(@history_days - 1)))

      {:ok,
       product
       |> summary(offers, history, today)
       |> Map.merge(%{offers: offers, history: history, today: today})}
    end
  end

  defp summary(product, offers, history, today) do
    in_stock = Enum.filter(offers, & &1.in_stock)
    verdict = PriceGuide.verdict(history, in_stock, today)

    %{
      product: product,
      verdict: verdict,
      image_url: product.image_url || Enum.find_value(offers, & &1.image_url)
    }
  end
end
