defmodule TcgCheapWeb.RegionText do
  @moduledoc """
  Sentences that name the current region's country, its shops or its
  currency (`TcgCheapWeb.Region.current/0`), one whole sentence per region.
  Languages inflect a country's name ("do Polski", "na Węgry",
  "Magyarországra"), so a country is never a placeholder in a sentence.

  Singles have no market outside Poland yet (`TcgCheapWeb.Region.from_pln/1`):
  there the card sentences speak of Cardmarket prices in the region's
  currency, not of its shops. Pages only Poland has (the articles, the bot
  page) keep their Polish sentences in place.
  """

  use Gettext, backend: TcgCheapWeb.Gettext

  alias TcgCheapWeb.Region

  defp region, do: Region.current().code

  @doc "The home page's search description."
  @spec home_description() :: String.t()
  def home_description do
    case region() do
      "hu" ->
        gettext(
          "Porównaj ceny Pokémon TCG w sklepach wysyłających na Węgry. Sprawdź oferty boosterów, ETB i boxów, historię cen i czy warto kupić teraz."
        )

      "pl" ->
        gettext(
          "Porównaj ceny Pokémon TCG w sklepach wysyłających do Polski. Sprawdź oferty boosterów, ETB, boxów i angielskich kart, historię cen i czy warto kupić teraz."
        )
    end
  end

  @doc "The promise under the home link-preview card's headline."
  @spec social_promise() :: String.t()
  def social_promise do
    case region() do
      "hu" ->
        gettext("Ceny Pokémon TCG ze sklepów wysyłających na Węgry, sprawdzane codziennie.")

      "pl" ->
        gettext("Ceny Pokémon TCG ze sklepów wysyłających do Polski, sprawdzane codziennie.")
    end
  end

  @doc "The promise under the products list's title."
  @spec products_promise() :: String.t()
  def products_promise do
    case region() do
      "hu" -> gettext("Najtańsze oferty Pokémon TCG w sklepach wysyłających na Węgry.")
      "pl" -> gettext("Najtańsze oferty Pokémon TCG w sklepach wysyłających do Polski.")
    end
  end

  @doc "The promise under the card list's title."
  @spec cards_promise() :: String.t()
  def cards_promise do
    case region() do
      "hu" -> cardmarket_cards()
      "pl" -> gettext("Najtańsze karty Pokémon TCG w sklepach wysyłających do Polski.")
    end
  end

  @doc "The card list's search answer when it has no figures of its own."
  @spec cards_answer() :: String.t()
  def cards_answer do
    case region() do
      "hu" -> cardmarket_cards()
      "pl" -> gettext("Angielskie karty Pokémon TCG w sklepach wysyłających do Polski.")
    end
  end

  defp cardmarket_cards,
    do: gettext("Angielskie karty Pokémon TCG z ceną z Cardmarket w forintach.")

  @doc "The card list's title."
  @spec cards_title() :: String.t()
  def cards_title do
    case region() do
      "hu" -> gettext("Ceny kart Pokémon TCG w forintach")
      "pl" -> gettext("Ceny kart Pokémon TCG w Polsce")
    end
  end

  @doc "A card page's full title, before the shorter ones without the country."
  @spec card_title(String.t()) :: String.t()
  def card_title(card) do
    case region() do
      "hu" -> gettext("%{card} – cena karty Pokémon w forintach", card: card)
      "pl" -> gettext("%{card} – cena karty Pokémon w Polsce", card: card)
    end
  end

  @doc "A set page's search answer when it knows nothing else of the set."
  @spec expansion_fallback(String.t()) :: String.t()
  def expansion_fallback(expansion) do
    case region() do
      "hu" ->
        gettext(
          "%{expansion}: porównaj ceny boosterów, ETB, boxów i kolekcji w sklepach wysyłających na Węgry.",
          expansion: expansion
        )

      "pl" ->
        gettext(
          "%{expansion}: porównaj ceny boosterów, ETB, boxów i kolekcji w sklepach wysyłających do Polski.",
          expansion: expansion
        )
    end
  end

  @doc "A set's search answer when no shop has its booster in stock."
  @spec booster_out_of_stock(String.t()) :: String.t()
  def booster_out_of_stock(expansion) do
    case region() do
      "hu" ->
        gettext("Boostera %{expansion} żaden sklep wysyłający na Węgry nie ma teraz na stanie.",
          expansion: expansion
        )

      "pl" ->
        gettext("Boostera %{expansion} żaden polski sklep nie ma teraz na stanie.",
          expansion: expansion
        )
    end
  end

  @doc "A product's search answer when no shop has it in stock."
  @spec product_out_of_stock(String.t()) :: String.t()
  def product_out_of_stock(name) do
    case region() do
      "hu" ->
        gettext("%{name}: teraz żaden sklep wysyłający na Węgry nie ma tego produktu na stanie.",
          name: name
        )

      "pl" ->
        gettext("%{name}: teraz żaden polski sklep nie ma tego produktu na stanie.", name: name)
    end
  end

  @doc """
  What a Cardmarket price with delivery includes. Every region adds the
  same tracked parcel from Germany (`TcgCheap.Sealed.Guide`); Poland's
  sentence names where it goes, as it was checked for Poland.
  """
  @spec cardmarket_delivery() :: String.t()
  def cardmarket_delivery do
    case region() do
      "hu" -> gettext("z wysyłką z Niemiec")
      "pl" -> gettext("z wysyłką do Polski")
    end
  end

  @doc """
  The line above a product list where shops abroad are compared with their
  delivery and the rows name only the shop; nil in Poland, whose rows say
  it beside each shop abroad.
  """
  @spec list_prices_note() :: String.t() | nil
  def list_prices_note do
    case region() do
      "hu" -> gettext("Ceny ze sklepów z zagranicy są z wysyłką na Węgry.")
      "pl" -> nil
    end
  end

  @doc """
  How prices abroad reach the region's currency, under a product's verdict;
  nil in Poland.
  """
  @spec foreign_shops_note() :: String.t() | nil
  def foreign_shops_note do
    case region() do
      "hu" ->
        gettext(
          "Sklepy z zagranicy sprzedają w swojej walucie, polskie w złotych. Ich ceny przeliczamy na forinty po dziennych kursach NBP. Strona sklepu może być po polsku albo w innym języku."
        )

      "pl" ->
        nil
    end
  end

  @doc "Which shop prices include delivery, under a product's verdict."
  @spec shop_prices_note(String.t()) :: String.t()
  def shop_prices_note(shipping) do
    case region() do
      "hu" ->
        gettext(
          "Ceny węgierskich sklepów są bez wysyłki, a sklepów z zagranicy – z wysyłką na Węgry. Do Cardmarket doliczamy %{shipping} za paczkę z Niemiec.",
          shipping: shipping
        )

      "pl" ->
        gettext(
          "Ceny w sklepach są bez wysyłki. Do Cardmarket doliczamy %{shipping} za paczkę z Niemiec.",
          shipping: shipping
        )
    end
  end
end
