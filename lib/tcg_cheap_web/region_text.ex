defmodule TcgCheapWeb.RegionText do
  @moduledoc """
  Sentences that name the current region's country, its shops or its
  currency (`TcgCheapWeb.Region.current/0`), one whole sentence per region.
  Languages inflect a country's name ("do Polski", "na Węgry",
  "Magyarországra"), so a country is never a placeholder in a sentence.

  Each region writes its own, as the callbacks below, in its country's
  module (`TcgCheap.Country`) and Gettext domain; these functions read the
  current region's.

  The card sentences speak of the region's shops where shops sell singles
  there (`TcgCheapWeb.Region.singles?/1`); elsewhere the card list's speak of
  Cardmarket prices alone, in sentences of every region. Pages only Poland
  has (the articles, the bot page) keep their Polish sentences in place.
  """

  use Gettext, backend: TcgCheapWeb.Gettext

  alias TcgCheapWeb.{Format, Region}

  @doc ~S(The country's name in the page language, for the region control: "Węgry".)
  @callback name() :: String.t()

  @doc "The region hint's sentence, in the region's language (`TcgCheapWeb.Locale`)."
  @callback hint() :: String.t()

  @doc "The region hint's link to the region."
  @callback hint_switch() :: String.t()

  @doc ~S(The location control's error for a point outside the country: "…outside Hungary. Enter a town.")
  @callback location_outside() :: String.t()

  @doc ~S(The location control's example of a town to type, with its "e.g.", in the page language.)
  @callback town_example() :: String.t()

  @doc "The home page's search description."
  @callback home_description() :: String.t()

  @doc "The promise under the home link-preview card's headline."
  @callback social_promise() :: String.t()

  @doc "The promise under the products list's title."
  @callback products_promise() :: String.t()

  @doc "The promise under the card list's title."
  @callback cards_promise() :: String.t()

  @doc "The card list's search answer when it has no figures of its own."
  @callback cards_answer() :: String.t()

  @doc "The card list's title."
  @callback cards_title() :: String.t()

  @doc "A card page's full title, before the shorter ones without the country."
  @callback card_title(card :: String.t()) :: String.t()

  @doc "A card page's search description with its cheapest offer."
  @callback card_description(name :: String.t(), number :: String.t(), price :: String.t()) ::
              String.t()

  @doc "The card list's search answer with the number of cards in stock."
  @callback cards_in_stock(cards :: String.t()) :: String.t()

  @doc "A card page's verdict when no shop has the card in stock."
  @callback card_unavailable() :: String.t()

  @doc "The same for screen readers, under the verdict."
  @callback card_unavailable_note() :: String.t()

  @doc "How a card's verdict is reached, with the `shops` it needs, counted as `Format.shops/1` writes them."
  @callback card_method(shops :: String.t()) :: String.t()

  @doc "Under a set's card list: which price each card shows."
  @callback card_prices_note() :: String.t()

  @doc "A Cardmarket card price with delivery to the country, in a set's singles banner."
  @callback cardmarket_card_delivery() :: String.t()

  @doc "The foot of a set's singles banner: which prices include delivery."
  @callback singles_prices_note() :: String.t()

  @doc "A set page's search answer when it knows nothing else of the set."
  @callback expansion_fallback(expansion :: String.t()) :: String.t()

  @doc "A set's search answer when no shop has its booster in stock."
  @callback booster_out_of_stock(expansion :: String.t()) :: String.t()

  @doc "A product's search answer when no shop has it in stock."
  @callback product_out_of_stock(name :: String.t()) :: String.t()

  @doc """
  What a Cardmarket price with delivery includes: the region's tracked
  parcel (`TcgCheap.Country.region/0`).
  """
  @callback cardmarket_delivery() :: String.t()

  @doc """
  The line above a product list where shops abroad are compared with their
  delivery and the rows name only the shop; nil where the rows say it.
  """
  @callback list_prices_note() :: String.t() | nil

  @doc "How prices abroad reach the region's currency, under a product's verdict; nil for none."
  @callback foreign_shops_note() :: String.t() | nil

  @doc "Which shop prices include delivery, under a product's verdict, with the Cardmarket parcel."
  @callback shop_prices_note(shipping :: String.t()) :: String.t()

  @doc """
  The region's sentences in the Markdown pages' method (`TcgCheapWeb.PageMarkdown`,
  in the region's language like the rest of it): where prices come from, what
  bounds a good price over the history `window` (days) and what stands in with fewer shops.
  """
  @callback markdown_method(window :: pos_integer()) :: %{
              prices: String.t(),
              good_price: String.t(),
              few_shops: String.t()
            }

  defp country, do: Region.current().country
  defp singles?, do: Region.singles?(Region.current())

  def location_outside, do: country().location_outside()
  def town_example, do: country().town_example()
  def home_description, do: country().home_description()
  def social_promise, do: country().social_promise()
  def products_promise, do: country().products_promise()
  # Without singles shops the card list has only Cardmarket's prices.
  def cards_promise,
    do:
      if(singles?(),
        do: country().cards_promise(),
        else: gettext("Angielskie karty Pokémon TCG z ceną z Cardmarket.")
      )

  def cards_answer,
    do:
      if(singles?(),
        do: country().cards_answer(),
        else: gettext("Angielskie karty Pokémon TCG z ceną z Cardmarket.")
      )

  def cards_title,
    do:
      if(singles?(),
        do: country().cards_title(),
        else: gettext("Ceny kart Pokémon TCG na Cardmarket")
      )

  def card_title(card),
    do:
      if(singles?(),
        do: country().card_title(card),
        else: gettext("%{card} – cena karty Pokémon na Cardmarket", card: card)
      )

  def card_description(name, number, price), do: country().card_description(name, number, price)
  def cards_in_stock(cards), do: country().cards_in_stock(cards)
  def card_unavailable, do: country().card_unavailable()
  def card_unavailable_note, do: country().card_unavailable_note()
  def card_method(minimum), do: country().card_method(Format.shops(minimum))
  def card_prices_note, do: country().card_prices_note()
  def cardmarket_card_delivery, do: country().cardmarket_card_delivery()
  def singles_prices_note, do: country().singles_prices_note()
  def expansion_fallback(expansion), do: country().expansion_fallback(expansion)
  def booster_out_of_stock(expansion), do: country().booster_out_of_stock(expansion)
  def product_out_of_stock(name), do: country().product_out_of_stock(name)
  def cardmarket_delivery, do: country().cardmarket_delivery()
  def list_prices_note, do: country().list_prices_note()
  def foreign_shops_note, do: country().foreign_shops_note()
  def shop_prices_note(shipping), do: country().shop_prices_note(shipping)
  def markdown_method(window), do: country().markdown_method(window)
end
