defmodule TcgCheap.Countries.Portugal do
  @moduledoc """
  Portugal: the guide's region `/pt/` in euro, with prices from Portuguese
  shops and shops abroad that deliver there.
  """

  @behaviour TcgCheap.Country
  @behaviour TcgCheapWeb.RegionText

  use Gettext, backend: TcgCheapWeb.Gettext

  @impl TcgCheap.Country
  def code, do: "PT"

  @impl TcgCheap.Country
  def shipped_from, do: dgettext("portugal", "wysyłka z Portugalii")

  @impl TcgCheap.Country
  def delivered_from, do: dgettext("portugal", "z wysyłką z Portugalii")

  @impl TcgCheap.Country
  def region do
    %{
      code: "pt",
      currency: "EUR",
      currency_symbol: "€",
      decimals: 2,
      language: "pt",
      hreflang: "pt-PT",
      popular_languages: [],
      # Cheaper domestic/German total Prices including packaging, checked 2026-11-20:
      # https://help.cardmarket.com/en/ShippingCosts
      # German Standardbrief through €25 and its tracked parcel at €200–€500;
      # otherwise domestic methods, with insured-courier estimates at the top.
      cardmarket_letter_tiers: [
        {Decimal.new("25"), Decimal.new("1.55"), :letter},
        {Decimal.new("100"), Decimal.new("5.10"), :tracked_letter},
        {Decimal.new("200"), Decimal.new("9.99"), :tracked_parcel},
        {Decimal.new("400"), Decimal.new("15.49"), :tracked_parcel},
        {Decimal.new("500"), Decimal.new("15.49"), :tracked_parcel},
        {Decimal.new("1000"), Decimal.new("20.15"), :insured_parcel},
        {Decimal.new("2000"), Decimal.new("34.08"), :insured_parcel},
        {Decimal.new("2500"), Decimal.new("34.08"), :insured_parcel},
        {Decimal.new("5000"), Decimal.new("56.33"), :insured_parcel},
        {Decimal.new("10000"), Decimal.new("150.00"), :insured_courier_estimate},
        {Decimal.new("20000"), Decimal.new("150.00"), :insured_courier_estimate},
        {Decimal.new("150000"), Decimal.new("150.00"), :insured_courier_estimate}
      ],
      # Cheapest tracked parcel from Germany up to 2 kg: DHL Paket Online.
      cardmarket_shipping_eur: Decimal.new("15.49"),
      slugs: %{products: "produtos", expansions: "expansoes", cards: "cartas"},
      pages: %{}
    }
  end

  @impl TcgCheapWeb.RegionText
  def name, do: dgettext("portugal", "Portugalia")

  @impl TcgCheapWeb.RegionText
  def hint, do: dgettext("portugal", "Wygląda na to, że jesteś w Portugalii.")

  @impl TcgCheapWeb.RegionText
  def hint_switch, do: dgettext("portugal", "Przejdź do wersji portugalskiej")

  @impl TcgCheapWeb.RegionText
  def location_outside,
    do: dgettext("portugal", "Ta lokalizacja jest poza Portugalią. Wpisz miejscowość.")

  @impl TcgCheapWeb.RegionText
  def town_example, do: dgettext("portugal", "np. Porto")

  @impl TcgCheapWeb.RegionText
  def home_description,
    do:
      dgettext(
        "portugal",
        "Porównaj ceny Pokémon TCG w sklepach wysyłających do Portugalii. Sprawdź oferty boosterów, ETB i boxów, historię cen i czy warto kupić teraz."
      )

  @impl TcgCheapWeb.RegionText
  def social_promise,
    do:
      dgettext(
        "portugal",
        "Ceny Pokémon TCG ze sklepów wysyłających do Portugalii, sprawdzane codziennie."
      )

  @impl TcgCheapWeb.RegionText
  def products_promise,
    do:
      dgettext("portugal", "Najtańsze oferty Pokémon TCG w sklepach wysyłających do Portugalii.")

  @impl TcgCheapWeb.RegionText
  def cards_promise,
    do: dgettext("portugal", "Najtańsze karty Pokémon TCG w sklepach wysyłających do Portugalii.")

  @impl TcgCheapWeb.RegionText
  def cards_answer,
    do:
      dgettext("portugal", "Angielskie karty Pokémon TCG w sklepach wysyłających do Portugalii.")

  @impl TcgCheapWeb.RegionText
  def cards_title, do: dgettext("portugal", "Ceny kart Pokémon TCG w Portugalii")

  @impl TcgCheapWeb.RegionText
  def card_title(card),
    do: dgettext("portugal", "%{card} – cena karty Pokémon w Portugalii", card: card)

  @impl TcgCheapWeb.RegionText
  def card_description(name, number, price),
    do:
      dgettext(
        "portugal",
        "%{name} %{number}: od %{price} w sklepach wysyłających do Portugalii.",
        name: name,
        number: number,
        price: price
      )

  @impl TcgCheapWeb.RegionText
  def cards_in_stock(cards),
    do:
      dgettext(
        "portugal",
        "Angielskie karty Pokémon TCG w sklepach wysyłających do Portugalii: %{cards} na stanie.",
        cards: cards
      )

  @impl TcgCheapWeb.RegionText
  def card_unavailable, do: dgettext("portugal", "Brak w portugalskich sklepach")

  @impl TcgCheapWeb.RegionText
  def card_unavailable_delivering,
    do: dgettext("portugal", "Brak w sklepach wysyłających do Portugalii")

  @impl TcgCheapWeb.RegionText
  def card_unavailable_note, do: dgettext("portugal", "Brak na stanie w portugalskich sklepach")

  @impl TcgCheapWeb.RegionText
  def card_method(shops),
    do:
      dgettext(
        "portugal",
        "Typowa cena to środek stawki: z każdego portugalskiego sklepu, który ma kartę na stanie, bierzemy najtańszą ofertę (potrzebujemy co najmniej %{shops}). Dobra cena jest co najmniej 5% niższa od typowej i od Cardmarket z wysyłką. Normalna – najwyżej 10% wyższa od typowej. Wyższa – drogo. Ceny portugalskich sklepów są bez dostawy, zagranicznych – z wysyłką do Portugalii.",
        shops: shops
      )

  @impl TcgCheapWeb.RegionText
  def card_prices_note,
    do:
      dgettext(
        "portugal",
        "Ceny bez dostawy (z zagranicy z wysyłką) albo trend Cardmarket w euro, co tańsze."
      )

  @impl TcgCheapWeb.RegionText
  def cardmarket_card_delivery, do: dgettext("portugal", "z wysyłką do Portugalii")

  @impl TcgCheapWeb.RegionText
  def singles_prices_note,
    do: dgettext("portugal", "Ceny bez dostawy. Z zagranicy: z wysyłką do Portugalii.")

  @impl TcgCheapWeb.RegionText
  def expansion_fallback(expansion),
    do:
      dgettext(
        "portugal",
        "%{expansion}: porównaj ceny boosterów, ETB, boxów i kolekcji w sklepach wysyłających do Portugalii.",
        expansion: expansion
      )

  @impl TcgCheapWeb.RegionText
  def booster_out_of_stock(expansion),
    do:
      dgettext(
        "portugal",
        "Boostera %{expansion} żaden sklep wysyłający do Portugalii nie ma teraz na stanie.",
        expansion: expansion
      )

  @impl TcgCheapWeb.RegionText
  def product_out_of_stock(name),
    do:
      dgettext(
        "portugal",
        "%{name}: teraz żaden sklep wysyłający do Portugalii nie ma tego produktu na stanie.",
        name: name
      )

  @impl TcgCheapWeb.RegionText
  def cardmarket_delivery, do: dgettext("portugal", "z wysyłką z Niemiec")

  @impl TcgCheapWeb.RegionText
  def list_prices_note,
    do: dgettext("portugal", "Ceny ze sklepów z zagranicy są z wysyłką do Portugalii.")

  @impl TcgCheapWeb.RegionText
  def foreign_shops_note,
    do:
      dgettext(
        "portugal",
        "Cena sklepu z zagranicy to ta, którą sklep podaje kupującym z Portugalii. Ceny w innej walucie niż euro przeliczamy po dziennych kursach NBP. Strona sklepu może być w innym języku."
      )

  @impl TcgCheapWeb.RegionText
  def markdown_method(window),
    do: %{
      prices:
        dgettext(
          "portugal",
          "Ceny pochodzą z publicznych feedów produktowych sklepów, pobieranych raz dziennie, i są w euro. Ceny portugalskich sklepów nie obejmują dostawy, a sklepów za granicą obejmują wysyłkę do Portugalii."
        ),
      good_price:
        dgettext(
          "portugal",
          "Dobra cena to najwyżej 95% typowej, normalna najwyżej 110%, powyżej jest drogo. Dobra cena musi też być najwyżej 95% zwykłej ceny produktu z ostatnich %{window} dni i trendu Cardmarket w euro z przesyłką z Niemiec, gdy są znane.",
          window: window
        ),
      few_shops:
        dgettext(
          "portugal",
          "Przy mniejszej liczbie sklepów nie ma oceny, a jako kontekst podajemy trend Cardmarket w euro."
        )
    }

  @impl TcgCheapWeb.RegionText
  def shop_prices_note(shipping),
    do:
      dgettext(
        "portugal",
        "Ceny portugalskich sklepów są bez wysyłki, a sklepów z zagranicy – z wysyłką do Portugalii. Do Cardmarket doliczamy %{shipping} za paczkę z Niemiec.",
        shipping: shipping
      )
end
