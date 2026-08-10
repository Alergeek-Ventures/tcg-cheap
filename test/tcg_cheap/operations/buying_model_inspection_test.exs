defmodule TcgCheap.Operations.BuyingModelInspectionTest do
  use TcgCheap.DataCase
  use Oban.Testing, repo: TcgCheap.Repo

  alias TcgCheap.Accounts
  alias TcgCheap.Operations.BuyingModelInspection
  alias TcgCheap.Pricing.SealedBuyingModel

  test "loads a bounded ordered inspection for a persisted admin" do
    admin = admin()

    assert {:ok, inspection} = BuyingModelInspection.load(admin)
    assert inspection.model_version == "sealed_buying_model_v1"
    assert inspection.aggregate_version == "sealed_market_daily_v1"
    assert inspection.model_status == "Provisional"
    assert inspection.validation_basis == "Synthetic policy cases only"
    assert all_enqueued(repo: TcgCheap.Repo) == []

    assert inspection.component_weights == [
             %{label: "Regular retailer benchmark", value: "55.00%"},
             %{label: "MSRP", value: "25.00%"},
             %{label: "LGS median", value: "10.00%"},
             %{label: "Sold-out center", value: "10.00%"}
           ]

    assert inspection.confidence.ready_threshold == "65.00%"

    assert inspection.sold_out_recency == [
             %{label: "0–14 days (inclusive)", value: "1.00×"},
             %{label: "15–30 days (inclusive)", value: "0.35×"}
           ]

    assert Enum.any?(inspection.availability, fn row ->
             row.label == "Scarce: recent sold-out majority" and
               row.value == "sold outs × 2 > fresh regular + LGS coverage"
           end)

    assert inspection.bands.guardrail == [
             %{label: "Great ceiling guardrail", value: "At most aggregate typical low"},
             %{label: "Fair ceiling guardrail", value: "At least aggregate benchmark"},
             %{
               label: "Expensive ceiling guardrail",
               value: "At least aggregate typical high × 1.05"
             }
           ]

    assert Enum.at(inspection.bands.trend_adjustments, 1) ==
             %{label: "Stable", value: "0%"}

    assert Enum.at(inspection.confidence.hard_requirements, 2) ==
             %{label: "Minimum regular shops (hard)", value: "5"}

    assert inspection.limited_reason_precedence == [
             %{position: 1, label: "Uncertain mapping"},
             %{position: 2, label: "Limited market aggregate"},
             %{position: 3, label: "Stale market evidence"},
             %{position: 4, label: "Insufficient history"},
             %{position: 5, label: "Low confidence"},
             %{position: 6, label: "Invalid band boundaries"}
           ]

    projection = inspect(inspection)
    refute projection =~ "Decimal"
    refute projection =~ "Elixir."
    refute projection =~ "#Function"
  end

  test "rejects missing and forged actors" do
    assert BuyingModelInspection.load(nil) == {:error, :invalid_actor}

    assert BuyingModelInspection.load(%TcgCheap.Accounts.Admin{id: Ecto.UUID.generate()}) ==
             {:error, :invalid_actor}
  end

  test "fails closed for malformed, nonfinite, and wrongly ordered policy reasons" do
    policy = SealedBuyingModel.policy()

    assert BuyingModelInspection.project(
             %{policy | version: "wrong"},
             SealedBuyingModel.limited_reasons()
           ) ==
             {:error, :invalid_model_policy}

    nonfinite = put_in(policy, [:component_weights, :msrp], Decimal.new("NaN"))

    assert BuyingModelInspection.project(nonfinite, SealedBuyingModel.limited_reasons()) ==
             {:error, :invalid_model_policy}

    assert BuyingModelInspection.project(
             policy,
             Enum.reverse(SealedBuyingModel.limited_reasons())
           ) ==
             {:error, :invalid_model_policy}

    assert BuyingModelInspection.project(policy, [:unknown_reason]) ==
             {:error, :invalid_model_policy}

    assert BuyingModelInspection.project(policy, %{}) == {:error, :invalid_model_policy}

    inconsistent = put_in(policy, [:confidence, :history_points_target], 4)

    assert BuyingModelInspection.project(inconsistent, SealedBuyingModel.limited_reasons()) ==
             {:error, :invalid_model_policy}

    rebalanced =
      policy
      |> put_in([:component_weights, :regular_benchmark], Decimal.new("0.50"))
      |> put_in([:component_weights, :msrp], Decimal.new("0.30"))

    assert BuyingModelInspection.project(rebalanced, SealedBuyingModel.limited_reasons()) ==
             {:error, :invalid_model_policy}
  end

  defp admin do
    unique = System.unique_integer([:positive])

    Accounts.register_admin!(
      %{
        email: "buying-model-inspection-#{unique}@example.test",
        password: "correct horse battery staple",
        password_confirmation: "correct horse battery staple"
      },
      authorize?: false
    )
  end
end
