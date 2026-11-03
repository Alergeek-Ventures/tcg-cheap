defmodule TcgCheap.Sealed.PullRates.Rate do
  @moduledoc """
  The chance of one rarity per pack. `per_pack` takes one of the forms the
  sources use, so pages can say it in any language: "1 in 5", "about 1 in
  12", "1 in 1,081", "3 per pack" or "5.39% (20 of 371 packs)". A rate for
  one card of the rarity, not all of them, names it in `card`.
  """

  use Ash.Resource, data_layer: :embedded

  # "1,081.5"
  @number ~S"\d{1,3}(?:,\d{3})*(?:\.\d+)?"
  @one_in "(about )?1 in (#{@number})"
  @per_pack ~S"(\d{1,2}) per pack"
  @hits "(#{@number})% \\((#{@number}) of (#{@number}) packs\\)"
  @one_in_odds ~r/\A#{@one_in}\z/
  @per_pack_odds ~r/\A#{@per_pack}\z/
  @hits_odds ~r/\A#{@hits}\z/

  @type odds ::
          {:one_in, Decimal.t(), boolean()}
          | {:per_pack, pos_integer()}
          | {:hits, Decimal.t(), Decimal.t(), Decimal.t()}

  validations do
    validate TcgCheap.Sealed.Validations.PullRateOdds
  end

  attributes do
    attribute :rarity, :string do
      description "The rarity, preferably as TCGdex names it in the set, e.g. Special Illustration Rare."
      allow_nil? false
      public? true
      constraints max_length: 100
    end

    attribute :per_pack, :string do
      description ~S'"1 in 5", "about 1 in 12", "1 in 1,081", "3 per pack" or "5.39% (20 of 371 packs)".'
      allow_nil? false
      public? true
      constraints max_length: 100, match: ~r/\A(?:#{@one_in}|#{@per_pack}|#{@hits})\z/
    end

    attribute :percent, :decimal do
      description "The chance per pack in percent, when the source gives it."
      public? true
      constraints greater_than: 0, max: 100
    end

    attribute :card, :string do
      description "The card's name as TCGdex gives it, when the rate is for that one card of the rarity."
      public? true
      constraints max_length: 100
    end
  end

  @doc "What `per_pack` says, parsed; nil when it has none of the forms."
  @spec odds(t() | String.t()) :: odds() | nil
  def odds(%__MODULE__{per_pack: per_pack}), do: odds(per_pack)

  def odds(per_pack) when is_binary(per_pack) do
    cond do
      match = Regex.run(@one_in_odds, per_pack) ->
        [_, about, packs] = match
        {:one_in, decimal(packs), about != ""}

      match = Regex.run(@per_pack_odds, per_pack) ->
        {:per_pack, match |> List.last() |> String.to_integer()}

      match = Regex.run(@hits_odds, per_pack) ->
        [_, percent, hits, packs] = match
        {:hits, decimal(percent), decimal(hits), decimal(packs)}

      true ->
        nil
    end
  end

  @doc "The chance per pack in percent: the one given, or else worked out from `per_pack`."
  @spec percent(t()) :: Decimal.t()
  def percent(%__MODULE__{percent: %Decimal{} = percent}), do: percent

  def percent(rate) do
    case odds(rate) do
      {:one_in, packs, _about?} -> Decimal.div(100, packs)
      {:per_pack, cards} -> Decimal.new(cards * 100)
      {:hits, percent, _hits, _packs} -> percent
    end
  end

  @doc "Chance of at least one hit across independent standard packs, or a guaranteed rarity."
  @spec across_packs(t(), pos_integer()) :: :guaranteed | float() | nil
  def across_packs(rate, count) when is_integer(count) and count > 0 do
    case odds(rate) do
      {:per_pack, cards} when cards >= 1 -> :guaranteed
      {:one_in, packs, _about?} -> combined(1 / Decimal.to_float(packs), count)
      {:hits, percent, _hits, _packs} -> combined(Decimal.to_float(percent) / 100, count)
      _ -> nil
    end
  end

  defp combined(probability, count), do: 100 * (1 - :math.pow(1 - min(probability, 1.0), count))

  defp decimal(number), do: number |> String.replace(",", "") |> Decimal.new()
end
