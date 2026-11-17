defmodule TcgCheapWeb.SocialImage.Answer do
  @moduledoc """
  The answer of a product or card, as the guide's page gives it: the verdict
  badge, the price, the shop line and notes.
  """

  alias TcgCheapWeb.SocialImage
  alias TcgCheapWeb.SocialImage.Text
  alias TcgCheapWeb.VerdictComponents

  @type price :: {String.t(), pos_integer(), :ink | :muted} | nil

  @doc """
  Badge, price and shop line, then notes, stacked up from the bottom edge;
  returns the SVG and its height. A nil verdict draws no badge.
  """
  @spec stack(map() | nil, price(), String.t(), [String.t()], number(), number()) ::
          {list(), integer()}
  def stack(verdict, price, shop_line, notes, x, width) do
    shop_lines = Text.wrap(shop_line, 23, :mono, width, 2)
    # A note wraps to the column like the shop line: a long amount's line
    # must not run off the card.
    note_lines = Enum.flat_map(notes, &Text.wrap(&1, 20, :mono, width, 2))
    badge_height = if verdict, do: 72 + 26, else: 0
    price_height = price_height(price)
    shop_height = length(shop_lines) * 34
    notes_height = if note_lines == [], do: 0, else: 12 + length(note_lines) * 30
    height = badge_height + price_height + shop_height + notes_height
    top = SocialImage.height() - SocialImage.margin() - height
    price_top = top + badge_height
    shop_top = price_top + price_height

    svg = [
      verdict && badge(verdict, x, top, 72, 40),
      price_line(price, x, price_top),
      Text.lines(shop_lines, x, shop_top, 23, 34, :mono, :ink),
      Text.lines(note_lines, x, shop_top + shop_height + 12, 20, 30, :mono, :muted)
    ]

    {svg, height}
  end

  defp price_height(nil), do: 0
  defp price_height({_text, size, _color}), do: round(size * 0.9)

  defp price_line(nil, _x, _top), do: nil

  defp price_line({text, size, color}, x, top),
    do: Text.line(text, x, top + round(size * 0.76), size, :display, color)

  @doc """
  The guide's large verdict badge: filled for good, normal and expensive, a
  paper slip with a drawn bottom edge otherwise; text and mark carry the
  meaning, never colour alone. A badge of a given width shrinks its label to
  fit (a longer verdict label, such as Croatian "Uobičajena cijena").
  """
  @spec badge(map(), number(), number(), pos_integer(), pos_integer(), number() | nil) ::
          [String.t() | nil]
  def badge(verdict, x, y, height, size, width \\ nil) do
    {fill, color, edge} = badge_colors(verdict)
    label = verdict |> VerdictComponents.verdict_label() |> String.upcase()
    mark = round(size * 0.7)
    text_x = x + 24 + mark + 14
    size = if width, do: fit_label(label, size, width - (text_x - x) - 24), else: size
    width = width || text_x - x + Text.measure(label, size, :display, 1.6) + 24

    [
      ~s(<rect x="#{x}" y="#{y}" width="#{round(width)}" height="#{height}" fill="#{fill}"/>),
      edge && edge_line(edge, x, y + height - 2, width),
      ~s|<g transform="translate(#{x + 24} #{y + (height - mark) / 2}) scale(#{mark / 16})" fill="none" stroke="#{color}" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round">| <>
        Enum.map_join(VerdictComponents.verdict_paths(verdict.status), &~s(<path d="#{&1}"/>)) <>
        "</g>",
      ~s(<text x="#{text_x}" y="#{y + height / 2 + size * 0.36}" font-family="#{Text.display_family()}" font-weight="700" font-size="#{size}" letter-spacing="1.6" fill="#{color}">#{Text.escape(label)}</text>)
    ]
  end

  defp fit_label(label, size, room),
    do: Enum.find(size..20//-2, 20, &(Text.measure(label, &1, :display, 1.6) <= room))

  defp badge_colors(%{status: :good}), do: {rise(), paper(), nil}
  defp badge_colors(%{status: :expensive}), do: {fall(), paper(), nil}
  defp badge_colors(%{status: :normal}), do: {ink(), paper(), nil}

  defp badge_colors(%{status: status}) when status in [:cardmarket, :insufficient_data],
    do: {paper(), ink(), {muted(), "12 8"}}

  defp badge_colors(%{status: :out_of_stock}), do: {paper(), ink(), {muted(), "4 8"}}

  defp rise, do: SocialImage.color(:rise)
  defp fall, do: SocialImage.color(:fall)
  defp paper, do: SocialImage.color(:paper)
  defp ink, do: SocialImage.color(:ink)
  defp muted, do: SocialImage.color(:muted)

  defp edge_line({color, dash}, x, y, width) do
    dash = if dash, do: ~s( stroke-dasharray="#{dash}"), else: ""

    ~s(<line x1="#{x}" y1="#{y}" x2="#{x + width}" y2="#{y}" stroke="#{color}" stroke-width="4"#{dash}/>)
  end
end
