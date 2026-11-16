defmodule TcgCheapWeb.SEO.Expansion do
  @moduledoc """
  Search metadata of a set's page, which is what people search for by name:
  "<set> cena", "<set> drop rate", "<set> lista kart". Its list narrowed by
  a search or a filter stays out of search.
  """

  use Gettext, backend: TcgCheapWeb.Gettext

  alias TcgCheap.Sealed.Catalogue
  alias TcgCheapWeb.{Format, OfferComponents, Paths, RegionText, SEO, SocialImage}

  @doc "The set page's path: the expansion's name plus its Cardmarket id, like a product's."
  @spec path(integer(), String.t()) :: String.t()
  def path(id, name), do: Paths.expansion(Catalogue.slug(name, id))

  @doc "The set page's full URL."
  @spec url(integer(), String.t()) :: String.t()
  def url(id, name), do: Paths.url(path(id, name))

  @doc "`page` is `TcgCheap.Sealed.Guide.expansion/3`."
  @spec metadata(
          map(),
          %{:id => integer(), :name => String.t(), optional(atom()) => any()},
          map()
        ) ::
          SEO.t()
  def metadata(params, %{id: id, name: name}, page) do
    canonical = url(id, name)

    SEO.compose(
      SEO.fit_title(titles(name, page)),
      SEO.fit_description(answer(name, page)),
      canonical,
      social_image:
        if(SEO.polish?(),
          do: SEO.social_image(path(id, name), SocialImage.Expansion.version(name, page)),
          else: SEO.home_image()
        ),
      social_image_alt:
        if(SEO.polish?(),
          do: gettext("%{expansion}: najcenniejsze karty i ceny", expansion: name),
          else: SEO.home_image_alt()
        ),
      alternates: SEO.alternates({:expansion, Catalogue.slug(name, id)}),
      robots:
        if(Enum.any?(~w(q rodzaj wersja), &Map.has_key?(params, &1)),
          do: "noindex, follow",
          else: "index, follow"
        ),
      structured_data: SEO.json_ld(SEO.breadcrumbs([SEO.all_products_crumb(), {name, canonical}]))
    )
  end

  # A set whose cards Polish shops sell is searched for its card prices too,
  # and for its boosters' when it has one.
  defp titles(name, %{set: %{singles: %{in_stock: in_stock}} = set, booster: nil})
       when in_stock > 0,
       do:
         Enum.filter(
           [
             set.pull_rates && gettext("%{expansion} – ceny kart i drop rate", expansion: name),
             gettext("%{expansion} – ceny kart Pokémon TCG", expansion: name),
             gettext("%{expansion} – ceny kart", expansion: name),
             name
           ],
           &is_binary/1
         )

  defp titles(name, %{set: %{singles: %{in_stock: in_stock}} = set})
       when in_stock > 0,
       do:
         Enum.filter(
           [
             set.pull_rates &&
               gettext("%{expansion} – ceny kart i boosterów, drop rate", expansion: name),
             gettext("%{expansion} – ceny kart i boosterów Pokémon TCG", expansion: name),
             gettext("%{expansion} – ceny kart i boosterów", expansion: name),
             gettext("%{expansion} – ceny kart", expansion: name),
             name
           ],
           &is_binary/1
         )

  defp titles(name, %{set: %{pull_rates: %{}}}),
    do: [
      gettext("%{expansion} – ceny, drop rate i lista kart Pokémon TCG", expansion: name),
      gettext("%{expansion} – ceny, drop rate i lista kart", expansion: name),
      name
    ]

  defp titles(name, %{set: %{rarities: [_ | _]}}),
    do: [
      gettext("%{expansion} – ceny i lista kart Pokémon TCG", expansion: name),
      gettext("%{expansion} – ceny i lista kart", expansion: name),
      name
    ]

  defp titles(name, _page),
    do: [
      gettext("%{expansion} – ceny boosterów, ETB i boxów Pokémon TCG", expansion: name),
      gettext("%{expansion} – ceny boosterów, ETB i boxów", expansion: name),
      name
    ]

  @doc """
  The set page's answer, in sentences, for its top and its search snippet:
  the single booster's cheapest price, the rarest pull rates, the number of
  cards and the dearest one.
  """
  @spec answer(String.t(), %{
          :set => map() | nil,
          :booster => map() | nil,
          optional(atom()) => any()
        }) :: [String.t()]
  def answer(name, %{set: set, booster: booster}) do
    [
      booster_sentence(name, booster),
      set && pull_rates_summary(set.pull_rates),
      set && cards_sentence(set)
    ]
    |> Enum.reject(&is_nil/1)
    |> case do
      [] ->
        [RegionText.expansion_fallback(name)]

      sentences ->
        sentences
    end
  end

  defp booster_sentence(_name, nil), do: nil

  defp booster_sentence(name, %{verdict: %{cheapest: nil}}),
    do: RegionText.booster_out_of_stock(name)

  defp booster_sentence(name, %{verdict: %{cheapest: cheapest}, preorder?: true}),
    do:
      gettext("Booster %{expansion}: przedsprzedaż od %{price} w %{shop}.",
        expansion: name,
        price: Format.price(cheapest.price),
        shop: OfferComponents.priced_shop_name(cheapest)
      )

  defp booster_sentence(name, %{verdict: %{cheapest: cheapest}}),
    do:
      gettext("Booster %{expansion}: najtaniej teraz %{price} w %{shop}.",
        expansion: name,
        price: Format.price(cheapest.price),
        shop: OfferComponents.priced_shop_name(cheapest)
      )

  @doc "The two rarest pull rates, as the page's table states them; nil without rates."
  @spec pull_rates_summary(map() | nil) :: String.t() | nil
  def pull_rates_summary(%{rates: [_ | _] = rates}) do
    odds = Enum.map_join(Enum.take(rates, 2), ", ", &"#{&1.rarity} #{Format.odds(&1.rate)}")
    gettext("Szansa na drop (pull rates): %{odds}.", odds: odds)
  end

  def pull_rates_summary(_pull_rates), do: nil

  defp cards_sentence(%{card_count: 0}), do: nil

  defp cards_sentence(%{card_count: count, top_cards: []}),
    do: gettext("Set liczy %{cards}.", cards: Format.cards(count))

  # The dearest card's price is a Polish shop's or Cardmarket's in złoty.
  defp cards_sentence(%{card_count: count, top_cards: [top | _]}) when top != nil do
    if SEO.polish?(),
      do: dearest_card_sentence(count, top),
      else: cards_sentence(%{card_count: count, top_cards: []})
  end

  defp dearest_card_sentence(count, top),
    do:
      gettext("Set liczy %{cards}, najdroższa to %{card} (%{price}, bez dostawy).",
        cards: Format.cards(count),
        card: top.card.name,
        price: Format.price(top.price)
      )
end
