defmodule TcgCheap.Trades.Valuation do
  @moduledoc """
  Pure arithmetic and state evaluation for a trade composition.

  This module deliberately knows nothing about presentation, images, providers,
  or valuation acquisition. Unknown cards and cards without a current valuation
  are retained as unvalued rows and excluded from numeric totals.
  """

  alias TcgCheap.Pricing.Singles.Freshness
  alias TcgCheap.Trades.Composition

  @type row :: %__MODULE__.Row{}
  @type side :: %__MODULE__.Side{}
  @type comparison :: :incomplete | :equal | {:higher, Composition.side(), Decimal.t()}
  @type t :: %__MODULE__.Evaluation{}

  defmodule Row do
    @moduledoc "A composition row with its canonical card and valuation state."
    @type t :: %__MODULE__{
            id: String.t(),
            quantity: pos_integer(),
            card: map() | nil,
            valuation: map() | nil,
            status: atom(),
            unit_value: Decimal.t() | nil,
            row_value: Decimal.t() | nil
          }
    defstruct [:id, :quantity, :card, :valuation, :status, :unit_value, :row_value]
  end

  defmodule Side do
    @moduledoc "The evaluated rows and aggregate state for one side of a trade."
    @type t :: %__MODULE__{
            rows: [Row.t()],
            known_total: Decimal.t(),
            complete?: boolean(),
            nonempty?: boolean(),
            unvalued_quantity: non_neg_integer()
          }
    defstruct rows: [],
              known_total: Decimal.new(0),
              complete?: true,
              nonempty?: false,
              unvalued_quantity: 0
  end

  defmodule Evaluation do
    @moduledoc "A complete deterministic evaluation of both trade sides."
    @type t :: %__MODULE__{
            left: Side.t(),
            right: Side.t(),
            comparison: TcgCheap.Trades.Valuation.comparison()
          }
    defstruct [:left, :right, :comparison]
  end

  @doc "Evaluates a bounded composition against canonical cards at the supplied time."
  @spec evaluate(Composition.t(), map(), DateTime.t()) :: t()
  def evaluate(%Composition{} = composition, cards_by_tcgdex_id, %DateTime{} = now)
      when is_map(cards_by_tcgdex_id) do
    left = evaluate_side(composition.left, cards_by_tcgdex_id, now)
    right = evaluate_side(composition.right, cards_by_tcgdex_id, now)

    %Evaluation{left: left, right: right, comparison: compare_sides(left, right)}
  end

  defp evaluate_side(items, cards, now) do
    rows = Enum.map(items, &evaluate_row(&1, cards, now))
    known_total = Enum.reduce(rows, Decimal.new(0), &add_row_value/2)
    unvalued_quantity = Enum.reduce(rows, 0, &add_unvalued_quantity/2)

    %Side{
      rows: rows,
      known_total: known_total,
      complete?: unvalued_quantity == 0,
      nonempty?: rows != [],
      unvalued_quantity: unvalued_quantity
    }
  end

  defp evaluate_row({id, quantity}, cards, now) do
    card = Map.get(cards, id)
    valuation = card && Map.get(card, :tcgdex_cardmarket_v1_current_valuation)
    unit_value = valuation && valuation.value_eur

    %Row{
      id: id,
      quantity: quantity,
      card: card,
      valuation: valuation,
      status: Freshness.status(valuation, now),
      unit_value: unit_value,
      row_value: if(unit_value, do: Decimal.mult(unit_value, Decimal.new(quantity)))
    }
  end

  defp add_row_value(%Row{row_value: nil}, total), do: total
  defp add_row_value(%Row{row_value: value}, total), do: Decimal.add(total, value)

  defp add_unvalued_quantity(%Row{row_value: nil, quantity: quantity}, total),
    do: total + quantity

  defp add_unvalued_quantity(%Row{}, total), do: total

  defp compare_sides(%Side{complete?: false}, _), do: :incomplete
  defp compare_sides(_, %Side{complete?: false}), do: :incomplete
  defp compare_sides(%Side{nonempty?: false}, _), do: :incomplete
  defp compare_sides(_, %Side{nonempty?: false}), do: :incomplete

  defp compare_sides(%Side{known_total: left}, %Side{known_total: right}) do
    difference = Decimal.abs(Decimal.sub(left, right))

    case Decimal.compare(left, right) do
      :eq -> :equal
      :gt -> {:higher, :left, difference}
      :lt -> {:higher, :right, difference}
    end
  end
end
