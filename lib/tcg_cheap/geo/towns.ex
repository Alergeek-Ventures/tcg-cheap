defmodule TcgCheap.Geo.Towns do
  @moduledoc """
  Towns of at least 1,000 inhabitants, for turning a typed town into
  coordinates, one list per country with a region
  (`TcgCheap.Countries`). Data from [GeoNames](https://www.geonames.org)
  (CC BY 4.0), reduced to `priv/geo/<country>.tsv`, named as the country's
  file in `lib/tcg_cheap/countries/` (as its Gettext domain is): name (in
  the country's language), area (the voivodeship, county or region, with the
  city for a city district or the county where a name repeats), coordinates
  and, for a district, its city; largest first.

  A country's list is read from its file when first needed and kept in
  `:persistent_term`, so a node holds only the countries its visitors use. A
  region without its file does not compile.
  """

  alias TcgCheap.{Countries, Geo}

  @type town :: %{
          id: non_neg_integer(),
          name: String.t(),
          area: String.t(),
          coords: Geo.coords(),
          city: String.t() | nil,
          key: String.t()
        }

  @dir Path.expand("../../../priv/geo", __DIR__)

  # ISO code => file name, for every region.
  @files Map.new(Countries.regions(), fn region ->
           name = region.module |> Module.split() |> List.last() |> Macro.underscore()
           path = Path.join(@dir, name <> ".tsv")
           Module.put_attribute(__MODULE__, :external_resource, path)

           unless File.exists?(path),
             do: raise(ArgumentError, "region #{region.code} needs its towns in #{path}")

           {region.country, name <> ".tsv"}
         end)

  defmodule SearchKey do
    @moduledoc false

    @combining_mark ~r/\p{Mn}/u
    @apostrophes ~r/['’]/u
    @separators ~r/[\s-]+/u

    # Search keys ignore case, accents, apostrophes and hyphens: "bielsko
    # biala" finds Bielsko-Biała, "malmo" Malmö, "s-hertogenbosch"
    # 's-Hertogenbosch. Ł and Đ do not decompose.
    def normalize(text) do
      text
      |> String.downcase()
      |> String.replace("ł", "l")
      |> String.replace("đ", "d")
      |> :unicode.characters_to_nfd_binary()
      |> String.replace(@combining_mark, "")
      |> String.replace(@apostrophes, "")
      |> String.replace(@separators, " ")
      |> String.trim()
    end
  end

  # The country's towns: the list, largest first, and the same by id.
  defp towns(country) do
    key = {__MODULE__, country}

    case :persistent_term.get(key, nil) do
      nil ->
        loaded = load(Map.fetch!(@files, country))
        :persistent_term.put(key, loaded)
        loaded

      loaded ->
        loaded
    end
  end

  defp load(file) do
    list =
      :tcg_cheap
      |> Application.app_dir(Path.join("priv/geo", file))
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

    {list, List.to_tuple(list)}
  end

  @doc "Towns of the country (its ISO code) whose name, or a word of it, starts with `query`: exact name first, then larger towns."
  @spec search(String.t(), String.t(), pos_integer()) :: [town()]
  def search(country, query, limit \\ 6) do
    case SearchKey.normalize(query) do
      "" ->
        []

      key ->
        {list, _by_id} = towns(country)

        list
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
  def fetch(country, id) when is_integer(id) and id >= 0 do
    {_list, by_id} = towns(country)
    if id < tuple_size(by_id), do: {:ok, elem(by_id, id)}, else: :error
  end

  def fetch(_country, _id), do: :error

  @doc "The coordinates of the largest town of that name in the country, if it has one."
  @spec coords(String.t(), String.t()) :: Geo.coords() | nil
  def coords(country, name) do
    key = SearchKey.normalize(name)
    {list, _by_id} = towns(country)

    case Enum.find(list, &(&1.key == key)) do
      nil -> nil
      town -> town.coords
    end
  end

  @doc "The country's town closest to the given point."
  @spec nearest(String.t(), Geo.coords()) :: town()
  def nearest(country, coords) do
    {list, _by_id} = towns(country)
    Enum.min_by(list, &Geo.distance_km(&1.coords, coords))
  end
end
