defmodule TcgCheap.Countries.Poland do
  @moduledoc """
  Poland: the guide's first region, `/pl/` in złoty, and the words that
  name it (`TcgCheap.Country`). Only Poland's market has the parts that
  read Polish data: singles from shops, retail chain deals, the banners
  above the lists and a set's most valuable cards.
  """

  @behaviour TcgCheap.Country
  @behaviour TcgCheapWeb.RegionText

  use Gettext, backend: TcgCheapWeb.Gettext

  @impl TcgCheap.Country
  def code, do: "PL"

  @impl TcgCheap.Country
  def shipped_from, do: dgettext("poland", "wysyłka z Polski")

  @impl TcgCheap.Country
  def delivered_from, do: dgettext("poland", "z wysyłką z Polski")

  @impl TcgCheap.Country
  def region do
    %{
      code: "pl",
      currency: "PLN",
      currency_symbol: "zł",
      decimals: 2,
      language: "pl",
      hreflang: "pl-PL",
      # Ukrainian, once the guide renders it: Poland's largest minority.
      popular_languages: ["uk"],
      # The cheapest tracked parcel to Poland from Germany, Cardmarket's largest
      # seller country (DHL Paket up to 2 kg, Cardmarket's shipping calculator,
      # 2026-11-02); orders above 25 € must be tracked, which covers most sealed
      # products.
      cardmarket_shipping_eur: Decimal.new("15.49"),
      slugs: %{products: "produkty", expansions: "rozszerzenia", cards: "karty"},
      pages: %{
        booster_prices: "ile-kosztuje-booster-pokemon",
        expensive_cards: "najdrozsze-karty-pokemon",
        card_value: "jak-sprawdzic-wartosc-karty-pokemon",
        bot: "bot"
      }
    }
  end

  @impl TcgCheapWeb.RegionText
  def name, do: dgettext("poland", "Polska")

  @impl TcgCheapWeb.RegionText
  def hint, do: dgettext("poland", "Wygląda na to, że jesteś w Polsce.")

  @impl TcgCheapWeb.RegionText
  def hint_switch, do: dgettext("poland", "Przejdź do wersji polskiej")

  @impl TcgCheapWeb.RegionText
  def location_outside,
    do: dgettext("poland", "Ta lokalizacja jest poza Polską. Wpisz miejscowość.")

  @impl TcgCheapWeb.RegionText
  def town_example, do: dgettext("poland", "np. Gdańsk")

  @impl TcgCheapWeb.RegionText
  def home_description,
    do:
      dgettext(
        "poland",
        "Porównaj ceny Pokémon TCG w sklepach wysyłających do Polski. Sprawdź oferty boosterów, ETB, boxów i angielskich kart, historię cen i czy warto kupić teraz."
      )

  @impl TcgCheapWeb.RegionText
  def social_promise,
    do:
      dgettext(
        "poland",
        "Ceny Pokémon TCG ze sklepów wysyłających do Polski, sprawdzane codziennie."
      )

  @impl TcgCheapWeb.RegionText
  def products_promise,
    do: dgettext("poland", "Najtańsze oferty Pokémon TCG w sklepach wysyłających do Polski.")

  @impl TcgCheapWeb.RegionText
  def cards_promise,
    do: dgettext("poland", "Najtańsze karty Pokémon TCG w sklepach wysyłających do Polski.")

  @impl TcgCheapWeb.RegionText
  def cards_answer,
    do: dgettext("poland", "Angielskie karty Pokémon TCG w sklepach wysyłających do Polski.")

  @impl TcgCheapWeb.RegionText
  def cards_title, do: dgettext("poland", "Ceny kart Pokémon TCG w Polsce")

  @impl TcgCheapWeb.RegionText
  def card_title(card),
    do: dgettext("poland", "%{card} – cena karty Pokémon w Polsce", card: card)

  @impl TcgCheapWeb.RegionText
  def expansion_fallback(expansion),
    do:
      dgettext(
        "poland",
        "%{expansion}: porównaj ceny boosterów, ETB, boxów i kolekcji w sklepach wysyłających do Polski.",
        expansion: expansion
      )

  @impl TcgCheapWeb.RegionText
  def booster_out_of_stock(expansion),
    do:
      dgettext("poland", "Boostera %{expansion} żaden polski sklep nie ma teraz na stanie.",
        expansion: expansion
      )

  @impl TcgCheapWeb.RegionText
  def product_out_of_stock(name),
    do:
      dgettext("poland", "%{name}: teraz żaden polski sklep nie ma tego produktu na stanie.",
        name: name
      )

  # The parcel was checked for Poland.
  @impl TcgCheapWeb.RegionText
  def cardmarket_delivery, do: dgettext("poland", "z wysyłką do Polski")

  # The rows say it beside each shop abroad.
  @impl TcgCheapWeb.RegionText
  def list_prices_note, do: nil

  @impl TcgCheapWeb.RegionText
  def foreign_shops_note, do: nil

  @impl TcgCheapWeb.RegionText
  def markdown_method(window),
    do: %{
      prices:
        "Ceny pochodzą z publicznych feedów produktowych sklepów, pobieranych raz dziennie. Ceny polskich sklepów nie obejmują dostawy, a sklepów za granicą obejmują wysyłkę do Polski.",
      good_price:
        "Dobra cena to najwyżej 95% typowej, normalna najwyżej 110%, powyżej jest drogo. Dobra cena musi też być najwyżej 95% zwykłej ceny produktu z ostatnich #{window} dni i trendu Cardmarket w złotych z przesyłką z Niemiec, gdy są znane.",
      few_shops:
        "Przy mniejszej liczbie sklepów nie ma oceny, a jako kontekst podajemy trend Cardmarket w złotych."
    }

  @impl TcgCheapWeb.RegionText
  def shop_prices_note(shipping),
    do:
      dgettext(
        "poland",
        "Ceny polskich sklepów są bez wysyłki, a sklepów z zagranicy – z wysyłką do Polski. Do Cardmarket doliczamy %{shipping} za paczkę z Niemiec.",
        shipping: shipping
      )
end
