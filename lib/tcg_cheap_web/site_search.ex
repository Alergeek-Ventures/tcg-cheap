defmodule TcgCheapWeb.SiteSearch do
  @moduledoc """
  The home page's search across products and cards, on every guide page.

  The home page searches as the visitor types (`TcgCheapWeb.HomeLive`).
  Elsewhere the bar leads there: Enter opens the home page's results for the
  query, and choosing products or cards opens that list's own search at once,
  as it does on the home page. Without LiveView the form is a GET to the home
  page, which leads to the list the same way.

  Every guide LiveView mounts this hook: it assigns the bar's empty form
  (`@site_search`) and handles its `"site-search"` events.
  """

  use TcgCheapWeb, :html
  use Gettext, backend: TcgCheapWeb.Gettext

  import Phoenix.LiveView, only: [attach_hook: 4, push_navigate: 2]

  alias TcgCheapWeb.Paths

  @max_query_length 100

  def on_mount(:default, _params, _session, socket) do
    {:cont,
     socket
     |> assign(:site_search, to_form(%{"q" => "", "w" => ""}))
     |> attach_hook(:site_search, :handle_event, &handle_event/3)}
  end

  # Typing waits for Enter: leaving the page on every keystroke would lose it.
  defp handle_event("site-search", %{"_target" => ["q"]}, socket), do: {:halt, socket}

  defp handle_event("site-search", params, socket),
    do: {:halt, push_navigate(socket, to: path(params))}

  defp handle_event(_event, _params, socket), do: {:cont, socket}

  @doc "Where a search leads: the chosen list's own search (`w`), or the home page's results."
  @spec path(map()) :: String.t()
  def path(params) do
    query = params |> query() |> query_params()

    case params["w"] do
      "produkty" -> Paths.products(query)
      "karty" -> Paths.cards(query)
      _all -> Paths.home(query)
    end
  end

  @doc "The search's query: trimmed and at most #{@max_query_length} characters; nested params (`?q[a]=b`) are none."
  @spec query(map()) :: String.t()
  def query(%{"q" => query}) when is_binary(query),
    do: query |> String.trim() |> String.slice(0, @max_query_length)

  def query(_params), do: ""

  @doc "A query as a page's `q` parameter, none when it is empty."
  @spec query_params(String.t()) :: keyword()
  def query_params(""), do: []
  def query_params(query), do: [q: query]

  attr :form, Phoenix.HTML.Form, required: true
  attr :id, :string, default: "site-search"
  attr :event, :string, default: "site-search"

  @doc """
  The search bar: the query and where to search, everything, products or
  cards. On a phone the choice sits under the query and the bar sticks under
  the masthead; once it sticks, the choice folds away (the `Stuck` hook).
  """
  def search_bar(assigns) do
    ~H"""
    <.form
      for={@form}
      id={@id}
      class="site-search"
      action={Paths.home()}
      method="get"
      role="search"
      phx-hook="Stuck"
      phx-mounted={JS.ignore_attributes(["data-stuck"])}
      phx-change={@event}
      phx-submit={@event}
    >
      <label for={"#{@id}-query"} class="sr-only">{gettext("Szukaj produktu albo karty")}</label>
      <div class="site-search-field">
        <.fluent_icon name={:search} class="site-search-icon" />
        <input
          id={"#{@id}-query"}
          name="q"
          type="search"
          value={@form[:q].value}
          maxlength="100"
          autocomplete="off"
          phx-debounce="300"
          placeholder={gettext("np. ETB albo Pikachu")}
        />
      </div>
      <fieldset class="site-search-scope">
        <legend class="sr-only">{gettext("Szukaj w")}</legend>
        <label :for={{value, label} <- scope_choices()}>
          <input type="radio" name="w" value={value} checked={@form[:w].value == value} />
          <span>{label}</span>
        </label>
      </fieldset>
    </.form>
    """
  end

  defp scope_choices,
    do: [
      {"", gettext("Wszystko")},
      {"produkty", gettext("Produkty")},
      {"karty", gettext("Karty")}
    ]
end
