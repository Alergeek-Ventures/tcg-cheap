defmodule TcgCheapWeb.BrowseLive.ChaseBanners do
  @moduledoc "A set page's chase banner: its most valuable card against pulling it from packs, or the set's single booster when its cards have no prices."

  use TcgCheapWeb, :html

  use Gettext, backend: TcgCheapWeb.Gettext

  import TcgCheapWeb.OfferComponents
  import TcgCheapWeb.VerdictComponents

  alias TcgCheap.Cards
  alias TcgCheap.Sealed.{Kinds, PriceGuide}
  alias TcgCheapWeb.{Format, Paths, RegionText}

  attr :booster, :map, required: true
  attr :set, :map, default: nil
  attr :cardmarket, :list, default: []
  attr :count, :integer, required: true
  attr :cards_href, :string, required: true

  # A set whose cards have no prices yet opens with its single booster: what
  # shops usually ask against the cheapest offer, then the set in numbers.
  def set_booster(assigns) do
    reference = booster_reference(assigns.booster)

    assigns =
      assign(assigns,
        cheapest: assigns.booster.verdict.cheapest,
        reference: reference,
        percent: booster_discount(assigns.booster.verdict.cheapest, reference),
        facts: booster_facts(assigns, reference)
      )

    ~H"""
    <div id="set-chase" class="set-chase">
      <.link
        class={["set-chase-art", @booster.product.stored_photo_card_url && "set-chase-products"]}
        navigate={Paths.product(@booster.product.slug)}
        tabindex="-1"
        aria-hidden="true"
      >
        <img
          :if={@booster.product.stored_photo_card_url}
          src={@booster.product.stored_photo_card_url}
          alt=""
          loading="eager"
          fetchpriority="high"
          class="set-chase-box"
        />
        <span :if={!@booster.product.stored_photo_card_url} class="set-chase-img set-chase-noart">
          <span class="set-chase-noart-note">{gettext("brak zdjęcia")}</span>
        </span>
      </.link>
      <div class="set-chase-head">
        <p class="set-chase-kicker">
          {if(@booster.preorder?,
            do: gettext("Booster w przedsprzedaży"),
            else: gettext("Pojedynczy booster")
          )}
        </p>
        <h2 class="set-chase-name">
          <.link id="set-booster" navigate={Paths.product(@booster.product.slug)}>
            {@booster.product.name}
          </.link>
        </h2>
        <p class="set-chase-meta"><.verdict_badge verdict={@booster.verdict} /></p>
      </div>
      <div class="set-chase-pair">
        <p :if={@reference} id="set-chase-pull" class="set-chase-side set-chase-pull">
          <%= case @reference do %>
            <% {:shops, typical, shops} -> %>
              <span class="set-chase-label">{gettext("Zwykle w sklepach")}</span>
              <strong>{Format.price(typical)}</strong>
              <span class="set-chase-detail">{ngettext(
                "mediana z %{count} sklepu",
                "mediana z %{count} sklepów",
                shops
              )}</span>
            <% {:cardmarket, price, _shops} -> %>
              <span class="set-chase-label">{gettext("Na Cardmarket")}</span>
              <strong>{Format.price(price)}</strong>
              <span class="set-chase-detail">{RegionText.cardmarket_delivery()}</span>
          <% end %>
        </p>
        <span :if={@percent} class="set-chase-or">{"−#{@percent}%"}</span>
        <.link
          id="set-chase-buy"
          class="set-chase-side set-chase-buy"
          navigate={Paths.product(@booster.product.slug)}
        >
          <%= if @cheapest do %>
            <span class="set-chase-label">{gettext("Kupisz za")}</span>
            <strong>{Format.price(@cheapest.price)}</strong>
            <span class="set-chase-detail">{gettext("w %{shop}", shop: priced_shop_name(@cheapest))
            |> glue_short_words()}</span>
          <% else %>
            <span class="set-chase-label">{gettext("Kupisz za")}</span>
            <strong class="set-chase-unknown">{gettext("brak na stanie")}</strong>
          <% end %>
        </.link>
      </div>
      <ul :if={@facts != []} id="set-booster-facts" class="set-chase-facts">
        <li
          :for={{{value, label}, index} <- Enum.with_index(@facts)}
          class={index == 3 && "set-chase-fact-extra"}
        >
          <strong>{value}</strong>
          <span>{label}</span>
        </li>
      </ul>
      <.chase_foot count={@count} priced?={false} href={@cards_href} />
    </div>
    """
  end

  # The shops' median when enough shops have it, else Cardmarket with delivery.
  defp booster_reference(%{verdict: %{typical_source: :shops} = verdict}),
    do: {:shops, verdict.typical, length(verdict.shop_prices)}

  defp booster_reference(%{cardmarket_delivered_price: %Decimal{} = price}),
    do: {:cardmarket, price, nil}

  defp booster_reference(_booster), do: nil

  # Three numbers beside the banner, as on every set page, and a fourth for
  # the 2×2 grid on a phone: the set's own first, then its boxes on Cardmarket.
  defp booster_facts(
         %{booster: booster, set: set, cardmarket: cardmarket, count: count},
         reference
       ) do
    # Borrowed odds are another set's, so they say nothing of this one's chase.
    rarest =
      set && set.pull_rates && !set.pull_rates.borrowed_from && List.first(set.pull_rates.rates)

    shop_count = match?({:shops, _typical, _shops}, reference) && elem(reference, 2)

    [
      count > 0 && {Format.number(count), ngettext("karta w secie", "kart w secie", count)},
      rarest && {Format.odds(rarest.rate), rarest.rarity},
      shop_count && {Format.number(shop_count), booster_shops_label(booster, shop_count)}
      | Enum.map(
          cardmarket,
          &{Format.price(&1.price), gettext("%{kind} na Cardmarket", kind: Kinds.label(&1.kind))}
        )
    ]
    |> Enum.filter(& &1)
    |> Enum.take(4)
  end

  defp booster_shops_label(%{preorder?: true}, count),
    do: ngettext("sklep przyjmuje zamówienia", "sklepy przyjmują zamówienia", count)

  defp booster_shops_label(_booster, count),
    do: ngettext("sklep ma go na stanie", "sklepy mają go na stanie", count)

  # How far the cheapest offer is under what shops usually ask. Cardmarket
  # with delivery stays context: a parcel for one booster is not a price to
  # measure a discount against.
  defp booster_discount(%{price: price}, {:shops, reference, _shops}),
    do: PriceGuide.discount_percent(price, reference)

  defp booster_discount(_cheapest, _reference), do: nil

  attr :top, :map, required: true
  attr :next, :list, required: true
  attr :booster, :map, required: true
  attr :count, :integer, required: true
  attr :cards_href, :string, required: true

  def set_chase(assigns) do
    ~H"""
    <div
      id="set-chase"
      class="set-chase"
      data-track-context
      data-track-placement="banner"
      data-track-card={@top.card.id}
      data-track-card-name={@top.card.name}
    >
      <.link
        class="set-chase-art"
        navigate={Paths.localize(@top.path)}
        data-track="card_clicked"
        tabindex="-1"
        aria-hidden="true"
      >
        <.chase_art top={@top} hero?={true} />
      </.link>
      <div class="set-chase-head">
        <p class="set-chase-kicker">{gettext("Najcenniejsza karta w secie")}</p>
        <h2 class="set-chase-name">
          <.link
            navigate={Paths.localize(@top.path)}
            data-track="card_clicked"
          >{@top.card.name}</.link>
        </h2>
        <p class="set-chase-meta">{chase_identity(@top.card)}</p>
      </div>
      <div class="set-chase-pair">
        <.link
          :if={@top.packs && @booster}
          id="set-chase-pull"
          class="set-chase-side set-chase-pull"
          navigate={Paths.product(@booster.product.slug)}
        >
          <.chase_pull_copy top={@top} booster={@booster} />
        </.link>
        <p :if={!@top.packs || !@booster} id="set-chase-pull" class="set-chase-side set-chase-pull">
          <.chase_pull_copy top={@top} booster={@booster} />
        </p>
        <span class="set-chase-or" aria-hidden="true">{gettext("albo")}</span>
        <.link
          id="set-chase-buy"
          class="set-chase-side set-chase-buy"
          navigate={Paths.localize(@top.path)}
          data-track="card_clicked"
        >
          <span class="set-chase-label">{gettext("Kupisz ją za")}</span>
          <strong>{Format.price(@top.price)}</strong>
          <span class="set-chase-detail">{chase_source(@top.source)}</span>
        </.link>
      </div>
      <div :if={@next != []} class="set-chase-rest">
        <h3 id="set-chase-next-title" class="set-chase-kicker">
          {gettext("Kolejne: wylosujesz albo kupisz")}
        </h3>
        <ul id="set-chase-next" class="set-chase-more" aria-labelledby="set-chase-next-title">
          <li
            :for={top <- @next}
            data-track-context
            data-track-placement="banner"
            data-track-card={top.card.id}
            data-track-card-name={top.card.name}
          >
            <div class="set-chase-mini">
              <.link
                class="set-chase-mini-thumb"
                navigate={Paths.localize(top.path)}
                data-track="card_clicked"
                tabindex="-1"
                aria-hidden="true"
              >
                <.chase_art top={top} />
              </.link>
              <.link
                class="set-chase-mini-name"
                navigate={Paths.localize(top.path)}
                data-track="card_clicked"
              >{top.card.name}</.link>
              <span class="set-chase-mini-meta">{chase_identity(top.card)}</span>
              <span class="set-chase-chips">
                <.link
                  :if={top.packs && @booster}
                  class="set-chase-chip set-chase-chip-pull"
                  navigate={Paths.product(@booster.product.slug)}
                >
                  <span class="sr-only">{gettext("wylosujesz średnio: ")}</span>{chase_pull_short(top)}
                </.link>
                <span
                  :if={!top.packs || !@booster}
                  class={[
                    "set-chase-chip set-chase-chip-pull",
                    !top.packs && "set-chase-chip-unknown"
                  ]}
                >
                  <span class="sr-only">{gettext("wylosujesz: ")}</span>{chase_pull_short(top)}
                </span>
                <.link
                  class="set-chase-chip set-chase-chip-buy"
                  navigate={Paths.localize(top.path)}
                  data-track="card_clicked"
                >
                  <span class="sr-only">{gettext("kupisz za ")}</span>{Format.price(top.price)}
                </.link>
              </span>
            </div>
          </li>
        </ul>
      </div>
      <.chase_foot count={@count} priced?={true} href={@cards_href} />
    </div>
    """
  end

  attr :top, :map, required: true
  attr :hero?, :boolean, default: false

  def chase_art(assigns) do
    ~H"""
    <img
      :if={@top.image}
      src={
        if(@hero?,
          do: Cards.Image.detail_url(@top.image),
          else: Cards.Image.thumbnail_url(@top.image)
        )
      }
      alt=""
      width="600"
      height="825"
      loading={if(@hero?, do: "eager", else: "lazy")}
      class={if(@hero?, do: "set-chase-img", else: "set-chase-mini-art")}
    />
    <span
      :if={!@top.image}
      class={[if(@hero?, do: "set-chase-img", else: "set-chase-mini-art"), "set-chase-noart"]}
      aria-hidden="true"
    >
      <span class="set-chase-noart-number">{@top.card.number}</span>
      <span :if={@hero?} class="set-chase-noart-note">{gettext("brak zdjęcia")}</span>
    </span>
    """
  end

  attr :top, :map, required: true
  attr :booster, :map, required: true

  defp chase_pull_copy(assigns) do
    ~H"""
    <%= cond do %>
      <% is_nil(@top.packs) -> %>
        <span class="set-chase-label">{gettext("Wylosujesz?")}</span>
        <strong class="set-chase-unknown">{gettext("szansy nie znamy")}</strong>
      <% @top.cost -> %>
        <span class="set-chase-label">{gettext("Wylosujesz średnio za")}</span>
        <strong>{Format.about(@top.cost)}</strong>
        <span class="set-chase-detail">{gettext("%{packs} po %{price}",
          packs: Format.packs(@top.packs),
          price: Format.price(@booster.verdict.cheapest.price)
        )}</span>
      <% true -> %>
        <span class="set-chase-label">{gettext("Wylosujesz średnio raz na")}</span>
        <strong>{Format.packs(@top.packs)}</strong>
        <span class="set-chase-detail">{chase_booster_state(@booster)}</span>
    <% end %>
    """
  end

  defp chase_booster_state(%{preorder?: true, premiere: %Date{} = date}),
    do: gettext("booster w przedsprzedaży, premiera %{date}", date: Format.day_month(date))

  defp chase_booster_state(%{preorder?: true}), do: gettext("booster w przedsprzedaży")
  defp chase_booster_state(_booster), do: gettext("boostera nie ma teraz na stanie")

  defp chase_pull_short(%{packs: nil}), do: gettext("szansy nie znamy")
  defp chase_pull_short(%{cost: %Decimal{} = cost}), do: Format.about(cost)

  defp chase_pull_short(%{packs: packs}),
    do: gettext("raz na %{packs}", packs: Format.packs(packs))

  @doc false
  def chase_identity(card),
    do:
      gettext("nr %{number} · %{rarity}",
        number: card.number,
        rarity:
          if(card.rarity,
            do: Cards.Rarities.label(card.rarity),
            else: gettext("Rzadkość nieznana")
          )
      )

  @doc false
  def chase_source({:shop, offer}),
    do: glue_short_words(gettext("w %{shop}", shop: card_shop_name(offer)))

  def chase_source(:cardmarket), do: gettext("na Cardmarket")

  attr :count, :integer, required: true
  attr :priced?, :boolean, required: true
  attr :href, :string, required: true

  def chase_foot(assigns) do
    ~H"""
    <p class="set-chase-foot">
      <span :if={@priced?}>{gettext("Ceny bez dostawy, szanse to szacunki.")}</span>
      <a :if={@count > 0} href={@href}>{ngettext(
        "Wszystkie karty (%{cards})",
        "Wszystkie %{cards} karty",
        @count,
        cards: Format.number(@count)
      )}</a>
    </p>
    """
  end
end
