defmodule TcgCheapWeb.VisitorLocation do
  @moduledoc """
  The visitor's location, for straight-line distances to shops' pickup
  stores.

  It lives only in the visitor's browser: the `VisitorLocation` hook keeps
  coordinates rounded to 0.01° (about 1 km) and a town name in
  localStorage and sends them in the LiveView connect params. Here it stays
  in the socket assigns; nothing stores it, and Phoenix filters the
  `location` parameters out of logs (`:filter_parameters`). Without
  JavaScript there is no location and no distances.

  The LiveViews that show distances call `assign_location/1` in mount and
  pass `"location-*"` events to `handle_event/3`.
  """

  use TcgCheapWeb, :html

  import Phoenix.LiveView, only: [connected?: 1, get_connect_params: 1, push_event: 3]

  alias TcgCheap.Geo
  alias TcgCheap.Geo.Towns
  alias TcgCheap.Sealed.Shops

  @type t :: %{coords: Geo.coords(), label: String.t()} | nil

  @radius_km 50
  @max_query_length 60

  @doc "How far a pickup store still counts as near, in kilometres."
  def radius_km, do: @radius_km

  @doc "Assigns the location the browser sent when connecting; nil before that."
  @spec assign_location(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def assign_location(socket) do
    location =
      if connected?(socket), do: from_browser(get_connect_params(socket)["location"])

    socket
    |> assign(:location, location)
    |> assign(:town_form, to_form(%{"town" => ""}, as: :location))
    |> assign(:town_matches, [])
    |> assign(:location_error, nil)
  end

  defp from_browser(%{"lat" => lat, "lon" => lon, "label" => label})
       when is_number(lat) and is_number(lon) and is_binary(label) and
              byte_size(label) in 1..120 do
    if in_poland?({lat, lon}), do: %{coords: rounded({lat, lon}), label: label}
  end

  defp from_browser(_location), do: nil

  # Poland's bounding box with a small margin: distances only make sense
  # to visitors who can reach a Polish shop.
  defp in_poland?({lat, lon}), do: lat >= 48.9 and lat <= 55.0 and lon >= 14.0 and lon <= 24.3

  defp rounded({lat, lon}), do: {Float.round(lat * 1.0, 2), Float.round(lon * 1.0, 2)}

  @doc "Handles the location control's events; the LiveView re-renders what depends on `@location`."
  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          Phoenix.LiveView.Socket.t()
  def handle_event("location-search", %{"location" => %{"town" => query}}, socket)
      when is_binary(query) do
    socket
    |> assign(:town_matches, query |> String.slice(0, @max_query_length) |> Towns.search())
    |> assign(:location_error, nil)
  end

  def handle_event("location-town", %{"location" => %{"town" => query}}, socket)
      when is_binary(query) do
    case query |> String.slice(0, @max_query_length) |> Towns.search(1) do
      [town] -> put_town(socket, town)
      [] -> assign(socket, :location_error, "Nie znamy takiej miejscowości.")
    end
  end

  def handle_event("location-pick", %{"location" => id}, socket) when is_binary(id) do
    with {id, ""} <- Integer.parse(id),
         {:ok, town} <- Towns.fetch(id) do
      put_town(socket, town)
    else
      _invalid -> socket
    end
  end

  def handle_event("location-coords", %{"location" => %{"lat" => lat, "lon" => lon}}, socket)
      when is_number(lat) and is_number(lon) do
    if in_poland?({lat, lon}) do
      coords = rounded({lat, lon})
      # A city district is named by its city: "Gdańsk", not "Aniołki".
      town = Towns.nearest(coords)
      put_location(socket, %{coords: coords, label: town.city || town.name})
    else
      assign(socket, :location_error, "Ta lokalizacja jest poza Polską. Wpisz miejscowość.")
    end
  end

  def handle_event("location-clear", _params, socket), do: put_location(socket, nil)

  def handle_event(_event, _params, socket), do: socket

  defp put_town(socket, town),
    do: put_location(socket, %{coords: rounded(town.coords), label: town.name})

  # The browser keeps the location: the hook stores what this pushes.
  defp put_location(socket, location) do
    browser =
      case location do
        %{coords: {lat, lon}, label: label} -> %{lat: lat, lon: lon, label: label}
        nil -> nil
      end

    socket
    |> assign(:location, location)
    |> assign(:town_matches, [])
    |> assign(:location_error, nil)
    |> push_event("location", %{location: browser})
  end

  @doc "Kilometres from the visitor to the shop's pickup store; nil without either."
  @spec pickup_km(String.t(), t()) :: float() | nil
  def pickup_km(_shop, nil), do: nil

  def pickup_km(shop, %{coords: coords}) do
    case Shops.fetch(shop) do
      {:ok, %{pickup_location: {_lat, _lon} = store}} -> Geo.distance_km(coords, store)
      _no_pickup -> nil
    end
  end

  @doc """
  The nearest of the given in-stock offers whose shop has a pickup store
  within the radius, cheapest first at the same distance; nil if none.
  """
  @spec nearest_pickup([%{shop: String.t(), price: Decimal.t()}], t()) ::
          %{offer: map(), shop: TcgCheap.Sealed.Shop.t(), km: float()} | nil
  def nearest_pickup(_offers, nil), do: nil

  def nearest_pickup(offers, %{coords: coords}) do
    offers
    |> Enum.flat_map(fn offer ->
      with {:ok, %{pickup_location: {_lat, _lon} = store} = shop} <- Shops.fetch(offer.shop),
           km when km <= @radius_km <- Geo.distance_km(coords, store) do
        [%{offer: offer, shop: shop, km: km}]
      else
        _not_near -> []
      end
    end)
    |> Enum.min_by(&{&1.km, Decimal.to_float(&1.offer.price)}, fn -> nil end)
  end

  @doc "Whether any of the offers comes from a shop with a pickup store."
  @spec pickup_offered?([%{shop: String.t()}]) :: boolean()
  def pickup_offered?(offers) do
    Enum.any?(offers, fn offer ->
      match?({:ok, %{pickup_location: {_lat, _lon}}}, Shops.fetch(offer.shop))
    end)
  end

  @doc "A rounded distance: \"14 km\"."
  @spec km(float()) :: String.t()
  def km(distance) when distance < 1, do: "< 1 km"
  def km(distance), do: "#{round(distance)} km"

  attr :location, :map, default: nil
  attr :form, Phoenix.HTML.Form, required: true
  attr :matches, :list, required: true
  attr :error, :string, default: nil

  @doc """
  "Ustaw lokalizację": use the device location or type a town. Hidden until
  LiveView connects, since it needs JavaScript. Other elements open it with
  `JS.dispatch("location:open", to: "#visitor-location")`.
  """
  def location_control(assigns) do
    ~H"""
    <p id="visitor-location-announce" class="sr-only" aria-live="polite" phx-update="ignore"></p>
    <details
      id="visitor-location"
      class="visitor-location"
      phx-hook="VisitorLocation"
      phx-mounted={JS.ignore_attributes(["open"]) |> JS.remove_attribute("hidden")}
      hidden
    >
      <summary id="visitor-location-summary" class="visitor-location-summary">
        <.fluent_icon name={:location} />
        <span :if={@location} class="visitor-location-label">
          <span class="sr-only">Twoja lokalizacja: </span>{@location.label}
        </span>
        <span :if={!@location} class="visitor-location-label">Ustaw lokalizację</span>
      </summary>
      <div class="visitor-location-panel">
        <%= if @location do %>
          <p class="visitor-location-lead">Teraz: {@location.label}. Zmień albo usuń.</p>
          <button
            type="button"
            id="visitor-location-clear"
            class="visitor-location-clear"
            phx-click="location-clear"
          >
            Usuń lokalizację
          </button>
        <% else %>
          <p class="visitor-location-lead">
            Pokażemy, jak daleko masz do sklepów z odbiorem osobistym.
          </p>
        <% end %>
        <button type="button" id="visitor-location-device" class="visitor-location-device">
          <.fluent_icon name={:location} />Użyj mojej lokalizacji
        </button>
        <p
          id="visitor-location-status"
          class="visitor-location-status"
          aria-live="polite"
          phx-update="ignore"
        >
        </p>
        <.form
          for={@form}
          id="visitor-location-form"
          phx-change="location-search"
          phx-submit="location-town"
        >
          <.input
            field={@form[:town]}
            type="search"
            id="visitor-location-town"
            label="albo wpisz miejscowość"
            class="visitor-location-input"
            autocomplete="off"
            maxlength="60"
            phx-debounce="200"
            placeholder="np. Gdańsk"
          />
        </.form>
        <ul :if={@matches != []} id="visitor-location-matches" class="visitor-location-matches">
          <li :for={town <- @matches}>
            <button
              type="button"
              id={"visitor-location-town-#{town.id}"}
              phx-click="location-pick"
              phx-value-location={town.id}
            >
              {town.name} <span>{town.area}</span>
            </button>
          </li>
        </ul>
        <p :if={@error} id="visitor-location-error" class="visitor-location-error" role="alert">
          {@error}
        </p>
        <p class="guide-note">
          Lokalizacja zostaje w Twojej przeglądarce. Odległości liczymy w linii prostej.
        </p>
      </div>
    </details>
    """
  end
end
