defmodule TcgCheap.Countries.Netherlands do
  @moduledoc """
  The Netherlands: the guide's region `/nl/` in euro, and the words that name
  it (`TcgCheap.Country`).
  """

  @behaviour TcgCheap.Country
  @behaviour TcgCheapWeb.RegionText

  use Gettext, backend: TcgCheapWeb.Gettext

  @impl TcgCheap.Country
  def code, do: "NL"

  @impl TcgCheap.Country
  def shipped_from, do: dgettext("netherlands", "wysyłka z Holandii")

  @impl TcgCheap.Country
  def delivered_from, do: dgettext("netherlands", "z wysyłką z Holandii")

  @impl TcgCheap.Country
  def region do
    %{
      code: "nl",
      currency: "EUR",
      currency_symbol: "€",
      decimals: 2,
      language: "nl",
      hreflang: "nl-NL",
      popular_languages: [],
      # DHL's Paket 2 kg from Germany to the Netherlands costs the same as to
      # Hungary, Sweden and Croatia (€14.49 online, checked 2026-11-15), plus
      # Cardmarket's €1 packaging fee:
      # https://www.dhl.de/de/privatkunden/pakete-versenden/weltweit-versenden/land/niederlande.html
      cardmarket_shipping_eur: Decimal.new("15.49"),
      slugs: %{products: "producten", expansions: "sets", cards: "kaarten"},
      pages: %{}
    }
  end

  @impl TcgCheapWeb.RegionText
  def name, do: dgettext("netherlands", "Holandia")

  @impl TcgCheapWeb.RegionText
  def hint, do: dgettext("netherlands", "Wygląda na to, że jesteś w Holandii.")

  @impl TcgCheapWeb.RegionText
  def hint_switch, do: dgettext("netherlands", "Przejdź do wersji holenderskiej")

  @impl TcgCheapWeb.RegionText
  def location_outside,
    do: dgettext("netherlands", "Ta lokalizacja jest poza Holandią. Wpisz miejscowość.")

  @impl TcgCheapWeb.RegionText
  def town_example, do: dgettext("netherlands", "np. Utrecht")

  @impl TcgCheapWeb.RegionText
  def home_description,
    do:
      dgettext(
        "netherlands",
        "Porównaj ceny Pokémon TCG w holenderskich sklepach i w sklepach wysyłających do Holandii. Sprawdź oferty boosterów, ETB i boxów, historię cen i czy warto kupić teraz."
      )

  @impl TcgCheapWeb.RegionText
  def social_promise,
    do:
      dgettext(
        "netherlands",
        "Ceny Pokémon TCG w holenderskich sklepach i w sklepach wysyłających do Holandii, sprawdzane codziennie."
      )

  @impl TcgCheapWeb.RegionText
  def products_promise,
    do:
      dgettext(
        "netherlands",
        "Najtańsze oferty Pokémon TCG w holenderskich sklepach i w sklepach wysyłających do Holandii."
      )

  @impl TcgCheapWeb.RegionText
  def cards_promise,
    do:
      dgettext(
        "netherlands",
        "Najtańsze karty Pokémon TCG w holenderskich sklepach i w sklepach wysyłających do Holandii."
      )

  @impl TcgCheapWeb.RegionText
  def cards_answer,
    do:
      dgettext(
        "netherlands",
        "Angielskie karty Pokémon TCG w holenderskich sklepach i w sklepach wysyłających do Holandii."
      )

  @impl TcgCheapWeb.RegionText
  def cards_title, do: dgettext("netherlands", "Ceny kart Pokémon TCG w Holandii")

  @impl TcgCheapWeb.RegionText
  def card_title(card),
    do: dgettext("netherlands", "%{card} – cena karty Pokémon w Holandii", card: card)

  @impl TcgCheapWeb.RegionText
  def card_description(name, number, price),
    do:
      dgettext(
        "netherlands",
        "%{name} %{number}: od %{price} w holenderskich sklepach i w sklepach wysyłających do Holandii.",
        name: name,
        number: number,
        price: price
      )

  @impl TcgCheapWeb.RegionText
  def cards_in_stock(cards),
    do:
      dgettext(
        "netherlands",
        "Angielskie karty Pokémon TCG w holenderskich sklepach i w sklepach wysyłających do Holandii: %{cards} na stanie.",
        cards: cards
      )

  @impl TcgCheapWeb.RegionText
  def card_unavailable, do: dgettext("netherlands", "Brak w holenderskich sklepach")

  @impl TcgCheapWeb.RegionText
  def card_unavailable_delivering,
    do: dgettext("netherlands", "Brak w sklepach wysyłających do Holandii")

  @impl TcgCheapWeb.RegionText
  def card_unavailable_note,
    do: dgettext("netherlands", "Brak na stanie w holenderskich sklepach")

  @impl TcgCheapWeb.RegionText
  def card_method(shops),
    do:
      dgettext(
        "netherlands",
        "Typowa cena to środek stawki: z każdego holenderskiego sklepu, który ma kartę na stanie, bierzemy najtańszą ofertę (potrzebujemy co najmniej %{shops}). Dobra cena jest co najmniej 5% niższa od typowej i od Cardmarket z wysyłką. Normalna – najwyżej 10% wyższa od typowej. Wyższa – drogo. Ceny holenderskich sklepów są bez dostawy, zagranicznych – z wysyłką do Holandii.",
        shops: shops
      )

  @impl TcgCheapWeb.RegionText
  def card_prices_note,
    do:
      dgettext(
        "netherlands",
        "Ceny bez dostawy (z zagranicy z wysyłką) albo trend Cardmarket w euro, co tańsze."
      )

  @impl TcgCheapWeb.RegionText
  def cardmarket_card_delivery, do: dgettext("netherlands", "z wysyłką do Holandii")

  @impl TcgCheapWeb.RegionText
  def singles_prices_note,
    do: dgettext("netherlands", "Ceny bez dostawy. Z zagranicy: z wysyłką do Holandii.")

  @impl TcgCheapWeb.RegionText
  def expansion_fallback(expansion),
    do:
      dgettext(
        "netherlands",
        "%{expansion}: porównaj ceny boosterów, ETB, boxów i kolekcji w holenderskich sklepach i w sklepach wysyłających do Holandii.",
        expansion: expansion
      )

  @impl TcgCheapWeb.RegionText
  def booster_out_of_stock(expansion),
    do:
      dgettext(
        "netherlands",
        "Boostera %{expansion} żaden holenderski sklep ani sklep wysyłający do Holandii nie ma teraz na stanie.",
        expansion: expansion
      )

  @impl TcgCheapWeb.RegionText
  def product_out_of_stock(name),
    do:
      dgettext(
        "netherlands",
        "%{name}: teraz żaden holenderski sklep ani sklep wysyłający do Holandii nie ma tego produktu na stanie.",
        name: name
      )

  @impl TcgCheapWeb.RegionText
  def cardmarket_delivery, do: dgettext("netherlands", "z wysyłką z Niemiec")

  @impl TcgCheapWeb.RegionText
  def list_prices_note,
    do: dgettext("netherlands", "Ceny ze sklepów z zagranicy są z wysyłką do Holandii.")

  @impl TcgCheapWeb.RegionText
  def foreign_shops_note,
    do:
      dgettext(
        "netherlands",
        "Cena sklepu z zagranicy to ta, którą sklep podaje kupującym z Holandii. Ceny w innej walucie niż euro przeliczamy po dziennych kursach NBP. Strona sklepu może być w innym języku."
      )

  @impl TcgCheapWeb.RegionText
  def markdown_method(window),
    do: %{
      prices:
        dgettext(
          "netherlands",
          "Ceny pochodzą z publicznych list produktów sklepów, pobieranych raz dziennie, i są w euro. Ceny holenderskich sklepów nie obejmują dostawy, a sklepów za granicą obejmują wysyłkę do Holandii."
        ),
      good_price:
        dgettext(
          "netherlands",
          "Dobra cena to najwyżej 95% typowej, normalna najwyżej 110%, powyżej jest drogo. Dobra cena musi też być najwyżej 95% zwykłej ceny produktu z ostatnich %{window} dni i trendu Cardmarket w euro z przesyłką z Niemiec, gdy są znane.",
          window: window
        ),
      few_shops:
        dgettext(
          "netherlands",
          "Przy mniejszej liczbie sklepów nie ma oceny, a jako kontekst podajemy trend Cardmarket w euro."
        )
    }

  @impl TcgCheapWeb.RegionText
  def shop_prices_note(shipping),
    do:
      dgettext(
        "netherlands",
        "Ceny holenderskich sklepów są bez wysyłki, a sklepów z zagranicy – z wysyłką do Holandii. Do Cardmarket doliczamy %{shipping} za paczkę z Niemiec.",
        shipping: shipping
      )
end
