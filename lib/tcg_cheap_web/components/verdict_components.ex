defmodule TcgCheapWeb.VerdictComponents do
  @moduledoc "The price verdict: its badge and drawn mark, the panel and method around it, and the Cardmarket reference price it is judged against."

  use TcgCheapWeb, :html

  use Gettext, backend: TcgCheapWeb.Gettext

  import TcgCheapWeb.OfferComponents

  alias TcgCheapWeb.{Format, Region}

  @doc """
  The verdict as a labelled badge; shape and text carry the meaning, not color
  alone. Fewer than 3 shops is one state, "Za mało sklepów", whether or not
  Cardmarket has a price: Cardmarket is context on the product page, never a
  verdict next to real ones.
  """
  attr :verdict, :map, required: true
  attr :id, :string, default: nil
  attr :class, :any, default: nil

  def verdict_badge(assigns) do
    assigns = assign(assigns, :status, badge_status(assigns.verdict.status))

    ~H"""
    <span id={@id} class={["verdict-badge", "verdict-#{@status}", @class]}>
      <.verdict_icon status={@status} />{verdict_label(@verdict)}
    </span>
    """
  end

  defp badge_status(:cardmarket), do: :insufficient_data
  defp badge_status(status), do: status

  @doc "The drawn mark of a verdict: down for good, equals for normal, up for expensive."
  attr :status, :atom, required: true

  def verdict_icon(assigns) do
    assigns = assign(assigns, :paths, verdict_paths(assigns.status))

    ~H"""
    <svg class="verdict-mark" viewBox="0 0 16 16" aria-hidden="true" focusable="false">
      <path :for={d <- @paths} d={d} />
    </svg>
    """
  end

  @doc "The SVG paths (16×16, stroked) of a verdict's drawn mark."
  @spec verdict_paths(atom()) :: [String.t()]
  def verdict_paths(:good), do: ["M8 2.5v11", "M3.5 9 8 13.5 12.5 9"]
  def verdict_paths(:normal), do: ["M3 5.75h10", "M3 10.25h10"]
  def verdict_paths(:expensive), do: ["M8 13.5v-11", "M3.5 7 8 2.5 12.5 7"]

  def verdict_paths(status) when status in [:cardmarket, :insufficient_data],
    do: ["M5.75 5.75a2.25 2.25 0 1 1 3.4 1.95c-.7.4-1.15.9-1.15 1.7v.6", "M8 12.75v.25"]

  def verdict_paths(:out_of_stock), do: ["M3 8h10"]
  # A clock: a pre-order, shipped on the premiere.
  def verdict_paths(:preorder),
    do: ["M8 2.5a5.5 5.5 0 1 1 0 11a5.5 5.5 0 1 1 0-11", "M8 5v3.25l2 1.5"]

  @doc ~S'The localized label of a verdict: "Dobra cena", "Za mało sklepów", …'
  @spec verdict_label(map()) :: String.t()
  def verdict_label(%{status: :good}), do: gettext("Dobra cena")
  def verdict_label(%{status: :normal}), do: gettext("Normalna cena")
  def verdict_label(%{status: :expensive}), do: gettext("Drogo")

  def verdict_label(%{status: status}) when status in [:cardmarket, :insufficient_data],
    do: gettext("Za mało sklepów")

  def verdict_label(%{status: :out_of_stock}), do: gettext("Brak w sklepach")

  def single_verdict_status(:cheaper), do: :good
  def single_verdict_status(:expensive), do: :expensive
  def single_verdict_status(v) when v in [:similar, :pennies], do: :normal
  def single_verdict_status(:unavailable), do: :out_of_stock
  def single_verdict_status(_), do: :insufficient_data

  # The same short words as a sealed product's verdict; how the price was
  # judged is told under "Jak liczymy?".
  def single_verdict_label(:unknown), do: gettext("Brak ceny Cardmarket")

  def single_verdict_label(verdict),
    do: verdict_label(%{status: single_verdict_status(verdict)})

  attr :id, :string, required: true
  attr :status, :atom, required: true
  slot :header, required: true
  slot :inner_block, required: true

  def verdict_panel(assigns) do
    ~H"""
    <section
      id={@id}
      class={["verdict-block", "verdict-block-#{@status}"]}
      aria-labelledby={"#{@id}-title"}
    >
      <h2 id={"#{@id}-title"} class="sr-only">{gettext("Ocena ceny")}</h2>
      {render_slot(@header)}
      <div class="verdict-body">{render_slot(@inner_block)}</div>
    </section>
    """
  end

  attr :id, :string, required: true
  slot :inner_block, required: true

  def verdict_method(assigns) do
    ~H"""
    <details id={@id} class="verdict-method">
      <summary data-track="product_section_opened" data-track-section="verdict_method">
        {gettext("Jak liczymy?")}<.fluent_icon name={:chevron_down} class="verdict-method-chevron" />
      </summary>
      {render_slot(@inner_block)}
    </details>
    """
  end

  attr :offer, :map, required: true
  attr :preorder?, :boolean, default: false
  attr :prefix, :string, default: "verdict"

  def verdict_now(assigns) do
    ~H"""
    <div :if={@offer} class="verdict-now">
      <div>
        <p id={"#{@prefix}-price"} class="verdict-price">{Format.price(@offer.price)}</p>
        <p id={"#{@prefix}-shop"} class="verdict-shop">
          {if(@preorder?,
            do: gettext("najtaniej w przedsprzedaży w"),
            else: gettext("najtaniej teraz w")
          )}&nbsp;<strong>{shop_name(@offer)}</strong><span :if={delivered_term(@offer)}>, {delivered_term(
            @offer
          )}</span>
        </p>
      </div>
      <a
        id={"#{@prefix}-go"}
        href={@offer.url}
        target="_blank"
        rel="noopener nofollow"
        class="verdict-go"
        data-track="shop_link_clicked"
        data-track-placement="verdict"
        data-track-shop={@offer.shop}
        data-track-price={@offer.price}
        data-track-in-stock={to_string(@offer.in_stock)}
        data-track-preorder={to_string(Map.get(@offer, :preorder, false))}
      >
        {gettext("Do sklepu")}<span class="sr-only">{gettext("(otwiera się w nowej karcie)")}</span>
      </a>
    </div>
    """
  end

  @doc """
  A Cardmarket price in złoty behind the Cardmarket logo, the one mark for a
  Cardmarket reference price, linking to the product there.
  """
  attr :price, :any, required: true
  attr :href, :string, required: true
  attr :id, :string, default: nil
  attr :class, :any, default: nil

  attr :shipping, :boolean, default: false

  def cardmarket_price(assigns) do
    ~H"""
    <a
      id={@id}
      href={@href}
      target="_blank"
      rel="noopener nofollow"
      class={["cardmarket-price", @class]}
      title={
        if(@shipping,
          do: gettext("Cena na Cardmarket z wysyłką"),
          else: gettext("Cena na Cardmarket (bez wysyłki)")
        )
      }
    >
      <img src={~p"/images/cardmarket.png"} alt="Cardmarket" width="16" height="16" />{Format.limit_price(
        @price
      )}
    </a>
    """
  end

  @doc "A product's page on Cardmarket, by its Cardmarket product id."
  @spec cardmarket_url(integer()) :: String.t()
  def cardmarket_url(id), do: "https://www.cardmarket.com/en/Pokemon/Products?idProduct=#{id}"

  attr :product, :map, required: true
  attr :cardmarket_price, :any, required: true
  attr :eur_rate, :map, default: nil

  attr :id, :string, default: "product-cardmarket"
  attr :reverse, :any, default: nil
  attr :reverse_pln, :any, default: nil

  def cardmarket_reference(assigns) do
    assigns = assign(assigns, :converted?, !euro_region?())

    ~H"""
    <section
      id={@id}
      class="product-section cardmarket-reference"
      aria-labelledby={"#{@id}-title"}
    >
      <div class="product-section-heading">
        <h2 id={"#{@id}-title"} class="cardmarket-title">
          <img src={~p"/images/cardmarket.png"} alt="" width="24" height="24" />{gettext(
            "Cena na Cardmarket"
          )}
        </h2>
        <p :if={@product.cardmarket_price_updated_on}>
          {gettext("stan na %{date}", date: Format.date(@product.cardmarket_price_updated_on))}
        </p>
      </div>
      <%= if @product.cardmarket_trend || @reverse do %>
        <p :if={@product.cardmarket_trend} id="cardmarket-trend" class="cardmarket-trend">
          {gettext("Trend:")} <strong>{Format.eur(@product.cardmarket_trend)}</strong>
          <span :if={@converted? && @cardmarket_price}>≈ {Format.rough_price(@cardmarket_price)}</span>
        </p>
        <p :if={@reverse} class="cardmarket-trend">
          {gettext("Reverse holo:")}
          <strong>{Format.eur(@reverse)}</strong><span :if={@converted? && @reverse_pln}>≈ {Format.rough_price(
            @reverse_pln
          )}</span>
        </p>
        <p class="guide-note">
          {gettext("Europejska giełda.")}
          <span :if={@converted? && @eur_rate}>
            {euro_rate_note(@eur_rate)}
          </span>
          <span :if={@product.cardmarket_added_on} id="product-added">
            {gettext("Na Cardmarket od %{date}.", date: Format.date(@product.cardmarket_added_on))
            |> Format.sentence()}
          </span>
        </p>
        <p class="reference-link">
          <a href={cardmarket_url(@product.cardmarket_id)} target="_blank" rel="noopener nofollow">
            {gettext("Zobacz na Cardmarket")} →
          </a>
        </p>
      <% else %>
        <p id="cardmarket-none" class="guide-note">
          {gettext("Cardmarket nie podaje jeszcze ceny tego produktu.")}
        </p>
      <% end %>
    </section>
    """
  end

  @doc """
  Whether the current region prices in euro, as Cardmarket does: its
  Cardmarket prices need no conversion, nor a note on the euro's rate.
  """
  @spec euro_region?() :: boolean()
  def euro_region?, do: Region.current().market.currency == "EUR"

  @doc """
  The euro's rate behind a Cardmarket price in the region's currency: NBP's
  own for złoty; another currency's goes through złoty at NBP's rates.
  """
  @spec euro_rate_note(%{rate: Decimal.t(), date: Date.t()}) :: String.t()
  def euro_rate_note(rate) do
    note =
      case Format.currency_symbol() do
        "zł" ->
          gettext("Kurs NBP %{rate} zł z %{date}.",
            rate: Format.rate(rate.rate),
            date: Format.date(rate.date)
          )

        # A rate tens or hundreds of units to the euro reads in hundredths.
        currency ->
          gettext("Kurs %{rate} %{currency} za euro z kursów NBP z %{date}.",
            rate: Format.rate(rate.rate, 2),
            currency: currency,
            date: Format.date(rate.date)
          )
      end

    Format.sentence(note)
  end
end
