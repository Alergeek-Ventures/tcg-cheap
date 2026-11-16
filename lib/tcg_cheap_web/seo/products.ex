defmodule TcgCheapWeb.SEO.Products do
  @moduledoc """
  Search metadata of the products list, the card list's equal. Narrowed by a
  search, a kind or an edition it stays out of search, as the card list does;
  a chosen expansion's list is its set page (`SEO.Expansion`).
  """

  use Gettext, backend: TcgCheapWeb.Gettext

  alias TcgCheapWeb.{Paths, RegionText, SEO}

  @spec metadata(map()) :: SEO.t()
  def metadata(params) do
    canonical = Paths.url(Paths.products())
    title = gettext("Ceny boosterów, ETB i boxów Pokémon TCG")

    SEO.compose(
      title,
      SEO.fit_description([
        RegionText.products_promise(),
        gettext("Najniższa cena i ocena każdego produktu, z historią cen.")
      ]),
      canonical,
      social_image: SEO.home_image(),
      social_image_alt: SEO.home_image_alt(),
      alternates: SEO.alternates(:products),
      robots:
        if(Enum.any?(~w(q rodzaj wersja), &Map.has_key?(params, &1)),
          do: "noindex, follow",
          else: "index, follow"
        ),
      structured_data:
        SEO.json_ld(%{"@type" => "CollectionPage", "name" => title, "url" => canonical})
    )
  end
end
