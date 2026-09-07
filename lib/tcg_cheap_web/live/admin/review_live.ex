defmodule TcgCheapWeb.Admin.ReviewLive do
  @moduledoc "Authenticated review desk for sealed catalogue and listing decisions."

  use TcgCheapWeb, :live_view

  alias TcgCheap.Catalogue.{
    CardmarketExpansionMapping,
    ListingProductMapping,
    SealedProduct,
    SealedProductAlias
  }

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
    create_product_draft
  )

  @visible_queue_limit 25

  @impl true
  def mount(params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Catalogue review desk")
      |> assign(:product_type_options, @product_type_options)
      |> assign(:visible_queue_limit, @visible_queue_limit)
      |> assign(:targeted_mapping_id, nil)

    case Map.get(params, "mapping_id") do
      nil -> {:ok, load_review_desk(socket)}
      mapping_id -> mount_targeted_mapping(socket, mapping_id)
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin
      flash={@flash}
      current_url={~p"/admin/review"}
      current_admin={@current_admin}
    >
      <div id="admin-review" class="admin-world">
        <main class="admin-main">
          <div class="admin-container">
            <section class="admin-intro" aria-labelledby="admin-review-title">
              <div>
                <h1 id="admin-review-title">Catalogue review desk</h1>
                <p>Verify evidence before publishing catalogue decisions.</p>
              </div>
              <nav id="admin-queue-nav" aria-label="Review queues">
                <a href="#draft-products">Products <strong>{@queue_counts.products}</strong></a>
                <a href="#pending-aliases">Aliases <strong>{@queue_counts.aliases}</strong></a>
                <a href="#listing-mappings">Mappings <strong>{@queue_counts.mappings}</strong></a>
                <a href="#cardmarket-expansion-reviews">Expansions
                <strong>{@queue_counts.expansions}</strong></a>
              </nav>
            </section>

            <section
              id="cardmarket-expansion-reviews"
              class="admin-queue"
              aria-labelledby="cardmarket-expansion-reviews-title"
            >
              <div class="admin-section-rule">
                <h2 id="cardmarket-expansion-reviews-title">Cardmarket expansions</h2>
                <span>
                  {if @cardmarket_expansion_review_status == :unavailable,
                    do: "Unavailable",
                    else: "#{@queue_counts.expansions} waiting"}
                </span>
              </div>
              <p
                :if={@queue_limit_notes.expansions}
                id="cardmarket-expansion-review-limit"
                class="admin-queue-limit"
              >
                {@queue_limit_notes.expansions}
              </p>
              <div id="cardmarket-expansion-review-queue" class="admin-dockets" phx-update="stream">
                <p
                  :if={@cardmarket_expansion_review_status == :empty}
                  id="cardmarket-expansion-review-empty"
                  class="admin-empty"
                >
                  No Cardmarket expansion reviews need approval.
                </p>
                <p
                  :if={@cardmarket_expansion_review_status == :unavailable}
                  id="cardmarket-expansion-review-unavailable"
                  class="admin-state-error"
                >
                  Unable to load Cardmarket expansion reviews. No healthy or empty state is being assumed.
                </p>
                <article
                  :for={{dom_id, mapping} <- @streams.cardmarket_expansion_reviews}
                  id={dom_id}
                  class="admin-docket"
                >
                  <% form = Map.fetch!(@cardmarket_expansion_forms, mapping.id) %>
                  <h3>{mapping.card_set.name}</h3>
                  <p>Cardmarket expansion {mapping.expansion_id} · {mapping.anchor_count} anchors</p>
                  <p id={"cardmarket-expansion-#{mapping.id}-review-reason"}>
                    Reason: {mapping.review_reason}
                  </p>
                  <p id={"cardmarket-expansion-#{mapping.id}-evidence"}>
                    Evidence: {format_evidence(mapping.evidence)}
                  </p>
                  <.form
                    for={form}
                    id={"approve-cardmarket-expansion-form-#{mapping.id}"}
                    phx-submit="approve_cardmarket_expansion"
                  >
                    <.input
                      field={form[:source_mapping_id]}
                      id={"cardmarket-expansion-#{mapping.id}-source"}
                      type="hidden"
                    />
                    <.input
                      field={form[:expected_updated_at]}
                      id={"cardmarket-expansion-#{mapping.id}-version"}
                      type="hidden"
                    />
                    <.input
                      field={form[:reason]}
                      id={"cardmarket-expansion-#{mapping.id}-approval-reason"}
                      type="text"
                      label="Approval reason"
                      required
                      maxlength="2000"
                    />
                    <button id={"approve-cardmarket-expansion-#{mapping.id}"} type="submit">Approve expansion</button>
                  </.form>
                </article>
              </div>
            </section>

            <section id="draft-products" class="admin-queue" aria-labelledby="draft-products-title">
              <div class="admin-section-rule">
                <h2 id="draft-products-title">Draft products</h2>
                <span>{@queue_counts.products} waiting</span>
              </div>
              <p
                :if={@queue_limit_notes.products}
                id="draft-products-limit"
                class="admin-queue-limit"
              >
                {@queue_limit_notes.products}
              </p>

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
                    <section class="admin-form-section admin-form-section--identity">
                      <h4>Identity</h4>
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
                    </section>
                    <section class="admin-form-section admin-form-section--classification">
                      <h4>Classification</h4>
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
                    </section>
                    <section class="admin-form-section admin-form-section--pricing-media">
                      <h4>Pricing and media</h4>
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
                    </section>
                    <section class="admin-form-section admin-form-section--details">
                      <h4>Product details</h4>
                      <.input
                        field={form[:description]}
                        id={"product-#{product.id}-description"}
                        type="textarea"
                        label="Description"
                      />
                      <.input
                        field={form[:contents]}
                        id={"product-#{product.id}-contents"}
                        type="textarea"
                        label="Contents (one item per line)"
                      />
                      <.input
                        field={form[:pack_count]}
                        id={"product-#{product.id}-pack-count"}
                        type="number"
                        label="Pack count"
                      />
                      <.input
                        field={form[:cards_per_pack]}
                        id={"product-#{product.id}-cards-per-pack"}
                        type="number"
                        label="Cards per pack"
                      />
                      <.input
                        field={form[:official_url]}
                        id={"product-#{product.id}-official-url"}
                        type="url"
                        label="Official product URL"
                      />
                      <.input
                        field={form[:details_source]}
                        id={"product-#{product.id}-details-source"}
                        type="text"
                        label="Details source"
                      />
                      <.input
                        field={form[:details_source_url]}
                        id={"product-#{product.id}-details-source-url"}
                        type="url"
                        label="Details source URL"
                      />
                    </section>
                    <section class="admin-form-section admin-form-section--reference-price">
                      <h4>Official reference price</h4>
                      <.input
                        field={form[:official_price_amount]}
                        id={"product-#{product.id}-official-price"}
                        type="number"
                        step="0.01"
                        label="Amount"
                      />
                      <.input
                        field={form[:official_price_currency]}
                        id={"product-#{product.id}-official-currency"}
                        type="text"
                        label="Currency"
                      />
                      <.input
                        field={form[:official_price_source]}
                        id={"product-#{product.id}-official-price-source"}
                        type="text"
                        label="Price source"
                      />
                      <.input
                        field={form[:official_price_source_url]}
                        id={"product-#{product.id}-official-price-source-url"}
                        type="url"
                        label="Price source URL"
                      />
                    </section>
                    <section class="admin-form-section admin-form-section--image-provenance">
                      <h4>Image provenance</h4>
                      <.input
                        field={form[:image_url]}
                        id={"product-#{product.id}-image-url"}
                        type="url"
                        label="Canonical image URL"
                      />
                      <.input
                        field={form[:image_source]}
                        id={"product-#{product.id}-image-source"}
                        type="text"
                        label="Image source"
                      />
                      <.input
                        field={form[:image_source_url]}
                        id={"product-#{product.id}-image-source-url"}
                        type="url"
                        label="Image source URL"
                      />
                    </section>
                    <section class="admin-form-section admin-form-section--publication">
                      <h4>Publication</h4>
                      <.input
                        field={form[:officially_distributed]}
                        id={"product-#{product.id}-official"}
                        type="checkbox"
                        label="Officially distributed in Poland in English"
                      />
                      <button id={"save-product-#{product.id}"} type="submit">Save draft</button>
                    </section>
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
              <p
                :if={@queue_limit_notes.aliases}
                id="pending-aliases-limit"
                class="admin-queue-limit"
              >
                {@queue_limit_notes.aliases}
              </p>

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
              <p
                :if={@queue_limit_notes.mappings}
                id="listing-mappings-limit"
                class="admin-queue-limit"
              >
                {@queue_limit_notes.mappings}
              </p>

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
                  <details class="admin-docket-details">
                    <summary class="admin-docket-summary">
                      <strong>{mapping.retailer_listing.source_title}</strong>
                      <span class="admin-docket-meta">
                        {mapping.retailer_listing.retailer.name} · {mapping.retailer_listing.source_listing_id}
                      </span>
                      <span class="admin-docket-status">{String.upcase(mapping.status)}</span>
                    </summary>
                    <div class="admin-docket-body">
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

                      <button
                        id={"create-product-draft-#{mapping.id}"}
                        type="button"
                        class="secondary-action"
                        phx-click="create_product_draft"
                        phx-value-id={mapping.id}
                      >
                        Create product draft
                      </button>

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
                          maxlength="2000"
                        />
                        <button
                          id={"reject-mapping-#{mapping.id}"}
                          type="submit"
                          class="secondary-action"
                        >
                          Reject mapping
                        </button>
                      </.form>
                    </div>
                  </details>
                </article>
              </div>
            </section>
          </div>
        </main>
      </div>
    </Layouts.admin>
    """
  end

  @impl true
  def handle_event(
        "approve_cardmarket_expansion",
        %{"cardmarket_expansion_mapping" => params},
        socket
      ) do
    with {:ok, %CardmarketExpansionMapping{} = mapping} <-
           get_cardmarket_mapping(params["source_mapping_id"], socket),
         {:ok, _} <-
           Core.approve_cardmarket_expansion(
             mapping.card_set,
             %{
               source_mapping_id: mapping.id,
               reason: params["reason"],
               expected_updated_at: params["expected_updated_at"]
             },
             actor: socket.assigns.current_admin
           ) do
      {:noreply, succeed(socket, "Cardmarket expansion approved.")}
    else
      {:error, error} -> {:noreply, fail(socket, "Cardmarket expansion was not approved", error)}
    end
  end

  def handle_event(
        "revise_product",
        %{"product" => %{"id" => id, "expected_updated_at" => expected_updated_at} = params},
        socket
      ) do
    attrs =
      params
      |> Map.drop(["id", "expected_updated_at"])
      |> parse_contents()
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
        "create_product_draft",
        %{"id" => id},
        socket
      ) do
    with {:ok, %ListingProductMapping{} = mapping} <- get_mapping(id, socket),
         {:ok, _product} <-
           Core.create_sealed_product_draft_from_listing(
             mapping.retailer_listing_id,
             actor: socket.assigns.current_admin
           ) do
      {:noreply, succeed(socket, "Product draft created from retailer listing.")}
    else
      {:error, error} -> {:noreply, fail(socket, "Product draft was not created", error)}
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

  defp load_review_desk(socket, targeted_mappings \\ nil) do
    actor = socket.assigns.current_admin

    {products, aliases, mappings} =
      case targeted_mappings do
        nil ->
          fetched_queue_limit = @visible_queue_limit + 1

          {
            Core.list_sealed_product_draft_review_queue!(
              query: [limit: fetched_queue_limit],
              actor: actor
            ),
            Core.list_sealed_product_alias_pending_queue!(
              query: [limit: fetched_queue_limit],
              actor: actor
            ),
            Core.list_listing_mapping_review_queue!(
              query: [limit: fetched_queue_limit],
              actor: actor
            )
          }

        mappings when is_list(mappings) ->
          {[], [], mappings}
      end

    {expansions, cardmarket_expansion_review_status} = cardmarket_review_queue(actor)

    approved_products = Core.list_approved_sealed_products!(actor: actor)
    approved_product_ids = MapSet.new(approved_products, & &1.id)
    visible_products = Enum.take(products, @visible_queue_limit)
    visible_aliases = Enum.take(aliases, @visible_queue_limit)
    visible_mappings = Enum.take(mappings, @visible_queue_limit)

    queue_counts = %{
      products: queue_count(products),
      aliases: queue_count(aliases),
      mappings: queue_count(mappings),
      expansions: expansion_queue_count(expansions, cardmarket_expansion_review_status)
    }

    queue_limit_notes = %{
      products: queue_limit_note(products),
      aliases: queue_limit_note(aliases),
      mappings: queue_limit_note(mappings),
      expansions: expansion_queue_limit_note(expansions, cardmarket_expansion_review_status)
    }

    socket
    |> assign(:queue_counts, queue_counts)
    |> assign(:queue_limit_notes, queue_limit_notes)
    |> assign(:cardmarket_expansion_review_status, cardmarket_expansion_review_status)
    |> assign(
      :cardmarket_expansion_forms,
      Map.new(Enum.take(expansions, @visible_queue_limit), fn mapping ->
        {mapping.id,
         to_form(
           %{
             "source_mapping_id" => mapping.id,
             "expected_updated_at" => DateTime.to_iso8601(mapping.card_set.updated_at),
             "reason" => ""
           },
           as: :cardmarket_expansion_mapping
         )}
      end)
    )
    |> assign(:product_forms, Map.new(visible_products, &{&1.id, product_form(&1)}))
    |> assign(
      :approved_product_options,
      Enum.map(approved_products, &{"#{&1.name} · #{&1.slug}", &1.id})
    )
    |> assign(
      :mapping_approve_forms,
      Map.new(visible_mappings, fn mapping ->
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
      Map.new(visible_mappings, fn mapping ->
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
    |> stream(:draft_products, visible_products, reset: true)
    |> stream(:pending_aliases, visible_aliases, reset: true)
    |> stream(:listing_mappings, visible_mappings, reset: true)
    |> stream(:cardmarket_expansion_reviews, Enum.take(expansions, @visible_queue_limit),
      reset: true
    )
  end

  defp cardmarket_review_queue(actor) do
    with {:ok, batch} when not is_nil(batch) <-
           Core.get_latest_successful_cardmarket_bulk_batch(actor: actor),
         {:ok, mappings} <- Core.list_cardmarket_expansion_review_queue(batch.id, actor: actor) do
      {mappings, if(mappings == [], do: :empty, else: :ok)}
    else
      {:ok, nil} -> {[], :empty}
      _ -> {[], :unavailable}
    end
  end

  defp expansion_queue_count(_queue, :unavailable), do: "Unavailable"
  defp expansion_queue_count(queue, _status), do: queue_count(queue)

  defp expansion_queue_limit_note(_queue, :unavailable), do: nil
  defp expansion_queue_limit_note(queue, _status), do: queue_limit_note(queue)

  defp mount_targeted_mapping(socket, mapping_id) do
    case Ecto.UUID.cast(mapping_id) do
      {:ok, uuid} ->
        case Core.get_listing_mapping_for_review(uuid, actor: socket.assigns.current_admin) do
          {:ok, %ListingProductMapping{} = mapping} ->
            {:ok, load_review_desk(assign(socket, :targeted_mapping_id, uuid), [mapping])}

          {:ok, nil} ->
            {:ok, unavailable_mapping_redirect(socket)}

          {:error, error} ->
            raise error
        end

      :error ->
        {:ok, unavailable_mapping_redirect(socket)}
    end
  end

  defp queue_count(queue) when length(queue) > @visible_queue_limit,
    do: "#{@visible_queue_limit}+"

  defp queue_count(queue), do: length(queue)

  defp queue_limit_note(queue) when length(queue) > @visible_queue_limit,
    do: "Showing first #{@visible_queue_limit}"

  defp queue_limit_note(_queue), do: nil

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
        "description" => product.description,
        "contents" => Enum.join(product.contents || [], "\n"),
        "pack_count" => product.pack_count,
        "cards_per_pack" => product.cards_per_pack,
        "official_url" => product.official_url,
        "details_source" => product.details_source,
        "details_source_url" => product.details_source_url,
        "official_price_amount" => product.official_price_amount,
        "official_price_currency" => product.official_price_currency,
        "official_price_source" => product.official_price_source,
        "official_price_source_url" => product.official_price_source_url,
        "image_source" => product.image_source,
        "image_source_url" => product.image_source_url,
        "officially_distributed" => product.officially_distributed
      },
      as: :product
    )
  end

  defp parse_contents(params) do
    case Map.fetch(params, "contents") do
      {:ok, value} when is_binary(value) ->
        Map.put(params, "contents", String.split(value, "\n", trim: true))

      {:ok, value} when is_list(value) ->
        Map.put(
          params,
          "contents",
          Enum.filter(value, &(is_binary(&1) and String.trim(&1) != ""))
        )

      _ ->
        params
    end
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

  defp get_cardmarket_mapping(id, socket) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} ->
        case Core.get_cardmarket_expansion_mapping(uuid, actor: socket.assigns.current_admin) do
          {:ok, nil} -> {:error, :stale_review}
          result -> result
        end

      :error ->
        {:error, :stale_review}
    end
  end

  defp succeed(socket, message) do
    socket = put_flash(socket, :info, message)

    case socket.assigns.targeted_mapping_id do
      nil -> load_review_desk(socket)
      _mapping_id -> redirect(socket, to: ~p"/admin/review")
    end
  end

  defp fail(socket, message, error) do
    socket
    |> put_flash(:error, "#{message}. #{review_error(error)}")
    |> reload_review_desk()
  end

  defp reload_review_desk(%{assigns: %{targeted_mapping_id: nil}} = socket),
    do: load_review_desk(socket)

  defp reload_review_desk(%{assigns: %{targeted_mapping_id: mapping_id}} = socket) do
    case Core.get_listing_mapping_for_review(mapping_id, actor: socket.assigns.current_admin) do
      {:ok, %ListingProductMapping{} = mapping} -> load_review_desk(socket, [mapping])
      {:ok, nil} -> unavailable_mapping_redirect(socket)
      {:error, error} -> raise error
    end
  end

  defp unavailable_mapping_redirect(socket) do
    socket
    |> put_flash(:error, "That listing mapping is no longer available for review.")
    |> redirect(to: ~p"/admin/review")
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

  defp format_evidence(evidence) when is_map(evidence) do
    evidence
    |> project_evidence()
    |> Jason.encode!()
    |> String.slice(0, 2_000)
  rescue
    _ -> "Structured evidence unavailable"
  end

  defp format_evidence(_), do: "Structured evidence unavailable"

  defp project_evidence(evidence) do
    %{}
    |> put_evidence_list(evidence, "anchor_card_printing_ids", &safe_uuid?/1)
    |> put_evidence_list(evidence, "anchor_cardmarket_product_ids", &positive_integer?/1)
    |> put_evidence_scalar(evidence, "set_expansion_degree")
    |> put_evidence_scalar(evidence, "expansion_set_degree")
  end

  @max_evidence_list_length 50

  defp put_evidence_list(acc, evidence, key, validator) do
    case evidence_value(evidence, key) do
      value when is_list(value) ->
        {values, discarded} =
          value
          |> Enum.filter(validator)
          |> Enum.split(@max_evidence_list_length)

        acc = Map.put(acc, key, values)

        if discarded == [] do
          acc
        else
          Map.put(acc, "#{key}_truncated_count", length(discarded))
        end

      _ ->
        acc
    end
  end

  defp put_evidence_scalar(acc, evidence, key) do
    case evidence_value(evidence, key) do
      value when is_integer(value) and value >= 0 and value <= 1_000_000 ->
        Map.put(acc, key, value)

      _ ->
        acc
    end
  end

  defp evidence_value(evidence, key), do: Map.get(evidence, key, Map.get(evidence, atom_key(key)))

  defp atom_key("anchor_card_printing_ids"), do: :anchor_card_printing_ids
  defp atom_key("anchor_cardmarket_product_ids"), do: :anchor_cardmarket_product_ids
  defp atom_key("set_expansion_degree"), do: :set_expansion_degree
  defp atom_key("expansion_set_degree"), do: :expansion_set_degree

  defp safe_uuid?(value) when is_binary(value) do
    match?({:ok, _}, Ecto.UUID.cast(value))
  end

  defp safe_uuid?(_value), do: false

  defp positive_integer?(value), do: is_integer(value) and value > 0 and value <= 1_000_000_000
end
