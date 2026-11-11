defmodule TcgCheap.Sealed.BoosterGuide do
  @moduledoc """
  What the guide "Ile kosztuje booster Pokémon?" reads, shared by every
  render for the cache's lifetime: the booster price page's facts
  (`Guide.booster_prices/1`), each of those recent sets with its release
  day, booster, Elite Trainer Box and whether it has a Booster Box (`sets`),
  the newest set's products in stock (`latest`) and every recent set's
  products in stock by type (`by_type`, newest set first).

  A product's `price` is its typical shop price (the median of each shop's
  lowest) when enough shops have it, else its cheapest (`few_shops?`). Its
  boosters bought one by one (`loose`) cost as many of its set's single
  boosters at the same kind of price (`single`: typical against typical,
  cheapest against cheapest); `extra` is what the rest of the box costs on
  top, negative when the box is cheaper than its boosters. The cards it
  holds beside them (`cards`) carry their Cardmarket trend in złoty when we
  know their Cardmarket product.
  """

  import Ecto.Query

  alias TcgCheap.{Repo, Sealed}
  alias TcgCheap.Sealed.{CardPrice, Guide, Product, TcgdexSet}

  # What a set comes out in, without the cases shops order by, decks or
  # loose card sets.
  @kinds [
    :booster,
    :booster_bundle,
    :blister,
    :elite_trainer_box,
    :booster_box,
    :collection,
    :tin
  ]
  @card_types [:promo_card, :oversize_card, :card]

  def guide, do: Guide.cached(:booster_guide, &read/0)

  defp read do
    now = DateTime.utc_now()
    page = Guide.booster_prices(now)
    names = Enum.map(page.boosters, & &1.product.set_name)
    order = names |> Enum.with_index() |> Map.new()

    single =
      Map.new(
        page.boosters,
        &{&1.product.set_name, %{typical: price(&1.verdict), cheapest: &1.verdict.cheapest.price}}
      )

    rate = Guide.eur_pln(page.today)

    products =
      names
      |> set_products(now)
      |> Enum.filter(&(&1.verdict.cheapest && not &1.preorder?))
      |> Enum.map(&priced(&1, single))
      |> with_card_values(rate)
      |> Enum.sort_by(&{order[&1.product.set_name], Decimal.to_float(&1.price)})

    by_set = Enum.group_by(products, & &1.product.set_name)
    latest = List.first(names)

    Map.merge(page, %{
      sets: sets(page.boosters, by_set),
      latest: latest && %{set: latest, products: Map.get(by_set, latest, [])},
      by_type: Enum.group_by(products, & &1.type)
    })
  end

  defp set_products([], _now), do: []

  defp set_products(names, now) do
    [
      query: [filter: [available: true, region: :en, set_name: [in: names], kind: [in: @kinds]]],
      load: [:stored_photo_small_url, :stored_photo_card_url, :photo_placeholder]
    ]
    |> Sealed.list_products!()
    |> Guide.summaries(now)
  end

  @doc """
  What kind of box a product is on the guide, by its kind and the name the
  publisher gives each kind of blister, tin and box.
  """
  def type(%{kind: :booster, name: name}),
    do: if(name =~ "Sleeved", do: :sleeved_booster, else: :booster)

  def type(%{kind: :blister, name: name}) do
    cond do
      name =~ "Premium Checklane" -> :premium_checklane
      name =~ ~r/\b3-Pack\b/ -> :three_pack
      name =~ ~r/\b1-Pack\b|Checklane/ -> :blister
      # Two-pack blisters, tech sticker collections.
      true -> :other_blister
    end
  end

  def type(%{kind: :elite_trainer_box, name: name}),
    do: if(name =~ "Pokémon Center", do: :pokemon_center_etb, else: :elite_trainer_box)

  def type(%{kind: :collection, name: name}),
    do: if(name =~ "Build & Battle", do: :build_and_battle, else: :collection)

  def type(%{kind: :tin, name: name}), do: if(name =~ "Mini Tin", do: :mini_tin, else: :tin)
  def type(%{kind: kind}), do: kind

  defp price(%{typical_source: :shops, typical: typical}), do: typical
  defp price(%{cheapest: %{price: price}}), do: price

  defp priced(%{product: product, verdict: verdict} = summary, single) do
    price = price(verdict)
    few_shops? = verdict.typical_source != :shops
    {boosters, own_set?} = boosters(product)

    set_booster =
      case Map.get(single, product.set_name) do
        nil -> nil
        prices -> if few_shops?, do: prices.cheapest, else: prices.typical
      end

    loose =
      if (product.kind != :booster and own_set? and boosters) && set_booster,
        do: Decimal.mult(set_booster, boosters)

    Map.merge(summary, %{
      type: type(product),
      price: price,
      few_shops?: few_shops?,
      boosters: boosters,
      single: set_booster,
      loose: loose,
      extra: loose && Decimal.sub(price, loose),
      items: items(product)
    })
  end

  # How many boosters a box holds, and whether they are all its own set's:
  # from its contents, else from its name ("3-Pack Blister").
  defp boosters(%{kind: :booster}), do: {1, true}

  defp boosters(%{contents: %{items: items}, set_name: set}) do
    case Enum.filter(items, &(&1.type == :booster)) do
      [] -> {nil, false}
      packs -> {Enum.sum_by(packs, & &1.quantity), Enum.all?(packs, &(&1.name in [nil, set]))}
    end
  end

  defp boosters(%{name: name}) do
    case Regex.run(~r/\b(\d+)-Pack\b/, name) do
      [_, count] -> {String.to_integer(count), true}
      nil -> {nil, false}
    end
  end

  # What a box holds beside its boosters; a single booster's contents are
  # its own cards.
  defp items(%{kind: :booster}), do: []
  defp items(%{contents: %{items: items}}), do: Enum.reject(items, &(&1.type == :booster))
  defp items(_product), do: []

  # Each card a box holds beside its boosters, with its Cardmarket trend in
  # złoty when known (nil otherwise).
  defp with_card_values(boxes, rate) do
    ids =
      for box <- boxes,
          item <- box.items,
          item.type in @card_types and item.cardmarket_id,
          uniq: true,
          do: item.cardmarket_id

    trends =
      CardPrice
      |> where([price], price.cardmarket_id in ^ids)
      |> select([price], {price.cardmarket_id, price.trend})
      |> Repo.all()
      |> Map.new()

    Enum.map(boxes, fn box ->
      cards =
        for item <- box.items, item.type in @card_types do
          %{item: item, value: Guide.to_pln(Map.get(trends, item.cardmarket_id), rate)}
        end

      Map.put(box, :cards, cards)
    end)
  end

  # Each set on the booster price page: its release day, booster, own Elite
  # Trainer Box in stock, whether the catalogue has a Booster Box of it (a
  # special set has none) and how many tins and collections it has.
  defp sets(boosters, by_set) do
    names = Enum.map(boosters, & &1.product.set_name)

    released =
      TcgdexSet
      |> where([set], set.language == "en" and set.name in ^names)
      |> select([set], {set.name, set.released_on})
      |> Repo.all()
      |> Map.new()

    kinds =
      Product
      |> where([p], p.region == :en and p.set_name in ^names)
      |> where([p], p.kind in [:booster_box, :tin, :collection])
      |> group_by([p], [p.set_name, p.kind])
      |> select([p], {{p.set_name, p.kind}, count(p.id)})
      |> Repo.all()
      |> Map.new()

    logos = Guide.expansion_logos()

    Enum.map(boosters, fn booster ->
      set = booster.product.set_name

      %{
        name: set,
        released_on: Map.get(released, set),
        logo: Map.get(logos, booster.product.cardmarket_expansion_id),
        booster: booster,
        etb:
          Enum.find(
            Map.get(by_set, set, []),
            &(&1.product.name == set <> " Elite Trainer Box")
          ),
        booster_box?: Map.has_key?(kinds, {set, :booster_box}),
        tins: Map.get(kinds, {set, :tin}, 0),
        collections: Map.get(kinds, {set, :collection}, 0)
      }
    end)
  end
end
