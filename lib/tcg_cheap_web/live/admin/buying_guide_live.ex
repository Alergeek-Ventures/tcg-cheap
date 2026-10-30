defmodule TcgCheapWeb.Admin.BuyingGuideLive do
  @moduledoc """
  Read-only buying-guide desk: what each shop's last fetch returned and which
  current offers match no catalogue product (candidates for new entries).
  """

  use TcgCheapWeb, :live_view

  alias TcgCheap.Sealed
  alias TcgCheap.Sealed.{Catalogue, Matcher, Shops}
  alias TcgCheapWeb.Polish

  @impl true
  def mount(_params, _session, socket) do
    now = DateTime.utc_now()
    offers = Sealed.list_offers!()
    current = Sealed.current_offers(now)

    {unmatched, excluded} =
      current
      |> Enum.reject(& &1.product_slug)
      |> Enum.split_with(&(not Matcher.excluded?(&1.title)))

    {:ok,
     socket
     |> assign(:page_title, "Buying guide")
     |> assign(:shops, shop_rows(offers, current))
     |> assign(:product_count, length(Catalogue.all()))
     |> assign(:unmatched_count, length(unmatched))
     |> assign(:excluded_count, length(excluded))
     |> stream(:unmatched, Enum.sort_by(unmatched, &{&1.shop, &1.title}))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin
      flash={@flash}
      current_url={~p"/admin/buying-guide"}
      current_admin={@current_admin}
    >
      <div id="admin-buying-guide" class="admin-world">
        <main class="admin-main">
          <div class="admin-container">
            <section class="admin-intro" aria-labelledby="admin-buying-guide-title">
              <div>
                <h1 id="admin-buying-guide-title">Buying guide</h1>
                <p>
                  {@product_count} catalogue products. Shops are fetched once a day; an offer counts while it was in
                  its shop's latest fetch (at most 3 days old). To cover an unmatched offer, add a product to
                  <code>TcgCheap.Sealed.Catalogue</code>
                  and deploy.
                </p>
              </div>
            </section>

            <section
              id="buying-guide-shops"
              class="admin-queue"
              aria-labelledby="buying-guide-shops-title"
            >
              <div class="admin-section-rule">
                <h2 id="buying-guide-shops-title">Shops</h2>
                <span>Last successful fetch</span>
              </div>
              <div class="admin-table-wrap">
                <table id="buying-guide-shop-table" class="admin-table">
                  <thead>
                    <tr>
                      <th scope="col">Shop</th>
                      <th scope="col">Last fetch (UTC)</th>
                      <th scope="col">Offers seen</th>
                      <th scope="col">Matched</th>
                      <th scope="col">Matched in stock</th>
                    </tr>
                  </thead>
                  <tbody>
                    <tr :for={shop <- @shops} id={"buying-guide-shop-#{shop.key}"}>
                      <th scope="row">{shop.name}</th>
                      <td class="admin-nowrap">{fetched_at(shop.last_fetch)}</td>
                      <td>{shop.seen}</td>
                      <td>{shop.matched}</td>
                      <td>{shop.matched_in_stock}</td>
                    </tr>
                  </tbody>
                </table>
              </div>
            </section>

            <section
              id="buying-guide-unmatched"
              class="admin-queue"
              aria-labelledby="buying-guide-unmatched-title"
            >
              <div class="admin-section-rule">
                <h2 id="buying-guide-unmatched-title">Unmatched offers</h2>
                <span id="buying-guide-unmatched-count">
                  {@unmatched_count} unmatched · {@excluded_count} excluded (non-English, preorder, bundle, accessory)
                </span>
              </div>
              <div class="admin-table-wrap">
                <table class="admin-table">
                  <thead>
                    <tr>
                      <th scope="col">Shop</th>
                      <th scope="col">Title</th>
                      <th scope="col">Price</th>
                      <th scope="col">Stock</th>
                    </tr>
                  </thead>
                  <tbody id="buying-guide-unmatched-list" phx-update="stream">
                    <tr id="buying-guide-unmatched-empty" class="hidden only:table-row">
                      <td colspan="4">Every current offer matches a catalogue product.</td>
                    </tr>
                    <tr :for={{dom_id, offer} <- @streams.unmatched} id={dom_id}>
                      <td class="admin-nowrap">{Shops.name(offer.shop)}</td>
                      <td>
                        <a href={offer.url} target="_blank" rel="noopener nofollow">{offer.title}</a>
                      </td>
                      <td class="admin-nowrap">{Polish.price(offer.price)}</td>
                      <td class="admin-nowrap">
                        {if offer.in_stock, do: "in stock", else: "out of stock"}
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>
            </section>
          </div>
        </main>
      </div>
    </Layouts.admin>
    """
  end

  defp shop_rows(offers, current) do
    by_shop = Enum.group_by(offers, & &1.shop)
    current_by_shop = Enum.group_by(current, & &1.shop)

    for shop <- Shops.all() do
      seen =
        case Map.get(by_shop, shop.key, []) do
          [] -> []
          shop_offers -> Sealed.latest_per_shop(shop_offers)
        end

      matched = Enum.filter(seen, & &1.product_slug)

      %{
        key: shop.key,
        name: shop.name,
        last_fetch: seen |> List.first() |> then(&(&1 && &1.last_seen_at)),
        seen: length(seen),
        matched: length(matched),
        matched_in_stock:
          current_by_shop
          |> Map.get(shop.key, [])
          |> Enum.count(&(&1.product_slug && &1.in_stock))
      }
    end
  end

  defp fetched_at(nil), do: "never"
  defp fetched_at(%DateTime{} = at), do: Calendar.strftime(at, "%Y-%m-%d %H:%M")
end
