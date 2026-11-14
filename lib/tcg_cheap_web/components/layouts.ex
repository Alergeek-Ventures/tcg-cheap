defmodule TcgCheapWeb.Layouts do
  @moduledoc """
  The public pages' layout (toasts around the page content), the admin shell,
  and the root and stylesheet templates.
  """
  use TcgCheapWeb, :html
  use Gettext, backend: TcgCheapWeb.Gettext

  # The root HTML skeleton (`root.html.heex`) and the other layouts/* templates.
  embed_templates "layouts/*"

  @doc """
  Renders a public page's content with the toast group that shows flashes and
  connection notices.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    {render_slot(@inner_block)}
    <LiveToast.toast_group
      flash={@flash}
      connected={assigns[:socket] != nil}
      toasts_sync={[]}
      corner={:top_right}
      toast_class_fn={&toast_class/1}
      connection_notifications={
        %{
          client_error: %{title: gettext("Brak połączenia"), body: gettext("Łączymy ponownie")},
          server_error: %{title: gettext("Coś poszło nie tak"), body: gettext("Łączymy ponownie")}
        }
      }
    />
    """
  end

  @doc """
  LiveToast's toast classes: the library's layout and its show and hide
  classes, with site.css drawing the toast (`.site-toast`).
  """
  @spec toast_class(map()) :: list()
  def toast_class(assigns) do
    [
      "site-toast site-toast-#{assigns[:kind]}",
      "group/toast pointer-events-auto relative z-[100] col-start-1 col-end-1 row-start-1 row-end-2 w-full origin-center overflow-hidden items-center justify-between",
      "[@media(scripting:enabled)]:opacity-0 [@media(scripting:enabled)]:[[data-phx-main]_&]:opacity-100",
      if(assigns[:rest][:hidden] == true, do: "hidden", else: "flex")
    ]
  end

  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :fluid?, :boolean, default: false, doc: "whether the admin content uses full width"
  attr :current_url, :string, required: true, doc: "the current admin URL"
  attr :live_resource, :atom, default: nil, doc: "the active Backpex resource"
  attr :current_admin, :any, required: true, doc: "the authenticated administrator"
  attr :socket, :any, required: true, doc: "the LiveView socket"
  attr :sidebar_open, :boolean, default: true, doc: "the persisted Backpex sidebar state"
  attr :preferences_manifest, :map, default: nil, doc: "the Backpex preferences manifest"
  slot :inner_block, required: true

  def admin(assigns) do
    ~H"""
    <div id="admin-catalogue">
      <Backpex.HTML.Layout.app_shell
        socket={@socket}
        fluid={@fluid?}
        live_resource={@live_resource}
        sidebar_open={@sidebar_open}
        preferences_manifest={@preferences_manifest}
      >
        <:sidebar_branding>
          <Backpex.HTML.Layout.sidebar_branding title="TCG Cheap admin">
            <:logo>
              <span class="grid size-9 place-items-center border-2 border-base-content bg-primary font-black text-primary-content">
                TC
              </span>
            </:logo>
          </Backpex.HTML.Layout.sidebar_branding>
        </:sidebar_branding>
        <:topbar>
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
          <Backpex.HTML.Layout.sidebar_item
            current_url={@current_url}
            navigate={~p"/admin/buying-guide"}
          >
            <Backpex.HTML.CoreComponents.icon name="hero-shopping-bag" class="size-5" /> Buying guide
          </Backpex.HTML.Layout.sidebar_item>
          <Backpex.HTML.Layout.sidebar_item
            current_url={@current_url}
            navigate={~p"/admin/dashboard"}
          >
            <Backpex.HTML.CoreComponents.icon name="hero-chart-bar" class="size-5" />
            Runtime dashboard
          </Backpex.HTML.Layout.sidebar_item>
          <Backpex.HTML.Layout.sidebar_item current_url={@current_url} navigate={~p"/admin/oban"}>
            <Backpex.HTML.CoreComponents.icon name="hero-queue-list" class="size-5" /> Oban dashboard
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

  @doc "The admin's stylesheet carries daisyUI and Backpex; public pages load the lighter one."
  @spec stylesheet(Plug.Conn.t()) :: String.t()
  def stylesheet(%Plug.Conn{path_info: ["admin" | _]}), do: ~p"/assets/css/admin.css"
  def stylesheet(_conn), do: ~p"/assets/css/app.css"
end
