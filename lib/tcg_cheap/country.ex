defmodule TcgCheap.Country do
  @moduledoc """
  A country the guide names, one module per country in
  `lib/tcg_cheap/countries/` (`TcgCheap.Countries`): how an offer from a
  shop there says where it ships from and, when the guide has a region
  there, the region's definition (`region/0`) and its whole sentences
  (`TcgCheapWeb.RegionText`).

  Its words are in its own Gettext domain, named as its file
  (`dgettext("hungary", …)`), so a country's translations are its own files
  (`priv/gettext/<language>/LC_MESSAGES/hungary.po`).
  """

  @typedoc """
  A region of the guide: a country with its own URLs, shops and prices.

    * `code` – its first path segment (`/hu/…`), cookie and switch value;
    * `currency` – the ISO code its prices are in, with the
      `currency_symbol` prices write after the amount and the `decimals`
      they show (0 for whole units, as forints are);
    * `language` – the page language unless the visitor chose another, and
      `hreflang`, the language and country search engines are told;
    * `popular_languages` – at most two other languages many people there
      read, which its language menu lists after its own and English (the
      rest of the guide's languages wait behind "more");
    * `cardmarket_untracked_letter_eur` and `cardmarket_tracked_letter_eur` –
      the single-card letters through and above Cardmarket's €25 tracking
      threshold, in euro, including packaging;
    * `cardmarket_shipping_eur` – the tracked parcel added to a Cardmarket
      trend, in euro, for verdicts and "with delivery" prices;
    * `slugs` – its path segments for the product, set and card pages and
      the card list: `%{products: …, expansions: …, cards: …}`;
    * `pages` – the guide's own pages it has, by page (`:booster_prices`,
      `:expensive_cards`, `:card_value`, `:bot`), each with its slug; a page
      without a translation is left out;
    * `visitors_from` (optional) – other countries, by ISO code, whose
      visitors the root sends to this region rather than to Poland's;
    * `whole_prices_from` (optional) – the amount from which prices are
      written in whole units though smaller ones keep their `decimals`
      (Sweden: "999 kr" and "8 kr", but a cheap card's "3,50 kr").
  """
  @type region :: %{
          optional(:visitors_from) => [String.t()],
          optional(:whole_prices_from) => Decimal.t(),
          code: String.t(),
          currency: String.t(),
          currency_symbol: String.t(),
          decimals: non_neg_integer(),
          language: String.t(),
          hreflang: String.t(),
          popular_languages: [String.t()],
          cardmarket_untracked_letter_eur: Decimal.t(),
          cardmarket_tracked_letter_eur: Decimal.t(),
          cardmarket_shipping_eur: Decimal.t(),
          slugs: %{products: String.t(), expansions: String.t(), cards: String.t()},
          pages: %{optional(atom()) => String.t()}
        }

  @doc "The ISO 3166 code: a shop's `country`, Cloudflare's `cf-ipcountry`."
  @callback code() :: String.t()

  @doc ~S(How an offer row says where a shop ships from: "wysyłka z Węgier".)
  @callback shipped_from() :: String.t()

  @doc ~S(How a price with delivery says where it comes from: "z wysyłką z Węgier".)
  @callback delivered_from() :: String.t()

  @doc "The guide's region in the country, nil without one."
  @callback region() :: region() | nil
end
