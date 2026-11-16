defmodule TcgCheap.Sealed.SetPage do
  @moduledoc """
  What an expansion's page shows besides its products, in the market's
  currency (`TcgCheap.Sealed.Market`).
  """

  alias TcgCheap.Sealed
  alias TcgCheap.Sealed.{ExpansionCards, Market, Product, Summary}

  @doc """
  What an expansion's page shows besides its products: its English single
  booster (`booster`, a summary, nil when there is none) and the set's pull
  rates and cards as on that booster's page with the card count and the most
  valuable card (`set`, nil when we have neither).
  `name` is the expansion's name. The booster and the Cardmarket boxes are
  in the market's currency; the cards' prices stay Polish (singles are
  priced only in Poland).
  """
  @spec read(integer(), String.t(), DateTime.t(), Market.t()) :: %{
          set: map() | nil,
          booster: Summary.t() | nil,
          cardmarket: [%{kind: atom(), price: Decimal.t()}]
        }
  def read(id, name, %DateTime{} = now, %Market{} = market \\ Market.poland()) do
    set = ExpansionCards.read(id)
    booster = booster(id, name, now, market)

    %{
      set: ExpansionCards.with_singles(set, booster),
      booster: booster,
      cardmarket: cardmarket_boxes(id, name, now, market)
    }
  end

  @doc """
  An expansion's English single booster as a summary with its list row's
  photos, nil when there is none. `name` is the expansion's name.
  """
  @spec booster(integer(), String.t(), DateTime.t(), Market.t()) :: Summary.t() | nil
  def booster(id, name, %DateTime{} = now, %Market{} = market) do
    [
      query: [
        filter: [kind: :booster, region: :en, cardmarket_expansion_id: id],
        select: Summary.fields()
      ],
      load: [
        :stored_photo_small_url,
        :stored_photo_card_url,
        :stored_photo_page_url,
        :photo_placeholder
      ]
    ]
    |> Sealed.list_products!()
    |> single_booster(name)
    |> List.wrap()
    |> Summary.list(now, market)
    |> List.first()
  end

  # "<set> Booster", else the set's only full-size booster ("Trick or Trade
  # BOOster", "EX Emerald Booster"); none when several could be meant.
  defp single_booster(boosters, name) do
    Enum.find(boosters, &(&1.name == name <> " Booster")) ||
      case Enum.reject(boosters, &Product.pack_size/1) do
        [booster] -> booster
        _boosters -> nil
      end
  end

  # The set's own Booster Box and Elite Trainer Box on Cardmarket (trend in
  # the market's currency, without delivery), for a banner that has no card
  # prices to show.
  defp cardmarket_boxes(id, name, now, market) do
    rate = Market.cardmarket_rate(market, DateTime.to_date(now))

    names = %{
      "#{name} Booster Box" => :booster_box,
      "#{name} Elite Trainer Box" => :elite_trainer_box
    }

    [
      query: [
        filter: [cardmarket_expansion_id: id, region: :en, name: [in: Map.keys(names)]],
        select: [:name, :cardmarket_trend]
      ]
    ]
    |> Sealed.list_products!()
    |> Enum.map(
      &%{
        kind: Map.fetch!(names, &1.name),
        price: Market.in_market(&1.cardmarket_trend, rate, market)
      }
    )
    # No trend, or no exchange rate yet, leaves a box without a price.
    |> Enum.filter(& &1.price)
    |> Enum.sort_by(&(&1.kind != :booster_box))
  end
end
