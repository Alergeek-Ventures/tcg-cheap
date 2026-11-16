defmodule TcgCheapWeb.SEO.Bot do
  @moduledoc """
  Search metadata of the bot page, for shop owners and the bot registries
  that link to it; it has no Markdown version.
  """

  use Gettext, backend: TcgCheapWeb.Gettext

  alias TcgCheapWeb.{Paths, SEO}

  @spec metadata() :: SEO.t()
  def metadata do
    canonical = Paths.url(Paths.page(:bot))

    SEO.compose(
      gettext("Bot TCG Cheap – informacje dla sklepów"),
      gettext(
        "Jak bot TCG Cheap czyta publiczne listy produktów sklepów, jak go rozpoznać i jak poprosić, żeby przestał."
      ),
      canonical,
      markdown: nil,
      social_image: SEO.home_image(),
      social_image_alt: SEO.home_image_alt(),
      structured_data:
        SEO.json_ld(
          SEO.breadcrumbs([SEO.all_products_crumb(), {gettext("Bot TCG Cheap"), canonical}])
        )
    )
  end
end
