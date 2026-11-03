defmodule TcgCheapWeb.SetComponents do
  @moduledoc "A set's pull rates and cards, shown on its single booster's page and on the set's page."

  use TcgCheapWeb, :html
  use Gettext, backend: TcgCheapWeb.Gettext

  alias TcgCheap.Sealed.PullRates.Rate
  alias TcgCheapWeb.Polish

  @doc "A set's pull rates per rarity, with their sources, or a note that none are known yet."
  attr :pull_rates, :map, required: true
  attr :standard_pack_size, :integer, default: nil
  attr :smaller_pack?, :boolean, default: false

  def pull_rates(%{pull_rates: nil} = assigns) do
    ~H"""
    <section
      id="product-pull-rates"
      class="product-section"
      aria-labelledby="product-pull-rates-title"
    >
      <div class="product-section-heading">
        <h2 id="product-pull-rates-title">{gettext("Szansa na drop")}</h2>
      </div>
      <.standard_pack_note count={@standard_pack_size} smaller?={@smaller_pack?} />
      <p id="pull-rates-unknown" class="guide-note">
        {gettext("Nie znamy jeszcze szans na drop w tym secie.")}
      </p>
    </section>
    """
  end

  def pull_rates(assigns) do
    ~H"""
    <section
      id="product-pull-rates"
      class="product-section"
      aria-labelledby="product-pull-rates-title"
    >
      <div class="product-section-heading">
        <h2 id="product-pull-rates-title">{gettext("Szansa na drop")}</h2>
        <p>{gettext("sprawdzono %{date}", date: Polish.date(@pull_rates.checked_on))}</p>
      </div>
      <.standard_pack_note count={@standard_pack_size} smaller?={@smaller_pack?} />
      <.borrowed_note from={@pull_rates.borrowed_from} />
      <table id="pull-rates" class="pull-rates">
        <thead>
          <tr>
            <th scope="col">{gettext("Rzadkość")}</th>
            <th scope="col">
              <%= if @smaller_pack? and @standard_pack_size do %>
                {gettext("Szansa w paczce %{count} kart", count: @standard_pack_size)}
              <% else %>
                {gettext("Szansa w paczce")}
              <% end %>
            </th>
          </tr>
        </thead>
        <tbody>
          <tr :for={row <- @pull_rates.rates}>
            <th scope="row">
              <%= if row.group do %>
                <a href={"#set-cards-#{row.group}-list"}>{row.rarity}</a>
              <% else %>
                {row.rarity}
              <% end %>
              <span class="pull-rate-detail">{Polish.odds(row.rate)}</span>
              <span :if={row.rate.card} class="pull-rate-detail">
                {gettext("konkretna karta: %{name}", name: row.rate.card)}
              </span>
            </th>
            <td class="pull-rate-percent">{chance(row.rate)}</td>
          </tr>
        </tbody>
      </table>
      <div class="table-notes">
        <p id="pull-rates-estimate" class="guide-note pull-rates-estimate">
          <.fluent_icon name={:info} />
          <span>{gettext("To szacunki społeczności")}</span>
        </p>
        <p class="guide-note table-sources">
          {sources_label(length(@pull_rates.sources))}
          <%= for {source, index} <- Enum.with_index(@pull_rates.sources) do %>
            <span :if={index > 0}>·</span>
            <a href={source.url} target="_blank" rel="noopener nofollow">{host(source.url)}</a>
            <span :if={source_details(source) != []}>({Enum.join(source_details(source), ", ")})</span>
          <% end %>
        </p>
      </div>
    </section>
    """
  end

  @doc """
  Estimates of another set standing in until this set's own are out: the
  one caveat that changes how to read the table, so it stands apart.
  """
  attr :from, :string, default: nil

  def borrowed_note(assigns) do
    ~H"""
    <p :if={@from} class="pull-rates-borrowed">
      <.fluent_icon name={:info} />
      <span>
        {gettext(
          "Tego setu nikt jeszcze nie policzył: to szanse z wcześniejszego setu (%{set}), niezweryfikowane dla tego.",
          set: @from
        )}
      </span>
    </p>
    """
  end

  attr :count, :integer, default: nil
  attr :smaller?, :boolean, default: false

  defp standard_pack_note(assigns) do
    ~H"""
    <p :if={@smaller?} id="pull-rates-pack-size" class="guide-note">
      <%= if @count do %>
        {gettext(
          "Te szanse dotyczą zwykłej paczki %{count} kart. W tej paczce jest mniej kart, więc szanse są niższe – o ile, nie wiadomo.",
          count: @count
        )}
      <% else %>
        {gettext(
          "Te szanse dotyczą zwykłej paczki. W tej paczce jest mniej kart, więc szanse są niższe – o ile, nie wiadomo."
        )}
      <% end %>
    </p>
    """
  end

  @doc ~S'"Źródło:" or "Źródła:".'
  def sources_label(count), do: ngettext("Źródło:", "Źródła:", count)

  @doc ~S'"pokebeach.com" for www.pokebeach.com.'
  def host(url), do: url |> URI.parse() |> Map.fetch!(:host) |> String.replace_prefix("www.", "")

  # "dane TCGplayer", "8 000 otwartych paczek".
  defp source_details(source) do
    [
      source.data_from && gettext("dane %{source}", source: source.data_from),
      source.sample_packs &&
        ngettext("%{count} otwarta paczka", "%{count} otwarte paczki", source.sample_packs,
          count: Polish.number(source.sample_packs)
        )
    ]
    |> Enum.filter(& &1)
  end

  # The chance of a pack holding the rarity: "20%", "6,5%", "0,73%"; a fixed
  # count per pack as "3×".
  defp chance(rate) do
    case Rate.odds(rate) do
      {:per_pack, cards} -> "#{cards}×"
      _odds -> rate |> Rate.percent() |> percent()
    end
  end

  @doc ~S'A chance in percent, to a precision that fits it: "20%", "6,5%", "0,73%".'
  def percent(percent) do
    cond do
      Decimal.compare(percent, 10) != :lt -> percent(percent, 0)
      Decimal.compare(percent, 1) != :lt -> percent(percent, 1)
      true -> percent(percent, 2)
    end
  end

  defp percent(percent, places), do: Polish.decimal(Decimal.round(percent, places)) <> "%"

  @doc "A set's cards by rarity, or a note that its card list is not known yet."
  attr :rarities, :list, required: true
  attr :cards_source_url, :string, default: nil
  attr :priced_on, Date, default: nil
  attr :logo_url, :string, default: nil

  def set_cards(%{rarities: []} = assigns) do
    ~H"""
    <section id="product-cards" class="product-section" aria-labelledby="product-cards-title">
      <div class="product-section-heading">
        <h2 id="product-cards-title">{gettext("Karty do zdobycia")}</h2>
      </div>
      <p id="cards-unknown" class="guide-note">
        {gettext("Nie mamy jeszcze listy kart z tego setu.")}
      </p>
    </section>
    """
  end

  def set_cards(assigns) do
    ~H"""
    <section id="product-cards" class="product-section" aria-labelledby="product-cards-title">
      <div class="product-section-heading set-cards-heading">
        <h2 id="product-cards-title">
          {gettext("Karty do zdobycia")}
          <span class="heading-count">{set_card_count(@rarities)}</span>
        </h2>
        <img :if={@logo_url} src={@logo_url} alt="" class="set-cards-logo" />
      </div>
      <.rarity_cards
        id="set-cards"
        rarities={@rarities}
        cards_source_url={@cards_source_url}
        priced_on={@priced_on}
      />
    </section>
    """
  end

  @doc ~S'"295 kart w secie".'
  def set_card_count(rarities) do
    count = rarities |> Enum.map(&length(&1.cards)) |> Enum.sum()

    ngettext("%{count} karta w secie", "%{count} karty w secie", count,
      count: Polish.number(count)
    )
  end

  @doc """
  A set's cards by rarity, the rarest first, each rarity folding open;
  `id`-N-list is a rarity's list, which the pull-rate rows link to.
  """
  attr :id, :string, required: true
  attr :rarities, :list, required: true
  attr :cards_source_url, :string, default: nil
  attr :priced_on, Date, default: nil
  attr :open_first?, :boolean, default: true

  def rarity_cards(assigns) do
    ~H"""
    <p :if={@cards_source_url} id={"#{@id}-unofficial"} class="guide-note pull-rates-estimate">
      <.fluent_icon name={:info} />
      <span>
        {gettext("Nieoficjalna lista kart sprzed premiery, może się jeszcze zmienić. Źródło:")}
        <a href={@cards_source_url} target="_blank" rel="noopener nofollow">
          {host(@cards_source_url)}
        </a>
      </span>
    </p>
    <div id={@id} class="set-cards">
      <details
        :for={{group, index} <- Enum.with_index(@rarities)}
        id={"#{@id}-#{index}"}
        class="set-cards-group"
        open={@open_first? and index == 0}
      >
        <summary>
          <span class="set-cards-rarity">{group.rarity || gettext("Rzadkość nieznana")}</span>
          <span class="set-cards-count">{length(group.cards)}</span>
          <.fluent_icon name={:chevron_down} class="set-cards-chevron" />
        </summary>
        <ol id={"#{@id}-#{index}-list"} class={[length(group.cards) < 6 && "set-cards-short"]}>
          <li :for={card <- group.cards}>
            <span class="set-cards-number">{card.number}</span>
            <.link
              :if={Map.get(card, :public_path)}
              navigate={card.public_path}
              class="single-card-name"
            >{card.name}</.link>
            <span :if={!Map.get(card, :public_path)}>{card.name}</span>
            <span :if={Map.get(card, :polish_price)} class="single-card-pl">
              <strong>{Polish.price(card.polish_price)}</strong>
            </span>
            <.card_price :if={!Map.get(card, :polish_price)} card={card} />
          </li>
        </ol>
      </details>
    </div>
    <p class="guide-note table-note">
      {gettext("Ceny w polskich sklepach, bez dostawy. Z ikoną: Cardmarket, gdy w Polsce brak.")}
    </p>
    """
  end

  attr :card, :map, required: true

  defp card_price(assigns) do
    ~H"""
    <span :if={Map.get(@card, :cardmarket_trend_pln)} class="set-cards-price"><img
      src={~p"/images/cardmarket.png"}
      alt="Cardmarket"
      width="16"
      height="16"
    /> ≈ {Polish.rough_zloty(@card.cardmarket_trend_pln)}</span>
    """
  end
end
