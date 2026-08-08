defmodule TcgCheap.Trades.Composition do
  @moduledoc """
  The URL-safe, name-free state of a trade.

  A composition deliberately contains only stable TCGdex identifiers and
  quantities. It is therefore safe to serialize into a link without leaking
  catalogue names, prices, or internal database identifiers.
  """

  @typedoc "A validated TCGdex identifier and its quantity."
  @type item :: {String.t(), pos_integer()}
  @type side :: :left | :right
  @type t :: %__MODULE__{left: [item()], right: [item()]}
  @type metadata :: %{malformed?: boolean(), truncated?: boolean()}

  @max_id_length 160
  @max_quantity 99
  @max_rows 50
  @max_side_bytes 8_000

  defstruct left: [], right: []

  @doc "Parses untrusted URL parameters into a composition and parse metadata."
  @spec from_params(term()) :: {t(), metadata()}
  def from_params(params) when is_map(params) do
    {left, left_meta} = parse_side(Map.get(params, "left"))
    {right, right_meta} = parse_side(Map.get(params, "right"))

    {%__MODULE__{left: left, right: right},
     %{
       malformed?: left_meta.malformed? or right_meta.malformed?,
       truncated?: left_meta.truncated? or right_meta.truncated?
     }}
  end

  def from_params(_), do: {%__MODULE__{}, %{malformed?: true, truncated?: false}}

  @doc "Serializes a composition to its compact query parameter map."
  @spec to_params(t()) :: %{optional(String.t()) => String.t()}
  def to_params(%__MODULE__{} = composition) do
    composition = normalize(composition)

    %{}
    |> maybe_put("left", composition.left)
    |> maybe_put("right", composition.right)
  end

  @doc "Serializes a composition as a deterministic `/trade` path."
  @spec to_path(t()) :: String.t()
  def to_path(%__MODULE__{} = composition) do
    case to_params(composition) |> Enum.sort() |> URI.encode_query() do
      "" -> "/trade"
      query -> "/trade?" <> query
    end
  end

  @doc "Adds a row, or increments its quantity, by one."
  @spec add(t(), side(), term()) :: t()
  def add(composition, side, id), do: add(composition, side, id, 1)

  @doc "Alias for adding one copy of an identifier."
  @spec increment(t(), side(), term()) :: t()
  def increment(composition, side, id), do: add(composition, side, id)

  @doc "Adds a row, or increments its quantity, by the supplied amount."
  @spec add(t(), side(), term(), term()) :: t()
  def add(%__MODULE__{} = composition, side, id, amount) when is_integer(amount) and amount > 0 do
    update_row(
      composition,
      side,
      id,
      fn quantity -> min(@max_quantity, quantity + amount) end,
      true
    )
  end

  def add(composition, _side, _id, _amount), do: safe_composition(composition)

  @doc "Decrements a row; quantity one removes the row."
  @spec decrement(t(), side(), term()) :: t()
  def decrement(%__MODULE__{} = composition, side, id),
    do: update_row(composition, side, id, &(&1 - 1), false)

  def decrement(composition, _side, _id), do: safe_composition(composition)

  @doc "Removes an identifier from one side."
  @spec remove(t(), side(), term()) :: t()
  def remove(%__MODULE__{} = composition, side, id) do
    case {valid_side?(side), valid_id(id)} do
      {true, {:ok, id}} ->
        put_side(
          composition,
          side,
          Enum.reject(side_items(composition, side), &match?({^id, _}, &1))
        )

      _ ->
        normalize(composition)
    end
  end

  def remove(composition, _side, _id), do: safe_composition(composition)

  @doc "Sets a row quantity, removing it when quantity is zero."
  @spec put_quantity(t(), side(), term(), term()) :: t()
  def put_quantity(%__MODULE__{} = composition, side, id, quantity)
      when is_integer(quantity) and quantity in 0..@max_quantity do
    with true <- valid_side?(side), {:ok, id} <- valid_id(id) do
      rows = side_items(composition, side)

      rows =
        if quantity == 0,
          do: Enum.reject(rows, &match?({^id, _}, &1)),
          else: upsert(rows, id, quantity)

      put_side(composition, side, rows)
    else
      _ -> normalize(composition)
    end
  end

  def put_quantity(composition, _side, _id, _quantity), do: safe_composition(composition)

  @doc "Returns the normalized rows for a side. Invalid sides return an empty list."
  @spec side_items(t(), side()) :: [item()]
  def side_items(%__MODULE__{} = composition, side) when side in [:left, :right],
    do: Map.fetch!(normalize(composition), side)

  def side_items(_, _), do: []

  defp parse_side(nil), do: {[], %{malformed?: false, truncated?: false}}

  defp parse_side(value) when is_binary(value) do
    if byte_size(value) > @max_side_bytes do
      {[], %{malformed?: true, truncated?: true}}
    else
      parse_bounded_side(value)
    end
  end

  defp parse_side(_), do: {[], %{malformed?: true, truncated?: false}}

  defp parse_bounded_side("") do
    {[], %{malformed?: false, truncated?: false}}
  end

  defp parse_bounded_side(value) do
    if String.valid?(value) do
      parse_tokens(value)
    else
      {[], %{malformed?: true, truncated?: false}}
    end
  end

  defp parse_tokens(value) do
    tokens = String.split(value, ",")
    rows = Enum.flat_map(tokens, &parse_token_row/1)
    malformed? = Enum.any?(tokens, &(parse_token(&1) == :error))
    unique_count = rows |> Enum.map(&elem(&1, 0)) |> MapSet.new() |> MapSet.size()

    {normalize_rows(rows), %{malformed?: malformed?, truncated?: unique_count > @max_rows}}
  end

  defp parse_token_row(token) do
    case parse_token(token) do
      {:ok, row} -> [row]
      :error -> []
    end
  end

  defp parse_token(token) do
    with [id, quantity] <- String.split(token, ":", parts: 2),
         {:ok, id} <- valid_id(id),
         {:ok, quantity} <- parse_quantity(quantity) do
      {:ok, {id, quantity}}
    else
      _ -> :error
    end
  end

  defp parse_quantity(value) do
    if value != "" and String.match?(value, ~r/^\d+$/u) do
      case Integer.parse(value) do
        {quantity, ""} when quantity in 1..@max_quantity -> {:ok, quantity}
        _ -> :error
      end
    else
      :error
    end
  end

  defp valid_id(value) when is_binary(value) and byte_size(value) in 1..@max_id_length do
    if String.match?(value, ~r/^[A-Za-z0-9._-]+$/), do: {:ok, value}, else: :error
  end

  defp valid_id(_), do: :error
  defp valid_side?(side), do: side in [:left, :right]

  defp normalize(%__MODULE__{left: left, right: right}),
    do: %__MODULE__{left: normalize_rows(left), right: normalize_rows(right)}

  defp safe_composition(%__MODULE__{} = composition), do: normalize(composition)
  defp safe_composition(_), do: %__MODULE__{}

  defp normalize_rows(rows) when is_list(rows) do
    rows
    |> Enum.reduce(%{}, fn
      {id, quantity}, acc when is_integer(quantity) and quantity in 1..@max_quantity ->
        case valid_id(id) do
          {:ok, id} -> Map.update(acc, id, quantity, &min(@max_quantity, &1 + quantity))
          :error -> acc
        end

      _, acc ->
        acc
    end)
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.take(@max_rows)
  end

  defp normalize_rows(_), do: []

  defp update_row(composition, side, id, fun, create?) do
    with true <- valid_side?(side), {:ok, id} <- valid_id(id) do
      rows = side_items(composition, side)

      case Enum.find(rows, &match?({^id, _}, &1)) do
        {^id, quantity} -> put_side(composition, side, upsert(rows, id, fun.(quantity)))
        nil when create? -> put_side(composition, side, upsert(rows, id, fun.(0)))
        nil -> normalize(composition)
      end
    else
      _ -> normalize(composition)
    end
  end

  defp upsert(rows, id, quantity) when quantity > 0 do
    if Enum.any?(rows, &match?({^id, _}, &1)) or length(rows) < @max_rows do
      normalize_rows([{id, quantity} | Enum.reject(rows, &match?({^id, _}, &1))])
    else
      rows
    end
  end

  defp upsert(rows, id, _quantity), do: Enum.reject(rows, &match?({^id, _}, &1))
  defp put_side(composition, side, rows), do: Map.put(composition, side, normalize_rows(rows))
  defp maybe_put(params, _key, []), do: params

  defp maybe_put(params, key, rows),
    do:
      Map.put(params, key, Enum.map_join(rows, ",", fn {id, quantity} -> "#{id}:#{quantity}" end))
end
