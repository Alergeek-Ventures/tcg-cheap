defmodule TcgCheapWeb.SEO do
  @moduledoc "Search metadata for the buying guide, derived from the same data as its visible pages."

  use TcgCheapWeb, :html
  use Gettext, backend: TcgCheapWeb.Gettext

  alias TcgCheap.Sealed.Kinds
  alias TcgCheapWeb.{GuideComponents, Polish, SocialImage}

  def home(params) do
    metadata(
      gettext("Pokémon TCG – porównywarka cen boosterów, ETB i boxów"),
      gettext(
        "Porównaj ceny Pokémon TCG w polskich sklepach. Sprawdź oferty boosterów, ETB i boxów, historię cen i czy warto kupić teraz."
      ),
      url(~p"/"),
      social_image: url(~p"/og?#{[v: SocialImage.home_version()]}"),
      social_image_alt:
        "TCG Cheap. " <>
          gettext("Sprawdź, czy cena jest dobra") <>
          ". " <> SocialImage.home_promise(),
      robots:
        if(Enum.any?(~w(q rodzaj wersja rozszerzenie), &Map.has_key?(params, &1)),
          do: "noindex, follow",
          else: "index, follow"
        ),
      structured_data: %{
        "@context" => "https://schema.org",
        "@type" => "WebSite",
        "name" => "TCG Cheap",
        "url" => url(~p"/")
      }
    )
  end

  def product(page) do
    product = page.product
    canonical = url(~p"/produkty/#{product.slug}")

    description =
      gettext(
        "%{name}: porównaj ceny i dostępność w polskich sklepach. Sprawdź historię cen oraz oferty z dostawą lub odbiorem osobistym.",
        name: product.name
      )

    product_data = %{
      "@type" => "Product",
      "name" => product.name,
      "description" => description,
      "url" => canonical,
      "category" => Kinds.label(product.kind)
    }

    product_data =
      if product.image_url,
        do: Map.put(product_data, "image", product.image_url),
        else: product_data

    # Only current, in-stock shop offers count, never MSRP, Cardmarket or a last-known price.
    product_data =
      case Enum.filter(page.offers, & &1.in_stock) do
        [] ->
          product_data

        offers ->
          {low, high} = Enum.min_max_by(offers, & &1.price, Decimal)

          Map.put(product_data, "offers", %{
            "@type" => "AggregateOffer",
            "url" => canonical,
            "priceCurrency" => "PLN",
            "lowPrice" => Decimal.to_string(low.price, :normal),
            "highPrice" => Decimal.to_string(high.price, :normal),
            "offerCount" => length(offers)
          })
      end

    metadata(
      gettext("%{name} – ceny i oferty Pokémon TCG", name: product.name),
      description,
      canonical,
      social_image:
        url(~p"/og/produkty/#{product.slug}?#{[v: SocialImage.product_version(page)]}"),
      social_image_alt: product.name <> ". " <> answer(page.verdict),
      structured_data: %{
        "@context" => "https://schema.org",
        "@graph" => [
          product_data,
          %{
            "@type" => "BreadcrumbList",
            "itemListElement" => [
              %{
                "@type" => "ListItem",
                "position" => 1,
                "name" => gettext("Wszystkie produkty"),
                "item" => url(~p"/")
              },
              %{
                "@type" => "ListItem",
                "position" => 2,
                "name" => product.name,
                "item" => canonical
              }
            ]
          }
        ]
      }
    )
  end

  # The answer the product's card shows, for its alt text.
  defp answer(%{cheapest: %{price: price} = cheapest} = verdict),
    do:
      gettext("%{verdict}: najtaniej teraz %{price} w %{shop}.",
        verdict: GuideComponents.verdict_label(verdict),
        price: Polish.price(price),
        shop: GuideComponents.shop_name(cheapest)
      )

  defp answer(_verdict), do: gettext("Teraz żaden sklep nie ma tego produktu na stanie.")

  # `social_image` is the designed link-preview card (TcgCheapWeb.SocialImage),
  # not the product photo, which stays in the structured data.
  defp metadata(title, description, canonical, opts) do
    %{
      title: title,
      description: description,
      canonical: canonical,
      robots: Keyword.get(opts, :robots, "index, follow"),
      social_image: Keyword.fetch!(opts, :social_image),
      social_image_alt: Keyword.fetch!(opts, :social_image_alt),
      structured_data: Keyword.fetch!(opts, :structured_data)
    }
  end

  attr :seo, :map, required: true

  def head(assigns) do
    ~H"""
    <meta id="seo-description" name="description" content={@seo.description} />
    <meta id="seo-robots" name="robots" content={@seo.robots} />
    <link id="seo-canonical" rel="canonical" href={@seo.canonical} />
    <meta id="seo-og-title" property="og:title" content={@seo.title <> " · TCG Cheap"} />
    <meta id="seo-og-description" property="og:description" content={@seo.description} />
    <meta id="seo-og-url" property="og:url" content={@seo.canonical} />
    <meta property="og:type" content="website" />
    <meta property="og:site_name" content="TCG Cheap" />
    <meta id="seo-og-image" property="og:image" content={@seo.social_image} />
    <meta property="og:image:type" content="image/jpeg" />
    <meta property="og:image:width" content={SocialImage.width()} />
    <meta property="og:image:height" content={SocialImage.height()} />
    <meta id="seo-og-image-alt" property="og:image:alt" content={@seo.social_image_alt} />
    <meta name="twitter:card" content="summary_large_image" />
    <meta id="seo-twitter-image-alt" name="twitter:image:alt" content={@seo.social_image_alt} />
    <script id="seo-structured-data" type="application/ld+json">
      <%= raw(Jason.encode!(@seo.structured_data, escape: :html_safe)) %>
    </script>
    """
  end

  attr :seo, :map, required: true

  # Root layouts render only on HTTP requests. Keep their metadata current on live navigation too.
  def sync(assigns) do
    ~H"""
    <div
      id="guide-seo"
      hidden
      phx-hook=".SearchMetadata"
      phx-update="ignore"
      data-seo={Jason.encode!(@seo)}
    />
    <script :type={Phoenix.LiveView.ColocatedHook} name=".SearchMetadata">
      export default {
        mounted() { this.sync() },
        updated() { this.sync() },
        sync() {
          const seo = JSON.parse(this.el.dataset.seo)
          const values = {
            "seo-description": seo.description,
            "seo-robots": seo.robots,
            "seo-og-title": `${seo.title} · TCG Cheap`,
            "seo-og-description": seo.description,
            "seo-og-url": seo.canonical,
            "seo-og-image": seo.social_image,
            "seo-og-image-alt": seo.social_image_alt,
            "seo-twitter-image-alt": seo.social_image_alt,
          }
          for (const [id, value] of Object.entries(values)) {
            const element = document.getElementById(id)
            if (value) element.setAttribute("content", value)
            else element.removeAttribute("content")
          }
          document.getElementById("seo-canonical").setAttribute("href", seo.canonical)
          document.getElementById("seo-structured-data").textContent = JSON.stringify(seo.structured_data)
        },
      }
    </script>
    """
  end
end
