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
    operation = Ash.Changeset.get_attribute(changeset, :operation)
    stage = Ash.Changeset.get_attribute(changeset, :stage)
    target_type = Ash.Changeset.get_attribute(changeset, :target_type)
    target_key = Ash.Changeset.get_attribute(changeset, :target_key)
    issue_kind = Ash.Changeset.get_attribute(changeset, :issue_kind)
    issue_code = Ash.Changeset.get_attribute(changeset, :issue_code)

    cond do
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

  defp valid_operation_stage?(_, _), do: false

  defp valid_stage_target?(stage, "catalogue", "tcgdex")
       when stage in ["catalogue_fetch", "catalogue_validation"],
       do: true

  defp valid_stage_target?(stage, "set", _target_key)
       when stage in ["set_fetch", "set_validation", "set_import"],
       do: true

  defp valid_stage_target?(stage, "card", _target_key)
       when stage in ["card_fetch", "card_import"],
       do: true

  defp valid_stage_target?(_, _, _), do: false

  defp valid_issue_category?(kind, "provider_response")
       when kind in ["unmatched", "ambiguous"],
       do: true

  defp valid_issue_category?("malformed", "malformed_response"), do: true
  defp valid_issue_category?("failed", code), do: code in @failed_codes
  defp valid_issue_category?(_, _), do: false
end
