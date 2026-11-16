defmodule TcgCheapWeb.SocialImage.Home do
  @moduledoc """
  The home card, which the region's other pages without a card of their own
  share: the promise and the verdict scale.
  """

  use Gettext, backend: TcgCheapWeb.Gettext

  alias TcgCheapWeb.{RegionText, SocialImage}
  alias TcgCheapWeb.SocialImage.{Answer, Text}

  @doc "The promise under the card's headline."
  @spec promise() :: String.t()
  def promise, do: RegionText.social_promise()

  @doc "A version of what the card shows, for its storage key and URL."
  @spec version() :: String.t()
  def version, do: SocialImage.version(promise())

  @doc "The card: the promise and the verdict scale."
  @spec draw() :: {:ok, binary()} | {:error, term()}
  def draw do
    margin = SocialImage.margin()
    height = SocialImage.height()
    width = SocialImage.width()
    x = margin + 16
    text_width = 600

    headline = Text.balanced(gettext("Sprawdź, czy cena jest dobra"), 96, :display, text_width, 2)

    promise_lines = Text.balanced(promise(), 27, :mono, text_width, 3)

    logo_height = 64
    headline_line = 92
    promise_line = 40

    left_height =
      logo_height + 46 + length(headline) * headline_line + 26 +
        length(promise_lines) * promise_line

    top = div(height - left_height, 2)
    headline_top = top + logo_height + 46
    promise_top = headline_top + length(headline) * headline_line + 26

    {card, card_height} = scale_card(728, width - x - 728)

    SocialImage.with_slot(fn ->
      SocialImage.render([
        SocialImage.background(),
        SocialImage.logo(x, top, logo_height),
        Text.lines(headline, x, headline_top, 96, headline_line, :display, :ink),
        Text.lines(promise_lines, x, promise_top, 27, promise_line, :mono, :ink),
        card.(div(height - card_height, 2))
      ])
    end)
  end

  # The verdict scale of the guide, as on a product page, without prices;
  # returns a function of its top edge and its height.
  defp scale_card(x, width) do
    inner = width - 64

    rows = [
      {%{status: :good}, gettext("do 95% typowej ceny")},
      {%{status: :normal}, gettext("do 110% typowej ceny")},
      {%{status: :expensive}, gettext("powyżej 110% typowej ceny")}
    ]

    heading = Text.wrap(gettext("Widzisz cenę w sklepie?"), 34, :display, inner, 2)
    heading_height = 34 + length(heading) * 36
    row_height = 64 + 46
    height = heading_height + 20 + length(rows) * row_height + 10

    card = fn y ->
      rows_top = y + heading_height + 20

      [
        ~s(<rect x="#{x}" y="#{y}" width="#{width}" height="#{height}" fill="#{SocialImage.color(:paper)}"/>),
        Text.lines(heading, x + 32, y + 34, 34, 36, :display, :ink),
        rows
        |> Enum.with_index()
        |> Enum.map(fn {{verdict, note}, index} ->
          row_y = rows_top + index * row_height

          [
            Answer.badge(verdict, x + 32, row_y, 64, 36, inner),
            Text.line(note, x + 32, row_y + 64 + 30, 20, :mono, :muted)
          ]
        end)
      ]
    end

    {card, height}
  end
end
