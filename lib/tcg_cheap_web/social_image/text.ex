defmodule TcgCheapWeb.SocialImage.Text do
  @moduledoc """
  Text on a card: measuring, wrapping and fitting it to a width, and drawing
  it as SVG. Fonts are the guide's: Barlow Condensed Bold (`:display`) and
  Azeret Mono (`:mono`).
  """

  alias TcgCheapWeb.SocialImage

  @display "Barlow Condensed"
  @mono "Azeret Mono"

  @min_title 40
  @title_sizes [72, 64, 56, 50, 44, @min_title]
  @xml_forbidden ~r/[\x00-\x08\x0B\x0C\x0E-\x1F]/u
  @spaces ~r/\s+/u

  @type font :: :display | :mono
  @type anchor :: String.t()

  @doc "The font family of the display face, for text drawn outside this module."
  @spec display_family() :: String.t()
  def display_family, do: @display

  @doc "The sizes a title is tried at, largest first."
  @spec title_sizes() :: [pos_integer(), ...]
  def title_sizes, do: @title_sizes

  @doc "The smallest title size."
  @spec min_title() :: pos_integer()
  def min_title, do: @min_title

  @doc "Single spaces, and none of the control characters XML forbids."
  @spec normalize(String.t()) :: String.t()
  def normalize(text),
    do:
      text
      |> String.replace(@xml_forbidden, "")
      |> String.split(@spaces, trim: true)
      |> Enum.join(" ")

  @doc "The text as SVG character data."
  @spec escape(String.t()) :: String.t()
  def escape(text),
    do: text |> normalize() |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()

  @doc """
  The text's width: advance widths in em. Azeret Mono is monospaced; Barlow
  Condensed Bold by character class, from the font's metrics, slightly
  generous.
  """
  @spec measure(String.t(), number(), font(), number()) :: number()
  def measure(text, size, font, letter_spacing \\ 0)

  def measure(text, size, :mono, letter_spacing),
    do: String.length(text) * (0.65 * size + letter_spacing)

  def measure(text, size, :display, letter_spacing) do
    text
    |> String.graphemes()
    |> Enum.reduce(0, fn grapheme, sum -> sum + display_em(grapheme) * size + letter_spacing end)
  end

  defp display_em(grapheme) do
    cond do
      grapheme in [" ", "\u00A0"] -> 0.2
      String.contains?("iljI|!.,:;'`·", grapheme) -> 0.23
      String.contains?("frt1()-[]{}\"*", grapheme) -> 0.33
      String.contains?("mwMW%@&#", grapheme) -> 0.69
      true -> 0.47
    end
  end

  @doc """
  The largest title size at which the whole name fits the room in balanced
  lines; otherwise the smallest size, in as many lines as the room holds,
  ellipsized. Returns `{size, lines}`.
  """
  @spec fit_title(String.t(), number(), number(), pos_integer(), [pos_integer(), ...]) ::
          {pos_integer(), [String.t()]}
  def fit_title(name, width, room, max_lines, sizes \\ @title_sizes) do
    Enum.find_value(sizes, fn size ->
      lines = greedy(name, size, :display, width)
      fits? = length(lines) <= max_lines and length(lines) * round(size * 0.96) <= room
      if fits?, do: {size, balanced(name, size, :display, width, max_lines)}
    end) ||
      {@min_title,
       wrap(
         name,
         @min_title,
         :display,
         width,
         room |> div(round(@min_title * 0.96)) |> max(1) |> min(max_lines)
       )}
  end

  @doc """
  The largest of `sizes` at which the text fits `max_lines` balanced lines;
  the smallest, ellipsized, otherwise. Returns `{size, lines}`.
  """
  @spec fit_lines(String.t(), number(), [pos_integer(), ...], pos_integer()) ::
          {pos_integer(), [String.t()]}
  def fit_lines(text, width, sizes, max_lines) do
    Enum.find_value(sizes, fn size ->
      if length(greedy(text, size, :display, width)) <= max_lines,
        do: {size, balanced(text, size, :display, width, max_lines)}
    end) || {List.last(sizes), wrap(text, List.last(sizes), :display, width, max_lines)}
  end

  @doc "The largest size, from `size` down to 36, at which a display line fits `width`."
  @spec fit_size(String.t(), pos_integer(), number()) :: pos_integer()
  def fit_size(text, size, width) do
    Enum.find(size..36//-4, 36, &(measure(text, &1, :display) <= width))
  end

  @doc """
  The fewest lines greedy wrapping needs, then the split with the most even
  line widths, so no word is left alone on the last line.
  """
  @spec balanced(String.t(), number(), font(), number(), pos_integer()) :: [String.t()]
  def balanced(text, size, font, width, max_lines) do
    words = String.split(text, " ", trim: true)
    count = length(greedy(text, size, font, width))

    if count <= 1 or count > max_lines or length(words) > 24 do
      wrap(text, size, font, width, max_lines)
    else
      words
      |> splits(count)
      |> Enum.map(fn lines -> Enum.map(lines, &Enum.join(&1, " ")) end)
      |> Enum.filter(fn lines -> Enum.all?(lines, &(measure(&1, size, font) <= width)) end)
      |> Enum.min_by(
        fn lines -> lines |> Enum.map(&measure(&1, size, font)) |> Enum.max() end,
        fn -> wrap(text, size, font, width, max_lines) end
      )
    end
  end

  # Every way to cut `words` into `count` non-empty lines.
  defp splits(words, 1), do: [[words]]

  defp splits(words, count) do
    for cut <- 1..(length(words) - count + 1)//1,
        {line, rest} = Enum.split(words, cut),
        tail <- splits(rest, count - 1),
        do: [line | tail]
  end

  defp greedy(text, size, font, width) do
    {lines, current} =
      text
      |> String.split(" ", trim: true)
      |> Enum.reduce({[], nil}, fn
        word, {lines, nil} ->
          {lines, word}

        word, {lines, current} ->
          candidate = current <> " " <> word

          if measure(candidate, size, font) <= width,
            do: {lines, candidate},
            else: {[current | lines], word}
      end)

    Enum.reverse(if current, do: [current | lines], else: lines)
  end

  @doc """
  Greedy lines, at most `max_lines`; a line that does not fit, or the last
  one when text is left over, ends in an ellipsis.
  """
  @spec wrap(String.t(), number(), font(), number(), pos_integer()) :: [String.t()]
  def wrap(text, size, font, width, max_lines) do
    lines = greedy(normalize(text), size, font, width)

    if length(lines) > max_lines do
      {kept, [last | _rest]} = Enum.split(lines, max_lines - 1)

      Enum.map(kept, &ellipsize(&1, size, font, width, false)) ++
        [ellipsize(last, size, font, width)]
    else
      Enum.map(lines, &ellipsize(&1, size, font, width, false))
    end
  end

  # The longest start of the line that fits with an ellipsis; a line that
  # fits as it is stays unless the ellipsis is forced.
  defp ellipsize(line, size, font, width, forced? \\ true)

  defp ellipsize(line, size, font, width, false) do
    if measure(line, size, font) <= width,
      do: line,
      else: ellipsize(line, size, font, width, true)
  end

  defp ellipsize(line, size, font, width, true) do
    line
    |> String.graphemes()
    |> Enum.scan(&(&2 <> &1))
    |> Enum.take_while(&(measure(&1 <> "…", size, font) <= width))
    |> List.last("")
    |> String.trim_trailing()
    |> Kernel.<>("…")
  end

  @doc "Lines of text, the first with its top at `top`, `line_height` apart."
  @spec lines(
          [String.t()],
          number(),
          number(),
          number(),
          number(),
          font(),
          atom(),
          anchor()
        ) :: [String.t()]
  def lines(lines, x, top, size, line_height, font, color, anchor \\ "start") do
    lines
    |> Enum.with_index()
    |> Enum.map(fn {line, index} ->
      line(line, x, top + index * line_height + round(size * 0.8), size, font, color, anchor)
    end)
  end

  @doc "One line of text on `baseline`; `color` is a `SocialImage.color/1` name."
  @spec line(String.t(), number(), number(), number(), font(), atom(), anchor()) :: String.t()
  def line(text, x, baseline, size, font, color, anchor \\ "start") do
    {family, weight} = font_face(font)

    ~s(<text x="#{x}" y="#{baseline}" text-anchor="#{anchor}" font-family="#{family}" font-weight="#{weight}" font-size="#{size}" fill="#{SocialImage.color(color)}">#{escape(text)}</text>)
  end

  defp font_face(:display), do: {@display, 700}
  defp font_face(:mono), do: {@mono, 400}
end
