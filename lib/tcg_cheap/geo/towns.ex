defmodule TcgCheap.Geo.Towns do
  @moduledoc """
  Polish towns of at least 1,000 inhabitants, for turning a typed town into
  coordinates. Data from [GeoNames](https://www.geonames.org) (CC BY 4.0),
  reduced to `priv/geo/towns.tsv`: name, area (the voivodeship, with the
  city for a city district or the county where a name repeats), coordinates
  and, for a district, its city; largest first.
  """

  alias TcgCheap.Geo

  @type town :: %{
          id: non_neg_integer(),
          name: String.t(),
          area: String.t(),
          coords: Geo.coords(),
          city: String.t() | nil,
          key: String.t()
        }

  @path Path.expand("../../../priv/geo/towns.tsv", __DIR__)
  @external_resource @path

  defmodule SearchKey do
    @moduledoc false

    # Search keys ignore case, Polish letters and hyphens: "bielsko biala"
    # finds Bielsko-Biała. A module of its own so the town list can use it
    # at compile time.
    def normalize(text) do
      text
      |> String.downcase()
      |> String.replace("ł", "l")
      |> :unicode.characters_to_nfd_binary()
      |> String.replace(~r/\p{Mn}/u, "")
      |> String.replace(~r/[\s-]+/u, " ")
      |> String.trim()
    end
  end

  @towns @path
         |> File.stream!()
         |> Stream.map(&(&1 |> String.trim_trailing("\n") |> String.split("\t")))
         |> Enum.with_index(fn [name, area, lat, lon, city], id ->
           %{
             id: id,
             name: name,
             area: area,
             coords: {String.to_float(lat), String.to_float(lon)},
             city: if(city != "", do: city),
             key: SearchKey.normalize(name)
           }
         end)

  @by_id List.to_tuple(@towns)

  @doc "Towns whose name, or a word of it, starts with `query`: exact name first, then larger towns."
  @spec search(String.t(), pos_integer()) :: [town()]
  def search(query, limit \\ 6) do
    case SearchKey.normalize(query) do
      "" ->
        []

      key ->
        @towns
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

  @spec fetch(term()) :: {:ok, town()} | :error
  def fetch(id) when is_integer(id) and id >= 0 and id < tuple_size(@by_id),
    do: {:ok, elem(@by_id, id)}

  def fetch(_id), do: :error

  @doc "The town closest to the given point."
  @spec nearest(Geo.coords()) :: town()
  def nearest(coords), do: Enum.min_by(@towns, &Geo.distance_km(&1.coords, coords))
end
