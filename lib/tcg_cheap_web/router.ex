defmodule TcgCheapWeb.Router do
  use TcgCheapWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {TcgCheapWeb.Layouts, :root}
    plug :protect_from_forgery

    plug :put_secure_browser_headers,
         %{
           "content-security-policy" =>
             "default-src 'self'; script-src 'self'; connect-src 'self' ws: wss:; img-src 'self' data:; style-src 'self' 'unsafe-inline'"
         }
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", TcgCheapWeb do
    pipe_through :browser

    live "/", HomeLive
  end

  # Other scopes may use custom stacks.
  # scope "/api", TcgCheapWeb do
  #   pipe_through :api
  # end
end
