defmodule TcgCheapWeb.CardRecords do
  @moduledoc """
  Record sales of Pokémon cards for the "Najdroższe karty Pokémon" article:
  for each card design its highest public auction result (buyer's premium
  included), confirmed by the auction house, Guinness World Records or a
  major news outlet, each with its source. Asking prices, unpaid closes and
  unconfirmed private sales stay out. The list is edited by hand when a
  confirmed record falls; `checked_on` says when it was last checked.

  `tcgdex_id` names the card's design in our catalogue, whose picture the
  article shows; a prize or promo card no catalogue has carries its own
  `image` in priv/static/images/records with the source it came from
  (`image_credit`).
  """

  use Gettext, backend: TcgCheapWeb.Gettext

  @checked_on ~D[2026-11-11]

  def checked_on, do: @checked_on

  @doc "The records, most expensive first, with the story each one tells."
  def all do
    [
      %{
        id: "pikachu-illustrator",
        name: "Pikachu Illustrator",
        detail: gettext("nagroda w konkursie magazynu CoroCoro, Japonia, 1998"),
        grade: "PSA 10",
        usd: 16_492_000,
        sold: {2026, 2},
        house: "Goldin",
        source:
          "https://www.guinnessworldrecords.com/news/2026/2/logan-pauls-rare-pokemon-card-becomes-most-expensive-ever-sold-in-record-setting-auction",
        image: "pikachu-illustrator.webp",
        image_credit:
          {"Bulbapedia",
           "https://archives.bulbagarden.net/wiki/File:Pok%C3%A9monIllustratorCoroCoropromo.jpg"},
        story:
          gettext(
            "W 1998 roku japoński magazyn CoroCoro ogłosił konkurs na ilustrację Pokémona. Nagrodą była karta, której nigdy nie dało się kupić, narysowana przez Atsuko Nishidę – autorkę Pikachu. Rozdano 39 egzemplarzy. Jedyny z najwyższą oceną PSA 10 kupił w 2021 roku Logan Paul za 5,275 mln dolarów i wyszedł z nim na szyi na galę WrestleMania. W lutym 2026 sprzedał go za ponad trzy razy więcej – to najdroższa karta kolekcjonerska w historii, nie tylko wśród Pokémonów. Nawet egzemplarz z oceną 9 poszedł we wrześniu 2026 za 5 mln dolarów."
          )
      },
      %{
        id: "art-academy-mudkip",
        name: "Mudkip z Art Academy",
        detail: gettext("japońska karta promocyjna, 2015"),
        grade: "PSA 10",
        usd: 4_880_000,
        sold: {2026, 10},
        house: "Goldin",
        source:
          "https://icv2.com/articles/news/view/63748/goldins-2026-pokemon-30th-anniversary-auction-rakes-over-28-million",
        image: "art-academy-mudkip.webp",
        image_credit:
          {"pokumon.com",
           "https://pokumon.com/card/daisuke-ochiai-mudkip-pokemon-art-academy-competition-2015-xy-p/"},
        story:
          gettext(
            "W 2015 roku Pokémon zorganizował konkurs na ilustrację przy grze Pokémon Art Academy. Zwycięskie rysunki fanów trafiły na karty promocyjne wydrukowane w znikomej liczbie – tego Mudkipa narysował Daisuke Ochiai. Ocenę PSA 10 mają tylko trzy egzemplarze. Jeszcze w 2024 roku jeden z nich kosztował 42 000 dolarów; we wrześniu 2026 drugi poszedł za 3,72 mln, a miesiąc później trzeci – za 4,88 mln."
          )
      },
      %{
        id: "trophy-pikachu",
        name: "Trofeum Pikachu „No. 1 Trainer”",
        detail: gettext("nagroda za 1. miejsce w turnieju, Japonia, 1997"),
        grade: "PSA 8",
        usd: 3_080_500,
        sold: {2026, 10},
        house: "Goldin",
        source:
          "https://icv2.com/articles/news/view/63748/goldins-2026-pokemon-30th-anniversary-auction-rakes-over-28-million",
        image: "trophy-pikachu.webp",
        image_credit:
          {"PriceCharting",
           "https://www.pricecharting.com/game/pokemon-japanese-promo/trophy-pikachu-gold-1"},
        story:
          gettext(
            "Złotą kartę z napisem „No. 1 Trainer” dostali tylko zwycięzcy pierwszego oficjalnego turnieju Pokémon w Japonii w 1997 roku. Ten egzemplarz ma ocenę zaledwie 8, a i tak poszedł za ponad 3 mln dolarów – przy kartach-trofeach liczy się przede wszystkim to, że jest ich garstka. Brązowe trofeum za trzecie miejsce, z oceną PSA 10, sprzedano w maju 2026 za 1,77 mln dolarów."
          )
      },
      %{
        id: "torchic-gold-star",
        tcgdex_id: "ex7-108",
        name: "Torchic ☆",
        detail: gettext("Gold Star, EX Team Rocket Returns 108/109, 2004"),
        grade: "PSA 10",
        usd: 2_700_000,
        sold: {2026, 9},
        house: "Alt",
        source: "https://alt.xyz/itm/1512d580-0dc6-4447-89ee-edc65a9f4103/sold",
        story:
          gettext(
            "Najdroższa karta Pokémon w języku angielskim. Gwiazdka przy nazwie to Gold Star: błyszcząca, inaczej ubarwiona wersja Pokémona, którą w angielskich boosterach pierwszy raz można było trafić właśnie w 2004 roku. Torchic nie jest ani legendarny, ani silny – zdecydował stan: najwyższą ocenę PSA 10 ma tylko 19 egzemplarzy. Na tej samej aukcji karta z oceną 9 poszła za 156 336 dolarów, siedemnaście razy taniej. Kilka tygodni wcześniej i później milion dolarów przekroczyły też Gold Stary z Rayquazą i Mudkipem."
          )
      },
      %{
        id: "charizard-no-rarity",
        name: "Charizard „No Rarity”",
        detail: gettext("japońska edycja podstawowa, pierwszy nakład, 1996"),
        grade: "PSA 10",
        usd: 1_700_000,
        sold: {2026, 3},
        house: "Heritage Auctions",
        source: "https://www.aol.com/articles/holo-charizard-breaks-one-pok-025856000.html",
        image: "charizard-no-rarity.webp",
        image_credit:
          {"PriceCharting",
           "https://www.pricecharting.com/game/pokemon-japanese-expansion-pack/charizard-no-rarity-6"},
        story:
          gettext(
            "Pierwszy japoński nakład kart z 1996 roku nie miał jeszcze w rogu symbolu rzadkości – stąd nazwa „No Rarity”. Charizard z tego nakładu w ocenie PSA 10 to najdroższy Charizard, jakiego sprzedano na aukcji."
          )
      },
      %{
        id: "typhlosion-1st-edition",
        tcgdex_id: "neo1-17",
        name: "Typhlosion",
        detail: gettext("Neo Genesis 17/111, pierwsze wydanie, 2000"),
        grade: "PSA 10",
        usd: 1_549_690,
        sold: {2026, 10},
        house: "Alt",
        source:
          "https://chasesociety.com/news/hottest-sales-of-the-week-the-second-art-academy-pikachu",
        story:
          gettext(
            "Neo Genesis to rozszerzenie, które w 2000 roku wprowadziło do gry drugą generację Pokémonów. Ten Typhlosion ma do tego drobny błąd druku: czerwoną kropkę obok symbolu rozszerzenia. Ocenę PSA 10 dostało 13 egzemplarzy tej karty."
          )
      },
      %{
        id: "charizard-1st-edition",
        tcgdex_id: "base1-4",
        name: "Charizard",
        detail: gettext("Base Set 4/102, pierwsze wydanie, 1999"),
        grade: "PSA 10",
        usd: 1_385_274,
        sold: {2026, 10},
        house: "Alt",
        source:
          "https://collectiblesnews.com/2026/10/10/pokemon-psa-10-first-edition-charizard-card-sells-for-record-1-385-million-at-alt/",
        story:
          gettext(
            "Najbardziej rozpoznawalna karta Pokémon: Charizard z pierwszego angielskiego wydania z 1999 roku. Ocenę PSA 10 ma 123 egzemplarzy i ich ceny rosną z miesiąca na miesiąc: w grudniu 2025 jeden poszedł za 550 000 dolarów, w lutym 2026 ten wyciągnięty na żywo przez Logana Paula – za 954 800, a w październiku kolejny przekroczył milion."
          )
      }
    ]
    |> Enum.map(&Map.merge(%{tcgdex_id: nil, image: nil, image_credit: nil}, &1))
  end

  @months ~w(styczeń luty marzec kwiecień maj czerwiec lipiec sierpień wrzesień październik listopad grudzień)

  @doc ~S'A month of sale: "luty 2026".'
  def month({year, month}) do
    if english?(),
      do: Calendar.strftime(Date.new!(year, month, 1), "%B %Y"),
      else: "#{Enum.at(@months, month - 1)} #{year}"
  end

  @doc ~S'Millions of dollars as the auction houses state them: "16,49 mln $", in English "$16.49M".'
  def usd(amount) do
    %{prefix: prefix, suffix: suffix} = usd_format()
    prefix <> millions(amount) <> suffix
  end

  @doc "How `usd/1` writes an amount, for the article's count-up to write it alike."
  def usd_format do
    if english?(),
      do: %{prefix: "$", suffix: "M", locale: "en-US"},
      else: %{prefix: "", suffix: "\u00A0mln\u00A0$", locale: "pl-PL"}
  end

  # At most two decimals: 16,49; 2,7.
  defp millions(amount) do
    (amount / 1_000_000)
    |> :erlang.float_to_binary(decimals: 2)
    |> String.trim_trailing("0")
    |> String.trim_trailing(".")
    |> String.replace(".", if(english?(), do: ".", else: ","))
  end

  defp english?, do: Gettext.get_locale(TcgCheapWeb.Gettext) == "en"
end
