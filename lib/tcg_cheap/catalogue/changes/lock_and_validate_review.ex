defmodule TcgCheap.Catalogue.Changes.LockAndValidateReview do
  @moduledoc "Locks a review row in the action transaction and validates its latest state."
  use Ash.Resource.Change

  alias Ash.Changeset
  alias TcgCheap.Catalogue.Validations.SealedProductApproval
  alias TcgCheap.Catalogue.Validations.SealedProductFields

  @impl true
  def init(opts) do
    valid_resource? = is_atom(opts[:resource])
    valid_lock_action? = is_atom(opts[:lock_action])
    valid_status_attribute? = is_atom(opts[:status_attribute])
    valid_expected? = is_binary(opts[:expected_status])
    valid_mode? = is_nil(opts[:mode]) or opts[:mode] == :product_approval

    if valid_resource? and valid_lock_action? and valid_status_attribute? and valid_expected? and
         valid_mode?,
       do: {:ok, opts},
       else:
         {:error,
          "resource, lock_action, status_attribute, expected_status, and mode options are invalid"}
  end

  @impl true
  def change(changeset, opts, _context) do
    Changeset.before_action(changeset, fn changeset -> lock_and_validate(changeset, opts) end)
  end

  defp lock_and_validate(changeset, opts) do
    id = Changeset.get_data(changeset, :id)
    resource = opts[:resource]
    action = opts[:lock_action]

    query =
      resource
      |> Ash.Query.for_read(action, %{id: id})
      |> Ash.Query.lock(:for_update)

    case Ash.read_one(query, domain: TcgCheap.Core, authorize?: false) do
      {:ok, nil} -> Changeset.add_error(changeset, message: "record no longer exists")
      {:ok, latest} -> validate_latest(changeset, latest, opts)
      {:error, error} -> Changeset.add_error(changeset, message: Exception.message(error))
    end
  end

  defp validate_latest(changeset, latest, opts) do
    if Map.get(latest, opts[:status_attribute]) != opts[:expected_status] do
      Changeset.add_error(changeset,
        message: "may only transition from #{opts[:expected_status]}"
      )
    else
      validate_completeness(changeset, latest, opts[:mode])
    end
  end

  defp validate_completeness(changeset, _latest, nil), do: changeset

  defp validate_completeness(changeset, latest, :product_approval) do
    errors =
      [
        SealedProductApproval.validate_record(latest),
        SealedProductFields.validate_values(
          latest.msrp_pln,
          latest.msrp_source
        )
      ]
      |> Enum.reject(&(&1 == :ok))

    Enum.reduce(errors, changeset, fn {:error, error}, changeset ->
      Changeset.add_error(changeset, error)
    end)
  end
end
