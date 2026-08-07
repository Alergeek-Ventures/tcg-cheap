defmodule TcgCheapWeb.HomeLive do
  use TcgCheapWeb, :live_view

  alias TcgCheap.Catalogue.SearchText

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       page_title: "Printing Archive",
       search_form: to_form(%{"query" => ""}, as: :search),
       search_status: :idle,
       result_count: 0
     )
     |> stream(:card_results, [])}
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
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="archive-world">
        <header id="archive-header" class="archive-header">
          <.link id="archive-wordmark" navigate={~p"/"} class="archive-wordmark">TCG CHEAP</.link>
          <div class="archive-header-meta">
            <span id="archive-section">PRINTING ARCHIVE</span>
            <span id="archive-mode">LOCAL CATALOGUE</span>
          </div>
        </header>

        <main id="archive-main" class="archive-main">
          <div class="archive-container">
            <section class="archive-intro" aria-labelledby="archive-title">
              <h1 id="archive-title">Find the printing.<br /><span>Keep the name.</span></h1>
              <p class="archive-lede">
                A quiet, local index for telling same-name cards apart at the counter.
              </p>
            </section>

            <section class="search-drawer" aria-labelledby="search-title">
              <h2 id="search-title">Search the archive</h2>
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
                    placeholder="Name, set, number, or TCGdex ID"
                    aria-describedby="search-help"
                  />
                  <span class="phx-change-loading" aria-live="polite">Checking local catalogue…</span>
                </div>
              </.form>
              <p id="search-help" class="search-help">
                Try a card name, set name, collector number, or stable TCGdex identity.
              </p>
            </section>

            <section class="archive-shelf" aria-labelledby="results-title">
              <div class="shelf-heading">
                <h2 id="results-title">Printing wall</h2>
                <p id="card-search-summary" aria-live="polite">
                  {summary_text(@search_status, @result_count)}
                </p>
              </div>

              <div id="card-search-results" phx-update="stream" class="label-wall">
                <div
                  :for={{stream_id, result} <- @streams.card_results}
                  id={stream_id}
                  class="label-slot"
                >
                  <.link
                    navigate={~p"/cards/#{result.tcgdex_id}"}
                    id={"card-detail-link-#{result.id}"}
                    class="printing-label-link"
                    aria-label={card_link_label(result)}
                  >
                    <article
                      id={"card-search-result-#{result.id}"}
                      class="printing-label"
                      aria-labelledby={"card-search-name-#{result.id}"}
                    >
                      <div class="label-art" aria-hidden="true">
                        <svg viewBox="0 0 72 96" role="presentation"><path d="M12 4h38l10 10v78H12zM50 4v12h10M20 28h32M20 38h24M20 70h32M20 78h18" /></svg>
                      </div>
                      <div class="label-copy">
                        <p id={"card-search-name-#{result.id}"} class="label-name">{result.name}</p>
                        <p class="label-set">{result.set_name}</p>
                        <dl class="label-data">
                          <div>
                            <dt>NO.</dt><dd>{result.collector_number}</dd>
                          </div>
                          <div>
                            <dt>TCGDEX</dt><dd>{result.tcgdex_id}</dd>
                          </div>
                        </dl>
                        <div class="label-chips">
                          <span :if={result.rarity} class="archive-chip chip-lilac">{result.rarity}</span>
                          <span :if={result.standard_legal} class="archive-chip chip-sage">STANDARD</span>
                          <span :if={result.expanded_legal} class="archive-chip chip-indigo">EXPANDED</span>
                        </div>
                      </div>
                    </article>
                  </.link>
                </div>
              </div>

              <div :if={@search_status == :idle} id="card-search-idle" class="state-note">
                <strong>Start with an identity.</strong>
                The archive keeps each exact printing on its own label.
              </div>
              <div :if={@search_status == :short} id="card-search-short" class="state-note">
                <strong>Keep going.</strong> Enter at least two characters to open the drawer.
              </div>
              <div :if={@search_status == :empty} id="card-search-empty" class="state-note">
                <strong>No local match.</strong>
                Try a set name, collector number, or the full card name.
              </div>
              <div
                :if={@search_status == :error}
                id="card-search-error"
                class="state-note state-error"
              >
                <strong>Drawer stuck.</strong>
                The local catalogue could not be read. Try again in a moment.
              </div>
              <div :if={@search_status == :invalid} id="card-search-invalid" class="state-note">
                <strong>That query is too long.</strong> Use 100 characters or fewer.
              </div>
            </section>
          </div>
        </main>
      </div>
    </Layouts.app>
    """
  end

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
  defp summary_text(_status, _count), do: "Awaiting a search"

  defp card_link_label(result),
    do: "#{result.name}, #{result.set_name}, collector number #{result.collector_number}"
end
