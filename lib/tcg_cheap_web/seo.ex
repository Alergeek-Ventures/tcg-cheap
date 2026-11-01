defmodule TcgCheapWeb.SEO do
  @moduledoc "Search metadata for the buying guide, derived from the same data as its visible pages."

  use TcgCheapWeb, :html
  use Gettext, backend: TcgCheapWeb.Gettext

  alias TcgCheap.Sealed.Kinds

  def home(params) do
    metadata(
      gettext("Pokémon TCG – porównywarka cen boosterów, ETB i boxów"),
      gettext(
        "Porównaj ceny Pokémon TCG w polskich sklepach. Sprawdź oferty boosterów, ETB i boxów, historię cen i czy warto kupić teraz."
      ),
      url(~p"/"),
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
      if image = image(product),
        do: Map.put(product_data, "image", image),
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
      image: image(product),
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

  defp metadata(title, description, canonical, opts) do
    %{
      title: title,
      description: description,
      canonical: canonical,
      robots: Keyword.get(opts, :robots, "index, follow"),
      image: Keyword.get(opts, :image),
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
    <meta id="seo-og-image" property="og:image" content={@seo.image} />
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
            "seo-og-image": seo.image,
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

  # Our stored copy of the packaging photo when there is one, else the shop's.
  defp image(%{photo_page_url: url}) when is_binary(url), do: url
  defp image(product), do: product.image_url
end
