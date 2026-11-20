defmodule TcgCheap.Countries.Sweden do
  @moduledoc """
  Sweden: the guide's region `/se/` in kronor, and the words that name it
  (`TcgCheap.Country`).
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
      # Shops price in whole kronor ("1 099 kr") and Sweden has no öre coins,
      # so prices are written in whole kronor; only amounts under 10 kr, as
      # cheap cards' converted trends, keep öre – and only when they have any
      # ("8 kr", "3,50 kr").
      decimals: 2,
      whole_prices_from: Decimal.new(10),
      language: "sv",
      hreflang: "sv-SE",
      popular_languages: [],
      # Cardmarket total Prices including packaging, checked 2026-11-20:
      # https://help.cardmarket.com/en/ShippingCosts
      # German Standardbrief through €25, then domestic Insured Letter (Rek).
      cardmarket_untracked_letter_eur: Decimal.new("1.55"),
      cardmarket_tracked_letter_eur: Decimal.new("11.11"),
      # Cheapest tracked parcel from Germany up to 2 kg: DHL Paket Online.
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
  def location_outside,
    do: dgettext("sweden", "Ta lokalizacja jest poza Szwecją. Wpisz miejscowość.")

  @impl TcgCheapWeb.RegionText
  def town_example, do: dgettext("sweden", "np. Göteborg")

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
  def cards_promise,
    do:
      dgettext(
        "sweden",
        "Najtańsze karty Pokémon TCG w szwedzkich sklepach i w sklepach wysyłających do Szwecji."
      )

  @impl TcgCheapWeb.RegionText
  def cards_answer,
    do:
      dgettext(
        "sweden",
        "Angielskie karty Pokémon TCG w szwedzkich sklepach i w sklepach wysyłających do Szwecji."
      )

  @impl TcgCheapWeb.RegionText
  def cards_title, do: dgettext("sweden", "Ceny kart Pokémon TCG w Szwecji")

  @impl TcgCheapWeb.RegionText
  def card_title(card),
    do: dgettext("sweden", "%{card} – cena karty Pokémon w Szwecji", card: card)

  @impl TcgCheapWeb.RegionText
  def card_description(name, number, price),
    do:
      dgettext(
        "sweden",
        "%{name} %{number}: od %{price} w szwedzkich sklepach i w sklepach wysyłających do Szwecji.",
        name: name,
        number: number,
        price: price
      )

  @impl TcgCheapWeb.RegionText
  def cards_in_stock(cards),
    do:
      dgettext(
        "sweden",
        "Angielskie karty Pokémon TCG w szwedzkich sklepach i w sklepach wysyłających do Szwecji: %{cards} na stanie.",
        cards: cards
      )

  @impl TcgCheapWeb.RegionText
  def card_unavailable, do: dgettext("sweden", "Brak w szwedzkich sklepach")

  @impl TcgCheapWeb.RegionText
  def card_unavailable_note, do: dgettext("sweden", "Brak na stanie w szwedzkich sklepach")

  @impl TcgCheapWeb.RegionText
  def card_method(shops),
    do:
      dgettext(
        "sweden",
        "Typowa cena to środek stawki: z każdego szwedzkiego sklepu, który ma kartę na stanie, bierzemy najtańszą ofertę (potrzebujemy co najmniej %{shops}). Dobra cena jest co najmniej 5% niższa od typowej i od Cardmarket z wysyłką. Normalna – najwyżej 10% wyższa od typowej. Wyższa – drogo. Ceny szwedzkich sklepów są bez dostawy, zagranicznych – z wysyłką do Szwecji.",
        shops: shops
      )

  @impl TcgCheapWeb.RegionText
  def card_prices_note,
    do:
      dgettext(
        "sweden",
        "Ceny bez dostawy, poza oznaczonymi „z wysyłką”, albo trend Cardmarket w koronach, co tańsze."
      )

  @impl TcgCheapWeb.RegionText
  def cardmarket_card_delivery, do: dgettext("sweden", "z wysyłką do Szwecji")

  @impl TcgCheapWeb.RegionText
  def singles_prices_note,
    do:
      dgettext(
        "sweden",
        "Ceny bez dostawy, poza oznaczonymi „z wysyłką”."
      )

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
        "Cena sklepu z zagranicy to ta, którą sklep podaje kupującym ze Szwecji. Gdy podaje ją tylko w swojej walucie, przeliczamy ją na korony po dziennych kursach NBP. Strona sklepu może być w innym języku."
      )

  @impl TcgCheapWeb.RegionText
  def markdown_method(window),
    do: %{
      prices:
        dgettext(
          "sweden",
          "Ceny pochodzą z publicznych list produktów i feedów sklepów, pobieranych raz dziennie, i są w koronach szwedzkich. Ceny szwedzkich sklepów nie obejmują dostawy, a sklepów za granicą obejmują wysyłkę do Szwecji."
        ),
      good_price:
        dgettext(
          "sweden",
          "Dobra cena to najwyżej 95% typowej, normalna najwyżej 110%, powyżej jest drogo. Dobra cena musi też być najwyżej 95% zwykłej ceny produktu z ostatnich %{window} dni i trendu Cardmarket w koronach (po kursach NBP) z przesyłką z Niemiec, gdy są znane.",
          window: window
        ),
      few_shops:
        dgettext(
          "sweden",
          "Przy mniejszej liczbie sklepów nie ma oceny, a jako kontekst podajemy trend Cardmarket w koronach."
        )
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
