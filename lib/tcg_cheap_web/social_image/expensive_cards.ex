defmodule TcgCheapWeb.SocialImage.ExpensiveCards do
  @moduledoc """
  The expensive cards article's preview: the record card between today's two
  most expensive, and the record and today's top price beside them.
  """

  use Gettext, backend: TcgCheapWeb.Gettext

  alias TcgCheapWeb.{CardRecords, Format, SocialImage}
  alias TcgCheapWeb.SocialImage.{Figures, Picture}

  @doc "A version of what the preview shows."
  @spec version(map()) :: String.t()
  def version(overview) do
    record = hd(CardRecords.all())

    SocialImage.version(
      {{record.id, record.name, record.usd, record.image},
       Enum.map(
         Enum.take(overview.highlights, 2),
         &{&1.card.name, Format.whole_price(&1.value), &1.image_large}
       )}
    )
  end

  @doc "The preview from `TcgCheap.Cards.Expensive.overview/0`."
  @spec draw(map()) :: SocialImage.result()
  def draw(overview) do
    record = hd(CardRecords.all())

    SocialImage.with_slot(fn ->
      today = Enum.take(overview.highlights, 2)
      # The last scan is drawn in front: the record.
      scans =
        Enum.map(today, &Picture.stored_scan(&1.image_large)) ++ [Picture.record_scan(record)]

      pngs = for {:ok, png} <- scans, do: png

      figures =
        Enum.filter(
          [
            %{
              text: CardRecords.usd(record.usd),
              size: 64,
              caption: gettext("rekord: %{card}", card: record.name)
            },
            today != [] &&
              %{
                text: "#{hd(today).card.name} ≈ #{Format.whole_price(hd(today).value)}",
                size: 48,
                caption: gettext("najdroższa z ostatnich lat")
              }
          ],
          & &1
        )

      headline = gettext("Najdroższe karty Pokémon")

      preview =
        case pngs do
          [] ->
            SocialImage.render(Figures.centred(headline, figures))

          pngs ->
            SocialImage.render([
              SocialImage.background(),
              Picture.draw_fan(pngs, 930, 315, 250, 200)
              | Figures.titled(headline, figures, 600, "end")
            ])
        end

      Picture.partial(preview, scans)
    end)
  end
end
