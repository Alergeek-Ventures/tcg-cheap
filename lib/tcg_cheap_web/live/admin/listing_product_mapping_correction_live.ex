defmodule TcgCheapWeb.Admin.ListingProductMappingCorrectionLive do
  @moduledoc "Authenticated confirmation page for reopening terminal listing mappings."

  use TcgCheapWeb, :live_view

  alias TcgCheap.Catalogue.ListingProductMapping
  alias TcgCheap.Core

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    actor = socket.assigns.current_user

    case load_mapping(id, actor) do
      {:ok, mapping} ->
        {:ok,
         socket
         |> assign(:page_title, "Correct listing mapping")
         |> assign(:mapping, mapping)
         |> assign(:form, to_form(%{}, as: :mapping_correction))}

      :error ->
        {:ok,
         socket
         |> put_flash(:error, "That mapping is no longer available for correction.")
         |> push_navigate(to: ~p"/admin/catalogue/mappings")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin
      flash={@flash}
      current_url={~p"/admin/catalogue/mappings"}
      current_admin={@current_admin}
    >
      <div id="admin-mapping-correction" class="admin-world">
        <main class="admin-main">
          <div class="admin-container">
            <section class="admin-intro" aria-labelledby="admin-mapping-correction-title">
              <div>
                <h1 id="admin-mapping-correction-title">Correct listing mapping</h1>
                <p>Reopen this mapping and send it back to the review queue.</p>
              </div>
            </section>

            <section
              id="mapping-correction-summary"
              class="admin-queue"
              aria-labelledby="mapping-correction-summary-title"
            >
              <div class="admin-section-rule">
                <h2 id="mapping-correction-summary-title">Current terminal decision</h2>
                <span>{@mapping.status}</span>
              </div>
              <dl class="admin-ledger">
                <div>
                  <dt>Retailer listing</dt>
                  <dd>
                    <.link
                      id="mapping-correction-listing-link"
                      navigate={~p"/admin/catalogue/listings/#{@mapping.retailer_listing.id}/show"}
                    >
                      {@mapping.retailer_listing.source_title}
                    </.link>
                  </dd>
                </div>
                <div :if={@mapping.confirmed_product}>
                  <dt>Confirmed product</dt>
                  <dd>
                    <.link
                      id="mapping-correction-product-link"
                      navigate={~p"/admin/catalogue/products/#{@mapping.confirmed_product.id}/show"}
                    >
                      {@mapping.confirmed_product.name}
                    </.link>
                  </dd>
                </div>
                <div>
                  <dt>Decision reason</dt><dd>{@mapping.reason || "Confirmed mapping"}</dd>
                </div>
                <div>
                  <dt>Decision time</dt><dd>{@mapping.approved_at || @mapping.rejected_at}</dd>
                </div>
              </dl>
              <p id="mapping-correction-history-note" class="admin-disclosure">
                Prior decisions remain available in mapping history after this correction.
              </p>
            </section>

            <.form
              for={@form}
              id="mapping-correction-form"
              class="mapping-correction-form"
              phx-submit="confirm_reopen"
            >
              <.input
                field={@form[:reason]}
                id="mapping-correction-reason"
                type="textarea"
                label="Correction reason"
                required
                maxlength="2000"
              />
              <div class="admin-decision-row">
                <.link
                  id="mapping-correction-cancel"
                  class="inline-flex min-h-11 items-center px-3"
                  navigate={~p"/admin/catalogue/mappings/#{@mapping.id}/show"}
                >
                  Cancel
                </.link>
                <button id="mapping-correction-submit" type="submit">Confirm reopen</button>
              </div>
            </.form>
          </div>
        </main>
      </div>
    </Layouts.admin>
    """
  end

  @impl true
  def handle_event("confirm_reopen", %{"mapping_correction" => %{"reason" => reason}}, socket) do
    mapping = socket.assigns.mapping
    reason = if is_binary(reason), do: String.trim(reason), else: ""

    if reason == "" do
      {:noreply,
       socket
       |> assign(
         :form,
         to_form(%{"reason" => reason},
           as: :mapping_correction,
           errors: [reason: {"Reason is required.", []}]
         )
       )
       |> put_flash(:error, "Enter a reason before reopening the mapping.")}
    else
      reopen_mapping(socket, mapping, reason)
    end
  end

  def handle_event("confirm_reopen", _params, socket) do
    {:noreply, put_flash(socket, :error, "Enter a reason before reopening the mapping.")}
  end

  defp reopen_mapping(socket, mapping, reason) do
    case Core.reopen_listing_mapping(
           mapping,
           %{expected_updated_at: mapping.updated_at, reason: reason},
           actor: socket.assigns.current_user
         ) do
      {:ok, _mapping} ->
        {:noreply,
         socket
         |> put_flash(:info, "Mapping reopened for review.")
         |> push_navigate(to: ~p"/admin/review#listing-mappings")}

      _error ->
        {:noreply,
         put_flash(socket, :error, "The mapping could not be reopened. Refresh and try again.")}
    end
  end

  defp load_mapping(id, actor) do
    with {:ok, uuid} <- Ecto.UUID.cast(id),
         {:ok, mapping} <-
           Ash.get(ListingProductMapping, uuid, action: :admin_catalogue, actor: actor),
         true <- mapping.status in ["matched", "rejected"],
         true <- Ash.can?({mapping, :reopen}, actor),
         {:ok, mapping} <-
           Ash.load(mapping, [:retailer_listing, :candidate_product, :confirmed_product],
             actor: actor
           ) do
      {:ok, mapping}
    else
      _ -> :error
    end
  rescue
    _ -> :error
  end
end
