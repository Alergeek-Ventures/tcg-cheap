defmodule TcgCheapWeb do
  @moduledoc """
  The shared setup of the web layer's modules, chosen by the atom given to
  `use`: `:router`, `:controller`, `:live_view`, `:html` or `:verified_routes`.

      use TcgCheapWeb, :controller
      use TcgCheapWeb, :html

  The quoted blocks hold imports, uses and aliases only; functions belong in
  modules imported here.
  """

  # The IndexNow key file proves to Bing and others that our URL submissions
  # (through OpenSEO) come from the site; the key is public by design.
  def static_paths,
    do:
      ~w(assets fonts images favicon.ico apple-touch-icon.png 3d69f8ee063d49579a3ebcf198001316.txt)

  def router do
    quote do
      use Phoenix.Router, helpers: false

      # Connection and controller functions for pipelines
      import Plug.Conn
      import Phoenix.Controller
      import Phoenix.LiveView.Router
    end
  end

  def controller do
    quote do
      use Phoenix.Controller, formats: [:html, :json]

      import Plug.Conn

      unquote(verified_routes())
    end
  end

  def live_view do
    quote do
      use Phoenix.LiveView

      on_mount Sentry.LiveViewHook

      unquote(html_helpers())
    end
  end

  def html do
    quote do
      use Phoenix.Component

      # Convenience functions from controllers
      import Phoenix.Controller,
        only: [get_csrf_token: 0, view_module: 1, view_template: 1]

      # Helpers for rendering HTML
      unquote(html_helpers())
    end
  end

  defp html_helpers do
    quote do
      # HTML escaping functionality
      import Phoenix.HTML
      # Core UI components
      import TcgCheapWeb.CoreComponents

      # Common modules used in templates
      alias Phoenix.LiveView.JS
      alias TcgCheapWeb.Layouts

      # Routes generation with the ~p sigil
      unquote(verified_routes())
    end
  end

  def verified_routes do
    quote do
      use Phoenix.VerifiedRoutes,
        endpoint: TcgCheapWeb.Endpoint,
        router: TcgCheapWeb.Router,
        statics: TcgCheapWeb.static_paths()
    end
  end

  @doc """
  When used, dispatch to the appropriate controller/live_view/etc.
  """
  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
