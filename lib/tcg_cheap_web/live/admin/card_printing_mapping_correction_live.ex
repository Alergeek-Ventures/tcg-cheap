defmodule TcgCheapWeb.Admin.CardPrintingMappingCorrectionLive do
  @moduledoc "Authenticated, safe Cardmarket mapping correction workflow."

  use TcgCheapWeb, :live_view

  alias TcgCheap.Catalogue.CardPrinting
  alias TcgCheap.Core
  alias TcgCheap.Pricing.Singles.ValuationAcquisition

  require Ash.Query

  @max_product_id 9_223_372_036_854_775_807

  @fields [
    :id,
    :tcgdex_id,
    :name,
    :set_name,
    :collector_number,
    :mapping_status,
    :cardmarket_product_id,
    :mapping_authority,
    :mapping_review_reason,
    :mapping_updated_at,
    :updated_at
  ]

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    actor = socket.assigns.current_user

    case load_card_printing(id, actor) do
      {:ok, card} ->
        {:ok,
         socket
         |> assign(:page_title, "Correct card mapping")
         |> assign(:card, card)
         |> assign(:form, correction_form(correction_values(card)))
         |> assign(:reopen_form, reopen_form(%{}))}

      :error ->
        {:ok,
         socket
         |> put_flash(:error, "That card is no longer available for correction.")
         |> push_navigate(to: ~p"/admin/catalogue/cards")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin
      flash={@flash}
      current_url={~p"/admin/catalogue/cards"}
      current_admin={@current_admin}
    >
      <div
        id="card-printing-mapping-correction"
        class={["mx-auto w-full max-w-6xl p-4 sm:p-6"]}
      >
        <header class={["mb-6 flex flex-wrap items-start justify-between gap-4"]}>
          <div class={["min-w-0"]}>
            <h1
              id="card-printing-mapping-correction-title"
              class={["text-2xl font-bold sm:text-3xl"]}
            >
              Correct mapping
            </h1>
            <p class={["mt-2 max-w-3xl text-sm leading-6"]}>
              Verify the exact printing before replacing its Cardmarket product identity.
            </p>
          </div>
          <.link
            id="card-printing-mapping-correction-back"
            navigate={~p"/admin/catalogue/cards"}
            class={["btn btn-outline min-h-11"]}
          >Back to cards</.link>
        </header>

        <section
          id="card-printing-mapping-summary"
          class={["border border-base-content bg-base-100 p-4 sm:p-6"]}
          aria-labelledby="card-printing-mapping-summary-title"
        >
          <h2 id="card-printing-mapping-summary-title" class={["text-lg font-semibold"]}>
            Card identity and current mapping
          </h2>
          <dl class={["mt-4 grid grid-cols-1 gap-x-6 text-sm sm:grid-cols-2 lg:grid-cols-3"]}>
            <div class={["min-w-0 border-t border-base-content/25 py-3"]}>
              <dt class={["text-base-content/65"]}>TCGdex ID</dt>
              <dd id="card-printing-tcgdex-id" class={["mt-1 break-words"]}>
                {@card.tcgdex_id}
              </dd>
            </div>
            <div class={["min-w-0 border-t border-base-content/25 py-3"]}>
              <dt class={["text-base-content/65"]}>Name</dt>
              <dd id="card-printing-name" class={["mt-1 break-words"]}>{@card.name}</dd>
            </div>
            <div class={["min-w-0 border-t border-base-content/25 py-3"]}>
              <dt class={["text-base-content/65"]}>Set / collector</dt>
              <dd id="card-printing-set-collector" class={["mt-1 break-words"]}>
                {@card.set_name} / {@card.collector_number}
              </dd>
            </div>
            <div class={["min-w-0 border-t border-base-content/25 py-3"]}>
              <dt class={["text-base-content/65"]}>Mapping status</dt>
              <dd id="card-printing-mapping-status" class={["mt-1 break-words"]}>
                {@card.mapping_status}
              </dd>
            </div>
            <div class={["min-w-0 border-t border-base-content/25 py-3"]}>
              <dt class={["text-base-content/65"]}>Cardmarket ID</dt>
              <dd id="card-printing-cardmarket-id" class={["mt-1 break-words"]}>
                {@card.cardmarket_product_id || "None"}
              </dd>
            </div>
            <div class={["min-w-0 border-t border-base-content/25 py-3"]}>
              <dt class={["text-base-content/65"]}>Mapping authority</dt>
              <dd id="card-printing-mapping-authority" class={["mt-1 break-words"]}>
                {@card.mapping_authority}
              </dd>
            </div>
            <div class={["min-w-0 border-t border-base-content/25 py-3"]}>
              <dt class={["text-base-content/65"]}>Review reason</dt>
              <dd id="card-printing-review-reason" class={["mt-1 break-words"]}>
                {@card.mapping_review_reason || "None"}
              </dd>
            </div>
            <div class={["min-w-0 border-t border-base-content/25 py-3"]}>
              <dt class={["text-base-content/65"]}>Review / mapping time</dt>
              <dd id="card-printing-mapping-time" class={["mt-1 break-words"]}>
                {@card.mapping_updated_at || "None"}
              </dd>
            </div>
          </dl>
          <p
            id="card-printing-mapping-warning"
            class={["mt-4 border border-warning bg-warning/15 p-3 text-sm leading-6"]}
          >
            Saving a change archives every current valuation for this printing. A new aggregate can
            become current only when its Cardmarket ID matches this mapping.
          </p>
        </section>

        <div class={["mt-6 grid grid-cols-1 gap-6 lg:grid-cols-2"]}>
          <section
            id="card-printing-correction-section"
            class={["border border-base-content bg-base-100 p-4 sm:p-6"]}
            aria-labelledby="card-printing-correction-title"
          >
            <h2 id="card-printing-correction-title" class={["text-lg font-semibold"]}>
              Set corrected mapping
            </h2>
            <p class={["mt-1 text-sm leading-6 text-base-content/70"]}>
              Record the verified product ID and why it supersedes the current evidence.
            </p>
            <.form
              for={@form}
              id="card-printing-correction-form"
              class={["mt-4 grid gap-4"]}
              phx-submit="correct_mapping"
            >
              <.input
                field={@form[:cardmarket_product_id]}
                id="card-printing-correction-cardmarket-id"
                type="text"
                inputmode="numeric"
                pattern="[0-9]+"
                maxlength="19"
                label="Cardmarket product ID"
                required
              />
              <.input
                field={@form[:reason]}
                id="card-printing-correction-reason"
                type="textarea"
                label="Correction reason"
                maxlength="2000"
                required
              />
              <button
                id="card-printing-correction-submit"
                type="submit"
                class={["btn btn-primary min-h-11 w-fit"]}
                phx-disable-with="Saving correction…"
              >Save correction</button>
            </.form>
          </section>

          <section
            :if={@card.mapping_status in ["matched", "unmatched"]}
            id="card-printing-reopen-section"
            class={["border border-base-content bg-base-100 p-4 sm:p-6"]}
            aria-labelledby="card-printing-reopen-title"
          >
            <h2 id="card-printing-reopen-title" class={["text-lg font-semibold"]}>
              Reopen for review
            </h2>
            <p class={["mt-1 text-sm leading-6 text-base-content/70"]}>
              Remove the active product ID and retain a reason for the next review.
            </p>
            <.form
              for={@reopen_form}
              id="card-printing-reopen-form"
              class={["mt-4 grid gap-4"]}
              phx-submit="reopen_mapping"
            >
              <.input
                field={@reopen_form[:reason]}
                id="card-printing-reopen-reason"
                type="textarea"
                label="Review reason"
                maxlength="2000"
                required
              />
              <button
                id="card-printing-reopen-submit"
                type="submit"
                class={["btn btn-outline min-h-11 w-fit"]}
                phx-disable-with="Reopening mapping…"
              >Reopen mapping</button>
            </.form>
          </section>
        </div>
      </div>
    </Layouts.admin>
    """
  end

  @impl true
  def handle_event("correct_mapping", %{"card_printing_correction" => params}, socket) do
    params = normalize_params(params)

    case {parse_product_id(params["cardmarket_product_id"]), params["reason"]} do
      {{:ok, product_id}, reason} when reason != "" ->
        submit_correction(socket, params, product_id)

      {{:ok, _product_id}, _reason} ->
        {:noreply,
         correction_error(
           socket,
           params,
           :reason,
           "Correction reason is required.",
           "Enter why this mapping should change."
         )}

      {:error, _reason} ->
        {:noreply,
         correction_error(
           socket,
           params,
           :cardmarket_product_id,
           "Enter a positive Cardmarket product ID.",
           "Check the Cardmarket product ID and try again."
         )}
    end
  end

  def handle_event("correct_mapping", _params, socket),
    do:
      {:noreply,
       correction_error(
         socket,
         %{},
         :cardmarket_product_id,
         "Enter a positive Cardmarket product ID.",
         "Check the Cardmarket product ID and try again."
       )}

  def handle_event("reopen_mapping", %{"card_printing_reopen" => params}, socket) do
    params = normalize_params(params)
    card = socket.assigns.card

    if card.mapping_status in ["matched", "unmatched"] and params["reason"] != "" do
      case Core.reopen_cardmarket_mapping(
             card,
             %{expected_updated_at: card.updated_at, reason: params["reason"]},
             actor: socket.assigns.current_user
           ) do
        {:ok, updated_card} ->
          ValuationAcquisition.notify_mapping_changed(updated_card)

          {:noreply,
           socket
           |> put_flash(:info, "Cardmarket mapping reopened for review.")
           |> push_navigate(to: ~p"/admin/catalogue/cards/#{card.id}/show")}

        _ ->
          {:noreply,
           reopen_error(
             socket,
             params,
             "The mapping changed or could not be reopened.",
             "Refresh the card before trying again."
           )}
      end
    else
      {:noreply,
       reopen_error(
         socket,
         params,
         "Review reason is required.",
         "Enter why this mapping needs another review."
       )}
    end
  end

  def handle_event("reopen_mapping", _params, socket),
    do:
      {:noreply,
       reopen_error(
         socket,
         %{},
         "Review reason is required.",
         "Enter why this mapping needs another review."
       )}

  defp load_card_printing(id, actor) do
    with {:ok, uuid} <- Ecto.UUID.cast(id),
         query <-
           CardPrinting
           |> Ash.Query.for_read(:admin_catalogue, %{}, actor: actor)
           |> Ash.Query.filter(id: uuid)
           |> Ash.Query.select(@fields),
         {:ok, [card]} <- Ash.read(query, actor: actor) do
      {:ok, card}
    else
      _ -> :error
    end
  rescue
    _ -> :error
  end

  defp normalize_params(params) do
    %{"cardmarket_product_id" => value, "reason" => reason} =
      Map.merge(%{"cardmarket_product_id" => "", "reason" => ""}, params)

    %{
      "cardmarket_product_id" => if(is_binary(value), do: String.trim(value), else: ""),
      "reason" => if(is_binary(reason), do: String.trim(reason), else: "")
    }
  end

  defp parse_product_id(value) when is_binary(value) do
    if Regex.match?(~r/^[0-9]+$/, value) do
      case Integer.parse(value) do
        {id, ""} when id in 1..@max_product_id -> {:ok, id}
        _ -> :error
      end
    else
      :error
    end
  end

  defp parse_product_id(_), do: :error

  defp submit_correction(socket, params, product_id) do
    card = socket.assigns.card

    case Core.correct_cardmarket_mapping(
           card,
           %{
             expected_updated_at: card.updated_at,
             cardmarket_product_id: product_id,
             reason: params["reason"]
           },
           actor: socket.assigns.current_user
         ) do
      {:ok, updated_card} ->
        ValuationAcquisition.notify_mapping_changed(updated_card)

        {:noreply,
         socket
         |> put_flash(:info, "Cardmarket mapping corrected.")
         |> push_navigate(to: ~p"/admin/catalogue/cards/#{card.id}/show")}

      _error ->
        {:noreply,
         correction_error(
           socket,
           params,
           :reason,
           "The mapping changed or could not be corrected.",
           "Refresh the card before trying again."
         )}
    end
  end

  defp correction_values(%{cardmarket_product_id: nil}),
    do: %{"cardmarket_product_id" => "", "reason" => ""}

  defp correction_values(card),
    do: %{
      "cardmarket_product_id" => Integer.to_string(card.cardmarket_product_id),
      "reason" => ""
    }

  defp correction_form(values, errors \\ []),
    do: to_form(values, as: :card_printing_correction, errors: errors)

  defp reopen_form(values, errors \\ []),
    do: to_form(values, as: :card_printing_reopen, errors: errors)

  defp correction_error(socket, params, field, message, flash_message) do
    socket
    |> assign(:form, correction_form(params, [{field, {message, []}}]))
    |> put_flash(:error, flash_message)
  end

  defp reopen_error(socket, params, message, flash_message) do
    socket
    |> assign(:reopen_form, reopen_form(params, reason: {message, []}))
    |> put_flash(:error, flash_message)
  end
end
