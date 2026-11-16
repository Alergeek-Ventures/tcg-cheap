defmodule TcgCheapWeb.ContentsComponents do
  @moduledoc "What a sealed product holds: its contents list, the card lists of its decks and what its packs drop."

  use TcgCheapWeb, :html

  use Gettext, backend: TcgCheapWeb.Gettext

  import TcgCheapWeb.SetComponents
  import TcgCheapWeb.VerdictComponents

  alias TcgCheap.Sealed.CardImage
  alias TcgCheap.Sealed.PullRates.Rate
  alias TcgCheapWeb.{Format, Paths}

  @generic_photos ~w(binder booster card_dividers code_card coin condition_markers damage_counters
                     deck_box dice energy_cards player_guide playmat sleeves sticker storage_box)a

  @doc """
  A picture of what a contents item usually looks like (sleeves, dice…),
  from another product; nil for items without one and for a named booster,
  whose example would show another set's logo.
  """
  def generic_contents_photo(%{type: :booster, name: set}) when is_binary(set), do: nil

  def generic_contents_photo(%{type: type}) when type in @generic_photos,
    do: ~p"/images/contents/#{"#{type}.webp"}"

  def generic_contents_photo(_item), do: nil

  @doc """
  What a sealed product's contents item is called, in a sentence. A recorded
  name is shown in the page language (`TcgCheapWeb.Format.recorded/1`).
  """
  def contents_item_label(%{type: :booster, name: nil}), do: gettext("booster")

  def contents_item_label(%{type: :booster, name: set}),
    do: gettext("booster %{set}", set: Format.recorded(set))

  def contents_item_label(%{type: :promo_card, name: nil}), do: gettext("karta promo")

  def contents_item_label(%{type: :promo_card, name: card}),
    do: gettext("karta promo %{card}", card: Format.recorded(card))

  def contents_item_label(%{type: :oversize_card, name: nil}), do: gettext("duża karta")

  def contents_item_label(%{type: :oversize_card, name: card}),
    do: gettext("duża karta %{card}", card: Format.recorded(card))

  def contents_item_label(%{type: :card, name: nil}), do: gettext("karta")

  def contents_item_label(%{type: :card, name: card}),
    do: gettext("karta %{card}", card: Format.recorded(card))

  def contents_item_label(%{type: :deck, variants: [_ | _] = variants}),
    do: gettext("talia losowa (1 z %{count})", count: length(variants))

  def contents_item_label(%{type: :deck, name: nil}), do: gettext("talia gotowa do gry")

  def contents_item_label(%{type: :deck, name: deck}),
    do: gettext("talia %{deck}", deck: Format.recorded(deck))

  def contents_item_label(%{type: :sleeves}), do: gettext("koszulki na karty")
  # A booster's single energy slot can hold something else, as its name says.
  def contents_item_label(%{type: :energy_cards, quantity: 1, name: name}) when is_binary(name),
    do: Format.recorded(name)

  def contents_item_label(%{type: :energy_cards, quantity: 1}), do: gettext("karta energii")
  def contents_item_label(%{type: :energy_cards}), do: gettext("karty energii")
  def contents_item_label(%{type: :dice}), do: gettext("kość do gry")
  # Dice in elite trainer boxes, tokens in decks.
  def contents_item_label(%{type: :damage_counters}), do: gettext("znaczniki obrażeń")
  def contents_item_label(%{type: :coin}), do: gettext("moneta")
  def contents_item_label(%{type: :condition_markers}), do: gettext("znaczniki stanów")
  def contents_item_label(%{type: :deck_box}), do: gettext("pudełko na talię")
  def contents_item_label(%{type: :storage_box}), do: gettext("pudełko na karty")
  def contents_item_label(%{type: :card_dividers}), do: gettext("przekładki")
  def contents_item_label(%{type: :player_guide}), do: gettext("przewodnik gracza")
  def contents_item_label(%{type: :rule_sheet}), do: gettext("zasady gry")
  def contents_item_label(%{type: :code_card}), do: gettext("karta z kodem do Pokémon TCG Live")
  def contents_item_label(%{type: :sticker}), do: gettext("naklejki")
  def contents_item_label(%{type: :pin}), do: gettext("przypinka")
  def contents_item_label(%{type: :figure}), do: gettext("figurka")
  def contents_item_label(%{type: :binder}), do: gettext("album")
  def contents_item_label(%{type: :playmat}), do: gettext("mata do gry")
  def contents_item_label(%{type: :other, name: name}), do: Format.recorded(name)

  attr :contents, :map, required: true
  attr :boosters, :map, required: true
  attr :odds?, :boolean, default: false, doc: "a single booster's page, whose pull rates follow"
  attr :listed_on, Date, default: nil, doc: "when Cardmarket listed the product"

  def contents(%{contents: nil} = assigns) do
    ~H"""
    <section id="product-contents" class="product-section" aria-labelledby="product-contents-title">
      <div class="product-section-heading">
        <h2 id="product-contents-title">{gettext("Co jest w środku")}</h2>
      </div>
      <p id="contents-unknown" class="guide-note">
        {gettext("Nie znamy jeszcze zawartości tego produktu.")}
      </p>
    </section>
    """
  end

  def contents(assigns) do
    items =
      assigns.contents.items
      |> Enum.with_index()
      |> Enum.sort_by(fn {item, _index} -> item_rank(item.type, assigns.odds?) end)
      |> Enum.map(fn {item, index} -> {item, index, item_label(item, assigns.listed_on)} end)

    assigns =
      assign(assigns,
        items: items,
        rows: ceil(length(items) / 2)
      )

    ~H"""
    <section id="product-contents" class="product-section" aria-labelledby="product-contents-title">
      <div class="product-section-heading">
        <h2 id="product-contents-title">{gettext("Co jest w środku")}</h2>
        <p>{gettext("sprawdzono %{date}", date: Format.date(@contents.checked_on))}</p>
      </div>
      <ul id="contents-items" class="contents-items" style={"--rows: #{@rows}"}>
        <li :for={{item, index, label} <- @items}>
          <span class="contents-text">
            <span class="contents-quantity">{item.quantity}×</span>
            <span class="contents-label">
              <%= cond do %>
                <% booster = booster(item, @boosters) -> %>
                  <.link navigate={Paths.product(booster.slug)}>{label}</.link>
                <% @odds? and item.type == :other -> %>
                  <%!-- A single booster holds only its random cards besides energy and a code: their chances are below. --%>
                  <a href="#product-pull-rates">{label}</a>
                <% item.cardmarket_id -> %>
                  <a
                    href={cardmarket_url(item.cardmarket_id)}
                    target="_blank"
                    rel="noopener nofollow"
                  >{label}</a>
                <% true -> %>
                  {label}
              <% end %>
              <span :if={item.set} class="contents-card-set">{item.set} {item.number}</span>
              <span :if={item.variants not in [nil, []]} class="contents-card-set">
                {Enum.map_join(item.variants, " · ", & &1.name)}
              </span>
              <a
                :if={has_deck_list?(item)}
                href={"#deck-list-#{index}"}
                class="contents-card-set"
              >
                {cond do
                  item.variants not in [nil, []] -> gettext("listy kart wszystkich talii")
                  item.type == :deck -> gettext("lista kart talii")
                  true -> gettext("lista kart")
                end}
              </a>
            </span>
          </span>
          <%= cond do %>
            <% image_url = CardImage.thumbnail_url(item.image) -> %>
              <a
                href={CardImage.detail_url(item.image)}
                class="contents-photo"
                data-photo-preview
                aria-label={gettext("Zdjęcie: %{item}", item: label)}
              >
                <img src={image_url} alt="" width="34" height="48" loading="lazy" />
              </a>
            <% photo_url = CardImage.photo_url(item.photo, "thumbnail") -> %>
              <a
                href={CardImage.photo_url(item.photo, "detail")}
                class="contents-photo"
                data-photo-preview
                aria-label={gettext("Zdjęcie: %{item}", item: label)}
              >
                <img src={photo_url} alt="" height="48" loading="lazy" />
              </a>
            <% booster_photo = booster_photo(item, @boosters) -> %>
              <%!-- The name beside it is the link people and screen readers use. --%>
              <.link
                navigate={Paths.product(booster(item, @boosters).slug)}
                class="contents-photo contents-photo-page"
                tabindex="-1"
                aria-hidden="true"
              >
                <img src={booster_photo} alt="" height="48" loading="lazy" />
              </.link>
            <% generic_url = generic_contents_photo(item) -> %>
              <a
                href={generic_url}
                class="contents-photo contents-photo-generic"
                data-photo-preview
                title={gettext("Zdjęcie poglądowe z innego produktu")}
                aria-label={gettext("Zdjęcie poglądowe: %{item}", item: label)}
              >
                <img src={generic_url} alt="" height="48" loading="lazy" />
                <span class="contents-photo-note">{gettext("zdjęcie poglądowe")}</span>
              </a>
            <% true -> %>
              <span class="contents-photo-missing">{gettext("brak zdjęcia")}</span>
          <% end %>
        </li>
      </ul>
      <p class="guide-note">
        {sources_label(length(@contents.sources))}
        <%= for {url, index} <- Enum.with_index(@contents.sources) do %>
          <span :if={index > 0}>·</span>
          <a href={url} target="_blank" rel="noopener nofollow">{host(url)}</a>
        <% end %>
      </p>
      <%!-- The links stay plain links; with JavaScript their photo opens over the page. --%>
      <div id="photo-preview" phx-hook=".PhotoPreview" phx-update="ignore">
        <dialog id="photo-preview-dialog" class="photo-preview">
          <img id="photo-preview-image" alt="" />
          <button id="photo-preview-close" type="button">{gettext("Zamknij")}</button>
        </dialog>
      </div>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".PhotoPreview">
        export default {
          mounted() {
            this.dialog = this.el.querySelector("dialog")
            this.image = this.dialog.querySelector("img")
            this.open = event => {
              const link = event.target.closest("a[data-photo-preview]")
              if (!link || event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return
              event.preventDefault()
              this.image.src = link.href
              this.image.alt = link.getAttribute("aria-label") ?? ""
              this.dialog.showModal()
            }
            document.addEventListener("click", this.open)
            // Any click closes it: on the photo, around it or on the button.
            this.dialog.addEventListener("click", () => this.dialog.close())
            this.dialog.addEventListener("close", () => this.image.removeAttribute("src"))
          },
          destroyed() { document.removeEventListener("click", this.open) }
        }
      </script>
    </section>
    """
  end

  # Fixed and random decks, and fixed cards of a deck-building box, whose
  # lists we know, by their place in the contents.
  @doc false
  def deck_lists(nil), do: []

  def deck_lists(contents) do
    for {deck, index} <- Enum.with_index(contents.items),
        has_deck_list?(deck),
        do: {deck, index}
  end

  defp has_deck_list?(item),
    do: item.cards not in [nil, []] or item.variants not in [nil, []]

  attr :deck, :map, required: true
  attr :index, :integer, required: true

  def deck_list(%{deck: %{variants: [_ | _]}} = assigns) do
    ~H"""
    <section
      id={"deck-list-#{@index}"}
      class="product-section"
      aria-labelledby={"deck-list-#{@index}-title"}
    >
      <div class="product-section-heading">
        <h2 id={"deck-list-#{@index}-title"}>{gettext("Możliwe talie")}</h2>
      </div>
      <p class="guide-note">
        {random_deck_note(@deck)}
      </p>
      <%!-- Ignored by patches, so a rejoin keeps the variant shown. --%>
      <fieldset id={"deck-variants-#{@index}"} class="deck-variants" phx-update="ignore">
        <legend class="sr-only">{gettext("Pokaż skład talii")}</legend>
        <%= for {variant, variant_index} <- Enum.with_index(@deck.variants) do %>
          <input
            type="radio"
            id={"deck-variant-#{@index}-#{variant_index}"}
            name={"deck-variant-#{@index}"}
            value={variant_index}
            checked={variant_index == 0}
            class="deck-variant-radio"
            aria-controls={"deck-variant-#{@index}-#{variant_index}-cards"}
          />
          <label for={"deck-variant-#{@index}-#{variant_index}"} class="deck-variant-label">
            {variant.name}
          </label>
          <div
            id={"deck-variant-#{@index}-#{variant_index}-cards"}
            class="deck-variant-cards"
            role="region"
            aria-labelledby={"deck-variant-#{@index}-#{variant_index}"}
          >
            <.deck_card_list cards={variant.cards} name={variant.name} />
          </div>
        <% end %>
      </fieldset>
    </section>
    """
  end

  def deck_list(assigns) do
    ~H"""
    <section
      id={"deck-list-#{@index}"}
      class="product-section"
      aria-labelledby={"deck-list-#{@index}-title"}
    >
      <div class="product-section-heading">
        <h2 id={"deck-list-#{@index}-title"}>{deck_title(@deck)}</h2>
        <p>
          {Format.cards(Enum.sum(Enum.map(@deck.cards, & &1.quantity)))}
        </p>
      </div>
      <.deck_card_list cards={@deck.cards} show_count={false} />
    </section>
    """
  end

  attr :cards, :list, required: true
  attr :name, :string, default: nil
  attr :show_count, :boolean, default: true

  defp deck_card_list(assigns) do
    groups =
      assigns.cards
      |> Enum.group_by(& &1.category)
      |> Enum.sort_by(fn {category, _cards} -> category_rank(category) end)
      |> Enum.map(fn {category, cards} ->
        %{category: category, cards: cards, count: cards |> Enum.map(& &1.quantity) |> Enum.sum()}
      end)

    assigns =
      assign(assigns,
        groups: groups,
        count: groups |> Enum.map(& &1.count) |> Enum.sum()
      )

    ~H"""
    <div class="deck-card-list">
      <p :if={@show_count} class="deck-variant-count">
        {gettext("Talia %{deck}", deck: @name)} · {Format.cards(@count)}
      </p>
      <div :for={group <- @groups} class="deck-list-group">
        <h3>
          {category_label(group.category)} <span class="deck-list-count">{group.count}</span>
        </h3>
        <ul class="contents-items" style={"--rows: #{ceil(length(group.cards) / 2)}"}>
          <li :for={card <- group.cards}>
            <span class="contents-text">
              <span class="contents-quantity">{card.quantity}×</span>
              <span class="contents-label">
                <a
                  :if={card.cardmarket_id}
                  href={cardmarket_url(card.cardmarket_id)}
                  target="_blank"
                  rel="noopener nofollow"
                >{card.name}</a>
                <span :if={!card.cardmarket_id}>{card.name}</span>
                <span :if={card.set} class="contents-card-set">{card.set} {card.number}</span>
              </span>
            </span>
            <%= cond do %>
              <% image_url = CardImage.thumbnail_url(card.image) -> %>
                <a
                  href={CardImage.detail_url(card.image)}
                  class="contents-photo"
                  data-photo-preview
                  aria-label={gettext("Zdjęcie: %{item}", item: card.name)}
                >
                  <img src={image_url} alt="" width="34" height="48" loading="lazy" />
                </a>
              <% photo_url = CardImage.photo_url(card.photo, "thumbnail") -> %>
                <a
                  href={CardImage.photo_url(card.photo, "detail")}
                  class="contents-photo"
                  data-photo-preview
                  aria-label={gettext("Zdjęcie: %{item}", item: card.name)}
                >
                  <img src={photo_url} alt="" width="34" height="48" loading="lazy" />
                </a>
              <% true -> %>
            <% end %>
          </li>
        </ul>
      </div>
      <p class="guide-note">
        {gettext(
          "Karty według listy wydawcy; set, numer i zdjęcie z TCGdex lub innych źródeł, nazwa otwiera kartę na Cardmarket."
        )}
      </p>
    </div>
    """
  end

  defp deck_title(%{type: type}) when type != :deck, do: gettext("Karty w zestawie")
  defp deck_title(%{name: nil}), do: gettext("Karty w talii")

  defp deck_title(%{name: deck}),
    do: gettext("Karty w talii %{deck}", deck: Format.recorded(deck))

  @category_order ["Pokemon", "Trainer", "Energy"]
  defp category_rank(category),
    do: Enum.find_index(@category_order, &(&1 == category)) || length(@category_order)

  defp category_label("Pokemon"), do: gettext("Pokémon")
  defp category_label("Trainer"), do: gettext("Karty Trenera")
  defp category_label("Energy"), do: gettext("Energia")
  defp category_label(_other), do: gettext("Inne karty")

  # A booster of a named set links to our page for that set's single booster.
  defp booster(%{type: :booster, name: set}, boosters) when is_binary(set), do: boosters[set]
  defp booster(_item, _boosters), do: nil

  defp booster_photo(item, boosters) do
    case booster(item, boosters) do
      %{stored_photo_small_url: url} when is_binary(url) -> url
      %{stored_photo_card_url: url} when is_binary(url) -> url
      _none -> nil
    end
  end

  # Without a photo of this product's item, a common one of that kind stands
  # in, marked as not this product's.
  # Code cards were printed for Pokémon TCG Online, from 2022 for either game;
  # from Crown Zenith, listed on Cardmarket in November 2022, for TCG Live
  # only. TCG Online's codes still redeem in TCG Live.
  @tcg_live_only_from ~D[2022-11-01]

  defp item_label(%{type: :code_card}, %Date{} = listed_on) do
    if Date.before?(listed_on, @tcg_live_only_from),
      do: gettext("karta z kodem do Pokémon TCG Online lub Live"),
      else: gettext("karta z kodem do Pokémon TCG Live")
  end

  defp item_label(item, _listed_on), do: contents_item_label(item)

  # A box holds one deck the publisher drew; a display holds several, each drawn.
  defp random_deck_note(%{quantity: 1, variants: variants}),
    do:
      gettext(
        "W pudełku jest jedna z tych %{count} talii, wylosowana przez producenta – nie da się jej wybrać. Sprawdź skład każdej:",
        count: length(variants)
      )

  defp random_deck_note(%{quantity: quantity, variants: variants}),
    do:
      gettext(
        "Każda z %{quantity} talii to jedna z tych %{count}, wylosowana przez producenta – nie da się ich wybrać. Sprawdź skład każdej:",
        quantity: quantity,
        count: length(variants)
      )

  # What a buyer opens comes first, the accessories after it.
  @item_order ~w(deck booster promo_card oversize_card card energy_cards)a
  # A single booster lists its random cards first, then the energy and the code.
  defp item_rank(:other, true = _odds?), do: -1

  defp item_rank(type, _odds?),
    do: Enum.find_index(@item_order, &(&1 == type)) || length(@item_order)

  attr :sets, :list, required: true

  def booster_odds(assigns) do
    ~H"""
    <section
      id="product-booster-odds"
      class="product-section"
      aria-labelledby="product-booster-odds-title"
    >
      <div class="product-section-heading">
        <h2 id="product-booster-odds-title">{gettext("Szansa na drop")}</h2>
      </div>
      <div :for={set <- @sets} id={"booster-odds-#{set.slug}"} class="booster-odds-set">
        <h3>{set.name}</h3>
        <%= if set.pull_rates do %>
          <.borrowed_note from={set.pull_rates.borrowed_from} />
          <table class="pull-rates">
            <thead>
              <tr>
                <th scope="col">{gettext("Rzadkość")}</th>
                <th scope="col">
                  {ngettext("W %{count} paczce", "W %{count} paczkach", set.count)}
                </th>
              </tr>
            </thead>
            <tbody>
              <tr :for={row <- set.pull_rates.rates}>
                <th scope="row">
                  <%= if row.group do %>
                    <a href={"#booster-odds-#{set.slug}-cards-#{row.group}-list"}>{row.rarity}</a>
                  <% else %>
                    {row.rarity}
                  <% end %>
                  <span :if={row.rate.card} class="pull-rate-detail">
                    {gettext("konkretna karta: %{name}", name: row.rate.card)}
                  </span>
                </th>
                <td class="pull-rate-percent">{combined_chance(row.rate, set.count)}</td>
              </tr>
            </tbody>
          </table>
          <div class="table-notes">
            <p class="guide-note pull-rates-estimate">
              <.fluent_icon name={:info} />
              <span>{gettext("To szacunki społeczności")}</span>
            </p>
            <p class="guide-note table-sources">
              {sources_label(length(set.pull_rates.sources))}
              <%= for {source, index} <- Enum.with_index(set.pull_rates.sources) do %>
                <span :if={index > 0}>·</span>
                <a href={source.url} target="_blank" rel="noopener nofollow">{host(source.url)}</a>
              <% end %>
            </p>
          </div>
        <% else %>
          <p class="guide-note">{gettext("Nie znamy jeszcze szans na drop w tym secie.")}</p>
        <% end %>
        <%= if set.rarities != [] do %>
          <h4 class="booster-odds-cards-title">
            {gettext("Karty do zdobycia")}
            <span class="heading-count">{set_card_count(set.rarities)}</span>
          </h4>
          <.rarity_cards
            id={"booster-odds-#{set.slug}-cards"}
            rarities={set.rarities}
            cards_source_url={set.cards_source_url}
            priced_on={set.priced_on}
            open_first?={false}
          />
        <% end %>
      </div>
    </section>
    """
  end

  defp combined_chance(rate, count) do
    case Rate.across_packs(rate, count) do
      :guaranteed -> gettext("w każdej paczce")
      nil -> gettext("Brak danych")
      value when value > 99 -> "> 99%"
      value when value < 0.01 -> "< " <> Format.decimal(Decimal.new("0.01")) <> "%"
      value -> "≈ " <> percent(Decimal.from_float(value))
    end
  end
end
