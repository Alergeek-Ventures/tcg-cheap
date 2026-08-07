defmodule TcgCheap.Pricing.Singles.ValuationHistory do
  @moduledoc "Pure projection of valuation snapshots into the public 30-day history."

  alias TcgCheap.Pricing.Singles.SingleValuationSnapshot

  defmodule Point do
    @moduledoc "A successful valuation observation for one UTC calendar date."

    @enforce_keys [:date, :fetched_at, :value_eur]
    defstruct [:date, :fetched_at, :value_eur]

    @type t :: %__MODULE__{
            date: Date.t(),
            fetched_at: DateTime.t(),
            value_eur: Decimal.t()
          }
  end

  @type point :: Point.t()

  @doc "Returns midnight UTC at the start of the current date and its preceding 29 dates."
  @spec window_start(DateTime.t()) :: DateTime.t()
  def window_start(%DateTime{} = now) do
    now
    |> DateTime.to_date()
    |> Date.add(-29)
    |> DateTime.new!(~T[00:00:00], "Etc/UTC")
  end

  @doc "Selects the latest in-window snapshot for each UTC date, preserving gaps."
  @spec daily_points([SingleValuationSnapshot.t()], DateTime.t()) :: [point()]
  def daily_points(snapshots, %DateTime{} = now) when is_list(snapshots) do
    start = window_start(now)

    snapshots
    |> Enum.filter(fn %SingleValuationSnapshot{fetched_at: fetched_at} ->
      DateTime.compare(fetched_at, start) != :lt and DateTime.compare(fetched_at, now) != :gt
    end)
    |> Enum.group_by(fn %SingleValuationSnapshot{fetched_at: fetched_at} ->
      DateTime.to_date(fetched_at)
    end)
    |> Enum.map(fn {date, daily_snapshots} ->
      snapshot = Enum.max_by(daily_snapshots, & &1, &later_snapshot?/2)

      %Point{date: date, fetched_at: snapshot.fetched_at, value_eur: snapshot.value_eur}
    end)
    |> Enum.sort_by(& &1.date, fn left, right -> Date.compare(left, right) != :gt end)
  end

  defp later_snapshot?(left, right) do
    case DateTime.compare(left.fetched_at, right.fetched_at) do
      :gt -> true
      :lt -> false
      :eq -> later_observation?(left, right)
    end
  end

  defp later_observation?(left, right) do
    case DateTime.compare(created_at(left), created_at(right)) do
      :gt -> true
      :lt -> false
      :eq -> (left.id || "") >= (right.id || "")
    end
  end

  defp created_at(%{created_at: %DateTime{} = created_at}), do: created_at
  defp created_at(%{created_at: nil}), do: ~U[0001-01-01 00:00:00Z]
end
