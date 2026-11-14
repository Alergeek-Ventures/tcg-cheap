defmodule TcgCheapWeb.ListingComponents do
  @moduledoc "The rows of the product and card lists, with their images, prices and meta lines."

  use TcgCheapWeb, :html

  use Gettext, backend: TcgCheapWeb.Gettext

  import TcgCheapWeb.OfferComponents
  import TcgCheapWeb.VerdictComponents

  alias TcgCheap.Sealed.{CardGuide, Kinds, Rarities, Regions}
  alias TcgCheapWeb.{Format, Paths, Region}

  def card_variant_label(:normal), do: gettext("Zwykła / holo")
  def card_variant_label(:reverse), do: gettext("Reverse holo")
  def card_variant_label(:special), do: gettext("Wzór specjalny")

  @doc """
  Product packaging image from our storage, else a placeholder drawn for its kind.

  With a `blur` (the photo's tiny inline preview), the preview shows blurred
  right away and the photo fades in over it once it has loaded (see the
  `data-progressive` script in the root layout).
  """
  attr :small_photo, :string, default: nil, doc: "the `small` variant (192 px), once stored"
  attr :photo, :string, default: nil
  attr :page_photo, :string, default: nil
  attr :blur, :string, default: nil
  attr :sizes, :string, default: nil
  attr :kind, :atom, default: nil
  attr :alt, :string, required: true
  attr :class, :any, default: nil
  attr :loading, :string, default: "lazy"
  attr :fetchpriority, :string, default: nil

  def product_image(assigns) do
    assigns =
      assigns
      |> assign(:url, assigns.photo)
      |> assign(:srcset, srcset(assigns))
      |> assign(:shape, placeholder_shape(assigns.kind))

    ~H"""
    <div class={["product-image", !@url && "product-image-placeholder", @class]}>
      <img :if={@url && @blur} src={@blur} alt="" aria-hidden="true" class="product-image-blur" />
      <img
        :if={@url}
        data-progressive={@blur && true}
        src={@url}
        srcset={@srcset}
        sizes={@srcset && @sizes}
        alt={@alt}
        loading={@loading}
        fetchpriority={@fetchpriority}
        decoding="async"
        referrerpolicy="no-referrer"
      />
      <svg :if={!@url && @alt == ""} viewBox="0 0 64 48" aria-hidden="true" focusable="false">
        <path :for={d <- @shape} d={d} />
      </svg>
      <svg
        :if={!@url && @alt != ""}
        viewBox="0 0 64 48"
        role="img"
        aria-label={gettext("Brak zdjęcia")}
      >
        <path :for={d <- @shape} d={d} />
      </svg>
    </div>
    """
  end

  defp srcset(%{photo: photo, page_photo: page_photo} = assigns)
       when is_binary(photo) and is_binary(page_photo) do
    [{assigns.small_photo, 192}, {photo, 352}, {page_photo, 960}]
    |> Enum.filter(&elem(&1, 0))
    |> Enum.map_join(", ", fn {url, width} -> "#{url} #{width}w" end)
  end

  defp srcset(_assigns), do: nil

  @doc "Line drawings (64×48, stroked) of the packaging, so a product without a photo still reads by shape."
  @spec placeholder_shape(atom()) :: [String.t()]
  def placeholder_shape(:booster),
    do: ["M24 6h16l2 4-2 4v20l2 4-2 4H24l-2-4 2-4V14l-2-4z", "M24 14h16M24 34h16"]

  def placeholder_shape(:blister),
    do: ["M14 6h36v36H14z", "M20 14h10v22H20zM34 14h10v22H34z", "M28 9h8"]

  def placeholder_shape(:tin),
    do: ["M16 12c0-4 32-4 32 0v24c0 4-32 4-32 0z", "M16 12c0 4 32 4 32 0"]

  def placeholder_shape(:deck), do: ["M18 8h24v32H18z", "M22 12h16v24H22z"]

  def placeholder_shape(:card_set),
    do: ["M14 10h20v28H14z", "M22 8h20v28H22z", "M30 6h20v28H30z"]

  def placeholder_shape(:case), do: ["M8 12h48v28H8z", "M8 20h48M24 12v28M40 12v28"]
  def placeholder_shape(:booster_box), do: ["M10 16h44v24H10z", "M10 16l6-8h44l-6 8M54 40l6-8V8"]
  def placeholder_shape(_kind), do: ["M8 10h48v30H8z", "M8 18h48M24 10v8M40 10v8"]

  @doc "A card's row in a list: image, name, number and set, cheapest shop, verdict and price."
  attr :id, :string, required: true
  attr :row, :map, required: true
  attr :placement, :string, default: "list", doc: "where the click came from, for analytics"
  attr :rarity?, :boolean, default: false, doc: "name the rarity, for printings of one card"

  attr :verdict?, :boolean,
    default: true,
    doc: "judge the shop's price; a guide for sellers shows the price alone"

  def card_row(assigns) do
    # With an offer in stock, the row answers as the card's page does: its
    # cheapest shop, the verdict and that shop's price. Without one, the
    # lower known price.
    polish? = Region.poland?(Region.current())

    assigns =
      assign(assigns,
        status: single_verdict_status(assigns.row.verdict),
        # Elsewhere than in Poland, only Cardmarket's price: no shop there sells singles.
        offer: if(polish?, do: assigns.row.offer),
        price:
          card_price(%{
            polish_price: assigns.row.price,
            cardmarket_trend_pln: assigns.row.cardmarket_trend_pln
          })
      )

    ~H"""
    <li
      id={@id}
      class="guide-product guide-card"
    >
      <.link
        navigate={Paths.localize(@row.path)}
        class="guide-product-link"
        data-track="card_clicked"
        data-track-placement={@placement}
        data-track-card={@row.card.id}
        data-track-card-name={@row.card.name}
        data-track-verdict={@row.verdict}
      >
        <div class="guide-product-image guide-card-image">
          <img
            :if={@row.image}
            src={@row.image}
            alt=""
            loading="lazy"
            width="88"
            height="88"
          />
          <span :if={!@row.image} class="guide-card-placeholder" aria-hidden="true"></span>
        </div>
        <div class="guide-product-copy">
          <h3 class="guide-product-name">{@row.card.name}</h3>
          <p class="guide-product-meta">
            <span :if={@rarity? && @row.card.rarity}>{Rarities.label(@row.card.rarity)} ·</span>
            {@row.card.number} · {@row.expansion_name}
          </p>
        </div>
        <div class="guide-product-deal">
          <%= if @offer do %>
            <span class="guide-product-shop">{priced_shop_name(@offer)}</span>
            <%!-- Without a Cardmarket price there is nothing to judge; the card's page says why. --%>
            <.verdict_badge
              :if={@verdict? and @status != :insufficient_data}
              verdict={%{status: @status}}
              id={"card-verdict-#{@row.card.id}"}
              class="guide-product-verdict"
            />
            <p class="guide-product-price"><strong>{Format.price(@offer.price)}</strong></p>
          <% else %>
            <p class="guide-product-price">
              <strong :if={@price}>{Format.price(@price)}</strong>
              <span :if={!@price}>{gettext("Cena nieznana")}</span>
            </p>
          <% end %>
        </div>
      </.link>
    </li>
    """
  end

  @doc """
  A card's price in the current region: in Poland the lower of its Polish
  shop price and its Cardmarket trend (`CardGuide.price/1`); elsewhere its
  Cardmarket trend in the region's currency, as singles have no shops there.
  """
  @spec card_price(map()) :: Decimal.t() | nil
  def card_price(card) do
    if Region.poland?(Region.current()),
      do: CardGuide.price(card),
      else: card |> Map.get(:cardmarket_trend_pln) |> Region.from_pln()
  end

  @doc "A product's row in a list: photo, name, kind, cheapest shop, verdict and price."
  attr :summary, :map, required: true
  attr :priority, :boolean, default: false, doc: "the list's first photo, loaded eagerly"

  attr :delivery_noted?, :boolean,
    default: false,
    doc:
      "a note above the list says which prices include delivery (`RegionText.list_prices_note/0`), so the row names only the shop"

  def product_row(assigns) do
    ~H"""
    <.link
      navigate={Paths.product(@summary.product.slug)}
      class="guide-product-link"
      data-track="product_clicked"
      data-track-product-slug={@summary.product.slug}
      data-track-verdict={@summary.verdict.status}
      data-track-preorder={to_string(@summary.preorder?)}
    >
      <.product_image
        small_photo={@summary.product.stored_photo_small_url}
        photo={@summary.product.stored_photo_card_url}
        page_photo={@summary.product.stored_photo_page_url}
        blur={@summary.product.photo_placeholder}
        sizes="(max-width: 42rem) 4.5rem, 5.5rem"
        loading={if(@priority, do: "eager", else: "lazy")}
        fetchpriority={if(@priority, do: "high")}
        kind={@summary.product.kind}
        alt=""
        class="guide-product-image"
      />
      <div class="guide-product-copy">
        <h3 class="guide-product-name">{@summary.product.name}</h3>
        <p class="guide-product-meta">
          {product_meta(@summary.product)}
        </p>
      </div>
      <div class="guide-product-deal">
        <span :if={@summary.verdict.cheapest} class="guide-product-shop">
          {if(@delivery_noted?,
            do: shop_name(@summary.verdict.cheapest),
            else: priced_shop_name(@summary.verdict.cheapest)
          )}
        </span>
        <%!-- Too few shops for a verdict: the row shows only the price; the product page says why. --%>
        <.verdict_badge
          :if={@summary.verdict.status not in [:cardmarket, :insufficient_data]}
          verdict={@summary.verdict}
          id={"verdict-#{@summary.product.slug}"}
          class="guide-product-verdict"
        />
        <p :if={@summary.verdict.cheapest} class="guide-product-price">
          <span
            :if={@summary.preorder?}
            id={"preorder-#{@summary.product.slug}"}
            class="guide-product-preorder"
          >
            <.verdict_icon status={:preorder} />{preorder_tag(@summary.premiere_in)}
          </span>
          <strong>{Format.price(@summary.verdict.cheapest.price)}</strong>
        </p>
      </div>
    </.link>
    """
  end

  @doc """
  Kind, the set where the name does not already say it, and the language
  edition unless English: "Kolekcja · Pitch Black", "Booster · Japońska".
  """
  @spec product_meta(TcgCheap.Sealed.Product.t()) :: String.t()
  def product_meta(%{set_name: set} = product) do
    set =
      if set && !String.contains?(String.downcase(product.name), String.downcase(set)), do: set

    region = if product.region != :en, do: Regions.label(product.region)

    [Kinds.label(product.kind), set, region]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end

  @doc ~S'The list tag of a pre-order: "przedsprzedaż · za 4 dni", or plain without a coming premiere.'
  @spec preorder_tag(non_neg_integer() | nil) :: String.t()
  def preorder_tag(nil), do: gettext("przedsprzedaż")

  def preorder_tag(days),
    do: gettext("przedsprzedaż · %{when}", when: Format.days_until(days))
end
