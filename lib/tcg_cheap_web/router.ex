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
  set_product_eans maintains verified barcodes for matching and the public scanner.
  set_product_contents records what a box holds (items, a fixed deck's cards, sources) for its page.
  list_suggested_prices shows REBEL's suggested retail prices; decide_suggested_price assigns an
  unmatched one to its exact product (same number of units) or keeps it unmatched.
  Write tools recompute prices at once. enqueue_shop_fetch and enqueue_catalogue_import refresh
  the data in the background.
  """

  # AI agents (see TcgCheap.Sealed tools): a bearer token, no session or cookies.
  # The dev server, like Tidewave, listens only on localhost and needs none.
  pipeline :mcp do
    if Mix.env() != :dev, do: plug(TcgCheapWeb.McpAuth)
  end

  scope "/", TcgCheapWeb do
    get "/sitemap.xml", CrawlController, :sitemap
    get "/robots.txt", CrawlController, :robots
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
        :enqueue_shop_fetch,
        :enqueue_catalogue_import,
        :list_suggested_prices,
        :decide_suggested_price,
        :enqueue_suggested_price_fetch
      ]
  end

  scope "/", TcgCheapWeb do
    pipe_through :browser

    live "/trade", TradeLive
    live "/cards/:tcgdex_id", CardDetailLive
  end

  scope "/", TcgCheapWeb do
    pipe_through [:browser, :guide_locale]

    get "/lang/:locale", LocaleController, :update

    live_session :guide, on_mount: [TcgCheapWeb.Locale] do
      live "/", HomeLive
      live "/produkty/:slug", ProductLive
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
      live "/operations", OperationsLive
      live_resources "/operations/import-issues", ImportIssueLive, only: [:index, :show]
      live "/catalogue/cards/:id/correct", CardPrintingMappingCorrectionLive

      live_resources "/catalogue/card-mapping-history", CardPrintingMappingDecisionLive,
        only: [:index, :show]

      live_resources "/catalogue/card-sets", CardSetLive, only: [:index, :show]
      live_resources "/catalogue/cards", CardPrintingLive, only: [:index, :show]
      live_resources "/catalogue/valuations", SingleValuationSnapshotLive, only: [:index, :show]
    end
  end

  # Other scopes may use custom stacks.
  # scope "/api", TcgCheapWeb do
  #   pipe_through :api
  # end
end
