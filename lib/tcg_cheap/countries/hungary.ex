defmodule TcgCheap.Countries.Hungary do
  @moduledoc """
  Hungary: the guide's region `/hu/` in forints, and the words that name it
  (`TcgCheap.Country`). Singles have no shops here yet: card prices are
  Cardmarket trends in forints.
  """

  @behaviour TcgCheap.Country
  @behaviour TcgCheapWeb.RegionText

  use Gettext, backend: TcgCheapWeb.Gettext

  @impl TcgCheap.Country
  def code, do: "HU"

  @impl TcgCheap.Country
  def shipped_from, do: dgettext("hungary", "wysyłka z Węgier")

  @impl TcgCheap.Country
  def delivered_from, do: dgettext("hungary", "z wysyłką z Węgier")

  @impl TcgCheap.Country
  def region do
    %{
      code: "hu",
      currency: "HUF",
      currency_symbol: "Ft",
      decimals: 0,
      language: "hu",
      hreflang: "hu-HU",
      popular_languages: [],
      # The same EU tariff as Poland's: DHL Paket 2 kg (€14.49) plus
      # Cardmarket's €1 parcel packaging fee, checked 2026-11-14:
      # https://www.dhl.de/de/privatkunden/pakete-versenden/weltweit-versenden/land/ungarn.html
      # https://help.cardmarket.com/en/ShippingCosts
      cardmarket_shipping_eur: Decimal.new("15.49"),
      slugs: %{products: "termekek", expansions: "szettek", cards: "kartyak"},
      pages: %{}
    }
  end

  @impl TcgCheapWeb.RegionText
  def name, do: dgettext("hungary", "Węgry")

  @impl TcgCheapWeb.RegionText
  def hint, do: dgettext("hungary", "Wygląda na to, że jesteś na Węgrzech.")

  @impl TcgCheapWeb.RegionText
  def hint_switch, do: dgettext("hungary", "Przejdź do wersji węgierskiej")

  @impl TcgCheapWeb.RegionText
  def home_description,
    do:
      dgettext(
        "hungary",
        "Porównaj ceny Pokémon TCG w sklepach wysyłających na Węgry. Sprawdź oferty boosterów, ETB i boxów, historię cen i czy warto kupić teraz."
      )

  @impl TcgCheapWeb.RegionText
  def social_promise,
    do:
      dgettext(
        "hungary",
        "Ceny Pokémon TCG ze sklepów wysyłających na Węgry, sprawdzane codziennie."
      )

  @impl TcgCheapWeb.RegionText
  def products_promise,
    do: dgettext("hungary", "Najtańsze oferty Pokémon TCG w sklepach wysyłających na Węgry.")

  @impl TcgCheapWeb.RegionText
  def cards_promise, do: cardmarket_cards()

  @impl TcgCheapWeb.RegionText
  def cards_answer, do: cardmarket_cards()

  defp cardmarket_cards,
    do: dgettext("hungary", "Angielskie karty Pokémon TCG z ceną z Cardmarket w forintach.")

  @impl TcgCheapWeb.RegionText
  def cards_title, do: dgettext("hungary", "Ceny kart Pokémon TCG w forintach")

  @impl TcgCheapWeb.RegionText
  def card_title(card),
    do: dgettext("hungary", "%{card} – cena karty Pokémon w forintach", card: card)

  @impl TcgCheapWeb.RegionText
  def expansion_fallback(expansion),
    do:
      dgettext(
        "hungary",
        "%{expansion}: porównaj ceny boosterów, ETB, boxów i kolekcji w sklepach wysyłających na Węgry.",
        expansion: expansion
      )

  @impl TcgCheapWeb.RegionText
  def booster_out_of_stock(expansion),
    do:
      dgettext(
        "hungary",
        "Boostera %{expansion} żaden sklep wysyłający na Węgry nie ma teraz na stanie.",
        expansion: expansion
      )

  @impl TcgCheapWeb.RegionText
  def product_out_of_stock(name),
    do:
      dgettext(
        "hungary",
        "%{name}: teraz żaden sklep wysyłający na Węgry nie ma tego produktu na stanie.",
        name: name
      )

  @impl TcgCheapWeb.RegionText
  def cardmarket_delivery, do: dgettext("hungary", "z wysyłką z Niemiec")

  @impl TcgCheapWeb.RegionText
  def list_prices_note,
    do: dgettext("hungary", "Ceny ze sklepów z zagranicy są z wysyłką na Węgry.")

  @impl TcgCheapWeb.RegionText
  def foreign_shops_note,
    do:
      dgettext(
        "hungary",
        "Sklepy z zagranicy sprzedają w swojej walucie, polskie w złotych. Ich ceny przeliczamy na forinty po dziennych kursach NBP. Strona sklepu może być po polsku albo w innym języku."
      )

  @impl TcgCheapWeb.RegionText
  def markdown_method(window),
    do: %{
      prices:
        dgettext(
          "hungary",
          "Ceny pochodzą z publicznych feedów produktowych sklepów, pobieranych raz dziennie, i są w forintach. Ceny węgierskich sklepów nie obejmują dostawy, a sklepów za granicą obejmują wysyłkę na Węgry."
        ),
      good_price:
        dgettext(
          "hungary",
          "Dobra cena to najwyżej 95% typowej, normalna najwyżej 110%, powyżej jest drogo. Dobra cena musi też być najwyżej 95% zwykłej ceny produktu z ostatnich %{window} dni i trendu Cardmarket w forintach (po kursach NBP) z przesyłką z Niemiec, gdy są znane.",
          window: window
        ),
      few_shops:
        dgettext(
          "hungary",
          "Przy mniejszej liczbie sklepów nie ma oceny, a jako kontekst podajemy trend Cardmarket w forintach."
        )
    }

  @impl TcgCheapWeb.RegionText
  def shop_prices_note(shipping),
    do:
      dgettext(
        "hungary",
        "Ceny węgierskich sklepów są bez wysyłki, a sklepów z zagranicy – z wysyłką na Węgry. Do Cardmarket doliczamy %{shipping} za paczkę z Niemiec.",
        shipping: shipping
      )
end
