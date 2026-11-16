defmodule TcgCheapWeb.SocialImage.Product do
  @moduledoc """
  A product's card: the same answer as its page, the verdict, the cheapest
  in-stock price and shop, the typical and suggested prices. Its photo comes
  only from our mirrored storage variant, shrunk before it is drawn.
  """

  use Gettext, backend: TcgCheapWeb.Gettext

  alias TcgCheapWeb.{Format, ListingComponents, OfferComponents, SocialImage}
  alias TcgCheapWeb.SocialImage.{Answer, Picture, Text}

  @min_title Text.min_title()

  @doc "A version of what the card shows, for its storage key and URL."
  @spec version(map()) :: String.t()
  def version(%{product: product, verdict: verdict} = page) do
    SocialImage.version(
      {product.name, product.stored_photo_page_url, product.kind, product.set_name,
       product.region, verdict.status,
       verdict.cheapest && {verdict.cheapest.price, verdict.cheapest.shop}, verdict.typical,
       length(verdict.shop_prices), page.past.last_known,
       page.suggested_price && page.suggested_price.price}
    )
  end

  @doc """
  The card from its guide page (`TcgCheap.Sealed.Guide.product/3`).
  `{:partial, jpeg}` is a card drawn without a photo the product has but
  that could not be fetched: worth serving, not worth keeping.
  """
  @spec draw(map()) :: SocialImage.result()
  def draw(%{product: product} = page) do
    margin = SocialImage.margin()
    height = SocialImage.height()

    SocialImage.with_slot(fn ->
      photo = Picture.photo(product.stored_photo_page_url)

      {column, tile} =
        case photo do
          {:ok, png} -> {630, Picture.draw_tile(png, margin, margin, height - 2 * margin)}
          _none -> {margin + 16, nil}
        end

      width = SocialImage.width() - margin - 16 - column
      {answer, answer_height} = answer_block(page, column, width)

      logo_height = 48
      title_top = margin + logo_height + 40
      # The room between the title's top and the answer, less the gap above it.
      room = height - margin - answer_height - 32 - title_top
      max_lines = if tile, do: 3, else: 2
      name = Text.normalize(product.name)

      # The facts line gives way when the name would not fit in one line.
      {facts, room} =
        case ListingComponents.product_meta(product)
             |> Text.normalize()
             |> Text.wrap(22, :mono, width, 1) do
          facts when room - 44 >= @min_title * 0.96 -> {facts, room - 44}
          _facts -> {[], room}
        end

      {size, title} = Text.fit_title(name, width, room, max_lines)
      line = round(size * 0.96)

      card =
        SocialImage.render([
          SocialImage.background(),
          tile,
          SocialImage.logo(column, margin, logo_height),
          Text.lines(title, column, title_top, size, line, :display, :ink),
          Text.lines(facts, column, title_top + length(title) * line + 14, 22, 30, :mono, :muted),
          answer
        ])

      case {card, photo} do
        {{:ok, jpeg}, :error} -> {:partial, jpeg}
        {card, _photo} -> card
      end
    end)
  end

  # The product's verdict, cheapest price and shop, then its typical and
  # suggested prices.
  defp answer_block(page, x, width) do
    %{verdict: verdict, past: past} = page

    {price, shop_line} =
      case {verdict, past} do
        {%{cheapest: %{price: price} = cheapest}, _past} ->
          {{Format.price(price), 104, :ink},
           gettext("najtaniej teraz w %{shop}", shop: OfferComponents.priced_shop_name(cheapest))}

        {_verdict, %{last_known: %{price: price, date: date}}} ->
          {{Format.price(price), 68, :muted},
           gettext("ostatnio najtaniej · %{date}", date: Calendar.strftime(date, "%d.%m.%Y"))}

        _none ->
          {nil, gettext("Teraz żaden sklep nie ma tego produktu na stanie.")}
      end

    notes =
      Enum.filter(
        [
          typical_note(verdict),
          page.suggested_price &&
            gettext("Cena sugerowana (REBEL): %{price}",
              price: Format.price(page.suggested_price.price)
            )
        ],
        &is_binary/1
      )

    Answer.stack(verdict, price, shop_line, notes, x, width)
  end

  # The Cardmarket comparison is already in the badge.
  defp typical_note(%{typical: %Decimal{} = typical, typical_source: :shops} = verdict),
    do:
      gettext("Typowa cena dziś w %{shops}: %{price}",
        shops: Format.in_shops(length(verdict.shop_prices)),
        price: Format.limit_price(typical)
      )

  defp typical_note(_verdict), do: nil
end
