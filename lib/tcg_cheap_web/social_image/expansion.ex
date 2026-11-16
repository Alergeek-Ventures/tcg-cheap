defmodule TcgCheapWeb.SocialImage.Expansion do
  @moduledoc """
  An expansion's preview: its three most valuable cards fanned out, its name,
  its top card and its booster beside them; without any scan, the name
  alone, centred.
  """

  use Gettext, backend: TcgCheapWeb.Gettext

  alias TcgCheap.Sealed.Shops
  alias TcgCheapWeb.{Format, SocialImage}
  alias TcgCheapWeb.SocialImage.{Figures, Picture}

  @doc "A version of what the preview shows (`TcgCheap.Sealed.SetPage.read/3`)."
  @spec version(String.t(), map()) :: String.t()
  def version(name, set_page) do
    top = top_card(set_page)

    SocialImage.version(
      {name, Enum.map(scan_cards(set_page), &{&1.card.id, &1.image}),
       top && {top.card.name, Format.whole_price(top.price), top.source},
       (booster = booster_price(set_page)) && Format.price(booster)}
    )
  end

  @doc """
  The preview from the expansion's set page (`TcgCheap.Sealed.SetPage.read/3`).
  """
  @spec draw(String.t(), map()) :: SocialImage.result()
  def draw(name, set_page) do
    SocialImage.with_slot(fn ->
      scans = Enum.map(scan_cards(set_page), &Picture.scan(&1.image))
      pngs = for {:ok, png} <- scans, do: png

      figures =
        Enum.filter(
          [
            (booster = booster_price(set_page)) &&
              %{text: gettext("Booster od %{price}", price: Format.price(booster)), size: 64},
            (top = top_card(set_page)) &&
              %{
                text: "#{top.card.name} ≈ #{Format.whole_price(top.price)}",
                size: 48,
                caption: top_card_caption(top)
              }
          ],
          & &1
        )

      preview =
        case pngs do
          [] ->
            SocialImage.render(Figures.centred(name, figures))

          [png] ->
            width = Picture.scan_width()

            SocialImage.render([
              SocialImage.background(),
              Picture.draw_scan(png, 72, SocialImage.margin(), width, 0)
              | Figures.titled(name, figures, 72 + width + 56, "start")
            ])

          pngs ->
            SocialImage.render([
              SocialImage.background(),
              Picture.draw_fan(pngs, 300, 315) | Figures.titled(name, figures, 600, "start")
            ])
        end

      Picture.partial(preview, scans)
    end)
  end

  # The set's most valuable card, with a scan or not.
  defp top_card(%{set: %{top_cards: [top | _]}}), do: top
  defp top_card(_set_page), do: nil

  # The cards on a set page's "most valuable" list that have a scan.
  defp scan_cards(%{set: %{top_cards: tops}}),
    do: tops |> Enum.filter(& &1.image) |> Enum.take(3)

  defp scan_cards(_set_page), do: []

  defp booster_price(%{booster: %{preorder?: false, verdict: %{cheapest: %{price: price}}}}),
    do: price

  defp booster_price(_set_page), do: nil

  # Where the set's top card price comes from, as the set page says it.
  defp top_card_caption(%{source: {:shop, shop}}),
    do: gettext("najcenniejsza karta · najtaniej w %{shop}", shop: Shops.name(shop))

  defp top_card_caption(_top), do: gettext("najcenniejsza karta · Cardmarket")
end
