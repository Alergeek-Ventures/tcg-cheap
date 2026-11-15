defmodule TcgCheap.Countries.Sweden do
  @moduledoc """
  Sweden: the guide's region `/se/` in kronor, and the words that name it
  (`TcgCheap.Country`). Singles have no market here yet: card prices are
  Cardmarket trends in kronor.
  """

  @behaviour TcgCheap.Country
  @behaviour TcgCheapWeb.RegionText

  use Gettext, backend: TcgCheapWeb.Gettext

  @impl TcgCheap.Country
  def code, do: "SE"

  @impl TcgCheap.Country
  def shipped_from, do: dgettext("sweden", "wysyłka ze Szwecji")

  @impl TcgCheap.Country
  def delivered_from, do: dgettext("sweden", "z wysyłką ze Szwecji")

  @impl TcgCheap.Country
  def region do
    %{
      code: "se",
      currency: "SEK",
      currency_symbol: "kr",
      # Shops price in whole kronor ("1 099 kr"), which prices show without
      # öre; cheap cards' converted trends keep them.
      decimals: 2,
      language: "sv",
      hreflang: "sv-SE",
      # DHL Paket 2 kg from Germany to Sweden (€14.49 online) plus
      # Cardmarket's €1 parcel packaging fee, checked 2026-11-14:
      # https://www.dhl.de/de/privatkunden/pakete-versenden/weltweit-versenden/land/schweden.html
      # https://help.cardmarket.com/en/ShippingCosts
      cardmarket_shipping_eur: Decimal.new("15.49"),
      slugs: %{products: "produkter", expansions: "set", cards: "kort"},
      pages: %{}
    }
  end

  @impl TcgCheapWeb.RegionText
  def name, do: dgettext("sweden", "Szwecja")

  @impl TcgCheapWeb.RegionText
  def hint, do: dgettext("sweden", "Wygląda na to, że jesteś w Szwecji.")

  @impl TcgCheapWeb.RegionText
  def hint_switch, do: dgettext("sweden", "Przejdź do wersji szwedzkiej")

  @impl TcgCheapWeb.RegionText
  def home_description,
    do:
      dgettext(
        "sweden",
        "Porównaj ceny Pokémon TCG w szwedzkich sklepach i w sklepach wysyłających do Szwecji. Sprawdź oferty boosterów, ETB i boxów, historię cen i czy warto kupić teraz."
      )

  @impl TcgCheapWeb.RegionText
  def social_promise,
    do:
      dgettext(
        "sweden",
        "Ceny Pokémon TCG w szwedzkich sklepach i w sklepach wysyłających do Szwecji, sprawdzane codziennie."
      )

  @impl TcgCheapWeb.RegionText
  def products_promise,
    do:
      dgettext(
        "sweden",
        "Najtańsze oferty Pokémon TCG w szwedzkich sklepach i w sklepach wysyłających do Szwecji."
      )

  @impl TcgCheapWeb.RegionText
  def cards_promise, do: cardmarket_cards()

  @impl TcgCheapWeb.RegionText
  def cards_answer, do: cardmarket_cards()

  defp cardmarket_cards,
    do: dgettext("sweden", "Angielskie karty Pokémon TCG z ceną z Cardmarket w koronach.")

  @impl TcgCheapWeb.RegionText
  def cards_title, do: dgettext("sweden", "Ceny kart Pokémon TCG w koronach")

  @impl TcgCheapWeb.RegionText
  def card_title(card),
    do: dgettext("sweden", "%{card} – cena karty Pokémon w koronach", card: card)

  @impl TcgCheapWeb.RegionText
  def expansion_fallback(expansion),
    do:
      dgettext(
        "sweden",
        "%{expansion}: porównaj ceny boosterów, ETB, boxów i kolekcji w szwedzkich sklepach i w sklepach wysyłających do Szwecji.",
        expansion: expansion
      )

  @impl TcgCheapWeb.RegionText
  def booster_out_of_stock(expansion),
    do:
      dgettext(
        "sweden",
        "Boostera %{expansion} żaden szwedzki sklep ani sklep wysyłający do Szwecji nie ma teraz na stanie.",
        expansion: expansion
      )

  @impl TcgCheapWeb.RegionText
  def product_out_of_stock(name),
    do:
      dgettext(
        "sweden",
        "%{name}: teraz żaden szwedzki sklep ani sklep wysyłający do Szwecji nie ma tego produktu na stanie.",
        name: name
      )

  @impl TcgCheapWeb.RegionText
  def cardmarket_delivery, do: dgettext("sweden", "z wysyłką z Niemiec")

  @impl TcgCheapWeb.RegionText
  def list_prices_note,
    do: dgettext("sweden", "Ceny ze sklepów z zagranicy są z wysyłką do Szwecji.")

  @impl TcgCheapWeb.RegionText
  def foreign_shops_note,
    do:
      dgettext(
        "sweden",
        "Sklepy z zagranicy sprzedają w swojej walucie. Ich ceny przeliczamy na korony po dziennych kursach NBP. Strona sklepu może być w innym języku."
      )

  @impl TcgCheapWeb.RegionText
  def markdown_method(window),
    do: %{
      prices:
        "Ceny pochodzą z publicznych list produktów i feedów sklepów, pobieranych raz dziennie, i są w koronach szwedzkich. Ceny szwedzkich sklepów nie obejmują dostawy, a sklepów za granicą obejmują wysyłkę do Szwecji.",
      good_price:
        "Dobra cena to najwyżej 95% typowej, normalna najwyżej 110%, powyżej jest drogo. Dobra cena musi też być najwyżej 95% zwykłej ceny produktu z ostatnich #{window} dni i trendu Cardmarket w koronach (po kursach NBP) z przesyłką z Niemiec, gdy są znane.",
      few_shops:
        "Przy mniejszej liczbie sklepów nie ma oceny, a jako kontekst podajemy trend Cardmarket w koronach."
    }

  @impl TcgCheapWeb.RegionText
  def shop_prices_note(shipping),
    do:
      dgettext(
        "sweden",
        "Ceny szwedzkich sklepów są bez wysyłki, a sklepów z zagranicy – z wysyłką do Szwecji. Do Cardmarket doliczamy %{shipping} za paczkę z Niemiec.",
        shipping: shipping
      )
end
