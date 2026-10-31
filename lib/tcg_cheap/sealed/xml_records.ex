defmodule TcgCheap.Sealed.XmlRecords do
  @max_records 20_000

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
  written. Entity expansion therefore cannot amplify the (size-bounded) input,
  and work stays linear in it: more than #{@max_records} kept records fail the
  parse instead of filling memory.
  """

  @behaviour Saxy.Handler

  @type field :: %{attrs: %{String.t() => String.t()}, text: String.t()}
  @type xml_record :: %{[String.t()] => [field()]}

  @doc """
  The records at `record_path` that `keep?` accepts, with the fields at the
  relative `paths`.
  """
  @spec parse(binary(), [String.t()], [[String.t()]], (xml_record() -> boolean())) ::
          {:ok, [xml_record()]} | {:error, :malformed_response | :too_many_records}
  def parse(xml, record_path, paths, keep?) when is_binary(xml) do
    state = %{
      record: Enum.reverse(record_path),
      depth: length(record_path),
      level: 0,
      max_relative: paths |> Enum.map(&length/1) |> Enum.max(fn -> 0 end),
      paths: MapSet.new(paths),
      keep?: keep?,
      stack: [],
      current: nil,
      field: nil,
      records: [],
      kept: 0
    }

    case Saxy.parse_string(xml, __MODULE__, state, expand_entity: :keep) do
      # A handler's {:stop, value} comes back as {:ok, value}.
      {:ok, :too_many_records} -> {:error, :too_many_records}
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
    state = %{state | stack: [name | state.stack], level: state.level + 1}
    below = state.level - state.depth

    cond do
      is_nil(state.current) and state.stack == state.record ->
        {:ok, %{state | current: %{[] => [field(attrs, "")]}}}

      is_nil(state.current) or not is_nil(state.field) or below > state.max_relative ->
        {:ok, state}

      true ->
        relative = state.stack |> Enum.take(below) |> Enum.reverse()

        if MapSet.member?(state.paths, relative),
          do: {:ok, %{state | field: {state.stack, relative, attrs, []}}},
          else: {:ok, state}
    end
  end

  def handle_event(:characters, chars, %{field: {stack, relative, attrs, text}} = state),
    do: {:ok, %{state | field: {stack, relative, attrs, [text | chars]}}}

  def handle_event(:end_element, _name, state) do
    case state |> finish_field() |> finish_record() do
      %{kept: kept} when kept > @max_records -> {:stop, :too_many_records}
      state -> {:ok, %{state | stack: tl(state.stack), level: state.level - 1}}
    end
  end

  def handle_event(_event, _data, state), do: {:ok, state}

  defp finish_field(%{field: {stack, relative, attrs, text}, stack: stack} = state) do
    field = field(attrs, IO.iodata_to_binary(text))
    # Newest first while parsing; finish_record/1 restores document order.
    current = Map.update(state.current, relative, [field], &[field | &1])
    %{state | current: current, field: nil}
  end

  defp finish_field(state), do: state

  defp finish_record(%{stack: record, record: record, current: %{} = current} = state) do
    current = Map.new(current, fn {path, fields} -> {path, Enum.reverse(fields)} end)

    if state.keep?.(current),
      do: %{state | records: [current | state.records], current: nil, kept: state.kept + 1},
      else: %{state | current: nil}
  end

  defp finish_record(state), do: state

  defp field(attrs, text), do: %{attrs: Map.new(attrs), text: String.trim(text)}
end
