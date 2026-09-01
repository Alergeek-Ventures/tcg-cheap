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

  pipeline :admin do
    plug TcgCheapWeb.AdminAuth
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", TcgCheapWeb do
    pipe_through :api

    get "/health", HealthController, :index, log: false
    get "/health/live", HealthController, :live, log: false
  end

  scope "/", TcgCheapWeb do
    pipe_through :browser

    live "/", HomeLive
    live "/trade", TradeLive
    live "/cards/:tcgdex_id", CardDetailLive
    live "/sealed/:slug", SealedProductDetailLive
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
      on_mount: [Backpex.InitAssigns, {TcgCheapWeb.AdminAuth, :require_admin}] do
      live "/review", ReviewLive
      live "/operations", OperationsLive
      live_resources "/operations/import-issues", ImportIssueLive, only: [:index, :show]
      live "/catalogue/mappings/:id/correct", ListingProductMappingCorrectionLive
      live "/catalogue/cards/:id/correct", CardPrintingMappingCorrectionLive
      live_resources "/catalogue/products", SealedProductLive
      live_resources "/catalogue/retailers", RetailerLive
      live_resources "/catalogue/aliases", SealedProductAliasLive
      live_resources "/catalogue/listings", RetailerListingLive, only: [:index, :show]
      live_resources "/catalogue/mappings", ListingProductMappingLive, only: [:index, :show]

      live_resources "/catalogue/mapping-history", ListingProductMappingDecisionLive,
        only: [:index, :show]

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
