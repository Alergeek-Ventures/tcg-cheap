defmodule TcgCheapWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use TcgCheapWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://phoenix.hexdocs.pm/scopes.html)"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    {render_slot(@inner_block)}
    <.flash_group flash={@flash} />
    """
  end

  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :fluid?, :boolean, default: false, doc: "whether the admin content uses full width"
  attr :current_url, :string, required: true, doc: "the current admin URL"
  attr :live_resource, :atom, default: nil, doc: "the active Backpex resource"
  attr :current_admin, :any, required: true, doc: "the authenticated administrator"
  slot :inner_block, required: true

  def admin(assigns) do
    ~H"""
    <div id="admin-catalogue">
      <Backpex.HTML.Layout.app_shell fluid={@fluid?} live_resource={@live_resource}>
        <:topbar>
          <Backpex.HTML.Layout.topbar_branding title="TCG Cheap admin">
            <:logo>
              <span class="grid size-9 place-items-center border-2 border-base-content bg-primary font-black text-primary-content">
                TC
              </span>
            </:logo>
          </Backpex.HTML.Layout.topbar_branding>
          <div class="ml-auto flex min-h-11 items-center gap-3 pr-2">
            <span id="admin-catalogue-identity" class="hidden text-sm sm:inline">
              {@current_admin.email}
            </span>
            <.link
              id="admin-catalogue-sign-out"
              href={~p"/admin/sign-out"}
              method="delete"
              class="btn btn-outline min-h-11"
            >
              Sign out
            </.link>
          </div>
        </:topbar>
        <:sidebar>
          <Backpex.HTML.Layout.sidebar_item current_url={@current_url} navigate={~p"/admin/review"}>
            <Backpex.HTML.CoreComponents.icon name="hero-check-badge" class="size-5" /> Review
          </Backpex.HTML.Layout.sidebar_item>
          <Backpex.HTML.Layout.sidebar_item
            current_url={@current_url}
            navigate={~p"/admin/catalogue/products"}
          >
            <Backpex.HTML.CoreComponents.icon name="hero-archive-box" class="size-5" /> Products
          </Backpex.HTML.Layout.sidebar_item>
          <Backpex.HTML.Layout.sidebar_item
            current_url={@current_url}
            navigate={~p"/admin/operations"}
          >
            <Backpex.HTML.CoreComponents.icon name="hero-command-line" class="size-5" /> Operations
          </Backpex.HTML.Layout.sidebar_item>
        </:sidebar>
        <Backpex.HTML.Layout.flash_messages flash={@flash} />
        {render_slot(@inner_block)}
      </Backpex.HTML.Layout.app_shell>
    </div>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title="We can't find the internet"
        phx-disconnected={
          show(".phx-client-error #client-error")
          |> JS.remove_attribute("hidden", to: ".phx-client-error #client-error")
        }
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        Attempting to reconnect
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title="Something went wrong!"
        phx-disconnected={
          show(".phx-server-error #server-error")
          |> JS.remove_attribute("hidden", to: ".phx-server-error #server-error")
        }
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        Attempting to reconnect
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 [[data-theme-source=system]_&]:!left-0 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
