defmodule TcgCheapWeb.SocialImage.Cards do
  @moduledoc """
  The card list's preview from its market figures: the best deal's scan, the
  count in stock and the deal beside it.
  """

  use Gettext, backend: TcgCheapWeb.Gettext

  alias TcgCheap.Sealed.Shops
  alias TcgCheapWeb.{Format, SocialImage}
  alias TcgCheapWeb.SocialImage.{Figures, Picture}

  @doc "A version of what the preview shows (`TcgCheap.Sealed.Guide.singles_market/0`)."
  @spec version(map()) :: String.t()
  def version(market) do
    deal = market.deal

    SocialImage.version(
      {market.in_stock, market.shops,
       deal && {deal.card.name, Format.price(deal.price), deal.shop, deal.image}}
    )
  end

  @doc "The preview from `TcgCheap.Sealed.Guide.singles_market/0`."
  @spec draw(map()) :: SocialImage.result()
  def draw(market) do
    SocialImage.with_slot(fn ->
      deal = market.deal
      scan = Picture.scan(deal && deal.image)
      title = gettext("Ceny kart Pokémon")

      figures =
        Enum.filter(
          [
            %{
              text:
                gettext("%{cards} na stanie",
                  cards: Format.cards(market.in_stock)
                ),
              size: 64,
              caption:
                gettext("w %{shops}",
                  shops: Format.in_shops(market.shops)
                )
            },
            deal &&
              %{
                text:
                  gettext("%{card} za %{price}",
                    card: deal.card.name,
                    price: Format.price(deal.price)
                  ),
                size: 48,
                caption:
                  gettext("najlepsza okazja teraz · %{shop}",
                    shop: Shops.name(deal.shop)
                  )
              }
          ],
          & &1
        )

      preview =
        case scan do
          {:ok, png} ->
            width = Picture.scan_width()

            SocialImage.render([
              SocialImage.background(),
              Picture.draw_scan(png, 72, SocialImage.margin(), width, 0)
              | Figures.titled(title, figures, 72 + width + 56, "start")
            ])

          _none ->
            SocialImage.render(Figures.centred(title, figures))
        end

      Picture.partial(preview, [scan])
    end)
  end
end
