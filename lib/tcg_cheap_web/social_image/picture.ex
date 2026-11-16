defmodule TcgCheapWeb.SocialImage.Picture do
  @moduledoc """
  Pictures on a card: loading a product photo, a card scan or a record's
  picture, and standing them on the bench as SVG.

  A loaded picture is `{:ok, png}`, `:none` (there is none to load) or
  `:error` (it could not be loaded).
  """

  alias TcgCheap.Cards
  alias TcgCheap.Storage
  alias TcgCheap.Storage.ImageDownload
  alias TcgCheapWeb.SocialImage
  alias Vix.Vips.Operation

  # A card scan is 245×342.
  @scan_ratio 342 / 245

  @type loaded :: {:ok, binary()} | :none | :error

  @doc "The width of a scan as tall as the card inside its margins."
  @spec scan_width() :: integer()
  def scan_width, do: round((SocialImage.height() - 2 * SocialImage.margin()) / @scan_ratio)

  @doc "A picture from our mirrored storage by its URL, shrunk before it is drawn."
  @spec photo(String.t() | nil) :: loaded()
  def photo(nil), do: :none

  def photo(url) do
    with {:ok, body, _type} <- ImageDownload.fetch_stored(url),
         {:ok, image} <- Operation.thumbnail_buffer(body, 600, size: :VIPS_SIZE_DOWN),
         {:ok, png} <- Image.write(image, :memory, suffix: ".png") do
      {:ok, png}
    else
      _unusable -> :error
    end
  end

  @doc "A card's scan from our mirrored storage (its detail variant) by source."
  @spec scan(String.t() | nil) :: loaded()
  def scan(nil), do: :none

  def scan(source) do
    hash = Cards.Image.source_hash(source)

    case Storage.mirrored_image_urls([hash], :detail) do
      %{^hash => url} -> stored_scan(url)
      _missing -> :error
    end
  end

  @doc "A scan from its URL in our storage."
  @spec stored_scan(String.t() | nil) :: loaded()
  def stored_scan(nil), do: :none
  def stored_scan(url), do: photo(url)

  @doc "A record's own picture, kept with the app (`priv/static/images/records`)."
  @spec record_scan(%{image: String.t() | nil}) :: loaded()
  def record_scan(%{image: nil}), do: :none

  def record_scan(%{image: file}) do
    path = Application.app_dir(:tcg_cheap, "priv/static/images/records/" <> file)

    with {:ok, body} <- File.read(path),
         {:ok, image} <- Operation.thumbnail_buffer(body, 600, size: :VIPS_SIZE_DOWN),
         {:ok, png} <- Image.write(image, :memory, suffix: ".png") do
      {:ok, png}
    else
      _unusable -> :error
    end
  end

  @doc "A preview missing a picture it should have is served, not kept."
  @spec partial(
          {:ok, binary()} | {:error, term()},
          [loaded()]
        ) :: {:ok, binary()} | {:partial, binary()} | {:error, term()}
  def partial({:ok, jpeg}, pictures) do
    if Enum.any?(pictures, &(&1 == :error)), do: {:partial, jpeg}, else: {:ok, jpeg}
  end

  def partial(error, _pictures), do: error

  @doc """
  A card scan standing on the bench with a soft shadow, turned `angle`
  degrees about its centre.
  """
  @spec draw_scan(binary(), number(), number(), pos_integer(), number()) :: [String.t()]
  def draw_scan(png, x, y, width, angle) do
    height = round(width * @scan_ratio)
    cx = x + width / 2
    cy = y + height / 2

    [
      ~s|<g transform="rotate(#{angle} #{cx} #{cy})" filter="url(#lift)">|,
      ~s(<image href="data:image/png;base64,#{Base.encode64(png)}" x="#{x}" y="#{y}" width="#{width}" height="#{height}" preserveAspectRatio="xMidYMid meet"/>),
      "</g>"
    ]
  end

  @doc """
  Up to three scans fanned out around (cx, cy): the last one in front,
  straight and `front` wide; the others `side` wide, turned out to its sides.
  """
  @spec draw_fan([binary(), ...], number(), number(), pos_integer(), pos_integer()) :: [
          [String.t()]
        ]
  def draw_fan(pngs, cx, cy, front \\ 220, side \\ 220) do
    placed =
      case pngs do
        [only] ->
          [{only, front, 0, 0, 0}]

        [left, last] ->
          [{left, side, -70, 16, -8}, {last, front, 70, 0, 4}]

        [left, right, last] ->
          [{left, side, -122, 20, -10}, {right, side, 122, 20, 10}, {last, front, 0, 0, 0}]
      end

    for {png, width, dx, dy, angle} <- placed do
      height = round(width * @scan_ratio)
      draw_scan(png, cx + dx - div(width, 2), cy + dy - div(height, 2), width, angle)
    end
  end

  @doc "A packaging photo on a paper tile."
  @spec draw_tile(binary(), number(), number(), pos_integer()) :: [String.t()]
  def draw_tile(png, x, y, size) do
    inset = 34

    [
      ~s(<rect x="#{x}" y="#{y}" width="#{size}" height="#{size}" fill="#{SocialImage.color(:paper)}"/>),
      ~s(<image href="data:image/png;base64,#{Base.encode64(png)}" x="#{x + inset}" y="#{y + inset}" width="#{size - 2 * inset}" height="#{size - 2 * inset}" preserveAspectRatio="xMidYMid meet"/>)
    ]
  end
end
