defmodule TcgCheapWeb.Admin.BuyingGuideLive do
  @moduledoc """
  Buying-guide desk: what each shop's last fetch returned, the current offers
  that match no catalogue product, the automatically matched ones, and manual
  decisions. An offer can be assigned to a product by hand, kept unmatched for
  good, or handed back to automatic matching; manual decisions are never
  overwritten by automatic matching.
  """

  use TcgCheapWeb, :live_view

  alias TcgCheap.Repo
  alias TcgCheap.Sealed
  alias TcgCheap.Sealed.{Kinds, Matcher, Refresh, Shops}
  alias TcgCheapWeb.Polish

  @result_limit 10
  @matched_limit 50

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Buying guide")
     |> assign(:assigning, nil)
     |> assign(:results, [])
     |> assign(:search_form, to_form(%{"query" => ""}, as: :product_search))
     |> assign(:matched_filter, to_form(%{"title" => ""}, as: :matched_filter))
     |> load()}
  end

  @impl true
  def handle_event("start_assign", %{"offer-id" => id}, socket) do
    case Sealed.get_offer(id) do
      {:ok, offer} ->
        {:noreply,
         socket
         |> assign(:assigning, offer)
         |> assign(:results, search(offer.title))
         |> assign(:search_form, to_form(%{"query" => offer.title}, as: :product_search))}

      _ ->
        {:noreply, put_flash(socket, :error, "That offer no longer exists.")}
    end
  end

  def handle_event("cancel_assign", _params, socket),
    do: {:noreply, socket |> assign(:assigning, nil) |> assign(:results, [])}

  def handle_event("search_products", %{"product_search" => %{"query" => query}}, socket)
      when is_binary(query) do
    {:noreply,
     socket
     |> assign(:results, search(query))
     |> assign(:search_form, to_form(%{"query" => query}, as: :product_search))}
  end

  def handle_event(
        "assign",
        %{"product-id" => product_id},
        %{assigns: %{assigning: offer}} = socket
      )
      when not is_nil(offer) do
    case write(fn ->
           Sealed.assign_offer_manually(offer, product_id, return_notifications?: true)
         end) do
      :ok ->
        {:noreply,
         socket
         |> assign(:assigning, nil)
         |> assign(:results, [])
         |> put_flash(:info, "Offer assigned.")
         |> load()}

      :error ->
        {:noreply, put_flash(socket, :error, "The offer could not be assigned.")}
    end
  end

  def handle_event("filter_matched", %{"matched_filter" => %{"title" => title}}, socket)
      when is_binary(title) do
    {:noreply,
     socket
     |> assign(:matched_filter, to_form(%{"title" => title}, as: :matched_filter))
     |> load()}
  end

  def handle_event("exclude", %{"offer-id" => id}, socket) do
    with {:ok, offer} <- Sealed.get_offer(id),
         :ok <- write(fn -> Sealed.exclude_offer_manually(offer, return_notifications?: true) end) do
      {:noreply, socket |> put_flash(:info, "The offer will stay unmatched.") |> load()}
    else
      _ -> {:noreply, put_flash(socket, :error, "The offer could not be unmatched.")}
    end
  end

  def handle_event("clear_manual", %{"offer-id" => id}, socket) do
    with {:ok, offer} <- Sealed.get_offer(id),
         :ok <- write(fn -> Sealed.clear_manual_offer(offer, return_notifications?: true) end) do
      {:noreply, socket |> put_flash(:info, "Manual assignment cleared.") |> load()}
    else
      _ -> {:noreply, put_flash(socket, :error, "The assignment could not be cleared.")}
    end
  end

  def handle_event(_event, _params, socket), do: {:noreply, socket}

  # Applies an assignment and immediately re-derives prices from it.
  defp write(action) do
    result =
      Repo.transaction(
        fn ->
          # Nothing subscribes to offer notifications; they are dropped.
          case action.() do
            {:ok, _offer, _notifications} -> Refresh.recompute(DateTime.utc_now())
            {:error, error} -> Repo.rollback(error)
          end
        end,
        timeout: Refresh.transaction_timeout()
      )

    if match?({:ok, _}, result), do: :ok, else: :error
  end

  defp search(query) do
    query
    |> Sealed.browse_products!(nil, page: [limit: @result_limit])
    |> Map.fetch!(:results)
  end

  defp load(socket) do
    now = DateTime.utc_now()
    offers = Sealed.list_offers!()
    current = Sealed.current_offers(now)

    {unmatched, excluded} =
      current
      |> Enum.reject(&(&1.product_id || &1.manual?))
      |> Enum.split_with(&(not Matcher.excluded?(&1.title)))

    title_filter = socket.assigns.matched_filter[:title].value |> String.downcase()

    matched =
      current
      |> Enum.filter(
        &(&1.product_id && not &1.manual? &&
            String.contains?(String.downcase(&1.title), title_filter))
      )
      |> Enum.sort_by(&{&1.shop, &1.title})

    matched_page = matched |> Enum.take(@matched_limit) |> Ash.load!(:product, domain: Sealed)
    manual = Sealed.list_manual_offers!()

    socket
    |> assign(:matched_limit, @matched_limit)
    |> assign(:shops, shop_rows(offers, current))
    |> assign(:product_count, Ash.count!(Sealed.Product, domain: Sealed))
    |> assign(:unmatched_count, length(unmatched))
    |> assign(:excluded_count, length(excluded))
    |> assign(:manual_count, length(manual))
    |> stream(:unmatched, Enum.sort_by(unmatched, &{&1.shop, &1.title}), reset: true)
    |> assign(:matched_count, length(matched))
    |> stream(:matched, matched_page, reset: true)
    |> stream(:manual, manual, reset: true)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin
      socket={@socket}
      flash={@flash}
      sidebar_open={@sidebar_open}
      preferences_manifest={@preferences_manifest}
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
                  {@product_count} catalogue products imported daily from Cardmarket. Shops are fetched once a day;
                  an offer counts while it was in its shop's latest fetch (at most 3 days old). Offers are matched
                  automatically; assign the rest by hand below.
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
              :if={@assigning}
              id="buying-guide-assign"
              class="admin-queue"
              aria-labelledby="buying-guide-assign-title"
            >
              <div class="admin-section-rule">
                <h2 id="buying-guide-assign-title">Assign offer</h2>
                <span>{Shops.name(@assigning.shop)} · {@assigning.title}</span>
              </div>
              <.form
                for={@search_form}
                id="buying-guide-product-search"
                phx-change="search_products"
                phx-submit="search_products"
              >
                <.input
                  field={@search_form[:query]}
                  type="search"
                  label="Search the catalogue"
                  autocomplete="off"
                  phx-debounce="300"
                />
              </.form>
              <ul id="buying-guide-product-results" class="admin-results">
                <li :if={@results == []} id="buying-guide-no-results">No matching products.</li>
                <li :for={product <- @results} id={"result-#{product.id}"}>
                  <span>
                    <strong>{product.name}</strong>
                    {Kinds.label(product.kind)}{if product.set_name, do: " · #{product.set_name}"} · Cardmarket #{product.cardmarket_id}
                  </span>
                  <button
                    type="button"
                    id={"assign-#{product.id}"}
                    phx-click="assign"
                    phx-value-product-id={product.id}
                  >Assign</button>
                </li>
              </ul>
              <button
                type="button"
                id="buying-guide-cancel-assign"
                class="secondary-action"
                phx-click="cancel_assign"
              >
                Cancel
              </button>
            </section>

            <section
              id="buying-guide-unmatched"
              class="admin-queue"
              aria-labelledby="buying-guide-unmatched-title"
            >
              <div class="admin-section-rule">
                <h2 id="buying-guide-unmatched-title">Unmatched offers</h2>
                <span id="buying-guide-unmatched-count">
                  {@unmatched_count} unmatched · {@excluded_count} excluded (preorder, bundle of many, accessory)
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
                      <th scope="col"><span class="sr-only">Action</span></th>
                    </tr>
                  </thead>
                  <tbody id="buying-guide-unmatched-list" phx-update="stream">
                    <tr id="buying-guide-unmatched-empty" class="hidden only:table-row">
                      <td colspan="5">Every current offer matches a catalogue product.</td>
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
                      <td>
                        <button
                          type="button"
                          id={"start-assign-#{offer.id}"}
                          phx-click="start_assign"
                          phx-value-offer-id={offer.id}
                        >Assign…</button>
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>
            </section>

            <section
              id="buying-guide-matched"
              class="admin-queue"
              aria-labelledby="buying-guide-matched-title"
            >
              <div class="admin-section-rule">
                <h2 id="buying-guide-matched-title">Matched offers</h2>
                <span id="buying-guide-matched-count">
                  {@matched_count} matched automatically; showing up to {@matched_limit}
                </span>
              </div>
              <.form
                for={@matched_filter}
                id="buying-guide-matched-filter"
                phx-change="filter_matched"
                phx-submit="filter_matched"
              >
                <.input
                  field={@matched_filter[:title]}
                  type="search"
                  label="Filter by offer title"
                  autocomplete="off"
                  phx-debounce="300"
                />
              </.form>
              <div class="admin-table-wrap">
                <table class="admin-table">
                  <thead>
                    <tr>
                      <th scope="col">Shop</th>
                      <th scope="col">Offer</th>
                      <th scope="col">Product</th>
                      <th scope="col">Price</th>
                      <th scope="col"><span class="sr-only">Actions</span></th>
                    </tr>
                  </thead>
                  <tbody id="buying-guide-matched-list" phx-update="stream">
                    <tr id="buying-guide-matched-empty" class="hidden only:table-row">
                      <td colspan="5">No automatically matched offers.</td>
                    </tr>
                    <tr :for={{dom_id, offer} <- @streams.matched} id={dom_id}>
                      <td class="admin-nowrap">{Shops.name(offer.shop)}</td>
                      <td>
                        <a href={offer.url} target="_blank" rel="noopener nofollow">{offer.title}</a>
                      </td>
                      <td>
                        <.link navigate={~p"/produkty/#{offer.product.slug}"}>{offer.product.name}</.link>
                      </td>
                      <td class="admin-nowrap">{Polish.price(offer.price)}</td>
                      <td class="admin-nowrap">
                        <button
                          type="button"
                          id={"reassign-#{offer.id}"}
                          phx-click="start_assign"
                          phx-value-offer-id={offer.id}
                        >Reassign…</button>
                        <button
                          type="button"
                          id={"exclude-#{offer.id}"}
                          class="secondary-action"
                          phx-click="exclude"
                          phx-value-offer-id={offer.id}
                        >Never match</button>
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>
            </section>

            <section
              id="buying-guide-manual"
              class="admin-queue"
              aria-labelledby="buying-guide-manual-title"
            >
              <div class="admin-section-rule">
                <h2 id="buying-guide-manual-title">Manual assignments</h2>
                <span>{@manual_count} kept regardless of automatic matching</span>
              </div>
              <div class="admin-table-wrap">
                <table class="admin-table">
                  <thead>
                    <tr>
                      <th scope="col">Shop</th>
                      <th scope="col">Offer</th>
                      <th scope="col">Product</th>
                      <th scope="col"><span class="sr-only">Action</span></th>
                    </tr>
                  </thead>
                  <tbody id="buying-guide-manual-list" phx-update="stream">
                    <tr id="buying-guide-manual-empty" class="hidden only:table-row">
                      <td colspan="4">No manual assignments.</td>
                    </tr>
                    <tr :for={{dom_id, offer} <- @streams.manual} id={dom_id}>
                      <td class="admin-nowrap">{Shops.name(offer.shop)}</td>
                      <td>{offer.title}</td>
                      <td>
                        <.link :if={offer.product} navigate={~p"/produkty/#{offer.product.slug}"}>
                          {offer.product.name}
                        </.link>
                        <span :if={is_nil(offer.product)}>Never matched</span>
                      </td>
                      <td>
                        <button
                          type="button"
                          id={"clear-manual-#{offer.id}"}
                          class="secondary-action"
                          phx-click="clear_manual"
                          phx-value-offer-id={offer.id}
                        >Clear</button>
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

  # The offers seen in a shop's latest fetch, however long ago it was.
  defp latest_fetch([]), do: []

  defp latest_fetch(offers) do
    latest = offers |> Enum.map(& &1.last_seen_at) |> Enum.max(DateTime)
    Enum.filter(offers, &(DateTime.compare(&1.last_seen_at, latest) == :eq))
  end

  defp shop_rows(offers, current) do
    by_shop = Enum.group_by(offers, & &1.shop)
    current_by_shop = Enum.group_by(current, & &1.shop)

    for shop <- Shops.all() do
      seen = by_shop |> Map.get(shop.key, []) |> latest_fetch()

      %{
        key: shop.key,
        name: shop.name,
        last_fetch: seen |> List.first() |> then(&(&1 && &1.last_seen_at)),
        seen: length(seen),
        matched: Enum.count(seen, & &1.product_id),
        matched_in_stock:
          current_by_shop
          |> Map.get(shop.key, [])
          |> Enum.count(&(&1.product_id && &1.in_stock))
      }
    end
  end

  defp fetched_at(nil), do: "never"
  defp fetched_at(%DateTime{} = at), do: Calendar.strftime(at, "%Y-%m-%d %H:%M")
end
