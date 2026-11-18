defmodule TcgCheapWeb.SocialImage.Single do
  @moduledoc """
  A card's preview: the scan on the left, the name and the answer beside it.
  """

  use Gettext, backend: TcgCheapWeb.Gettext

  alias TcgCheap.Sealed.Market
  alias TcgCheapWeb.{Format, OfferComponents, Region, SocialImage, VerdictComponents}
  alias TcgCheapWeb.SocialImage.{Answer, Picture, Text}

  # Versions hash what a preview draws, as drawn: a price to the unit of the
  # currency it shows, not the day's exact conversion, so a preview is drawn
  # again only when it would look different.

  @doc "A version of what the preview shows (`TcgCheap.Cards.Guide.page/4`)."
  @spec version(map()) :: String.t()
  def version(page) do
    %{cheapest: cheapest, verdict: verdict} = answer_row(page)

    price =
      if cheapest,
        do: {Format.price(cheapest.price), cheapest.shop},
        else: (answer = cardmarket_answer(page)) && elem(answer, 0)

    SocialImage.version(
      {page.card.name, page.card.number, page.expansion_name, page.image,
       VerdictComponents.single_verdict_status(verdict), price}
    )
  end

  @doc """
  The preview from its guide page (`TcgCheap.Cards.Guide.page/4`).
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
      case {cheapest, cardmarket_answer(page)} do
        {%{price: price}, _cardmarket} ->
          {{Format.price(price), 104, :ink},
           gettext("najtaniej teraz w %{shop}", shop: OfferComponents.card_shop_name(cheapest))}

        {nil, {value, label}} ->
          {{value, 68, :muted}, label}

        {nil, nil} ->
          {nil, gettext("Teraz żaden sklep nie ma tej karty na stanie.")}
      end

    # Where no singles shop is at home a shop's price has no delivery in it.
    notes =
      if cheapest && !Region.own_singles?(Region.current()),
        do: [gettext("Cena bez dostawy")],
        else: []

    Answer.stack(badge, price, line, notes, x, width)
  end

  # What the page answers for a card no shop has: where shops sell singles,
  # the Cardmarket price with delivery that is its headline; elsewhere the
  # trend. Both are the amount and its label as the page writes them.
  defp cardmarket_answer(page) do
    if Region.singles?(Region.current()) do
      with %Decimal{} = reference <- answer_row(page).reference do
        {Format.limit_price(reference),
         if(Region.own_singles?(Region.current()),
           do: gettext("na Cardmarket z wysyłką · wszystkie języki i stany kart"),
           else: gettext("trend na Cardmarket, bez wysyłki · wszystkie języki i stany kart")
         )}
      end
    else
      with %Decimal{} = value <- cardmarket_price(page) do
        {Format.whole_price(value), gettext("cena na Cardmarket")}
      end
    end
  end

  # The Cardmarket trend in the page's market currency.
  defp cardmarket_price(%{price: %{trend: trend}, rate: rate, market: market}),
    do: Market.in_market(trend, rate, market)

  defp cardmarket_price(_page), do: nil
end
