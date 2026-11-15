defmodule TcgCheap.Countries.Croatia do
  @moduledoc """
  Croatia: the guide's region `/hr/` in euro, and the words that name it
  (`TcgCheap.Country`). Visitors from Bosnia and Herzegovina land here too
  (`visitors_from`), though no shop's delivery there is counted. Singles have
  no shops here yet: card prices are Cardmarket trends in euro.
  """

  @behaviour TcgCheap.Country
  @behaviour TcgCheapWeb.RegionText

  use Gettext, backend: TcgCheapWeb.Gettext

  @impl TcgCheap.Country
  def code, do: "HR"

  @impl TcgCheap.Country
  def shipped_from, do: dgettext("croatia", "wysyłka z Chorwacji")

  @impl TcgCheap.Country
  def delivered_from, do: dgettext("croatia", "z wysyłką z Chorwacji")

  @impl TcgCheap.Country
  def region do
    %{
      code: "hr",
      currency: "EUR",
      currency_symbol: "€",
      decimals: 2,
      language: "hr",
      hreflang: "hr-HR",
      popular_languages: [],
      # DHL's tariff from Germany is the same for Croatia as for Hungary
      # (checked 2026-11-14), so the same parcel as Hungary's:
      # https://www.dhl.de/de/privatkunden/pakete-versenden/weltweit-versenden/land/kroatien.html
      cardmarket_shipping_eur: Decimal.new("15.49"),
      slugs: %{products: "proizvodi", expansions: "setovi", cards: "karte"},
      pages: %{},
      # Bosnian visitors read Croatian; their own country has no region.
      visitors_from: ["BA"]
    }
  end

  @impl TcgCheapWeb.RegionText
  def name, do: dgettext("croatia", "Chorwacja")

  @impl TcgCheapWeb.RegionText
  def hint, do: dgettext("croatia", "Wygląda na to, że jesteś w Chorwacji.")

  @impl TcgCheapWeb.RegionText
  def hint_switch, do: dgettext("croatia", "Przejdź do wersji chorwackiej")

  @impl TcgCheapWeb.RegionText
  def home_description,
    do:
      dgettext(
        "croatia",
        "Porównaj ceny Pokémon TCG w sklepach wysyłających do Chorwacji. Sprawdź oferty boosterów, ETB i boxów, historię cen i czy warto kupić teraz."
      )

  @impl TcgCheapWeb.RegionText
  def social_promise,
    do:
      dgettext(
        "croatia",
        "Ceny Pokémon TCG ze sklepów wysyłających do Chorwacji, sprawdzane codziennie."
      )

  @impl TcgCheapWeb.RegionText
  def products_promise,
    do: dgettext("croatia", "Najtańsze oferty Pokémon TCG w sklepach wysyłających do Chorwacji.")

  @impl TcgCheapWeb.RegionText
  def cards_promise, do: cardmarket_cards()

  @impl TcgCheapWeb.RegionText
  def cards_answer, do: cardmarket_cards()

  defp cardmarket_cards,
    do: dgettext("croatia", "Angielskie karty Pokémon TCG z ceną z Cardmarket w euro.")

  @impl TcgCheapWeb.RegionText
  def cards_title, do: dgettext("croatia", "Ceny kart Pokémon TCG w euro")

  @impl TcgCheapWeb.RegionText
  def card_title(card),
    do: dgettext("croatia", "%{card} – cena karty Pokémon w euro", card: card)

  @impl TcgCheapWeb.RegionText
  def expansion_fallback(expansion),
    do:
      dgettext(
        "croatia",
        "%{expansion}: porównaj ceny boosterów, ETB, boxów i kolekcji w sklepach wysyłających do Chorwacji.",
        expansion: expansion
      )

  @impl TcgCheapWeb.RegionText
  def booster_out_of_stock(expansion),
    do:
      dgettext(
        "croatia",
        "Boostera %{expansion} żaden sklep wysyłający do Chorwacji nie ma teraz na stanie.",
        expansion: expansion
      )

  @impl TcgCheapWeb.RegionText
  def product_out_of_stock(name),
    do:
      dgettext(
        "croatia",
        "%{name}: teraz żaden sklep wysyłający do Chorwacji nie ma tego produktu na stanie.",
        name: name
      )

  @impl TcgCheapWeb.RegionText
  def cardmarket_delivery, do: dgettext("croatia", "z wysyłką z Niemiec")

  @impl TcgCheapWeb.RegionText
  def list_prices_note,
    do: dgettext("croatia", "Ceny ze sklepów z zagranicy są z wysyłką do Chorwacji.")

  @impl TcgCheapWeb.RegionText
  def foreign_shops_note,
    do:
      dgettext(
        "croatia",
        "Sklepy z zagranicy sprzedają w swojej walucie. Ceny w innej walucie niż euro przeliczamy po dziennych kursach NBP. Strona sklepu może być w innym języku."
      )

  @impl TcgCheapWeb.RegionText
  def markdown_method(window),
    do: %{
      prices:
        dgettext(
          "croatia",
          "Ceny pochodzą z publicznych feedów produktowych sklepów, pobieranych raz dziennie, i są w euro. Ceny chorwackich sklepów nie obejmują dostawy, a sklepów za granicą obejmują wysyłkę do Chorwacji."
        ),
      good_price:
        dgettext(
          "croatia",
          "Dobra cena to najwyżej 95% typowej, normalna najwyżej 110%, powyżej jest drogo. Dobra cena musi też być najwyżej 95% zwykłej ceny produktu z ostatnich %{window} dni i trendu Cardmarket w euro z przesyłką z Niemiec, gdy są znane.",
          window: window
        ),
      few_shops:
        dgettext(
          "croatia",
          "Przy mniejszej liczbie sklepów nie ma oceny, a jako kontekst podajemy trend Cardmarket w euro."
        )
    }

  @impl TcgCheapWeb.RegionText
  def shop_prices_note(shipping),
    do:
      dgettext(
        "croatia",
        "Ceny chorwackich sklepów są bez wysyłki, a sklepów z zagranicy – z wysyłką do Chorwacji. Do Cardmarket doliczamy %{shipping} za paczkę z Niemiec.",
        shipping: shipping
      )
end
