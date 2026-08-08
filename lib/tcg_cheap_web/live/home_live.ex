defmodule TcgCheapWeb.HomeLive do
  use TcgCheapWeb, :live_view

  alias TcgCheap.Catalogue.CardImage
  alias TcgCheap.Catalogue.SearchText
  alias TcgCheap.Pricing.Singles.Freshness

  @max_autocomplete_options 10

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       page_title: "Compare Pokémon prices",
       mode: :singles,
       search_form: to_form(%{"query" => ""}, as: :search),
       search_status: :idle,
       result_count: 0,
       search_query: "",
       autocomplete_options: [],
       active_option_id: nil
     )
     |> stream_configure(:card_results, dom_id: fn result -> "card-option-#{result.id}" end)
     |> stream(:card_results, [])}
  end

  @impl true
  def handle_event("search", _params, %{assigns: %{mode: :sealed}} = socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("search", %{"search" => %{"query" => query}}, socket) do
    normalized = SearchText.normalize(query)
    socket = assign(socket, :search_query, normalized)

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
     |> assign(
       search_status: :sealed_unavailable,
       result_count: 0,
       search_query: "",
       autocomplete_options: [],
       active_option_id: nil
     )
     |> stream(:card_results, [], reset: true)}
  end

  def handle_event("switch_mode", %{"mode" => "singles"}, socket) do
    {:noreply,
     socket
     |> assign(mode: :singles, search_form: to_form(%{"query" => ""}, as: :search))
     |> assign(
       search_status: :idle,
       result_count: 0,
       search_query: "",
       autocomplete_options: [],
       active_option_id: nil
     )
     |> stream(:card_results, [], reset: true)}
  end

  def handle_event("autocomplete_key", %{"key" => key}, socket)
      when key in ["ArrowDown", "ArrowUp"] do
    move_active_option(socket, key)
  end

  def handle_event("autocomplete_key", %{"key" => "Enter"}, socket) do
    case Enum.find(
           socket.assigns.autocomplete_options,
           &(&1.dom_id == socket.assigns.active_option_id)
         ) do
      %{tcgdex_id: tcgdex_id} -> {:noreply, push_navigate(socket, to: ~p"/cards/#{tcgdex_id}")}
      nil -> {:noreply, socket}
    end
  end

  def handle_event("autocomplete_key", %{"key" => "Escape"}, socket) do
    if socket.assigns.autocomplete_options == [] do
      {:noreply, socket}
    else
      clear_results(socket, :idle)
    end
  end

  def handle_event("autocomplete_key", _params, socket), do: {:noreply, socket}

  def handle_event("select_option", %{"tcgdex-id" => tcgdex_id}, socket) do
    case Enum.find(socket.assigns.autocomplete_options, &(&1.tcgdex_id == tcgdex_id)) do
      %{tcgdex_id: ^tcgdex_id} ->
        {:noreply, push_navigate(socket, to: ~p"/cards/#{tcgdex_id}")}

      nil ->
        {:noreply, socket}
    end
  end

  def handle_event("select_option", _params, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="decision-world">
        <header id="decision-header" class="decision-header">
          <.link id="decision-wordmark" navigate={~p"/"}>TCG CHEAP</.link>
        </header>

        <main id="decision-main" class="decision-main">
          <div class="decision-container">
            <section class="decision-intro" aria-labelledby="decision-title">
              <h1 id="decision-title">Compare Pokémon prices</h1>
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
                <h2 id="search-title">Find a card</h2>
                <.form for={@search_form} id="card-search-form">
                  <label for="card-search-query" class="sr-only">Search for a card</label>
                  <div class="search-field-wrap">
                    <.input
                      field={@search_form[:query]}
                      type="search"
                      id="card-search-query"
                      name="search[query]"
                      autocomplete="off"
                      maxlength="100"
                      phx-hook="CardAutocomplete"
                      role="combobox"
                      aria-autocomplete="list"
                      aria-controls="card-search-results"
                      aria-expanded={to_string(@autocomplete_options != [])}
                      aria-activedescendant={active_option_dom_id(@active_option_id)}
                      placeholder="Search for a card"
                    />
                  </div>
                </.form>
              </section>

              <section class="decision-results" aria-label="Search results">
                <p id="card-search-summary" class="sr-only" aria-live="polite">
                  {summary_text(@search_status, @result_count, @search_query)}
                </p>

                <div
                  id="card-search-results"
                  phx-update="stream"
                  class="evidence-slips"
                  role="listbox"
                  aria-label="Card search results"
                >
                  <div
                    :for={{stream_id, result} <- @streams.card_results}
                    id={stream_id}
                    class={["evidence-slot", @active_option_id == stream_id && "active-option"]}
                    role="option"
                    aria-selected={to_string(@active_option_id == stream_id)}
                    aria-labelledby={option_labelledby(result)}
                    phx-click="select_option"
                    phx-value-tcgdex-id={result.tcgdex_id}
                    tabindex="-1"
                  >
                    <article
                      id={"card-search-result-#{result.id}"}
                      class="evidence-slip"
                      aria-labelledby={"card-search-name-#{result.id} card-search-set-#{result.id}"}
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
                            aria-label="No image is available for this card."
                          >
                            <svg viewBox="0 0 72 96" aria-hidden="true"><path d="M12 4h38l10 10v78H12zM50 4v12h10M20 28h32M20 38h24M20 70h32M20 78h18" /></svg>
                          </div>
                        <% end %>
                      </div>
                      <div class="evidence-copy">
                        <p id={"card-search-name-#{result.id}"} class="evidence-name">
                          {result.name}
                        </p>
                        <p id={"card-search-set-#{result.id}"} class="evidence-set">
                          {result.set_name} · #{result.collector_number}
                        </p>
                        <div
                          :if={rarity_present?(result.rarity)}
                          class="evidence-tags"
                          aria-label="Rarity"
                        >
                          <span
                            :if={result.rarity}
                            class="evidence-tag"
                            id={"card-rarity-#{result.id}"}
                          >{result.rarity}</span>
                        </div>
                        <div class="estimate-cell">
                          <strong id={"card-estimate-#{result.id}"}>{estimate_display(
                            Map.get(result, :tcgdex_cardmarket_v1_current_valuation)
                          )}</strong>
                          <span
                            :if={Map.get(result, :tcgdex_cardmarket_v1_current_valuation)}
                            id={"card-freshness-#{result.id}"}
                          >{freshness_text(Map.get(result, :tcgdex_cardmarket_v1_current_valuation))}</span>
                        </div>
                        <span
                          id={"card-select-action-#{result.id}"}
                          class="detail-action"
                        >View price</span>
                      </div>
                    </article>
                  </div>
                </div>

                <div :if={@search_status == :short} id="card-search-short" class="state-note">
                  Type at least 2 characters.
                </div>
                <div :if={@search_status == :empty} id="card-search-empty" class="state-note">
                  No cards found.
                </div>
                <div
                  :if={@search_status == :error}
                  id="card-search-error"
                  class="state-note state-error"
                >
                  Search is unavailable. Try again.
                </div>
                <div :if={@search_status == :invalid} id="card-search-invalid" class="state-note">
                  Search is too long. Use 100 characters or fewer.
                </div>

                <p :if={@search_status == :results} class="estimate-note">
                  Estimates only · Shipping not included.
                </p>
                <details :if={@search_status == :results} id="price-details" class="price-details">
                  <summary>How prices work</summary>
                  <div id="price-methodology" class="price-methodology">
                    <p>
                      <strong>Methodology:</strong>
                      aggregate Cardmarket estimate from TCGdex under <code>tcgdex_cardmarket_v1</code>.
                      Seller identity and seller/offer count are unavailable from the active aggregate;
                      language, condition, finish exactness, and Poland shipping are not verified; shipping
                      is not calculated.
                    </p>
                  </div>
                  <aside id="price-disclaimer" class="price-disclaimer" aria-label="Price disclaimer">
                    TCG Cheap is unofficial and not affiliated with Pokémon, Nintendo, TCGdex,
                    Cardmarket, or listed companies. This estimate is not guaranteed resale value
                    or investment advice.
                  </aside>
                </details>
              </section>
            <% else %>
              <section
                id="sealed-unavailable"
                class="decision-search unavailable-note"
                aria-labelledby="sealed-unavailable-title"
              >
                <h2 id="sealed-unavailable-title">
                  Sealed price comparison isn't ready yet.
                </h2>
                <p>
                  Switch back to Singles to compare a card price.
                </p>
              </section>
            <% end %>
          </div>
        </main>
      </div>
    </Layouts.app>
    """
  end

  defp estimate_display(nil), do: "Price unavailable"
  defp estimate_display(%{value_eur: value}), do: "€" <> format_eur(value)
  defp estimate_display(_), do: "Price unavailable"

  defp freshness_text(valuation) do
    now = DateTime.utc_now()
    age = max(DateTime.diff(now, valuation.fetched_at, :day), 0)

    updated =
      case age do
        0 -> "Updated today"
        1 -> "Updated yesterday"
        days -> "Updated #{days} days ago"
      end

    if Freshness.status(valuation, now) == :stale,
      do: updated <> " · May be outdated",
      else: updated
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
        options =
          results
          |> Enum.take(@max_autocomplete_options)
          |> Enum.map(fn result ->
            %{dom_id: "card-option-#{result.id}", tcgdex_id: result.tcgdex_id, result: result}
          end)

        {:noreply,
         socket
         |> assign(
           search_status: :results,
           result_count: length(results),
           autocomplete_options: options,
           active_option_id: List.first(options).dom_id
         )
         |> stream(:card_results, Enum.map(options, & &1.result), reset: true)}

      {:ok, []} ->
        {:noreply,
         socket
         |> assign(
           search_status: :empty,
           result_count: 0,
           autocomplete_options: [],
           active_option_id: nil
         )
         |> stream(:card_results, [], reset: true)}

      {:error, _reason} ->
        {:noreply,
         socket
         |> assign(
           search_status: :error,
           result_count: 0,
           autocomplete_options: [],
           active_option_id: nil
         )
         |> stream(:card_results, [], reset: true)}
    end
  end

  defp clear_results(socket, status) do
    {:noreply,
     socket
     |> assign(
       search_status: status,
       result_count: 0,
       autocomplete_options: [],
       active_option_id: nil
     )
     |> stream(:card_results, [], reset: true)}
  end

  defp move_active_option(socket, key) do
    options = socket.assigns.autocomplete_options

    if options == [] do
      {:noreply, socket}
    else
      current_index = Enum.find_index(options, &(&1.dom_id == socket.assigns.active_option_id))
      next_index = next_option_index(key, current_index, length(options))
      selected = Enum.at(options, next_index)
      previous = Enum.find(options, &(&1.dom_id == socket.assigns.active_option_id))

      stream_options =
        [previous, selected]
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq_by(& &1.dom_id)

      {:noreply,
       socket
       |> assign(:active_option_id, selected.dom_id)
       |> stream_insert_options(stream_options)}
    end
  end

  defp stream_insert_options(socket, options) do
    Enum.reduce(options, socket, fn option, socket ->
      stream_insert(socket, :card_results, option.result)
    end)
  end

  defp next_option_index("ArrowDown", nil, _count), do: 0
  defp next_option_index("ArrowUp", nil, count), do: count - 1
  defp next_option_index("ArrowDown", index, count), do: rem(index + 1, count)
  defp next_option_index("ArrowUp", index, count), do: rem(index - 1 + count, count)

  defp active_option_dom_id(nil), do: nil
  defp active_option_dom_id(id), do: id

  defp summary_text(:results, 1, query), do: "1 card for #{query}"
  defp summary_text(:results, count, query), do: "#{count} cards for #{query}"

  defp summary_text(:empty, _count, query), do: "No cards found for #{query}"
  defp summary_text(:error, _count, query), do: "Search unavailable for #{query}"
  defp summary_text(:invalid, _count, query), do: "Search too long for #{query}"
  defp summary_text(:short, _count, query), do: "Type at least 2 characters for #{query}"
  defp summary_text(_status, _count, _query), do: ""

  defp rarity_present?(rarity), do: not is_nil(rarity) and rarity != ""

  defp card_link_label(result),
    do: "#{result.name}, #{result.set_name}, collector number #{result.collector_number}"

  defp option_labelledby(result) do
    [
      "card-search-name-#{result.id}",
      "card-search-set-#{result.id}",
      if(rarity_present?(result.rarity), do: "card-rarity-#{result.id}"),
      "card-estimate-#{result.id}",
      if(Map.get(result, :tcgdex_cardmarket_v1_current_valuation),
        do: "card-freshness-#{result.id}"
      )
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
  end
end
