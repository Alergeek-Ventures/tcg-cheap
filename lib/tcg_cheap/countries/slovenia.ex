defmodule TcgCheap.Countries.Slovenia do
  @moduledoc """
  Slovenia: the guide's region `/si/` in euro, and the words that name it
  (`TcgCheap.Country`).
  """

  @behaviour TcgCheap.Country
  @behaviour TcgCheapWeb.RegionText

  use Gettext, backend: TcgCheapWeb.Gettext

  @impl TcgCheap.Country
  def code, do: "SI"

  @impl TcgCheap.Country
  def shipped_from, do: dgettext("slovenia", "wysyłka ze Słowenii")

  @impl TcgCheap.Country
  def delivered_from, do: dgettext("slovenia", "z wysyłką ze Słowenii")

  @impl TcgCheap.Country
  def region do
    %{
      code: "si",
      currency: "EUR",
      currency_symbol: "€",
      decimals: 2,
      language: "sl",
      hreflang: "sl-SI",
      popular_languages: [],
      # Cheaper domestic/German total Prices including packaging, checked 2026-11-20:
      # https://help.cardmarket.com/en/ShippingCosts
      # Domestic methods except €200–€500 and €4,200–€5,000, where Germany is
      # cheaper; the final tiers are insured-courier estimates, not fixed quotes.
      cardmarket_letter_tiers: [
        {Decimal.new("25"), Decimal.new("1.55"), :letter},
        {Decimal.new("100"), Decimal.new("2.80"), :tracked_letter},
        {Decimal.new("150"), Decimal.new("7.87"), :tracked_parcel},
        {Decimal.new("200"), Decimal.new("12.43"), :insured_parcel},
        {Decimal.new("400"), Decimal.new("15.49"), :tracked_parcel},
        {Decimal.new("500"), Decimal.new("15.49"), :tracked_parcel},
        {Decimal.new("1000"), Decimal.new("31.30"), :insured_parcel},
        {Decimal.new("2000"), Decimal.new("31.30"), :insured_parcel},
        {Decimal.new("2500"), Decimal.new("31.30"), :insured_parcel},
        {Decimal.new("4200"), Decimal.new("31.30"), :insured_parcel},
        {Decimal.new("5000"), Decimal.new("122.00"), :insured_parcel},
        {Decimal.new("10000"), Decimal.new("150.00"), :insured_courier_estimate},
        {Decimal.new("20000"), Decimal.new("150.00"), :insured_courier_estimate},
        {Decimal.new("150000"), Decimal.new("150.00"), :insured_courier_estimate}
      ],
      # Cheapest tracked parcel from Germany up to 2 kg: DHL Paket Online.
      cardmarket_shipping_eur: Decimal.new("15.49"),
      slugs: %{products: "izdelki", expansions: "seti", cards: "karte"},
      pages: %{}
    }
  end

  @impl TcgCheapWeb.RegionText
  def name, do: dgettext("slovenia", "Słowenia")

  @impl TcgCheapWeb.RegionText
  def hint, do: dgettext("slovenia", "Wygląda na to, że jesteś w Słowenii.")

  @impl TcgCheapWeb.RegionText
  def hint_switch, do: dgettext("slovenia", "Przejdź do wersji słoweńskiej")

  @impl TcgCheapWeb.RegionText
  def location_outside,
    do: dgettext("slovenia", "Ta lokalizacja jest poza Słowenią. Wpisz miejscowość.")

  @impl TcgCheapWeb.RegionText
  def town_example, do: dgettext("slovenia", "np. Maribor")

  @impl TcgCheapWeb.RegionText
  def home_description,
    do:
      dgettext(
        "slovenia",
        "Porównaj ceny Pokémon TCG w sklepach wysyłających do Słowenii. Sprawdź oferty boosterów, ETB i boxów, historię cen i czy warto kupić teraz."
      )

  @impl TcgCheapWeb.RegionText
  def social_promise,
    do:
      dgettext(
        "slovenia",
        "Ceny Pokémon TCG ze sklepów wysyłających do Słowenii, sprawdzane codziennie."
      )

  @impl TcgCheapWeb.RegionText
  def products_promise,
    do: dgettext("slovenia", "Najtańsze oferty Pokémon TCG w sklepach wysyłających do Słowenii.")

  @impl TcgCheapWeb.RegionText
  def cards_promise,
    do: dgettext("slovenia", "Najtańsze karty Pokémon TCG w sklepach wysyłających do Słowenii.")

  @impl TcgCheapWeb.RegionText
  def cards_answer,
    do: dgettext("slovenia", "Angielskie karty Pokémon TCG w sklepach wysyłających do Słowenii.")

  @impl TcgCheapWeb.RegionText
  def cards_title, do: dgettext("slovenia", "Ceny kart Pokémon TCG w Słowenii")

  @impl TcgCheapWeb.RegionText
  def card_title(card),
    do: dgettext("slovenia", "%{card} – cena karty Pokémon w Słowenii", card: card)

  @impl TcgCheapWeb.RegionText
  def card_description(name, number, price),
    do:
      dgettext("slovenia", "%{name} %{number}: od %{price} w sklepach wysyłających do Słowenii.",
        name: name,
        number: number,
        price: price
      )

  @impl TcgCheapWeb.RegionText
  def cards_in_stock(cards),
    do:
      dgettext(
        "slovenia",
        "Angielskie karty Pokémon TCG w sklepach wysyłających do Słowenii: %{cards} na stanie.",
        cards: cards
      )

  @impl TcgCheapWeb.RegionText
  def card_unavailable, do: dgettext("slovenia", "Brak w słoweńskich sklepach")

  @impl TcgCheapWeb.RegionText
  def card_unavailable_delivering,
    do: dgettext("slovenia", "Brak w sklepach wysyłających do Słowenii")

  @impl TcgCheapWeb.RegionText
  def card_unavailable_note, do: dgettext("slovenia", "Brak na stanie w słoweńskich sklepach")

  @impl TcgCheapWeb.RegionText
  def card_method(shops),
    do:
      dgettext(
        "slovenia",
        "Typowa cena to środek stawki: z każdego słoweńskiego sklepu, który ma kartę na stanie, bierzemy najtańszą ofertę (potrzebujemy co najmniej %{shops}). Dobra cena jest co najmniej 5% niższa od typowej i od Cardmarket z wysyłką. Normalna – najwyżej 10% wyższa od typowej. Wyższa – drogo. Ceny słoweńskich sklepów są bez dostawy, zagranicznych – z wysyłką do Słowenii.",
        shops: shops
      )

  @impl TcgCheapWeb.RegionText
  def card_prices_note,
    do:
      dgettext(
        "slovenia",
        "Ceny bez dostawy (z zagranicy z wysyłką) albo trend Cardmarket w euro, co tańsze."
      )

  @impl TcgCheapWeb.RegionText
  def cardmarket_card_delivery, do: dgettext("slovenia", "z wysyłką do Słowenii")

  @impl TcgCheapWeb.RegionText
  def singles_prices_note,
    do: dgettext("slovenia", "Ceny bez dostawy. Z zagranicy: z wysyłką do Słowenii.")

  @impl TcgCheapWeb.RegionText
  def expansion_fallback(expansion),
    do:
      dgettext(
        "slovenia",
        "%{expansion}: porównaj ceny boosterów, ETB, boxów i kolekcji w sklepach wysyłających do Słowenii.",
        expansion: expansion
      )

  @impl TcgCheapWeb.RegionText
  def booster_out_of_stock(expansion),
    do:
      dgettext(
        "slovenia",
        "Boostera %{expansion} żaden sklep wysyłający do Słowenii nie ma teraz na stanie.",
        expansion: expansion
      )

  @impl TcgCheapWeb.RegionText
  def product_out_of_stock(name),
    do:
      dgettext(
        "slovenia",
        "%{name}: teraz żaden sklep wysyłający do Słowenii nie ma tego produktu na stanie.",
        name: name
      )

  @impl TcgCheapWeb.RegionText
  def cardmarket_delivery, do: dgettext("slovenia", "z wysyłką z Niemiec")

  @impl TcgCheapWeb.RegionText
  def list_prices_note,
    do: dgettext("slovenia", "Ceny ze sklepów z zagranicy są z wysyłką do Słowenii.")

  @impl TcgCheapWeb.RegionText
  def foreign_shops_note,
    do:
      dgettext(
        "slovenia",
        "Cena sklepu z zagranicy to ta, którą sklep podaje kupującym ze Słowenii. Ceny w innej walucie niż euro przeliczamy po dziennych kursach NBP. Strona sklepu może być w innym języku."
      )

  @impl TcgCheapWeb.RegionText
  def markdown_method(window),
    do: %{
      prices:
        dgettext(
          "slovenia",
          "Ceny pochodzą z publicznych feedów produktowych sklepów, pobieranych raz dziennie, i są w euro. Ceny słoweńskich sklepów nie obejmują dostawy, a sklepów za granicą obejmują wysyłkę do Słowenii."
        ),
      good_price:
        dgettext(
          "slovenia",
          "Dobra cena to najwyżej 95% typowej, normalna najwyżej 110%, powyżej jest drogo. Dobra cena musi też być najwyżej 95% zwykłej ceny produktu z ostatnich %{window} dni i trendu Cardmarket w euro z przesyłką z Niemiec, gdy są znane.",
          window: window
        ),
      few_shops:
        dgettext(
          "slovenia",
          "Przy mniejszej liczbie sklepów nie ma oceny, a jako kontekst podajemy trend Cardmarket w euro."
        )
    }

  @impl TcgCheapWeb.RegionText
  def shop_prices_note(shipping),
    do:
      dgettext(
        "slovenia",
        "Ceny słoweńskich sklepów są bez wysyłki, a sklepów z zagranicy – z wysyłką do Słowenii. Do Cardmarket doliczamy %{shipping} za paczkę z Niemiec.",
        shipping: shipping
      )
end
