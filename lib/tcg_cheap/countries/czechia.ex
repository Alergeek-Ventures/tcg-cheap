defmodule TcgCheap.Countries.Czechia do
  @moduledoc """
  Czechia: the guide's region `/cz/` in Czech koruna, and the words that name it
  (`TcgCheap.Country`).
  """

  @behaviour TcgCheap.Country
  @behaviour TcgCheapWeb.RegionText

  use Gettext, backend: TcgCheapWeb.Gettext

  @impl TcgCheap.Country
  def code, do: "CZ"

  @impl TcgCheap.Country
  def shipped_from, do: dgettext("czechia", "wysyłka z Czech")

  @impl TcgCheap.Country
  def delivered_from, do: dgettext("czechia", "z wysyłką z Czech")

  @impl TcgCheap.Country
  def region do
    %{
      code: "cz",
      currency: "CZK",
      currency_symbol: "Kč",
      decimals: 0,
      language: "cs",
      hreflang: "cs-CZ",
      # Slovak is read here too, but the guide has no Slovak interface yet.
      popular_languages: [],
      # Cheaper domestic/German total Prices including packaging, checked 2026-11-20:
      # https://help.cardmarket.com/en/ShippingCosts
      # German Standardbrief through €25, insured domestic letters through €10,000,
      # then the lower German insured-courier estimate (not a fixed courier quote).
      cardmarket_letter_tiers: [
        {Decimal.new("25"), Decimal.new("1.55"), :letter},
        {Decimal.new("60"), Decimal.new("3.85"), :tracked_letter},
        {Decimal.new("200"), Decimal.new("4.95"), :insured_letter},
        {Decimal.new("1200"), Decimal.new("5.54"), :insured_letter},
        {Decimal.new("2400"), Decimal.new("7.31"), :insured_letter},
        {Decimal.new("2500"), Decimal.new("19.70"), :insured_letter},
        {Decimal.new("5000"), Decimal.new("19.70"), :insured_letter},
        {Decimal.new("10000"), Decimal.new("19.70"), :insured_letter},
        {Decimal.new("20000"), Decimal.new("150.00"), :insured_courier_estimate},
        {Decimal.new("150000"), Decimal.new("150.00"), :insured_courier_estimate}
      ],
      # Cheapest tracked parcel from Germany up to 2 kg: DHL Paket Online.
      cardmarket_shipping_eur: Decimal.new("15.49"),
      slugs: %{products: "produkty", expansions: "sety", cards: "karty"},
      pages: %{}
    }
  end

  @impl TcgCheapWeb.RegionText
  def name, do: dgettext("czechia", "Czechy")

  @impl TcgCheapWeb.RegionText
  def hint, do: dgettext("czechia", "Wygląda na to, że jesteś w Czechach.")

  @impl TcgCheapWeb.RegionText
  def hint_switch, do: dgettext("czechia", "Przejdź do wersji czeskiej")

  @impl TcgCheapWeb.RegionText
  def location_outside,
    do: dgettext("czechia", "Ta lokalizacja jest poza Czechami. Wpisz miejscowość.")

  @impl TcgCheapWeb.RegionText
  def town_example, do: dgettext("czechia", "np. Brno")

  @impl TcgCheapWeb.RegionText
  def home_description,
    do:
      dgettext(
        "czechia",
        "Porównaj ceny Pokémon TCG w sklepach wysyłających do Czech. Sprawdź oferty boosterów, ETB i boxów, historię cen i czy warto kupić teraz."
      )

  @impl TcgCheapWeb.RegionText
  def social_promise,
    do:
      dgettext(
        "czechia",
        "Ceny Pokémon TCG ze sklepów wysyłających do Czech, sprawdzane codziennie."
      )

  @impl TcgCheapWeb.RegionText
  def products_promise,
    do: dgettext("czechia", "Najtańsze oferty Pokémon TCG w sklepach wysyłających do Czech.")

  @impl TcgCheapWeb.RegionText
  def cards_promise,
    do: dgettext("czechia", "Najtańsze karty Pokémon TCG w sklepach wysyłających do Czech.")

  @impl TcgCheapWeb.RegionText
  def cards_answer,
    do: dgettext("czechia", "Angielskie karty Pokémon TCG w sklepach wysyłających do Czech.")

  @impl TcgCheapWeb.RegionText
  def cards_title, do: dgettext("czechia", "Ceny kart Pokémon TCG w Czechach")

  @impl TcgCheapWeb.RegionText
  def card_title(card),
    do: dgettext("czechia", "%{card} – cena karty Pokémon w Czechach", card: card)

  @impl TcgCheapWeb.RegionText
  def card_description(name, number, price),
    do:
      dgettext("czechia", "%{name} %{number}: od %{price} w sklepach wysyłających do Czech.",
        name: name,
        number: number,
        price: price
      )

  @impl TcgCheapWeb.RegionText
  def cards_in_stock(cards),
    do:
      dgettext(
        "czechia",
        "Angielskie karty Pokémon TCG w sklepach wysyłających do Czech: %{cards} na stanie.",
        cards: cards
      )

  @impl TcgCheapWeb.RegionText
  def card_unavailable, do: dgettext("czechia", "Brak w czeskich sklepach")

  @impl TcgCheapWeb.RegionText
  def card_unavailable_delivering,
    do: dgettext("czechia", "Brak w sklepach wysyłających do Czech")

  @impl TcgCheapWeb.RegionText
  def card_unavailable_note, do: dgettext("czechia", "Brak na stanie w czeskich sklepach")

  @impl TcgCheapWeb.RegionText
  def card_method(shops),
    do:
      dgettext(
        "czechia",
        "Typowa cena to środek stawki: z każdego czeskiego sklepu, który ma kartę na stanie, bierzemy najtańszą ofertę (potrzebujemy co najmniej %{shops}). Dobra cena jest co najmniej 5% niższa od typowej i od Cardmarket z wysyłką. Normalna – najwyżej 10% wyższa od typowej. Wyższa – drogo. Ceny czeskich sklepów są bez dostawy, zagranicznych – z wysyłką do Czech.",
        shops: shops
      )

  @impl TcgCheapWeb.RegionText
  def card_prices_note,
    do:
      dgettext(
        "czechia",
        "Ceny bez dostawy, poza oznaczonymi „z wysyłką”, albo trend Cardmarket w koronach czeskich, co tańsze."
      )

  @impl TcgCheapWeb.RegionText
  def cardmarket_card_delivery, do: dgettext("czechia", "z wysyłką do Czech")

  @impl TcgCheapWeb.RegionText
  def singles_prices_note,
    do:
      dgettext(
        "czechia",
        "Ceny bez dostawy, poza oznaczonymi „z wysyłką”."
      )

  @impl TcgCheapWeb.RegionText
  def expansion_fallback(expansion),
    do:
      dgettext(
        "czechia",
        "%{expansion}: porównaj ceny boosterów, ETB, boxów i kolekcji w sklepach wysyłających do Czech.",
        expansion: expansion
      )

  @impl TcgCheapWeb.RegionText
  def booster_out_of_stock(expansion),
    do:
      dgettext(
        "czechia",
        "Boostera %{expansion} żaden sklep wysyłający do Czech nie ma teraz na stanie.",
        expansion: expansion
      )

  @impl TcgCheapWeb.RegionText
  def product_out_of_stock(name),
    do:
      dgettext(
        "czechia",
        "%{name}: teraz żaden sklep wysyłający do Czech nie ma tego produktu na stanie.",
        name: name
      )

  @impl TcgCheapWeb.RegionText
  def cardmarket_delivery, do: dgettext("czechia", "z wysyłką z Niemiec")

  @impl TcgCheapWeb.RegionText
  def list_prices_note,
    do: dgettext("czechia", "Ceny ze sklepów z zagranicy są z wysyłką do Czech.")

  @impl TcgCheapWeb.RegionText
  def foreign_shops_note,
    do:
      dgettext(
        "czechia",
        "Cena sklepu z zagranicy to ta, którą sklep podaje kupującym z Czech. Ceny w innej walucie niż korona czeska przeliczamy po dziennych kursach NBP. Strona sklepu może być w innym języku."
      )

  @impl TcgCheapWeb.RegionText
  def markdown_method(window),
    do: %{
      prices:
        dgettext(
          "czechia",
          "Ceny pochodzą z publicznych list produktów sklepów, pobieranych raz dziennie, i są w koronach czeskich. Ceny czeskich sklepów nie obejmują dostawy, a sklepów za granicą obejmują wysyłkę do Czech."
        ),
      good_price:
        dgettext(
          "czechia",
          "Dobra cena to najwyżej 95% typowej, normalna najwyżej 110%, powyżej jest drogo. Dobra cena musi też być najwyżej 95% zwykłej ceny produktu z ostatnich %{window} dni i trendu Cardmarket w koronach czeskich (po kursach NBP) z przesyłką z Niemiec, gdy są znane.",
          window: window
        ),
      few_shops:
        dgettext(
          "czechia",
          "Przy mniejszej liczbie sklepów nie ma oceny, a jako kontekst podajemy trend Cardmarket w koronach czeskich."
        )
    }

  @impl TcgCheapWeb.RegionText
  def shop_prices_note(shipping),
    do:
      dgettext(
        "czechia",
        "Ceny czeskich sklepów są bez wysyłki, a sklepów z zagranicy – z wysyłką do Czech. Do Cardmarket doliczamy %{shipping} za paczkę z Niemiec.",
        shipping: shipping
      )
end
