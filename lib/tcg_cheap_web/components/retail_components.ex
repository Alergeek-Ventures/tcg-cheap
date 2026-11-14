defmodule TcgCheapWeb.RetailComponents do
  @moduledoc "Retail chains' deals: the section listing them and the leaflet clippings."

  use TcgCheapWeb, :html

  use Gettext, backend: TcgCheapWeb.Gettext

  alias TcgCheap.Sealed.RetailDeal
  alias TcgCheapWeb.{Format, Paths}

  attr :id, :string, required: true
  attr :deals, :list, required: true
  attr :title, :string, required: true
  attr :products?, :boolean, default: false, doc: "name each deal's product, for lists of many"

  @doc """
  Retail chains' prices running today (`TcgCheap.Sealed.RetailDeal`), with
  their days and source, apart from the shop offers: stock differs from shop
  to shop, so they never enter the verdict.
  """
  def retail_deals(assigns) do
    ~H"""
    <section id={@id} class="product-section retail-deals" aria-labelledby={"#{@id}-title"}>
      <div class="product-section-heading">
        <h2 id={"#{@id}-title"}>{@title}</h2>
      </div>
      <.retail_clips id={@id} deals={@deals} products?={@products?} />
      <p class="guide-note">
        {gettext("Ceny z gazetek i zgłoszeń. Dostępność różna, nie wliczamy ich do oceny.")}
      </p>
    </section>
    """
  end

  attr :id, :string, required: true, doc: "prefix of each deal's DOM id"
  attr :deals, :list, required: true
  attr :products?, :boolean, default: false, doc: "name each deal's product, for lists of many"

  @doc """
  Retail deals as clippings from a leaflet, as the chains print them: the
  chain's logo, the price on a sticker, "nowe" for a deal that started in the
  last two days, then its days and the source the price was checked in.
  """
  def retail_clips(assigns) do
    ~H"""
    <ul class="retail-clips">
      <li
        :for={deal <- @deals}
        id={"#{@id}-#{deal.id}"}
        class={["retail-clip", !@products? && "retail-clip-unnamed"]}
      >
        <span :if={fresh_deal?(deal)} class="retail-clip-fresh">{gettext("nowe")}</span>
        <%!-- Every chain's logo carries its name, so the clipping shows no name beside it. --%>
        <img
          src={~p"/images/chains/#{Atom.to_string(deal.chain) <> ".webp"}"}
          alt={RetailDeal.chain_name(deal.chain)}
          width="96"
          height="32"
          loading="lazy"
          class={[
            "retail-clip-logo",
            RetailDeal.square_logo?(deal.chain) && "retail-clip-logo-square"
          ]}
        />
        <strong class="retail-clip-sticker">{Format.price(deal.price)}</strong>
        <p :if={@products?} class="retail-clip-name">
          <.link :if={deal.product} navigate={Paths.product(deal.product.slug)}>{deal.product.name}</.link>
          <span :if={!deal.product}>{deal.title}</span>
        </p>
        <p class="retail-clip-when">{deal_days(deal)}</p>
        <p class="retail-clip-source">
          <a
            href={deal.source_url}
            target="_blank"
            rel="noopener nofollow"
            data-track="retail_deal_source_clicked"
            data-track-chain={deal.chain}
            aria-label={
              gettext("%{chain}: źródło ceny (otwiera się w nowej karcie)",
                chain: RetailDeal.chain_name(deal.chain)
              )
            }
          >{gettext("źródło")}&nbsp;↗</a>
        </p>
      </li>
    </ul>
    """
  end

  defp fresh_deal?(deal), do: Date.diff(Date.utc_today(), deal.starts_on) <= 2

  @doc ~S(A retail deal's days and caveat: "2–8 listopada · wybrane sklepy".)
  def deal_days(deal) do
    # A no-break space keeps each "·" at the end of a line, never at the start.
    [Format.days(deal.starts_on, deal.ends_on), deal.note]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\u00A0· ")
  end
end
