defmodule TcgCheapWeb.SEO.Home do
  @moduledoc "Search metadata of the region's home page."

  use TcgCheapWeb, :verified_routes
  use Gettext, backend: TcgCheapWeb.Gettext

  alias TcgCheapWeb.{Paths, RegionText, SEO}

  @spec metadata(map()) :: SEO.t()
  def metadata(params) do
    SEO.compose(
      gettext("Pokémon TCG – ceny kart, boosterów i boxów"),
      RegionText.home_description(),
      Paths.url(Paths.home()),
      social_image: SEO.home_image(),
      social_image_alt: SEO.home_image_alt(),
      # The root sends each visitor to their region's home page.
      alternates: SEO.alternates(:home) ++ [%{hreflang: "x-default", href: url(~p"/")}],
      robots:
        if(Enum.any?(~w(q rodzaj wersja rozszerzenie), &Map.has_key?(params, &1)),
          do: "noindex, follow",
          else: "index, follow"
        ),
      structured_data:
        SEO.json_ld([
          %{"@type" => "WebSite", "name" => "TCG Cheap", "url" => Paths.url(Paths.home())},
          %{
            "@type" => "Organization",
            "name" => "TCG Cheap",
            "url" => Paths.url(Paths.home()),
            "logo" => static_url(TcgCheapWeb.Endpoint, ~p"/apple-touch-icon.png")
          }
        ])
    )
  end
end
