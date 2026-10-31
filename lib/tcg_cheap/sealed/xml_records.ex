defmodule TcgCheap.Sealed.XmlRecords do
  @moduledoc """
  Reads the repeated records of an untrusted XML feed, keeping only the
  fields a feed client asks for.

  A record is every element at `record_path` (element names from the root,
  as written in the document, prefixes included). For each record the result
  maps each wanted path relative to the record to its occurrences in document
  order, each `%{attrs: %{name => value}, text: trimmed_text}`; the relative
  path `[]` holds the record element's own attributes. Everything else, such
  as long descriptions, is dropped while parsing, and so is every record that
  `keep?` rejects: a whole-shop export holds tens of thousands of products, of
  which a few hundred are wanted.

  Parsing uses Saxy, which creates no atoms, skips a DTD instead of reading
  its entity declarations and expands only character references and the five
  predefined entities; `expand_entity: :keep` leaves any other reference as
  written. Entity expansion therefore cannot amplify the (size-bounded) input.
  """

  @behaviour Saxy.Handler

  @type field :: %{attrs: %{String.t() => String.t()}, text: String.t()}
  @type xml_record :: %{[String.t()] => [field()]}

  @doc """
  The records at `record_path` that `keep?` accepts, with the fields at the
  relative `paths`.
  """
  @spec parse(binary(), [String.t()], [[String.t()]], (xml_record() -> boolean())) ::
          {:ok, [xml_record()]} | {:error, :malformed_response}
  def parse(xml, record_path, paths, keep?) when is_binary(xml) do
    state = %{
      record: Enum.reverse(record_path),
      depth: length(record_path),
      paths: MapSet.new(paths),
      keep?: keep?,
      stack: [],
      current: nil,
      field: nil,
      records: []
    }

    case Saxy.parse_string(xml, __MODULE__, state, expand_entity: :keep) do
      {:ok, %{records: records}} -> {:ok, Enum.reverse(records)}
      {:error, _exception} -> {:error, :malformed_response}
    end
  end

  @doc "The text of the first `path` field of `record`, or nil."
  @spec text(xml_record(), [String.t()]) :: String.t() | nil
  def text(record, path) do
    case Map.get(record, path) do
      [%{text: text} | _] -> text
      nil -> nil
    end
  end

  @doc "The `name` attribute of the first `path` field of `record`, or nil."
  @spec attr(xml_record(), [String.t()], String.t()) :: String.t() | nil
  def attr(record, path, name) do
    case Map.get(record, path) do
      [%{attrs: attrs} | _] -> Map.get(attrs, name)
      nil -> nil
    end
  end

  @impl Saxy.Handler
  def handle_event(:start_element, {name, attrs}, state) do
    state = %{state | stack: [name | state.stack]}

    cond do
      is_nil(state.current) and state.stack == state.record ->
        {:ok, %{state | current: %{[] => [field(attrs, "")]}}}

      is_nil(state.current) or not is_nil(state.field) ->
        {:ok, state}

      true ->
        relative = state.stack |> Enum.take(length(state.stack) - state.depth) |> Enum.reverse()

        if MapSet.member?(state.paths, relative),
          do: {:ok, %{state | field: {state.stack, relative, attrs, []}}},
          else: {:ok, state}
    end
  end

  def handle_event(:characters, chars, %{field: {stack, relative, attrs, text}} = state),
    do: {:ok, %{state | field: {stack, relative, attrs, [text | chars]}}}

  def handle_event(:end_element, _name, state) do
    state = state |> finish_field() |> finish_record()
    {:ok, %{state | stack: tl(state.stack)}}
  end

  def handle_event(_event, _data, state), do: {:ok, state}

  defp finish_field(%{field: {stack, relative, attrs, text}, stack: stack} = state) do
    field = field(attrs, IO.iodata_to_binary(text))
    current = Map.update(state.current, relative, [field], &(&1 ++ [field]))
    %{state | current: current, field: nil}
  end

  defp finish_field(state), do: state

  defp finish_record(%{stack: record, record: record, current: %{} = current} = state) do
    if state.keep?.(current),
      do: %{state | records: [current | state.records], current: nil},
      else: %{state | current: nil}
  end

  defp finish_record(state), do: state

  defp field(attrs, text), do: %{attrs: Map.new(attrs), text: String.trim(text)}
end
