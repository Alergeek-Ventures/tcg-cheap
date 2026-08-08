defmodule TcgCheapWeb.HomeLive do
  use TcgCheapWeb, :live_view

  alias TcgCheap.Catalogue.CardImage
  alias TcgCheap.Catalogue.SearchText
  alias TcgCheap.Pricing.Singles.Freshness

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       page_title: "Singles Valuation Bench",
       mode: :singles,
       search_form: to_form(%{"query" => ""}, as: :search),
       search_status: :idle,
       result_count: 0
     )
     |> stream(:card_results, [])}
  end

  @impl true
  def handle_event("search", _params, %{assigns: %{mode: :sealed}} = socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("search", %{"search" => %{"query" => query}}, socket) do
    normalized = SearchText.normalize(query)
    socket = assign(socket, :search_form, to_form(%{"query" => query}, as: :search))

    cond do
      normalized == "" -> clear_results(socket, :idle)
      length(String.graphemes(normalized)) < 2 -> clear_results(socket, :short)
      length(String.graphemes(normalized)) > 100 -> clear_results(socket, :invalid)
      true -> search_locally(socket, normalized)
    end
  end

  @impl true
  def handle_event("switch_mode", %{"mode" => "sealed"}, socket) do
    {:noreply,
     socket
     |> assign(mode: :sealed, search_form: to_form(%{"query" => ""}, as: :search))
     |> assign(search_status: :sealed_unavailable, result_count: 0)
     |> stream(:card_results, [], reset: true)}
  end

  def handle_event("switch_mode", %{"mode" => "singles"}, socket) do
    {:noreply,
     socket
     |> assign(mode: :singles, search_form: to_form(%{"query" => ""}, as: :search))
     |> assign(search_status: :idle, result_count: 0)
     |> stream(:card_results, [], reset: true)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="decision-world">
        <header id="decision-header" class="decision-header">
          <.link id="decision-wordmark" navigate={~p"/"}>TCG CHEAP</.link>
          <span id="decision-context">COUNTER CHECK / LOCAL DATA</span>
        </header>

        <main id="decision-main" class="decision-main">
          <div class="decision-container">
            <section class="decision-intro" aria-labelledby="decision-title">
              <div>
                <h1 id="decision-title">Make the call<br /><span>before the trade.</span></h1>
                <p class="decision-lede">
                  Identify the exact single, then verify the local estimate.
                </p>
              </div>
              <div id="mode-switch" class="mode-switch" role="group" aria-label="Choose product mode">
                <button
                  id="mode-singles"
                  type="button"
                  phx-click="switch_mode"
                  phx-value-mode="singles"
                  aria-pressed={to_string(@mode == :singles)}
                >Singles</button>
                <button
                  id="mode-sealed"
                  type="button"
                  phx-click="switch_mode"
                  phx-value-mode="sealed"
                  aria-pressed={to_string(@mode == :sealed)}
                >Sealed products</button>
              </div>
            </section>

            <%= if @mode == :singles do %>
              <section class="decision-search" aria-labelledby="search-title">
                <h2 id="search-title">Search an exact printing</h2>
                <.form for={@search_form} id="card-search-form" phx-change="search">
                  <label for="card-search-query" class="sr-only">Search by card name, set, collector number, or TCGdex ID</label>
                  <div class="search-field-wrap">
                    <.input
                      field={@search_form[:query]}
                      type="search"
                      id="card-search-query"
                      name="search[query]"
                      autocomplete="off"
                      maxlength="100"
                      phx-debounce="250"
                      placeholder="Card name, set, number, or ID"
                      aria-describedby="search-help"
                    />
                    <span class="phx-change-loading" aria-live="polite">Checking local data…</span>
                  </div>
                </.form>
                <p id="search-help" class="search-help">
                  Local-only search. No provider calls at the counter.
                </p>
              </section>

              <section class="decision-results" aria-labelledby="results-title">
                <div class="results-heading">
                  <h2 id="results-title">Evidence</h2>
                  <p id="card-search-summary" aria-live="polite">
                    {summary_text(@search_status, @result_count)}
                  </p>
                </div>

                <aside id="price-methodology" class="price-methodology" aria-label="Price methodology">
                  <p>
                    <strong>Methodology:</strong>
                    aggregate Cardmarket estimate from TCGdex under <code>tcgdex_cardmarket_v1</code>. Language, condition, seller identity/count,
                    finish-specific exactness, and Poland shipping are not verified; shipping is not
                    calculated.
                  </p>
                </aside>

                <div id="card-search-results" phx-update="stream" class="evidence-slips">
                  <div
                    :for={{stream_id, result} <- @streams.card_results}
                    id={stream_id}
                    class="evidence-slot"
                  >
                    <article
                      id={"card-search-result-#{result.id}"}
                      class="evidence-slip"
                      aria-labelledby={"card-search-name-#{result.id}"}
                    >
                      <div class="evidence-art">
                        <%= if image_url = CardImage.thumbnail_url(result.image_url) do %>
                          <img
                            id={"card-search-image-#{result.id}"}
                            src={image_url}
                            alt={card_link_label(result)}
                            width="245"
                            height="337"
                            loading="lazy"
                            decoding="async"
                            referrerpolicy="no-referrer"
                          />
                        <% else %>
                          <div
                            id={"card-search-image-missing-#{result.id}"}
                            class="card-image-missing"
                            role="img"
                            aria-label="TCGdex has no image for this printing."
                          >
                            <svg viewBox="0 0 72 96" aria-hidden="true"><path d="M12 4h38l10 10v78H12zM50 4v12h10M20 28h32M20 38h24M20 70h32M20 78h18" /></svg>
                          </div>
                        <% end %>
                      </div>
                      <div class="evidence-copy">
                        <p class="evidence-label">EXACT IDENTITY</p>
                        <p id={"card-search-name-#{result.id}"} class="evidence-name">
                          {result.name}
                        </p>
                        <p class="evidence-set">{result.set_name}</p>
                        <div
                          :if={result.rarity || result.standard_legal || result.expanded_legal}
                          class="evidence-tags"
                          aria-label="Printing discriminators"
                        >
                          <span
                            :if={result.rarity}
                            class="evidence-tag"
                            id={"card-rarity-#{result.id}"}
                          >{result.rarity}</span>
                          <span
                            :if={result.standard_legal}
                            class="evidence-tag"
                            id={"card-standard-#{result.id}"}
                          >STANDARD</span>
                          <span
                            :if={result.expanded_legal}
                            class="evidence-tag"
                            id={"card-expanded-#{result.id}"}
                          >EXPANDED</span>
                        </div>
                        <dl class="evidence-data">
                          <div>
                            <dt>NO.</dt><dd>{result.collector_number}</dd>
                          </div><div>
                            <dt>TCGDEX</dt><dd>{result.tcgdex_id}</dd>
                          </div>
                        </dl>
                        <div class="estimate-cell">
                          <span class="evidence-label">LOCAL ESTIMATE</span><strong id={"card-estimate-#{result.id}"}>{estimate_display(
                            Map.get(result, :tcgdex_cardmarket_v1_current_valuation)
                          )}</strong><span id={"card-freshness-#{result.id}"}>{freshness_text(
                            Map.get(result, :tcgdex_cardmarket_v1_current_valuation)
                          )}</span>
                        </div>
                        <.link
                          navigate={~p"/cards/#{result.tcgdex_id}"}
                          id={"card-detail-link-#{result.id}"}
                          class="detail-action"
                          aria-label={"Open value details for #{card_link_label(result)}"}
                        >Open value details <span aria-hidden="true">→</span></.link>
                      </div>
                    </article>
                  </div>
                </div>

                <div :if={@search_status == :idle} id="card-search-idle" class="state-note">
                  <strong>Ready when you are.</strong>
                  Search a name, set, collector number, or stable ID.
                </div>
                <div :if={@search_status == :short} id="card-search-short" class="state-note">
                  <strong>Keep going.</strong> Enter at least two characters.
                </div>
                <div :if={@search_status == :empty} id="card-search-empty" class="state-note">
                  <strong>No local match.</strong>
                  Try the set name, collector number, or full card name.
                </div>
                <div
                  :if={@search_status == :error}
                  id="card-search-error"
                  class="state-note state-error"
                >
                  <strong>Local data unavailable.</strong> Try again in a moment.
                </div>
                <div :if={@search_status == :invalid} id="card-search-invalid" class="state-note">
                  <strong>That query is too long.</strong> Use 100 characters or fewer.
                </div>

                <aside id="price-disclaimer" class="price-disclaimer" aria-label="Price disclaimer">
                  TCG Cheap is unofficial and not affiliated with Pokémon, Nintendo, TCGdex,
                  Cardmarket, or listed companies. This estimate is not guaranteed resale value
                  or investment advice.
                </aside>
              </section>
            <% else %>
              <section
                id="sealed-unavailable"
                class="decision-search unavailable-note"
                aria-labelledby="sealed-unavailable-title"
              >
                <h2 id="sealed-unavailable-title">
                  Sealed products are not in the local catalogue yet.
                </h2>
                <p>
                  Nothing is being searched or estimated here. Switch back to Singles to check a card.
                </p>
              </section>
            <% end %>
          </div>
        </main>
      </div>
    </Layouts.app>
    """
  end

  defp estimate_display(nil), do: "?"
  defp estimate_display(%{value_eur: value}), do: "€" <> format_eur(value)
  defp estimate_display(_), do: "?"

  defp freshness_text(nil), do: "UNPRICED / NO LOCAL ESTIMATE"

  defp freshness_text(valuation) do
    case Freshness.status(valuation, DateTime.utc_now()) do
      :fresh -> "FRESH · within 7 days"
      :stale -> "STALE · older than 7 days"
    end
  end

  defp format_eur(%Decimal{} = value) do
    [whole, fraction] =
      value
      |> Decimal.round(2)
      |> Decimal.to_string(:normal)
      |> String.split(".", parts: 2)
      |> Kernel.++(["0"])
      |> Enum.take(2)

    whole <> "." <> String.pad_trailing(fraction, 2, "0")
  end

  defp format_eur(value) when is_binary(value), do: format_eur(Decimal.new(value))
  defp format_eur(value) when is_integer(value), do: format_eur(Decimal.new(value))

  defp search_locally(socket, query) do
    case TcgCheap.Core.search_card_printings(query) do
      {:ok, results} when is_list(results) and results != [] ->
        {:noreply,
         socket
         |> assign(search_status: :results, result_count: length(results))
         |> stream(:card_results, results, reset: true)}

      {:ok, []} ->
        {:noreply,
         socket
         |> assign(search_status: :empty, result_count: 0)
         |> stream(:card_results, [], reset: true)}

      {:error, _reason} ->
        {:noreply,
         socket
         |> assign(search_status: :error, result_count: 0)
         |> stream(:card_results, [], reset: true)}
    end
  end

  defp clear_results(socket, status) do
    {:noreply,
     socket
     |> assign(search_status: status, result_count: 0)
     |> stream(:card_results, [], reset: true)}
  end

  defp summary_text(:results, count),
    do: "#{count} exact #{if count == 1, do: "printing", else: "printings"}"

  defp summary_text(:empty, _count), do: "0 printings"
  defp summary_text(:error, _count), do: "Catalogue unavailable"
  defp summary_text(:invalid, _count), do: "Query too long"
  defp summary_text(:sealed_unavailable, _count), do: "Not available yet"
  defp summary_text(_status, _count), do: "Awaiting a search"

  defp card_link_label(result),
    do:
      "#{result.name}, #{result.set_name}, collector number #{result.collector_number}, TCGdex ID #{result.tcgdex_id}"
end
