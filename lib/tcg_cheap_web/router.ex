defmodule TcgCheapWeb.Router do
  use TcgCheapWeb, :router
  use AshAuthentication.Phoenix.Router

  import Backpex.Router
  import Oban.Web.Router
  import Phoenix.LiveDashboard.Router

  # sobelow_skip ["Config.CSP"]
  # CSP is generated per request by TcgCheapWeb.CSPNonce, which Sobelow cannot trace through the custom plug.
  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {TcgCheapWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers

    plug TcgCheapWeb.CSPNonce

    plug :load_from_session
  end

  pipeline :guide_locale do
    plug TcgCheapWeb.Locale
  end

  pipeline :admin do
    plug TcgCheapWeb.AdminAuth
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  @mcp_instructions """
  TCG Cheap buying guide: a Cardmarket sealed Pokémon catalogue, offers from Polish shops matched
  to it automatically, and daily prices. Your job is keeping offer matching correct:
  1. shop_status: are fetches recent, and how much of each shop matches?
  2. list_unmatched_offers, then explain_match to see why a title does not match.
  3. If the product is in the catalogue (search_products), assign_offer; if the offer is not a
     catalogue product (accessory, bundle, other game), exclude_offer. When unsure, leave it:
     a wrong match poisons the price history.
  4. list_matched_offers: audit automatic matches; fix a wrong one with assign_offer or exclude_offer.
  5. list_manual_decisions and clear_manual_decision: review or undo manual decisions.
  Daily English singles workflow: check shop_status singles counts, list_unmatched_card_offers
  (filter shop/reason/set), explain_card_match, then search_cards. assign_card_offer fixes an exact
  identity; exclude_card_offer rejects a non-card. Never assign non-English cards to English ones.
  list_matched_card_offers suspicious=true audits price and variant outliers; special patterned
  prints have no reference. list_card_decisions and clear_card_decision review and undo decisions.
  enqueue_card_sync copies the English sets needed by singles matching. Singles decisions never
  recompute sealed prices.
  set_product_eans maintains verified barcodes for matching.
  set_product_contents records what a box holds (items, a fixed deck's cards, sources) for its page.
  set_product_photo replaces missing, tiny or wrong shop photos with a checked one.
  set_pull_rates records a set's estimated pull rates for its single booster's page, once
  enqueue_card_sync (also run daily) has copied the set's cards. record_unofficial_set_cards
  records a new set's published card list until TCGdex lists the set.
  set_expansion_logo records a checked logo for an expansion's tile in the public expansion filter.
  list_suggested_prices shows REBEL's suggested retail prices; decide_suggested_price assigns an
  unmatched one to its exact product (same number of units) or keeps it unmatched.
  Retail chains (Lidl, Rossmann, Żabka…) publish no feed: check their leaflets and deal posts,
  record_retail_deal each Pokémon TCG price with its days and source, list_retail_deals to avoid
  duplicates and remove_retail_deal a wrong one.
  Write tools recompute prices at once. enqueue_shop_fetch and enqueue_catalogue_import refresh
  the data in the background. Shops abroad need their currency's NBP rate from the last week:
  enqueue_exchange_rate_fetch gets one before such a shop's fetch.
  """

  # AI agents (see TcgCheap.Sealed tools): a bearer token, no session or cookies.
  # The dev server, like Tidewave, listens only on localhost and needs none.
  pipeline :mcp do
    if Mix.env() != :dev, do: plug(TcgCheapWeb.McpAuth)
  end

  scope "/", TcgCheapWeb do
    get "/media/tcgdex/:hash/:size", RemoteImageController, :show
    get "/sitemap.xml", CrawlController, :sitemap
    get "/robots.txt", CrawlController, :robots
    get "/llms.txt", CrawlController, :llms
  end

  # Markdown versions of the guide's pages for AI agents, reached through
  # TcgCheapWeb.MarkdownNegotiation: no session, cookies or HTML.
  scope "/md", TcgCheapWeb do
    get "/", MarkdownController, :home
    get "/ile-kosztuje-booster-pokemon", MarkdownController, :booster_prices
    get "/produkty/:slug", MarkdownController, :product
    get "/rozszerzenia/:slug", MarkdownController, :expansion
    get "/rozszerzenia/:slug/karty/:card_slug", MarkdownController, :single
  end

  # Link-preview cards for crawlers: no session, cookies or HTML.
  scope "/og", TcgCheapWeb do
    get "/", SocialImageController, :home
    get "/produkty/:slug", SocialImageController, :product
  end

  scope "/", TcgCheapWeb do
    pipe_through :api

    get "/health", HealthController, :index, log: false
    get "/health/live", HealthController, :live, log: false
  end

  scope "/mcp" do
    pipe_through :mcp

    forward "/", AshAi.Mcp.Router,
      otp_app: :tcg_cheap,
      mcp_name: "TCG Cheap buying guide",
      instructions: @mcp_instructions,
      tools: [
        :list_unmatched_card_offers,
        :list_matched_card_offers,
        :list_card_decisions,
        :explain_card_match,
        :search_cards,
        :assign_card_offer,
        :exclude_card_offer,
        :clear_card_decision,
        :shop_status,
        :list_unmatched_offers,
        :list_matched_offers,
        :list_manual_decisions,
        :search_products,
        :get_product,
        :explain_match,
        :assign_offer,
        :exclude_offer,
        :clear_manual_decision,
        :set_product_eans,
        :set_product_contents,
        :set_product_photo,
        :set_pull_rates,
        :record_unofficial_set_cards,
        :set_expansion_logo,
        :enqueue_shop_fetch,
        :enqueue_catalogue_import,
        :enqueue_card_sync,
        :enqueue_exchange_rate_fetch,
        :list_suggested_prices,
        :decide_suggested_price,
        :enqueue_suggested_price_fetch,
        :list_retail_deals,
        :record_retail_deal,
        :remove_retail_deal
      ]
  end

  scope "/", TcgCheapWeb do
    pipe_through :browser

    get "/trade", LegacyRedirectController, :home
    get "/cards/:tcgdex_id", LegacyRedirectController, :home
  end

  scope "/", TcgCheapWeb do
    pipe_through [:browser, :guide_locale]

    get "/lang/:locale", LocaleController, :update
  end

  pipeline :single_canonical do
    plug TcgCheapWeb.SingleCanonical
  end

  # All public guide pages share history and LiveView navigation. Crossing a
  # live_session boundary forces a full document reload, including on Safari.
  live_session :guide, on_mount: [TcgCheapWeb.Locale, TcgCheapWeb.SiteFooter] do
    scope "/", TcgCheapWeb do
      pipe_through [:browser, :guide_locale]

      live "/", HomeLive, :index
      live "/rozszerzenia/:slug", HomeLive, :expansion
      live "/produkty/:slug", ProductLive
      live "/ile-kosztuje-booster-pokemon", BoosterPriceLive
    end

    scope "/", TcgCheapWeb do
      pipe_through [:browser, :guide_locale, :single_canonical]

      live "/rozszerzenia/:slug/karty/:card_slug", SingleLive
    end
  end

  scope "/admin", TcgCheapWeb do
    pipe_through :browser

    get "/sign-in", AdminSessionController, :new
    post "/sign-in", AdminSessionController, :create
    delete "/sign-out", AdminSessionController, :delete
  end

  scope "/admin", TcgCheapWeb.Admin do
    pipe_through [:browser, :admin]

    live_dashboard "/dashboard",
      metrics: {TcgCheapWeb.Telemetry, :metrics},
      ecto_repos: [TcgCheap.Repo],
      allow_destructive_actions: false,
      additional_pages: [live_logs: LiveDashboardLogger],
      request_logger: true,
      csp_nonce_assign_key: :csp_nonce,
      on_mount: [
        AshAuthentication.Phoenix.LiveSession,
        {TcgCheapWeb.AdminAuth, :require_admin},
        LiveDashboardLogger.Hooks
      ]

    oban_dashboard("/oban",
      oban_name: Oban,
      resolver: TcgCheapWeb.ObanResolver,
      csp_nonce_assign_key: :csp_nonce,
      on_mount: [
        AshAuthentication.Phoenix.LiveSession,
        {TcgCheapWeb.AdminAuth, :require_admin}
      ]
    )

    backpex_routes()

    ash_authentication_live_session :admin_review,
      on_mount: [{TcgCheapWeb.AdminAuth, :require_admin}, Backpex.InitAssigns] do
      live "/buying-guide", BuyingGuideLive
    end
  end

  # Other scopes may use custom stacks.
  # scope "/api", TcgCheapWeb do
  #   pipe_through :api
  # end
end
