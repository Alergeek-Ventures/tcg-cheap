defmodule TcgCheap.Geo do
  @moduledoc "Straight-line distances between points given as `{latitude, longitude}` in degrees."

  @type coords :: {float(), float()}

  @earth_radius_km 6371.0

  @doc "The great-circle (haversine) distance in kilometres."
  @spec distance_km(coords(), coords()) :: float()
  def distance_km({lat1, lon1}, {lat2, lon2}) do
    d_lat = radians(lat2 - lat1)
    d_lon = radians(lon2 - lon1)

    a =
      :math.pow(:math.sin(d_lat / 2), 2) +
        :math.cos(radians(lat1)) * :math.cos(radians(lat2)) * :math.pow(:math.sin(d_lon / 2), 2)

    2 * @earth_radius_km * :math.asin(:math.sqrt(a))
  end

  defp radians(degrees), do: degrees * :math.pi() / 180
end
