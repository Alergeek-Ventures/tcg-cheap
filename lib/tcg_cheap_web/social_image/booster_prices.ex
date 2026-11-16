defmodule TcgCheapWeb.SocialImage.BoosterPrices do
  @moduledoc """
  The booster price page's preview: the newest set's booster on a paper
  tile, the cheapest booster and the newest one's price beside it.
  """

  use Gettext, backend: TcgCheapWeb.Gettext

  alias TcgCheapWeb.{Format, OfferComponents, SocialImage}
  alias TcgCheapWeb.SocialImage.{Figures, Picture}

  @doc "A version of what the preview shows."
  @spec version(map()) :: String.t()
  def version(page) do
    SocialImage.version(
      Enum.map(
        [page.cheapest, List.first(page.boosters)]
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq_by(& &1.product.id),
        fn booster ->
          {booster.product.id, booster.product.set_name, booster.product.stored_photo_card_url,
           Format.price(booster.verdict.cheapest.price), booster.verdict.cheapest.shop}
        end
      )
    )
  end

  @doc "The preview from `TcgCheap.Sealed.BoosterGuide.prices/1`."
  @spec draw(map()) :: SocialImage.result()
  def draw(page) do
    SocialImage.with_slot(fn ->
      newest = List.first(page.boosters)
      cheapest = page.cheapest
      photo = Picture.photo(newest && newest.product.stored_photo_card_url)
      title = gettext("Ile kosztuje booster Pokémon?")

      figures =
        Enum.filter(
          [
            cheapest &&
              %{
                text:
                  gettext("od %{price}", price: Format.price(cheapest.verdict.cheapest.price)),
                size: 64,
                caption: gettext("najtańszy: %{set}", set: cheapest.product.set_name)
              },
            newest && (is_nil(cheapest) or newest.product.id != cheapest.product.id) &&
              %{
                text:
                  "#{newest.product.set_name}: #{Format.price(newest.verdict.cheapest.price)}",
                size: 48,
                caption:
                  gettext("najnowszy set · %{shop}",
                    shop: OfferComponents.priced_shop_name(newest.verdict.cheapest)
                  )
              }
          ],
          & &1
        )

      preview =
        case photo do
          {:ok, png} ->
            margin = SocialImage.margin()

            SocialImage.render([
              SocialImage.background(),
              Picture.draw_tile(png, margin, margin, SocialImage.height() - 2 * margin)
              | Figures.titled(title, figures, 630, "start")
            ])

          _none ->
            SocialImage.render(Figures.centred(title, figures))
        end

      Picture.partial(preview, [photo])
    end)
  end
end
