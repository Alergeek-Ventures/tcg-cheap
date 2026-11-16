defmodule TcgCheapWeb.SocialImage.Single do
  @moduledoc """
  A card's preview: the scan on the left, the name and the answer beside it.
  """

  use Gettext, backend: TcgCheapWeb.Gettext

  alias TcgCheap.Sealed.Guide
  alias TcgCheapWeb.{Format, OfferComponents, SocialImage, VerdictComponents}
  alias TcgCheapWeb.SocialImage.{Answer, Picture, Text}

  # Versions hash what a preview draws, as drawn: a price to the złoty or
  # grosz it shows, not the day's exact conversion, so a preview is drawn
  # again only when it would look different.

  @doc "A version of what the preview shows (`TcgCheap.Sealed.CardGuide.page/3`)."
  @spec version(map()) :: String.t()
  def version(page) do
    %{cheapest: cheapest, verdict: verdict} = answer_row(page)

    price =
      if cheapest,
        do: {Format.price(cheapest.price), cheapest.shop},
        else: (value = cardmarket_pln(page)) && Format.whole_price(value)

    SocialImage.version(
      {page.card.name, page.card.number, page.expansion_name, page.image,
       VerdictComponents.single_verdict_status(verdict), price}
    )
  end

  @doc """
  The preview from its guide page (`TcgCheap.Sealed.CardGuide.page/3`).
  `{:partial, jpeg}` is a preview drawn without a scan that could not be
  fetched.
  """
  @spec draw(map()) :: SocialImage.result()
  def draw(page) do
    margin = SocialImage.margin()

    SocialImage.with_slot(fn ->
      scan = Picture.scan(page.image)
      scan_width = Picture.scan_width()

      {column, art} =
        case scan do
          {:ok, png} -> {72 + scan_width + 56, Picture.draw_scan(png, 72, margin, scan_width, 0)}
          _none -> {margin + 16, nil}
        end

      width = SocialImage.width() - margin - column
      {answer, answer_height} = answer(page, column, width)

      logo_height = 48
      title_top = margin + logo_height + 40
      facts = Text.wrap("#{page.card.number} · #{page.expansion_name}", 22, :mono, width, 1)
      room = SocialImage.height() - margin - answer_height - 32 - title_top - 44

      {size, title} =
        Text.fit_title(Text.normalize(page.card.name), width, room, 2, [
          96,
          84 | Text.title_sizes()
        ])

      line = round(size * 0.96)

      preview =
        SocialImage.render([
          SocialImage.background(),
          art,
          SocialImage.logo(column, margin, logo_height),
          Text.lines(title, column, title_top, size, line, :display, :ink),
          Text.lines(facts, column, title_top + length(title) * line + 14, 22, 30, :mono, :muted),
          answer
        ])

      Picture.partial(preview, [scan])
    end)
  end

  # The normal print's answer, or the first print a shop has in stock.
  defp answer_row(page),
    do: Enum.find(page.answers, & &1.cheapest) || hd(page.answers)

  defp answer(page, x, width) do
    %{cheapest: cheapest, verdict: verdict} = answer_row(page)
    status = VerdictComponents.single_verdict_status(verdict)
    # Only a judged price or a missing one has a badge; "too few shops" means
    # nothing on a card.
    badge = if status in [:good, :normal, :expensive, :out_of_stock], do: %{status: status}

    {price, line} =
      case {cheapest, cardmarket_pln(page)} do
        {%{price: price}, _cardmarket} ->
          {{Format.price(price), 104, :ink},
           gettext("najtaniej teraz w %{shop}", shop: OfferComponents.priced_shop_name(cheapest))}

        {nil, %Decimal{} = value} ->
          {{Format.whole_price(value), 68, :muted}, gettext("cena na Cardmarket")}

        {nil, nil} ->
          {nil, gettext("Teraz żaden sklep nie ma tej karty na stanie.")}
      end

    Answer.stack(badge, price, line, [], x, width)
  end

  defp cardmarket_pln(%{price: %{trend: trend}, rate: rate}), do: Guide.to_pln(trend, rate)
  defp cardmarket_pln(_page), do: nil
end
