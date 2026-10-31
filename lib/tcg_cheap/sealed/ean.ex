defmodule TcgCheap.Sealed.Ean do
  @moduledoc """
  EAN-13 barcodes. A 12-digit UPC-A becomes its EAN-13 form with a leading
  zero; anything else counts only when its GS1 check digit is right.
  """

  @doc "The 13-digit EAN for `code`, or `nil` when it is not a valid barcode."
  @spec normalize(term()) :: String.t() | nil
  def normalize(code) when is_binary(code) do
    code =
      case String.replace(code, ~r/[\s-]/, "") do
        <<_::binary-size(12)>> = code -> "0" <> code
        code -> code
      end

    if String.match?(code, ~r/\A[0-9]{13}\z/) and check_digit_valid?(code), do: code
  end

  def normalize(_code), do: nil

  defp check_digit_valid?(code) do
    sum =
      code
      |> String.graphemes()
      |> Enum.map(&String.to_integer/1)
      |> Enum.with_index()
      |> Enum.map(fn {digit, index} -> if rem(index, 2) == 1, do: digit * 3, else: digit end)
      |> Enum.sum()

    rem(sum, 10) == 0
  end
end
