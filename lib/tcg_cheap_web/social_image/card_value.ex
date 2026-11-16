defmodule TcgCheapWeb.SocialImage.CardValue do
  @moduledoc """
  The card value guide's preview: three of its example cards fanned out, the
  dearest in front, and the question with what half the cards and the
  dearest ones cost beside them.
  """

  use Gettext, backend: TcgCheapWeb.Gettext

  alias TcgCheapWeb.{Format, SocialImage}
  alias TcgCheapWeb.SocialImage.{Figures, Picture}

  @doc "A version of what the preview shows."
  @spec version(map()) :: String.t()
  def version(guide) do
    SocialImage.version({figures(guide.spread), Enum.map(examples(guide), & &1.row.image_large)})
  end

  @doc "The preview from `TcgCheap.Sealed.CardValue.guide/0`."
  @spec draw(map()) :: SocialImage.result()
  def draw(guide) do
    SocialImage.with_slot(fn ->
      scans = Enum.map(examples(guide), &Picture.stored_scan(&1.row.image_large))
      pngs = for {:ok, png} <- scans, do: png
      figures = figures(guide.spread)
      headline = gettext("Ile jest warta twoja karta Pokémon?")

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

  # The cheapest, a middle and the dearest example, the dearest drawn last,
  # in front.
  defp examples(%{examples: examples}) do
    case examples do
      [_, _, _ | _] -> [hd(examples), Enum.at(examples, -2), List.last(examples)]
      fewer -> fewer
    end
  end

  defp figures(nil), do: []

  defp figures(spread) do
    Enum.filter(
      [
        %{
          text: gettext("do %{price}", price: Format.whole_price_ceiling(spread.median)),
          size: 64,
          caption: gettext("kosztuje połowa kart w sklepach")
        },
        spread.over_100 > 0 &&
          %{
            text: gettext("1 na %{count}", count: round(spread.count / spread.over_100)),
            size: 48,
            caption: gettext("kosztuje ponad 100 zł")
          }
      ],
      & &1
    )
  end
end
