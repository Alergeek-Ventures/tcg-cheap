defmodule TcgCheap.Sealed.AgentTools.KnownKeys do
  @moduledoc """
  Rejects keys a map argument does not know, which casting would silently
  drop, so a misspelt field never passes as missing.
  """

  alias Ash.Error.Action.InvalidArgument

  @doc """
  `:ok` when the raw argument `value` has only `known` keys, and the maps in
  its lists only the keys `lists` gives for them; otherwise an error on
  `field` naming every unknown key.
  """
  @spec check(term(), atom(), [String.t()], %{String.t() => [String.t()]}) ::
          :ok | {:error, Exception.t()}
  def check(value, field, known, lists) do
    case unknown_keys(value, known, lists) do
      [] ->
        :ok

      paths ->
        {:error,
         InvalidArgument.exception(
           field: field,
           message: "unknown keys: #{Enum.join(paths, ", ")}"
         )}
    end
  end

  defp unknown_keys(%{} = value, known, lists) do
    extra(value, known, "") ++
      Enum.flat_map(lists, fn {key, known} -> list_extra(value, key, known) end)
  end

  defp unknown_keys(_value, _known, _lists), do: []

  defp list_extra(map, key, known) do
    case value(map, key) do
      list when is_list(list) ->
        list
        |> Enum.with_index()
        |> Enum.flat_map(fn
          {%{} = entry, index} -> extra(entry, known, "#{key}[#{index}].")
          _other -> []
        end)

      _other ->
        []
    end
  end

  defp extra(map, known, prefix),
    do: for(key <- Map.keys(map), to_string(key) not in known, do: prefix <> to_string(key))

  defp value(map, key), do: Map.get(map, key) || Map.get(map, String.to_existing_atom(key))
end
