defmodule TcgCheap.Geo.Towns do
  @moduledoc """
  Towns of at least 1,000 inhabitants, for turning a typed town into
  coordinates, one list per country with a region
  (`TcgCheap.Countries`). Data from [GeoNames](https://www.geonames.org)
  (CC BY 4.0), reduced to `priv/geo/<country>.tsv`, named as the country's
  file in `lib/tcg_cheap/countries/` (as its Gettext domain is): name (in
  the country's language), area (the region, voivodeship or county, with the
  county where a name repeats; empty where GeoNames has no regions in the
  country's language), latitude, longitude and, for a city district, its
  city; largest first.

  The lists are read at compile time and built into this module. A region
  without its file, or a malformed line, does not compile.
  """

  alias TcgCheap.{Countries, Geo, ModuleDir}

  @type town :: %{
          id: non_neg_integer(),
          name: String.t(),
          area: String.t(),
          coords: Geo.coords(),
          city: String.t() | nil,
          key: String.t(),
          reach_km: float()
        }

  defmodule SearchKey do
    @moduledoc false

    @combining_mark ~r/\p{Mn}/u
    @apostrophes ~r/['’]/u
    @separators ~r/[\s-]+/u

    # Search keys ignore case, accents, apostrophes and hyphens: "bielsko
    # biala" finds Bielsko-Biała, "malmo" Malmö, "s-hertogenbosch"
    # 's-Hertogenbosch. Ł and Đ do not decompose, nor does the Icelandic Ð
    # that some sources and keyboards put in Đ's place.
    def normalize(text) do
      text
      |> String.downcase()
      |> String.replace("ł", "l")
      |> String.replace(["đ", "ð"], "d")
      |> :unicode.characters_to_nfd_binary()
      |> String.replace(@combining_mark, "")
      |> String.replace(@apostrophes, "")
      |> String.replace(@separators, " ")
      |> String.trim()
    end
  end

  defmodule Loader do
    @moduledoc false

    alias TcgCheap.Geo
    alias TcgCheap.Geo.Towns.SearchKey

    # How far a point may be from a town and still count as in its country
    # (`TcgCheap.Geo.Towns.near/2`) is read from the list itself: a town's
    # reach is @slack times its distance to its @neighbours-th nearest town,
    # at least @min_reach_km. A town among others reaches only as far as they
    # do (a point 27 km from Landskrona is across the Øresund), and one far
    # from the rest, like Kiruna, reaches the sparse land around it.
    @neighbours 3
    @slack 1.5
    @min_reach_km 15

    @doc "The towns of a country's file, largest first, each with its reach."
    def read(path) do
      towns =
        path
        |> File.read!()
        |> String.split("\n", trim: true)
        |> Enum.with_index()
        |> Enum.map(fn {line, id} -> parse(line, id, path) end)

      points =
        Enum.map(towns, fn %{id: id, coords: {lat, _lon} = coords} ->
          {id, coords, flat_scale(lat)}
        end)

      for {town, point} <- Enum.zip(towns, points) do
        Map.put(town, :reach_km, reach_km(point, points))
      end
    end

    defp parse(line, id, path) do
      with false <- String.contains?(line, "\r"),
           [name, area, lat, lon, city] when name != "" <- String.split(line, "\t"),
           {lat, ""} when lat >= -90 and lat <= 90 <- Float.parse(lat),
           {lon, ""} when lon >= -180 and lon <= 180 <- Float.parse(lon) do
        %{
          id: id,
          name: name,
          area: area,
          coords: {lat, lon},
          city: if(city != "", do: city),
          key: SearchKey.normalize(name)
        }
      else
        _malformed ->
          raise ArgumentError,
                "#{Path.relative_to_cwd(path)}:#{id + 1}: expected name, area, latitude, " <>
                  "longitude and city (may be empty), separated by tabs, in a line ending with LF"
      end
    end

    # The neighbours are found on a flat map (squared degrees, longitude
    # scaled by the latitude's cosine) and only the last one's distance is
    # measured properly.
    defp reach_km({id, coords, scale}, points) do
      nearest =
        Enum.reduce(points, [], fn
          {^id, _coords, _scale}, nearest ->
            nearest

          {_id, other, _scale}, nearest ->
            keep_nearest(nearest, {flat_distance(coords, other, scale), other})
        end)

      case nearest do
        [_, _, _] ->
          {_flat, third} = List.last(nearest)
          max(@min_reach_km, @slack * Geo.distance_km(coords, third))

        _fewer ->
          @min_reach_km
      end
    end

    defp keep_nearest([_, _, _] = nearest, {distance, _other} = candidate) do
      {farthest, _} = List.last(nearest)
      if distance < farthest, do: insert(nearest, candidate), else: nearest
    end

    defp keep_nearest(nearest, candidate), do: insert(nearest, candidate)

    defp insert(nearest, candidate),
      do: [candidate | nearest] |> Enum.sort() |> Enum.take(@neighbours)

    defp flat_scale(lat), do: :math.cos(lat * :math.pi() / 180)

    defp flat_distance({lat1, lon1}, {lat2, lon2}, scale),
      do: :math.pow((lon2 - lon1) * scale, 2) + :math.pow(lat2 - lat1, 2)
  end

  @dir Path.expand("../../../priv/geo", __DIR__)

  # ISO code => the country's towns, for every region.
  @towns Map.new(Countries.regions(), fn region ->
           path = Path.join(@dir, ModuleDir.name(region.module) <> ".tsv")
           Module.put_attribute(__MODULE__, :external_resource, path)

           unless File.exists?(path),
             do: raise(ArgumentError, "region #{region.code} needs its towns in #{path}")

           {region.country, Loader.read(path)}
         end)

  for {country, towns} <- @towns do
    defp towns(unquote(country)), do: unquote(Macro.escape(towns))
  end

  @doc "Towns of the country (its ISO code) whose name, or a word of it, starts with `query`: exact name first, then larger towns."
  @spec search(String.t(), String.t(), pos_integer()) :: [town()]
  def search(country, query, limit \\ 6) do
    case SearchKey.normalize(query) do
      "" ->
        []

      key ->
        country
        |> towns()
        |> Enum.flat_map(&rank(&1, key))
        |> Enum.sort_by(&elem(&1, 0))
        |> Enum.take(limit)
        |> Enum.map(&elem(&1, 1))
    end
  end

  defp rank(%{key: key} = town, key), do: [{0, town}]

  defp rank(town, key) do
    cond do
      String.starts_with?(town.key, key) -> [{1, town}]
      String.contains?(town.key, " " <> key) -> [{2, town}]
      true -> []
    end
  end

  @spec fetch(String.t(), term()) :: {:ok, town()} | :error
  def fetch(country, id) when is_integer(id) and id >= 0,
    do: country |> towns() |> Enum.fetch(id)

  def fetch(_country, _id), do: :error

  @doc """
  The coordinates of the town of that name in the country. Raises for a name
  the country's list does not have or has more than once, so that a shop's
  `pickup_city` is checked when the shops are compiled; a repeated name needs
  the shop's own `pickup_location`.
  """
  @spec coords!(String.t(), String.t()) :: Geo.coords()
  def coords!(country, name) do
    key = SearchKey.normalize(name)

    case Enum.filter(towns(country), &(&1.key == key)) do
      [town] ->
        town.coords

      [] ->
        raise ArgumentError, "#{country} has no town #{inspect(name)}: give a pickup_location"

      _repeated ->
        raise ArgumentError,
              "#{country} has several towns #{inspect(name)}: give a pickup_location"
    end
  end

  @doc """
  The country's town closest to the point among those whose reach covers it,
  or nil: the point is then taken to be outside the country. A town's reach
  is read from the list (see `Loader`), so that sparse land, such as the
  Swedish fells or an island, counts as inside, and Copenhagen across the
  Øresund does not. It is a distance rule, not a border: a place a few
  kilometres beyond a border town is still taken to be inside.
  """
  @spec near(String.t(), Geo.coords()) :: town() | nil
  def near(country, coords) do
    country
    |> towns()
    |> Enum.map(&{Geo.distance_km(&1.coords, coords), &1})
    |> Enum.filter(fn {distance, town} -> distance <= town.reach_km end)
    |> Enum.min_by(&elem(&1, 0), fn -> nil end)
    |> case do
      {_distance, town} -> town
      nil -> nil
    end
  end
end
