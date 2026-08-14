defmodule TcgCheap.Operations.Validations.ImportIssue do
  @moduledoc "Validates the retained import-issue operation, target, and category matrix."

  use Ash.Resource.Validation

  @sync_stages [
    "catalogue_fetch",
    "catalogue_validation",
    "set_fetch",
    "set_validation",
    "set_import"
  ]
  @enrichment_stages ["set_fetch", "set_validation", "set_import", "card_fetch", "card_import"]
  @retailer_stages ["retailer_fetch", "listing_validation", "listing_import"]
  @failed_codes [
    "budget",
    "rate_limit",
    "timeout",
    "transport",
    "provider_response",
    "persistence",
    "configuration",
    "local_input",
    "unknown"
  ]

  @impl true
  def init(opts), do: {:ok, opts}

  @impl true
  def validate(changeset, _opts, _context) do
    provider_key = Ash.Changeset.get_attribute(changeset, :provider_key)
    operation = Ash.Changeset.get_attribute(changeset, :operation)
    stage = Ash.Changeset.get_attribute(changeset, :stage)
    target_type = Ash.Changeset.get_attribute(changeset, :target_type)
    target_key = Ash.Changeset.get_attribute(changeset, :target_key)
    issue_kind = Ash.Changeset.get_attribute(changeset, :issue_kind)
    issue_code = Ash.Changeset.get_attribute(changeset, :issue_code)

    cond do
      not valid_provider?(provider_key) ->
        {:error, field: :provider_key, message: "is not a safe import provider"}

      not valid_provider_operation?(provider_key, operation) ->
        {:error, field: :operation, message: "is not valid for the import provider"}

      not valid_operation_stage?(operation, stage) ->
        {:error, field: :stage, message: "is not valid for the import operation"}

      not valid_stage_target?(stage, target_type, target_key) ->
        {:error, field: :target_type, message: "is not valid for the import stage"}

      not valid_issue_category?(issue_kind, issue_code) ->
        {:error, field: :issue_code, message: "is not valid for the issue kind"}

      true ->
        :ok
    end
  end

  defp valid_operation_stage?("card_catalogue_sync", stage), do: stage in @sync_stages

  defp valid_operation_stage?("card_catalogue_enrichment", stage),
    do: stage in @enrichment_stages

  defp valid_operation_stage?("sealed_retailer_refresh", stage), do: stage in @retailer_stages

  defp valid_operation_stage?(_, _), do: false

  defp valid_provider?("tcgdex_catalogue"), do: true

  defp valid_provider?(provider_key) when is_binary(provider_key),
    do: Regex.match?(~r/\Asealed_retailer:[A-Za-z0-9][A-Za-z0-9._-]{0,143}\z/, provider_key)

  defp valid_provider?(_), do: false

  defp valid_provider_operation?("tcgdex_catalogue", operation),
    do: operation in ["card_catalogue_sync", "card_catalogue_enrichment"]

  defp valid_provider_operation?(provider_key, "sealed_retailer_refresh"),
    do: valid_provider?(provider_key) and String.starts_with?(provider_key, "sealed_retailer:")

  defp valid_provider_operation?(_, _), do: false

  defp valid_stage_target?(stage, "catalogue", "tcgdex")
       when stage in ["catalogue_fetch", "catalogue_validation"],
       do: true

  defp valid_stage_target?(stage, "set", _target_key)
       when stage in ["set_fetch", "set_validation", "set_import"],
       do: true

  defp valid_stage_target?(stage, "card", _target_key)
       when stage in ["card_fetch", "card_import"],
       do: true

  defp valid_stage_target?(stage, "retailer", target_key) when stage in @retailer_stages do
    is_binary(target_key) and
      Regex.match?(
        ~r/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/,
        target_key
      ) and target_key == String.downcase(target_key)
  end

  defp valid_stage_target?(_, _, _), do: false

  defp valid_issue_category?(kind, "provider_response")
       when kind in ["unmatched", "ambiguous"],
       do: true

  defp valid_issue_category?("partial", "partial_coverage"), do: true
  defp valid_issue_category?("malformed", "malformed_response"), do: true
  defp valid_issue_category?("failed", code), do: code in @failed_codes
  defp valid_issue_category?(_, _), do: false
end
