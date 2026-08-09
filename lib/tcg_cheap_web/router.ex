defmodule TcgCheapWeb.Router do
  use TcgCheapWeb, :router
  use AshAuthentication.Phoenix.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {TcgCheapWeb.Layouts, :root}
    plug :protect_from_forgery

    plug :put_secure_browser_headers,
         %{
           "content-security-policy" =>
             "default-src 'self'; script-src 'self'; connect-src 'self' ws: wss:; img-src 'self' data: https://assets.tcgdex.net; style-src 'self' 'unsafe-inline'"
         }

    plug :load_from_session
  end

  pipeline :admin do
    plug TcgCheapWeb.AdminAuth
  end

  pipeline :api do
    plug :accepts, ["json"]
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

    ash_authentication_live_session :admin_review,
      on_mount: [{TcgCheapWeb.AdminAuth, :require_admin}] do
      live "/review", ReviewLive
    end
  end

  # Other scopes may use custom stacks.
  # scope "/api", TcgCheapWeb do
  #   pipe_through :api
  # end
end
