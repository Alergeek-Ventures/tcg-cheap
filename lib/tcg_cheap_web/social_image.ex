defmodule TcgCheapWeb.SocialImage do
  @moduledoc """
  Link-preview cards (Open Graph, 1200×630 JPEG) for the buying guide, drawn
  as SVG in the guide's look, rendered with resvg and the bundled fonts
  (`priv/social_fonts`, OFL; full Latin Extended, unlike the subset web
  fonts) and encoded with libvips.

  This module is the canvas every card is drawn on: its size and palette,
  the logo, the render pipeline and the cache-key `version/1`. Text,
  pictures, the verdict badge and the figure layouts have their own modules
  under `TcgCheapWeb.SocialImage.*`; each page kind's card and version are
  in `TcgCheapWeb.SocialImage.<Page>` (`draw` and `version`).

  Text beside card scans is aligned towards them; text alone is centred. At
  most two cards render at once; `TcgCheapWeb.SocialImageController` keeps
  rendered cards in storage.
  """

  # Bump when the layout changes, so stored and cached cards are replaced.
  @design 7

  @width 1200
  @height 630
  @margin 56

  # The logo is 405×96.
  @logo_ratio 405 / 96
  @max_renders 2
  # A render waits this long for a free slot before giving up.
  @slot_wait_ms 3_000

  @type result :: {:ok, binary()} | {:partial, binary()} | {:error, term()}

  @doc "The card's width in pixels."
  @spec width() :: pos_integer()
  def width, do: @width

  @doc "The card's height in pixels."
  @spec height() :: pos_integer()
  def height, do: @height

  @doc "The space kept free around a card's content."
  @spec margin() :: pos_integer()
  def margin, do: @margin

  @doc "A colour of the guide's palette as an SVG fill."
  @spec color(:bench | :paper | :ink | :muted | :rise | :fall) :: String.t()
  def color(:bench), do: "#f1eadc"
  def color(:paper), do: "#fffdf8"
  def color(:ink), do: "#171614"
  def color(:muted), do: "#6d6256"
  def color(:rise), do: "#27714b"
  def color(:fall), do: "#a6402f"

  @doc "A version of what a card shows, for its storage key and URL."
  @spec version(term()) :: String.t()
  def version(content),
    do: {@design, content} |> :erlang.phash2() |> Integer.to_string(36) |> String.downcase()

  @doc "The bench the cards stand on."
  @spec background() :: String.t()
  def background,
    do: ~s(<rect width="#{@width}" height="#{@height}" fill="#{color(:bench)}"/>)

  @doc "The logo's width at `height`."
  @spec logo_width(pos_integer()) :: integer()
  def logo_width(height), do: round(height * @logo_ratio)

  @doc "The logo with its top left corner at `x`, `y`."
  @spec logo(number(), number(), pos_integer()) :: String.t()
  def logo(x, y, height) do
    %{logo: logo} = assets()

    ~s(<image href="data:image/webp;base64,#{logo}" x="#{x}" y="#{y}" width="#{logo_width(height)}" height="#{height}"/>)
  end

  @doc """
  An SVG to a JPEG: resvg draws it, libvips encodes it far smaller than the
  PNG, which matters to messengers that drop large previews. `parts` is
  nested iodata; non-binaries (nil) are dropped.
  """
  @spec render(iodata() | list()) :: {:ok, binary()} | {:error, term()}
  def render(parts) do
    %{fontdb: fontdb} = assets()

    svg = [
      ~s(<svg xmlns="http://www.w3.org/2000/svg" width="#{@width}" height="#{@height}" viewBox="0 0 #{@width} #{@height}">),
      ~s(<defs><filter id="lift" x="-25%" y="-25%" width="150%" height="150%"><feDropShadow dx="0" dy="10" stdDeviation="12" flood-color="#{color(:ink)}" flood-opacity="0.28"/></filter></defs>),
      parts |> List.flatten() |> Enum.filter(&is_binary/1),
      "</svg>"
    ]

    with {:ok, png} <-
           svg
           |> IO.iodata_to_binary()
           |> Resvg.svg_string_to_png_binary(fontdb: fontdb, resources_dir: System.tmp_dir!()),
         {:ok, image} <- Image.from_binary(png) do
      Image.write(image, :memory, suffix: ".jpg", quality: 90, strip_metadata: true)
    end
  end

  @doc """
  Runs a render. Renders block a normal scheduler (the resvg NIF is not
  dirty) and need memory for the photo, so at most #{@max_renders} run at
  once; others wait a few seconds for a slot, then give `{:error, :busy}`.
  """
  @spec with_slot((-> result()), non_neg_integer()) :: result()
  def with_slot(fun, waited \\ 0) do
    %{slots: slots} = assets()

    cond do
      :atomics.add_get(slots, 1, 1) <= @max_renders ->
        try do
          fun.()
        after
          :atomics.sub(slots, 1, 1)
        end

      waited < @slot_wait_ms ->
        :atomics.sub(slots, 1, 1)
        Process.sleep(100)
        with_slot(fun, waited + 100)

      true ->
        :atomics.sub(slots, 1, 1)
        {:error, :busy}
    end
  end

  # The font database, the logo and the render slots, loaded once per node.
  defp assets do
    case :persistent_term.get(__MODULE__, nil) do
      nil ->
        {:ok, fontdb} =
          Resvg.init_fontdb(
            font_dirs: [Application.app_dir(:tcg_cheap, "priv/social_fonts")],
            skip_system_fonts: true
          )

        logo =
          :tcg_cheap
          |> Application.app_dir("priv/static/images/tcg-cheap.webp")
          |> File.read!()
          |> Base.encode64()

        assets = %{fontdb: fontdb, logo: logo, slots: :atomics.new(1, signed: true)}
        :persistent_term.put(__MODULE__, assets)
        assets

      assets ->
        assets
    end
  end
end
