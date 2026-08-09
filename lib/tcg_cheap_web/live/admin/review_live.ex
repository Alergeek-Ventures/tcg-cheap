defmodule TcgCheapWeb.Admin.ReviewLive do
  @moduledoc "Authenticated review desk for sealed catalogue and listing decisions."

  use TcgCheapWeb, :live_view

  alias TcgCheap.Catalogue.{ListingProductMapping, SealedProduct, SealedProductAlias}
  alias TcgCheap.Core

  @product_type_options [
    {"Booster pack", "booster_pack"},
    {"Sleeved booster", "sleeved_booster"},
    {"Booster bundle", "booster_bundle"},
    {"Booster box", "booster_box"},
    {"Elite Trainer Box", "elite_trainer_box"},
    {"Tin", "tin"},
    {"Collection box", "collection_box"},
    {"Deck", "deck"},
    {"Trainer toolkit", "trainer_toolkit"},
    {"Other", "other"}
  ]

  @review_events ~w(
    revise_product
    approve_product
    archive_product
    approve_alias
    reject_alias
    approve_mapping
    reject_mapping
  )

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Sealed review desk")
     |> assign(:product_type_options, @product_type_options)
     |> load_review_desk()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div id="admin-review" class="admin-world">
        <header class="admin-header">
          <.link id="admin-review-home" navigate={~p"/"}>TCG CHEAP</.link>
          <nav id="admin-review-header-nav" aria-label="Admin sections">
            <.link id="admin-review-header-link" navigate={~p"/admin/review"} aria-current="page">
              Review
            </.link>
            <.link id="admin-review-operations-header-link" navigate={~p"/admin/operations"}>Operations</.link>
          </nav>
          <div class="admin-header-actions">
            <span>{@current_admin.email}</span>
            <.link id="admin-sign-out" href={~p"/admin/sign-out"} method="delete">Sign out</.link>
          </div>
        </header>

        <main class="admin-main">
          <div class="admin-container">
            <section class="admin-intro" aria-labelledby="admin-review-title">
              <div>
                <h1 id="admin-review-title">Sealed review desk</h1>
                <p>Confirm identity before anything can reach the collector catalogue.</p>
              </div>
              <nav id="admin-queue-nav" aria-label="Review queues">
                <a href="#draft-products">Products <strong>{@queue_counts.products}</strong></a>
                <a href="#pending-aliases">Aliases <strong>{@queue_counts.aliases}</strong></a>
                <a href="#listing-mappings">Mappings <strong>{@queue_counts.mappings}</strong></a>
              </nav>
            </section>

            <section id="draft-products" class="admin-queue" aria-labelledby="draft-products-title">
              <div class="admin-section-rule">
                <h2 id="draft-products-title">Draft products</h2>
                <span>{@queue_counts.products} waiting</span>
              </div>

              <div id="draft-product-queue" class="admin-dockets" phx-update="stream">
                <p id="draft-product-empty" class="admin-empty hidden only:block">
                  No product drafts need review.
                </p>
                <article
                  :for={{dom_id, product} <- @streams.draft_products}
                  id={dom_id}
                  class="admin-docket product-docket"
                >
                  <% form = Map.fetch!(@product_forms, product.id) %>
                  <div class="admin-docket-heading">
                    <div>
                      <h3>{product.name}</h3>
                      <p>{product.slug}</p>
                    </div>
                    <span>Product draft</span>
                  </div>

                  <.form
                    for={form}
                    id={"product-review-form-#{product.id}"}
                    phx-submit="revise_product"
                    class="admin-product-form"
                  >
                    <.input field={form[:id]} id={"product-#{product.id}-id"} type="hidden" />
                    <.input
                      field={form[:expected_updated_at]}
                      id={"product-#{product.id}-version"}
                      type="hidden"
                    />
                    <.input
                      field={form[:name]}
                      id={"product-#{product.id}-name"}
                      type="text"
                      label="Canonical name"
                      required
                    />
                    <.input
                      field={form[:slug]}
                      id={"product-#{product.id}-slug"}
                      type="text"
                      label="Stable slug"
                      required
                    />
                    <.input
                      field={form[:product_type]}
                      id={"product-#{product.id}-type"}
                      type="select"
                      label="Product type"
                      options={@product_type_options}
                    />
                    <.input
                      field={form[:series_name]}
                      id={"product-#{product.id}-series"}
                      type="text"
                      label="Series"
                    />
                    <.input
                      field={form[:set_name]}
                      id={"product-#{product.id}-set"}
                      type="text"
                      label="Set"
                    />
                    <.input
                      field={form[:release_date]}
                      id={"product-#{product.id}-release-date"}
                      type="date"
                      label="Release date"
                    />
                    <.input
                      field={form[:msrp_pln]}
                      id={"product-#{product.id}-msrp"}
                      type="number"
                      step="0.01"
                      label="MSRP (PLN)"
                    />
                    <.input
                      field={form[:msrp_source]}
                      id={"product-#{product.id}-msrp-source"}
                      type="text"
                      label="MSRP source"
                    />
                    <.input
                      field={form[:msrp_source_url]}
                      id={"product-#{product.id}-msrp-url"}
                      type="url"
                      label="MSRP source URL"
                    />
                    <.input
                      field={form[:image_url]}
                      id={"product-#{product.id}-image-url"}
                      type="url"
                      label="Image URL"
                    />
                    <.input
                      field={form[:officially_distributed]}
                      id={"product-#{product.id}-official"}
                      type="checkbox"
                      label="Officially distributed in Poland in English"
                    />
                    <button id={"save-product-#{product.id}"} type="submit">Save draft</button>
                  </.form>

                  <div class="admin-decision-row">
                    <button
                      id={"approve-product-#{product.id}"}
                      type="button"
                      phx-click="approve_product"
                      phx-value-id={product.id}
                      phx-value-version={DateTime.to_iso8601(product.updated_at)}
                    >
                      Approve product
                    </button>
                    <button
                      id={"archive-product-#{product.id}"}
                      type="button"
                      class="secondary-action"
                      phx-click="archive_product"
                      phx-value-id={product.id}
                      phx-value-version={DateTime.to_iso8601(product.updated_at)}
                    >
                      Archive draft
                    </button>
                  </div>
                </article>
              </div>
            </section>

            <section id="pending-aliases" class="admin-queue" aria-labelledby="pending-aliases-title">
              <div class="admin-section-rule">
                <h2 id="pending-aliases-title">Pending aliases</h2>
                <span>{@queue_counts.aliases} waiting</span>
              </div>

              <div id="pending-alias-queue" class="admin-dockets compact-dockets" phx-update="stream">
                <p id="pending-alias-empty" class="admin-empty hidden only:block">
                  No aliases need review.
                </p>
                <article
                  :for={{dom_id, alias_record} <- @streams.pending_aliases}
                  id={dom_id}
                  class="admin-docket alias-docket"
                >
                  <div class="admin-docket-heading">
                    <div>
                      <h3>{alias_record.original_value}</h3>
                      <p>{alias_record.sealed_product.name}</p>
                    </div>
                    <span>{String.upcase(alias_record.kind)}</span>
                  </div>
                  <dl class="admin-evidence-grid">
                    <div>
                      <dt>Normalized</dt><dd>{alias_record.normalized_value}</dd>
                    </div>
                    <div>
                      <dt>Product slug</dt><dd>{alias_record.sealed_product.slug}</dd>
                    </div>
                  </dl>
                  <div class="admin-decision-row">
                    <button
                      id={"approve-alias-#{alias_record.id}"}
                      type="button"
                      phx-click="approve_alias"
                      phx-value-id={alias_record.id}
                      phx-value-version={DateTime.to_iso8601(alias_record.updated_at)}
                    >
                      Approve alias
                    </button>
                    <button
                      id={"reject-alias-#{alias_record.id}"}
                      type="button"
                      class="secondary-action"
                      phx-click="reject_alias"
                      phx-value-id={alias_record.id}
                      phx-value-version={DateTime.to_iso8601(alias_record.updated_at)}
                    >
                      Reject alias
                    </button>
                  </div>
                </article>
              </div>
            </section>

            <section
              id="listing-mappings"
              class="admin-queue"
              aria-labelledby="listing-mappings-title"
            >
              <div class="admin-section-rule">
                <h2 id="listing-mappings-title">Listing mappings</h2>
                <span>{@queue_counts.mappings} waiting</span>
              </div>

              <div id="listing-mapping-queue" class="admin-dockets" phx-update="stream">
                <p id="listing-mapping-empty" class="admin-empty hidden only:block">
                  No retailer listings need mapping review.
                </p>
                <article
                  :for={{dom_id, mapping} <- @streams.listing_mappings}
                  id={dom_id}
                  class="admin-docket mapping-docket"
                >
                  <% approve_form = Map.fetch!(@mapping_approve_forms, mapping.id) %>
                  <% reject_form = Map.fetch!(@mapping_reject_forms, mapping.id) %>
                  <div class="admin-docket-heading">
                    <div>
                      <h3>{mapping.retailer_listing.source_title}</h3>
                      <p>
                        {mapping.retailer_listing.retailer.name} · {mapping.retailer_listing.source_listing_id}
                      </p>
                    </div>
                    <span>{String.upcase(mapping.status)}</span>
                  </div>

                  <dl class="admin-evidence-grid">
                    <div>
                      <dt>Price / stock</dt>
                      <dd>
                        {format_price(mapping.retailer_listing.current_price_pln)} · {mapping.retailer_listing.stock_status}
                      </dd>
                    </div>
                    <div>
                      <dt>GTIN</dt><dd>{mapping.retailer_listing.gtin || "Not supplied"}</dd>
                    </div>
                    <div>
                      <dt>Candidate</dt><dd>{candidate_name(mapping)}</dd>
                    </div>
                    <div>
                      <dt>Confidence</dt><dd>{format_decimal(mapping.confidence)}</dd>
                    </div>
                    <div class="wide-evidence">
                      <dt>Reason</dt><dd>{mapping.reason || "No matcher reason"}</dd>
                    </div>
                    <div class="wide-evidence">
                      <dt>Evidence</dt><dd>{format_evidence(mapping.evidence)}</dd>
                    </div>
                    <div class="wide-evidence">
                      <dt>Source</dt>
                      <dd>
                        <a
                          id={"mapping-source-#{mapping.id}"}
                          href={mapping.retailer_listing.direct_url}
                          target="_blank"
                          rel="noopener noreferrer"
                        >
                          Open retailer listing
                        </a>
                      </dd>
                    </div>
                  </dl>

                  <.form
                    for={approve_form}
                    id={"approve-mapping-form-#{mapping.id}"}
                    phx-submit="approve_mapping"
                    class="mapping-decision-form"
                  >
                    <.input
                      field={approve_form[:id]}
                      id={"mapping-#{mapping.id}-approve-id"}
                      type="hidden"
                    />
                    <.input
                      field={approve_form[:expected_updated_at]}
                      id={"mapping-#{mapping.id}-approve-version"}
                      type="hidden"
                    />
                    <.input
                      field={approve_form[:confirmed_product_id]}
                      id={"mapping-#{mapping.id}-confirmed-product"}
                      type="select"
                      label="Confirmed canonical product"
                      options={@approved_product_options}
                      prompt="Choose an approved product"
                    />
                    <button
                      id={"approve-mapping-#{mapping.id}"}
                      type="submit"
                      disabled={@approved_product_options == []}
                    >
                      Approve mapping
                    </button>
                  </.form>

                  <.form
                    for={reject_form}
                    id={"reject-mapping-form-#{mapping.id}"}
                    phx-submit="reject_mapping"
                    class="mapping-decision-form reject-form"
                  >
                    <.input
                      field={reject_form[:id]}
                      id={"mapping-#{mapping.id}-reject-id"}
                      type="hidden"
                    />
                    <.input
                      field={reject_form[:expected_updated_at]}
                      id={"mapping-#{mapping.id}-reject-version"}
                      type="hidden"
                    />
                    <.input
                      field={reject_form[:reason]}
                      id={"mapping-#{mapping.id}-reason"}
                      type="text"
                      label="Rejection reason"
                      placeholder="Why this listing must not map"
                      required
                    />
                    <button id={"reject-mapping-#{mapping.id}"} type="submit" class="secondary-action">
                      Reject mapping
                    </button>
                  </.form>
                </article>
              </div>
            </section>
          </div>
        </main>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event(
        "revise_product",
        %{"product" => %{"id" => id, "expected_updated_at" => expected_updated_at} = params},
        socket
      ) do
    attrs =
      params
      |> Map.drop(["id", "expected_updated_at"])
      |> nil_if_blank()
      |> Map.put(:expected_updated_at, expected_updated_at)

    with {:ok, %SealedProduct{} = product} <- get_product(id, socket),
         {:ok, _product} <-
           Core.revise_sealed_product_draft(product, attrs, actor: socket.assigns.current_admin) do
      {:noreply, succeed(socket, "Draft saved.")}
    else
      {:error, error} -> {:noreply, fail(socket, "Draft was not saved", error)}
    end
  end

  def handle_event("approve_product", %{"id" => id, "version" => expected_updated_at}, socket) do
    with {:ok, %SealedProduct{} = product} <- get_product(id, socket),
         {:ok, _product} <-
           Core.approve_sealed_product(product, %{expected_updated_at: expected_updated_at},
             actor: socket.assigns.current_admin
           ) do
      {:noreply, succeed(socket, "Product approved.")}
    else
      {:error, error} -> {:noreply, fail(socket, "Product was not approved", error)}
    end
  end

  def handle_event("archive_product", %{"id" => id, "version" => expected_updated_at}, socket) do
    with {:ok, %SealedProduct{} = product} <- get_product(id, socket),
         {:ok, _product} <-
           Core.archive_sealed_product(product, %{expected_updated_at: expected_updated_at},
             actor: socket.assigns.current_admin
           ) do
      {:noreply, succeed(socket, "Draft archived.")}
    else
      {:error, error} -> {:noreply, fail(socket, "Draft was not archived", error)}
    end
  end

  def handle_event("approve_alias", %{"id" => id, "version" => expected_updated_at}, socket) do
    with {:ok, %SealedProductAlias{} = alias_record} <- get_alias(id, socket),
         {:ok, _alias_record} <-
           Core.approve_sealed_product_alias(
             alias_record,
             %{expected_updated_at: expected_updated_at},
             actor: socket.assigns.current_admin
           ) do
      {:noreply, succeed(socket, "Alias approved.")}
    else
      {:error, error} -> {:noreply, fail(socket, "Alias was not approved", error)}
    end
  end

  def handle_event("reject_alias", %{"id" => id, "version" => expected_updated_at}, socket) do
    with {:ok, %SealedProductAlias{} = alias_record} <- get_alias(id, socket),
         {:ok, _alias_record} <-
           Core.reject_sealed_product_alias(
             alias_record,
             %{expected_updated_at: expected_updated_at},
             actor: socket.assigns.current_admin
           ) do
      {:noreply, succeed(socket, "Alias rejected.")}
    else
      {:error, error} -> {:noreply, fail(socket, "Alias was not rejected", error)}
    end
  end

  def handle_event(
        "approve_mapping",
        %{
          "mapping" => %{
            "id" => id,
            "confirmed_product_id" => confirmed_product_id,
            "expected_updated_at" => expected_updated_at
          }
        },
        socket
      ) do
    with true <- confirmed_product_id != "",
         {:ok, %ListingProductMapping{} = mapping} <- get_mapping(id, socket),
         {:ok, _mapping} <-
           Core.approve_listing_mapping(
             mapping,
             %{
               confirmed_product_id: confirmed_product_id,
               confidence: Decimal.new(1),
               evidence: %{method: "admin_review"},
               expected_updated_at: expected_updated_at
             },
             actor: socket.assigns.current_admin
           ) do
      {:noreply, succeed(socket, "Listing mapping approved.")}
    else
      false -> {:noreply, fail(socket, "Listing mapping was not approved", :missing_product)}
      {:error, error} -> {:noreply, fail(socket, "Listing mapping was not approved", error)}
    end
  end

  def handle_event(
        "reject_mapping",
        %{
          "mapping" => %{
            "id" => id,
            "reason" => reason,
            "expected_updated_at" => expected_updated_at
          }
        },
        socket
      ) do
    with reason when is_binary(reason) and byte_size(reason) > 0 <- String.trim(reason),
         {:ok, %ListingProductMapping{} = mapping} <- get_mapping(id, socket),
         {:ok, _mapping} <-
           Core.reject_listing_mapping(
             mapping,
             %{reason: reason, expected_updated_at: expected_updated_at},
             actor: socket.assigns.current_admin
           ) do
      {:noreply, succeed(socket, "Listing mapping rejected.")}
    else
      "" -> {:noreply, fail(socket, "Listing mapping was not rejected", :missing_reason)}
      {:error, error} -> {:noreply, fail(socket, "Listing mapping was not rejected", error)}
    end
  end

  def handle_event(event, _params, socket) when event in @review_events do
    {:noreply, fail(socket, "Review action was not accepted", :invalid_review_event)}
  end

  defp load_review_desk(socket) do
    actor = socket.assigns.current_admin
    products = Core.list_sealed_product_draft_review_queue!(actor: actor)
    aliases = Core.list_sealed_product_alias_pending_queue!(actor: actor)
    mappings = Core.list_listing_mapping_review_queue!(actor: actor)
    approved_products = Core.list_public_sealed_products!(actor: actor)
    approved_product_ids = MapSet.new(approved_products, & &1.id)

    socket
    |> assign(:queue_counts, %{
      products: length(products),
      aliases: length(aliases),
      mappings: length(mappings)
    })
    |> assign(:product_forms, Map.new(products, &{&1.id, product_form(&1)}))
    |> assign(
      :approved_product_options,
      Enum.map(approved_products, &{"#{&1.name} · #{&1.slug}", &1.id})
    )
    |> assign(
      :mapping_approve_forms,
      Map.new(mappings, fn mapping ->
        selected_id =
          if mapping.candidate_product_id in approved_product_ids,
            do: mapping.candidate_product_id,
            else: nil

        {mapping.id,
         to_form(
           %{
             "id" => mapping.id,
             "confirmed_product_id" => selected_id,
             "expected_updated_at" => DateTime.to_iso8601(mapping.updated_at)
           },
           as: :mapping
         )}
      end)
    )
    |> assign(
      :mapping_reject_forms,
      Map.new(mappings, fn mapping ->
        {mapping.id,
         to_form(
           %{
             "id" => mapping.id,
             "reason" => "",
             "expected_updated_at" => DateTime.to_iso8601(mapping.updated_at)
           },
           as: :mapping
         )}
      end)
    )
    |> stream(:draft_products, products, reset: true)
    |> stream(:pending_aliases, aliases, reset: true)
    |> stream(:listing_mappings, mappings, reset: true)
  end

  defp product_form(product) do
    to_form(
      %{
        "id" => product.id,
        "expected_updated_at" => DateTime.to_iso8601(product.updated_at),
        "name" => product.name,
        "slug" => product.slug,
        "product_type" => product.product_type,
        "series_name" => product.series_name,
        "set_name" => product.set_name,
        "release_date" => product.release_date,
        "msrp_pln" => product.msrp_pln,
        "msrp_source" => product.msrp_source,
        "msrp_source_url" => product.msrp_source_url,
        "image_url" => product.image_url,
        "officially_distributed" => product.officially_distributed
      },
      as: :product
    )
  end

  defp get_product(id, socket) do
    case Core.get_sealed_product_draft_for_review(id, actor: socket.assigns.current_admin) do
      {:ok, nil} -> {:error, :stale_review}
      result -> result
    end
  end

  defp get_alias(id, socket) do
    case Core.get_pending_sealed_product_alias_for_review(id,
           actor: socket.assigns.current_admin
         ) do
      {:ok, nil} -> {:error, :stale_review}
      result -> result
    end
  end

  defp get_mapping(id, socket) do
    case Core.get_listing_mapping_for_review(id, actor: socket.assigns.current_admin) do
      {:ok, nil} -> {:error, :stale_review}
      result -> result
    end
  end

  defp succeed(socket, message) do
    socket
    |> put_flash(:info, message)
    |> load_review_desk()
  end

  defp fail(socket, message, error) do
    socket
    |> put_flash(:error, "#{message}. #{review_error(error)}")
    |> load_review_desk()
  end

  defp review_error(:stale_review), do: "Another review already changed this row."
  defp review_error(:missing_product), do: "Choose an approved canonical product."
  defp review_error(:missing_reason), do: "Add a reason before rejecting it."
  defp review_error(:invalid_review_event), do: "Reload the queue and try again."

  defp review_error(error) do
    error
    |> Exception.message()
    |> String.replace(~r/\s+/, " ")
    |> String.slice(0, 240)
  rescue
    _ -> "Check the evidence and try again."
  end

  defp nil_if_blank(params) do
    Map.new(params, fn
      {key, value} when is_binary(value) ->
        case String.trim(value) do
          "" -> {key, nil}
          trimmed -> {key, trimmed}
        end

      pair ->
        pair
    end)
  end

  defp candidate_name(%{candidate_product: %SealedProduct{} = product}),
    do: "#{product.name} · #{product.slug}"

  defp candidate_name(_mapping), do: "No candidate"

  defp format_price(nil), do: "No price"
  defp format_price(price), do: "#{Decimal.to_string(price, :normal)} PLN"

  defp format_decimal(nil), do: "Not scored"
  defp format_decimal(value), do: Decimal.to_string(value, :normal)

  defp format_evidence(nil), do: "No structured evidence"
  defp format_evidence(evidence), do: Jason.encode!(evidence)
end
