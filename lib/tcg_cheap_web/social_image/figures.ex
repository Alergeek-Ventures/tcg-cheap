defmodule TcgCheapWeb.SocialImage.Figures do
  @moduledoc """
  The text layouts of the cards that show a title and figures (a big line
  and an optional caption under it): beside the scans, or alone and centred
  for a preview without a picture. A figure is a map with `:text`, `:size`
  and `:caption` (optional).
  """

  alias TcgCheapWeb.SocialImage
  alias TcgCheapWeb.SocialImage.Text

  @type figure :: %{
          required(:text) => String.t(),
          optional(:size) => pos_integer(),
          optional(:caption) => String.t()
        }

  @doc """
  A title and figures, centred vertically and aligned at `x` towards the
  scans beside them: "end" when they are on the right, "start" when on the
  left.
  """
  @spec titled(String.t(), [figure()], number(), String.t()) :: list()
  def titled(title, figures, x, anchor) do
    margin = SocialImage.margin()
    width = if anchor == "end", do: x - margin - 16, else: SocialImage.width() - margin - x
    logo_height = 48
    logo_x = if anchor == "end", do: x - SocialImage.logo_width(logo_height), else: x
    {size, lines} = Text.fit_lines(Text.normalize(title), width, [84, 72, 64, 56], 2)
    line = round(size * 0.98)

    laid =
      Enum.map(figures, fn figure ->
        figure_size = Text.fit_size(figure.text, Map.get(figure, :size, 64), width)

        captions =
          case Map.get(figure, :caption) do
            nil -> []
            caption -> Text.wrap(caption, 26, :mono, width, 2)
          end

        {figure.text, figure_size, captions,
         round(figure_size * 0.95) + length(captions) * 34 + 26}
      end)

    height =
      logo_height + 36 + length(lines) * line + 30 +
        Enum.sum(Enum.map(laid, &elem(&1, 3)))

    top = div(SocialImage.height() - height, 2)
    title_top = top + logo_height + 36

    {figure_svg, _end} =
      Enum.map_reduce(laid, title_top + length(lines) * line + 30, fn {text, figure_size,
                                                                       captions, figure_height},
                                                                      figure_top ->
        baseline = figure_top + round(figure_size * 0.78)

        {[
           Text.line(text, x, baseline, figure_size, :display, :ink, anchor),
           Text.lines(captions, x, baseline + 10, 26, 34, :mono, :muted, anchor)
         ], figure_top + figure_height}
      end)

    [
      SocialImage.logo(logo_x, top, logo_height),
      Text.lines(lines, x, title_top, size, line, :display, :ink, anchor),
      figure_svg
    ]
  end

  @doc "A title and figures alone, centred, for a preview without a picture."
  @spec centred(String.t(), [figure()]) :: list()
  def centred(title, figures) do
    centre = div(SocialImage.width(), 2)
    width = SocialImage.width() - 2 * (SocialImage.margin() + 64)
    logo_height = 56
    logo_width = SocialImage.logo_width(logo_height)
    {size, lines} = Text.fit_lines(Text.normalize(title), width, [88, 76, 64], 2)
    line = round(size * 0.98)

    laid =
      Enum.map(figures, fn figure ->
        figure_size = Text.fit_size(figure.text, min(Map.get(figure, :size, 64), 56), width)

        captions =
          if caption = Map.get(figure, :caption),
            do: Text.wrap(caption, 26, :mono, width, 1),
            else: []

        {figure.text, figure_size, captions,
         round(figure_size * 0.95) + length(captions) * 34 + 22}
      end)

    height =
      logo_height + 40 + length(lines) * line + 30 + Enum.sum(Enum.map(laid, &elem(&1, 3)))

    top = div(SocialImage.height() - height, 2)
    title_top = top + logo_height + 40

    {figure_svg, _end} =
      Enum.map_reduce(laid, title_top + length(lines) * line + 30, fn {text, figure_size,
                                                                       captions, figure_height},
                                                                      figure_top ->
        baseline = figure_top + round(figure_size * 0.78)

        {[
           Text.line(text, centre, baseline, figure_size, :display, :ink, "middle"),
           Text.lines(captions, centre, baseline + 10, 26, 34, :mono, :muted, "middle")
         ], figure_top + figure_height}
      end)

    [
      SocialImage.background(),
      SocialImage.logo(centre - div(logo_width, 2), top, logo_height),
      Text.lines(lines, centre, title_top, size, line, :display, :ink, "middle"),
      figure_svg
    ]
  end
end
