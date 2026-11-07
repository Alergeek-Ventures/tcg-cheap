defmodule TcgCheapWeb.BoosterPriceLive do
  @moduledoc """
  What a Pokémon booster costs in Poland today: the answer on top, the
  retail chains' deals running today, then each recent English set's
  booster with its cheapest shop price and verdict.
  """

  use TcgCheapWeb, :live_view
  use Gettext, backend: TcgCheapWeb.Gettext

  import TcgCheapWeb.GuideComponents

  alias TcgCheap.Sealed.Guide
  alias TcgCheapWeb.{Polish, SEO, VisitorLocation}

  @impl true
  def mount(_params, _session, socket) do
    page = Guide.booster_prices(DateTime.utc_now())
    seo = SEO.booster_prices(page)

    {:ok,
     socket
     |> assign(page: page, seo: seo, page_title: seo.title)
     |> VisitorLocation.assign_location()}
  end

  @impl true
  def handle_event("location-" <> _ = event, params, socket),
    do: {:noreply, VisitorLocation.handle_event(event, params, socket)}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <SEO.sync seo={@seo} />
      <div class="guide-world">
        <.site_header locale={@locale} return_to={@locale_return_to}>
          <VisitorLocation.location_control
            location={@location}
            ready={@location_ready?}
            form={@town_form}
            matches={@town_matches}
            error={@location_error}
          />
        </.site_header>
        <main
          id="booster-prices"
          class="guide-main product-page booster-prices"
          data-guide-url={@locale_return_to}
        >
          <.link id="booster-prices-back" data-guide-back navigate={~p"/"} class="guide-back">
            <.fluent_icon name={:arrow_left} />{gettext("Wszystkie produkty")}
          </.link>

          <%!-- The answer as the product page states a price: the figure, then where. --%>
          <section class="booster-prices-intro" aria-labelledby="booster-prices-title">
            <h1 id="booster-prices-title">{gettext("Ile kosztuje booster Pokémon?")}</h1>
            <%= if cheapest = @page.cheapest do %>
              <p id="booster-prices-from" class="verdict-price">
                {gettext("od %{price}", price: Polish.price(cheapest.verdict.cheapest.price))}
              </p>
              <p id="booster-prices-answer" class="guide-note">
                {gettext("%{product} w %{shop} · najnowszy set, %{set}: od %{price}",
                  product: cheapest.product.name,
                  shop: shop_name(cheapest.verdict.cheapest),
                  set: hd(@page.boosters).product.set_name,
                  price: Polish.price(hd(@page.boosters).verdict.cheapest.price)
                )}
              </p>
            <% else %>
              <p id="booster-prices-answer">{SEO.booster_answer(@page)}</p>
            <% end %>
          </section>

          <.retail_deals
            :if={@page.retail_deals != []}
            id="booster-prices-retail-deals"
            title={gettext("Okazje w sieciówkach")}
            deals={@page.retail_deals}
            products?
          />

          <section
            id="booster-prices-shops"
            class="product-section"
            aria-labelledby="booster-prices-shops-title"
          >
            <div class="product-section-heading">
              <h2 id="booster-prices-shops-title">{gettext("Boostery w polskich sklepach")}</h2>
              <p>{gettext("angielskie, najnowsze sety najpierw")}</p>
            </div>
            <ul id="booster-prices-list" class="guide-products">
              <li :if={@page.boosters == []} class="guide-empty">
                {gettext("Teraz żaden polski sklep nie ma angielskiego boostera na stanie.")}
              </li>
              <li
                :for={summary <- @page.boosters}
                id={"booster-#{summary.product.slug}"}
                class="guide-product"
              >
                <.link
                  navigate={~p"/produkty/#{summary.product.slug}"}
                  class="guide-product-link"
                  data-track="product_clicked"
                  data-track-product-slug={summary.product.slug}
                >
                  <.product_image
                    small_photo={summary.product.stored_photo_small_url}
                    photo={summary.product.stored_photo_card_url}
                    blur={summary.product.photo_placeholder}
                    kind={summary.product.kind}
                    sizes="(max-width: 42rem) 4.5rem, 5.5rem"
                    alt=""
                    class="guide-product-image"
                  />
                  <div class="guide-product-copy">
                    <h3 class="guide-product-name">{summary.product.set_name}</h3>
                  </div>
                  <div class="guide-product-deal">
                    <span :if={summary.verdict.cheapest} class="guide-product-shop">
                      {shop_name(summary.verdict.cheapest)}
                    </span>
                    <p :if={summary.verdict.cheapest} class="guide-product-price">
                      <strong>{Polish.price(summary.verdict.cheapest.price)}</strong>
                    </p>
                  </div>
                </.link>
              </li>
            </ul>
            <p class="guide-note">
              {gettext(
                "Najniższa cena na stanie w polskich sklepach internetowych, bez dostawy. Ocenę ceny znajdziesz na stronie boostera."
              )}
            </p>
          </section>
        </main>
        <.site_footer sets={@footer_sets} />
      </div>
    </Layouts.app>
    """
  end
end
