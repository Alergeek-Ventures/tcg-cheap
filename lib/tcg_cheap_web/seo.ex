defmodule TcgCheapWeb.SEO do
  @moduledoc """
  Search metadata for the buying guide, derived from the same data as its
  visible pages, in the current region (`TcgCheapWeb.Region`): its URLs, its
  currency and, for a page the other regions index too, `hreflang`
  alternates to them.

  This module holds what every page shares: the metadata shape (`t:t/0`,
  built by `compose/4`), the fitting of titles and descriptions to what
  search results show, `hreflang` alternates, the structured-data building
  blocks, the link-preview image URLs and the `head/1` and `sync/1`
  components that put the metadata on the page. Each page kind builds its
  own metadata in `TcgCheapWeb.SEO.<Page>.metadata/…`.
  """

  use TcgCheapWeb, :html

  use Gettext, backend: TcgCheapWeb.Gettext

  alias TcgCheapWeb.{PageMarkdown, Paths, Region, SocialImage}

  @type alternate :: %{hreflang: String.t(), href: String.t()}

  @type t :: %{
          title: String.t(),
          page_title: String.t(),
          description: String.t(),
          canonical: String.t(),
          markdown: String.t() | nil,
          robots: String.t(),
          alternates: [alternate()],
          social_image: String.t(),
          social_image_alt: String.t(),
          structured_data: map()
        }

  # Search results show about 60 characters of a title and 160 of a
  # description and cut the rest. A page lists its title from the fullest to
  # the shortest form; the description keeps the first sentences that fit, so
  # the answer always stays.
  @title_limit 60
  @description_limit 160
  @brand " · TCG Cheap"

  @doc """
  A page's metadata. Options: `:social_image` and `:social_image_alt` and
  `:structured_data` (required), `:robots` (default "index, follow"),
  `:alternates` (named only by an indexed page) and `:markdown` (the URL of
  the page's Markdown version, by default derived from `canonical`; nil for
  a page without one).
  """
  @spec compose(String.t(), String.t(), String.t(), keyword()) :: t()
  def compose(title, description, canonical, opts) do
    robots = Keyword.get(opts, :robots, "index, follow")

    %{
      title: title,
      page_title: page_title(title),
      description: description,
      canonical: canonical,
      # nil leaves the alternate link without an href.
      markdown: Keyword.get_lazy(opts, :markdown, fn -> PageMarkdown.url_for(canonical) end),
      robots: robots,
      # An unindexed page names no alternates.
      alternates: if(robots == "index, follow", do: Keyword.get(opts, :alternates, []), else: []),
      social_image: Keyword.fetch!(opts, :social_image),
      social_image_alt: Keyword.fetch!(opts, :social_image_alt),
      structured_data: Keyword.fetch!(opts, :structured_data)
    }
  end

  # The browser tab's and the search result's title, with our name when it fits.
  defp page_title(title) do
    branded = title <> @brand
    if String.length(branded) <= @title_limit, do: branded, else: title
  end

  @doc "The first title, from the fullest to the shortest, that fits a search result; the last one otherwise."
  @spec fit_title([String.t(), ...]) :: String.t()
  def fit_title(titles),
    do: Enum.find(titles, List.last(titles), &(String.length(&1) <= @title_limit))

  @doc "The first sentences that fit a search result's snippet; a `nil` sentence is left out."
  @spec fit_description([String.t() | nil, ...]) :: String.t()
  def fit_description([first | rest]) do
    rest
    |> Enum.filter(&is_binary/1)
    |> Enum.reduce_while(first, fn sentence, description ->
      longer = description <> " " <> sentence

      if String.length(longer) <= @description_limit,
        do: {:cont, longer},
        else: {:halt, description}
    end)
  end

  @doc "Whether the current region is Poland, the only one with shop prices for cards."
  @spec polish?() :: boolean()
  def polish?, do: Region.poland?(Region.current())

  @doc """
  The page's URL in each region that has it, for hreflang; none when only
  one region does. A region that keeps its page out of the index is left
  out by the caller (`indexed`).
  """
  @spec alternates(Paths.page(), [Region.t()]) :: [alternate()]
  def alternates(page, indexed \\ Region.all()) do
    links =
      for region <- indexed,
          path = Paths.page_path(region, page),
          do: %{hreflang: region.hreflang, href: Paths.url(path)}

    if length(links) > 1, do: links, else: []
  end

  @doc "A page's link-preview card: under /og at the page's own path."
  @spec social_image(String.t(), String.t()) :: String.t()
  def social_image(path, version),
    do: unverified_url(TcgCheapWeb.Endpoint, "/og" <> path, v: version)

  @doc "The link-preview card of the home page, which pages without a card of their own share."
  @spec home_image() :: String.t()
  def home_image, do: social_image(Paths.home(), SocialImage.Home.version())

  @doc "The alt text of the home page's card."
  @spec home_image_alt() :: String.t()
  def home_image_alt,
    do:
      "TCG Cheap. " <>
        gettext("Sprawdź, czy cena jest dobra") <> ". " <> SocialImage.Home.promise()

  @doc "The structured data of a page: one node, or several as a graph."
  @spec json_ld(map() | [map()]) :: map()
  def json_ld(nodes) when is_list(nodes),
    do: %{"@context" => "https://schema.org", "@graph" => nodes}

  def json_ld(node), do: Map.put(node, "@context", "https://schema.org")

  @doc "A breadcrumb trail from `{name, url}` pairs, the first being the top."
  @spec breadcrumbs([{String.t(), String.t()}, ...]) :: map()
  def breadcrumbs(crumbs) do
    %{
      "@type" => "BreadcrumbList",
      "itemListElement" =>
        crumbs
        |> Enum.with_index(1)
        |> Enum.map(fn {{name, url}, position} ->
          %{"@type" => "ListItem", "position" => position, "name" => name, "item" => url}
        end)
    }
  end

  @doc "The breadcrumb for the list of all products, the top of most trails."
  @spec all_products_crumb() :: {String.t(), String.t()}
  def all_products_crumb, do: {gettext("Wszystkie produkty"), Paths.url(Paths.home())}

  @doc "The breadcrumb for the card list."
  @spec cards_crumb() :: {String.t(), String.t()}
  def cards_crumb, do: {gettext("Karty"), Paths.url(Paths.cards())}

  @doc "An article by us, last changed on `modified_on` (nil when no data says)."
  @spec article(String.t(), Date.t() | nil, String.t()) :: map()
  def article(headline, modified_on, canonical) do
    %{
      "@type" => "Article",
      "headline" => headline,
      "inLanguage" => Gettext.get_locale(TcgCheapWeb.Gettext),
      "dateModified" => modified_on && Date.to_iso8601(modified_on),
      "author" => %{
        "@type" => "Organization",
        "name" => "TCG Cheap",
        "url" => Paths.url(Paths.home())
      },
      "mainEntityOfPage" => canonical
    }
  end

  @doc "The price range of in-stock offers (each with a `Decimal` `price`), for a Product."
  @spec aggregate_offer([map(), ...], String.t(), String.t()) :: map()
  def aggregate_offer(offers, currency, canonical) do
    {low, high} = Enum.min_max_by(offers, & &1.price, Decimal)

    %{
      "@type" => "AggregateOffer",
      "url" => canonical,
      "priceCurrency" => currency,
      "lowPrice" => Decimal.to_string(low.price, :normal),
      "highPrice" => Decimal.to_string(high.price, :normal),
      "offerCount" => length(offers)
    }
  end

  attr :seo, :map, required: true

  def head(assigns) do
    ~H"""
    <meta id="seo-description" name="description" content={@seo.description} />
    <meta id="seo-robots" name="robots" content={@seo.robots} />
    <link id="seo-canonical" rel="canonical" href={@seo.canonical} />
    <link id="seo-markdown" rel="alternate" type="text/markdown" href={@seo.markdown} />
    <link
      :for={alternate <- @seo.alternates}
      rel="alternate"
      hreflang={alternate.hreflang}
      href={alternate.href}
      data-seo-alternate
    />
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
          const markdown = document.getElementById("seo-markdown")
          if (seo.markdown) markdown.setAttribute("href", seo.markdown)
          else markdown.removeAttribute("href")
          document.getElementById("seo-structured-data").textContent = JSON.stringify(seo.structured_data)
          document.querySelectorAll("link[data-seo-alternate]").forEach(link => link.remove())
          const markdownLink = document.getElementById("seo-markdown")
          for (const {hreflang, href} of seo.alternates) {
            const link = document.createElement("link")
            Object.assign(link, {rel: "alternate", hreflang, href})
            link.setAttribute("data-seo-alternate", "")
            markdownLink.after(link)
          }
        },
      }
    </script>
    """
  end
end
