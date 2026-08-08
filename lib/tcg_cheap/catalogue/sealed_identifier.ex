defmodule TcgCheap.Catalogue.SealedIdentifier do
  @moduledoc "Pure normalization and validation for sealed-product aliases."
  # Explicit SQL checksum generation necessarily nests length and weight branches.
  # credo:disable-for-this-file Credo.Check.Refactor.Nesting

  alias TcgCheap.Catalogue.SearchText

  def normalize(kind, value) when kind in [:name, "name"], do: SearchText.normalize(value)

  def normalize(kind, value) when kind in [:ean, "ean"] and is_binary(value) do
    value = String.replace(value, ~r/[ \-]/, "")
    if String.match?(value, ~r/^\d+$/), do: value, else: ""
  end

  def normalize(_, _), do: ""

  def valid_ean?(value) when is_binary(value) do
    digits = String.graphemes(value)

    length(digits) in [8, 12, 13, 14] and
      Enum.all?(digits, &(&1 in ~w(0 1 2 3 4 5 6 7 8 9))) and
      check_digit?(digits)
  end

  def valid_ean?(_), do: false

  @doc "Returns the explicit SQL predicate implementing the same GS1 check digit rules."
  # The generated predicate intentionally nests each explicit length/checksum branch.
  # credo:disable-for-next-line Credo.Check.Refactor.Nesting
  def postgres_gtin_check(column) when is_binary(column) do
    lengths = [8, 12, 13, 14]

    checks =
      Enum.map_join(lengths, " OR ", fn length ->
        body_length = length - 1

        terms =
          Enum.map_join(1..body_length, " + ", fn position ->
            weight = if rem(body_length - position, 2) == 0, do: 3, else: 1
            "#{weight} * substring(#{column}, #{position}, 1)::integer"
          end)

        "(length(#{column}) = #{length} AND mod(10 - mod(#{terms}, 10), 10) = substring(#{column}, #{length}, 1)::integer)"
      end)

    "#{column} ~ '^[0-9]+$' AND (#{checks})"
  end

  defp check_digit?(digits) do
    {body, [check]} = Enum.split(digits, -1)

    body
    |> Enum.reverse()
    |> Enum.with_index()
    |> Enum.reduce(0, fn {digit, index}, sum ->
      weight = if rem(index, 2) == 0, do: 3, else: 1
      sum + String.to_integer(digit) * weight
    end)
    |> then(&(rem(10 - rem(&1, 10), 10) == String.to_integer(check)))
  end
end
